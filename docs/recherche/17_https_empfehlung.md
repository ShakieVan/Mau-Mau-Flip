# Mau-Mau Flip: http im Urlaubs-WLAN – Gutachten und Empfehlung (Stand 04.10.2026)

Kennzeichnung: **[belegt]** = offizielle Doku oder Quellcode, selbst geprüft · **[Bericht]** = Forum, Blog, Drittanbieter oder nur aus den Rechercheberichten übernommen · **[Ableitung]** = eigener Schluss · **[Gerätetest nötig]**. Die Nummern (Q1 usw.) verweisen auf die Quellenliste am Ende. Projektdateien wurden nicht verändert.

## Kurz gesagt

1. **Die Befürchtung trifft für private Adressen nicht zu.** In der Grundeinstellung öffnet jeder untersuchte Browser `http://192.168.x.y:Port`. Nur wer freiwillig einen strengen Sicherheitsmodus einschaltet, sieht eine Warnseite, und auf der kann man immer auf „Weiter“ tippen.
2. **Das eigentliche Problem ist der fehlende „Secure Context“.** Über http fehlen einige Browser-Funktionen. Das trifft vor allem **Godot-Web**: Mit der Standard-Startseite startet es über http gar nicht, und der Ton ist gefährdet.
3. **Echtes HTTPS im Offline-Hotspot gibt es nicht.** Ein Weg über eine eigene Domain wäre möglich, aber nur, wenn die Gäste Internet haben. Er ist aufwendig und kommt höchstens später als Option.
4. **PWA und WebRTC bauen wir jetzt nicht.** Wir legen nur die billige Vorarbeit an: Protokollversion und eine gekapselte Transportschicht.
5. **Neu gefunden:** Den Rat „Seite und WebSocket auf demselben Port“ (Bericht 1) kann Godot mit Bordmitteln nicht umsetzen (Details in Abschnitt 2.2).

---

## 1. Faktencheck der 5 tragenden Aussagen

### A1 – Chrome (154, Android) versucht bei privaten IPs kein HTTPS und warnt nicht. Nur der freiwillige Strengmodus warnt. → **bestätigt**
- In Googles Leitfaden steht wörtlich: „Non-unique hostnames, local IP addresses, and single-label hostnames will also not show warnings.“ Ein „Weiter“ merkt sich Chrome 15 Tage. [belegt] (Q2)
- Im Quellcode überspringt Chrome das HTTPS-Upgrade in den nicht-strengen Modi für „non-unique hostnames“. Eine IP gilt als nicht eindeutig, wenn sie nicht öffentlich routbar ist (`!IsPubliclyRoutable()`). Nicht-Standardports und ausdrücklich getipptes `http://` sind ebenfalls ausgenommen. [belegt] (Q3, Q4)
- Gegenprobe: Mit Androids „Advanced Protection“ gilt die Einstellung „Immer sichere Verbindungen“ auch für private Seiten. Dann erscheint eine Warnseite mit „Weiter“. [belegt] (Q5)

### A2 – Safari (iOS ab 18.2) versucht bei Links zuerst still HTTPS und fällt danach von selbst auf http zurück. → **teilweise bestätigt**
- Den Mechanismus beschreibt Apple selbst: Safari versucht HTTPS und fällt nur bei einem Fehler auf http zurück. [belegt] (Q7) Getippte URLs werden nicht hochgestuft. [Bericht] (Q8)
- Der Upgrade-Versuch läuft mit **3 s Timeout** (oder dem gemessenen Durchschnitt). [belegt, WebKit-Code] (Q9)
- **Nicht widerlegt, aber auch nicht belegt:** Eine Ausnahme für private IPs gibt es nicht im öffentlichen WebKit-Code. Die Entscheidung zum Hochstufen kommt als Flag vom Plattform-Request (`wasSchemeOptimisticallyUpgraded`), fällt also im geschlossenen Teil (Safari oder CFNetwork). (Q10) Ob ein QR-Scan aus der Kamera als „Link“ zählt: [Gerätetest nötig].

### A3 – Firefox nimmt lokale IPs aus, sogar im HTTPS-Only-Modus. → **bestätigt**
- `dom.security.https_only_mode.upgrade_local` steht auf `false`, und der Code gibt dann für lokale Adressen eine Ausnahme zurück. `https_first_for_custom_ports` steht auf `false`. [belegt] (Q11, Q12)

### A4 – Godot 4.6 Web braucht einen Secure Context. → **bestätigt für den Start, beim Ton unklar**
- `getMissingFeatures()` meldet „Secure Context“ **unabhängig von Threads**. `full-size.html` ruft `startGame()` nur auf, wenn nichts fehlt. [belegt] (Q13, Q14)
- **Kritik an den Berichten 2 und 3:** „Godot-Web geht über http praktisch nicht“ ist zu pauschal. Eine eigene HTML-Hülle darf `engine.startGame()` direkt aufrufen. [belegt] (Q41)
- Das Risiko bleibt beim Ton. Godot ruft `ctx.audioWorklet.addModule(...)` in `GodotAudio.init` ungeschützt auf (Q15), und `audioWorklet` gibt es nur im Secure Context (Q18). Ein Fehler beim Audio-Start ist also wahrscheinlich. [Ableitung] Ein älterer Test ohne die Prüfung zeigte: Firefox lief ohne Ton, Chromium mit WASM-Fehler. [Bericht] (Q16)

### A5 – Es gibt kein browser-vertrauenswürdiges Zertifikat für private IPs, und selbstsigniert scheitert auf dem iPhone. → **bestätigt**
- Die Baseline Requirements verbieten Zertifikate für „Reserved IP Addresses“ und „Internal Names“. [belegt] (Q19)
- Let's Encrypt prüft IP-Zertifikate nur über http-01 oder tls-alpn-01, kein DNS-01. Die IP muss also öffentlich erreichbar sein. Die Zertifikate gelten 160 h. [belegt] (Q20, Q21)
- Safaris Standard-WebSocket auf iOS kann kein `wss://` mit selbstsigniertem Zertifikat. [belegt, Projekt-Doku Cockpit] (Q22)

### Zusätzliche Befunde aus der Prüfung
- **Z1 – Chrome-Abfrage für den lokalen Netzzugriff (LNA) bei WebSockets: widersprüchlich.** Blink-Intent und Release Notes zu Chrome 147 sagen, WebSockets zu lokalen Adressen lösen eine Abfrage aus (Q25, Q26). Ein Hersteller-Support-Artikel sagt dagegen, bei WebSockets gebe es **keine** Abfrage (Q27). Das betrifft nur die PWA-Idee. → [Gerätetest nötig]
- **Z2 – Ein Port für Seite und WebSocket:** `WebSocketPeer.accept_stream()` akzeptiert nur eine nackte `StreamPeerTCP` (oder TLS) und liest den Handshake selbst. [belegt] (Q32) Hat unser HTTP-Server die Anfrage schon gelesen, kann er die Verbindung nicht mehr übergeben. [Ableitung]
- **Z3 – Chrome-Flag „Insecure origins treated as secure“:** Bericht 2 sagt, auf Android brauche das Root. Das gilt nur für die Kommandozeile. Über `chrome://flags` geht es auf Android ohne Root. [Bericht] (Q37, Q52)

---

## 2. Empfehlung (in einfacher Sprache)

### 2.1 Stimmt „viele Browser lassen kein http mehr zu“?

**Für unseren Fall nein.** Keine untersuchte Quelle beschreibt eine Sperre für http auf privaten Adressen ohne „Weiter“-Möglichkeit, weder heute noch angekündigt. Ein Gerätetest für Safari mit privater IP steht noch aus (Abschnitt 3).

| Browser | Normal eingestellt | Mit strenger Einstellung (freiwillig) |
|---|---|---|
| Chrome Android | Öffnet direkt, ohne HTTPS-Versuch. In der Adressleiste steht „Nicht sicher“. [belegt] (Q2–Q4) | Warnseite, einmal „Weiter“, wird 15 Tage gemerkt. Bei Advanced Protection automatisch an. [belegt] (Q2, Q5) |
| Chrome iOS | Öffnet. Das Upgrade ist im iOS-Code standardmäßig aus. [Bericht] (Q47) | Warnseite und „Weiter“. [Bericht] / [Gerätetest nötig] |
| Safari iOS ab 18.2 | Öffnet. Bei Link oder QR vermutlich zuerst ein stiller HTTPS-Versuch, dann automatisch http. Kostet bis zu ~3 s, die wir serverseitig wegbekommen. [belegt Mechanik] (Q7, Q9) | „Warnung bei nicht sicherer Verbindung“: Warnseite. Ob bei privater IP ein „Weiter“ kommt: [Gerätetest nötig] (Q8) |
| Firefox Android | Öffnet direkt. Lokale IPs und eigene Ports sind ausgenommen. [belegt] (Q11, Q12) | HTTPS-Only: lokale IPs bleiben ausgenommen. [belegt] (Q11, Q12) |
| Samsung Internet | Chromium-Basis, vermutlich wie Chrome. Eine IP ohne `http://` wird teils als Suchbegriff behandelt. [Bericht] (Q45) | Eigener HTTPS-Schalter, Wirkung unbekannt. [Gerätetest nötig] |
| Edge / Brave / Opera (Android) | Chromium-Logik, also wie Chrome. [Bericht] (Q46, Q49) | Brave „Strict“: Warnseite und Zulassen. [Bericht] (Q46) |
| DuckDuckGo | Öffnet. Hochgestuft wird nur, was auf der eigenen Liste steht. [Bericht] (Q48) | – |

**Was über http wirklich fehlt** (MDN-Liste der Secure-Context-Funktionen) [belegt] (Q17, Q18):
- Service Worker, also keine Offline-PWA
- Bildschirm-Wachhalten (Wake Lock)
- `crypto.subtle` und `crypto.randomUUID`
- Teilen (Web Share) und die neue Zwischenablage-API
- Benachrichtigungen
- AudioWorklet

**Was über http weiter geht** [Ableitung: stehen nicht auf der MDN-Liste (Q17)]:
- WebSocket, localStorage, IndexedDB
- WebGL2 und WebAssembly
- einfaches Web Audio ohne Worklet
- `crypto.getRandomValues` (taugt für Client-IDs)

### 2.2 Was wir einbauen, damit http reibungslos klappt

**In der Host-App (Server)**
1. **HTTPS-Anklopfen sofort abweisen.**
   - Ist das erste Byte einer neuen Verbindung `0x16` (TLS-Handshake, Q33), schließt der Server sofort (optional mit TLS-Alert) und schreibt einen Log-Eintrag.
   - Ohne das wartet unser GDScript-Server auf eine HTTP-Zeile, und Safari hängt bis zum 3-s-Timeout. [belegt Timeout (Q9)] Mit dem Abweisen fällt Safari sofort zurück. [Ableitung]
   - Der Log-Eintrag zeigt bei Tests, welcher Browser es überhaupt versucht.
2. **Nie auf https umleiten.**
   - Kein HSTS: Für IP-Adressen wirkt es ohnehin nicht (Q34). [belegt]
   - Kein `upgrade-insecure-requests`: Das würde auch `ws://` in `wss://` umschreiben (Q35). [belegt]
3. **Fester Port über 1024.** Chrome und Firefox stufen eigene Ports nicht hoch. [belegt] (Q3, Q11)
4. **WebSocket und Seite: am besten ein Port.** Wegen Z2 gibt es zwei Möglichkeiten:
   - **(a) Zweiter Port nur für den WebSocket.** Das funktioniert heute, weil Chrome Verbindungen zwischen lokalen Adressen nicht prüft (Q23). Das Risiko: Chrome will die Prüfung auf alle cross-origin-Anfragen ins LAN ausweiten (Q24), und eine http-Seite darf die Erlaubnis nicht einmal anfragen (Q23). Dann wäre (a) in Chrome blockiert. [Ableitung]
   - **(b) Ein kleiner eigener WebSocket-Server in GDScript auf demselben Port:** Handshake mit SHA-1 und Base64, Rahmenformat nach RFC 6455 (Q53). Das ist überschaubar und zukunftssicher. [Ableitung]
   - **Empfehlung:** (b). Falls das zu früh zu viel ist, (a), aber hinter einer Schnittstelle, damit sich später leicht wechseln lässt.
5. **Alles offline ausliefern.** Keine CDN-Skripte und keine Webfonts; ohne Internet hängen solche Abrufe. [Ableitung]
6. **Wiederverbinden mit Sitzungs-Token.** Display aus oder App-Wechsel trennen die Verbindung. Für iPadOS 26 wird berichtet, dass lokales `ws://` nach ~1 s abbricht. [Bericht] (Q31)
7. **APK für Android-Gäste (optional).** Chrome blockiert http-Downloads mit einer sichtbaren Warnung. Private IPs sind nicht ausgenommen, der Gast tippt „Behalten“. [belegt Code] (Q6)

**Im QR-Code**
- Immer die volle URL: `http://192.168.43.1:PORT/`, mit Schema und Port. [Ableitung aus Q3, Q11]
- Unter dem QR-Code dieselbe Adresse groß als Text zum Abtippen. Getippte `http://`-Adressen stufen Safari und Chrome nicht hoch. [Bericht (Q8), belegt (Q3)]

**Auf der Startseite (Web-Client)**
- Winzig und schnell, ohne externe Abhängigkeiten.
- Beim Start prüfen, was da ist (`isSecureContext`, Wake Lock). Daran entscheiden, was angeboten wird.
- Knopf „Tippen zum Starten“. Er schaltet den Ton frei und startet einen Ersatz fürs Wachhalten (Video-Trick wie bei NoSleep.js). [Bericht (Q42), Gerätetest nötig] Klappt das nicht, Hinweis: „Automatische Sperre hochsetzen“.
- Hinweis „Bitte quer halten“, falls hochkant.
- Kurz erklären, was „Nicht sicher“ bedeutet: Die Daten sind nur im eigenen WLAN unverschlüsselt. Google selbst sagt, dass http auf privaten Seiten nur von jemandem im selben Netz missbraucht werden kann. [belegt] (Q1)

**Hilfetexte in der Host-App neben dem QR-Code** (denn wer eine Warnseite bekommt, sieht unsere Startseite noch nicht):
- „Warnseite ‚Verbindung nicht sicher‘? Auf ‚Weiter‘ bzw. ‚Trotzdem öffnen‘ tippen.“ [belegt für Chrome (Q2); Safari: Gerätetest nötig]
- „Lädt lange oder gar nicht? Adresse abtippen, mit `http://` davor.“ [Ableitung]
- „Im Hotel-WLAN klappt es nicht? Dort dürfen sich Geräte oft nicht sehen. Den Hotspot des Host-Handys nehmen.“ [belegt AP-Isolation (Q36)]
- „Im Hotspot keine Verbindung? Testweise die mobilen Daten ausschalten.“ [Bericht (Q50), Gerätetest nötig]

### 2.3 Gibt es einen sinnvollen HTTPS-Weg?

| Weg | Geht offline im Host-Hotspot? | iPhone? | Aufwand | Urteil |
|---|---|---|---|---|
| Zertifikat für die private IP | nein, verboten (Q19, Q20) | – | – | **nein** |
| Selbstsigniertes Zertifikat | Seite ja (mit Warnung), aber `wss://` scheitert auf iOS (Q22) | nein | mittel | **nein** |
| Eigene CA auf Gästegeräten | ja | nur mit Profil und manuellem Vertrauen; Root-CA auf fremden Handys ist riskant (Bericht 2) | hoch | **nein** (höchstens für eigene Geräte) |
| Plex-Muster: eigene Domain, Name zeigt auf LAN-IP, Gerätezertifikat per DNS-01 (Q38) | **nein**, der Gast braucht Internet-DNS. Der LocalOnlyHotspot leitet DNS laut Quellcode nicht weiter. [Bericht] (Q39) Router mit Rebind-Schutz blocken es. [Bericht] (Q40) | ja, wenn DNS geht | hoch: Domain (~10 €/Jahr), Relay, ACME-Plugin, Erneuerung alle paar Wochen | **optional, später** |
| Chrome-Flag „Insecure origins treated as secure“ | ja | nein, Safari hat nichts Vergleichbares | Gast trägt die IP in `chrome://flags` ein | **nur Test-/Nerd-Tipp**, gut für unseren Godot-Web-Ton-Test (Q37, Q52) |

**Ergebnis:** Für den Normalfall (Urlaub, offline) gibt es keinen HTTPS-Weg. Wir bauen auf http. Das Plex-Muster lohnt sich erst, wenn Godot-Web auf dem iPhone unbedingt HTTPS braucht und die Runde ohnehin Internet hat. [Ableitung]

### 2.4 PWA und WebRTC: jetzt, später oder nie?
- **Android-PWA (https) mit `ws://` zur LAN-IP: später, niedrige Priorität.**
  - Technisch geht es nach der Freigabe; private IP-Literale sind von der Mixed-Content-Sperre ausgenommen. [belegt] (Q23, Q25, Q26) Ob WebSockets wirklich eine Abfrage zeigen, ist widersprüchlich (Z1).
  - Der Nutzen ist klein, denn Android-Gäste können die APK oder den schlanken Client nehmen. [Ableitung]
- **iPhone-PWA mit `ws://`: geht nicht.**
  - Safari blockiert `ws://` von https-Seiten. [Bericht] (Q29)
  - WebKits Umsetzung des lokalen Netzzugriffs prüft WebSockets noch nicht und ist nicht gemergt. [belegt] (Q28)
- **iPhone über WebRTC mit QR-Austausch in beide Richtungen: vorerst nicht.** Das ist theoretisch möglich (Bericht 3), aber aufwendig und ohne iPhone nicht testbar. [Ableitung]
- **Jetzt (billig):** Protokollversion in der Begrüßungsnachricht und eine gekapselte Transportschicht. Damit lässt sich ein zweiter Weg später ergänzen. [Ableitung]

### 2.5 Was das für die gewünschte Mischform heißt (iPhone: Godot-Web oder schlanker Client)
- Die Wahl bleibt, aber die Reihenfolge dreht sich um: **Standard ist der schlanke Client.** Godot-Web heißt „experimentell“ und wird erst freigeschaltet, wenn es über http mit eigener Hülle und **ohne Threads** läuft. Threads brauchen Cross-Origin-Isolation (Q13), und die gibt es ohne Secure Context nicht. [Ableitung]
- **Das können wir ohne iPhone testen.** Die Secure-Context-Regeln sind in allen Browsern gleich. Startet Godot-Web über http in Chrome und Firefox auf Android mit Ton, ist die größte Hürde genommen. Offen bleiben dann nur iPhone-Eigenheiten wie Leistung und Wachhalten. [Ableitung]
- **Fehlt der Ton,** gibt es zwei Möglichkeiten: Godot-Web ohne Ton anbieten, oder in der eigenen Hülle einen Audio-Ersatz (Shim) bzw. ein angepasstes Export-Template probieren. [Ableitung, Gerätetest nötig]

---

## 3. Offene Punkte, die nur ein Gerätetest klärt

**Jetzt mit Android testbar**
1. Godot-Web 4.6 mit eigener Hülle, ohne Threads, über `http://IP:Port`: Startet es, gibt es Ton? (Chrome, Firefox, Samsung Internet) Gegenprobe mit dem Chrome-Flag aus Z3.
2. Chrome mit „Immer sichere Verbindungen“ für private Seiten: genauer Ablauf von Warnseite und „Weiter“, mit und ohne schnelles TLS-Abweisen.
3. Samsung Internet mit „Zu sicherer Verbindung wechseln“, und eine IP ohne `http://`.
4. APK-Download über http in Chrome: genauer Ablauf und Texte.
5. LocalOnlyHotspot: Kommt ein Gast mit eingeschalteten mobilen Daten auf 192.168.x.y?
6. Zweiter WebSocket-Port gegen gleichen Port in Chrome 154. Beides sollte heute gehen.

**Nur mit iPhone** (z. B. iPhone eines Mitspielers, dazu das Server-Log der TLS-Versuche; für Darstellung, Start und Ton notfalls ein Cloud-Dienst mit echten iPhones, der laut Doku auch private IPs erreicht (Q43))
1. QR-Code aus der Kamera-App führt zu Safari: Gibt es einen HTTPS-Versuch, auf welchem Port, und wie lange dauert er mit und ohne schnelles Abweisen?
2. Safari mit „Warnung bei nicht sicherer Verbindung“ und privater IP: Kommt ein „Weiter“?
3. Hält `ws://` stabil (Bericht zu iPadOS 26)? Klappt das Wiederverbinden nach Display aus und App-Wechsel?
4. Funktioniert der Ersatz fürs Wachhalten (Video-Trick) über http?
5. Godot-Web auf iPhone-Safari: Start, Ton, Leistung.
6. Grundverhalten von Chrome iOS und Brave iOS.

---

## Quellen
- Q1 https://blog.google/security/https-by-defau/ (Weiterleitung von https://security.googleblog.com/2025/10/https-by-default.html)
- Q2 https://chromium.googlesource.com/chromium/src/+/main/docs/security/ask-before-http/ask-before-http-adoption-guide.md
- Q3 https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/ssl/https_upgrades_interceptor.cc
- Q4 https://chromium.googlesource.com/chromium/src/+/main/net/base/url_util.cc
- Q5 https://blog.google/security/advancing-protection-in-chrome-on/
- Q6 https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/download/insecure_download_blocking.cc
- Q7 https://webkit.org/blog/16301/webkit-features-in-safari-18-2/
- Q8 https://lapcatsoftware.com/articles/2024/12/1.html
- Q9 https://github.com/WebKit/WebKit/blob/main/Source/WebKit/NetworkProcess/NetworkResourceLoader.cpp
- Q10 https://github.com/WebKit/WebKit/blob/main/Source/WebCore/loader/FrameLoader.cpp · https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/network/cocoa/ResourceRequestCocoa.mm
- Q11 https://github.com/mozilla-firefox/firefox/blob/main/modules/libpref/init/StaticPrefList.yaml
- Q12 https://github.com/mozilla-firefox/firefox/blob/main/dom/security/nsHTTPSOnlyUtils.cpp
- Q13 https://github.com/godotengine/godot/blob/4.6/platform/web/js/engine/features.js
- Q14 https://github.com/godotengine/godot/blob/4.6/misc/dist/html/full-size.html
- Q15 https://github.com/godotengine/godot/blob/4.6/platform/web/js/libs/library_godot_audio.js
- Q16 https://github.com/godotengine/godot-proposals/issues/10076
- Q17 https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts/features_restricted_to_secure_contexts
- Q18 https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/audioWorklet
- Q19 https://cabforum.org/working-groups/server/baseline-requirements/requirements/ (Abschnitt 4.2.2)
- Q20 https://letsencrypt.org/2025/07/01/issuing-our-first-ip-address-certificate
- Q21 https://letsencrypt.org/2026/01/15/6day-and-ip-general-availability
- Q22 https://cockpit-project.org/running/safari.html
- Q23 https://github.com/WICG/local-network-access/blob/main/explainer.md
- Q24 https://developer.chrome.com/blog/local-network-access
- Q25 https://groups.google.com/a/chromium.org/g/blink-dev/c/O6GMKt44Ups
- Q26 https://developer.chrome.com/release-notes/147
- Q27 https://www.sprinklr.com/help/articles/resolving-browser-local-network-access-restrictions-for-sprinklr-websockets/resolving-browser-local-network-access-restrictions-for-sprinklr-websockets/69fa06f8c8cbd953dd028264
- Q28 https://github.com/WebKit/WebKit/pull/75708
- Q29 https://bugs.webkit.org/show_bug.cgi?id=171934 · https://discussions.apple.com/thread/256075428
- Q30 https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy (Safari, WKWebView und SFSafariViewController brauchen keine Berechtigung fürs lokale Netz) [belegt]
- Q31 https://developer.apple.com/forums/thread/811063
- Q32 https://github.com/godotengine/godot/blob/4.6/modules/websocket/wsl_peer.cpp
- Q33 https://www.rfc-editor.org/rfc/rfc8446#section-5.1
- Q34 https://www.rfc-editor.org/rfc/rfc6797#section-8.1
- Q35 https://www.w3.org/TR/upgrade-insecure-requests/
- Q36 https://www.tp-link.com/us/blog/2586/what-is-ap-isolation-and-when-to-enable-it-/
- Q37 https://www.chromium.org/Home/chromium-security/deprecating-powerful-features-on-insecure-origins/
- Q38 https://words.filippo.io/how-plex-is-doing-https-for-all-its-users/
- Q39 https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/heads/main/Tethering/src/android/net/ip/IpServer.java (aus Bericht 2, nicht nachgeprüft)
- Q40 https://openwrt.org/docs/guide-user/base-system/dhcp · https://fritz.com/service/wissensdatenbank/dok/FRITZ-Box-7510/3565_FRITZ-Box-meldet-Der-DNS-Rebind-Schutz-hat-Ihre-Anfrage-aus-Sicherheitsgrunden-abgewiesen/
- Q41 https://docs.godotengine.org/en/stable/tutorials/platform/web/customizing_html5_shell.html
- Q42 https://github.com/richtr/NoSleep.js
- Q43 https://www.browserstack.com/support/faq/local-testing/local-exceptions/i-face-issues-while-testing-localhost-urls-or-private-servers-in-safari-on-macos-os-x-and-ios
- Q45 https://forums.androidcentral.com/threads/samsung-internet-browser-how-to-access-local-ip-addresses.1012123/
- Q46 https://github.com/brave/brave-core/blob/master/chromium_src/chrome/browser/ssl/https_upgrades_interceptor.cc
- Q47 https://chromium.googlesource.com/chromium/src/+/main/ios/components/security_interstitials/https_only_mode/feature.cc
- Q48 https://duckduckgo.com/duckduckgo-help-pages/privacy/smarter-encryption
- Q49 https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/automatichttpsdefault
- Q50 https://developer.apple.com/forums/thread/706795
- Q52 https://issues.chromium.org/issues/40616382
- Q53 https://www.rfc-editor.org/rfc/rfc6455