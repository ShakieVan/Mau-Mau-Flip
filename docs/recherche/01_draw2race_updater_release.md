# Draw2Race: Update-Funktion und Build/Release, Analyse zur Übernahme in Mau-Mau Flip

Ich habe nur gelesen und nichts verändert. Alle Pfade sind relativ zu `C:\Users\Shakie\Documents\Programmierung\Draw2Race` (das ist dasselbe Verzeichnis wie `E:\Documents\Programmierung\Draw2Race`).

## 1. So sucht die App nach Updates und installiert sie

**Dateien:** `game/scripts/updater.gd` (Klasse `Updater`, Node, Signal `changed`) und `game/android/build/src/main/java/com/godot/game/Updater.java`.

**Endpunkte**
- Regulär: `ENDPOINT = https://api.github.com/repos/ShakieVan/Draw2Race/releases/latest`
- Beta: `ENDPOINT_BETA = https://api.github.com/repos/ShakieVan/Draw2Race-Beta/releases?per_page=20`
- Das Beta-Repo braucht die Liste, weil es dort nur Pre-Releases gibt. Darum liefert `/releases/latest` dort 404. Auch `gh release view -R ShakieVan/Draw2Race-Beta` ohne Tag meldet „release not found“.
- Mitgesendete Header:
  - Abfrage: `User-Agent: Draw2Race/<ver>`, `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`
  - Download: `Accept: application/octet-stream`

**Kanalwahl**
- Gespeichert in `ProgressStore.data["update_beta"]`; umgeschaltet mit `set_beta(on)`. Das verwirft den Cache `update_release` und startet sofort `check(true)`.
- Im Beta-Kanal werden nacheinander `[ENDPOINT_BETA, ENDPOINT]` abgefragt, mit einem einzigen `HTTPRequest` (`request_next()`, `_checked()` mit `CONNECT_ONE_SHOT`). Die höchste Version gewinnt (`best`). Ein neueres reguläres Release geht einem Beta-Nutzer also nicht verloren.
- Die Oberfläche ist `hud.gd` → `update_dialog()` (etwa Zeile 772) mit dem Schalter „Beta-Versionen erhalten“.

**Prüflogik (`parse()` / `parse_release()`, statisch und testbar)**
Ein Release wird nur angenommen, wenn alle Bedingungen gelten:
- Es ist kein Entwurf.
- Ein Pre-Release oder ein Release aus dem Beta-Repo zählt nur mit `allow_beta`.
- Der Tag lautet `vX.Y.Z` und besteht nur aus Zahlen (`valid_version`).
- Es gibt genau ein Asset namens `Draw2Race-X.Y.Z.apk`.
- Die Größe liegt zwischen 1 Byte und `MAX_APK_BYTES` (512 MB).
- Das Feld `digest` lautet `sha256:<64 hex>`. GitHub rechnet das selbst aus, man muss keine Prüfsumme mitveröffentlichen.
- `browser_download_url` stimmt exakt mit `https://github.com/<REPO>/releases/download/<tag>/<name>` überein.
- Ergebnis: `{version, notes (max. 6000 Zeichen), size, sha256, url, beta, raw}`.

**Versionsvergleich**
- `current_version()` liest `ProjectSettings application/config/version`.
- `compare_versions()` vergleicht genau drei Zahlenteile. Zusätze wie `-beta` sind nicht erlaubt.

**Ablauf der Prüfung**
- `setup(store)`:
  - legt ein `HTTPRequest` an (`use_threads=true`, `timeout=30`);
  - liest den Cache `update_release` (rohes JSON), damit „Neue Version verfügbar“ auch offline erscheint;
  - setzt `apk_ready`, wenn die Datei schon geladen ist.
- `check(manual)`:
  - automatisch höchstens alle 24 h (`DAY_MS`, Schlüssel `update_last_check`). Der Zeitstempel wird schon vor der Anfrage gesetzt.
  - `main.gd` (Zeilen 129–136) ruft `check(false)` nur unter Android auf.
- `finish_check()`:
  - Hat keine Quelle mit 200 oder 404 geantwortet, erscheint „Keine Verbindung.“
  - Sonst wird gecacht und mit der installierten Version verglichen.
- Im Menü erscheint der Knopf „Update ↓“ (`hud.gd` etwa Zeile 293), sobald `updater.available()` gilt.

**Download und Fortschritt**
- `download()` räumt zuerst mit `prune()` auf und lädt dann nach `user://updates/<sha256>.apk.part` (`http.download_file`).
- Beim Download gilt `timeout = 0`. Stattdessen läuft in `_process` ein Wächter: Kommen `STALL_TIMEOUT` = 30 s lang keine neuen Bytes (`get_downloaded_bytes()`), folgt `cancel_request()`.
- Der Prozentwert ist `get_downloaded_bytes()*100/release.size`, gemeldet über `changed.emit()`.

**Integritätsprüfung**
- `_downloaded()` startet `_hash_file()` in einem eigenen `Thread` (SHA-256 in 1-MB-Blöcken, dazu Größenvergleich).
- `_hashed()` benennt `.part` in `.apk` um und setzt `apk_ready`.

**Installation unter Android (`install()`)**
- `android()` holt `Engine.get_singleton("AndroidRuntime").getActivity()` und `JavaClassWrapper.wrap("com.godot.game.Updater")`. Es gibt kein Plugin, nur statische Java-Methoden.
- `Updater.java` stellt diese Methoden bereit:
  - `canInstall()` nutzt `PackageManager.canRequestPackageInstalls()`.
  - `openInstallPermission()` öffnet `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES` mit `package:<pkg>` auf dem UI-Thread.
  - `verify(activity, path, version)`:
    - liest das geladene APK mit `getPackageArchiveInfo(path, GET_SIGNING_CERTIFICATES)`;
    - prüft, ob der Paketname gleich ist;
    - prüft, ob `getLongVersionCode()` größer ist als installiert;
    - prüft, ob `versionName` gleich der Release-Version ist;
    - prüft, ob die Signierer-Menge (`signingInfo.getApkContentsSigners()`) identisch ist.
    - Ein leerer Text bedeutet: in Ordnung.
  - `install()`:
    - `FileProvider.getUriForFile(activity, <pkg>+".fileprovider", file)`
    - `Intent.ACTION_VIEW` mit MIME-Typ `application/vnd.android.package-archive`, `ClipData.newRawUri` und `FLAG_GRANT_READ_URI_PERMISSION`
    - `startActivity` auf dem UI-Thread
- **FileProvider:** Es gibt keinen eigenen. Die Godot-Bibliothek (`godot-lib.template_*.aar`) bringt `androidx.core.content.FileProvider` mit, Authority `${applicationId}.fileprovider`, Pfade `@xml/godot_provider_paths` mit `files-path "/"`. Damit ist `user://` (= `/data/data/<pkg>/files`) abgedeckt.
- **Berechtigungen:** `INTERNET` und `REQUEST_INSTALL_PACKAGES`. Sie sind von Hand in `game/android/build/src/main/AndroidManifest.xml` eingetragen; zusätzlich steht `permissions/request_install_packages=true` im Exportprofil. Für den Mehrspieler kommen `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE` und `CHANGE_WIFI_MULTICAST_STATE` dazu.
- **Voraussetzung:** Gradle-Build (`gradle_build/use_gradle_build=true`, Vorlage in `game/android/build`, `.build_version = 4.6.1.stable`).
- **Abweichungen von der Godot-Vorlage:** Ein Vergleich mit `android_source.zip` zeigt genau diese Änderungen:
  - die Berechtigungen im Haupt-Manifest;
  - `org.gradle.daemon=false` in `gradle.properties`;
  - die neuen Dateien `Updater.java` und `NetHelper.java`.

  `build.gradle`, `config.gradle` und `settings.gradle` sind unverändert (minSdk 24, targetSdk 35).

## 2. Versionierung, Signierung, Build und Veröffentlichung

**Version**
- Sie steht an zwei Stellen, die gleich sein müssen:
  - `game/project.godot` → `config/version="0.2.31"` (die App liest diesen Wert zur Laufzeit);
  - `game/export_presets.cfg` → `version/name="0.2.31"`.
- `tools/build.ps1` prüft nur, ob die Namen gleich sind.
- **versionCode** (`version/code=33`) ist ein einfacher Zähler, der von Hand je Build um 1 erhöht wird (0.2.30 → 32, 0.2.31 → 33).
- **Nummernschema** (Nutzerentscheidung vom 03.10., `docs/IMPLEMENTIERUNG.md` Zeile 208):
  - Ein reguläres Release endet immer auf `.0` und erhöht die mittlere Stelle.
  - Betas zählen danach die letzte Stelle hoch.
  - Wird eine Beta zum Release, wird sie mit der nächsten `.0`-Nummer und höherem Code neu gebaut.
  - Bisher gibt es noch kein `.0`-Release. 0.2.27 wurde vorher als dieselbe APK (gleicher Digest) in beide Repos hochgeladen.

**Signierung**
- Fester Projekt-Debugschlüssel `.tools/draw2race-debug.keystore` (Alias `androiddebugkey`, Passwort `android`).
- Er wird über `GODOT_ANDROID_KEYSTORE_DEBUG_PATH`, `GODOT_ANDROID_KEYSTORE_DEBUG_USER` und `GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD` gesetzt.
- Exportiert wird mit `--export-debug`, das heißt Debug-Vorlage und debuggable.
- **Risiken:**
  - `.tools/` steht in `.gitignore`, der Schlüssel ist also nicht versioniert und nur lokal gesichert.
  - Geht er verloren oder wird er versehentlich gewechselt, lehnt `verify` jedes Update ab („Signatur passt nicht“), und Android würde es ohnehin verweigern. Nutzer müssten die App deinstallieren und verlören ihren Spielstand, denn `allowBackup=false`.
  - Ein Release-Schlüssel ist laut Doku noch offen.

**Build**
- `tools/setup.ps1` lädt Godot 4.6.1 und die Exportvorlagen nach `.tools/` und kopiert sie nach `%APPDATA%\Godot\export_templates\4.6.1.stable`.
- JDK 17 und SDK stehen in `%APPDATA%\Godot\editor_settings-4.6.tres` (`export/android/java_sdk_path`, `android_sdk_path`).
- `tools/build.ps1 -Target All|Windows|Android|Test` läuft so ab:
  1. Benannter Mutex `Global\Draw2RaceGodot`.
  2. Headless-Import. Danach Draw2Race-spezifische Anpassungen der Importeinstellungen (JPG→WebP, Mipmaps, WAV verlustfrei) mit erneutem Import.
  3. 16 Test-Suiten mit `--quit-after 180 --script res://tests/<t>.gd`. Bestanden heißt: Exitcode 0, keine `SCRIPT ERROR|ERROR:|FAIL:`-Zeilen und eine `RESULT:`-Zeile.
  4. Bei Bedarf werden die Godot-AARs aus `.tools/export/templates/android_source.zip` nach `game/android/build/libs` entpackt (nicht im Repo).
  5. Keystore-Umgebungsvariablen setzen, dann `--export-debug Android builds/Draw2Race.apk`.
  6. Versionsnamen vergleichen und nach `builds/Draw2Race-<version>.apk` kopieren.
  7. Lizenztexte nach `builds/` kopieren.

**Veröffentlichen**
- Das geht von Hand mit `gh`; es gibt kein Skript (`IMPLEMENTIERUNG.md` Zeile 207: `gh release create vX.Y.Z builds/Draw2Race-X.Y.Z.apk`).
- Was die Releases zeigen:
  - **Regulär** (`ShakieVan/Draw2Race`, öffentlicher Quellcode): Titel `Draw2Race 0.2.27`, Tag `v0.2.27`, Asset `Draw2Race-0.2.27.apk` (`application/vnd.android.package-archive`, etwa 308 MB). Der Tag zeigt auf den gepushten main-Stand (541599f).
    - Notizen: deutsches Markdown für Endnutzer mit fetten Zwischenüberschriften und Spiegelstrichen, am Ende Größe und Installationshinweis.
    - Releases bisher: v0.1.0 (Asset noch `Draw2Race.apk`, wird vom Updater ignoriert), v0.2.1–v0.2.8 und v0.2.27 (Latest).
  - **Beta** (`ShakieVan/Draw2Race-Beta`): Das Repo enthält nur `README.md` und `LICENSE` (ein Commit f78f20d, auf den alle Tags zeigen). Die Beschreibung verweist auf die regulären Releases.
    - Releases sind als **Pre-release** markiert, Titel `Draw2Race 0.2.31 (Beta)`, Tag `v0.2.31`, Asset `Draw2Race-0.2.31.apk` (etwa 313 MB). 22 Releases, das neueste vom 04.10. 07:32.
    - Notizen: kurz, mit Hinweisen wie „Alle Handys einer Runde brauchen dieselbe Version (0.2.31). Größe etwa 310 MB.“
  - Daraus abgeleiteter Befehl für Betas (nicht als Skript dokumentiert): `gh release create vX.Y.Z builds/Draw2Race-X.Y.Z.apk -R ShakieVan/Draw2Race-Beta --prerelease --title "Draw2Race X.Y.Z (Beta)" --notes …`
- **Beobachtung:** Das lokale `main` ist 4 Commits vor `origin/main` (0.2.28 bis 0.2.31). Der Quellcode der Betas wird also offenbar nicht mit jeder Beta gepusht.
- Commit-Konvention: `0.2.31 (Beta): <Zusammenfassung>`.

## 3. Bekannte Fallstricke und Lehren

1. **Download-Abbruch nach 30 s (Hotfix 0.2.26):** `HTTPRequest.timeout` begrenzt die gesamte Anfrage, nicht die Pause zwischen zwei Datenpaketen. Die Lösung ist der Stillstands-Wächter in `_process`. Alte Updater-Versionen können sich nicht selbst reparieren; 0.2.26 musste von Hand installiert werden.
   - Lehre: Der Updater muss ab der ersten öffentlichen Version stimmen. Ein Ausweichknopf „Im Browser herunterladen“ fehlt in Draw2Race und wäre eine sinnvolle Ergänzung.
2. **Gradle-Dienst:** Ohne `org.gradle.daemon=false` kehrte der Godot-Export nie zurück.
3. **Stiller Signaturwechsel:** Fehlt `.tools/draw2race-debug.keystore`, setzt `build.ps1` die Umgebungsvariablen einfach nicht (`if (Test-Path)` ohne `else`). Godot signiert dann mit `%APPDATA%\Godot\keystores\debug.keystore`, und das Update scheitert erst auf dem Handy.
   - Besser: Der Build bricht ab, wenn der Schlüssel fehlt.
4. **versionCode wird nicht geprüft:** Wer das Erhöhen vergisst, merkt es erst nach dem Download am Gerät („Keine neuere Version“).
   - Besser: Der Code wird aus der Version berechnet, oder `build.ps1` prüft ihn gegen das letzte Release.
5. **Alte Android-Versionen:** minSdk ist 24, aber `Updater.java` nutzt APIs ab 26/28:
   - `canRequestPackageInstalls` (API 26), `getLongVersionCode` und `signingInfo` (API 28).
   - Unter Android 7–8.1 gibt es dafür `NoSuchMethodError`. Das ist ein `Error`, den `catch (Exception)` nicht abfängt.
   - Abhilfe: `Build.VERSION.SDK_INT`-Prüfungen oder `PackageInfoCompat`, oder minSdk 28. Für Mitspieler mit alten Urlaubshandys ist das relevant.
6. **Pre-Release-Repo:** `/releases/latest` liefert dort 404. Deshalb wird die Liste abgefragt und 404 als „geantwortet“ gewertet.
7. **Keine Zusätze in der Version:** Nur `X.Y.Z` ist erlaubt. Eine Beta wird nur zum Release, indem man mit `.0` und höherem Code neu baut.
8. **Asset-Name muss exakt passen:** Die URL wird genau verglichen. GitHub ersetzt Leerzeichen und Sonderzeichen in Asset-Namen; ein Name wie „Mau-Mau Flip-1.0.0.apk“ würde deshalb abgelehnt.
9. **Liegengebliebene APK:** Nach einem erfolgreichen Update bleibt die geladene APK in `user://updates` liegen. `prune()` läuft nur beim nächsten Download (bei Draw2Race etwa 300 MB).
10. **GitHub-Abfragelimit:** Ohne Anmeldung gelten 60 Anfragen pro Stunde und IP. Im geteilten Urlaubs-WLAN hinter einem Router ist das schnell erreicht, und eine 403 wird als „Keine Verbindung.“ angezeigt. Die tägliche Drosselung mildert das.
11. Der Zeitstempel `update_last_check` wird vor der Anfrage gesetzt. Ein Fehlschlag sperrt die automatische Prüfung also für 24 h; die manuelle bleibt möglich.

## 4. Übernahme in Mau-Mau Flip

**Fast 1:1 übernehmbar**
- `game/scripts/updater.gd`. Die ganze Logik bleibt; nur Konstanten und Texte ändern sich (siehe unten). Es braucht einen Store mit `data: Dictionary` und `save()` (`ProgressStore` in `game/scripts/progress.gd`, Schlüssel `update_beta`, `update_release`, `update_last_check`).
- `game/android/build/src/main/java/com/godot/game/Updater.java`. Das Java-Paket bleibt `com.godot.game`: Das ist der Namespace der Godot-Vorlage und unabhängig von der `applicationId`. `JavaClassWrapper.wrap("com.godot.game.Updater")` bleibt also gleich. Anzupassen sind nur das ClipData-Label und die API-Prüfungen aus Fallstrick 5.
- Manifest-Ergänzungen (`INTERNET`, `REQUEST_INSTALL_PACKAGES`, die WLAN-Berechtigungen) und `org.gradle.daemon=false`. Einen FileProvider braucht man nicht.
- Integration: aus `main.gd` (`add_child(updater)`, `setup(store)`, `changed`, `check(false)` nur unter Android) und aus `hud.gd` (`update_dialog()` und der Menüknopf „Update ↓“).
- Tests: `game/tests/test_core.gd` Zeilen 177–205 (6 Prüfungen: Vergleich, gültiges Release, fremde URL/Entwurf/fehlende Prüfsumme, Pre-Release, Beta-Liste, Beta-Repo).
- `tools/setup.ps1` unverändert. Von `tools/build.ps1` das Gerüst: Mutex, Import, Test-Schleife, `libs`-Entpacken, Keystore-Variablen, Versionsvergleich, versionierte APK-Kopie.
- Die README-Vorlage des Beta-Repos und die Konventionen für Titel, Tag und Asset.

**Anzupassen**
- `REPOSITORY` und `BETA_REPOSITORY`, zum Beispiel `ShakieVan/Mau-Mau-Flip` und `ShakieVan/Mau-Mau-Flip-Beta` (ohne Leerzeichen).
- Asset-Name in `parse_release()` (`"Draw2Race-%s.apk"`), zum Beispiel `MauMauFlip-%s.apk`. Ihn identisch in `build.ps1` und den Tests ändern.
- `User-Agent` sowie die Statustexte („… für Draw2Race erlauben“) und das ClipData-Label in Java.
- **Paketname** `package/unique_name`, zum Beispiel `de.maumauflip.game`. Bindestriche sind nicht erlaubt, und der Name ist endgültig. Dazu `package/name="Mau-Mau Flip"`, `config/name` und `version/code` ab 1.
- **Keystore:** einen eigenen erzeugen, zum Beispiel `.tools/maumauflip.keystore`, und außerhalb von `.tools/` sichern. Ein Release-Export mit eigenem Release-Schlüssel (`GODOT_ANDROID_KEYSTORE_RELEASE_*`) ist kleiner und nicht debuggable; das muss aber vor dem ersten öffentlichen Release feststehen.
- `build.ps1`: den Mutex-Namen ändern und die Draw2Race-spezifischen Importanpassungen (Texturen/WAV) und die Test-Liste entfernen. Bei fehlendem Keystore abbrechen und versionCode prüfen oder berechnen.
- Bildschirmausrichtung: im Manifest und Exportprofil steht `landscape`. Für ein Kartenspiel neu entscheiden.

**Für die APK-Weitergabe durch den Host**
- `verify()` und `install()` lassen sich direkt wiederverwenden, auch für eine vom Host empfangene APK. Die SHA-256 kommt dann vom Host statt von GitHub.
- Den Pfad der eigenen APK liefert eine kleine Java-Ergänzung (`activity.getApplicationInfo().sourceDir`). Der Gradle-Export erzeugt eine einzelne APK. Die Mau-Mau-Flip-APK wird viel kleiner sein als die etwa 310 MB von Draw2Race.

**Projektordner:** Unter `E:\Documents\Programmierung\` gibt es zwei Ordner, `Mau-Mau Flip` und `Mau-Maul Flip`. Der Pfad enthält ein Leerzeichen. Den Gradle-Export sollte man dort früh testen, denn Draw2Race liegt in einem Pfad ohne Leerzeichen.