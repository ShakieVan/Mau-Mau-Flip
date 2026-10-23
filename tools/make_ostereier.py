"""Hörproben für „Ostereier Teil 2“ (an Mitspieler senden) mit MOSS-SoundEffect v2.0 erzeugen und nachbearbeiten.

Entwurf (13.10.2026), ändert keine Spieldateien. Töne: Gähnen, Schnarchen, Wecker (Ticken und Klingeln IN EINEM STÜCK
erzeugt, nie zusammengeschnitten; dazu „nur Klingeln“ als Ausweichlösung), Papierkugel (Wurf, Plopp) und die Reaktionen
Lachen, Schreck, Klatschen, Daumen. Nutzt tools/make_sfx_moss.py (Erzeugung, Schnitt, Pegel, Begrenzer, Katzen-Leitplanke)
und die Handy-Simulation aus tools/make_schnurren.py.

Aufruf (PowerShell)
  . E:\\Draw2Race-AudioLab\\env.ps1
  $py = 'E:\\Draw2Race-AudioLab\\moss-sfx\\.venv\\Scripts\\python.exe'
  & $py tools\\make_ostereier.py --alles [--gpu 0]        # erzeugen, bearbeiten, AudioSet-Prüfung, Hörseite
  & $py tools\\make_ostereier.py --erzeugen [--nur wecker,daumen] [--gpu 0]
  & $py tools\\make_ostereier.py --bearbeiten               # ohne GPU
  & 'E:\\Draw2Race-AudioLab\\analyse\\.venv\\Scripts\\python.exe' tools\\make_ostereier.py --ast   # AudioSet (CPU)
  & $py tools\\make_ostereier.py --seite                    # Auswahl, Ablage, messwerte.json, hoeren.html
  & $py tools\\make_ostereier.py --alles --nur gaehnen2 --gpu 0   # nur diese Töne; --ast/--seite mit --nur lassen alle
                                                            # anderen Einträge (ast.json, messwerte.json, Dateien) stehen
  & $py tools\\make_ostereier.py --alles --nur furzkissen --gpu 0  # Furzkissen (15.10.2026)
  Vorhandene Rohdateien werden nicht neu erzeugt. Benötigt ffmpeg im PATH.

Gähnen Runde 2 („gaehnen2“, 13.10.2026): Runde 1 klang nach tiefem, gepresstem Stöhnen (Nutzerbefund, AudioSet „Groan“
0,4–0,65). Neue Prompts (Frau luftig, Morgen mit Strecken, Zeichentrick, höflich hinter der Hand, müdes Kind) mit einem
CFG-Negativ-Prompt gegen Stöhnen/Ächzen/Grunzen (Pipeline-Argument negative_prompt, siehe MitNegativ) und als A/B-Zwillinge
mit „no groaning …“ im Prompt ohne Negativ-Prompt. Auswahl: AudioSet-Klassen in TOENE[...]["meiden"] schließen aus,
Atemklassen zählen mit ihrer Summe, Tonhöhe und Stimmanteil (librosa.pyin, stimme_messen) gehen in die Notizen ein;
Dubletten über alle Paare; höchstens 3 je Prompt-Variante. Stand: 78 erzeugt, 8 behalten (gaehnen2_01–08). Ergebnis
A/B: Negativ-Prompt Groan im Median 0,01, „no groaning …“ im Prompt 0,10 (2 von 10 brauchbar).

Gähnen Runde 3 („gaehnen3“, 13.10.2026): Nutzerbefund zu Runde 2: überall erst das „Gähnen“, danach das Luftholen;
richtig ist erst tief Einatmen (offener Mund), dann ein langes stimmhaftes, fallendes „aaah“, gehaucht ausklingend.
Reihenfolge ausdrücklich im Prompt („first … then …“), angelehnt an „frau“/Seed 4110 (gaehnen2_02), Negativ-Prompt wie
Runde 2; eigener Schnitt (gaehnen_schnitt), der den leisen Atem vorn behält. Reihenfolge-Prüfung (reihenfolge_messen,
analyse-Umgebung, Grenzen RF_*): vorn ≥ 0,5 s hörbarer, gehauchter Atem, danach der stimmhafte Teil (Mitte hinter der
Mitte der Dauer) mit fallender Tonhöhe, gehauchtes Ende, kein neuer Atemzug danach; wer sie nicht besteht, fällt aus
(„nur_ok“, kein Auffüllen). Gegenprobe: alle 8 Kandidaten der Runde 2 fallen durch. Dazu ein einziger Versuch
„gaehnen3_02umgestellt“ (umstellen): in gaehnen2_02 Atem und „aaah“ an der natürlichen Pause getauscht, Nähte in der
Stille überblendet. Je Variante optional CFG und Daueransage (6. Feld des Prompt-Eintrags, optionen_von). Stand:
297 erzeugt (25 Varianten), 6 bestanden (frau_zuerst 2/36, frau_followed_lang_cfg7 2/36, frau_followed_lang 1/12,
frau_zuerst_5s 1/6); sonst Stimme zuerst, nur Hauchen ohne Stimme, zu kurzer Atem vorn oder stimmhaftes Ende.

Furzkissen („furzkissen“, 15.10.2026, neues Easter Egg): Scherzkissen aus Gummi, das man einem Mitspieler unterschiebt.
Komisches, gummiartiges „Pfrrrrt“, eher lustig als eklig; keine echten Körpergeräusche, nichts Feuchtes, keine Stimmen,
kein Lachen. Vier Arten als Kategorie im 6. Feld des Prompt-Eintrags (je eigene Zieldauer, Daueransage, ggf. Pegel):
kurz und knackig, lang und flatternd, zum Schluss steigend (quietschig), leiseres kleines „Pfft“. Alles Unerwünschte
als CFG-Negativ-Prompt. Messung furz_messen (analyse-Umgebung): Stöße, Tonhöhe und ihr Verlauf zum Schluss, Knattern,
Klangfarbe; die quietschige Art muss zum Schluss messbar steigen. Auswahl ausgewogen über die Arten (reihum die
besten), nur Bestandene, Dubletten über alle Paare; Nummern nach Art geordnet. AudioSet kennt „Fart“, „Squeak“,
„Squish“, „Boing“, aber weder „Raspberry“ noch „Rubber“. Stand: 110 erzeugt (14 Prompt-Varianten in zwei Runden),
30 bestanden, 10 behalten (furzkissen_01–10). Tragend: „kurz“, „kurz2“, „lang“/„lang_14“/„lang2“, „quietschig“,
„quietschig_langsam“, „pfft_furz“; „pfft“/„pfft_klein“ ohne „fart“ ergaben Glocken, „kurz_platt“ Schläge.
Erzeugt im Sparmodus auf GPU 0 (LM Studio belegte beide GPUs), rund 30 s je Ton.

Zunge rausstrecken („baeh“, 16.10.2026, neue Reaktion 😛/😝): kindlich-neckisches „Bäää“/„Bläää“, gern mit kurzem
Zungen-Flattern (Prusten), lustig und freundlich; 0,6–1,2 s, ein Laut, keine Wörter, kein Lachen, kein Tier (nicht nach
Schaf/Ziege: im Prompt „bleh“, „baa“/„bleating“ nur im Negativ-Prompt). Vier Arten (kurz, lang, mit Prusten, hell) wie
beim Furzkissen, Auswahl reihum, nur Bestandene. Messung baeh_messen: Zahl der Laute, Stimme/Tonhöhe, Flattern 20–80 Hz,
Zittern 4–12 Hz (Meckern); dazu muss AudioSet einen Mundlaut/eine Stimme hören („mensch“). Stand: 164 erzeugt
(22 Prompt-Varianten in drei Runden), 21 bestanden, 8 behalten (baeh_01–08, je 2 pro Art). Das Modell kennt das
Raspberry nicht („raspberry“, „Bronx cheer“: Zischen, Plopps, Knall); geflattert hat nur „mouth fart“ (mundfurz,
bleh_mundfurz; AudioSet hört dann „Fart“). Viele „bleh“ hört AudioSet als Sprache, lange „bleeeh“ als Summen/Gesang,
helle Stimmen als Wimmern, Kichern, Pfeifen oder Miauen. Schaf/Ziege gab nie den Ausschlag (einziger Fall lang_7126,
ohnehin ohne Stimme). Sparmodus auf GPU 0 (--vram 6.5, Spitze 5,4 GiB), etwa 30 s je Ton.
Lauf: & $py tools\\make_ostereier.py --erzeugen --nur baeh --gpu 0 --vram 6.5, dann --bearbeiten/--ast/--seite mit
--nur baeh.

Sparmodus (15.10.2026): Ist auf der GPU weniger als SPARSAM_AB_GIB frei (z. B. fremdes Sprachmodell geladen), lädt
erzeugen das Modell in den Arbeitsspeicher und holt je Schritt nur den gerade nötigen Teil auf die GPU
(Textkodierer, DiT, VAE; DiffSynth-VRAM-Verwaltung), ohne Autocast-Zwischenspeicher der bf16-Gewichte (requires_grad
aus; gleiche Rechnung, gleicher Ton je Seed), Stapel 1; PyTorch darf höchstens den freien Speicher minus
SPARSAM_RESERVE_GIB belegen, damit fremde Prozesse nicht verdrängt werden. Frei = laut nvidia-smi (unter WDDM zählt
torch.cuda.mem_get_info den Speicher untätiger fremder Prozesse als frei und verdrängt ihn). Ist ein fremder Prozess
schon ausgelagert (nvidia-smi zeigt dann zu viel frei), die Grenze mit --vram <GiB> von Hand setzen, z. B.
  & $py tools\\make_ostereier.py --erzeugen --nur furzkissen --gpu 0 --vram 6.5

Erzeugung: je Ton 3 Prompt-Varianten × 3 Seeds; nach der ersten Sichtung mehr Seeds bzw. eine vierte Variante bei
Wecker (22), Gähnen (12), Schreck (11), Plopp (12); Klingeln 2 × 3. 100 Schritte, CFG 4, shift 5, Daueransage im
Prompt wie in make_sfx_moss.py (Original 2 s länger gespeichert, danach geschnitten). Gleicher Seed bei ähnlichem
Prompt ergibt oft fast denselben Ton: solche Dubletten (Spektrogramm r > 0,9) fallen aus der Auswahl.

Nachbearbeitung je Kandidat
  Gleichanteil weg, Hochpass (60–90 Hz je Ton), Schnitt wie make_sfx_moss.find_event („anfang“/„haupt“); Wecker: eigener
  Schnitt, nur Anfang und Ende (siehe wecker_schnitt), nie zusammengesetzt. Katzen-Leitplanke wie make_sfx_moss --spiel:
  Tiefpass vor- und rückwärts (Butterworth 4. Ordnung, 48 dB/Oktave) mit der höchsten Grenzfrequenz zwischen 6 und
  3,5 kHz, bei der über 6 kHz höchstens −30 dB Energieanteil bleiben. Weiches Ein-/Ausblenden (Kosinus, je Ton),
  Lautheit (höchste Momentan-Lautheit, 400 ms) je Ton, Begrenzer, echte Spitze ≤ −1 dBTP, Ogg Vorbis q6 mono 48 kHz.
  Handy-Simulation wie make_schnurren.handy_modell (auf gleiche Lautheit gehoben).

Prüfung ohne Ohren: AudioSet-Klassifikator (MIT/ast-finetuned-audioset-10-10-0.4593, CPU, analyse-Umgebung) auf
erwartete Klassen, Sprache und Katzenlaute; Pulsfolge 15–50 Hz (Schnurr-Bereich, wie tools/hoerseite_sfx_ki.py);
schmale Linien 2–6 kHz (Piepen). Je Ton bleiben die besten BEHALTEN Kandidaten; Reihenfolge = Empfehlung.

Rohdaten (außerhalb des Repos): E:\\Draw2Race-AudioLab\\ostereier_roh (<id>.wav/.json, tmp/, kandidaten.json, ast.json)
Ergebnis: audio/entwurf/ostereier/ (<ton>_NN.ogg, <ton>_NN_handy.ogg, messwerte.json, hoeren.html)
"""
import argparse
import html
import json
import os
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("TORCHDYNAMO_DISABLE", "1")
import make_sfx_moss as m      # noqa: E402
import make_schnurren as s     # noqa: E402

FS = m.FS
ROH = r"E:\Draw2Race-AudioLab\ostereier_roh"
TMP = os.path.join(ROH, "tmp")
KAND_JSON = os.path.join(ROH, "kandidaten.json")
AST_JSON = os.path.join(ROH, "ast.json")
OUT = os.path.join(m.ROOT, "audio", "entwurf", "ostereier")
ANALYSE_PY = r"E:\Draw2Race-AudioLab\analyse\.venv\Scripts\python.exe"
AST_MODEL = "MIT/ast-finetuned-audioset-10-10-0.4593"
LEITPLANKE_DB = -30.0
NO_WORDS = "no words"
# Wecker: lauteste Ticks (50-ms-Pegel) gegenüber dem Klingeln. Leiser als TICK_MIN_DB -> auf TICK_ZIEL_DB anheben.
TICK_MIN_DB, TICK_ZIEL_DB, TICK_MAX_DB = -20.0, -16.0, 30.0
# Sparmodus der Erzeugung (siehe Kopf): darunter freier GPU-Speicher -> Modell im Arbeitsspeicher, Teile nach Bedarf
SPARSAM_AB_GIB, SPARSAM_RESERVE_GIB = 16.0, 0.8

# ---------------------------------------------------------------------------------------------------------------
# Töne. Pegel (höchste Momentan-Lautheit der Datei): Bezug sind die Spieltöne (audio/sfx_README.md): dran −17,5,
# sieg −16,5, Jubel −18,1/−18,6, flip −20,5, mischen −22,5, karte −25,2, Schnurren −20 LUFS; Mau −11,4 LUFS.
# Wecker so laut wie „Du bist dran“ (soll wecken), Stimmen und Klatschen wie der Jubel, Papier wie Flip/Mischen.
# erwartet: AudioSet-Klassen, die der Ton treffen soll. stimme: menschliche Laute (Sprache-Verdacht milder gewertet).
# ---------------------------------------------------------------------------------------------------------------
TOENE = {
    "gaehnen": {
        "titel": "Gähnen", "zweck": "an einen langsamen Spieler senden", "ziel_text": "2,5–3,5 s",
        "sekunden": 3.0, "ziel": (2.5, 3.6), "modus": "anfang", "vorlauf": 0.6, "einblenden": 0.04, "ausblenden": 0.35,
        "lufs": -19.0, "begrenzer": 3.0, "hochpass": 90.0, "stimme": True, "behalten": 6,
        "erwartet": ["Sigh", "Groan", "Breathing", "Wail, moan", "Gasp", "Pant"],
        "seeds": [3101, 3102, 3103],
        "prompts": [
            ("herzhaft", "a man gives a long, hearty, exaggerated yawn, deep breath in, then a drawn-out funny yawning groan that ends in a relaxed sigh, close-up, quiet room, " + NO_WORDS,
             "Mann, lang und übertrieben, endet mit einem Seufzer", [3101, 3102, 3103, 3104, 3105, 3106]),
            ("muede", "a very tired person yawning loudly and widely, one long stretching yawn with a low voice, close microphone, dry room, no speech",
             "sehr müde, breit, tiefe Stimme"),
            ("komisch", "a comical big yawn from an adult man, the yawn sound rises and then falls, ending with a satisfied smack of the lips, close-up, no talking",
             "komisch, steigt und fällt, Schmatzen am Ende"),
        ],
    },
    # Runde 2 (13.10.2026). Nutzerbefund zu Runde 1: klingt „als ob jemand am Klo abdrückt oder beim Sex kommt“ (tiefes,
    # gepresstes Stöhnen/Ächzen; AudioSet „Groan“ 0,4–0,65). Die Prompts der Runde 1 verlangten selbst ein „yawning groan“
    # bzw. eine „low voice“. Jetzt: luftiges Einatmen mit offenem Mund, kurzes entspanntes Ausatmen, kein Pressen.
    # Negativbegriffe auf zwei Wegen (A/B mit gleichen Seeds): als CFG-Negativ-Prompt („negativ“, ersetzt in der
    # Pipeline den leeren Gegen-Prompt) und, nur bei den Zwillingen „…_im_prompt“, als „no groaning …“ im Prompt
    # (Stil von make_sfx_moss.py, dort ohne Negativ-Prompt). Auswahl: AudioSet „meiden“ (Stöhnen, Ächzen, Grunzen,
    # Schreien …) schließt aus; Atemklassen (erwartet) zählen mit ihrer Summe; Tonhöhe/Stimmanteil (pyin) als Hinweis.
    "gaehnen2": {
        "titel": "Gähnen, Runde 2", "zweck": "an einen langsamen Spieler senden",
        "ziel_text": "2–3 s: tiefes, luftiges Einatmen mit offenem Mund („haaah“, Tonhöhe steigt und fällt), kurzes entspanntes Ausatmen, evtl. kleines „mm“",
        "hinweis": "Neu nach dem Befund zu Runde 1 (klang nach Stöhnen und Ächzen): Prompts ohne Stöhnen und tiefe Stimme, "
                   "Stöhnen/Ächzen/Grunzen/Schreien zusätzlich als Negativ-Prompt; ausgeschlossen wurde, was AudioSet deutlich als "
                   "„Groan“, „Grunt“, „Wail, moan“, Schreien, Sprechen oder Katze hört. Die Notizen zu Stimmlage, Tonhöhenverlauf "
                   "und Ende stammen aus einer Tonhöhenmessung, nicht vom Hören.",
        "sekunden": 3.0, "ziel": (2.0, 3.3), "modus": "anfang", "vorlauf": 0.6, "einblenden": 0.04, "ausblenden": 0.3,
        "lufs": -19.0, "begrenzer": 3.0, "hochpass": 90.0, "stimme": True, "behalten": 8,
        "erwartet": ["Breathing", "Sigh", "Gasp", "Pant"], "atem_summe": True, "tonhoehe": True, "dubletten_alle": True,
        # AudioSet-Klasse: Grenze für den Ausschluss (ab der Hälfte ein Hinweis); gewichtet als Abzug in den Punkten
        # Groan/Moan streng (0,15), weil genau das in Runde 1 störte
        "meiden": {"Groan": 0.15, "Grunt": 0.15, "Wail, moan": 0.15, "Whimper": 0.25, "Screaming": 0.15, "Yell": 0.15,
                   "Shout": 0.15, "Bellow": 0.15, "Roar": 0.15, "Growling": 0.15, "Burping, eructation": 0.1, "Fart": 0.1,
                   "Snoring": 0.3, "Singing": 0.2, "Music": 0.25, "Babbling": 0.25,
                   # nach der ersten Sichtung: „comic“ ergab Pfeife/Theremin/Trompete, „morgen“ teils Hund/Heulen/Summen
                   "Whistle": 0.2, "Whistling": 0.2, "Musical instrument": 0.2, "Theremin": 0.2, "Animal": 0.2,
                   "Dog": 0.15, "Howl": 0.15, "Whale vocalization": 0.2, "Humming": 0.4},
        "atem_mindestens": 0.15,          # Summe der Atemklassen: darunter hört AudioSet kein Atmen/Seufzen -> Ausschluss
        "je_variante_max": 3,             # Vielfalt in der Auswahl (siehe seite)
        "sprache_grenze": (0.3, 0.15),
        "negativ": "groaning, moaning, grunting, straining, pushing, effort, deep pressed male voice, growling, roaring, "
                   "screaming, speech, words, singing, music, cat, meow",
        "seeds": [4101, 4102, 4103, 4104, 4105, 4106],
        "prompts": [
            ("frau", "a young woman yawns lightly, a long airy open-mouthed breath in, a soft breathy haaah that rises and then falls in pitch, then a short relaxed breath out, effortless and gentle, close-up, quiet room, " + NO_WORDS,
             "Frau, leicht und luftig", list(range(4101, 4119))),
            ("morgen", "a sleepy person yawning in the morning while stretching, a big wide-open airy yawn, breathy haaaah rising and falling, then a short relaxed exhale and a small content mm, close-up, bedroom, " + NO_WORDS,
             "verschlafen am Morgen mit Strecken, kleines „mm“"),
            ("comic", "cartoon yawn sound effect, a funny exaggerated airy yawn, a breathy haaaa-aah that swoops up and down in pitch, light and playful, ending with a quick satisfied mm, animated cartoon, " + NO_WORDS,
             "Zeichentrick, verspielt, „mm“ am Ende"),
            ("hoeflich", "a short polite yawn behind a hand, a quiet airy breath in with the mouth wide open, slightly muffled by the hand, then a soft relaxed breath out, close-up, quiet room, " + NO_WORDS,
             "kurz und höflich hinter vorgehaltener Hand"),
            ("kind", "a tired child yawning, a long airy breathy yawn with a gentle haaah rising and falling in pitch, followed by a small sleepy sigh, close-up, quiet room, " + NO_WORDS,
             "müdes Kind, endet mit kleinem Seufzer"),
        ],
    },
    "schnarchen": {
        "titel": "Schnarchen", "zweck": "an einen langsamen Spieler senden", "ziel_text": "4–5 s, 2–3 Atemzüge",
        "sekunden": 4.5, "ziel": (4.0, 5.2), "modus": "anfang", "vorlauf": 0.5, "einblenden": 0.05, "ausblenden": 0.4,
        "lufs": -19.0, "begrenzer": 3.0, "hochpass": 70.0, "stimme": True, "behalten": 6,
        "erwartet": ["Snoring", "Snort"],
        "seeds": [3201, 3202, 3203],
        "prompts": [
            ("tief", "a man snoring loudly, three slow deep snores, each a long rattling inhale followed by a soft puffing exhale, close-up, quiet bedroom, " + NO_WORDS,
             "drei tiefe Schnarcher, Ausatmen als Pusten"),
            ("komisch", "comedic cartoon snoring, a sleeping man snores with a loud rumbling inhale and a funny lip-flapping exhale, two or three breaths, close microphone",
             "komisch, Lippenflattern beim Ausatmen"),
            ("ruhig", "a person sleeping and snoring steadily, a heavy snore on each breath in and a soft sigh out, indoor, close-up, no talking",
             "gleichmäßig, Schnarcher beim Einatmen, sanft aus"),
        ],
    },
    "wecker": {
        "titel": "Wecker", "zweck": "an einen langsamen Spieler senden", "ziel_text": "~3 s Ticken, dann 1,5–2 s Klingeln, in einem Stück",
        "sekunden": 5.0, "ziel": (4.3, 5.8), "modus": "wecker", "vorlauf": 0.03, "einblenden": 0.01, "ausblenden": 0.12,
        "lufs": -17.5, "begrenzer": 4.0, "hochpass": 60.0, "stimme": False, "behalten": 6, "glocke": True,
        "erwartet": ["Alarm clock", "Tick-tock", "Tick", "Clock"],
        "erwartet_ticken": ["Tick-tock", "Tick", "Clock"],
        "erwartet_klingeln": ["Alarm clock", "Bell", "Telephone bell ringing", "Alarm", "Bicycle bell"],
        "seeds": [3301, 3302, 3303, 3304],
        "prompts": [
            ("ticken_dann", "an old mechanical wind-up alarm clock ticking steadily for three seconds, then its bell suddenly rings loudly and shrilly for two seconds, close-up, indoor",
             "alter Aufziehwecker: 3 s Ticken, dann 2 s schrilles Klingeln", [3301, 3302, 3303, 3304, 3305, 3306]),
            ("zwei_glocken", "a vintage twin-bell alarm clock, loud regular tick tock for about three seconds, then a sudden loud metallic ringing of the bells for two seconds, close-up, quiet bedroom",
             "Wecker mit zwei Glocken, lautes Tick-Tack, dann metallisches Klingeln"),
            ("tick_tack", "clock ticking, tick tock tick tock tick tock, then a mechanical alarm clock goes off with rapid loud bell ringing, close-up, dry room",
             "Tick-Tack, dann schnelles lautes Klingeln", [3301, 3302, 3303, 3304, 3305, 3306, 3307, 3308]),
            # nach der ersten Sichtung (13.10.2026): „zwei_glocken“ ergab viermal nur Klingeln, „tick_tack“ viermal Ticken + Klingeln
            ("leise_tick", "a mechanical alarm clock softly ticking, tick tock tick tock, for three seconds in a quiet bedroom, then suddenly its loud bell rings rapidly for two seconds, close-up",
             "leises Tick-Tack im stillen Zimmer, dann plötzlich lautes Klingeln", [3311, 3312, 3313, 3314]),
        ],
    },
    "klingeln": {
        "titel": "Nur Klingeln (Ausweichlösung)", "zweck": "falls das Ticken nicht taugt: Ticken in der Animation, nur der Klingelton", "ziel_text": "~1,5 s",
        "sekunden": 1.5, "ziel": (1.2, 1.8), "modus": "anfang", "vorlauf": 0.05, "einblenden": 0.005, "ausblenden": 0.3,
        "lufs": -17.5, "begrenzer": 4.0, "hochpass": 60.0, "stimme": False, "behalten": 3, "glocke": True,
        "erwartet": ["Alarm clock", "Bell", "Telephone bell ringing", "Alarm", "Bicycle bell"],
        "seeds": [3351, 3352, 3353],
        "prompts": [
            ("hammer", "a mechanical alarm clock bell ringing loudly, rapid metal hammer striking the bells, close-up, short",
             "Klöppel schlägt schnell auf die Glocken"),
            ("schrill", "old twin-bell alarm clock ringing, shrill continuous metallic ringing, indoor, close-up",
             "alter Wecker, schrill und durchgehend"),
        ],
    },
    "papierkugel_wurf": {
        "titel": "Papierkugel: Knüllen und Wurf", "zweck": "Papierkugel an einen Mitspieler werfen", "ziel_text": "~1 s",
        "sekunden": 1.0, "ziel": (0.6, 1.3), "modus": "anfang", "vorlauf": 0.08, "einblenden": 0.005, "ausblenden": 0.12,
        "lufs": -21.0, "begrenzer": 6.0, "hochpass": 60.0, "stimme": False, "behalten": 6,
        "erwartet": ["Crumpling, crinkling", "Whoosh, swoosh, swish", "Crackle", "Rustle", "Whip", "Crushing"],
        "seeds": [3401, 3402, 3403],
        "prompts": [
            ("knuellen_wusch", "a sheet of paper quickly crumpled into a ball by hand, then a short soft whoosh as it is thrown, close-up, dry room",
             "Blatt zusammenknüllen, dann kurzes weiches Wusch"),
            ("knistern", "crumpling paper into a ball, crinkling and crackling paper, followed by a quick swish of a throw through the air, close-up",
             "knisterndes Knüllen, dann schneller Wurf"),
            ("schnell", "hands quickly scrunching a piece of paper into a tight ball, short crinkly crumple, then a fast airy swoosh, indoor",
             "schnell und kurz geknüllt, luftiges Wusch"),
        ],
    },
    "papierkugel_plopp": {
        "titel": "Papierkugel: Treffer (Plopp)", "zweck": "die Kugel kommt beim Mitspieler an", "ziel_text": "0,3–0,5 s",
        "sekunden": 1.0, "ziel": (0.2, 0.5), "modus": "haupt", "vorlauf": 0.03, "einblenden": 0.003, "ausblenden": 0.08,
        "lufs": -21.5, "begrenzer": 6.0, "hochpass": 60.0, "stimme": False, "behalten": 6,
        "erwartet": ["Plop", "Thump, thud", "Crumpling, crinkling", "Tap", "Knock", "Crackle", "Whack, thwack", "Slap, smack"],
        "seeds": [3501, 3502, 3503],
        "prompts": [
            ("tisch", "a light crumpled paper ball lands softly on a table, one soft papery plop, close-up, quiet room",
             "leichte Kugel landet weich auf dem Tisch"),
            ("dumpf", "a small ball of paper hits a wooden desk, soft dull tap with a tiny crinkle, single hit, close-up",
             "dumpfer Tipp auf Holz mit kleinem Knistern"),
            ("kopf", "a crumpled paper ball bounces off a person's head, one soft light papery bonk, single short hit, comedic",
             "prallt vom Kopf ab, weiches „Bonk“"),
            # nach der ersten Sichtung (13.10.2026): AudioSet hörte bei „tisch“/„kopf“ eher einen Knall
            ("kissen", "a crumpled paper ball softly lands on a cushion, a gentle muffled papery plop, very short, close-up, quiet room",
             "landet auf einem Kissen, gedämpftes Plopp", [3504, 3505, 3506]),
        ],
    },
    "lachen": {
        "titel": "Lachen (Reaktion 😂)", "zweck": "Reaktion", "ziel_text": "~1,5 s",
        "sekunden": 1.5, "ziel": (1.1, 1.9), "modus": "anfang", "vorlauf": 0.3, "einblenden": 0.03, "ausblenden": 0.3,
        "lufs": -19.0, "begrenzer": 3.0, "hochpass": 90.0, "stimme": True, "behalten": 6,
        "erwartet": ["Laughter", "Giggle", "Snicker", "Chuckle, chortle", "Belly laugh"],
        "seeds": [3601, 3602, 3603],
        "prompts": [
            ("kichern", "a person giggling contagiously, a short burst of happy giggles, " + NO_WORDS + ", close-up, indoor",
             "ansteckendes Kichern"),
            ("herzlich", "a man chuckling and laughing heartily for a moment, warm amused laughter, no speech, close microphone",
             "Mann, herzlich und warm"),
            ("zu_zweit", "two friends bursting into short infectious laughter together, joyful giggling, " + NO_WORDS + ", dry room",
             "zwei Leute prusten los"),
        ],
    },
    "schreck": {
        "titel": "Schreck (Reaktion 😱)", "zweck": "Reaktion", "ziel_text": "~0,8 s",
        "sekunden": 1.0, "ziel": (0.5, 1.0), "modus": "anfang", "vorlauf": 0.25, "einblenden": 0.02, "ausblenden": 0.15,
        "lufs": -19.0, "begrenzer": 3.0, "hochpass": 90.0, "stimme": True, "behalten": 6,
        "erwartet": ["Gasp", "Breathing", "Sigh", "Pant"],
        "seeds": [3701, 3702, 3703],
        "prompts": [
            ("oh", "a person gasps in surprise, a short sharp startled intake of breath with a tiny voiced oh, close-up, " + NO_WORDS,
             "scharfes Luftschnappen mit kleinem „Oh“", [3701, 3702, 3703, 3704, 3705]),
            ("frau", "a woman gasps in shock, a single quick surprised gasp, close microphone, dry room, no speech",
             "Frau, ein kurzes erschrockenes Luftschnappen"),
            ("mann", "a man gasps, startled and surprised, one short breathy gasp, indoor, close-up, no talking",
             "Mann, kurz und gehaucht"),
        ],
    },
    "klatschen": {
        "titel": "Klatschen (Reaktion 👏)", "zweck": "Reaktion", "ziel_text": "~1,5 s, wenige Hände",
        "sekunden": 1.5, "ziel": (1.1, 1.9), "modus": "anfang", "vorlauf": 0.05, "einblenden": 0.005, "ausblenden": 0.35,
        "lufs": -19.0, "begrenzer": 4.0, "hochpass": 60.0, "stimme": False, "behalten": 6,
        "erwartet": ["Applause", "Clapping"],
        "seeds": [3801, 3802, 3803],
        "prompts": [
            ("wenige", "a few people clapping their hands briefly, short friendly applause from three or four people, small room, close-up, no cheering",
             "drei, vier Leute klatschen kurz"),
            ("kurz", "a short burst of applause from a small group that stops quickly, indoor, no voices",
             "kleine Gruppe, hört schnell auf"),
            ("begeistert", "two or three people clapping hands enthusiastically for a moment, short lively applause, dry room, no voices",
             "zwei, drei Leute, begeistert"),
        ],
    },
    "daumen": {
        "titel": "Daumen hoch (Reaktion 👍)", "zweck": "Reaktion", "ziel_text": "~0,4 s",
        "sekunden": 1.0, "ziel": (0.25, 0.6), "modus": "anfang", "vorlauf": 0.02, "einblenden": 0.003, "ausblenden": 0.2,
        "lufs": -19.0, "begrenzer": 4.0, "hochpass": 60.0, "stimme": False, "behalten": 6,
        "erwartet": ["Ding", "Plop", "Boing", "Marimba, xylophone", "Chime", "Glockenspiel", "Burst, pop",
                     "Jingle, tinkle", "Bell", "Mallet percussion", "Ringtone", "Clang", "Ping"],
        "seeds": [3901, 3902, 3903],
        "prompts": [
            ("pling", "a single soft friendly pling notification, warm round mallet note, very short, user interface confirmation",
             "weiches „Pling“, runder Schlägelton"),
            ("plopp", "a short cheerful cartoon pop with a soft ringing ping, positive confirmation sound, very short",
             "fröhliches Plopp mit kleinem Nachklang"),
            ("marimba", "one soft marimba note, short and round, gentle positive notification, warm",
             "ein weicher Marimba-Ton"),
        ],
    },
}
# Gähnen Runde 2, A/B: Zwillinge mit den Negativbegriffen im Prompt und ohne Negativ-Prompt (5. Feld ""), gleiche Seeds
# wie die ersten beiden der Hauptvariante. Prompt-Eintrag: (Name, Prompt, Notiz[, Seeds[, Negativ-Prompt]]).
IM_PROMPT = "no groaning, no moaning, no grunting, no straining"
for _p in list(TOENE["gaehnen2"]["prompts"]):
    assert _p[1].endswith(NO_WORDS)
    TOENE["gaehnen2"]["prompts"].append((_p[0] + "_im_prompt", _p[1][:-len(NO_WORDS)] + IM_PROMPT + ", " + NO_WORDS,
                                         _p[2] + "; Negativbegriffe im Prompt statt Negativ-Prompt", [4101, 4102], ""))
# Nach der ersten Sichtung (13.10.2026): „comic“ ergab sechsmal Pfeife/Theremin/Trompete statt Stimme, „morgen“ und „kind“
# teils Hund/Heulen oder nur Summen. Varianten mit „human voice“ und erweitertem Negativ-Prompt; „frau“ (zuverlässig) mit
# 12 weiteren Seeds, „morgen2“ mit 8. Die Zwillinge „…_im_prompt“ lagen deutlich schlechter (Groan im Median 0,10 gegen 0,01 mit
# Negativ-Prompt): Begriffe wie „groaning“ im Prompt ziehen das Modell eher hin; daher keine weiteren Zwillinge.
# „comic2“ ergab trotzdem Schreien/Jammern; nicht weiter verfolgt.
NEG_PLUS = (TOENE["gaehnen2"]["negativ"] + ", whistle, slide whistle, theremin, trumpet, musical instrument, animal, dog, "
            "dog yawn, howl")
TOENE["gaehnen2"]["prompts"] += [
    ("comic2", "a person does a big funny exaggerated cartoon-style yawn with their own voice, a long breathy open-mouthed haaaah sliding up and then down in pitch, then a relaxed breath out and a tiny satisfied mm, human voice only, close-up, quiet room, " + NO_WORDS,
     "Zeichentrick-Gähnen mit menschlicher Stimme, „mm“ am Ende", [4111, 4112, 4113, 4114, 4115, 4116], NEG_PLUS),
    ("morgen2", "a sleepy young woman yawning widely in the morning, a long airy human yawn, breathy haaaah rising and then falling in pitch, then a short relaxed exhale with a soft content mm, close-up, bedroom, " + NO_WORDS,
     "Frau, verschlafen am Morgen, weit offen, kleines „mm“", list(range(4111, 4119)), NEG_PLUS),
    ("jugend", "a tired teenager yawning lazily, a long airy open-mouthed human yawn, breathy haaah rising and then falling in pitch, then a relaxed breath out, effortless, close-up, quiet room, " + NO_WORDS,
     "müder Jugendlicher, lässig", [4121, 4122, 4123, 4124, 4125, 4126], NEG_PLUS),
    # dritte Sichtung: „hoeflich“ war oft sehr leise mit Rauschteppich; neu als Frau im Aufbau von „frau“ (zuverlässig)
    ("hoeflich2", "a young woman gives a short polite yawn behind her hand, a soft airy open-mouthed breath in, a gentle breathy haaah rising and then falling in pitch, then a quick relaxed breath out, close-up, quiet room, " + NO_WORDS,
     "Frau, höflich hinter der Hand, sanft", [4131, 4132, 4133, 4134, 4135, 4136], NEG_PLUS),
]
# Gähnen Runde 3 (13.10.2026). Nutzerbefund zu Runde 2: Bei allen Kandidaten kommt zuerst das „Gähnen“ (stimmhaft) und
# danach das Luftholen; gaehnen2_02 (Frau, halb gehaucht, halb Stimme, fallend, luftiges Ende) war „schon ganz gut“.
# Richtig: erst tief Luft holen (Einatmen durch den offenen Mund), dann ein langes stimmhaftes „aAaaaaahhh“ beim Ausatmen,
# fallend, gehaucht ausklingend. Die Prompts der Runde 2 endeten selbst mit „then a short relaxed breath out“; jetzt
# steht die Reihenfolge ausdrücklich im Prompt (first … then …), ohne Atemzug danach. Angelehnt an „frau“ mit Seed 4110
# (gaehnen2_02), Negativ-Prompt wie dort; dazu zwei hellere, jugendliche Stimmen (Negativ-Prompt wie „jugend“).
# Auswahl nur mit bestandener Reihenfolge-Prüfung (reihenfolge_messen; „nur_ok“: kein Auffüllen mit Ausgeschlossenen).
# Eigener Schnitt („einatmen“, gaehnen_schnitt), weil find_event den leiseren Atem vorn abschnitte.
G3_SEEDS = [4110] + list(range(5101, 5112))
TOENE["gaehnen3"] = {
    "titel": "Gähnen, Runde 3", "zweck": "an einen langsamen Spieler senden",
    "ziel_text": "3–4 s: erst tief Luft holen (Einatmen durch den offenen Mund, gehaucht), dann ein langes stimmhaftes "
                 "„aAaaaahhh“ beim Ausatmen, Tonhöhe fällt, klingt gehaucht aus",
    "hinweis": "Neu nach dem Befund zu Runde 2 (erst das Gähnen, danach das Luftholen; gaehnen2_02 „schon ganz gut“): Die "
               "Reihenfolge steht ausdrücklich im Prompt, angelehnt an den Prompt und Seed von gaehnen2_02, Negativ-Prompt "
               "gegen Stöhnen und Ächzen wie in Runde 2. Behalten wurde nur, was die Reihenfolge-Prüfung besteht (Messung "
               "von Pegel, Stimmhaftigkeit und Tonhöhe, kein Hören): vorn etwa 0,5 s (ab 0,45 s) hörbarer, gehauchter Atem, "
               "danach der stimmhafte Teil (seine Mitte hinter der Mitte des Tons) mit fallender Tonhöhe, gehauchtes Ende "
               "ohne neuen Atemzug, höchstens 0,8 s Stille zwischen Atem und „aaah“. Dazu die Ausschlüsse aus Runde 2 "
               "(Stöhnen, Ächzen, Sprache, Katze). Das Modell setzt die Stimme meist an den Anfang oder haucht nur: von 297 "
               "erzeugten Kandidaten bestanden 6 (alle mit Frauenstimme; die Varianten mit Mädchen-/Jungenstimme ergaben "
               "meist nur Hauchen). Das „aaah“ ist bei den meisten kürzer als gewünscht (0,5–0,8 s), das Einatmen dafür lang. "
               "gaehnen3_02umgestellt ist gaehnen2_02 mit getauschten Teilen (zusammengesetzt, außerhalb der Rangfolge).",
    "sekunden": 3.5, "ziel": (2.6, 4.3), "modus": "einatmen", "vorlauf": 0.04, "einblenden": 0.04, "ausblenden": 0.3,
    "lufs": -19.0, "begrenzer": 3.0, "hochpass": 90.0, "stimme": True, "behalten": 8, "nur_ok": True,
    "erwartet": ["Breathing", "Sigh", "Gasp", "Pant"], "atem_summe": True, "tonhoehe": True, "dubletten_alle": True,
    "reihenfolge": True,
    "meiden": dict(TOENE["gaehnen2"]["meiden"]), "atem_mindestens": 0.15, "je_variante_max": 3, "sprache_grenze": (0.3, 0.15),
    "negativ": TOENE["gaehnen2"]["negativ"],
    "seeds": G3_SEEDS[:4],
    "prompts": [
        ("frau_zuerst", "a young woman yawns lightly: first a long, deep, airy breath in through her wide-open mouth, then a long, soft, voiced aaaah while she breathes out, slowly falling in pitch, ending in a soft breathy sigh, effortless and gentle, close-up, quiet room, " + NO_WORDS,
         "Frau wie gaehnen2_02, Reihenfolge ausdrücklich: erst Einatmen, dann „aaah“", G3_SEEDS + list(range(5112, 5136))),
        ("frau_reihe", "a young woman yawning, in this order: first a long deep inhale through the open mouth, then a long voiced descending aaaah while exhaling, ending in a soft breathy sigh, close-up, quiet room, " + NO_WORDS,
         "Frau, „in this order: first … then …“", G3_SEEDS[:4]),
        ("frau_zwei_teile", "a woman's yawn in two parts: first she slowly breathes in deeply through her wide-open mouth for about one second, an audible airy inhale, then she lets it out with a long relaxed voiced aaaah sliding down in pitch that fades into a breathy whisper, close-up, quiet room, " + NO_WORDS,
         "Frau, Gähnen in zwei Teilen (1 s Einatmen, dann „aaah“)", G3_SEEDS[:8]),
        ("frau_beginnt", "a long yawn from a young woman that begins with a deep, airy, audible inhale and ends with a long, soft, voiced aaaah on the exhale, falling in pitch and trailing off into a gentle breathy sigh, close-up, quiet room, " + NO_WORDS,
         "Frau, „beginnt mit … endet mit …“", G3_SEEDS[:4]),
        # erste Sichtung (22 Kandidaten): „beginnt“ und „reihe“ ergaben fast nur ein „aaah“ ohne Atem davor (teils Summen,
        # Hund/Heulen); „zuerst“, „zwei_teile“ und „maedchen_hell“ je 1–2-mal Atem vor dem „aaah“. Diese mit mehr Seeds,
        # dazu zwei Formulierungen, die mit dem Einatmen als Hauptverb beginnen („takes a breath … and directly after“).
        ("frau_atem_zuerst", "a young woman takes a slow, deep, audible breath in through her wide-open mouth, and directly after it she lets out a long, soft, voiced yawning aaaah that falls in pitch and fades into a breathy sigh, close-up, quiet room, " + NO_WORDS,
         "Frau, Einatmen als Hauptverb, „direkt danach“ das „aaah“", G3_SEEDS),
        ("frau_luft_holen", "a young woman yawning: she first sucks in a long deep breath of air with her mouth wide open, and then, without a pause, breathes out with a long voiced descending aaaah, ending in a soft breathy sigh, close-up, quiet room, " + NO_WORDS,
         "Frau, „saugt erst Luft ein, dann ohne Pause aaah“", G3_SEEDS),
        # zweite Sichtung (66 Kandidaten, kein einziger bestanden): Atem vorn nur in 9 von 66; sonst „aaah“ zuerst (34) oder
        # nur Atem ohne Stimme (26); das „aaah“ endete meist mit Stimme statt gehaucht. Neu im Stil der Trainings-
        # beschreibungen (AudioCaps: „X followed by Y“), kurz, ohne eigenen Atemzug am Ende (Runde 2: „then a short relaxed
        # breath out“ ergab den Atem hinten); das Ende als „wird hauchig und verklingt“.
        ("frau_followed", "a woman inhales deeply through her open mouth, followed by a long voiced yawning aaaah that falls in pitch and gets softer and breathier until it fades out, close-up, quiet room, " + NO_WORDS,
         "Frau, „inhales …, followed by …“, Ende wird hauchig", list(range(5101, 5117))),
        ("atemzug_followed", "a long airy gasp of breath in, followed by a young woman's long voiced descending yawn aaaah that turns breathy at the end, close-up, quiet room, " + NO_WORDS,
         "Frau, „gasp of breath in, followed by …“", G3_SEEDS[1:7]),
        ("maedchen_followed", "a teenage girl breathes in deeply through her open mouth, followed by a long voiced yawning aaaah in a bright young voice, falling in pitch and turning breathy at the end, close-up, quiet room, " + NO_WORDS,
         "jugendlich hell (Mädchen), „followed by …“", G3_SEEDS[1:7], NEG_PLUS),
        # dritte Sichtung (18): „frau_followed“ am besten (3 von 6: Atem 0,3–0,45 s, dann „aaah“, hauchiges Ende),
        # „maedchen_followed“ sechsmal nur Hauchen ohne Stimme, „atemzug_followed“ meist Stimme zuerst. Daher „frau_followed“
        # mit 10 weiteren Seeds, dazu mit längerem, langsamem Einatmen und mit hellen Stimmen im selben Aufbau.
        ("frau_followed_lang", "a woman slowly inhales a long deep breath through her wide-open mouth, followed by a long voiced yawning aaaah that falls in pitch and gets softer and breathier until it fades out, close-up, quiet room, " + NO_WORDS,
         "Frau, langsames langes Einatmen, „followed by …“", G3_SEEDS),
        ("hell_followed", "a young woman with a bright, high, girlish voice inhales deeply through her open mouth, followed by a long voiced yawning aaaah that falls in pitch and gets softer and breathier until it fades out, close-up, quiet room, " + NO_WORDS,
         "junge Frau, helle Mädchenstimme, „followed by …“", list(range(5101, 5111))),
        ("junge_followed", "a teenage boy with a light young voice inhales deeply through his open mouth, followed by a long voiced yawning aaaah that falls in pitch and gets softer and breathier until it fades out, close-up, quiet room, " + NO_WORDS,
         "jugendlich hell (Junge), „followed by …“", list(range(5101, 5109)), NEG_PLUS),
        # vierte Sichtung (124): Atem vorn nur in 14, bestanden 1 (frau_followed_lang_5101). Versuch mit stärkerer
        # Prompt-Führung (CFG 7 statt 4) und längerer Daueransage (5 s statt 3,5 s), gleiche Prompts und Seeds.
        ("frau_zuerst_cfg7", "a young woman yawns lightly: first a long, deep, airy breath in through her wide-open mouth, then a long, soft, voiced aaaah while she breathes out, slowly falling in pitch, ending in a soft breathy sigh, effortless and gentle, close-up, quiet room, " + NO_WORDS,
         "wie „frau_zuerst“, CFG 7", list(range(5101, 5117)), None, {"cfg": 7.0}),
        ("frau_followed_lang_cfg7", "a woman slowly inhales a long deep breath through her wide-open mouth, followed by a long voiced yawning aaaah that falls in pitch and gets softer and breathier until it fades out, close-up, quiet room, " + NO_WORDS,
         "wie „frau_followed_lang“, CFG 7", list(range(5101, 5137)), None, {"cfg": 7.0}),
        ("frau_zuerst_5s", "a young woman yawns lightly: first a long, deep, airy breath in through her wide-open mouth, then a long, soft, voiced aaaah while she breathes out, slowly falling in pitch, ending in a soft breathy sigh, effortless and gentle, close-up, quiet room, " + NO_WORDS,
         "wie „frau_zuerst“, Daueransage 5 s", list(range(5101, 5107)), None, {"sekunden": 5.0}),
        # fünfte Sichtung (Rohdaten): CFG 7 ergab in 5 von 12 Atem → „aaah“ → hauchiges Ende (Atem oft nur 0,35–0,45 s),
        # 5 s Daueransage dagegen mehrere getrennte Laute. Weiter mit CFG 7, mehr Seeds, Einatmen „zwei Sekunden lang“
        # und zwei hellere Stimmen.
        ("frau_zwei_sek_cfg7", "a woman slowly breathes in through her wide-open mouth for two full seconds, a long audible airy inhale, followed by a long voiced yawning aaaah that falls in pitch and gets breathier until it fades out, close-up, quiet room, " + NO_WORDS,
         "Frau, Einatmen „zwei Sekunden lang“, CFG 7", G3_SEEDS, None, {"cfg": 7.0}),
        ("hell_followed_cfg7", "a young woman with a bright, high, girlish voice slowly inhales a long deep breath through her wide-open mouth, followed by a long voiced yawning aaaah that falls in pitch and gets softer and breathier until it fades out, close-up, quiet room, " + NO_WORDS,
         "junge Frau, helle Mädchenstimme, CFG 7", list(range(5101, 5109)), None, {"cfg": 7.0}),
        ("jugend_followed_cfg7", "a teenage girl with a bright young voice slowly inhales a long deep breath through her open mouth, followed by a long voiced yawning aaaah that falls in pitch and gets breathier until it fades out, close-up, quiet room, " + NO_WORDS,
         "jugendlich hell (Mädchen), CFG 7", list(range(5101, 5109)), NEG_PLUS, {"cfg": 7.0}),
        # sechste Sichtung (190): bestanden 2. Häufigster Fehler jetzt „nur Hauchen, keine Stimme“ (Wörter wie „airy“,
        # „breath“ ziehen zum Flüstern) und ein zu kurzer Atem vorn (0,3–0,4 s). Ein großer Seufzer hat dieselbe Form
        # wie das gewünschte Gähnen (tief einatmen, dann stimmhaftes, fallendes „aaah“) und beginnt von Natur aus mit dem
        # Einatmen; daher Prompts als müder, gähnender Seufzer, „with her voice“.
        # siebte Sichtung (214): Atem vorn am häufigsten bei „frau_zuerst“ (3/12), „junge_hell“ (2/6),
        # „frau_followed_lang_cfg7“ (3/16), „seufzer“ (1/6, bestanden); diese vier mit vielen weiteren Seeds.
        ("seufzer", "a tired young woman takes a long, deep, audible breath in through her open mouth and then lets it all out in a long sleepy aaaah with her voice, falling in pitch and ending breathy, like a big yawn, close-up, quiet room, " + NO_WORDS,
         "Frau, müder Seufzer wie ein großes Gähnen, „with her voice“", list(range(5101, 5127))),
        ("seufzer_cfg7", "a tired young woman takes a long, deep, audible breath in through her open mouth and then lets it all out in a long sleepy aaaah with her voice, falling in pitch and ending breathy, like a big yawn, close-up, quiet room, " + NO_WORDS,
         "wie „seufzer“, CFG 7", list(range(5101, 5107)), None, {"cfg": 7.0}),
        ("seufzer_laut_cfg7", "a woman inhales deeply and then exhales with a long, loud, voiced, sleepy sigh, aaaaah, falling in pitch, close-up, quiet room, " + NO_WORDS,
         "Frau, tief einatmen, dann lauter stimmhafter Seufzer, CFG 7", list(range(5101, 5107)), None, {"cfg": 7.0}),
        ("einatmen_seufzer_cfg7", "a deep inhaling gasp of air followed by a long voiced sleepy sigh from a woman, like a yawn, close-up, quiet room, " + NO_WORDS,
         "Frau, „inhaling gasp followed by voiced sigh“, CFG 7", list(range(5101, 5107)), None, {"cfg": 7.0}),
        ("maedchen_hell", "a teenage girl with a bright, light young voice yawns: first a long deep breath in through her open mouth, then a long voiced aaaah falling in pitch as she breathes out, ending in a soft breathy sigh, close-up, quiet room, " + NO_WORDS,
         "jugendlich hell (Mädchen)", G3_SEEDS[:8], NEG_PLUS),
        ("junge_hell", "a teenage boy with a light, clear young voice yawns: first a long deep breath in through his open mouth, then a long relaxed voiced aaaah falling in pitch as he breathes out, ending in a soft breathy sigh, close-up, quiet room, " + NO_WORDS,
         "jugendlich hell (Junge)", G3_SEEDS[:6] + list(range(5106, 5124)), NEG_PLUS),
    ],
}
# Furzkissen (15.10.2026, neues Easter Egg): ein Scherzkissen aus Gummi, das man einem Mitspieler unterschiebt.
# Klassisches komisches, gummiartiges „Pfrrrrt“, wenn die Luft aus dem Kissen gedrückt wird, eher lustig als eklig: keine
# echten Körpergeräusche, nichts Feuchtes, keine Stimmen, kein Lachen, keine Wörter. Vier Arten (Kategorie im 6. Feld,
# je mit eigener Zieldauer „ziel“ und Daueransage, das „Pfft“ mit eigenem Pegel): kurz und knackig, lang und flatternd,
# zum Schluss steigend (quietschig; „steigt_ht“: so viele Halbtöne muss die Tonhöhe zum Schluss messbar steigen),
# leiseres kleines „Pfft“. Unerwünschtes nur als CFG-Negativ-Prompt (Gähnen Runde 2: Begriffe wie „no …“ im Prompt
# ziehen das Modell eher hin). Pegel zwischen papierkugel_wurf (−21) und den Reaktionen (−19), das „Pfft“ 3 dB leiser.
FURZ_NEGATIV = ("speech, words, voice, talking, whispering, laughter, laughing, giggling, crowd, cheering, screaming, "
                "shouting, singing, music, wet, liquid, splash, squelch, squishy, mud, gurgling, dripping, toilet, "
                "realistic human body, burp, groan, grunt, cat, meow, purr, hiss, animal, bird, mouse")
FURZ_ARTEN = {"kurz": "kurz und knackig", "lang": "lang und flatternd", "quietschig": "zum Schluss steigend (quietschig)",
              "pfft": "leises kleines „Pfft“"}
F_KURZ = {"kategorie": "kurz", "ziel": (0.55, 0.95), "sekunden": 1.0}
F_LANG = {"kategorie": "lang", "ziel": (1.15, 1.85), "sekunden": 1.8, "ausblenden": 0.2}
F_QUIETSCH = {"kategorie": "quietschig", "ziel": (0.7, 2.2), "sekunden": 1.4, "steigt_ht": 3.0}   # bis 2,2 s: das Quietschen kommt am Ende
F_PFFT = {"kategorie": "pfft", "ziel": (0.2, 0.6), "sekunden": 0.6, "lufs": -23.0, "ausblenden": 0.08}
F_SEEDS = list(range(6101, 6107))
TOENE["furzkissen"] = {
    "titel": "Furzkissen", "zweck": "einem Mitspieler ein Furzkissen (Scherzkissen aus Gummi) unterschieben",
    "ziel_text": "komisches, gummiartiges „Pfrrrrt“, eher lustig als eklig: kurz und knackig 0,6–0,9 s, lang und "
                 "flatternd 1,2–1,8 s, zum Schluss steigend (quietschig), leiseres kleines „Pfft“ (−23 LUFS)",
    "hinweis": "Neues Easter Egg. Unerwünschtes (Stimmen, Lachen, Feuchtes, echte Körpergeräusche, Katze, Zischen) steht "
               "als Negativ-Prompt. Behalten wurde nur, was AudioSet als Furz oder Quietschen erkennt und nicht deutlich nach "
               "Sprache, Schreien, Lachen, Flüssigkeit, Rülpsen, Katze, Vogel, Maus, Insekt oder Tier klingt, die Zieldauer der Art einhält "
               "und (quietschige Art) zum Schluss messbar steigt; Dubletten über alle Paare aussortiert. Auswahl reihum "
               "über die vier Arten, Nummern nach Art geordnet. Die Beschreibungen (Stöße, Tonhöhe, Knattern, Klangfarbe) "
               "stammen aus Messungen, nicht vom Hören.",
    "sekunden": 1.0, "ziel": (0.55, 0.95), "modus": "anfang", "vorlauf": 0.03, "einblenden": 0.004, "ausblenden": 0.12,
    "lufs": -20.0, "begrenzer": 4.0, "hochpass": 60.0, "stimme": False, "behalten": 10,
    "erwartet": ["Fart", "Squeak", "Boing"], "erwartet_mindestens": 0.05,
    "furz": True, "ausgewogen": True, "nur_ok": True, "dubletten_alle": True, "streng": True, "puls_purr": True,
    "sprache_grenze": (0.25, 0.12),
    # Ausschluss ab der Grenze, Hinweis ab der Hälfte, Abzug in den Punkten (wie gaehnen2)
    "meiden": {"Laughter": 0.1, "Giggle": 0.1, "Snicker": 0.1, "Belly laugh": 0.1, "Chuckle, chortle": 0.1,
               "Baby laughter": 0.1, "Screaming": 0.1, "Shout": 0.1, "Yell": 0.1, "Children shouting": 0.1,
               "Babbling": 0.15, "Singing": 0.15, "Whispering": 0.15,
               "Liquid": 0.15, "Splash, splatter": 0.15, "Slosh": 0.15, "Drip": 0.15, "Gurgling": 0.15, "Pour": 0.15,
               "Trickle, dribble": 0.15, "Toilet flush": 0.1, "Squish": 0.3,
               "Burping, eructation": 0.25, "Groan": 0.15, "Grunt": 0.15, "Stomach rumble": 0.2,
               "Hiss": 0.25, "Mouse": 0.1, "Bird": 0.2, "Chirp, tweet": 0.2,
               # zweite Sichtung: teils Mücke/Fliege/Insekt (Beute für Katzen) oder Tier/Heulen
               "Mosquito": 0.15, "Fly, housefly": 0.15, "Insect": 0.15, "Bee, wasp, etc.": 0.15,
               "Animal": 0.15, "Domestic animals, pets": 0.15, "Dog": 0.15, "Howl": 0.15},
    # nur zur Beschreibung in ast.json
    "beobachten": ["Boing", "Vibration", "Buzz", "Rattle", "Trumpet", "Brass instrument", "Trombone", "Didgeridoo",
                   "Duck", "Quack", "Goose", "Honk", "Frog", "Croak", "Motorboat, speedboat", "Engine", "Sound effect",
                   "Whoosh, swoosh, swish", "Toot", "Vehicle horn, car horn, honking", "Rumble", "Harmonica", "Creak"],
    "negativ": FURZ_NEGATIV,
    "seeds": F_SEEDS,
    "prompts": [
        ("kurz", "a rubber whoopee cushion is sat on and lets out a short, punchy, comedic fart noise, a quick rubbery pfrrt of squeezed air, prank toy sound effect, close-up, dry room",
         "kurz und knackig: Kissen wird kurz plattgesessen", list(range(6101, 6113)), None, F_KURZ),
        ("kurz_platt", "someone sits down hard on a whoopee cushion, one quick loud raspy rubbery fart sound, short and snappy, cartoon prank, close-up",
         "kurz und knackig: hart draufgesetzt, rau", F_SEEDS, None, F_KURZ),
        ("lang", "a whoopee cushion slowly squeezed flat, a long drawn-out rubbery fart noise, fluttering and flapping pfrrrrrrt as the air squeezes out of the rubber, comedic prank sound effect, close-up, dry room",
         "lang und flatternd: langsam ausgedrückt", F_SEEDS, None, F_LANG),
        ("lang_flattern", "a long flappy whoopee cushion fart, the rubber opening vibrates and flutters loudly for over a second, brrrrrrt, funny prank toy, close-up",
         "lang und flatternd: Gummi flattert über eine Sekunde", F_SEEDS, None, F_LANG),
        ("quietschig", "a whoopee cushion fart noise that starts low and rubbery and rises in pitch at the end into a high squeaky toot as the last air escapes, comedic prank sound effect, close-up, dry room",
         "steigend: tief und gummiartig, zum Schluss hoch und quietschig", list(range(6101, 6113)), None, F_QUIETSCH),
        ("quietschig_langsam", "a rubber whoopee cushion squeezed slowly, a fluttering fart sound that gets higher and higher in pitch and ends with a squeaky rubbery peep, cartoon prank, close-up",
         "steigend: wird immer höher, endet quietschig", list(range(6101, 6113)), None, F_QUIETSCH),
        ("pfft", "a tiny whoopee cushion gives a small, soft, short pfft of air, a little rubbery puff, quiet and brief, comedic prank toy, close-up, dry room",
         "kleines „Pfft“: winziges Kissen, kurzer Luftstoß", F_SEEDS, None, F_PFFT),
        ("pfft_klein", "a small half-empty whoopee cushion pressed lightly, one short quiet rubbery pfft, very brief, close-up",
         "kleines „Pfft“: halb leeres Kissen leicht gedrückt", F_SEEDS, None, F_PFFT),
        # erste Sichtung (48, 15.10.2026): AudioSet hört „Fart“ deutlich nur bei „kurz“ (3/6), „lang“ (2/6) und „quietschig“
        # bzw. „quietschig_langsam“ (je 1–2/6). „kurz_platt“ (hart draufsetzen) ergab Schläge/Türen/Gitarre, „lang_flattern“
        # (Gummi vibriert, brrrt) Rasierer/Flöte/Mücke, „pfft“/„pfft_klein“ zwölfmal Glocke/„Ding“/Gitarre statt Luft. „lang“
        # lief natürlich 2,0–2,7 s (gekürzt) -> Daueransage 1,4/1,5 s. Neu: mehr Seeds für die tragenden Prompts, „fart“
        # ausdrücklich im „Pfft“ und einfache Formulierungen nach dem Muster von „kurz“.
        ("kurz2", "a short comedic fart noise from a whoopee cushion, a quick rubbery pfrrt, prank sound effect, close-up, dry room",
         "kurz und knackig: einfache Formulierung", F_SEEDS, None, F_KURZ),
        ("lang_14", "a whoopee cushion slowly squeezed flat, a long drawn-out rubbery fart noise, fluttering and flapping pfrrrrrrt as the air squeezes out of the rubber, comedic prank sound effect, close-up, dry room",
         "lang und flatternd: wie „lang“, Daueransage 1,4 s", list(range(6101, 6109)), None, dict(F_LANG, sekunden=1.4)),
        ("lang2", "a long comedic fart noise from a whoopee cushion, a drawn-out rubbery pfrrrrrrt that flutters and sputters as the air is squeezed out, prank sound effect, close-up, dry room",
         "lang und flatternd: knattert und stottert", list(range(6101, 6109)), None, dict(F_LANG, sekunden=1.5)),
        ("quietschig2", "a comedic fart noise from a whoopee cushion that ends in a rising squeaky toot, a rubbery pfrrrt with the pitch going up at the end, prank sound effect, close-up, dry room",
         "steigend: endet mit steigendem Quietschen", F_SEEDS, None, F_QUIETSCH),
        ("pfft_furz", "a tiny, short, quiet fart noise from a small whoopee cushion, a quick little rubbery pfft, comedic prank sound effect, close-up, dry room",
         "kleines „Pfft“: winziger, leiser Furz", list(range(6101, 6109)), None, F_PFFT),
        ("pfft_furz2", "a small whoopee cushion lets out a very short, soft little fart, pfft, quiet comedic prank sound, close-up",
         "kleines „Pfft“: sehr kurz und weich", list(range(6101, 6109)), None, F_PFFT),
    ],
}
# Zunge rausstrecken (16.10.2026, neue Reaktion 😛/😝): ein kindlich-neckisches „Bäää“ bzw. „Bläää“, wie wenn jemand
# die Zunge rausstreckt und frech „bäh“ macht, gern mit kurzem Zungen-Flattern (Prusten), lustig und freundlich, nicht
# gemein. 0,6–1,2 s, ein einziger Laut, keine verständlichen Wörter, kein Lachen, keine Katzen- oder Tierlaute: „bäää“
# darf nicht nach Schaf oder Ziege klingen. Das englische „baa“ IST das Schaf; im Prompt steht daher „bleh“, „baa“ und
# „bleating“ nur im CFG-Negativ-Prompt. Vier Arten wie beim Furzkissen (Kategorie im 6. Feld, je Zieldauer und
# Daueransage), Auswahl reihum über die Arten, nur Bestandene. Messung baeh_messen (analyse-Umgebung): Zahl der Laute,
# Stimme und Tonhöhe (stimme_messen), Zungen-Flattern (Hüllkurve 20–80 Hz wie das Knattern des Furzkissens), Zittern
# 4–12 Hz in Pegel und Tonhöhe (ein Meckern wie Schaf/Ziege).
BAEH_NEGATIV = ("sheep, lamb, goat, bleating, baa, baaing, animal, farm animal, cow, moo, cat, meow, purr, dog, bird, "
                "duck, speech, words, talking, sentence, laughter, laughing, giggling, crying, sobbing, whining, "
                "screaming, shouting, yelling, singing, music, burp, fart, groan")
BAEH_ARTEN = {"kurz": "kurzes freches „Bäh“", "lang": "langgezogenes „Bäääh“",
              "prusten": "mit Prusten (Zungen-Flattern)", "hell": "helle Kinder- bzw. Comicstimme"}
B_KURZ = {"kategorie": "kurz", "ziel": (0.5, 0.9), "sekunden": 0.7}
B_LANG = {"kategorie": "lang", "ziel": (0.8, 1.25), "sekunden": 1.1, "ausblenden": 0.2}
B_PRUSTEN = {"kategorie": "prusten", "ziel": (0.55, 1.2), "sekunden": 1.0}
B_HELL = {"kategorie": "hell", "ziel": (0.5, 1.15), "sekunden": 0.8}
B_SEEDS = list(range(7101, 7107))
B_SEEDS3 = list(range(7121, 7127))         # dritte Runde: weitere Seeds für die tragenden Varianten
TOENE["baeh"] = {
    "titel": "Zunge rausstrecken (Reaktion 😛)", "zweck": "Reaktion (😛/😝)",
    "ziel_text": "0,6–1,2 s: kindlich-neckisches „Bäää“/„Bläää“ wie mit rausgestreckter Zunge, gern mit kurzem "
                 "Zungen-Flattern (Prusten), lustig und freundlich; ein einziger Laut, keine Wörter, kein Lachen, kein Tier",
    "hinweis": "Neue Reaktion. Schaf, Ziege, Tier, Sprache, Lachen, Weinen und Schreien stehen als Negativ-Prompt "
               "(im Prompt „bleh“, weil das englische „baa“ das Schaf ist). Behalten wurde nur, was AudioSet nicht deutlich "
               "als Schaf, Ziege, Tier, Sprache, Lachen, Weinen, Schreien, Summen, Gesang, Pfeifen oder Katze hört, was "
               "AudioSet überhaupt als Mundlaut oder Stimme erkennt, aus einem einzigen Laut besteht, "
               "die Zieldauer der Art einhält und nicht meckernd zittert; die Art „mit Prusten“ muss messbar flattern, die "
               "helle Art eine hohe Stimme haben. Dubletten über alle Paare aussortiert, Auswahl reihum über die vier "
               "Arten. Die Beschreibungen (Stimmlage, Tonhöhe, Flattern, Zittern) stammen aus Messungen, nicht vom Hören.",
    "sekunden": 0.8, "ziel": (0.5, 1.2), "modus": "anfang", "vorlauf": 0.06, "einblenden": 0.01, "ausblenden": 0.15,
    "lufs": -19.0, "begrenzer": 3.0, "hochpass": 90.0, "stimme": True, "behalten": 8,
    "erwartet": ["Babbling", "Child speech, kid speaking", "Whoop", "Sound effect", "Fart"],
    "arten": BAEH_ARTEN, "baeh": True, "ausgewogen": True, "nur_ok": True, "dubletten_alle": True, "streng": True,
    "puls_purr": True, "sprache_grenze": (0.6, 0.35),
    # Ausschluss ab der Grenze, Hinweis ab der Hälfte, Abzug in den Punkten (wie gaehnen2/furzkissen)
    "meiden": {"Sheep": 0.08, "Goat": 0.08, "Bleat": 0.08, "Livestock, farm animals, working animals": 0.1,
               "Cattle, bovinae": 0.1, "Moo": 0.1, "Animal": 0.12, "Domestic animals, pets": 0.12, "Dog": 0.12,
               "Whimper (dog)": 0.12, "Duck": 0.1, "Quack": 0.1, "Goose": 0.1, "Honk": 0.1, "Horse": 0.12,
               "Neigh, whinny": 0.12, "Pig": 0.1, "Oink": 0.1, "Bird": 0.15, "Wild animals": 0.12,
               "Laughter": 0.12, "Giggle": 0.12, "Baby laughter": 0.12, "Belly laugh": 0.12, "Chuckle, chortle": 0.12,
               "Snicker": 0.12, "Crying, sobbing": 0.12, "Baby cry, infant cry": 0.12, "Whimper": 0.12,
               "Wail, moan": 0.15, "Screaming": 0.12, "Yell": 0.2, "Shout": 0.2, "Children shouting": 0.2,
               "Battle cry": 0.15, "Singing": 0.2, "Child singing": 0.2, "Music": 0.25, "Groan": 0.2,
               "Burping, eructation": 0.25,
               # nach der ersten Sichtung: lange „bleeeh“ teils Summen/Mantra/Gesang, helle Stimmen teils Huhn, Eule,
               # Heulen, Krächzen; Pfeifen/Theremin statt Stimme
               "Humming": 0.2, "Mantra": 0.12, "Chant": 0.15, "Male singing": 0.15, "Female singing": 0.15,
               "Fowl": 0.12, "Chicken, rooster": 0.12, "Owl": 0.12, "Howl": 0.12, "Canidae, dogs, wolves": 0.12,
               "Squawk": 0.12, "Bird vocalization, bird call, bird song": 0.15, "Whistle": 0.15, "Whistling": 0.15,
               "Theremin": 0.15,
               # zweite Sichtung: das Prusten ergab Zischen, Sprühen, Plopps, Schnippen, Klatschen, Herzschlag statt eines
               # Mundlauts
               "Heart sounds, heartbeat": 0.1, "Heart murmur": 0.1, "Plop": 0.3, "Finger snapping": 0.2,
               "Slap, smack": 0.25, "Spray": 0.15, "Hiss": 0.2, "Steam": 0.15, "Static": 0.2, "Whip": 0.2},
    # Mundlaut/Stimme: mindestens eine dieser Klassen ab „mensch_mindestens“, sonst hört AudioSet keinen Menschen
    # (Pfeifen, Musik, Geräusch); Klassen, die zugleich in „meiden“ stehen, schließen dort ohnehin aus
    "mensch": ["Speech", "Male speech, man speaking", "Female speech, woman speaking", "Child speech, kid speaking",
               "Babbling", "Whoop", "Yell", "Shout", "Grunt", "Groan", "Snort", "Gasp", "Sigh", "Breathing", "Pant",
               "Throat clearing", "Humming", "Fart", "Gargling", "Singing", "Male singing", "Female singing",
               "Child singing", "Yodeling", "Whimper", "Screaming", "Baby cry, infant cry", "Cough", "Sneeze", "Sniff",
               "Wail, moan", "Mantra", "Chant", "Synthetic singing", "Burping, eructation", "Hiccup"],
    "mensch_mindestens": 0.05,
    # nur zur Beschreibung in ast.json
    "beobachten": ["Speech", "Babbling", "Child speech, kid speaking", "Whoop", "Sound effect", "Fart", "Humming",
                   "Grunt", "Snort", "Hubbub, speech noise, speech babble", "Children playing", "Squeak", "Boing",
                   "Vibration", "Buzz", "Rattle", "Cartoon", "Male speech, man speaking", "Female speech, woman speaking",
                   "Mosquito", "Insect", "Kazoo", "Breathing", "Sigh", "Gasp", "Throat clearing", "Cough", "Sneeze",
                   "Synthetic singing", "Speech synthesizer", "Gargling", "Plop", "Slap, smack", "Finger snapping",
                   "Static", "Chewing, mastication", "Sniff"],
    "negativ": BAEH_NEGATIV,
    "seeds": B_SEEDS,
    "prompts": [
        ("kurz", "a person playfully sticks out their tongue and makes one short cheeky bleh sound, a quick nasal teasing blehh, funny and friendly, close-up, dry room, " + NO_WORDS,
         "kurz: Zunge raus, ein kurzes freches „bleh“", B_SEEDS, None, B_KURZ),
        ("kurz_albern", "one short silly mocking bleh with the tongue sticking out, a single playful nasal vocal sound, cheeky but friendly, close-up, quiet room, " + NO_WORDS,
         "kurz: albern-spöttisch, ein einziger Laut", B_SEEDS + B_SEEDS3, None, B_KURZ),
        ("lang", "a person sticks out their tongue and teases with a long drawn-out nasal bleeeeh, one single silly vocal sound, playful and friendly, close-up, dry room, " + NO_WORDS,
         "lang: langgezogenes „bleeeeh“", B_SEEDS + B_SEEDS3, None, B_LANG),
        ("lang_blaeh", "a playful drawn-out teasing blaaaah with the tongue sticking out, a long nasal mocking vocal sound that slowly fades, funny, not mean, close-up, quiet room, " + NO_WORDS,
         "lang: „blaaaah“, klingt langsam aus", B_SEEDS + B_SEEDS3, None, B_LANG),
        ("prusten", "a person sticks out their tongue and blows a raspberry, a short playful blehhh ending in a fluttering pbbbt of the lips and tongue, funny teasing, close-up, dry room, " + NO_WORDS,
         "Prusten: „blehhh“, endet in einem flatternden Zungen-Raspberry", B_SEEDS, None, B_PRUSTEN),
        ("raspberry", "a quick playful tongue raspberry, the tongue sticks out and flutters between the lips, bllbllbleh, cheeky teasing vocal sound, close-up, dry room, " + NO_WORDS,
         "Prusten: Zunge flattert zwischen den Lippen, „bllbllbleh“", B_SEEDS, None, B_PRUSTEN),
        ("kind", "a little child sticks out their tongue and teases with a bright, high, cheeky bleeeh, one single playful vocal sound, funny and friendly, close-up, quiet room, " + NO_WORDS,
         "hell: kleines Kind, helles freches „bleeeh“", B_SEEDS, None, B_HELL),
        ("comic", "a cartoon character with a high squeaky voice sticks out its tongue and goes bleh, a short funny teasing vocal sound effect, animated cartoon, close-up, " + NO_WORDS,
         "hell: Zeichentrickfigur mit hoher Quietschstimme", B_SEEDS, None, B_HELL),
    ],
}
# Erste Sichtung (48, 16.10.2026): „kurz“ ergab meist stimmlose Luftstöße (AudioSet Niesen/Seufzen), „kurz_albern“ eine
# Stimme, die AudioSet als Sprache hört; „lang“/„lang_blaeh“ stimmhaft, aber oft Summen, Mantra, Jammern oder Musik;
# „prusten“/„raspberry“ Plopps, Schnippen, Rauschen statt Zungen-Flattern; „kind“ Wimmern, Weinen, Kichern, Miauen;
# „comic“ Pfeifen, Alarm, Musik und einmal Miauen. Das Modell hält die Daueransage nicht ein (natürlich 0,9–2,8 s statt
# 0,7–1,1 s), daher kürzere Ansagen. Neu: Formulierungen wie in Geräuschbibliotheken („human vocal sound effect“,
# „Bronx cheer“, „blows a raspberry with lips and tongue“), Stimme ausdrücklich („voiced“, „human voice“); bei den hellen
# Stimmen zusätzlich Wimmern, Weinen, Miauen, Quietschen und Pfeifen im Negativ-Prompt; beim Prusten ein Zwilling ohne
# „fart“ im Negativ-Prompt (A/B). Einige mit CFG 6 (stärkere Prompt-Führung).
BAEH_NEG_HELL = BAEH_NEGATIV + ", whimper, whining, baby crying, kitten, squeak, squeal, whistle, alarm, siren"
BAEH_NEG_OHNE_FURZ = BAEH_NEGATIV.replace(", fart", "")
B_SEEDS2 = list(range(7111, 7117))
B_KURZ2 = dict(B_KURZ, sekunden=0.5)
B_LANG2 = dict(B_LANG, sekunden=0.9)
B_PRUSTEN2 = dict(B_PRUSTEN, sekunden=0.8)
B_HELL2 = dict(B_HELL, sekunden=0.6)
TOENE["baeh"]["prompts"] += [
    ("kurz_sfx", "human vocal sound effect, a short cheeky bleh with the tongue sticking out, voiced and nasal, one quick syllable, comedic and friendly, close-up, dry room, " + NO_WORDS,
     "kurz: „human vocal sound effect“, stimmhaft und näselnd", B_SEEDS2, None, B_KURZ2),
    ("kurz_frau", "a young woman sticks her tongue out and makes a quick voiced bleh, one short cheeky syllable with her voice, playful teasing, close-up, quiet room, " + NO_WORDS,
     "kurz: junge Frau, kurzes stimmhaftes „bleh“", B_SEEDS2 + B_SEEDS3, None, dict(B_KURZ2, cfg=6.0)),
    ("lang_frech", "a cheeky teenager sticks out the tongue and mocks with a long nasal voiced bleeeeh, sarcastic and playful, one single sound, close-up, quiet room, " + NO_WORDS,
     "lang: frecher Teenager, langes näselndes „bleeeeh“", B_SEEDS2, None, B_LANG2),
    ("lang_sfx", "human vocal sound effect, a long mocking nasal bleeeeh with the tongue sticking out, comedic and friendly, close-up, dry room, " + NO_WORDS,
     "lang: „human vocal sound effect“, langes spöttisches „bleeeeh“", B_SEEDS2, None, dict(B_LANG2, cfg=6.0)),
    ("raspberry_blow", "a person blows a raspberry with their lips and tongue, a rubbery fluttering pbbbbbt, human mouth sound, playful teasing, close-up, dry room",
     "Prusten: Raspberry mit Lippen und Zunge, „pbbbbbt“", B_SEEDS2, None, B_PRUSTEN2),
    ("raspberry_blow_ohne", "a person blows a raspberry with their lips and tongue, a rubbery fluttering pbbbbbt, human mouth sound, playful teasing, close-up, dry room",
     "Prusten: wie „raspberry_blow“, ohne „fart“ im Negativ-Prompt", B_SEEDS2, BAEH_NEG_OHNE_FURZ, B_PRUSTEN2),
    ("bronx", "Bronx cheer, a comedic human raspberry made with the tongue between the lips, a short fluttering blowing sound, close-up, dry room",
     "Prusten: „Bronx cheer“ (Zunge zwischen den Lippen)", B_SEEDS2, None, B_PRUSTEN2),
    ("bleh_prusten", "a cheeky voice goes bleh and then blows a short raspberry with the tongue out, blehhpbbbt, one quick playful sound, close-up, dry room, " + NO_WORDS,
     "Prusten: „bleh“ geht in ein kurzes Raspberry über", B_SEEDS2, None, dict(B_PRUSTEN2, cfg=6.0)),
    ("kind_frech", "a cheeky little girl sticks out her tongue at her brother and goes bleeeh, a bright playful voiced bleh, teasing and happy, close-up, quiet room, " + NO_WORDS,
     "hell: freches kleines Mädchen, helles „bleeeh“", B_SEEDS2, BAEH_NEG_HELL, B_HELL2),
    ("comic_stimme", "a cartoon character with a high-pitched human voice teases with a short nasal bleh, tongue out, comedic vocal sound effect, close-up, " + NO_WORDS,
     "hell: Zeichentrickfigur mit hoher menschlicher Stimme", B_SEEDS2 + B_SEEDS3 + [7127, 7128], BAEH_NEG_HELL, dict(B_HELL2, cfg=6.0)),
]
# Zweite Sichtung (108, 16.10.2026): bestanden nur 15 (kurz 5, lang 5, hell 4, Prusten 1 fraglich). „raspberry_blow“,
# „bronx“ und „bleh_prusten“ ergaben Zischen, Sprühen, Plopps, Knall, Peitsche oder Sprache, nie ein Flattern (das Modell
# kennt das Raspberry offenbar nicht); messbar geflattert hat bisher nur, was das Modell als Furz kennt (Furzkissen).
# Neu fürs Prusten daher „mouth fart“/„lip trill“, ohne „fart“ im Negativ-Prompt, dafür Zischen, Plopp, Knall, Nasses
# und das Furzkissen selbst (das gibt es im Spiel schon). Dazu weitere Seeds der Varianten, die bestanden haben
# (kurz_albern, kurz_frau, lang, lang_blaeh, comic_stimme), und eine hellere Zeichentrickstimme.
BAEH_NEG_PRUSTEN = (BAEH_NEG_OHNE_FURZ + ", hiss, spray, steam, snake, static, white noise, plop, pop, bang, explosion, "
                    "whip, slap, wet, liquid, splash, toilet, whoopee cushion")
TOENE["baeh"]["prompts"] += [
    ("mundfurz", "a person blows a raspberry with their mouth, a silly rubbery fart noise made with the lips and tongue, pbbbbt, playful teasing, close-up, dry room",
     "Prusten: Raspberry als „Mund-Furz“ mit Lippen und Zunge", B_SEEDS3, BAEH_NEG_PRUSTEN, B_PRUSTEN2),
    ("bleh_mundfurz", "a kid sticks out the tongue and blows a raspberry, a short voiced blehhh with fluttering lips like a silly mouth fart, playful teasing, close-up, quiet room, " + NO_WORDS,
     "Prusten: kurzes stimmhaftes „blehhh“ mit flatternden Lippen", B_SEEDS3, BAEH_NEG_PRUSTEN, B_PRUSTEN2),
    ("lippen_brrr", "a person does a short silly lip trill, the lips flutter loosely, a playful voiced brrrrr, close-up, dry room, " + NO_WORDS,
     "Prusten: Lippenflattern „brrrr“ (lip trill)", B_SEEDS3, BAEH_NEG_PRUSTEN, B_PRUSTEN2),
    # dritte Sichtung (56): „mundfurz“/„bleh_mundfurz“ flattern messbar (4 von 12, AudioSet „Fart“ 0,66–0,93), „lippen_brrr“
    # ergab Plopps/Holzklänge; „comic_hoch“ 3 von 6 bestanden. Danach Schluss (Erzeugung dauerte dem Nutzer zu lange).
    ("comic_hoch", "a cheerful cartoon character with a bright high-pitched human voice sticks its tongue out and goes bleeeh, one short playful voiced bleh, comedic vocal sound effect, close-up, " + NO_WORDS,
     "hell: fröhliche Zeichentrickfigur, hohe menschliche Stimme", B_SEEDS3, BAEH_NEG_HELL, dict(B_HELL2, cfg=6.0)),
]
# Heulen (18.10.2026, sechste Reaktion 😭 „Heulen“): gespieltes, übertriebenes Heulen wie bei einem schlechten Verlierer
# („buhuhu“, „wääh“), lustig und harmlos, nie echtes Leid; kein Baby, kein Schreien, kein Stöhnen (Gähnen Runde 1 klang dem
# Nutzer nach Klo/Sex: Stöhnen, Ächzen, Pressen stehen daher im Negativ-Prompt und in „meiden“), kein Lachen, keine
# Wörter, kein Tier (Heulen ≠ Wolf/Hund). 0,8–1,9 s (Lachen und Klatschen sind 1,9 s). Vier Arten wie beim „Bäää“:
# rhythmisches „Buhuhu“, langgezogenes „Wääh“, kurzes Schluchzen mit Schniefen, Zeichentrick-Heulen. Kürzere
# Daueransagen, weil das Modell sie überzieht (Befund „baeh“).
HEUL_NEGATIV = ("baby, infant, newborn, toddler, tantrum, screaming, scream, shriek, horror, pain, real distress, "
                "laughter, laughing, giggling, speech, words, talking, sentence, singing, music, moaning, groaning, "
                "straining, grunting, sexual, animal, dog, wolf, howl, cat, meow, kitten, bird, siren, alarm, whistle")
HEUL_ARTEN = {"buhuhu": "rhythmisches „Buhuhu“", "waeh": "langgezogenes „Wääh“",
              "schniefen": "kurzes Schluchzen mit Schniefen", "comic": "Zeichentrick-Heulen"}
H_SEEDS = list(range(7201, 7207))
H_BUHU = {"kategorie": "buhuhu", "ziel": (0.9, 1.9), "sekunden": 1.2}
H_WAEH = {"kategorie": "waeh", "ziel": (0.8, 1.9), "sekunden": 1.1}
H_SCHNIEF = {"kategorie": "schniefen", "ziel": (0.7, 1.7), "sekunden": 1.0}
H_COMIC = {"kategorie": "comic", "ziel": (0.8, 1.9), "sekunden": 1.1}
TOENE["heulen"] = {
    "titel": "Heulen (Reaktion 😭)", "zweck": "Reaktion (😭)",
    "ziel_text": "0,8–1,9 s: gespieltes, übertriebenes Heulen wie ein schlechter Verlierer („buhuhu“, „wääh“), lustig und "
                 "harmlos; keine Wörter, kein Baby, kein Schreien, kein Stöhnen, kein Lachen, kein Tier",
    "hinweis": "Neue Reaktion. Baby, Schreien, Stöhnen/Ächzen, Lachen, Sprache, Musik und Tiere (auch Wolf/Hund) stehen als "
               "Negativ-Prompt. Behalten wurde nur, was AudioSet als Weinen/Schluchzen/Wimmern erkennt und nicht deutlich "
               "als Baby, Schreien, Stöhnen, Lachen, Sprache, Gesang, Tier oder Katze hört und die Zieldauer der Art "
               "einhält. Dubletten über alle Paare aussortiert, Auswahl reihum über die vier Arten. Beschreibungen stammen "
               "aus Messungen, nicht vom Hören.",
    "sekunden": 1.1, "ziel": (0.8, 1.9), "modus": "anfang", "vorlauf": 0.08, "einblenden": 0.01, "ausblenden": 0.2,
    "lufs": -19.0, "begrenzer": 3.0, "hochpass": 90.0, "stimme": True, "behalten": 8,
    "erwartet": ["Crying, sobbing", "Whimper", "Sniff"], "erwartet_mindestens": 0.05,
    "arten": HEUL_ARTEN, "ausgewogen": True, "nur_ok": True, "dubletten_alle": True, "streng": True,
    "puls_purr": True, "sprache_grenze": (0.5, 0.3),
    "meiden": {"Baby cry, infant cry": 0.35, "Screaming": 0.12, "Yell": 0.2, "Shout": 0.2, "Children shouting": 0.2,
               "Groan": 0.12, "Grunt": 0.15, "Wail, moan": 0.3, "Laughter": 0.12, "Giggle": 0.12, "Belly laugh": 0.12,
               "Chuckle, chortle": 0.12, "Snicker": 0.12, "Baby laughter": 0.12, "Singing": 0.2, "Music": 0.25,
               "Humming": 0.2, "Howl": 0.1, "Dog": 0.12, "Whimper (dog)": 0.12, "Canidae, dogs, wolves": 0.1,
               "Animal": 0.15, "Domestic animals, pets": 0.12, "Bird": 0.15, "Whistle": 0.15, "Siren": 0.12,
               "Burping, eructation": 0.2, "Fart": 0.15},
    "beobachten": ["Speech", "Babbling", "Child speech, kid speaking", "Whimper", "Sniff", "Sigh", "Breathing", "Gasp",
                   "Wail, moan", "Baby cry, infant cry", "Sound effect", "Cartoon", "Hiccup", "Cough"],
    "negativ": HEUL_NEGATIV,
    "seeds": H_SEEDS,
    "prompts": [
        ("buhuhu", "a person pretends to cry in an exaggerated comedic way, theatrical fake sobbing boo hoo hoo, a few short rhythmic sobs, funny and playful, close-up, dry room, " + NO_WORDS,
         "Buhuhu: theatralisches, gespieltes Schluchzen", H_SEEDS, None, H_BUHU),
        ("buhuhu_verlierer", "a grown man fake cries like a sore loser after a board game, a short silly boo-hoo-hoo sobbing, comedic and harmless, close-up, quiet room, " + NO_WORDS,
         "Buhuhu: erwachsener Mann als schlechter Verlierer", H_SEEDS, None, H_BUHU),
        ("waeh", "a person bursts into a short exaggerated cartoonish wail, one drawn-out comedic waaah crying sound, playful not sad, close-up, dry room, " + NO_WORDS,
         "Wääh: kurzes, übertriebenes Losheulen", H_SEEDS, None, H_WAEH),
        ("waeh_frau", "a young woman jokingly whines and cries waaah for a moment, a short melodramatic fake cry, funny, close-up, quiet room, " + NO_WORDS,
         "Wääh: junge Frau, gespielt melodramatisch", H_SEEDS, None, H_WAEH),
        ("schniefen", "a person sobs briefly and sniffles, two or three short whimpering sobs with a sniff at the end, mock sadness, playful, close-up, dry room, " + NO_WORDS,
         "Schniefen: zwei, drei Schluchzer, am Ende ein Schniefen", H_SEEDS, None, H_SCHNIEF),
        ("schniefen_kurz", "quick comedic sniffling and sobbing, a short pitiful sob sob sniff, playful fake sadness, close-up, quiet room, " + NO_WORDS,
         "Schniefen: kurz und jämmerlich", H_SEEDS, None, H_SCHNIEF),
        ("comic", "a cartoon character bursts into tears, a short funny exaggerated crying sound effect with a human voice, animated cartoon, close-up, " + NO_WORDS,
         "Comic: Zeichentrickfigur bricht in Tränen aus", H_SEEDS, None, H_COMIC),
        ("comic_traenen", "cartoon style comedic crying, a character wails with streams of tears, a short silly boo hoo sound effect, human voice, close-up, " + NO_WORDS,
         "Comic: Tränenbäche, albernes „Buhu“", H_SEEDS, None, H_COMIC),
    ],
}
# Erste Sichtung (48, 18.10.2026): nur 1 bestanden (waeh_frau_7206). „comedic“, „cartoon“ und „sore loser“ ergaben Sprache,
# Schreien, Grunzen, Räuspern, Truthahn/Insekt oder Wolfsheulen; Weinen erkannte AudioSet nur bei „waeh_frau“ (7201: Jammern,
# Wimmern; 7206). Zweite Runde: echtes, übertriebenes Schluchzen statt „komischer“ Geräusche (der Witz liegt im Übertreiben),
# Formulierungen aus Geräuschbibliotheken, teils CFG 6; „waeh_frau“ mit weiteren Seeds; „pain, real distress“ nicht mehr im
# Negativ-Prompt (zog weg vom Weinen).
HEUL_NEG2 = HEUL_NEGATIV.replace("horror, pain, real distress, ", "")
H_SEEDS2 = list(range(7211, 7217))
TOENE["heulen"]["prompts"] = [(p[0], p[1], p[2], H_SEEDS + H_SEEDS2, p[4], p[5]) if p[0] == "waeh_frau" else p
                              for p in TOENE["heulen"]["prompts"]]
TOENE["heulen"]["prompts"] += [
    ("weinen_frau", "a woman bursts into tears and sobs for a moment, short crying with shaky sobbing breaths, close-up, quiet room, " + NO_WORDS,
     "Frau bricht kurz in Tränen aus und schluchzt", H_SEEDS2, HEUL_NEG2, H_WAEH),
    ("schluchzen_mann", "a man sobs and cries briefly, a few loud blubbering sobs, boo hoo, close-up, quiet room, " + NO_WORDS,
     "Mann: ein paar laute, blubbernde Schluchzer", H_SEEDS2, HEUL_NEG2, H_BUHU),
    ("wimmern", "a person whimpers and sobs softly, a short pitiful crying whimper with a sniff, close-up, dry room, " + NO_WORDS,
     "kurzes, jämmerliches Wimmern mit Schniefen", H_SEEDS2, HEUL_NEG2, H_SCHNIEF),
    ("melodrama", "melodramatic crying, a person wails and sobs dramatically for a second, overacted fake tears, close-up, quiet room, " + NO_WORDS,
     "melodramatisch: übertrieben schluchzen und jammern", H_SEEDS2, HEUL_NEG2, dict(H_WAEH, cfg=6.0)),
    ("heulen_sfx", "human vocal sound effect, short crying and sobbing, voiced sobs, boo hoo hoo, close-up, dry room, " + NO_WORDS,
     "„human vocal sound effect“: kurzes Weinen, „buhuhu“", H_SEEDS2, HEUL_NEG2, dict(H_BUHU, cfg=6.0)),
    ("heulen_comic_sfx", "crying sound effect, a short exaggerated sob, a person cries waaah and sniffles, human voice, close-up, " + NO_WORDS,
     "Comic: „crying sound effect“, kurzes übertriebenes Losheulen", H_SEEDS2, HEUL_NEG2, dict(H_COMIC, cfg=6.0)),
]
# Zweite Sichtung (90, 18.10.2026): wieder nur 1 neu bestanden (weinen_frau_7216). Weinen erkennt AudioSet selten („Whimper“ meist
# unter 0,1); der deutlichste Kandidat (waeh_frau_7201: „Wail, moan“ 0,52, „Whimper“ 0,20, Baby 0,24) fiel an der Grenze für
# „Wail, moan“. Der Nutzer entscheidet beim Hören (die Messwerte stehen auf der Hörseite), daher für die Auswahl lockerer:
# „Wail, moan“ bis 0,6, Baby bis 0,45 (beides weiter als Hinweis ab der Hälfte und mit Abzug in den Punkten).
TOENE["heulen"]["meiden"].update({"Wail, moan": 0.6, "Baby cry, infant cry": 0.45})
# Facepalm (18.10.2026, siebte Reaktion 🤦 „Facepalm“): Hand klatscht auf die Stirn, gern mit einem kurzen, genervten
# Seufzer danach; trocken-komisch. Kein Stöhnen/Ächzen (siehe Heulen), keine Wörter, kein Applaus (Klatschen gibt es
# schon), nichts Nasses. Vier Arten: Klatsch mit Seufzer, nur der Klatsch (kurz wie „Daumen hoch“), nur der Seufzer,
# Zeichentrick.
FACE_NEGATIV = ("speech, words, talking, sentence, groaning, moaning, grunting, straining, sexual, laughter, laughing, "
                "applause, clapping hands, crowd, cheering, crying, sobbing, screaming, music, singing, animal, cat, "
                "meow, dog, explosion, gunshot, wet, liquid, splash, toilet, kiss")
FACE_ARTEN = {"klatsch_seufzer": "Klatsch auf die Stirn, dann ein Seufzer", "klatsch": "nur der Klatsch auf die Stirn",
              "seufzer": "genervter Seufzer", "comic": "Zeichentrick-Facepalm"}
FP_SEEDS = list(range(7301, 7307))
FP_BEIDES = {"kategorie": "klatsch_seufzer", "ziel": (0.8, 1.8), "sekunden": 1.2}
FP_KLATSCH = {"kategorie": "klatsch", "ziel": (0.2, 0.7), "sekunden": 0.5, "ausblenden": 0.12}
FP_SEUFZER = {"kategorie": "seufzer", "ziel": (0.7, 1.7), "sekunden": 1.1}
FP_COMIC = {"kategorie": "comic", "ziel": (0.5, 1.7), "sekunden": 1.0}
TOENE["facepalm"] = {
    "titel": "Facepalm (Reaktion 🤦)", "zweck": "Reaktion (🤦)",
    "ziel_text": "0,3–1,8 s: Hand klatscht auf die Stirn, gern mit kurzem, genervtem Seufzer; trocken-komisch, keine Wörter, "
                 "kein Stöhnen, kein Applaus",
    "hinweis": "Neue Reaktion. Sprache, Stöhnen/Ächzen, Lachen, Applaus, Weinen, Schreien, Musik, Tiere, Knall und Nasses "
               "stehen als Negativ-Prompt. Behalten wurde nur, was AudioSet als Schlag/Klatsch oder Seufzen/Atmen erkennt "
               "und nicht deutlich als Stöhnen, Applaus, Lachen, Weinen, Sprache, Knall, Tier oder Katze hört und die "
               "Zieldauer der Art einhält. Dubletten über alle Paare aussortiert, Auswahl reihum über die vier Arten. "
               "Beschreibungen stammen aus Messungen, nicht vom Hören.",
    "sekunden": 1.0, "ziel": (0.3, 1.8), "modus": "anfang", "vorlauf": 0.04, "einblenden": 0.004, "ausblenden": 0.2,
    "lufs": -19.0, "begrenzer": 4.0, "hochpass": 70.0, "stimme": True, "behalten": 8,
    "erwartet": ["Slap, smack", "Whack, thwack", "Sigh", "Breathing"], "erwartet_mindestens": 0.05,
    "arten": FACE_ARTEN, "ausgewogen": True, "nur_ok": True, "dubletten_alle": True, "streng": True,
    "puls_purr": True, "sprache_grenze": (0.5, 0.3),
    "meiden": {"Groan": 0.12, "Grunt": 0.15, "Wail, moan": 0.12, "Applause": 0.2, "Crowd": 0.15, "Cheering": 0.15,
               "Laughter": 0.12, "Giggle": 0.12, "Chuckle, chortle": 0.12, "Crying, sobbing": 0.15, "Whimper": 0.15,
               "Screaming": 0.12, "Snoring": 0.15, "Music": 0.25, "Singing": 0.2, "Humming": 0.2, "Animal": 0.15,
               "Dog": 0.12, "Explosion": 0.12, "Gunshot, gunfire": 0.1, "Burping, eructation": 0.2, "Fart": 0.15,
               "Splash, splatter": 0.15, "Liquid": 0.15},
    "beobachten": ["Speech", "Clapping", "Slap, smack", "Whack, thwack", "Thump, thud", "Tap", "Sigh", "Breathing",
                   "Gasp", "Pant", "Snort", "Sniff", "Sound effect", "Cartoon", "Wood block", "Knock"],
    "negativ": FACE_NEGATIV,
    "seeds": FP_SEEDS,
    "prompts": [
        ("beides", "a person slaps their own forehead with the palm of the hand, one soft dull smack, followed by a short exasperated sigh, comedic, close-up, dry room, " + NO_WORDS,
         "Klatsch auf die Stirn, dann ein genervter Seufzer", FP_SEEDS, None, FP_BEIDES),
        ("beides_mann", "a man facepalms, one quick flat hand slap against his forehead and then a weary disappointed sigh, funny, close-up, quiet room, " + NO_WORDS,
         "Mann: kurzer Klatsch, müder enttäuschter Seufzer", FP_SEEDS, None, FP_BEIDES),
        ("klatsch", "a single soft dull slap of a palm hitting a forehead, one short fleshy smack, close-up, dry room, no voice",
         "nur ein dumpfer Klatsch der Handfläche auf die Stirn", FP_SEEDS, None, FP_KLATSCH),
        ("klatsch_comic", "cartoon facepalm sound effect, one comedic hand slap on the forehead, short and dry, close-up, no voice",
         "Zeichentrick-Klatsch auf die Stirn, kurz und trocken", FP_SEEDS, None, FP_KLATSCH),
        ("seufzer", "a long exasperated sigh of disbelief, a person exhales slowly through the nose, unimpressed and annoyed, close-up, dry room, " + NO_WORDS,
         "langer, ungläubig-genervter Seufzer durch die Nase", FP_SEEDS, None, FP_SEUFZER),
        ("seufzer_frau", "a woman lets out a short weary sigh, a deflated disappointed exhale, comedic, close-up, quiet room, " + NO_WORDS,
         "Frau: kurzer, müder, enttäuschter Seufzer", FP_SEEDS, None, FP_SEUFZER),
        ("comic", "a cartoon character slaps its forehead with a hollow pop and lets out a funny deflated sigh, comedic sound effect, human voice, close-up, " + NO_WORDS,
         "Comic: hohler Klatsch, dann ein komischer Seufzer", FP_SEEDS, None, FP_COMIC),
        ("comic_slapstick", "slapstick facepalm, a hand smacks a forehead with a comedic thwack, then an exaggerated tired huff, animated cartoon, close-up, " + NO_WORDS,
         "Comic: Slapstick-Klatsch, dann ein übertriebenes Schnaufen", FP_SEEDS, None, FP_COMIC),
    ],
}
# (Abgebrochen am 18.10.2026: Der Nutzer nimmt stattdessen eigene Aufnahmen, tools/make_reaktion_aufnahmen.py.)
# Nutzerbefund zu Heulen (18.10.2026): Kandidat 03 (waeh_frau_7201) am besten, „klingt aber eher wie ein verzweifelter Schrei“;
# gewünscht ist ein theatralisches, übertriebenes Weinen. Runde 3 als eigener Ton „heulen3“ (eigene Nummern): Schluchzen und
# Weinen in Theater-/Seifenoper-Manier, „buhuhu“ mit zitterndem Atem, dazu weitere Seeds von waeh_frau; Schreien, Panik,
# Verzweiflung und Angst im Negativ-Prompt; Schreien hart gemieden, Jammern bis 0,6 erlaubt (Weinen klingt so).
HEUL3_NEGATIV = (HEUL_NEG2 + ", desperate, despair, terror, fear, panic, horror scream, shriek of pain, yelling, howling")
H3_SEEDS = list(range(7231, 7239))
H3_DRAMA = {"kategorie": "drama", "ziel": (1.0, 1.95), "sekunden": 1.3}
H3_WAEH = {"kategorie": "waeh", "ziel": (1.0, 1.95), "sekunden": 1.2}
TOENE["heulen3"] = dict(TOENE["heulen"], **{
    "titel": "Heulen, Runde 3 (Reaktion 😭)",
    "ziel_text": "1,0–1,95 s: theatralisches, übertriebenes Weinen (Schluchzen, „buhuhu“, zitternder Atem), kein Schrei, keine "
                 "Verzweiflung; keine Wörter, kein Baby, kein Stöhnen, kein Lachen, kein Tier",
    "hinweis": "Runde 3 nach dem Nutzerbefund „Kandidat 3 am besten, klingt aber eher wie ein verzweifelter Schrei“: Prompts mit "
               "Theater- und Seifenoper-Weinen, Schreien/Panik/Verzweiflung im Negativ-Prompt und hart gemieden. Beschreibungen "
               "stammen aus Messungen, nicht vom Hören.",
    "arten": {"drama": "theatralisches Schluchzen", "waeh": "melodramatisches „Wääh“"},
    "meiden": dict(TOENE["heulen"]["meiden"], **{"Screaming": 0.08, "Yell": 0.12, "Shout": 0.12, "Battle cry": 0.1,
                                                  "Wail, moan": 0.6, "Baby cry, infant cry": 0.4}),
    "erwartet": ["Crying, sobbing", "Whimper", "Sniff", "Wail, moan"], "erwartet_mindestens": 0.08,
    "negativ": HEUL3_NEGATIV, "seeds": H3_SEEDS, "behalten": 8,
    "prompts": [
        ("drama", "a drama queen weeps theatrically, exaggerated loud sobbing with shaky trembling breaths, boo hoo hoo, overacted fake crying, comedic, close-up, quiet room, " + NO_WORDS,
         "Drama-Queen: übertriebenes lautes Schluchzen, zitternder Atem", H3_SEEDS, None, dict(H3_DRAMA, cfg=6.0)),
        ("seifenoper", "melodramatic soap opera weeping, a woman sobs and cries dramatically with a trembling voice, exaggerated tearful crying, sad but theatrical, close-up, " + NO_WORDS,
         "Seifenoper: Frau weint melodramatisch mit zitternder Stimme", H3_SEEDS, None, H3_WAEH),
        ("blubbern", "a man blubbers and weeps theatrically, exaggerated tearful crying with hiccuping sobs, boo hoo hoo, comedic overacting, close-up, quiet room, " + NO_WORDS,
         "Mann blubbert und weint theatralisch, schluchzend", H3_SEEDS, None, H3_DRAMA),
        ("schluchzer", "exaggerated theatrical sobbing, several loud rhythmic sobs one after another, uh-huh-huh-huh, a person weeps dramatically, tearful, close-up, " + NO_WORDS,
         "mehrere laute, rhythmische Schluchzer hintereinander", H3_SEEDS, None, dict(H3_DRAMA, cfg=6.0)),
        ("waeh_frau", "a young woman jokingly whines and cries waaah for a moment, a short melodramatic fake cry, funny, close-up, quiet room, " + NO_WORDS,
         "wie Heulen 03 (waeh_frau): junge Frau, gespielt melodramatisch, neue Seeds", list(range(7221, 7229)), None, H3_WAEH),
    ],
})
# Nutzerwunsch zu Facepalm (18.10.2026): „eher einen Klatscher direkt gefolgt von einem genervten ‚ääääh‘ (vom Tonfall ähnlich
# wie eine Kuh)“ – tief, gedehnt, genervt. Runde 2 als eigener Ton „facepalm2“. Das tiefe Äääh ist ein Brummen/Stöhnen der
# Stimme: „Groan“ diesmal erwartet und bis 0,7 erlaubt; eine echte Kuh (Moo, Cattle, Animal) und alles Sexuelle bleiben gemieden.
FACE2_NEGATIV = ("speech, words, talking, sentence, sexual, moaning in pleasure, laughter, laughing, applause, clapping hands, crowd, "
                 "cheering, crying, sobbing, screaming, music, singing, cow, cattle, moo, mooing, animal, farm animal, sheep, goat, "
                 "dog, cat, meow, explosion, gunshot, wet, liquid, splash, toilet, burp, fart")
FP2_SEEDS = list(range(7311, 7319))
FP2 = {"kategorie": "klatsch_aeh", "ziel": (0.9, 1.9), "sekunden": 1.3}
TOENE["facepalm2"] = dict(TOENE["facepalm"], **{
    "titel": "Facepalm, Runde 2 (Reaktion 🤦)",
    "ziel_text": "0,9–1,9 s: Klatsch auf die Stirn, direkt danach ein tiefes, gedehntes, genervtes „Äääh“ (Tonfall fast wie eine "
                 "Kuh, aber Mensch); keine Wörter, kein Applaus, nichts Sexuelles",
    "hinweis": "Runde 2 nach dem Nutzerwunsch „Klatscher direkt gefolgt von einem genervten ‚ääääh‘, vom Tonfall ähnlich wie eine "
               "Kuh“. Ob der Klatsch vorn liegt, ist nicht gemessen. Beschreibungen stammen aus Messungen, nicht vom Hören.",
    "arten": {"klatsch_aeh": "Klatsch, dann genervtes „Äääh“"},
    "erwartet": ["Groan", "Grunt", "Sigh", "Slap, smack", "Whack, thwack"], "erwartet_mindestens": 0.05,
    "meiden": {k: v for k, v in dict(TOENE["facepalm"]["meiden"], **{"Groan": 0.7, "Grunt": 0.6, "Wail, moan": 0.35,
               "Cattle, bovinae": 0.12, "Moo": 0.12, "Livestock, farm animals, working animals": 0.12, "Animal": 0.15,
               "Snoring": 0.2}).items()},
    "negativ": FACE2_NEGATIV, "seeds": FP2_SEEDS, "behalten": 8, "begrenzer": 3.0, "hochpass": 70.0,
    "prompts": [
        ("aeh", "a hand slaps a forehead, immediately followed by a long deep annoyed voiced aaaah, a low drawn-out exasperated human groan of disbelief, comedic, close-up, dry room, " + NO_WORDS,
         "Klatsch, sofort danach ein langes, tiefes, genervtes „Aaaah“", FP2_SEEDS, None, FP2),
        ("ugh", "facepalm, one quick flat slap on the forehead and right after it a long low frustrated uuugh, a deep nasal droning human voice, annoyed, funny, close-up, " + NO_WORDS,
         "Klatsch, dann ein tiefes, näselndes, frustriertes „Uuugh“", FP2_SEEDS, None, FP2),
        ("brummen", "a slap on the forehead followed by a drawn-out low bored human voice, a deep droning annoyed aaaaeh, grumpy and slow, comedic sound effect, close-up, " + NO_WORDS,
         "Klatsch, dann ein gedehntes, tiefes, brummiges „Äääh“", FP2_SEEDS, None, dict(FP2, cfg=6.0)),
        ("genervt", "human vocal sound effect, a smack of a palm on a forehead, then a long deep exasperated nasal aaaah of annoyance, like a grumpy teenager, close-up, dry room, " + NO_WORDS,
         "„human vocal sound effect“: Klatsch, dann genervtes, tiefes „Aaaah“", FP2_SEEDS, None, dict(FP2, cfg=6.0)),
    ],
})
# Nutzer 23.10.2026 nach dem Hören: „Das klingt alles doof“ – „Hmmm“ und „Küsschen“ kommen aus eigenen Aufnahmen
# (tools/make_reaktion_aufnahmen.py --nur hmm,kuss, Stufe nur6); die Einträge hmm/kuss hier bleiben als Beleg der verworfenen Runde.
# Nachdenken (23.10.2026, Reaktion 🤔 „Hmmm“): nachdenkliches, gesummtes „Hmmm“ mit geschlossenem Mund, das hoch anfängt
# und etwas nach unten gleitet (Nutzerwunsch). Gemessen mit stimme_messen („hmm“ in bewerten): überwiegend stimmhaft,
# Gipfel der Tonhöhe vorn, danach mindestens HMM_FALL_HT Halbtöne abwärts, kaum Anstieg. Kein Stöhnen (siehe Gähnen),
# keine Wörter, kein Gesang/keine Melodie, kein Tier.
HMM_FALL_HT = 2.5
HMM_NEGATIV = ("speech, words, talking, sentence, singing, song, melody, music, musical instrument, moaning, groaning, "
               "grunting, straining, sexual, pleasure, sigh, laughter, laughing, giggling, crying, animal, cat, meow, purr, "
               "dog, cow, moo, bee, buzzing, engine, motor, electrical hum, siren, whistle")
HMM_ARTEN = {"fallend": "„Hmmm“, hoch anfangend und abwärts gleitend", "lang": "langes, grübelndes „Hmmmmm“",
             "comic": "Zeichentrick-„Hmmm“"}
HM_SEEDS = list(range(7401, 7407))
HM_FALL = {"kategorie": "fallend", "ziel": (0.7, 1.6), "sekunden": 1.1}
HM_LANG = {"kategorie": "lang", "ziel": (1.0, 1.95), "sekunden": 1.5}
HM_COMIC = {"kategorie": "comic", "ziel": (0.6, 1.6), "sekunden": 1.0}
TOENE["hmm"] = {
    "titel": "Nachdenken „Hmmm“ (Reaktion 🤔)", "zweck": "Reaktion (🤔)",
    "ziel_text": "0,7–1,95 s: nachdenkliches, gesummtes „Hmmm“ (Mund zu), fängt hoch an und gleitet etwas nach unten; keine "
                 "Wörter, kein Gesang, kein Stöhnen, kein Tier",
    "hinweis": "Neue Reaktion. Sprache, Gesang/Melodie, Stöhnen/Ächzen, Seufzen, Lachen, Weinen, Tiere und Brummen von Maschinen "
               "stehen als Negativ-Prompt. Behalten wurde nur, was überwiegend stimmhaft ist, den Tonhöhengipfel vorn hat und "
               "danach mindestens 2,5 Halbtöne fällt (pyin), und was AudioSet nicht deutlich als Stöhnen, Sprache, "
               "Gesang, Tier oder Katze hört. Dubletten über alle Paare aussortiert, Auswahl reihum über die Arten. "
               "Beschreibungen stammen aus Messungen, nicht vom Hören.",
    "sekunden": 1.1, "ziel": (0.7, 1.95), "modus": "anfang", "vorlauf": 0.06, "einblenden": 0.01, "ausblenden": 0.2,
    "lufs": -19.0, "begrenzer": 3.0, "hochpass": 80.0, "stimme": True, "behalten": 8, "tonhoehe": True, "hmm": True,
    "erwartet": ["Humming", "Hum", "Male speech, man speaking", "Female speech, woman speaking", "Speech"],
    "erwartet_mindestens": 0.03,
    "arten": HMM_ARTEN, "ausgewogen": True, "nur_ok": True, "dubletten_alle": True, "streng": True,
    "puls_purr": True, "sprache_grenze": (0.75, 0.5),
    "meiden": {"Groan": 0.15, "Grunt": 0.2, "Wail, moan": 0.15, "Singing": 0.25, "Music": 0.3, "Laughter": 0.12,
               "Giggle": 0.12, "Crying, sobbing": 0.12, "Sigh": 0.35, "Animal": 0.15, "Domestic animals, pets": 0.12,
               "Cattle, bovinae": 0.12, "Moo": 0.12, "Bee, wasp, etc.": 0.12, "Insect": 0.12, "Buzz": 0.2,
               "Mains hum": 0.15, "Engine": 0.12, "Burping, eructation": 0.15},
    "beobachten": ["Speech", "Humming", "Hum", "Sigh", "Breathing", "Groan", "Male speech, man speaking",
                   "Female speech, woman speaking", "Sound effect", "Cartoon"],
    "negativ": HMM_NEGATIV,
    "seeds": HM_SEEDS,
    "prompts": [
        ("denken", "a person thinks hard and goes hmmm with the mouth closed, one thoughtful hummed hmm that starts high and slowly glides down in pitch, pondering, close-up, dry room, " + NO_WORDS,
         "nachdenkliches „Hmmm“ mit geschlossenem Mund, hoch anfangend, abwärts gleitend", HM_SEEDS, None, HM_FALL),
        ("denken_mann", "a man ponders a tricky decision, a single voiced hmmm through the nose, high at the start and falling lower at the end, skeptical and curious, close-up, quiet room, " + NO_WORDS,
         "Mann: „Hmmm“ durch die Nase, oben anfangend, unten endend", HM_SEEDS, None, HM_FALL),
        ("denken_frau", "a woman considers her options, a curious hummed hmmmm with closed lips, the pitch starts high and drifts downward, playful thinking sound, close-up, quiet room, " + NO_WORDS,
         "Frau: neugieriges „Hmmmm“ mit geschlossenen Lippen, Tonhöhe sinkt", HM_SEEDS, None, HM_FALL),
        ("gruebeln", "a long drawn-out pondering hmmmmm, a person hums thoughtfully with closed mouth, starting on a higher note and sinking slowly, as if solving a puzzle, close-up, dry room, " + NO_WORDS,
         "langes, grübelndes „Hmmmmm“, sinkt langsam", HM_SEEDS, None, HM_LANG),
        ("comic", "a cartoon character strokes its chin and goes hmmmm, a comedic thoughtful humming sound with a downward pitch glide, human voice, close-up, " + NO_WORDS,
         "Comic: Zeichentrickfigur reibt sich das Kinn, „Hmmmm“ nach unten", HM_SEEDS, None, dict(HM_COMIC, cfg=6.0)),
        ("sfx", "human vocal sound effect, a single thinking hmm, closed-mouth hum, high pitch at the beginning falling down at the end, close-up, dry room, " + NO_WORDS,
         "„human vocal sound effect“: ein „Hmm“, oben anfangend, unten endend", HM_SEEDS, None, dict(HM_FALL, cfg=6.0)),
    ],
}
# Knutschen (23.10.2026, Reaktion 😘 „Kuss“): ein Luftkuss/Schmatzer wie „mwah“ – lieb und lustig, nicht feucht, nicht
# sexuell. AudioSet kennt keinen Kuss; am nächsten liegen „Squish“, „Slap, smack“, „Burst, pop“. Darum nur schwach
# erwartet; über die Auswahl entscheidet der Nutzer beim Hören. Kurz (0,25–1,1 s).
KUSS_NEGATIV = ("speech, words, talking, sentence, wet, slurping, saliva, spit, liquid, splash, chewing, eating, sexual, moaning, "
                "groaning, breathing heavily, laughter, laughing, giggling, music, singing, animal, cat, meow, dog, bird, "
                "fish, gunshot, explosion, clapping, applause, fart, burp")
KUSS_ARTEN = {"mwah": "Luftkuss „mwah“", "schmatz": "kurzer Schmatzer", "doppelt": "zwei Küsschen", "comic": "Zeichentrick-Kuss"}
K_SEEDS = list(range(7501, 7507))
K_MWAH = {"kategorie": "mwah", "ziel": (0.3, 1.1), "sekunden": 0.7, "ausblenden": 0.12}
K_SCHMATZ = {"kategorie": "schmatz", "ziel": (0.15, 0.6), "sekunden": 0.5, "ausblenden": 0.08}
K_DOPPELT = {"kategorie": "doppelt", "ziel": (0.4, 1.1), "sekunden": 0.8, "ausblenden": 0.1}
K_COMIC = {"kategorie": "comic", "ziel": (0.3, 1.1), "sekunden": 0.7, "ausblenden": 0.12}
TOENE["kuss"] = {
    "titel": "Knutschen (Reaktion 😘)", "zweck": "Reaktion (😘)",
    "ziel_text": "0,15–1,1 s: Luftkuss oder Schmatzer („mwah“), lieb und lustig; nicht feucht, nicht sexuell, keine Wörter",
    "hinweis": "Neue Reaktion. Sprache, Nasses/Schlürfen/Kauen, Sexuelles, Stöhnen, Lachen, Musik, Tiere, Knall und Applaus "
               "stehen als Negativ-Prompt. AudioSet kennt keinen Kuss: behalten wurde, was die Zieldauer einhält und nicht "
               "deutlich nach Sprache, Kauen/Schlürfen, Stöhnen, Lachen, Knall, Applaus, Tier oder Katze klingt. Dubletten über "
               "alle Paare aussortiert, Auswahl reihum über die Arten. Beschreibungen stammen aus Messungen, nicht vom Hören.",
    "sekunden": 0.7, "ziel": (0.15, 1.1), "modus": "anfang", "vorlauf": 0.03, "einblenden": 0.003, "ausblenden": 0.12,
    "lufs": -20.0, "begrenzer": 4.0, "hochpass": 120.0, "stimme": True, "behalten": 8,
    "erwartet": ["Squish", "Slap, smack", "Burst, pop", "Speech", "Sound effect"], "erwartet_mindestens": 0.0,
    "arten": KUSS_ARTEN, "ausgewogen": True, "nur_ok": True, "dubletten_alle": True, "streng": True,
    "puls_purr": True, "sprache_grenze": (0.6, 0.35),
    "meiden": {"Chewing, mastication": 0.15, "Liquid": 0.15, "Splash, splatter": 0.15, "Drip": 0.15, "Groan": 0.12,
               "Wail, moan": 0.12, "Laughter": 0.12, "Giggle": 0.12, "Applause": 0.15, "Clapping": 0.2, "Music": 0.25,
               "Animal": 0.15, "Bird": 0.15, "Dog": 0.12, "Gunshot, gunfire": 0.1, "Explosion": 0.1, "Fart": 0.15,
               "Burping, eructation": 0.15, "Breathing": 0.3},
    "beobachten": ["Speech", "Squish", "Slap, smack", "Burst, pop", "Tap", "Sound effect", "Cartoon", "Whistle",
                   "Chewing, mastication", "Breathing", "Sniff"],
    "negativ": KUSS_NEGATIV,
    "seeds": K_SEEDS,
    "prompts": [
        ("mwah", "a person blows a loving air kiss, one short smooch with a voiced mwah, lips pressed and released, sweet and playful, close-up, dry room, " + NO_WORDS,
         "Luftkuss mit stimmhaftem „mwah“, lieb und verspielt", K_SEEDS, None, K_MWAH),
        ("mwah_frau", "a woman blows a kiss, a cute short mwah smooch sound, affectionate and funny, close-up, quiet room, " + NO_WORDS,
         "Frau wirft einen Kuss, kurzes süßes „mwah“", K_SEEDS, None, K_MWAH),
        ("schmatz", "a single quick kiss sound, a short dry lip smack smooch, no voice, close-up, dry room",
         "ein kurzer, trockener Schmatzer der Lippen, ohne Stimme", K_SEEDS, None, K_SCHMATZ),
        ("schmatz_wange", "a quick peck on the cheek, one short soft kiss smack, close-up, quiet room, no voice",
         "Küsschen auf die Wange, kurz und weich", K_SEEDS, None, K_SCHMATZ),
        ("doppelt", "two quick affectionate kisses, smooch smooch, short lip smacks one after another, playful, close-up, dry room, no voice",
         "zwei schnelle Küsschen hintereinander", K_SEEDS, None, K_DOPPELT),
        ("comic", "cartoon kiss sound effect, an exaggerated comedic smooch, a loud pucker and a pop, mwah, close-up, " + NO_WORDS,
         "Comic: übertriebener Schmatzer mit Plopp, „mwah“", K_SEEDS, None, dict(K_COMIC, cfg=6.0)),
        ("sfx", "human vocal sound effect, a kiss blown into the air, pucker and mwah, short and cute, close-up, dry room, " + NO_WORDS,
         "„human vocal sound effect“: Luftkuss, spitzen und „mwah“", K_SEEDS, None, dict(K_MWAH, cfg=6.0)),
    ],
}
_ORDNUNG = ["gaehnen", "gaehnen2", "gaehnen3"] + [k for k in TOENE if not k.startswith("gaehnen") and k not in
                                                  ("baeh", "heulen", "heulen3", "facepalm", "facepalm2", "hmm", "kuss")]
_ORDNUNG.insert(_ORDNUNG.index("daumen") + 1, "baeh")      # bei den Reaktionen
_ORDNUNG.insert(_ORDNUNG.index("baeh") + 1, "heulen")
_ORDNUNG.insert(_ORDNUNG.index("heulen") + 1, "heulen3")
_ORDNUNG.insert(_ORDNUNG.index("heulen3") + 1, "facepalm")
_ORDNUNG.insert(_ORDNUNG.index("facepalm") + 1, "facepalm2")
_ORDNUNG.insert(_ORDNUNG.index("facepalm2") + 1, "hmm")
_ORDNUNG.insert(_ORDNUNG.index("hmm") + 1, "kuss")
TOENE = {k: TOENE[k] for k in _ORDNUNG}
# Einziger Versuch „gaehnen3_02umgestellt“: in gaehnen2_02 (Rohdatei gaehnen2_frau_4110) Einatmen und „aaah“ tauschen,
# an der natürlichen Pause dazwischen und mit weicher Blende in der Stille (siehe umstellen). Nur, wenn die Pause klar ist
# und die Nähte in der Stille liegen; sonst entfällt er.
UMGESTELLT = {"id": "gaehnen3_umgestellt_4110", "quelle": "gaehnen2_frau_4110", "datei": "gaehnen3_02umgestellt"}
REIHE = list(TOENE)
SPRACHE =["Speech", "Male speech, man speaking", "Female speech, woman speaking", "Child speech, kid speaking",
           "Conversation", "Narration, monologue", "Speech synthesizer"]
KATZE = ["Cat", "Meow", "Purr", "Caterwaul", "Roaring cats (lions, tigers)"]
WARN = ["Hiss", "Animal", "Domestic animals, pets", "Bird", "Dog", "Squeak", "Squeal", "Whistle", "Whistling",
        "Beep, bleep", "Baby cry, infant cry", "Whimper", "Music", "Singing", "Frog", "Croak", "Roar", "Growling", "Screaming", "Explosion", "Gunshot, gunfire", "Bang"]


def candidates(nur=None):
    out = []
    keys = [k.strip() for k in nur.split(",")] if nur else None
    for ton, t in TOENE.items():
        if keys and ton not in keys:
            continue
        for pr in t["prompts"]:
            pname, prompt, notiz = pr[:3]
            opt = optionen_von(pr)
            for sd in seeds_von(t, pr):
                out.append(dict({"id": f"{ton}_{pname}_{sd}", "ton": ton, "variante": pname, "prompt": prompt,
                                 "prompt_notiz": notiz, "seed": sd, "sekunden": opt.get("sekunden", t["sekunden"]),
                                 "negativ": negativ_von(t, pr), "cfg": opt.get("cfg", m.CFG)},
                                # Abweichungen je Variante (Furzkissen): Zieldauer, Pegel, Ausblenden, Art, Anstieg
                                **{k: opt[k] for k in VARIANTE_FELDER if k in opt}))
        if ton == "gaehnen3":
            # nicht erzeugt, sondern aus gaehnen2_02 umgestellt (umstellen); läuft außerhalb der Rangfolge
            q = json.load(open(os.path.join(ROH, UMGESTELLT["quelle"] + ".json"), encoding="utf-8"))
            out.append({"id": UMGESTELLT["id"], "ton": ton, "variante": "umgestellt", "prompt": q["prompt"],
                        "prompt_notiz": "gaehnen2_02 mit getauschten Teilen: erst der Atem, dann das „aaah“",
                        "seed": q["seed"], "sekunden": q["sekunden"], "negativ": q.get("negativ", ""), "umgestellt": True})
    return out


def negativ_von(t, pr):
    """CFG-Negativ-Prompt eines Prompt-Eintrags: 5. Feld (None = wie der Ton), sonst „negativ“ des Tons, sonst leer
    (wie die Pipeline)."""
    return pr[4] if len(pr) > 4 and pr[4] is not None else t.get("negativ", "")


def optionen_von(pr):
    """6. Feld eines Prompt-Eintrags: Abweichungen je Variante, {"cfg": …, "sekunden": …} (Daueransage), dazu
    VARIANTE_FELDER: „ziel“ (Zieldauer), „lufs“, „ausblenden“, „kategorie“ (Art), „steigt_ht“ (Mindestanstieg zum Schluss)."""
    return pr[5] if len(pr) > 5 else {}


VARIANTE_FELDER = ("ziel", "lufs", "ausblenden", "kategorie", "steigt_ht")


def ton_fuer(c):
    """Einstellungen des Tons mit den Abweichungen der Variante (nur Kandidaten aus candidates; in den Ergebnissen
    heißen sie ziel/ziel_lufs/kategorie/steigt_min_ht, „lufs“ ist dort der gemessene Pegel)."""
    t = TOENE[c["ton"]]
    return dict(t, **{k: c[k] for k in ("ziel", "lufs", "ausblenden") if k in c}) if any(k in c for k in VARIANTE_FELDER) else t


def seeds_von(t, pr):
    return pr[3] if len(pr) > 3 and pr[3] else t["seeds"]


# ---------------------------------------------------------------------------------------------------------------
# Erzeugung (moss-sfx-Umgebung, GPU)
# ---------------------------------------------------------------------------------------------------------------
class MitNegativ:
    """Reicht die Pipeline an make_sfx_moss.generate_batch weiter und setzt dabei den CFG-Negativ-Prompt
    (Pipeline-Argument negative_prompt; leer = Grundeinstellung der Pipeline)."""

    def __init__(self, pipe, negativ):
        self.pipe, self.engine, self.negativ = pipe, pipe.engine, negativ

    def __call__(self, **kw):
        return self.pipe(negative_prompt=self.negativ, **kw)


def pipeline_sparsam(frei, gesamt):
    """Sparmodus (siehe Kopf): Modell im Arbeitsspeicher laden; die DiffSynth-VRAM-Verwaltung holt je Schritt nur den
    nötigen Teil auf die GPU (Textkodierer, dann DiT, dann VAE) und legt die übrigen in den Arbeitsspeicher. Ohne
    requires_grad hält Autocast keine bf16-Kopie der fp32-DiT-Gewichte vor (rechnet sie je Schicht neu um: gleiches
    Ergebnis). PyTorch darf höchstens frei − SPARSAM_RESERVE_GIB belegen (Fehler statt Verdrängen fremder Prozesse)."""
    import torch
    if "Draw2Race-AudioLab" not in os.environ.get("HF_HOME", ""):
        sys.exit("HF_HOME zeigt nicht in die Werkstatt. Vorher: . E:\\Draw2Race-AudioLab\\env.ps1")
    grenze = frei - int(SPARSAM_RESERVE_GIB * 2 ** 30)
    torch.cuda.set_per_process_memory_fraction(max(0.05, grenze / gesamt), 0)
    sys.path.insert(0, m.MOSS_REPO)
    from moss_soundeffect_v2 import MossSoundEffectPipeline
    t0 = time.time()
    pipe = MossSoundEffectPipeline.from_pretrained(m.MODEL_ID, torch_dtype=torch.bfloat16, device="cpu",
                                                   local_files_only=True)
    eng = pipe.engine
    for p in eng.parameters():
        p.requires_grad_(False)
    eng.device = "cuda"
    eng.vram_management_enabled = True
    return pipe, time.time() - t0


def gpu_frei_nvsmi(gpu):
    """Freier Speicher laut nvidia-smi (Bytes). Unter Windows (WDDM) meldet torch.cuda.mem_get_info das Budget des
    Prozesses: Speicher eines untätigen fremden Prozesses zählt dort als frei und wird beim Belegen verdrängt
    (15.10.2026: LM Studio, 17 GB auf GPU 0 ausgelagert)."""
    try:
        o = subprocess.run(["nvidia-smi", "--query-gpu=memory.used,memory.total", "--format=csv,noheader,nounits",
                            "-i", str(gpu)], capture_output=True, text=True, check=True).stdout
        used, total = (int(v) for v in o.strip().split(","))
        return (total - used) * 2 ** 20
    except Exception:
        return None


def erzeugen(cs, gpu, stapel=3, vram=None):
    """vram: höchstens so viele GiB auf der GPU belegen (erzwingt den Sparmodus), z. B. wenn ein fremder Prozess
    gerade ausgelagert ist und nvidia-smi deshalb zu viel freien Speicher zeigt."""
    os.environ["CUDA_VISIBLE_DEVICES"] = str(gpu)
    import soundfile as sf
    import torch
    os.makedirs(ROH, exist_ok=True)
    todo = [c for c in cs if not c.get("umgestellt") and not os.path.exists(os.path.join(ROH, c["id"] + ".wav"))]
    print(f"Zu erzeugen: {len(todo)} von {len(cs)} (GPU {gpu})", flush=True)
    if not todo:
        return
    smi = gpu_frei_nvsmi(gpu)
    frei, gesamt = torch.cuda.mem_get_info(0)
    if smi is not None:
        frei = min(frei, smi)
    if vram is not None:
        frei = min(frei, int((vram + SPARSAM_RESERVE_GIB) * 2 ** 30))
    if vram is not None or frei < SPARSAM_AB_GIB * 2 ** 30:
        print(f"GPU {gpu}: {frei / 2 ** 30:.1f} von {gesamt / 2 ** 30:.1f} GiB nutzbar -> Sparmodus "
              f"(höchstens {(frei / 2 ** 30) - SPARSAM_RESERVE_GIB:.1f} GiB, Stapel 1)", flush=True)
        pipe, t_load = pipeline_sparsam(frei, gesamt)
        stapel = 1
    else:
        pipe, t_load = m.load_pipeline()
    print(f"Modell geladen in {t_load:.0f} s", flush=True)
    torch.cuda.reset_peak_memory_stats()
    groups = {}
    for c in todo:
        groups.setdefault((c["ton"], c.get("negativ", ""), c.get("cfg", m.CFG), c["sekunden"]), []).append(c)
    t0 = time.time()
    n = 0
    for (ton, negativ, cfg, _sek), items in groups.items():
        for i in range(0, len(items), stapel):
            b = items[i:i + stapel]
            waves, dt = m.generate_batch(MitNegativ(pipe, negativ) if negativ else pipe, b, m.STEPS, cfg, m.SHIFT)
            for c, w in zip(b, waves):
                sf.write(os.path.join(ROH, c["id"] + ".wav"), w, FS, subtype="FLOAT")
                meta = dict(c, schritte=m.STEPS, cfg=cfg, sigma_shift=m.SHIFT, modell=m.MODEL_ID, stapel=len(b),
                            laufzeit_je_ton_s=round(dt / len(b), 1), erzeugt=time.strftime("%Y-%m-%d %H:%M:%S"))
                with open(os.path.join(ROH, c["id"] + ".json"), "w", encoding="utf-8") as f:
                    json.dump(meta, f, ensure_ascii=False, indent=1)
            n += len(b)
            print(f"  {', '.join(c['id'] for c in b)}: {dt:.0f} s ({n}/{len(todo)}, {time.time() - t0:.0f} s, "
                  f"GPU-Spitze {torch.cuda.max_memory_allocated() / 2 ** 30:.1f} GiB)", flush=True)
    del pipe
    torch.cuda.empty_cache()


# ---------------------------------------------------------------------------------------------------------------
# Messungen
# ---------------------------------------------------------------------------------------------------------------
def puls_15_50(y):
    """Pulsfolge 15–50 Hz (Schnurr-Bereich) wie tools/hoerseite_sfx_ki.py: stärkste Linie im Hüllkurvenspektrum."""
    import numpy as np
    from scipy.signal import butter, hilbert, resample_poly, sosfiltfilt
    if len(y) <= 0.3 * FS:
        return None
    h = np.abs(hilbert(y))
    h = sosfiltfilt(butter(4, 150, "low", fs=FS, output="sos"), h)
    h = resample_poly(h, 1, FS // 1000)
    h = h - h.mean()
    n = 8192
    spec = np.abs(np.fft.rfft(h * np.hanning(len(h)), n=n))
    fm = np.fft.rfftfreq(n, 1 / 1000)
    band = (fm >= 15) & (fm <= 50)
    ref = (fm >= 5) & (fm <= 120)
    i = int(np.argmax(np.where(band, spec, 0)))
    return {"hz": round(float(fm[i]), 1), "schaerfe": round(float(spec[i] / (np.median(spec[ref]) + 1e-12)), 1)}


def wecker_messen(x):
    """Klingel-Einsatz, -Ende und Ticks davor. Klingeln = erster Abschnitt, in dem der 50-ms-Pegel 0,4 s lang zu
    mindestens 80 % höchstens 10 dB unter dem Klingelpegel L liegt (L = 92. Perzentil des 50-ms-Pegels; das Klingeln ist
    der laute, dauerhafte Teil). Einsatz verfeinert mit der 10-ms-Hüllkurve. Ticks: Spitzen der 3-ms-Hüllkurve über
    1 kHz vor dem Einsatz (Prominenz ≥ 10 dB, Abstand ≥ 0,12 s, höchstens 45 dB unter L). Zeiten in s ab Dateianfang."""
    import numpy as np
    from scipy import signal
    hop, w = int(0.01 * FS), int(0.05 * FS)
    if len(x) < 4 * w:
        return None
    c = np.concatenate([[0.0], np.cumsum(np.square(x))])
    idx = np.arange(0, len(x) - w, hop)
    e = 10 * np.log10((c[idx + w] - c[idx]) / w + 1e-20)
    L = float(np.percentile(e, 92))
    hi = e > L - 10
    k = 40
    ring = None
    for i in range(len(e) - k):
        if hi[i] and hi[i:i + k].mean() >= 0.8:
            ring = i
            break
    if ring is None:
        return None
    # Klingeln beginnt oft flatternd (kurze Lücken): rückwärts, solange der Pegel höchstens 15 dB unter L liegt und
    # Lücken kürzer als 60 ms sind.
    first, gap = ring, 0
    for j in range(ring - 1, -1, -1):
        if e[j] > L - 15:
            first, gap = j, 0
        else:
            gap += 1
            if gap > 6:
                break
    env = m.envelope_db(x, 10.0)
    a = max(0, int(idx[first]) - int(0.05 * FS))
    b = min(len(x), int(idx[first]) + w + int(0.1 * FS))
    above = np.nonzero(env[a:b] > L - 15)[0]
    onset = a + int(above[0]) if len(above) else int(idx[first])
    last, gap = ring, 0
    for j in range(ring, len(e)):
        if e[j] > L - 15:
            last, gap = j, 0
        else:
            gap += 1
            if gap > 30:
                break
    ende = min(len(x), int(idx[last]) + w)
    hpx = signal.sosfiltfilt(signal.butter(4, 1000, "high", fs=FS, output="sos"), x)
    henv = m.envelope_db(hpx, 3.0)
    seg = henv[:max(2, onset - int(0.04 * FS))]
    pk, _ = signal.find_peaks(seg, prominence=10.0, distance=int(0.12 * FS), height=L - 45)
    ticks = [round(p / FS, 3) for p in pk]
    d = np.diff(ticks) if len(ticks) > 1 else np.array([])
    nach = e[idx > ende + int(0.3 * FS)]
    vor = e[(idx >= (pk[0] if len(pk) else 0)) & (idx < onset - w)]
    return {"klingeln_ab_s": round(onset / FS, 3), "klingeln_bis_s": round(ende / FS, 3),
            "klingeln_dauer_s": round((ende - onset) / FS, 3), "klingel_pegel_db": round(L, 1),
            "ticks": len(ticks), "tick_zeiten_s": ticks[:60], "erster_tick_s": ticks[0] if ticks else None,
            "ticken_dauer_s": round(onset / FS - ticks[0], 3) if ticks else 0.0,
            "tick_abstand_s": round(float(np.median(d)), 3) if len(d) else None,
            "tick_streuung": round(float(np.std(d) / (np.mean(d) + 1e-9)), 2) if len(d) > 1 else None,
            "ticken_rel_db": round(float(np.max(vor) - L), 1) if len(vor) else None,
            "nach_klingeln_rel_db": round(float(np.max(nach) - L), 1) if len(nach) else None}


def wecker_schnitt(xl):
    """Nur Anfang und Ende werden geschnitten (weiche Blenden), nie etwas zusammengesetzt.
    Anfang: am ersten Laut; tickt der Wecker länger als 3,4 s, beginnt die Datei an der leisesten Stelle 3,25–2,9 s vor
    dem Klingeln (Einblenden 60 ms). Ende: Klingeln mit natürlichem Ausklang (höchstens 0,6 s); klingelt er länger als
    2,4 s, wird er ab 1,95 s nach dem Einsatz in 0,4 s ausgeblendet."""
    import numpy as np
    w = wecker_messen(xl)
    if w is None:
        return None
    env = m.envelope_db(xl)
    top = float(env.max())
    onset = int(w["klingeln_ab_s"] * FS)
    on = np.nonzero(env > top - 45)[0]
    first = int(on[0]) if len(on) else 0
    if w["erster_tick_s"] is not None:
        first = min(first, int(w["erster_tick_s"] * FS))
    start = max(0, first - int(0.03 * FS))
    ein, info = 0.01, {}
    if onset - start > int(3.4 * FS):
        a, b = onset - int(3.25 * FS), onset - int(2.9 * FS)
        start = a + int(np.argmin(env[a:b]))
        ein = 0.06
        info["ticken_vorn_gekuerzt_s"] = round((start - first) / FS, 2)
    ende = int(w["klingeln_bis_s"] * FS)
    info["klingeln_natuerlich_s"] = w["klingeln_dauer_s"]
    if ende - onset > int(2.4 * FS):
        end, aus = onset + int(2.35 * FS), 0.4
        info["klingeln_ausgeblendet"] = True
    else:
        L = w["klingel_pegel_db"]
        tail = env[ende:min(len(env), ende + int(0.6 * FS))]
        quiet = np.nonzero(tail < L - 40)[0]
        end, aus = ende + (int(quiet[0]) if len(quiet) else len(tail)), 0.12
        info["klingeln_ausgeblendet"] = False
    end = min(len(xl), end)
    info.update({"start_s": round(start / FS, 3), "roh_klingeln_ab_s": w["klingeln_ab_s"],
                 "roh_ticken_rel_db": w["ticken_rel_db"]})
    return start, end, ein, aus, info


def ticken_anheben(x, info):
    """Ist das Ticken mehr als TICK_MIN_DB leiser als das Klingeln (am Handy dann unhörbar), wird der Teil vor dem
    Klingeln mit einer weichen Pegelkurve auf TICK_ZIEL_DB angehoben (höchstens TICK_MAX_DB); 60–10 ms vor dem
    Klingel-Einsatz geht die Kurve in 50 ms (Kosinus) auf 0 dB zurück. Kein Schnitt, nichts zusammengesetzt."""
    import numpy as np
    rel = info.get("roh_ticken_rel_db")
    if rel is None or rel >= TICK_MIN_DB:
        return x, 0.0
    g_db = min(TICK_MAX_DB, TICK_ZIEL_DB - rel)
    g = np.ones(len(x))
    on = int(info["roh_klingeln_ab_s"] * FS)
    a, b = max(0, on - int(0.06 * FS)), max(0, on - int(0.01 * FS))
    G = 10 ** (g_db / 20)
    g[:a] = G
    u = np.linspace(0, 1, b - a)
    g[a:b] = 1 + (G - 1) * (0.5 + 0.5 * np.cos(np.pi * u))
    return x * g, round(float(g_db), 1)


def laute_strecken(env, grenze_db, min_s=0.03, luecke_s=0.0):
    """Strecken (a, b) mit Hüllkurve über grenze_db (absolut), kürzer als min_s verworfen, Lücken unter luecke_s
    überbrückt."""
    runs = [(a, b) for a, b in m.quiet_runs(env > grenze_db, 1) if b - a >= int(min_s * FS)]
    out = []
    for a, b in runs:
        if out and a - out[-1][1] < int(luecke_s * FS):
            out[-1] = (out[-1][0], b)
        else:
            out.append((a, b))
    return out


def gaehnen_schnitt(xl, t):
    """Gähnen Runde 3 (modus „einatmen“): Das Einatmen vorn ist leiser als das „aaah“; find_event setzte den Anfang an
    den ersten Einsatz 20 dB unter dem Höchstwert und schnitte es ab. Hier: hörbar = 50-ms-Hüllkurve höchstens 40 dB
    unter dem Höchstwert (eine 10-ms-Hüllkurve lag am spitzen Stimmeinsatz so hoch, dass der Atem darunter fiel),
    Strecken unter 50 ms zählen nicht, Lücken unter 1,0 s werden überbrückt (die Pause zwischen Atem und „aaah“ bleibt,
    wie sie ist; zu lange Pausen fallen in der Reihenfolge-Prüfung auf); genommen wird die zusammenhängende Strecke mit
    dem Höchstwert, 40 ms davor, 60 ms danach, höchstens ziel[1] s (dann ausgeblendet)."""
    import numpy as np
    env = m.envelope_db(xl, 50.0)
    top = float(env.max())
    ipk = int(env.argmax())
    st = laute_strecken(env, top - 40.0, 0.05, 1.0)
    a, b = next(((a, b) for a, b in st if a <= ipk < b), (ipk, ipk + 1))
    start = max(0, a - int(t["vorlauf"] * FS))
    end = min(len(xl), b + int(0.06 * FS))
    cap = int(t["ziel"][1] * FS)
    natural = (end - start) / FS
    end = min(end, start + cap)
    return start, end, {"start_s": round(start / FS, 3), "hoechstwert_s": round(ipk / FS, 3),
                        "natuerliche_dauer_s": round(natural, 3), "gekuerzt": bool(natural * FS > cap)}


def umstellen(force=False):
    """Einziger Versuch „gaehnen3_02umgestellt“: gaehnen2_02 (Rohdatei gaehnen2_frau_4110) besteht aus „aaah“ (stimmhaft),
    einer Pause und einem gehauchten Atemzug, den der Nutzer als Luftholen hört. Getauscht wird nur, wenn genau zwei
    Strecken (hörbar = 10-ms-Hüllkurve ≤ 42 dB unter dem Höchstwert, Lücken < 0,15 s überbrückt, je ≥ 0,3 s) mit einer
    klaren Pause (≥ 0,15 s, leiser als −40 dB) dazwischen da sind, die erste stimmhaft (≥ 50 % der Rahmen), die zweite
    gehaucht (≤ 10 %). Neu: [Pause vor dem Atem, Atem, 0,10 s Ausklang] + [0,10 s vor dem „aaah“, „aaah“, Ausklang bis in
    die Pause] + [Stille vom Dateiende]. Jede Naht ist eine Überblendung gleicher Leistung (sin/cos, 40 ms) und muss
    in der Stille liegen (beide Seiten ≤ −38 dB unter dem Höchstwert, 20-ms-Pegel); sonst entfällt der Versuch.
    Gibt (ok, Info) zurück und schreibt <UMGESTELLT id>.wav/.json nach ROH."""
    import librosa
    import numpy as np
    import soundfile as sf
    from scipy import signal
    ziel = os.path.join(ROH, UMGESTELLT["id"] + ".wav")
    if os.path.exists(ziel) and not force:
        return True, json.load(open(os.path.join(ROH, UMGESTELLT["id"] + ".json"), encoding="utf-8"))["umstellen"]
    raw, sr = sf.read(os.path.join(ROH, UMGESTELLT["quelle"] + ".wav"), dtype="float32")
    x = raw.astype(np.float64)
    xl = signal.sosfilt(signal.butter(2, 90.0, "high", fs=FS, output="sos"), x - x.mean())
    env = m.envelope_db(xl, 10.0)
    top = float(env.max())
    st = [(a, b) for a, b in laute_strecken(env, top - 42.0, 0.03, 0.15) if b - a >= int(0.3 * FS)]
    info = {"quelle": UMGESTELLT["quelle"], "strecken_s": [(round(a / FS, 3), round(b / FS, 3)) for a, b in st]}

    def stimmhaft(a, b):
        y = librosa.resample(x[a:b].astype(np.float32), orig_sr=FS, target_sr=16000)
        f0, _vf, vp = librosa.pyin(y, fmin=65, fmax=800, sr=16000, frame_length=1024, hop_length=160)
        return float(np.mean((vp >= 0.4) & np.isfinite(f0)))

    def nein(grund):
        info["ok"], info["grund"] = False, grund
        if os.path.exists(ziel):
            os.remove(ziel)
        return False, info
    if len(st) != 2:
        return nein(f"{len(st)} statt 2 Strecken (Stimme, Atem)")
    (va, vb), (ba, bb) = st
    info["stimmhaft_erste"], info["stimmhaft_zweite"] = round(stimmhaft(va, vb), 2), round(stimmhaft(ba, bb), 2)
    pause = env[vb:ba]
    info["pause_s"] = round((ba - vb) / FS, 3)
    info["pause_pegel_db"] = round(float(np.median(pause) - top), 1) if len(pause) else None
    if info["stimmhaft_erste"] < 0.5 or info["stimmhaft_zweite"] > 0.1:
        return nein("erste Strecke nicht stimmhaft oder zweite nicht gehaucht")
    if ba - vb < int(0.15 * FS) or info["pause_pegel_db"] > -40:
        return nein("keine klare Pause zwischen „aaah“ und Atem")
    halt = int(0.10 * FS)
    blende = int(0.04 * FS)
    p_vor_atem = max(vb + blende, ba - halt)                 # in der Pause, kurz vor dem Atem
    atem_ende = min(len(x), bb + halt)                      # Atem mit 0,10 s Ausklang
    stimme_an = max(0, va - halt)                           # 0,10 s vor dem „aaah“ (gehauchter Einsatz bleibt)
    stimme_aus = min(ba - halt, vb + int(0.2 * FS))         # Ausklang bis in die Pause
    ruhe = laute_strecken(env, top - 45.0, 0.0, 0.0)
    ruhe_ab = max(atem_ende, ruhe[-1][1] + int(0.05 * FS)) if ruhe else atem_ende
    teile = [x[p_vor_atem:atem_ende], x[stimme_an:stimme_aus], x[ruhe_ab:]]
    u = np.linspace(0, np.pi / 2, blende)
    aus_k, ein_k = np.cos(u), np.sin(u)
    naehte = []

    def pegel(seg):
        return float(10 * np.log10(np.mean(np.square(seg)) + 1e-20) - top)
    y = teile[0]
    for nxt in teile[1:]:
        if len(nxt) < blende:
            break
        links, rechts = y[-blende:], nxt[:blende]
        naehte.append({"bei_s": round((len(y) - blende) / FS, 3), "links_db": round(pegel(links), 1),
                      "rechts_db": round(pegel(rechts), 1)})
        y = np.concatenate([y[:-blende], links * aus_k + rechts * ein_k, nxt[blende:]])
    info.update({"naehte": naehte, "schnitte_s": {"atem_von": round(p_vor_atem / FS, 3), "atem_bis": round(atem_ende / FS, 3),
                                                 "stimme_von": round(stimme_an / FS, 3), "stimme_bis": round(stimme_aus / FS, 3),
                                                 "stille_ab": round(ruhe_ab / FS, 3)},
                 "neue_pause_s": round(((atem_ende - bb) + (va - stimme_an)) / FS, 3)})
    laut = [n for n in naehte if max(n["links_db"], n["rechts_db"]) > -38.0]
    if laut:
        return nein(f"Naht nicht in der Stille ({laut[0]['links_db']}/{laut[0]['rechts_db']} dB)")
    info["ok"] = True
    sf.write(ziel, y.astype(np.float32), FS, subtype="FLOAT")
    q = json.load(open(os.path.join(ROH, UMGESTELLT["quelle"] + ".json"), encoding="utf-8"))
    meta = dict(q, id=UMGESTELLT["id"], ton="gaehnen3", variante="umgestellt", umstellen=info,
                erzeugt=time.strftime("%Y-%m-%d %H:%M:%S"))
    json.dump(meta, open(os.path.join(ROH, UMGESTELLT["id"] + ".json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return True, info


# ---------------------------------------------------------------------------------------------------------------
# Nachbearbeitung (moss-sfx-Umgebung, ohne GPU)
# ---------------------------------------------------------------------------------------------------------------
def leitplanke(x, start, end, ein, aus, lufs, max_gr):
    """Tiefpass (vor- und rückwärts) mit der höchsten Grenzfrequenz 6000 → 3500 Hz, bei der der fertige Ton über 6 kHz
    höchstens −30 dB hat; dann Ein-/Ausblenden, Pegel, Begrenzer (make_sfx_moss.finish)."""
    import numpy as np
    from scipy import signal
    m.FADE_IN_S = ein
    cfg = {"ausblenden": aus}
    ohne = round(float(m.band_share_db(x[start:end], 6000.0)), 1)
    y, li, share, fc = None, None, 0.0, 6000.0
    for fc in np.arange(6000.0, 3500.0 - 1e-6, -50.0):
        xf = signal.sosfiltfilt(signal.butter(4, float(fc), "low", fs=FS, output="sos"), x)
        seg = xf[start:end]
        if m.band_share_db(seg, 6000.0) > LEITPLANKE_DB - 0.3 and fc > 3500.0:
            continue
        y, li = m.finish(seg, cfg, lufs, max_gr)
        share = m.band_share_db(y, 6000.0)
        if share <= LEITPLANKE_DB:
            break
    li.update({"tiefpass_hz": float(fc), "leitplanke_ok": bool(share <= LEITPLANKE_DB),
               "ueber_6k_ohne_tiefpass_db": ohne, "einblenden_s": ein, "ausblenden_s": aus})
    return y, li


def kodieren(wav, ogg):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-map_metadata", "-1", "-ac", "1", "-ar", str(FS),
                    "-fflags", "+bitexact", "-flags:a", "+bitexact", "-c:a", "libvorbis", "-q:a", "6", ogg], check=True)


def bearbeiten(cs):
    import numpy as np
    import soundfile as sf
    from scipy import signal
    os.makedirs(TMP, exist_ok=True)
    res = []
    for c in cs:
        p = os.path.join(ROH, c["id"] + ".wav")
        if not os.path.exists(p):
            print("  fehlt:", c["id"], flush=True)
            continue
        t = ton_fuer(c)
        raw, sr = sf.read(p, dtype="float32")
        assert sr == FS
        mr = m.measure_raw(raw)
        r = {"roh": c["id"], "ton": c["ton"], "variante": c["variante"], "prompt": c["prompt"],
             "prompt_notiz": c["prompt_notiz"], "seed": c["seed"], "sekunden_prompt": c["sekunden"],
             "roh_spitze_dbfs": mr["spitze_dbfs"], "roh_leer": mr["leer"], "roh_leise": mr["leise"]}
        if "ziel" in c:
            r["ziel"] = list(c["ziel"])
        if "kategorie" in c:
            r["kategorie"] = c["kategorie"]
        if "steigt_ht" in c:
            r["steigt_min_ht"] = c["steigt_ht"]
        if c.get("negativ"):
            r["negativ"] = c["negativ"]
        if c.get("cfg", m.CFG) != m.CFG:
            r["cfg"] = c["cfg"]
        if c.get("umgestellt"):
            r["umgestellt"] = json.load(open(os.path.join(ROH, c["id"] + ".json"), encoding="utf-8"))["umstellen"]
        if mr["leer"]:
            r["fehler"] = "Original leer"
            res.append(r)
            continue
        x = raw.astype(np.float64) - float(np.mean(raw))
        x = signal.sosfilt(signal.butter(2, t["hochpass"], "high", fs=FS, output="sos"), x)
        xl = signal.sosfilt(signal.butter(4, m.LOWPASS_HZ, "low", fs=FS, output="sos"), x)
        ein, aus = t["einblenden"], t["ausblenden"]
        if t["modus"] == "wecker":
            cut = wecker_schnitt(xl)
            if cut is None:
                r["fehler"] = "kein Klingeln gefunden"
                res.append(r)
                print("  ", c["id"], r["fehler"], flush=True)
                continue
            start, end, ein, aus, info = cut
            x, info["ticken_angehoben_db"] = ticken_anheben(x, info)
            info["natuerliche_dauer_s"] = round((end - start) / FS, 3)
            info["gekuerzt"] = bool(info.get("klingeln_ausgeblendet") or info.get("ticken_vorn_gekuerzt_s"))
        elif t["modus"] == "einatmen":
            start, end, info = gaehnen_schnitt(xl, t)
        else:
            start, end, info = m.find_event(xl, t)
        y, li = leitplanke(x, start, end, ein, aus, t["lufs"], t["begrenzer"])
        info.update(li)
        y = np.concatenate([y, np.zeros(int(m.TAIL_S * FS))])
        rid = c["id"]
        wav = os.path.join(TMP, rid + ".wav")
        sf.write(wav, y.astype("float32"), FS, subtype="PCM_24")
        kodieren(wav, os.path.join(TMP, rid + ".ogg"))
        zd = m.decode(os.path.join(TMP, rid + ".ogg"))
        sim = s.handy_modell(zd)
        r.update({"dauer_s": round(len(zd) / FS, 2), "lufs": round(float(m.momentary_max_lufs(zd)), 1),
                  "ziel_lufs": t["lufs"], "spitze_dbtp": round(float(m.true_peak_db(zd)), 1),
                  "begrenzer_db": info.get("begrenzer_db"), "tiefpass_hz": info["tiefpass_hz"],
                  "leitplanke_ok": info["leitplanke_ok"], "ueber_6k_ohne_tiefpass_db": info["ueber_6k_ohne_tiefpass_db"],
                  "ueber_6k_db": round(m.band_share_db(zd, 6000.0), 1), "ueber_10k_db": round(m.band_share_db(zd, 10000.0), 1),
                  "ueber_12k_db": round(m.band_share_db(zd, 12000.0), 1),
                  "mitten_500_4k_db": round(m.band_share_db(zd, 500, 4000), 1), "unter_300_db": round(m.band_share_db(zd, 0, 300), 1),
                  "linien_2_6k": m.narrow_lines(zd, 2000.0, 6000.0), "puls_15_50": puls_15_50(zd),
                  "natuerliche_dauer_s": info.get("natuerliche_dauer_s"), "gekuerzt": info.get("gekuerzt"),
                  "einblenden_s": info["einblenden_s"], "ausblenden_s": info["ausblenden_s"],
                  "sim_lufs": round(float(m.momentary_max_lufs(sim)), 1),
                  "sim_mitten_500_4k_db": round(float(m.band_share_db(sim, 500, 4000)), 1)})
        r["sim_pegelverlust_db"] = round(r["sim_lufs"] - r["lufs"], 1)
        if t["modus"] == "wecker":
            wm = wecker_messen(zd)
            r["wecker"] = wm
            r["wecker_schnitt"] = {k: v for k, v in info.items() if k in ("ticken_vorn_gekuerzt_s", "klingeln_natuerlich_s",
                                                                            "klingeln_ausgeblendet", "start_s", "roh_klingeln_ab_s",
                                                                            "roh_ticken_rel_db", "ticken_angehoben_db")}
        s.handy_probe({"id": rid, "lufs": r["lufs"], "sim_lufs": r["sim_lufs"]}, zd, sim, TMP)
        os.remove(os.path.join(TMP, rid + "_handy.wav"))
        print(f"  {rid}: {r['dauer_s']} s, {r['lufs']} LUFS, TP {r['tiefpass_hz']:.0f} Hz, >6k {r['ueber_6k_db']} dB"
              + (f", Klingeln ab {r['wecker']['klingeln_ab_s']} s" if r.get("wecker") else ""), flush=True)
        res.append(r)
    alt = {}
    if os.path.exists(KAND_JSON):
        alt = {r["roh"]: r for r in json.load(open(KAND_JSON, encoding="utf-8"))}
    alt.update({r["roh"]: r for r in res})
    json.dump(list(alt.values()), open(KAND_JSON, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    return res


# ---------------------------------------------------------------------------------------------------------------
# AudioSet-Prüfung (analyse-Umgebung, CPU)
# ---------------------------------------------------------------------------------------------------------------
def stimme_messen(y, sr=16000):
    """Stimmlage und Verlauf einer Stimme (librosa.pyin, 65–800 Hz, Fenster 64 ms, Schritt 10 ms) über die aktiven
    Rahmen (RMS höchstens 30 dB unter dem Höchstwert). Stimmhaft heißt Stimmwahrscheinlichkeit ≥ 0,4: pyins eigene
    Entscheidung markierte gehauchten Atem mit Resonanzen (um 0,8–2 kHz) als „stimmhaft“ mit F0 500–950 Hz, obwohl die
    Wahrscheinlichkeit dort bei 0,03–0,05 lag (Gegenprobe: Obertonreihe im Spektrum). Anteil stimmhafter Rahmen (Rest =
    Hauchen/Atem), F0-Median und
    10/90-Perzentil, Verlauf (Median der ersten/letzten 5 stimmhaften Rahmen gegen den Gipfel der geglätteten Kurve, in
    Halbtönen), Gipfel-Lage (0 = Anfang, 1 = Ende der stimmhaften Strecke) und das Ende (letzte 0,5 s der aktiven Strecke:
    stimmhafter Anteil und spektraler Schwerpunkt; stimmhaft und dunkel = Summen wie „mm“)."""
    import librosa
    import numpy as np
    from scipy.signal import medfilt
    hop, fl = 160, 1024
    f0, _vf, vp = librosa.pyin(y, fmin=65, fmax=800, sr=sr, frame_length=fl, hop_length=hop)
    rms = librosa.feature.rms(y=y, frame_length=fl, hop_length=hop)[0]
    cen = librosa.feature.spectral_centroid(y=y, sr=sr, n_fft=fl, hop_length=hop)[0]
    n = min(len(f0), len(rms), len(cen))
    f0, vp, rms, cen = f0[:n], vp[:n], rms[:n], cen[:n]
    db = 20 * np.log10(rms + 1e-9)
    akt = db > db.max() - 30
    sth = (vp >= 0.4) & akt & np.isfinite(f0)
    out = {"stimmhaft_anteil": round(float(sth.sum() / max(1, akt.sum())), 2), "schwerpunkt_hz": round(float(np.median(cen[akt])), 0)}
    ai = np.nonzero(akt)[0]
    if len(ai):
        e0 = max(ai[0], ai[-1] - int(0.5 * sr / hop))
        seg = np.arange(e0, ai[-1] + 1)
        seg = seg[akt[seg]]
        out["ende_stimmhaft"] = round(float(sth[seg].mean()), 2)
        out["ende_schwerpunkt_hz"] = round(float(np.median(cen[seg])), 0)
    fv = f0[sth]
    if len(fv) >= 10:
        k = medfilt(fv, 7)
        a, e = float(np.median(fv[:5])), float(np.median(fv[-5:]))
        g = int(np.argmax(k))
        out.update({"f0_median_hz": round(float(np.median(fv)), 0), "f0_p10_hz": round(float(np.percentile(fv, 10)), 0),
                    "f0_p90_hz": round(float(np.percentile(fv, 90)), 0),
                    "anstieg_ht": round(12 * np.log2(k[g] / a), 1), "abfall_ht": round(12 * np.log2(k[g] / e), 1),
                    "gipfel_lage": round(g / max(1, len(k) - 1), 2)})
    return out


# Reihenfolge-Prüfung Gähnen Runde 3 (Grenzen)
RF_HOERBAR_DB = -35.0        # Rahmen gilt als hörbar: RMS (64 ms) höchstens 35 dB unter dem Höchstwert
RF_STIMME_DB = -30.0         # stimmhafte Rahmen zählen nur, wenn höchstens 30 dB unter dem Höchstwert
RF_EINATMEN_S = 0.45         # vorn mindestens so viel hörbarer Atem vor dem stimmhaften Teil (Vorgabe „mindestens ~0,5 s“)
RF_EINATMEN_STIMME = 0.2     # höchstens so viel Stimme im Atem vorn
RF_EINATMEN_PEGEL_DB = -32.0  # lautester Rahmen des Atems vorn mindestens so laut (sonst kaum hörbar)
RF_LAGE = 0.5                # Mitte der stimmhaften Rahmen (Zeit) hinter der Mitte der hörbaren Strecke
RF_FALL_HT = 2.0             # Tonhöhe fällt vom Gipfel zum Ende um mindestens so viele Halbtöne (und mehr als sie steigt)
RF_ENDE_S = 0.3              # Ende = letzte 0,3 s der hörbaren Strecke
RF_ENDE_STIMME = 0.4         # ... höchstens so viel Stimme (gehaucht)
RF_NEUER_ATEM = (0.12, 0.25)  # nach dem stimmhaften Teil: Pause ≥ 0,12 s, danach ≥ 0,25 s hörbar = neuer Atemzug
RF_PAUSE_S = (0.45, 0.8)     # Pause (still) zwischen Atem und „aaah“: ab 0,45 s Hinweis, ab 0,8 s zerfällt es in zwei Laute
RF_LUECKE_S = 0.08           # Unterbrechung im „aaah“: so lange ohne Stimme; ab 2 Unterbrechungen stockend („a-ah-aaah“)


def reihenfolge_messen(y, sr=16000):
    """Reihenfolge eines Gähnens (Runde 3): erst Einatmen (gehaucht, hörbar), dann stimmhaftes „aaah“ mit fallender
    Tonhöhe, gehauchtes Ende. Rahmen 10 ms (pyin 65–800 Hz, Fenster 64 ms; stimmhaft = Stimmwahrscheinlichkeit ≥ 0,4 wie
    stimme_messen und höchstens RF_STIMME_DB unter dem Höchstwert). Stimmhafter Teil = von der ersten bis zur letzten
    Stelle, an der 150 ms lang mindestens 60 % der Rahmen stimmhaft sind. Gemessen: Einatmen (hörbare Rahmen vor dem
    stimmhaften Teil, deren Stimmanteil und lautester Rahmen), Beginn des stimmhaften Teils, Lage (Mitte der stimmhaften
    Rahmen relativ zur hörbaren Strecke), Tonhöhe im stimmhaften Teil (Anfang/Gipfel/Ende, Halbtöne), Ende (letzte 0,3 s)
    und ein neuer Atemzug nach dem stimmhaften Teil (Pause, dann wieder hörbar). Zeiten in s ab Dateianfang."""
    import librosa
    import numpy as np
    from scipy.ndimage import uniform_filter1d
    from scipy.signal import medfilt
    hop, fl = 160, 1024
    f0, _vf, vp = librosa.pyin(y, fmin=65, fmax=800, sr=sr, frame_length=fl, hop_length=hop)
    rms = librosa.feature.rms(y=y, frame_length=fl, hop_length=hop)[0]
    n = min(len(f0), len(rms))
    f0, vp, rms = f0[:n], vp[:n], rms[:n]
    db = 20 * np.log10(rms + 1e-9)
    db -= db.max()
    s = hop / sr
    akt = db > RF_HOERBAR_DB
    sth = (vp >= 0.4) & np.isfinite(f0) & (db > RF_STIMME_DB)
    ai = np.nonzero(akt)[0]
    out = {"dauer_hoerbar_s": round(float((ai[-1] - ai[0] + 1) * s), 2) if len(ai) else 0.0}
    if not len(ai):
        out["fehler"] = "nichts hörbar"
        return out
    a0, a1 = int(ai[0]), int(ai[-1])
    out["hoerbar_ab_s"], out["hoerbar_bis_s"] = round(a0 * s, 2), round(a1 * s, 2)
    sus = np.nonzero(uniform_filter1d(sth.astype(float), 15) >= 0.6)[0]
    if not len(sus):
        out["fehler"] = "kein stimmhafter Teil"
        out["stimmhaft_anteil"] = round(float(sth[a0:a1 + 1].mean()), 2)
        return out
    vi = np.nonzero(sth)[0]
    v0 = int(vi[vi >= sus[0] - 7][0])
    v1 = int(vi[vi <= sus[-1] + 7][-1])
    vor = np.arange(a0, v0)
    out["stimme_ab_s"] = round(v0 * s, 2)
    out["stimme_bis_s"] = round(v1 * s, 2)
    out["einatmen_s"] = round(float(akt[vor].sum() * s), 2) if len(vor) else 0.0
    out["einatmen_stimme"] = round(float(sth[vor][akt[vor]].mean()), 2) if akt[vor].any() else 0.0
    out["einatmen_pegel_db"] = round(float(db[vor].max()), 1) if len(vor) else None
    # längste Pause (nicht hörbar) zwischen Atem und Stimme
    lue = [b - a for a, b in m.quiet_runs(~akt[vor], 1)] if len(vor) else []
    out["pause_vor_stimme_s"] = round(max(lue) * s, 2) if lue else 0.0
    st_t = vi[(vi >= v0) & (vi <= v1)]
    lue_st = [b - a for a, b in m.quiet_runs(~sth[v0:v1 + 1], int(RF_LUECKE_S / s))]
    out["unterbrechungen"] = len(lue_st)
    out["lage"] = round(float((st_t.mean() - a0) / max(1, a1 - a0)), 2)
    out["stimmhaft_anteil"] = round(float(sth[a0:a1 + 1].sum() / max(1, akt[a0:a1 + 1].sum())), 2)
    fv = f0[st_t]
    if len(fv) >= 15:
        k = medfilt(fv, 7)
        q = max(5, len(k) // 10)
        fa, fe = float(np.median(k[:q])), float(np.median(k[-q:]))
        g = int(np.argmax(k))
        out.update({"f0_anfang_hz": round(fa), "f0_gipfel_hz": round(float(k[g])), "f0_ende_hz": round(fe),
                    "steigt_ht": round(float(12 * np.log2(k[g] / fa)), 1), "faellt_ht": round(float(12 * np.log2(k[g] / fe)), 1),
                    "netto_ht": round(float(12 * np.log2(fa / fe)), 1)})
    e0 = max(a0, a1 - int(RF_ENDE_S / s))
    out["ende_stimme"] = round(float(sth[e0:a1 + 1].mean()), 2)
    nach = np.arange(v1 + 1, a1 + 1)
    out["nachlauf_s"] = round(len(nach) * s, 2)
    out["nachlauf_stimme"] = round(float(sth[nach].mean()), 2) if len(nach) else 0.0
    neu = None
    if len(nach):
        pausen = m.quiet_runs(~akt[nach], int(RF_NEUER_ATEM[0] / s))
        for pa, pb in pausen:
            laut = akt[nach][pb:].sum() * s
            if laut >= RF_NEUER_ATEM[1]:
                neu = {"ab_s": round(float((v1 + 1 + pb) * s), 2), "dauer_s": round(float(laut), 2),
                       "pegel_db": round(float(db[nach][pb:].max()), 1)}
                break
        if neu is None and len(nach) * s >= 0.5:
            # ohne Pause, aber der Nachlauf schwillt wieder an (Luftholen direkt hinter dem „aaah“?)
            d = db[nach]
            ref = float(d[:min(len(d), 10)].max())
            j = int(np.argmax(d))
            if j * s >= 0.3 and d[j] > ref + 3.0 and d[j] > RF_HOERBAR_DB + 5:
                neu = {"ab_s": round(float((v1 + 1 + j) * s), 2), "dauer_s": round(float(len(nach) * s - j * s), 2),
                       "pegel_db": round(float(d[j]), 1), "anschwellen_db": round(float(d[j] - ref), 1)}
    out["neuer_atem_am_ende"] = neu
    return out


def reihenfolge_pruefen(rf):
    """Gründe (Ausschluss) aus reihenfolge_messen."""
    if rf.get("fehler"):
        return [f"Reihenfolge: {rf['fehler']}"]
    g = []
    if rf["einatmen_s"] < RF_EINATMEN_S:
        g.append(f"kein hörbares Einatmen vorn (nur {z(rf['einatmen_s'], 2)} s Atem vor der Stimme ab {z(rf['stimme_ab_s'], 2)} s)")
    if rf["einatmen_s"] > 0 and rf["einatmen_stimme"] > RF_EINATMEN_STIMME:
        g.append(f"Anfang schon stimmhaft ({z(100 * rf['einatmen_stimme'], 0)} % Stimme im Atem vorn)")
    if rf["einatmen_s"] >= RF_EINATMEN_S and (rf["einatmen_pegel_db"] if rf["einatmen_pegel_db"] is not None else -99.0) < RF_EINATMEN_PEGEL_DB:
        g.append(f"Einatmen kaum hörbar ({z(rf['einatmen_pegel_db'])} dB unter dem lautesten Teil)")
    if rf["lage"] < RF_LAGE:
        g.append(f"stimmhafter Teil liegt vorn (Mitte bei {z(100 * rf['lage'], 0)} % der Dauer)")
    if "faellt_ht" not in rf:
        g.append("Tonhöhe nicht messbar")
    elif rf["faellt_ht"] < RF_FALL_HT or rf["faellt_ht"] <= rf["steigt_ht"]:
        g.append(f"Tonhöhe fällt nicht (steigt {z(rf['steigt_ht'])}, fällt {z(rf['faellt_ht'])} Halbtöne)")
    if rf["ende_stimme"] > RF_ENDE_STIMME:
        g.append(f"Ende nicht gehaucht ({z(100 * rf['ende_stimme'], 0)} % Stimme in den letzten {z(RF_ENDE_S, 1)} s)")
    if rf.get("unterbrechungen", 0) >= 2:
        g.append(f"„aaah“ stockend ({rf['unterbrechungen']}-mal unterbrochen)")
    if rf["pause_vor_stimme_s"] >= RF_PAUSE_S[1]:
        g.append(f"lange Pause zwischen Einatmen und „aaah“ ({z(rf['pause_vor_stimme_s'], 2)} s): zwei getrennte Laute")
    if rf["neuer_atem_am_ende"]:
        na = rf["neuer_atem_am_ende"]
        g.append(f"Luftholen am Ende (ab {z(na['ab_s'], 2)} s, {z(na['dauer_s'], 2)} s nach dem stimmhaften Teil)")
    return g


def reihenfolge_text(rf, stimme_txt=""):
    """Kurzbeschreibung, z. B. „Frau, 0,8 s Einatmen, dann fallendes aaah, endet gehaucht“."""
    if rf.get("fehler"):
        return rf["fehler"]
    t = [stimme_txt] if stimme_txt else []
    t.append(f"{z(rf['einatmen_s'], 1)} s Einatmen" + (" (sehr leise)" if (rf["einatmen_pegel_db"] if rf["einatmen_pegel_db"] is not None else -99.0) < RF_EINATMEN_PEGEL_DB else ""))
    if rf["pause_vor_stimme_s"] >= 0.15:
        t.append(f"{z(rf['pause_vor_stimme_s'], 1)} s Pause")
    fa = rf.get("faellt_ht", 0.0)
    st = rf.get("steigt_ht", 0.0)
    form = ("steigt erst etwas und fällt dann" if st >= 1.5 and fa > st else "fällt" if fa >= RF_FALL_HT and fa > st
            else "steigt" if st > fa else "bleibt fast gleich")
    dauer = rf["stimme_bis_s"] - rf["stimme_ab_s"]
    t.append(f"dann {z(dauer, 1)} s „aaah“ (Tonhöhe {form}" + (f", {z(fa, 0)} Halbtöne" if fa >= RF_FALL_HT else "") + ")")
    t.append("endet gehaucht" if rf["ende_stimme"] <= RF_ENDE_STIMME else "endet mit Stimme")
    if rf["neuer_atem_am_ende"]:
        t.append("danach noch ein Atemzug")
    return ", ".join(t)


FZ_PERIODE_R = 0.35     # Rahmen gilt als periodisch (Ton/Brummen), wenn die normierte Autokorrelation so hoch ist


def furz_messen(y, sr=16000):
    """Furzkissen: Ablauf und Klang (Messung, nicht gehört), Rahmen 10 ms. Hörbar = RMS (32 ms) höchstens 30 dB unter
    dem Höchstwert. Stöße = hörbare Strecken (Lücken unter 60 ms überbrückt, Strecken unter 30 ms verworfen).
    Tonhöhe: pyin erkennt im rauen Flattern fast nie Stimme (Stimmwahrscheinlichkeit um 0,01); daher normierte
    Autokorrelation je Rahmen (128 ms, Hann, auf die Fensterüberlappung normiert, höchstens 25 dB unter dem Höchstwert),
    stärkster Gipfel bei 40–1600 Hz, bei
    fast gleich hohen Gipfeln (≥ 85 %) der kürzeste Abstand (gegen Oktavfehler); periodisch = Gipfel ≥ FZ_PERIODE_R.
    Verlauf über die periodischen Rahmen (Median über 5): Anfang = Median des ersten Drittels, Schluss = Median des
    letzten Viertels, „schluss_ht“ = Schluss gegen Anfang in Halbtönen (> 0 steigt). Dazu der spektrale Schwerpunkt im
    ersten Drittel und im letzten Viertel der hörbaren Rahmen („hell_ht“, > 0 = wird heller). Knattern: stärkste Linie
    10–60 Hz im Hüllkurvenspektrum des Bands 300 Hz–4 kHz (wie am Handy), Schärfe gegen den Median 4–150 Hz.
    Klangfarbe: Schwerpunkt und Flachheit (Median über die hörbaren Rahmen; Flachheit hoch = Luft/Rauschen)."""
    import librosa
    import numpy as np
    from scipy.signal import butter, hilbert, medfilt, resample_poly, sosfiltfilt
    hop = 160
    s = hop / sr
    rms = librosa.feature.rms(y=y, frame_length=512, hop_length=hop)[0]
    db = 20 * np.log10(rms + 1e-9)
    db -= db.max()
    akt = db > -30.0
    ai = np.nonzero(akt)[0]
    if not len(ai):
        return {"fehler": "nichts hörbar"}
    a0, a1 = int(ai[0]), int(ai[-1])
    out = {"hoerbar_ab_s": round(a0 * s, 2), "hoerbar_s": round((a1 - a0 + 1) * s, 2)}
    st = []
    for a, b in m.quiet_runs(akt, 1):
        if st and a - st[-1][1] < 6:
            st[-1] = (st[-1][0], b)
        else:
            st.append((a, b))
    st = [(a, b) for a, b in st if b - a >= 3]
    out["stoesse"] = len(st)
    out["stoesse_s"] = [(round(a * s, 2), round(b * s, 2)) for a, b in st][:12]
    fl_n, lmin, lmax = 2048, int(sr / 1600), int(sr / 40)     # 128 ms: 40 Hz liegt bei 20 % der Fensterlänge
    yp = np.pad(y, (fl_n // 2, fl_n // 2))
    n = len(db)
    f0 = np.full(n, np.nan)
    rr = np.zeros(n)
    win = np.hanning(fl_n)
    wkorr = np.sum(win ** 2) / np.correlate(win, win, "full")[fl_n - 1:]
    for i in range(n):
        if db[i] <= -25.0:
            continue
        fr = yp[i * hop:i * hop + fl_n]
        if len(fr) < fl_n:
            break
        fr = (fr - fr.mean()) * win
        ac = np.fft.irfft(np.abs(np.fft.rfft(fr, 2 * fl_n)) ** 2)[:fl_n]
        # Normierung auf die Überlappung (sonst fallen lange Abstände ab)
        ac = ac / (ac[0] + 1e-12) * wkorr
        seg = ac[lmin:lmax + 1]
        j = int(np.argmax(seg))
        if seg[j] <= 0:
            continue
        kand = np.nonzero((seg[1:-1] >= 0.85 * seg[j]) & (seg[1:-1] >= seg[:-2]) & (seg[1:-1] >= seg[2:]))[0] + 1
        j = int(kand[0]) if len(kand) else j
        rr[i], f0[i] = float(seg[j]), sr / (lmin + j)
    per = np.isfinite(f0) & (rr >= FZ_PERIODE_R)
    out["periodisch"] = round(float(per[a0:a1 + 1].sum() / max(1, akt[a0:a1 + 1].sum())), 2)
    out["tonhaltig"] = out["periodisch"]
    fv = f0[per]
    if len(fv) >= 8:
        k = medfilt(fv, 5)
        fa, fe = float(np.median(k[:max(3, len(k) // 3)])), float(np.median(k[-max(3, len(k) // 4):]))
        out.update({"f0_median_hz": round(float(np.median(k))), "f0_anfang_hz": round(fa), "f0_schluss_hz": round(fe),
                    "f0_max_hz": round(float(np.percentile(k, 95))), "schluss_ht": round(float(12 * np.log2(fe / fa)), 1),
                    "f0_schluss_zeit_s": round(float(np.nonzero(per)[0][-1] * s), 2)})
    yb = sosfiltfilt(butter(4, [300, 4000], "bandpass", fs=sr, output="sos"), y)
    h = np.abs(hilbert(yb))
    h = sosfiltfilt(butter(4, 150, "low", fs=sr, output="sos"), h)
    h = resample_poly(h, 1, sr // 1000)[int(a0 * s * 1000):int((a1 + 1) * s * 1000)]
    if len(h) >= 150:
        h = h - h.mean()
        nf = 8192
        sp = np.abs(np.fft.rfft(h * np.hanning(len(h)), n=nf))
        fm = np.fft.rfftfreq(nf, 1 / 1000)
        band, ref = (fm >= 10) & (fm <= 60), (fm >= 4) & (fm <= 150)     # darüber ist es die Tonhöhe des Brummens
        i = int(np.argmax(np.where(band, sp, 0)))
        out["knattern_hz"] = round(float(fm[i]))
        out["knattern_schaerfe"] = round(float(sp[i] / (np.median(sp[ref]) + 1e-12)), 1)
    cen = librosa.feature.spectral_centroid(y=y, sr=sr, n_fft=1024, hop_length=hop)[0]
    fl = librosa.feature.spectral_flatness(y=y, n_fft=1024, hop_length=hop)[0]
    k2 = min(len(cen), len(fl), len(akt))
    ca = cen[:k2][akt[:k2]]
    out["schwerpunkt_hz"] = round(float(np.median(ca)))
    out["flachheit"] = round(float(np.median(fl[:k2][akt[:k2]])), 3)
    if len(ca) >= 8:
        out["hell_ht"] = round(float(12 * np.log2(np.median(ca[-max(2, len(ca) // 4):]) / np.median(ca[:max(2, len(ca) // 3)]))), 1)
    return out


def furz_text(fm, dauer):
    """Kurzbeschreibung aus furz_messen (Messung, nicht gehört), z. B. „ein Stoß, 0,8 s, tief (110 Hz), knattert mit
    35 Hz, Tonhöhe steigt zum Schluss um 9 Halbtöne, dumpf“."""
    if fm.get("fehler"):
        return fm["fehler"]
    t = ["ein Stoß" if fm["stoesse"] <= 1 else f"{fm['stoesse']} Stöße", f"{z(dauer, 2)} s"]
    per = fm.get("periodisch", fm.get("tonhaltig", 0.0))
    t.append("rau, kaum fester Ton" if per < 0.3 else "rau mit etwas Ton" if per < 0.6 else "fester, brummender Ton")
    f0 = fm.get("f0_median_hz")
    if f0 is not None and per >= 0.25:
        t.append(("tief" if f0 < 90 else "mittlere Lage" if f0 < 200 else "hoch") + f" (um {f0} Hz)")
    sh = fm.get("schluss_ht")
    if sh is not None:
        t.append(f"Tonhöhe steigt zum Schluss um {z(sh, 0)} Halbtöne" if sh >= 3 else
                 f"Tonhöhe fällt zum Schluss um {z(-sh, 0)} Halbtöne" if sh <= -3 else "Tonhöhe bleibt etwa gleich")
    elif fm.get("hell_ht") is not None and fm["hell_ht"] >= 3:
        t.append(f"wird zum Schluss heller ({z(fm['hell_ht'], 0)} Halbtöne)")
    if fm.get("knattern_schaerfe", 0) >= 4:
        t.append(f"knattert mit etwa {fm['knattern_hz']} Hz")
    sp = fm["schwerpunkt_hz"]
    t.append("dumpf" if sp < 900 else "mittelhell" if sp < 1800 else "schnarrend")
    if fm["flachheit"] >= 0.15:
        t.append("luftig")
    return ", ".join(t)


# Zunge rausstrecken (Grenzen, siehe bewerten)
BAEH_LUECKE_S = 0.12         # Laute: Lücken darunter überbrückt (Flattern, kurze Einbrüche); darüber zwei Laute
BAEH_LAUT_DB = -20.0         # ein Laut zählt nur, wenn sein lautester Rahmen höchstens so weit unter dem Höchstwert liegt
BAEH_STIMME_MIN = 0.3        # Arten außer „prusten“: mindestens so viel Stimme (sonst nur Luft/Hauchen)
BAEH_FLATTERN_HZ = (20, 80)  # Flattern: Rate der Zunge/Lippen (Hz); darunter liegen Silbenfolgen wie beim Lachen
BAEH_FLATTERN_R = 0.4        # ein 200-ms-Fenster flattert, wenn die Autokorrelation der Hüllkurve dort so hoch ist
BAEH_FLATTERN_ANTEIL = 0.25  # Art „prusten“: mindestens dieser Anteil der hörbaren Fenster flattert
BAEH_HELL_HZ = 280.0         # Art „hell“: Grundton im Mittel mindestens so hoch
BAEH_ZITTERN = (6.0, 2.0, 0.4)  # Meckern: Schärfe der Linie 4,5–12 Hz ≥ 6 und Tiefe (Std. 4–12 Hz) ≥ 2 dB bzw. ≥ 0,4 Halbtöne


def baeh_messen(y, sr=16000):
    """Zunge rausstrecken: Ablauf und Klang (Messung, nicht gehört), Rahmen 10 ms. Stimme wie stimme_messen (Anteil,
    Grundton, Verlauf). Laute = hörbare Strecken (RMS 32 ms höchstens 30 dB unter dem Höchstwert), Lücken unter
    BAEH_LUECKE_S überbrückt, kürzer als 60 ms oder leiser als BAEH_LAUT_DB verworfen. Flattern (Zunge/Lippen):
    Hüllkurve des Bands 300 Hz–4 kHz (Tiefpass 100 Hz, 8. Ordnung, damit der Grundton einer Stimme kaum durchkommt),
    je 200-ms-Fenster die Periodizität bei 20–80 Hz (siehe unten); Anteil der flatternden Fenster, ihre Rate (Median)
    und das 75. Perzentil der Periodizität. Zittern (Meckern wie Schaf oder Ziege, ein
    regelmäßiges Beben): im Kern des längsten Lauts (siehe unten) Pegel (dB, 10 ms) und Tonhöhe (Halbtöne, längste
    stimmhafte Strecke) gegen ihren gleitenden Median (250 ms), stärkste Linie 4,5–12 Hz mit Schärfe gegen den Median
    1–25 Hz (nur bei mindestens 2,5 Schwingungen im Kern), Tiefe = Standardabweichung nach Bandpass 4–12 Hz."""
    import librosa
    import numpy as np
    from scipy.signal import butter, hilbert, medfilt, resample_poly, sosfiltfilt
    out = stimme_messen(y, sr)
    hop = 160
    s = hop / sr
    rms = librosa.feature.rms(y=y, frame_length=512, hop_length=hop)[0]
    db = 20 * np.log10(rms + 1e-9)
    db -= db.max()
    akt = db > -30.0
    ai = np.nonzero(akt)[0]
    if not len(ai):
        out["fehler"] = "nichts hörbar"
        return out
    a0, a1 = int(ai[0]), int(ai[-1])
    out["hoerbar_ab_s"], out["hoerbar_s"] = round(a0 * s, 2), round((a1 - a0 + 1) * s, 2)
    st = []
    for a, b in m.quiet_runs(akt, 1):
        if st and a - st[-1][1] < int(BAEH_LUECKE_S / s):
            st[-1] = (st[-1][0], b)
        else:
            st.append((a, b))
    st = [(a, b) for a, b in st if b - a >= 6 and db[a:b].max() > BAEH_LAUT_DB]
    out["laute"] = len(st)
    out["laute_s"] = [(round(a * s, 2), round(b * s, 2)) for a, b in st][:8]

    def linie(sig, fs, lo, hi, ref):
        sig = sig - np.mean(sig)
        nf = 8192
        sp = np.abs(np.fft.rfft(sig * np.hanning(len(sig)), n=nf))
        fm = np.fft.rfftfreq(nf, 1 / fs)
        band, rb = (fm >= lo) & (fm <= hi), (fm >= ref[0]) & (fm <= ref[1])
        i = int(np.argmax(np.where(band, sp, 0)))
        return float(fm[i]), float(sp[i] / (np.median(sp[rb]) + 1e-12))
    yb = sosfiltfilt(butter(4, [300, 4000], "bandpass", fs=sr, output="sos"), y)
    h = np.abs(hilbert(yb))
    h = sosfiltfilt(butter(8, 100, "low", fs=sr, output="sos"), h)     # Grundton einer Stimme kaum durchlassen
    h = resample_poly(h, 1, sr // 1000)[int(a0 * s * 1000):int((a1 + 1) * s * 1000)]
    if len(h) >= 200:
        # je 200-ms-Fenster (Schritt 50 ms, nur Fenster im hörbaren Teil) die normierte Autokorrelation der
        # Hüllkurve (Hochpass 12 Hz, auf die Überlappung bezogen), höchstes lokales Maximum bei Abständen 1/80–1/20 s;
        # Fenster mit r ≥ BAEH_FLATTERN_R flattern. Ein Spektrum taugt hier nicht: die Hüllkurve hat unten am meisten
        # Energie, die stärkste Linie lag sonst fast immer am unteren Bandrand.
        h = sosfiltfilt(butter(2, 12, "high", fs=1000, output="sos"), h - h.mean())
        dbk = np.repeat(db, int(round(s * 1000)))[a0 * int(round(s * 1000)):][:len(h)]
        lo, hi = int(1000 / BAEH_FLATTERN_HZ[1]), int(1000 / BAEH_FLATTERN_HZ[0])
        fen = []
        for i0 in range(0, len(h) - 200 + 1, 50):
            if np.median(dbk[i0:i0 + 200]) < -25.0:
                continue
            f = h[i0:i0 + 200]
            ac = np.correlate(f, f, "full")[199:]
            ac = ac / (ac[0] + 1e-12) * 200.0 / (200.0 - np.arange(200))
            seg = ac[lo:hi + 1]
            k = np.nonzero((seg[1:-1] > seg[:-2]) & (seg[1:-1] >= seg[2:]))[0] + 1
            j = int(k[np.argmax(seg[k])]) if len(k) else None
            fen.append((float(seg[j]), 1000.0 / (lo + j)) if j is not None else (0.0, 0.0))
        if fen:
            ok = [hz for r_, hz in fen if r_ >= BAEH_FLATTERN_R]
            out["flattern_anteil"] = round(len(ok) / len(fen), 2)
            out["flattern_r"] = round(float(np.percentile([r_ for r_, _ in fen], 75)), 2)
            out["flattern_hz"] = round(float(np.median(ok))) if ok else None
    if st:
        # Kern = längste Strecke des längsten Lauts, die höchstens 20 dB unter dem Höchstwert liegt, ohne je 50 ms am Rand
        # (Einsatz und Ausklingen sind kein Zittern); Pegel und Tonhöhe dort mit 4–12 Hz bandgefiltert (vor/rückwärts)
        a, b = max(st, key=lambda ab: ab[1] - ab[0])
        kern = [(ka, kb) for ka, kb in m.quiet_runs(db[a:b] > -20.0, 1)]
        ka, kb = max(kern, key=lambda ab: ab[1] - ab[0]) if kern else (0, 0)
        ka, kb = a + ka + 5, a + kb - 5
        out["kern_s"] = round(max(0, kb - ka) * s, 2)
        bp = butter(2, [4.0, 12.0], "bandpass", fs=1 / s, output="sos")
        if kb - ka >= 30:
            d = db[ka:kb]
            hz, sch = linie(d - medfilt(d, 25), 1 / s, 4.5, 12, (1, 25))
            # mindestens 2,5 Schwingungen im Kern, sonst ist es eher die Form des Lauts
            if (kb - ka) * s * hz >= 2.5:
                out.update({"zittern_pegel_hz": round(hz, 1), "zittern_pegel_schaerfe": round(sch, 1),
                            "zittern_pegel_db": round(float(np.std(sosfiltfilt(bp, d))), 1)})
        f0, _vf, vp = librosa.pyin(y, fmin=65, fmax=800, sr=sr, frame_length=1024, hop_length=hop)
        n = min(len(f0), len(db))
        sth = (vp[:n] >= 0.4) & np.isfinite(f0[:n]) & (db[:n] > -30.0)
        runs = m.quiet_runs(sth[ka:min(kb, n)], 1) if kb > ka else []
        va, vb = max(runs, key=lambda ab: ab[1] - ab[0]) if runs else (0, 0)
        if vb - va >= 30:
            ht = 12 * np.log2(f0[ka + va:ka + vb] / 100.0)
            hz, sch = linie(ht - medfilt(ht, 25), 1 / s, 4.5, 12, (1, 25))
            if (vb - va) * s * hz >= 2.5:
                out.update({"zittern_ton_hz": round(hz, 1), "zittern_ton_schaerfe": round(sch, 1),
                            "zittern_ton_ht": round(float(np.std(sosfiltfilt(bp, ht))), 2)})
    zp = out.get("zittern_pegel_schaerfe", 0) >= BAEH_ZITTERN[0] and out.get("zittern_pegel_db", 0) >= BAEH_ZITTERN[1]
    zt = out.get("zittern_ton_schaerfe", 0) >= BAEH_ZITTERN[0] and out.get("zittern_ton_ht", 0) >= BAEH_ZITTERN[2]
    out["meckert"] = bool(zp or zt)
    return out


def baeh_text(bm, dauer):
    """Kurzbeschreibung aus baeh_messen (Messung, nicht gehört), z. B. „ein Laut, 0,8 s, helle Kinderstimme (um 350 Hz),
    überwiegend Stimme, Tonhöhe fällt zum Ende um 5 Halbtöne, mit Zungen-Flattern (etwa 30 Hz)“."""
    if bm.get("fehler"):
        return bm["fehler"]
    t = ["ein Laut" if bm["laute"] <= 1 else f"{bm['laute']} getrennte Laute", f"{z(dauer, 2)} s"]
    f0, sa = bm.get("f0_median_hz"), bm["stimmhaft_anteil"]
    if f0 is None or sa < 0.15:
        t.append("fast nur Luft, kaum Stimme")
    else:
        lage = ("sehr hohe Comic-/Kinderstimme" if f0 >= 380 else "helle Kinderstimme" if f0 >= BAEH_HELL_HZ
                else "helle Stimme" if f0 >= 200 else "mittlere Stimme" if f0 >= 130 else "tiefe Stimme")
        t.append(f"{lage} (um {z(f0, 0)} Hz)")
        t.append("überwiegend Luft/Prusten" if sa < 0.3 else "halb Stimme, halb Luft" if sa < 0.6 else "überwiegend Stimme")
        an, ab = bm.get("anstieg_ht", 0.0), bm.get("abfall_ht", 0.0)
        t.append(f"Tonhöhe steigt um {z(an, 0)} und fällt um {z(ab, 0)} Halbtöne" if an >= 2 and ab >= 2 else
                 f"Tonhöhe steigt um {z(an, 0)} Halbtöne" if an >= 2 else
                 f"Tonhöhe fällt zum Ende um {z(ab, 0)} Halbtöne" if ab >= 2 else "Tonhöhe fast gleich")
    if bm.get("flattern_anteil", 0) >= BAEH_FLATTERN_ANTEIL and bm.get("flattern_hz"):
        t.append(f"mit Zungen-/Lippenflattern (etwa {bm['flattern_hz']} Hz, {z(100 * bm.get('flattern_anteil', 0), 0)} % der Dauer)")
    if bm.get("meckert"):
        t.append("zittert regelmäßig (Meckern?)")
    sp = bm.get("schwerpunkt_hz", 0)
    t.append("dumpf" if sp < 900 else "näselnd-hell" if sp < 2200 else "scharf")
    return ", ".join(t)


def ast_lauf(nur=None):
    os.environ["HF_HUB_OFFLINE"] = "1"
    import librosa
    import numpy as np
    import torch
    from transformers import ASTFeatureExtractor, ASTForAudioClassification
    fe = ASTFeatureExtractor.from_pretrained(AST_MODEL)
    model = ASTForAudioClassification.from_pretrained(AST_MODEL).eval()
    labels = model.config.id2label
    idx = {v: int(k) for k, v in labels.items()}
    watch = set(SPRACHE + KATZE + WARN)
    for t in TOENE.values():
        watch |= set(t["erwartet"]) | set(t.get("erwartet_ticken", [])) | set(t.get("erwartet_klingeln", []))
        watch |= set(t.get("meiden", {})) | set(t.get("beobachten", [])) | set(t.get("mensch", []))
    keys = [k.strip() for k in nur.split(",")] if nur else None

    def tag(y):
        inp = fe(y, sampling_rate=16000, return_tensors="pt")
        with torch.no_grad():
            p = torch.sigmoid(model(**inp).logits)[0].numpy()
        top = np.argsort(p)[::-1][:8]
        return {"top": [(labels[int(i)], round(float(p[i]), 3)) for i in top],
                "werte": {k: round(float(p[idx[k]]), 3) for k in sorted(watch) if k in idx}}
    kand = json.load(open(KAND_JSON, encoding="utf-8"))
    res = json.load(open(AST_JSON, encoding="utf-8")) if os.path.exists(AST_JSON) else {}
    for r in kand:
        wav = os.path.join(TMP, r["roh"] + ".wav")
        if r.get("fehler") or not os.path.exists(wav) or (keys and r["ton"] not in keys):
            continue
        y, _ = librosa.load(wav, sr=16000, mono=True)
        e = tag(y)
        if TOENE[r["ton"]].get("tonhoehe"):
            e["stimme"] = stimme_messen(y)
        if TOENE[r["ton"]].get("reihenfolge"):
            e["reihenfolge"] = reihenfolge_messen(y)
        if TOENE[r["ton"]].get("furz"):
            e["furz"] = furz_messen(y)
        if TOENE[r["ton"]].get("baeh"):
            e["baeh"] = baeh_messen(y)
        wm = r.get("wecker")
        if wm:
            t0 = int(wm["klingeln_ab_s"] * 16000)
            e["ticken"] = tag(y[:max(t0, 1600)])
            e["klingeln"] = tag(y[t0:])
        res[r["roh"]] = e
        print(r["roh"], e["top"][:4], flush=True)
    json.dump(res, open(AST_JSON, "w", encoding="utf-8"), indent=1, ensure_ascii=False)


# ---------------------------------------------------------------------------------------------------------------
# Auswahl und Hörseite
# ---------------------------------------------------------------------------------------------------------------
def z(v, nk=1):
    return f"{v:.{nk}f}".replace(".", ",").replace("-", "−")


def bewerten(r, a):
    """Punkte (Empfehlung, keine Ohren), Ausschlussgründe und Hinweise."""
    t = TOENE[r["ton"]]
    w = a.get("werte", {}) if a else {}
    erw_k = max(t["erwartet"], key=lambda k: w.get(k, 0.0))
    erw = w.get(erw_k, 0.0)
    spr_k = max(SPRACHE, key=lambda k: w.get(k, 0.0))
    spr = w.get(spr_k, 0.0)
    kat_k = max(KATZE, key=lambda k: w.get(k, 0.0))
    kat = w.get(kat_k, 0.0)
    gruende, hinweise = [], []
    if not a:
        hinweise.append("ohne AudioSet-Prüfung")
    if kat > 0.10:
        gruende.append(f"katzenähnlich (AudioSet „{kat_k}“ {z(kat, 2)})")
    elif kat > 0.04:
        hinweise.append(f"leichter Katzen-Verdacht (AudioSet „{kat_k}“ {z(kat, 2)})")
    if w.get("Hiss", 0) > 0.25:
        hinweise.append(f"Zischen? (AudioSet „Hiss“ {z(w['Hiss'], 2)})")
    meiden = t.get("meiden", {})
    meiden_summe = 0.0
    for k, g in meiden.items():
        v = w.get(k, 0.0)
        meiden_summe += v
        if v > g:
            gruende.append(f"klingt nach „{k}“ (AudioSet {z(v, 2)}, Grenze {z(g, 2)})")
        elif v > g / 2:
            hinweise.append(f"etwas „{k}“ (AudioSet {z(v, 2)})")
    teile = [w] + [(a or {}).get(p, {}).get("werte", {}) for p in ("ticken", "klingeln")]
    for k in ("Squeal", "Squeak", "Whistle", "Beep, bleep", "Animal", "Frog", "Roar", "Growling", "Screaming"):
        if k in meiden or k in t["erwartet"]:
            continue
        v = max(tw.get(k, 0.0) for tw in teile)
        if v > 0.15:
            hinweise.append(f"AudioSet „{k}“ {z(v, 2)}: auf Quietschen/Piepen/Tierähnliches achten")
    knall = max(w.get(k, 0.0) for k in ("Explosion", "Gunshot, gunfire", "Bang"))
    if knall > 0.15:
        hinweise.append(f"AudioSet hört eher einen Knall (Explosion/Bang {z(knall, 2)}): zu hart?")
    grenze = t.get("sprache_grenze") or ((0.6, 0.35) if t["stimme"] else (0.4, 0.2))
    if spr > grenze[0]:
        gruende.append(f"Sprache? (AudioSet „{spr_k}“ {z(spr, 2)})")
    elif spr > grenze[1]:
        hinweise.append(f"etwas Sprache-Verdacht (AudioSet „{spr_k}“ {z(spr, 2)}), auf Wörter achten")
    if not r["leitplanke_ok"]:
        gruende.append(f"Katzen-Leitplanke verfehlt (über 6 kHz {z(r['ueber_6k_db'])} dB)")
    pu = r.get("puls_15_50")
    puls = bool(pu and pu["hz"] >= 17 and pu["schaerfe"] >= 10)
    if puls:
        msg = f"Hüllkurve pulsiert mit {z(pu['hz'], 0)} Hz (Schnurr-Bereich 15–50 Hz, Schärfe {z(pu['schaerfe'])})"
        if (r["ton"] == "schnarchen" or t.get("puls_purr")) and w.get("Purr", 0) > 0.03:
            gruende.append(msg + " und AudioSet „Purr“ " + z(w["Purr"], 2))
        else:
            hinweise.append(msg)
    if r["linien_2_6k"]:
        hz, prom, _rel = r["linien_2_6k"][0]
        if prom >= 20 and not t.get("glocke"):
            gruende.append(f"Katzen-Leitplanke: schmale Linie bei {hz} Hz (+{z(prom)} dB über der Umgebung), Piepen")
        else:
            hinweise.append(f"schmale Linie bei {hz} Hz (+{z(prom)} dB über der Umgebung): auf Piepen achten"
                            + (" (bei einer Glocke zu erwarten)" if t.get("glocke") else ""))
    lo, hi = r.get("ziel") or t["ziel"]
    d = r["dauer_s"] - m.TAIL_S
    if d < 0.75 * lo:
        gruende.append(f"zu kurz ({z(d, 2)} s)")
    elif d < lo and t.get("streng"):
        gruende.append(f"kürzer als das Ziel ({z(d, 2)} s statt {z(lo, 2)}–{z(hi, 2)} s)")
    elif d < lo:
        hinweise.append(f"etwas kürzer als das Ziel ({z(d, 2)} s)")
    gekuerzt = bool(r.get("gekuerzt") and t["modus"] != "wecker" and (r.get("natuerliche_dauer_s") or 0) > d + 0.1)
    if gekuerzt:
        hinweise.append(f"natürlich {z(r['natuerliche_dauer_s'], 1)} s, auf {z(d, 2)} s gekürzt und ausgeblendet")
    if a and t.get("erwartet_mindestens") and erw < t["erwartet_mindestens"]:
        gruende.append(f"AudioSet erkennt keine der erwarteten Klassen ({', '.join(t['erwartet'])}; höchstens {z(erw, 2)})")
    elif a and erw < 0.05:
        hinweise.append("AudioSet erkennt keine der erwarteten Klassen")
    if r["roh_leise"]:
        hinweise.append("Original sehr leise")
    defizit = r.get("ziel_lufs", t["lufs"]) - r["lufs"]
    if defizit > 4:
        hinweise.append(f"nur {z(r['lufs'])} LUFS statt {z(r.get('ziel_lufs', t['lufs']))}: sehr kurzer, spitzer Schlag, die Spitzengrenze (−1 dBTP) hält ihn leiser")
    # Furzkissen: Flattern liegt von Natur aus im Puls-Bereich (nur Hinweis, Ausschluss nur mit AudioSet „Purr“)
    punkte = (4.0 * erw - 2.0 * knall - 20.0 * kat - (0.0 if t.get("puls_purr") else 1.5) * puls
              - 0.5 * bool(r["linien_2_6k"]) - 0.05 * abs(r["sim_pegelverlust_db"]))
    punkte -= 2.0 * max(0.0, spr - 0.2) if t["stimme"] else 3.0 * spr
    punkte -= 2.0 * (d < lo) + 1.0 * gekuerzt + 0.3 * max(0.0, defizit - 2.0)
    if t.get("atem_summe"):
        atem = sum(w.get(k, 0.0) for k in t["erwartet"])
        punkte += 2.0 * atem
        r["ast_atem_summe"] = round(atem, 3)
        if a and atem < t.get("atem_mindestens", 0.0):
            gruende.append(f"AudioSet hört kaum Atmen/Seufzen (Atemklassen zusammen {z(atem, 2)})")
    if meiden:
        punkte -= 6.0 * meiden_summe
        r["ast_meiden"] = {k: round(w.get(k, 0.0), 3) for k in meiden}
    if t.get("furz"):
        punkte += 2.0 * w.get("Fart", 0.0)          # das eigentliche Ziel; Quietschen allein ist kein Furzkissen
        r["ast_beobachtet"] = {k: round(w[k], 3) for k in t.get("beobachten", []) + t["erwartet"]
                                 if k != erw_k and w.get(k, 0.0) >= 0.05}
        fm = (a or {}).get("furz")
        if fm is None:
            gruende.append("ohne Furzkissen-Messung")
        else:
            r["furz"] = fm
            sh = fm.get("schluss_ht")
            if r.get("steigt_min_ht") is not None:
                if sh is None and (fm.get("hell_ht") or 0.0) >= r["steigt_min_ht"]:
                    hinweise.append(f"Tonhöhe nicht messbar, wird zum Schluss aber heller ({z(fm['hell_ht'])} Halbtöne)")
                elif sh is None:
                    gruende.append("Tonhöhe nicht messbar (soll zum Schluss steigen)")
                elif sh < r["steigt_min_ht"]:
                    gruende.append(f"Tonhöhe steigt zum Schluss nicht (Schluss gegen Anfang {z(sh)} Halbtöne)")
                else:
                    punkte += 0.1 * min(sh, 24.0)        # der Anstieg macht diese Art aus: deutlicher = besser
            if r.get("kategorie") == "lang" and fm.get("stoesse", 1) > 2:
                hinweise.append(f"{fm['stoesse']} getrennte Stöße statt eines langen Flatterns")
                punkte -= 0.5
            if fm.get("flachheit", 0.0) >= 0.15 and r.get("kategorie") != "pfft":
                hinweise.append(f"viel Luft/Rauschen (Flachheit {z(fm['flachheit'], 2)})")
    if t.get("baeh"):
        r["ast_beobachtet"] = {k: round(w[k], 3) for k in t.get("beobachten", []) + t["erwartet"]
                               if k != erw_k and w.get(k, 0.0) >= 0.05}
        bm = (a or {}).get("baeh")
        art = r.get("kategorie")
        if bm is None:
            gruende.append("ohne Bäh-Messung")
        elif bm.get("fehler"):
            gruende.append(f"Bäh-Messung: {bm['fehler']}")
        else:
            r["baeh"] = bm
            sa, f0 = bm["stimmhaft_anteil"], bm.get("f0_median_hz")
            mk = max(t["mensch"], key=lambda k: w.get(k, 0.0))
            r["ast_mensch"] = (mk, round(w.get(mk, 0.0), 3))
            if a and w.get(mk, 0.0) < t["mensch_mindestens"]:
                gruende.append(f"AudioSet hört keinen Mundlaut und keine Stimme (höchstens „{mk}“ {z(w.get(mk, 0.0), 2)})")
            schaf = max(w.get(k, 0.0) for k in ("Sheep", "Goat", "Bleat"))
            if 0.03 < schaf <= min(t["meiden"][k] for k in ("Sheep", "Goat", "Bleat")):
                hinweise.insert(0, f"klingt evtl. nach Schaf/Ziege (Grenzfall, AudioSet bis {z(schaf, 2)})")
            if bm["laute"] > 1:
                gruende.append(f"{bm['laute']} getrennte Laute statt eines einzigen „Bäh“")
            if art != "prusten" and sa < BAEH_STIMME_MIN:
                gruende.append(f"kaum Stimme ({z(100 * sa, 0)} % stimmhaft), eher Luft/Hauchen als „Bäh“")
            fl = bm.get("flattern_anteil", 0.0)
            if art == "prusten":
                if fl < BAEH_FLATTERN_ANTEIL:
                    gruende.append(f"kaum Flattern messbar ({z(100 * fl, 0)} % der Dauer, Zunge/Lippen 20–80 Hz)")
                else:
                    punkte += 1.0 * min(fl, 0.8) + 1.0 * bm.get("flattern_r", 0.0)
            elif fl >= BAEH_FLATTERN_ANTEIL:
                punkte += 0.2                     # etwas Flattern ist erwünscht („Bläh“ mit Prusten)
            if art == "hell":
                if f0 is None or f0 < BAEH_HELL_HZ:
                    gruende.append("Stimme nicht hell" + (f" (Grundton im Mittel {z(f0, 0)} Hz)" if f0 else " (kein Grundton messbar)"))
                else:
                    punkte += 0.3
            if bm.get("meckert"):
                hinweise.append("zittert regelmäßig in Pegel oder Tonhöhe (4–12 Hz): auf Meckern wie Schaf/Ziege achten")
                punkte -= 1.5
                if max(w.get(k, 0.0) for k in ("Sheep", "Goat", "Bleat")) > 0.03:
                    gruende.append("meckert (Zittern 4–12 Hz) und AudioSet hört etwas Schaf/Ziege")
            if f0 is not None and f0 < 130 and sa > 0.35:
                hinweise.append(f"tiefe Stimme (Grundton im Mittel {z(f0, 0)} Hz): eher brummig als kindlich-frech?")
                punkte -= 0.5
            punkte += 0.5 * min(sa, 0.8) if art != "prusten" else 0.0
    st = (a or {}).get("stimme")
    if st is not None:
        r["stimme"] = st
        f0 = st.get("f0_median_hz")
        sa = st["stimmhaft_anteil"]
        if f0 is not None and f0 < 130 and sa > 0.35:
            hinweise.append(f"tiefe, stimmhafte Stimme (Grundton im Mittel {z(f0, 0)} Hz): auf Stöhnen achten")
            punkte -= 1.0
        if sa < 0.15:
            # Gähnen hat ein „haaah“ mit Tonhöhe; nur Hauchen klingt eher nach Ausatmen/Seufzen
            hinweise.append("fast nur Atem, kaum Stimme: eher Ausatmen/Seufzen als Gähnen?")
            punkte -= 1.0
        elif f0 is not None and sa <= 0.95 and max(st.get("anstieg_ht", 0.0), st.get("abfall_ht", 0.0)) >= 2 \
                and not t.get("hmm"):
            punkte += 0.5                 # Stimme mit Tonhöhenbewegung und etwas Hauch: typisch für Gähnen
    if t.get("hmm"):
        # „Hmmm“: überwiegend stimmhaft (gesummt), Gipfel vorn, danach deutlich abwärts, kaum Anstieg davor
        if st is None:
            gruende.append("ohne Tonhöhen-Messung")
        elif "abfall_ht" not in st:
            gruende.append("Tonhöhe nicht messbar")
        else:
            if st["stimmhaft_anteil"] < 0.55:
                gruende.append(f"kaum gesummt ({z(100 * st['stimmhaft_anteil'], 0)} % stimmhaft)")
            if st["gipfel_lage"] > 0.35:
                gruende.append(f"Tonhöhe fängt nicht oben an (Gipfel bei {z(100 * st['gipfel_lage'], 0)} % der Stimme)")
            if st["abfall_ht"] < HMM_FALL_HT:
                gruende.append(f"Tonhöhe fällt kaum ({z(st['abfall_ht'])} Halbtöne vom Gipfel bis zum Ende)")
            if st["anstieg_ht"] > 2.5:
                hinweise.append(f"steigt vorn erst {z(st['anstieg_ht'])} Halbtöne an")
                punkte -= 0.5
            punkte += 0.15 * min(st["abfall_ht"], 12.0) + 1.0 * min(st["stimmhaft_anteil"], 0.9)
            if st.get("ende_schwerpunkt_hz") and st["ende_schwerpunkt_hz"] > 1500:
                hinweise.append(f"Ende hell (Schwerpunkt {z(st['ende_schwerpunkt_hz'], 0)} Hz): eher „Hääh“ als „Hmmm“?")
    if t.get("reihenfolge"):
        rf = (a or {}).get("reihenfolge")
        if rf is None:
            gruende.append("ohne Reihenfolge-Prüfung")
        else:
            r["reihenfolge"] = rf
            rg = reihenfolge_pruefen(rf)
            r["reihenfolge_ok"] = not rg
            gruende += rg
            if not rg:
                # Einatmen gut hörbar und nicht zu kurz, langes und deutlich fallendes „aaah“, keine lange Pause
                aah = rf["stimme_bis_s"] - rf["stimme_ab_s"]
                if aah < 0.8:
                    hinweise.append(f"kurzes „aaah“ ({z(aah, 1)} s stimmhaft)")
                punkte += (min(rf["einatmen_s"], 1.0) + 0.1 * min(rf["faellt_ht"], 8.0) + 0.8 * min(aah, 1.5)
                           + 0.05 * max(0.0, rf["einatmen_pegel_db"] + 25.0) - 1.0 * (rf["pause_vor_stimme_s"] >= RF_PAUSE_S[0]))
                if rf.get("unterbrechungen") == 1:
                    hinweise.append("„aaah“ einmal kurz unterbrochen")
                    punkte -= 0.5
                if rf["einatmen_pegel_db"] > -1.0:
                    hinweise.append("Einatmen so laut wie das „aaah“")
                if rf["pause_vor_stimme_s"] >= RF_PAUSE_S[0]:
                    hinweise.append(f"{z(rf['pause_vor_stimme_s'], 2)} s Stille zwischen Einatmen und „aaah“")
    wm = r.get("wecker")
    if wm:
        tk = (a or {}).get("ticken", {}).get("werte", {})
        kl = (a or {}).get("klingeln", {}).get("werte", {})
        tick_erw = max([tk.get(k, 0.0) for k in t["erwartet_ticken"]] + [0.0])
        ring_erw = max([kl.get(k, 0.0) for k in t["erwartet_klingeln"]] + [0.0])
        if wm["ticks"] < 4:
            gruende.append(f"kaum Ticken vor dem Klingeln ({wm['ticks']} Ticks)")
        if wm["ticken_dauer_s"] < 2.0:
            gruende.append(f"Ticken zu kurz ({z(wm['ticken_dauer_s'], 1)} s)")
        if wm["klingeln_dauer_s"] < 0.8:
            gruende.append(f"Klingeln zu kurz ({z(wm['klingeln_dauer_s'], 1)} s)")
        if wm["nach_klingeln_rel_db"] is not None and wm["nach_klingeln_rel_db"] > -20:
            hinweise.append("nach dem Klingeln noch Geräusche")
        if wm["tick_streuung"] is not None and wm["tick_streuung"] > 0.35:
            hinweise.append(f"Ticken unregelmäßig (Streuung {z(wm['tick_streuung'], 2)})")
        sc = r.get("wecker_schnitt", {})
        if sc.get("ticken_vorn_gekuerzt_s"):
            hinweise.append(f"tickte länger: Anfang um {z(sc['ticken_vorn_gekuerzt_s'], 1)} s gekürzt (weich eingeblendet)")
        if sc.get("ticken_angehoben_db"):
            hinweise.append(f"Ticken war {z(abs(sc['roh_ticken_rel_db']))} dB leiser als das Klingeln: mit weicher Pegelkurve "
                            f"um {z(sc['ticken_angehoben_db'])} dB angehoben (kein Schnitt)")
        if wm["ticken_rel_db"] is not None and wm["ticken_rel_db"] > -3:
            hinweise.append("Ticken fast so laut wie das Klingeln (eher Klingelstöße?)")
        if sc.get("klingeln_ausgeblendet"):
            hinweise.append(f"klingelte {z(sc['klingeln_natuerlich_s'], 1)} s: nach 1,95 s in 0,4 s ausgeblendet")
        if a and tick_erw < 0.05:
            hinweise.append("AudioSet hört im ersten Teil kein Ticken")
        if a and ring_erw < 0.05:
            hinweise.append("AudioSet hört im zweiten Teil keine Klingel")
        punkte += 3.0 * ring_erw + 2.0 * tick_erw - 1.0 * abs(wm["ticken_dauer_s"] - 3.0) - 1.0 * abs(wm["klingeln_dauer_s"] - 1.75)
        punkte -= (wm["tick_streuung"] or 1.0) + 2.0 * (wm["ticks"] < 4)
        punkte -= 1.5 * bool(wm["ticken_rel_db"] is not None and wm["ticken_rel_db"] > -3)
        r["klingeln_ab_s"] = wm["klingeln_ab_s"]
        r["ast_ticken_bester"] = round(tick_erw, 3)
        r["ast_klingeln_bester"] = round(ring_erw, 3)
    if r.get("fehler"):
        gruende.append(r["fehler"])
    r["ast_erwartet"] = (erw_k, round(erw, 3))
    r["ast_sprache"] = (spr_k, round(spr, 3))
    r["ast_katze"] = (kat_k, round(kat, 3))
    r["ast_top"] = (a or {}).get("top", [])[:5]
    r["ausschluss"] = gruende
    r["hinweise"] = hinweise
    r["punkte"] = round(punkte, 2)
    return r


def stimme_text(st, ende=True):
    """Kurzbeschreibung aus stimme_messen (Messung, nicht gehört). ende=False: ohne das Ende (Gähnen Runde 3: dort
    beschreibt reihenfolge_text das Ende nach eigener Messung)."""
    teile = []
    f0, sa = st.get("f0_median_hz"), st["stimmhaft_anteil"]
    if f0 is None:
        teile.append("fast nur Atem, kaum Stimme")
    else:
        lage = "tiefe" if f0 < 130 else "mittlere" if f0 < 250 else "hohe" if f0 < 400 else "sehr hohe"
        teile.append(f"{lage} Stimme (Grundton im Mittel {z(f0, 0)} Hz)")
        teile.append("überwiegend gehaucht" if sa < 0.3 else "halb gehaucht, halb Stimme" if sa < 0.6 else "überwiegend Stimme")
        an, ab = st["anstieg_ht"], st["abfall_ht"]
        if an >= 2 and ab >= 2:
            teile.append(f"Tonhöhe steigt um {z(an, 0)} und fällt um {z(ab, 0)} Halbtöne")
        elif an >= 2:
            teile.append(f"Tonhöhe steigt um {z(an, 0)} Halbtöne")
        elif ab >= 2:
            teile.append(f"Tonhöhe fällt um {z(ab, 0)} Halbtöne")
        else:
            teile.append("Tonhöhe fast gleich")
    es, ec = st.get("ende_stimmhaft"), st.get("ende_schwerpunkt_hz")
    if es is not None and ende:
        teile.append("endet summend (kleines „mm“?)" if es >= 0.5 and ec < 900 else "endet gehaucht" if es < 0.25
                     else "endet mit Stimme")
    return ", ".join(teile)


def notiz(r):
    t = TOENE[r["ton"]]
    teile = [f"Prompt „{r['variante']}“: {r['prompt_notiz']}."]
    if r.get("kategorie") and (t.get("furz") or t.get("arten")):
        teile.insert(0, f"Art: {t.get('arten', FURZ_ARTEN).get(r['kategorie'], r['kategorie'])}.")
    if r.get("umgestellt"):
        u = r["umgestellt"]
        sc = u["schnitte_s"]
        teile.append(f"Aus gaehnen2_02 (Seed {r['seed']}) umgestellt: Atem {z(sc['atem_von'], 2)}–{z(sc['atem_bis'], 2)} s nach vorn, "
                     f"dann „aaah“ {z(sc['stimme_von'], 2)}–{z(sc['stimme_bis'], 2)} s (Zeiten im Original); natürliche Pause im "
                     f"Original {z(u['pause_s'], 2)} s ({z(u['pause_pegel_db'])} dB), neu {z(u['neue_pause_s'], 2)} s; Nähte "
                     "40 ms überblendet in der Stille (" + ", ".join(f"{z(n['links_db'])}/{z(n['rechts_db'])} dB" for n in u["naehte"]) + ").")
    if r.get("reihenfolge"):
        teile.append(f"Ablauf gemessen: {reihenfolge_text(r['reihenfolge'])}.")
    if r.get("stimme"):
        teile.append(f"Gemessen: {stimme_text(r['stimme'], ende=not r.get('reihenfolge'))}.")
    if r.get("furz"):
        teile.append(f"Gemessen: {furz_text(r['furz'], r['dauer_s'] - m.TAIL_S)}.")
    if r.get("baeh"):
        teile.append(f"Gemessen: {baeh_text(r['baeh'], r['dauer_s'] - m.TAIL_S)}.")
    wm = r.get("wecker")
    if wm:
        tz = wm["tick_zeiten_s"]
        teile.append(f"Ticken ab {z(tz[0] if tz else 0, 2)} s ({wm['ticks']} Ticks, Abstand {z(wm['tick_abstand_s'] or 0, 2)} s), "
                     f"Klingeln ab {z(wm['klingeln_ab_s'], 2)} s, {z(wm['klingeln_dauer_s'], 2)} s lang.")
    if r["ast_top"]:
        e = r["ast_erwartet"]
        teile.append(f"AudioSet: „{e[0]}“ {z(e[1], 2)} (Spitze: „{r['ast_top'][0][0]}“ {z(r['ast_top'][0][1], 2)}).")
        if r.get("ast_meiden") and t.get("furz"):
            am = r["ast_meiden"]
            teile.append("Kontrolle: " + ", ".join(f"„{k}“ {z(am[k], 2)}" for k in ("Laughter", "Squish", "Liquid", "Burping, eructation", "Hiss")
                                                   if k in am) + ".")
            if r.get("ast_beobachtet"):
                teile.append("AudioSet hört außerdem: " + ", ".join(f"„{k}“ {z(v, 2)}" for k, v in sorted(r["ast_beobachtet"].items(), key=lambda kv: -kv[1])) + ".")
        elif r.get("ast_meiden") and t.get("baeh"):
            am = r["ast_meiden"]
            teile.append("Kontrolle: " + ", ".join(f"„{k}“ {z(am[k], 2)}" for k in ("Sheep", "Goat", "Bleat", "Animal", "Laughter",
                                                                                     "Crying, sobbing", "Screaming", "Yell") if k in am)
                         + f", Sprache {z(r['ast_sprache'][1], 2)}.")
            if r.get("ast_beobachtet"):
                teile.append("AudioSet hört außerdem: " + ", ".join(f"„{k}“ {z(v, 2)}" for k, v in sorted(r["ast_beobachtet"].items(), key=lambda kv: -kv[1])) + ".")
        elif r.get("ast_meiden"):
            am = r["ast_meiden"]
            teile.append("Kontrolle Stöhnen: " + ", ".join(f"„{k}“ {z(am[k], 2)}" for k in ("Groan", "Grunt", "Wail, moan") if k in am)
                         + (f"; Atemklassen zusammen {z(r['ast_atem_summe'], 2)}" if "ast_atem_summe" in r else "") + ".")
    if r["tiefpass_hz"] < 6000:
        teile.append(f"Tiefpass {z(r['tiefpass_hz'] / 1000, 2)} kHz (Leitplanke).")
    if r["ausschluss"]:
        teile.append("Auffällig: " + "; ".join(r["ausschluss"]) + ".")
    if r["hinweise"]:
        h = "; ".join(r["hinweise"])
        teile.append("Hinweis: " + h + ("" if h.endswith("?") else "."))
    return " ".join(teile)


def tick_txt(rel):
    if rel is None:
        return "ohne messbare Ticks"
    return f"{z(abs(rel))} dB {'leiser' if rel < 0 else 'lauter'} als das Klingeln (lautester Tick, 50-ms-Pegel)"


def svg_verlauf(zd, wm):
    import numpy as np
    w = int(0.025 * FS)
    k = len(zd) // w
    r = 10 * np.log10(np.mean(np.square(zd[:k * w]).reshape(k, w), axis=1) + 1e-12)
    px = 80
    top = float(r.max())
    pts = " ".join(f"{(i + 0.5) * 0.025 * px:.1f},{min(118, max(2, (top - r[i]) * 2.2 + 4)):.1f}" for i in range(k))
    width = int(len(zd) / FS * px) + 10
    o = f'<svg viewBox="0 0 {width} 130" width="100%" style="max-width:{width}px;background:#8881;border-radius:6px">'
    for sec in range(int(len(zd) / FS) + 1):
        o += f'<line x1="{sec * px}" y1="0" x2="{sec * px}" y2="130" stroke="#8884"/><text x="{sec * px + 2}" y="127" font-size="9" fill="#888">{sec} s</text>'
    for tt in wm["tick_zeiten_s"]:
        o += f'<line x1="{tt * px:.1f}" y1="112" x2="{tt * px:.1f}" y2="120" stroke="#2e8b57" stroke-width="1.5"/>'
    xa = wm["klingeln_ab_s"] * px
    xb = wm["klingeln_bis_s"] * px
    o += f'<rect x="{xa:.1f}" y="0" width="{max(1.0, xb - xa):.1f}" height="110" fill="#ff4fa322"/>'
    o += f'<line x1="{xa:.1f}" y1="0" x2="{xa:.1f}" y2="120" stroke="#ff4fa3" stroke-width="2"/>'
    o += f'<text x="{xa + 3:.1f}" y="10" font-size="10" fill="#ff4fa3">Klingeln ab {z(wm["klingeln_ab_s"], 2)} s</text>'
    return o + f'<polyline fill="none" stroke="#2471a3" stroke-width="1.5" points="{pts}"/></svg>'


def svg_gaehnen(zd, rf):
    """Pegelverlauf (25 ms) mit dem Atem vor der Stimme (grün) und dem stimmhaften Teil (rosa) aus reihenfolge_messen."""
    import numpy as np
    w = int(0.025 * FS)
    k = len(zd) // w
    r = 10 * np.log10(np.mean(np.square(zd[:k * w]).reshape(k, w), axis=1) + 1e-12)
    px = 80
    top = float(r.max())
    pts = " ".join(f"{(i + 0.5) * 0.025 * px:.1f},{min(118, max(2, (top - r[i]) * 2.2 + 4)):.1f}" for i in range(k))
    width = int(len(zd) / FS * px) + 10
    o = f'<svg viewBox="0 0 {width} 130" width="100%" style="max-width:{width}px;background:#8881;border-radius:6px">'
    for sec in range(int(len(zd) / FS) + 1):
        o += f'<line x1="{sec * px}" y1="0" x2="{sec * px}" y2="130" stroke="#8884"/><text x="{sec * px + 2}" y="127" font-size="9" fill="#888">{sec} s</text>'
    xa, xv, xe = rf["hoerbar_ab_s"] * px, rf["stimme_ab_s"] * px, rf["stimme_bis_s"] * px
    o += f'<rect x="{xa:.1f}" y="0" width="{max(1.0, xv - xa):.1f}" height="110" fill="#2e8b5722"/>'
    o += f'<rect x="{xv:.1f}" y="0" width="{max(1.0, xe - xv):.1f}" height="110" fill="#ff4fa322"/>'
    o += f'<text x="{xa + 3:.1f}" y="10" font-size="10" fill="#2e8b57">Atem</text>'
    o += f'<text x="{xv + 3:.1f}" y="10" font-size="10" fill="#ff4fa3">„aaah“ ab {z(rf["stimme_ab_s"], 2)} s</text>'
    return o + f'<polyline fill="none" stroke="#2471a3" stroke-width="1.5" points="{pts}"/></svg>'


def dubletten(rs, alle=False):
    """Gleicher Seed bei ähnlichem Prompt ergibt manchmal fast denselben Ton. Vergleich der Spektrogramme (Terzbänder
    100 Hz–6 kHz, Fenster 2048, dB): Korrelation r > 0,9 -> der schwächere gilt als Dublette und fällt aus der Auswahl.
    alle=True (TOENE[...]["dubletten_alle"]): alle Paare vergleichen, nicht nur gleiche Seeds."""
    import numpy as np
    from scipy import signal
    spg = {}
    edges = [100 * 2 ** (i / 3) for i in range(0, 20)]
    for r in rs:
        zd = m.decode(os.path.join(TMP, r["roh"] + ".ogg"))
        f, _t, S = signal.spectrogram(zd, FS, nperseg=2048, noverlap=1024)
        B = np.array([S[(f >= lo) & (f < hi)].sum(axis=0) for lo, hi in zip(edges[:-1], edges[1:])])
        spg[r["roh"]] = np.maximum(10 * np.log10(B + 1e-12), -100)
    for i, a in enumerate(rs):
        for b in rs[i + 1:]:
            if a["seed"] != b["seed"] and not alle:
                continue
            A, B = spg[a["roh"]], spg[b["roh"]]
            n = min(A.shape[1], B.shape[1])
            if n < 4:
                continue
            c = float(np.corrcoef(A[:, :n].ravel(), B[:, :n].ravel())[0, 1])
            schwach, stark = (a, b) if a["punkte"] < b["punkte"] else (b, a)
            if c > 0.9:
                schwach["ausschluss"].append(f"fast gleich wie {stark['roh']} (Spektrogramm r = {z(c, 2)})")
            elif c > 0.85:
                schwach.setdefault("aehnlich", []).append((stark["roh"], round(c, 2)))


def arten(t):
    """Arten (Kategorien) eines Tons in der Reihenfolge der Prompts; ohne Kategorie zählt die Variante."""
    return list(dict.fromkeys(optionen_von(p).get("kategorie", p[0]) for p in t["prompts"]))


def seite(nur=None):
    """Auswahl, Ablage, messwerte.json und hoeren.html. Mit nur (Töne, kommagetrennt) werden nur diese Töne neu
    ausgewählt und abgelegt; alle übrigen Einträge in messwerte.json und ihre Dateien bleiben unverändert, die Hörseite
    wird aus dem zusammengeführten Stand neu geschrieben."""
    import re
    kand = json.load(open(KAND_JSON, encoding="utf-8"))
    ast = json.load(open(AST_JSON, encoding="utf-8")) if os.path.exists(AST_JSON) else {}
    os.makedirs(OUT, exist_ok=True)
    mw_pfad = os.path.join(OUT, "messwerte.json")
    keys = [k.strip() for k in nur.split(",")] if nur else None
    neu = [t for t in REIHE if t in keys] if keys else REIHE
    alt = json.load(open(mw_pfad, encoding="utf-8")) if keys and os.path.exists(mw_pfad) else None
    muster = re.compile(r"^(%s)_\d\d(umgestellt)?(_handy)?\.ogg$" % "|".join(re.escape(t) for t in neu))
    for f in os.listdir(OUT):
        if f.endswith(".ogg") and (alt is None or muster.match(f)):
            os.remove(os.path.join(OUT, f))
    behalten, verworfen = [], []
    for ton in neu:
        t = TOENE[ton]
        for r in kand:
            if r["ton"] == ton and r.get("fehler"):
                verworfen.append({"roh": r["roh"], "ton": ton, "punkte": None, "gruende": [r["fehler"]], "hinweise": []})
        rs = [bewerten(dict(r), ast.get(r["roh"])) for r in kand if r["ton"] == ton and not r.get("fehler")]
        # der umgestellte Versuch läuft außerhalb der Rangfolge (nur, wenn umstellen gelungen ist, Rohdatei vorhanden)
        umg = [r for r in rs if r.get("umgestellt") and os.path.exists(os.path.join(ROH, r["roh"] + ".wav"))]
        rs = [r for r in rs if not r.get("umgestellt")]
        dubletten(rs, t.get("dubletten_alle", False))
        ok = sorted([r for r in rs if not r["ausschluss"]], key=lambda r: -r["punkte"])
        cap = t.get("je_variante_max")
        if cap:
            # Vielfalt: zuerst höchstens cap Kandidaten je Prompt-Variante (Zwilling „…_im_prompt“ zählt mit), dann der Rest
            erst, spaeter, n = [], [], {}
            for r in ok:
                b = r["variante"].replace("_im_prompt", "")
                n[b] = n.get(b, 0) + 1
                (erst if n[b] <= cap else spaeter).append(r)
            for r in spaeter:
                r["vielfalt"] = True
            ok = erst + spaeter
        kats = arten(t)
        if t.get("ausgewogen"):
            # Furzkissen: reihum der beste jeder Art, dann der zweitbeste … (Vielfalt über die Arten)
            je = {k: [r for r in ok if r.get("kategorie", r["variante"]) == k] for k in kats}
            ok = [je[k][i] for i in range(max([len(v) for v in je.values()] + [0])) for k in kats if i < len(je[k])]
        rest = sorted([r for r in rs if r["ausschluss"] and not any(g.startswith("fast gleich") for g in r["ausschluss"])],
                      key=lambda r: -r["punkte"])
        wahl = (ok if t.get("nur_ok") else ok + rest)[:t["behalten"]]
        if t.get("ausgewogen"):
            # Nummern nach Art geordnet (Reihenfolge der Prompts), innerhalb der Art nach Punkten
            wahl.sort(key=lambda r: (kats.index(r.get("kategorie", r["variante"])), -r["punkte"]))
        for i, r in enumerate(wahl, 1):
            r["id"] = f"{ton}_{i:02d}"
        for r in umg:
            r["id"] = UMGESTELLT["datei"]
            r["hinweise"].insert(0, "zusammengesetzt (Teile getauscht), außerhalb der Rangfolge")
        wahl += umg
        idmap = {r["roh"]: r["id"] for r in wahl}
        for r in wahl:
            for roh, c in r.pop("aehnlich", []):
                if roh in idmap:
                    gs = "gleicher Seed, " if roh.endswith(f"_{r['seed']}") else ""
                    r["hinweise"].append(f"ähnlich wie {idmap[roh]} ({gs}Spektrogramm r = {z(c, 2)})")
            r["notiz"] = notiz(r)
            for suf in (".ogg", "_handy.ogg"):
                shutil.copy(os.path.join(TMP, r["roh"] + suf), os.path.join(OUT, r["id"] + suf))
            behalten.append(r)
        for r in rs:
            if r not in wahl:
                verworfen.append({"roh": r["roh"], "ton": ton, "punkte": r.get("punkte"),
                                  "gruende": r["ausschluss"] or [f"weniger Punkte (höchstens {cap} je Prompt-Variante)"
                                                                 if r.get("vielfalt") else "weniger Punkte"],
                                  "hinweise": r.get("hinweise", [])})
    if alt:
        behalten = [r for r in alt["kandidaten"] if r["ton"] not in neu] + behalten
        verworfen = [v for v in alt["verworfen"] if v["ton"] not in neu] + verworfen
        behalten.sort(key=lambda r: REIHE.index(r["ton"]))
        verworfen.sort(key=lambda v: REIHE.index(v["ton"]))
    seite_schreiben(behalten, verworfen, bool(ast))
    out = {"stand": time.strftime("%Y-%m-%d"), "modell": m.MODEL_ID, "lizenz_modell": "Apache-2.0",
           "skript": "tools/make_ostereier.py",
           "einstellungen": {"schritte": m.STEPS, "cfg": m.CFG, "sigma_shift": m.SHIFT, "abtastrate": FS,
                             "leitplanke": "Tiefpass vor-/rückwärts 6–3,5 kHz, über 6 kHz ≤ −30 dB",
                             "lautheit": "höchste Momentan-Lautheit (400 ms, BS.1770)", "ogg": "Vorbis q6, mono, 48 kHz",
                             "handy_modell": "Hochpass 400 Hz (8. Ordnung), Tiefpass 8 kHz, +5 dB um 1,5 kHz",
                             "ast": AST_MODEL if ast else None},
           "toene": {k: {"titel": v["titel"], "ziel_s": list(v["ziel"]), "ziel_lufs": v["lufs"], "daueransage_s": v["sekunden"],
                         "prompts": {p[0]: dict({"prompt": p[1], "seeds": seeds_von(v, p)},
                                                **({"negativ": negativ_von(v, p)} if "negativ" in v else {}), **optionen_von(p))
                                     for p in v["prompts"]},
                         "behalten": v["behalten"]}
                     for k, v in TOENE.items()},
           "kandidaten": [{k: v for k, v in r.items() if k not in ("prompt_notiz",)} for r in behalten],
           "verworfen": verworfen}
    json.dump(out, open(mw_pfad, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    for r in behalten:
        if r["ton"] not in neu:
            continue
        print(r["id"], r["roh"], r["dauer_s"], r["punkte"], r["ausschluss"], flush=True)
    print(f"behalten {len(behalten)}, verworfen {len(verworfen)}", flush=True)


def seite_schreiben(behalten, verworfen, mit_ast):
    old = open(os.path.join(m.ROOT, "audio", "entwurf", "jubel3", "hoeren.html"), encoding="utf-8").read()
    css = old[old.index("<style>"):old.index("</style>")]
    css += """.group{margin:30px 0 10px;padding-top:6px;border-top:2px solid var(--line)}.group h2{font-size:1.35rem}
nav{display:flex;flex-wrap:wrap;gap:6px;margin:10px 0 4px}nav a{color:var(--ink);text-decoration:none;border:1px solid var(--line);border-radius:99px;padding:2px 10px;font-size:.85rem;background:var(--card)}
.card h3{font-size:1.05rem;margin:0}.warn{color:#c0392b}</style>"""
    import numpy as np  # noqa: F401  (svg_verlauf)
    nav = "".join(f'<a href="#{t}">{html.escape(TOENE[t]["titel"])}</a>' for t in REIHE)
    teile = []
    for ton in REIHE:
        t = TOENE[ton]
        rs = [r for r in behalten if r["ton"] == ton]
        n_ges = sum(1 for c in candidates(ton) if not c.get("umgestellt"))
        rs = [r for r in rs if not r.get("umgestellt")] + [r for r in rs if r.get("umgestellt")]
        hw = '<p class="sub">' + html.escape(t["hinweis"]) + "</p>" if t.get("hinweis") else ""
        teile.append(f"""<section class="group" id="{ton}"><h2>{html.escape(t['titel'])}</h2>
<p class="sub">{html.escape(t['zweck'])}; Ziel {html.escape(t['ziel_text'])}; {z(t['lufs'])} LUFS. {len(rs)} von {n_ges} erzeugten Kandidaten, Reihenfolge = Empfehlung nach Messwerten{' (je Art)' if t.get('ausgewogen') else ''}.</p>{hw}</section>""")
        art = None
        for r in rs:
            if t.get("ausgewogen") and r.get("kategorie") != art:
                art = r.get("kategorie")
                teile.append(f'<h3 style="margin:18px 0 6px">{html.escape(t.get("arten", FURZ_ARTEN).get(art, art or ""))}</h3>')
            wm = r.get("wecker")
            extra = ""
            if wm:
                zd = m.decode(os.path.join(OUT, r["id"] + ".ogg"))
                extra = (f'<p class="sub">Pegelverlauf (grüne Striche = Ticks, rosa = Klingeln)</p>{svg_verlauf(zd, wm)}'
                         f'<p class="facts"><b>Für die Animation:</b> Klingeln ab {z(wm["klingeln_ab_s"], 2)} s bis {z(wm["klingeln_bis_s"], 2)} s; '
                         f'{wm["ticks"]} Ticks ab {z(wm["erster_tick_s"] or 0, 2)} s, Abstand {z(wm["tick_abstand_s"] or 0, 2)} s; '
                         f'Ticken {tick_txt(wm["ticken_rel_db"])}. AudioSet Ticken-Teil {z(r["ast_ticken_bester"], 2)}, Klingel-Teil {z(r["ast_klingeln_bester"], 2)}.</p>')
            rf = r.get("reihenfolge")
            if rf and not rf.get("fehler"):
                zd = m.decode(os.path.join(OUT, r["id"] + ".ogg"))
                extra = (f'<p class="sub">Pegelverlauf (grün = Atem vor der Stimme, rosa = stimmhafter Teil)</p>{svg_gaehnen(zd, rf)}'
                         f'<p class="facts"><b>Reihenfolge-Prüfung:</b> {"bestanden" if r.get("reihenfolge_ok") else "nicht bestanden"}; '
                         f'Einatmen {z(rf["einatmen_s"], 2)} s (Stimme darin {z(100 * rf["einatmen_stimme"], 0)} %, lautester Teil '
                         f'{z(rf["einatmen_pegel_db"] if rf["einatmen_pegel_db"] is not None else -99)} dB), stimmhaft ab {z(rf["stimme_ab_s"], 2)} s '
                         f'bis {z(rf["stimme_bis_s"], 2)} s (Mitte bei {z(100 * rf["lage"], 0)} % der Dauer), Tonhöhe '
                         f'{rf.get("f0_anfang_hz", "–")} → Gipfel {rf.get("f0_gipfel_hz", "–")} → {rf.get("f0_ende_hz", "–")} Hz, '
                         f'Ende {z(100 * rf["ende_stimme"], 0)} % Stimme.</p>')
            warn = ' <span class="tag">auffällig</span>' if r["ausschluss"] else ""
            top = ", ".join(f"„{k}“ {z(v, 2)}" for k, v in r["ast_top"][:4]) if r["ast_top"] else "–"
            linie = (f"Linie {r['linien_2_6k'][0][0]} Hz (+{z(r['linien_2_6k'][0][1])} dB)" if r["linien_2_6k"] else "keine schmale Linie 2–6 kHz")
            pu = r.get("puls_15_50") or {"hz": 0, "schaerfe": 0}
            teile.append(f"""<section class="card"><h3>{r['id']} <span class="tag">{html.escape(r['variante'])} &middot; Seed {r['seed']} &middot; {z(r['dauer_s'], 2)} s</span>{warn}</h3>
<p class="sub">{html.escape(r['notiz'])}</p>
<p class="sub">Original (Laptop/Kopfhörer)</p><audio controls preload="none" src="{r['id']}.ogg"></audio>
<p class="sub">So etwa am Handy (Lautsprecher-Modell, auf gleiche Lautheit gehoben)</p><audio controls preload="none" src="{r['id']}_handy.ogg"></audio>
{extra}<p class="facts">{z(r['lufs'])} LUFS, Spitze {z(r['spitze_dbtp'])} dBTP; Tiefpass {z(r['tiefpass_hz'] / 1000, 2)} kHz, über 6/10/12 kHz {z(r['ueber_6k_db'])}/{z(r['ueber_10k_db'])}/{z(r['ueber_12k_db'])} dB (ohne Tiefpass {z(r['ueber_6k_ohne_tiefpass_db'])} dB); {linie}; Puls 15–50 Hz: {z(pu['hz'], 0)} Hz, Schärfe {z(pu['schaerfe'])};
Handy-Modell: Pegelverlust {z(r['sim_pegelverlust_db'])} dB, Mitten {z(r['sim_mitten_500_4k_db'])} dB. AudioSet: {html.escape(top)}; Sprache {z(r['ast_sprache'][1], 2)}, Katze {z(r['ast_katze'][1], 2)}. Punkte {z(r['punkte'], 2)}.</p>
<details><summary>Prompt</summary><p class="facts">{html.escape(r['prompt'])} duration: {r['sekunden_prompt']:.1f}s</p></details></section>""")
    verw = "".join(f"<li>{html.escape(v['roh'])}: {html.escape('; '.join(v['gruende']))}</li>" for v in verworfen)
    page = f"""<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Easter Eggs Hörproben</title>
{css}</head><body><main>
<h1>Easter Eggs: Hörproben</h1><p class="lead">Töne zum Senden an Mitspieler (Gähnen, Schnarchen, Wecker, Papierkugel, Furzkissen) und für Reaktionen. {len(behalten)} Kandidaten, erzeugt mit MOSS-SoundEffect v2.0 (Apache 2.0), mono, weich ein- und ausgeblendet. Offline, lokal. Entwurf, nichts davon ist im Spiel.</p>
<nav>{nav}</nav>
<div class="hint"><b>Wecker in einem Stück:</b> Ticken und Klingeln hat das Modell zusammen erzeugt; geschnitten wurden nur Anfang und Ende (weiche Blenden), nichts zusammengesetzt. Der Klingel-Einsatz ist gemessen (Sekunde ab Dateianfang, in messwerte.json als <code>klingeln_ab_s</code>) und steht bei jedem Wecker, damit die Animation darauf passt. War das Ticken mehr als 20 dB leiser als das Klingeln (am Handy unhörbar), ist es vor dem Klingeln mit einer weichen Pegelkurve angehoben (steht beim Kandidaten).<br>
<b>Katzen-Leitplanke:</b> keine Katzenlaute in den Prompts; Tiefpass so, dass über 6 kHz höchstens −30 dB bleiben; geprüft auf Pulsfolge 15–50 Hz (Schnurr-Bereich) und schmale Linien 2–6 kHz (Piepen){', AudioSet-Klassifikator auf Katze/Miauen/Schnurren und Sprache' if mit_ast else ''}. Ein Wecker ist von Natur aus eine Glocke mit schnellem Klöppel: Linien und Puls sind dort zu erwarten und nur markiert. Beim Furzkissen ist das Flattern des Gummis von Natur aus ein Puls in diesem Bereich: markiert, ausgeschlossen nur, wenn AudioSet zugleich Schnurren hört; Quietschen, das nach Maus oder Vogel klingt, fällt aus. Dasselbe gilt für das Zungen-Flattern beim „Bäh“; dort fällt außerdem aus, was nach Schaf, Ziege oder anderem Tier klingt.<br>
<b>Pegel:</b> Wecker −17,5 LUFS (wie „Du bist dran“), Stimmen, Klatschen und Daumen −19 LUFS (wie der Jubel), Papier −21/−21,5 LUFS (wie Flip/Mischen), Furzkissen −20 LUFS (dazwischen), sein kleines „Pfft“ −23 LUFS; Mau-Ton −11,4 LUFS. Im Spiel kommt die Stufe der Spieltöne dazu (normal −4,5 dB).<br>
<b>Ehrlich:</b> Niemand hat gehört; Rangfolge und Notizen stützen sich auf Messwerte und den AudioSet-Klassifikator. Bitte besonders auf verständliche Wörter, katzenähnliche Laute und Klicks achten.</div>
{''.join(teile)}
<section class="group"><h2>Verworfen</h2><details><summary>{len(verworfen)} Kandidaten (Gründe)</summary><ul class="facts">{verw}</ul></details></section>
</main></body></html>"""
    open(os.path.join(OUT, "hoeren.html"), "w", encoding="utf-8").write(page)


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--alles", action="store_true")
    ap.add_argument("--erzeugen", action="store_true")
    ap.add_argument("--bearbeiten", action="store_true")
    ap.add_argument("--ast", action="store_true")
    ap.add_argument("--seite", action="store_true")
    ap.add_argument("--nur", help="Töne, kommagetrennt (gaehnen,wecker)")
    ap.add_argument("--gpu", type=int, default=0)
    ap.add_argument("--vram", type=float, help="höchstens so viele GiB auf der GPU (Sparmodus erzwingen)")
    a = ap.parse_args()
    cs = candidates(a.nur)
    if (a.alles or a.bearbeiten) and any(c.get("umgestellt") for c in cs):
        ok, info = umstellen()
        print("Umgestellt:", "ja" if ok else "nein", json.dumps(info, ensure_ascii=False), flush=True)
    if a.alles or a.erzeugen:
        erzeugen(cs, a.gpu, vram=a.vram)
    if a.alles or a.bearbeiten:
        bearbeiten(cs)
    if a.ast:
        ast_lauf(a.nur)
    elif a.alles:
        subprocess.run([ANALYSE_PY, os.path.abspath(__file__), "--ast"] + (["--nur", a.nur] if a.nur else []), check=True)
    if a.alles or a.seite:
        seite(a.nur)
