# Modul S – Töne

Stand 05.10.2026 (Nachtschicht Beta 0.1.1). Erzeugt die Spieltöne und erweitert `AppSound` um Mau-Klang, Sperre, Probehören und eigene Lautstärke der übrigen Töne.

## Dateien

| Datei | Inhalt |
|---|---|
| `tools/make_sfx.py` | Synthese der Töne karte, ziehen, mischen, flip, sieg, fehler, dran (numpy/scipy, Bausteine aus `make_mau_sounds.py`), Pegel, Kodieren, Messung |
| `game/assets/sfx/<ton>.ogg` (+ `.import`) | die sieben Töne für Godot (Ogg Vorbis q6) |
| `webclient/sfx/<ton>.ogg`, `<ton>.m4a` | dieselben Töne für den Browser-Client (M4A: AAC mit Tiefpass 6 kHz) |
| `webclient/sfx/index.json` | Liste für `ton.js` (`{"karte": "karte.m4a", …, "mau": "mau.m4a"}`): Der Browser-Client nimmt damit die Dateien statt seiner Synth-Klänge |
| `audio/sfx_README.md` | Klangbeschreibung, Leitplanken, Messwerte, offene Punkte |
| `game/scripts/app/sound.gd` | `AppSound` erweitert (API `play(name)` unverändert) |
| `game/tests/test_app_sound.gd` | 60 Prüfungen |

Neu erzeugen: `. E:\Draw2Race-AudioLab\env.ps1`, dann `& E:\Draw2Race-AudioLab\analyse\.venv\Scripts\python.exe tools\make_sfx.py`, danach `tools/godot_import.ps1`.

## Schnittstelle `App.sound` (AppSound)

```gdscript
App.sound.play(name) -> bool          # "mau", "karte", "ziehen", "mischen", "flip", "sieg", "fehler", "dran"; false = still (aus, gesperrt, Datei fehlt)
App.sound.play_preview(klang) -> bool # Einstellungen: Mau-Ton im Klang klang probehören; bei mau_ton "aus" leise; 3-s-Sperre gilt
App.sound.mau_lock_left_ms() -> int   # Restzeit der Mau-Sperre (0 = frei), z. B. für einen Hinweis beim Probehören
App.sound.mau_klang() -> String       # eingestellter Klang (gültig, Standard "stimme")
App.sound.volume_db(name) -> float    # -80 = stumm
App.sound.stop_all()
AppSound.MAU_KLAENGE                  # ["stimme", "gesungen", "blubb", "spieluhr", "kalimba"]
```

Einstellungen (in `App.settings`; `AppSettings` übernimmt unbekannte Schlüssel ungeprüft, `AppSound` prüft sie selbst):

| Schlüssel | Werte | Wirkung |
|---|---|---|
| `mau_ton` | aus / leise / normal | Mau-Ton −80 / −14 / −6 dB (wie bisher) |
| `mau_klang` | stimme / gesungen / blubb / spieluhr / kalimba | Datei `mau_<klang>.ogg`; Unbekanntes oder fehlende Datei → `mau_stimme`, dann `mau.ogg` |
| `toene` | aus / leise / normal | **neu, optional:** übrige Töne −80 / −16 / −8 dB; Standard normal. `mau_ton` wirkt nicht auf sie |

Verhalten:

- **Mau-Sperre:** Zwischen zwei Mau-Tönen auf einem Gerät liegen mindestens 3 s; `play("mau")` und `play_preview()` bleiben in der Sperre still (false). Ein stummer Versuch (aus, Datei fehlt) startet keine Sperre. Wer den Ton auslöst, entscheidet weiter der Aufrufer (nur das Gerät, das „Mau!“ gedrückt hat).
- **Vorladen:** `_ready()` lädt alle Töne und alle Mau-Klänge (`preload_all()`).
- **Gleichzeitig:** sechs Abspieler; ein freier wird bevorzugt, sonst der älteste übernommen. Derselbe Ton startet innerhalb von 40 ms nur einmal (mehrere Karten im selben Bild klingen nicht doppelt laut).
- **Pegel:** Die Dateien sind gegen den Mau-Ton abgeglichen (Sieg so laut wie Mau, alle anderen leiser; Werte in `audio/sfx_README.md`). Feinabgleich ohne neue Dateien über `TRIM_DB` in `sound.gd`.
- Für Tests: `now_override` (feste Uhr), `dir` (anderer Ordner), `last_played`, `last_db`, `last_file`, `playing_count()`, `is_loaded(file)`.

## Tests

- `test_app_sound.gd` (headless, auch mit `-Extra '--audio-driver','Dummy'`): 60 ok – Dateien und Längen, Vorladen, Browser-Dateien und `index.json`, Klangwahl samt Rückfall, Lautstärken (`mau_ton`, `toene` unabhängig), Sperre an der 3000-ms-Grenze, Probehören (Sperre, „aus“ → leise, unbekannter Klang), 40-ms-Doppelstart, sechs Abspieler gleichzeitig, fehlende Dateien still ohne Sperre.
- `test_app_services.gd` (Modul C) weiter grün: 24 ok.

## Hinweise für andere Module

- **Einstellungsseite (F2):** Auswahl `mau_klang` mit `AppSound.MAU_KLAENGE`, Knopf „Probehören“ → `App.sound.play_preview(klang)`; gibt er false zurück, kurz „Gleich noch einmal …“ zeigen (`mau_lock_left_ms()`). Optional ein Schalter für `toene`. Den aktuellen Klang mit `App.sound.mau_klang()` lesen (`AppSettings.defaults()` kennt `mau_klang` und `toene` nicht).
- **Browser-Client (E2):** `ton.js` liest jetzt `sfx/index.json` und spielt die M4A-Dateien. Soll er je nach Browser OGG oder M4A wählen, müsste `ton.js` das selbst entscheiden (die Liste nennt eine Datei je Ton). `webclient/sfx/mau.m4a` stammt noch aus der Mau-Runde und ist ohne 6-kHz-Tiefpass kodiert.
- **„Mau-Mau!“** hat noch kein eigenes Motiv; `sieg` passt bis dahin.

## Offen

1. Niemand hat die Töne gehört: Hörtest auf einem Handy (Papierklang, Lästigkeit beim 50. Mal, Knacken) und Pegel auf dem Gerät gegen den Mau-Ton.
2. Die Einstellungsoberfläche für `mau_klang`/`toene` baut ein anderes Modul.
