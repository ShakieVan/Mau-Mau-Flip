# Draw2Race-Analyse: Android-Integration und Projektinfrastruktur als Grundlage für Mau-Mau Flip (Godot 4.6)

## Kurzfazit
- Draw2Race nutzt kein Godot-Plugin. Es gibt einen eigenen Gradle-Build mit selbst geschriebenen Java-Klassen, die nur statische Methoden haben. GDScript ruft sie über `JavaClassWrapper` mit `AndroidRuntime.getActivity()` auf. Laufzeitberechtigungen werden nirgends angefragt (`OS.request_permission` kommt im Code nicht vor), und es gibt keine Listener aus GDScript.
- (d) Pfad der eigenen APK und (e) Multicast-Sperre und eigene IP-Adressen gehen sofort: (e) ist praktisch fertig, (d) ist ein Einzeiler.
- (a) APK über das Teilen-Menü verschicken ist mit dem Updater-Muster in etwa einem Tag machbar.
- (c) HTTP- und WebSocket-Server sind machbar. Dabei gibt es aber zwei Fallen, die zur Architektur gehören: Die Godot-Hauptschleife steht still, solange die App pausiert ist. Und ein Godot-Web-Export über einfaches `http://` im lokalen Netz scheitert am „Secure Context“-Check.
- (b) LocalOnlyHotspot ist machbar, braucht aber zwingend Java-Code (der Callback ist eine Klasse, kein Interface) und eine Laufzeitberechtigung. Gerätetests sind nötig.

---

## 1. Welche nativen Android-Funktionen Draw2Race schon nutzt, und wie

**Technik:** Custom-Gradle-Build (`gradle_build/use_gradle_build=true` in `C:\Users\Shakie\Documents\Programmierung\Draw2Race\game\export_presets.cfg`). Die Vorlage liegt in `game\android\build` (`.build_version` = 4.6.1.stable). Eigene Java-Dateien liegen unter `game\android\build\src\main\java\com\godot\game\`:
- `Updater.java`
- `NetHelper.java` (ungespeicherte Änderungen vom S24-Test heute)
- `GodotApp.java` (unverändert aus der Vorlage)

Die Projektsuche nach `JavaClassWrapper`, `get_singleton`, `permission`, `plugin`, `AndroidRuntime` und `Intent` findet nur zwei Aufrufstellen:
- `game\scripts\net\net_android.gd`, Zeilen 13–16
- `game\scripts\updater.gd`, Zeilen 276–279

Es gibt keine `addons/`-Plugins, kein Plugin v1 oder v2, kein `OS.request_permission(s)` und keine Intents in GDScript.

Das Muster, nahezu identisch in beiden Dateien:
```gdscript
static func _java() -> Array:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return []
	var activity = Engine.get_singleton("AndroidRuntime").getActivity()
	var java = JavaClassWrapper.wrap("com.godot.game.NetHelper")
	return [java, activity] if java != null and activity != null else []
```

**Updater.java** (Aufruf aus `updater.gd`):
- `canInstall`
- `openInstallPermission`: `ACTION_MANAGE_UNKNOWN_APP_SOURCES`, über `runOnUiThread`
- `installedVersion`
- `verify`: Paketname, `versionCode` größer als installiert, `versionName` stimmt, Signatur identisch (`GET_SIGNING_CERTIFICATES`)
- `install`: über den FileProvider der Godot-Bibliothek:
```java
Uri uri = FileProvider.getUriForFile(activity, activity.getPackageName() + ".fileprovider", file);
Intent intent = new Intent(Intent.ACTION_VIEW);
intent.setDataAndType(uri, "application/vnd.android.package-archive");
intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
activity.runOnUiThread(() -> activity.startActivity(intent));
```
Den FileProvider habe ich in `godot-lib.template_release.aar` geprüft: Kennung `${applicationId}.fileprovider`. Freigegeben sind `files-path "/"`, `external-path "."` und `external-files-path "."`. `/data/app` ist **nicht** freigegeben.

**NetHelper.java** (Aufruf aus `net_android.gd`):
- `state()`: JSON mit allen Netzen (Handle, Transport, Internet/validated, `local` = NET_CAPABILITY 36 ab API 35, iface, IPv4/Präfix, Gateway), Standardnetz und gebundenem Netz, DHCP-Gateway, Multicast-Status und Schnittstellen
- `interfaces()`: `NetworkInterface` mit IPv4, Präfix und Broadcast
- `bindWifi`, `bindNetwork(handle)`, `unbind`: `bindProcessToNetwork`
- `multicastAcquire`, `multicastRelease`: eigene `WifiManager.MulticastLock`, nicht referenzgezählt

**Designprinzip, das man übernehmen sollte:**
- Java liefert nur Strings (JSON), bool oder einfache Werte, nie komplexe Java-Objekte.
- Jede Entscheidung trifft GDScript als reine Funktion des JSON-Zustands, z. B. `hotspot_network`, `host_plan`, `bound_to_wifi`.
- Das ist am PC mit Werten aus Geräteprotokollen testbar: `FakeAndroid` in `game\tests\test_lobby.gd` ersetzt die Anbindung über `var android_api` in `net_lobby.gd`.
- Außerhalb von Android liefern alle Funktionen Ersatzwerte (`IP.get_local_interfaces()`).

**Berechtigungen** (alle „normal“, ohne Dialog): INTERNET, REQUEST_INSTALL_PACKAGES, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE, CHANGE_WIFI_MULTICAST_STATE. Sie stehen doppelt: im Exportprofil und kommentiert in `game\android\build\src\main\AndroidManifest.xml`. `src\debug\AndroidManifest.xml` erzeugt der Export.

**Gradle:**
- `config.gradle`: compileSdk 35, targetSdk 35, minSdk 24, AGP 8.6.1, Gradle 8.11.1, JDK 17
- `gradle.properties`: `org.gradle.daemon=false`. Ohne diesen Eintrag kehrte der Export nie zurück.

---

## 2. Infrastruktur, die das neue Projekt übernehmen sollte

| Baustein | Datei (Draw2Race) | Anpassen |
|---|---|---|
| Setup | `tools\setup.ps1`: lädt Godot 4.6.1 und die Exportvorlagen nach `.tools` bzw. `%APPDATA%\Godot\export_templates` | Version unverändert |
| Build | `tools\build.ps1` (siehe Liste unter der Tabelle) | Mutex-Name, Testliste, Paketname; Import-Anpassungen für JPG/WAV/Texturen streichen |
| Testläufer | `tools\godot_run.ps1`: Zeitgrenze, `-EnvPairs`, eigenen Prozessbaum beenden, Mutex | Mutex-Name |
| Mehrprozess-Netztest | `tools\net_test.ps1` + `game\scripts\net\net_cli.gd` / `lobby_cli.gd`: Host und N Clients als headless Prozesse, Ergebniszeilen mit Prüfsummen | auf Kartenspiel umbauen; dazu einen Browser-Client-Test (z. B. Playwright, auch mit WebKit unter Windows) |
| Tests | `game\tests\test_*.gd`: `extends SceneTree`, `check()` → `PASS:`/`FAIL:`, `RESULT: x/y`, `quit(1)` bei Fehler; Exportprofil `exclude_filter="tests/*"` | gleich |
| Android-Build-Ordner | `.gitignore`: Vorlage und eigene Java-Dateien versionieren, `build/`, `.gradle/`, `src/main/assets/`, `libs/`, `local.properties` ignorieren | gleich |
| Updater | `game\scripts\updater.gd` + `Updater.java`: Release- und Beta-Repo, `digest`-SHA-256 der GitHub-API, exakte URL, Wächter gegen hängende Downloads, `user://updates/<sha>.apk` | `REPOSITORY`/`BETA_REPOSITORY`, Asset-Name `MauMauFlip-X.Y.Z.apk` |
| Netz-Helfer | `NetHelper.java` + `net_android.gd` (mit Tests aus `test_lobby.gd`) | Name der Multicast-Sperre; den committeten Stand nach dem S24-Fix nehmen |
| Doku | siehe Liste unter der Tabelle | gleich |
| Sonstiges | `Start-Draw2Race.cmd`, `builds\README.md`, Lizenzdateien in `builds/`, verstecktes Entwicklermenü (5× aufs Logo) mit Netztest und `user://*.log` | gleich |

**Was `tools\build.ps1` macht:**
- Import
- alle Testreihen laufen immer durch, danach eine Zusammenfassung
- Windows- und Android-Export
- `libs/*.aar` bei Bedarf aus `android_source.zip` nachziehen
- Projekt-Keystore über `GODOT_ANDROID_KEYSTORE_DEBUG_*`
- Prüfung, dass die Version in `project.godot` und im Exportprofil gleich ist
- Kopie nach `builds/<Name>-<version>.apk`
- Mutex `Global\Draw2RaceGodot`, damit mehrere Agenten nicht gleichzeitig Godot laufen lassen

**Doku-Struktur:**
- `AGENTS.md`: Stand, Einstieg, dauerhafte Leitplanken, Nutzerentscheidungen mit Datum, Schlusssatz „keine zusätzliche Genehmigungspflicht“
- `README.md`
- `docs\IMPLEMENTIERUNG.md`: chronologisch je Version mit Änderungen, Tests, Gerätetest und Offen
- `docs\MULTIPLAYER_RECHERCHE.md`: Belegmarken [belegt]/[Bericht]/[ungeprüft]/[Gerätetest], Prüfprotokoll, Quellen, „Entscheidungen des Nutzers (Datum)“

**Konventionen:**
- Nummernschema: Release `X.Y.0`, Betas `X.Y.Z`; `version/code` steigt immer; der Updater vergleicht nur Zahlen, also keine Zusätze wie `-beta`.
- Release mit `gh release create vX.Y.Z builds/...apk`; Beta als Pre-Release im Beta-Repo.

**Für den Neuanfang besser machen:**
- Eigenen Keystore sofort anlegen und sichern. In Draw2Race liegt er nur in `.tools\draw2race-debug.keystore`, und `.tools/` ist gitignored. Ist er weg, lehnt `verify()` jedes Update ab.
- Draw2Race veröffentlicht `--export-debug`-Builds. Vorteil: die App ist debuggable, `adb shell run-as` geht. Nachteil: Debug-Template. Das sollte man bewusst entscheiden.
- Das Projektverzeichnis hat ein Leerzeichen (`E:\Documents\Programmierung\Mau-Mau Flip`). Der erste Gradle-Export sollte das prüfen. Daneben gibt es einen leeren Ordner `Mau-Maul Flip`, vermutlich ein Tippfehler; er ist zugleich das Arbeitsverzeichnis dieser Sitzung.

---

## 3. Machbarkeit (a)–(e)

### Godot 4.6, was geht und was nicht
- **JavaClassWrapper (seit 4.4):**
  - statische und Instanzmethoden auf zurückgegebenen Objekten
  - Konstruktoren (`Intent.Intent()`)
  - Felder und Konstanten, innere Klassen mit `$`
  - `get_exception()`
  - Godot-Callables als Argument (PR #99492, 4.4)
- **AndroidRuntime** (eingebaut, per `javap` aus godot-lib 4.6.1 gelesen):
  - `getActivity()`, `getApplicationContext()`
  - `createRunnableFromGodotCallable()`, `createCallableFromGodotCallable()`
  - `updatePersistableUriPermission()`
  - Die Klasse `org.godotengine.godot.variant.Callable` mit `call(Object...)` existiert. Eine eigene Java-Methode kann also vermutlich eine GDScript-Callable als Rückruf annehmen. Am Gerät prüfen. Der Rückruf käme auf einem Java-Thread an, in GDScript also `call_deferred`.
- **Interfaces oder Listener aus GDScript implementieren:** geht in 4.6 nicht.
  - Godot 4.7 bringt `JavaClassWrapper.create_sam_callback()` und `create_proxy()` (PR #115498, 01.04.2026 gemergt, Meilenstein 4.7). Die stable-Doku zeigt bereits 4.7.
  - Laut Beschreibung geht das nur für Interfaces, abstrakte und konkrete Klassen bleiben außen vor.
- **Robustester Weg für Rückrufe** bleibt das Draw2Race-Muster: Java speichert den Zustand in statischen Feldern, GDScript fragt per `state()` ab.
- **Plugin v2** (AAR + EditorExportPlugin, Signale über `emitSignal`) wäre eine Alternative. Es lohnt sich nur, wenn Draw2Race und Mau-Mau Flip die Helfer gemeinsam nutzen sollen. Empfehlung: beim erprobten Custom-Build bleiben. Bei einem Godot-Update muss die Build-Vorlage neu installiert werden, die eigenen Dateien kommen dann aus git zurück.
- **Hauptschleife steht still bei Pause:** Ist die Activity pausiert (Teilen-Menü offen, Berechtigungsdialog, Bildschirm aus), läuft keine `_process`-Schleife. Draw2Race meldet deshalb in `main.gd` (ab Zeile 1278) „im Hintergrund“, bevor Android die App anhält. Server, die weiterlaufen müssen, gehören in einen `Thread` oder nach Java.
- **Berechtigungen im Exportprofil:** Godots Exportliste kennt `CHANGE_WIFI_STATE`, aber **nicht** `NEARBY_WIFI_DEVICES` (siehe `.tools\android_export.cpp`, Zeilen 110 f.). `custom_permissions` kann keine Flags setzen. Also direkt in `src\main\AndroidManifest.xml` eintragen.

### (a) Eigene APK über das Teilen-Menü (Quick Share, Bluetooth): machbar, etwa 1 Tag
- Neue Java-Methode, analog zu `Updater.install`:
  1. `sourceDir` nach `files/share/MauMauFlip-<ver>.apk` kopieren (nötig, weil der FileProvider `/data/app` nicht freigibt; dazu ein lesbarer Dateiname).
  2. `ACTION_SEND` mit Typ `application/vnd.android.package-archive`, `EXTRA_STREAM`, `ClipData` und `FLAG_GRANT_READ_URI_PERMISSION`.
  3. `Intent.createChooser` über `runOnUiThread`.
- Rein mit JavaClassWrapper ginge es in 4.6 auch, das Java-Muster ist aber robuster.
- Den Link zum Spiel teilt man auf dieselbe Art per `text/plain`.

Risiken:
- Bluetooth lehnt in AOSP den Empfang von APKs ab: Der Empfang hat eine MIME-Whitelist ohne APK. Für Samsung ist das ungeprüft. Außerdem ist Bluetooth langsam.
- Quick Share erreicht keine iPhones, dort hilft nur der QR-Code.
- Der Empfänger muss die Installation aus unbekannten Quellen für die Dateien- oder Quick-Share-App erlauben. Samsung „Auto Blocker“ ist ungeprüft.
- Google-Entwicklerverifizierung: Seit 30.09.2026 gilt sie in BR, ID, SG und TH, 2027 weltweit. Bis 20 Geräte gibt es ein Hobby-Konto ohne Ausweis, außerdem den „advanced flow“; adb ist ausgenommen. Das betrifft GitHub-Verteilung und Weitergabe gleichermaßen.
- Bessere Ergänzung ohne Quick Share: Der Host liefert die APK über seinen eigenen HTTP-Server aus, siehe (c). Die App eines Gastes könnte den Host sogar als Update-Quelle nutzen und dabei `Updater.verify()` wiederverwenden.

### (b) LocalOnlyHotspot starten und Zugangsdaten auslesen: machbar, nur mit Java, 2–3 Tage plus Gerätetest
- `WifiManager.LocalOnlyHotspotCallback` ist eine **Klasse** (per `javap` auf `android.jar` API 36 geprüft) mit `onStarted(Reservation)`, `onStopped()` und `onFailed(int)`. Fehlerwerte: `ERROR_NO_CHANNEL`, `ERROR_GENERIC`, `ERROR_INCOMPATIBLE_MODE`, `ERROR_TETHERING_DISALLOWED`. Weder 4.6 noch 4.7 können sie aus GDScript implementieren.
- Java-Helfer:
  - `startHotspot(activity)` mit Handler auf dem Main-Looper; die Reservation in einem statischen Feld halten
  - `hotspotState()` als JSON mit Status, SSID, Passphrase, Sicherheitstyp und Fehlercode
  - `stopHotspot()` ruft `close()` auf
- Zugangsdaten: `getSoftApConfiguration()` mit `getWifiSsid()` bzw. `getSsid()`, `getPassphrase()` und `getSecurityType()` (ab API 30); bis API 29 `getWifiConfiguration()`.
  - In API 36 gibt es `startLocalOnlyHotspotWithConfiguration`, der öffentliche `SoftApConfiguration.Builder` kann aber nur `setChannels`. Eine eigene SSID ist also nicht möglich; SSID und Passwort sind jedes Mal zufällig, der QR-Code `WIFI:T:WPA;S:…;P:…;;` entsteht deshalb pro Sitzung neu.
- Manifest:
  - `NEARBY_WIFI_DEVICES` mit `usesPermissionFlags="neverForLocation"`
  - `ACCESS_FINE_LOCATION` mit `maxSdkVersion="32"`
  - `CHANGE_WIFI_STATE`
- Laufzeitdialog über `OS.request_permission(...)` und das SceneTree-Signal `on_request_permissions_result`. Das ist in Draw2Race noch nie genutzt worden, also am Gerät prüfen. Bis Android 12 (S10) muss nach meinem Kenntnisstand zusätzlich der Standort eingeschaltet sein; ungeprüft.
- Einschränkungen:
  - kein Internet
  - parallel zum normalen Hotspot nicht möglich (`ERROR_INCOMPATIBLE_MODE`)
  - ob das Heim-WLAN dabei verbunden bleibt, zeigt `isStaApConcurrencySupported()`
  - der Hotspot endet mit dem App-Prozess
  - der Emulator taugt dafür vermutlich nicht
- Vorhandene Logik passt: `hotspot_interfaces()` und `host_plan()` (ein Host mit eigenem Hotspot bindet sich nie) liefern die IP für den Link-QR-Code. Ob Android den LocalOnlyHotspot wie den normalen Hotspot meldet (swlan0/ap0, Android 16 als „lokales Netz“), ist am S10, S21 und S24 zu prüfen.

### (c) HTTP- und WebSocket-Server im Spiel: machbar, mit Architekturentscheidungen
- Godot hat keinen HTTP-Server. Man baut einen minimalen selbst mit `TCPServer.listen(port, "*")` und `StreamPeerTCP` (GET und statische Dateien). Für WebSocket gibt es `WebSocketMultiplayerPeer.create_server()` oder `WebSocketPeer.accept_stream()`.
- `accept_stream` übernimmt den Handshake selbst. HTTP und WS deshalb auf **getrennten Ports** betreiben, oder die WS-Rahmung selbst schreiben.
- `INTERNET` genügt. `ACCESS_LOCAL_NETWORK` wird erst ab targetSdk 37 Pflicht, Godot 4.6 setzt 35.
- **Fallen:**
  1. Die Hauptschleife pausiert, siehe oben. Datei-Auslieferung (APK, Web-Dateien) gehört in einen Thread, und während des Hostens sollte der Bildschirm anbleiben: `DisplayServer.screen_set_keep_on(true)`.
  2. Der Host darf seinen Prozess nicht ans WLAN binden, wenn er selbst den Hotspot stellt. Lehre vom S24, siehe 4.
  3. **Ein Godot-Web-Export über `http://<LAN-IP>` scheitert:** `platform/web/js/engine/features.js` (4.6-stable) prüft `isSecureContext` immer. Das ginge nur mit eigener HTML-Shell, wobei ungeklärt ist, ob Audio und Co. dann funktionieren, oder mit HTTPS und selbstsigniertem Zertifikat (Safari-Warnung, Ausnahme gilt pro Port).
- **Empfehlung:**
  - Für den Browser einen schlanken eigenen HTML/JS-Client; `ws://` von einer `http://`-Seite braucht keinen Secure Context.
  - WebSocket als einzigen Transport für App und Browser verwenden. Draw2Race schickt schon eigene Pakete direkt über `ENetMultiplayerPeer.put_packet` (`net_session.gd`, ohne SceneMultiplayer RPCs), die Protokollschicht lässt sich also übertragen.
  - UDP-Suche gibt es im Browser nicht, daher QR-Code bzw. URL.
  - Testen ohne iPhone: Playwright mit WebKit unter Windows plus Android-Chrome, iOS echt über Bekannte oder einen Cloud-Gerätedienst.

### (d) Pfad der installierten eigenen APK: sofort machbar
- `activity.getPackageCodePath()` oder `getApplicationInfo().sourceDir`. Das liefert einen String und geht daher auch direkt per JavaClassWrapper.
- Bei Installation einer Universal-APK gibt es nur `base.apk`; zur Sicherheit `splitSourceDirs == null` prüfen.
- Die eigene App darf die Datei lesen. Zum Teilen wird sie kopiert (FileProvider), der HTTP-Server kann direkt aus `sourceDir` streamen.
- Die geteilte APK trägt dieselbe Signatur, spätere GitHub-Updates passen also.

### (e) Wi-Fi-Multicast-Sperre und eigene IP-Adressen: fertig vorhanden
- `NetHelper.multicastAcquire/Release`, `interfaces()` und `state()` sowie `NetAndroid.interfaces()`, `hotspot_addresses()` und `wifi_addresses()` lassen sich 1:1 übernehmen. Nur Paket- und Lock-Namen ändern.
- Godot nimmt für Broadcast-Sockets zusätzlich selbst eine Sperre (laut Recherche-Doku 4.2).

---

## 4. Lehren aus den Gerätetests
Geräte: S10 (Android 12), S21 (Android 15), S24 Ultra (Android 16), alle Samsung, per WLAN-Debugging. S10 und S21 haben keine SIM.

1. **Android 16 meldet den eigenen Hotspot als eigenes Netz** (Transport WLAN, `swlan0`, ohne Gateway, „lokales Netz“). Bis Android 15 erscheint er nur als Schnittstelle.
   - Ein ans Heim-WLAN gebundener Host schickte Antworten an Hotspot-Spieler ins Heim-WLAN. Nach „WLAN aus“ band er sich an den eigenen Hotspot.
   - Regel: Mit eigenem Hotspot nie binden („zweigleisig“).
   - Dateien: `net_android.gd` (`host_plan`, `hotspot_network`), `NetHelper.isLocal`; IMPLEMENTIERUNG.md, Abschnitte vom 04.10.
2. **Nach einem WLAN-Wechsel meldet Android das verlorene Netz weiter als „gebunden“** (Transport „?“). Deshalb gibt es `bound_to_wifi()`, geprüft mit Werten aus dem Geräteprotokoll in `test_lobby.gd`.
3. **Samsung betreibt den Hotspot ohne SIM neben dem Heim-WLAN** (S21). Messwerte:
   - 8–9 % Verlust der Echo-Pakete, RTT im Schnitt 36 ms
   - im Heim-WLAN 40 ms, Spitzen bis 220 ms durch den WLAN-Stromsparmodus
   - Rundruf-Suche in 0,06–0,23 s
4. **Ungetestet:** Mitspieler mit aktiven mobilen Daten (Routing in den Hotspot ohne Internet) und Hotspot ganz ohne Internet. Das ist für Urlaub und Browser-Clients das Kernszenario.
5. **Router-Störfall:** Ein WPA3-Router erneuert den Gruppenschlüssel alle 10 min. Das S10 wird dabei abgemeldet, und Android schaltet danach das WLAN-Debugging ab. Wiederverbinden muss eingeplant werden.
6. **Hintergrund und langsame Geräte:** Die Pause muss gemeldet werden, bevor Android die App anhält. Zeitgrenzen: normal 8–20 s, beim Laden 25–45 s (Hänger von 5,1 s gemessen).
7. **Der PC-Test fand einen Eingabefehler nicht:** Schnelle Fingerstriche beim Linienende scheiterten erst am Gerät (0.2.31). Tests mit realistischen Touch-Geschwindigkeiten schreiben.
8. **Updater:** `HTTPRequest.timeout` begrenzt die *ganze* Anfrage. Der Download brach nach 30 s ab und brauchte einen Wächter (0.2.26). Alte Installationen mussten einmal von Hand aktualisiert werden. Der Updater muss also ab Version 1 korrekt sein.
9. **Build und APK:** Der Gradle-Daemon blockierte den Export (`org.gradle.daemon=false`). Die APK schrumpfte von 345 auf 172 MB durch nur ARM64, `compress_native_libraries` und verlustbehaftete Texturen. Ohne x86_64 ist ein Emulator-Test nur noch mit einem eigenen Build möglich.
10. **Diagnose:** Logs in `user://*.log`, abholen mit `adb shell run-as <paket> cat files/<log>`; das setzt eine debuggable App voraus. Der Emulator (API 36, AVD `Medium_Phone`) wurde für Installation, Start und Touch genutzt und ersetzt kein echtes Gerät. Für 20:9-Kontrollbilder `-Resolution 1600x720` nehmen, denn 2400x1080 begrenzt Windows still.
11. **Nur Samsung-Geräte im Test:** Für LocalOnlyHotspot, Quick Share und Berechtigungsdialoge wäre ein Nicht-Samsung-Gerät wertvoll.

Relevante Pfade:
- `C:\Users\Shakie\Documents\Programmierung\Draw2Race\game\scripts\net\net_android.gd`
- `...\game\scripts\updater.gd`
- `...\game\android\build\src\main\java\com\godot\game\{Updater,NetHelper,GodotApp}.java`
- `...\game\android\build\src\main\AndroidManifest.xml`
- `...\game\android\build\{config.gradle,gradle.properties}`
- `...\game\export_presets.cfg`
- `...\tools\{setup,build,godot_run,net_test}.ps1`
- `...\game\tests\test_lobby.gd`
- `...\docs\IMPLEMENTIERUNG.md` (Zeilen 199–219, 350–354, 414–520)
- `...\docs\MULTIPLAYER_RECHERCHE.md` (Abschnitte 4.2–4.4, 10)
- `...\AGENTS.md`

**Quellen:**
- [Godot 4.6: Integrating with Android APIs](https://docs.godotengine.org/en/4.6/tutorials/platform/android/javaclasswrapper_and_androidruntimeplugin.html)
- [JavaClassWrapper 4.6](https://docs.godotengine.org/en/4.6/classes/class_javaclasswrapper.html)
- [JavaClassWrapper stable/4.7](https://docs.godotengine.org/en/stable/classes/class_javaclasswrapper.html)
- [PR #99492 (Callable-Argumente, 4.4)](https://github.com/godotengine/godot/pull/99492)
- [PR #115498 (create_sam_callback/create_proxy, 4.7)](https://github.com/godotengine/godot/pull/115498)
- [Godot features.js 4.6-stable](https://raw.githubusercontent.com/godotengine/godot/4.6-stable/platform/web/js/engine/features.js)
- [Android Local-only hotspot](https://developer.android.com/develop/connectivity/wifi/localonlyhotspot)
- [AOSP Bluetooth: Dateityp-Whitelist (Pastebin-Auszug)](https://pastebin.com/8d7g7LTu)
- [Android developer verification (Android Developers Blog)](https://android-developers.googleblog.com/2026/03/android-developer-verification-rolling-out-to-all-developers.html)
- [Android Authority zur Verifizierung](https://www.androidauthority.com/android-sideloading-developer-verification-first-wave-rollout-3717921/)
- Lokal per `javap` geprüft: `godot-lib.template_release.aar` (4.6.1) und `android.jar` API 34/35/36.