# Mitspielen ohne App (iPhone) bei „Mau-Mau Flip“: Recherche, Stand 04.10.2026

Kennzeichnung: **[belegt]** = Quelle sagt das ausdrücklich · **[Bericht]** = Erfahrungsbericht oder Issue · **[ungeprüft]** / **[Gerätetest]** = muss sich am echten Gerät zeigen · **[Schätzung]**

## 0. Kurzfassung und Empfehlung

**Empfehlung: Option B.** Wir bauen einen eigenen, schlanken Browser-Client (TypeScript mit DOM/CSS und Canvas, PixiJS nur falls nötig). Die Dateien stecken in der APK. Der Godot-Host liefert sie über **http://** aus, und der Client spricht über **ws://** mit dem Host. Die gesamte Spiellogik bleibt beim Host, der allein entscheidet. Der Web-Client zeigt nur an und schickt Spielzüge.

**Warum nicht der Godot-Web-Export (A)?**
- **Start bricht ab:** Godots Web-Startcode prüft auch bei Single-Thread-Builds immer auf „Secure Context“. Ohne HTTPS startet die Standard-Seite das Spiel gar nicht [3][4].
- **Keine Änderung geplant:** Die Godot-Maintainer wollen das nicht ändern und raten zu (selbstsigniertem) HTTPS [5].
- **Kein Ton:** Godots Web-Audio nutzt AudioWorklet, und das gibt es nur im Secure Context [7]. Wer die Prüfung herauspatcht, bekommt laut Bericht ein Spiel ohne Ton [5][6].
- **HTTPS hilft nicht:** Mit selbstsigniertem Zertifikat scheitert iOS-Safari an **wss://**. Safari übernimmt die Zertifikats-Ausnahme der Seite nicht für WebSockets [30]. Das wurde noch 2025 in einer iOS-26-Beta gemeldet [27].

**Warum B funktioniert:** Plain HTTP mit ws:// geht in Safari ohne Berechtigungsdialog [23][24][29]. Bedingung: Man verzichtet auf die APIs, die nur im Secure Context laufen (Abschnitt 1).

**Rückfall:** Godot-Web-Export mit eigener HTML-Shell ohne die Secure-Context-Prüfung, über HTTP, ohne Godot-Ton. Nur als Notlösung und vorher als 1-Tages-Test (Abschnitt 5).

## 1. Was iPhone-Safari auf http://192.168.x.x kann und nicht kann

**Zugriff auf private IP-Adressen**
- Safari erreicht lokale IP-Adressen ohne Dialog [Bericht 24]. iOS „Local Network Privacy“ gilt für Apps. Eine Web-View in einer App zählt als App (Apple, Jan. 2026) [23].
- Chrome, Firefox und Edge auf iOS sind Apps. Sie zeigen den iOS-Dialog „lokales Netzwerk“, der erlaubt werden muss [23].
- Folge: In der Anleitung „bitte in Safari öffnen“ schreiben. Ist ein anderer Browser Standard, öffnet die Kamera den QR-Link dort [ungeprüft].

**Local Network Access (LNA)**
- Chrome sperrt seit Version 142 Anfragen von öffentlichen Seiten an lokale Adressen bzw. fragt nach. Lokal zu lokal bleibt ohne Dialog [25].
- WebKit baut LNA gerade ebenfalls ein, auch nur für öffentlich zu lokal (PR vom 23.09.2026) [26].
- Folge: Seite und WebSocket kommen vom selben Host, das ist unkritisch [belegt für Chrome, für Safari Gerätetest].

**„HTTPS zuerst“**
- Safari ab 18.2 versucht auf iOS immer zuerst HTTPS und fällt erst bei einem Fehler auf HTTP zurück [21]. Das gilt für angeklickte Links, nicht für eingetippte Adressen [22].
- Die optionale Einstellung „Warnung bei nicht sicherer Verbindung“ zeigt dann einen Dialog [21].
- Folge: Ein QR-Link könnte erst HTTPS probieren. Der Host-Server sollte einen TLS-Verbindungsversuch (erstes Byte 0x16) sofort abweisen, damit der Rückfall auf HTTP schnell geht [Gerätetest].

**WebSocket ws:// von einer http-Seite**
- Erlaubt. Blockiert wird nur ws:// von einer https-Seite (Mixed Content) [29].
- In der iOS-26-Beta 3 war ws:// im LAN wackelig, in Beta 5 behoben [27].
- iPadOS 26.2: In einer Home-Bildschirm-Web-App (über Chrome installiert) wird ws:// nach etwa 1 s getrennt. Im normalen Browser läuft es stabil. Apple untersucht das unter FB21416603 (Jan. 2026) [28].

**wss:// mit selbstsigniertem Zertifikat**
- iOS-Safari unterstützt das nicht, auch nicht nach „Vertrauen“ [30]. Noch 2025 wurde ein Zertifikatsfehler bei `wss://192.168…` gemeldet [27].
- Folge: Kein HTTPS-Weg.

**Ohne Secure Context fehlen** [31]
- Service Worker
- Screen Wake Lock
- Async Clipboard
- Web Share (navigator.share) [33]
- Notifications und Push
- Web Locks, Gamepad, DeviceOrientation, Storage API
- **Web Crypto: crypto.subtle und crypto.randomUUID** [32]
- AudioWorklet [7]

**Verfügbar bleiben**
- crypto.getRandomValues [32]
- localStorage, sessionStorage, IndexedDB
- WebSocket, WebGL2 (seit Safari 15 [59]), Web Audio ohne Worklet, WebAssembly

**Folgen für den Code**
- Sitzungs-Token mit getRandomValues erzeugen.
- Keine Bibliotheken einbauen, die randomUUID oder subtle brauchen.
- Kein Teilen-Knopf über navigator.share.

**Vollbild und Ausrichtung**
- Das iPhone unterstützt die Fullscreen-API für normale Elemente nicht (nur iPad oder Video). Apple sagt dazu sinngemäß „no supported way“ [35].
- Ausrichtung sperren ist nicht verbreitet und geht typischerweise nur im Vollbild [36]. Also muss das Layout hochkant und quer funktionieren.
- Seit iOS 26 öffnet jede zum Home-Bildschirm hinzugefügte Seite als Web-App ohne Browserleisten [20][42].
- Aber: Der Android-Hotspot wählt seit Android 11 bei jedem Einschalten ein zufälliges Netz [43], also eine neue Adresse. Dazu kommt der iPadOS-Fehler aus [28]. Darum nur als optionaler Tipp.

**Bildschirmsperre und Hintergrund**
- Wake Lock gibt es seit iOS 16.4, in Home-Bildschirm-Apps ab 18.4 [34]. Ohne HTTPS ist es aber nicht verfügbar [31].
- Beim Sperren oder App-Wechsel wird der WebSocket sofort geschlossen [37]. Das Anhalten im Hintergrund ist erwartetes iOS-Verhalten [38]. Web Audio wird beim Sperren sofort pausiert [Bericht 39].
- **Pflicht daher:**
  - automatisch neu verbinden bei `visibilitychange` bzw. `pageshow`
  - Token in localStorage, mit try/catch abgesichert
  - der Host hält den Platz frei
- Gegen die automatische Sperre: der NoSleep-Trick (stumm laufendes Endlosvideo nach einem Tipp) [40], Wirkung unter iOS 26/27 [Gerätetest]. Zusätzlich in der Lobby der Hinweis „Automatische Sperre: Nie“.

**Arbeitsspeicher**
- iOS lädt eine Seite bei zu viel Speicher ohne Fehlermeldung neu.
- Berichtet werden etwa 300 MB [12], auf schwachen Geräten weniger [39].

**Ton**
- Ton gibt es erst nach einem Tipp des Nutzers.
- Web Audio läuft standardmäßig als „ambient“ und ist damit beim Stummschalter still.
- `navigator.audioSession.type='playback'` (Safari ab 16.4, experimentell) spielt trotz Stummschalter, pausiert aber die Musik anderer Apps [41].
- Folge: Standard „ambient“ lassen und eine Option „Ton trotz Stummschalter“ anbieten.

**Texteingabe**
- Im HTML-Client reicht ein normales `<input>`.
- Im Godot-Web-Export geht das nur mit dem experimentellen virtuellen Keyboard, das bekannte Macken hat [18].

## 2. Die Optionen im Einzelnen

### (A) Godot-Web-Export vom Host-Handy

**Was dafür spricht**
- Single-Thread ist seit 4.3 Standard und braucht weder SharedArrayBuffer noch COOP/COEP-Header. Die früheren Apple-Probleme sind damit weitgehend weg [1][2].
- Godot 4.5 und neuer nutzt WASM-SIMD, die offiziellen Templates verlangen Safari ab 16.4 [13][14].
- Größter Vorteil: keine doppelte Darstellungslogik.

**Was dagegen spricht**
- **Secure Context:** Die Prüfung steht in `features.js` (master), unabhängig von Threads [3]. Die Standard-Shell startet ohne sie nicht [4].
- **Haltung der Maintainer:** Proposal #10076 ist seit 06/2024 offen. Calinou schreibt dort, Browserhersteller schalten neue Funktionen nur im Secure Context frei, und empfiehlt mkcert bzw. selbstsignierte Zertifikate [5].
- **Ton:** Nach dem Entfernen der Prüfung lief der Test nur ohne Ton [5][6].
- **Stabilität auf iOS:**
  - Ein Audio-Speicherleck führte zu Abstürzen, behoben in 4.5 [8][9].
  - Neuer Audio-Absturz mit 4.5.1 auf iOS 26.3 (Feb. 2026, noch offen). Umgehung: Wiedergabeart „Stream“ statt „Sample“ [10].
  - SubViewportContainer führt auf iOS zu „WebGL context lost“, noch offen [11].
  - Die Speichergrenze von etwa 300 MB [12].
- **Größe:**
  - wasm roh etwa 33 MB (4.3) [16]. Ein Projekt von 2026 hat 39,5 MB, gzip etwa 10 MB [17].
  - Der Lade-Test kommt mit Brotli und wasm-opt auf etwa 6,3 MB (4.6.2) [15].
  - Mit selbst gebauten, abgespeckten Templates sind etwa 2,4 MB (Brotli) möglich [16].
  - Über Hotspot-WLAN dauert die Übertragung wenige Sekunden [Schätzung]. Teurer ist das Kompilieren und Starten auf alten iPhones. Safari 26 startet große WASM-Module dank eines neuen Interpreters schneller [20].
- **Vorkomprimiert ausliefern** geht mit einem eigenen GDScript-Server: `.wasm.gz` mit `Content-Encoding: gzip` und `Content-Type: application/wasm` [2]. Brotli bieten Browser über plain HTTP praktisch nicht an (Chrome nur über HTTPS) [60]. Also gzip nehmen.

**Urteil:** Nicht als Hauptweg.

### (B) Eigener schlanker Web-Client (empfohlen)

**Aufbau**
- Statische Dateien in der APK, realistisch unter 2 MB [Schätzung]. Kein WASM, kaum Speicherbedarf, sofortiger Start.
- PixiJS optional, laut älterem Vergleich etwa 125 kB gzip [58]. CSS-3D-Flip und Canvas-Partikel reichen für eine „Lite“-Fassung der Effekte, etwa die Joker-Strahlen.
- Host-Seite: Godot `TCPServer` plus `WebSocketPeer.accept_stream()` [56].
- Für die statischen Dateien:
  - ein kleiner GDScript-Server, z. B. nach dem Muster von godottpd [57]
  - oder ein Java-Helfer wie der NetHelper von Draw2Race
  - am einfachsten zwei Ports: einer für HTTP, einer für WebSocket.
- Browser können kein ENet bzw. UDP, nur HTTP, WebSocket und WebRTC [2]. Der Host braucht also so oder so WebSocket.

**Vorschlag zur Vereinfachung:** WebSocket für **alle** Clients, auch die App-Clients. Bei einem rundenbasierten Kartenspiel ist die TCP-Latenz egal [56]. Die UDP-Suche aus Draw2Race bleibt für die Apps.

**Nachteil:** eine zweite Darstellungsschicht.

**So bleibt der Aufwand klein**
- Der Host erzeugt die gefilterte Sicht pro Spieler einheitlich für Godot- und Web-Clients. Dazu gehört bei Flip auch die jeweils andere Kartenseite der Gegnerkarten.
- Ein versioniertes JSON-Protokoll.
- Kartengrafik aus einer Quelle (SVG, daraus ein PNG/WebP-Atlas für beide Clients).

**Bonus:** Auch Android-Mitspieler, die keine APK installieren können oder wollen, und PC-Browser können mitspielen.

### (C) Alles in Web-Technik, Android-App als Hülle

- TWA (Trusted Web Activity) scheidet aus. Sie braucht einen HTTPS-Ursprung und „Digital Asset Links“ [46].
- WebView oder Capacitor: Man bräuchte einen eigenen HTTP- und WebSocket-Server in Kotlin oder Java. Es gibt kein gepflegtes Server-Plugin; capacitor-websockets läuft nur unter iOS und ist nicht auf npm [47].
- Die Godot-Basis von Draw2Race ginge verloren: Updater, Netzcode, Build-Skript, Know-how.
- Die iPhones hätten trotzdem dieselben HTTP-Einschränkungen.

**Urteil:** Nicht empfohlen.

### (D) Sonstiges

- **PWA bzw. Offline:** Service Worker nur im Secure Context [31]. Also kein Offline-Cache.
- **HTTPS im LAN:**
  - Selbstsigniertes Zertifikat: Warnseite und das wss-Problem [30].
  - Ein Root-Zertifikat-Profil auf jedem Gast-iPhone installieren: unzumutbar.
  - Eine echte Domain mit Zertifikat braucht DNS, also Internet.
- **Native iOS-App:**
  - Der Godot-iOS-Export braucht macOS und Xcode [48].
  - TestFlight braucht das Apple Developer Program für 99 USD im Jahr; externe Builds gehen durch Apples Beta-Prüfung [49].
  - App Clips brauchen eine App im App Store.
  - EU-Alternativ-Marktplätze wie AltStore PAL brauchen ebenfalls Developer-Program und Notarisierung durch Apple, nur in EU, Japan und Brasilien [50].
  - Ohne Mac und iPhone unrealistisch.
- **„Geräte in der Nähe“ für iPhones:**
  - Quick Share und AirDrop arbeiten seit 11/2025 zusammen, zuerst auf dem Pixel 10, 2026 ausgeweitet (u. a. Pixel 9/8a, Galaxy S26, OnePlus 15) [45].
  - Das iPhone muss „Jeder für 10 Minuten“ einstellen [45].
  - Ob auch Links übertragen werden, ist ungeprüft.
  - Der QR-Code bleibt der Hauptweg.

## 3. Empfohlener Ablauf für iPhone-Gäste

1. Der Host zeigt **QR 1 „WLAN beitreten“** (`WIFI:T:WPA;S:…;P:…;;`). Die iPhone-Kamera kann damit seit iOS 11 direkt beitreten [44].
   - Das geht nur, wenn das Spiel die Zugangsdaten kennt, also beim LocalOnlyHotspot (Draw2Race-Meilenstein M8).
   - Sonst verweist das Spiel auf den QR-Code in den Hotspot-Einstellungen von Android [Bericht 44].
2. **QR 2 „Im Browser mitspielen“** mit `http://<host-ip>:<port>/`. Er wird pro Sitzung neu erzeugt, weil sich das Netz ändert [43].
3. Die Seite lädt, der Gast gibt seinen Namen ein, der Host weist den Platz zu. Das Token wird in localStorage gespeichert.
4. Bei Sperre oder Verbindungsabbruch:
   - Der Client verbindet sich automatisch neu.
   - Der Host zeigt „Spieler X getrennt“ und wartet.
   - Optional als Hausregel: nach einer Zeitgrenze automatisch aussetzen.
5. **Notweg für Gäste, deren Token verloren ist** (z. B. privater Tab): „Ich bin wieder da: Platz 3“, der Host bestätigt.

**Weitere Punkte für den Host**
- gzip-Dateien vorab erzeugen.
- Korrekte MIME-Typen setzen.
- Den Origin-Header des WebSockets prüfen.
- Fehler aus dem Browser (`window.onerror`) per WebSocket ins Host-Log schicken, analog zu net_log in Draw2Race.

## 4. Risiken und Gegenmaßnahmen

| Risiko | Gegenmaßnahme |
|---|---|
| iOS-Updates ändern das Verhalten (ws-Aussetzer in einer iOS-26-Beta [27], iPadOS-26.2-Web-App-Fehler [28], WebKit-LNA in Arbeit [26]) | robustes Neuverbinden; iPhone-Freunde testen die Beta-Kanal-Versionen |
| Automatische Sperre und Hintergrund trennen die Verbindung [37][38] | Neuverbinden mit Token, NoSleep-Trick [40], Hinweis in der Lobby |
| Doppelte Darstellung läuft auseinander | Host entscheidet allein, gemeinsame Grafiken, automatische Protokolltests |
| Verzögerung durch „HTTPS zuerst“ [21] | TLS-Versuch sofort abweisen; Port in der URL |
| Drittbrowser auf iOS zeigen den Dialog „lokales Netzwerk“ [23] | Hinweistext „Safari verwenden / erlauben“ |
| Stummschalter macht Ton aus [41] | Option „Ton trotz Stummschalter“; Signal „Du bist dran“ auch optisch |
| Speicher bzw. alte iPhones | schlanker Client; keine großen Texturen |

## 5. Rückfall-Option

1. **Godot-Web-Export als Notfall-Client über HTTP:**
   - eigene HTML-Shell (`html/custom_html_shell` [2]) ohne den Secure-Context-Abbruch
   - keine SubViewports [11]
   - Speicher deutlich unter 300 MB [12]
   - Ton weglassen oder über `JavaScriptBridge` mit eigenem Web-Audio ohne Worklet
   - vorher 1 Tag Test mit Playwright-WebKit und einem echten iPhone
   - Risiko: Jede neue Godot-Version kann den Patch kaputt machen [5].
2. **Letzter Ausweg:** iPhone-Spieler spielen im „Weitergeben“-Modus an einem Android-Gerät mit.

## 6. Testen ohne iPhone und Mac

**Stufe 1: Desktop**
- Chrome und Firefox im Responsive-Modus.
- Playwright-WebKit unter Windows (`npx playwright wk <url>`) [52]:
  - kommt aus dem aktuellen WebKit-Hauptzweig, oft vor Safari [51]
  - der Funktionsumfang hängt aber von der Plattform ab, z. B. die Video-Codecs [51]
  - auf Nicht-Apple-Plattformen sind u. a. WebRTC und OffscreenCanvas abgeschaltet [51b]
  - iPhone-Geräteprofile emulieren nur Bildgröße, User-Agent und Touch. Sperrbildschirm, Speichergrenze, Audio-Session und Safari-Leisten bildet das nicht ab [Schätzung].
- Automatische Ende-zu-Ende-Tests: ein headless Godot-Host (Muster wie `net_cli.gd` und `lobby_cli.gd` in Draw2Race) plus mehrere Playwright-WebKit-Clients.

**Stufe 2: GNOME Web (Epiphany)**
- Über WSL2, ebenfalls WebKitGTK, also ähnlich aussagekräftig [52].

**Stufe 3: echte iPhones in der Cloud**
- BrowserStack Live mit BrowserStack-Local-Tunnel; private IP oder bs-local.com funktionieren [53].
- Das Open-Source-Programm von BrowserStack ist kostenlos, setzt aber offenen Quellcode voraus [53].
- TestMu AI (früher LambdaTest), kostenloser Plan: 5 Sitzungen à 2 Minuten pro Monat [54], also nur für kurze Stichproben.
- Der Host läuft dafür als Godot-Desktop-Build am PC.

**Stufe 4: iPhones von Freunden**
- Checkliste abarbeiten (siehe 7).
- Debuggen ohne Mac:
  - inspect.dev unter Windows mit USB [55]
  - ios-webkit-debug-proxy [55]
  - Eruda als Konsole direkt in der Seite (Debug-Build) [55]
  - eigenes Fern-Log über den WebSocket
- iPhone-Tester brauchen nur den Browser, also keine Installation aus dem Beta-Repo.

## 7. Offen, nur am Gerät klärbar

- Wie schnell fällt Safari von HTTPS auf HTTP zurück, wenn der Link aus dem QR-Code kommt?
- Wirkt der NoSleep-Trick unter iOS 26/27?
- Ist ws:// im Android-Hotspot stabil, auch wenn der Hotspot kein Internet hat?
- Schickt Safari über HTTP `Accept-Encoding: gzip`?
- Läuft die Home-Bildschirm-Web-App über http mit ws://?
- Überträgt Quick Share/AirDrop auch Links?
- Wie verhält sich ein iPhone mit Chrome als Standardbrowser beim QR-Code?

## Quellen

1. https://godotengine.org/article/progress-report-web-export-in-4-3/
2. https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html
3. https://github.com/godotengine/godot/blob/master/platform/web/js/engine/features.js
4. https://github.com/godotengine/godot/blob/master/misc/dist/html/full-size.html
5. https://github.com/godotengine/godot-proposals/issues/10076
6. https://github.com/godotengine/godot-proposals/discussions/10075
7. https://developer.mozilla.org/en-US/docs/Web/API/AudioWorklet
8. https://github.com/godotengine/godot/issues/107390
9. https://github.com/godotengine/godot/pull/107948
10. https://github.com/godotengine/godot/issues/116750
11. https://github.com/godotengine/godot/issues/100272
12. https://forum.godotengine.org/t/web-export-to-ios-suddenly-crashing-after-working-for-ages/120627/5
13. https://godotengine.org/releases/4.5/
14. https://godotengine.org/article/upcoming-serious-web-performance-boost/
15. https://github.com/JohannesDeml/Godot-Web-LoadingTest
16. https://amann.dev/blog/2025/godot_web_size/
17. https://github.com/eddy121384-ui/Pieceful/issues/56
18. https://github.com/godotengine/godot/issues/106539 · https://github.com/godotengine/godot/issues/76215
20. https://webkit.org/blog/17333/webkit-features-in-safari-26-0/
21. https://webkit.org/blog/16301/webkit-features-in-safari-18-2/
22. https://lapcatsoftware.com/articles/2024/12/1.html
23. https://developer.apple.com/forums/thread/811690
24. https://developer.apple.com/forums/thread/788044
25. https://developer.chrome.com/blog/local-network-access
26. https://github.com/WebKit/WebKit/pull/74003
27. https://developer.apple.com/forums/thread/792842
28. https://developer.apple.com/forums/thread/811063
29. https://discussions.apple.com/thread/256075428
30. https://cockpit-project.org/running/safari
31. https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts/features_restricted_to_secure_contexts
32. https://developer.mozilla.org/en-US/docs/Web/API/Crypto
33. https://developer.mozilla.org/en-US/docs/Web/API/Web_Share_API
34. https://webkit.org/blog/16574/webkit-features-in-safari-18-4/
35. https://developer.apple.com/forums/thread/770080
36. https://developer.mozilla.org/en-US/docs/Web/API/ScreenOrientation/lock
37. https://bugs.webkit.org/show_bug.cgi?id=247943
38. https://developer.apple.com/forums/thread/716118
39. https://github.com/Nehanth/pooled/issues/207
40. https://github.com/richtr/NoSleep.js/
41. https://developer.mozilla.org/en-US/docs/Web/API/AudioSession/type · https://nattog.dev/blog/web-audio-ios-unmute
42. https://www.idownloadblog.com/2025/06/17/apple-ios-26-safari-web-apps-home-screen-bookmarks/
43. https://github.com/Mygod/VPNHotspot/issues/193
44. https://scanapp.org/blog/2026/06/01/how-to-connect-to-wifi-by-scanning-a-qr-code.html · https://www.samsung.com/au/support/mobile-devices/use-qr-code-for-mobile-hotspot/
45. https://www.macrumors.com/2026/02/11/airdrop-quick-share-interoperability-more-phones/ · https://support.google.com/pixelphone/answer/9286773?hl=en
46. https://developer.android.com/develop/ui/views/layout/webapps/trusted-web-activities
47. https://github.com/pauldev20/capacitor-websockets
48. https://docs.godotengine.org/en/4.5/tutorials/export/exporting_for_ios.html
49. https://developer.apple.com/programs/
50. https://developer.altstore.io/
51. https://playwright.dev/docs/browsers · 51b: https://github.com/microsoft/playwright/issues/31017
52. https://schepp.dev/posts/running-webkit-on-windows/
53. https://www.browserstack.com/open-source · https://www.browserstack.com/guide/access-local-host-on-mobile
54. https://www.testmuai.com/pricing/
55. https://inspect.dev/guides/debug-safari-ios · https://github.com/google/ios-webkit-debug-proxy · https://soto92.github.io/portfolio/publication/debug-ios/
56. https://docs.godotengine.org/en/stable/tutorials/networking/websocket.html · https://docs.godotengine.org/en/stable/classes/class_websocketpeer.html
57. https://github.com/bit-garden/godottpd
58. https://dev.to/ritza/phaser-vs-pixijs-for-making-2d-games-2j8c · https://pixijs.com/blog/pixi-v8-launches
59. https://webkit.org/blog/11989/new-webkit-features-in-safari-15/
60. https://en.wikipedia.org/wiki/Brotli
- Draw2Race-Kontext (nur gelesen): C:\Users\Shakie\Documents\Programmierung\Draw2Race\docs\MULTIPLAYER_RECHERCHE.md · C:\Users\Shakie\Documents\Programmierung\Draw2Race\game\scripts\net\net_session.gd