# KI-Spieltöne: Kandidaten, Bewertung, Favoriten

Ersatz für die synthetischen Spieltöne aus `tools/make_sfx.py`, die zu einfach klingen. Hier liegen 79 Kandidaten für 8 Töne, erzeugt am 05.10.2026.

> **Von niemandem im Team gehört.** Erzeugung und Auswahl stammen von KI-Agenten. Die Rangfolge beruht auf Messwerten, Spektrogrammen und zwei Audio-Modellen, nicht auf Ohren. Bitte mit **`hoeren.html`** anhören (Handy-Lautsprecher und Kopfhörer). **Seit 06.10.2026 sind die Favoriten im Spiel** (`game/`, `webclient/`), gefiltert und abgestimmt: siehe „Im Spiel“.

**Herkunft:** KI-erzeugt mit MOSS-SoundEffect v2.0, Apache 2.0.

## Herkunft und Lizenz

- **Modell:** `OpenMOSS-Team/MOSS-SoundEffect-v2.0` (Hugging Face), Code `github.com/OpenMOSS/MOSS-TTS`, Unterordner `moss_soundeffect_v2`. **Lizenz Apache 2.0** für Code und Gewichte, nicht gated. Die Lizenz stellt keine Bedingungen an die erzeugten Töne.
- **Keine Aufnahmen und keine fremden Samples.** Jeder Ton ist aus Text-Prompt und festem Seed reproduzierbar (bis auf GPU-Rundung).
- **Für die Töne im Spiel** gilt die Projektlizenz (CC BY-NC 4.0). `audio/sfx_README.md` ist angepasst (früher stand dort „keine KI-Generatoren“).
- **Bewertungsmodelle** (nur zum Beschreiben, nichts davon steckt in den Tönen): Qwen3-Omni-30B-A3B-Captioner (Apache 2.0, int8-Variante der Werkstatt) und der AudioSet-Klassifikator `MIT/ast-finetuned-audioset-10-10-0.4593` (BSD-3).

## Favoriten

Kopien liegen in `favoriten/<ton>.ogg` und `.m4a` (ungefiltert, wie unten gemessen). Einzelheiten zu jedem Kandidaten stehen in `hoeren.html`. Die Fassungen im Spiel liegen in `spiel/` (Abschnitt „Im Spiel“).

| Ton | Favorit | Platz 2 | Platz 3 | Warum der Favorit |
|---|---|---|---|---|
| Karte legen | `karte_02` | `karte_07` | `karte_09` | ein einzelner Schlag mit glattem Ausklang (0,24 s), unter den knackigen Kandidaten am wenigsten Höhen, auf dem Handy voll hörbar |
| Karte ziehen | `ziehen_07` | `ziehen_04` | `ziehen_02` | ein vollständiger, schneller Wisch: nach 46 ms hörbar, nach 0,25 s vorbei, sauber; aber sehr hell |
| Mischen | `mischen_06` | `mischen_08` | `mischen_05` | zwei dichte Flatter-Schübe wie beim Riffeln, gleichmäßig laut (fast am Lautheitsziel) |
| Flip | `flip_02` | `flip_12` | `flip_10` | einziger Kandidat, den beide Modelle als Wusch hören (AudioSet „Whoosh“ 0,49), danach ein heller Glanz |
| Du bist dran | `dran_04` | `dran_05` | `dran_02` | Marimba, drei Anschläge aufwärts (etwa A4 – D5 – A5), warm, hält die Katzen-Leitplanke ein |
| Fehler | `fehler_09` | `fehler_11` | `fehler_05` | hohles, holziges „Tock“, sauber, von den dumpfen Kandidaten am besten auf dem Handy (−7 dB) |
| Sieg | `sieg_03` | `sieg_01` | `sieg_07` | Glockenspiel/Marimba, Tonfolge steigt (etwa C4 – E4 – G4 – C5), sauber, kaum Höhen |
| Stapel aufstoßen (neu) | `stapel_02` | `stapel_06` | `stapel_08` | zwei klar getrennte Schläge, sauber, 0,51 s; der Ton wird im Spiel noch nicht verwendet |

Messwerte der Favoriten (Kandidat, Tiefpass 12 kHz; die Werte im Spiel stehen unter „Im Spiel“). „Über 6 kHz“ ist der Energieanteil gegenüber dem ganzen Ton. Die Katzen-Leitplanke verlangt höchstens −30 dB.

| Favorit | Dauer | Lautheit | Spitze | Handy | über 6 kHz |
|---|---|---|---|---|---|
| `karte_02` | 0,24 s | −23,4 LUFS | −1,1 dBTP | −0,4 dB | −22,6 dB |
| `ziehen_07` | 0,60 s | −21,0 LUFS | −1,1 dBTP | 0,0 dB | −3,8 dB |
| `mischen_06` | 1,20 s | −19,8 LUFS | −1,1 dBTP | −0,1 dB | −6,0 dB |
| `flip_02` | 1,40 s | −17,0 LUFS | −3,8 dBTP | −2,1 dB | −10,2 dB |
| `dran_04` | 0,60 s | −18,0 LUFS | −3,6 dBTP | −2,6 dB | −35,4 dB |
| `fehler_09` | 0,25 s | −22,4 LUFS | −1,1 dBTP | −7,0 dB | −73,9 dB |
| `sieg_03` | 1,76 s | −16,0 LUFS | −7,1 dBTP | −6,3 dB | −39,5 dB |
| `stapel_02` | 0,51 s | −24,5 LUFS | −1,1 dBTP | −0,6 dB | −16,7 dB |

## Im Spiel (06.10.2026)

**Entscheidung des Hauptagenten:** Die Favoriten kommen ins Spiel (Stapel nicht, er wird noch nicht verwendet). Jeder Ton wird vor- und rückwärts tiefpassgefiltert (`sosfiltfilt`), je Ton mit der höchsten Grenzfrequenz zwischen 4 und 6 kHz, bei der über 6 kHz höchstens −30 dB bleiben. So bleibt jeder Ton so hell wie möglich und hält trotzdem die Katzen-Leitplanke ein.

- **Erzeugung:** `tools/make_sfx_moss.py --spiel` (ohne GPU, liest nur `roh/`, bitgleich wiederholbar). Schnitt wie beim Kandidaten, dann Tiefpass mit Suche 6 → 4 kHz in 50-Hz-Schritten, Pegel je Ton, Begrenzer, echte Spitze ≤ −1 dBTP. Das Skript prüft WAV, OGG und M4A (über 6/10/12 kHz ≤ −30/−50/−60 dB) und kopiert nur, wenn alles passt.
- **Zusätzlich:** `ziehen_07` bekommt eine schmale Kerbe bei 6000 Hz. Schon der Rohton enthält dort einen reinen Ton, 14 dB über der Umgebung (ein Achtel der Abtastrate, wohl ein Rest des Dekoders; die Warnung auf der Hörseite beginnt erst bei 18 dB). `fehler_09` bekommt −6 dB Tiefen unter 300 Hz, damit er auf dem Handy-Lautsprecher hörbar bleibt (dort +2,5 dB).
- **Dateien:** `spiel/<ton>.wav|.ogg|.m4a|.png`, `spiel/messwerte.json`; Kopien in `game/assets/sfx/<ton>.ogg` sowie `webclient/sfx/<ton>.ogg` und `.m4a` (AAC-LC mit `-b:a 192k`; mit `128k` legte der Kodierer beim Kartenlegen Rauschen über 6 kHz).
- **Alte Fassungen:** Die synthetischen Töne aus `tools/make_sfx.py` liegen zum Vergleich in `alt/`.
- **Lautstärken:** Karte legen dezent, ziehen gleich laut, mischen und flip etwas lauter, dran und sieg am lautesten, alle deutlich unter dem Mau-Ton. Der Abgleich steckt in den Dateien; die App spielt Spieltöne bei „normal“ mit −4,5 dB (Mau −2 dB). Einzelheiten in `audio/sfx_README.md`.

| Ton | Kandidat | Tiefpass | Lautheit | Spitze | Handy | über 6 kHz (WAV/OGG/M4A) | über 10/12 kHz | im Spiel gegen Mau |
|---|---|---|---|---|---|---|---|---|
| Karte legen | `karte_02` | 5,85 kHz | −25,2 LUFS | −1,1 dBTP | −0,4 dB | −30,3/−30,3/−30,4 dB | −90,1/−93,2 dB | −16,3 dB |
| Karte ziehen | `ziehen_07` | 5,05 kHz + Kerbe 6 kHz | −24,5 LUFS | −2,2 dBTP | −0,1 dB | −30,6/−30,5/−30,8 dB | −69,0/−86,8 dB | −15,6 dB |
| Mischen | `mischen_06` | 4,75 kHz | −22,5 LUFS | −5,0 dBTP | −0,1 dB | −30,3/−30,4/−30,4 dB | −76,1/−99,6 dB | −13,6 dB |
| Flip | `flip_02` | 5,35 kHz | −20,5 LUFS | −7,1 dBTP | −3,4 dB | −30,5/−30,7/−30,6 dB | −73,5/−95,5 dB | −11,6 dB |
| Du bist dran | `dran_04` | 6,00 kHz | −17,5 LUFS | −3,2 dBTP | −2,6 dB | −48,1/−48,5/−48,1 dB | −105,4/−126,5 dB | −8,6 dB |
| Fehler | `fehler_09` | 6,00 kHz, Tiefen −6 dB | −21,7 LUFS | −1,1 dBTP | −5,3 dB | −80,8/−80,6/−68,9 dB | −105,6/−108,7 dB | −12,8 dB |
| Sieg | `sieg_03` | 6,00 kHz | −16,5 LUFS | −7,6 dBTP | −6,3 dB | −48,9/−49,1/−49,0 dB | −106,7/−135,5 dB | −7,6 dB |

Lautheit: höchste Momentan-Lautheit der Datei (400 ms, BS.1770). Karte und Fehler sind durch die Spitze begrenzt. „Im Spiel gegen Mau“: Abstand zur Aufnahme „Mao“ (−11,4 LUFS, im Spiel −2 dB) bei Stufe „normal“. Schmale Linien zwischen 2 und 6 kHz: keine. Pulsfolge 15–50 Hz: nirgends deutlich (Schärfe höchstens 6,9).

## Beim Anhören prüfen

1. **`karte_02`** erklingt in jeder Partie sehr oft: Klingt es nach Karte oder nach Münze bzw. Klick? Nervt es beim 50. Mal? Das Modell erkennt bei keinem Karten-Kandidaten sicher eine Spielkarte.
2. **`ziehen_07`** ist ein heller Wisch. Im Spiel liegt er tiefpassgefiltert bei 5,05 kHz (siehe „Im Spiel“); mit dem ungefilterten Kandidaten vergleichen. Ein Zischen wäre für Katzen ungünstig.
3. **`flip_02`**: Bei 0,75 s bricht der tiefe Teil hart ab, danach kommt ein „Shing“. Ist das ein gewollter Effekt oder ein Fehler? Wirkt es zu sehr nach Schwert? Der Höhepunkt liegt erst bei 0,75 s.
4. **`dran_04`**: Der dritte Anschlag wird 90 ms nach dem Einsatz ausgeblendet (Zieldauer 0,6 s). Wirkt das abgeschnitten?
5. **`dran_05`** (Platz 2) und einige Einzeltöne: Das Modell vergleicht sie mit bekannten Handy-Nachrichtentönen. Im Spiel könnte man eine eingehende Nachricht vermuten.
6. **`fehler_09`**: Ist er auf dem Handy-Lautsprecher noch hörbar (−7 dB)? Sonst `fehler_05` (−1,7 dB), der aber dem Kartenlegen ähneln könnte.

## Höhen und Katzen-Leitplanke (entschieden 06.10.2026)

**Entschieden:** Tiefpass vor- und rückwärts, Grenzfrequenz je Ton zwischen 4 und 6 kHz (siehe „Im Spiel“). Ergebnis: karte 5,85 kHz, ziehen 5,05 kHz, mischen 4,75 kHz, flip 5,35 kHz; dran, fehler und sieg 6 kHz. Die Abwägung vom 05.10.2026 bleibt zur Nachvollziehbarkeit stehen:

`make_sfx_moss.py` begrenzt die Kandidaten bei 12 kHz. Die Leitplanke aus `audio/sfx_README.md` erlaubt über 6 kHz höchstens −30 dB; die bisherigen Töne waren bei 5 kHz begrenzt.

- **Halten die Leitplanke ein:** `dran_04`, `fehler_09`, `sieg_03`.
- **Verletzen sie:** `karte_02`, `ziehen_07`, `mischen_06`, `flip_02` und `stapel_02` (−3,8 bis −22,6 dB).
- **`--tiefpass 5000` allein reicht nicht.** `tools/make_sfx_moss.py --nur-nachbearbeiten --tiefpass 5000` (etwa 20 s, ohne GPU) filtert nur mit 24 dB/Oktave (Butterworth 4. Ordnung, vorwärts). Nachgerechnet an den bearbeiteten Dateien bleiben vier Favoriten über der Grenze. Der alte Generator `make_sfx.py` filterte vor- und rückwärts (48 dB/Oktave); auch damit liegen `ziehen_07` und `mischen_06` noch knapp darüber. Erst 4 kHz vor- und rückwärts hält bei allen.

| über 6 kHz | jetzt (12 kHz) | `--tiefpass 5000` | 5 kHz vor- und rückwärts | 4 kHz vor- und rückwärts |
|---|---|---|---|---|
| `karte_02` | −22,6 dB | −35,6 dB | −44,6 dB | −59,4 dB |
| `ziehen_07` | −3,8 dB | −18,1 dB | −29,2 dB | −43,5 dB |
| `mischen_06` | −6,0 dB | −18,3 dB | −27,9 dB | −42,3 dB |
| `flip_02` | −10,2 dB | −25,0 dB | −35,4 dB | −50,8 dB |
| `stapel_02` | −16,7 dB | −28,5 dB | −38,1 dB | −53,1 dB |

- **Umsetzung (06.10.2026):** `process(leitplanke=True)` in `make_sfx_moss.py` filtert vor- und rückwärts und sucht die Grenzfrequenz je Ton (statt fest 4 kHz). Aufruf: `make_sfx_moss.py --spiel`. Die Kandidaten oben bleiben unverändert (12 kHz).
- **Klangfolge:** Die Papiergeräusche verlieren ihr Knistern, beim Flip verschwindet der Glanz von `flip_02` weitgehend. Bei `sieg_07` würde der Glockenakkord matter. Ob das schlimm ist, zeigt nur ein Hörvergleich.
- **Alternative:** Höhen behalten und die Leitplanke für Papiergeräusche bewusst lockern. Die Grenzwerte stammen aus der Mau-Ton-Prüfung (`audio/entwurf/mau/README.md`); ob kurze Papiergeräusche Katzen genauso stören, habe ich nicht geprüft.

## Erzeugung

- **Skript:** `tools/make_sfx_moss.py` (Aufruf und alle Parameter im Skriptkopf). Umgebung, Repo-Klon und Modell liegen in der Werkstatt `E:\Draw2Race-AudioLab\moss-sfx` (siehe dortige `LIESMICH.md`).
- **Kandidaten:** je Ton 2–4 Prompt-Varianten mit 3–4 festen Seeds. Bei flip, fehler und dran kam nach der ersten Durchsicht eine vierte Variante dazu. Keine Prompts mit Vögeln, Quietschen, Miauen oder Zischlauten.
- **Modell-Einstellungen:** 100 Schritte, CFG 4,0, sigma shift 5,0, bfloat16. Das Modell berechnet immer 30 s; auf einer RTX 3090 dauert ein Ton 23–28 s.
- **Daueransage:** Unter etwa 2 s hält sich das Modell kaum an „duration“. Deshalb wird länger erzeugt und danach geschnitten.
- **Nachbearbeitung:**
  - Gleichanteil entfernen, Hochpass 60 Hz, Tiefpass 12 kHz.
  - Schnitt am Hauptschlag bzw. am ersten deutlichen Einsatz, höchstens bis zur Zieldauer; ein- und ausblenden.
  - Lautheit auf ein Ziel je Ton, Begrenzer, echte Spitze höchstens −1 dBTP.
  - Kurze Schläge erreichen ihr Lautheitsziel nicht, weil das Messfenster 400 ms lang ist (−22 bis −31 LUFS).
- **Dateien je Kandidat:** `<ton>_<nr>.wav` (24 Bit, 48 kHz mono), `.ogg` (Vorbis q6), `.m4a` (AAC-LC 160 kbit/s). Originale in `roh/`.

## Bewertung

Je Kandidat gingen vier Quellen ein. Die Regeln je Ton stehen in `tools/bewertung_sfx_ki.py`.

1. **Messwerte der Erzeugung** (`varianten.json`): Dauer, Lautheit, Schwerpunkt, Energie über 6/8/12 kHz, Handy-Verlust (Hochpass 800 Hz), Begrenzung, Rauschabstand des Originals.
2. **Eigene Messungen** (`messung_extra.json`, `tools/hoerseite_sfx_ki.py messen`):
   - ffmpeg `astats` an WAV, OGG und M4A
   - Einsatzverzug (wann der Ton −20 dB vom Höchstwert erreicht)
   - Einsätze und stärkste Frequenz je Einsatz
   - schmale Linien im Spektrum über 5 kHz
   - Pulsfolge 15–50 Hz in der Hüllkurve (Schnurr-Bereich)
   - Anteil über 6 kHz nach gedachtem Tiefpass 5 kHz
3. **AudioSet-Klassen** (`tags_ast.json`): die stärksten Klassen und Warnklassen (Sprache, Tier, Katze, Musik, Rauschen, Zischen …).
4. **Beschreibungsmodell** (`beschreibungen.json`, `tools/beschreibe_sfx_ki.py`): Qwen3-Omni-Captioner, je Kandidat zwei Durchgänge.
   - eine freie Beschreibung
   - die Antwort auf die Frage, was zu hören ist, wie hochwertig und realistisch es klingt und ob es Störgeräusche, Rauschen, Verzerrung, Musik, Stimmen oder Tierlaute gibt
   - 45–95 s je Kandidat auf beiden GPUs, zusammen etwa 80 min. Das Skript ersetzt dafür beim Erzeugen die Experten-Schleife der int8-Variante durch Gather + bmm; das Ergebnis ist bis auf bf16-Rundung gleich und etwa 4-mal so schnell.

**Kriterien:** Passt der Klang zum Zweck? Gibt es Störgeräusche, Stimmen oder Tierlaute? Liegt die Dauer im Ziel und setzt der Ton sofort ein? Ist er auf dem Handy hörbar? Hält er die Katzen-Leitplanke ein? Bei Gleichstand zählt der sauberere Ton.

### Ergebnisse

- **Technisch sauber:**
  - Keine Übersteuerung: Flat factor 0 in allen WAV-, OGG- und M4A-Dateien.
  - Höchste Spitze nach dem Kodieren −0,94 dBTP (M4A) bzw. −0,98 dBTP (OGG).
  - Die Dauern von WAV, OGG und M4A stimmen überein.
- **Tierlaute:** keine (AudioSet Katze, Tier, Vogel überall unter 0,03).
- **Stimmen:** Jubel und Klatschen (`sieg_04` bis `sieg_06`, AudioSet „Speech“ bis 0,54) scheiden aus. Bei `flip_07` hört das Beschreibungsmodell ein Grunzen, AudioSet nicht; der Kandidat ist nicht in der Auswahl.
- **Zischen:** `flip_03` klingt wie eine Sprühdose (AudioSet „Hiss“ 0,64). Zischen ist ein Drohlaut für Katzen, den Kandidaten nicht verwenden.
- **Pfeifen:** schmale Linie bei 16 kHz in `flip_01`, fast so stark wie der stärkste Teil des Spektrums.
- **Treffer je Ton:**
  - Am besten getroffen: dran (Marimba), sieg (Glockenspiel), fehler (Holz) und stapel.
  - Schwächer: Für das Beschreibungsmodell klingen die Papiergeräusche nach Folie, Bonbonpapier, Reißen oder Klicks, nicht nach Spielkarten.
  - Flip: Kein Kandidat enthält den gewünschten warmen Glockenton; die Kartenprompts ergeben meist Papierreißen.

### Grenzen des Beschreibungsmodells

- **Kurze Schläge** beschreibt es oft als Klick, Metall oder Tastatur. Bei Schlägen meldet es mehrfach Übersteuerung, obwohl keine gemessen wird.
- **Die gezielte Frage** nennt „card game app“. Die Antworten deuten deshalb fast alles als Spielkarte und melden fast immer „keine Störgeräusche“. Für die Frage, was zu hören ist, zählt die freie Beschreibung.
- **Erfundene Töne:** Es hört mehrmals nach dem Ereignis einen tiefen Sinus- oder Brummton (`dran_07`, `flip_10`, `sieg_05`, `stapel_06`). Gemessen ist dort nichts oder nur Reste 30–50 dB unter dem Ton.
- **Tonhöhen und Dauern** in den Beschreibungen sind oft falsch, zum Beispiel „1047 Hz (C6)“ bei fast jedem Glockenton. Tonfolgen wurden deshalb mit einer CQT-Analyse nachgemessen.
- **Vergleiche mit bekannten Handy- und System-Hinweistönen** (bei sieben dran-Kandidaten) sind wahrscheinlich Gewohnheit des Modells. Sie zeigen aber, dass ein heller Glockenton schnell nach Benachrichtigung klingt.
- **Abgeschnittene Texte:** 15 der 79 freien Beschreibungen erreichten die Grenze von 450 Token.

## Mögliche nächste Schritte

1. **Hörtest** mit `hoeren.html`: zuerst „Im Spiel“ (gefiltert) gegen den ungefilterten Favoriten und gegen „alt“, dann gegen Platz 2/3, auf Handy und mit Kopfhörern.
2. **Anderer Kandidat oder andere Lautstärke:** `SPIEL` in `tools/make_sfx_moss.py` ändern, dann `make_sfx_moss.py --spiel`, `tools/godot_import.ps1` und `hoerseite_sfx_ki.py seite`.
3. **Gezielt nachbessern:**
   - **Flip:** neuer Prompt ohne „cards“, etwa „soft magical whoosh with a warm bell“. Oder einen Wusch mit dem alten synthetischen Glanz mischen.
   - **ziehen_06:** mit längerer Zieldauer neu schneiden; sein Hauptteil liegt bei 0,4–0,55 s.
   - **dran_04:** mit 0,75 s Zieldauer neu schneiden, damit der dritte Anschlag ausklingt.
   - **Weitere Seeds:** Für karte und ziehen lohnen sie, weil diese Töne am häufigsten erklingen.
4. **Pegel im Spiel:** auf dem Gerät gegen den Mau-Ton prüfen. Insgesamt lauter oder leiser: `TON_DB` in `game/scripts/app/sound.gd` und `STUFEN_SPIEL` in `webclient/ton.js` gemeinsam ändern (`TRIM_DB` bleibt leer, der Browser kennt keinen Feinabgleich).
5. **Stapel:** Wird der Ton genutzt, braucht `sound.gd` einen Eintrag und `SPIEL` in `make_sfx_moss.py` eine Zeile.

## Dateien

| Pfad | Inhalt |
|---|---|
| `hoeren.html` | Hörseite, offline: Abschnitt „Im Spiel“, je Ton Favorit, Platz 2 und 3, weitere Kandidaten, alte Fassung zum Vergleich |
| `<ton>_<nr>.wav/.ogg/.m4a` | bearbeitete Kandidaten |
| `roh/` | Originale des Modells (32-Bit-Float) mit Prompt und Seed je `.json` |
| `favoriten/` | Kopien der Favoriten als `<ton>.ogg` und `<ton>.m4a` (ungefiltert, 12 kHz) |
| `spiel/` | Fassungen im Spiel: `<ton>.wav` (24 Bit), `.ogg`, `.m4a`, `.png` (Spektrogramm), `messwerte.json` (`make_sfx_moss.py --spiel`) |
| `alt/` | die alten synthetischen Töne (`tools/make_sfx.py`, bis 05.10.2026 im Spiel) als `.ogg` und `.m4a` |
| `varianten.json` | Prompt, Seed, Laufzeit und Messwerte aller Kandidaten |
| `messung_extra.json` | eigene Zusatzmessungen |
| `tags_ast.json` | AudioSet-Klassen |
| `beschreibungen.json` | Texte des Beschreibungsmodells (englisch) |
| `spektrogramme/<ton>.png`, `<ton>_roh.png` | Übersicht je Ton (bearbeitet und Original) |
| `spektrogramme/einzeln/<id>.png` | Spektrogramm je Kandidat (für die Hörseite) |

## Neu bewerten

```powershell
. E:\Draw2Race-AudioLab\env.ps1
$py = 'E:\Draw2Race-AudioLab\analyse\.venv\Scripts\python.exe'
& $py tools\beschreibe_sfx_ki.py ast          # AudioSet-Klassen (CPU, 1 min)
& $py tools\beschreibe_sfx_ki.py qwen         # Beschreibungen (beide GPUs, etwa 70 min; vorhandene werden übersprungen)
& $py tools\hoerseite_sfx_ki.py alles         # messen, Spektrogramme, hoeren.html, Favoriten kopieren
```

Rangfolge und Begründungen stehen in `tools/bewertung_sfx_ki.py`. Wer nach dem Anhören anders entscheidet, ändert dort `rang` und ruft `hoerseite_sfx_ki.py seite favoriten` auf.
