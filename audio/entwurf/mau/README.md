# Entwürfe für den „Mau!“-Ton

Wer seine vorletzte Karte legt, drückt „Mau!“. Dazu soll ein kurzes, süßes Mauzen erklingen, das echte Katzen weder anlockt noch verwirrt (Nutzerwunsch, AGENTS.md Punkt 19). Hier liegen fünf Entwürfe mit ihren Messwerten und der Einschätzung eines lokalen Audio-Beschreibungsmodells.

**Herkunft aller Dateien:** synthetisch, eigenes Skript `tools/make_mau_sounds.py` (numpy/scipy, additive Synthese). Keine Aufnahmen, keine fremden Samples, keine KI-Generatoren, kein Zufall: Ein neuer Lauf erzeugt bitgleiche WAV-Dateien. Lizenz wie das Projekt (CC BY-NC 4.0).

**Anhören:** `hoeren.html` im Browser öffnen (funktioniert offline).

**Prüfung:** Die unabhängige Gegenprüfung mit Rangfolge steht im Abschnitt „Prüfung“ am Ende. **Niemand im Team hat die Töne bisher gehört.**

## Überblick

| Variante | Konzept | Töne | Dauer¹ | Schwerpunkt | Handy² | Modell hört (Runde 2) | Leitplanken |
|---|---|---|---|---|---|---|---|
| `a_blubb` | A „Blubb-Mau“, Tag | C4 → E4 (große Terz auf) | 293 ms | 474 Hz | −9,7 dB | Synthesizer-/Orgelton, „Benachrichtigung“ | 1–9 erfüllt, 12: 5/5 |
| `a_blubb_nacht` | A „Blubb-Mau“, Nacht | D4 → H3 (kleine Terz ab) | 308 ms | 457 Hz | −9,6 dB | tiefer Rechteckton, „NES-Game-Over“ | 1–9 erfüllt, 12: 5/5 |
| `b_gesungen` | B „Gesungenes Mau“ | H3 → E4 (Quarte auf) | 318 ms | 647 Hz | −7,1 dB | Kinderstimme sagt „Mao“, „Partytröte/Spielzeug“ | 1–9 erfüllt, 12: 4/5 |
| `c_spieluhr` | C „Spieluhr-Mau“ | C5 → E5 (große Terz auf) | 328 ms | 583 Hz | −9,1 dB | Glockenspiel/Celesta, „Tada“-Ton | 1–9 erfüllt, 12: 5/5 |
| `d_kalimba` | D „Kalimba-Pfoten-Mau“ | F4 → C5 (Quinte auf) | 301 ms | 432 Hz | −12,4 dB | Synthesizer-Note, „Power-up“ | 1–9 erfüllt, 12: 5/5 |

¹ Hüllkurve über −40 dB vom Höchstwert. ² Lautheitsverlust auf einem simulierten Handy-Lautsprecher (Hochpass 800 Hz, 12 dB/Oktave): Je kleiner der Betrag, desto besser kommt der Ton auf dem Handy durch.

Keine Variante hält das Modell für einen echten Tierruf. Den absichtlich katzenartigen Kontrollton beschreibt es dagegen als „Miau einer Hauskatze“, kann also unterscheiden. Die erste Fassung von B wurde als Katze gehört und deshalb überarbeitet (siehe „Iterationen“).

Konzept E („Okarina-Mau“) ist nicht gebaut: Die Recherche führt es wegen mittleren Katzenrisikos nur als letzte Wahl. Die fünfte Datei ist stattdessen die Nacht-Fassung von A (Option Tag und Nacht; Leitplanke 11 erlaubt höchstens zwei feste Varianten).

## Dateien

| Datei | Inhalt |
|---|---|
| `<variante>.wav` | Original: 48 kHz, mono, 16 Bit |
| `<variante>.ogg` | Ogg Vorbis (q6, etwa 110 kbit/s): Godot und Browser |
| `<variante>.m4a` | AAC (128 kbit/s): Safari/iPhone |
| `spektrogramme/<variante>.png` | Spektrogramm 0–24 kHz (90 dB Dynamik), Ausschnitt 0–6 kHz mit Grundfrequenz, Hüllkurve |
| `varianten.json` | Entwurfswerte je Variante (Töne, Soll-Formanten, Filterweg, Messabschnitte) |
| `messwerte.json` | alle Messwerte und die Leitplanken-Prüfung je Variante, auch für die kodierten Dateien |
| `beschreibungen.json` | Modelltexte je Runde: `runde1`, `versuche_b`, `runde2` (vollständig, englisch) |
| `hoeren.html` | Hörseite |

Skripte in `tools/`: `make_mau_sounds.py` (Synthese), `measure_mau_sounds.py` (Messung, Spektrogramme, Leitplanken-Prüfung), `describe_mau_sounds.py` (Modellbeschreibung). Jedes Skript erklärt im Kopf Zweck, Aufruf und Verfahren.

## Neu erzeugen und prüfen

```powershell
. E:\Draw2Race-AudioLab\env.ps1
$py = "E:\Draw2Race-AudioLab\analyse\.venv\Scripts\python.exe"
& $py tools\make_mau_sounds.py              # WAV, OGG, M4A, varianten.json
& $py tools\measure_mau_sounds.py           # messwerte.json, spektrogramme/
& $py tools\describe_mau_sounds.py runde3   # Modellbeschreibung (lokal, GPU; etwa 2,5 min je Datei)
```

Die Werkstatt `E:\Draw2Race-AudioLab` wird dabei nur gelesen. Zwischendateien und Logs des Beschreibungsskripts landen in ihrem Cache-Ordner `cache\tmp\mau_mau_flip_beschreibung\`. Das Skript hält die 27 GB großen int8-Experten im Arbeitsspeicher und lädt nur den Rest (5 GB) auf die GPU. So läuft es auch, wenn ein anderer Dienst (hier zeitweise ein `llama-server`) die GPUs größtenteils belegt.

## Pegel

Alle Varianten sind gleich laut: höchste Momentan-Lautheit (400 ms, BS.1770) −18 LUFS, echte Spitze −7 bis −11 dBTP, auch nach dem Kodieren (Leitplanke 9: höchstens −6 dBFS). ffmpeg `ebur128` misst integriert −19,8 LUFS, weil der Ton kein ganzes 400-ms-Fenster füllt. Der RMS-Pegel im Kern liegt bei etwa −15 dBFS.

**Abweichung:** Leitplanke 9 nennt als Dateipegel „RMS etwa −24 dBFS“, der Auftrag „etwa −16 LUFS“. Gewählt ist −18 LUFS mit Spitze unter −6 dBTP. So sind die Varianten beim Vergleichen gleich laut und es bleibt Platz nach oben. **Für das Spiel gilt:** Den Mau-Ton am Player oder Bus so einpegeln, dass er nicht lauter als der lauteste andere Spielton ist (voraussichtlich −6 bis −9 dB, also nahe −24 dBFS RMS). Im Raum bei Standard-Lautstärke höchstens 60 dB(A) in 1 m.

## Varianten im Einzelnen

Formanten werden aus der Obertonhüllkurve gemessen (Spitzen der Teiltöne k·F0). Bei F0 um 250–330 Hz liegen die Teiltöne weit auseinander, deshalb sind die Werte nur auf etwa ±F0/3 genau. „Keine Spitze“ heißt: Die Hüllkurve fällt vom Grundton an ab (dunkler o/u-Klang). Modelltexte sind gekürzt und übersetzt; den vollen englischen Text enthält `beschreibungen.json`.

### A „Blubb-Mau“ (Tag) – `a_blubb`

- **Konzept:** weicher Synth. Ein Sinus-Kern plus Dreieck mit etwas Rechteck, damit das „a“ durchkommt. Nur ungerade Teiltöne, dadurch klingt es hohl und rund. Zwei parallele Formant-Bandpässe wandern m (300/900 Hz) → a (800/1300 Hz) → o (560/1050 Hz); das u (380/850 Hz) schließt sich erst im Ausklang. Am Anfang ein kleiner „Plopp“: Die Tonhöhe fällt in der Anstiegszeit 2 Halbtöne von oben ein (Zeitkonstante 7 ms). Dann C4 (262 Hz) und nach 125 ms in 25 ms E4 (330 Hz). Tiefpass 5 kHz (8. Ordnung).
- **Messwerte:** Dauer 293 ms, Kern (über −10 dB) 242 ms. Töne 263 Hz (108 ms stabil, ±20 Cent) und 331 Hz (130 ms, ±30 Cent), Intervall +4,0 Halbtöne. Kein Bogen (0,1 Halbtöne), Gleiten in den Tönen höchstens 0,4 Okt./s. Schwerpunkt 474 Hz. Energie über 2/6/10/12 kHz: −34/−86/−87/−88 dB. HNR 27,7 dB, Modulation 15–50 Hz 4,3 %, Klick-Prüfung −57 dB. Anstieg 20 ms, Ausklang 75 ms, Spitze −10,5 dBTP. Formant im a-Teil etwa 600 Hz (h1 und h3 gleich stark), im o-Teil keine Spitze. F2 ist nicht getrennt messbar, weil nur ungerade Teiltöne vorhanden sind.
- **Handy:** −9,7 dB; der zweite Ton ist auf dem Handy 4,9 dB leiser als der erste.
- **Spektrogramm:** `spektrogramme/a_blubb.png`
- **Modell (Runde 1 und 2 gleich):** „Ein klarer, resonanter elektronischer Ton … Synthesizer oder digitale Orgel, hell und summend … wie ein Testton oder einfacher Hinweiston.“ Neutrale Frage: „Benachrichtigungston eines Computers oder Mobilgeräts.“ Gezielte Frage: synthetischer Spielton, nicht mit einem Tierruf zu verwechseln.
- **Leitplanken:** 1–9 messbar erfüllt. Der Plopp ist ein steiles Gleiten (etwa 6 Okt./s). Er liegt aber ganz in der Anstiegszeit unter −6 dB, fällt nach unten (kein katzentypischer Anstieg) und ist im Rezept A ausdrücklich vorgesehen. Leitplanke 12: Abweichung in allen 5 Achsen (gestuft, Menschengröße, 293 ms, Tiefpass, Synth-Klangfarbe).

### A „Blubb-Mau“ (Nacht) – `a_blubb_nacht`

- **Konzept:** wie A Tag, aber für die dunkle Kartenseite: D4 (294 Hz) → H3 (247 Hz), kleine Terz abwärts. Formanten a 860/1150 Hz, o 520/980 Hz, im Ausklang u 360/800 Hz. Teiltöne nur bis 4 kHz, Tiefpass 4 kHz.
- **Messwerte:** Dauer 308 ms, Kern 252 ms. Töne 293 Hz (110 ms, ±20 Cent) und 248 Hz (140 ms, ±20 Cent), Intervall −2,9 Halbtöne, kein Bogen. Schwerpunkt 457 Hz. Energie über 2/6/10/12 kHz: −33/−86/−87/−88 dB. HNR 27,0 dB, Modulation 3,4 %, Klick −55 dB. Anstieg 21 ms, Ausklang 81 ms, Spitze −10,9 dBTP. Formant im a-Teil etwa 630 Hz.
- **Handy:** −9,6 dB; der zweite Ton ist auf dem Handy 7,3 dB leiser. Das passt zur fallenden, dunklen Nacht, ergibt auf dem Handy aber die schwächste Melodie.
- **Spektrogramm:** `spektrogramme/a_blubb_nacht.png`
- **Modell (Runde 1 und 2 gleich):** „Ein reiner, tiefer Rechteckton, summend und hohl … erinnert stark an den ‚Game Over‘-Ton des NES (Chiptune der 1980er).“ Neutrale Frage: „Digitaler Synthesizer oder Computer.“ Gezielte Frage: synthetischer Spielton, nicht mit einem Tierruf zu verwechseln.
- **Leitplanken:** 1–9 erfüllt; 12: alle 5 Achsen.

### B „Gesungenes Mau“ – `b_gesungen`

- **Konzept:** stilisierte Stimme in Menschengröße mit additiver Formant-Synthese (nur F1 und F2). Die Quelle ist hell wie ein Sprachchip (Obertonabfall k^−1), ohne Atem, Rauschen, Vibrato und ohne reale Stimme. Erst ein gesummtes m (28 ms, Nasal-Formant 260 Hz), dann a (820/1250 Hz) auf H3 (247 Hz). Nach 140 ms geht es in 25 ms eine Quarte hinauf auf E4 (330 Hz) mit o (560/1050 Hz), das sich im Ausklang zum u (400/880 Hz) schließt.
- **Messwerte:** Dauer 318 ms, Kern 264 ms. Töne 247 Hz (120 ms, ±30 Cent) und 331 Hz (140 ms, ±30 Cent), Intervall +5,1 Halbtöne, kein Bogen, Gleiten höchstens 0,5 Okt./s. Schwerpunkt 647 Hz. Energie über 2/6/10/12 kHz: −54/−86/−87/−88 dB. HNR 26,5 dB, Modulation 3,7 %, Klick −56 dB. Anstieg 23 ms, Ausklang 75 ms, Spitze −6,9 dBTP (OGG −6,8). Formanten im a-Teil F1 ≈ 770 Hz, F2 ≈ 1130 Hz; höchste Spitze in den Tönen 1130 Hz.
- **Handy:** −7,1 dB (bester Wert); der zweite Ton ist auf dem Handy 3,1 dB leiser.
- **Spektrogramm:** `spektrogramme/b_gesungen.png`
- **Modell (Runde 2):** „Eine hohe Kinderstimme (etwa 3–6 Jahre) sagt das Wort ‚Mao‘, hell und melodisch, mit steigender Intonation.“ Neutrale Frage: „Eine Person, die in eine Partytröte bläst, oder ein Scherzspielzeug.“ Gezielte Frage: synthetischer Spielton, nicht mit einem Tierruf zu verwechseln. Als einzige Variante wird B als Wort gehört, und zwar als „Mao“.
- **Leitplanken:** 1–9 erfüllt. 12: Achsen a–d erfüllt, e (instrumentale Klangfarbe) nicht, denn es ist eine Stimme. Restrisiko laut Recherche: Menschenstimmen lösen Hinwenden aus [Q10], bei Katzen mit ähnlichem Namen („Mausi“, „Maui“) eher mehr [Q11].

### C „Spieluhr-Mau“ – `c_spieluhr`

- **Konzept:** zwei Celesta-artige Töne, C5 (523 Hz) und nach 130 ms E5 (659 Hz). Teiltöne 1, 2 und 3, also fast nur Grundton und Oktave. Weicher Anschlag (18 ms); beim zweiten Ton wird der erste abgedämpft. Ein nicht resonanter Tiefpass öffnet sich 500 → 1250 Hz („ma“) und schließt sich wieder auf 500 Hz („u“). Keine Vokal-Formanten.
- **Messwerte:** Dauer 328 ms, Kern 254 ms. Töne 525 Hz (122 ms) und 658 Hz (100 ms), Intervall +3,9 Halbtöne, kein Bogen. Schwerpunkt 583 Hz. Energie über 2/6/10/12 kHz: −63/−86/−87/−87 dB, damit am weitesten weg vom Vogel- und Mausbereich. HNR 32,4 dB, Modulation 3,7 %, Klick −50 dB. Anstieg 15 ms, Ausklang 128 ms, Spitze −7,9 dBTP.
- **Handy:** −9,1 dB; der zweite Ton ist auf dem Handy 2,7 dB lauter als der erste.
- **Spektrogramm:** `spektrogramme/c_spieluhr.png`
- **Modell (Runde 1 und 2 gleich):** „Ein heller, glockenartiger Ton wie Glockenspiel oder Celesta … erinnert an den ‚Tada‘-Ton von Windows XP.“ Neutrale Frage: „Benachrichtigungston eines Computers oder Smartphones.“ Gezielte Frage: synthetischer Spielton, nicht mit einem Tierruf zu verwechseln.
- **Leitplanken:** 1–9 erfüllt (Grundtöne im Instrumentenbereich 330–880 Hz, perkussiv); 12: alle 5 Achsen. „Mau“ ist nur angedeutet.

### D „Kalimba-Pfoten-Mau“ – `d_kalimba`

- **Konzept:** zwei warme Zupftöne, F4 (349 Hz) und nach 120 ms C5 (523 Hz), eine Quinte aufwärts. Teiltöne 1 bis 4 wie bei einem weich angeschlagenen Stab, weicher Anschlag (18 ms). Der Tiefpass öffnet sich beim ersten Ton (450 → 1800 Hz, „ma“) und schließt sich beim zweiten (1800 → 600 Hz, „u“). **Abweichung vom Rezept:** Das Rezept nannte D4 → A4 (294 → 440 Hz). D4 liegt aber unter dem Instrumentenbereich der Leitplanke 3 (330–880 Hz), deshalb liegt D eine Quarte höher.
- **Messwerte:** Dauer 301 ms, Kern 245 ms. Töne 351 Hz (108 ms) und 525 Hz (132 ms), Intervall +7,0 Halbtöne, kein Bogen. Schwerpunkt 432 Hz. Energie über 2/6/10/12 kHz: −38/−86/−87/−88 dB. HNR 32,1 dB, Modulation 5,1 %, Klick −54 dB. Anstieg 12 ms, Ausklang 104 ms, Spitze −8,1 dBTP. Der 4. Teilton des zweiten Tons liegt bei 2,09 kHz. Er ist schwach und klingt in etwa 25 ms ab, ist also kein reiner Ton im Bereich 2–9 kHz.
- **Handy:** −12,4 dB, der schwächste Wert, weil viel Energie im Grundton liegt; der zweite Ton ist auf dem Handy 3,7 dB lauter.
- **Spektrogramm:** `spektrogramme/d_kalimba.png`
- **Modell (Runde 1 und 2 gleich):** „Eine klare, synthetische Note … hell und obertonreich, kurzer perkussiver Anschlag … wie ein ‚Power-up‘ in Videospielen der 80er und 90er.“ Neutrale Frage: „Benachrichtigungston eines Computers oder Smartphones.“ Gezielte Frage: synthetischer Spielton, nicht mit einem Tierruf zu verwechseln.
- **Leitplanken:** 1–9 erfüllt; 12: alle 5 Achsen.

### Kontrollton (nur für das Modell)

`describe_mau_sounds.py` erzeugt im Temp-Ordner einen absichtlich katzenartigen Laut: Bogenkontur 550 → 850 → 480 Hz, 0,75 s, kleine Formanten, leichtes Zittern und etwas Hauch. Er gehört nicht zu den Spieltönen und liegt nicht im Projekt. Das Modell beschreibt ihn in beiden Runden als „ausdrucksstarkes Miau einer Hauskatze“, auf die neutrale Frage als „eine miauende Katze“. Daran zeigt sich, dass das Modell Katzenlaute erkennt; dass es die Varianten nicht als Katze hört, sagt also etwas aus.

## Leitplanken-Prüfung

Gemessen mit `tools/measure_mau_sounds.py` (Verfahren im Skriptkopf). „ja“ = eingehalten.

| # | Leitplanke | A Tag | A Nacht | B | C | D |
|---|---|---|---|---|---|---|
| 1 | Dauer 200–380 ms, Kern ≤ 300 ms | ja (293/242) | ja (308/252) | ja (318/264) | ja (328/254) | ja (301/245) |
| 2 | ≤ 2 stabile Töne ≥ 80 ms, ±30 Cent, Wechsel ≤ 30 ms, kein Bogen, kein Gleiten > 1 Okt./s | ja | ja | ja | ja | ja |
| 3 | F0: Stimme 180–330 Hz, Instrument 330–880 Hz | ja | ja | ja | ja | ja |
| 4 | Formanten F1 ≤ 1000, F2 ≤ 1500 Hz, keine Spitze über 1,8 kHz, kein [i] | ja | ja | ja | – (keine) | – (keine) |
| 5 | Energie über 6/10/12 kHz ≤ −30/−50/−60 dB (WAV, OGG, M4A) | ja (−86/−87/−88) | ja | ja | ja | ja |
| 6 | kein Rauschen, HNR ≥ 20 dB, keine Klicks | ja | ja | ja | ja | ja |
| 7 | keine Modulation 15–50 Hz, kein Vibrato, keine Pulsfolge | ja | ja | ja | ja | ja |
| 8 | Anstieg 10–40 ms (Stimme 20–40), Ausklang 60–150 ms | ja (20/75) | ja (21/81) | ja (23/75) | ja (15/128) | ja (12/104) |
| 9 | Spitze ≤ −6 dBFS | ja (−10,5) | ja (−10,9) | ja (−6,9) | ja (−7,9) | ja (−8,1) |
| 10 | ein Ton je Ansage, keine Schleife, kein Echo | Dateien ja; Spielcode offen | | | | |
| 11 | immer dieselbe Datei, höchstens 2 feste Varianten | ja (kein Zufall im Skript) | | | | |
| 12 | Abstand zu echten Rufen: ≥ 3 von 5 Achsen | 5/5 | 5/5 | 4/5 | 5/5 | 5/5 |

Zur Genauigkeit:

- Der Tonwechsel ist mit pyin (21-ms-Fenster) gemessen. Nach Abzug der Fensterbreite bleiben 0–14 ms Lücke; im Entwurf dauert er 25 ms.
- Die Modulationstiefe 15–50 Hz (3–5 %) stammt aus den Übergängen von Formanten und Tönen, nicht aus periodischer Modulation. Die Spektrogramme zeigen keine Seitenbänder.
- Der breite Schleier im 0–6-kHz-Bild um den Tonwechsel ist ein Effekt des langen Analysefensters (85 ms) über einem Tonhöhensprung, kein Rauschen; die HNR bleibt hoch.
- Oberhalb von 6 kHz liegt nur noch das Quantisierungsrauschen der 16-Bit-Datei (etwa −86 dB gegenüber dem Signal).

## Iterationen

**Runde 0 → 1 (Messung):**

1. **Pegelverlauf.** Mit offenem Mund (a) war B viel lauter als mit m und u, und bei B lag der lauteste Punkt im u. Der Anstieg auf −3 dB dauerte deshalb 165 ms statt höchstens 40 ms. Jetzt wird die Leistung je Abtastwert auf einen vorgegebenen Pegelverlauf gebracht.
2. **Anstieg und Ausklang.** A war für eine Stimme zu schnell (15 ms, jetzt 20 ms), D zu schnell (8 ms, jetzt 12 ms; Anschlag 10 → 18 ms). Der Ausklang von A war mit 59 ms zu kurz, jetzt 75 ms.
3. **Handy.** A verlor auf einem Kleinlautsprecher 17–19 dB, weil fast alles im Grundton lag. Abhilfe: mehr Obertöne (mehr Dreieck, etwas Rechteck, schmalerer und kräftigerer F1). Der Schwerpunkt stieg von 300 auf 474 Hz, der Verlust sank auf −9,7 dB. Bei B war der zweite Ton auf dem Handy 8,5 dB leiser. Abhilfe: Der Vokal schließt erst im Ausklang zum u (a → o → u), und der Pegelausgleich gewichtet halb wie ein Handy-Lautsprecher. Jetzt sind es etwa −3 dB. Bei D sind die Teiltöne 2–4 kräftiger.
4. **Messverfahren.** Die pyin-Schwelle wurde gesenkt (die Tonhöhe war richtig, nur die Wahrscheinlichkeit niedrig). Formanten werden jetzt aus der Obertonhüllkurve statt per LPC bestimmt (LPC hing bei hohem F0 an einzelnen Teiltönen fest). Gleiten wird per Ausgleichsgerade statt Frame-Differenz gemessen (pyin rastert in 10-Cent-Schritten).

**Runde 1 (Modell):** A Tag, A Nacht, C und D wurden als synthetische Töne beschrieben. **B in der ersten Fassung** (weiche Quelle k^−1,6, Formanten F1–F4) hörte das Modell als „hohes, klares Miau einer Hauskatze, sanft, leicht klagend“ und hielt eine Verwechslung mit einem echten Tierruf für möglich. Daraufhin wurden mehrere B-Fassungen getestet:

| Versuch | Änderung | Modell (Beschreibung / neutrale Frage) | Ergebnis |
|---|---|---|---|
| `b_hell` | Quelle k^−1,0 (heller) | synthetisches „Boing“ / Partytröte | kein Tier; aber F3 tritt bei 2,3–2,7 kHz als Spitze hervor (Leitplanke 4) |
| `b_chip` | hell, sprunghafte und schmale Formanten | „Boing“ wie in Looney Tunes / Partytröte | kein Tier, klingt nach Effekt statt nach „Mau“ |
| `b_tief` | A3 → D4, k^−1,3 | Kinderstimme sagt „Bye“; „könnte mit Tierruf verwechselt werden“ | verworfen |
| `b_tief_chip` | A3 → D4, hell, sprunghaft | synthetisches „Boop“ / Horn | kein Tier, wenig „Mau“ |
| `b_f3breit` | hell, F3/F4 3,5-mal breiter | Kinderstimme „moo“ / „Person, die eine Katze nachmacht“ | kein echtes Tier, aber nah am Miau-Nachahmen |
| **`b_ohne_f3`** | hell, nur F1/F2 | Kinderstimme sagt „Mao“ / Partytröte oder Spielzeug | **übernommen**: „Mau“ erkennbar, kein Tier, keine Spitze über 1,8 kHz, am wenigsten Energie über 2 kHz (−54 dB) |

**Runde 2 (Modell, Endstand):** Alle fünf Varianten wurden mit drei Abfragen geprüft (freie Beschreibung, gezielte Frage, neutrale Frage). Keine wird als Tier gehört, der Kontrollton weiter als Katze. Bei gleicher Datei liefert die gierige Dekodierung denselben Text; A, A Nacht, C und D sind deshalb in Runde 1 und 2 wortgleich.

**Grenzen des Modells:**

- Der Captioner ist nicht für Fragen trainiert. Die gezielte Frage nennt „cat meowing“ und lenkt damit: „ähnelt ‚meow‘“ und „klingt süß“ antwortet das Modell bei allen Dateien, auch beim Kontrollton. Diese beiden Antworten sagen deshalb nichts aus.
- Dauer und Tonhöhen in den Beschreibungen stimmen oft nicht (es nennt 0,8 s, A4, 110 Hz, C6), und den Zwei-Ton-Schritt bemerkt es bei A, C und D nicht.
- Belastbar ist nur die grobe Einordnung „Katze/Tier“ gegenüber „Stimme/synthetisch“, weil der Kontrollton zuverlässig als Katze erkannt wird. Ein Modell ist kein Katzenohr: Die Katzenprobe ersetzt es nicht.

## Abspielregeln für den Spielcode (aus der Recherche)

- Ein Ton je Ansage, keine Schleife, kein Echo; Sperre von mindestens 3 s im ganzen Netz.
- Im Netzwerk spielt nur das Gerät, auf dem „Mau!“ gedrückt wurde. Die anderen zeigen eine Animation, optional mit Vibration. „Ton auf allen Geräten“ ist standardmäßig aus. Für Browser-Gäste gilt dasselbe; der Host liefert die Datei offline aus (.ogg und .m4a).
- Immer dieselbe Datei, keine zufällige Tonhöhe; höchstens die zwei festen Fassungen Tag/Nacht.
- Einstellung „Mau-Ton: aus / leise / normal“ mit dem Hinweis „Katze im Raum? Leise stellen“.
- „Mau-Mau!“ bekommt ein eigenes Motiv (höchstens 600 ms), nicht zweimal den Mau-Ton hintereinander.

## Offene Punkte

1. **Menschlicher Hörtest.** Ob ein Ton süß klingt und als „Mau“ erkannt wird, kann das Modell nicht beurteilen. Bitte mit `hoeren.html` vergleichen, auch auf einem Handy-Lautsprecher. Mein Vorschlag für die engere Wahl: **B** (wird als „Mao“ gehört, nicht als Katze, beste Handy-Werte) und **A Tag/Nacht** (passt zum Tag/Nacht-Leitmotiv); **C** als sicherste Rückfalllösung (rein instrumental, am wenigsten Energie über 2 kHz).
2. **Katzentest** mit der gewählten Variante, schonend und freiwillig, nach Recherche Abschnitt 5: 2–5 Katzen, ihr Mensch ist dabei, Handy in 1–2 m Abstand, 5 Darbietungen im Abstand von 30–60 s, abwechselnd mit einem neutralen Klick. Bestanden, wenn keine Katze sich nähert, sucht oder antwortet und das Hinwenden nur bei den ersten 1–2 Darbietungen auftritt.
3. **Tag/Nacht für die gewählte Variante.** Nur A hat bisher eine Nacht-Fassung. Fällt die Wahl auf B, C oder D, lässt sich die Nacht-Fassung im selben Skript ergänzen (kleine Terz abwärts, dunkler gefiltert).
4. **Pegel im Spiel** gegen die übrigen Spieltöne abgleichen (siehe „Pegel“) und den Raumpegel messen (≤ 60 dB(A) in 1 m).
5. **„Mau-Mau!“-Motiv** (eigener Ton, ≤ 600 ms) ist noch nicht entworfen.

## Prüfung

Unabhängige Gegenprüfung vom 04.10.2026. Die Klangdateien sind unverändert. Gemessen habe ich mit der Werkstatt-Python (numpy, scipy, librosa) und ffmpeg/ffprobe 9.0.1, mit eigenen Verfahren statt `measure_mau_sounds.py`. Die Prüfskripte lagen nur im temporären Arbeitsordner.

> **Niemand im Team hat die Töne bisher gehört.** Klangdesigner und Prüfer sind KI-Agenten. Alle Aussagen beruhen auf Messungen und auf einem Beschreibungsmodell. Ob ein Ton süß klingt, als „Mau“ erkannt wird und Katzen kalt lässt, zeigt erst der Hörtest (siehe „Beim Anhören beachten“).

### Vorgehen

- `tools/make_mau_sounds.py` gelesen und alle Varianten im Speicher neu erzeugt.
- Alle zehn kodierten Dateien mit ffprobe geprüft und vollständig dekodiert (ffmpeg `-xerror`).
- WAV, OGG und M4A selbst gemessen:
  - **Hüllkurve:** mit 2,5-, 5- und 10-ms-Fenster sowie analytisch aus dem Skript.
  - **Tonhöhe:** Harmonischen-Summe mit 20-ms-Fenster, dazu YIN.
  - **Bandenergie:** steiler FIR-Hochpass, wie `sox sinc`.
  - **Klicks:** Hochton-Anteil in 2-ms-Abschnitten.
  - **Modulation:** Hüllkurvenspektrum 15–50 Hz.
  - **Lautheit:** ffmpeg `ebur128`.
  - **Handy:** zwei Lautsprecher-Modelle.
- Spektrogramme angesehen: die vorhandenen und eigene mit 5-ms-Fenster und 110 dB Dynamik, getrennt für WAV, OGG und M4A.

### Befunde

Keine Variante verstößt in der Sache gegen eine Leitplanke. Gefunden habe ich zwei formale Grenzfälle (A: Anstieg, A Tag und B: 330-Hz-Grenze), ein schwaches Kodier-Artefakt in den M4A-Dateien, drei Ungenauigkeiten im README und eine Pegelfrage im Spielcode.

**Dateien und Abspielbarkeit**

- Alle 15 Klangdateien sind vorhanden und dekodieren fehlerfrei:
  - WAV: 48 kHz, mono, 16 Bit.
  - OGG: Vorbis, etwa 110 kbit/s.
  - M4A: AAC, etwa 114–118 kbit/s.
- Alle Fassungen liegen zeitgleich zur WAV (Versatz 0).
- OGG endet 128 Abtastwerte (2,7 ms) früher. Das fällt in die 20 ms Stille am Dateiende und ist harmlos.
- Ein neuer Lauf des Skripts ergibt alle fünf WAV-Dateien bitgleich.

**Klickfreiheit am Anfang und Ende**

- **WAV und OGG sind klickfrei:**
  - Erster und letzter Abtastwert sind 0.
  - Der Ton setzt mit weichem Kosinus-Anstieg ein.
  - Am Ende folgen 21–36 ms Stille.
  - Über 6 kHz liegt nur das 16-Bit-Grundrauschen (etwa −101 dBFS in 2-ms-Abschnitten).
- **M4A:** Bei A, A Nacht, C und D legt der AAC-Kodierer in den ersten 50 ms einen schwachen Breitband-Schleier (5–15 kHz).
  - Stärke: höchstens −66 dB unter dem stärksten Abschnitt (D), also weit unter Leitplanke 5.
  - Es ist trotzdem das einzige klickartige Muster in allen Dateien. B ist frei davon.

**Leitplanken 1–9**

| # | Ergebnis |
|---|---|
| 1 | eingehalten: Dauer 291–328 ms, Kern 241–262 ms |
| 2 | eingehalten, Plopp von A vom Rezept gedeckt (siehe unten) |
| 3 | eingehalten; **Grenzfall** bei A Tag und B (siehe unten) |
| 4 | eingehalten: B über 2 kHz −54 dB, kein Gipfel über 1,8 kHz |
| 5 | eingehalten mit großem Abstand (siehe unten) |
| 6, 7 | eingehalten (siehe unten) |
| 8 | **Grenzfall** bei A Tag und A Nacht (siehe unten); sonst eingehalten |
| 9 | Spitze eingehalten; RMS etwa 9 dB über der Vorgabe (siehe „Pegel und Lautheit“) |

- **L2 Tonhöhenkontur**
  - Die Töne sind im Skript exakt konstant. Gemessene Schwankungen bis ±30 Cent stammen vom Messfenster an den Rändern der Töne.
  - Der Tonwechsel dauert 25 ms (A, B). Bei C und D klingt der erste Ton gedämpft unter dem zweiten aus.
  - Es gibt keinen Bogen (höchstens 0,1 Halbtöne).
  - Schneller als 1 Okt./s gleitet die Tonhöhe nur im Tonwechsel und beim „Plopp“ von A und A Nacht.
  - Beim Plopp weicht die Tonhöhe nur bis etwa 13 ms um mehr als 30 Cent ab; der Pegel liegt dort bei etwa −8 dB. Das Gleiten über 1 Okt./s dauert aber bis etwa 22 ms (Pegel etwa −2 dB, Restabweichung unter 10 Cent). Die README-Angabe „ganz unter −6 dB“ stimmt also nur für den hörbaren Teil. Das Rezept A sieht den Plopp ausdrücklich vor.
- **L3 Grundfrequenz:** Der zweite Ton von A Tag und B ist E4 (329,6 Hz), also 0,4 Hz unter der Stimm-Obergrenze von 330 Hz. Der pyin-Messwert von 331 Hz besteht nur dank 1 % Toleranz in `measure_mau_sounds.py`.
- **L5 Obere Frequenzgrenze:** Energie über 6/10/12 kHz:
  - WAV: etwa −86/−87/−88 dB (16-Bit-Grundrauschen).
  - OGG: −95 dB oder weniger.
  - M4A, schlechtester Fall D: −78/−84/−86 dB.
- **L6 und L7 Rauschen und Modulation**
  - Die Spektrogramme zeigen saubere Teiltöne und kein Rauschen.
  - Der Schleier um den Tonwechsel im 0–6-kHz-Bild der A-Varianten verschwindet mit einem 21-ms-Fenster. Er ist also ein Analyse-Effekt, wie im README beschrieben.
  - Im Hüllkurvenspektrum zwischen 15 und 50 Hz gibt es keine scharfe Linie (wie sie Schnurren erzeugen würde), nur breite Ausläufer des Tonwechsels: höchstens 4,5 % bei D um 31 Hz.
- **L8 Hüllkurve**
  - **Grenzfall A:** Der Anstieg von A Tag misst je nach Fenster 18,3–19,7 ms, analytisch 18,4 ms. A Nacht misst 18,9–20,8 ms, analytisch 19,6 ms.
  - Für Stimmklänge verlangt Leitplanke 8 mindestens 20 ms. Das README meldet 20 bzw. 21 ms; das ist ein Effekt des 10-ms-Messfensters.
  - Praktisch ist das unerheblich, weil ein Schreck einen hohen Pegel braucht. Formal ist die Grenze aber knapp verfehlt.
  - Übrige Werte eingehalten: B 22–24 ms, C 15 ms, D 11,5–13 ms (Instrument: mindestens 10 ms). Ausklang 72–144 ms.

**Pegel und Lautheit**

Pegel und Lautheit passen zueinander:

| Variante | Echte Spitze | RMS im Kern |
|---|---|---|
| A Tag | −10,5 dBTP | −15,2 dBFS |
| A Nacht | −10,9 dBTP | −15,4 dBFS |
| B | −6,9 dBTP | −15,8 dBFS |
| C | −7,9 dBTP | −15,5 dBFS |
| D | −8,1 dBTP | −15,2 dBFS |

- Alle Varianten haben −18,0 LUFS als höchsten Momentanwert, nach eigener Rechnung und nach ffmpeg. Integriert sind es −19,7 bis −19,8 LUFS.
- Nach dem Kodieren ändert sich die Spitze um höchstens 0,25 dB. B als OGG erreicht −6,8 dBTP und bleibt unter −6 dBTP.
- Der RMS-Pegel liegt etwa 9 dB über der Vorgabe „etwa −24 dBFS“. Das README nennt diese Abweichung offen.

**Handy**

Wie gut eine Variante auf dem Handy abschneidet, hängt stark vom angenommenen Lautsprecher ab:

| Lautsprecher-Modell | A Tag | A Nacht | B | C | D |
|---|---|---|---|---|---|
| README: Hochpass 800 Hz, 12 dB/Oktave | −9,7 dB | −9,6 dB | −7,1 dB | −9,1 dB | −12,4 dB |
| strenger: Hochpass 1 kHz, 24 dB/Oktave | −13,5 dB | −13,1 dB | −9,6 dB | **−17,7 dB** | **−22,9 dB** |

C und D werden auf kleinen Lautsprechern deutlich leiser und dünner als A und B.

**Spielcode** (`game/scripts/app/sound.gd`)

- „Mau“ spielt bei „normal“ mit −6 dB, alle anderen Töne mit −8 dB. Sind die Dateien gleich laut, wäre der Mau-Ton 2 dB lauter als die übrigen Töne. Leitplanke 9 verlangt: nicht lauter als der lauteste andere Spielton.
- Noch ruft kein Code den Mau-Ton auf. Die 3-s-Sperre (Leitplanke 10) fehlt deshalb ebenfalls noch.

**Beschreibungsmodell**

- Auf die gezielte Frage antwortet das Modell bei allen Dateien gleich, auch beim Kontrollton: synthetisch, ähnelt „meow“, süß.
- Unterschiede zeigen nur die neutrale Frage und die Frage nach Verwechslung mit einem Tierruf.
- Als Gegenprobe dient ein einziger, selbst gebauter Kontrollton. Das ist ein schwacher Nachweis.

**README gegen Dateien**

- Das README stimmt mit den Dateien überein, bis auf drei Angaben: Anstieg von A, Plopp „ganz unter −6 dB“ und die 330-Hz-Toleranz.
- Nicht erwähnt ist die lokale Stilvorlage `audio/referenz/simons_cat_mau.wav`. Sie ist Fremdmaterial und per `.gitignore` ausgeschlossen. Gemessen:
  - Tonlage ähnlich, etwa 280–320 Hz.
  - Dauer 416 ms.
  - gleitender Anstieg um etwa 2,5 Halbtöne (etwa 1,4 Okt./s).
  - Energie über 10 kHz: −34 dB.

  Als Spielton verstieße sie gegen die Leitplanken 1, 2 und 5. Sie taugt nur als Vorlage für Tonlage und Charakter.

### Rangfolge

Die Rangfolge ist vorläufig. Sie beruht auf Messung und Katzenrisiko; ob ein Ton süß klingt und nach „Mau“, entscheidet der Hörtest.

1. **A „Blubb-Mau“ Tag, mit A Nacht als Tag/Nacht-Paar.**
   - **Warum vorn:** der beste Kompromiss.
     - Die Vokalbewegung m → a → o → u deutet „Mau“ an, der Klang bleibt aber klar synthetisch (Modell: „Benachrichtigungston“).
     - Alle 5 Abstandsachsen sind erfüllt.
     - Auf dem Handy solide in beiden Modellen (−9,7 / −13,5 dB).
     - Passt schon jetzt zum Tag/Nacht-Leitmotiv.
   - **Vorher nötig:** Anstieg verlängern (Empfehlung 1).
   - **Schwäche:** A Nacht allein ist schwächer, weil ihr zweiter Ton auf dem Handy 7 dB leiser ist.
2. **C „Spieluhr-Mau“.**
   - **Warum stark:** die sicherste Variante. Kein Stimmklang, keine Formanten, größter Abstand bei allen Grenzwerten (über 2 kHz −63 dB).
   - **Schwächen:**
     - „Mau“ ist nur angedeutet.
     - Auf einem steilen Handy-Lautsprecher verliert sie −17,7 dB.
     - Die Grundtöne (523 und 659 Hz) liegen in der mittleren Miau-Tonlage. Das ist erlaubt, weil der Ton perkussiv ist, beim Katzentest aber zu beachten.
   - **Rolle:** Rückfall, falls A durchfällt.
3. **B „Gesungenes Mau“.**
   - **Stärken:** am ehesten ein „Mauzen“; auf dem Handy am kräftigsten (−7,1 / −9,6 dB).
   - **Schwächen:**
     - Als einzige Variante eine Stimme (Achse e verfehlt).
     - Das Modell hört ein Kind.
     - Der zweite Ton liegt auf der 330-Hz-Grenze.
     - Laut Recherche wenden sich Katzen Menschenstimmen zu [Q10] und reagieren auf ähnliche Namen [Q11].
   - **Kann aufrücken,** wenn Menschen B klar vorziehen **und** B den Katzentest besteht.
4. **D „Kalimba-Pfoten-Mau“.**
   - **Stärke:** katzensicher.
   - **Schwächen:**
     - am wenigsten „Mau“;
     - auf dem Handy am schwächsten (−12,4 / −22,9 dB);
     - stärkster Anteil zwischen 2 und 9 kHz aller Varianten: 4. Teilton bei 2,09 kHz, −29 dB gegenüber dem stärksten Anteil. Als Teil eines Klangs ist das zulässig.

Unter „Offene Punkte“ steht B vorn. Ich setze A vor B, weil B als einzige Variante ein Katzenrisiko trägt, das sich nicht wegmessen lässt: die Stimme.

### Empfehlungen

1. **Anstieg von A verlängern:** in `blubb()` `attack` von 0,030 s (Tag) und 0,032 s (Nacht) auf 0,034 bzw. 0,035 s setzen. Dann neu erzeugen und messen. Der Anstieg liegt danach analytisch bei 20,6 bzw. 21,3 ms.
2. **M4A neu kodieren:** ohne Hochton-Schleier, z. B. mit `-af lowpass=f=6000` vor dem AAC-Kodierer oder mit `-cutoff 6000`. Danach erneut prüfen. Im Spiel (Godot) OGG verwenden, das ist die sauberste Fassung.
3. **Optional, Abstand zur 330-Hz-Grenze:** A Tag und B um einen Halbton tiefer legen (A: H3 → Dis4, B: B3 → Es4). Das nur tun, wenn der Hörtest es zulässt.
4. **Pegel im Spiel:**
   - In `sound.gd` `MAU_DB.normal` höchstens auf den Pegel der anderen Töne setzen (−8 dB), besser −9 dB. Das entspricht etwa −24 dBFS RMS.
   - Auf einem echten Handy gegen die übrigen Töne abgleichen.
   - Raumpegel messen: höchstens 60 dB(A) in 1 m.
5. **Abspielregeln im aufrufenden Code umsetzen:** 3-s-Sperre im ganzen Netz, Ton nur auf dem Gerät, auf dem „Mau!“ gedrückt wurde. Dazu einen Test schreiben.
6. **Prüfskript schärfen:** Grenzfälle beim Anstieg mit kürzerem Fenster oder analytisch messen. Die 1-%-Toleranz bei Leitplanke 3 entfernen oder offen ausweisen.

### Beim Anhören beachten

- **Selbst hören:** Niemand hat die Töne bisher gehört. Bitte selbst hören, bevor eine Variante ins Spiel kommt.
- **Wie hören:**
  - Über den Handy-Lautsprecher, nicht nur mit Kopfhörern.
  - In normaler Lautstärke, nicht voll aufgedreht.
  - `hoeren.html` funktioniert offline auch auf dem Handy.
  - Mehrere Personen hören lassen und die Reihenfolge wechseln.
- **Je Variante notieren:**
  - Wie süß ist sie (1–5)?
  - Klingt sie nach „Mau“?
  - Klingt sie nach echter Katze oder Kätzchen? Dann ausscheiden.
  - Knackt etwas am Anfang oder Ende?
  - Nervt sie auch beim 20. Mal? In einer Partie erklingt der Ton oft.
- **Mit Katze im Raum:**
  - In den ersten Hördurchgängen nicht gezielt vorspielen. Ist ohnehin eine Katze im Raum, sie aber beobachten.
  - Danach mit den 1–2 Favoriten den schonenden Test machen (Recherche, Abschnitt 5):
    - Handy 1–2 m von der Katze entfernt, normale Lautstärke, ihr Mensch ist dabei.
    - 5 Durchgänge im Abstand von 30–60 s, abwechselnd mit einem neutralen Klick.
- **Worauf achten:**
  - Ohren oder Kopf drehen sich zum Handy.
  - Die Katze steht auf oder kommt heran.
  - Sie sucht am oder hinter dem Handy.
  - Sie antwortet mit einem Miau.
  - Ihre Pupillen weiten sich.
  - Sie zuckt zusammen oder flieht.
- **Wie bewerten:** Ein einmaliges Ohrendrehen beim ersten Mal ist normal, wie bei jedem neuen Geräusch. Bestanden ist eine Variante, wenn:
  - das Hinwenden nachlässt,
  - es nicht stärker ist als beim Klick,
  - und keine Katze sucht, herankommt oder antwortet.
- **Rücksicht auf die Katze:**
  - Abbrechen, sobald eine Katze unruhig wirkt.
  - Keine echten Miaus zum Vergleich abspielen.
  - Die Töne nicht in Schleife abspielen.
- **Ergebnis notieren:** Variante, Katze, Durchgang und Reaktion kurz festhalten und hier im README nachtragen.

## Quellen (aus der Recherche, hier zitiert)

- [Q10] Saito, Shinozuka (2013): Vocal recognition of owners by domestic cats. Animal Cognition. https://link.springer.com/article/10.1007/s10071-013-0620-4
- [Q11] Saito et al. (2019): Domestic cats discriminate their names from other words. Scientific Reports. https://www.nature.com/articles/s41598-019-40616-4
- Leitplanken, Konzepte A–E und Prüfablauf stammen aus der Recherche zum Mau-Ton (04.10.2026, Quellen Q1–Q32).
