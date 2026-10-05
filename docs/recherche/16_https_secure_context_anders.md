**Fazit:** Für Chrome auf Android funktioniert der Weg über eine PWA mit Secure Context. Auf dem iPhone funktioniert er nur mit WebRTC und einem QR-Austausch in beide Richtungen. Das ist aufwendig und ohne iPhone nicht testbar. Ein wichtiger Nebenbefund ändert die geplante Mischform: Godot-Web startet über `http://<IP>` gar nicht. Godot-Web gehört deshalb in die https-PWA, und der schlanke Client wird der http-Weg für alle.

Ich habe keine Projektdateien verändert. Nur Hilfsdateien liegen im Scratchpad (`tn3179.json`, `webrtc.zip`).

---

## Nebenbefund: Godot-Web braucht zwingend einen Secure Context
- Die Startseite von Godot 4.6 (`full-size.html`) ruft `Engine.getMissingFeatures()` auf. Diese Prüfung meldet unabhängig von Threads „Secure Context - Check web server configuration (use HTTPS)“, und der Start bricht ab. [belegt] https://github.com/godotengine/godot/blob/4.6-stable/platform/web/js/engine/features.js · https://github.com/godotengine/godot/blob/4.6-stable/misc/dist/html/full-size.html
- Auch mit einer eigenen Startseite ohne diese Prüfung bleibt ein Problem: Beim Initialisieren des Tons ruft Godot ohne Vorbedingung `ctx.audioWorklet.addModule(...)` auf. [belegt] https://github.com/godotengine/godot/blob/4.6-stable/platform/web/js/libs/library_godot_audio.js
  - `audioWorklet` gibt es nur im Secure Context. [belegt] https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/audioWorklet
  - Folge: Godot-Web über http läuft bestenfalls ohne Ton. [Ableitung, Gerätetest nötig]
- Wake Lock gibt es ebenfalls nur im Secure Context. [belegt] https://developer.mozilla.org/en-US/docs/Web/API/Screen_Wake_Lock_API
- Konsequenz: „Godot-Web probieren, sonst schlanker Client“ geht über den http-Link des Hosts nicht. Godot-Web braucht https, also die PWA auf GitHub Pages. [Ableitung]

## 1. Von der https-PWA zu `ws://192.168.x.y`
**Chrome (Desktop und Android) ab Version 147:**
- WebSockets ins lokale Netz lösen eine Berechtigungsabfrage aus.
- Nach der Erlaubnis gilt für private IP-Adressen und `.local`-Namen eine Ausnahme von der Mixed-Content-Sperre.
- Voraussetzung ist ein Secure Context. Android WebView ist ausgenommen.
- [belegt] https://groups.google.com/a/chromium.org/g/blink-dev/c/O6GMKt44Ups · https://developer.chrome.com/blog/local-network-access · https://developer.chrome.com/release-notes/147

**`targetAddressSpace` für WebSocket (Chrome 154)** braucht man nur bei Hostnamen, die auf eine lokale Adresse zeigen. Bei einer IP-Adresse genügt `new WebSocket("ws://192.168.43.1:8080")`. [belegt] https://chromestatus.com/release-notes/154
- Godots `WebSocketPeer` im Web-Export funktioniert damit ohne Anpassung. [Ableitung]
- Lehnt der Gast die Abfrage ab, geht nichts. Wir brauchen dann einen Hinweis und den Rückfall auf den http-Weg. [Ableitung]

**Firefox:**
- Firefox fragt ebenfalls nach lokalem Netzzugriff (Policy ab Version 145). [belegt] https://firefox-admin-docs.mozilla.org/reference/policies/localnetworkaccess/
- Mozillas offizielle Position ist offen. [belegt] https://github.com/mozilla/standards-positions/issues/1260
- Ob die Mixed-Content-Ausnahme für `ws://` umgesetzt ist, bleibt unklar. Das Verhalten hat sich 2026 schon einmal geändert. [Bericht] https://bugzilla.mozilla.org/show_bug.cgi?id=2059274 → [Gerätetest nötig]
- Samsung Internet und andere Chromium-Ableger: [Gerätetest nötig]

**Safari/WebKit blockiert die Verbindung:**
- `ws://` von einer https-Seite wird geblockt, sogar zu `localhost`. [Bericht] https://discussions.apple.com/thread/256075428 · der WebKit-Bug dazu ist offen: https://bugs.webkit.org/show_bug.cgi?id=171934
- WebKit baut Local Network Access gerade erst ein. WebSocket fehlt noch ausdrücklich, und der PR ist nicht gemergt. [belegt] https://github.com/WebKit/WebKit/pull/75708
- Die Features von Safari 27.0 erwähnen Local Network Access nicht. [belegt] https://webkit.org/blog/18325/webkit-features-for-safari-27-0/
- Folge: Auf dem iPhone ist der Weg „PWA + WebSocket“ heute nicht möglich. [Ableitung]

**WebTransport ist kein Ausweg:**
- Safari kann WebTransport seit 26.4. [belegt] https://webkit.org/blog/17862/webkit-features-for-safari-26-4/
- Das Anheften eines selbstsignierten Zertifikats per Hash (`serverCertificateHashes`) will WebKit aber nicht umsetzen. Ohne Internet gibt es kein echtes Zertifikat. [belegt] https://github.com/w3c/webtransport/issues/623

## 2. WebRTC-DataChannel mit QR-Signalisierung
**Grundsätzlich möglich:**
- WebRTC fällt nicht unter Mixed Content. Chrome regelt WebRTC noch nicht über die Netzwerk-Berechtigung, es gibt nur einen Prototyp-Plan. [belegt] https://developer.chrome.com/blog/local-network-access · https://groups.google.com/a/chromium.org/g/blink-dev/c/CDy8LAs-DoA

**Größe der Daten im QR-Code:**
- Ein normales SDP hat etwa 2,5 kB. Das Projekt QWBP schafft 55–100 Byte (QR-Version 4–5). [Bericht: Beta, Selbstangabe] https://github.com/magarcia/qwbp · https://magarcia.io/air-gapped-webrtc-breaking-the-qr-limit/
- Für uns reicht ein eigenes Minimalformat:
  - Host → Gast: Fingerprint, ufrag/pwd, IP:Port, Protokollversion – etwa 70–100 Byte.
  - Gast → Host: Fingerprint und ufrag/pwd – etwa 60 Byte.
  - [Ableitung]
- Kompression bringt bei diesen Daten nichts. [Bericht, gleiche Quelle]

**Es braucht zwingend beide Richtungen.** Jede Seite muss Fingerprint und ICE-Zugangsdaten der anderen kennen; auch QWBP tauscht symmetrisch aus. [belegt] https://github.com/magarcia/qwbp/blob/main/COMPATIBILITY.md
Ohne Server gibt es drei Möglichkeiten für den Rückweg vom Gast zum Host:
- **(a) Der Host scannt den QR-Code des Gasts.**
  - Godot kann ab 4.5 die Android-Kamera nutzen. [belegt] https://github.com/godotengine/godot/pull/106094
  - Zum Auslesen des QR-Codes braucht es ein Plugin. Offline klappt das nur mit dem fest eingebauten ML-Kit-Modell (~2,4 MB) oder ZXing. Die nachladbare Variante kommt über die Play-Dienste und braucht Internet. [belegt] https://developers.google.com/ml-kit/vision/barcode-scanning/android
- **(b) Der Gast öffnet `http://host/…?a=<Daten>` als normale Seitennavigation.** Das zählt nicht als Mixed Content. In der iOS-Web-App öffnet sich dafür ein In-App-Browser. Ob die PWA im Hintergrund weiterläuft, ist offen. [Ableitung, Gerätetest nötig]
- **(c) fetch, iframe oder Bild an den http-Host** → wird geblockt (siehe Punkt 1). [Ableitung]

**ICE ohne Internet:**
- Chrome versteckt lokale IPs hinter `.local`-Namen, außer die Seite hat die Kamera- oder Mikrofonfreigabe. [belegt] https://groups.google.com/g/discuss-webrtc/c/6stQXi72BEU
- Safari gibt Host-Kandidaten erst nach dieser Freigabe heraus. [Bericht] https://bugs.webkit.org/show_bug.cgi?id=186302
- Die Kandidaten des Gasts werden aber gar nicht gebraucht:
  - Der Host nennt seine echte IP:Port im Angebot.
  - Die Prüfpakete des Gasts kommen beim Host an. Der Host lernt die Gastadresse dabei als „peer-reflexive“ Kandidat. [belegt] https://www.rfc-editor.org/rfc/rfc8445#section-7.3.1.3
  - libjuice (das ICE-Backend von libdatachannel) legt diesen Kandidaten aus eingehenden Anfragen an. [belegt] https://github.com/paullouisageneau/libjuice/blob/master/src/agent.c
  - Damit ist kein ICE-lite nötig. [Ableitung]
- `.local`-Namen löst libdatachannel über den Resolver des Systems auf. [belegt] https://github.com/paullouisageneau/libdatachannel/blob/master/src/candidate.cpp
  - Ob Android das kann: [Gerätetest nötig]. Wegen der peer-reflexiven Kandidaten ist es egal.

**Godot-Host (Plugin webrtc-native):**
- Version 1.2.2 vom 30.09.2026 läuft mit Godot 4.3+ und enthält Android-Bibliotheken für arm64 und x86_64 (je ~3,4 MB). [belegt] https://github.com/godotengine/webrtc-native/releases/tag/1.2.2-stable (Inhalt der Zip geprüft)
- Das 16-KB-Page-Size-Problem (Pflicht für Google Play) ist seit 1.2.0 behoben. [belegt] https://github.com/godotengine/webrtc-native/issues/179
- Ob die Kandidatensuche im Android-Hotspot funktioniert: [Gerätetest nötig]

**iOS-Berechtigung für das lokale Netz:**
- QWBP berichtet von einer „Local Network“-Abfrage auf iOS. [Bericht]
- Apple TN3179 sagt dagegen: Verkehr aus Safari, WKWebView und SFSafariViewController braucht diese Berechtigung nicht. [belegt] https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- → [Gerätetest nötig]

## 3. iOS-Besonderheiten
**Bleibt die PWA im Cache?**
- Web-Apps auf dem Home-Bildschirm zählen ihre eigenen Nutzungstage, nicht die von Safari. [belegt] https://webkit.org/blog/10218/full-third-party-cookie-blocking-and-more/
- Seit Safari 17 gilt: Bis 60 % des Speichers pro Origin. Bei Speicherdruck wird die am längsten ungenutzte Seite gelöscht. `persist()` wird nach Heuristik gewährt, z. B. für Home-Bildschirm-Apps. [belegt] https://webkit.org/blog/14403/updates-to-storage-policy/
- Der Cache bleibt also in der Regel erhalten, garantiert ist es nicht. [Ableitung]

**Getrennte Speicher:**
- Safari und Web-App teilen sich den Speicher nur teilweise. Wer in Safari den Verlauf löscht, löscht auch PWA-Caches. [Bericht] https://firt.dev/ios-14/
- Empfehlung: Nach dem Hinzufügen die App einmal online vom Home-Icon starten. [Ableitung, Gerätetest nötig]

**Links öffnen nicht in der installierten Web-App** (kein Link Capturing). [belegt] https://firt.dev/notes/pwa-ios/
- Ein QR-Scan mit der iPhone-Kamera öffnet also Safari, nicht die PWA.
- Der Gast muss die App selbst öffnen und dort scannen. [Ableitung]

**Kamera:**
- Kamerazugriff in Web-Apps geht seit iOS 13. [belegt] https://firt.dev/notes/pwa-ios/
- Es gibt Berichte über wiederholte Berechtigungsabfragen. [Bericht] https://bugs.webkit.org/show_bug.cgi?id=215884 · https://developer.apple.com/forums/thread/788518
- Der eingebaute QR-Erkenner (BarcodeDetector) ist in iOS-Safari aus. Wir bräuchten eine JS-Bibliothek wie jsQR oder zxing-wasm. [belegt] https://caniuse.com/mdn-api_barcodedetector

**Weitere Punkte:**
- WebRTC in Web-Apps funktioniert. [belegt] https://firt.dev/notes/pwa-ios/
- Wake Lock funktioniert in Home-Bildschirm-Apps erst ab iOS 18.4. [belegt] https://webkit.org/blog/16574/webkit-features-in-safari-18-4/
- Apple hat die geplante Abschaffung der Home-Bildschirm-Apps in der EU (iOS 17.4) zurückgenommen. [belegt] https://9to5mac.com/2024/03/01/apple-home-screen-web-apps-ios-17-eu/
- Risiko für den http-Weg: Unter iPadOS 26.2 brechen `ws://`-Verbindungen aus einer http-PWA nach etwa 1 s ab. Der Fehler (FB21416603) ist gemeldet. [Bericht] https://developer.apple.com/forums/thread/811063

## 4. Versionsabgleich zwischen gecachtem Client und Host
Lösbar, alle Punkte hier sind [Ableitung]:
- **Protokollversion und Mindestversion** stehen im Host-Link bzw. QR-Code. Die PWA prüft das vor dem Verbinden.
- **Mehrere Spielversionen vorhalten:** Die PWA speichert die Engine (`.wasm`) einmal und je Protokollversion eine `.pck`. Beim Start wählt sie die passende Datei über `mainPack`.
- **Notausgang:** Passt keine Version, bietet die PWA den http-Link für den schlanken Client an.
- **Spiellogik vom Host nachladen** (über den Datenkanal mit `load_resource_pack`) ginge auch. Dann führt der Gast aber Code vom Host aus, das ginge nur mit Signatur. Erst einmal nicht machen.
- **Eine Adresse für beide Wege:** Die http-Startseite des Hosts zeigt einen Knopf „Godot-Version öffnen“. Er führt zu `https://shakievan.github.io/…#h=192.168.43.1:8080`. Der Service Worker liefert die Seite offline aus. Die Host-Adresse steht im Fragment, wird also nicht an den Server geschickt.
- **Eigene Domain sinnvoll:** Alle GitHub-Pages-Projekte eines Kontos teilen sich die Origin `shakievan.github.io`. [belegt: URL-Schema] https://docs.github.com/en/pages/getting-started-with-github-pages/about-github-pages
  - Speicher, Kontingent und Berechtigungen werden also geteilt. Eine eigene Domain ist besser. [Ableitung]

## 5. Aufwand und Risiko im Vergleich
| Weg | Nutzen für | Zusatzaufwand | Bei euch testbar | Hauptrisiko |
|---|---|---|---|---|
| http mit schlankem Client (Standard) | alle | – | Android ja | kein Wake Lock, kein AudioWorklet; Safari versucht bei Links zuerst https und fällt dann zurück [Bericht] https://lapcatsoftware.com/articles/2024/12/1.html; Chrome warnt bei privaten Adressen nicht [belegt] https://security.googleblog.com/2025/10/https-by-default.html |
| PWA mit Godot-Web über `ws://` | Chrome Android | gering: Godot-PWA-Export (eingebaut [belegt] https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html), Erklärung zur Berechtigungsabfrage, Versionsprüfung | ja | Gast lehnt Abfrage ab; andere Chromium-Browser |
| PWA mit WebRTC und QR-Austausch | iOS (und alle) | hoch: webrtc-native, QR-Scanner im Host, QR-Format auf beiden Seiten, zweiter Transportweg im Server (WebSocket und WebRTC parallel), Scan in beide Richtungen pro Gast | **nein** (kein iPhone) | viele offene Gerätetests |

## Empfehlung
1. **Standardweg:** http mit dem schlanken HTML/TS-Client für alle Gäste, auch iPhone. Godot-Web bieten wir über den http-Link nicht an, weil es dort nicht startet.
2. **Optionaler Zusatzweg „Godot-Web-App“** für Gäste mit vorbereitetem Gerät: zuerst nur für Android/Chrome, also PWA auf GitHub Pages mit `ws://` an die IP. Der Aufwand ist gering, testbar ist es, und es entspricht der gewünschten Wahl pro Gerät.
3. **iOS-WebRTC jetzt nicht bauen.** Den Server aber gleich mit einer Transport-Abstraktion und Protokollversionen anlegen, damit sich WebRTC später ergänzen lässt. Erst angehen, wenn jemand mit iPhone testen kann.