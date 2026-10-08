"""Kandidaten fuer das Katzenschnurren (Aussetzen-Karte) mit MOSS-SoundEffect v2.0 erzeugen und nachbearbeiten.
Entwurf; gewaehlt (08.10.2026): schnurren3_03 wurde unveraendert als game/assets/sfx/schnurren.ogg uebernommen (Ton "schnurren" beim Aussetzen). Nutzt Funktionen aus tools/make_sfx_moss.py (Schnitt, Pegel, Begrenzer).
Aufruf: . E:\Draw2Race-AudioLab\env.ps1; & E:\Draw2Race-AudioLab\moss-sfx\.venv\Scripts\python.exe tools\make_schnurren.py [--nur-nachbearbeiten]
Rohdaten liegen ausserhalb des Repos: E:\Draw2Race-AudioLab\schnurren_roh
"""
import argparse, json, os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ["TORCHDYNAMO_DISABLE"] = "1"
import make_sfx_moss as m

ROH = r"E:\Draw2Race-AudioLab\schnurren_roh"
OUT = os.path.join(m.ROOT, "audio", "entwurf", "schnurren")
LUFS = -20.0
PROMPTS = [
    ("nah", "a cat purring softly, close-up, content and relaxed, steady low rumble, quiet room, no meow"),
    ("schlaefrig", "sleepy cat purr, very gentle slow soft rumbling, cozy, close microphone, no meow"),
    ("triller", "a cat purring warmly with one soft little trill at the start, gentle and short, no meow"),
    ("kaetzchen", "a small kitten purring quietly, soft breathy gentle rumble, cozy, no meow"),
    # Runde 2 nach der Klassifikation (AudioSet hielt Runde 1 meist fuer Magenknurren)
    ("hausKatze", "domestic cat purring, rhythmic purr with soft breathing in and out, recorded close with a microphone, calm"),
    ("schnurrt", "the purring of a happy cat lying on a lap, warm continuous purr, gentle inhale and exhale, indoor"),
    ("sanft", "soft cat purr, light rhythmic vibrating purr with gentle airy texture, relaxed pet, close-up"),
    ("kurz", "short contented cat purr, a few seconds, soft and rhythmic, then fading gently, cozy living room"),
]
SEEDS = [1101, 1102]
LENGTHS = {"nah": 1.4, "schlaefrig": 1.8, "triller": 1.4, "kaetzchen": 1.2, "hausKatze": 1.6, "schnurrt": 1.6, "sanft": 1.4, "kurz": 1.4}


def cands():
    out = []
    for pi, (name, p) in enumerate(PROMPTS):
        for si, s in enumerate(SEEDS):
            out.append({"id": f"schnurren_{pi*len(SEEDS)+si+1:02d}", "name": name, "prompt": p, "seed": s, "laenge": LENGTHS[name]})
    return out


def erzeugen(cs, gpu):
    os.environ["CUDA_VISIBLE_DEVICES"] = str(gpu)
    import soundfile as sf
    os.makedirs(ROH, exist_ok=True)
    todo = [c for c in cs if not os.path.exists(os.path.join(ROH, c["id"] + ".wav"))]
    if not todo:
        return
    pipe, _ = m.load_pipeline()
    for i in range(0, len(todo), 4):
        b = todo[i:i + 4]
        for c in b:
            c["sekunden"] = 2.0
        waves, dt = m.generate_batch(pipe, b, m.STEPS, m.CFG, m.SHIFT)
        for c, w in zip(b, waves):
            sf.write(os.path.join(ROH, c["id"] + ".wav"), w, m.FS, subtype="FLOAT")
            json.dump({k: c[k] for k in ("id", "prompt", "seed")}, open(os.path.join(ROH, c["id"] + ".json"), "w"))
        print(f"Stapel {i//4+1}: {dt:.0f} s", flush=True)


def modulation(x):
    """Pulsrate der Huellkurve (Hz) und Schaerfe (Spitze / Median im Bereich 10-60 Hz)."""
    import numpy as np
    from scipy import signal
    env = np.abs(signal.hilbert(x))
    env = signal.sosfiltfilt(signal.butter(2, 120, "low", fs=m.FS, output="sos"), env)
    env = env[::48] - env[::48].mean()
    f, p = signal.welch(env, 1000, nperseg=min(len(env), 512))
    sel = (f >= 10) & (f <= 60)
    k = int(np.argmax(p[sel]))
    return round(float(f[sel][k]), 1), round(float(p[sel][k] / (np.median(p[sel]) + 1e-20)), 1)


def nachbearbeiten(cs):
    import numpy as np, soundfile as sf
    m.FADE_IN_S = 0.15
    os.makedirs(OUT, exist_ok=True)
    res = []
    for c in cs:
        raw, _ = sf.read(os.path.join(ROH, c["id"] + ".wav"), dtype="float32")
        cfg = {"ziel": (1.0, c["laenge"]), "modus": "anfang", "vorlauf": 0.05, "ausblenden": 0.3, "lufs": LUFS, "begrenzer": 3.0}
        m.SOUNDS["_schn"] = cfg
        x, info = m.process(raw, "_schn", m.LOWPASS_HZ, leitplanke=True)
        y = np.concatenate([x, np.zeros(int(m.TAIL_S * m.FS))])
        wav = os.path.join(OUT, c["id"] + ".wav")
        sf.write(wav, y.astype("float32"), m.FS, subtype="PCM_24")
        ff = ["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-map_metadata", "-1", "-ac", "1", "-ar", str(m.FS)]
        subprocess.run(ff + ["-c:a", "libvorbis", "-q:a", "6", os.path.join(OUT, c["id"] + ".ogg")], check=True)
        # Messung am dekodierten Ogg
        dec = m.decode(os.path.join(OUT, c["id"] + ".ogg"))
        rate, scharf = modulation(x)
        r = {"id": c["id"], "name": c["name"], "prompt": c["prompt"], "seed": c["seed"],
             "dauer_s": round(len(y) / m.FS, 2), "lufs": round(float(m.momentary_max_lufs(x)), 1),
             "spitze_dbtp": round(float(m.true_peak_db(x)), 1), "tiefpass_hz": info["tiefpass_hz"],
             "ueber_6k_db": round(float(m.band_share_db(x, 6000)), 1), "ueber_6k_ogg_db": round(float(m.band_share_db(dec, 6000)), 1),
             "puls_hz": rate, "puls_scharfe": scharf}
        print(r, flush=True)
        res.append(r)
    json.dump(res, open(os.path.join(OUT, "messwerte.json"), "w"), indent=1, ensure_ascii=False)



# ---------------------------------------------------------------------------------------------------------------
# Runde 2: fuer Handy-Lautsprecher (nichts Tiefes unter ~300 Hz, Schnurren im Mittenbereich erkennbar)
# Aufruf: ... make_schnurren.py --runde2 [--nur-nachbearbeiten]
# ---------------------------------------------------------------------------------------------------------------
OUT2 = os.path.join(m.ROOT, "audio", "entwurf", "schnurren2")
PROMPTS2 = [
    ("hell", "close-mic cat purring, raspy and breathy, bright"),
    ("knistert", "kitten purr close to the microphone, crackly texture"),
    ("triller", "cat purring with soft trill"),
    ("rasselnd", "cat purring with audible breathing in and out, rattly raspy purr, close microphone, crisp and clear"),
    ("schnurrend", "bright fast pulsing cat purr, small cat, whirring and fluttering, close-up, no meow"),
    ("motor", "happy cat purring like a tiny motor, rough rattling purr, airy breath, close microphone"),
]
SEEDS2 = [1201, 1202, 1203]
PRESETS = {  # Pulsstaerke, Exciter-Anteil, Rauschschicht (dB relativ), Laenge (s)
    "hell": (0.6, 0.8, -14, 1.4), "knistert": (0.6, 0.8, -14, 1.2), "triller": (0.5, 0.8, -16, 1.5),
    "rasselnd": (0.6, 0.9, -14, 1.6), "schnurrend": (0.5, 0.7, -16, 1.2), "motor": (0.7, 0.9, -13, 1.4),
}
R1_NEU = ("schnurren_01", "schnurren_03", "schnurren_04", "schnurren_08", "schnurren_09", "schnurren_11",
          "schnurren_13", "schnurren_14", "schnurren_16")


def cands2():
    out = []
    n = 0
    for name, p in PROMPTS2:
        for s in SEEDS2:
            n += 1
            out.append({"id": f"s2_{n:02d}", "name": name, "prompt": p, "seed": s, "quelle": "neu", "preset": name})
    for c in cands():  # Varianten aus der ersten Runde (Rohdaten schnurren_NN.wav), neu aufbereitet
        if c["id"] in R1_NEU:
            out.append({"id": c["id"], "name": "r1-" + c["name"], "prompt": c["prompt"], "seed": c["seed"],
                        "quelle": "runde1", "preset": "hell"})
    return out


def peaking(f0, gain_db, q):
    import numpy as np
    A = 10 ** (gain_db / 40)
    w = 2 * np.pi * f0 / m.FS
    al = np.sin(w) / (2 * q)
    b = [1 + al * A, -2 * np.cos(w), 1 - al * A]
    a = [1 + al / A, -2 * np.cos(w), 1 - al / A]
    return np.array(b) / a[0], np.array(a) / a[0]


def bp(x, lo, hi, order=2):
    from scipy import signal
    return signal.sosfiltfilt(signal.butter(order, [lo, hi], "band", fs=m.FS, output="sos"), x)


def lp(x, f, order=2):
    from scipy import signal
    return signal.sosfiltfilt(signal.butter(order, f, "low", fs=m.FS, output="sos"), x)


def hp(x, f, order=4):
    from scipy import signal
    return signal.sosfiltfilt(signal.butter(order, f, "high", fs=m.FS, output="sos"), x)


def rms(x):
    import numpy as np
    return float(np.sqrt(np.mean(x ** 2)) + 1e-12)


def aufbereiten(raw, preset, seed=0):
    """Rohschnurren -> handytauglich: Exciter (Obertoene aus dem Bass), Puls (aus dem Original auf das Mittenband
    uebertragen, bei schwachem Puls dezent synthetisch ergaenzt) auf Rassel-Schicht, Praesenz 1-3,5 kHz, Hochpass 250 Hz."""
    import numpy as np
    from scipy import signal
    a_puls, exc, noise_db, laenge = PRESETS[preset]
    rng = np.random.default_rng(seed)
    x = raw.astype(np.float64) - float(np.mean(raw))
    low = bp(x, 35, 320)
    mid = lp(hp(x, 280), 9000)
    drive = np.tanh(3.5 * low / rms(low))
    harm = bp(drive - np.mean(drive), 400, 3500)
    env = np.abs(signal.hilbert(low)) + 0.5 * np.abs(signal.hilbert(bp(x, 280, 1200)))
    slow, fast = lp(env, 7), lp(env, 45)
    pn = (fast - slow) / (slow + 1e-9)
    pn = pn / (np.std(pn) + 1e-9)
    f_p, schaerfe = modulation(low)
    f_p = f_p if 18 <= f_p <= 28 else 23.0
    jit = lp(rng.standard_normal(len(x)), 3)
    jit = jit / (np.std(jit) + 1e-9)
    phase = 2 * np.pi * np.cumsum(f_p * (1 + 0.03 * jit)) / m.FS
    syn = (0.5 + 0.5 * np.cos(phase)) ** 1.6
    syn = (syn - syn.mean()) / (syn.std() + 1e-9)
    p = pn if schaerfe >= 8 else 0.6 * pn + 0.8 * syn
    p = p / (np.std(p) + 1e-9)
    gain = np.clip(1 + a_puls * p, 0.12, 2.6)
    rass = bp(rng.standard_normal(len(x)), 700, 3600)
    rass = rass / rms(rass) * rms(mid) * 10 ** (noise_db / 20)
    atem = lp(np.abs(signal.hilbert(mid)), 6)
    atem = atem / (atem.max() + 1e-9)
    y = mid * gain + exc * rms(mid) * (harm / rms(harm)) * 0.7 * np.clip(1 + 0.8 * p, 0.1, 2.6) + rass * gain * atem
    for f0, g, q in ((1200, 3.0, 0.9), (2300, 4.0, 0.9), (3400, 2.5, 1.0)):
        y = signal.lfilter(*peaking(f0, g, q), y)
    y = hp(lp(y, 8000, 4), 250, 4)
    return y, laenge, {"puls_quelle": "original" if schaerfe >= 8 else "original+synthetisch",
                       "puls_roh_hz": f_p, "puls_roh_scharfe": schaerfe}


def handy_modell(x):
    """Lautsprecher-Modell: Hochpass 400 Hz (Butterworth 8. Ordnung, steil), Tiefpass 8 kHz, Resonanz +5 dB um 1,5 kHz."""
    from scipy import signal
    y = signal.sosfilt(signal.butter(8, 400, "high", fs=m.FS, output="sos"), x)
    y = signal.sosfilt(signal.butter(4, 8000, "low", fs=m.FS, output="sos"), y)
    return signal.lfilter(*peaking(1500, 5.0, 1.6), y)


def puls_tiefe(x):
    """Modulationstiefe der Huellkurve im Band 500 Hz - 4 kHz bei 15-35 Hz: (Tiefe, Frequenz Hz).
    Tiefe = Amplitude der Huellkurven-Schwingung / Mittelwert, im gleichmaessigen Kern (ohne Ein-/Ausblenden)."""
    import numpy as np
    from scipy import signal
    b = bp(x, 500, 4000)
    env = lp(np.abs(signal.hilbert(b)), 60)
    n = len(env)
    core = env[int(0.2 * m.FS): n - int(0.35 * m.FS)]
    if len(core) < 0.3 * m.FS:
        core = env[int(0.1 * m.FS): n - int(0.1 * m.FS)]
    core = core[::24]
    fs2 = m.FS / 24
    w = np.hanning(len(core))
    spec = np.abs(np.fft.rfft((core - core.mean()) * w, 8192)) * 2 / w.sum()
    fr = np.fft.rfftfreq(8192, 1 / fs2)
    sel = (fr >= 15) & (fr <= 35)
    k = int(np.argmax(spec[sel]))
    return round(float(spec[sel][k] / (core.mean() + 1e-12)), 2), round(float(fr[sel][k]), 1)


def messen2(x, sim):
    import numpy as np
    d = {"lufs": round(float(m.momentary_max_lufs(x)), 1), "spitze_dbtp": round(float(m.true_peak_db(x)), 1),
         "mitten_500_4k_db": round(float(m.band_share_db(x, 500, 4000)), 1),
         "unter_300_db": round(float(m.band_share_db(x, 0, 300)), 1)}
    d["sim_mitten_500_4k_db"] = round(float(m.band_share_db(sim, 500, 4000)), 1)
    d["sim_lufs"] = round(float(m.momentary_max_lufs(sim)), 1)
    d["sim_pegelverlust_db"] = round(d["sim_lufs"] - d["lufs"], 1)
    d["tiefe"], d["tiefe_hz"] = puls_tiefe(x)
    d["sim_tiefe"], d["sim_tiefe_hz"] = puls_tiefe(sim)
    return d


def ogg(wav, path):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-map_metadata", "-1", "-ac", "1", "-ar", str(m.FS),
                    "-c:a", "libvorbis", "-q:a", "6", path], check=True)


def handy_probe(r, zd, sim, tmp):
    import numpy as np, soundfile as sf
    """Handy-Simulation als Hoerprobe, auf die Lautheit des Originals gehoben (der Verlust steht in den Messwerten)."""
    sg = 10 ** ((r["lufs"] - r["sim_lufs"]) / 20)
    s2 = sim * min(sg, 10 ** ((-1.5 - m.true_peak_db(sim)) / 20))
    w = os.path.join(tmp, r["id"] + "_handy.wav")
    sf.write(w, s2.astype("float32"), m.FS, subtype="PCM_24")
    ogg(w, os.path.join(tmp, r["id"] + "_handy.ogg"))


def nachbearbeiten2(cs, tmp):
    import numpy as np, soundfile as sf
    m.FADE_IN_S = 0.12
    os.makedirs(tmp, exist_ok=True)
    res = []
    for c in cs:
        raw, _ = sf.read(os.path.join(ROH, c["id"] + ".wav"), dtype="float32")
        y, laenge, info = aufbereiten(raw, c["preset"], c["seed"])
        cfg = {"ziel": (0.8, laenge), "modus": "anfang", "vorlauf": 0.05, "ausblenden": 0.3, "lufs": LUFS, "begrenzer": 4.0}
        m.SOUNDS["_schn"] = cfg
        start, end, ev = m.find_event(y, cfg)
        z, li = m.finish(y[start:end], cfg, LUFS, 4.0)
        z = np.concatenate([z, np.zeros(int(m.TAIL_S * m.FS))])
        wav = os.path.join(tmp, c["id"] + ".wav")
        sf.write(wav, z.astype("float32"), m.FS, subtype="PCM_24")
        ogg(wav, os.path.join(tmp, c["id"] + ".ogg"))
        zd = m.decode(os.path.join(tmp, c["id"] + ".ogg"))
        sim = handy_modell(zd)
        r = {"id": c["id"], "name": c["name"], "prompt": c["prompt"], "seed": c["seed"], "quelle": c["quelle"],
             "dauer_s": round(len(z) / m.FS, 2)}
        r.update(info)
        r.update(messen2(zd, sim))
        handy_probe(r, zd, sim, tmp)
        print(r, flush=True)
        res.append(r)
    vgl = []  # Vergleich: Kandidaten der ersten Runde unveraendert durch dasselbe Handy-Modell
    for i in ("schnurren_01", "schnurren_09", "schnurren_14"):
        zd = m.decode(os.path.join(m.ROOT, "audio", "entwurf", "schnurren", i + ".ogg"))
        sim = handy_modell(zd)
        r = {"id": "alt_" + i, "name": "Runde 1: " + i, "dauer_s": round(len(zd) / m.FS, 2)}
        r.update(messen2(zd, sim))
        handy_probe(r, zd, sim, tmp)
        print(r, flush=True)
        vgl.append(r)
    return res, vgl


def auswahl(res, n=10):
    """Verwirft Kandidaten, die in der Handy-Simulation fast verschwinden, ihren Puls verlieren, zu tief (technisch,
    Tremolo) oder zu leise geraten sind; Rangfolge nach natuerlicher Pulstiefe (Ziel 0,7) und echtem Puls aus dem Original."""
    ok = [r for r in res if r["sim_mitten_500_4k_db"] > -3.0 and 0.35 <= r["sim_tiefe"] <= 1.0
          and 18 <= r["sim_tiefe_hz"] <= 28.5 and r["sim_pegelverlust_db"] > -4.0 and r["lufs"] > -21.5]
    ok.sort(key=lambda r: -(-abs(r["sim_tiefe"] - 0.7) + (0.15 if r["puls_quelle"] == "original" else 0)
                            - 0.02 * max(0.0, -r["sim_pegelverlust_db"])))
    return ok[:n]


def seite2(keep, vgl, anzahl=27):
    """Hoerseite audio/entwurf/schnurren2/hoeren.html (lokal, ohne externe Dateien)."""
    import html
    old = open(os.path.join(m.ROOT, "audio", "entwurf", "schnurren", "hoeren.html"), encoding="utf-8").read()
    css = old[old.index("<style>"):old.index("</style>") + 8]
    cards = []
    for r in keep:
        herkunft = ("Rohton aus Runde 1, neu aufbereitet" if r["quelle"] == "runde1" else "neu erzeugt (Runde 2)")
        puls = ("Puls aus dem Original" if r["puls_quelle"] == "original"
                else "Puls aus dem Original, dezent synthetisch verstaerkt (Original pulsierte schwach)")
        cards.append(f"""<section class="card"><h2>{r['nr']} <span class="tag">{html.escape(r['name'])}</span></h2>
<p class="sub">{herkunft} - Seed {r['seed']} - {r['dauer_s']} s</p>
<p class="sub">Original (am Laptop/Kopfhoerer)</p><audio controls preload="none" src="{r['nr']}.ogg"></audio>
<p class="sub">So etwa am Handy (Lautsprecher-Modell, auf gleiche Lautheit gehoben)</p><audio controls preload="none" src="{r['nr']}_handy.ogg"></audio>
<p class="facts">{puls}. Handy-Modell: Puls {r['sim_tiefe_hz']} Hz, Modulationstiefe {r['sim_tiefe']} (Original {r['tiefe']}) im Band 500 Hz-4 kHz;
Mittenanteil des Originals {r['mitten_500_4k_db']} dB, unter 300 Hz {r['unter_300_db']} dB; Pegelverlust durch das Handy {r['sim_pegelverlust_db']} dB;
{r['lufs']} LUFS, Spitze {r['spitze_dbtp']} dBTP.</p>
<details><summary>Prompt</summary><p class="facts">{html.escape(r['prompt'])}</p></details></section>""")
    alt = "".join(f"""<section class="card"><h2>Vergleich: {html.escape(r['name'])} <span class="tag">Runde 1</span></h2>
<p class="sub">Dieselbe Handy-Simulation auf den alten Ton (auf gleiche Lautheit gehoben, sonst waere fast nichts zu hoeren)</p>
<audio controls preload="none" src="{r['id']}_handy.ogg"></audio>
<p class="facts">Ohne Anhebung verliert dieser Ton {abs(r['sim_pegelverlust_db'])} dB; nur {r['mitten_500_4k_db']} dB seiner Energie liegen bei 500 Hz-4 kHz.</p></section>""" for r in vgl)
    page = f"""<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Katzenschnurren Runde 2</title>
{css}</head><body><main>
<h1>Katzenschnurren, Runde 2: handytauglich</h1><p class="lead">{len(keep)} Kandidaten (beste von {anzahl} geprueften, MOSS-SoundEffect v2.0, Apache 2.0), alle -20 LUFS, mono, 0,8-1,6 s, weich ein- und ausgeblendet. Offline, lokal.</p>
<div class="hint"><b>Was anders ist:</b> Hochpass 250 Hz, Praesenz bei 1-3,5 kHz, Obertoene aus dem Bass (Exciter), eine leise Rassel-Schicht im Mittenband und der Schnurr-Puls (ca. 20-26 Hz) auf dem Mittenband. So erkennt das Ohr das Schnurren auch ohne Bass.<br>
<b>Handy-Modell:</b> Hochpass 400 Hz (steil), Tiefpass 8 kHz, +5 dB Resonanz um 1,5 kHz. Modulationstiefe = Schwankung der Huellkurve im Band 500 Hz-4 kHz relativ zum Mittelwert; echtes Schnurren etwa 0,4-0,9, ueber 1 klingt eher nach Tremolo.<br>
<b>Ehrlich:</b> Niemand hat gehoert; die Eignung stuetzt sich auf Messwerte. Bitte am echten Handy anhoeren (Hoerseite vom Laptop aus ist nur eine Naeherung). Verworfen wurde, was im Handy-Modell zu leise, zu tief moduliert oder ohne Puls blieb.</div>
{''.join(cards)}<h2>Zum Vergleich: Runde 1 am Handy-Modell</h2>{alt}</main></body></html>"""
    open(os.path.join(OUT2, "hoeren.html"), "w", encoding="utf-8").write(page)


def haupt2(a):
    import shutil
    cs = cands2()
    if not a.nur_nachbearbeiten:
        erzeugen(cs[:len(PROMPTS2) * len(SEEDS2)], a.gpu)
    tmp = os.path.join(ROH, "r2_tmp")
    res, vgl = nachbearbeiten2(cs, tmp)
    keep = auswahl(res)
    os.makedirs(OUT2, exist_ok=True)
    for f in os.listdir(OUT2):
        if f.endswith((".ogg", ".json")):
            os.remove(os.path.join(OUT2, f))
    for i, r in enumerate(keep, 1):
        r["nr"] = f"schnurren2_{i:02d}"
        for suf in (".ogg", "_handy.ogg"):
            shutil.copy(os.path.join(tmp, r["id"] + suf), os.path.join(OUT2, r["nr"] + suf))
    for r in vgl:
        shutil.copy(os.path.join(tmp, r["id"] + "_handy.ogg"), os.path.join(OUT2, r["id"] + "_handy.ogg"))
    json.dump({"behalten": keep, "verworfen": [r for r in res if r not in keep], "vergleich_runde1": vgl},
              open(os.path.join(OUT2, "messwerte.json"), "w"), indent=1, ensure_ascii=False)
    seite2(keep, vgl, len(res))
    print("behalten:", [(r["nr"], r["id"], r["sim_tiefe"], r["sim_mitten_500_4k_db"]) for r in keep])


# ---------------------------------------------------------------------------------------------------------------
# Runde 3: weicher rund um schnurren2_09 (= Rohton s2_10, "rasselnd", Seed 1201, Preset rasselnd)
# Aufruf: ... make_schnurren.py --runde3 [--nur-nachbearbeiten]
# ---------------------------------------------------------------------------------------------------------------
OUT3 = os.path.join(m.ROOT, "audio", "entwurf", "schnurren3")
P09 = "cat purring with audible breathing in and out, rattly raspy purr, close microphone, crisp and clear"
# Einstellungen von 09 (Runde 2): Puls 0.6, Exciter 0.9, Rauschschicht -14 dB, Praesenz 1200/2300/3400 Hz +3/+4/+2,5 dB,
# Tiefpass 8 kHz (4. Ordnung), Hochpass 250 Hz, Laenge 1,62 s.
R3 = {  # name: (Beschreibung, Rohton, Parameter)
    "09_ref": ("09 unveraendert (Bezug, Runde 2)", "s2_10", None),
    "etwas_weicher": ("09 etwas weicher", "s2_10", dict(a=0.60, exc=0.75, noise=-20, peaks=((1200, 2.0, .9), (2300, 2.0, .9), (3400, 0.0, 1.0)), lp=5500, hp=220)),
    "weicher": ("09 weicher", "s2_10", dict(a=0.60, exc=0.65, noise=-26, peaks=((1200, 1.5, .9), (2300, 1.0, .9)), lp=4800, hp=200)),
    "deutlich_weicher": ("09 deutlich weicher", "s2_10", dict(a=0.60, exc=0.5, noise=None, peaks=((1000, 1.0, .9),), lp=4000, hp=190)),
    "waermer": ("09 waermer", "s2_10", dict(a=0.60, exc=0.6, noise=-24, peaks=((500, 2.5, .8), (900, 1.5, .8), (2300, 0.5, .9)), lp=4200, hp=170)),
    "ohne_rasseln": ("09 ohne Rassel-Schicht", "s2_10", dict(a=0.60, exc=0.7, noise=None, peaks=((1200, 2.0, .9), (2300, 1.0, .9)), lp=5000, hp=210)),
    "mehr_puls": ("09 weich, Puls etwas staerker", "s2_10", dict(a=0.95, exc=0.6, noise=-26, peaks=((1200, 1.5, .9), (2300, 1.0, .9)), lp=4600, hp=200)),
    "tp35": ("09 mit Tiefpass 3,5 kHz", "s2_10", dict(a=0.60, exc=0.6, noise=-26, peaks=((1000, 1.5, .9), (2000, 1.0, .9)), lp=3500, hp=210)),
}
NEU3 = [("neu_a", 1301), ("neu_b", 1302), ("neu_c", 1303), ("neu_d", 1304)]
NEU3_PARAM = dict(a=0.60, exc=0.6, noise=-26, peaks=((1200, 1.5, .9), (2300, 1.0, .9)), lp=4600, hp=200)


def aufbereiten3(raw, P, seed):
    """Wie aufbereiten(), aber mit freien Parametern: Praesenz-Peaks, Tiefpass, Hochpass, optionale Rassel-Schicht."""
    import numpy as np
    from scipy import signal
    x = raw.astype(np.float64) - float(np.mean(raw))
    rng = np.random.default_rng(seed)
    low = bp(x, 35, 320)
    mid = lp(hp(x, 280), 9000)
    drive = np.tanh(3.5 * low / rms(low))
    harm = bp(drive - np.mean(drive), 400, 3500)
    env = np.abs(signal.hilbert(low)) + 0.5 * np.abs(signal.hilbert(bp(x, 280, 1200)))
    slow, fast = lp(env, 7), lp(env, 45)
    pn = (fast - slow) / (slow + 1e-9)
    pn = pn / (np.std(pn) + 1e-9)
    f_p, schaerfe = modulation(low)
    f_p = f_p if 18 <= f_p <= 28 else 23.0
    jit = lp(rng.standard_normal(len(x)), 3)
    jit = jit / (np.std(jit) + 1e-9)
    phase = 2 * np.pi * np.cumsum(f_p * (1 + 0.03 * jit)) / m.FS
    syn = (0.5 + 0.5 * np.cos(phase)) ** 1.6
    syn = (syn - syn.mean()) / (syn.std() + 1e-9)
    p = pn if schaerfe >= 8 else 0.6 * pn + 0.8 * syn
    p = p / (np.std(p) + 1e-9)
    gain = np.clip(1 + P["a"] * p, 0.12, 2.6)
    y = mid * gain + P["exc"] * rms(mid) * (harm / rms(harm)) * 0.7 * np.clip(1 + 0.8 * p, 0.1, 2.6)
    if P["noise"] is not None:
        rass = bp(rng.standard_normal(len(x)), 700, 3600)
        rass = rass / rms(rass) * rms(mid) * 10 ** (P["noise"] / 20)
        atem = lp(np.abs(signal.hilbert(mid)), 6)
        atem = atem / (atem.max() + 1e-9)
        y = y + rass * gain * atem
    for f0, g, q in P["peaks"]:
        if g:
            y = signal.lfilter(*peaking(f0, g, q), y)
    y = hp(lp(y, P["lp"], 4), P["hp"], 4)
    return y, {"puls_quelle": "original" if schaerfe >= 8 else "original+synthetisch", "puls_roh_hz": f_p, "puls_roh_scharfe": schaerfe}


def messen3(zd, sim):
    d = messen2(zd, sim)
    d["ueber_3k_db"] = round(float(m.band_share_db(zd, 3000)), 1)
    d["sim_ueber_3k_db"] = round(float(m.band_share_db(sim, 3000)), 1)
    d["ueber_5k_db"] = round(float(m.band_share_db(zd, 5000)), 1)
    return d


def nachbearbeiten3(tmp):
    import numpy as np, soundfile as sf
    m.FADE_IN_S = 0.12
    os.makedirs(tmp, exist_ok=True)
    jobs = [(k, v[0], v[1], v[2], 1201) for k, v in R3.items() if v[2] is not None]
    for k, s in NEU3:
        jobs.append((k, f"Neu erzeugt (Seed {s}), weiche Aufbereitung", f"s3_{k}", NEU3_PARAM, s))
    res = []
    for k, name, rohid, P, seed in jobs:
        raw, _ = sf.read(os.path.join(ROH, rohid + ".wav"), dtype="float32")
        y, info = aufbereiten3(raw, P, seed)
        cfg = {"ziel": (0.8, 1.62), "modus": "anfang", "vorlauf": 0.05, "ausblenden": 0.3, "lufs": LUFS, "begrenzer": 4.0}
        m.SOUNDS["_schn"] = cfg
        start, end, ev = m.find_event(y, cfg)
        z, li = m.finish(y[start:end], cfg, LUFS, 4.0)
        z = np.concatenate([z, np.zeros(int(m.TAIL_S * m.FS))])
        wav = os.path.join(tmp, k + ".wav")
        sf.write(wav, z.astype("float32"), m.FS, subtype="PCM_24")
        ogg(wav, os.path.join(tmp, k + ".ogg"))
        zd = m.decode(os.path.join(tmp, k + ".ogg"))
        sim = handy_modell(zd)
        r = {"id": k, "name": name, "roh": rohid, "seed": seed, "dauer_s": round(len(z) / m.FS, 2), "param": {kk: vv for kk, vv in P.items()}}
        r.update(info)
        r.update(messen3(zd, sim))
        handy_probe(r, zd, sim, tmp)
        print({kk: vv for kk, vv in r.items() if kk != "param"}, flush=True)
        res.append(r)
    # Bezug 09 und Runde-2-Vergleich, unveraendert gemessen
    ref = []
    for nr in ("schnurren2_09", "schnurren2_01", "schnurren2_02", "schnurren2_08"):
        zd = m.decode(os.path.join(m.ROOT, "audio", "entwurf", "schnurren2", nr + ".ogg"))
        sim = handy_modell(zd)
        r = {"id": nr, "name": "Runde 2: " + nr, "dauer_s": round(len(zd) / m.FS, 2)}
        r.update(messen3(zd, sim))
        handy_probe(r, zd, sim, tmp)
        print(r, flush=True)
        ref.append(r)
    return res, ref


def haupt3(a):
    import shutil
    if not a.nur_nachbearbeiten:
        erzeugen([{"id": f"s3_{k}", "prompt": P09, "seed": s} for k, s in NEU3], a.gpu)
    tmp = os.path.join(ROH, "r3_tmp")
    res, ref = nachbearbeiten3(tmp)
    os.makedirs(OUT3, exist_ok=True)
    for r in res + ref:
        if r["id"].startswith("schnurren2_"):
            continue
        pass
    json.dump({"kandidaten": res, "bezug_runde2": ref}, open(os.path.join(OUT3, "messwerte_roh.json"), "w"), indent=1, ensure_ascii=False)
    print("fertig; Auswahl und Seite per --runde3-seite")


# --- Runde 3: Ablage und Hoerseite aus messwerte_roh.json (Aufruf: make_schnurren.py --runde3-seite) ---
NOTIZEN3 = {
    "etwas_weicher": "Naechster an 09: Praesenz bei 3,4 kHz weg, 1,2/2,3 kHz nur +2 dB, Rassel-Schicht -20 statt -14 dB, Tiefpass 5,5 kHz, Hochpass 220 Hz.",
    "ohne_rasseln": "Wie 09, aber ganz ohne Rassel-Schicht (kein Rauschen im Mittenband); Praesenz nur +2/+1 dB, Tiefpass 5 kHz.",
    "mehr_puls": "Weich wie 'weicher', Puls aber staerker eingestellt (0,95 statt 0,6); die Huellkurve begrenzt die Tiefe, hoerbar nur leicht deutlicher.",
    "weicher": "Praesenz +1,5/+1 dB, Rassel -26 dB, Exciter 0,65, Tiefpass 4,8 kHz, Hochpass 200 Hz.",
    "tp35": "Wie 'weicher', aber Tiefpass 3,5 kHz: am wenigsten Luft und Kratzen, am meisten 'Pelz'.",
    "deutlich_weicher": "Keine Rassel-Schicht, nur +1 dB bei 1 kHz, Exciter 0,5, Tiefpass 4 kHz, Hochpass 190 Hz.",
    "waermer": "Anhebung um 500/900 Hz statt im Praesenzbereich, Tiefpass 4,2 kHz, Hochpass 170 Hz: runder, etwas 'waermer', Rassel -24 dB.",
    "neu_d": "Neu erzeugt (Seed 1304, Prompt von 09), weiche Aufbereitung. Original pulsierte schwach, Puls dezent synthetisch ergaenzt; Tiefe 0,9 ist eher gleichmaessig-tremoloartig.",
    "neu_b": "Neu erzeugt (Seed 1302, Prompt von 09), weiche Aufbereitung. Echter Puls, etwas leiser im Handy-Mittenband.",
    "neu_c": "Neu erzeugt (Seed 1303, Prompt von 09), weiche Aufbereitung. Puls zum Teil synthetisch, Tiefe 0,9.",
}
REIHE3 = ["etwas_weicher", "ohne_rasseln", "mehr_puls", "weicher", "tp35", "deutlich_weicher", "waermer", "neu_d", "neu_b", "neu_c"]


def seite3():
    import html, shutil
    d = json.load(open(os.path.join(OUT3, "messwerte_roh.json"), encoding="utf-8"))
    by = {r["id"]: r for r in d["kandidaten"]}
    ref = {r["id"]: r for r in d["bezug_runde2"]}
    tmp = os.path.join(ROH, "r3_tmp")
    for f in os.listdir(OUT3):
        if f.endswith(".ogg"):
            os.remove(os.path.join(OUT3, f))
    shutil.copy(os.path.join(m.ROOT, "audio", "entwurf", "schnurren2", "schnurren2_09.ogg"), os.path.join(OUT3, "bezug_09.ogg"))
    shutil.copy(os.path.join(tmp, "schnurren2_09_handy.ogg"), os.path.join(OUT3, "bezug_09_handy.ogg"))
    out = []
    cards = []
    r9 = ref["schnurren2_09"]

    def card(nr, titel, r, note, tag):
        return f"""<section class="card"><h2>{nr} <span class="tag">{html.escape(titel)}</span></h2>
<p class="sub">{html.escape(note)}</p>
<p class="sub">Original (Laptop/Kopfhoerer)</p><audio controls preload="none" src="{tag}.ogg"></audio>
<p class="sub">So etwa am Handy (Lautsprecher-Modell, auf gleiche Lautheit gehoben)</p><audio controls preload="none" src="{tag}_handy.ogg"></audio>
<p class="facts">Handy-Modell: Mittenanteil 500 Hz-4 kHz {r['sim_mitten_500_4k_db']} dB, Energie ueber 3 kHz {r['sim_ueber_3k_db']} dB (Original {r['ueber_3k_db']} dB, ueber 5 kHz {r['ueber_5k_db']} dB); Puls {r['sim_tiefe_hz']} Hz, Tiefe {r['sim_tiefe']}; {r['lufs']} LUFS, Spitze {r['spitze_dbtp']} dBTP, {r['dauer_s']} s.</p></section>"""

    cards.append(card("Bezug", "schnurren2_09 (Runde 2)", r9, "Das war dein Favorit; Rohton s2_10, 'rasselnd', Seed 1201.", "bezug_09"))
    for i, k in enumerate(REIHE3, 1):
        r = by[k]
        nr = f"schnurren3_{i:02d}"
        for suf in (".ogg", "_handy.ogg"):
            shutil.copy(os.path.join(tmp, k + suf), os.path.join(OUT3, nr + suf))
        r["nr"] = nr
        out.append(r)
        cards.append(card(nr, r["name"] if not k.startswith("neu") else "neu " + k[-1], r, NOTIZEN3[k], nr))
    json.dump({"bezug_09": r9, "kandidaten": out, "runde2_vergleich": [ref[x] for x in ref if x != "schnurren2_09"]},
              open(os.path.join(OUT3, "messwerte.json"), "w"), indent=1, ensure_ascii=False)
    os.remove(os.path.join(OUT3, "messwerte_roh.json"))
    old = open(os.path.join(m.ROOT, "audio", "entwurf", "schnurren2", "hoeren.html"), encoding="utf-8").read()
    css = old[old.index("<style>"):old.index("</style>") + 8]
    page = f"""<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Katzenschnurren Runde 3</title>
{css}</head><body><main>
<h1>Katzenschnurren, Runde 3: weicher rund um 09</h1><p class="lead">Oben dein Favorit 09 als Bezug, darunter 10 Kandidaten, geordnet von nah an 09 bis weiter weg. Alle -20 LUFS, mono, ca. 1,6 s. Offline, lokal.</p>
<div class="hint"><b>Was 09 ausmacht:</b> Rohton s2_10 (Prompt 'rasselnd': Atmen rein/raus, rasselig, nah am Mikro), Seed 1201. Echter, scharfer Puls im Rohton (25 Hz, Schaerfe 19), flache Tiefe 0,4, wenig Bass, viel Mittenanteil. Die Aufbereitung war allerdings die haerteste von Runde 2: Praesenz +3/+4/+2,5 dB bei 1,2/2,3/3,4 kHz, Rassel-Schicht -14 dB, Tiefpass 8 kHz - daher das Kratzige.<br>
<b>Jetzt:</b> dieselbe Aufnahme, Puls unveraendert, aber weniger Praesenz, kaum/keine Rassel-Schicht, Tiefpass 3,5-5,5 kHz, Hochpass 170-220 Hz. Energie ueber 3 kHz sinkt am Handy von {r9['sim_ueber_3k_db']} dB (09) auf etwa -27 bis -34 dB; der Mittenanteil bleibt klar (Runde 1 lag bei -15 dB, hier -1 bis -2 dB).<br>
<b>Ehrlich:</b> Niemand hat gehoert; Messwerte, keine Ohren. Bitte am echten Handy anhoeren.</div>
{''.join(cards)}</main></body></html>"""
    open(os.path.join(OUT3, "hoeren.html"), "w", encoding="utf-8").write(page)
    print([(r["nr"], r["id"]) for r in out])


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--nur-nachbearbeiten", action="store_true")
    ap.add_argument("--gpu", type=int, default=0)
    ap.add_argument("--runde2", action="store_true")
    ap.add_argument("--runde3", action="store_true")
    ap.add_argument("--runde3-seite", action="store_true")
    a = ap.parse_args()
    if a.runde3_seite:
        seite3()
        sys.exit(0)
    if a.runde3:
        haupt3(a)
        sys.exit(0)
    if a.runde2:
        haupt2(a)
        sys.exit(0)
    cs = cands()
    if not a.nur_nachbearbeiten:
        erzeugen(cs, a.gpu)
    nachbearbeiten(cs)
