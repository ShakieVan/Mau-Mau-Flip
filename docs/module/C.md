# Modul C – Projekt, Android, App-Dienste, Bau

Stand 04.10.2026, Nachtschicht. Alles aus dem Auftrag ist umgesetzt. Die signierte Release-APK 0.1.1 läuft auf dem S21 und bleibt dort installiert (zuletzt die Platzhalter-Startszene, SHA-256 `a6f4e746…`). Die Update-Abfrage gegen das noch leere Beta-Repo hat funktioniert.

## Umgesetzt

### Projekt

**`game/project.godot`**
- Version 0.1.1, Compatibility-Renderer, Querformat (sensor), Autoload `App`.
- Symbol `res://assets/ui/icon_512.png`. Startbild `res://assets/ui/splash.png` auf `#0A0D20`.
- `keep_screen_on=true`, das ist Godots Standard, hier ausdrücklich gesetzt.
- Neu: `rendering/textures/canvas_textures/default_texture_filter=3` (Linear Mipmap), auf Vorschlag von Modul B (siehe Abweichung 9).

**`game/export_presets.cfg`**
- **Windows:** `../builds/MauMauFlip.exe`, pck eingebettet.
- **Android:**
  - Gradle-Bau, nur arm64-v8a.
  - Paket `de.maumauflip.game`, Name „Mau-Mau Flip“, Version 0.1.1, Code 1001.
  - Immersiv.
  - Berechtigungen nach Plan 9, also mit VIBRATE und WAKE_LOCK.
  - Launcher-Symbole: main, adaptiv vorn/hinten und zusätzlich monochrom.
- **Beide Profile:**
  - `include_filter="assets/web.zip,assets/fonts/*.txt"`
  - `exclude_filter="tests/*"`

**`game/scenes/main.tscn`**
- Nur ein Platzhalter mit eingebettetem Skript.
- Zeigt Version, Update-Status und Kanal.
- Modul F ersetzt ihn.

### Android: `game/android/`

**Gradle-Vorlage**
- Godot 4.6.1, entpackt wie Godots „Android-Build-Vorlage installieren“.
- Dazu gehören `.build_version` und `build/.gdignore`.
- `gradle.properties` mit `org.gradle.daemon=false`.

**Java-Helfer** aus Draw2Race 1.0.1 übernommen:
- `Updater.java`
  - Texte für Mau-Mau Flip.
  - `SDK_INT`-Prüfungen für API 26 (`canRequestPackageInstalls`) und API 28 (`getLongVersionCode`, `signingInfo`).
  - Überall `catch (Throwable)`.
- `NetHelper.java`: Multicast-Sperre heißt jetzt „MauMauFlipNetz“; überall `catch (Throwable)`.
- `ApkShare.java`: Thread heißt jetzt „MauMauFlip-ApkShare“; überall `catch (Throwable)`.
- `GodotApp.java`: aus der Vorlage, dazu: Fokusmarkierung aus, App-Link merken (siehe unten).
- `AppLink.java`: App-Link „In der App spielen“ (siehe unten).

**`src/main/AndroidManifest.xml`**
- Berechtigungen wie Draw2Race, dazu VIBRATE und WAKE_LOCK.
- `screenOrientation="sensorLandscape"`.

**App-Link „In der App spielen“ (Beta 1.0.2)**
- Adresse `maumauflip://join?h=<IP>&p=<Port>`. Die Spielseite öffnet sie auf Android als `intent://join?h=…&p=…#Intent;scheme=maumauflip;package=de.maumauflip.game;S.browser_fallback_url=…;end` (Rückfall: `http://<IP>:<Port>/?app=1`).
- Manifest: eigener `activity-alias` `.GodotAppLink` → `.GodotApp`, `exported="true"`, Filter VIEW + DEFAULT + BROWSABLE, `scheme="maumauflip"`, `host="join"`. Ein Alias, weil `.GodotApp` nicht exportiert ist; die bestehenden Einträge bleiben unverändert. Godots `src/release`-Manifest nennt nur `.GodotApp` und `.GodotAppLauncher`, der Alias kommt unverändert aus `src/main` dazu.
- `AppLink.java` merkt sich den Link: `GodotApp.onCreate` (nicht nach einer Wiederherstellung, nicht aus dem Verlauf) und `onNewIntent` rufen `remember(intent)` auf. `take()` liefert ihn einmal und vergisst ihn dann.
- `NetAndroid.take_app_link()` holt ihn ab (PC und Tests: `app_link_stub`). `parse_app_link()` liefert `{ok, address, port, error}` und nimmt nur private IPv4-Adressen (10/8, 172.16/12, 192.168/16) mit Port 1–65535.
- `App.check_app_link()` läuft beim Start, beim Fortsetzen und bei Fokus. Es löst `app_link_received` aus. Das Hauptmenü holt den Link mit `take_pending_link()` und gibt ihn an `JoinScreen.handle_link(nav, link)` weiter.
- `handle_link` macht Folgendes:
  - Ungültiger Link: nur ein Hinweis.
  - Schon mit genau diesem Spiel verbunden: Hinweis, sonst nichts.
  - Lobby, Partie oder andere Verbindung offen: Rückfrage „Anderem Spiel beitreten?“ (Wechseln/Bleiben).
  - Sonst: Hauptmenü → „Im WLAN spielen“ → `JoinScreen.direct_to(ip, port)`, das ohne Suche verbindet. Fehlt der Name, fragt es zuerst danach („NameFrage“).
- Test: `tests/test_app_link.gd`.

### App-Dienste: `game/scripts/app/`

| Datei | Klasse | Inhalt |
|---|---|---|
| `app.gd` | Autoload `App` | API wie im Auftrag; Update-Prüfung beim Start nur auf Android; Diagnose ins Log; `selftest()` |
| `settings.gd` | `AppSettings` | `user://einstellungen.json`, sofort gespeichert über `.tmp` und Umbenennen, `.bak` als Rückfall; Werte werden geprüft; Namensfilter wie Draw2Race |
| `updater.gd` | `Updater` | aus Draw2Race; Repos und Asset für Mau-Mau Flip, Beta-Standard nach Version, 403 → „GitHub-Limit erreicht – später erneut versuchen“, `open_release_page()` |
| `apk_share.gd` | `ApkShare` | aus Draw2Race; `MauMauFlip-<version>.apk`, neu: `server_info()` für `/apk` |
| `net_android.gd` | `NetAndroid` | aus Draw2Race; eigene IPv4-Hilfen, damit es nicht von `NetProtocol` abhängt |
| `sound.gd` | `AppSound` | `play(name)` mit sechs Stimmen; Lautstärke nach `mau_ton`; fehlende Dateien bleiben still |

### Werkzeuge: `tools/`

Alle Skripte sind UTF-8 mit BOM gespeichert. Windows PowerShell 5.1 liest Dateien ohne BOM als ANSI, und „–“ bricht dann das Parsen.

**`setup.ps1`**
- Lädt Godot 4.6.1.
- Holt aus dem Vorlagenarchiv nur die gebrauchten Exportvorlagen nach `.tools/export/templates/`. Mit `-TemplatesArchive <tpz>` wird ein vorhandenes Archiv genommen statt zu laden.
- Ergänzt in `%APPDATA%\Godot\export_templates\4.6.1.stable` nur fehlende Dateien und überschreibt nie.
- Installiert die Gradle-Vorlage und zieht `libs/*.aar` nach. Eigene Dateien überschreibt es nie, auch nicht mit `-ReinstallAndroidTemplate`.

**`build.ps1 -Target Test|Windows|Android|Web|All [-SkipTests]`**
- Hält den Mutex `Global\MauMauFlipGodot`.
- Trägt `version/name` und `version/code` aus `project.godot` ins Exportprofil ein (X·1 000 000 + Y·1 000 + Z).
- **Web:** packt `webclient/` nach `game/assets/web.zip`.
  - Über .NET `ZipArchive`, Pfade relativ mit „/“, keine Ordnereinträge, keine versteckten Dateien.
  - Läuft auch vor Test, Windows und Android.
- **Test:** führt alle `test_*.gd` außer `_lang`/`_shot` nacheinander aus.
  - Jeder Lauf hat eine Zeitgrenze.
  - Bestanden heißt: Exitcode 0, eine RESULT-Zeile und keine Zeile mit `SCRIPT ERROR`, `ERROR:` oder `FAIL:`.
  - Danach folgt eine Zusammenfassung; bei einem Fehler bricht der Bau ab.
- **Android:**
  - Vorab prüft keytool, ob der Schlüssel zum festgeschriebenen SHA-256 `85d6f9d9…15cd` passt. Fehlt er, bricht der Bau ab.
  - Release-Export über `GODOT_ANDROID_KEYSTORE_RELEASE_*`. Alias und Passwort kommen aus der properties-Datei, das Passwort steht nie auf einer Befehlszeile.
  - Danach `apksigner verify --print-certs`: genau ein Unterzeichner, nämlich der Projektschlüssel.
  - `aapt dump badging` prüft Paket, Code und Name sowie „nicht debuggable“.
  - Erst dann entsteht `builds/MauMauFlip-<version>.apk`, dazu der Baubeleg `builds/MauMauFlip-<version>.build.json` (Hash, Tests ja/nein).

**`release.ps1 -Channel beta|release [-SkipBuild] [-WhatIf]`**
- **Prüft:**
  - Versionsschema: Beta Z ≠ 0, Release Z = 0.
  - `docs/release_notes/X.Y.Z.md` ist vorhanden.
  - Der Tag ist im Ziel-Repo noch frei.
  - Der Baubeleg passt zur APK und ist mit Tests entstanden.
  - Signatur und `aapt`-Angaben.
- **Legt an:**
  - Ist das Beta-Repo leer, zuerst README.md und LICENSE. Der README-Text ist an Draw2Race-Beta angelehnt.
  - Dann `gh release create vX.Y.Z MauMauFlip-X.Y.Z.apk`, Titel „Mau-Mau Flip X.Y.Z (Beta)“, Notizen aus der Datei. Beta mit `--prerelease`, Release mit `--latest`.
- **Prüft nach**, wie der Updater: genau ein Asset, Größe, `digest` = sha256 und die exakte URL.
- Die Probleme werden gesammelt und am Ende zusammen gemeldet.

### `.gitignore`

Wie Draw2Race für die erzeugten Gradle-Teile. Zusätzlich ausgeschlossen:
- `game/android/build/src/debug/` und `src/release/`: Der Export erzeugt sie bei jedem Lauf (Manifest, Symbole, Namen).
- `game/assets/web.zip`: Der Bau erzeugt sie.

## Schnittstelle (für andere Module)

```gdscript
App.settings.get_value(key, fallback = null)   # gespeichert → Standardwert aus settings.gd → fallback
App.settings.set_value(key, value) -> bool      # prüft und speichert sofort; false = ungültig (nichts geändert) oder Speicherfehler
App.settings.set_values(dict) / reset(key) / has_value(key) / player_name() / remember_names(names)
AppSettings.clean_name(text) / filter_name(text)   # Namensfilter (max. 12 Zeichen) wie Draw2Race
signal App.settings.changed(key, value)
```

**Schlüssel und Standardwerte**

| Schlüssel | Standard |
|---|---|
| `name` | `""` |
| `mau_ton` | `"normal"` |
| `toene` | `"aus"` (Spieltöne aus / leise / normal) |
| `hervorheben` | `true` („Spielbare Karten hervorheben“, nur dieses Gerät, AGENTS.md 24) |
| `vibration` | `true` |
| `effekte` | `"voll"` |
| `beta` | `true`, wenn die Version nicht auf `.0` endet |
| `sortierung` | `"farbe"` |
| `regeln` | `{}` |
| `letzte_namen` | `[]` (höchstens 12) |

- Unbekannte Schlüssel werden unverändert gespeichert.
- `beta` wird erst gespeichert, wenn jemand den Kanal umschaltet. Bis dahin folgt er der installierten Version.

```gdscript
App.sound.play(name) -> bool        # "mau"/"mau_mau" nach mau_ton (aus/-12/-2 dB), sonst nach toene (aus/-12.5/-4.5 dB, Standard aus); res://assets/sfx/<name>.ogg|.wav
App.vibrate(ms, strength = -1.0)    # nur mit Einstellung vibration, nur Handy
App.set_keep_screen_on(on) / App.keep_screen_on()
App.version() -> String / App.is_android() -> bool
await App.selftest() -> bool        # Gerätetest der Java-Helfer samt APK-Kopie (Log), z. B. für ein verstecktes Entwicklermenü

App.updater: status, release {version, notes, size, sha256, url, beta}, busy, percent, apk_ready, signal changed
             check(manual), available(), download(), install(), can_install(), open_permission(),
             beta(), set_beta(on), open_release_page()   # „Im Browser herunterladen“
             statisch: compare_versions, valid_version, version_code, parse, failure_text, release_page

App.apk_share: server_info() -> {path, size, sha256, name, version} | {}   # erster Aufruf startet die Kopie; danach poll()/changed
               share(), status, percent, offer(), release_file(), available()
               source_override = {"path": …, "version": …}   # am PC und in Tests statt der installierten APK

NetAndroid (statisch): state(), interfaces(), summary(s), bind_wifi(), bind_network(handle), unbind(), multicast(on),
             host_plan(s, sockets), join_binding(s, address), wifi_*(), hotspot_*(), in_subnet(), ipv4_to_int(), directed_broadcast(), usable_ipv4()
```

**Zum Android-Log** (`adb logcat -s godot`)
- Beim Start erscheinen die Netzlage, der Status der Java-Helfer und Größe/SHA-256 der eigenen APK.
- Die Prüfsumme wird einmal je installierter Version berechnet und zwischengespeichert.
- Bei jedem neuen Update-Status erscheint eine Zeile `Updater: …`.

## Abweichungen vom Plan bzw. Auftrag

1. **Namen der Launcher-Symbole.**
   - Modul B hat sie als `android_adaptive_foreground_432.png`, `android_adaptive_background_432.png` und zusätzlich `android_adaptive_monochrome_432.png` angelegt, nicht als `android_fg_432.png`/`android_bg_432.png`.
   - Eingetragen sind die tatsächlichen Namen, Monochrom für Android-13-Themensymbole eingeschlossen.
2. **Java-Helfer aus Draw2Race 1.0.1 statt 1.0.0.**
   - 1.0.1 enthält bereits die geforderten `SDK_INT`-Prüfungen und `catch (Throwable)` im Updater.
   - NetHelper und ApkShare fangen jetzt ebenfalls Throwable.
3. **Ausrichtung.**
   - Im Manifest steht wie gefordert `sensorLandscape`.
   - Godot ersetzt das beim Export für `orientation=4` durch `userLandscape`. Das bedeutet ebenfalls beide Querlagen, beachtet aber die Drehsperre. Es ist Godots Zuordnung, ich habe sie gelassen.
4. **`get_value`-Vorrang:** gespeicherter Wert → Standardwert aus `settings.gd` → Vorgabe des Aufrufers. So zeigt z. B. `get_value("beta", false)` trotzdem den versionsabhängigen Standard.
5. **403-Text:** „GitHub-Limit erreicht – später erneut versuchen.“. Ist die Wartezeit bekannt, folgt „(in etwa N Minuten)“.
6. **Neu im Updater:**
   - Ohne neue Prüfung (höchstens einmal am Tag) zeigt der Status „Zuletzt geprüft: TT.MM.JJJJ, HH:MM.“ statt „Noch nicht geprüft.“.
   - `version_code()` und `default_beta()` als statische Funktionen.
7. **Neu:** `ApkShare.server_info()` für `/apk`, `App.selftest()` und die Startdiagnose im Log.
   - Startparameter, etwa `--esa command_line_params`, erreichen eine Release-APK nicht: Godot verwirft sie für exportierte Activities, das habe ich im Bytecode von `GodotActivity` geprüft. Ein Selbsttest per adb ohne Bedienung geht daher nicht.
   - `selftest()` habe ich einmal über einen Zwischenbau auf dem S21 ausgeführt: OK.
8. **`build.ps1` setzt auch `version/name`** aus `project.godot`, statt bei Abweichung abzubrechen.
   - Zusätzlich gibt es `-SkipTests` und den Baubeleg. `release.ps1` verlangt einen Bau mit Tests.
   - Vor dem Export prüft keytool den Schlüssel, nach dem Export prüft `aapt` Paket und Version.
9. **Projektstandard Texturfilter „Linear Mipmap“** (B, Abweichung 2): Damit greifen die Mipmaps der Karten im Gegnerfächer.
   - Am PC habe ich ein Kontrollbild mit echtem Renderer geprüft: Texturen ohne Mipmaps (UI-Symbole) werden korrekt gezeichnet, verkleinerte Karten glatt.
   - Modul F kann je Node anders setzen.
10. **Startbild:** `boot_splash/fullsize` gibt es in 4.6 nicht mehr. Der Standard `stretch_mode = keep` (= 1, geprüft) entspricht B's Wunsch „fullsize“.
11. **`%APPDATA%\Godot\export_templates\4.6.1.stable`:**
    - `setup.ps1` hat dort `version.txt`, `web_nothreads_release.zip` und `web_nothreads_debug.zip` ergänzt.
    - Es sind offizielle 4.6.1-Dateien und nur Ergänzungen; nichts wurde überschrieben. Das Verzeichnis teilt sich das Projekt mit Draw2Race.
12. **`docs/BETA1_PLAN.md`, Abschnitt „Abweichungen“:** nicht bearbeitet, weil das nicht meine Datei ist. Bitte von dieser Liste übernehmen.

## Tests (headless, `tools/godot_run.ps1`)

| Test | Ergebnis | Inhalt |
|---|---|---|
| `test_app_updater.gd` | 29 ok | Versionsvergleich und -schema, versionCode-Formel samt Abgleich mit dem Exportprofil, Beta-Standard, Release-Parsing (Release/Beta-Repo, Vorabversion, Asset-Name genau einmal, Digest sha256/64 Hex, URL, Entwurf, Größe), 403/429/kein Netz/502, Prüfzeitpunkt erst nach Erfolg, leeres Repo, Aufräumen der APK nach dem Update, Kanalwechsel, Status „Zuletzt geprüft“ |
| `test_app_settings.gd` | 22 ok | Standardwerte, sofort speichern und laden, Kopien statt Verweise, ungültige Werte, Beta erst nach Umschalten gespeichert, `set_values`/Signal, `.bak`-Rückfall, Namensfilter, letzte Namen, Speicherfehler |
| `test_app_services.gd` | 24 ok | Tonlautstärken und Stummschaltung, fehlende Dateien still, `mau.ogg` spielt; ApkShare-Ersatzdatei: `server_info` (path/size/sha256/name); NetAndroid-Rückfall am PC; Autoload-API; keine Update-Prüfung am PC |
| `test_app_net_android.gd` | 16 ok | IPv4-Hilfen und die Hotspot/WLAN-Einordnung mit den Geräte-Werten aus Draw2Race |

**`build.ps1 -Target Test`**
- Der Läufer funktioniert: 20 Testskripte in etwa 5 Minuten, Zusammenfassung, Abbruch bei Fehler.
- Stand 22:10: Alle bestehen außer `test_net_session` (Modul D, 13 FAIL).
- Davor meldete `test_net_server` zeitweise eine Engine-Fehlerzeile `ERROR: Condition "!is_open()"` aus `get_available_bytes` (`test_net_server.gd:500`, `_side_job`). Sie zählt als Fehlschlag.

**Weitere Prüfungen**
- **`build.ps1 -Target Android -SkipTests`:**
  - Signierte Release-APK, 48,7 MB.
  - Signatur: Projektschlüssel.
  - `de.maumauflip.game` 0.1.1 (1001), minSdk 24, targetSdk 35, nicht debuggable.
  - Die Java-Klassen liegen im Dex.
  - `web.zip` und `OFL.txt` sind im Paket.
- **`build.ps1 -Target Windows -SkipTests`:** `builds/MauMauFlip.exe`.
- **`-Target Web`:** in einer Kopie mit versteckten Dateien geprüft. Einträge mit „/“, keine Ordner, versteckte Dateien ausgelassen.
- **`release.ps1 -Channel beta -WhatIf`** im Projekt meldet zu Recht:
  - Die Notizen `docs/release_notes/0.1.1.md` fehlen.
  - Die APK entstand ohne Tests.
- **Dasselbe in einer Kopie mit Notizen und Baubeleg „mit Tests“:**
  - Zeigt „WhatIf“ für README.md, LICENSE und `gh release create … --prerelease`.
  - `-Channel release` meldet „X.Y.0 erwartet“ und „Haupt-Repo leer“.
- **Gerätetest S21** (SM-G991B, Android 15):
  - `adb install -r`, danach Start per `monkey`.
  - Querformat, Vollbild, keine Fehler im Log.
  - Log beim ersten Start: `Updater: Suche nach Updates … (Kanal Beta)`, danach `Updater: Noch kein passendes Release veröffentlicht. (Kanal Beta)`. Das Beta-Repo ist leer, das Haupt-Repo meldet 404.
  - Java-Helfer: NetHelper, Updater und ApkShare antworten im Release-Paket.
  - Selbsttest (Zwischenbau): APK-Kopie 49 MB in 377 ms, mit FileAccess lesbar, SHA-256 gleich der gebauten Datei.
  - Gewährt sind VIBRATE und WAKE_LOCK.
  - Am Gerät habe ich nur das Paket `de.maumauflip.game` installiert. Es bleibt installiert.

## Offene Punkte und Hinweise

**Modul D**
- `test_net_session` scheitert noch.
- Die Engine-Fehlerzeile in `test_net_server` vermeiden; der Bau wertet `ERROR:`-Zeilen streng aus.
- `/apk`: `App.apk_share.server_info()` aufrufen, bis es nicht mehr leer ist. Den Pfad liest `FileAccess`; nach dem Spiel `release_file()`.
- Für Bindung und Multicast-Sperre `NetAndroid` nutzen.

**Modul F**
- `scenes/main.tscn` ersetzen.
- Update-Dialog:
  - `App.updater` zeigt `status`, `release.notes` und `percent`.
  - Knöpfe: Prüfen (`check(true)`), Laden (`download()`), Installieren (`install()`), „Im Browser herunterladen“ (`open_release_page()`).
  - Schalter „Beta-Kanal“: `set_beta()`.
- „App teilen“: `App.apk_share.share()`, Status über `changed`.
- Optional ein verstecktes Entwicklermenü mit `App.selftest()`.

**Modul G / F:** Während Partie und Lobby kann `App.set_keep_screen_on(true)` gesetzt werden. Der Projektstandard ist ohnehin „an“.

**Koordinator**
- Vor der Veröffentlichung:
  - `docs/release_notes/0.1.1.md` anlegen.
  - `tools/build.ps1 -Target Android` **mit** Tests (alle grün), dann `tools/release.ps1 -Channel beta`.
- `release.ps1` legt im leeren Beta-Repo zuerst README.md und LICENSE an.
- Ins Repo gehören:
  - die Gradle-Vorlage samt Java-Helfern, `res/` und `.build_version`
  - nicht: `libs/`, `build/`, `src/debug|release/` (laut `.gitignore`)
- `.tools/` (Godot, Vorlagen, **Release-Schlüssel**) bleibt lokal. Den Schlüssel außerhalb des Projekts sichern (AGENTS.md 10).

**Die adb-Verbindung zum S21 war wackelig**
- Der adb-Server wurde mehrfach neu gestartet, vermutlich durch parallele Agenten mit anderen adb-Fassungen.
- Das Gerät erscheint abwechselnd als `192.168.178.8:35829` und als mDNS-Name `adb-R5CT1232BEE-6MV80O (2)._adb-tls-connect._tcp`.
- Für Skripte: die Seriennummer per `adb devices -l | grep SM_G991B` ermitteln und jeden Aufruf mit Zeitgrenze versehen. `logcat -c` wartet sonst unbegrenzt auf das Gerät.

**Windows-Symbol:** Der Windows-Build hat noch kein eigenes Symbol. Dafür wären eine `.ico` und `modify_resources` mit rcedit nötig.
