"""Zusatzmessungen, Hörseite und Favoriten für die KI-Tonkandidaten in audio/sfx_ki/.

Schritte (einzeln oder mehrere nacheinander aufrufbar, z. B. "seite favoriten")
  messen   eigene Messungen je bearbeitetem Kandidaten -> audio/sfx_ki/messung_extra.json
           (ffmpeg astats an WAV, OGG und M4A; Einsatzverzug; Einsätze und Grundton je Einsatz; schmale Linien im
           Spektrum über 5 kHz; Rauschabstand des Originals)
  bilder   Spektrogramm je Kandidat -> audio/sfx_ki/spektrogramme/einzeln/<id>.png (ffmpeg showspectrumpic)
  seite    audio/sfx_ki/hoeren.html aus varianten.json, messung_extra.json, beschreibungen.json, tags_ast.json und
           der Bewertung in tools/bewertung_sfx_ki.py (von Hand aus Messwerten und Modellbeschreibungen abgeleitet)
  favoriten  kopiert die Favoriten nach audio/sfx_ki/favoriten/<ton>.ogg|.m4a (ungefiltert, nicht ins Spiel)
  alles    alle Schritte

Die Fassungen im Spiel erzeugt tools/make_sfx_moss.py --spiel (audio/sfx_ki/spiel/, mit messwerte.json); die Seite zeigt
sie im Abschnitt „Im Spiel“. Die alten synthetischen Töne (tools/make_sfx.py, bis 05.10.2026 im Spiel) liegen zum
Vergleich in audio/sfx_ki/alt/.

Aufruf (PowerShell)
  . E:\\Draw2Race-AudioLab\\env.ps1
  & E:\\Draw2Race-AudioLab\\analyse\\.venv\\Scripts\\python.exe tools\\hoerseite_sfx_ki.py alles
Benötigt ffmpeg/ffprobe im PATH, numpy, scipy, soundfile, librosa (Analyse-Umgebung der Werkstatt).
"""
import html
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SFX = ROOT / "audio" / "sfx_ki"
EINZELN = SFX / "spektrogramme" / "einzeln"
FAV = SFX / "favoriten"
ALT = SFX / "alt"            # alte synthetische Töne (Kopien aus webclient/sfx vom 05.10.2026)
SPIEL = SFX / "spiel"        # Fassungen im Spiel (make_sfx_moss.py --spiel)


def rd(path, default=None):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else ({} if default is None else default)


def kandidaten():
    return rd(SFX / "varianten.json")["kandidaten"]


# ---------------------------------------------------------------------------------------------------------------
# messen
# ---------------------------------------------------------------------------------------------------------------
def astats(path):
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af",
                        "astats=measure_perchannel=none:measure_overall=Peak_level+RMS_level+Noise_floor+Flat_factor"
                        "+Peak_count+DC_offset", "-f", "null", "-"], capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    out = {}
    for key, name in (("Peak level dB", "spitze_db"), ("RMS level dB", "rms_db"), ("Noise floor dB", "rauschboden_db"),
                      ("Flat factor", "flat_factor"), ("Peak count", "spitzen_anzahl"), ("DC offset", "dc")):
        m = re.findall(rf"{re.escape(key)}:\s*(-?[\d.]+|-?inf)", r.stderr)
        if m:
            v = m[-1]
            out[name] = round(float(v), 3) if v not in ("inf", "-inf") else v
    return out


def dauer(path):
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                       capture_output=True, text=True)
    try:
        return round(float(r.stdout.strip()), 3)
    except ValueError:
        return None


def analyse(wav):
    import librosa
    import numpy as np
    import soundfile as sf
    from scipy.ndimage import median_filter
    from scipy.signal import welch

    y, sr = sf.read(wav, dtype="float64")
    if y.ndim > 1:
        y = y.mean(1)
    peak = np.max(np.abs(y)) + 1e-12
    # Hüllkurve 2 ms
    hop = int(sr * 0.002)
    env = np.array([np.sqrt(np.mean(y[i:i + hop] ** 2)) for i in range(0, len(y) - hop, hop)]) + 1e-12
    env_db = 20 * np.log10(env / env.max())
    t_env = np.arange(len(env)) * hop / sr
    first = int(np.argmax(env_db > -20))
    res = {
        "einsatz_m20db_ms": round(t_env[first] * 1000, 1),
        "hoechstwert_ms": round(float(np.argmax(np.abs(y))) / sr * 1000, 1),
    }
    # Einsätze (librosa) und Grundton nach jedem Einsatz
    on = librosa.onset.onset_detect(y=y.astype(np.float32), sr=sr, units="time", backtrack=False, delta=0.15)
    res["einsaetze_s"] = [round(float(t), 3) for t in on][:12]
    pitches = []
    for t in on[:6]:
        a = int((t + 0.015) * sr)
        seg = y[a:a + int(0.09 * sr)]
        if len(seg) < 1024:
            continue
        spec = np.abs(np.fft.rfft(seg * np.hanning(len(seg)), n=16384))
        f = np.fft.rfftfreq(16384, 1 / sr)
        band = (f > 80) & (f < 4000)
        pitches.append(int(f[band][np.argmax(spec[band])]))
    res["staerkste_frequenz_je_einsatz_hz"] = pitches
    # schmale Linien im Spektrum über 5 kHz (Pfeifen) – Welch-Spektrum gegen geglättete Grundlinie
    f, p = welch(y, fs=sr, nperseg=8192)
    pdb = 10 * np.log10(p + 1e-20)
    base = median_filter(pdb, size=101)
    prom = pdb - base
    top = pdb.max()
    lines = []
    for i in range(1, len(f) - 1):
        if f[i] > 5000 and prom[i] > 12 and pdb[i] > top - 60 and pdb[i] >= pdb[i - 1] and pdb[i] >= pdb[i + 1]:
            lines.append((int(f[i]), round(float(prom[i]), 1), round(float(pdb[i] - top), 1)))
    lines.sort(key=lambda x: -x[1])
    res["linien_ueber_5k"] = lines[:5]
    # Anteil über 6 kHz nach einem gedachten Tiefpass 5 kHz wie in make_sfx_moss.py --tiefpass 5000 (Butterworth
    # 4. Ordnung, nur vorwärts); Katzen-Leitplanke: höchstens −30 dB
    from scipy.signal import butter, sosfilt, sosfiltfilt
    y5 = sosfilt(butter(4, 5000, "low", fs=sr, output="sos"), y)
    f2, p2 = welch(y5, fs=sr, nperseg=4096)
    res["ueber_6k_nach_tp5k_db"] = round(float(10 * np.log10(p2[f2 > 6000].sum() / p2.sum() + 1e-20)), 1)
    # Pulsfolge 15–50 Hz (Schnurr-Bereich, vgl. audio/sfx_README.md): Hüllkurvenspektrum, stärkste Linie
    from scipy.signal import hilbert, resample_poly
    if len(y) > 0.3 * sr:
        h = np.abs(hilbert(y))
        h = sosfiltfilt(butter(4, 150, "low", fs=sr, output="sos"), h)
        h = resample_poly(h, 1, sr // 1000)
        h = h - h.mean()
        n = 8192
        spec = np.abs(np.fft.rfft(h * np.hanning(len(h)), n=n))
        fm = np.fft.rfftfreq(n, 1 / 1000)
        band = (fm >= 15) & (fm <= 50)
        ref = (fm >= 5) & (fm <= 120)
        i = int(np.argmax(np.where(band, spec, 0)))
        res["puls_15_50"] = {"hz": round(float(fm[i]), 1),
                             "schaerfe": round(float(spec[i] / (np.median(spec[ref]) + 1e-12)), 1)}
    return res


def messen():
    out = {}
    for c in kandidaten():
        cid = c["id"]
        wav = SFX / f"{cid}.wav"
        e = analyse(wav)
        e["wav"] = astats(wav)
        e["ogg"] = astats(SFX / f"{cid}.ogg")
        e["m4a"] = astats(SFX / f"{cid}.m4a")
        e["dauer_wav_s"] = dauer(wav)
        e["dauer_ogg_s"] = dauer(SFX / f"{cid}.ogg")
        e["dauer_m4a_s"] = dauer(SFX / f"{cid}.m4a")
        e["rauschabstand_roh_db"] = c["messwerte_roh"]["rauschabstand_db"]
        out[cid] = e
        print(cid, {k: e[k] for k in ("einsatz_m20db_ms", "einsaetze_s", "staerkste_frequenz_je_einsatz_hz",
                                      "linien_ueber_5k")}, "m4a pk", e["m4a"].get("spitze_db"), flush=True)
    (SFX / "messung_extra.json").write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")


# ---------------------------------------------------------------------------------------------------------------
# bilder
# ---------------------------------------------------------------------------------------------------------------
def bilder():
    EINZELN.mkdir(parents=True, exist_ok=True)
    for c in kandidaten():
        png = EINZELN / f"{c['id']}.png"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(SFX / f"{c['id']}.wav"), "-lavfi",
                        "showspectrumpic=s=640x200:legend=1:scale=log:fscale=lin:color=intensity:gain=2",
                        "-frames:v", "1", str(png)], check=True)
        try:  # Palette statt Vollfarbe: etwa ein Viertel der Dateigröße, für die Hörseite genau genug
            from PIL import Image
            Image.open(png).convert("RGB").quantize(colors=64, method=Image.Quantize.MEDIANCUT).save(png, optimize=True)
        except ImportError:
            pass
    print("Spektrogramme:", len(list(EINZELN.glob("*.png"))), flush=True)


# ---------------------------------------------------------------------------------------------------------------
# seite, favoriten
# ---------------------------------------------------------------------------------------------------------------
def bewertung():
    """BEWERTUNG, KURZ, REIHENFOLGE aus tools/bewertung_sfx_ki.py (eigene Datei, damit dieses Skript lesbar bleibt)."""
    import bewertung_sfx_ki as b
    return b.BEWERTUNG, b.KURZ, b.REIHENFOLGE


def esc(s):
    return html.escape(str(s), quote=True)


def zahl(v, nk=1):
    return f"{v:.{nk}f}".replace(".", ",").replace("-", "−")


def hinweise(c, mx, ast):
    """Automatische Warnzeichen je Kandidat (Text, Stufe 'warn' oder 'info')."""
    out = []
    m = c["messwerte"]
    w = ast.get("ast_warn", {})
    if w.get("Speech", 0) >= 0.1 or w.get("Human voice", 0) >= 0.1:
        out.append((f"AudioSet: Stimme/Sprache {zahl(max(w.get('Speech', 0), w.get('Human voice', 0)), 2)}", "warn"))
    for k in ("Hiss", "Static", "White noise"):
        if w.get(k, 0) >= 0.2:
            out.append((f"AudioSet: {k} {zahl(w[k], 2)}", "warn"))
    if any(w.get(k, 0) >= 0.05 for k in ("Cat", "Meow", "Purr", "Bird", "Dog", "Animal")):
        out.append(("AudioSet: Tierlaut-Verdacht", "warn"))
    if m["ueber_6k_db"] > -30:
        out.append((f"über 6 kHz {zahl(m['ueber_6k_db'])} dB (Katzen-Leitplanke −30 dB)", "info"))
    starke = [l for l in mx.get("linien_ueber_5k", []) if l[1] >= 18 and l[2] >= -45]
    if starke:
        out.append(("schmale Linie bei " + ", ".join(f"{zahl(l[0] / 1000)} kHz" for l in starke[:2]), "warn"))
    puls = mx.get("puls_15_50")
    if puls and puls["hz"] >= 17 and puls["schaerfe"] >= 10:
        out.append((f"Hüllkurve pulsiert mit {zahl(puls['hz'], 0)} Hz (Schnurr-Bereich 15–50 Hz)", "warn"))
    if mx.get("einsatz_m20db_ms", 0) >= 60:
        out.append((f"leiser Anlauf: erst nach {int(mx['einsatz_m20db_ms'])} ms laut", "info"))
    if m["handy_db"] <= -9:
        out.append((f"Handy-Lautsprecher {zahl(m['handy_db'])} dB (viel Tiefbass)", "warn"))
    if c["messwerte_roh"]["rauschabstand_db"] < 50:
        out.append((f"Rauschabstand im Original nur {zahl(c['messwerte_roh']['rauschabstand_db'])} dB", "warn"))
    return out


CSS = """
:root{--paper:#f6efe2;--card:#fffaf1;--ink:#2b2420;--muted:#6d6158;--line:#e2d6c3;--neon:#d6337f;--neon2:#138a8a;
--ok:#2f8a4c;--ok-bg:#e8f4ec;--warn:#9a4a12;--warn-bg:#fbe9d8;--info:#4a5568;--info-bg:#ece8f3}
*{box-sizing:border-box}
body{margin:0;background:var(--paper);color:var(--ink);font:16px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:920px;margin:0 auto;padding:24px 16px 64px}
h1{font-size:1.7rem;margin:0 0 4px}
h2{font-size:1.35rem;margin:0}
h3{font-size:1.05rem;margin:0}
p{margin:.4em 0}
a{color:var(--neon2)}
code{font-size:.9em;background:#efe6d6;border-radius:4px;padding:0 4px}
.lead{color:var(--muted);margin:0 0 12px}
.box{border-left:4px solid var(--neon2);background:var(--card);border-radius:6px;padding:10px 14px;margin:14px 0}
.box.warnbox{border-left-color:var(--neon)}
.tabelle{overflow-x:auto}
table{border-collapse:collapse;width:100%;font-size:.95rem;background:var(--card);border-radius:8px}
th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line);vertical-align:top;overflow-wrap:anywhere}
th{color:var(--muted);font-weight:600}
nav{display:flex;flex-wrap:wrap;gap:6px;margin:14px 0 0}
nav a{background:var(--card);border:1px solid var(--line);border-radius:999px;padding:3px 12px;text-decoration:none;color:var(--ink)}
section.ton{margin-top:36px;padding-top:12px;border-top:2px solid var(--line)}
.kopf{display:flex;flex-wrap:wrap;align-items:baseline;gap:4px 14px}
.zweck{color:var(--muted)}
.alt{display:flex;flex-wrap:wrap;align-items:center;gap:4px 12px;background:var(--info-bg);border-radius:10px;padding:6px 12px;margin:12px 0}
.alt span{font-weight:600;color:var(--info)}
.alt audio{flex:1 1 260px;margin:4px 0}
.fazit{margin:8px 0 12px}
.karte{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px 16px;margin:12px 0}
.karte.fav{border:2px solid var(--ok);box-shadow:0 2px 0 var(--ok-bg)}
.karte.aus{opacity:.8}
.titel{display:flex;flex-wrap:wrap;align-items:center;gap:8px}
.badge{font-size:.8rem;font-weight:700;border-radius:999px;padding:2px 10px}
.badge.fav{background:var(--ok);color:#fff}
.badge.r2,.badge.r3{background:var(--ok-bg);color:var(--ok)}
.badge.aus{background:#ece7de;color:var(--muted)}
audio{display:block;width:100%;max-width:560px;margin:8px 0 4px}
.meta{color:var(--muted);font-size:.88rem}
.prompt{font-style:italic;color:var(--muted);font-size:.88rem}
.grund{margin:6px 0}
.chips{display:flex;flex-wrap:wrap;gap:6px;margin:6px 0}
.chip{font-size:.8rem;border-radius:6px;padding:1px 8px}
.chip.warn{background:var(--warn-bg);color:var(--warn)}
.chip.info{background:var(--info-bg);color:var(--info)}
details{margin:6px 0}
summary{cursor:pointer;color:var(--neon2);font-size:.92rem}
details.weitere>summary{font-size:1rem;font-weight:600;margin-top:8px;color:var(--ink)}
details img{display:block;max-width:100%;height:auto;margin-top:6px;border-radius:6px}
.modell{font-size:.88rem;background:#f3ebdd;border-radius:8px;padding:8px 12px;white-space:pre-wrap}
.klein{font-size:.85rem;color:var(--muted)}
.neu{display:flex;flex-wrap:wrap;align-items:center;gap:4px 12px;background:var(--ok-bg);border-radius:10px;padding:6px 12px;margin:12px 0}
.neu span{font-weight:600;color:var(--ok)}
.neu audio{flex:1 1 260px;margin:4px 0}
section.spiel{margin-top:28px}
.spielton{background:var(--card);border:2px solid var(--ok);border-radius:12px;padding:14px 16px;margin:12px 0}
.vergleich{display:grid;grid-template-columns:auto minmax(0,1fr);gap:0 12px;align-items:center;margin:8px 0 4px}
.vergleich span{font-size:.88rem;color:var(--muted)}
.vergleich audio{margin:3px 0;max-width:none}
@media (max-width:600px){.vergleich{grid-template-columns:minmax(0,1fr)}.vergleich span{margin-top:6px}}
@media (max-width:600px){h1{font-size:1.4rem}.karte{padding:12px}.tabelle.kurz th:nth-child(3),.tabelle.kurz td:nth-child(3){display:none}}
"""

JS = """
document.addEventListener('play', e => {
  for (const a of document.querySelectorAll('audio')) if (a !== e.target) a.pause();
}, true);
"""


def karte_html(c, rang, grund, mx, ast, besch):
    KURZ = bewertung()[1]
    cid = c["id"]
    m = c["messwerte"]
    aus = c.get("aussortiert")
    cls = "karte" + (" fav" if rang == 1 else "") + (" aus" if aus else "")
    if rang == 1:
        badge = '<span class="badge fav">Favorit</span>'
    elif rang in (2, 3):
        badge = f'<span class="badge r{rang}">Platz {rang}</span>'
    elif aus:
        badge = '<span class="badge aus">aussortiert</span>'
    else:
        badge = ""
    chips = "".join(f'<span class="chip {lvl}">{esc(t)}</span>' for t, lvl in hinweise(c, mx, ast))
    tags = ", ".join(f"{esc(k)} {zahl(v, 2)}" for k, v in ast.get("ast_top", [])[:4])
    frei = besch.get("frei", "")
    frage = besch.get("frage", "")
    teile = [
        f'<article class="{cls}" id="{esc(cid)}">',
        f'<div class="titel"><h3>{esc(cid)}</h3>{badge}</div>',
        f'<audio controls preload="none"><source src="{esc(cid)}.m4a" type="audio/mp4">'
        f'<source src="{esc(cid)}.ogg" type="audio/ogg"></audio>',
        f'<div class="meta">Dauer {zahl(m["dauer_s"], 2)} s · Lautheit {zahl(m["lufs_momentan_max"])} LUFS · '
        f'Schwerpunkt {m["schwerpunkt_hz"]} Hz · über 6 kHz {zahl(m["ueber_6k_db"])} dB · '
        f'Handy {zahl(m["handy_db"])} dB · Prompt P{c["prompt_nr"]}, Seed {c["seed"]}</div>',
        f'<p class="prompt">„{esc(c["prompt"])}“</p>',
    ]
    if KURZ.get(cid):
        teile.append(f'<p><b>Modell hört:</b> {esc(KURZ[cid])}</p>')
    if grund:
        teile.append(f'<p class="grund"><b>{"Warum Favorit" if rang == 1 else "Bewertung"}:</b> {esc(grund)}</p>')
    if aus:
        teile.append(f'<p class="grund"><b>Aussortiert:</b> {esc(aus)}</p>')
    if chips:
        teile.append(f'<div class="chips">{chips}</div>')
    teile.append(f'<details><summary>Spektrogramm</summary><img loading="lazy" '
                 f'src="spektrogramme/einzeln/{esc(cid)}.png" alt="Spektrogramm {esc(cid)}"></details>')
    if frei or frage:
        teile.append('<details><summary>Modelltexte (Qwen3-Omni-Captioner, englisch) und AudioSet-Tags</summary>'
                     f'<p class="klein">Freie Beschreibung:</p><div class="modell">{esc(frei)}</div>'
                     f'<p class="klein">Antwort auf die gezielte Frage:</p><div class="modell">{esc(frage)}</div>'
                     f'<p class="klein">AudioSet (AST): {tags}</p></details>')
    teile.append("</article>")
    return "\n".join(teile)


def player(stem, cls="", preload="none"):
    """<audio> mit M4A (Safari) und OGG; stem relativ zu audio/sfx_ki/ ohne Endung."""
    return (f'<audio controls preload="{preload}"{cls}><source src="{esc(stem)}.m4a" type="audio/mp4">'
            f'<source src="{esc(stem)}.ogg" type="audio/ogg"></audio>')


def spiel_html(BEWERTUNG, REIHENFOLGE):
    """Abschnitt „Im Spiel“: die endgültigen Fassungen aus audio/sfx_ki/spiel/ (make_sfx_moss.py --spiel)."""
    rep = rd(SPIEL / "messwerte.json")
    toene = rep.get("toene", {})
    if not toene:
        return ""
    stufe = rep.get("stufe_normal_db", {})
    lim = rep.get("leitplanke", {})
    zeilen, karten = [], []
    for t in [t for t in REIHENFOLGE if t in toene]:
        m = toene[t]
        name = BEWERTUNG[t]["name"]
        fc = zahl(m["tiefpass_hz"] / 1000, 2)
        gm = m.get("gegen_mau_db")
        zeilen.append(f'<tr><td><a href="#spiel-{t}">{esc(name)}</a></td><td>{esc(m["kandidat"])}</td><td>{fc} kHz</td>'
                      f'<td>{zahl(m["lufs_momentan_max"])} LUFS</td><td>{zahl(m["handy_db"])} dB</td>'
                      f'<td>{zahl(m["ueber_6k_db"])} dB</td><td>{zahl(gm) + " dB" if gm is not None else "–"}</td></tr>')
        extra = ""
        if m.get("tiefen_kuhschwanz"):
            k = m["tiefen_kuhschwanz"]
            extra = (f'<p class="klein">Zusätzlich Tiefen {zahl(k["db"], 0)} dB unter {zahl(k["hz"], 0)} Hz: Der Körper '
                     f'des Tons liegt bei etwa 165 Hz, den ein Handy-Lautsprecher nicht wiedergibt. So bleibt Platz für '
                     f'den hörbaren Teil.</p>')
        if m.get("kerben_hz"):
            extra += (f'<p class="klein">Zusätzlich eine schmale Kerbe bei '
                      f'{", ".join(zahl(h, 0) for h in m["kerben_hz"])} Hz: Schon der Rohton enthält dort einen reinen '
                      f'Pfeifton (wohl ein Rest des Modells), 14 dB über der Umgebung.</p>')
        alt = (f'<span>alt (synthetisch)</span>{player("alt/" + t)}' if (ALT / f"{t}.m4a").exists() else "")
        karten.append(
            f'<article class="spielton" id="spiel-{t}"><div class="titel"><h3>{esc(name)}</h3>'
            f'<span class="badge fav">im Spiel</span></div>'
            f'{player("spiel/" + t)}'
            f'<div class="meta">aus {esc(m["kandidat"])} · Tiefpass {fc} kHz vor- und rückwärts · Dauer '
            f'{zahl(m["dauer_s"], 2)} s · Lautheit {zahl(m["lufs_momentan_max"])} LUFS · Spitze '
            f'{zahl(m["spitze_dbtp"])} dBTP · Handy {zahl(m["handy_db"])} dB · über 6 kHz {zahl(m["ueber_6k_db"])} dB '
            f'(OGG {zahl(m["ogg"]["ueber_6k_db"])}, M4A {zahl(m["m4a"]["ueber_6k_db"])}) · über 10/12 kHz '
            f'{zahl(m["ueber_10k_db"])}/{zahl(m["ueber_12k_db"])} dB'
            + (f' · im Spiel {zahl(-gm)} dB unter dem Mau-Ton' if gm is not None else "") + '</div>'
            f'{extra}<div class="vergleich"><span>Favorit ungefiltert (12 kHz)</span>{player(m["kandidat"])}{alt}</div>'
            f'<details><summary>Spektrogramm (im Spiel)</summary><img loading="lazy" src="spiel/{esc(t)}.png" '
            f'alt="Spektrogramm {esc(name)} im Spiel"></details></article>')
    ton_db = stufe.get("toene")
    mau_db = stufe.get("mau_ton")
    pegel = (f' Im Spiel kommt die Stufe „Spieltöne“ dazu: „normal“ {zahl(ton_db)} dB, der Mau-Ton spielt bei „normal“ '
             f'mit {zahl(mau_db)} dB. „gegen Mau“ ist der Abstand zur Aufnahme „Mao“ im Spiel.'
             if ton_db is not None and mau_db is not None else "")
    return f"""<section class="spiel" id="im-spiel"><h2>Im Spiel</h2>
<p>Seit 06.10.2026 spielen App und Browser-Client diese Fassungen. Je Ton der Favorit, vor- und rückwärts
tiefpassgefiltert (Butterworth, zusammen 48 dB/Oktave) mit der höchsten Grenzfrequenz zwischen 4 und 6 kHz, bei der
über {zahl(lim.get("ueber_hz", 6000) / 1000, 0)} kHz höchstens {zahl(lim.get("hoechstens_db", -30), 0)} dB bleiben
(Katzen-Leitplanke). So bleibt jeder Ton so hell wie möglich. Lautstärken sind aufeinander abgestimmt: Karte legen
dezent, „Du bist dran“ und Sieg am lautesten, alle leiser als der Mau-Ton.{pegel} Spieltöne sind ab Werk aus
(Einstellungen → Spieltöne).</p>
<div class="tabelle"><table><thead><tr><th>Ton</th><th>Kandidat</th><th>Tiefpass</th><th>Lautheit</th><th>Handy-Verlust</th>
<th>über 6 kHz</th><th>gegen Mau</th></tr></thead><tbody>{''.join(zeilen)}</tbody></table></div>
{''.join(karten)}
<p class="klein">Unter jedem Ton zum Vergleich der ungefilterte Favorit (Kandidat, Tiefpass 12 kHz) und der alte
synthetische Ton. Erzeugt mit <code>tools/make_sfx_moss.py --spiel</code>; Messwerte in
<code>spiel/messwerte.json</code>.</p></section>"""


def seite():
    BEWERTUNG, _, REIHENFOLGE = bewertung()
    v = rd(SFX / "varianten.json")
    kand = {c["id"]: c for c in v["kandidaten"]}
    mx = rd(SFX / "messung_extra.json")
    ast = rd(SFX / "tags_ast.json")
    besch = rd(SFX / "beschreibungen.json")
    frage = None
    try:
        from beschreibe_sfx_ki import FRAGE as frage
    except ImportError:
        pass

    nav = "".join(f'<a href="#ton-{t}">{esc(BEWERTUNG[t]["name"])}</a>' for t in REIHENFOLGE)
    zeilen = []
    for t in REIHENFOLGE:
        b = BEWERTUNG[t]
        fav = b["rang"][0]
        zeilen.append(f'<tr><td><a href="#ton-{t}">{esc(b["name"])}</a></td><td><a href="#{fav}">{fav}</a></td>'
                      f'<td>{esc(", ".join(b["rang"][1:]))}</td><td>{esc(b["kurzgrund"])}</td></tr>')
    teile = [f"""<!doctype html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Spieltöne zum Anhören</title><style>{CSS}</style></head><body><main>
<h1>Spieltöne zum Anhören</h1>
<p class="lead">Mau-Mau Flip · KI-Kandidaten aus MOSS-SoundEffect v2.0 (Apache 2.0) · Stand 06.10.2026</p>
<div class="box"><b>Niemand im Team hat diese Töne bisher gehört.</b> Die Rangfolge beruht nur auf Messwerten,
Spektrogrammen und zwei Audio-Modellen (Qwen3-Omni-Captioner beschreibt, AudioSet-Klassifikator AST prüft auf Stimmen,
Tierlaute, Musik und Rauschen). Die Favoriten sind seit 06.10.2026 im Spiel, gefiltert und abgestimmt (Abschnitt
<a href="#im-spiel">Im Spiel</a>). Bitte mit Handy-Lautsprecher und mit Kopfhörern anhören; wer einen anderen
Kandidaten will, ändert die Wahl in <code>tools/make_sfx_moss.py</code> (<code>SPIEL</code>).</div>
<div class="tabelle kurz"><table><thead><tr><th>Ton</th><th>Favorit</th><th>Platz 2, 3</th><th>Kurz</th></tr></thead>
<tbody>{''.join(zeilen)}</tbody></table></div>
<nav><a href="#im-spiel">Im Spiel</a>{nav}</nav>
<div class="box warnbox"><b>Entschieden: Höhen.</b> Die Kandidaten unten sind bei 12 kHz begrenzt. Die Katzen-Leitplanke aus
<code>audio/sfx_README.md</code> erlaubt über 6 kHz höchstens −30 dB; die Papiergeräusche liegen dort bei −4 bis −25 dB.
Die Hinweise „über 6 kHz …“ an den Kandidaten markieren das. Für das Spiel wird jeder Ton vor- und rückwärts
gefiltert, je Ton mit der höchsten Grenzfrequenz zwischen 4 und 6 kHz, die die Leitplanke einhält.</div>
{spiel_html(BEWERTUNG, REIHENFOLGE)}
"""]
    for t in REIHENFOLGE:
        b = BEWERTUNG[t]
        cfg = v["toene"][t]
        alt = ALT / f"{t}.m4a"
        teile.append(f'<section class="ton" id="ton-{t}"><div class="kopf"><h2>{esc(b["name"])}</h2>'
                     f'<span class="zweck">{esc(b["zweck"])} · Ziel {zahl(cfg["ziel_s"][0], 2)}–'
                     f'{zahl(cfg["ziel_s"][1], 2)} s</span></div>')
        if (SPIEL / f"{t}.m4a").exists():
            teile.append(f'<div class="neu"><span>im Spiel (gefiltert)</span>{player("spiel/" + t)}</div>')
        if alt.exists():
            teile.append(f'<div class="alt"><span>alt (synthetisch)</span>{player("alt/" + t)}</div>')
        else:
            teile.append('<div class="alt"><span>alt</span> – für diesen Ton gibt es noch keine Fassung'
                         + (' (wird im Spiel nicht verwendet)' if not (SPIEL / f"{t}.m4a").exists() else '') + '.</div>')
        teile.append(f'<p class="fazit">{esc(b["fazit"])}</p>')
        for i, cid in enumerate(b["rang"], 1):
            teile.append(karte_html(kand[cid], i, b["gruende"].get(cid, ""), mx.get(cid, {}), ast.get(cid, {}),
                                    besch.get(cid, {})))
        rest = [c for c in v["kandidaten"] if c["ton"] == t and c["id"] not in b["rang"]]
        rest.sort(key=lambda c: (bool(c.get("aussortiert")), c["nr"]))
        teile.append(f'<details class="weitere"><summary>Weitere Kandidaten ({len(rest)})</summary>')
        for c in rest:
            teile.append(karte_html(c, 0, b["gruende"].get(c["id"], ""), mx.get(c["id"], {}),
                                    ast.get(c["id"], {}), besch.get(c["id"], {})))
        teile.append("</details>")
        prompts = "".join(f"<li>P{i}: {esc(p)}</li>" for i, p in enumerate(cfg["prompts"], 1))
        teile.append(f'<details><summary>Prompts für „{esc(b["name"])}“</summary><ul class="klein">{prompts}</ul>'
                     f'</details></section>')
    teile.append(f"""<section class="ton"><h2>So wurde bewertet</h2>
<p>Je Kandidat: Messwerte aus <code>varianten.json</code> (Dauer, Lautheit, Schwerpunkt, Anteil über 6 kHz,
Handy-Verlust mit Hochpass 800 Hz), eigene Messungen in <code>messung_extra.json</code> (ffmpeg astats an WAV, OGG und
M4A, Einsatzverzug, Einsätze, schmale Linien über 5 kHz), AudioSet-Klassen in <code>tags_ast.json</code> und zwei Texte
des Qwen3-Omni-30B-A3B-Captioners (int8, lokal) in <code>beschreibungen.json</code>: eine freie Beschreibung und die
Antwort auf die Frage <i>{esc(frage or '')}</i></p>
<p>Grenzen: Die Modelle beschreiben kurze Klänge oft blumig und erfinden Einzelheiten (z. B. Tonhöhen, Räume). Ob
etwas nervt, billig wirkt oder beim 50. Mal stört, können sie nicht beurteilen. Diese Seite ersetzt den Hörtest nicht.</p>
<p class="klein">Erzeugt von <code>tools/hoerseite_sfx_ki.py</code>; Bewertung in <code>tools/bewertung_sfx_ki.py</code>.</p>
</section></main><script>{JS}</script></body></html>""")
    (SFX / "hoeren.html").write_text("\n".join(teile), encoding="utf-8")
    print("hoeren.html geschrieben", flush=True)


def favoriten():
    BEWERTUNG, _, REIHENFOLGE = bewertung()
    FAV.mkdir(exist_ok=True)
    for t in REIHENFOLGE:
        cid = BEWERTUNG[t]["rang"][0]
        for ext in ("ogg", "m4a"):
            shutil.copyfile(SFX / f"{cid}.{ext}", FAV / f"{t}.{ext}")
    (FAV / "LIESMICH.txt").write_text(
        "Favoriten je Ton (Kopien der Kandidaten, ungefiltert bis 12 kHz). Herkunft: KI-erzeugt mit MOSS-SoundEffect\n"
        "v2.0, Apache 2.0. Die Fassungen im Spiel (gefiltert, Katzen-Leitplanke) liegen in ../spiel/.\n"
        "Von niemandem im Team gehört. Auswahl und Gründe: ../README.md und ../hoeren.html\n\n"
        + "".join(f"{t}: {BEWERTUNG[t]['rang'][0]}\n" for t in REIHENFOLGE), encoding="utf-8")
    print("Favoriten kopiert:", ", ".join(f"{t}={BEWERTUNG[t]['rang'][0]}" for t in REIHENFOLGE), flush=True)


if __name__ == "__main__":
    schritte = {"messen": messen, "bilder": bilder, "seite": seite, "favoriten": favoriten}
    wahl = list(schritte) if sys.argv[1:] == ["alles"] else sys.argv[1:]
    if not wahl or any(w not in schritte for w in wahl):
        sys.exit(__doc__)
    for w in wahl:
        schritte[w]()
