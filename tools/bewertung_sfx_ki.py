"""Bewertung der KI-Tonkandidaten (audio/sfx_ki/), von Hand am 05.10.2026.

Grundlage: Messwerte (varianten.json, messung_extra.json), AudioSet-Tags (tags_ast.json) und die Beschreibungen
des Qwen3-Omni-Captioners (beschreibungen.json). Niemand hat die Töne gehört.
Die gezielte Frage nennt „card game app“; die Antworten darauf deuten deshalb vieles als Spielkarte. Was zu hören ist,
stützt sich vor allem auf die freie Beschreibung, die Frage dient der Suche nach Störgeräuschen.

REIHENFOLGE  Abschnitte der Hörseite
BEWERTUNG    je Ton: name, zweck, rang (Favorit, Platz 2, Platz 3), kurzgrund (Tabelle), fazit, gruende je Kandidat
KURZ         je Kandidat: was das Modell hört (sinngemäß, gekürzt)
"""

REIHENFOLGE = ["karte", "ziehen", "mischen", "flip", "dran", "fehler", "sieg", "stapel"]

BEWERTUNG = {
    "karte": {
        "name": "Karte legen",
        "zweck": "Karte auf den Tisch, kurz und trocken; erklingt in jeder Partie sehr oft",
        "rang": ["karte_02", "karte_07", "karte_09"],
        "kurzgrund": "ein einzelner Schlag mit glattem Ausklang (0,24 s), unter den knackigen Kandidaten am "
                     "wenigsten Höhen, auf dem Handy voll hörbar",
        "fazit": "Das Modell erkennt bei keinem Kandidaten sicher eine Spielkarte; es hört Klicks, Klacken und "
                 "Holzschläge. Kurze Schläge sind für Beschreibungsmodelle schwer, hier zählt der Hörtest besonders. "
                 "Die drei Favoriten sind einzelne, saubere Schläge ohne Übersteuerungsverdacht. Wer es dumpfer mag "
                 "(Filztisch, katzenfreundlich): karte_04, auf dem Handy aber 6 dB leiser.",
        "gruende": {
            "karte_02": "Ein Schlag mit glattem, kurzem Ausklang, keine Nachschläge. Über 6 kHz −22,6 dB (die "
                        "wenigsten Höhen der knackigen Kandidaten), Handy −0,4 dB, Original mit 67 dB "
                        "Rauschabstand. Das Modell hört ein metallisches Klicken mit kurzem Klappern; beim Anhören "
                        "prüfen, ob es nach Karte oder nach Münze klingt.",
            "karte_07": "Sehr kurzer, kräftiger Schlag (0,14 s) mit tiefem Anteil (Schwerpunkt 956 Hz), Handy "
                        "−1,2 dB. Heller als karte_02 (über 6 kHz −15,4 dB); das Modell hört einen kleinen "
                        "Metallgegenstand auf harter Fläche, sauber.",
            "karte_09": "Der kürzeste (0,10 s), knackig; AudioSet ordnet ihn am ehesten als „Slap, smack“ ein. Das "
                        "Modell hört eine mechanische Tastatur – beim 50. Mal könnte das nach Tippen klingen. Hell "
                        "(über 6 kHz −11 dB), schmale Spitze bei 7,6 kHz.",
            "karte_01": "Mehrere Nachschläge (Einsätze bei 64, 117, 181, 224 ms); das Modell hört Klick und "
                        "Aufschlag wie einen Kameraverschluss. Sehr hell (über 6 kHz −9,5 dB).",
            "karte_04": "Holzschlag auf hohlem Körper, dumpf und sauber (über 6 kHz −36,5 dB, katzenfreundlich), "
                        "auf dem Handy aber −6,1 dB. Dumpfe Alternative.",
            "karte_05": "Drei Schläge, AudioSet „Knock“ 0,66; das Modell hört Übersteuerung und Rauschen.",
            "karte_06": "Dumpfer Knacks mit Aufschlag, katzenfreundlich (über 6 kHz −47,6 dB), Handy −6,0 dB; das "
                        "Modell hört Übersteuerung (gemessen nicht, Spitze −1,1 dBTP).",
            "karte_08": "Zwei Schläge, sehr spitz (6 dB begrenzt, danach 6 dB abgesenkt), Original mit nur 54 dB "
                        "Rauschabstand; das Modell hört harte Übersteuerung.",
        },
    },
    "mischen": {
        "name": "Mischen",
        "zweck": "Stapel riffeln, zu Beginn einer Runde",
        "rang": ["mischen_06", "mischen_08", "mischen_05"],
        "kurzgrund": "zwei dichte Flatter-Schübe wie beim Riffeln, gleichmäßig laut (fast am Lautheitsziel), "
                     "AudioSet-Klasse „Shuffling cards“ hier am höchsten",
        "fazit": "Das Modell hört bei allen Kandidaten eher Folie oder Bonbonpapier als Spielkarten; ein echtes "
                 "Riffeln mit anschließendem Zusammenschieben erkennt es nirgends. Alle sind hell (über 6 kHz −4 bis "
                 "−8 dB, Katzen-Leitplanke −30 dB) und bis auf mischen_02 bei 1,2 s abgeschnitten (Ausblenden "
                 "50 ms). Mischen erklingt selten, Helligkeit stört hier weniger als beim Kartenlegen.",
        "gruende": {
            "mischen_06": "Zwei dichte Schübe (etwa 0,45–0,6 s und 0,85–1,1 s) aus vielen kleinen Klicks, wie "
                          "beim Riffeln; dazwischen einzelne Klicks. Fast am Lautheitsziel (−19,8 statt −18 LUFS), "
                          "also ohne große Ausreißer. Das Modell hört Zellophan-Knistern, sauber, ohne Störungen.",
            "mischen_08": "Am wärmsten (Schwerpunkt 2,6 kHz, über 6 kHz −8,4 dB), dichtes Flattern über die ganze "
                          "Länge, fast am Lautheitsziel (−19,6 LUFS). Das Modell hört ein papierartiges Reißen mit Rascheln. Hüllkurve "
                          "mit leichter 17-Hz-Periodik (Schärfe 7, unter der Warnschwelle).",
            "mischen_05": "Mehrere getrennte Schübe mit einem Aufprall; −21,7 LUFS. Das Modell hört eine "
                          "Snacktüte, die geöffnet wird; AudioSet „Crack“ 0,43.",
            "mischen_01": "Knistern mit Knacken (Folie, die aufgerissen wird); Pause in der Mitte.",
            "mischen_02": "Endet als einziger natürlich (1,17 s), aber leise (−25,2 LUFS) und spitz; Folie.",
            "mischen_03": "Gleichmäßige Klickfolge, am ehesten wie Riffeln, aber leise (−26,3 LUFS) und spitz; "
                          "das Modell hört Bonbonpapier.",
            "mischen_04": "Leise (−26,5 LUFS) und spitz; Knistern mit Knacken.",
            "mischen_07": "Sehr regelmäßige Klickschübe (das Modell: 10–12 Klicks/s, „mechanisch, metallisch“), am "
                          "hellsten (Schwerpunkt 5,4 kHz).",
        },
    },
    "flip": {
        "name": "Flip",
        "zweck": "Flip-Karte wendet alles (Tag ↔ Nacht): Wusch mit Glanz",
        "rang": ["flip_02", "flip_12", "flip_10"],
        "kurzgrund": "einziger Kandidat, den beide Modelle als Wusch hören (AudioSet „Whoosh“ 0,49), danach ein "
                     "heller Glanz; sauber",
        "fazit": "Kein Kandidat enthält den gewünschten warmen Glockenton; die Kartenprompts ergeben vor allem "
                 "Papierreißen. Nur flip_02 klingt nach magischem Übergang. Alle Flip-Kandidaten sind hell "
                 "(über 6 kHz −0,4 bis −25 dB); ein Tiefpass 5 kHz würde den Glanz von flip_02 weitgehend nehmen.",
        "gruende": {
            "flip_02": "Wusch, der 0,75 s anschwillt, dann ein metallisches „Shing“ und ein heller Nachglanz. "
                       "AudioSet: Whoosh 0,49; keine Stimme, kein Rauschen; Original mit 82 dB Rauschabstand. "
                       "Beim Anhören prüfen: der harte Wechsel bei 0,75 s (unten bricht das Rauschen ab) und ob "
                       "das „Shing“ zu sehr nach Schwert klingt. Der Höhepunkt liegt erst bei 0,75 s; die "
                       "Flip-Animation müsste darauf warten oder der Ton früher starten.",
            "flip_12": "Kurzer, sauberer Wisch in den ersten 0,3 s, danach ein leiser hoher Nachglanz (8,7–10 kHz, "
                       "22 dB leiser). Klingt eher nach schneller Karte als nach Magie, ist aber knapp und sauber.",
            "flip_10": "Papierflattern über 0,7 s, danach Ruhe. Das Modell hört am Ende einen tiefen Summton; "
                       "gemessen ist der Rest 32 dB leiser als der Ton, also kaum hörbar. Wirkt eher wie Reißen.",
            "flip_01": "Starke schmale Linie bei 16 kHz (nur 5 dB unter der stärksten Spektrallinie) und eine "
                       "Hüllkurve, die mit 20 Hz pulsiert; das Modell hört Knistern wie Übersteuerung.",
            "flip_03": "Zischen wie aus einer Sprühdose (AudioSet „Hiss“ 0,64, „Snake“ 0,46). Zischen ist ein "
                       "Drohlaut für Katzen – nicht verwenden.",
            "flip_04": "Wusch mit Hall, aber AudioSet „Static“ 0,45, Rauschabstand im Original nur 36 dB, erst nach "
                       "378 ms laut.",
            "flip_07": "Papierreißen; das Modell hört danach ein kurzes Grunzen eines Mannes (AudioSet sieht keine "
                       "Stimme). Wegen des Verdachts nicht in der Auswahl.",
            "flip_08": "Folienrascheln; sehr spitz (nach dem Begrenzer noch 11 dB abgesenkt), dadurch leise (−30,8 LUFS).",
            "flip_09": "Papierreißen mit Aufprall, am wärmsten (über 6 kHz −25 dB), aber erst nach 188 ms laut; das "
                       "Modell hört an der lautesten Stelle Knistern.",
            "flip_11": "Reißen und dumpfer Aufprall wie beim Öffnen eines Umschlags; dumpf (Handy −5,4 dB).",
        },
    },
    "dran": {
        "name": "Du bist dran",
        "zweck": "sanfter, kurzer Hinweis, wenn man am Zug ist (gewünscht: zwei Töne aufwärts)",
        "rang": ["dran_04", "dran_05", "dran_02"],
        "kurzgrund": "Marimba/Holz, drei Anschläge aufwärts (etwa A4 – D5 – A5), sauber, klingt nicht nach "
                     "Handy-Benachrichtigung",
        "fazit": "Die meisten Kandidaten sind ein einzelner Glockenton. Mehrere Töne gibt es nur bei P2 (dran_04 "
                 "bis dran_06). Das Modell vergleicht mehrere helle Glockentöne mit bekannten Handy- und "
                 "System-Hinweistönen; das kann eine Fehldeutung sein, wäre aber im Spiel ungünstig, weil man "
                 "eine eingehende Nachricht vermuten könnte.",
        "gruende": {
            "dran_04": "Holzschlägel auf Marimba, drei Anschläge im Abstand von 0,25 s, Tonhöhe steigt (etwa "
                       "A4 – D5 – A5). Warm, trocken, über 6 kHz −35 dB (Katzen-Leitplanke eingehalten), Handy "
                       "−2,6 dB. Kein Vergleich mit Handy-Tönen. Beim Anhören prüfen: Der dritte Anschlag wird nach "
                       "90 ms ausgeblendet (Zieldauer 0,6 s) und könnte abgeschnitten wirken.",
            "dran_05": "Drei schnelle Glockenspiel-Töne in 0,26 s, sauber. Das Modell vergleicht ihn mit einem "
                       "bekannten Handy-Nachrichtenton – im Spiel verwechselbar. Handy −4,3 dB.",
            "dran_02": "Ein einzelner, sehr klarer hoher Glockenton (etwa D6), am besten auf dem Handy (−0,8 dB), "
                       "über 6 kHz −44 dB. Nur ein Ton statt zwei; als schlichter Ersatz geeignet.",
            "dran_01": "Ein einzelner Ton, auf dem Handy −9,9 dB.",
            "dran_03": "Ein einzelner Ton mit etwas Hall, Handy −5,4 dB.",
            "dran_06": "Derselbe Ton dreimal angeschlagen (kein Anstieg); Hüllkurve pulsiert mit 24 Hz, das Modell "
                       "hört am Ende einen Klick.",
            "dran_07": "Einzelner metallischer Glockenschlag; leise Linie bei 7,1 kHz. Das Modell hört danach ein "
                       "60-Hz-Brummen; gemessen liegt unter 300 Hz nichts (über 45 dB leiser), vermutlich eine "
                       "Fehldeutung.",
            "dran_08": "Einzelner Glockenton; das Modell vergleicht ihn mit einem bekannten Handy-Nachrichtenton.",
            "dran_09": "Glockiger Doppelschlag (hoch, dann tiefer Akkord), klavierartig; das Modell vergleicht ihn "
                       "mit einem bekannten System-Hinweiston.",
            "dran_10": "Einzelner Akkord-Glockenton.",
            "dran_11": "Einzelner Glockenton, sauber.",
            "dran_12": "Einzelner Glockenton; im Original nur 41 dB Rauschabstand.",
        },
    },
    "fehler": {
        "name": "Fehler",
        "zweck": "weiches „nö“ bei einem ungültigen Zug; darf nicht nerven, muss auf dem Handy hörbar sein",
        "rang": ["fehler_09", "fehler_11", "fehler_05"],
        "kurzgrund": "hohles, holziges „Tock“ (Schlägel auf Handtrommel), sauber; unter den dumpfen Kandidaten "
                     "am besten auf dem Handy (−7 dB)",
        "fazit": "Fast alle Kandidaten sind tiefe Schläge, die auf Handy-Lautsprechern viel verlieren (−7 bis "
                 "−40 dB). Der alte synthetische Ton verlor −12 dB. Wer einen hörbareren Fehler-Ton will, nimmt "
                 "fehler_05, riskiert aber eine Verwechslung mit dem Kartenlegen.",
        "gruende": {
            "fehler_09": "Schlägel auf hohlem Holz, tiefes holziges „Tock“ mit kurzem Nachklang, 0,25 s. Sauber, "
                         "keine Stimme (AudioSet „Grunt“ nur 0,03). Schwerpunkt 363 Hz, Handy −7,0 dB.",
            "fehler_11": "Hohles „Plopp“ mit einem zweiten, tieferen Nachschlag (etwa A♯4 → G4) – fallend wie ein "
                         "„nö“. Handy −11,3 dB; das Modell hört ein leises Nachklingen.",
            "fehler_05": "Kurzes, hartes Klacken (0,11 s), auf dem Handy am besten (−1,7 dB). Kein „nö“-Charakter; "
                         "könnte mit dem Kartenlegen verwechselt werden.",
            "fehler_02": "Basstrommel-artiger Schlag mit Klick, Handy −9,2 dB, etwas kurz (0,2 s).",
            "fehler_08": "Tiefer Schlag, den AudioSet als Klopfen (an eine Tür) einordnet (0,81); Handy −14,5 dB.",
            "fehler_10": "Holzblock, warm, aber viel Tiefbass (Schwerpunkt 127 Hz, Handy −15,9 dB).",
            "fehler_12": "Holzblock mit hörbarem Nachklingen (AudioSet „Clang“/„Ding“), Handy −14,4 dB.",
        },
    },
}

BEWERTUNG["ziehen"] = {
    "name": "Karte ziehen",
    "zweck": "Karte vom Stapel nehmen: kurzes, weiches Wischen; erklingt sehr oft",
    "rang": ["ziehen_07", "ziehen_04", "ziehen_02"],
    "kurzgrund": "ein vollständiger, schneller Wisch (nach 50 ms hörbar, nach 0,25 s vorbei), sauber; aber sehr hell",
    "fazit": "Kein Kandidat klingt für das Modell nach Gleiten; es hört Reißen, Knistern oder Klicks. Die Wisch-Form "
             "(anschwellendes Rauschen, das wieder abfällt) haben nur ziehen_04, ziehen_05 und ziehen_07; sie sind "
             "hell (über 6 kHz −3,8 bis −6,4 dB) mit einer Betonung um 6 kHz und liegen damit weit über der "
             "Katzen-Leitplanke. Der alte Ton war deshalb bei 2,4 kHz begrenzt. Für ziehen lohnt der Vergleich "
             "mit Tiefpass 5 kHz besonders. ziehen_06 wäre der wärmste, aber sein Hauptteil liegt erst bei "
             "0,4–0,55 s und wird von der Zieldauer 0,6 s abgeschnitten.",
    "gruende": {
        "ziehen_07": "Rauschen schwillt in 0,15 s an und fällt bei 0,25 s ab, endet mit einem leisen Klick; danach "
                     "nur noch leiser Ausklang. Schnell da (46 ms), kurz – gut für einen häufigen Ton. Das Modell "
                     "hört einen sauberen, einzelnen Riss durch steifes Papier. Sehr hell (Schwerpunkt 5,7 kHz, "
                     "über 6 kHz −3,8 dB), Betonung bei 6 kHz.",
        "ziehen_04": "Die deutlichste Wisch-Form: Anschwellen 0,1–0,35 s, kleiner Klick am Ende wie ein "
                     "Aufsetzen. AudioSet am ehesten „Zipper“. Hell (über 6 kHz −4,3 dB) mit schwachen Linien "
                     "bei 16–17,6 kHz; erst nach 164 ms laut, wirkt also verzögert.",
        "ziehen_02": "Die warme Alternative (Schwerpunkt 1,7 kHz, über 6 kHz −14,7 dB): kurze Klick- und "
                     "Klapperfolge bei 0,1–0,25 s, danach Ruhe. Das Modell hört einen metallischen Riegel – "
                     "eher Klicken als Wischen.",
        "ziehen_01": "Kurzer Schlag mit Nachschlägen (0,27 s); das Modell hört harte Übersteuerung.",
        "ziehen_03": "Knacks mit Aufprall und Rascheln; das Modell hört Übersteuerung.",
        "ziehen_05": "Wisch mit einem Knacks am Ende, hell; erst nach 174 ms laut; das Modell hört Übersteuerung.",
        "ziehen_06": "Am wärmsten (über 6 kHz −21 dB), sauber, aber der Hauptteil liegt bei 0,4–0,55 s und wird am "
                     "Ende der Zieldauer abgeschnitten; die ersten 0,2 s sind fast still.",
        "ziehen_08": "Durchgehendes Knistern wie eine Snacktüte; Rauschabstand im Original nur 52 dB.",
        "ziehen_09": "Knistern wie eine Snacktüte, sehr hell (über 6 kHz −4 dB).",
    },
}

BEWERTUNG["sieg"] = {
    "name": "Sieg",
    "zweck": "kurze, fröhliche Melodie, wenn jemand fertig ist (so laut wie der Mau-Ton)",
    "rang": ["sieg_03", "sieg_01", "sieg_07"],
    "kurzgrund": "Glockenspiel/Marimba, Töne steigen stufenweise an (gemessen etwa C4 – E4 – G4 – C5, auf einen "
                 "Halbton genau), sauber, kaum Höhen",
    "fazit": "Die Fassungen mit Jubel und Klatschen (sieg_04 bis sieg_06) enthalten Stimmen („Wooo!“, AudioSet "
             "„Speech“ bis 0,54) und Rauschen; sie scheiden aus. Unter den Melodien steigt nur sieg_03 deutlich an; "
             "sieg_01, sieg_02 und sieg_08 wiederholen ein Zwei-Ton-Motiv. Die hellen Glocken in sieg_07 und sieg_09 "
             "liegen über der Katzen-Leitplanke.",
    "gruende": {
        "sieg_03": "Erst ein Anschlag, dann eine schneller werdende Tonfolge, die stufenweise ansteigt; der letzte "
                   "Ton klingt länger. Das passt am besten zu „geschafft“. Sauber, leichter Hall, über 6 kHz "
                   "−39,5 dB (Katzen-Leitplanke eingehalten), 1,76 s. Das Modell beschreibt die Folge einmal als "
                   "fallend, einmal als steigend; die Tonhöhenmessung zeigt einen Anstieg. Handy −6,3 dB.",
        "sieg_01": "Warme Marimba, vier Anschläge im gleichmäßigen Abstand (0,25 s), ein Motiv aus zwei Tönen, "
                   "das sich wiederholt. Sehr sauber und am katzenfreundlichsten (über 6 kHz −47,7 dB); wirkt "
                   "eher wie ein freundliches Signal als wie ein Triumph. Handy −5,4 dB.",
        "sieg_07": "Kurzer Lauf, dann ein lange klingender Glockenakkord – am ehesten eine kleine Fanfare. Aber "
                   "helle Glockenteiltöne bei 9–16 kHz (über 6 kHz −22 dB, über der Katzen-Leitplanke); mit "
                   "Tiefpass 5 kHz würde der Akkord matter.",
        "sieg_02": "Wie sieg_01, ein Ton mehr (fünf Anschläge); das Modell hört ein fallendes Motiv.",
        "sieg_04": "Jubel einer Gruppe („Wooo!“) mit Klatschen, Hall und Rauschen; Stimmen.",
        "sieg_05": "Klatschen mit kurzem Ruf, AudioSet „Speech“ 0,54; Rauschen.",
        "sieg_06": "Klatschen und Jubel einer großen Gruppe, Rauschen; Stimmen.",
        "sieg_08": "Fünfmal fast derselbe Ton, metallisch, wie ein Metallofon; das Modell nennt es "
                   "„mechanisch gleichmäßig“. Auf dem Handy am besten (−2,2 dB).",
        "sieg_09": "Glitzernde, fallende Glockenkaskade wie eine App-Belohnung; anhaltender Teilton bei 6,8 kHz "
                   "(nur 12 dB unter der stärksten Linie), über 6 kHz −10 dB.",
    },
}

BEWERTUNG["stapel"] = {
    "name": "Stapel aufstoßen",
    "zweck": "neu, noch nicht im Spiel: Stapel zweimal auf den Tisch stoßen (z. B. nach dem Mischen)",
    "rang": ["stapel_02", "stapel_06", "stapel_08"],
    "kurzgrund": "zwei klar getrennte, saubere Schläge mit kurzem Aufsetzen, 0,51 s, auf dem Handy voll hörbar",
    "fazit": "Der Ton wird im Spiel bisher nicht verwendet (sound.gd kennt ihn nicht); es gibt keine alte Fassung. "
             "Prompt P2 („zweimal stoßen“) trifft die Idee besser als P1.",
    "gruende": {
        "stapel_02": "Zwei getrennte Schläge, der zweite etwas tiefer, je mit kurzem Aufsetzen; das Modell hört "
                     "einen kleinen harten Block, der zweimal aufsetzt. Sauber, 0,51 s, Handy −0,6 dB, über 6 kHz "
                     "−16,7 dB.",
        "stapel_06": "Zwei dumpfe Holzschläge, warm und katzenfreundlich (über 6 kHz −53 dB), 0,43 s. AudioSet "
                     "hört „Knock“ (0,60), also eher Klopfen; auf dem Handy −6,9 dB. Das Modell hört danach einen "
                     "110-Hz-Sinuston, gemessen ist zwischen den Schlägen nichts (−49 dB) – Fehldeutung.",
        "stapel_08": "Ein heller Aufprall mit mehreren leiseren Nachschlägen wie ein Aufsetzen und Zurechtrücken, "
                     "0,76 s, Handy −2,5 dB.",
        "stapel_01": "Das Modell hört ein Sturmfeuerzeug (Klick, Reibrad, Zünden); leise (−29,5 LUFS) und sehr spitz.",
        "stapel_03": "Zwei metallische Klicks mit Pause, wie ein Riegel.",
        "stapel_04": "Knistern einer Folientüte mit Aufsetzen.",
        "stapel_05": "Klacken mit metallischem Rasseln wie Münze oder Würfel.",
        "stapel_07": "Ein einzelner metallischer Klack (Schreibmaschine), danach fast nur Ausklang.",
    },
}

KURZ = {
    # karte
    "karte_01": "scharfer Klick und dumpfer Aufschlag, wie ein Kameraverschluss",
    "karte_02": "metallisches Klicken mit kurzem Klappern (wie ein kleiner Gegenstand, der aufschlägt), sauber",
    "karte_03": "schnelle Folge von Knacken und Knistern",
    "karte_04": "Holzschlag auf einen hohlen Körper, holzig und kurz, sauber",
    "karte_05": "metallisches Klacken mit Aufprall und Nachklingen; das Modell hört Übersteuerung und Rauschen",
    "karte_06": "spröder Knacks mit dumpfem Aufschlag; das Modell hört Übersteuerung",
    "karte_07": "kurzer, heller Schlag wie ein kleiner Metallgegenstand auf harter Fläche, sauber",
    "karte_08": "lauter Schlag mit Aufprall; das Modell hört harte Übersteuerung",
    "karte_09": "einzelner, sehr kurzer Klick wie eine mechanische Tastatur, sauber",
    # ziehen
    "ziehen_01": "scharfer Schlag mit leiserem Nachschlag; das Modell hört Übersteuerung",
    "ziehen_02": "metallisches Klicken mit kurzem Klappern, wie ein Riegel oder Schalter, sauber",
    "ziehen_03": "spröder Knacks mit Aufprall und kurzem Rascheln; das Modell hört Übersteuerung",
    "ziehen_04": "kurzes Reißen oder Ratschen (Folie) mit leisem Rascheln, sauber",
    "ziehen_05": "Knacks mit dumpfem Aufprall, als fiele ein Blatt Papier; das Modell hört Übersteuerung",
    "ziehen_06": "einzelnes, sauberes Reißen von steifem Papier",
    "ziehen_07": "einzelnes, sauberes Reißen von steifem Papier in einem Zug",
    "ziehen_08": "durchgehendes Knistern einer Folientüte",
    "ziehen_09": "unregelmäßiges Knistern einer Folientüte",
    # mischen
    "mischen_01": "Knistern von Folie und ein spröder Knacks",
    "mischen_02": "Knistern und Rascheln, wie eine Snacktüte",
    "mischen_03": "gleichmäßiges Knistern von Bonbonpapier",
    "mischen_04": "Knistern von Folie und ein Knacks",
    "mischen_05": "Knistern mit dumpfem Aufprall, wie eine Snacktüte, die geöffnet wird",
    "mischen_06": "Zellophan-Knistern mit leiserem Rascheln, sauber",
    "mischen_07": "schnelle, regelmäßige Klickfolge, hell und mechanisch",
    "mischen_08": "papierartiges Reißen (etwa 0,3 s) mit anschließendem Rascheln",
    # sieg
    "sieg_01": "Xylofon oder Glockenspiel, ein Zwei-Ton-Motiv zweimal, sauber und trocken",
    "sieg_02": "Xylofon oder Glockenspiel, Zwei-Ton-Motiv wiederholt, sehr sauber",
    "sieg_03": "Glockenspiel, ein Anschlag und eine kurze, schnelle Tonfolge, letzter Ton länger, sauber mit "
               "leichtem Hall",
    "sieg_04": "Jubel einer Gruppe („Wooo!“) und Klatschen in einer Halle, Rauschen",
    "sieg_05": "Klatschen einer kleinen Gruppe mit kurzem Ruf, Rauschen",
    "sieg_06": "Klatschen und Jubel einer großen Gruppe, Rauschen",
    "sieg_07": "Holzblock und helle Glocken, Lauf und ein klingender Akkord, mit Hall",
    "sieg_08": "gleich klingende metallische Anschläge (Metallofon), sehr regelmäßig",
    "sieg_09": "kristallene, fallende Glockenkaskade wie eine App-Belohnung",
    # stapel
    "stapel_01": "Klick, Reiben und leises Zünden wie bei einem Sturmfeuerzeug",
    "stapel_02": "zwei kurze Schläge eines kleinen harten Blocks auf eine harte Fläche, sauber",
    "stapel_03": "metallischer Klick mit Schaben, Pause, dann derselbe Klick noch einmal",
    "stapel_04": "Knistern einer Folientüte, danach dumpfes Aufsetzen",
    "stapel_05": "Klacken und Aufprall, dann metallisches Rasseln wie eine Münze",
    "stapel_06": "Holzblock-Klack mit kurzem Raumklang; danach angeblich ein tiefer Sinuston (gemessen nicht)",
    "stapel_07": "ein einzelner metallischer Klack wie eine Schreibmaschinentaste",
    "stapel_08": "heller Aufprall mit dumpfem Nachschlag, als würde etwas aufspringen und liegen bleiben",
    # dran
    "dran_01": "ein einzelner heller Synth-Glockenton, sauber, ohne Störgeräusche",
    "dran_02": "ein hoher, klarer elektronischer Glockenton, sehr sauber; erinnert das Modell an einen bekannten "
               "System-Hinweiston",
    "dran_03": "ein einzelner glasiger Synth-Glockenton mit etwas Hall, sauber",
    "dran_04": "Holzschlägel auf Marimba oder Xylofon, mehrere Anschläge mit kurzer Pause, trocken und sauber",
    "dran_05": "kurzer heller Glockenspiel-Hinweis, sauber; das Modell vergleicht ihn mit einem bekannten "
               "Handy-Nachrichtenton",
    "dran_06": "heller Hinweis, als schnelles Arpeggio aus drei Tönen gehört; am Ende ein kurzer Klick",
    "dran_07": "ein einzelner metallischer Glockenschlag, natürlich und sauber",
    "dran_08": "ein einzelner elektronischer Glockenton mit etwas Hall; erinnert das Modell an einen bekannten "
               "Handy-Nachrichtenton",
    "dran_09": "glockiger Dreiklang (Celesta/Klavier); erinnert das Modell an einen bekannten System-Hinweiston",
    "dran_10": "ein einzelner Glockenton mit Obertönen, sauber",
    "dran_11": "ein einzelner Glockenton, sauber und unaufdringlich",
    "dran_12": "ein einzelner glasiger Glockenton, sauber",
    # fehler
    "fehler_01": "tiefer Basstrommel-Schlag mit kurzem Klick",
    "fehler_02": "tiefer Basstrommel-Schlag mit Klick, sauber",
    "fehler_03": "tiefer, hohler Schlag (Holz oder Trommel)",
    "fehler_04": "tiefer, dumpfer Schlag mit langem Nachklang",
    "fehler_05": "kurzes, hartes Klacken (Kunststoff auf harter Fläche), sauber",
    "fehler_06": "tiefer, voller Schlag mit kurzem Anschlaggeräusch",
    "fehler_07": "tiefer, hohler Holzschlag",
    "fehler_08": "tiefer Basstrommel-Schlag, sauber",
    "fehler_09": "Holzschlägel auf hohlem Holz (Handtrommel), tiefes holziges „Tock“, sauber",
    "fehler_10": "Holzblock mit Schlägel, warm und holzig, sauber",
    "fehler_11": "hohles „Plopp“ (Hand auf Kunststoff) mit leisem Nachklingen",
    "fehler_12": "Holzblock mit Schlägel, holzig, kurzer Nachklang",
    # flip
    "flip_01": "hohes Rascheln wie Folie; das Modell hört Knistern wie bei Übersteuerung und danach ein leises Brummen",
    "flip_02": "synthetischer Wusch, dann ein metallisches „Shing“ (wie Schwert ziehen oder Karte wenden), sauber",
    "flip_03": "lautes Zischen wie aus einer Sprühdose",
    "flip_04": "kräftiger Wusch mit Hall wie in einer großen Halle, danach ein tiefer Sinuston",
    "flip_05": "Wusch mit dumpfem Aufprall",
    "flip_06": "dumpfer Aufprall mit kurzem Quietschen",
    "flip_07": "Papierreißen und Rascheln; danach hört das Modell ein kurzes Grunzen eines Mannes",
    "flip_08": "Rascheln einer Folienverpackung und ein Reißen",
    "flip_09": "Papierreißen mit leisem Aufprall; an der lautesten Stelle hört das Modell Knistern",
    "flip_10": "Papierreißen (etwa 0,4 s), danach laut Modell ein tiefer Summton",
    "flip_11": "Papierreißen und dumpfer Aufprall, wie beim Öffnen eines Umschlags",
    "flip_12": "kurzes, sauberes Reißen oder Wischen, danach fast Stille",
}
