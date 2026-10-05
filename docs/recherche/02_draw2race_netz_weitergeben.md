# Analyse: lokaler Mehrspieler in Draw2Race (Stand 0.2.31, 04.10.2026)

Ich habe nur gelesen und keine Dateien verändert.

**Wurzelverzeichnis:** `C:\Users\Shakie\Documents\Programmierung\Draw2Race` (zeigt auf `E:\Documents\Programmierung\Draw2Race`).

**Gelesene Dateien:**
- Netzcode in `game\scripts\net\`: `net_protocol.gd`, `net_discovery.gd`, `net_session.gd`, `net_lobby.gd`, `net_android.gd`, `net_draw.gd`, `net_race.gd`, `net_log.gd`, `net_cli.gd`, `lobby_cli.gd`, `net_test_screen.gd`
- Weitere Skripte in `game\scripts\`: `pass_party.gd`, `party_hud.gd`, `lobby_hud.gd`, `player_colors.gd`, `name_tags.gd`
- Die Mehrspieler-Teile von `main.gd`: `open_party` bis `party_finish`, `open_wlan` bis `net_round_cancelled`, `pause_game`, `_notification`, `go_back`
- Java und Manifest: `game\android\build\src\main\java\com\godot\game\NetHelper.java`, `AndroidManifest.xml`
- Werkzeuge: `tools\net_test.ps1`, `tools\godot_run.ps1`
- Doku: `docs\MULTIPLAYER_RECHERCHE.md` vollständig, `docs\IMPLEMENTIERUNG.md` Abschnitte 414–521 und 199–209 (Updater)

**Git:**
- `41e2e59` 0.2.31: Linienende behoben.
- `fa4418c` 0.2.30 (= HEAD~1): der ganze Mehrspieler, 81 Dateien, +13101/−215.
  - Neu in diesem Commit: `NetHelper.java` (+218), Manifest (+6), alle Netzskripte, `lobby_hud` (+867), `name_tags` (+480), `party_hud` (+380), `pass_party` (+199), `player_colors` (+99) und `tools/net_test.ps1` (+142).
  - Neue Tests: `test_net`, `test_lobby`, `test_draw`, `test_race`, `test_party`, `test_multi`, `test_tags`.
  - Ältere Commits (0.2.24–0.2.29) betreffen den Mehrspieler nicht.

---

## 1. Architektur

### Schichten (vom Netz zur Oberfläche)

1. **`NetProtocol`** (`net_protocol.gd`, statisch, rein): Konstanten, Kodierung, Anmeldeprüfung, Suchpakete, Adressrechnung.
2. **`NetSession`** (`net_session.gd`): eine ENet-Sitzung mit Anmeldung, Ping, Uhrabgleich und Trennung. Sie kennt keine Fahrzeuge. Ihr Kommentar betont, dass die Sitzung nichts an Knotenpfade bindet.
3. **`NetDiscovery`** (`net_discovery.gd`): Host-Suche über UDP.
4. **`NetAndroid`** (`net_android.gd`) mit **`NetHelper.java`**: Netzstatus, WLAN-Bindung, Multicast-Sperre, Hotspot-Erkennung. Aufgerufen wird über `JavaClassWrapper.wrap("com.godot.game.NetHelper")`, nach demselben Muster wie `updater.gd`. Am PC liefern die Funktionen Ersatzwerte aus `IP.get_local_interfaces()`.
5. **`NetLobby`** (`net_lobby.gd`): Spielzustand des Hosts, Wünsche der Mitspieler, Rundenablauf. Sie besitzt Session und Discovery als Kindknoten. Netz und Daten, keine Szene.
6. **`NetDraw`** und **`NetRace`** (RefCounted, rennspezifisch). Sie entstehen pro Runde in `NetLobby`.
7. **Oberfläche**: `lobby_hud.gd` (`LobbyScreens`) und `party_hud.gd` (`PartyScreens`). Den Ablauf steuert `main.gd` über Phasen wie `net_menu`, `net_lobby`, `net_garage`, `net_round`, `net_countdown`, `draw`, `net_drawn`, `net_reveal`, `countdown`, `race`, `result`.

### Transport

- **ENet über UDP**, Godot `ENetMultiplayerPeer`. Es wird **direkt** benutzt (`put_packet`, `get_packet`, `set_target_peer`, `set_transfer_mode`, `set_transfer_channel`), ohne SceneMultiplayer, RPCs, MultiplayerSpawner oder Synchronizer.
- **Ports:**

  | Port | Protokoll | Zweck |
  |---|---|---|
  | 24680 | ENet | Spiel (`GAME_PORT`) |
  | 24681 | UDP | Host lauscht auf Suchanfragen und Gateway-Proben (`DISCOVERY_PORT`) |
  | 24682 | UDP | Mitspieler lauschen auf Ankündigungen (`BEACON_PORT`) |

- **Plätze:** `MAX_CLIENTS = 3`, mit Host höchstens 4 Menschen. `host()` ruft `create_server(port, MAX_CLIENTS + 1, CUSTOM_CHANNELS)` mit einem Platz zu viel auf. So bekommt der vierte Mitspieler noch den Grund „Spiel ist voll“ statt einer stummen Absage.
- **Kanäle:** `CHANNEL_CONTROL = 0` ist zuverlässig (Lobby, Linien, Ereignisse); Pings laufen dort unzuverlässig. `CHANNEL_SNAPSHOT = 1` ist `UNRELIABLE_ORDERED` für Renn-Schnappschüsse.
- **Kein WebSocket, kein TCP.** HTTP gibt es nur im Updater (`HTTPRequest` zu GitHub).

### Autoritativer Host

Ja, durchgehend. Der Host führt den gesamten Lobby-Zustand und verteilt ihn als `lobby`-Nachricht. Das geschieht nach jeder Änderung und zusätzlich jede Sekunde mit frischem Ping (`NetLobby._broadcast`, `STATE_INTERVAL_MS = 1000`).

- **Mitspieler schicken nur Wünsche:** `pick`, `ready`, `away`, `loaded`, `draw_progress`, `draw_plan`, `draw_withdraw`, `race_turbo`, `race_alive`.
- **Der Host prüft:**
  - `_apply_pick`: Farbe eindeutig, Name eindeutig.
  - `NetDraw.check_plan`: Lage, Tempo, Fortschritt der Linie.
  - Prüfsumme der Strecke.
- **Mitspieler säubern ihrerseits jede Host-Nachricht** (`NetLobby.clean_players`, `clean_settings`, `NetDraw._clean_roster`, `NetRace.clean_rows`, `unpack_snapshot` mit Endlichkeits- und Größenprüfung).
- **Im Rennen rechnet nur der Host.** Gleitkomma ist zwischen Handys nicht bitgleich (libm aus bionic); der Godot-Vorschlag #7128 für Festkomma wurde „closed as not planned“.

### Nachrichtenformat

- **ENet-Paket:** 2 Byte Kennung `"D2"` (0x44 0x32), 1 Byte Protokollversion (`VERSION = 6`), dann `var_to_bytes(Dictionary)` mit dem Typ im Schlüssel `"t"` (`NetProtocol.encode` / `decode`).
- **Entpacken:** immer `bytes_to_var`, nie `…_with_objects`. Grenze `MAX_MESSAGE_BYTES = 1 MB`.
- **Fremde Protokollversion** ergibt `{"t": "_foreign"}`. Der Host lehnt dann mit klarem Grund ab.
- **Ablehnung** hat ein versionsunabhängiges Format (`encode_reject`): Versionsbyte 0, danach UTF-8 `"code\ngrund"`. Auch ein Gerät mit anderer Protokollversion kann den Grund also lesen.
  - Codes: `protocol`, `bad`, `game`, `physics`, `track`, `full`, `busy`, `kick`.
- **Reservierte Typen**, die `NetSession` selbst behandelt: `hello`, `welcome`, `reject`, `ping`, `pong`, `players`, `bye`. Alles andere geht als Signal `message_received` weiter.
- **Weiterleitung in `NetLobby`:** `draw_*` geht an `NetDraw.on_message`, `race_*` an `NetRace.on_message`, der Rest an `custom_message`.
- **Suchpakete** sind JSON-Text mit Magie `"D2R-HOST"` bzw. `"D2R-SUCHE"`. `_parse_json` verwirft Fremdpakete ohne Engine-Fehlermeldung: höchstens 1 KB, erstes Zeichen `{`, keine Steuerbytes unter 9, Feld `"v"` muss eine Zahl sein.

### Discovery (`NetDiscovery`, dreistufig)

1. **Ankündigung und Rundruf**
   - Der Host sendet jede Sekunde (`announce_interval_ms`) an 255.255.255.255 **und** an den gerichteten Rundruf jedes eigenen IPv4-Netzes (`_refresh_targets`, `NetProtocol.directed_broadcast`), Zielport 24682.
   - Mitspieler fragen zusätzlich jede Sekunde selbst per Rundruf an Port 24681. Der Host antwortet per Unicast an den Absender (`_poll_host`).
   - Der gerichtete Rundruf ist nötig, weil 255.255.255.255 bei eingeschalteten mobilen Daten oft im Mobilnetz landet.
2. **Gateway-Probe**: eine Unicast-Anfrage an das WLAN-Gateway (`NetAndroid.wifi_gateway`). Im Handy-Hotspot ist der Host das Gateway. Seit Android 11 wählt der Hotspot ein zufälliges `192.168.x.0/24`.
3. **Adresse von Hand** (`add_manual`), optional `127.0.0.1` für PC-Tests (`probe_local`).

Weitere Einzelheiten:
- **Inhalt jeder Antwort:** Name, Port, Spieler/max, Spielversion, Physik, Sitzungskennung `sid`, `busy` (Rennen läuft), `re` (über welchen Weg gefragt wurde) und `q`/`n` (Nummern für die Antwortzeit).
- **Einträge** sind nach `sid` geschlüsselt; ein Host mit mehreren Adressen ergibt also einen Eintrag. Sie verfallen nach 4,5 s (`expire_after_ms`).
- **Sortierung:** kompatible Spiele zuerst (`sorted_games`).
- Zähler je Weg und eine Protokollzeile je erstem Fund dienen der Gerätediagnose.
- `NetLobby._only_announced` erkennt den Fall „Host sichtbar, antwortet aber nicht“: mindestens 3 Ankündigungen, aber keine einzige Antwort. Dann erscheint ein gezielter Hinweis.

**Multicast-Sperre:** Godot nimmt sie für Rundruf-Sockets selbst (PR #33910). Zusätzlich hält `NetHelper.multicastAcquire` eine eigene, nicht referenzgezählte Sperre `"Draw2RaceNetz"` (`NetAndroid.multicast`). Sie wird in `NetLobby.enter` geholt und in `exit` freigegeben.

**Berechtigungen** im Manifest: `INTERNET`, `REQUEST_INSTALL_PACKAGES` (Updater), `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`. Keine Laufzeitdialoge, targetSdk 35.

### WLAN-Bindung (Android)

`NetHelper.bindNetwork(handle)` ruft `ConnectivityManager.bindProcessToNetwork` auf. Grund: Ein Hotspot ohne Internet wird nie zum Standardnetz. Bei aktiven mobilen Daten liefen ungebundene Sockets sonst ins Mobilnetz.

- **Gilt nur für danach erzeugte Sockets.** Also erst binden (`NetLobby._bind`), dann Sitzung und Suche anlegen.
- **Beim Verlassen wird gelöst** (`exit`), damit Update-Suche und Internet wieder gehen.
- **Gastgeber mit eigenem Hotspot bindet nie** (`NetAndroid.host_plan`): Gebundene Sockets nutzen nur die Routing-Tabelle des WLANs, und dort fehlt das Hotspot-Netz.
- **Hotspot-Erkennung** (`hotspot_network`, `hotspot_interfaces`):
  - Schnittstellen `swlan`/`softap`/`ap` immer; `wlan1/2`, `rndis`, `usb`, `bt-pan` nur ohne Gateway.
  - Android 16 meldet den eigenen Hotspot als eigenes „lokales Netz“.
- **Hotspot geht erst nach dem Eröffnen an** (`_host_hotspot`): Bindung lösen, `discovery.restart_host()` mit gleicher `sid` aufrufen, und solange noch niemand beigetreten ist, auch den ENet-Host neu anlegen.
- **WLAN-Wechsel** (`refresh_status` alle 2 s): `bound_to_wifi` vergleicht das Handle; danach wird neu gebunden und neu gesucht.

### Lobby-Ablauf und Beitritt (`NetLobby`, Nachrichtenliste im Dateikopf)

1. **Einstieg:** `enter()` bindet und holt die Multicast-Sperre, dann startet `search()`.
2. **Eröffnen:** `host(track, stage)` legt ENet-Server und Ankündigung an; der Host steht als Spieler 1 in der Liste.
3. **Beitreten:** `join(addr)`.
   - ENet verbindet; der Mitspieler sendet sofort `hello` mit `proto`, `game` (App-Version), `physics` (`RaceVehicle.VERSION`), `track` (SHA-256 über alle Streckendateien, `tracks_hash`), `name`, `os` und `model`.
   - Der Host prüft mit `check_hello`, in dieser Reihenfolge: Protokoll, Felder, Spielversion, Physik, Strecken, dann `join_block` („Rennen läuft“), dann „voll“.
   - Annahme: `welcome {id, name (eindeutig), host, game, proto, host_time}`, danach die Liste `players`.
   - Wer sich nicht binnen 5 s anmeldet, fliegt (`HELLO_TIMEOUT_MS`).
4. **Wunsch nach der Annahme:** Der Mitspieler schickt `pick {car, color, name, seq}`. Der Host antwortet mit dem vollständigen Zustand `lobby {rev, phase, round, settings, players[{id, name, car, color, ready, host, away, loaded, ping, ack}]}`.
5. **Kein Flackern durch Wunschnummern:** Jeder Wunsch trägt eine fortlaufende Nummer (`_wish`). Bis der Host sie als `ack` bestätigt, behält die eigene Zeile den lokalen Wunsch (`_client_message` bei `"lobby"`). Sonst würde „Bereit“ flackern.
6. **Einstellungen:** Nur der Host stellt ein (`set_track`/`stage`/`ai`/`contacts`). Jede Änderung setzt „Bereit“ aller Mitspieler zurück (`_settings_changed`).
7. **Start:** Nur der Host startet (`start_round`, Bedingung `start_problem()`). Es folgen `start {round}`, dann lädt jedes Gerät und meldet `loaded {hash}`.
   - Wenn alle geladen haben, sendet der Host `go {draw_at}`.
   - Abbruch bei abweichender Prüfsumme (`kick` mit Code `track`).
8. **Zurück:** `back {reason}` führt in die Lobby; `close {reason}` bedeutet, der Host beendet. Danach trennt er sauber.
9. **Revanche:** `rematch()` startet eine neue Runde mit der Startreihenfolge als Liste von Spieler-IDs (`_round_players(order)`).

### Namen und Farben

- **Namen:**
  - `NetProtocol.clean_name`: höchstens 12 Zeichen, keine Steuerzeichen, Umlaute erlaubt.
  - Gleiche Namen bekommen eine Ziffer („Anna 2“), über `NetProtocol.unique_name` bzw. `NameTags.unique_name`.
  - Gespeichert wird der eigene Name im Spielstand (`ProgressStore`).
- **Spielerfarben** (`player_colors.gd`):
  - 6 Farben (Rot, Himmelblau, Gelb, Lila, Orange, Weiß), auch bei Rot-Grün-Schwäche unterscheidbar (OKLab-Mindestabstand über normales Sehen, Protanopie und Deuteranopie, `distance()`).
  - `default_for(slot)` gibt die Vorgabe je Platz. Wer eine belegte Farbe wünscht, bekommt die nächste freie (`free_color`). Der Host entscheidet endgültig.
  - `rival_order` wählt KI-Autos, die sich farblich abheben.
- **Namensschilder** (`name_tags.gd`): 2D-Schilder an 3D-Positionen (`unproject_position`), am Bildrand mit Pfeil, mit Ausweichlogik. Komplett 3D- und rennbezogen.

### Wiederverbindung

**Gibt es nicht.**
- Während einer Runde ist der Beitritt gesperrt (`session.join_block = "Das Rennen hat schon begonnen…"`).
- Ein Mitspieler, der geht, bleibt mit abgegebener Linie in der Runde, und sein Auto fährt ohne Turbo (`NetDraw.peer_left`, `NetRace.peer_left`). Ohne Linie fliegt er aus der Runde.
- Wenn der Host geht, endet die Sitzung für alle (`NetLobby.closed`, `main.net_closed`, Hinweis, Menü). Eine Host-Übergabe wurde bewusst ausgeschlossen.
- Es gibt keine Sitzungs- oder Spielerkennung, um nach einem Abbruch wieder auf denselben Platz zu kommen. Wiedereinstieg geht erst in der nächsten Lobby.
- **App im Hintergrund:** `main._notification` ruft `lobby.set_away(true)` auf, bevor Android die App anhält. Die anderen sehen dann „im Hintergrund“.
  - Im Rennen wird zusätzlich der Turbo losgelassen (`race.set_turbo(false)`).
  - Kommt die App rechtzeitig zurück, springt die Anzeige zur gemeinsamen Zeit (`display_ticks`, Sprung über 15 Takte).
  - Sonst greift die ENet-Zeitgrenze.

### Zeitsynchronisation

- **Echo-Ping** alle 250 ms, unzuverlässig (`NetSession._tick`, `PingStats`).
  - Messgrößen: RTT, Jitter (RFC 3550), Verlust, Anlaufverluste.
  - **Uhrversatz** = `remote + rtt/2 − now`, aus der **schnellsten der letzten 16** Antworten.
- **Gemeinsame Uhr:** `host_time_usec()` ist die Host-Uhr, beim Mitspieler plus Versatz. `clock_synced()` gilt ab 4 Antworten.
- **Gemeinsame Zeitpunkte** werden in Host-Zeit verschickt:
  - `draw_at` ≈ 3 s nach „alle geladen“
  - `reveal_at` = Verteilen + 0,8 s
  - `start_at` = `reveal_at` + 3 s
  - `go_at` = `start_at` + 3 s Ampel
- **Messwerte:** am PC 1–5 ms genau. Gerätetest im Heim-WLAN: Versatz auf ±5 ms übereinstimmend gemessen, RTT im Mittel 40 ms, Spitzen 220 ms durch WLAN-Stromsparen.
- `NetDraw.host_now()` hat einen Rückfall ohne Abgleich: Zeitpunkt der letzten Host-Nachricht.

### Fehlerbehandlung (Auswahl, alles in `net_session.gd`)

- **ENet-Paketdrossel:** ENet drosselt bei schwankender RTT unzuverlässige Pakete; am PC ging über die Hälfte der Pings verloren. Gegenmaßnahme `_on_peer_connected`: `throttle_configure(1000, 32, 0)` und eigene ENet-Pings alle 100 ms.
  - Bleibt eine Anlaufphase von etwa 1 s nach dem Verbinden. Verluste darin zählen nicht (`WARMUP_USEC` 2,5 s, `early_lost`).
- **Zeitgrenzen:** `peer_timeout` normal 8–20 s, beim Laden 25–45 s (`NetLobby.load_timeout`, `loading_window`, `_apply_timeouts`).
  - Zusätzlich trennt das Spiel selbst bei Funkstille ab der Mindestgrenze, frühestens nach 3 s (`SILENCE_FLOOR_MS`). Grund: ENet prüft nur, wenn eine Wiederholung fällig ist, und deren Abstand verdoppelt sich.
  - Im Rennen erkennt `silent_usec()` Ausfälle schon nach 0,5 s (`NetRace._check_silence`).
- **`_put()`** sendet nur an Partner, die ENet gerade als verbunden führt. Sonst entsteht „Unable to send packet on channel 1, max channels: 0“.
- **Sauberes Beenden** mit `close_gracefully(msg, 600 ms)`: letzte Nachricht senden, `flush`, `peer_disconnect_later`, dann warten, bis alle weg sind. ENet trennt erst, wenn die zuverlässigen Pakete angekommen sind.
- **Schließen während `poll()`** wird verschoben (`_close_after_poll`), weil die ENet-Signale innerhalb von `poll()` laufen.
- **Gerätelog:** `NetLog` schreibt jede Zeile mit Zeitstempel sofort auf die Platte (`user://mehrspieler.log`, `user://netztest.log`), ab 4 MB wird rotiert. Abholen mit `adb shell run-as de.draw2race.game cat files/…`.

---

## 2. Weitergeben-Modus („Auf einem Handy“, M2b)

**Daten:** `pass_party.gd` (`PassParty`). **Bildschirme:** `party_hud.gd` (`PartyScreens`). **Ablauf:** `main.gd` (`open_party` … `party_finish`). **Turboknöpfe:** `turbo_pads.gd`.

**Phasen:** `party_setup` → (`party_garage`) → `handover` → `draw` → `drawn` → (nächster Spieler `handover` …) → `reveal` → `countdown` → `race` → `result`.

**Einstellungen** (`setup_screen`, `player_row`):
- 2–4 Spieler, jeweils mit Name (Eingabefeld), Auto und Farbe über die Garage (`garage_screen`).
- Hinzufügen und Entfernen von Spielern; Strecke, Stufe, KI, Berührungen.
- Startknopf „Los – {Name} zeichnet zuerst“.
- Nichts davon wird gespeichert (`party_memory` lebt nur in der Sitzung; der Spielstand bleibt bytegleich).

**Übergabekarte** (`PartyScreens.handover`, `main.party_handover`):
- `world.visible = false`, Linien und Autos werden gelöscht (`clear_cars`, `draw_routes([], [])`).
- Eine bildschirmfüllende dunkle Fläche (`#0c3239`) mit einer Karte. Oben ein Streifen in der Spielerfarbe.
  - Zeile „LINIE k VON n · STRECKE“, Titel „Spieler k: Name“.
  - Untertitel „Handy nehmen, dann tippen“ bzw. „Handy weitergeben, dann tippen“.
  - Liste aller Spieler mit Farbpunkt und Stand „fertig ✓ / ist dran / wartet“.
  - Fläche in der Spielerfarbe: „Tippen, wenn du das Handy hast“; Hinweis „Die Linien der anderen bleiben verdeckt …“.
- **Die ganze Fläche ist ein Knopf** (`HandoverTap`). **Tippsperre 350 ms** (`CARD_GUARD_MS`), damit der Finger des Vorgängers nicht gleich weiterklickt.

**Zeichnen und danach:**
- Während des Zeichnens zeigt ein Schild in der Spielerfarbe, wer dran ist (`draw_chip`).
- Danach folgt `drawn_card`: „Gut gezeichnet, Name!“, „Neu zeichnen“ und „Weitergeben →“ (beim Letzten „Alle Linien zeigen →“). Hinweis: „Weitergeben verdeckt deine Linie“.
- Der Spielerwechsel ist schlicht `party.turn += 1` und ein neuer `party_handover()` (`main.party_pass`).

**Enthüllung:** Alle Linien erscheinen 3 s lang in den Spielerfarben (`REVEAL_TIME`). Eine Legende zeigt Namen und Farbstreifen. Tippen startet sofort (`reveal`, `update_reveal`).

**Rennen:**
- Turboknöpfe je Mensch in den Bildschirmecken (`hud.pads.show_pads`), mehrere Finger gleichzeitig (`pad_input` nach Touch-Index), am PC die Tasten 1–4.
- Die Kamera hält alle Menschen im Bild.
- `NameTags` behandelt im Weitergeben-Modus alle Menschen als „eigene“ Autos.

**Wertung** (`results`): Namen und Zeiten, kein Gold, keine Bestenliste. Danach „Revanche“ (neue Linien, der Sieger startet hinten, `PassParty.rematch` / `note_result`), „Einstellungen ändern“ oder „Zurück zum Menü“.

**Pause und Zurück:**
- Pause: „Kurze Pause. Alle Linien warten“, mit „Weiter“, „Meine Linie neu zeichnen“, „Runde abbrechen“, „Zum Menü“.
- `pause_game()` greift bei Fokusverlust.
- Die Zurück-Taste ist je Phase belegt (`main.go_back`).

**Namen:** Leere Namen werden zu „Spieler n“; Doppelte bekommen eine Ziffer (`PassParty.names`).

---

## 3. Was ist für ein rundenbasiertes Kartenspiel wiederverwendbar?

### Direkt übernehmbar, praktisch unverändert

| Teil | Anmerkung |
|---|---|
| `NetSession` | Komplett generisch: Anmeldung, Ablehnung mit Grund, Ping, RTT, Uhr, Funkstille, `close_gracefully`, `kick`, `send(peer_id)` und `send_all`. Nur `physics_version` und `track_hash` umdeuten (Regel- bzw. Asset-Version). |
| `NetProtocol` | Magie (z. B. `"MF"`), Versionsfeld, `encode`/`decode`, `encode_reject`, `check_hello`, Beacon/Query-JSON, Adressfunktionen. `RaceVehicle.VERSION` durch eine Regelversion ersetzen. |
| `NetDiscovery` | Generisch: drei Suchwege, Sitzungskennung, `busy`, Zähler. |
| `NetAndroid` und `NetHelper.java` | Generisch und mit Gerätetests gehärtet: WLAN-Bindung, Hotspot-Erkennung inklusive Android 16, `host_plan`, Gateway, Multicast-Sperre. Paket- und Klassennamen anpassen. |
| `NetLog`, `net_cli.gd`, `net_test_screen.gd` | Generisch (Diagnosebildschirm M0, Automatikmodus). |
| `PlayerColors` | Algorithmus generisch, **aber Vorsicht** (siehe unten). |
| Lobby-Muster aus `NetLobby` | Host-Zustand als Vollbild `lobby {rev, …}`; Mitspielerwünsche mit `seq`/`ack`; Bereit wird bei Einstellungsänderungen zurückgesetzt; `join_block`; `away` beim Pausieren; Start → laden → `loaded` → `go`; `back`/`close`; Revanche-Reihenfolge; Logik zu WLAN-Bindung und Hotspot (`_bind`, `_host_hotspot`, `refresh_status`); Testschnittstellen (`overrides`, `android_api`, `forced_status`, `auto_poll`). |
| Oberflächenmuster aus `lobby_hud.gd` | An Ort und Stelle aktualisieren statt neu aufbauen (Signaturen `_games_sig`, `_settings_sig`, `_garage_sig`), sonst gehen Fingertipps und der Fokus des Namensfelds verloren; Toast; Netzhinweise (`status_text`, `host_addresses`); Adressdialog oben wegen der Bildschirmtastatur; Bestätigungen bei Zurück (`go_back`). |
| Übergabekarte aus `party_hud.gd` | Direkt als Sichtschutz zwischen Zügen nutzbar, inklusive Tippsperre. |

### Rennspezifisch, nicht übernehmen

- `NetRace`: 30-Hz-Schnappschüsse, Interpolation, Extrapolation, Turbo mit 6 Takten Verzug, `race_alive`, Marionetten.
- Die Linienlogik in `NetDraw` (`pack_plan`, `check_plan`).
- `name_tags.gd` (3D-Projektion).
- Die Einstellungsfelder von `NetLobby` (`track`, `stage`, `ai`, `contacts`, `max_ai`, `tracks_hash`, `report_loaded` mit `Circuit`).
- Alle Bezüge auf `RaceVehicle.CARS`, `PassParty`, `ProgressStore`.
- Die `PassParty`-Daten (Linien, Startaufstellung).

### Als Muster wertvoll

- **`NetDraw`:** verdeckte Abgabe beim Host, gemeinsame Enthüllung erst, wenn alle fertig sind, dazu eine Prüfsumme über alles Verteilte (`plans_digest`).
- **`NetRace`:** ein autoritatives Ereignisprotokoll plus Nachrechnen. `replay` und `sim_digest` belegen, dass der Host bitgleich wie die Offline-Logik rechnet. Bei einem Kartenspiel geht das mit Aktionslog plus Seed.

### Was sich für verdeckte Information ändern muss

1. **Ansicht je Empfänger statt Rundruf.** Heute schickt `NetLobby._broadcast()` mit `send_all(state_message())` allen dasselbe. Für Karten braucht es eine Funktion wie `view_for(peer_id)` und je Partner `session.send(id, …)`.
   - Den eigenen Hand-Inhalt bekommt nur der Besitzer.
   - Andere sehen pro Karte nur die öffentliche Seite. Bei Flip ist das die jeweils andere Kartenseite, also auch für den eigenen Rand gilt: Die eigene Rückseite darf man selbst nicht sehen, die Mitspieler schon. Dazu kommen die Kartenzahl und beim Nachziehstapel die oben sichtbare Seite.
2. **Zufall und Mischen nur beim Host, Seed nie verschicken.** Sonst kann ein Gerät den Stapel nachrechnen.
3. **Eingaben als Absichten** (`play {card_id, seq}`, `draw`, `choose_color` …), vom Host gegen die Regeln geprüft. Das ist dasselbe Muster wie `pick`/`ready`/`draw_plan` mit `seq`/`ack` und `draw_reject {reason}`.
4. **Ereignisse zuverlässig mit Rundenzähler** statt Schnappschüssen. Kanal 1 und die unzuverlässigen Modi werden unnötig.
5. **Prüfsummen** nur über öffentliche Daten. Eine je Empfänger unterschiedliche Sicht kann nicht über eine gemeinsame Gesamtprüfsumme geprüft werden.
6. **Wiederverbindung wird Pflicht.** Ein Kartenspiel dauert länger, Handys sperren den Bildschirm, und iOS-Browser trennen Hintergrund-Tabs. Nötig sind eine Spielerkennung bzw. ein Token beim `hello`, eine Platzreservierung statt `join_block`, und nach dem Wiederbeitritt ein frisches `view_for(id)`. Draw2Race hat nichts davon.
7. **Der Host spielt selbst mit.** Sein Gerät kennt alle Karten; das lässt sich technisch nicht verhindern, nur in der Oberfläche nie anzeigen. Optional wäre ein reines „Tisch“-Gerät denkbar.
8. **Sitzordnung:** Die Spielerliste hat heute die Beitrittsreihenfolge (Host zuerst). `_round_players(order)` übernimmt aber schon eine ID-Liste. Eine vom Host gesetzte Sitzreihenfolge passt also in dieses Muster. Jeder Client rotiert die Darstellung so, dass er selbst unten sitzt.
9. **Weitergeben-Modus:** Die Übergabekarte wird **vor jedem Zug** gebraucht, nicht nur einmal je Runde. Nach dem Zug wird die Hand automatisch verdeckt. Bei Flip ist das unkritisch, weil die Fremdseiten der Mitspieler ohnehin öffentlich sind; die eigene Rückseite darf trotzdem nicht erscheinen.

**Achtung Farben:** Die Spielerfarben aus `PlayerColors` (Rot, Himmelblau, Gelb, Lila, Orange) überschneiden sich mit den Kartenfarben beider Flip-Seiten (Rot, Gelb, Grün, Blau bzw. Pink, Türkis, Orange, Lila). Die Spieler sollten im Kartenspiel nicht über diese Farben, sondern über Avatar oder Symbol und neutrale Akzente unterscheidbar sein.

---

## 4. Testwerkzeuge

### Headless-Testreihen

Sie liegen in `game\tests\`, sind `SceneTree`-Skripte und laufen über `tools\godot_run.ps1 -Script res://tests/… -Timeout …`. Dieses Skript hält die Systemsperre `Global\Draw2RaceGodot`.

| Test | Inhalt |
|---|---|
| `test_net.gd` | Kodierung, Versionsprüfung, Suchformat, Adressrechnung, CLI-Parser. Eine Loopback-Sitzung Host plus Mitspieler **im selben Prozess**, synchron in `_init` mit Abfrage von Hand (`auto_poll = false`), Testports 24780–24782. Ablehnung bei falscher Version und vollem Spiel. Prüft auch, dass die Netzskripte die Simulation nicht berühren. |
| `test_lobby.gd` | Host und **drei** Mitspieler im selben Prozess über 127.0.0.1, Ports 24790–24792. Vorgaben über die statische Variable `NetLobby.overrides`: `probe_local`, `use_broadcast = false`, `use_binding = false`, `auto_poll = false`, kurze Zeitgrenzen. Suche, Beitritt, Zustand gleich, Ablehnungen, Verlassen, Abbrüche, Hintergrund. Zum Schluss die **echte Oberfläche** (`main.tscn`) als Mitspieler und als Host samt Zurück-Taste. |
| `test_draw.gd`, `test_race.gd` | Wie oben (Ports 24796–98 bzw. 24800–02, Zeitraffer 6×). Linien bytegleich bei allen; der Host rechnet bitgleich wie `RaceField` ohne Netz; 10 % verworfene Schnappschüsse; Fehlerfälle. |
| `test_party.gd` | Weitergeben mit 2, 3 und 4 Spielern über die echte Oberfläche. Spielstand bytegleich, Determinismus, Zurück-Taste. |
| `test_tags.gd`, `test_multi.gd` | Namensschilder; Umbau „mehrere Menschen“ (Einzelspieler bitgleich). |
| Kontrollbilder | `lobby_shots.gd`, `party_shots.gd`, `draw_shots.gd`, `race_shots.gd`, `tag_shots.gd`. `lobby_shots` gibt mit `forced_status` einen erfundenen Android-Netzstatus vor (WLAN bzw. kein WLAN). Hinweis: `-Resolution 2400x1080` wird von Windows still auf 1924×1061 begrenzt; für 20:9 besser `1600x720`. |

Für die Bindungs- und Hotspot-Logik lässt sich `android_api` durch einen Ersatz austauschen. Die Fallbeispiele in den Tests stammen aus echten Geräteprotokollen.

Stand: 16 Testreihen mit 1402 Prüfungen.

### Mehrere Prozesse auf einem PC (`tools\net_test.ps1`)

Das Skript startet getrennte headless-Godot-Prozesse **ohne** die Godot-Sperre (sie müssen gleichzeitig laufen) und wertet ihre Ergebniszeilen aus.

- **Ping-Modus** (`net_cli.gd` → `NetTestScreen` im Automatikmodus, `--nettest=host|join|join:ADR|search`):
  - 1 Host und N Mitspieler.
  - Mitspieler 1 sucht per Rundruf und Ankündigung, Mitspieler 2 verbindet über 127.0.0.1, Mitspieler 3 über die LAN-Adresse des PCs (die Adresse am Standard-Gateway).
  - `-Reject` fügt einen Mitspieler mit falscher Version hinzu, `-Search` einen reinen Suchlauf.
- **Lobby-Modus** (`-Lobby`, `lobby_cli.gd`, `--lobbytest=…`):
  - Ein komplettes Spiel: Host, 3 Mitspieler und Bot-Linien (`ai_route`), Turbo nach festem Plan je Name.
  - Störfälle: `--lobbytest-fake=track|version` (Ablehnung erwartet), `--lobbytest-leave` (saubere Abmeldung), `--lobbytest-stall` (Hänger des Hauptthreads von 5–6 s beim Laden), `--lobbytest-drop` (Schnappschussverlust), `--lobbytest-speed` (Zeitraffer).
- **Auswertung:**
  - Exitcode und Zeilen `NETTEST-ERGEBNIS` bzw. `LOBBYTEST-ERGEBNIS`.
  - Keine `SCRIPT ERROR` oder `ERROR:`-Zeilen.
  - Prüfsummen `digest=`, `wertung=`, `sim=`, `farben=` müssen bei allen Prozessen gleich sein.
  - Der Host muss `abgemeldet=1` melden.
- **Besonderheiten bei mehreren Instanzen auf einem Rechner:**
  - Den passiven Ankündigungs-Port 24682 kann nur **ein** Prozess binden. Die übrigen fallen auf „nur aktive Suche“ zurück (`start_search`, `passive_ok`).
  - `probe_local` fragt zusätzlich 127.0.0.1.
  - Die Tests nutzen eigene Portbereiche je Testreihe.
  - `Engine.max_fps = 120` bzw. 60, damit kein Prozess im Leerlauf tausende Bilder je Sekunde rechnet.

### Auf dem Gerät

- Ein versteckter Bildschirm **„Netztest“** im Entwicklermenü (5× aufs Logo tippen, `NetTestScreen`): Host, Mitspielen, Adresse eingeben, „Nur anfragen“, ein Schalter „An WLAN binden“, die Liste gefundener Spiele mit Fundweg, RTT, Jitter, Verlust, Uhrversatz, ENet-Drossel und Netzstatus. Er schreibt `user://netztest.log`.
- Im Spiel selbst schreibt die Lobby `user://mehrspieler.log`.
- Die Handys werden per WLAN-Debugging angesprochen.

---

## 5. Vorüberlegungen zu Browser, WebSocket, Hotspot, Hotel-WLAN, QR-Code und APK-Weitergabe

- **Browser-Clients und WebSocket:** **Keinerlei Überlegungen.** Im ganzen Projekt kommen weder WebSocket, WebRTC noch ein HTTP-Server vor. Am nächsten kommt ein PC als Mitspieler (Recherche 4.5): Weil nur der Host rechnet, könnte der Windows-Build als Host oder Mitspieler teilnehmen.
- **Hotspot:** ausführlich behandelt, Recherche 1, 2A, 3a und 4.2–4.4.
  - Der normale Handy-Hotspot ist der **Hauptweg**; ein gemeinsames WLAN gilt als gleichwertig.
  - Laut Google bis zu 10 Geräte; Anbieter können Tethering sperren; ohne SIM teils kein Hotspot.
  - Seit Android 11 ein zufälliges Netz, daher die Gateway-Probe.
  - Hauptstolperstelle: Mitspieler mit mobilen Daten. Lösung ist die WLAN-Bindung, ersatzweise „mobile Daten aus“.
  - Pixel-Hotspot nicht auf „nur 6 GHz“ stellen.
  - Offen am Gerät: Hotspot ganz ohne Internet, Mitspieler mit mobilen Daten, Host mit eigenem Hotspot.
- **Hotel- und Gast-WLAN mit Geräte-Isolierung:** nur kurz erwähnt. Gast- oder Hotel-WLANs sperren oft den Verkehr zwischen Geräten, dann soll man auf den Handy-Hotspot ausweichen (2B). In der Vergleichstabelle stehen als Risiko „Gast-WLANs mit Geräte-Isolierung; Router, die Broadcasts filtern“. Eine eigene Lösung gibt es nicht.
- **QR-Code:** an drei Stellen.
  1. Als Ergänzung zur Adresseingabe: Der Host zeigt seine Adresse als QR. Dafür wird das Addon Kenyoni „QR Code“ genannt (reines GDScript, MIT, Godot 4.4–4.7).
  2. Meilenstein **M8 „Komfort (später)“**: Das Spiel öffnet selbst ein WLAN (LocalOnlyHotspot) und zeigt einen QR-Code, den die Mitspieler scannen. Aufwand +2–3 Tage. Braucht den Laufzeitdialog `NEARBY_WIFI_DEVICES` (Android 13+) bzw. Standort bis Android 12. Geht nicht, solange der normale Hotspot läuft; das System kann ihn beenden; kein Internet.
  3. Hersteller-QR zum Teilen des Hotspots: ungeprüft. Die Google-Hilfe nennt keinen solchen QR-Code.
- **APK-Weitergabe:** **Nicht vorgesehen.** Es gilt nur die Regel „vorher zu Hause alle auf dieselbe Version bringen“, weil unterwegs ohne Internet das Update nicht geht und die Lobby abweichende Versionen strikt ablehnt.
  - Der vorhandene Updater bietet aber die Bausteine: `updater.gd` mit `Updater.java` prüft Paketname, höheren `versionCode`, `versionName` und identische Signatur, dann installiert er über den FileProvider. Dazu kommen `REQUEST_INSTALL_PACKAGES` und zwei Kanäle (`REPOSITORY` `ShakieVan/Draw2Race`, `BETA_REPOSITORY` `ShakieVan/Draw2Race-Beta`).
- **Nicht empfohlen** (mit Begründung in der Recherche):
  - Wi-Fi Direct: launisch, viel Java.
  - Bluetooth: keine IP-Verbindung, mehrere Verbindungen wackelig.
  - Google Nearby: braucht Play-Dienste, keine IP-Verbindung, proprietär; nur als Plan C.
- **Android 17:** Mit targetSdk 37 wird `ACCESS_LOCAL_NETWORK` ein Laufzeitdialog („Geräte in der Nähe“). Er gilt auch für Rundruf, Multicast und mDNS. Draw2Race (targetSdk 35) ist vorerst nicht betroffen; ein Godot-Update kann den Standardwert aber anheben.

---

## 6. Bekannte Probleme und Lehren

| Problem und Befund | Lösung bzw. Stelle |
|---|---|
| ENet drosselt unzuverlässige Pakete bei RTT-Schwankung; etwa 1 s nach dem Verbinden einmal für ~1 s auf 1/32. | `NetSession._on_peer_connected` (`throttle_configure(1000, 32, 0)`, `ping_interval(100)`), `WARMUP_USEC`. Über 127.0.0.1 ist das Verhalten noch offen. |
| ENet-Zeitgrenze greift erst bei fälliger Wiederholung, deren Abstand sich verdoppelt; tatsächliche Trennung zwischen Minimum und doppeltem Minimum. | Eigene Funkstille-Prüfung in `NetSession._tick`; schnelle Erkennung über `silent_usec()`. |
| Ein langsames Handy (S10) hing beim Laden des Steinbruchs 5,1 s und flog heraus. | Lange Zeitgrenzen 25–45 s beim Laden (`NetLobby.loading_window`, `_apply_timeouts`). Der Host verschickt `start` und ruft `flush()` auf, **bevor** er selbst lädt (`_begin_round`). |
| „Unable to send packet on channel 1, max channels: 0“ beim Senden an einen Partner, der gerade getrennt wird. | `NetSession._put` prüft `packet_peer.get_state()`. |
| Die Gegenseite sah die Trennung vor der letzten Nachricht. | `close_gracefully` mit `peer_disconnect_later` und Wartezeit. |
| Eigener Lobby-Wunsch flackerte, weil ein älterer Host-Zustand ihn überschrieb. | `seq`/`ack` in `NetLobby._wish` und `_client_message`. |
| Ein Neuaufbau der Oberfläche jede Sekunde verschluckte Tipps und nahm dem Namensfeld den Fokus. | Signaturen und Aktualisierung an Ort und Stelle (`lobby_hud.gd`, `net_test_screen._rebuild_games`). |
| Die Bildschirmtastatur verdeckte Eingabefelder. | Dialoge oben im Bild; `RaceHUD.update_keyboard_lift`. |
| 255.255.255.255 ging bei aktiven mobilen Daten ins Mobilnetz. | Gerichteter Rundruf je Schnittstelle (`NetDiscovery._refresh_targets`). |
| Gerätetest S24 Ultra (Android 16) mit eigenem Hotspot und Heim-WLAN zugleich: Antworten an Hotspot-Mitspieler liefen ins Heim-WLAN; nach „WLAN aus“ band sich das Spiel an den eigenen Hotspot. | `NetAndroid.hotspot_network`, `host_plan`, `NetLobby._bind`, `_host_hotspot`. |
| Nach einem WLAN-Wechsel meldet Android weiter das alte, verlorene Netz als gebunden. | `NetAndroid.bound_to_wifi` vergleicht das Handle; danach neu binden und neu suchen (`refresh_status`). Am Gerät noch ungeprüft. |
| Gleitkomma ist zwischen Geräten nicht bitgleich. | Nur der Host rechnet; Determinismus über `replay` und `sim_digest` belegt. |
| Hotspot des S21 (Samsung betreibt ihn neben dem Heim-WLAN): 8–9 % Verlust der Echo-Pakete. | Puffer und Interpolation; für ein Kartenspiel irrelevant, zuverlässige Nachrichten genügen. |
| WLAN-Stromsparmodus: RTT-Spitzen bis 220 ms. | Kein Handlungsbedarf bei rundenbasiertem Spiel. |
| S10 an einem WPA3-Router: Bei der Erneuerung des Gruppenschlüssels alle 10 min gelegentlich abgemeldet (`DISASSOC_STA_HAS_LEFT`). | Realistischer Störfall. Spricht für Wiederverbindung. |
| **Linienende (0.2.31):** Ein schneller letzter Strich setzte Punkte hinter das Ziel, der Host lehnte mit „Die Linie läuft rückwärts“ ab, das Rennen startete nicht. Am PC unentdeckt, weil die Bot-Linien immer exakt im Ziel endeten. | `LineRecorder.sample()`. **Lehre:** Testdaten von Bots decken menschliche Randfälle nicht ab; Client-Erzeugung und Host-Prüfung müssen auf denselben Regeln beruhen und gegen echte Bedienung getestet werden. |
| Unterwegs ist keine Aktualisierung möglich, die Lobby lehnt fremde Versionen strikt ab. | Bisher nur der Hinweis „vorher aktualisieren“. Genau die Lücke, die die APK-Weitergabe in Mau-Mau Flip schließen soll. |
| App im Hintergrund: Android hält sie an. | `main._notification` mit `set_away` und Turbo-Freigabe; `pause_game` hält im WLAN nichts an. |
| Kleinere Altlasten im Code und in der Doku | `unique_name` existiert doppelt (`NetProtocol` mit `MAX_NAME` 12, `NameTags` mit `ProgressStore.NAME_MAX`), ebenso `clean_name` (`NetProtocol` und `ProgressStore`). Der Kopf von `MULTIPLAYER_RECHERCHE.md` sagt noch „Status: Recherche, nichts davon ist umgesetzt“. In `IMPLEMENTIERUNG.md` steht unter M3 „Protokoll jetzt 3“; aktuell ist es 6. |
| Offene Geräteprüfungen laut `IMPLEMENTIERUNG.md` (Zeile 520) | Hotspot ganz ohne Internet, Mitspieler mit mobilen Daten (S24), Host mit eigenem Hotspot, Neu-Binden nach WLAN-Wechsel. |
| Host-Handy | Wird warm und braucht viel Akku (Hotspot, Rechnen, Darstellung). |

**Testgeräte des Nutzers:** S10 (Android 12), S21 (Android 15), S24 Ultra (Android 16), alle Samsung.

---

## Folgerungen für Mau-Mau Flip (meine Einschätzung, nicht aus Draw2Race)

- **ENet lässt sich im Browser nicht nutzen.** Godot-Web kann nur WebSocket bzw. WebRTC. Der Host bräuchte also zusätzlich einen WebSocket-Server (`WebSocketMultiplayerPeer.create_server` bzw. `TCPServer` mit `WebSocketPeer`).
  - `NetSession` nutzt fast nur die allgemeine `MultiplayerPeer`-Schnittstelle. ENet-spezifisch sind nur `get_peer()` mit Drossel, Zeitgrenze, `peer_disconnect_later`, Statistik sowie `enet.host.flush()`.
  - Eine dünne Transport-Abstraktion würde ENet für die Apps und WebSocket für Browser parallel erlauben. Für ein Kartenspiel ist WebSocket über TCP (immer zuverlässig) ohnehin ausreichend; es ginge also auch mit WebSocket allein.
- **Nachrichtenformat für den Browser:** `var_to_bytes` versteht nur Godot. Für einen leichten HTML/JS-Client ist JSON das passende Format.
- **Seite ausliefern:** Godot hat keinen HTTP-Server. Ein Mini-HTTP-Server über `TCPServer` oder ein Java-Helfer müsste die Webseite **und die eigene APK** ausliefern. Die eigene APK liegt unter `ApplicationInfo.sourceDir`.
  - Ein einziger QR-Code bzw. Link `http://<host-ip>:port/` bedient dann iPhones (Browser-Client) und Android-Geräte ohne App (APK-Download).
  - Die Signaturprüfung aus `Updater.java` ist für die Weitergabe von App zu App wiederverwendbar.
- **Kein HTTPS:** Die Seite muss über `http://` kommen, damit `ws://` zur lokalen IP nicht als gemischter Inhalt gesperrt wird.
- **UDP-Suche kann der Browser nicht.** Für Browser-Clients bleiben QR-Code und Link der einzige Weg.
- **Ordnername:** Der angelegte Projektordner heißt `E:\Documents\Programmierung\Mau-Maul Flip`, mit „Maul“. Das ist vermutlich ein Tippfehler.