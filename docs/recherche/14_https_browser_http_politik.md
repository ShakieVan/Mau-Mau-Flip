# http:// auf privaten IP-Adressen: Browserverhalten im Herbst 2026 (Android + iOS)

## Kurzfazit

1. **Mit den Standardeinstellungen öffnet jeder untersuchte Browser `http://<private-IP>:<Port>/`.** Chrome, Firefox und die übrigen Chromium-Browser versuchen bei privaten IPs gar kein HTTPS. Safari unternimmt bei Links vermutlich einen stillen HTTPS-Versuch und fällt danach von selbst auf http zurück. Das kann bis zu etwa 3 s Verzögerung kosten, und genau die können wir auf dem Server verhindern.
2. **Nur Opt-in-Strengmodi zeigen eine Warnseite:** Chrome mit „öffentliche & private Websites“ (bei Android-16-Advanced-Protection ist das automatisch aktiv), Chrome iOS mit seinem Schalter, Safari mit „Not Secure Connection Warning“, Brave „Strict“. Der Nutzer tippt dann einmal auf „Weiter“. Ein echtes Verbot ohne Weiter-Knopf gibt es in keinem Browser, und Firefox nimmt lokale IPs sogar im HTTPS-Only-Modus aus.
3. **Das größere Problem sind nicht die Browser, sondern die Secure-Context-Pflicht.** Die Standard-HTML-Hülle von Godot 4.6 bricht ohne Secure Context ab (Code-Beleg im Nebenbefund). Für die Godot-Web-Variante brauchen wir also eine eigene Hülle, oder wir nehmen den schlanken Client.
4. **Für ein Verbot von http auf privaten Adressen gibt es keine Anzeichen.** Es gibt aber Verschärfungen am Rand: Chrome will Local Network Access (LNA, eine Berechtigungsabfrage für Zugriffe ins lokale Netz) künftig auf alle cross-origin-Anfragen ins LAN ausweiten. Android 17 führt eine eigene Berechtigung für das lokale Netz ein (ACCESS_LOCAL_NETWORK). Gegenmaßnahme: Seite und WebSocket auf **demselben Host und Port** betreiben.

Teile der früheren Recherche sind bestätigt, andere nur mit Einschränkung (Details in Abschnitt 4 und im Nebenbefund):
- **Chrome nimmt private IPs aus:** bestätigt.
- **Safari 18.2 versucht HTTPS bei Links:** bestätigt. Ob das auch für private IPs gilt, ist nirgends dokumentiert.
- **Probleme mit `wss://` und selbstsignierten Zertifikaten auf iOS:** bestätigt.
- **Liste der Secure-Context-APIs:** bestätigt und ergänzt.

---

## 1. Tabelle: Browser × Standard × strengster Modus

| Browser / Plattform | Standard (Okt. 2026): geht `http://IP:Port`? Was sieht der Nutzer? | Strengster Modus: was muss der Nutzer tippen? |
|---|---|---|
| **Chrome Android (154)** | Geht, kein HTTPS-Versuch. Private IPs gelten als „non-unique“ und sind ausgenommen, ebenso Nicht-Standardports und explizit eingegebenes `http://`. In der Adressleiste steht „Nicht sicher“. [belegt] | Einstellung „Warnt bei unsicheren öffentlichen & privaten Websites“ oder Android Advanced Protection: Chrome versucht HTTPS auf demselben Port, dann kommt die Warnseite. Einmal „Weiter zur Website“ tippen, die Entscheidung bleibt 15 Tage pro Host gespeichert. [belegt]; genauer UI-Text [Gerätetest nötig] |
| **Chrome iOS** | Geht. Das HTTPS-Upgrade-Feature ist im iOS-Code standardmäßig aus; ein Feldversuch könnte es serverseitig einschalten. [belegt Code / Ableitung] | Schalter „Immer sichere Verbindungen verwenden“ (ohne Wahl öffentlich/privat). Nur localhost ist ausgenommen, also HTTPS-Versuch, dann Warnseite, dann „Weiter“. [belegt Code / Ableitung] |
| **Safari iOS 18.2 bis 27** | Geht. Bei angetippten Links und Lesezeichen kommt vermutlich zuerst ein stiller HTTPS-Versuch, danach der automatische Rückfall auf http. Getippte URLs werden nicht hochgestuft. Der Rückfall kommt sofort bei TLS- oder Verbindungsfehler, sonst nach etwa 3 s Timeout. Ausnahmen für private IPs sind nicht dokumentiert, und Nutzer berichten von Verzögerungen bei lokalen http-Links. [belegt Mechanik / Bericht Verzögerung]. Verhalten beim QR-Code aus der Kamera-App [Gerätetest nötig] | Einstellung „Not Secure Connection Warning“ (Einstellungen → Apps → Safari): Warnseite „This Connection Is Not Secure“, dann „Continue“ tippen. Dass für localhost ein Fehler ohne Weiter-Knopf kam, wurde erst im Juni 2026 in WebKit behoben (wahrscheinlich ab Safari 27). Für private IPs [Gerätetest nötig] |
| **Firefox Android** | Geht direkt. HTTPS-First ist an, nimmt aber lokale IPs, Nicht-Standardports und explizites `http://` aus. [belegt Code] | HTTPS-Only-Modus: lokale IPs bleiben ausgenommen (`upgrade_local` steht auf false). Es muss nichts getippt werden. [belegt Code] |
| **Firefox iOS** | Geht. Ein HTTPS-Upgrade ist hinter einem serverseitigen Feature-Flag möglich, und zwar mit automatischem Rückfall auf http. [belegt Code] | Keinen eigenen Strengmodus gefunden. [Ableitung] |
| **Samsung Internet** | Basiert auf Chromium (v29 nutzt Blink 136, v30 erschien im Mai 2026). Daneben gibt es Samsungs eigenen Schalter „Switch to secure connection (HTTPS)“. Wie das bei privaten IPs wirkt, ist unbekannt. Eine IP ohne `http://` wird teils als Suchbegriff behandelt. [Bericht] / [Gerätetest nötig] | Unbekannt. [Gerätetest nötig] |
| **Edge Android** | Das alte „Automatic HTTPS“ ist seit Edge 140 abgeschaltet und durch Chromiums HTTPS-Upgrades ersetzt. Daher sehr wahrscheinlich wie Chrome im Standard. [belegt Policy-Doku / Ableitung] | Wahrscheinlich wie Chrome. [Gerätetest nötig] |
| **Edge iOS** | Nutzt WKWebView. Wahrscheinlich wie Chrome iOS. [Ableitung] / [Gerätetest nötig] | [Gerätetest nötig] |
| **Brave Android** | Geht. Brave legt nur eine Schicht über Chromiums Upgrade-Logik; die Ausnahme für private Adressen greift außerhalb des Strict-Modus. [belegt Code] | Shields „Strict“: Warnseite, dann „Weiter“. [belegt Code] |
| **Brave iOS** | Im Code gibt es keine IP-Ausnahme, also HTTPS-Versuch und bei Fehler automatischer Rückfall. [belegt Code] | „Strict“: eigene Warnseite („HTTP blockiert“), dann zulassen. [belegt Code]; UI-Text [Gerätetest nötig] |
| **DuckDuckGo** (Android: System-WebView, iOS: WKWebView) | Geht. „Smarter Encryption“ stuft nur Domains auf ihrer Liste hoch, private IPs stehen dort nicht. Es gibt keine Warnseite. [belegt] | Kein Strengmodus bekannt. [Ableitung] |
| **Opera Android** | Basiert auf Chromium. Laut Forum hat Opera keinen Schalter „Immer sichere Verbindungen“, daher gilt Chromiums Standard und private IPs sind ausgenommen. [Bericht / Ableitung] | Kein Strengmodus bekannt. [Bericht] |

**iOS-Dialog „Lokales Netzwerk“:** Laut Apple brauchen Datenverkehr aus Safari, SFSafariViewController und WKWebView **keine** Berechtigung fürs lokale Netz. Chrome, Firefox und Edge auf iOS zeigen beim Laden der Seite und für den WebSocket also keinen solchen Dialog. [belegt, TN3179] Sie selbst können ihn für eigene Funktionen trotzdem einmal auslösen. [Ableitung]

**Chrome LNA (seit Chrome 142, für WebSockets ab 147):** Eine http-Seite auf einer privaten IP, die einen WebSocket zur **selben** privaten IP öffnet, ist eine local→local-Verbindung und **nicht** betroffen. Abgefragt wird nur bei public→local, public→loopback und local→loopback. [belegt] Microsoft schreibt allerdings, LNA gelte „noch nicht“ für local→local. [belegt]

**APK über http in Chrome:** HTTP-Downloads gelten als „insecure download“ und werden mit einer sichtbaren Warnung blockiert, die der Nutzer mit „Behalten“ umgehen kann. Ausgenommen ist nur localhost, private IPs **nicht**. APK steht nicht auf der Liste der als sicher geltenden Dateiendungen. [belegt Code] Genauer UI-Text [Gerätetest nötig].

---

## 2. Serverseitige Tricks

1. **TLS-ClientHello sofort ablehnen.** Das erste Byte prüfen: Ist es `0x16` (TLS-Handshake), sofort einen TLS-Alert senden (z. B. `15 03 01 00 02 02 28`) oder die Verbindung einfach schließen.
   - In WebKit lösen „SecureConnectionFailed“, „NetworkConnectionLost“ und „CannotConnectToHost“ den Rückfall auf http aus. Ohne Antwort greift erst der Timeout von 3 s, oder der gemessene Durchschnitt. [belegt Code]
   - Chrome fällt bei jedem Netzwerkfehler zurück. Ausnahmen sind nur DNS-Fehler, ERR_NETWORK_CHANGED, ERR_INTERNET_DISCONNECTED und ERR_ADDRESS_UNREACHABLE. Die Timer stehen auf 3 s, im Warnmodus auf 5 s. [belegt Code]
   - Das ist wichtig, weil der GDScript-Server sonst auf `\r\n\r\n` wartet und so die Verzögerung erst erzeugt. [Ableitung]
   - Nebeneffekt: TLS-Versuche ins Log schreiben. So lässt sich bei Gerätetests sehen, welcher Browser hochstuft. [Ableitung]
2. **Im QR-Code die vollständige URL `http://192.168.x.y:PORT/` verwenden,** also Schema und Port immer ausschreiben. Chrome und Firefox stufen explizites `http://` und Nicht-Standardports außerhalb des Strengmodus nie hoch. [belegt Code] Samsung Internet behandelt eine IP ohne Schema eventuell als Suchbegriff. [Bericht]
3. **Port über 1024 behalten.** Port 80 ist auf Android ohne Root ohnehin nicht möglich. [Ableitung] Die Nicht-Standardport-Ausnahme hilft bei Chrome und Firefox. [belegt]
4. **HSTS ist für IP-Literale wirkungslos.** Nach RFC 6797 §8.1 merkt sich der Browser eine IP nicht als HSTS-Host, und ein HSTS-Header über unverschlüsseltes http wird ohnehin ignoriert. [belegt] Trotzdem nie setzen. Keine IP-URL bedeutet außerdem kein mDNS und kein DNS, was im Offline-Fall robuster ist. [Ableitung]
5. **Kein `Content-Security-Policy: upgrade-insecure-requests` senden.** Diese Anweisung schreibt laut Spezifikation auch `ws://` in `wss://` um (Abschnitt 5 „Modifications to WebSockets“), und das würde den WebSocket brechen. [belegt] Den Request-Header `Upgrade-Insecure-Requests: 1` ignorieren und niemals auf https umleiten. [Ableitung]
6. **Seite und WebSocket über denselben Host und Port ausliefern.** WebSockets bauen die Verbindung mit `http(s)://`-Schema auf, also ist ein WebSocket zum gleichen Host und Port same-origin. [Ableitung aus der WHATWG-WebSocket-Spezifikation] Chrome plant, LNA auf „all cross-origins requests going to destinations on the local network“ auszudehnen. LNA verlangt einen Secure Context, also wäre ein cross-origin-WebSocket von einer http-Seite dann blockiert. [belegt Zitat / Ableitung]
7. **IP-Adresse pro Sitzung stabil halten.** Chrome speichert die „Weiter“-Entscheidung im Strengmodus 15 Tage pro Host. [belegt]
8. **Hinweis im Beitrittsbildschirm** für Nutzer mit Strengmodus: „Bei Warnung ‚Weiter‘ tippen“. Dazu ein WebSocket mit automatischem Wiederverbinden. Unter iPadOS 26 gibt es Berichte, dass lokale `ws://`-Verbindungen nach etwa 1 s per FIN/RST abbrechen; ein Feedback an Apple läuft. [Bericht]

---

## 3. Gibt es Anzeichen für ein Verbot von http auf privaten Adressen?

- **Chrome:** Der Standard nimmt private Websites ausdrücklich aus. Begründung: „There is no single owner of `192.168.0.1` for a certification authority“. Der Modus mit Warnungen auch für private Websites bleibt Opt-in. Google schreibt außerdem: „In the future, we hope to work to further reduce barriers to adoption of HTTPS, especially for local network sites.“ Einen Zeitplan gibt es nicht. [belegt] Eine Verschärfung kommt also eher dann, wenn lokales HTTPS einfacher geworden ist. [Ableitung]
- **Chrome LNA:** Die Ausweitung auf cross-origin-Anfragen im LAN ist angekündigt. Same-origin bleibt davon unberührt. [belegt]
- **WebKit:** Local Network Access wird gerade implementiert (Commits von Juli bis Oktober 2026). Die Einstellung `LocalNetworkAccessEnabled` steht aber auf `false` und gilt als „unstable“. [belegt] Wenn sie der Spezifikation folgt, ist local→local nicht betroffen. [Ableitung]
- **Firefox:** Lokale Adressen sind selbst im HTTPS-Only-Modus ausgenommen. [belegt]
- **Android 17:** Die Berechtigung `ACCESS_LOCAL_NETWORK` ist Pflicht ab targetSdk 37 und gilt auch für **eingehende** TCP-Verbindungen. Die Android-Doku spricht Browser ausdrücklich an; WebViews erben die Berechtigung der App. [belegt] Godot 4.6 setzt targetSdk 36, und Play verlangt seit 31.08.2026 API 36. Unser Host bekommt die Berechtigung also vorerst automatisch über INTERNET. [belegt] Das gilt für alle Apps, nicht speziell für http. [Ableitung]
- **Ergebnis:** Für 2026/27 gibt es kein Signal für ein generelles Verbot. Die Risiken sind die Opt-in-Strengmodi, Berechtigungen auf Plattformebene und fehlende Secure-Context-APIs. [Ableitung]

---

## 4. Nebenbefund: wichtig für die Wahl Godot-Web gegen schlanken Client

- **Godot 4.6 startet ohne Secure Context nicht.** `Engine.getMissingFeatures()` meldet „Secure Context“ auch bei Exporten ohne Threads, und die Standardhülle `full-size.html` zeigt dann nur die Fehlermeldung statt `startGame()` aufzurufen. Wir bräuchten eine **eigene HTML-Hülle**. [belegt Code]
- **Audio-Init ist ein weiteres Risiko.** `ctx.audioWorklet.addModule(...)` wird beim Audio-Start ohne Schutz aufgerufen, und `audioWorklet` gibt es nur im Secure Context. Über http droht dort also eine Exception. [belegt Code / Ableitung]. Ob das den Start verhindert oder nur das Audio [Gerätetest nötig].
- **APIs, die über http fehlen** (MDN): Service Worker (also auch PWA und Offline), Screen Wake Lock, Web Crypto (`crypto.subtle`), `crypto.randomUUID`, AudioWorklet, die asynchrone Clipboard-API, Web Share, Gamepad, DeviceOrientation/-Motion, Notifications, getUserMedia und die Storage API. [belegt] WebSocket, localStorage und IndexedDB laufen über http. [Ableitung]
- **Zur früheren Aussage „wss:// mit selbstsignierten Zertifikaten auf iOS“:** Das Cockpit-Projekt dokumentiert, dass Safaris Standard-WebSocket-Framework auf iOS und iPadOS kein `wss://` mit selbstsigniertem oder ungültigem Zertifikat unterstützt, auch nicht als vertrauenswürdig markiert. [belegt Projekt-Doku] Der oft zitierte Forenthread zu iOS 26 Beta 3 beschrieb dagegen einen Beta-Fehler, der in Beta 5 behoben war. [Bericht]

---

## 5. Was wir auf echten Geräten prüfen müssen

1. Safari iOS 18, 26 und 27: QR-Code aus der Kamera-App mit `http://IP:Port`. Gibt es einen HTTPS-Versuch, auf welchem Port, und wie lange dauert er mit und ohne schnelle TLS-Ablehnung?
2. Safari mit „Not Secure Connection Warning“ und privater IP: Erscheint der Weiter-Knopf?
3. Samsung Internet mit eingeschaltetem „Switch to secure connection (HTTPS)“.
4. Chrome Android im Strengmodus: Warnseite und Weiter-Ablauf.
5. Ablauf beim APK-Download in Chrome Android.
6. Brave iOS im Standardmodus.
7. Stabilität des `ws://`-WebSockets auf iPadOS 26.
8. Godot-Web mit eigener Hülle über http: läuft Audio?

---

## Quellen

**Chrome**
- https://security.googleblog.com/2025/10/https-by-default.html (leitet weiter auf https://blog.google/security/https-by-defau/)
- https://chromium.googlesource.com/chromium/src/+/main/docs/security/ask-before-http/ask-before-http-adoption-guide.md
- https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/ssl/https_upgrades_interceptor.cc
- https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/ssl/https_upgrades_util.cc
- https://chromium.googlesource.com/chromium/src/+/main/net/base/url_util.cc
- https://chromium.googlesource.com/chromium/src/+/main/chrome/common/chrome_features.cc
- https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/download/insecure_download_blocking.cc
- https://chromium.googlesource.com/chromium/src/+/main/ios/chrome/browser/https_upgrades/model/https_only_mode_upgrade_tab_helper.mm
- https://chromium.googlesource.com/chromium/src/+/main/ios/components/security_interstitials/https_only_mode/feature.cc
- https://chromiumdash.appspot.com/fetch_milestone_schedule?mstone=154 (Chrome 154 stabil seit 22.09.2026)
- https://support.google.com/chrome/answer/10468685?hl=en&co=GENIE.Platform%3DAndroid
- https://support.google.com/chrome/answer/10468685?hl=en&co=GENIE.Platform%3DiOS
- https://security.googleblog.com/2025/07/advancing-protection-in-chrome-on.html

**Local Network Access**
- https://developer.chrome.com/blog/local-network-access
- https://github.com/WICG/local-network-access/blob/main/explainer.md
- https://developer.chrome.com/release-notes/142
- https://learn.microsoft.com/en-us/deployedge/ms-edge-local-network-access

**Safari / WebKit / Apple**
- https://webkit.org/blog/16301/webkit-features-in-safari-18-2/
- https://lapcatsoftware.com/articles/2024/12/1.html
- https://github.com/WebKit/WebKit/blob/main/Source/WebKit/NetworkProcess/NetworkResourceLoader.cpp
- https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/network/cocoa/ResourceErrorCocoa.mm
- https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/WebPageProxy.cpp
- https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebpagePreferences.h
- https://github.com/WebKit/WebKit/blob/main/Source/WTF/Scripts/Preferences/UnifiedWebPreferences.yaml
- https://bugs.webkit.org/show_bug.cgi?id=284559
- https://github.com/WebKit/WebKit/pull/65222
- https://support.apple.com/guide/iphone/iphfba2ed790/27/ios/27
- https://discussions.apple.com/thread/255937564
- https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- https://developer.apple.com/forums/thread/811063
- https://developer.apple.com/forums/thread/792842
- https://cockpit-project.org/running/safari

**Firefox**
- https://github.com/mozilla-firefox/firefox/blob/main/dom/security/nsHTTPSOnlyUtils.cpp
- https://github.com/mozilla-firefox/firefox/blob/main/modules/libpref/init/StaticPrefList.yaml
- https://support.mozilla.org/en-US/kb/https-first
- https://github.com/mozilla-mobile/firefox-ios/blob/main/firefox-ios/Client/TabManagement/Tab.swift

**Samsung, Edge, Brave, DuckDuckGo, Opera**
- https://developer.samsung.com/internet/release-note.html
- https://news.samsung.com/global/samsung-internet-17-0-puts-privacy-and-security-front-and-center
- https://forums.androidcentral.com/threads/samsung-internet-browser-how-to-access-local-ip-addresses.1012123/
- https://browsercalendar.com/browsers/samsung-internet
- https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/automatichttpsdefault
- https://github.com/brave/brave-core/blob/master/chromium_src/chrome/browser/ssl/https_upgrades_interceptor.cc
- https://github.com/brave/brave-core/blob/master/ios/brave-ios/Sources/BraveShields/HttpsUpgradeTabHelper.swift
- https://brave.com/privacy-updates/29-https-by-default-ios/
- https://duckduckgo.com/duckduckgo-help-pages/privacy/smarter-encryption
- https://forums.opera.com/topic/65917/force-https-opera-for-android

**Standards**
- https://www.rfc-editor.org/rfc/rfc6797#section-8.1
- https://www.w3.org/TR/upgrade-insecure-requests/ (Abschnitt 5)
- https://websockets.spec.whatwg.org/#concept-websocket-establish

**Android**
- https://developer.android.com/privacy-and-security/local-network-permission
- https://developer.android.com/about/versions/17/behavior-changes-17
- https://developer.android.com/google/play/requirements/target-sdk

**Godot**
- https://github.com/godotengine/godot/blob/4.6/platform/android/java/app/config.gradle
- https://github.com/godotengine/godot/blob/4.6/platform/web/js/engine/features.js
- https://github.com/godotengine/godot/blob/4.6/misc/dist/html/full-size.html
- https://github.com/godotengine/godot/blob/4.6/platform/web/js/libs/library_godot_audio.js
- https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html

**MDN**
- https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts/features_restricted_to_secure_contexts
- https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/audioWorklet
- https://developer.mozilla.org/en-US/docs/Web/API/Crypto/randomUUID

Es wurden keine Projektdateien verändert.