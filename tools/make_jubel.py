"""Kandidaten fuer den Sieg-Jubel (jubelnde Menge am Spielende) mit MOSS-SoundEffect v2.0 erzeugen und nachbearbeiten.
Entwurf (Stand 10.10.2026): gewählt Runde 3, Nr. 01 und 06 (jubel_1/jubel_2 im Spiel, zufällig). Nutzt tools/make_sfx_moss.py und die Handy-Simulation aus tools/make_schnurren.py.
Aufruf: . E:\\Draw2Race-AudioLab\\env.ps1; & E:\\Draw2Race-AudioLab\\moss-sfx\\.venv\\Scripts\\python.exe tools\\make_jubel.py [--nur-nachbearbeiten]
Rohdaten liegen ausserhalb des Repos: E:\\Draw2Race-AudioLab\\jubel_roh
Ergebnis: audio/entwurf/jubel/ (jubel_NN.ogg, jubel_NN_handy.ogg, messwerte.json, hoeren.html)
"""
import argparse, html, json, os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ["TORCHDYNAMO_DISABLE"] = "1"
import make_sfx_moss as m
import make_schnurren as s

ROH = r"E:\Draw2Race-AudioLab\jubel_roh"
OUT = os.path.join(m.ROOT, "audio", "entwurf", "jubel")
LUFS = -18.5          # Sieg-Glockenspiel: -16,5; Mau: -11,4. Menge ist dichtes, dauerndes Rauschen -> wirkt bei gleicher Zahl lauter
NO_WORDS = "no intelligible words, no booing, friendly"
SEKUNDEN = 6.0
# (Name, Prompt, Laenge s, Ausblenden s, Notiz)
PROMPTS = [
    ("familie", "a small group of five happy friends and family cheering and clapping around a table, joyful whoops and laughter, cozy living room, " + NO_WORDS,
     4.5, 1.3, "Kleine begeisterte Gruppe am Tisch: nah, warm, wenig Hall."),
    ("halle", "distant crowd cheering in a large indoor hall, warm swelling roar of joyful cheers and applause, far away, hall reverb, " + NO_WORDS,
     5.5, 1.8, "Jubel aus der Ferne: grosse Halle, Hall, weich anschwellend."),
    ("juhu", "crowd cheering with applause, a few whistles and happy whoops, joyful celebration, " + NO_WORDS,
     5.0, 1.5, "Jubel mit Applaus, vereinzelte Pfiffe und Juhu-Rufe ohne Woerter."),
    ("kurz", "a short burst of happy cheering that turns into warm applause and fades out gently, " + NO_WORDS,
     3.6, 1.3, "Kurzer Jubel, dann Applaus als Ausklang."),
    ("ovation", "a happy audience clapping warmly and cheering after a great performance, concert hall acoustics, " + NO_WORDS,
     5.0, 1.6, "Publikum nach einem Auftritt: Applaus vorne, Jubel darueber."),
]
SEEDS = [2101, 2102]


def cands():
    out = []
    for pi, (name, p, L, fo, note) in enumerate(PROMPTS):
        for si, sd in enumerate(SEEDS):
            out.append({"id": f"jubel_{pi*len(SEEDS)+si+1:02d}", "name": name, "prompt": p, "seed": sd, "laenge": L,
                        "aus": fo, "notiz": note, "sekunden": SEKUNDEN})
    return out


def erzeugen(cs, gpu):
    os.environ["CUDA_VISIBLE_DEVICES"] = str(gpu)
    import soundfile as sf
    os.makedirs(ROH, exist_ok=True)
    todo = [c for c in cs if not os.path.exists(os.path.join(ROH, c["id"] + ".wav"))]
    if not todo:
        return
    pipe, _ = m.load_pipeline()
    for i in range(0, len(todo), 2):
        b = todo[i:i + 2]
        waves, dt = m.generate_batch(pipe, b, m.STEPS, m.CFG, m.SHIFT)
        for c, w in zip(b, waves):
            sf.write(os.path.join(ROH, c["id"] + ".wav"), w, m.FS, subtype="FLOAT")
            json.dump({k: c[k] for k in ("id", "prompt", "seed")}, open(os.path.join(ROH, c["id"] + ".json"), "w"))
        print(f"Stapel {i//2+1}: {dt:.0f} s", flush=True)


def aufbereiten(raw, L):
    """Rohton -> warmer Jubel fuer Handy: Hochpass 150 Hz, Tiefpass 6,5 kHz, +2,5 dB um 650 Hz (Fuelle),
    -2 dB um 3,5 kHz (gegen Kratzen), Schnitt ab Einsatz."""
    import numpy as np
    from scipy import signal
    x = raw.astype(np.float64) - float(np.mean(raw))
    x = s.hp(x, 150, 4)
    x = s.lp(x, 6500, 4)
    for f0, g, q in ((650, 2.5, 0.8), (3500, -2.0, 1.0)):
        x = signal.lfilter(*s.peaking(f0, g, q), x)
    env = m.envelope_db(x)
    top = env.max()
    on = int(np.nonzero(env > top - 22.0)[0][0])
    start = max(0, on - int(0.05 * m.FS))
    n = int(L * m.FS)
    y = x[start:start + n]
    if len(y) < n:
        y = np.concatenate([y, np.zeros(n - len(y))])
    return y


def fertig(y, aus, ziel_lufs):
    import numpy as np
    m.FADE_IN_S = 0.15
    cfg = {"ausblenden": aus}
    z, info = m.finish(y, cfg, ziel_lufs, 4.0)
    return np.concatenate([z, np.zeros(int(m.TAIL_S * m.FS))]), info


def crest(x):
    import numpy as np
    return round(float(20 * np.log10(np.max(np.abs(x)) / (np.sqrt(np.mean(x ** 2)) + 1e-12))), 1)


def schwankung(x):
    """Wie gleichmaessig der Jubel in der Mitte ist: Streuung (dB) der 100-ms-Effektivwerte im Kern."""
    import numpy as np
    n = len(x)
    core = x[int(0.3 * m.FS): n - int(1.5 * m.FS)]
    if len(core) < m.FS:
        return 0.0
    w = int(0.1 * m.FS)
    k = len(core) // w
    r = np.sqrt(np.mean(core[:k * w].reshape(k, w) ** 2, axis=1)) + 1e-9
    return round(float(np.std(20 * np.log10(r))), 1)


def nachbearbeiten(cs):
    import numpy as np, soundfile as sf
    os.makedirs(OUT, exist_ok=True)
    res = []
    for c in cs:
        raw, _ = sf.read(os.path.join(ROH, c["id"] + ".wav"), dtype="float32")
        y = aufbereiten(raw, c["laenge"])
        z, info = fertig(y, c["aus"], LUFS)
        wav = os.path.join(OUT, c["id"] + ".wav")
        sf.write(wav, z.astype("float32"), m.FS, subtype="PCM_24")
        s.ogg(wav, os.path.join(OUT, c["id"] + ".ogg"))
        zd = m.decode(os.path.join(OUT, c["id"] + ".ogg"))
        sim = s.handy_modell(zd)
        r = {"id": c["id"], "name": c["name"], "prompt": c["prompt"], "seed": c["seed"], "notiz": c["notiz"],
             "dauer_s": round(len(z) / m.FS, 2), "lufs": round(float(m.momentary_max_lufs(zd)), 1),
             "spitze_dbtp": round(float(m.true_peak_db(zd)), 1), "begrenzer_db": info["begrenzer_db"],
             "crest_db": crest(zd), "schwankung_db": schwankung(zd),
             "mitten_500_4k_db": round(float(m.band_share_db(zd, 500, 4000)), 1),
             "ueber_6k_db": round(float(m.band_share_db(zd, 6000)), 1),
             "ueber_3k_db": round(float(m.band_share_db(zd, 3000)), 1),
             "unter_300_db": round(float(m.band_share_db(zd, 0, 300)), 1),
             "sim_lufs": round(float(m.momentary_max_lufs(sim)), 1),
             "sim_mitten_500_4k_db": round(float(m.band_share_db(sim, 500, 4000)), 1)}
        r["sim_pegelverlust_db"] = round(r["sim_lufs"] - r["lufs"], 1)
        s.handy_probe(r, zd, sim, OUT)
        os.remove(os.path.join(OUT, r["id"] + "_handy.wav"))
        os.remove(wav)
        print(r, flush=True)
        res.append(r)
    return res


def rang(res):
    """Empfehlung nach Messwerten (Ohren fehlen): wenig Pegelverlust am Handy, gleichmaessiger Kern, wenig Hoehen
    (Kratzen), niedriges Spitze/Effektiv-Verhaeltnis, volle Mitten. Die Reihenfolge ist nur eine Hilfe."""
    def score(r):
        return (-abs(r["sim_pegelverlust_db"]) * 1.0 - r["schwankung_db"] * 0.6 - max(0, r["crest_db"] - 12) * 0.4
                + (r["sim_mitten_500_4k_db"] + 3) * 0.5 - max(0, r["ueber_3k_db"] + 12) * 0.3)
    for r in res:
        r["punkte"] = round(score(r), 2)
    return sorted(res, key=lambda r: -r["punkte"])


def seite(res):
    old = open(os.path.join(m.ROOT, "audio", "entwurf", "schnurren3", "hoeren.html"), encoding="utf-8").read()
    css = old[old.index("<style>"):old.index("</style>") + 8]
    cards = []
    for i, r in enumerate(res, 1):
        cards.append(f"""<section class="card"><h2>{i}. {r['id']} <span class="tag">{html.escape(r['name'])}</span></h2>
<p class="sub">{html.escape(r['notiz'])} Seed {r['seed']}, {r['dauer_s']} s.</p>
<p class="sub">Original (Laptop/Kopfhoerer)</p><audio controls preload="none" src="{r['id']}.ogg"></audio>
<p class="sub">So etwa am Handy (Lautsprecher-Modell, auf gleiche Lautheit gehoben)</p><audio controls preload="none" src="{r['id']}_handy.ogg"></audio>
<p class="facts">{r['lufs']} LUFS, Spitze {r['spitze_dbtp']} dBTP (Begrenzer {r['begrenzer_db']} dB), Spitze/Effektiv {r['crest_db']} dB, Schwankung im Kern {r['schwankung_db']} dB;
Mitten 500 Hz-4 kHz {r['mitten_500_4k_db']} dB, ueber 3 kHz {r['ueber_3k_db']} dB, ueber 6 kHz {r['ueber_6k_db']} dB, unter 300 Hz {r['unter_300_db']} dB;
Handy-Modell: Pegelverlust {r['sim_pegelverlust_db']} dB, Mitten {r['sim_mitten_500_4k_db']} dB.</p>
<details><summary>Prompt</summary><p class="facts">{html.escape(r['prompt'])}</p></details></section>""")
    page = f"""<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Jubelnde Menge Runde 1</title>
{css}</head><body><main>
<h1>Jubelnde Menge am Spielende, Runde 1</h1><p class="lead">{len(res)} Kandidaten (MOSS-SoundEffect v2.0, Apache 2.0), alle {LUFS} LUFS, mono, 3,6-5,5 s, weich ein- und ausgeblendet. Reihenfolge = Empfehlung nach Messwerten. Offline, lokal.</p>
<div class="hint"><b>Pegel:</b> {LUFS} LUFS = 2 dB leiser als der Sieg-Glockenspiel-Ton (-16,5), rund 7 dB unter dem Mau-Ton (-11,4). Eine Menge ist dichtes Rauschen ohne Pausen und wirkt bei gleicher Zahl lauter als ein Glockenspiel; im Spiel (Stufe normal, -4,5 dB) liegt sie bei etwa -23 LUFS.<br>
<b>Aufbereitung:</b> Hochpass 150 Hz, Tiefpass 6,5 kHz, +2,5 dB um 650 Hz (Fuelle), -2 dB um 3,5 kHz (gegen Kratzen).<br>
<b>Handy-Modell:</b> Hochpass 400 Hz (steil), Tiefpass 8 kHz, +5 dB Resonanz um 1,5 kHz.<br>
<b>Ehrlich:</b> Niemand hat gehoert; die Rangfolge stuetzt sich auf Messwerte. Bitte auf Verstaendliches (Woerter), Buhen oder Bedrohliches achten.</div>
{''.join(cards)}</main></body></html>"""
    open(os.path.join(OUT, "hoeren.html"), "w", encoding="utf-8").write(page)



# ---------------------------------------------------------------------------------------------------------------
# Runde 2 (10.10.2026): Nutzer waehlt jubel_08, wuenscht ~3 s laengeres Ausklingen ueber abnehmende Jubeldichte
# (weniger Leute), nicht ueber Leiserdrehen. Aufruf: ... make_jubel.py --runde2 [--nur-nachbearbeiten]
# Ergebnis: audio/entwurf/jubel2/ (jubel2_a..d.ogg, *_handy.ogg, jubel_08_bezug*.ogg, messwerte.json, hoeren.html)
# ---------------------------------------------------------------------------------------------------------------
OUT2 = os.path.join(m.ROOT, "audio", "entwurf", "jubel2")
FS = m.FS
KOPF_S = 2.0           # so lange bleibt 08 unveraendert (die Ausblendung von 08 beginnt erst bei 2,3 s)
BLENDE_S = 0.6         # Kreuzblende Kopf -> Ausklang
ENDE_S = 0.3           # nur die allerletzten 0,3 s weich aus
MOSS_PROMPTS = [
    ("m1", "applause and cheering dying down, last few claps and a single cheer, " + NO_WORDS, [2201, 2202]),
    ("m2", "a crowd's applause thinning out until only a few people are still clapping, then one last happy whoop, " + NO_WORDS, [2203, 2204]),
]


def moss_cands():
    return [{"id": f"jubel2_moss_{n}_{sd}", "prompt": p, "seed": sd, "sekunden": 5.0, "laenge": 5.0, "aus": 0.3, "name": n}
            for n, p, sds in MOSS_PROMPTS for sd in sds]


def quelle08():
    """Aufbereiteter, ungeschnittener Rohton von 08 (lange Fassung als Kornvorrat) und die Verstaerkung, mit der 08 fertig wurde."""
    import numpy as np, soundfile as sf
    raw, _ = sf.read(os.path.join(ROH, "jubel_08.wav"), dtype="float32")
    y = aufbereiten(raw, 7.5)
    z, _i = fertig(aufbereiten(raw, 3.6), 1.3, LUFS)
    y36 = y[:int(3.6 * FS)]
    a, b = int(0.5 * FS), int(2.0 * FS)
    g = float(np.sqrt(np.mean(z[a:b] ** 2) / np.mean(y36[a:b] ** 2)))
    return y, g


def korn_vorrat(y):
    """Zwei Vorraete aus 08: Klatscher (kurze, spitze Ereignisse) und Rufe (halbsekundenlange mittenreiche Stuecke).
    Nur aus dem dichten Teil 0,5-4,3 s (danach laeuft das Rohmaterial von selbst aus)."""
    import numpy as np
    from scipy import signal
    a0, a1 = int(0.5 * FS), int(4.3 * FS)
    hi = s.hp(y, 1500, 4)
    w = int(0.004 * FS)
    env = np.sqrt(np.convolve(hi ** 2, np.ones(w) / w, mode="same")) + 1e-9
    envdb = 20 * np.log10(env)
    wl = int(0.25 * FS)
    loc = 20 * np.log10(np.sqrt(np.convolve(hi ** 2, np.ones(wl) / wl, mode="same")) + 1e-9)
    pk, _pr = signal.find_peaks(envdb[a0:a1], prominence=3.0, distance=int(0.12 * FS))
    pk = pk + a0
    sc = envdb[pk] - loc[pk]
    order = np.argsort(-sc)
    klatsch = []
    for i in order[:60]:
        p0 = pk[i]
        g = y[p0 - int(0.008 * FS): p0 + int(0.14 * FS)].copy()
        n = len(g)
        win = np.ones(n)
        fi, fo = int(0.004 * FS), int(0.07 * FS)
        win[:fi] = np.sin(np.linspace(0, np.pi / 2, fi)) ** 2
        win[-fo:] = np.cos(np.linspace(0, np.pi / 2, fo)) ** 2
        klatsch.append(g * win)
    mid = s.bp(y, 300, 1500, 2)
    rufe = []
    L = int(0.55 * FS)
    cand = []
    for st in range(a0, a1 - L, int(0.05 * FS)):
        seg = slice(st, st + L)
        cand.append((float(np.mean(mid[seg] ** 2) / (np.mean(y[seg] ** 2) + 1e-12)), st))
    cand.sort(reverse=True)
    used = []
    for _sc, st in cand:
        if all(abs(st - u) > L for u in used):
            used.append(st)
            g = y[st:st + L].copy()
            f = int(0.12 * FS)
            g[:f] *= np.sin(np.linspace(0, np.pi / 2, f)) ** 2
            g[-f:] *= np.cos(np.linspace(0, np.pi / 2, f)) ** 2
            rufe.append(g)
        if len(used) >= 10:
            break
    return klatsch, rufe


def rms_db(x):
    import numpy as np
    return float(10 * np.log10(np.mean(np.square(x)) + 1e-12))


def granular(y, kopf, T, r0, tau, seed, p_ruf0=0.35):
    """Ausklang aus Koernern: Anzahl pro Sekunde r(u)=r0*exp(-u/tau), jedes Korn in fester Lautstaerke (die Zahl der
    'Leute' sinkt, kein Regler). Zurueck: (Signal der Laenge T s, Liste [(u, art)])."""
    import numpy as np
    rng = np.random.default_rng(seed)
    klatsch, rufe = korn_vorrat(y)
    n = int(T * FS)
    out = np.zeros(n + int(1.0 * FS))
    # feste Kornverstaerkung: bei der Anfangsdichte soll die (inkoharente) Summe so laut sein wie der Kopf an der Naht
    ref = rms_db(kopf[-int(0.5 * FS):])
    overlap0 = r0 * 0.3
    kornpegel = float(np.mean([rms_db(g) for g in klatsch + rufe]))
    c = 10 ** ((ref - kornpegel - 10 * np.log10(overlap0)) / 20)
    events = []
    u = 0.0
    while u < T - 1.6:
        u += rng.exponential(1.0 / r0)
        if u < T - 1.6 and rng.random() <= np.exp(-u / tau):          # Ausduennen der Poisson-Folge
            events.append(u)
    res = []
    last_ruf = -9.0
    for u in events:
        ruf = rng.random() < p_ruf0 * np.exp(-u / (tau * 1.6)) and (u - last_ruf) > 0.25
        res.append((u, "ruf" if ruf else "klatsch"))
        if ruf:
            last_ruf = u
    # die letzten 1,6 s von Hand: ein einzelner Ruf, dann wenige Klatscher mit wachsendem Abstand
    res.append((T - 1.5, "ruf"))
    t, gap = T - 1.05, 0.18
    while t < T - 0.25:
        res.append((t, "klatsch"))
        t += gap
        gap *= 1.55
    res.sort()
    for u, art in res:
        pool = rufe if art == "ruf" else klatsch
        g = pool[int(rng.integers(len(pool)))] * c * 10 ** (rng.uniform(-1.5, 1.5) / 20)
        if art == "ruf":
            g = g * 1.6
        i = int(u * FS)
        out[i:i + len(g)] += g[:len(out) - i]
    return out[:n], res


def dichte_score(t):
    """Wie deutlich duennt ein Ausklang aus: Pegelabfall Anfang -> letztes Drittel plus Streuung (Luecken) im Ende."""
    import numpy as np
    w = int(0.1 * FS)
    k = len(t) // w
    r = 10 * np.log10(np.mean(t[:k * w].reshape(k, w) ** 2, axis=1) + 1e-12)
    ende = r[-(k // 3):]
    return float(np.mean(r[:5]) - np.mean(ende)) + 0.4 * float(np.std(ende))


def bauen(kopf_y, tail, blende, gesamt):
    """Kopf (08 unveraendert bis KOPF_S) + Ausklang ab KOPF_S, Gleichleistungs-Kreuzblende `blende` s."""
    import numpy as np
    k = int(KOPF_S * FS)
    nb = int(blende * FS)
    out = np.zeros(int(gesamt * FS))
    out[:k + nb] = kopf_y[:k + nb]
    t = np.linspace(0, np.pi / 2, nb)
    out[k:k + nb] *= np.cos(t)
    tl = tail[:len(out) - k].copy()
    tl[:nb] *= np.sin(t)
    out[k:k + len(tl)] += tl
    return out


def abschluss(x, g):
    import numpy as np
    x = x * g
    n = len(x)
    f = int(0.15 * FS)
    x[:f] *= np.sin(np.linspace(0, np.pi / 2, f)) ** 2
    fo = m.cosine_fade(n, ENDE_S, False)
    x[n - len(fo):] *= fo
    tp = m.true_peak_db(x)
    if tp > -1.1:
        x *= 10 ** ((-1.1 - tp) / 20)
    return np.concatenate([x, np.zeros(int(m.TAIL_S * FS))])


def verlauf(zd, schritt=0.5):
    import numpy as np
    w = int(schritt * FS)
    k = len(zd) // w
    r = 10 * np.log10(np.mean(zd[:k * w].reshape(k, w) ** 2, axis=1) + 1e-12)
    return [round(float(v), 1) for v in r]


def svg(zd, ref=None):
    import numpy as np
    w = int(0.1 * FS)

    def kurve(x, col):
        k = len(x) // w
        r = 10 * np.log10(np.mean(x[:k * w].reshape(k, w) ** 2, axis=1) + 1e-12)
        pts = " ".join(f"{i*w/FS*60:.1f},{max(0, min(60, -r[i]-8))*2.2:.1f}" for i in range(k))
        return f'<polyline fill="none" stroke="{col}" stroke-width="1.5" points="{pts}"/>'
    o = '<svg viewBox="0 0 460 140" width="100%" style="max-width:460px;background:#8881;border-radius:6px">'
    o += ''.join(f'<line x1="{x*60}" y1="0" x2="{x*60}" y2="140" stroke="#8884"/><text x="{x*60+2}" y="136" font-size="9" fill="#888">{x} s</text>' for x in range(0, 8))
    if ref is not None:
        o += kurve(ref, "#c0392b")
    return o + kurve(zd, "#2471a3") + '</svg>'


def runde2(nur_nachbearbeiten, gpu):
    import numpy as np, soundfile as sf, shutil
    os.makedirs(OUT2, exist_ok=True)
    mc = moss_cands()
    if not nur_nachbearbeiten:
        erzeugen(mc, gpu)
    y, g = quelle08()
    kopf = y[:int(4.0 * FS)]
    z08 = m.decode(os.path.join(OUT, "jubel_08.ogg"))
    ref_rms = rms_db(y[int(1.2 * FS):int(2.0 * FS)])
    sc = {}
    for c in mc:
        raw, _ = sf.read(os.path.join(ROH, c["id"] + ".wav"), dtype="float32")
        t = aufbereiten(raw, 4.5)
        t = t * 10 ** ((ref_rms - rms_db(t[:int(1.0 * FS)])) / 20)       # Anfang des Ausklangs = Pegel des Kopfes
        sc[c["id"]] = (dichte_score(t), t, c)
    best = max(sc, key=lambda k_: sc[k_][0])
    print("MOSS-Auswahl:", {k_: round(v[0], 1) for k_, v in sc.items()}, "->", best, flush=True)
    moss, bestc = sc[best][1], sc[best][2]
    varianten = []
    # (a) granular, 6,5 s
    Ta = 6.5 - KOPF_S
    ga, ev_a = granular(y, kopf[:int(KOPF_S * FS)], Ta, 60, 1.9, 7)
    varianten.append(("a", "Granular aus 08",
                      f"Nach {KOPF_S:g} s wie 08, dann nur noch Koerner aus 08 (Klatscher und Rufe), deren Zahl pro Sekunde exponentiell faellt (60 auf wenige); jedes Korn in fester Lautstaerke, kein Fader. Letzte Klatscher mit wachsenden Abstaenden, ein einzelner Ruf. Letzte 0,3 s weich aus.",
                      bauen(kopf, ga, BLENDE_S, 6.5),
                      {"koerner": len(ev_a), "pro_s": [sum(1 for u, _ in ev_a if i <= u < i + 1) for i in range(int(Ta))]}))
    # (b) MOSS, 6,5 s
    varianten.append(("b", "MOSS-Ausklang",
                      f"Nach {KOPF_S:g} s wie 08; im dichten Teil ({BLENDE_S:g} s Kreuzblende) uebernimmt ein von MOSS erzeugter Ausklang (Prompt: {bestc['prompt'][:90]}..., Seed {bestc['seed']}); Pegel an der Naht angeglichen, sonst unveraendert.",
                      bauen(kopf, moss, BLENDE_S, 6.5), {"moss": best}))
    # (c) Mischung: Koerner-Ausklang, das duenne Ende von MOSS
    Tc = 6.5 - KOPF_S
    gc, ev_c = granular(y, kopf[:int(KOPF_S * FS)], 2.3, 60, 1.3, 11)
    gc = np.concatenate([gc, np.zeros(int((Tc - 2.3) * FS))])
    xc = bauen(kopf, gc, BLENDE_S, 6.5)
    mt = moss[-(len(xc) - int((KOPF_S + 2.3 - 0.4) * FS)):]
    start = int((KOPF_S + 2.3 - 0.4) * FS)
    nb = int(0.8 * FS)
    t = np.linspace(0, np.pi / 2, nb)
    xc[start:start + nb] *= np.cos(t)
    xc[start + nb:] = 0
    mt2 = mt.copy()
    mt2[:nb] *= np.sin(t)
    ende = min(len(xc), start + len(mt2))
    xc[start:ende] += mt2[:ende - start]
    varianten.append(("c", "Mischung",
                      f"Wie (a), aber das duenne Ende (ab {KOPF_S+2.3-0.4:.1f} s) stammt von MOSS ({best}): echte letzte Klatscher und Ruf; Kreuzblende 0,8 s.",
                      xc, {"moss": best}))
    # (d) granular, laenger
    Td = 7.3 - KOPF_S
    gd, ev_d = granular(y, kopf[:int(KOPF_S * FS)], Td, 60, 2.4, 13)
    varianten.append(("d", "Granular, laenger", "Wie (a), aber 7,3 s: etwas langsamere Abnahme der Koernerzahl.",
                      bauen(kopf, gd, BLENDE_S, 7.3),
                      {"koerner": len(ev_d), "pro_s": [sum(1 for u, _ in ev_d if i <= u < i + 1) for i in range(int(Td))]}))
    res = []
    for k_, name, notiz, x, extra in varianten:
        zf = abschluss(x, g)
        wav = os.path.join(OUT2, f"jubel2_{k_}.wav")
        sf.write(wav, zf.astype("float32"), FS, subtype="PCM_24")
        s.ogg(wav, os.path.join(OUT2, f"jubel2_{k_}.ogg"))
        os.remove(wav)
        zd = m.decode(os.path.join(OUT2, f"jubel2_{k_}.ogg"))
        sim = s.handy_modell(zd)
        r = {"id": f"jubel2_{k_}", "name": name, "notiz": notiz, "dauer_s": round(len(zd) / FS, 2),
             "lufs": round(float(m.momentary_max_lufs(zd)), 1), "spitze_dbtp": round(float(m.true_peak_db(zd)), 1),
             "anfang_rms_db": round(rms_db(zd[int(0.5 * FS):int(2.0 * FS)]), 1),
             "bezug08_anfang_rms_db": round(rms_db(z08[int(0.5 * FS):int(2.0 * FS)]), 1),
             "verlauf_db_je_0_5s": verlauf(zd), "sim_lufs": round(float(m.momentary_max_lufs(sim)), 1),
             "ueber_3k_db": round(float(m.band_share_db(zd, 3000)), 1)}
        r["sim_pegelverlust_db"] = round(r["sim_lufs"] - r["lufs"], 1)
        r.update(extra)
        s.handy_probe(r, zd, sim, OUT2)
        os.remove(os.path.join(OUT2, r["id"] + "_handy.wav"))
        r["_zd"] = zd
        print({k2: v for k2, v in r.items() if k2 != "_zd"}, flush=True)
        res.append(r)
    for suffix in (".ogg", "_handy.ogg"):
        shutil.copy(os.path.join(OUT, "jubel_08" + suffix), os.path.join(OUT2, "jubel_08_bezug" + suffix))
    seite2(res, z08, best)
    for r in res:
        r.pop("_zd")
    json.dump(res, open(os.path.join(OUT2, "messwerte.json"), "w"), indent=1, ensure_ascii=False)


def seite2(res, z08, best):
    old = open(os.path.join(m.ROOT, "audio", "entwurf", "schnurren3", "hoeren.html"), encoding="utf-8").read()
    css = old[old.index("<style>"):old.index("</style>") + 8]
    cards = ["""<section class="card"><h2>Bezug: jubel_08 <span class="tag">gewaehlt, 3,6 s</span></h2>
<p class="sub">Original</p><audio controls preload="none" src="jubel_08_bezug.ogg"></audio>
<p class="sub">Handy-Simulation</p><audio controls preload="none" src="jubel_08_bezug_handy.ogg"></audio></section>"""]
    for r in res:
        extra = f"<br>Koerner pro Sekunde im Ausklang (ab {KOPF_S:g} s): {r['pro_s']}" if "pro_s" in r else ""
        cards.append(f"""<section class="card"><h2>{r['id'][-1]}. {html.escape(r['name'])} <span class="tag">{r['dauer_s']} s</span></h2>
<p class="sub">{html.escape(r['notiz'])}</p>
<p class="sub">Original (Laptop/Kopfhoerer)</p><audio controls preload="none" src="{r['id']}.ogg"></audio>
<p class="sub">So etwa am Handy (Lautsprecher-Modell, auf gleiche Lautheit gehoben)</p><audio controls preload="none" src="{r['id']}_handy.ogg"></audio>
<p class="sub">Pegel-Verlauf (blau; rot = 08), 100-ms-Fenster</p>{svg(r['_zd'], z08)}
<p class="facts">Pegel je 0,5 s (dB): {r['verlauf_db_je_0_5s']}{extra}<br>
Anfang (0,5-2 s) {r['anfang_rms_db']} dB, 08: {r['bezug08_anfang_rms_db']} dB; {r['lufs']} LUFS, Spitze {r['spitze_dbtp']} dBTP; ueber 3 kHz {r['ueber_3k_db']} dB; Handy-Modell Pegelverlust {r['sim_pegelverlust_db']} dB.</p></section>""")
    page = f"""<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Jubel Runde 2</title>
{css}</head><body><main>
<h1>Jubel, Runde 2: laenger ausklingen</h1><p class="lead">Wunsch: 08 soll ca. 3 s laenger ausklingen, indem die <b>Jubeldichte</b> abfaellt (weniger Leute, einzelne Klatscher, ein letzter Ruf) statt leiser zu werden. Der Anfang ist 08 (bis {KOPF_S:g} s unveraendert), nur die letzten 0,3 s weich aus.</p>
<div class="hint"><b>Ehrlich:</b> Niemand hat gehoert; Empfehlung nach Bauart und Messwerten. Bitte auf Woerter, Buhen und Koernerklang (unnatuerliche Wiederholungen) achten. MOSS-Ausklang gewaehlt: {best}.</div>
{''.join(cards)}</main></body></html>"""
    open(os.path.join(OUT2, "hoeren.html"), "w", encoding="utf-8").write(page)


# ---------------------------------------------------------------------------------------------------------------
# Runde 3 (10.10.2026): Runde 2 war zusammengeschnitten und klang abgehackt. Jetzt: ganze Stuecke aus einem Guss von MOSS
# (Dauer 7,0 s im Prompt, Rohton 9 s), KEINE Koerner, KEIN Ansetzen, KEINE Kreuzblenden. Viele Seeds, automatische
# Vorauswahl nach Ausklang (kein Loch, keine Pegelspruenge, abnehmende Dichte), Klangaehnlichkeit zu 08, Stimm-Verdacht.
# Aufruf: ... make_jubel.py --runde3 [--nur-nachbearbeiten] [--gpu N]
# Ergebnis: audio/entwurf/jubel3/ (jubel3_NN.ogg, *_handy.ogg, jubel_08_bezug*.ogg, messwerte.json, hoeren.html)
# ---------------------------------------------------------------------------------------------------------------
OUT3 = os.path.join(m.ROOT, "audio", "entwurf", "jubel3")
SEK3 = 7.0
BEHALTEN = 8
P3 = [
    ("fade", "a short burst of happy cheering that turns into warm applause, then the applause thins out, fewer and fewer people clapping, a few last claps and it fades out gently, " + NO_WORDS,
     [2102, 2103, 2104, 2105, 2106, 2107, 2108, 2109]),
    ("ebbt", "small excited crowd cheering and applauding, then the cheering naturally dies down, fewer and fewer people clapping, a few last claps, warm indoor room, " + NO_WORDS,
     [2301, 2302, 2303, 2304, 2305, 2306, 2307, 2308]),
    ("rufe", "small excited crowd applauding with a few happy whoops, then the cheering naturally dies down, fewer and fewer people clapping, a few last claps, warm indoor room, " + NO_WORDS,
     [2401, 2402, 2403, 2404, 2405, 2406, 2407, 2408]),
]


def cands3():
    out = []
    for n, p, sds in P3:
        for sd in sds:
            out.append({"id": f"jubel3_roh_{n}_{sd}", "name": n, "prompt": p, "seed": sd, "sekunden": SEK3, "laenge": SEK3})
    return out


def rms_db(x):
    import numpy as np
    return float(10 * np.log10(np.mean(np.square(x)) + 1e-12))


def pegel_kurve(x, fenster=0.1):
    import numpy as np
    w = int(fenster * FS)
    k = len(x) // w
    return 10 * np.log10(np.mean(x[:k * w].reshape(k, w) ** 2, axis=1) + 1e-12)


def dichte_je_halbsekunde(x):
    import numpy as np
    from scipy import signal
    # Einzelne, abgesetzte Klatscher (Huellkurve 1,5-6 kHz, 3 ms, mind. 12 dB ueber der Umgebung). In dichtem Applaus
    # verschmelzen sie, bei duennem treten sie einzeln hervor: die Zahl steigt daher oft, wenn der Applaus ausduennt.
    hi = s.bp(x, 1500, 6000, 2)
    w = int(0.003 * FS)
    env = 20 * np.log10(np.sqrt(np.convolve(hi ** 2, np.ones(w) / w, mode="same")) + 1e-9)
    pk, _ = signal.find_peaks(env, prominence=12.0, distance=int(0.04 * FS))
    n = int(len(x) / (0.5 * FS))
    return [int(np.sum((pk >= i * 0.5 * FS) & (pk < (i + 1) * 0.5 * FS))) for i in range(n)]


def spearman(v):
    import numpy as np
    if len(v) < 3 or np.std(v) == 0:
        return 0.0
    a = np.argsort(np.argsort(v)).astype(float)
    b = np.arange(len(v), dtype=float)
    return float(np.corrcoef(a, b)[0, 1])


def spektrum_3okt(x):
    import numpy as np
    from scipy import signal
    f, p = signal.welch(x, FS, nperseg=8192)
    mitten = [200 * 2 ** (i / 3) for i in range(0, 14)]
    o = []
    for a_, b_ in zip(mitten[:-1], mitten[1:]):
        sel = (f >= a_) & (f < b_)
        o.append(10 * np.log10(np.sum(p[sel]) + 1e-18))
    o = np.array(o)
    return o - np.mean(o)


def stimm_verdacht(x):
    """Laengster zusammenhaengender Lauf (s) mit klarer Tonhoehe 80-400 Hz (normierte Autokorrelation > 0,7; 08 selbst hat 0,7 s am Anfang): eine einzelne
    Stimme oder ein Wort; ein Menschenhaufen ergibt dagegen kaum periodische Laeufe."""
    import numpy as np
    b = s.bp(x, 80, 1200, 2)
    hop, win = int(0.01 * FS), int(0.04 * FS)
    lo, hi = int(FS / 400), int(FS / 80)
    flags = []
    for st in range(0, len(b) - win - hi, hop):
        seg = b[st:st + win + hi]
        e = np.sum(seg[:win] ** 2)
        if e < 1e-9:
            flags.append(False)
            continue
        a0 = seg[:win]
        best = 0.0
        for lag in range(lo, hi, 4):
            a1 = seg[lag:lag + win]
            c = float(np.dot(a0, a1) / (np.sqrt(e * np.sum(a1 ** 2)) + 1e-12))
            best = max(best, c)
        flags.append(best > 0.7)
    run = mx = 0
    for f_ in flags:
        run = run + 1 if f_ else 0
        mx = max(mx, run)
    return round(mx * 0.01, 2), round(float(np.mean(flags)), 2)


def analyse3(z, ref_rms, spek08, dichte08):
    """z: aufbereitetes Stueck (Pegel schon an 08 angeglichen). Liefert Messwerte und Ausschlussgruende."""
    import numpy as np
    k = pegel_kurve(z, 0.1)
    ref = ref_rms
    t_end = 0.0
    for i in range(len(k) - 1, -1, -1):
        if k[i] > ref - 40:
            t_end = (i + 1) * 0.1
            break
    r = {"ende_s": round(t_end, 2)}
    # (a) Loch: 10-ms-Pegel unter ref-38 dB laenger als 120 ms vor den letzten 1,5 s
    k10 = pegel_kurve(z, 0.01)
    stop = max(0, int((t_end - 1.5) * 100))
    lauf = mx = 0
    for v in k10[int(0.2 * 100):stop]:
        lauf = lauf + 1 if v < ref - 38 else 0
        mx = max(mx, lauf)
    r["loch_ms"] = mx * 10
    # Pegelspruenge abwaerts: 100-ms-Fenster auf 50-ms-Raster, Abfall > 6 dB innerhalb 100 ms, ab 2 s bis 0,5 s vor Ende
    # (Rauschartiger Applaus schwankt in 100 ms von selbst um 10 dB; deshalb 250-ms-Fenster im 125-ms-Raster, Abfall > 5 dB.)
    wf, hp_ = int(0.25 * FS), int(0.125 * FS)
    k50 = np.array([10 * np.log10(np.mean(z[i:i + wf] ** 2) + 1e-12) for i in range(0, len(z) - wf, hp_)])
    sprung = 0.0
    n_sprung = 0
    for i in range(int(2.0 / 0.125), min(len(k50) - 2, int((t_end - 0.8) / 0.125))):
        d = k50[i] - k50[i + 2]
        sprung = max(sprung, d)
        if d > 5.0 and k50[i + 2] > ref - 30:
            n_sprung += 1
    # Abriss: Pegel faellt innerhalb 250 ms um > 12 dB, obwohl er vorher noch nicht weit unter dem Anfang lag (auch im Schlussteil)
    abriss = 0.0
    for i in range(int(2.0 / 0.125), len(k50) - 2):
        if k50[i] > ref - 12:
            abriss = max(abriss, k50[i] - k50[i + 2])
    r["abriss_db"] = round(float(abriss), 1)
    r["max_abfall_db_250ms"] = round(float(sprung), 1)
    r["spruenge"] = n_sprung
    # Ende: letzte 0,5 s weit unter dem Anfang?
    r["pegel_ende_rel_db"] = round(float(np.mean(k[max(0, int(t_end * 10) - 5):max(1, int(t_end * 10))]) - ref), 1)
    # (b) Dichte/Pegel in Halbsekunden
    d = dichte_je_halbsekunde(z[:int(max(t_end, 1) * FS)])
    lv = list(pegel_kurve(z[:int(max(t_end, 1) * FS)], 0.5))
    r["dichte"] = d
    r["pegel_0_5s"] = [round(float(v), 1) for v in lv]
    n = len(d)
    ab = max(2, int(np.argmax(np.array(lv[:max(3, n // 2)]) + 0.0)))     # ab dem lautesten Punkt der ersten Haelfte
    r["dichte_trend"] = round(spearman(d[ab:]), 2)
    r["pegel_trend"] = round(spearman(lv[ab:]), 2)
    r["anfang_dichte"] = round(float(np.mean(d[1:4])), 1)
    r["dichte08_anfang"] = round(float(np.mean(dichte08[1:4])), 1)
    r["dichte_ende"] = round(float(np.mean(d[-3:])), 1)
    # (c) Klangaehnlichkeit zu 08: Abstand der 1/3-Oktav-Spektren der ersten 2 s (dB RMS)
    sp = spektrum_3okt(z[:int(2.0 * FS)])
    r["spektrum_abstand_db"] = round(float(np.sqrt(np.mean((sp - spek08) ** 2))), 2)
    # (d) Stimm-Verdacht
    lauf_s, anteil = stimm_verdacht(z[:int(max(t_end, 1) * FS)])
    r["stimm_lauf_s"] = lauf_s
    r["stimm_anteil"] = anteil
    grund = []
    if t_end < 5.4:
        grund.append("zu kurz")
    if r["loch_ms"] > 120:
        grund.append("Loch")
    if r["pegel_ende_rel_db"] > -12:
        grund.append("bricht laut ab")
    if abriss > 12:
        grund.append("Abriss am Ende")
    if n_sprung > 0:
        grund.append("Pegelsprung")
    if lauf_s > 0.85:
        grund.append("Stimme?")
    r["ausschluss"] = grund
    r["punkte"] = round(
        -abs(r["spektrum_abstand_db"]) * 1.0
        + 6.0 * (-r["pegel_trend"])
        - 0.5 * max(0, sprung - 3) - 1.0 * n_sprung - 0.3 * max(0, abriss - 8)
        - 0.02 * max(0, r["loch_ms"] - 60)
        - 3.0 * max(0, lauf_s - 0.7) - 3 * max(0, anteil - 0.3)
        - 0.4 * max(0, ref - 8 - float(np.mean(k[5:10])))
        - 0.5 * abs(t_end - 6.6)
        - 0.15 * max(0, r["pegel_ende_rel_db"] + 25) - (0 if t_end >= 5.4 else 5), 2)
    return r


def aufbereiten3(raw, ref_rms):
    """Wie 08 (aufbereiten), Schnitt ab Einsatz, bis 7,6 s, Anfang (0,5-2 s) auf den Pegel von 08 gebracht."""
    y = aufbereiten(raw, 7.6)
    g = 10 ** ((ref_rms - rms_db(y[int(0.5 * FS):int(2.0 * FS)])) / 20)
    return y * g


def seite3(res, z08):
    old = open(os.path.join(m.ROOT, "audio", "entwurf", "schnurren3", "hoeren.html"), encoding="utf-8").read()
    css = old[old.index("<style>"):old.index("</style>") + 8]
    cards = ["""<section class="card"><h2>Bezug: jubel_08 <span class="tag">gewaehlt, 3,6 s</span></h2>
<p class="sub">Original</p><audio controls preload="none" src="jubel_08_bezug.ogg"></audio>
<p class="sub">Handy-Simulation</p><audio controls preload="none" src="jubel_08_bezug_handy.ogg"></audio></section>"""]
    for i, r in enumerate(res, 1):
        mx = max(max(r["dichte"]), 1)
        bal = "".join(f'<rect x="{j*14+2}" y="{50-d*48/mx:.1f}" width="11" height="{d*48/mx:.1f}" fill="#2471a3"/>' for j, d in enumerate(r["dichte"]))
        dsvg = f'<svg viewBox="0 0 {len(r["dichte"])*14+4} 52" width="100%" style="max-width:{len(r["dichte"])*14+4}px;background:#8881;border-radius:6px">{bal}</svg>'
        cards.append(f"""<section class="card"><h2>{i}. {r['id']} <span class="tag">{html.escape(r['name'])} &middot; Seed {r['seed']} &middot; {r['dauer_s']} s</span></h2>
<p class="sub">{html.escape(r['notiz'])}</p>
<p class="sub">Original (Laptop/Kopfhoerer)</p><audio controls preload="none" src="{r['id']}.ogg"></audio>
<p class="sub">So etwa am Handy (Lautsprecher-Modell, auf gleiche Lautheit gehoben)</p><audio controls preload="none" src="{r['id']}_handy.ogg"></audio>
<p class="sub">Pegelverlauf (blau; rot = 08), 100-ms-Fenster</p>{svg(r['_zd'], z08)}
<p class="sub">Einzeln hoerbare Klatscher je 0,5 s (steigt, wenn der Applaus ausduennt, weil sie dann nicht mehr verschmelzen)</p>{dsvg}
<p class="facts">Klatscher je 0,5 s: {r['dichte']}; Pegel je 0,5 s (dB): {r['pegel_0_5s']}<br>
Trend ab Pegelhoechstwert (Spearman, -1 = gleichmaessig abnehmend): Pegel {r['pegel_trend']}, einzelne Klatscher {r['dichte_trend']}; groesster Abfall in 250 ms {r['max_abfall_db_250ms']} dB; Loch {r['loch_ms']} ms; Ende {r['pegel_ende_rel_db']} dB unter dem Anfang.<br>
Klang-Abstand zu 08 (erste 2 s): {r['spektrum_abstand_db']} dB; Klatscher am Anfang je 0,5 s {r['anfang_dichte']} (08: {r['dichte08_anfang']}); laengster Stimm-Lauf {r['stimm_lauf_s']} s (Anteil {r['stimm_anteil']}).<br>
{r['lufs']} LUFS, Spitze {r['spitze_dbtp']} dBTP, ueber 3 kHz {r['ueber_3k_db']} dB; Handy-Modell Pegelverlust {r['sim_pegelverlust_db']} dB. Punkte {r['punkte']}.</p>
<details><summary>Prompt</summary><p class="facts">{html.escape(r['prompt'])} duration: {SEK3:.1f}s</p></details></section>""")
    page = f"""<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Jubel Runde 3</title>
{css}</head><body><main>
<h1>Jubel, Runde 3: in einem Guss ausklingen</h1><p class="lead">Runde 2 war zusammengeschnitten und klang abgehackt. Diese {len(res)} Stuecke hat <b>MOSS-SoundEffect v2.0 komplett in einem Stueck erzeugt</b>: kein Zusammenschneiden, keine Koerner, keine Kreuzblenden. Es wurde nur ab dem Einsatz geschnitten, wie 08 aufbereitet (Hochpass 150 Hz, Tiefpass 6,5 kHz, +2,5 dB um 650 Hz, -2 dB um 3,5 kHz) und der Anfang auf den Pegel von 08 gebracht; nur das letzte Stueck (50 ms bis 0,3 s) ist weich aus. Aus {res[0]['_gesamt']} Versuchen automatisch vorsortiert; Reihenfolge = Empfehlung nach Messwerten.</p>
<div class="hint"><b>Auswahl nach:</b> kein Loch und keine Pegelspruenge im Ausklang, der Pegel nimmt ab dem Hoechstwert gleichmaessig ab (kein Absatz > 5 dB in 250 ms), Anfang so dicht und klangaehnlich wie 08, kein Verdacht auf Stimmen/Woerter.<br>
<b>Ehrlich:</b> Niemand hat gehoert. Bitte besonders auf ein natuerliches Ausklingen achten und auf Verstaendliches oder Buhen.</div>
{''.join(cards)}</main></body></html>"""
    open(os.path.join(OUT3, "hoeren.html"), "w", encoding="utf-8").write(page)


def runde3(nur_nachbearbeiten, gpu):
    import numpy as np, soundfile as sf, shutil
    os.makedirs(OUT3, exist_ok=True)
    cs = cands3()
    if not nur_nachbearbeiten:
        erzeugen(cs, gpu)
    z08 = m.decode(os.path.join(OUT, "jubel_08.ogg"))
    ref_rms = rms_db(z08[int(0.5 * FS):int(2.0 * FS)])
    spek08 = spektrum_3okt(z08[:int(2.0 * FS)])
    dichte08 = dichte_je_halbsekunde(z08)
    gut = []
    for c in cs:
        p = os.path.join(ROH, c["id"] + ".wav")
        if not os.path.exists(p):
            continue
        raw, _ = sf.read(p, dtype="float32")
        z = aufbereiten3(raw, ref_rms)
        r = analyse3(z, ref_rms, spek08, dichte08)
        r.update({"roh": c["id"], "name": c["name"], "seed": c["seed"], "prompt": c["prompt"]})
        print(c["id"], {k: v for k, v in r.items() if k not in ("prompt", "dichte", "pegel_0_5s")}, flush=True)
        gut.append((r, z))
    ok = sorted([t for t in gut if not t[0]["ausschluss"]], key=lambda t: -t[0]["punkte"])
    rest = sorted([t for t in gut if t[0]["ausschluss"]], key=lambda t: -t[0]["punkte"])
    wahl = (ok + rest)[:BEHALTEN]
    print(f"{len(gut)} Versuche, {len(ok)} ohne Ausschluss, behalten {len(wahl)}", flush=True)
    res = []
    for i, (r, z) in enumerate(wahl, 1):
        n = min(len(z), int((r["ende_s"] + 0.35) * FS))
        x = z[:n].copy()
        f = int(0.15 * FS)
        x[:f] *= np.sin(np.linspace(0, np.pi / 2, f)) ** 2
        leise = r["pegel_ende_rel_db"] <= -25
        fo = m.cosine_fade(len(x), 0.05 if leise else ENDE_S, False)
        x[len(x) - len(fo):] *= fo
        tp = m.true_peak_db(x)
        if tp > -1.1:
            x *= 10 ** ((-1.1 - tp) / 20)
        x = np.concatenate([x, np.zeros(int(m.TAIL_S * FS))])
        rid = f"jubel3_{i:02d}"
        wav = os.path.join(OUT3, rid + ".wav")
        sf.write(wav, x.astype("float32"), FS, subtype="PCM_24")
        s.ogg(wav, os.path.join(OUT3, rid + ".ogg"))
        os.remove(wav)
        zd = m.decode(os.path.join(OUT3, rid + ".ogg"))
        sim = s.handy_modell(zd)
        r2 = dict(r)
        r2.update({"id": rid, "dauer_s": round(len(zd) / FS, 2), "lufs": round(float(m.momentary_max_lufs(zd)), 1),
                   "spitze_dbtp": round(float(m.true_peak_db(zd)), 1),
                   "anfang_rms_db": round(rms_db(zd[int(0.5 * FS):int(2.0 * FS)]), 1), "bezug08_anfang_rms_db": round(ref_rms, 1),
                   "ueber_3k_db": round(float(m.band_share_db(zd, 3000)), 1), "sim_lufs": round(float(m.momentary_max_lufs(sim)), 1)})
        r2["sim_pegelverlust_db"] = round(r2["sim_lufs"] - r2["lufs"], 1)
        r2["notiz"] = (f"Prompt-Variante {r['name']}. " + ("Auffaellig: " + ", ".join(r["ausschluss"]) + ". " if r["ausschluss"] else "")
                       + f"Ausklang bis {r['ende_s']} s, Pegel-Trend {r['pegel_trend']}, groesster Abfall {r['max_abfall_db_250ms']} dB/250 ms.")
        s.handy_probe(r2, zd, sim, OUT3)
        os.remove(os.path.join(OUT3, rid + "_handy.wav"))
        r2["_zd"] = zd
        r2["_gesamt"] = len(gut)
        res.append(r2)
    for suffix in (".ogg", "_handy.ogg"):
        shutil.copy(os.path.join(OUT, "jubel_08" + suffix), os.path.join(OUT3, "jubel_08_bezug" + suffix))
    seite3(res, z08)
    for r in res:
        r.pop("_zd"), r.pop("_gesamt")
    json.dump(res, open(os.path.join(OUT3, "messwerte.json"), "w"), indent=1, ensure_ascii=False)
    print("Reihenfolge:", [(r["id"], r["name"], r["seed"], r["punkte"], r["ausschluss"]) for r in res])


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--nur-nachbearbeiten", action="store_true")
    ap.add_argument("--gpu", type=int, default=0)
    ap.add_argument("--runde2", action="store_true")
    ap.add_argument("--runde3", action="store_true")
    a = ap.parse_args()
    if a.runde3:
        runde3(a.nur_nachbearbeiten, a.gpu)
        sys.exit(0)
    if a.runde2:
        runde2(a.nur_nachbearbeiten, a.gpu)
        sys.exit(0)
    cs = cands()
    if not a.nur_nachbearbeiten:
        erzeugen(cs, a.gpu)
    res = rang(nachbearbeiten(cs))
    json.dump(res, open(os.path.join(OUT, "messwerte.json"), "w"), indent=1, ensure_ascii=False)
    seite(res)
    print("Reihenfolge:", [(r["id"], r["punkte"]) for r in res])
