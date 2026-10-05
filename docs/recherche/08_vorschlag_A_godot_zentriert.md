# Architekturvorschlag „Godot-zentriert“ für Mau-Mau Flip

## Kurzfazit

- Es gibt ein einziges Godot-4.6-Projekt mit drei Exporten:
  - **Android-APK:** Host, Mitspieler und Weitergeben-Modus. Die APK enthält zusätzlich den Web-Export als Dateien.
  - **Web:** Godot-Web-Export ohne Threads, nur als Mitspieler. Das Host-Handy liefert ihn über `http://` aus.
  - **Windows:** für Entwicklung, Tests und den PC als Host.
- Die Regeln laufen nur beim Host. Jedes Gerät bekommt nur seine eigene Sicht (`view_for(seat)`).
- **Ein Transport für alle:** einfaches WebSocket mit JSON-Text. Das gilt für App-Mitspieler und Browser-Mitspieler. ENet fällt weg. Die UDP-Suche aus Draw2Race bleibt nur für Apps.
- **Größter Vorteil:** Tisch, Hand und Effekte gibt es nur einmal. Der iPhone-Browser bekommt dieselbe Optik wie die App. Browser-Mitspieler haben automatisch genau die Version des Hosts.
- **Größte Schwäche:** Godot-Web über einfaches `http://` im WLAN ist eine Konfiguration, die Godot offiziell nicht unterstützt. Ich habe den Quelltext der installierten Vorlage geprüft (siehe 0). Das Problem ist lösbar, aber erst ein echtes iPhone beweist es.
  - Deshalb ist **Meilenstein M1 ein harter Go/No-Go-Test**, bevor Effekte entstehen.
  - Das JSON-Protokoll hält einen Plan B offen: einen schlanken HTML-Client, der dasselbe Protokoll spricht.
- **Aufwand:** etwa 70–90 Personentage bis 1.0. Der spielbare Kern mit Netz und Browser-Mitspielern braucht etwa 32.

---

## 0. Was ich selbst geprüft habe und wo ich den Berichten widerspreche

Geprüft habe ich die Godot-4.6.1-Vorlage `C:\Users\Shakie\Documents\Programmierung\Draw2Race\.tools\export\templates\web_nothreads_release.zip`. Ich habe sie im Speicher gelesen und nichts entpackt oder angelegt.

| Befund | Bedeutung |
|---|---|
| Die Secure-Context-Sperre steht **nur in der Standard-Seite `godot.html`**. Sie ruft `Engine.getMissingFeatures()` auf und zeigt bei Fehlen einen Fehlerhinweis. `engine.startGame()` prüft selbst nichts. | Eine **eigene Start-Seite** ohne diese Prüfung startet die Engine. Die Aussage „Godot-Web über http scheitert“ (Berichte android-infra und browser-iphone) gilt nur für die Standard-Seite. |
| In `godot.js` ruft `GodotAudio.init()` ungeschützt `ctx.audioWorklet.addModule(...)` auf (Positions-Worklet). `audioWorklet` gibt es nur im Secure Context. | Über http wirft die Audio-Initialisierung einen TypeError. Wahrscheinlich bricht damit der **ganze Start** ab, nicht nur der Ton. Den Lauf selbst habe ich nicht ausgeführt. Der Bericht „läuft ohne Ton“ stammt aus einer älteren Version. **Abhilfe:** Die eigene Start-Seite startet bei `!isSecureContext` mit `args: ['--audio-driver','Dummy']`. Die Klänge laufen über eine eigene kleine Web-Audio-Brücke (`AudioBufferSourceNode` braucht keinen Secure Context). |
| Andere Browser-Schnittstellen sind abgesichert: `getGamepads` (try/catch), Zwischenablage (try/catch), `vibrate` (typeof). Es gibt kein `crypto.subtle` und kein `randomUUID`, nur `getRandomValues`. | Ich habe keine weitere harte Abhängigkeit vom Secure Context gefunden. |
| Godot reagiert nicht auf `visibilitychange` der Seite (nur WebXR). | Das Neuverbinden nach Sperre oder Tab-Wechsel muss die Start-Seite selbst auslösen, über `JavaScriptBridge`. |
| Größen: `godot.wasm` 37,7 MB roh, **9,5 MB komprimiert**; `godot.js` 316 kB / 79 kB. | Ein Gast lädt beim ersten Mal etwa 10 MB plus das eigene `.pck` mit 2–5 MB. Im WLAN sind das Sekunden. 6 Gäste gleichzeitig über einen 2,4-GHz-Hotspot brauchen eher 15–40 s (Schätzung). |
| Android-Vorlage: `libgodot_android.so` für arm64 hat 69 MB roh und 23 MB komprimiert; armeabi-v7a kostet weitere ~25 MB. | Erwartete APK nur für arm64: **etwa 40–55 MB** einschließlich Web-Export. Mit armv7 für alte Urlaubshandys etwa 65–80 MB. Das ist viel kleiner als die rund 310 MB von Draw2Race. |
| Die Web-Vorlagen liegen in `.tools\export\templates\`. In `%APPDATA%\Godot\export_templates\4.6.1.stable` sind aber nur Android und Windows installiert. | `setup.ps1` muss die Dateien `web_nothreads_*.zip` mitkopieren. |
| `net_session.gd` (548 Zeilen) hat etwa 20 ENet-spezifische Stellen: Drossel, Statistik, `peer_disconnect_later`, Zeitgrenzen. | Der Umbau auf WebSocket ist ein Teilumbau, kein Austausch einer Klasse. Die eigene Ping-, Uhr- und Funkstille-Logik bleibt erhalten. |

**Weitere Abweichungen von den Berichten:**
- Ich empfehle **nicht** `WebSocketMultiplayerPeer`, sondern einfaches `WebSocketPeer` (`TCPServer` + `accept_stream`, auf dem Client `connect_to_url`) mit JSON-Textrahmen. Dann kann auch ein Nicht-Godot-Programm das Protokoll sprechen: ein Playwright-Testbot oder der HTML-Client aus Plan B.
- **Testfalle:** `http://localhost` und `127.0.0.1` gelten im Browser als Secure Context. Lokale Browsertests würden die iPhone-Situation also *nicht* nachstellen. Sie müssen die LAN-IP verwenden (Abschnitt 6).

---

## 1. Komponenten-Übersicht

```
┌──────────────────── Godot-4.6.1-Projekt „Mau-Mau Flip“ (eine Codebasis, Compatibility-Renderer) ────────────────────┐
│ core/      (reines GDScript, RefCounted, ohne Szene, headless testbar)                                               │
│   cards.gd        112 Karten; Paarung hell/dunkel pro Runde per Seed                                                 │
│   rule_config.gd  offizielle Regeln + Optionen (1.13) + Hausregeln + Voreinstellungen                                │
│   game_state.gd   Stapel, Hände, aktive Seite, Richtung, Wunschfarbe, Ansagen, Wertung                               │
│   rules.gd        apply(seat, intent) -> {ok|reason, events[]}  (deterministisch, Seed bleibt beim Host)             │
│   views.gd        view_for(seat), event_for(seat, ev)  ← einzige Stelle, die Verdecktes filtert                      │
│   bot.gd          einfache Heuristik (Tests, leere Plätze)                                                           │
│ session/                                                                                                             │
│   host_session.gd   besitzt GameState, Ereignislog, Plätze+Tokens; speichert nach jedem Ereignis (Fortsetzen)       │
│   local_seat.gd     Host-eigener Platz und Weitergeben-Modus (ohne Netz, aber auch über view_for)                    │
│   remote_seat.gd    Mitspieler: Snapshot + nummerierte Ereignisse über WebSocket                                     │
│   table_director.gd „Tischregie“: Ereignis-Warteschlange → Animationen; Aufholen bei Rückstand                       │
│ net/                                                                                                                 │
│   net_protocol.gd   JSON, Magie/Version, hello/welcome/reject, Absichten mit seq/ack                                 │
│   net_session.gd    aus Draw2Race: Anmeldung, Ablehnung mit Grund, Ping/Uhr/Funkstille – Transport: WebSocketPeer    │
│   ws_server.gd      TCPServer + WebSocketPeer.accept_stream (Hauptschleife)                                          │
│   http_server.gd    eigener Thread: / Landing · /play/<ver>/ Web-Export (.gz) · /apk · /v.json · TLS-Abweisung       │
│   net_discovery.gd, net_android.gd   UDP-Suche, WLAN-Bindung, Hotspot-Erkennung (nur App)                            │
│   invite.gd         Einladen-Bildschirm, QR (Kenyoni-Addon), Link/APK teilen, Spiel-WLAN                             │
│ platform/                                                                                                            │
│   platform.gd       Adapter mit Ersatz für Tests (Muster android_api aus Draw2Race)                                  │
│   web_bridge.gd     JavaScriptBridge: Token/Name aus localStorage, visibilitychange, Fern-Log, Sfx                   │
│   sfx.gd            Android/PC: AudioStreamPlayer-Pool · Web: window.mmfAudio.play(name, rate, gain)                 │
│ ui/   Tisch, Hand (Bogen/Lupe/Karussell), Sitzordnung, Lobby, Optionen, Effekte (3 Stufen), Übergabekarte            │
│ web/  shell.html (eigene Start-Seite), landing.html                                                                  │
│ android/build/src/main/java/com/godot/game/                                                                          │
│   Updater.java (Draw2Race) · NetHelper.java (Draw2Race) · ShareHelper.java (neu) · HotspotHelper.java (neu)          │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
 Exporte:  Android (alles) │ Web nothreads (nur Mitspieler, Host-Menü per Feature-Tag aus) │ Windows (Entwicklung, PC als Host)
```

```
 GitHub: ShakieVan/Mau-Mau-Flip (Releases) · ShakieVan/Mau-Mau-Flip-Beta (Pre-Releases)
        │ HTTPS, nur wenn Internet da ist
        ▼
 ┌─────────────── Host-Handy (Android-App, autoritativ, kennt alle Karten, zeigt nur die eigenen) ───────────────┐
 │  WS :8081  (alle Mitspieler)   HTTP :8080 (Landing, Web-Export, APK)   UDP 24681/24682 (Suche)               │
 └─────┬────────────────────────────────┬────────────────────────────────┬──────────────────────────────────────┘
       │ UDP-Suche + WS                 │ QR/Link → http → ws            │ Quick Share (ACTION_SEND) oder /apk
 Android-App-Gast                 Browser-Gast (iPhone Safari,     Android ohne App
 (gleiche App; ist sie älter:     Android Chrome, PC)              → installiert → wird App-Gast
  „Update vom Host“ über /apk)    = Godot-Web-Export vom Host
 Netz: gemeinsames WLAN │ System-Hotspot des Hosts │ „Spiel-WLAN“ (LocalOnlyHotspot, WLAN-QR)
```

### Kernentscheidungen

**Regelkern**
- Eine deterministische Zustandsmaschine mit `RuleConfig`. Sie läuft im Netz nur in der `HostSession`, im Weitergeben-Modus lokal.
- Mitspieler berechnen spielbare Karten nur zum Hervorheben, aus ihrer eigenen Sicht. Ob ein Zug gilt, entscheidet immer der Host.

**Verdeckte Information** (vollständig in `views.gd`)
- Die eigene Hand enthält nur die aktive Seite, mit Kennungen, die pro Runde zufällig vergeben werden.
- Gegnerhände kommen als **sortierte Menge der für mich sichtbaren Seite, ohne Kennungen**. So verraten weder die Sortierung noch stabile Kennungen über Flips hinweg Kartenpaare.
- Vom Nachziehstapel kommt nur die inaktive Seite der obersten Karte.
- Seed und Paarungstabelle verlassen den Host nie.
- Beim Anzweifeln bekommt nur der Herausforderer die Hand zu sehen.
- Weil der Browser-Client der vollständige Godot-Code ist, wäre jedes Datenleck sofort auslesbar. Ein automatischer Test prüft deshalb jede ausgehende Nachricht auf verbotene Daten (siehe 6).

**Protokoll** (JSON, Versionsfeld)
- Mitspieler → Host:
  - `hello{proto, app, kind:"app"|"web", token?, name}`
  - Absichten `play{seq, card, color?}`, `draw`, `keep`, `mau`, `catch`, `challenge`
  - `ready`, `ping`
- Host → Mitspieler:
  - `welcome{seat, token, sid}`, `lobby{rev, seats, rules, …}`
  - `snapshot{seq, view}`, `ev{seq, list}` (je Empfänger zugeschnitten)
  - `ack{seq, ok|reason}`, `reject{code, reason}`
- Für Wünsche gilt das `seq`/`ack`-Muster aus Draw2Race (kein Flackern).

**Transport**
- WebSocket über TCP für alle. Bei einem rundenbasierten Spiel ist das ausreichend und einfacher als ENet plus WebSocket parallel.
- Die eigenen Pings und die Funkstille-Erkennung aus `NetSession` bleiben, nur mit längeren Grenzen.

**Wiederverbindung** (Pflicht)
- Beim `welcome` vergibt der Host ein Token: `Crypto.generate_random_bytes`.
- Speicherort beim Mitspieler:
  - App: `user://`
  - Web: `localStorage`, in try/catch
- Nach dem Wiederbeitritt kommt ein vollständiger `snapshot` ohne Animationen.
- Der Host hält den Platz frei. Für einen getrennten Spieler am Zug wählt der Host: warten, überspringen oder Bot übernimmt.
- Der Host speichert seinen Zustand nach jedem Ereignis. Nach einem Absturz oder Prozessende stellt „Partie fortsetzen“ dieselbe `sid` und dieselben Tokens wieder her, und die Mitspieler verbinden sich selbst neu.

**Suche**
- App-Gäste finden den Host per UDP (`NetDiscovery` mit drei Wegen).
- Browser-Gäste kommen nur über QR-Code oder Link, mit Token im Pfad: `http://<ip>:8080/j/<token>`.
- Für App-Gäste bei gefiltertem Rundruf: Die Landing-Seite bietet unter Android „In der App öffnen“ an (Intent-Link `maumauflip://join?...`). Ein QR-Code reicht dann für alle.

**HTTP-Server** (GDScript, eigener Thread, nicht blockierend)
- `TCPServer` mit einer Schleife über alle Verbindungen und `put_partial_data`. So laden mehrere Gäste parallel.
- Vorkomprimierte `.gz`-Dateien mit `Content-Encoding: gzip`, `application/wasm` und `Cache-Control: immutable` unter einem Pfad mit Versionsnummer.
- `Range`-Unterstützung für die APK.
- Beginnt eine Anfrage mit dem Byte 0x16 (TLS-Versuch durch „HTTPS zuerst“ in Safari), wird sie sofort geschlossen. Dann fällt Safari schnell auf http zurück.
- Der WebSocket-Server läuft in der Hauptschleife. Hängt sie (Teilen-Menü, Berechtigungsdialog), sehen die Mitspieler „Host pausiert“. Die Zeitgrenzen sind entsprechend großzügig.

**Eigene Start-Seite `shell.html`**
- Lädt `godot.wasm` sofort im Hintergrund, während der Gast seinen Namen in ein normales HTML-`<input>` tippt. So wird die experimentelle Godot-Tastatur unter iOS umgangen.
- Der Knopf „Beitreten“ erledigt dreierlei: Er gibt Web Audio frei, startet den NoSleep-Trick und startet die Engine mit `--audio-driver Dummy`.
- Sie prüft, ob WebGL2 und WASM-SIMD vorhanden sind. Fehlen sie, kommt ein verständlicher Hinweis statt eines Absturzes.
- Sie leitet `window.onerror` und die Konsole über den WebSocket ins Host-Log.

**Weitergeben-Modus**
- `LocalSeat` wechselt den Platz hinter der Übergabekarte. Muster: `party_hud.gd` mit 350-ms-Tippsperre, dazu „zum Aufdecken halten“.
- Der Tisch dreht sich zum aktuellen Spieler.
- Der Sichtschutz zeigt keine Rückseitenfächer.

**Updater**
- `updater.gd` und `Updater.java` aus Draw2Race, mit den dort gelernten Korrekturen (siehe 3).
- Für Browser-Gäste braucht es keinen Updater, denn sie bekommen immer die Version des Hosts.

**APK offline**
- **„App senden“:** `ShareHelper.java` kopiert `sourceDir` nach `files/share/MauMauFlip-x.y.z.apk` und öffnet über den FileProvider das Teilen-Menü (`ACTION_SEND`, Quick Share).
- **Download über die Landing-Seite:** `/apk`, direkt aus `sourceDir`.
- **„Update vom Host“:** Die Lobby erkennt einen älteren App-Gast. Die App lädt dann `/apk`, prüft die SHA-256 aus `v.json` und anschließend `Updater.verify` (Paket, höherer versionCode, gleiche Signatur), dann installiert sie.
- **App-Gast neuer als der Host:** Die Lobby bietet „Im Browser mitspielen“ an. Das ist die Host-Version, also immer passend.

**Hotspot und QR**
- Der Bildschirm „Mitspieler einladen“ hat Kacheln: Gleiches WLAN/Hotspot (Link-QR), Spiel-WLAN (LocalOnlyHotspot), App senden, Link senden.
- Beim Spiel-WLAN zeigt **ein** großer QR-Code abwechselnd „① WLAN“ (`WIFI:T:WPA;S:…;P:…;;`) und „② Spiel öffnen“. Die Daten stehen jeweils auch im Klartext darunter.
- Die IP ermittelt `NetAndroid` (Hotspot- oder WLAN-Adressen). Ein bestimmtes Subnetz wird nie angenommen.

**Darstellung**
- Compatibility-Renderer auf allen Zielen, damit App und Web gleich aussehen.
- Tischregie, Federn, Hand-Stufen A/B/C, Joker-Strahlen nach Verfahren A (Kontur abtasten, keine SubViewports, wegen „WebGL context lost“ unter iOS) und drei Effektstufen, alles wie im Bericht hand-ux.
- Browser starten mit der Stufe „Reduziert“ und stufen bei Ruckeln selbst herunter.

**Sitzordnung**
- Teil des Lobby-Zustands. Der Host zieht die Avatare auf die Plätze.
- Jedes Gerät dreht die Ansicht mit `seat_pos(r, n)` und spiegelt sie nie. Dieser Code ist für App und Web derselbe.

**Hausregeln**
- `RuleConfig` mit Gruppen und Voreinstellungen (Offiziell, Klassisch 500, Familie, Mau-Mau-Tradition, Chaos, Schnell).
- Die Regeln kommen mit `lobby`. Jede Änderung setzt „Bereit“ zurück (Muster aus Draw2Race).
- „Reinwerfen“ ist im Weitergeben-Modus ausgegraut.

---

## 2. Anforderungen: Umsetzung und Bewertung

| Anforderung | Umsetzung | Wie gut? |
|---|---|---|
| Veröffentlichung auf GitHub (Release- und Beta-Repo) | `ShakieVan/Mau-Mau-Flip` und `ShakieVan/Mau-Mau-Flip-Beta`, Asset `MauMauFlip-X.Y.Z.apk`, Konventionen wie bei Draw2Race. Die Repos lege ich in M0 erst nach deinem OK an. | sehr gut, erprobt |
| Update-Funktion wie bei Draw2Race | Updater 1:1 übernommen, plus Knopf „im Browser herunterladen“, API-Prüfungen für Android 7–8.1 und Abbruch bei fehlendem Keystore | sehr gut |
| Host gibt die APK weiter (verbundene Geräte, Geräte in der Nähe) | Quick Share über das Teilen-Menü, `/apk` über QR/Landing-Seite, „Update vom Host“ für verbundene App-Gäste | gut. Offen bleibt das Verhalten von Play Protect offline und ab 2027 die Entwicklerverifizierung (siehe Risiken). Bluetooth taugt nicht. |
| Mitspielen per Browser (iPhone) | Godot-Web-Export vom Host über http plus ws, mit eigener Start-Seite | **voraussichtlich gut, nur auf dem Papier belegt.** Hängt an M1. Geräte ohne WASM-SIMD (älter als Safari 16.4, z. B. iPhone 7) bleiben draußen. |
| Link per QR und an Geräte in der Nähe | QR (Kenyoni) mit Token-Link. Link teilen über `ACTION_SEND text/plain`. AirDrop-Kopplung nur mit wenigen Android-Modellen, darum bleibt der QR-Code der Hauptweg. | gut |
| „Bessere Methode“ fürs iPhone | Gleicher Godot-Client statt eigener Web-App; ein QR-Code für alle; Android-Gäste können ebenfalls ohne Installation spielen (wichtig ab 2027). Native iOS-App, PWA und HTTPS scheiden aus. | Das ist der eigentliche Mehrwert dieses Wegs. |
| Weitergeben und Netzwerk | `LocalSeat` und `RemoteSeat` hängen am selben `view_for` | sehr gut |
| Hand sortierbar, „fancy“ scrollbar | Katalog aus hand-ux (Fischauge, Schwung, Einrasten, FLIP-Umsortierung) **einmal** gebaut, läuft in App und Web | App sehr gut; Web gleich, aber GDScript in WASM ist langsamer (am Gerät messen) |
| Host legt Sitzreihenfolge fest, jeder sieht aus seiner Blickrichtung | Tisch-Editor in der Lobby, Drehung je Gerät | sehr gut |
| Effekte nahe am Original und „überwältigend cool“ | ein Effektkatalog, drei Stufen, Joker-Strahlen ohne SubViewport | siehe nächste Tabelle |
| Optionale Hausregeln | `RuleConfig` mit Voreinstellungen; die Regeln laufen nur beim Host, die Mitspieler zeigen sie nur an | sehr gut |

**Effektqualität je Plattform**

| Effekt | Android-App | iPhone-Browser (Godot-Web) |
|---|---|---|
| Fächer, Lupe, Karussell, Federn, Sortieranimation | voll | gleicher Code; Bildrate am Gerät messen |
| Partikel (Ausspielen, Zieh 5, Konfetti) | Stufe Voll, ≤ 800 | Standard Reduziert ≤ 300, Voll wählbar |
| Joker-Strahlen aus der sichtbaren Kontur | voll | gleich (Kontur abtasten, ohne SubViewport) |
| Flip-Inszenierung mit Vollbild-Shader | 1,6 s voll | voll auf neueren iPhones, sonst 0,7 s; Bildschirm auslesen nur kurz |
| Richtungswechsel animiert, Richtungsring | voll | gleich |
| Ton | AudioStreamPlayer | eigene Web-Audio-Brücke. Der Stummschalter macht still; Option „Ton trotz Stummschalter“. Formate MP3/AAC/WAV, kein Ogg. |
| Haptik | ja, mit Stärke | iPhone nein (Safari kennt kein `vibrate`); Android-Chrome ohne Stärke |
| Holo-Joker mit Lagesensor | ja | nein (kein Secure Context) |
| Bildschirm wach halten | `screen_set_keep_on` | NoSleep-Trick, noch ungeprüft; Hinweis „Automatische Sperre: Nie“ |
| Vollbild, Ausrichtung | ja, hochkant | Safari-Leisten bleiben; im Querformat ein Hinweis „Bitte hochkant drehen“ |

Ehrliche Einordnung: Auf neueren iPhones (ab etwa iPhone 12, Schätzung) ist die Optik praktisch identisch. Auf älteren Modellen läuft „Reduziert“. Was fehlt, sind Haptik, Sensoren und echtes Vollbild. Bei Bildschirmauflösung (DPR 3) kosten große Shader viel Füllrate; das klärt der Test in M1.

---

## 3. Wiederverwendung aus Draw2Race

Pfade relativ zu `C:\Users\Shakie\Documents\Programmierung\Draw2Race`.

| Teil | Umfang | Übernahme |
|---|---|---|
| `game/scripts/updater.gd` (287 Z.), `android/.../Updater.java` (79 Z.), Tests in `game/tests/test_core.gd` Z. 177–205 | fast 1:1 | Repo- und Asset-Name, User-Agent und Texte ändern; Prüfungen für API 26/28 ergänzen (der `NoSuchMethodError` auf Android 7–8.1); Knopf für den Download im Browser |
| `android/.../NetHelper.java` (239 Z.), `game/scripts/net/net_android.gd` (305 Z.), FakeAndroid-Fälle aus `test_lobby.gd` | 1:1 | Namen von Multicast-Sperre und Paket ändern; den committeten Stand nach dem S24-Fix nehmen |
| `net_discovery.gd` (282 Z.) | 1:1 | Magie und Ports; die Antwort bekommt zusätzlich die HTTP-Adresse und die APK-SHA-256 |
| `net_log.gd`, `net_cli.gd`, `net_test_screen.gd` (614 Z.) | weitgehend | Diagnosebildschirm, dazu Anzeige verbundener Web-Gäste und HTTP-Zähler |
| `net_protocol.gd` (198 Z.) | teilweise | Ablehnungscodes, `check_hello`, Namen bereinigen, Adressrechnung bleiben; Kodierung wird JSON statt `var_to_bytes` |
| `net_session.gd` (548 Z.) | etwa 60 % | Anmeldung, Ablehnung, Ping/RTT/Uhr, Funkstille, `close_gracefully` als Ablauf; etwa 20 ENet-Stellen gegen WebSocketPeer tauschen |
| `net_lobby.gd` (974 Z.) | Muster, etwa 40 % | `seq`/`ack`, „Bereit“ zurücksetzen, `away`, `back`/`close`, Revanche-Reihenfolge, `_bind`/`_host_hotspot`/`refresh_status`, `overrides` für Tests; `join_block` wird zur Platzreservierung |
| `lobby_hud.gd` (845 Z.), `party_hud.gd` (362 Z.) | Muster | Aktualisierung an Ort und Stelle über Signaturen, Toast, Adressdialog oben, Übergabekarte mit Tippsperre |
| `player_colors.gd` | Algorithmus | OKLab- und Machado-Prüfung für die Kartenpaletten, **nicht** als Spielerfarben |
| `tools/setup.ps1`, `godot_run.ps1`, `net_test.ps1`, `lobby_cli.gd` | Gerüst | Web-Vorlagen mitkopieren; Mutex umbenennen; die Mehrprozess-Tests spielen Bot-Partien |
| `tools/build.ps1` | Gerüst | neue Reihenfolge: Import → Tests → Web-Export → gzip → `webdist/` → Android-Export → Windows. Ohne Keystore abbrechen, versionCode aus der Version berechnen, Draw2Race-spezifische Importanpassungen streichen |
| `game/android/build` (Gradle-Vorlage 4.6.1, `org.gradle.daemon=false`, Manifest-Berechtigungen), `.gitignore`-Regeln | 1:1 | dazu Intent-Filter `maumauflip://`, `CHANGE_WIFI_STATE`, `NEARBY_WIFI_DEVICES` (neverForLocation), `ACCESS_FINE_LOCATION` (maxSdk 32), `VIBRATE` |
| Doku-Aufbau (`AGENTS.md`, `docs/IMPLEMENTIERUNG.md`, Recherche mit Belegmarken) | 1:1 | – |

**Nicht übernehmen:** `net_race.gd`, `net_draw.gd` (nur die Idee „verdeckt abgeben, gemeinsam aufdecken“), `name_tags.gd`, die Daten aus `pass_party.gd`, alles aus 3D und Rennen, ENet-Kanäle und Schnappschüsse.

Einsparung durch die Übernahme: geschätzt 8–12 Personentage, vor allem bei Updater, Android-Netz und Testgerüst.

---

## 4. Aufwand und Meilensteine

Gerechnet sind Personentage (PT) für einen Hobbyentwickler mit Claude als Programmierer, einschließlich Gerätetests, ohne Grafikproduktion.

| M | Inhalt | PT |
|---|---|---|
| **M0 Fundament** | Projekt in `E:\Documents\Programmierung\Mau-Mau Flip` (Pfad mit Leerzeichen: den Gradle-Export sofort testen). Paketname festlegen (z. B. `de.maumauflip.game`). Release-Keystore erzeugen und doppelt sichern. `build.ps1` für Android, Web, Windows und Tests. Updater übernehmen. Beide Repos (nach deinem OK). Beta 0.1.0 mit Startbildschirm und **funktionierendem Update**, denn der Updater muss ab Version 1 stimmen. | 3 |
| **M1 iPhone-Test (Go/No-Go)** | Minimaler Tisch mit Fächer, einem Partikel-Effekt, Flip-Shader und Ton über die Brücke. Eigene Start-Seite mit Dummy-Audio und Namensfeld. HTTP-Server im Thread, gzip, TLS-Abweisung. WS-Echo. Messen: Ladezeit mit 1 und 4 Gästen, Startzeit, Bildrate beim Fächern, Speicher, Ton nach Tipp, Neuverbinden nach Sperre. Geräte: Playwright-WebKit über LAN-IP, Android-Chrome, BrowserStack-iPhone (iOS 17/18/26), ein iPhone von Freunden. | 4 |
| M2 Regelkern | Karten, Paarung, alle offiziellen Regeln samt Optionen aus 1.13, Anzweifeln, Mau-Ansage, Wertung, `view_for`, Ereignislog, Prüfsummen (1280/1480) | 6 |
| M3 Spielbar auf einem Gerät | Tisch in Grundform, Hand-Stufen A/B, Tischregie, Weitergeben mit Sichtschutz und Drehung, Bots | 7 |
| M4 Netz App ↔ App | WebSocket-Transport, Lobby, Sitzordnung-Editor, Tokens/Wiederverbindung, Partie fortsetzen, UDP-Suche, WLAN-Bindung | 7 |
| M5 Browser-Gäste im Spiel | Landing-Seite, QR, Einladen-Bildschirm (Link), iOS-Lebenszyklus (`visibilitychange` → Neuverbinden), NoSleep, vollständige Sfx-Brücke, Fern-Log | 5 |
| **= Erste Beta „spielbarer Kern“** | **ab hier mit iPhone-Freunden testen** | **≈ 32** |
| M6 Offline-Verteilung | ShareHelper (APK und Link), `/apk` mit Range, Update vom Host, Deep-Link `maumauflip://`, „Log teilen“ | 4 |
| M7 Hand-UX und Karten (Muss) | Karussell C, Schwung und Gummiband, Sortiermodi samt Umsortieren nach Flip, Kartenbaukasten mit MSDF, Paletten und Formsymbole, Grundeffekte aller Karten, Effektstufen | 16–20 |
| M8 Hausregeln | „Bis zum Letzten“, Stapeln, Bluff-Modi, Ansage-Kontrolle, Optionen-Bildschirm, Voreinstellungen | 4–5 |
| M9 Spiel-WLAN | HotspotHelper (LocalOnlyHotspot, Laufzeitberechtigung), WLAN-QR im Wechsel mit dem Link-QR, Tests auf S10, S21, S24 | 3–4 |
| M10 Effekte (Soll) | Joker-Strahlen, Flip-Inszenierung mit Tag/Nacht und Musik, Zieh 5, Spielautomat bei „Zieh bis Farbe“, Sieg, Klänge, automatische Rückstufung | 10–14 |
| M11 Härtung und 1.0.0 | Lange Partien, Störfälle, Play-Protect- und Quick-Share-Tests, Doku | 4–5 |
| **Summe** | | **≈ 70–90** |

**Zum Vergleich:** Ein eigener HTML-Client würde M1 und M5 kaum verbilligen, aber etwa 15–25 PT für eine zweite Darstellung kosten. Danach bräuchte jeder weitere Effekt 30–50 % Mehraufwand in M7 und M10. Der Godot-Weg kostet dafür etwa 5–7 PT Sonderarbeit (Start-Seite, Audio-Brücke, gzip-Server, Test) und trägt das Risiko aus M1.

---

## 5. Risiken

| Risiko | Wahrsch. / Folge | Gegenmaßnahme |
|---|---|---|
| **Godot-Web über http wird nicht unterstützt** (Godot lehnt es ab, Proposal #10076) | mittel / hoch | Eigene Start-Seite (Quelltext geprüft, siehe 0). Godot auf 4.6.x festhalten. Der Test aus M1 läuft als Regressionstest bei jedem Godot-Update. Plan B steht bereit (unten). |
| **Audio im unsicheren Kontext** (ungeschütztes `audioWorklet` in 4.6.1) | hoch, aber lösbar / mittel | `--audio-driver Dummy` nur bei `!isSecureContext`, Klänge über die eigene Web-Audio-Brücke. Musik nur einfach (Schleife) oder gar nicht im Web. |
| iPhone ohne Testgerät: unbekanntes Verhalten (Sperre, Speicher-Neuladen, Leisten, „WebGL context lost“) | hoch / mittel | Wiederverbindung mit Token. Kein SubViewport. Texturen sparsam (Kartenatlas statt 224 Einzelbilder). Fern-Log. BrowserStack und iPhones von Freunden ab der ersten Beta. |
| Ladezeit und Start auf älteren iPhones (9,5 MB WASM komprimiert) | mittel / mittel | WASM schon beim Namen-Tippen laden. Cache mit versionierten Pfaden. Gäste nacheinander einladen. Später optional eine eigene, schlankere Vorlage (ohne 3D, etwa 3–5 MB). Die braucht aber emsdk und SCons, also eine zusätzliche Werkzeugkette, und nur bei gemessenem Bedarf. |
| Zu alte iPhones (vor Safari 16.4, kein WASM-SIMD) | gering bis mittel / mittel | Die Start-Seite erkennt das und rät zum Weitergeben-Modus am Host-Handy. Ein HTML-Client könnte sie abdecken, dieser Weg nicht. |
| iOS verlässt ein WLAN ohne Internet nach dem Ruhezustand; Safari „HTTPS zuerst“; Chrome unter iOS fragt nach „lokalem Netzwerk“ | mittel / mittel | Hinweise auf dem Bildschirm (Bildschirm anlassen, Safari benutzen, „Kein Internet“ ist normal). TLS sofort abweisen. Wiederverbindung. |
| Hauptschleife des Hosts steht (Teilen-Menü, Dialoge, Bildschirm aus) | hoch / mittel | HTTP läuft im Thread. Großzügige Zeitgrenzen, Anzeige „Host pausiert“, `screen_set_keep_on`, Zustand nach jedem Ereignis speichern. Ein Vordergrunddienst (Java) erst, wenn Tests es zeigen. |
| Android-Funktionen aus Godot | gering / mittel | Erprobtes Muster: statisches Java plus `JavaClassWrapper`, der Zustand kommt als JSON. Neu sind Laufzeitberechtigungen über `OS.request_permission` und der Hotspot-Rückruf (Klasse, also Java Pflicht). Ab targetSdk 37 wird `ACCESS_LOCAL_NETWORK` Pflicht. |
| Android-Entwicklerverifizierung 2027 (Installation und Updates nur registrierter Apps) | sicher / hoch für den APK-Weg | Früh registrieren (Hobby-Konto bis 20 Geräte oder volles Konto). **Der Browser-Weg ist davon nicht betroffen und dient Android-Gästen als Ausweg.** |
| Eine Codebasis, zwei Laufzeitumgebungen (Safari-WebGL und Android-GLES), Verzweigungen nach Plattform | mittel / mittel | Alle Unterschiede in `platform/`, mit Ersatz für Tests. Feature-Tags statt verstreuter `OS.has_feature`-Abfragen. Kontrollbilder App gegen Web. |
| Leistung: GDScript in WASM ist langsamer; CPU-Partikel; DPR 3 | mittel / mittel | Browser starten mit „Reduziert“; Rückstufung unter 45 fps. Layout als reine Funktion ohne Rechenspitzen. Joker-Strahlen kosten etwa 200 Punkt-in-Polygon-Prüfungen pro Bild in C++, das ist unkritisch. |
| Datenleck, weil der Browser-Client der vollständige Code ist | gering / hoch | Nur `views.gd` filtert; ein automatischer Lecktest prüft jede ausgehende Nachricht. |
| Keystore geht verloren, oder Debug- und Release-Signatur werden vermischt | gering / sehr hoch | Release-Schlüssel ab M0, außerhalb von `.tools` doppelt gesichert; der Build bricht ohne Schlüssel ab. |
| Host-Handy wird warm und leert den Akku (Hotspot, Server, Effekte) | mittel / gering | Bildrate im Leerlauf senken; Hinweis auf ein Ladekabel. |

**Kritik an meiner eigenen Perspektive**
- Der ganze Browser-Weg ruht auf einer Konfiguration, die Godot nicht unterstützt. Belegt ist sie bisher nur durch das Lesen des Quelltexts, nicht durch einen Lauf auf dem iPhone.
- „Identische Effekte“ ist nur teilweise wahr. Haptik, Sensoren und Vollbild fehlen, und auf alten iPhones fallen die Effekte eine Stufe tiefer.
- Jeder Gast lädt beim ersten Mal etwa 12–15 MB statt unter 1 MB. Bei 6 Gästen über einen Hotspot ist das spürbar.
- Jede Godot-Version kann die Start-Seite oder die Audio-Umgehung brechen, denn die Engine wird ab dann aktiv gegen ihre eigene Empfehlung betrieben.

**Plan B (schon im Entwurf eingeplant):**
- Fällt M1 durch, bleibt Godot für App und Host. iPhones bekommen einen schlanken HTML/JS-Client, der dasselbe JSON-Protokoll spricht, mit „Lite“-Effekten. Mehraufwand etwa 15–25 PT.
- Alles Übrige (Regelkern, Server, Wiederverbindung, Tests) bleibt unverändert, weil das Protokoll von Anfang an kein Godot-Binärformat ist.
- **Gründe, auf Plan B umzuschwenken** (jedes einzelne genügt):
  - Kein sicherer Start auf iOS 17, 18 oder 26.
  - Neuladen oder „WebGL context lost“ in einer 30-minütigen Sitzung auf einem iPhone der 11er-Klasse.
  - Über 15 s bis zum Tisch für 4 gleichzeitige Gäste.
  - Unter 30 fps beim Wischen durch die Hand.

---

## 6. Teststrategie ohne iPhone und Mac

1. **Headless-Tests für Regeln und Sichten** (`tools/build.ps1 -Target Test`, Muster `extends SceneTree`):
   - Kartenzahlen und Punktsummen 1280/1480.
   - Jede Regeloption, Flip-Reihenfolge, Neumischen, Anzweifeln und „Zieh bis Farbe“ mit leerem Stapel.
   - Wiederholen aus Seed und Ereignislog.
   - **Lecktest:** Tausend zufällige Bot-Partien mit zufälliger `RuleConfig`. Jede Nachricht an Platz X wird auf fremde aktive Seiten, Kennungen fremder Karten, Seed und Paarungen durchsucht.
2. **Im selben Prozess:** Host plus 3 Mitspieler über WebSocket an 127.0.0.1, wie `test_lobby.gd`. Geprüft werden Beitritt, Ablehnungen, volles Spiel, Wiederverbindung mitten im Zug, Host-Neustart mit „Partie fortsetzen“ und kaputte oder zu große JSON-Nachrichten.
3. **Mehrere Prozesse** (`net_test.ps1`): Host und N headless Godot-Mitspieler spielen ganze Partien. Diese Mitspieler sind **derselbe Code wie im Web-Export**, die Protokoll- und Logikfehler fallen also schon ohne Browser auf. Die Prüfsummen der öffentlichen Daten müssen bei allen gleich sein.
4. **Browser-Ende-zu-Ende** (Playwright, neu unter `tools/web_e2e/`):
   - Der Windows-Build hostet und liefert den Web-Export aus, **erreichbar über die LAN-IP und nicht über localhost**. Der Test prüft ausdrücklich `isSecureContext === false`.
   - Clients: WebKit (Safari-Ersatz unter Windows, nur näherungsweise; ob WebGL2 dort geht, ist noch ungeprüft) und Chromium mit iPhone-Profil.
   - Ablauf: Laden, Namen eingeben, Beitreten, über einen `window.mmfTest`-Haken (nur in Debug-Builds) mitspielen.
   - Störfälle: `visibilitychange` und `pagehide` nachstellen, um das Neuverbinden zu prüfen; Netz drosseln (Chromium CDP).
   - Kontrollbilder: App gegen Web.
   - Weil das Protokoll JSON ist, können zusätzlich Bots als einfache Node- oder Playwright-Skripte mitspielen.
5. **Eigene Android-Geräte** (S10, S21, S24): Jedes Gerät als Host; Chrome auf Android als Browser-Gast. Hotspot ohne Internet, Gast mit mobilen Daten, Spiel-WLAN, Quick Share mit APK, Play-Protect-Dialog offline. Ein Nicht-Samsung-Gerät wäre wertvoll.
6. **Echte iPhones in der Cloud:** BrowserStack Live mit Local-Tunnel zum Windows-Host. `bs-local.com` ist kein localhost, also gilt auch dort kein Secure Context, wie im echten Spiel. Das Open-Source-Programm ist kostenlos, wenn das Repo öffentlich ist.
   - **Prüfliste:** Start auf mehreren iOS-Versionen, Ton nach Tipp, Stummschalter, Sperren und Entsperren, Drehen, Safari-Leisten, 30-Minuten-Sitzung, Rückfall von „HTTPS zuerst“.
7. **iPhones von Freunden** ab der ersten Beta. Sie brauchen keine Installation.
   - Fern-Log über WebSocket (`window.onerror`, Konsole, Speicher- und Bildratenwerte) ins Host-Log, das „Log teilen“ verschickt.
   - Optional Eruda als Konsole in Debug-Builds, oder inspect.dev unter Windows per USB.
8. **Regression bei jedem Godot-Update:** Der Test aus M1 und die Browser-Tests aus Stufe 4 laufen zuerst. Erst danach wird die Version gewechselt.

---

## 7. Offene Entscheidungen für dich

1. **Diesen Weg mit M1 als Go/No-Go angehen?** Die Alternative wäre, gleich mit dem HTML-Client zu beginnen.
2. **Paketname:** Vorschlag `de.maumauflip.game`. Er ist endgültig.
3. **ABIs:** nur arm64 (etwa 40–55 MB) oder zusätzlich armv7 für alte Urlaubshandys (etwa 65–80 MB)?
4. **Release-Builds mit eigenem Schlüssel und „Log teilen“** statt Debug-Builds mit `adb run-as`, wie bei Draw2Race? Ich empfehle die Release-Builds.
5. **Quellcode-Repo öffentlich?** Das wäre Voraussetzung für das kostenlose BrowserStack-Programm.
6. **Registrierung bei der Android-Entwicklerverifizierung:** Hobby-Konto bis 20 Geräte oder volles Konto? Das wird spätestens 2027 nötig.

Der Ordner `E:\Documents\Programmierung\Mau-Mau Flip` enthält bisher nur `.git` und eine noch nicht hinzugefügte `LICENSE`. Laut früherem Bericht gibt es daneben noch einen Ordner „Mau-Maul Flip“, vermutlich ein Tippfehler, der weg kann.