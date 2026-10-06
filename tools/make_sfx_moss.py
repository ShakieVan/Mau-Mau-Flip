"""Erzeugt Kandidaten für die Spieltöne von Mau-Mau Flip mit dem Geräusch-Modell MOSS-SoundEffect v2.0.

Zweck
  Die synthetischen Töne aus tools/make_sfx.py klingen zu einfach. Dieses Skript lässt ein Text-zu-Geräusch-Modell
  je Ton mehrere Kandidaten erzeugen (2–3 Prompt-Varianten × feste Seeds), schneidet und pegelt sie und legt eine
  Spektrogramm-Übersicht an. Ausgewählt wird danach von Hand (anhören); das Skript ändert keine Spieldateien.

Modell und Lizenz
  OpenMOSS-Team/MOSS-SoundEffect-v2.0 (Hugging Face), Lizenz Apache 2.0, DiT 1,3 Mrd. Parameter + DAC-VAE (48 kHz,
  mono) + Qwen3-Textkodierer, etwa 10,5 GB. Code: github.com/OpenMOSS/MOSS-TTS, Unterordner moss_soundeffect_v2.
  Apache 2.0 regelt Code und Gewichte und stellt keine Bedingungen an die erzeugten Töne.

Aufruf (PowerShell; Umgebung, Repo-Klon und Modell-Cache liegen in der Werkstatt E:\\Draw2Race-AudioLab\\moss-sfx)
  . E:\\Draw2Race-AudioLab\\env.ps1
  $py = 'E:\\Draw2Race-AudioLab\\moss-sfx\\.venv\\Scripts\\python.exe'
  & $py tools\\make_sfx_moss.py                          # alles: erzeugen (GPU 0), nachbearbeiten, Übersicht
  & $py tools\\make_sfx_moss.py --nur karte,flip         # nur diese Töne
  & $py tools\\make_sfx_moss.py --nur karte_03 --erneut  # einen Kandidaten neu erzeugen (Seed in ERSATZ_SEED)
  & $py tools\\make_sfx_moss.py --gpu 0 --teil 1/2 --nur-erzeugen   # zwei GPUs parallel:
  & $py tools\\make_sfx_moss.py --gpu 1 --teil 2/2 --nur-erzeugen   #   je eine Hälfte der Kandidaten
  & $py tools\\make_sfx_moss.py --nur-nachbearbeiten     # danach: aus roh/ alles bearbeiten, messen, Übersicht
  & $py tools\\make_sfx_moss.py --rauchtest              # ein kurzer Ton, Laufzeit und Speicher
  & $py tools\\make_sfx_moss.py --spiel                  # Favoriten (SPIEL) mit Katzen-Leitplanke ins Spiel, ohne GPU
  & $py tools\\make_sfx_moss.py --spiel --ohne-kopie     #   dasselbe, aber nur audio/sfx_ki/spiel/ schreiben (Probe)
  Benötigt ffmpeg im PATH. Vorhandene Rohdateien werden nicht neu erzeugt (außer mit --erneut).
  Nach --spiel: tools/godot_import.ps1 (Godot-Import), danach tools/hoerseite_sfx_ki.py seite.

Parameter der Erzeugung (Empfehlung der Modellkarte)
  100 Schritte, CFG 4,0, sigma shift 5,0, bfloat16. Das Modell entrauscht immer 30 s; die Rechenzeit hängt daher
  nicht von der Tonlänge ab (RTX 3090: 23–26 s je Ton im 3er-Stapel, VRAM-Spitze 18 GiB; Stapel 1: 14,5 GiB).
  Die Dauer steht als „duration: X.Xs“ im Prompt (wie im Training). Unter etwa 2 s hält das Modell sie kaum ein,
  deshalb wird das Original ROH_EXTRA (2 s) länger gespeichert und das Ereignis danach herausgeschnitten.
  torch.compile/Triton sind abgeschaltet (TORCHDYNAMO_DISABLE=1, Windows).
  Rauschen: je Kandidat ein eigener CPU-Generator mit festem Seed (wie die Pipeline bei Stapelgröße 1), auch wenn
  mehrere Kandidaten in einem Stapel laufen. Gleicher Seed und Prompt ergeben denselben Ton (bis auf GPU-Rundung).

Nachbearbeitung (je Kandidat)
  Gleichanteil weg, Hochpass 60 Hz (Butterworth 2. Ordnung), Tiefpass 12 kHz (Butterworth 4. Ordnung, sanft;
  --tiefpass). Schnitt: Stille ist alles unter −45 dB vom Höchstwert (Hüllkurve 2 ms); Anfang am Hauptschlag bzw.
  am ersten deutlichen Einsatz mit begrenztem Vorlauf, Ende an der ersten Stille ≥ 60 ms, höchstens die Zieldauer
  (Einzelheiten über SOUNDS). Einblenden 3 ms, Ausblenden 30–80 ms (Kosinus). Pegel: Lautheit auf ein Ziel je Ton
  (höchste Momentan-Lautheit, 400 ms, BS.1770; kurze Schläge erreichen es wegen des 400-ms-Fensters nicht ganz),
  Spitzen darüber mit einem Begrenzer mit Vorausschau (1,5 ms, höchstens 3–6 dB), echte Spitze höchstens −1 dBTP.
  20 ms Stille am Ende (Kodierer).

Ausgabe (Projekt)
  audio/sfx_ki/roh/<ton>_<nr>.wav      Original des Modells (32-Bit-Float, 48 kHz), dazu <ton>_<nr>.json (Prompt, Seed …)
  audio/sfx_ki/<ton>_<nr>.wav|.ogg|.m4a bearbeitet: WAV 24 Bit, Ogg Vorbis q6, AAC 160 kbit/s
  audio/sfx_ki/varianten.json          Prompt, Seed, Dauer, Messwerte aller Kandidaten
  audio/sfx_ki/spektrogramme/<ton>.png Übersicht (ffmpeg showspectrumpic, je Kandidat ein Feld), <ton>_roh.png

Fassungen im Spiel (--spiel, Entscheidung 06.10.2026; Einzelheiten über SPIEL)
  Je Ton der Favorit aus roh/: gleicher Schnitt wie der Kandidat, dann Tiefpass vor- und rückwärts (sosfiltfilt,
  Butterworth 4. Ordnung, zusammen 48 dB/Oktave) mit der höchsten Grenzfrequenz zwischen 6 und 4 kHz (Schritt 50 Hz),
  bei der der fertige Ton über 6 kHz höchstens −30 dB Energieanteil hat (Katzen-Leitplanke, audio/sfx_README.md).
  Pegel je Ton (SPIEL[...]["lufs"]), Begrenzer, echte Spitze ≤ −1 dBTP. Bricht ab und kopiert nichts, wenn WAV, OGG
  oder M4A über 6/10/12 kHz mehr als −30/−50/−60 dB haben.
  audio/sfx_ki/spiel/<ton>.wav|.ogg|.m4a|.png   Fassung (WAV 24 Bit), Vorbis q6, AAC-LC (-b:a 192k), Spektrogramm
  audio/sfx_ki/spiel/messwerte.json             Messwerte (WAV und dekodierte OGG/M4A), Grenzfrequenz, Pegel im Spiel
  game/assets/sfx/<ton>.ogg, webclient/sfx/<ton>.ogg und .m4a   Kopien (alle mono, 48 kHz)
"""
import argparse
import io
import json
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "audio", "sfx_ki")
OUT_ROH = os.path.join(OUT, "roh")
OUT_SPEK = os.path.join(OUT, "spektrogramme")
MOSS_REPO = os.environ.get("MOSS_SFX_REPO", r"E:\Draw2Race-AudioLab\moss-sfx\MOSS-TTS")
MODEL_ID = "OpenMOSS-Team/MOSS-SoundEffect-v2.0"
FS = 48000

STEPS = 100
CFG = 4.0
SHIFT = 5.0
LOWPASS_HZ = 12000.0
HIGHPASS_HZ = 60.0
TRIM_DB = -45.0
FADE_IN_S = 0.003
PEAK_LIMIT_DB = -1.0
TAIL_S = 0.02

# ---------------------------------------------------------------------------------------------------------------
# Töne: Zieldauer (s), Daueransage im Prompt (s), Ausblenden (s), Ziel-Lautheit (LUFS, höchste Momentan-Lautheit),
# Schnitt-Modus und Vorlauf (s), Prompt-Varianten und Seeds. Kandidat-Nummer = Prompt-Index × len(seeds) + Seed-Index + 1.
# Keine Prompts mit Vögeln, Quietschen, Miauen oder Zischlauten (Katzen im Raum).
#
# Daueransage: Unter etwa 2 s hält sich das Modell kaum an „duration“ (Rauchtest 05.10.2026: bei 0.6s lag der
# Kartenklatsch bei 1,8 s; 1.0s, 1.5s und 2.0s ergeben mit gleichem Seed fast dieselbe Struktur, Inhalt bis 1–2 s).
# Deshalb wird das Original ROH_EXTRA s länger als die Ansage gespeichert und das Ereignis danach herausgeschnitten:
#   modus "haupt":  um den lautesten Moment (einzelner Schlag); Vorlauf höchstens `vorlauf` s davor
#   modus "anfang": ab dem ersten deutlichen Einsatz (Hüllkurve > −20 dB vom Höchstwert); Vorlauf wie oben
# Ende: erste Stille (< −45 dB vom Höchstwert, mindestens 60 ms) nach dem Anker, höchstens die Zieldauer.
# ---------------------------------------------------------------------------------------------------------------
ROH_EXTRA = 2.0

SOUNDS = {
    "karte": {
        "ziel": (0.25, 0.5), "sekunden": 1.0, "ausblenden": 0.03, "lufs": -19.0, "modus": "haupt", "vorlauf": 0.04, "begrenzer": 6.0,
        "prompts": [
            "a single playing card tossed onto a wooden table, crisp light paper slap, close-up, dry room, no music",
            "one playing card placed down firmly on a felt card table, soft papery snap, close-up, quiet room",
            "a plastic coated playing card flicked onto a wooden tabletop, one short dry slap, single hit",
        ],
        "seeds": [101, 102, 103],
    },
    "ziehen": {
        "ziel": (0.3, 0.6), "sekunden": 1.0, "ausblenden": 0.04, "lufs": -20.0, "modus": "anfang", "vorlauf": 0.25, "begrenzer": 6.0,
        "prompts": [
            "a playing card slid off the top of a deck and picked up, soft paper swipe, close-up",
            "drawing one card from a deck, short smooth slide of paper against paper, close-up, quiet room",
            "a single card pulled from a card stack across a table, soft brushing slide, dry",
        ],
        "seeds": [201, 202, 203],
    },
    "mischen": {
        "ziel": (0.6, 1.2), "sekunden": 1.5, "ausblenden": 0.05, "lufs": -18.0, "modus": "anfang", "vorlauf": 0.2, "begrenzer": 4.0,
        "prompts": [
            "a deck of playing cards riffle shuffled and bridged once, close-up, wooden table",
            "quick riffle shuffle of a deck of cards, fluttering paper, close-up, dry room",
        ],
        "seeds": [301, 302, 303, 304],
    },
    "flip": {
        "ziel": (0.8, 1.4), "sekunden": 1.5, "ausblenden": 0.08, "lufs": -17.0, "modus": "anfang", "vorlauf": 0.4,
        "prompts": [
            "magical whoosh with a short sparkling shimmer, cards flipping over, soft fantasy transition",
            "a soft airy swoosh as a whole row of cards turns over, followed by a warm gentle chime, calm magical transition",
            "a fan of playing cards flipped over in one quick motion, papery flutter with a soft magical glow sound",
            # P4 nach der ersten Sichtung: P2 ergab teils nur dumpfes Grollen
            "a quick soft swish of cards turning over, followed by one gentle warm bell tone, calm magical transition",
        ],
        "seeds": [401, 402, 403],
    },
    "sieg": {
        "ziel": (1.0, 2.0), "sekunden": 2.0, "ausblenden": 0.08, "lufs": -16.0, "modus": "anfang", "vorlauf": 0.1,
        "prompts": [
            "short cheerful victory jingle, marimba and soft bells, playful game win",
            "small group cheering and clapping briefly, friendly",
            "a short bright fanfare on glockenspiel and marimba, happy ascending notes, game level complete",
        ],
        "seeds": [501, 502, 503],
    },
    "fehler": {
        "ziel": (0.2, 0.4), "sekunden": 1.0, "ausblenden": 0.03, "lufs": -19.0, "modus": "haupt", "vorlauf": 0.04, "begrenzer": 6.0,
        "prompts": [
            "soft muted wooden knock, gentle low 'nope' interface sound",
            "a short dull low thud, muffled wooden block tap, soft error notification",
            "two quick soft low wooden knocks, muted, gentle negative user interface sound",
            # P4 nach der ersten Sichtung: P1–P3 ergaben teils fast nur Tiefbass (auf Handys unhörbar)
            "a soft hollow wooden block tap, mid-range, short and muted, gentle 'nope' interface sound",
        ],
        "seeds": [601, 602, 603],
    },
    "dran": {
        "ziel": (0.3, 0.6), "sekunden": 1.0, "ausblenden": 0.06, "lufs": -18.0, "modus": "anfang", "vorlauf": 0.05,
        "prompts": [
            "gentle warm two-note mallet chime notification, calm",
            "quick soft marimba two-note rising notification, notes in fast succession, warm and friendly, short",
            "a gentle vibraphone ding-dong, two quick soft notes, calm user interface notification",
            # P4 nach der ersten Sichtung: P1/P3 ergaben in 0,6 s meist nur einen Ton
            "two soft marimba notes in quick succession, rising interval, warm and calm notification, very short",
        ],
        "seeds": [701, 702, 703],
    },
    "stapel": {
        "ziel": (0.4, 0.8), "sekunden": 1.0, "ausblenden": 0.05, "lufs": -18.0, "modus": "anfang", "vorlauf": 0.08, "begrenzer": 6.0,
        "prompts": [
            "stack of playing cards squared and tapped on a table",
            "a deck of cards knocked lightly against a wooden table twice to straighten it, close-up",
        ],
        "seeds": [801, 802, 803, 804],
    },
}

# Ersatz-Seeds für aussortierte Kandidaten ("karte_03": 1103). Danach: --nur karte_03 --erneut
ERSATZ_SEED = {}

# Nach Sichtung der Spektrogramme und Messwerte aussortiert (bleiben erhalten, stehen in varianten.json mit Grund).
AUSSORTIERT = {
    "karte_03": "kein einzelner Kartenschlag, sondern eine Folge vieler Klicks (eher Riffeln)",
    "fehler_01": "fast nur Tiefbass (Schwerpunkt 76 Hz), auf Handy-Lautsprechern kaum hörbar",
    "fehler_03": "sehr dumpf und leer (Schwerpunkt 165 Hz), auf Handy-Lautsprechern kaum hörbar",
    "fehler_04": "fast nur Tiefbass (Schwerpunkt 117 Hz, Handy −33 dB)",
    "fehler_06": "fast nur Tiefbass (Schwerpunkt 160 Hz, Handy −26 dB)",
    "fehler_07": "fast nur Tiefbass (Schwerpunkt 70 Hz), auf Handy-Lautsprechern kaum hörbar",
    "flip_05": "dumpfes Grollen (Schwerpunkt 145 Hz), weder Wusch noch Glanz",
    "flip_06": "dumpfes Rauschen (Schwerpunkt 260 Hz), kein Glanz",
}

# ---------------------------------------------------------------------------------------------------------------
# Fassungen im Spiel (--spiel; Entscheidung 06.10.2026: die Favoriten aus tools/bewertung_sfx_ki.py kommen ins Spiel)
#   Schnitt wie beim Kandidaten, dann Tiefpass vor- und rückwärts mit der höchsten Grenzfrequenz zwischen 6 und 4 kHz,
#   bei der über 6 kHz höchstens −30 dB bleiben (Katzen-Leitplanke aus audio/sfx_README.md; process(leitplanke=True)).
#   Zusätzlich geprüft (am WAV und an den dekodierten OGG/M4A): über 10 kHz ≤ −50 dB, über 12 kHz ≤ −60 dB.
#   lufs: Ziel der Datei (höchste Momentan-Lautheit). Kurze Schläge erreichen es wegen der Spitzengrenze nicht ganz.
#   Im Spiel kommt die Stufe „toene“ dazu (game/scripts/app/sound.gd TON_DB, webclient/ton.js STUFEN_SPIEL). Abgleich:
#   karte erklingt oft und bleibt dezent; dran und sieg hörbar, nicht schrill; fehler auch auf dem Handy-Lautsprecher.
# ---------------------------------------------------------------------------------------------------------------
LEITPLANKE_HZ = 6000.0
LEITPLANKE_DB = -30.0
LEITPLANKE_SUCHE = (6000.0, 4000.0, 50.0)          # Grenzfrequenz: von, bis, Schritt (Hz)
LEITPLANKE_WEITER = ((10000.0, -50.0), (12000.0, -60.0))
OUT_SPIEL = os.path.join(OUT, "spiel")
SPIEL_GODOT = os.path.join(ROOT, "game", "assets", "sfx")
SPIEL_WEB = os.path.join(ROOT, "webclient", "sfx")
AAC_SPIEL = ["-c:a", "aac", "-b:a", "192k", "-cutoff", "8000"]   # AAC-LC (Safari/iPhone); 128k legt bei karte Rauschen über 6 kHz
# Abgleich (06.10.2026, Messwerte in audio/sfx_ki/README.md): karte und fehler sind kurze Schläge, ihre Lautheit
# begrenzt die Spitze (−1 dBTP). karte bleibt dort (dezent), ziehen gleich laut (erklingt ebenso oft), mischen und flip
# darüber, dran und sieg am lautesten, alle deutlich unter dem Mau-Ton. fehler_09 hat seinen Körper bei 165 Hz, den
# Handy-Lautsprecher nicht wiedergeben; ein Tiefen-Kuhschwanz (−6 dB unter 300 Hz) gibt Spitzenreserve für den
# hörbaren Teil (500–1000 Hz): auf dem Handy +2,5 dB, sonst +0,7 dB. ziehen_07 enthält schon im Rohton einen reinen
# Ton bei genau 6000 Hz (fs/8, wohl ein Rest des Modell-Dekoders; 14 dB über der Umgebung): schmale Kerbe.
SPIEL = {
    "karte":   {"kandidat": "karte_02",   "lufs": -24.5},
    "ziehen":  {"kandidat": "ziehen_07",  "lufs": -24.5, "kerben": (6000.0,)},
    "mischen": {"kandidat": "mischen_06", "lufs": -22.5},
    "flip":    {"kandidat": "flip_02",    "lufs": -20.5},
    "dran":    {"kandidat": "dran_04",    "lufs": -17.5},
    "fehler":  {"kandidat": "fehler_09",  "lufs": -16.5, "tiefen": (300.0, -6.0)},
    "sieg":    {"kandidat": "sieg_03",    "lufs": -16.5},
}


def candidates():
    """Alle Kandidaten in fester Reihenfolge: dict(id, ton, nr, prompt_nr, prompt, seed, sekunden)."""
    out = []
    for ton, cfg in SOUNDS.items():
        nr = 0
        for pi, prompt in enumerate(cfg["prompts"]):
            for seed in cfg["seeds"]:
                nr += 1
                cid = f"{ton}_{nr:02d}"
                out.append({"id": cid, "ton": ton, "nr": nr, "prompt_nr": pi + 1, "prompt": prompt,
                            "seed": ERSATZ_SEED.get(cid, seed), "sekunden": cfg["sekunden"]})
    return out


def select(cands, nur):
    if not nur:
        return cands
    keys = [k.strip() for k in nur.split(",") if k.strip()]
    return [c for c in cands if c["ton"] in keys or c["id"] in keys]


# ---------------------------------------------------------------------------------------------------------------
# Erzeugung
# ---------------------------------------------------------------------------------------------------------------

def load_pipeline():
    hf_home = os.environ.get("HF_HOME", "")
    if "Draw2Race-AudioLab" not in hf_home:
        sys.exit("HF_HOME zeigt nicht in die Werkstatt. Vorher: . E:\\Draw2Race-AudioLab\\env.ps1")
    import torch
    sys.path.insert(0, MOSS_REPO)
    from moss_soundeffect_v2 import MossSoundEffectPipeline
    t0 = time.time()
    pipe = MossSoundEffectPipeline.from_pretrained(MODEL_ID, torch_dtype=torch.bfloat16, device="cuda",
                                                   local_files_only=True)
    return pipe, time.time() - t0


def seeded_noise(engine, seeds):
    """Ersetzt generate_noise der Pipeline: Element i bekommt Rauschen aus einem eigenen Generator mit seeds[i],
    genau wie ein Einzelaufruf mit diesem Seed."""
    import torch

    def gen(shape, seed=None, rand_device="cpu", rand_torch_dtype=torch.float32, device=None, torch_dtype=None):
        assert shape[0] == len(seeds), (shape, seeds)
        parts = [torch.randn((1,) + tuple(shape[1:]), generator=torch.Generator(rand_device).manual_seed(int(s)),
                             device=rand_device, dtype=rand_torch_dtype) for s in seeds]
        noise = torch.cat(parts, 0)
        return noise.to(dtype=torch_dtype or engine.torch_dtype, device=device or engine.device)
    return gen


def generate_batch(pipe, batch, steps, cfg, shift):
    """Ein Stapel gleicher Dauer. Gibt Liste float32-Arrays (mono) und die Laufzeit zurück."""
    import numpy as np
    import torch
    seconds = batch[0]["sekunden"]
    assert all(c["sekunden"] == seconds for c in batch)
    engine = pipe.engine
    engine.generate_noise = seeded_noise(engine, [c["seed"] for c in batch])
    # Daueransage wie in der Pipeline ("<prompt> duration: X.Xs"), aber länger behalten (ROH_EXTRA), weil das Modell
    # kurze Ansagen nicht genau einhält.
    prompts = [f"{c['prompt'].strip()} duration: {seconds:.1f}s" for c in batch]
    try:
        torch.cuda.synchronize()
        t0 = time.time()
        audio = pipe(prompt=prompts, seconds=seconds + ROH_EXTRA, append_duration_suffix=False,
                     num_inference_steps=steps, cfg_scale=cfg, sigma_shift=shift, seed=0, progress_bar_cmd=lambda x: x)
        torch.cuda.synchronize()
        dt = time.time() - t0
    finally:
        del engine.generate_noise
    wav = audio.detach().float().cpu().numpy()          # (B, C, T)
    return [np.asarray(w[0], dtype=np.float32) for w in wav], dt


def run_generation(cands, args):
    import soundfile as sf
    import torch
    os.makedirs(OUT_ROH, exist_ok=True)
    todo = [c for c in cands if args.erneut or not os.path.exists(os.path.join(OUT_ROH, c["id"] + ".wav"))]
    if args.teil:
        k, n = (int(v) for v in args.teil.split("/"))
        todo = [c for i, c in enumerate(todo) if i % n == k - 1]
    print(f"Zu erzeugen: {len(todo)} Kandidaten (GPU {args.gpu})", flush=True)
    if not todo:
        return
    pipe, t_load = load_pipeline()
    print(f"Modell geladen in {t_load:.1f} s, belegt {torch.cuda.memory_allocated() / 2**30:.2f} GiB", flush=True)
    groups = {}
    for c in todo:
        groups.setdefault(c["ton"], []).append(c)
    for ton, items in groups.items():
        for i in range(0, len(items), args.stapel):
            batch = items[i:i + args.stapel]
            torch.cuda.reset_peak_memory_stats()
            waves, dt = generate_batch(pipe, batch, args.schritte, args.cfg, args.shift)
            peak = torch.cuda.max_memory_allocated() / 2**30
            for c, w in zip(batch, waves):
                path = os.path.join(OUT_ROH, c["id"] + ".wav")
                sf.write(path, w, FS, subtype="FLOAT")
                meta = dict(c, schritte=args.schritte, cfg=args.cfg, sigma_shift=args.shift, modell=MODEL_ID,
                            stapel=len(batch), laufzeit_stapel_s=round(dt, 2),
                            laufzeit_je_ton_s=round(dt / len(batch), 2), vram_spitze_gib=round(peak, 2),
                            gpu=args.gpu, erzeugt=time.strftime("%Y-%m-%d %H:%M:%S"))
                with open(os.path.join(OUT_ROH, c["id"] + ".json"), "w", encoding="utf-8") as f:
                    json.dump(meta, f, ensure_ascii=False, indent=1)
            print(f"  {', '.join(c['id'] for c in batch)}: {dt:.1f} s ({dt / len(batch):.1f} s je Ton), "
                  f"VRAM-Spitze {peak:.2f} GiB", flush=True)


def smoke_test(args):
    import numpy as np
    import soundfile as sf
    import torch
    pipe, t_load = load_pipeline()
    print(f"Laden: {t_load:.1f} s, belegt {torch.cuda.memory_allocated() / 2**30:.2f} GiB")
    c = dict(candidates()[0])
    os.makedirs(OUT_ROH, exist_ok=True)
    for size in (1, 4):
        batch = [dict(c, seed=c["seed"] + j) for j in range(size)]
        torch.cuda.reset_peak_memory_stats()
        waves, dt = generate_batch(pipe, batch, args.schritte, args.cfg, args.shift)
        peak = torch.cuda.max_memory_allocated() / 2**30
        w = waves[0]
        print(f"Stapel {size}: {dt:.1f} s gesamt, {dt / size:.1f} s je Ton, VRAM-Spitze {peak:.2f} GiB, "
              f"Länge {len(w) / FS:.2f} s, Spitze {20 * np.log10(np.abs(w).max() + 1e-12):.1f} dBFS")
    sf.write(os.path.join(args.rauchtest_ziel, "rauchtest.wav"), waves[0], FS, subtype="FLOAT")


# ---------------------------------------------------------------------------------------------------------------
# Nachbearbeitung und Messung
# ---------------------------------------------------------------------------------------------------------------

K_SHELF = ([1.53512485958697, -2.69169618940638, 1.19839281085285], [1.0, -1.69065929318241, 0.73248077421585])
K_HIGHPASS = ([1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621])


def momentary_max_lufs(x):
    """Höchste Momentan-Lautheit (400 ms, Schritt 10 ms, BS.1770 K-Bewertung bei 48 kHz), wie tools/make_sfx.py."""
    import numpy as np
    from scipy import signal
    pad = np.zeros(int(0.4 * FS))
    y = np.concatenate([pad, x, pad])
    y = signal.lfilter(*K_SHELF, y)
    y = signal.lfilter(*K_HIGHPASS, y)
    win, hop = int(0.4 * FS), int(0.01 * FS)
    c = np.concatenate([[0.0], np.cumsum(y ** 2)])
    ms = (c[win::hop] - c[:-win:hop]) / win
    return -0.691 + 10 * np.log10(ms.max() + 1e-20)


def true_peak_db(x):
    import numpy as np
    from scipy import signal
    return 20 * np.log10(np.abs(signal.resample_poly(x, 4, 1)).max() + 1e-20)


def envelope_db(x, win_ms=2.0):
    import numpy as np
    w = max(1, int(win_ms * FS / 1000))
    p = np.convolve(x ** 2, np.ones(w) / w, mode="same")
    return 10 * np.log10(p + 1e-20)


def cosine_fade(n, length, rising):
    import numpy as np
    m = min(n, max(1, int(length * FS)))
    u = np.linspace(0, 1, m)
    ramp = 0.5 - 0.5 * np.cos(np.pi * u)
    return ramp if rising else ramp[::-1]


def quiet_runs(quiet, min_len):
    """Läufe von True mit mindestens min_len Abtastwerten als Liste (a, b), b exklusiv."""
    import numpy as np
    q = np.concatenate([[False], quiet, [False]]).astype(np.int8)
    d = np.diff(q)
    starts, ends = np.nonzero(d == 1)[0], np.nonzero(d == -1)[0]
    return [(a, b) for a, b in zip(starts, ends) if b - a >= min_len]


def find_event(x, cfg):
    """Schnittgrenzen (start, end, info) nach SOUNDS-Modus; siehe Kommentar über SOUNDS."""
    import numpy as np
    env = envelope_db(x)
    top = env.max()
    ipk = int(env.argmax())
    cap = int(cfg["ziel"][1] * FS)
    if cfg["modus"] == "anfang":
        # Energiereichstes Fenster der Zieldauer (Schritt 1 ms), darin der erste deutliche Einsatz (−20 dB vom
        # Höchstwert im Fenster). So zählt ein einzelnes Klicken vor dem eigentlichen Ton nicht als Anfang.
        c = np.concatenate([[0.0], np.cumsum(x ** 2)])
        starts = np.arange(0, max(1, len(x) - cap), FS // 1000)
        w0 = int(starts[np.argmax(c[np.minimum(starts + cap, len(x))] - c[starts])])
        wenv = env[w0:w0 + cap]
        ref = w0 + int(wenv.argmax())
        anchor = w0 + int(np.nonzero(wenv > wenv.max() - 20.0)[0][0])
    else:
        ref = anchor = ipk
    runs = quiet_runs(env < top + TRIM_DB, int(0.03 * FS))
    lead = int(cfg["vorlauf"] * FS)
    before = [b for a, b in runs if b <= anchor]
    start = before[-1] if before else int(np.nonzero(env >= top + TRIM_DB)[0][0])
    if anchor - start > lead:
        # Kein stiller Abschnitt im Vorlauf: Fuß des Einsatzes (30 dB unter dem Anker), sonst leisester Punkt.
        win = env[anchor - lead:anchor + 1]
        foot = np.nonzero(win < env[anchor] - 30.0)[0]
        start = anchor - lead + (int(foot[-1]) if len(foot) else int(win.argmin()))
    start = max(0, start - int(0.002 * FS))
    if cfg["modus"] == "haupt":
        # Einzelschlag: Ende an der ersten Stille ≥ 60 ms nach dem Höchstwert (spätere Schläge fallen weg).
        gaps = [a for a, b in quiet_runs(env < top + TRIM_DB, int(0.06 * FS)) if a > ref]
        end = gaps[0] if gaps else int(np.nonzero(env >= top + TRIM_DB)[0][-1])
    else:
        # Folge (Riffeln, Klopfen, Glanz, Melodie): Lücken bleiben, nur die Stille am Ende des Zielfensters fällt weg.
        seg = np.nonzero(env[start:start + cap] >= top + TRIM_DB)[0]
        end = start + (int(seg[-1]) if len(seg) else min(cap, len(x) - start - 1))
        tail = env[start + cap:]
        if len(tail) and tail.max() >= top + TRIM_DB:
            end = start + cap                                # Ton läuft über das Ziel hinaus: gekürzt
            tail_on = np.nonzero(tail < top + TRIM_DB)[0]
            natural_end = start + cap + (int(tail_on[0]) if len(tail_on) else len(tail))
        else:
            natural_end = end
    end = min(len(x), end + int(0.002 * FS))
    natural = ((end if cfg["modus"] == "haupt" else max(end, natural_end)) - start) / FS
    cut = natural * FS > cap
    end = min(end, start + cap)
    return start, end, {"start_s": round(start / FS, 3), "anker_s": round(anchor / FS, 3),
                        "hoechstwert_s": round(ref / FS, 3), "natuerliche_dauer_s": round(natural, 3),
                        "gekuerzt": bool(cut)}


def process(raw, ton, lowpass, leitplanke=False, lufs=None, begrenzer=None, tiefen=None, kerben=()):
    """Bearbeitet einen Rohton. Gibt (Abtastwerte ohne Endstille, Info) zurück.

    leitplanke=False (Kandidaten): Tiefpass `lowpass` nur vorwärts (Butterworth 4. Ordnung).
    leitplanke=True (Fassung im Spiel): gleicher Schnitt wie beim Kandidaten (Grenzen aus der Kette mit `lowpass`),
      aber Tiefpass vor- und rückwärts (sosfiltfilt, Butterworth 4. Ordnung, zusammen 8. Ordnung = 48 dB/Oktave,
      phasenneutral) mit der höchsten Grenzfrequenz aus LEITPLANKE_SUCHE (6 → 4 kHz, Schritt 50 Hz), bei der der
      fertige Ton (nach Ein-/Ausblenden, Pegel und Begrenzer) über LEITPLANKE_HZ höchstens LEITPLANKE_DB hat.
    lufs/begrenzer: Ziel-Lautheit und größte Begrenzung abweichend von SOUNDS (für SPIEL).
    tiefen=(Hz, dB): Tiefen-Kuhschwanzfilter vor dem Tiefpass (nur mit leitplanke; SPIEL["fehler"]).
    kerben=(Hz, …): schmale Kerbfilter (Q 30, vor- und rückwärts) gegen Pfeiftöne des Modells (nur mit leitplanke)."""
    import numpy as np
    from scipy import signal
    cfg = SOUNDS[ton]
    x = raw.astype(np.float64) - float(np.mean(raw))
    x = signal.sosfilt(signal.butter(2, HIGHPASS_HZ, "high", fs=FS, output="sos"), x)
    xl = signal.sosfilt(signal.butter(4, lowpass, "low", fs=FS, output="sos"), x)
    start, end, info = find_event(xl, cfg)
    target = cfg["lufs"] if lufs is None else lufs
    max_gr = cfg.get("begrenzer", 3.0) if begrenzer is None else begrenzer
    if not leitplanke:
        y, li = finish(xl[start:end], cfg, target, max_gr)
        info.update(li)
        return y, info
    if tiefen:
        x = signal.lfilter(*low_shelf(*tiefen), x)
    for hz in kerben:
        x = signal.filtfilt(*signal.iirnotch(hz, 30.0, fs=FS), x)
    hi, lo, step = LEITPLANKE_SUCHE
    tried = []
    for fc in np.arange(hi, lo - 1e-6, -step):
        xf = signal.sosfiltfilt(signal.butter(4, float(fc), "low", fs=FS, output="sos"), x)
        y, li = finish(xf[start:end], cfg, target, max_gr)
        share = band_share_db(y, LEITPLANKE_HZ)
        tried.append((float(fc), round(share, 1)))
        if share <= LEITPLANKE_DB:
            break
    else:
        sys.exit(f"{ton}: Leitplanke ({LEITPLANKE_DB} dB über {LEITPLANKE_HZ:.0f} Hz) auch bei {lo:.0f} Hz verfehlt")
    info.update(li)
    info.update({"tiefpass_hz": float(fc), "tiefpass": "Butterworth 4. Ordnung vor- und rückwärts (sosfiltfilt)",
                 "ueber_6k_suche": tried[-3:], "ueber_6k_bei_6000_hz_db": tried[0][1]})
    if tiefen:
        info["tiefen_kuhschwanz"] = {"hz": tiefen[0], "db": tiefen[1]}
    if kerben:
        info["kerben_hz"] = list(kerben)
    return y, info


def low_shelf(f0, gain_db, slope=0.7):
    """Tiefen-Kuhschwanzfilter (Biquad nach RBJ Audio EQ Cookbook): (b, a)."""
    import numpy as np
    A = 10 ** (gain_db / 40)
    w = 2 * np.pi * f0 / FS
    c, s = np.cos(w), np.sin(w)
    al = s / 2 * np.sqrt((A + 1 / A) * (1 / slope - 1) + 2)
    r = 2 * np.sqrt(A) * al
    b = [A * ((A + 1) - (A - 1) * c + r), 2 * A * ((A - 1) - (A + 1) * c), A * ((A + 1) - (A - 1) * c - r)]
    a = [(A + 1) + (A - 1) * c + r, -2 * ((A - 1) + (A + 1) * c), (A + 1) + (A - 1) * c - r]
    return np.array(b) / a[0], np.array(a) / a[0]


def finish(x, cfg, target_lufs, max_gr_db):
    """Ein-/Ausblenden und Pegel eines geschnittenen Tons. Gibt (Abtastwerte, Info) zurück."""
    import numpy as np
    x = x.copy()
    n = len(x)
    x[:min(n, int(FADE_IN_S * FS))] *= cosine_fade(n, FADE_IN_S, True)
    fo = cosine_fade(n, cfg["ausblenden"], False)
    x[n - len(fo):] *= fo
    # Pegel: erst auf die Ziel-Lautheit, Spitzen darüber mit dem Begrenzer (höchstens max_gr_db dB), Rest
    # durch Absenken, bis die echte Spitze ≤ −1 dBTP ist.
    x *= 10 ** ((target_lufs - momentary_max_lufs(x)) / 20)
    ceiling = 10 ** ((PEAK_LIMIT_DB - 0.1) / 20)
    gr = 0.0
    if true_peak_db(x) > PEAK_LIMIT_DB - 0.1:
        x, gr = limit(x, ceiling, max_gr_db)
    g_peak = 10 ** ((PEAK_LIMIT_DB - 0.1 - true_peak_db(x)) / 20)
    if g_peak < 1.0:
        x *= g_peak
    return x, {"begrenzer_db": round(gr, 1),
               "nach_begrenzer_abgesenkt_db": round(abs(20 * np.log10(min(g_peak, 1.0))), 1)}


def spectrum(x):
    """Welch-Spektrum wie in measure() (sehr kurze Ausschnitte mit Stille auf 4096 Werte aufgefüllt)."""
    import numpy as np
    from scipy import signal
    xs = np.pad(x, (0, max(0, 4096 - len(x))))
    return signal.welch(xs, FS, nperseg=2048, noverlap=1536, window="hann")


def band_share_db(x, lo, hi=FS / 2):
    """Energieanteil des Bands [lo, hi) gegenüber dem ganzen Ton in dB (ungerundet)."""
    import numpy as np
    f, p = spectrum(x)
    m = (f >= lo) & (f < hi)
    return float(10 * np.log10(p[m].sum() / (p.sum() + 1e-30) + 1e-20))


def limit(x, ceiling, max_gr_db, lookahead=0.0015, release=0.04):
    """Spitzenbegrenzer mit Vorausschau: Verstärkung je Abtastwert so, dass |x| ≤ ceiling, höchstens max_gr_db
    Absenkung; gleitendes Minimum (± lookahead), Rückkehr mit Zeitkonstante `release`, danach Glättung (lookahead/2).
    Gibt (Signal, größte Absenkung in dB) zurück."""
    import numpy as np
    from scipy.ndimage import minimum_filter1d, uniform_filter1d
    floor = 10 ** (-max_gr_db / 20)
    req = np.clip(ceiling / np.maximum(np.abs(x), 1e-12), floor, 1.0)
    la = max(1, int(lookahead * FS))
    g = minimum_filter1d(req, size=2 * la + 1, mode="nearest")
    coef = 1.0 - np.exp(-1.0 / (release * FS))
    out = np.empty_like(g)
    prev = 1.0
    for i, v in enumerate(g):
        prev = min(v, prev + (1.0 - prev) * coef)
        out[i] = prev
    out = uniform_filter1d(out, size=la + 1, mode="nearest")
    return x * out, float(-20 * np.log10(out.min()))


def count_onsets(x, hi_db=-18.0, lo_db=-30.0):
    """Einsätze: Hüllkurve (5 ms) steigt über hi_db (vom Höchstwert), nachdem sie unter lo_db war."""
    env = envelope_db(x, 5.0)
    top = env.max()
    count, high = 0, False
    for v in env[::48]:
        if not high and v > top + hi_db:
            count, high = count + 1, True
        elif high and v < top + lo_db:
            high = False
    return count


def measure(x):
    import numpy as np
    from scipy import signal
    env = envelope_db(x)
    above = np.nonzero(env > env.max() - 40)[0]
    xs = np.pad(x, (0, max(0, 4096 - len(x))))           # sehr kurze Ausschnitte: mit Stille auffüllen
    f, p = signal.welch(xs, FS, nperseg=2048, noverlap=1536, window="hann")
    total = p.sum() + 1e-30

    def share(lo, hi=FS / 2):
        m = (f >= lo) & (f < hi)
        return round(10 * np.log10(p[m].sum() / total + 1e-20), 1)

    band = (f >= 3000) & (f < 4000)
    return {
        "dauer_s": round(len(x) / FS, 3),
        "dauer_ueber_m40db_s": round((above[-1] - above[0]) / FS, 3),
        "spitze_dbtp": round(true_peak_db(x), 1),
        "lufs_momentan_max": round(momentary_max_lufs(x), 1),
        "rms_dbfs": round(10 * np.log10(np.mean(x ** 2) + 1e-20), 1),
        "schwerpunkt_hz": round(float((f * p).sum() / total)),
        "ueber_8k_db": share(8000),
        "ueber_6k_db": share(6000),
        "ueber_12k_db": share(12000),
        "anteil_3_4k_db": share(3000, 4000),
        "spitze_3_4k_db": round(10 * np.log10(p[band].max() / p.max() + 1e-20), 1),
        "einsaetze": count_onsets(x),
        # Handy-Lautsprecher (wie tools/make_sfx.py): Lautheitsverlust mit Hochpass 800 Hz, 12 dB/Oktave
        "handy_db": round(momentary_max_lufs(signal.sosfilt(signal.butter(2, 800, "high", fs=FS, output="sos"), x))
                          - momentary_max_lufs(x), 1),
    }


def measure_raw(raw):
    """Original: Spitze, Inhalt über −45 dB (von–bis), Rauschabstand (Hüllkurven-Höchstwert gegen 10-%-Quantil),
    leer (< −50 dBFS) bzw. leise (< −30 dBFS)."""
    import numpy as np
    x = raw.astype(np.float64)
    peak = float(np.abs(x).max())
    env = envelope_db(x)
    above = np.nonzero(env > env.max() + TRIM_DB)[0]
    return {"dauer_s": round(len(x) / FS, 3),
            "spitze_dbfs": round(20 * np.log10(peak + 1e-12), 1),
            "rms_dbfs": round(10 * np.log10(np.mean(x ** 2) + 1e-20), 1),
            "inhalt_von_s": round(above[0] / FS, 3) if len(above) else None,
            "inhalt_bis_s": round(above[-1] / FS, 3) if len(above) else None,
            "rauschabstand_db": round(float(env.max() - np.percentile(env, 10)), 1),
            "einsaetze": count_onsets(x),
            "leer": bool(peak < 10 ** (-50 / 20)), "leise": bool(peak < 10 ** (-30 / 20))}


def encode(wav_path, base):
    ff = ["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-map_metadata", "-1", "-ac", "1", "-ar", str(FS)]
    subprocess.run(ff + ["-c:a", "libvorbis", "-q:a", "6", base + ".ogg"], check=True)
    subprocess.run(ff + ["-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", base + ".m4a"], check=True)


def spectrogram_png(wav_path):
    out = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", wav_path, "-lavfi",
                          "showspectrumpic=s=420x180:legend=1:scale=log:fscale=lin:color=intensity:gain=2",
                          "-frames:v", "1", "-f", "image2pipe", "-vcodec", "png", "pipe:1"],
                         capture_output=True, check=True).stdout
    return out


def overview(ton, items, out_png, roh):
    """Übersicht je Ton: ffmpeg showspectrumpic je Kandidat, mit Beschriftung zu einem Bild zusammengesetzt."""
    from PIL import Image, ImageDraw, ImageFont
    tiles = []
    for c in items:
        path = os.path.join(OUT_ROH if roh else OUT, c["id"] + ".wav")
        img = Image.open(io.BytesIO(spectrogram_png(path))).convert("RGB")
        if roh:
            m = c.get("messwerte_roh", {})
            label = (f"{c['id']}  P{c['prompt_nr']}  seed {c['seed']}  Inhalt {m.get('inhalt_von_s')}-"
                     f"{m.get('inhalt_bis_s')} s  Spitze {m.get('spitze_dbfs')} dBFS")
        else:
            m = c.get("messwerte", {})
            label = (f"{c['id']}  P{c['prompt_nr']}  seed {c['seed']}  {m.get('dauer_s')} s  "
                     f">8k {m.get('ueber_8k_db')} dB  Handy {m.get('handy_db')} dB")
        if c.get("aussortiert"):
            label += "  [aussortiert]"
        tiles.append((img, label))
    try:
        font = ImageFont.load_default(size=15)
    except TypeError:
        font = ImageFont.load_default()
    cols = 3
    tw = max(t[0].width for t in tiles)
    th = max(t[0].height for t in tiles) + 24
    rows = (len(tiles) + cols - 1) // cols
    head = 30 + 18 * len(SOUNDS[ton]["prompts"])
    sheet = Image.new("RGB", (cols * tw, head + rows * th), (24, 24, 28))
    draw = ImageDraw.Draw(sheet)
    draw.text((8, 6), f"{ton} ({'roh' if roh else 'bearbeitet'})", fill=(255, 220, 120), font=font)
    for i, p in enumerate(SOUNDS[ton]["prompts"]):
        draw.text((8, 28 + 18 * i), f"P{i + 1}: {p}", fill=(200, 200, 200), font=font)
    for i, (img, label) in enumerate(tiles):
        x0, y0 = (i % cols) * tw, head + (i // cols) * th
        draw.text((x0 + 6, y0 + 4), label, fill=(235, 235, 235), font=font)
        sheet.paste(img, (x0, y0 + 24))
    sheet.save(out_png)


def run_postprocessing(cands, args):
    import numpy as np
    import soundfile as sf
    os.makedirs(OUT_SPEK, exist_ok=True)
    index_path = os.path.join(OUT, "varianten.json")
    old = {}
    if os.path.exists(index_path):
        with open(index_path, encoding="utf-8") as f:
            old = {c["id"]: c for c in json.load(f).get("kandidaten", [])}
    done = []
    for c in cands:
        raw_path = os.path.join(OUT_ROH, c["id"] + ".wav")
        if not os.path.exists(raw_path):
            print(f"  fehlt: {c['id']}")
            continue
        with open(os.path.join(OUT_ROH, c["id"] + ".json"), encoding="utf-8") as f:
            meta = json.load(f)
        raw, sr = sf.read(raw_path, dtype="float32")
        assert sr == FS
        mr = measure_raw(raw)
        x, info = process(raw, c["ton"], args.tiefpass)
        x = np.concatenate([x, np.zeros(int(TAIL_S * FS))])
        base = os.path.join(OUT, c["id"])
        sf.write(base + ".wav", x, FS, subtype="PCM_24")
        encode(base + ".wav", base)
        m = measure(x[: len(x) - int(TAIL_S * FS)])
        m.update(info)
        cfg = SOUNDS[c["ton"]]
        m["ziel_s"] = list(cfg["ziel"])
        m["ziel_lufs"] = cfg["lufs"]
        m["kuerzer_als_ziel"] = bool(m["dauer_s"] < cfg["ziel"][0])
        entry = {k: meta[k] for k in ("id", "ton", "nr", "prompt_nr", "prompt", "seed", "sekunden", "schritte", "cfg",
                                      "sigma_shift", "laufzeit_je_ton_s", "vram_spitze_gib", "gpu", "erzeugt")}
        entry["tiefpass_hz"] = args.tiefpass
        entry["messwerte_roh"] = mr
        entry["messwerte"] = m
        entry["dateien"] = {k: os.path.relpath(base + e, ROOT).replace("\\", "/")
                            for k, e in (("wav", ".wav"), ("ogg", ".ogg"), ("m4a", ".m4a"))}
        entry["dateien"]["roh"] = os.path.relpath(raw_path, ROOT).replace("\\", "/")
        if c["id"] in old and "bewertung" in old[c["id"]]:
            entry["bewertung"] = old[c["id"]]["bewertung"]
        if c["id"] in AUSSORTIERT:
            entry["aussortiert"] = AUSSORTIERT[c["id"]]
        old[c["id"]] = entry
        done.append(entry)
        flag = " LEER" if mr["leer"] else ""
        print(f"  {c['id']}: {m['dauer_s']:.3f} s (natürlich {info['natuerliche_dauer_s']:.2f} s), "
              f"{m['lufs_momentan_max']} LUFS, {m['spitze_dbtp']} dBTP, Schwerpunkt {m['schwerpunkt_hz']} Hz, "
              f">8k {m['ueber_8k_db']} dB, Einsätze {m['einsaetze']}{flag}", flush=True)
    order = {c["id"]: i for i, c in enumerate(candidates())}
    allc = sorted(old.values(), key=lambda e: order.get(e["id"], 10**6))
    index = {
        "modell": MODEL_ID, "lizenz_modell": "Apache-2.0",
        "einstellungen": {"schritte": args.schritte, "cfg": args.cfg, "sigma_shift": args.shift, "abtastrate": FS,
                          "hochpass_hz": HIGHPASS_HZ, "tiefpass_hz": args.tiefpass, "stille_schwelle_db": TRIM_DB,
                          "einblenden_s": FADE_IN_S, "spitze_max_dbtp": PEAK_LIMIT_DB, "endstille_s": TAIL_S,
                          "lautheit": "höchste Momentan-Lautheit (400 ms, BS.1770)"},
        "toene": {t: {"ziel_s": list(v["ziel"]), "sekunden": v["sekunden"], "ausblenden_s": v["ausblenden"],
                      "ziel_lufs": v["lufs"], "prompts": v["prompts"], "seeds": v["seeds"]} for t, v in SOUNDS.items()},
        "kandidaten": allc,
    }
    with open(index_path, "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=1)
    by_ton = {}
    for e in allc:
        by_ton.setdefault(e["ton"], []).append(e)
    for ton in sorted({e["ton"] for e in done}):
        overview(ton, by_ton[ton], os.path.join(OUT_SPEK, ton + ".png"), roh=False)
        overview(ton, by_ton[ton], os.path.join(OUT_SPEK, ton + "_roh.png"), roh=True)
    print(f"Bearbeitet: {len(done)}; varianten.json: {len(allc)} Kandidaten", flush=True)


# ---------------------------------------------------------------------------------------------------------------
# Fassungen im Spiel (--spiel)
# ---------------------------------------------------------------------------------------------------------------

def decode(path):
    import numpy as np
    out = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(FS),
                          "pipe:1"], capture_output=True, check=True).stdout
    return np.frombuffer(out, dtype="<f4").astype(np.float64)


def measure_spiel(x):
    """measure() plus Anteil über 10 kHz und Handy-Lautheit (Lautheit mit Hochpass 800 Hz)."""
    m = measure(x)
    m["ueber_10k_db"] = round(band_share_db(x, 10000.0), 1)
    m["handy_lufs"] = round(m["lufs_momentan_max"] + m["handy_db"], 1)
    m["linien_2_6k"] = narrow_lines(x, 2000.0, 6000.0)
    return m


def narrow_lines(x, lo, hi, prominence_db=12.0):
    """Schmale Linien (Piepen) im Band [lo, hi): Welch-Spektrum (8192) gegen geglättete Grundlinie (Median über 101
    Werte, wie tools/hoerseite_sfx_ki.py). Liste (Hz, Überhöhung dB, Pegel gegen die stärkste Spitze dB), stärkste zuerst."""
    import numpy as np
    from scipy import signal
    from scipy.ndimage import median_filter
    xs = np.pad(x, (0, max(0, 8192 - len(x))))
    f, p = signal.welch(xs, FS, nperseg=8192)
    pdb = 10 * np.log10(p + 1e-20)
    prom = pdb - median_filter(pdb, size=101)
    top = pdb.max()
    out = [(int(f[i]), round(float(prom[i]), 1), round(float(pdb[i] - top), 1)) for i in range(1, len(f) - 1)
           if lo <= f[i] < hi and prom[i] > prominence_db and pdb[i] > top - 60 and pdb[i] >= pdb[i - 1]
           and pdb[i] >= pdb[i + 1]]
    return sorted(out, key=lambda v: -v[1])[:3]


def game_levels():
    """Stufe „normal“ der Spieltöne und der Mau-Töne in dB aus game/scripts/app/sound.gd (TON_DB, MAU_DB)."""
    import re
    try:
        with open(os.path.join(ROOT, "game", "scripts", "app", "sound.gd"), encoding="utf-8") as f:
            src = f.read()
        ton = float(re.search(r'TON_DB := \{[^}]*"normal": (-?[\d.]+)', src).group(1))
        mau = float(re.search(r'MAU_DB := \{[^}]*"normal": (-?[\d.]+)', src).group(1))
        return ton, mau
    except (OSError, AttributeError):
        return None, None


def spectrogram_file(wav_path, png_path):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-lavfi",
                    "showspectrumpic=s=640x200:legend=1:scale=log:fscale=lin:color=intensity:gain=2",
                    "-frames:v", "1", png_path], check=True)
    from PIL import Image
    Image.open(png_path).convert("RGB").quantize(colors=64, method=Image.Quantize.MEDIANCUT).save(png_path, optimize=True)


def run_spiel(args):
    """Favoriten mit Katzen-Leitplanke fertig machen: audio/sfx_ki/spiel/<ton>.wav|.ogg|.m4a|.png und messwerte.json,
    dann game/assets/sfx/<ton>.ogg sowie webclient/sfx/<ton>.ogg und .m4a. Die Rohdateien in roh/ werden nur gelesen."""
    import numpy as np
    import soundfile as sf
    os.makedirs(OUT_SPIEL, exist_ok=True)
    ton_db, mau_db = game_levels()
    ref = {}
    for name in ("mau", "mau_mau"):
        p = os.path.join(SPIEL_GODOT, name + ".ogg")
        if os.path.exists(p):
            ref[name] = measure_spiel(decode(p))
    rows = {}
    problems = []
    for ton, sp in SPIEL.items():
        cid = sp["kandidat"]
        raw, sr = sf.read(os.path.join(OUT_ROH, cid + ".wav"), dtype="float32")
        assert sr == FS
        x, info = process(raw, ton, LOWPASS_HZ, leitplanke=True, lufs=sp["lufs"], begrenzer=sp.get("begrenzer"),
                          tiefen=sp.get("tiefen"), kerben=sp.get("kerben", ()))
        x = np.concatenate([x, np.zeros(int(TAIL_S * FS))])
        base = os.path.join(OUT_SPIEL, ton)
        sf.write(base + ".wav", x, FS, subtype="PCM_24")
        # bitexact: feste Ogg-Seriennummer und keine Kodierer-Kennung, damit ein neuer Lauf dieselben Dateien ergibt
        ff = ["ffmpeg", "-y", "-loglevel", "error", "-i", base + ".wav", "-map_metadata", "-1", "-ac", "1",
              "-ar", str(FS), "-fflags", "+bitexact", "-flags:a", "+bitexact"]
        subprocess.run(ff + ["-c:a", "libvorbis", "-q:a", "6", base + ".ogg"], check=True)
        subprocess.run(ff + AAC_SPIEL + ["-movflags", "+faststart", base + ".m4a"], check=True)
        m = measure_spiel(x[: len(x) - int(TAIL_S * FS)])
        m.update(info)
        m["kandidat"] = cid
        m["ziel_lufs"] = sp["lufs"]
        m["datei_s"] = round(len(x) / FS, 3)
        for ext in ("ogg", "m4a"):
            mm = measure_spiel(decode(base + "." + ext))
            m[ext] = {k: mm[k] for k in ("lufs_momentan_max", "spitze_dbtp", "ueber_6k_db", "ueber_10k_db",
                                         "ueber_12k_db", "spitze_3_4k_db", "handy_db")}
            m[ext]["bytes"] = os.path.getsize(base + "." + ext)
        for label, mm in (("wav", m), ("ogg", m["ogg"]), ("m4a", m["m4a"])):
            limits = ((LEITPLANKE_HZ, LEITPLANKE_DB),) + LEITPLANKE_WEITER
            for (hz, lim), key in zip(limits, ("ueber_6k_db", "ueber_10k_db", "ueber_12k_db")):
                if mm[key] > lim:
                    problems.append(f"{ton} {label}: über {hz / 1000:.0f} kHz {mm[key]} dB (Grenze {lim} dB)")
            if mm["spitze_dbtp"] > PEAK_LIMIT_DB + 0.3:
                problems.append(f"{ton} {label}: Spitze {mm['spitze_dbtp']} dBTP")
        if ton_db is not None:
            m["im_spiel_lufs"] = round(m["lufs_momentan_max"] + ton_db, 1)
            if "mau" in ref:
                m["gegen_mau_db"] = round(m["im_spiel_lufs"] - (ref["mau"]["lufs_momentan_max"] + mau_db), 1)
        spectrogram_file(base + ".wav", base + ".png")
        rows[ton] = m
    if problems:
        sys.exit("Leitplanke verletzt, nichts ins Spiel kopiert:\n  " + "\n  ".join(problems))
    for ton in (() if args.ohne_kopie else SPIEL):
        base = os.path.join(OUT_SPIEL, ton)
        shutil.copyfile(base + ".ogg", os.path.join(SPIEL_GODOT, ton + ".ogg"))
        shutil.copyfile(base + ".ogg", os.path.join(SPIEL_WEB, ton + ".ogg"))
        shutil.copyfile(base + ".m4a", os.path.join(SPIEL_WEB, ton + ".m4a"))
    out = {"stand": time.strftime("%Y-%m-%d"), "modell": MODEL_ID, "lizenz_modell": "Apache-2.0",
           "lizenz_dateien": "CC BY-NC 4.0 (Projektlizenz)",
           "leitplanke": {"ueber_hz": LEITPLANKE_HZ, "hoechstens_db": LEITPLANKE_DB, "suche_hz": list(LEITPLANKE_SUCHE),
                          "weitere": [list(v) for v in LEITPLANKE_WEITER]},
           "kodierung": {"ogg": "Vorbis q6, mono, 48 kHz", "m4a": " ".join(AAC_SPIEL[1:]) + ", mono, 48 kHz"},
           "stufe_normal_db": {"toene": ton_db, "mau_ton": mau_db}, "bezug": ref, "toene": rows}
    with open(os.path.join(OUT_SPIEL, "messwerte.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    z = lambda v, nk=1: f"{v:.{nk}f}".replace(".", ",").replace("-", "−")   # noqa: E731
    print("| Ton | Kandidat | Tiefpass | Dauer | Lautheit (Ziel) | Spitze | Handy | über 6/10/12 kHz | OGG über 6 kHz | "
          "M4A über 6 kHz | im Spiel | gegen Mau |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for ton, m in rows.items():
        print(f"| {ton} | `{m['kandidat']}` | {z(m['tiefpass_hz'] / 1000, 2)} kHz | {z(m['dauer_s'], 2)} s | "
              f"{z(m['lufs_momentan_max'])} LUFS ({z(m['ziel_lufs'])}) | {z(m['spitze_dbtp'])} dBTP | "
              f"{z(m['handy_db'])} dB | {z(m['ueber_6k_db'])}/{z(m['ueber_10k_db'])}/{z(m['ueber_12k_db'])} dB | "
              f"{z(m['ogg']['ueber_6k_db'])} dB | {z(m['m4a']['ueber_6k_db'])} dB | "
              f"{z(m.get('im_spiel_lufs', float('nan')))} LUFS | {z(m.get('gegen_mau_db', float('nan')))} dB |")
    for name, mm in ref.items():
        print(f"Bezug {name}: {mm['lufs_momentan_max']} LUFS, {mm['spitze_dbtp']} dBTP, Handy {mm['handy_db']} dB")
    if args.ohne_kopie:
        print("Nur audio/sfx_ki/spiel/ geschrieben (--ohne-kopie).", flush=True)
    else:
        print(f"Ins Spiel kopiert: {', '.join(SPIEL)} (game/assets/sfx, webclient/sfx). Danach tools/godot_import.ps1.",
              flush=True)


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")         # Tabellen mit „−“ auch ohne PYTHONUTF8
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--nur", help="Töne oder Kandidaten, kommagetrennt (karte,flip_03)")
    ap.add_argument("--gpu", type=int, default=0)
    ap.add_argument("--teil", help="k/n: nur jeden n-ten Kandidaten ab k (zwei GPUs parallel)")
    ap.add_argument("--stapel", type=int, default=3, help="Kandidaten je Modellaufruf (gleicher Ton)")
    ap.add_argument("--erneut", action="store_true", help="vorhandene Rohdateien neu erzeugen")
    ap.add_argument("--nur-erzeugen", action="store_true")
    ap.add_argument("--nur-nachbearbeiten", action="store_true")
    ap.add_argument("--rauchtest", action="store_true")
    ap.add_argument("--rauchtest-ziel", default=os.environ.get("TEMP", "."))
    ap.add_argument("--schritte", type=int, default=STEPS)
    ap.add_argument("--cfg", type=float, default=CFG)
    ap.add_argument("--shift", type=float, default=SHIFT)
    ap.add_argument("--tiefpass", type=float, default=LOWPASS_HZ)
    ap.add_argument("--spiel", action="store_true", help="Favoriten mit Katzen-Leitplanke ins Spiel (ohne GPU)")
    ap.add_argument("--ohne-kopie", action="store_true", help="mit --spiel: nur audio/sfx_ki/spiel/ schreiben")
    args = ap.parse_args()

    os.environ["CUDA_VISIBLE_DEVICES"] = str(args.gpu)   # vor dem Import von torch
    os.environ.setdefault("TORCHDYNAMO_DISABLE", "1")    # kein torch.compile/Triton (Windows)
    if not shutil.which("ffmpeg") and not args.nur_erzeugen:
        sys.exit("ffmpeg fehlt im PATH")
    if args.rauchtest:
        smoke_test(args)
        return
    if args.spiel:
        run_spiel(args)
        return
    cands = select(candidates(), args.nur)
    if not cands:
        sys.exit(f"Keine Kandidaten für --nur {args.nur}")
    if not args.nur_nachbearbeiten:
        run_generation(cands, args)
    if not args.nur_erzeugen:
        run_postprocessing(cands, args)


if __name__ == "__main__":
    main()
