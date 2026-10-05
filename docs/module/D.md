# Modul D – Netz (Beta 0.1.1)

Stand 04.10.2026, Nachtschicht. Umgesetzt ist `docs/BETA1_PLAN.md` Abschnitt 5 vollständig, dazu die WLAN-Bindung aus Draw2Race. Alle Tests grün, auch ein echter Chrome (PC, headless) und der Chrome des S10 (über `adb reverse`) gegen den GDScript-Server.

## Dateien

| Datei | Klasse | Inhalt |
|---|---|---|
| `game/scripts/net/net_protocol.gd` | `NetProtocol` | Konstanten (PROTO=1, Ports, Grenzen), JSON kodieren/prüfen (Zahlen → int), Prüfung je Nachrichtentyp, Namensfilter, Begrüßung samt Versionsprüfung, Sofortantwort auf „ping“, Suchformat, Adressrechnung |
| `game/scripts/net/net_ws.gd` | `NetWs` | WebSocket nach RFC 6455, rein: Accept-Schlüssel (SHA-1 über `HashingContext` + Base64), Rahmen kodieren/zerlegen, Maskierung (je 4 Byte), Close-Codes, strenge UTF-8-Prüfung |
| `game/scripts/net/net_server.gd` | `NetServer` | Ein Port für alles: HTTP/1.1 (web.zip, `/info`, `/apk`), eigener WebSocket-Server auf `/ws`; eigener Netz-Thread |
| `game/scripts/net/net_session.gd` | `NetHostSession` | Gastgeber-Sitzung, spielunabhängig: Spieler, Token, Plätze, Bereit, Wiederverbinden, Lobby, Ablehnungen; besitzt Server und Suche |
| `game/scripts/net/net_client.gd` | `NetClient` | App-Mitspieler mit Godot-`WebSocketPeer`, Token je Gastgeber-Adresse, Auto-Reconnect, Ping, Zeitgrenze |
| `game/scripts/net/net_discovery.gd` | `NetDiscovery` | UDP-Suche „MMF?“ auf 24692, gerichtete Rundrufe, Liste mit Alter |
| `game/scripts/net/net_addresses.gd` | `NetAddresses` | Eigene Adressen für QR und Suche, Multicast-Sperre und WLAN-Bindung – dünne Hülle um `NetAndroid` (Modul C) mit Rückfall auf `IP.get_local_interfaces()` |
| `game/scripts/net/net_log.gd` | `NetLog` | Netzprotokoll `user://netz.log` (wie Draw2Race) |
| `game/tests/test_net_protocol.gd`, `test_net_server.gd`, `test_net_session.gd`, `test_net_binding.gd` | | Tests (siehe unten) |
| `game/tests/net_browser_host.gd` | | Godot-Seite des Browser-Tests (absichtlich kein `test_*.gd`, läuft nur mit Chrome) |
| `tools/nettest/browser_test.ps1`, `tools/nettest/page/` | | Browser-Test mit Chrome headless bzw. Chrome am Handy |

## Thread oder Hauptthread (bewusst entschieden)

**Die gesamte Netzarbeit des Servers läuft in einem eigenen Netz-Thread** (`NetServer.threaded = true`, Standard): Annehmen, TLS-Erkennung, HTTP, Dateien aus der Zip, APK-Ströme, WebSocket-Handshake und -Rahmen, Ping/Pong, Grenzen und Zeitgrenzen.

- Grund: `docs/recherche/13_gegenpruefung.md` Punkt 6. Bei `onStop` (App-Wechsel, Bildschirm aus, Vollbild-Einstellungen wie „Apps installieren“) steht die Hauptschleife. Der Thread liefert weiter Seiten und die APK aus, beantwortet WebSocket-Pings **und das Lebenszeichen `{t:"ping"}` der Clients** (`NetProtocol.auto_reply`, zustandslos) und puffert alle anderen Nachrichten, bis die Hauptschleife wieder läuft. Clients laufen also nicht in ihre 15-s-Zeitgrenze.
- Der Thread spricht mit dem Hauptthread nur über zwei Warteschlangen (Befehle hin, Ereignisse zurück) und zwei kleine Dictionaries (`/info`, APK-Quelle), alle unter einem Mutex. Signale entstehen nur in `poll()` auf dem Hauptthread. `apk_provider` wird nur im Hauptthread aufgerufen; eine einmal bekannte APK-Quelle bleibt zwischengespeichert, Downloads laufen also auch bei stehender Hauptschleife.
- Ein Thread genügt: Mehrere APK-Downloads laufen verzahnt, nicht blockierend (`put_partial_data`, 64-KB-Stücke). Gemessen am PC über Loopback: 40 MB in 0,35 s (114 MB/s), also limitiert nur das WLAN.
- Leerlauf: 4 ms Schlaf mit offenen Verbindungen, 10 ms ohne; solange Bytes fließen, kein Schlaf.
- Grenzen des Ansatzes: Friert Android den Prozess ein (Cached-Zustand), stehen auch Threads. Dagegen helfen nur `keep_screen_on` und der Vordergrunddienst (Modul C).
- `threaded = false` erledigt dieselbe Arbeit in `poll()` (Tests, Plattformen ohne Threads).
- Client und Suche laufen im Hauptthread: Sie werden nur gebraucht, solange der jeweilige Bildschirm offen ist. Gegen Pausen hilft das Wiederverbinden mit Token.

## Schnittstelle

### NetHostSession (für Modul G, HostTable)

```gdscript
var s := NetHostSession.new()
s.web_zip_path = "res://assets/web.zip"           # Standard
s.apk_provider = func(): return App.apk_share.server_info() if App.apk_share.available() else {"keine": true}
add_child(s)                                        # auto_poll: poll() in _process
s.start(App.settings.get_value("name", "Gastgeber"))  # Port 24690, Rückfall bis 24699; Gastgeber = Spieler s.host_id auf Platz 0
s.player_joined / player_left / player_rejoined (id) ; s.message(id, msg) ; s.lobby_changed ; s.finished ; s.log_line(text)
```

**Signale**
- `player_left` heißt nur „getrennt“: Der Platz bleibt, `connected=false`.
- `player_rejoined`: derselbe Spieler ist mit seinem Token zurück. Läuft die Partie, schickt die Spielsteuerung ihm sofort `state` (ohne Partie verteilt die Sitzung selbst die Lobby).
- `message(id, msg)` bekommt alle Nachrichten außer `hello`, `ping`, `lobby_ready` und `log` – vor allem `act`, bereits bereinigt: `{t:"act", seq?, a:{a, card?, color?, target?}}`. Andere Felder fallen weg.

**Spieler und Plätze**
- `players[id]` = `{id, name, kind, token, connected, ready, seat, conn, local, address}`.
- `kind`: `"app"` (auch der Gastgeber), `"web"` oder `"bot"`.
- `add_local_player(name, "bot")` fügt einen Computergegner hinzu (−1 = voll); `remove_player(id, text)` entfernt einen Spieler, ein verbundener bekommt `bye`, die Plätze rücken nach.
- `set_seat_order(ids)` setzt die Sitzordnung; nicht genannte Spieler folgen, false = ungültig.
- Abfragen: `ordered_ids()`, `seat_of(id)`, `id_at_seat(seat)`, `player(id)`, `all_ready()`.

**Lobby und Partie**
- `set_rules(dict)` setzt die Bereit-Meldungen der Mitspieler zurück.
- `lobby_message()` baut `{t:"lobby", rev, players:[{id, name, kind, connected, ready, seat}], rules, host_id}`. Sie wird nach jeder Änderung automatisch verteilt (`auto_lobby`), solange keine Partie läuft.
- `send_start()` setzt `running = true` und schickt jedem Mitspieler `{t:"start", seat}`. `set_running(false)` führt zurück in die Lobby; neue Spieler ohne Token werden während der Partie mit `running` abgelehnt.

**Senden und Beenden**
- `send_to(id, msg)` → false, wenn der Spieler nicht verbunden oder lokal ist. `broadcast(msg, except_id)`.
- `finish(text)` beendet nicht blockierend: `bye` an alle, die Clients schließen selbst, danach Signal `finished`. `stop(text)` beendet sofort und wartet höchstens 1 s.

**Hilfen**
- `info()` liefert `/info` und die Suchantwort.
- `apk_url(host)` liefert `http://<Adresse, über die der Client kam>:<port>/apk`.
- `port()`.

**Ablehnungen**

| Code | Wann | Text |
|---|---|---|
| `proto` | anderes Protokoll | mit Hinweis „App vom Gastgeber holen: http://…/apk“ |
| `version` | andere Spielversion (exakt verglichen) | Gerät älter: „App vom Gastgeber holen: http://<ip>:<port>/apk“, Browser zusätzlich „Seite neu laden“. Gerät neuer: „Der Gastgeber sollte seine App aktualisieren“ (eine Rückstufung ginge ohnehin nicht). |
| `full` | mehr als 10 Plätze (Gastgeber, Mitspieler und Computergegner zusammen) | |
| `running` | Partie läuft, kein bekanntes Token | |

`welcome` = `{t:"welcome", id, token, host_name, proto, game}`. Das Token hat 24 Hex-Zeichen (12 Byte aus `Crypto.generate_random_bytes`).

### NetClient (für Modul G, ClientTable)

```gdscript
var c := NetClient.new(); add_child(c)
c.connect_to(address, port, name)       # kind "app"; Token aus user://netz_token.json je "adresse:port"
c.state                                 # "connecting" (auch beim Neuverbinden) → "open" (angenommen) → "closed" (endgültig)
c.state_changed(state) ; c.welcomed(id, host_name) ; c.message(msg) ; c.rejected(code, text) ; c.closed(text)
c.send(msg) -> Error                    # nur bei state == "open", sonst ERR_UNAVAILABLE
c.close() ; c.my_id ; c.token ; c.rtt_ms ; c.attempts ; c.close_text ; c.reject_code
```

- Neu verbunden wird nach 1, 2, 4, dann alle 5 s. Lebenszeichen alle 5 s, 15 s ohne Nachricht gilt als Verlust.
- Endgültig ist eine Trennung nur durch `close()`, `reject`, `bye` oder Close-Code 4000 (eine neuere Verbindung desselben Spielers hat übernommen).

### NetDiscovery (für Modul F/G, Beitreten)

- `start_search()` bindet vorher ans WLAN (Android) und fragt jede Sekunde mit „MMF?“: gerichteter Rundruf je Schnittstelle (ohne Mobilfunk), 255.255.255.255, WLAN-Gateway (Hotspot) sowie eingetippte Adressen (`add_manual`).
- `games_list()` liefert `[{address, addresses, port, name, version, proto, players, max, running, compatible, sid, first_ms, last_ms, age_ms}]`, passende Spiele zuerst. Einträge verfallen nach 5 s. Signal `games_changed`.
- Der Gastgeber antwortet über die Sitzung (`use_discovery`, Port 24692).

### NetAddresses (für Modul F, QR-Code und Adresse)

- `own_addresses()` → `[{address, kind: "wlan"|"hotspot"|"lan"|"other"|"virtual", iface}]`, beste zuerst. Mobilfunk, CLAT, Loopback und Link-local erscheinen nie.
- `urls(port)` → `"http://<ip>:<port>/"`. Der QR-Code nimmt die erste; alle Adressen zusätzlich als Text zeigen.
- `bind_for(purpose, address)` und `release(purpose)` rufen Sitzung, Client und Suche selbst auf. `bind_problem` enthält den Klartext (z. B. „Kein WLAN verbunden.“).

### NetServer (Details)

**Routen**

| Route | Verhalten |
|---|---|
| `GET /` | `index.html` aus der Zip |
| `GET /<datei>` | Datei aus `res://assets/web.zip`. Liegt alles unter einem gemeinsamen Ordner mit `index.html`, wird er abgeschnitten. |
| `/info` | JSON `{game:"mau-mau-flip", version, proto, name, players, max, port, running, sid, addresses}`, `no-store` |
| `/apk` | Quelle über `apk_provider` (siehe unten), gestückelt gestreamt, `Content-Disposition: attachment; filename="MauMauFlip-<version>.apk"`, `Range` (eine Spanne → 206/416), HEAD, höchstens 6 gleichzeitig (sonst 503) |
| `/ws` | WebSocket |

Fehlt die web.zip, liefert `/` eine eingebaute Hinweisseite mit APK-Link; andere Dateien ergeben 404.

`apk_provider` gibt zurück:
- `{path, size, name}`: bereit.
- `{}`: wird vorbereitet. Die Anfrage wartet bis 8 s, dann 503 mit `Retry-After`.
- ein Dictionary ohne gültigen `path`: keine APK, 404.

Mit `ApkShare.server_info()` passt das zusammen; den Fall „gar keine APK“ (PC) vorher prüfen wie im Beispiel oben. `set_apk(info)` setzt die Quelle direkt. `start()` der Sitzung fragt den Provider einmal, damit die Kopie früh anläuft.

**Cache und Kompression**
- Antworten tragen `ETag` (MD5 des Inhalts); bei `If-None-Match` kommt 304.
- Versionierte Dateien bekommen `Cache-Control: public, max-age=31536000, immutable`: Abfrage `?v=…` oder Name mit Prüfsumme bzw. Version (`app.3f9a1c2e.js`, `app.0.1.1.js`). Alles andere bekommt `no-cache`.
- gzip für html/css/js/json/svg/txt über 512 Byte, wenn der Client es anbietet; einmal berechnet und zwischengespeichert.

**MIME-Typen:** html, css, js/mjs, json, webmanifest, svg, webp, png, jpg, gif, ico, ttf, otf, woff, woff2, ogg, m4a, mp3, wav, mp4, webm, wasm, apk.

**Grenzen und Antworten**
- Kopf über 8 KB → 431.
- Inhalt über 8 KB → 413.
- Methode außer GET/HEAD → 405 mit `Allow`.
- Unsinn → 400.
- `/ws` ohne Upgrade → 426.
- keep-alive (15 s Leerlauf, 200 Anfragen) und Pipelining der Reihe nach.
- Erstes Byte 0x16 → sofort schließen und zählen (`tls_rejected`). Chrome scheitert damit nach 5–6 ms (PC) bzw. 68 ms (S10) und nicht erst nach 3 s.
- Kein HSTS, keine Umleitung, kein `upgrade-insecure-requests`.

**WebSocket**
- Handshake nach RFC 6455.
- Origin muss leer sein oder Host und Port gleich dem `Host`-Kopf haben, sonst 403.
- Client-Rahmen müssen maskiert sein (sonst 1002). Nur Text, Binär → 1003; ungültiges UTF-8 → 1007.
- Fragmentierung mit eingeschobenen Steuerrahmen; Ping → Pong; Close-Handshake in beide Richtungen.
- Nachrichten über 8 KB werden verworfen (`ws_dropped "size"`, die Sitzung schickt `err`); über 64 KB → 1009 und Trennung.
- Rate-Limit: 20 Nachrichten/s als Eimer mit 20 Marken, der Überschuss wird verworfen. Wer dauerhaft flutet (über 60 verworfen je Sekunde), bekommt 1008.
- Leerlauf: nach 10 s ein Server-Ping, nach 30 s Trennung (4001). Höchstens 32 WebSockets und 128 TCP-Verbindungen.
- Eigene Close-Codes: 4000 = ersetzt durch eine neuere Verbindung desselben Spielers, 4001 = Zeitgrenze (Anmeldung bzw. Stille).

**Zähler:** `stats()` liefert unter anderem `http`, `http_404`, `tls_rejected`, `gzip`, `ws_opened`, `ws_active`, `rate_dropped`, `oversize`, `apk_started`, `apk_done`, `apk_aborted`, `apk_active`, `bytes_out` und `protocol_errors`.

### NetProtocol

- Konstanten: `PROTO=1`, `PORT=24690`, `PORT_LAST=24699`, `DISCOVERY_PORT=24692`, `MAX_PLAYERS=10`, `MAX_CLIENT_MESSAGE=8192`, `MAX_RATE=20`, `MAX_NAME=14`.
- `decode(text, max)` liefert ein Dictionary mit `t`; ganzzahlige Zahlen werden rekursiv int. `encode(msg)`.
- `clean_client_message(msg)`, `clean_action(a)`, `clean_name(text, fallback)`. Der Namensfilter entfernt Steuer-, Richtungs- und Nullbreitenzeichen, begrenzt kombinierende Zeichen auf 2 und fasst Leerraum zusammen.
- `make_hello`, `check_hello`, `make_info`, `parse_reply`, Adressfunktionen.

## Abweichungen vom Plan (mit Begründung)

1. **Zusätzliche Dateien** `net_ws.gd`, `net_addresses.gd` und `net_log.gd`. Der Rahmen-Code ist rein und einzeln testbar; die Adress- und Bindungslogik hängt an NetAndroid (Modul C) und soll an einer Stelle liegen.
2. **WLAN-Bindung ergänzt** (steht nicht im Plan, Regeln aus Draw2Race `NetLobby._bind`). Ohne Bindung laufen Sockets bei eingeschalteten mobilen Daten und einem WLAN/Hotspot ohne Internet ins Mobilnetz – genau der Urlaubsfall. Abschaltbar mit `NetAddresses.use_binding = false`. Am Gerät in diesem Projekt noch ungeprüft; die Entscheidungen sind gegen Modul Cs echte Regeln getestet.
3. **Kopf über 8 KB → 431** (RFC 6585) statt 413; 413 gilt für einen Inhalt über 8 KB.
4. **Übergroße Client-Nachricht (8–64 KB): verwerfen und `err`, nicht trennen.** Sonst entstünde eine Schleife aus Trennen und Neuverbinden, z. B. mit langen Browser-Fehlerlogs. Erst über 64 KB wird mit 1009 getrennt.
5. **Lebenszeichen `ping` beantwortet der Server-Thread** (`auto_reply`); die Sitzung sieht es nicht. Grund: Thread-Entscheidung oben.
6. **Verzögertes Schließen nach `reject`/`bye`** (`close_ws(…, grace_ms)`): Der Server wartet bis zu 3 s, bis der Client selbst schließt. Gefunden im Test: Godots `WebSocketPeer` verwirft Nachrichten, die im selben `poll()` wie ein vollständiger Close-Handshake ankommen; ein sofortiger Close-Rahmen kostete das `reject`. `stop(text)` blockiert höchstens 1 s; besser `finish(text)`.
7. **NetClient-Zustand „open“ heißt „angenommen“** (nach `welcome`), nicht „Socket offen“. Während des Neuverbindens ist der Zustand „connecting“.
8. **Gastgeber in der Lobby mit `kind:"app"`, Computergegner `"bot"`.** Die Grenze von 10 Plätzen umfasst alle.
9. **`/info` hat zusätzliche Felder** `proto`, `max`, `running`, `sid` und `addresses`; dieselben stehen in der Suchantwort.
10. **Browser-Test ohne `--virtual-time-budget`:** Chromes virtuelle Zeit wartet nicht auf WebSocket-Verkehr, die Zeitgrenzen der Seite liefen sofort ab. Ein offener Abruf, der die Zeit anhält, hielt im Versuch auch die WebSocket-Ereignisse an. Stattdessen hält ein verstecktes iframe zum „Halter“ (Port + 1, antwortet nie) das load-Ereignis auf, bis die Seite fertig ist; `--dump-dom` schreibt danach, `--timeout` ist das Sicherheitsnetz. Mit `-Budget n` lässt sich die virtuelle Zeit trotzdem zuschalten.
11. **Name höchstens 14 Zeichen** (im Plan ohne Zahl). Die Eingabefelder in F und E sollten dieselbe Grenze haben.
12. **Suche nur als Anfrage/Antwort**, wie im Plan, ohne die periodischen Ankündigungen von Draw2Race; dazu Gateway-Probe und eingetippte Adressen.

## Tests

| Test | Ergebnis | Inhalt |
|---|---|---|
| `test_net_protocol.gd` | **115 ok** | decode/ints, Prüfung je Typ, Namensfilter, Versionsprüfung und Texte, auto_reply, Suchformat, Adressen, RFC-Beispiele (Accept-Schlüssel, maskiertes „Hello“), Längen 0/125/126/65535/65536/70000, Fehlerrahmen, UTF-8, HTTP-Kopf, Herkunft, Cache-Regeln, MIME, Schnittstellen-Einordnung |
| `test_net_server.gd` | **95 ok** (~13 s) | Routen aus Test-Zip (ZIPPacker), gzip, ETag/304, HEAD, 404/405/413/431/400, keep-alive und Pipelining, `/info`, TLS-Byte, APK (ganz, Range, 416, HEAD, 3 gleichzeitig, Quelle später bereit), Rückfallport, Hinweisseite. WebSocket: Handshake, maskiert, fragmentiert mit Ping, Byte für Byte, 9 KB verworfen, Close in beide Richtungen, 1002/1003/1007/1009, Herkunft, auto_reply, Rate-Limit und Flut → 1008, 60 KB/100 KB/100 KB fragmentiert, 100 KB vom Server, Leerlauf-Ping und 4001. **Hauptthread steht 1,5 s:** Seite, APK und Pong kommen trotzdem. Server ohne Thread. |
| `test_net_session.gd` | **80 ok** (~6 s) | 3 NetClients, doppelter Name, Token, Lobby, Bereit, Sitzordnung, Regeln setzen Bereit zurück, Computergegner, send_to/broadcast, Aktion bereinigt, Browser-Log, RTT. Wiederverbinden mit Token: Server trennt, Client stürzt ab, Gastgeber hängt (Zeitgrenze) → jeweils gleiche id. Partie läuft: Rückkehr geht, neu → `running`. `version` mit APK-Adresse, `proto`, `full`, 8 KB → `err`, Rate, Anmeldefrist, Suche über 127.0.0.1, `/info`, Entfernen, `finish` mit `bye`, Gastgeber-Neustart. |
| `test_net_binding.gd` | **17 ok** | Bindung und QR-Adressen mit Modul Cs echten NetAndroid-Regeln und erfundenen Gerätezuständen: Heim-WLAN, Hotspot plus WLAN, nur Hotspot (Android 16/15), Gastgeber im eigenen Hotspot, Freigabe nach dem letzten Zweck |
| `tools/nettest/browser_test.ps1` | **bestanden** (Godot 11 ok, DOM RESULT-OK) | Chrome headless am PC: Seite, gzip-JS, CSS (`?v=`), `/info`, https auf denselben Port nach 5 ms abgewiesen, hello/welcome/lobby, Ping/Pong, lobby_ready, Log über 5 KB, Trennen und Rückkehr mit Token (gleiche id), state mit „Grüße 🃏 Mau“ und 70 KB |
| `browser_test.ps1 -Adb <S10>` | **bestanden** | Dasselbe im Chrome des S10 (Android 12) über `adb reverse`; https nach 68 ms abgewiesen |

Aufrufe:
- `tools/godot_run.ps1 -Script res://tests/test_net_<thema>.gd -Headless`
- Browser: `powershell -NoProfile -Command "& '…\tools\nettest\browser_test.ps1'"`
- am Handy zusätzlich: `-Adb '<Seriennummer aus adb devices>'`

Kein Test gibt `ERROR:`-Zeilen aus, das prüft `build.ps1`. Die Testports liegen bei TCP 24790–24801 und UDP 24796.

## Hinweise an andere Module

**Modul G (HostTable/ClientTable)**
- Beim Wiederbeitritt (`player_rejoined`) dem Spieler sofort `state` schicken.
- Zum Beenden `finish()` statt `stop(text)`.
- Ablehnungen und `err` kommen bei `NetClient` als `rejected` bzw. `message` an.
- Der Mau-Ton bleibt Sache der Oberfläche (Katzen-Leitplanke).

**Modul E (Browser-Client)**
- Close-Code **4000** heißt „durch eine neuere Verbindung ersetzt“ (z. B. zweiter Tab mit demselben Token). Bitte dann nicht neu verbinden; heute verbindet `netz.js` neu, und zwei Tabs würden sich gegenseitig verdrängen.
- Dateien mit `?v=<Version>` einbinden: Dann bleiben sie ein Jahr im Cache, sonst gilt `no-cache` mit ETag.
- Log-Texte bleiben unter 8 KB (`netz.js` kürzt schon auf 900 Zeichen).
- Höchstens 20 Nachrichten/s.

**Modul C**
- `NetAndroid`-Funktionen werden dynamisch geladen (`state`, `interfaces`, `wifi_*`, `hotspot_*`, `host_plan`, `join_binding`, `in_hotspot`, `bound_to_wifi`, `bind_wifi`, `bind_network`, `unbind`, `multicast`, `wifi_gateway`). Fehlt eine, gilt der PC-Rückfall.
- `assets/web.zip` steht schon im Exportfilter.
- Der Vordergrunddienst bleibt nötig (Punkt 6), sonst friert Android auch den Netz-Thread ein.

**Modul F**
- QR aus `NetAddresses.urls(port)[0]`; alle Adressen als Text.
- Hinweis aus `NetAddresses.bind_problem` anzeigen.

## Offene Punkte

- **Gerätetest im WLAN** (S21 Gastgeber, S10 App und Chrome) steht aus; er braucht die gebaute APK. Mein Gerätetest lief über `adb reverse` (localhost), nicht über das LAN.
- **PC als Gastgeber für Handys:** Windows hat für `.tools\Godot_v4.6.1-stable_win64_console.exe` keine Firewall-Regel; für die GUI-Exe steht eine *Block*-Regel (Privat/Öffentlich). Eingehende LAN-Verbindungen zum PC-Gastgeber kommen so nicht an. Ich habe nichts geändert. Falls ein Firewall-Dialog für Godot auf dem Bildschirm steht, entscheidet der Nutzer.
- **WLAN-Wechsel während des Spiels:** Draw2Race bindet alle 2 s neu (`refresh_status`); das ist nicht übernommen. Gebunden wird beim Eröffnen, Beitreten und Suchen.
- **Antwort der Suche** kommt nur, solange die Hauptschleife des Gastgebers läuft; Beitritt über Adresse und QR geht auch dann.
- **gzip wird beim ersten Abruf berechnet** (einmal je Datei). Bei großem JS könnte der Bau vorkomprimieren; heute nicht nötig.
- **Range** nur für `/apk`, nicht für Zip-Dateien.
- Am S10 ist in Chrome noch ein Tab „Mau-Mau Flip – Netztest“ (127.0.0.1:24800) offen. Er ist harmlos und kann geschlossen werden; das Handy ist wieder auf dem Startbildschirm.
