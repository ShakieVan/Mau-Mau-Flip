# Gegenprüfung der kritischen Annahmen (04.10.2026)

Ein skeptischer Prüfer hat versucht, die Annahmen zu widerlegen, von denen die Empfehlung in `12_empfehlung.md` abhängt. Grundlage waren Quelltext (Godot 4.6.1, WebKit, AOSP), offizielle Dokumentation und Issue-Tracker.

## 1. Der Godot-4.6.1-Web-Export (nothreads) startet auf iOS-Safari über http://<LAN-IP> mit eigener Startseite und --audio-driver Dummy vollständig. Außer dem AudioWorklet in GodotAudio.init hängt nichts am Secure Context.

**Urteil: unklar**

Ich habe den Quelltext von 4.6.1-stable selbst gelesen und die Lesart bestätigt.

**Was der Quelltext zeigt**
- features.js: getMissingFeatures() meldet „Secure Context“ als fehlend. engine.js ruft die Funktion aber weder in init() noch in startGame() oder start() auf, sondern exportiert sie nur. Eine eigene Startseite umgeht die Prüfung also.
- library_godot_audio.js: GodotAudio.init ruft ctx.audioWorklet.addModule(...) ohne Schutzprüfung auf.
- OS_Web registriert die Treiber „AudioWorklet“ und „ScriptProcessor“. Beide laufen über AudioDriverWeb::init → godot_audio_init → GodotAudio.init. Ohne Secure Context würde damit jeder Web-Audiotreiber werfen. Nur der Dummy-Treiber vermeidet diesen Weg.
- Die übrigen Secure-Context-APIs sind abgesichert:
  - Zwischenablage: Prüfung auf navigator.clipboard.
  - Gamepads: getGamepads steht in try/catch.
  - PWA: Prüfung 'serviceWorker' in navigator.
  - getUserMedia und WebMIDI: jeweils Existenzprüfung.

**Was dagegen spricht oder offen bleibt**
- Ich habe keinen einzigen Gerätebericht gefunden, dass Godot 4.x über http auf iOS läuft.
- godot-proposals #10076 (offen seit 06/2024) berichtet nur von Firefox: Start ohne Ton, nachdem die Prüfung entfernt wurde.
- Laut Godot-Doku braucht der Web-Export HTTPS (außer localhost). Außerdem hat Safari „mehrere Probleme mit WebGL 2.0“.
- Die Emscripten-Laufzeit (godot.js) habe ich nicht vollständig auf weitere Secure-Context-Abhängigkeiten geprüft.

Der Quelltext stützt die Behauptung, ein Gerätebeweis fehlt.

**Konsequenz:**

Die Grundsatzentscheidung darf erst nach M1 auf einem echten iPhone fallen. Plan B/C nicht verwerfen.

Für M1:
- Die Startseite ersetzt getMissingFeatures durch eine eigene Prüfung nur auf WebGL2 und WebAssembly.
- Fehler auf der Seite selbst anzeigen (window.onerror, unhandledrejection). Der Web-Inspector von Safari braucht einen Mac.
- Testen mit einem minimalen Projekt und mit dem echten Projekt.
- Im Web-Build keine Zwischenablage-, Gamepad- oder Mikrofonfunktionen verwenden.

**Quellen:**
- https://github.com/godotengine/godot/blob/4.6.1-stable/platform/web/js/engine/features.js
- https://github.com/godotengine/godot/blob/4.6.1-stable/platform/web/js/engine/engine.js
- https://github.com/godotengine/godot/blob/4.6.1-stable/platform/web/js/libs/library_godot_audio.js
- https://github.com/godotengine/godot/blob/4.6.1-stable/platform/web/os_web.cpp
- https://github.com/godotengine/godot/blob/4.6.1-stable/platform/web/audio_driver_web.cpp
- https://github.com/godotengine/godot/blob/4.6.1-stable/platform/web/js/libs/library_godot_display.js
- https://github.com/godotengine/godot/blob/4.6.1-stable/platform/web/js/libs/library_godot_input.js
- https://github.com/godotengine/godot/blob/4.6.1-stable/platform/web/js/libs/library_godot_os.js
- https://github.com/godotengine/godot-proposals/issues/10076
- https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html

## 2. Mit dem Dummy-Audiotreiber ruft Godot-Web weder GodotAudio.init noch die Sample-Wiedergabe auf. Eine eigene Web-Audio-Brücke über JavaScriptBridge (AudioBufferSourceNode, kein Worklet) spielt die Klänge auf iOS ohne Secure Context nach dem ersten Tippen ab.

**Urteil: teilweise**

**Teil 1 ist durch den Quelltext bestätigt**
- AudioDriverWeb::init ist der einzige Aufrufer von godot_audio_init und damit von GodotAudio.init.
- In der Basisklasse AudioDriver sind register_sample, stop_sample_playback usw. leer. start_sample_playback gibt nur eine Warnung aus. Mit Dummy wird also kein JavaScript der Sample-Wiedergabe aufgerufen.
- Haken: AudioServer::start_sample_playback hängt jede Wiedergabe an sample_playback_list an. Der Dummy-Treiber meldet nie „fertig“, die Liste wächst also. AudioStreamPlayer gehört deshalb nicht in den Web-Build.
- Im nothreads-Build ist Thread nur ein Platzhalter. Der Dummy-Treiber mischt also gar nichts.

**Teil 2 ist plausibel, aber nicht am Gerät belegt**
Nur audioWorklet ist laut Spezifikation an den Secure Context gebunden, AudioContext und AudioBufferSourceNode nicht. Es gibt aber Bedingungen:
- (a) Das Freischalten (ctx.resume() bzw. ein stummer Puffer) muss nach meiner Ableitung synchron im DOM-Ereignis der Startseite passieren (pointerup/touchend). GDScript-_input läuft erst im nächsten Frame, also außerhalb der Nutzergeste. Das habe ich nicht am Gerät geprüft.
- (b) Web Audio folgt auf iOS dem Stummschalter. Abhilfe ist navigator.audioSession.type = 'playback' (Safari 16.4+/17). Die Spezifikation verlangt dafür keinen Secure Context, WebKits IDL habe ich nicht gesehen.
- (c) Safari kann Ogg erst ab iOS/Safari 18.4. AAC/MP3/WAV sind sicher.
- (d) Langzeitstabilität:
  - Godot #107390: WebKit gibt AudioWorklet-Prozessoren nicht frei, der Speicher explodiert und die Seite lädt neu. Behoben durch PR #107948 in 4.5.
  - Godot #116750 (offen seit 25.02.2026): iPhone 12 mit iOS 26.3 stürzt im Sample-Modus nach 10–30 Minuten ab, im Stream-Modus nicht. Die Ursache ist unklar.
  - Eine Brücke ohne Worklets umgeht die bekannte Ursache. Dauertests mit vielen kurzen Quellknoten fehlen aber.

**Konsequenz:**

Die Ton-Brücke ist als Sonderweg tragfähig, wenn sie so gebaut wird:
- Freischalten per JavaScript-Listener in der Startseite, nicht aus GDScript.
- Option navigator.audioSession.type = 'playback' bewusst entscheiden (Stummschalter ignorieren oder respektieren).
- Assets als AAC/MP3.
- Puffer einmal dekodieren und wiederverwenden, Quellknoten nach onended trennen.
- Im Web-Build kein AudioStreamPlayer.

In M1 gehört ein 30-Minuten-Dauertest mit hoher Effektdichte dazu.

**Quellen:**
- https://github.com/godotengine/godot/blob/4.6.1-stable/servers/audio/audio_server.h
- https://github.com/godotengine/godot/blob/4.6.1-stable/servers/audio/audio_server.cpp
- https://github.com/godotengine/godot/blob/4.6.1-stable/servers/audio/audio_driver_dummy.cpp
- https://github.com/godotengine/godot/blob/4.6.1-stable/platform/web/audio_driver_web.cpp
- https://github.com/godotengine/godot/issues/107390
- https://github.com/godotengine/godot/pull/107948
- https://github.com/godotengine/godot/issues/116750
- https://w3c.github.io/audio-session/
- https://huddee.com/blog/apple-quietly-fixed-web-audio-bug
- https://caniuse.com/ogg-vorbis

## 3. Ein iPhone der 11er-Klasse hält eine 30-minütige Godot-Web-Sitzung durch (godot.wasm 37,7 MB roh / 9,5 MB komprimiert, Compatibility-Renderer, kein SubViewport): kein Neuladen wegen Speichermangel, kein „WebGL context lost“, beim Wischen mindestens 30, Ziel 45 fps.

**Urteil: unklar**

Für iPhone 11 mit Godot 4.6 habe ich keine Messung gefunden. Die Dateigrößen habe ich nicht nachgemessen.

Bekannte Fehlerbilder sprechen für ein reales Risiko, das sich aber teilweise vermeiden lässt:
- #107390: Speicherleck durch WebKit-Worklets, führte zum Neuladen. Behoben in 4.5 und mit Dummy ohnehin umgangen.
- #116750: Absturz im Sample-Modus auf iOS 26.3 nach 10–30 Minuten, offen. Mit Dummy umgangen.
- #100272: SubViewportContainer führt auf iOS 17/18 in allen Browsern zu „WebGL context lost“, offen. Laut Plan wird kein SubViewport verwendet.
- Godot-Forum 08/2025 (Einzelbericht): iOS lädt die Seite neu, wenn der Laufzeitspeicher über etwa 300 MB steigt. Ein Testprojekt lief dort mit etwa 20 fps.
- Godot-Forum 09/2024: WebGL-Kontextverlust auf iOS 18, auf iOS 17 erst nach längerer Spielzeit.
- Auf webglcontextlost reagiert Godot 4.6.1 nur mit alert('WebGL context lost, please reload the page'). Es gibt keine Wiederherstellung.
- Laut Godot-Doku ist Web auf Mobilgeräten deutlich langsamer als nativ, nothreads zusätzlich langsamer.

Ob 30 bzw. 45 fps beim Wischen erreicht werden, ist damit weder bestätigt noch widerlegt.

**Konsequenz:**

M1 muss auf einem iPhone der 11er-Klasse messen:
- 30 Minuten Spielbetrieb.
- fps beim Wischen durch die Hand.
- Neuladen- und Kontextverlust-Ereignisse.

Die Messung und die Neustart-/Wiedereinstiegslogik bauen wir selbst ein. Der Kontextverlust muss als Wiedereinstieg mit Zustandsabgleich behandelt werden.

Für das Spiel gilt:
- Texturbudget klein halten, Karten in Atlanten, keine SubViewports.
- Effekte als Shader statt zusätzlicher Render-Targets.

Vorher festlegen, ab welchem Messwert der PixiJS-Client (Plan B/C) gewählt wird.

**Quellen:**
- https://github.com/godotengine/godot/issues/100272
- https://github.com/godotengine/godot/issues/107390
- https://github.com/godotengine/godot/issues/116750
- https://forum.godotengine.org/t/webgl-context-loss-and-app-crash-in-godot-4-3-exported-web-on-ios-browsers/81024
- https://forum.godotengine.org/t/web-export-to-ios-suddenly-crashing-after-working-for-ages/120627/5
- https://github.com/godotengine/godot/blob/4.6.1-stable/platform/web/js/libs/library_godot_display.js
- https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html

## 4. Android-Hotspot und LocalOnlyHotspot vergeben seit Android 11 bei jedem Start ein zufälliges Subnetz. Damit ändert sich die Origin je Sitzung, Cache, localStorage-Token und gespeicherte Namen gelten nicht über Sitzungen hinweg. Trotzdem erreichen 4–6 Gäste den Tisch über 2,4-GHz-Hotspot ohne Cache in höchstens 15 s.

**Urteil: teilweise**

**Die Kernaussage stimmt nur für Android 11.** Das zeigt der AOSP-Quelltext:
- Android 11 (android-11.0.0_r1): PrivateAddressCoordinator wählt bei jedem Start zufällig ein Netz in 192.168.0.0/16, ohne Zwischenspeicher.
- Ab Android 12 (android-12.0.0_r1): Es gibt mCachedAddresses. IpServer.configureIPv4 ruft requestIpv4Address(useLastAddress = true) auf. Die letzte Adresse je Schnittstellentyp wird wiederverwendet, solange sie nicht mit einem Upstream-Netz kollidiert.
- Aktueller main-Zweig: Laut Kommentar in requestStickyDownstreamAddress versucht Android zuerst die zuletzt verwendete Adresse für das Paar (Schnittstellentyp, Scope).
- Der Zwischenspeicher liegt nur im Arbeitsspeicher. Neu gewürfelt wird nach einem Neustart oder bei einem Konflikt.
- Ab Android 13 kommen 172.16/12 und 10/8 hinzu. Ab 25Q2 liegt der Startbereich zu 93,7 % in 10.0.0.0/8.
- Seit Android 14 haben normaler Hotspot (Scope GLOBAL) und LocalOnlyHotspot (Scope LOCAL) getrennte Schlüssel.
- Der Draw2Race-Gerätetest (S21, Android 15) ergab 172.17.251.0/24. Das passt zum AOSP-Verhalten. Abweichungen einzelner Hersteller habe ich nicht geprüft.

Draw2Race/docs/MULTIPLAYER_RECHERCHE.md (Zeile 101) übernimmt die überholte Aussage.

**Was trotzdem stimmt:** HTTP-Cache und localStorage hängen an der Origin (Host und Port). Die Origin wechselt aber nicht je Sitzung, sondern bei:
- Neustart des Handys oder einem Adresskonflikt,
- Wechsel zwischen Hotspot, LocalOnlyHotspot und Heim-WLAN,
- einem anderen Port.

**15 s sind nicht belegt.** Überschlag:
- 6 × 15 MB = 720 Mbit. Bei etwa 22 Mbit/s (Erfahrungswert für 2,4-GHz-Hotspots, schwache Quelle) sind das rund 33 s.
- 4 × 12 MB sind rund 17 s.
- Dazu kommen Wasm-Kompilierung und Start auf dem iPhone.
- Ob Browser Brotli über http anbieten, habe ich nicht geprüft. Vorkomprimiertes gzip ist sicher.

**Konsequenz:**

Den Platzcode-/Adress-Notweg trotzdem einbauen: Neustart, Konflikt und Netzwechsel ändern die Adresse weiterhin.

„Jede Sitzung kalt“ ist aber zu pessimistisch:
- Festen Port verwenden.
- Dateinamen mit Hash und Cache-Control immutable ausliefern.
- Token und Namen mit Rückfall (Namensabfrage) speichern.

Dann wirkt der Cache innerhalb eines Urlaubs oft.

Die Ladezeit in M1 mit 4–6 echten Geräten auf 2,4 GHz messen. Gegenmittel: 5 GHz bevorzugen, Datenmenge senken (gzip, Template schlanker), Gäste gestaffelt beitreten lassen.

Draw2Race-Doku korrigieren.

**Quellen:**
- https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/tags/android-11.0.0_r1/Tethering/src/com/android/networkstack/tethering/PrivateAddressCoordinator.java
- https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/tags/android-12.0.0_r1/Tethering/src/com/android/networkstack/tethering/PrivateAddressCoordinator.java
- https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/tags/android-12.0.0_r1/Tethering/src/android/net/ip/IpServer.java
- https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/heads/main/staticlibs/device/com/android/net/module/util/PrivateAddressCoordinator.java
- https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/heads/main/Tethering/src/android/net/ip/IpServer.java
- C:\Users\Shakie\Documents\Programmierung\Draw2Race\docs\IMPLEMENTIERUNG.md
- C:\Users\Shakie\Documents\Programmierung\Draw2Race\docs\MULTIPLAYER_RECHERCHE.md
- https://lifetips.alibaba.com/tech-efficiency/how-to-speed-up-your-android-hotspot-connection

## 5. iOS-Safari lädt eine http-Seite vom Host-Handy per QR-Link. Der Rückfall von „HTTPS zuerst“ geht schnell, wenn der Host TLS-Versuche (Byte 0x16) sofort schließt. ws:// zum selben Host funktioniert ohne Dialog, auch im Hotspot ohne Internet und nach Bildschirmsperre mit Wiederverbinden.

**Urteil: teilweise**

**Durch Quelltext und offizielle Doku gestützt**
- Safari 18.2+ versucht bei http-Links zuerst HTTPS (WebKit-Blog). Eingetippte URLs werden nicht hochgestuft (lapcatsoftware). Ob ein QR-Aufruf aus der Kamera als Link zählt, ist offen.
- WebKit-Quelltext (CachedResourceLoader.cpp, shouldPerformHTTPSUpgrade): Hochgestuft werden nur Hauptframe-Navigationen. ws://, Wasm und pck sind nicht betroffen.
- NetworkResourceLoader.cpp: Der optimistische HTTPS-Versuch hat eine Zeitgrenze von 3 s bzw. dem Mittel der bisherigen HTTPS-Verbindungszeiten.
- ResourceErrorCocoa.mm: Rückfall auf HTTP gibt es unter anderem bei TimedOut, CannotConnectToHost, NetworkConnectionLost und SecureConnectionFailed. Sofortiges Schließen bei 0x16 (oder ein RST auf :443 bei implizitem Port 80) löst also den schnellen Rückfall aus statt der 3-s-Wartezeit.
- Apple TN3179: Verkehr aus WKWebView, SFSafariViewController und Safari braucht keine Freigabe „Lokales Netzwerk“. Es gibt also keinen iOS-Berechtigungsdialog, auch nicht in WKWebView-basierten Drittbrowsern.

**Einschränkungen**
- Die optionale Einstellung „Warnung bei nicht sicherer Verbindung“ (Safari 18.2+) zeigt vor dem Rückfall eine Warnseite. Für diese Nutzer gibt es also doch einen Dialog. Der zugehörige Fehler, bei dem die Warnung localhost blockierte (WebKit-Bug 284559), ist seit 06/2026 behoben.
- Hotspot ohne Internet: Dazu habe ich nichts gefunden.
- Bildschirmsperre: Safari hält JavaScript im Hintergrund vollständig an. WebSockets können ohne close-Ereignis „hängen“ (WebKit-Bug 247943 betraf close bei Netzverlust, behoben in 17.3). Wiederverbinden klappt nur, wenn die Seite bei visibilitychange/pageshow aktiv neu verbindet. Bei Speicherdruck verwirft iOS die Seite, dann startet Godot komplett neu.

**Konsequenz:**

Der Browser-Weg ist grundsätzlich gedeckt.

Pflichten für den Host-Server:
- TLS-ClientHello (0x16) erkennen und sofort schließen.
- QR-Link mit explizitem Port.
- Wiederverbinden per visibilitychange/pageshow, Sitzungstoken und vollständigem Zustandsabgleich vom Host. Auch der komplette Seiten-Neustart muss als Wiedereinstieg funktionieren.

In M1 testen:
- Kamera-QR gegen eingetippte URL.
- Mit eingeschalteter Warn-Einstellung.
- Hotspot ohne Internet, mit mobilen Daten an und aus.
- Sperre länger als 1 Minute.

**Quellen:**
- https://webkit.org/blog/16301/webkit-features-in-safari-18-2/
- https://lapcatsoftware.com/articles/2024/12/1.html
- https://github.com/WebKit/WebKit/blob/main/Source/WebCore/loader/cache/CachedResourceLoader.cpp
- https://github.com/WebKit/WebKit/blob/main/Source/WebKit/NetworkProcess/NetworkResourceLoader.cpp
- https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/network/cocoa/ResourceErrorCocoa.mm
- https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- https://bugs.webkit.org/show_bug.cgi?id=284559
- https://bugs.webkit.org/show_bug.cgi?id=247943

## 6. Ein GDScript-TCPServer in einem eigenen Thread liefert Web-Dateien und die APK weiter aus, während die Godot-Activity pausiert (Teilen-Menü, Berechtigungsdialog). Android friert den Prozess dabei nicht ein und beendet ihn nicht. Der WebSocket in der Hauptschleife übersteht solche Pausen mit großzügigen Zeitgrenzen.

**Urteil: teilweise**

**Godot 4.6.1 auf Android (Quelltext)**
- Godot.onPause → GodotGLRenderView.onActivityPaused löst nur focusout und NOTIFICATION_APPLICATION_PAUSED aus.
- Der GL-Thread, der die Hauptschleife (GodotLib.step) antreibt, wird erst in onStop angehalten (pauseGLThread).
- Bei durchsichtigen Überlagerungen wie dem Berechtigungsdialog (und vermutlich dem Teilen-Menü) läuft also sogar die Hauptschleife weiter. Die Annahme „Activity pausiert, nur der Thread läuft“ trifft nicht zu.

**Kritisch ist onStop:** Vollbild-Einstellungen (z. B. „Apps installieren“), App-Wechsel, Bildschirm aus. Dann steht die Hauptschleife samt WebSocket-Abfrage. Ein eigener Thread läuft nur weiter, solange der Prozess nicht eingefroren ist:
- Android 14+: Prozesse im Cached-Zustand werden 10 s danach eingefroren, alle Threads stehen still.
- Sind alle Prozesse der App eingefroren, beendet das System ihre aktiven TCP-Sockets (AOSP-Doku, Android-14-Verhaltensänderungen).
- Android 15: Netzwerkanfragen außerhalb eines gültigen Prozess-Lebenszyklus scheitern (UnknownHostException/IOException).

Wann ein gerade verlassener Vordergrundprozess als „cached“ gilt und was Hersteller zusätzlich einfrieren, habe ich nicht gemessen.

Für sichtbar pausierte Zustände ist „friert nicht ein“ plausibel. Für gestoppte Zustände hält die Behauptung nicht.

**Konsequenz:**

Ein GDScript-Thread allein reicht für die Offline-Verteilung nicht. Nötig sind:
- Bildschirm an lassen (keep_screen_on) während Lobby und Partie.
- Ein kleiner Vordergrunddienst für die Dauer von Verteilung und Partie. Er hält den Prozess aus dem Cached-Zustand. Der Server selbst muss dafür nicht in Java laufen, der GDScript-Thread läuft dann weiter.
- Host-Netzcode nicht nur in _process abfragen, oder großzügige Zeitgrenzen plus Wiederverbinden.

Gerätetest: Teilen-Menü, Quick Share, Seite „Apps installieren“, Bildschirm aus, App-Wechsel über 10 s (Android 14/15/16).

Cs Begründung für den Vordergrunddienst ist damit im Kern berechtigt.

**Quellen:**
- https://github.com/godotengine/godot/blob/4.6.1-stable/platform/android/java/lib/src/main/java/org/godotengine/godot/Godot.kt
- https://github.com/godotengine/godot/blob/4.6.1-stable/platform/android/java/lib/src/main/java/org/godotengine/godot/GodotGLRenderView.java
- https://github.com/godotengine/godot/blob/4.6.1-stable/platform/android/java/lib/src/main/java/org/godotengine/godot/gl/GodotRenderer.java
- https://github.com/godotengine/godot/blob/4.6.1-stable/platform/android/java_godot_lib_jni.cpp
- https://source.android.com/docs/core/perf/cached-apps-freezer
- https://developer.android.com/about/versions/14/behavior-changes-all
- https://developer.android.com/about/versions/15/behavior-changes-all

## 7. Die eigene APK (Kopie von sourceDir nach user://share) lässt sich offline per Quick Share oder über /apk weitergeben und beim Empfänger installieren, auch wenn Play Protect ohne Netz eingreift. Updater.verify nimmt sie an, spätere GitHub-Updates funktionieren. Die Entwicklerverifizierung (2027 auch in Deutschland) blockiert das nur bei nicht registrierten Apps.

**Urteil: teilweise**

**Weitergabe**
- Quick Share überträgt beliebige Dateien, auch APKs, und funktioniert ohne Internet (Google-Hilfe, Sekundärquellen).
- Der Empfänger braucht „Unbekannte Apps installieren“ für die Dateien-App bzw. den Browser.
- Play Protect hat einen Offline-Scan gegen bekannte Schadsoftware. Für unbekannte Apps empfiehlt es einen Online-Scan. Wie das ohne Netz genau abläuft, ist nicht dokumentiert.
- Dass base.apk bei einer Einzel-APK-Installation die vollständige APK ist, habe ich nicht am Gerät geprüft.

**Updater.verify (Draw2Race Updater.java)**
- Bei der Erstinstallation ist verify gar nicht beteiligt, das macht der System-Installer.
- Bei einem Update vom Host akzeptiert verify nur: gleiches Paket, versionCode strikt größer als installiert, versionName gleich der übergebenen Version, identische Signaturen.
- Spätere GitHub-Updates funktionieren nur, wenn alle Builds denselben Schlüssel haben.
- Draw2Race baut Releases mit --export-debug und einem Projekt-Debugschlüssel. Fehlt .tools/draw2race-debug.keystore, fällt build.ps1 ohne Meldung auf Godots Standard-Debugschlüssel zurück. Danach kommt „Signatur passt nicht“ bzw. der Installer verweigert das Update.

**Entwicklerverifizierung**
- Ab 30.09.2026 in Brasilien, Indonesien, Singapur und Thailand. „Global“ ab 2027, für Deutschland gibt es kein eigenes Datum.
- Registriert werden Paketname und SHA-256 des Signaturzertifikats, mit Eigentumsnachweis über eine signierte APK mit adi-registration.properties.
- Volles Konto mit Ausweisprüfung.
- Das kostenlose Konto „Limited distribution“ erlaubt nur 20 Geräte. Jedes Gerät muss vorher einzeln autorisiert werden (QR und Code am Gerät, Eintrag in der Console). Für spontane Urlaubsgäste ist das ungeeignet.
- Nicht registrierte Apps lassen sich weiter per ADB oder über den „advanced flow“ installieren (Entwicklermodus, Neustart, 24 h Wartezeit, einmalig).
- Offline: Im SDK steht DEVELOPER_VERIFICATION_FAILED_REASON_NETWORK_UNAVAILABLE (Android Authority, 09/2025). Damit könnte die Installation ohne Netz auch bei registrierten Apps scheitern. Eine offizielle Klarstellung habe ich nicht gefunden.

„Blockiert nur nicht registrierte Apps“ ist daher unvollständig.

**Konsequenz:**

Vor dem ersten öffentlichen Release:
- Einen dauerhaften Release-Schlüssel festlegen und sichern.
- Mit Release-Export bauen und den stillen Rückfall auf einen fremden Schlüssel im Build-Skript verbieten.

Die Host-Weitergabe als Update weiter über verify prüfen. Gäste mit gleicher oder neuerer Version sauber abweisen.

Registrierung (volles Konto) bis 2027 einplanen. Die Offline-Installation registrierter Apps als offenes Risiko beobachten.

Den Browser-Weg auch für Android-Gäste als Ausweg behalten.

Gerätetest: Quick Share und /apk ganz ohne Netz, danach ein GitHub-Update auf dem Gastgerät.

**Quellen:**
- C:\Users\Shakie\Documents\Programmierung\Draw2Race\game\android\build\src\main\java\com\godot\game\Updater.java
- C:\Users\Shakie\Documents\Programmierung\Draw2Race\game\scripts\updater.gd
- C:\Users\Shakie\Documents\Programmierung\Draw2Race\tools\build.ps1
- https://developer.android.com/developer-verification
- https://developer.android.com/developer-verification/guides/faq
- https://developer.android.com/developer-verification/guides/limited-distribution
- https://support.google.com/android-developer-console/answer/17131204?hl=en
- https://support.google.com/android-developer-console/answer/16640821?hl=en
- https://android-developers.googleblog.com/2026/03/android-developer-verification-rolling-out-to-all-developers.html
- https://www.androidauthority.com/android-sideload-offline-3598988/
- https://developers.google.com/android/play-protect/client-protections
- https://support.google.com/android/answer/9286773?hl=en

## 8. Ohne eigenes iPhone und ohne Mac lässt sich Safari realistisch testen: BrowserStack Open Source ist kostenlos bei öffentlichem Quellcode, der iOS-Simulator läuft auf GitHub-macOS-Runnern bei öffentlichen Repos kostenlos, Playwright-WebKit unter Windows kann WebGL2 für den Godot-Export darstellen. Tests müssen über eine Netzwerk-IP statt localhost laufen, weil localhost als Secure Context gilt.

**Urteil: teilweise**

**Bestätigt**
- macOS-Runner: Laut GitHub-Doku sind Standard-Runner in öffentlichen Repos kostenlos, größere Runner kosten immer. ShakieVan/Mau-Mau-Flip ist öffentlich. iOS-Simulator-Läufe in CI sind also kostenlos möglich.
- localhost-Regel: Laut Secure-Contexts-Spezifikation (MDN) gelten localhost, 127.0.0.0/8 und *.localhost als vertrauenswürdig, sind also Secure Context. Tests über eine LAN-IP bzw. einen anderen Hostnamen sind deshalb richtig.

**Nicht realistisch für Behauptung 3**
Der Simulator läuft auf Mac-Hardware. Speichergrenzen, GPU und Tempo eines iPhone 11 bildet er nicht nach. Für Funktionsprüfungen taugt er, für Leistung und Speicher nicht.

**BrowserStack**
- Das Programm bietet Live, Automate und Percy, 5 Nutzer und 5 parallele Sitzungen, „Lifetime“. Man bewirbt sich mit der Projekt-URL, die Kriterien stehen nicht öffentlich auf der Seite.
- Mau-Mau Flip steht laut LICENSE unter CC BY-NC 4.0. Das ist keine OSI-Open-Source-Lizenz.
- Ob BrowserStack das Projekt aufnimmt, ist deshalb unsicher. „Kostenlos, wenn der Code öffentlich ist“ ist zu stark.

**Playwright-WebKit unter Windows**
- Das ist der WinCairo-Port mit Wasm-JIT seit Ende 2024.
- WebGL funktioniert grundsätzlich: Issue #42885 (09/2026) meldet einen gesunden Kontext, aber leere Screenshots nach Größenänderung nur unter Windows.
- WebGL2 mit einem Godot-Export ist nicht belegt.
- Playwright schaltet per Patch Funktionen ab (#31017). Ersatz für iOS-Safari ist es nicht.

**Konsequenz:**

Für die Go/No-Go-Entscheidung in M1 eine echte iPhone-Sitzung fest einplanen. Möglichkeiten:
- BrowserStack Live nach Zusage (Antrag früh stellen, Lizenzfrage klären – die Lizenzwahl entscheidet der Nutzer),
- geliehenes iPhone, z. B. von Mitreisenden,
- Vorführgerät im Laden.

Simulator-CI nur als Funktions-Regression: Laden über http per IP, keine Ausnahmen in der Konsole, ws-Verbindung, Ton-Freischaltung.

Playwright-WebKit unter Windows nur als grober Frühindikator.

**Quellen:**
- https://docs.github.com/en/billing/concepts/product-billing/github-actions
- https://www.browserstack.com/open-source
- E:\Documents\Programmierung\Mau-Mau Flip\LICENSE
- https://github.com/microsoft/playwright/issues/42885
- https://github.com/microsoft/playwright/issues/31017
- https://iangrunert.com/2024/10/07/every-jit-tier-enabled-jsc-windows
- https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts

