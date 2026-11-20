# Tests

Wie der Bau prüft. Vorher stand das in `docs/IMPLEMENTIERUNG.md` (Abschnitt „Prüfen“, jetzt im Archiv unter `docs/archiv/`).

## Ablauf

`tools/build.ps1 -Target Test` (und vor jedem Android- oder Windows-Bau) prüft zuerst den Vermittler-Kern (`relay/test/core_test.html` in Chrome headless), packt den Browser-Client, importiert das Projekt, führt die Browser-Tests (Online, Umzug, Übernahme) aus und dann alle `game/tests/test_*.gd` außer `*_lang*` und `*_shot*`. Stand Beta 1.6.20: 114 Testläufe. Ein schon getesteter Stand baut dank Testcache in etwa 0,6 min; ein voller Testlauf dauerte bei Beta 1.1.2 etwa 3,5 min, seitdem sind viele Tests dazugekommen.

- **Zwei Spuren:** Reine Tests (`test_rules_*`, `test_ui_*`, `test_card_view`, `test_smoke`, `test_game_local`, `test_b_assets`) laufen gleichzeitig in mehreren Godot-Prozessen, jeder mit eigenem `user://` (APPDATA in einem Wegwerfordner). Netz-, Lobby-, Bildschirm- und App-Tests laufen nacheinander in einer eigenen Spur mit dem echten `user://`. Neue Testskripte, die nicht zum Muster passen, landen automatisch in der seriellen Spur (`Test-Kind` in `tools/build.ps1`).
- **Teile:** Lange Dauerläufe (`test_rules_bots_long`, `_swap`, `_views_long`, `_gamble`, `_discard`) laufen in Teilen mit der Umgebungsvariable `TEIL=k/n` (`game/tests/teil.gd`): Partie i gehört zu Teil i % n + 1, feste Einzelprüfungen zu Teil 1. Alle Teile zusammen prüfen dieselben Startwerte; ein Einzelaufruf ohne `TEIL` prüft alles.
- **Sperre:** Der Bau hält `Global\MauMauFlipGodot` einmal und startet seine Testprozesse ohne erneutes Sperren; fremde Godot-Läufe (`godot_run.ps1`, `godot_import.ps1`) warten wie bisher.
- **Testergebnis-Cache:** Nach einem vollständig grünen Lauf merkt sich der Bau die Prüfsumme des Stands (alle von git erfassten oder erfassbaren Dateien in `game/` und `webclient/`, dazu `tools/build.ps1`; Erzeugtes wie `.godot/`, `android/build/build/` und `web.zip` nicht) in `.tools/test_cache.json`. Ist der Stand unverändert, überspringen `-Target Test`, `Android` und `All` die Tests („Tests für diesen Stand schon grün, übersprungen“); der Baubeleg vermerkt dann `tests: true, tests_cached: true`. Jede Änderung einer erfassten Datei erzwingt neue Tests. `-NoTestCache` lässt die Tests immer laufen, `-SkipTests` lässt sie wie bisher weg (`tests: false`), `-Parallel n` legt die Zahl paralleler Prozesse fest. Die Laufzeiten je Lauf stehen in `.tools/test_times.json` (längste zuerst beim nächsten Mal).

Bestanden heißt:
- Exitcode 0,
- eine Zeile `RESULT: n ok`,
- keine Zeile mit `SCRIPT ERROR`, `ERROR:` oder `FAIL:`.

Erwartete Fehlpfade melden sich deshalb als `WARNING`, z. B. `MauGame.create` mit ungültiger Spielerzahl. UI-Tests beenden sich über `game/tests/clean_exit.gd`: Töne anhalten, Knoten freigeben, 0,3 s warten, statische Zwischenspeicher leeren. Sonst meldet Godot „resources still in use at exit“.

## Wackelige Läufe

- `test_takeover_mixed` wackelt unter Last im Gesamtlauf, einzeln ist er grün.
- `test_game_online`: Der Browser-Gast kam einmal unter Volllast nicht in 30 s in die Partie (Ursache nicht bewiesen, allein grün).
- Rechnet eine andere Sitzung parallel, mit `tools/build.ps1 -Target Android -Parallel 6` bauen.
- Bildtakt-Fehler (z. B. Regie und Kartenflug im selben langen Bild) lassen sich mit `tools/godot_run.ps1 … -Extra @('--fixed-fps','30')` nachstellen.

## Kontrollbilder

- Die Shot-Tests `game/tests/*_shot.gd` laufen nicht im Bau, nur von Hand. Ohne `SHOT_DIR` schreiben sie PNG nach `docs/module/`.
- Am PC mit ANGLE rendern (`--rendering-driver opengl3_angle`), sonst erscheinen bei Transparenz grüne Blöcke.
- Ins Repo kommen Kontrollbilder als JPEG (seit Beta 1.6.12). Ältere PNG-Bilder stehen nur noch in der Git-Geschichte, siehe `docs/module/BILDER.md`.
