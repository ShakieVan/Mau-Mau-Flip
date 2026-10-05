**Echtes HTTPS für den lokalen Host: Optionen, Bedingungen, Fazit (Stand 04.10.2026)**

## Kurzfazit

- Ein vertrauenswürdiges Zertifikat für eine private IP gibt es nicht. Die Vermutung des Nutzers stimmt. [belegt] https://cabforum.org/working-groups/server/baseline-requirements/requirements/ (Abschnitt 4.2.2)
- Der einzige realistische Weg zu echtem HTTPS ist das Plex-Muster: eine eigene öffentliche Domain, deren Namen auf die private IP zeigen, und je Gerät ein eigenes Let's-Encrypt-Zertifikat über DNS-01. Das geht nur, wenn der Gast den Namen über das Internet auflösen kann. Im Kernszenario (LocalOnlyHotspot ohne Internet) klappt das nicht. [Ableitung, Belege unten]
- Plain HTTP über die IP ist heute in den Browsern nicht blockiert. Das Problem ist der fehlende Secure Context: Der Godot-4.6-Web-Export startet ohne ihn gar nicht. Der schlanke HTML/TS-Client muss deshalb voll über HTTP funktionieren. Godot-Web bleibt eine Option für Fälle, in denen HTTPS verfügbar ist. [belegt/Ableitung, unten]

## 0. Was die Ausgangslage tatsächlich ist

- **Chrome 154 (Oktober 2026):** „Always Use Secure Connections" ist standardmäßig nur für öffentliche Seiten aktiv. Private Seiten (lokale IPs, einteilige Hostnamen) warnen nicht. Google begründet das ausdrücklich: private Namen sind nicht eindeutig, deshalb sind Zertifikate dafür „complicated". [belegt] https://blog.google/security/https-by-defau/ (Weiterleitung von https://security.googleblog.com/2025/10/https-by-default.html)
- **Safari 18.2 (iOS):** Safari versucht bei Links zuerst HTTPS und fällt nur zurück, wenn das scheitert. Optional gibt es eine Einstellung, die vor dem HTTP-Fallback warnt. [belegt] https://webkit.org/blog/16301/webkit-features-in-safari-18-2/
- **Safari-Details:**
  - Getippte `http://`-URLs werden nicht hochgestuft. [Bericht] https://lapcatsoftware.com/articles/2024/12/1.html
  - Mit eingeschalteter Warn-Einstellung blockierte Safari `http://localhost` ohne Option zum Weiterladen. Ob das auch für private IPs gilt: [Gerätetest nötig].
  - Ob ein Link aus der iOS-Kamera (QR-Code) als „Link" zählt und einen HTTPS-Versuch auslöst: [Gerätetest nötig].
- **Praktischer Tipp:** Safari könnte `https://IP:Port` auf dem HTTP-Port versuchen. Der GDScript-Server sollte daher ein TLS-ClientHello (erstes Byte 0x16) erkennen und die Verbindung sofort schließen. Dann ist der Fallback schnell. [Ableitung]
- **Ohne Secure Context fehlen:** Service Worker, Screen Wake Lock, Web Crypto (`crypto.subtle`), Async Clipboard, Web Share, Notifications. [belegt] https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts/features_restricted_to_secure_contexts
- **AudioWorklet** funktioniert nur im Secure Context. [belegt] https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/audioWorklet
- **Wichtig für den Mischbetrieb:**
  - Godot 4.6 prüft den Secure Context ohne Bedingung, also auch bei Single-Thread-Exporten: `if (!Features.isSecureContext()) missing.push('Secure Context ...')`. [belegt] https://raw.githubusercontent.com/godotengine/godot/4.6/platform/web/js/engine/features.js
  - Die Standard-HTML-Shell startet die Engine dann nicht. [belegt] https://raw.githubusercontent.com/godotengine/godot/4.6/misc/dist/html/full-size.html
  - Wer die Prüfung herauspatcht, bekommt in Firefox ein Spiel ohne Ton. In Chromium scheiterte das Laden. Das Issue ist offen. [Bericht] https://github.com/godotengine/godot-proposals/issues/10076
  - Folge: Godot-Web über `http://IP` geht praktisch nicht. Mit einer eigenen Shell und ohne Ton wäre es vielleicht machbar. [Ableitung + Gerätetest nötig]

## 1. Let's-Encrypt-Zertifikate für IP-Adressen

- Seit 15.01.2026 allgemein verfügbar. Nur mit dem Profil „shortlived", gültig 160 Stunden. [belegt] https://letsencrypt.org/2026/01/15/6day-and-ip-general-availability
- Nur die Prüfverfahren http-01 und tls-alpn-01 sind erlaubt, kein DNS-01. Die CA muss die IP also öffentlich erreichen. [belegt] https://letsencrypt.org/2025/07/01/issuing-our-first-ip-address-certificate
- Die Baseline Requirements 2.3.1 (Abschnitt 4.2.2) sagen wörtlich: „CAs SHALL NOT issue Certificates containing Internal Names or Reserved IP Addresses". Als „Reserved" gilt alles im IANA-Special-Registry, dazu gehören auch die privaten Bereiche. [belegt] https://cabforum.org/working-groups/server/baseline-requirements/requirements/
- **Urteil:** Für 192.168/10/172.16–31 unmöglich, auch gegen Geld bei keiner öffentlichen CA.

## 2. Öffentliche Domain, deren DNS auf private IPs zeigt (Plex-Muster)

### 2a. Ein gemeinsamer Wildcard-Schlüssel in der App: Nein

- Wird ein Schlüssel kompromittiert, muss die CA das Zertifikat binnen 24 Stunden widerrufen (BR 4.9.1.1). [belegt] https://cabforum.org/working-groups/server/baseline-requirements/requirements/
- Let's Encrypt wertet einen in einer App mitgelieferten Schlüssel ausdrücklich als Kompromittierung. [belegt] https://letsencrypt.org/docs/certificates-for-localhost/
- Beispiele:
  - Blizzard (localbattle.net), EA, Microsoft: widerrufen. [belegt] https://www.feistyduck.com/newsletter/issue_36_private_keys_in_software
  - beA der Bundesrechtsanwaltskammer: Nach dem Widerruf wurde eine selbstsignierte Root-CA mit ausgeliefert, was MITM für alle Domains ermöglichte. [belegt] gleiche Quelle
  - Cisco und Spotify. [belegt] https://www.feistyduck.com/newsletter/issue_29_cisco_and_spotify_ship_private_keys_in_applications
  - sslip.io veröffentlichte 2015 kurz den Wildcard-Schlüssel; das Zertifikat wurde schnell widerrufen. [belegt] https://nip.io/
- „anyip" veröffentlicht den Wildcard-Schlüssel nach eigener Aussage „by design". Darauf sollte man nicht bauen. [belegt] https://github.com/taptap/anyip
- **Sonderfall kurzlebige Zertifikate:** Laut BR „MAY" die CA sie widerrufen, muss es aber nicht. [belegt, BR 4.9.1.1] Ein öffentlicher Schlüssel erlaubt trotzdem jedem im selben WLAN, sich dazwischenzuschalten. Damit wäre HTTPS sinnlos. [Ableitung]

### 2b. Je Gerät ein eigenes Zertifikat: technisch sauber

- **Vorbild Plex:** Jeder Server bekommt ein Wildcard-Zertifikat `*.HASH.plex.direct` (DigiCert-Partnerschaft). Namen wie `1-2-3-4.HASH.plex.direct` lösen zu 1.2.3.4 auf. Der Schlüssel taugt nur für den eigenen Hash. [belegt] https://words.filippo.io/how-plex-is-doing-https-for-all-its-users/
- **Hobby-Vorbild tlsmy.net:** Wildcard `*.accountid.tlsmy.net` per Let's Encrypt über DNS-01. Der Schlüssel verlässt das Gerät nie. [belegt] https://github.com/supersat/tlsmy.net

**Was wir bräuchten:**

1. **Eine Domain:** etwa 10 USD pro Jahr (.com bei Cloudflare zum Selbstkostenpreis, 10,44 USD). [Bericht] https://startupowl.com/reviews/cloudflare-registrar
2. **DNS, zwei Varianten:**
   - **B1 (billig):** Cloudflare-DNS (kostenlos) plus ein Worker. Der Host setzt beim Spielstart `<geräte-id>.domain` als A-Record auf seine LAN-IP. Der Worker darf nur private IPs akzeptieren, damit kein Phishing möglich ist. Der Host braucht dafür beim Spielstart kurz Internet. Worker-Free-Tier: 100.000 Anfragen pro Tag. [Bericht] https://github.com/cloudflare/cloudflare-docs/blob/production/src/content/docs/workers/platform/limits.mdx [Ableitung für das Design]
   - **B2 (robuster):** IP-kodierte Namen `192-168-43-1.<id>.domain` über einen eigenen synthetisierenden Nameserver, etwa sslip.io selbst gehostet mit `-public=false` nur für private IPs ([belegt] https://github.com/cunnie/sslip.io) oder anyip mit `-only-private`. Der Host braucht zur Spielzeit kein Internet. Dafür braucht es einen kleinen Server mit öffentlicher IP und Port 53 (wenige Euro im Monat). [Ableitung]
   - Die NS-Delegation an nip.io/sslip.io ist zwar kostenlos, unterstützt aber nur HTTP-01. Für private IPs ist das unbrauchbar. [belegt] https://nip.io/ + [Ableitung]
3. **Ein Relay für die DNS-01-TXT-Records:** Es darf nur Einträge für die eigene Subdomain setzen und muss den Geräteschlüssel prüfen. [Ableitung, Muster wie tlsmy.net]
4. **ACME in der App:**
   - Godots `Crypto` kann keinen CSR erzeugen. [belegt] https://docs.godotengine.org/en/stable/classes/class_crypto.html
   - Also bräuchte es ein Android-Plugin (Kotlin) oder das Relay müsste den Schlüssel erzeugen, was schlechter ist. [Ableitung]
   - Den TLS-Server kann Godot: `StreamPeerTLS.accept_stream(stream, TLSOptions.server(key, cert))` mit vollständiger Kette. [belegt] https://docs.godotengine.org/en/stable/classes/class_streampeertls.html, https://docs.godotengine.org/en/stable/classes/class_tlsoptions.html
5. **Erneuerung:**
   - Laufzeiten: heute 90 Tage, ab 10.02.2027 64 Tage, ab 16.02.2028 45 Tage. [belegt] https://linuxiac.com/lets-encrypt-to-cut-certificate-lifetimes-to-45-days-by-2028/
   - Der Host muss also alle paar Wochen online sein, zum Beispiel vor dem Urlaub. [Ableitung]
   - Limits: 50 neue Zertifikate pro registrierter Domain und Woche; ARI-Erneuerungen sind von allen Limits ausgenommen. [belegt] https://letsencrypt.org/docs/rate-limits/
   - Ein Eintrag in die Public Suffix List nur zum Umgehen der Limits wird abgelehnt. [Bericht] https://github.com/publicsuffix/list/wiki/Guidelines/ebf4b8f643f8a5c5e09e4d4dbd03855346ffada8
6. **Prüfung beim Gast ohne Online-Abfrage:** Let's Encrypt hat OCSP am 06.08.2025 abgeschaltet und nutzt nur noch CRLs. Der Gast muss bei der Prüfung nichts online nachfragen. [belegt] https://letsencrypt.org/2025/08/06/ocsp-service-has-reached-end-of-life + [Ableitung]
7. **Datenschutz:** Zertifikatsnamen landen öffentlich in den Certificate-Transparency-Logs. Geräte-IDs deshalb zufällig wählen. [belegt] https://tailscale.com/kb/1153/enabling-https
8. **Chrome Local Network Access:** Eine Seite, die von einer privaten IP geladen wird, ist ein „local"-Kontext. local→local löst keinen Berechtigungsdialog aus. [belegt] https://github.com/WICG/local-network-access/blob/main/explainer.md

**Kosten und Aufwand:** B1 etwa 10 Euro pro Jahr, B2 zusätzlich etwa 3–6 Euro pro Monat für den Server. Der Entwicklungs- und Betriebsaufwand ist hoch: Relay, ACME-Plugin, Missbrauchsschutz. [Ableitung]

### 2c. Der Knackpunkt: Der Gast muss den Namen auflösen können

- **Im LocalOnlyHotspot gibt es keine Namensauflösung:**
  - Der DHCP-Server im Android-Hotspot gibt den Host selbst als DNS-Server aus (`addr /* dnsServer */`). [belegt] https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/heads/main/Tethering/src/android/net/ip/IpServer.java
  - DNS-Weiterleitungen werden nur gesetzt, wenn es einen Upstream gibt. Eine Upstream-Verbindung wird nur für echtes Tethering (STATE_TETHERED) angefordert, nicht für LOCAL_ONLY. [belegt Quelltext] https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/heads/main/Tethering/src/com/android/networkstack/tethering/Tethering.java
  - Folge: Öffentliche Namen werden im LocalOnlyHotspot nicht aufgelöst. [Ableitung]
- **Eigener DNS-Server in der App:** Ports unter 1024 brauchen CAP_NET_BIND_SERVICE ([belegt] https://man7.org/linux/man-pages/man7/ip.7.html). Normale Apps haben das nicht, und Port 53 auf der Hotspot-Schnittstelle belegt ohnehin das System-dnsmasq. Ohne Root geht es also nicht. [Ableitung]
- **Normaler Hotspot mit mobilen Daten des Hosts funktioniert vermutlich:** dnsmasq leitet weiter. Das Android-dnsmasq läuft ohne `--stop-dns-rebind`. [belegt Quelltext] https://android.googlesource.com/platform/system/netd/+/refs/heads/main/server/TetherController.cpp → Antworten mit privaten IPs kommen durch. [Ableitung] Allerdings kann die App diesen Hotspot nicht selbst einschalten; das muss der Nutzer in den Einstellungen tun. [Ableitung]
- **Gemeinsames WLAN mit Internet funktioniert, solange der Router keinen Rebind-Schutz hat:**
  - Die FRITZ!Box hat einen DNS-Rebind-Schutz. Ausnahmen pro Hostname kann nur der Admin eintragen. [belegt] https://fritz.com/service/wissensdatenbank/dok/FRITZ-Box-7510/3565_FRITZ-Box-meldet-Der-DNS-Rebind-Schutz-hat-Ihre-Anfrage-aus-Sicherheitsgrunden-abgewiesen/
  - OpenWrt hat `rebind_protection=1` als Standard. [belegt] https://openwrt.org/docs/guide-user/base-system/dhcp
  - Plex-Nutzer müssen dafür Ausnahmen einrichten. [belegt] https://words.filippo.io/how-plex-is-doing-https-for-all-its-users/
  - In Ferienwohnungen ist das ein häufiger Fehlerfall. [Ableitung]
- **Gast mit eigenen mobilen Daten im LocalOnlyHotspot:** Das hängt vom Betriebssystem ab. Bleibt das WLAN ohne Internet das Standardnetz, scheitert DNS. Wird Mobilfunk Standard, geht DNS über Mobilfunk; der Verkehr ins 192.168.x-Netz muss dann aber übers WLAN laufen. Es gibt Berichte, dass lokale Verbindungen bei aktivem Mobilfunk scheitern. [Bericht] https://developer.apple.com/forums/thread/706795 → [Gerätetest nötig], ebenso für Private DNS, iCloud Private Relay und filternde Resolver.

## 3. Eigene CA oder selbstsigniertes Zertifikat

- **Chrome auf Android:** Warnseite, die man durchklicken kann. Ob wss:// danach funktioniert: [Gerätetest nötig].
- **iOS:**
  - Das Standard-WebSocket-Framework von Safari unterstützt wss mit selbstsignierten oder ungültigen Zertifikaten nicht. Abhilfe laut Cockpit: ein gültiges Zertifikat oder das experimentelle Feature „NSURLSession WebSocket". [belegt] https://cockpit-project.org/running/safari.html
  - HTTPS wird akzeptiert, wss nicht. [Bericht] https://www.hotelexistence.ca/ios-safaris-websockets-implementation-doesnt-work-with-self-signed-certs/
  - Es funktioniert nur mit einer eigenen CA, die installiert und auf „volles Vertrauen" gestellt ist. [Bericht] https://gist.github.com/apankrat/612dde3d7f01c4713c9579b0a94d9547
- **Profilinstallation auf iOS:** Profil laden, in den Einstellungen installieren, dann unter Einstellungen > Allgemein > Info > Zertifikatsvertrauenseinstellungen volles Vertrauen einschalten. Apple richtet das an Administratoren. [belegt] https://support.apple.com/en-ca/102390
- **Risiko:** Eine Root-CA auf fremden Handys ist ein Vertrauensanker für alles. Liegt der CA-Schlüssel in der App, ist das der beA-Fall. [belegt Feisty Duck, s. o.]
- **Urteil:** Für Gäste nicht zumutbar. Höchstens als Nerd-Option für eigene Geräte. [Ableitung]

## 4. Sonstiges

- **mDNS .local:**
  - Android 12+ löst .local seit dem Modul-Update vom November 2021 auf, aber nicht über Mobilfunk oder VPN. [Bericht] https://www.esper.io/blog/android-dessert-bites-26-mdns-local-47912385
  - Für .local gibt es kein öffentliches Zertifikat (Internal Name, BR 4.2.2) [belegt], und .local ist kein Secure Context [belegt] https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts
  - Bringt also nur eine schönere URL.
- **Chrome-Flag `unsafely-treat-insecure-origin-as-secure`:** Existiert. Auf Android braucht die Kommandozeilen-Variante Root. [belegt] https://www.chromium.org/Home/chromium-security/deprecating-powerful-features-on-insecure-origins/ Safari hat nichts Vergleichbares. Für Gäste unrealistisch. [Ableitung]
- **Tailscale/MagicDNS:** Zertifikate kommen von Let's Encrypt über DNS-01 ([belegt] https://tailscale.com/kb/1153/enabling-https). Die Namen sind aber nur im Tailnet erreichbar, Gäste bräuchten App und Konto. → Nein. [Ableitung]
- **Öffentlich gehostete HTTPS-PWA mit ws:// zur LAN-IP:**
  - Chrome nimmt Anfragen an private IP-Literale nach einem Berechtigungsdialog vom Mixed-Content-Block aus. [belegt] https://developer.chrome.com/blog/local-network-access
  - Laut Explainer gilt das auch für WebSockets. [belegt] https://github.com/WICG/local-network-access/blob/main/explainer.md
  - Für Safari ist kein Gegenstück bekannt. [Ableitung, Gerätetest nötig]
  - WebRTC-DataChannel mit QR-Signalisierung in beide Richtungen wäre theoretisch offline-fähig, aber sehr umständlich. [Ableitung]

## Fazit

- **Gibt es einen realistischen HTTPS-Weg?** Ja, aber nur nach dem Plex-Muster: eigene Domain, Gerätezertifikat über DNS-01, Variante B1 für etwa 10 Euro im Jahr. Und nur, wenn alle drei Bedingungen gelten:
  1. Gäste haben Internet-DNS: WLAN mit Internet ohne Rebind-Schutz, oder normaler Hotspot mit den mobilen Daten des Hosts, eventuell die eigenen mobilen Daten des Gastes [Gerätetest nötig].
  2. Der Host war innerhalb der Zertifikatslaufzeit online.
  3. Bei B1 ist der Host beim Spielstart kurz online.
- Im typischen Offline-Fall mit LocalOnlyHotspot gibt es kein browser-vertrauenswürdiges HTTPS. [Ableitung aus den Belegen oben]
- **Empfehlung:**
  - Basis bleibt `http://IP:Port` per QR-Code.
  - Der schlanke Client ist der Pflichtpfad über HTTP: kein Service Worker, kein `crypto.subtle`, Ersatz für Wake Lock.
  - Godot-Web nur anbieten, wenn ein Secure Context vorhanden ist, oder eine gepatchte Shell testen und Tonverlust in Kauf nehmen.
  - Optional später als Stufe 2: Die per HTTP geladene Seite prüft, ob `https://<ip>.<id>.domain` erreichbar ist, und schaltet dann auf HTTPS und Godot-Web um. Bis dahin kostet das nichts. [Ableitung]

Ich habe keine Projektdateien geändert. Im Scratchpad liegen nur heruntergeladene Quelltexte zur Prüfung (IpServer.java, Tethering.java, TetherController.cpp, br.html/br.txt).