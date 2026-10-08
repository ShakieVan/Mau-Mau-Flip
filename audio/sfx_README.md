# Spieltöne (außer „Mau!“)

Kurze Töne im Stil „Papier & Neon“: Papier für Karten und Mischen, ein Wusch mit Glanz für den Flip, Holz für den Fehler, Marimba und Glockenspiel für „Du bist dran“ und den Sieg.

**Herkunft:** KI-erzeugt mit dem Geräusch-Modell **MOSS-SoundEffect v2.0** (`OpenMOSS-Team/MOSS-SoundEffect-v2.0`, Code `github.com/OpenMOSS/MOSS-TTS`). Lizenz des Modells: **Apache 2.0** für Code und Gewichte; sie stellt keine Bedingungen an die erzeugten Töne. Keine Aufnahmen, keine fremden Samples. Jeder Ton ist aus Text-Prompt und festem Seed erzeugt, ausgewählt aus 79 Kandidaten (`audio/sfx_ki/README.md`) und mit `tools/make_sfx_moss.py --spiel` nachbearbeitet. **Die Dateien stehen unter der Projektlizenz CC BY-NC 4.0.**

Bis 05.10.2026 stand hier: „synthetisch, eigenes Skript `tools/make_sfx.py`, keine KI-Generatoren“. Das gilt nicht mehr. Der Nutzer fand die synthetischen Töne zu einfach („C64-Niveau“). Sie liegen zum Vergleich in `audio/sfx_ki/alt/`; `tools/make_sfx.py` würde sie neu erzeugen und dabei die KI-Töne im Spiel überschreiben.

**Niemand hat die Töne bisher gehört.** Anhören: `audio/sfx_ki/hoeren.html`, Abschnitt „Im Spiel“ (offline, mit dem ungefilterten Favoriten und dem alten Ton zum Vergleich).

**Standard:** Spieltöne sind ab Werk **aus** (Einstellung „Spieltöne“: aus / leise / normal), in der App und im Browser-Client.

## Töne

| Ton | Datei | Kandidat | Klang | Dauer |
|---|---|---|---|---|
| Karte legen | `karte` | `karte_02` | ein einzelner Kartenschlag mit kurzem, glattem Ausklang | 0,24 s |
| Karte ziehen | `ziehen` | `ziehen_07` | schneller Papierwisch | 0,60 s |
| Mischen | `mischen` | `mischen_06` | zwei dichte Flatter-Schübe wie beim Riffeln | 1,20 s |
| Flip | `flip` | `flip_02` | Wusch, danach ein heller Glanz | 1,40 s |
| Du bist dran | `dran` | `dran_04` | Marimba, drei Anschläge aufwärts (etwa A4 – D5 – A5) | 0,60 s |
| Fehler | `fehler` | `fehler_09` | hohles, holziges „Tock“ | 0,25 s |
| Sieg | `sieg` | `sieg_03` | Glockenspiel und Marimba, Tonfolge aufwärts (etwa C4 – E4 – G4 – C5) | 1,76 s |
| Aussetzen | `schnurren` | `schnurren3_03` (Runde 3, `tools/make_schnurren.py --runde3`) | sanftes Katzenschnurren, spielt beim Legen von „Aussetzen“ und „Alle aussetzen“ auf allen Geräten | 1,64 s |

Ausgabe (alle mono, 48 kHz, 20 ms Stille am Ende):

- `game/assets/sfx/<ton>.ogg`: Ogg Vorbis q6 (Godot)
- `webclient/sfx/<ton>.ogg`: dieselbe Datei für den Browser-Client
- `webclient/sfx/<ton>.m4a`: AAC-LC (ffmpeg `-b:a 192k`, tatsächlich etwa 130–160 kbit/s), Kodierer-Grenze 8 kHz (für Safari auf dem iPhone). Mit `-b:a 128k` legt der Kodierer beim Kartenlegen Rauschen über 6 kHz (−23 dB statt −30 dB).
- `audio/sfx_ki/spiel/<ton>.wav` (24 Bit, Vorlage), `.ogg`, `.m4a`, `.png` (Spektrogramm) und `messwerte.json`

`webclient/sfx/index.json` nennt dem Browser-Client die Dateien. Fehlt eine Datei oder scheitert das Dekodieren, nimmt `webclient/ton.js` seinen eingebauten Synth-Klang.

## Neu erzeugen

```powershell
. E:\Draw2Race-AudioLab\env.ps1
$py = 'E:\Draw2Race-AudioLab\moss-sfx\.venv\Scripts\python.exe'
& $py tools\make_sfx_moss.py --spiel          # Favoriten bearbeiten, prüfen, nach game/ und webclient/ kopieren
tools\godot_import.ps1                        # Godot-Import auffrischen
& $py tools\hoerseite_sfx_ki.py seite         # Hörseite mit Abschnitt „Im Spiel“
```

`--spiel` braucht keine GPU und lädt kein Modell: Es liest nur die Rohdateien `audio/sfx_ki/roh/<kandidat>.wav`. Ein neuer Lauf ergibt bitgleiche Dateien. Mit `--ohne-kopie` schreibt es nur `audio/sfx_ki/spiel/`. Welcher Kandidat ins Spiel kommt und wie laut, steht in `SPIEL` in `tools/make_sfx_moss.py`.

## Bearbeitung

1. **Schnitt** wie beim Kandidaten: Gleichanteil weg, Hochpass 60 Hz, Ausschnitt um den Hauptschlag bzw. ab dem ersten deutlichen Einsatz, höchstens die Zieldauer.
2. **Tiefpass vor- und rückwärts** (`sosfiltfilt`, Butterworth 4. Ordnung, zusammen 8. Ordnung = 48 dB/Oktave, phasenneutral). Grenzfrequenz je Ton: die höchste zwischen 6 und 4 kHz (Schritt 50 Hz), bei der der fertige Ton über 6 kHz höchstens −30 dB Energieanteil hat. So bleibt jeder Ton so hell wie möglich.
3. **Nur bei zwei Tönen zusätzlich:**
   - `ziehen`: schmale Kerbe bei 6000 Hz (Q 30, vor- und rückwärts). Schon der Rohton des Modells enthält dort einen reinen Ton, 14 dB über der Umgebung (genau ein Achtel der Abtastrate, wohl ein Rest des Dekoders). Ohne Kerbe wäre er ein leises Pfeifen. Danach reicht ein Tiefpass von 5,05 statt 4,80 kHz.
   - `fehler`: Tiefen-Kuhschwanzfilter −6 dB unter 300 Hz. Der Körper des „Tock“ liegt bei 165 Hz; das gibt ein Handy-Lautsprecher nicht wieder, es kostet aber Spitzenreserve. Mit dem Filter wird der hörbare Teil (500–1000 Hz) auf dem Handy 2,5 dB lauter, über Kopfhörer 0,7 dB.
4. **Ein- und Ausblenden:** Kosinus, 3 ms am Anfang, 30–80 ms am Ende; keine Schleife.
5. **Pegel:** Lautheit auf ein Ziel je Ton (höchste Momentan-Lautheit, 400 ms, BS.1770), Spitzen darüber mit einem Begrenzer mit Vorausschau (höchstens 3–6 dB), echte Spitze höchstens −1 dBTP.
6. **Prüfung:** Das Skript bricht ab und kopiert nichts, wenn WAV, OGG oder M4A über 6/10/12 kHz mehr als −30/−50/−60 dB haben oder die Spitze über −0,7 dBTP liegt. `game/tests/test_app_sound.gd` prüft dieselben Grenzen an `messwerte.json`.

## Katzen-Leitplanke (sinngemäß aus `audio/entwurf/mau/README.md`)

**Eingehalten.** Messwerte in der Tabelle unten.

- **Kein Rauschen über 6 kHz:** über 6/10/12 kHz höchstens −30/−50/−60 dB gegenüber dem ganzen Ton, auch nach dem Kodieren. Die Papiergeräusche und der Flip liegen knapp unter −30 dB (−30,3 bis −30,8 dB): Die Grenzfrequenz ist so gewählt. Die tonalen Töne liegen weit darunter (−48 bis −81 dB).
- **Kein Piepen bei 3–4 kHz:** keine schmale Linie zwischen 2 und 6 kHz (Suche nach Spitzen mehr als 12 dB über der Umgebung). Die Papiergeräusche haben dort viel breitbandige Energie (−4 bis −6 dB Anteil, stärkster Teil des Spektrums), aber keine Spitze. Bei Flip, dran, sieg und fehler liegt der Anteil bei −17 bis −68 dB.
- **Keine Tierlaute, Stimmen, Zischen:** keine Prompts mit Vögeln, Quietschen, Miauen oder Zischlauten. Der AudioSet-Klassifikator findet bei keinem Kandidaten Katze, Tier oder Vogel (unter 0,03). Der zischende Kandidat `flip_03` ist nicht im Spiel.
- **Schnurren (Ausnahme):** Der Ton `schnurren` ist ein absichtliches Schnurren (Nutzerentscheidung 08.10.2026) und fällt unter keine dieser Prüfungen. Er liegt wie die übrigen Spieltöne unter der Einstellung „Spieltöne“ (ab Werk aus), Lautheit −23,6 LUFS, Spitze −1,1 dBFS; Herkunft wie oben (MOSS-SoundEffect v2.0, Apache 2.0), Datei unverändert kopiert aus `audio/entwurf/schnurren3/schnurren3_03.ogg` nach `game/assets/sfx/schnurren.ogg`.
- **Kein Schnurren (bei allen anderen Tönen):** Die Hüllkurve pulsiert im Bereich 15–50 Hz nirgends deutlich (Schärfe höchstens 6,9; Warnschwelle 10).
- **Weicher Einsatz:** Kosinus-Anstieg 3 ms. Karte, dran und sieg sind bewusst klare Anschläge.

## Pegel im Spiel

- **Bezug:** der Mau-Ton „Mao“ (`mau.ogg`, −11,4 LUFS, spielt bei „normal“ mit −2 dB, also −13,4 LUFS).
- **Stufen der Spieltöne** (`game/scripts/app/sound.gd`, `TON_DB`): normal −4,5 dB, leise −12,5 dB, aus stumm. Das ist 2,5 bzw. 10,5 dB unter Mau „normal“.
- **Abgleich in den Dateien,** nicht in `TRIM_DB` (bleibt leer), damit App und Browser gleich klingen:
  - **Karte legen** erklingt in jeder Partie sehr oft und bleibt dezent: Sie bleibt dort, wo die Spitzengrenze sie hält (−25,2 LUFS), im Spiel 16 dB unter dem Mau-Ton. Weil der Schlag nur 0,24 s dauert, unterschätzt das 400-ms-Messfenster ihn um etwa 2 dB.
  - **Karte ziehen** erklingt ebenso oft und ist gleich laut.
  - **Mischen** und **Flip** 2 bzw. 4 dB lauter.
  - **Du bist dran** und **Sieg** am lautesten, 8,6 bzw. 7,6 dB unter dem Mau-Ton; beide klingen weich (Marimba, Glockenspiel) und haben kaum Höhen.
  - **Fehler** ist ebenfalls ein kurzer, spitzenbegrenzter Schlag. Mit dem Tiefen-Kuhschwanz ist er auf dem Handy-Lautsprecher etwa so laut wie das Kartenlegen (1,4 dB leiser), über Kopfhörer 3,5 dB lauter.
- **Browser-Client:** `webclient/ton.js` regelt die Spieltöne mit eigenen Stufen (`STUFEN_SPIEL`). Für dasselbe Verhältnis zum Mau-Ton wie in der App gehören dort 0,75 (normal) und 0,3 (leise) hin, bei Mau 1,0.
- Derselbe Ton startet innerhalb von 40 ms nur einmal; bis zu sechs Töne klingen gleichzeitig (`sound.gd`).

## Messwerte

Gemessen von `tools/make_sfx_moss.py --spiel` am fertigen Ton (vor dem Kodieren) und an den dekodierten Dateien; alle Werte in `audio/sfx_ki/spiel/messwerte.json`. Lautheit: höchste Momentan-Lautheit (400 ms, BS.1770). Handy: Lautheitsverlust mit Hochpass 800 Hz (12 dB/Oktave). „Über 6 kHz“: Energieanteil gegenüber dem ganzen Ton. „Im Spiel“: bei Stufe „normal“ (−4,5 dB); „gegen Mau“: Abstand zum Mau-Ton im Spiel.

| Ton | Tiefpass | Lautheit (Ziel) | Spitze | Handy | über 6/10/12 kHz | OGG über 6 kHz | M4A über 6 kHz | 3–4 kHz Anteil | im Spiel | gegen Mau |
|---|---|---|---|---|---|---|---|---|---|---|
| `karte` | 5,85 kHz | −25,2 LUFS (−24,5) | −1,1 dBTP | −0,4 dB | −30,3/−90,1/−93,2 dB | −30,3 dB | −30,4 dB | −4,4 dB | −29,7 LUFS | −16,3 dB |
| `ziehen` | 5,05 kHz | −24,5 LUFS (−24,5) | −2,2 dBTP | −0,1 dB | −30,6/−69,0/−86,8 dB | −30,5 dB | −30,8 dB | −4,7 dB | −29,0 LUFS | −15,6 dB |
| `mischen` | 4,75 kHz | −22,5 LUFS (−22,5) | −5,0 dBTP | −0,1 dB | −30,3/−76,1/−99,6 dB | −30,4 dB | −30,4 dB | −6,0 dB | −27,0 LUFS | −13,6 dB |
| `flip` | 5,35 kHz | −20,5 LUFS (−20,5) | −7,1 dBTP | −3,4 dB | −30,5/−73,5/−95,5 dB | −30,7 dB | −30,6 dB | −17,4 dB | −25,0 LUFS | −11,6 dB |
| `dran` | 6,00 kHz | −17,5 LUFS (−17,5) | −3,2 dBTP | −2,6 dB | −48,1/−105,4/−126,5 dB | −48,5 dB | −48,1 dB | −34,5 dB | −22,0 LUFS | −8,6 dB |
| `fehler` | 6,00 kHz | −21,7 LUFS (−16,5) | −1,1 dBTP | −5,3 dB | −80,8/−105,6/−108,7 dB | −80,6 dB | −68,9 dB | −67,8 dB | −26,2 LUFS | −12,8 dB |
| `sieg` | 6,00 kHz | −16,5 LUFS (−16,5) | −7,6 dBTP | −6,3 dB | −48,9/−106,7/−135,5 dB | −49,1 dB | −49,0 dB | −36,7 dB | −21,0 LUFS | −7,6 dB |
| `mau` (Bezug) | – | −11,4 LUFS | −1,0 dBTP | −7,3 dB | – | – | – | – | −13,4 LUFS | 0 |

Bemerkungen:

- `karte` und `fehler` erreichen ihr Lautheitsziel nicht: Die echte Spitze ist auf −1 dBTP begrenzt (Begrenzer 1,1 bzw. 5,9 dB).
- dran, fehler und sieg brauchen keinen Tiefpass unter 6 kHz; sie halten die Leitplanke schon bei 6 kHz.
- Höchste echte Spitze nach dem Kodieren: −1,1 dBTP (OGG und M4A).

## Offene Punkte

1. **Hörtest** auf einem Handy-Lautsprecher und mit Kopfhörern (`audio/sfx_ki/hoeren.html`, Abschnitt „Im Spiel“). Besonders:
   - `karte` und `ziehen` erklingen in jeder Partie sehr oft: Nervt etwas beim 50. Mal? Klingt `karte_02` nach Karte oder nach Münze bzw. Klick?
   - Wie viel nimmt der Tiefpass den Papiergeräuschen (`ziehen` 5,05 kHz, `mischen` 4,75 kHz)? Vergleich mit dem ungefilterten Favoriten.
   - `flip_02`: Bei 0,75 s bricht der tiefe Teil hart ab, danach kommt der Glanz. Gewollt oder störend?
   - `dran_04`: Der dritte Anschlag wird 90 ms nach dem Einsatz ausgeblendet. Wirkt das abgeschnitten?
   - `fehler` mit abgesenkten Tiefen: auf dem Handy hörbar genug, über Kopfhörer nicht zu dünn?
2. **Pegel auf dem Gerät** gegen den Mau-Ton prüfen. Lauter oder leiser insgesamt: `TON_DB` in `sound.gd` und `STUFEN_SPIEL` in `ton.js` gemeinsam ändern. Einzelne Töne: `SPIEL` in `make_sfx_moss.py`, dann neu erzeugen.
3. **Stapel aufstoßen** (`stapel_02`) wird im Spiel noch nicht verwendet; dafür bräuchten `sound.gd` und `SPIEL` einen Eintrag.
