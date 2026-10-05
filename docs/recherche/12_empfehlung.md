# Empfehlung der Jury: Godot-zentriert (A) mit eingebautem Plan B (B) und gezielten Ideen aus C

## Architektur (Synthese)

**Grundlage**
- Ein Godot-4.6.1-Projekt mit Compatibility-Renderer. Godot bleibt auf 4.6.x festgehalten, bis die Regressionstests eine neue Version freigeben.
- Drei Exporte:
  - **Android:** Host, Mitspieler und Weitergeben-Modus. Die APK enthält den Web-Export.
  - **Web nothreads:** nur Mitspieler. Das Host-Menü ist per Feature-Tag aus.
  - **Windows:** Entwicklung und PC als Host.

**Regelkern (aus A, ergänzt aus B)**
- Deterministisches GDScript ohne Szene, headless testbar, mit `RuleConfig` und Voreinstellungen (Standard R24, Optionen aus Regelbericht 1.13).
- Vier Funktionen: `view_for(seat)`, `events_for(seat, ev)` und, neu aus B, **`hints_for(seat)`**. Diese liefert spielbare Karten, mögliche Aktionen, allgemeine Abfragen (Farbe, Spieler, Anzweifeln) und fertige Hinweistexte.
- Karten-Kennungen und die Paarung hell/dunkel werden pro Runde zufällig vergeben.
- Gegnerhände kommen als sortierte Menge ohne Kennungen. Der Seed verlässt den Host nie.
- Lecktest über jede ausgehende Nachricht.

**Transport**
- `TCPServer` mit `WebSocketPeer.accept_stream` und JSON-Text, für App- und Browser-Mitspieler gleich. ENet fällt weg.
- `set_no_delay(true)`.
- Alle Zahlen beim Lesen prüfen und umwandeln, denn Godot liefert sie aus JSON als Float (aus B).
- Größengrenzen: 8 KB für Client-Nachrichten, 64 KB für Host-Nachrichten.
- Höchstens 20 Nachrichten pro Sekunde je Client, Prüfung des `Origin`-Headers, Schlüssel im Pfad.
- Die Formate von `reject` und `hello` stehen ab der ersten verteilten Version fest. Protokoll-Beispieldateien (Golden Files) unter `shared/protocol/fixtures` gibt es ab dem ersten Tag (aus B).

**Ports (aus B)**
- HTTP 24690, WebSocket 24691, UDP 24692/24693.
- Damit liegen sie neben Draw2Race und nicht auf 8080/8081.

**HTTP-Server (GDScript, eigener Thread)**
- Einladungsseite mit Geräteweiche:
  - Android: „App installieren“ oder „Im Browser spielen“
  - iPhone: direkt „Im Browser spielen“
  - mit App: Intent-Link `maumauflip://`
- `/play/<version>/` mit vorkomprimierten `.gz`-Dateien und `application/wasm`.
- `/apk` mit Range-Unterstützung, aus der Kopie in `user://share/`. Dieselbe Kopie nutzt der FileProvider (aus B).
- HEAD-Anfragen. TLS-Versuche (erstes Byte 0x16) werden sofort geschlossen.

**Browser-Client = Godot-Web mit eigener `shell.html` (aus A)**
- Lädt `godot.wasm` schon, während der Gast seinen Namen in ein normales HTML-Feld tippt.
- Der Knopf „Beitreten“ gibt Web Audio frei, startet den NoSleep-Trick und startet die Engine. Ohne Secure Context geschieht das mit `--audio-driver Dummy`, die Klänge laufen dann über eine eigene Web-Audio-Brücke.
- Prüft vorab WebGL2 und WASM-SIMD und zeigt bei Fehlen einen verständlichen Hinweis.
- Fern-Log über den WebSocket ins Host-Log.
- Bei `visibilitychange`/`pageshow` verbindet der Client neu.
- Safari-Härtung aus C:
  - Bei `webglcontextlost`: Seite neu laden und per Token wieder einsteigen.
  - `touch-action:none`, `gesturestart` abfangen, keine Gesten in den äußersten 20 px, kein `pushState`.
  - Höhe über `dvh`/`visualViewport`.
  - Pixeldichte auf höchstens 2 begrenzen, sofern das in Godot-Web machbar ist (prüfen).
  - Start in der Effektstufe „Reduziert“.

**Wiederverbindung**
- Token: in Godot mit `Crypto.generate_random_bytes`, im Browser mit `getRandomValues`.
- Nach dem Wiederbeitritt kommt nur ein vollständiger Snapshot, ohne Nachspielen der Ereignisse (aus B).
- **Vierstelliger Platzcode als Notweg (aus B).** Er ist Pflicht, weil sich die Adresse mit jeder Hotspot-Sitzung ändert.
- Für einen getrennten Spieler am Zug wählt der Host: warten, aussetzen oder Bot übernimmt.
- Der Host speichert nach jedem Ereignis. Nach einem Absturz stellt „Partie fortsetzen“ das Spiel wieder her.

**Mischform (aus B):** Ein Gerät im Netz verwaltet mehrere Plätze mit Übergabekarte, z. B. für Kinder ohne Handy oder ein iPhone mit leerem Akku.

**Android**
- Updater 1:1 aus Draw2Race, mit diesen Korrekturen:
  - `SDK_INT`-Prüfungen und `catch (Throwable)`
  - Knopf „Im Browser herunterladen“
  - 403 als „GitHub-Limit erreicht“ melden
  - geladene APK nach erfolgreichem Update löschen
  - Zeitstempel erst nach Erfolg setzen
- `ShareHelper.java` (APK und Link über `ACTION_SEND`), `HotspotHelper.java` (LOHS), `NetHelper.java` im committeten Stand nach dem S24-Fix.
- Berechtigungen direkt im Manifest eintragen. Bildschirm wach halten.
- Einen Vordergrunddienst gibt es erst, wenn Gerätetests zeigen, dass er nötig ist.

**Release**
- Eigener Release-Keystore, dreifach gesichert, davon einmal offline. Release-Export mit „Log teilen“.
- versionCode = `X*1_000_000 + Y*1_000 + Z` (aus B).
- Asset `MauMauFlip-X.Y.Z.apk`.
- `build.ps1` bricht ab, wenn der Keystore fehlt.
- Neues Skript `tools/release.ps1` (aus C) für `gh release` in beiden Repos.
- `setup.ps1` kopiert die Web-Vorlagen mit.

**Tests**
1. Headless-Tests für Regeln und Lecks: 10 000 Bot-Partien, Kontrollsummen 1280/1480.
2. Host und Mitspieler im selben Prozess über WebSocket.
3. Mehrere Prozesse mit headless Godot-Mitspielern. Das ist derselbe Code wie im Web-Export.
4. Playwright über die **LAN-IP**, mit der Prüfung `isSecureContext === false` und einem Test-Haken.
5. **iOS-Simulator auf einem GitHub-macOS-Runner (aus C, korrigiert):** über die Netzwerk-IP des Runners, nie über `localhost`.
6. BrowserStack Live mit Local-Tunnel.
7. iPhones von Freunden mit Checkliste.
8. Vor jedem Godot-Update laufen M1-Test und Browser-Tests als Freigabe.

## Plan B, falls M1 durchfällt

- Alles bleibt, nur der Browser-Client wechselt zum TypeScript/PixiJS-Client aus B.
- Er spricht dasselbe JSON-Protokoll, nutzt die `hints` vom Host und gemeinsame Dateien (`layout.json`, `effects.json`, `palette.json`). Dazu kommen Vitest, Playwright und ein portables Node.
- Mehraufwand: etwa 15–25 PT.
- Alternativ ist an dieser Stelle der Wechsel zu C möglich. Das entscheidet der Nutzer, siehe unten.

## Reihenfolge der Meilensteine (PT = Personentage)

| M | Inhalt | PT |
|---|---|---|
| **M0a** | **Gerüst, nichts veröffentlichen.** Projekt in `E:\Documents\Programmierung\Mau-Mau Flip`; den Gradle-Export im Pfad mit Leerzeichen sofort testen. Paketname, Keystore, `build.ps1` mit Web-Export und gzip, `setup.ps1`. | 1–2 |
| **M1** | **iPhone-Test, Go/No-Go.** Details unten. | 4–5 |
| | **Entscheidung:** Godot-Web, Plan B oder C | |
| M0b | Updater und Release-Kette. Beide Repos erst nach OK des Nutzers. Beta 0.1.x; Update-Kette 0.1.1 → 0.1.2 auf S10, S21 und S24 prüfen. | 2 |
| M2 | Regelkern mit `view_for`, `events_for`, `hints_for`, Lecktest, Bots | 6–7 |
| M3 | Spielbar auf einem Gerät: Hand-Stufen A/B, Tischregie, Weitergeben mit Drehung und Sichtschutz | 7–9 |
| M4 | Netz App ↔ App: WebSocket, Lobby, Sitz-Editor, Token und Platzcode, Fortsetzen, UDP-Suche, WLAN-Bindung | 7–9 |
| M5 | Browser-Gäste im Spiel (mit Plan B: 12–18 PT) | 5 |
| | **Erste spielbare Beta, ab hier mit iPhone-Freunden testen** | **≈ 32–40** |
| M6 | Offline-Verteilung: App und Link senden, `/apk` mit Range, Update vom Host, Intent-Link | 4–5 |
| M7 | Hand-UX komplett (Karussell C, Schwung, Sortieren) und Kartenbaukasten | 16–20 |
| M8 | Hausregeln | 4–6 |
| M9 | Spiel-WLAN (LOHS) mit WLAN-QR | 3–4 |
| M10 | Effekte (Joker-Strahlen, Flip-Inszenierung, Zieh 5, „Zieh bis Farbe“, Sieg) | 10–14 |
| M11 | Härtung und Version 1.0.0 | 4–5 |
| | **Summe** | **≈ 72–95**, mit Plan B zusätzlich 15–25 |

### M1 im Detail

**Testaufbau**
- Minimaler Tisch: Fächer, ein Partikeleffekt, Flip-Shader, Ton über die Brücke.
- Der Android-Host liefert über http aus und stellt ein WebSocket-Echo bereit.
- Geräte: mindestens ein echtes iPhone (Freunde) **und** BrowserStack oder der iOS-Simulator.

**Abbruchkriterien** (jedes einzelne genügt für Plan B):
- kein sicherer Start auf zwei iOS-Versionen über `http://<LAN-IP>`
- Neuladen oder „WebGL context lost“ in einer 30-minütigen Sitzung auf einem iPhone der 11er-Klasse
- mehr als 15 s bis zum Tisch für 4 gleichzeitige Gäste, **ohne Cache**, über den S24-Hotspot ohne Internet
- unter 30 fps beim Wischen durch die Hand (Ziel: 45 fps)
- kein Ton nach dem Tippen auf „Beitreten“
- Wiederverbinden nach 30 s Sperre dauert länger als 3 s
- der Host liefert keine Dateien mehr, während das Teilen-Menü offen ist

## Offene Entscheidungen für den Nutzer

1. **Grundsatz:**
   - Empfehlung: Bei Godot bleiben und zuerst M1 fahren.
   - Alternative: Gleich auf C wechseln, wenn die gleiche Optik auf dem iPhone ab Tag 1 Pflicht ist und der Abschied von der Draw2Race-Basis in Kauf genommen wird.
2. **Was passiert, wenn M1 durchfällt?**
   - Vorschlag: Plan B (Godot-App bleibt, iPhones bekommen die „Lite“-Optik).
   - Alternative: Wechsel zu C.
3. **iPhone für M1:** Welche Freunde mit iPhone können in den ersten zwei Wochen testen? Ohne ein echtes Gerät ist M1 nicht aussagekräftig.
4. **Quellcode öffentlich?** Das ist die Voraussetzung für das kostenlose BrowserStack-Open-Source-Programm und kostenlose macOS-Runner.
5. **Namen, endgültig:**
   - Paketname, z. B. `de.maumauflip.game`
   - Repos `ShakieVan/Mau-Mau-Flip` und `ShakieVan/Mau-Mau-Flip-Beta`
   - Asset `MauMauFlip-X.Y.Z.apk`
6. **Builds:** Release-Builds mit eigenem Schlüssel und „Log teilen“ (Empfehlung) oder Debug-Builds mit `adb run-as` wie bei Draw2Race?
7. **ABIs:**
   - nur arm64: etwa 40–55 MB
   - zusätzlich armv7 für alte Urlaubshandys: etwa 65–80 MB
8. **Android-Entwicklerverifizierung 2027:** Limited-Konto (bis 20 Geräte, kostenlos) oder volles Konto (25 USD)?
9. **Bildschirmausrichtung:** hochkant (Vorschlag aus dem Bericht hand-ux), anders als bei Draw2Race (quer).
10. **Ordner `Mau-Maul Flip` löschen?** Er existiert und ist vermutlich ein Tippfehler.
11. **Regelfragen** aus dem Regelbericht (Anzweifeln, eigene Rückseiten, Standard-Voreinstellung) spätestens vor M2 klären.