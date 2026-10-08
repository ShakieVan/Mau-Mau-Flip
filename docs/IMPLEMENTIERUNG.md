# Mau-Mau Flip 0.1.1 — Implementierungsstand

05.10.2026, erste Beta. Gebaut nach `docs/BETA1_PLAN.md` in den Modulen A–G, E und S (je ein Bericht in `docs/module/`). Maßgeblich ist der Code; diese Datei fasst den Stand zusammen.

## Enthalten

- **Regelwerk** (Modul A): 112 doppelseitige Karten, vollständige Regeln nach der Fassung 2024 als Standard. Deterministisch aus einem Seed.
  - Regeloptionen und Voreinstellungen „offiziell“, „familie“, „mau_mau“, „klassisch500“. Dazu gehören bis zum Letzten spielen, Stapeln, Bluff/Anzweifeln, Ziehen bis spielbar, Mau-Ruf mit Erwischen und Rückseiten sichtbar/verdeckt.
  - Jeder Platz bekommt nur seine Sicht (`view_for`, `events_for`); fremde Vorderseiten und der Seed verlassen den Gastgeber nie.
  - Computergegner in drei Stufen, die nur auf ihrer eigenen Sicht entscheiden.
  - Speichern und Fortsetzen über `to_dict`/`from_dict`.
- **Drei Spielarten mit derselben Tischoberfläche** (Modul G, `G.md`):
  - Übungsspiel: 1 Mensch gegen 1–5 Computergegner (`LocalTable "solo"`).
  - Weitergeben: 2–10 Menschen an einem Gerät, optional mit Computergegnern (`LocalTable "pass"`). Vor jedem Menschenwechsel kommt ein Sichtschutz ohne Karten.
  - Netzwerk: `HostTable` als Gastgeber, `ClientTable` für App-Mitspieler, Browser-Gäste über dieselbe Sitzung.
- **Netz** (Modul D): ein TCP-Port 24690 (Rückfall bis 24699) für Seiten, APK-Download und WebSocket, mit eigenem HTTP/1.1- und WebSocket-Server in GDScript.
  - TLS-Versuche werden sofort abgewiesen.
  - UDP-Suche über Port 24692, Wiederverbinden per Token, Sitzordnung durch den Gastgeber.
  - WLAN- bzw. Hotspot-Bindung wie bei Draw2Race.
- **Browser-Client „Lite“** (Modul E, `webclient/`): reines HTML/CSS/JS ohne Build-Schritt und ohne Abhängigkeiten von außen. Er spielt vollständig mit, ist im Querformat nutzbar, verbindet sich selbst neu und meldet Fehler an den Gastgeber.
- **Oberfläche** (Module F1a, F1b, F2) im Entwurf „Papier & Neon“:
  - Hand in drei Stufen: Fächer, Lupe, Bogen-Karussell.
  - Gesten: ausspielen, umsortieren, Hilfe per „?“.
  - Sortieren nach Farbe, Wert, Punkten oder von Hand; eigene Rückseiten ansehen.
  - Tisch mit gedrehter Sitzordnung, Richtungsring und Tag/Nacht-Flip.
  - Tischregie mit Effekten je Ereignis und Joker-Strahlen aus der sichtbaren Kontur.
  - QR-Code in eigenem GDScript.
  - Bildschirme: Hauptmenü, Einrichtungen, Lobby, Beitreten, Regeln, Einstellungen.
- **App** (Modul C):
  - Updater mit Release- und Beta-Kanal.
  - „App teilen“ über das Teilen-Menü und `/apk` beim Gastgeber.
  - Einstellungen, Vibration, Bildschirm an.
  - Gradle-Vorlage mit Java-Helfern; Release-Signatur mit dem Projektschlüssel.
- **Töne** (Modul S und Nutzerentscheidungen 20/21):
  - „Mau!“ und „Mau-Mau!“ sind die Aufnahmen des Nutzers („Mao“, „Mao-Mao“), aufbereitet mit `tools/make_mau_aufnahmen.sh`. Sie spielen auf allen Geräten am Tisch, außer der Mau-Ton ist dort aus.
  - Die übrigen Spieltöne sind synthetisch und stehen ab Werk auf „aus“.
  - Die synthetischen Mau-Klänge und die Einstellung „Mau-Klang“ entfallen.

## Modulübersicht

| Ordner / Datei | Modul | Aufgabe | Bericht |
|---|---|---|---|
| `game/scripts/rules/` (6 Dateien, ~2 400 Zeilen) | A | `CardDB`, `RuleConfig`, `MauGame`, `MauBot`, `RulesText`, `RulesFixture` | `docs/module/A.md` |
| `game/assets/cards/`, `fonts/`, `ui/`, `tools/cards/` | B | Kartenbilder (108 Gesichter + Rückseite), Schriften (OFL), Logo, Symbole | `B.md` |
| `game/scripts/app/`, `game/android/`, `tools/*.ps1` | C | Autoload `App`, Einstellungen, Updater, ApkShare, NetAndroid, Ton; Bau und Veröffentlichung | `C.md`, `S.md` |
| `game/scripts/net/` (8 Dateien, ~2 800 Zeilen) | D | `NetServer`, `NetProtocol`, `NetHostSession`, `NetClient`, `NetDiscovery`, `NetAddresses` | `D.md` |
| `webclient/` (~3 900 Zeilen) | E | Browser-Client „Lite“, Selbsttest `?autotest=1`, Schein-Gastgeber `?mock=1` | `E1.md`, `E2.md` |
| `game/scripts/ui/` (29 Dateien) | F1a, F1b | Hand, Karten, Tisch, Regie, Effekte, QR-Code, Thema | `F1a.md`, `F1b.md` |
| `game/scripts/ui/screens/`, `table_screen.gd`, `scenes/main.tscn` | F2 | Bildschirme und Tischszene, Verdrahtung mit Modul G | `F2.md` |
| `game/scripts/game/` (5 Dateien, ~1 100 Zeilen) | G | `TableSource`, `GameTable`, `LocalTable`, `HostTable`, `ClientTable` | `G.md` |
| `game/assets/sfx/`, `webclient/sfx/`, `audio/` | S | Spieltöne, Mau-Aufnahmen, `sfx/index.json` für den Browser | `S.md` |

## Prüfen

`tools/build.ps1 -Target Test` packt den Browser-Client, importiert das Projekt und führt alle `game/tests/test_*.gd` aus (außer `*_lang*` und `*_shot*`).

- **Zwei Spuren:** Reine Tests (`test_rules_*`, `test_ui_*`, `test_card_view`, `test_smoke`, `test_game_local`, `test_b_assets`) laufen gleichzeitig in mehreren Godot-Prozessen, jeder mit eigenem `user://` (APPDATA in einem Wegwerfordner). Netz-, Lobby-, Bildschirm- und App-Tests laufen nacheinander in einer eigenen Spur mit dem echten `user://`. Neue Testskripte, die nicht zum Muster passen, landen automatisch in der seriellen Spur (`Test-Kind` in `tools/build.ps1`).
- **Teile:** Lange Dauerläufe (`test_rules_bots_long`, `_swap`, `_views_long`, `_gamble`, `_discard`) laufen in Teilen mit der Umgebungsvariable `TEIL=k/n` (`game/tests/teil.gd`): Partie i gehört zu Teil i % n + 1, feste Einzelprüfungen zu Teil 1. Alle Teile zusammen prüfen dieselben Startwerte; ein Einzelaufruf ohne `TEIL` prüft alles.
- **Sperre:** Der Bau hält `Global\MauMauFlipGodot` einmal und startet seine Testprozesse ohne erneutes Sperren; fremde Godot-Läufe (`godot_run.ps1`, `godot_import.ps1`) warten wie bisher.
- **Testergebnis-Cache:** Nach einem vollständig grünen Lauf merkt sich der Bau die Prüfsumme des Stands (alle von git erfassten oder erfassbaren Dateien in `game/` und `webclient/`, dazu `tools/build.ps1`; Erzeugtes wie `.godot/`, `android/build/build/` und `web.zip` nicht) in `.tools/test_cache.json`. Ist der Stand unverändert, überspringen `-Target Test`, `Android` und `All` die Tests („Tests für diesen Stand schon grün, übersprungen“); der Baubeleg vermerkt dann `tests: true, tests_cached: true`. Jede Änderung einer erfassten Datei erzwingt neue Tests. `-NoTestCache` lässt die Tests immer laufen, `-SkipTests` lässt sie wie bisher weg (`tests: false`), `-Parallel n` legt die Zahl paralleler Prozesse fest. Die Laufzeiten je Lauf stehen in `.tools/test_times.json` (längste zuerst beim nächsten Mal).

Bestanden heißt:
- Exitcode 0,
- eine Zeile `RESULT: n ok`,
- keine Zeile mit `SCRIPT ERROR`, `ERROR:` oder `FAIL:`.

Erwartete Fehlpfade melden sich deshalb als `WARNING`, z. B. `MauGame.create` mit ungültiger Spielerzahl. UI-Tests beenden sich über `game/tests/clean_exit.gd`: Töne anhalten, Knoten freigeben, 0,3 s warten, statische Zwischenspeicher leeren. Sonst meldet Godot „resources still in use at exit“.

**Stand 05.10.2026, abends: 34 Testläufe, 3 919 Einzelprüfungen, alle grün** (Zahl der Prüfungen je Lauf):

| Bereich | Testlauf | Prüfungen |
|---|---|---|
| A Regelwerk | `test_rules_cards` · `test_rules_play` · `test_rules_views` · `test_rules_bots` | 655 · 1053 · 66 · 190 |
| A lang | `test_rules_bots_long` (10 000 Partien, ~5 min) · `test_rules_views_long` (~1 min) | 190 · 66 |
| B Assets | `test_b_assets` | 120 |
| C App | `test_app_services` · `test_app_settings` · `test_app_updater` · `test_app_net_android` · `test_smoke` | 26 · 22 · 29 · 16 · 1 |
| S Töne | `test_app_sound` | 62 |
| D Netz | `test_net_protocol` · `test_net_server` · `test_net_session` · `test_net_binding` | 115 · 95 · 80 · 17 |
| G Spielsteuerung | `test_game_local` · `test_game_net` | 93 · 50 |
| F1a Hand | `test_ui_hand_layout` · `_gesture` · `_sort` · `_view` · `_fixes` · `test_card_view` | 79 · 42 · 21 · 74 · 70 · 5 |
| F1b Tisch | `test_ui_table_layout` · `_director` · `_view` · `_smoke` · `_qr` · `_theme` | 145 · 19 · 61 · 2 · 140 · 22 |
| Mau für alle | `test_ui_mau` (Ton bei jedem Ereignis, Sprechblasen-Varianten, Entprellung) | 73 |
| F2 Bildschirme | `test_screens_flow` | 46 |
| E Browser-Vertrag | `test_web_contract` (Sichten, Ereignisse, Aktionen, Auslieferung, `sfx/index.json`, Mau-Blasen im Browser) | 174 |
| Gerätetest-Nachbesserung | `test_screens_device_fixes` (Lobby → Tisch mit echtem Server und App-Gast, Zurück-Taste doppelt/gehalten, Wischen über Karten und Knöpfe, „Bereit“ sichtbar, Hintergrund-Zwischenbild) | 53 |

Dauer des Laufs: etwa 8 Minuten, davon 4¾ Minuten `test_rules_bots_long` und knapp 1 Minute `test_rules_views_long`. Ausgaben ohne `ERROR:` und ohne „resources still in use“. Erwartete `WARNING`-Zeilen gibt es nur in `test_app_settings` (abgelehnte Werte) und `test_rules_play` (ungültige Spielerzahl).

Am 05.10. behoben, damit alle Läufe grün sind:
- `test_rules_play`: `MauGame.create` meldet die ungültige Spielerzahl als Warnung statt als Fehler.
- `test_screens_flow`, `test_ui_table_smoke`, `test_ui_table_view`: sauberes Beenden über `clean_exit.gd`. Ursache war ein beim `quit()` noch laufender Ton (Sieg, Flip).
- `test_web_contract`, `test_app_sound`: `webclient/sfx/index.json` gibt es jetzt verbindlich. Es nennt mindestens `mau` und `mau_mau`, und jede genannte Datei liegt vor.
- `test_app_services`, `test_app_sound`, `test_screens_flow`: an die Nutzerentscheidungen 20/21 angepasst. Dazu gehören Mau-Lautstärke −2/−12 dB, Spieltöne ab Werk aus, keine Gerätesperre mehr und Entprellung je Platz.

Nachbesserung nach dem Gerätetest (06.10., `docs/geraetetest/0.1.1/BERICHT.md`, Abschnitt „Nachbesserung“):
- **H1, WLAN-Start:** `NetServer`, `NetHostSession`, `NetDiscovery` und `NetClient` stoppen nicht mehr in `_exit_tree`. Das löste auch das Umhängen der Spielsteuerung von der Lobby an den Tisch aus. Jetzt stoppen sie erst, wenn sie am Ende des Frames noch draußen sind, oder beim Freigeben (`NOTIFICATION_PREDELETE`).
- **M1, Zurück-Taste:** Android meldet einen Druck als `KEY_BACK` und 1 ms später als `NOTIFICATION_WM_GO_BACK_REQUEST`, beim Halten wiederholt. `ScreenNav.back_pressed()` fasst Meldungen im gleitenden Fenster von 650 ms zusammen. Eine offene Lobby-Rückfrage schließt mit Zurück.
- **M2, Wischen:** `ScreenKit.scroller()` liefert `ScreenKit.TouchScroll`. Karten, Zeilen und Knöpfe darin reichen die Geste weiter (`MOUSE_FILTER_PASS`), die Totzone beträgt 14 px.
- **M3, Bildrate:**
  - `TableBackground` rechnet den Shader in ein Zwischenbild in Basisauflösung, 20-mal pro Sekunde und bei Änderungen sofort.
  - Mobil gilt `Engine.max_fps = 60` (`App.MOBILE_MAX_FPS`).
  - Messung im Ruhezustand: `tests/perf_table.gd` (mit Renderer, kein Test).
- **N1:** Der Regeltext in der Gast-Lobby blättert für sich, „Bereit“ bleibt sichtbar.

**Weitere Prüfungen außerhalb des Testlaufs**
- **Kontrollbilder** mit echtem Renderer (`tools/godot_run.ps1` ohne `-Headless`):
  - `test_ui_hand_shots.gd`, `test_ui_table_shots.gd`, `test_ui_mau_shots.gd` (Mau-Blasen)
  - Bilder in `docs/module/F1a_*.png`, `F1b_*.png`, `E1_*.png`, `E2_*.png`.
- **Browser-Client:**
  - `bash tools/webtest/run_webtest.sh`: Autotests gegen den Schein-Gastgeber.
  - `tools/webtest/web_e2e.ps1`: echter Chrome gegen den Godot-Gastgeber `game/tests/web_host.gd`; mit `-Adb` im Chrome des S10.
- **Netz im Browser:** `tools/nettest/browser_test.ps1` mit Chrome am PC und auf dem S10 (über `adb reverse`).
- **Gerät S21:** signierte Release-APK installiert und gestartet, Updater gegen das Beta-Repo (Modul C, Zwischenstand vom 04.10.).

## Bekannte offene Punkte

- **Gerätetest im WLAN:** Der erste Gerätetest vom 05.10. fand H1, M1–M3 und N1/N2; siehe Nachbesserung oben und `docs/geraetetest/0.1.1/BERICHT.md`. iPhone-Gäste stehen aus (über Freunde bzw. Cloud-Geräte).
- **„Partie fortsetzen“** fehlt in der Oberfläche. Speicherstand und `resume()` sind in Modul G fertig und getestet.
- **Hörtest am Handy** für die aufbereiteten Mau-Aufnahmen und die Spieltöne steht aus.
- **Nicht in 0.1.1** (Plan Abschnitt 1, „Später“): Godot-Web-Client, Spiel-WLAN per LocalOnlyHotspot mit WLAN-QR, automatisches „Update vom Gastgeber“, Reinwerfen und 7-Tausch, „Rückseiten wie am echten Tisch“, Musik.
- **Hand:** Gestenschwellen, dp-Umrechnung und Federn sind nur am PC abgestimmt. Übersichtsblatt ab 25 Karten und Randmarken fehlen (`F1a.md`).
- **Netz:** Kein Neubinden bei WLAN-Wechsel während des Spiels. Die Windows-Firewall blockiert eingehende Verbindungen zum PC-Gastgeber (`D.md`).
- **Windows-Build** ohne eigenes Programmsymbol.
- **`tools/build.ps1`** nimmt nur `*_lang*` und `*_shot*` vom Testlauf aus. Die langen Tests heißen aber `*_long` und laufen deshalb mit. Das deckt die Pflichtprüfung „10 000 Bot-Partien“ bei jedem Bau ab; seit dem parallelen Lauf in Teilen und dem Testergebnis-Cache kostet es kaum noch Zeit (siehe „Prüfen“).

## Builds und Quellen

- Engine: Godot 4.6.1, Compatibility-Renderer, Querformat, Basisgröße 1600×720.
- `tools/build.ps1 -Target Android` erzeugt `builds/MauMauFlip-0.1.1.apk`: Paket `de.maumauflip.game`, Version 0.1.1 (Code 1001), signiert mit `.tools/maumauflip-release.keystore`. Signatur, Paket und Version werden nach dem Bau geprüft.
- `tools/build.ps1 -Target Windows` erzeugt `builds/MauMauFlip.exe` zum Testen am PC.
- Veröffentlichung mit `tools/release.ps1 -Channel beta` (nur nach Bau mit Tests) im Repo `ShakieVan/Mau-Mau-Flip-Beta`; Quellcode in `ShakieVan/Mau-Mau-Flip`. Lizenz CC BY-NC 4.0.
- Einstellungen und Speicherstand liegen unter `user://`: Windows `%APPDATA%/Godot/app_userdata/Mau-Mau Flip/`, Android im privaten App-Verzeichnis.
