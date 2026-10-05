# Recherche: APK offline weitergeben und lokales Netz im Urlaub (Mau-Mau Flip)

Stand 04.10.2026. Ich habe nur gelesen. Projektdateien sind unverändert, die Hilfsdateien im Scratchpad sind wieder gelöscht.

Kennzeichnung: **[belegt]** = offizielle Doku, **[Quellcode]** = AOSP- oder Godot-Quelltext gelesen, **[Bericht]** = Presse oder Foren, **[Ableitung]** = daraus geschlossen, **[Gerätetest]** = offen und nur am Gerät zu klären. Die Zahlen in eckigen Klammern verweisen auf die Quellenliste am Ende.

## Kurzfazit

1. **Neuer Stolperstein: Android-Entwicklerverifizierung.** Seit 30.09.2026 gilt sie in Brasilien, Indonesien, Singapur und Thailand, **2027 weltweit** [1][3]. Danach lassen sich nur noch registrierte Apps installieren und aktualisieren, egal auf welchem Weg die APK kommt. Das gilt auch für Updates [2].
   - Ausnahmen: die „Advanced Flow“-Freischaltung (einmalig mit 24 h Wartezeit) und ADB [2][5].
   - Offline droht im ungünstigsten Fall ein Abbruch, weil die Prüfung Netz braucht [7][8].
   - Folge: Mau-Mau Flip früh registrieren. Am besten installieren alle die App zu Hause mit Internet. Die Offline-Weitergabe bleibt Notlösung.
2. **Beste APK-Wege:**
   - Teilen-Menü → **Quick Share** (offline, schnell, ohne gemeinsames WLAN) [10].
   - **Eingebauter HTTP-Server** mit QR-Link, der zugleich den Browser-Client ausliefert.
   - **Bluetooth taugt nicht.** AOSP nimmt `.apk` per Bluetooth gar nicht an [13].
3. **Updates nach Fremdweg funktionieren.** Bedingung: gleicher Paketname, gleicher Signaturschlüssel und eine höhere versionCode [15].
4. **Netz:** Hotel-WLAN hat oft Client-Isolation [37][38]. Dann hilft nur ein Netz vom Host-Handy, am bequemsten das **LocalOnlyHotspot** (LOHS):
   - Die App liest SSID und Passwort aus und zeigt sie als WLAN-QR [41].
   - Es scheitert, solange das normale Tethering läuft (Ausnahme: Gerät kann mehrere Hotspots) [43].
5. **iPhone im Netz ohne Internet:**
   - Verkehr ins eigene Subnetz läuft immer über WLAN [53].
   - Ein manuell beigetretenes WLAN bleibt nur bis zum Ruhezustand. Beim automatischen Wiederbeitritt verlässt iOS ein WLAN ohne Internet sofort wieder [51].
   - Folge: iPhone-Bildschirm anlassen und Wiederverbinden einbauen.
6. **Nebenbefund:** Ein Godot-4-Web-Export startet nicht von `http://192.168.x.x`, weil er einen „Secure Context“ verlangt [61][62]. Der Browser-Client muss also schlankes HTML/JS werden, oder man patcht diese Prüfung heraus.

---

## Vorab: Android-Entwicklerverifizierung (betrifft alle Wege)

- **Zeitplan:** seit 30.09.2026 in den vier Pilotländern, 2027 weltweit. Gilt für zertifizierte Geräte ab Android 7, ausgeliefert über Play-Dienste [1][2][3]. **[belegt]**
- **Was registriert wird:** Paketname plus Signaturschlüssel [3]. **[belegt]**
- **Konto für Hobbyisten („Limited distribution“):**
  - Kostenlos, ohne Ausweis, aber **höchstens 20 Geräte** [4].
  - Jedes Gerät erzeugt per QR oder Link einen Code, den du in der Konsole einträgst. Links verfallen nach 7 Tagen.
  - Nicht freigeschaltete Geräte können weder installieren noch aktualisieren [4]. **[belegt]**
- **Volles Konto:** einmalig 25 USD, mit Ausweisprüfung [68]. **[belegt]**
- **Advanced Flow für Nutzer:**
  - Entwickleroptionen → „Apps von nicht verifizierten Entwicklern zulassen“ → Neustart → **24 h warten** → bestätigen → 7 Tage oder dauerhaft.
  - Danach kommt pro Installation eine Warnung mit „Trotzdem installieren“ [2][5][6].
  - Ohne diese Freischaltung scheitern auch Updates nicht registrierter Apps [2]. **[belegt]**
- **Offline:**
  - Google nennt Netz „im ungünstigsten Fall“ nötig. Es gibt einen Cache *beliebter* Apps und „Pre-Auth-Tokens“ von Stores [7].
  - Im SDK steht `DEVELOPER_VERIFICATION_FAILED_REASON_NETWORK_UNAVAILABLE` [8].
  - Laut inoffizieller Analyse darf der Nutzer bei einem Netzfehler je nach Richtlinie eventuell übergehen [9]. **[Bericht, offen]**
  - Eine kleine Hobby-App liegt sicher nicht im Cache. **[Ableitung]**
- **Für dich:** Deutschland ist 2026 noch nicht betroffen. Für 2027 brauchst du einen Plan:
  - Registrieren: volles Konto, oder Limited, wenn 20 Geräte reichen.
  - Die Offline-Installation im Flugmodus testen, sobald die Regel hier gilt. **[Gerätetest]**

---

## Teil A – APK-Weitergabe

### Überblick

| Weg | Offline | Empfänger braucht | Aufwand Godot | Bewertung |
|---|---|---|---|---|
| Teilen-Menü → Quick Share | ja (Bluetooth + WLAN direkt) [10][11] | Quick Share sichtbar „Alle, 10 Min.“, Datei-App darf installieren | klein (Java-Helfer, FileProvider) | **empfohlen** |
| Teilen-Menü → Bluetooth | ja | – | gleich | **unbrauchbar**: AOSP nimmt keine APK an [13] |
| HTTP-Server + QR | ja, im gemeinsamen Netz | Browser; „Unbekannte Apps“ für den Browser | mittel | **empfohlen** (liefert auch den Web-Client) |
| Files by Google → Apps → Teilen | ja | wie Quick Share | null (Anleitung) | Notlösung ohne Code [12] |
| Wi-Fi Direct / Nearby Connections | ja | **App muss schon installiert sein** | hoch | für den APK-Transport sinnlos |

### A1 Teilen-Menü (ACTION_SEND der eigenen APK)

**Quick Share**
- Läuft ab Android 6. Findet Geräte per Bluetooth und überträgt direkt per WLAN, **ohne Internet** [10][11]. **[belegt]**
- Empfangene Dateien landen in Downloads/Quick Share [10]. Für Fremde muss der Empfänger „Alle für 10 Minuten“ wählen [10]. **[belegt]**
- Quick Share überträgt beliebige Dateien [67]. **[Bericht]**

**Eigene App-Teilen-Funktion?**
- Die Play-Store-Funktion „Apps teilen“ ist **seit März 2025 abgeschaltet** [12]. **[belegt]**
- Als Ersatz nennt 9to5Google *Files by Google* → Kategorien → Apps → ⋮ → Teilen [12]. **[Bericht]**
- Ob dort auch nicht aus dem Play Store installierte Apps erscheinen: **[Gerätetest]**.

**Bluetooth**
- Die Annahmeliste in AOSP (`ACCEPTABLE_SHARE_INBOUND_TYPES`) enthält Bilder, Audio, Video, Texte, PDF, Office und ZIP, aber **kein** `application/vnd.android.package-archive` [13]. **[Quellcode]**
- Hersteller wie Samsung könnten abweichen. **[Gerätetest]**

**Umsetzung in Godot**
- Draw2Race nutzt schon Java-Klassen im Gradle-Build plus `JavaClassWrapper`. Ab Godot 4.4 liefert `Engine.get_singleton("AndroidRuntime")` Activity und Context [26]. **[belegt]**
- Der FileProvider der Godot-Bibliothek (Kennung `<paket>.fileprovider`) gibt nur `files/`, den externen Speicher und `external-files` frei. **[lokal geprüft: `res/xml/godot_provider_paths.xml` in Draw2Races `godot-lib.template_release.aar`]**
- `base.apk` liegt unter `/data/app/…` und ist darüber **nicht** erreichbar. Lösung: vor dem Teilen nach `files/share/MauMauFlip-x.y.z.apk` kopieren. Dann `FileProvider.getUriForFile`, `ACTION_SEND` mit Typ `application/vnd.android.package-archive`, Lesefreigabe für die URI und `createChooser` [29]. **[Ableitung]**

**Schritte beim Empfänger**
- Datei antippen.
- Android 8+ fragt einmal je Quell-App (Dateien-App bzw. Browser) nach „Unbekannte Apps installieren“ [14]. **[belegt]**
- Play Protect kann „Unbekannte App“ melden oder einen Scan empfehlen. Bei den bekannten Fällen gibt es „Weitere Details“ → „Trotzdem installieren“ [19][20]. Der Code-Scan schickt Teile der App an Google [19], also bleibt das Verhalten offline offen. **[Bericht, Gerätetest]**

**Einschränkungen nach Android-Version**
- Android 14 blockiert Apps mit targetSdk < 23 [16]. Für Godot irrelevant.
- Android 13 bis 15 sperren für so installierte Apps „eingeschränkte Einstellungen“ wie Bedienungshilfen [17]. Die braucht Mau-Mau Flip nicht. **[belegt/Bericht]**
- Android 16 mit „Erweitertem Schutz“ (Advanced Protection) verbietet Installationen außerhalb von Play **ganz**, auch Updates solcher Apps [18]. Für Nutzer, die das eingeschaltet haben, gibt es keinen Weg. **[Bericht]**

### A2 Eingebauter HTTP-Server + QR (`http://IP:Port/`)

**Technik**
- Godot hat keinen HTTP-Server. Machbar ist `TCPServer` plus eigenes kleines HTTP für die Seite und die APK in Blöcken.
- WebSocket gelingt mit `WebSocketPeer.accept_stream()` auf einer angenommenen TCP-Verbindung [30]. **[belegt]**
- Weil `accept_stream` den rohen Strom erwartet: HTTP und WebSocket am einfachsten auf **zwei Ports**. **[Ableitung]**
- Ports unter 1024 darf eine App nicht öffnen, also z. B. 8080 [66]. **[Bericht]**
- Ab targetSdk 37 braucht die App `ACCESS_LOCAL_NETWORK` auch für **eingehende** Verbindungen [60]. **[belegt]**

**Browser-Warnungen (Chrome Android)**
- Für APKs war 2024 geplant, die Warnung „Datei könnte schädlich sein“ nur noch bei abgeschaltetem Play Protect zu zeigen [21]. **[Bericht]**
- Seit Chrome 117 warnt Chrome bei „riskanten“ Downloads über HTTP; Fortfahren bleibt möglich [22]. **[Bericht]**
- „HTTPS als Standard“ ab Chrome 154 (Oktober 2026) warnt **nur bei öffentlichen** Seiten; private IPs sind ausgenommen [23][24]. **[belegt]**
- Ob auch die Download-Warnung private IPs ausnimmt, ist nicht dokumentiert. **[Gerätetest]**

**Kein HTTPS**
- Für `192.168.x.x` gibt es kein vertrauenswürdiges Zertifikat [23].
- Damit ist die Seite **kein Secure Context**: kein Wake Lock, keine Service Worker [55][56]. **[belegt]**

**Sicherheit**
- Ein zufälliges Token im Pfad (z. B. `/j/K7Q2/`) hält Fremde im Hotel-WLAN fern.
- Der Server läuft nur, solange die Lobby offen ist. **[Ableitung]**

**Übertragungsdauer**
- Rund 10–30 s für 50 MB über 2,4-GHz-LOHS. Mehrere gleichzeitige Downloads teilen sich die Bandbreite. **[Schätzung]**

### A3 Wi-Fi Direct, Nearby Connections, Bluetooth direkt

- Für die **erste** Weitergabe nutzlos: Alle drei setzen die App auf beiden Seiten voraus.
- **Wi-Fi Direct:** braucht `NEARBY_WIFI_DEVICES` bzw. Standort plus eingeschalteten Standortmodus [31]. iPhones können kein Wi-Fi Direct [34]. **[belegt/Bericht]**
- **Nearby Connections:** offline über Bluetooth, BLE und WLAN, auf Android abhängig von Play-Diensten. Das native iOS-SDK hilft Browser-Spielern nicht [32][33]. **[belegt]**

### A4 Installierte APK als Quelle

- `ApplicationInfo.sourceDir` ist der „volle Pfad zur Basis-APK“. `splitSourceDirs` ist `null`, wenn keine Splits installiert sind [27]. **[Quellcode]**
- Ein selbst exportiertes, per Datei installiertes Godot-APK hat keine Splits. Erst ein AAB über Play erzeugt welche. **[Ableitung]**
- Android installiert die Datei unverändert. Die geteilte APK ist also **bitgleich und gleich signiert** wie die laufende Version. Vorteil: Alle bekommen genau die Host-Version, was zum Netzprotokoll passt. **[Ableitung; einmal per SHA-256 prüfen = Gerätetest]**
- **Größe:**
  - Gradle-Builds können aufblähen: 340 MB statt 106 MB in Godot 4.4.0 [28]. **[Bericht]**
  - Deine Draw2Race-APKs liegen bei **172–345 MB** (lokal gesehen).
  - Für die Weitergabe also den Release-Export schlank halten (nur arm64, keine Debug-Symbole) und die echte Größe messen.

### A5 Spätere Updates über den In-App-Updater

- **Ja, funktioniert:** Android vergleicht beim Update nur die Zertifikate [15]. **[belegt]**
- Bedingungen:
  - Gleicher Paketname und Schlüssel, versionCode höher. Ein Downgrade scheitert.
  - Die geteilte Host-Version darf also nicht älter sein als die beim Empfänger.
  - Release- und Beta-Repo brauchen bewusst gleiche (oder bewusst getrennte) Paketname-Schlüssel-Paare.
- **„Update-Hoheit“ (Android 14+):** Nur ein Installer mit der privilegierten Berechtigung `ENFORCE_UPDATE_OWNERSHIP` kann sie beanspruchen, etwa der Play Store [25]. Dateien-App oder Chrome tun das nicht, dein Updater bleibt frei. **[belegt]**
- **„Unbekannte Apps“:** Mau-Mau Flip braucht diese Freigabe selbst, wie in Draw2Race über `canRequestPackageInstalls` [14].
- **2027:** Die Verifizierung prüft auch Updates [2].
- **Idee „Update vom Host“:** Stellt die Lobby eine ältere Client-Version fest, lädt die App die APK vom Host-Server. Vorhandene Prüfung wie in Draw2Race: Paket, Version und Signatur über `getPackageArchiveInfo`. Dann installieren, ganz ohne Internet. **[Ableitung]**

---

## Teil B – Netz im Urlaub

### B1 Client-Isolation (AP-Isolation)

- **Verbreitung:** in fast jedem professionellen Access Point eingebaut, oft Standard in Hotel-, Gast- und Campus-Netzen [37][38][39]. Verlässliche Statistiken gibt es nicht. **[Bericht]**
- **Erkennen:**
  - App-Clients: UDP-Rundruf bekommt keine Antwort *und* TCP zur Host-IP läuft trotz gleichem Subnetz in einen Timeout.
  - Browser: Der Link-QR lädt nicht.
  - Teilweise Isolation kommt vor: Rundrufe gefiltert, Unicast frei. Darum zusätzlich direkt verbinden und Gateway-Probe nutzen (wie Draw2Race). **[Ableitung]**
  - Der Host kann Isolation allein nicht feststellen.

### B2 Netz vom Host: normaler Hotspot oder LOHS

| | Normaler Hotspot (Tethering) | LocalOnlyHotspot (API 26+) |
|---|---|---|
| Start | Nutzer in den Schnelleinstellungen | App, nur **im Vordergrund**, sonst `ERROR_INCOMPATIBLE_MODE` [43] **[Quellcode]** |
| Zugangsdaten für QR | **nicht** auslesbar: `getSoftApConfiguration()` ist System-API mit `NETWORK_SETTINGS` [41]. System-QR nutzen (Pixel, Samsung) [46] | `reservation.getSoftApConfiguration()` (API 30+); `getWifiConfiguration()` (26–29) liefert bei WPA3 eventuell `null` [41] **[Quellcode]** |
| SSID/Passwort | vom Nutzer gesetzt | Muster `AndroidShare_<Zufall>`; 15 Zeichen aus `2-9a-z` (keine Verwechsler); WPA3-SAE-Transition, sonst WPA2 [42] **[Quellcode]** |
| Band/Abschalten | je nach Einstellung, eventuell 6 GHz | Standard 2,4 GHz; **automatisches Abschalten aus** [42] **[Quellcode]** |
| Internet für Gäste | ja, über die Daten des Hosts | **nein** [40] **[belegt]** |
| Gleichzeitig mit anderem | – | scheitert, solange Tethering läuft (außer bei Geräten mit mehreren Hotspots) [43]. Mehrere Apps teilen sich einen LOHS. Nutzer und System können ihn beenden (`onStopped`) [41] |
| Berechtigung | keine | `NEARBY_WIFI_DEVICES` (13+), davor `ACCESS_FINE_LOCATION` [40] |
| Subnetz | seit Android 11 zufälliges /24 aus 192.168.0.0/16; Code erlaubt künftig andere private Bereiche [44][45] | wie Tethering **[Ableitung]** → eigene IP immer über die Netzwerkschnittstellen ermitteln, nie 192.168 annehmen |

- **Mobiles Internet des Hosts:** LOHS ändert das Routing des Hosts nicht. Er bleibt online. **[Ableitung, Gerätetest]**
- **Gleichzeitig im Hotel-WLAN bleiben:** Ob der Host verbunden bleibt, sagt `isStaApConcurrencySupported()` [41]. **[Quellcode]**
- **Gäste-Datenverbrauch:** Beim normalen Hotspot surfen die Gäste mit den Daten des Hosts. iPhones können je WLAN den **Datensparmodus** einschalten [57]. **[belegt]**
- **Godot:** `LocalOnlyHotspotCallback` ist eine **Klasse**, kein Interface [41]. Ein Proxy über JavaClassWrapper (nur für Interfaces) [26] reicht also nicht. Nötig ist ein Java-Helfer im Gradle-Build, wie der Draw2Race-Updater. **[Quellcode/Ableitung]**

### B3 WLAN-QR-Code und Verhalten der Clients

**Format**
- `WIFI:T:WPA;S:<ssid>;P:<passwort>;;` — laut WPA3-Spezifikation steht `T:` immer auf `WPA`, auch bei WPA3. `T:SAE` (erzeugt von Android selbst) ist ungültig und wird oft nicht erkannt [47][48]. **[belegt/Bericht]**
- Die LOHS-Zeichen brauchen kein Escaping. Bei eigenen SSIDs mit `;` oder `:` unterscheiden sich die Escape-Regeln der Leser [48].

**Erkennung**
- iPhone-Kamera seit iOS 11 [49]. **[Bericht]**
- Android 10+: Einstellungen → WLAN → QR-Symbol neben „Netzwerk hinzufügen“, außerdem Kamera bzw. Google Lens je nach Hersteller [50]. **[Bericht]**

**iPhone im WLAN ohne Internet**
- Verkehr ins eigene Subnetz geht direkt über WLAN, unabhängig von der Standardroute [53]. **[belegt]**
- Ob das WLAN Standardroute wird, ist nebensächlich; dann fällt höchstens das Internet des iPhones aus [52].
- In den Einstellungen steht „Keine Internetverbindung“. Das ist normal.
- **Haltbarkeit:** Ein manuell beigetretenes Netz hält iOS bis zum Ruhezustand. Beim automatischen Beitritt prüft iOS auf Internet und **verlässt das Netz sofort**, wenn keins da ist [51]. **[belegt]**
- Folge für iPhone-Spieler:
  - Bildschirmsperre aus (Wake Lock geht auf `http://IP` nicht [55]).
  - Wiederverbinden mit Sitz-Token einbauen.
  - Ein Hotspot *mit* Internet (normales Tethering mit Daten) ist für iPhones stabiler.
- Safari zeigt keinen Dialog „lokales Netzwerk“; Chrome auf iOS schon [54]. **[Bericht]**

**Android-Browser-Spieler mit mobilen Daten**
- Sie landen oft im Mobilnetz statt im Hotspot [59]. Draw2Race stuft das ebenfalls als wahrscheinlich ein. **[Bericht]**
- Rat: „Mobile Daten aus“, bzw. bei der Meldung „Kein Internet“ „Verbunden bleiben“.
- App-Spieler lösen das per Programm: `bindProcessToNetwork` oder `WifiNetworkSpecifier`. Letzteres verbindet nur die App und zeigt einen Systemdialog, den Android pro Zugangspunkt merkt [58]. **[belegt]**

### B4 Gerätesuche

- **Browser:** braucht keine Suche, die IP steht im Link-QR.
- **App:**
  - UDP-Rundruf (Godot holt den Multicast-Lock selbst; eventuell `CHANGE_WIFI_MULTICAST_STATE`) [69].
  - Im Host-Netz besser an die Subnetz-Broadcast-Adresse (`x.y.z.255`) senden statt `255.255.255.255`. Sonst kann der Rundruf über Mobilfunk hinausgehen. **[Ableitung]**
  - Zusätzlich die Gateway-Probe (der Host ist das Gateway) und manuelle IP, wie in Draw2Race.
- Ab targetSdk 37 gilt `ACCESS_LOCAL_NETWORK` auch für Broadcast, Multicast und mDNS [60].

### B5 Bluetooth als Spiel-Notweg

- Die Bandbreite reicht: SPP schafft real etwa 100–200 KB/s [36].
- Aber:
  - Safari auf iOS kann **kein Web Bluetooth** [35].
  - Das Koppeln ist umständlich.
  - Es ginge nur zwischen Android-Apps.
- Nicht empfohlen. Nearby Connections wäre der bessere reine App-Notweg, kostet aber eine Play-Dienste-Abhängigkeit [32].

---

## Teil C – Empfehlung

### Host-Bildschirm „Mitspieler einladen“

Der Bildschirm hat drei Kacheln:
- **„Gleiches WLAN“:** Link-QR.
- **„Spiel-WLAN“:** LOHS mit zwei QR-Schritten.
- **„App senden“:** Teilen-Menü.

Die Seite hinter dem Link erkennt das Gerät:
- Android: **„App installieren (empfohlen)“** und **„Im Browser spielen“**.
- iPhone: direkt „Im Browser spielen“.

### Abläufe

| Fall | Ablauf |
|---|---|
| **(i) Android ohne App** | Auf Wunsch sofort im Browser spielen. 1. Wahl: Host → „App senden“ → **Quick Share**. Empfänger: Sichtbarkeit „Alle, 10 Min.“, annehmen, Datei öffnen, Dateien-App freigeben, Play-Protect-Dialog bestätigen. 2. Wahl: Link-QR → „App installieren“ (Chrome-Warnung, Chrome freigeben). Danach prüft die Lobby die Version und bietet „Update vom Host“. |
| **(ii) iPhone** | Browser. Im selben WLAN reicht der Link-QR. Sonst Spiel-WLAN: WLAN-QR, dann Link-QR. Hinweise: „Bildschirm anlassen“, „‚Kein Internet‘ ist normal“. Wiederverbinden per Token. |
| **(iii) Alle im selben funktionierenden WLAN** | Nur Link-QR. App-Clients finden den Host per Rundruf. APK über die Link-Seite (schnell im WLAN) oder per Quick Share. |
| **(iv) Isolation oder kein WLAN** | **Spiel-WLAN per LOHS:** in der App, mit QR, ohne Datenverbrauch. Läuft Tethering (`ERROR_INCOMPATIBLE_MODE`), ist das selbst im Spiel nicht lösbar: Host schaltet den System-Hotspot ab. Ersatz: System-Hotspot bleibt an, sein WLAN-QR kommt aus den Einstellungen [46], die App zeigt nur den Link-QR. Mit Daten am Host bleiben iPhones stabiler verbunden, die Gäste verbrauchen aber Daten des Hosts. |

### Zwei QR-Codes elegant auf einem Bildschirm

- **Nicht nebeneinander.** Die Kamera greift dann zufällig einen Code. **[Ableitung]**
- Stattdessen **ein großer QR mit Schrittleiste** „① WLAN beitreten → ② Spiel öffnen“.
  - Er wechselt alle paar Sekunden automatisch und lässt sich antippen.
  - Jeder Schritt hat eine eigene Rahmenfarbe und die Daten im Klartext: SSID und Passwort bzw. die Adresse.
- Darunter ein Zähler „3 Spieler in der Lobby“. Der Host sieht so, wer durch ist.
- Ein Ein-QR-Weg über ein Captive Portal geht nicht. DNS und DHCP gehören dem System, Port 53/80 sind für Apps gesperrt [66]. **[Ableitung]**
- **Optionales Experiment:** NFC-Tag-Emulation (Android HCE, Typ-4-Tag mit URL). iPhones ab XS lesen solche Tags im Hintergrund. Ein Projekt meldet Erfolg mit iOS [64]. **[Bericht, Gerätetest]**

### Reihenfolge der Umsetzung

1. HTTP-Server mit Landing-Seite, APK-Download, Web-Client und Link-QR (z. B. Kenyoni-QR-Addon [63]).
2. „App senden“: `base.apk` → `files/share` → FileProvider → `ACTION_SEND`.
3. LOHS-Java-Helfer mit WLAN-QR.
4. „Update vom Host“.
5. Später: NFC.

### Gerätetests (offen)

- Quick Share mit APK auf Samsung und Pixel; Play-Protect-Dialog offline.
- Chrome-Download der APK von `http://192.168…`.
- Ob Files by Google auch nicht aus dem Play Store installierte Apps teilt.
- LOHS: QR-Beitritt mit iPhone und Android; Host bleibt im Hotel-WLAN und hat weiter Internet.
- iPhone: Verhalten bei Bildschirmsperre im LOHS.
- Android-Browser-Spieler mit mobilen Daten an.
- Ab 2027: Installation im Flugmodus.

---

## Quellen
1. https://android-developers.googleblog.com/2026/03/android-developer-verification-rolling-out-to-all-developers.html
2. https://developer.android.com/developer-verification/guides/faq?hl=en
3. https://developer.android.com/developer-verification/guides
4. https://support.google.com/android-developer-console/answer/17131204?hl=en
5. https://support.google.com/android/answer/17588095?hl=en
6. https://9to5google.com/2026/08/18/google-gradually-rolling-out-androids-advanced-sideloading-ahead-of-developer-verification/
7. https://www.androidauthority.com/how-android-app-verification-works-3603559/
8. https://www.androidauthority.com/android-sideload-offline-3598988/
9. https://gist.github.com/agnostic-apollo/b8d8daa24cbdd216687a6bef53d417a6
10. https://support.google.com/android/answer/9286773?hl=en
11. https://www.android.com/articles/quick-share-on-android/
12. https://9to5google.com/2025/03/09/google-play-share-apps/
13. https://android.googlesource.com/platform/packages/modules/Bluetooth/+/refs/heads/main/android/app/src/com/android/bluetooth/opp/Constants.java
14. https://android-developers.googleblog.com/2017/08/making-it-safer-to-get-apps-on-android-o.html
15. https://developer.android.com/studio/publish/app-signing
16. https://developer.android.com/about/versions/14/behavior-changes-all
17. https://www.androidauthority.com/android-15-enhanced-confirmation-mode-3436697/
18. https://www.androidauthority.com/android-16-advanced-protection-mode-3518368/
19. https://9to5google.com/2023/10/18/google-play-protect-scan/
20. https://www.howtogeek.com/two-ways-to-install-apps-when-google-play-protect-wont-allow-it/
21. https://www.androidauthority.com/google-chrome-downloading-apks-3465272/
22. https://www.ghacks.net/2023/08/17/google-chrome-to-enable-https-first-by-default-for-all-users/
23. https://blog.google/security/https-by-defau/
24. https://groups.google.com/a/chromium.org/g/chromium-dev/c/KOmfh5BW6Mw
25. https://www.androidauthority.com/android-14-sideload-warning-update-ownership-3345719/
26. https://docs.godotengine.org/en/stable/tutorials/platform/android/javaclasswrapper_and_androidruntimeplugin.html
27. https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/content/pm/ApplicationInfo.java
28. https://github.com/godotengine/godot/issues/104137
29. https://developer.android.com/training/sharing/send
30. https://docs.godotengine.org/en/stable/classes/class_websocketpeer.html
31. https://developer.android.com/develop/connectivity/wifi/wifip2p
32. https://developers.google.com/nearby/connections/overview
33. https://android-developers.googleblog.com/2017/07/announcing-nearby-connections-20-fully.html
34. https://developer.apple.com/forums/thread/12885
35. https://caniuse.com/web-bluetooth
36. https://community.infineon.com/t5/Knowledge-Base-Articles/FAQs-on-Bluetooth-Serial-Port-Profile-SPP/ta-p/915028
37. https://www.axiomremote.com/blog/wifi-client-isolation-remote-desktop
38. https://support.google.com/chromecast/answer/7566322?hl=en
39. https://www.tp-link.com/us/blog/2586/what-is-ap-isolation-and-when-to-enable-it-/
40. https://developer.android.com/develop/connectivity/wifi/localonlyhotspot
41. https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/main/framework/java/android/net/wifi/WifiManager.java
42. https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/main/service/java/com/android/server/wifi/WifiApConfigStore.java
43. https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/main/service/java/com/android/server/wifi/WifiServiceImpl.java
44. https://android.googlesource.com/platform/frameworks/base/+/8a8e7e0350d901a18093280dfad6a516a7f26256%5E!/
45. https://github.com/Mygod/VPNHotspot/issues/193
46. https://www.howtogeek.com/how-to-share-your-androids-hotspot-using-a-qr-code/ und https://www.samsung.com/au/support/mobile-devices/use-qr-code-for-mobile-hotspot/
47. https://www.wi-fi.org/system/files/WPA3%20Specification%20v3.5.pdf
48. https://stevetech.me/posts/wifi-qr-codes-are-broken
49. https://9to5mac.com/2017/06/09/ios-11-scan-routers-qr-code-quickly-join-network/
50. https://www.androidpolice.com/2020/07/18/how-to-share-wi-fi-network-passwords-via-qr-code-on-android/
51. https://developer.apple.com/forums/thread/734361
52. https://developer.apple.com/forums/thread/734344
53. https://developer.apple.com/forums/thread/734293
54. https://developer.apple.com/forums/thread/811690
55. https://developer.mozilla.org/en-US/docs/Web/API/Screen_Wake_Lock_API
56. https://developer.mozilla.org/en-US/docs/Web/Security/Defenses/Secure_Contexts
57. https://support.apple.com/en-us/102433
58. https://developer.android.com/develop/connectivity/wifi/wifi-bootstrap
59. https://www.b4x.com/android/forum/threads/esp32-android-iphone-without-internet.147889/
60. https://developer.android.com/privacy-and-security/local-network-permission
61. https://github.com/godotengine/godot/blob/master/platform/web/js/engine/features.js
62. https://github.com/godotengine/godot-proposals/issues/10076
63. https://kenyoni-software.github.io/godot-addons/addons/qr_code/
64. https://github.com/underwindfall/NFCAndroid
65. https://www.macrumors.com/2026/06/02/google-airdrop-support-more-android-phones/ (Quick Share ↔ AirDrop, Gerätelisten auch in [10])
66. https://www.b4x.com/android/forum/threads/java-net-bindexception-bind-failed-eacces-permission-denied.96084/
67. https://en.wikipedia.org/wiki/Quick_Share
68. https://support.google.com/android-developer-console/answer/16604405?hl=en
69. https://docs.godotengine.org/en/stable/classes/class_packetpeerudp.html

Lokal geprüft (nur gelesen): `C:\Users\Shakie\Documents\Programmierung\Draw2Race\game\android\build\libs\release\godot-lib.template_release.aar` (`res/xml/godot_provider_paths.xml`), `C:\Users\Shakie\Documents\Programmierung\Draw2Race\game\android\build\src\main\java\com\godot\game\Updater.java`, `C:\Users\Shakie\Documents\Programmierung\Draw2Race\docs\MULTIPLAYER_RECHERCHE.md`, `C:\Users\Shakie\Documents\Programmierung\Draw2Race\builds\` (APK-Größen).