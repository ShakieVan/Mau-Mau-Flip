"""Misst die „Mau!“-Entwürfe gegen die Leitplanken und zeichnet Spektrogramme.

Aufruf (PowerShell, gekapselte Werkstatt E:\\Draw2Race-AudioLab)
  . E:\\Draw2Race-AudioLab\\env.ps1
  E:\\Draw2Race-AudioLab\\analyse\\.venv\\Scripts\\python.exe tools\\measure_mau_sounds.py [ordner]
  Standard-Ordner: audio/entwurf/mau/. Benötigt numpy, scipy, librosa, soundfile, matplotlib; ffmpeg im PATH.

Ergebnis: <ordner>/messwerte.json und <ordner>/spektrogramme/<variante>.png; Kurzfassung auf der Konsole.

Messverfahren
  Hüllkurve      RMS in 10-ms-Fenstern (Schritt 1 ms), in dB relativ zum Höchstwert
  Dauer          erste bis letzte Stelle über −40 dB; „Kern“ über −10 dB
  Anstieg        erste Stelle über −40 dB bis erste Stelle über −3 dB
  Ausklang       letzte Stelle über −3 dB bis letzte Stelle über −40 dB
  Grundfrequenz  librosa.pyin (Fenster 1024 = 21 ms, Schritt 2,5 ms) nur über −25 dB; stabile Abschnitte = Läufe mit
                 höchstens ±30 Cent um ihren Median, mindestens 80 ms lang
  Bogen          größter Anstieg mit anschließendem Abfall (steigend-fallend) in Halbtönen
  Gleiten        Steigung einer Ausgleichsgeraden über 40-ms-Fenster innerhalb der stabilen Töne (Oktaven/s)
  Formanten      Spitzen der Obertonhüllkurve (Teiltöne k·F0, Parabel durch drei Nachbarn) in den Vokal-Abschnitten
                 aus varianten.json; F2-Höchstwert über 50-ms-Abschnitte in den stabilen Tönen. LPC hängt bei F0 über 250 Hz an
                 einzelnen Obertönen fest und wird deshalb nicht verwendet. Genauigkeit etwa ±F0/3.
  Bandenergie    Leistungsspektrum der ganzen Datei; Anteil oberhalb 2/5/6/8/10/12 kHz relativ zur Gesamtenergie
  Klicks         größter Anteil über 6 kHz in 5-ms-Abschnitten (nur Abschnitte über −40 dB)
  HNR            Autokorrelation nach Boersma (40-ms-Fenster), Median der Abschnitte über −20 dB
  Modulation     Tiefe der Hüllkurvenschwankung im Band 15–50 Hz im Kern (Hilbert-Hüllkurve)
  Lautheit       eigene Momentan-Lautheit (BS.1770, 400 ms) und ffmpeg ebur128 (integriert, echte Spitze)
  Handy          grobe Simulation eines Kleinlautsprechers (Hochpass 800 Hz, 12 dB/Oktave): Lautheitsverlust und
                 Pegel von Ton 2 gegenüber Ton 1; zeigt, ob die Zwei-Ton-Melodie auf dem Handy erhalten bleibt
  Kodierte Dateien (.ogg, .m4a) werden mit ffmpeg dekodiert und auf Bandenergie, Klicks und Spitze geprüft.
"""
import json
import os
import re
import subprocess
import sys

import librosa
import matplotlib
import numpy as np
import soundfile as sf
from scipy import signal

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

FS = 48000
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "audio", "entwurf", "mau")

K_SHELF = ([1.53512485958697, -2.69169618940638, 1.19839281085285], [1.0, -1.69065929318241, 0.73248077421585])
K_HIGHPASS = ([1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621])


def db(x):
    return 10 * np.log10(np.maximum(x, 1e-30))


def decode(path):
    out = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(FS), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(out, dtype="<f4").astype(float)


def envelope_db(x, win_s=0.010, hop_s=0.001):
    win, hop = int(win_s * FS), int(hop_s * FS)
    pad = np.concatenate([np.zeros(win // 2), x, np.zeros(win // 2)])
    c = np.concatenate([[0.0], np.cumsum(pad ** 2)])
    idx = np.arange(0, len(x), hop)
    ms = (c[idx + win] - c[idx]) / win
    e = db(ms)
    return idx / FS, e - e.max()


def crossings(t, e, level):
    above = np.where(e >= level)[0]
    return (t[above[0]], t[above[-1]]) if len(above) else (np.nan, np.nan)


def momentary_max_lufs(x):
    pad = np.zeros(int(0.4 * FS))
    y = np.concatenate([pad, x, pad])
    y = signal.lfilter(*K_SHELF, y)
    y = signal.lfilter(*K_HIGHPASS, y)
    win, hop = int(0.4 * FS), int(0.01 * FS)
    c = np.concatenate([[0.0], np.cumsum(y ** 2)])
    ms = (c[win::hop] - c[:-win:hop]) / win
    return -0.691 + db(ms.max())


def true_peak_db(x):
    return 20 * np.log10(np.abs(signal.resample_poly(x, 4, 1)).max() + 1e-20)


def ffmpeg_ebur128(path):
    """Integrierte Lautheit und echte Spitze laut ffmpeg; der Ton wird mit Stille umgeben (400-ms-Blöcke)."""
    r = subprocess.run(["ffmpeg", "-nostats", "-i", path, "-af", "adelay=400:all=1,apad=pad_dur=0.6,ebur128=peak=true",
                        "-f", "null", "-"], capture_output=True, text=True, encoding="utf-8", errors="replace")
    tail = r.stderr[r.stderr.rfind("Summary:"):]
    i = re.search(r"I:\s+(-?[\d.]+) LUFS", tail)
    p = re.search(r"True peak:\s+Peak:\s+(-?[\d.]+|-inf) dBFS", tail)
    return (float(i.group(1)) if i else None), (float(p.group(1)) if p else None)


def band_energy(x, edges=(2000, 5000, 6000, 8000, 10000, 12000)):
    P = np.abs(np.fft.rfft(x, n=1 << int(np.ceil(np.log2(len(x) * 2))))) ** 2
    f = np.fft.rfftfreq(1 << int(np.ceil(np.log2(len(x) * 2))), 1 / FS)
    total = P.sum()
    return {f"ueber_{e // 1000}k_db": round(float(db(P[f > e].sum() / total)), 1) for e in edges}, \
        float((f * P).sum() / total)


def click_check(x, frame_s=0.005):
    """Größter Anteil über 6 kHz in 5-ms-Abschnitten: Klicks und Kodierfehler zeigen sich als kurze Breitband-Spitzen."""
    sos = signal.butter(8, 6000, btype="high", fs=FS, output="sos")
    hi = signal.sosfiltfilt(sos, x)
    n = int(frame_s * FS)
    m = len(x) // n
    e_all = (x[:m * n].reshape(m, n) ** 2).mean(1)
    e_hi = (hi[:m * n].reshape(m, n) ** 2).mean(1)
    ok = db(e_all) >= db(e_all.max()) - 40
    return float(db((e_hi[ok] / e_all[ok]).max()))


def hnr_median(x, win_s=0.040, hop_s=0.010, fmin=150, fmax=1000):
    n, hop = int(win_s * FS), int(hop_s * FS)
    w = np.hanning(n)
    rw = np.correlate(w, w, "full")[n - 1:]
    rw /= rw[0]
    lo, hi = int(FS / fmax), int(FS / fmin)
    frames, energies = [], []
    for s in range(0, len(x) - n, hop):
        fr = x[s:s + n]
        energies.append((fr ** 2).mean())
        frames.append(fr)
    energies = np.array(energies)
    keep = db(energies) >= db(energies.max()) - 20
    vals = []
    for fr, k in zip(frames, keep):
        if not k:
            continue
        y = (fr - fr.mean()) * w
        r = np.fft.irfft(np.abs(np.fft.rfft(y, 2 * n)) ** 2)[:n]
        r = r / r[0] / np.maximum(rw, 1e-9)
        rmax = np.clip(r[lo:hi].max(), 1e-6, 0.999999)
        vals.append(10 * np.log10(rmax / (1 - rmax)))
    return float(np.median(vals)), float(np.min(vals))


def am_depth(x, t_env, e_env, band=(15, 50)):
    """Hüllkurvenschwankung 15–50 Hz im Kern (über −10 dB, 20 ms vom Rand), als Anteil der mittleren Hüllkurve."""
    env = np.abs(signal.hilbert(x))
    env = signal.sosfiltfilt(signal.butter(4, 100, fs=FS, output="sos"), env)
    bp = signal.sosfiltfilt(signal.butter(2, band, btype="band", fs=FS, output="sos"), env)
    t0, t1 = crossings(t_env, e_env, -10)
    a, b = int((t0 + 0.02) * FS), int((t1 - 0.02) * FS)
    if b - a < int(0.03 * FS):
        return float("nan")
    return float(np.sqrt((bp[a:b] ** 2).mean()) / env[a:b].mean())


def pitch_track(x):
    hop = 120
    f0, voiced, prob = librosa.pyin(x, fmin=150, fmax=1000, sr=FS, frame_length=1024, hop_length=hop,
                                    center=True)
    t = librosa.frames_to_time(np.arange(len(f0)), sr=FS, hop_length=hop)
    return t, f0, voiced, prob


def stable_segments(t, cents, min_len=0.080, tol=30.0):
    """Läufe, in denen alle Werte höchstens ±tol Cent vom Median des Laufs abweichen (gierig von links)."""
    segs, i, n = [], 0, len(t)
    while i < n:
        if np.isnan(cents[i]):
            i += 1
            continue
        j = i
        while j + 1 < n and not np.isnan(cents[j + 1]):
            cand = cents[i:j + 2]
            if np.abs(cand - np.median(cand)).max() > tol:
                break
            j += 1
        if t[j] - t[i] >= min_len:
            seg = cents[i:j + 1]
            segs.append({"von_s": round(float(t[i]), 4), "bis_s": round(float(t[j]), 4),
                         "f0_median_hz": round(float(440 * 2 ** ((np.median(seg) - 5700) / 1200)), 1),
                         "abweichung_max_cent": round(float(np.abs(seg - np.median(seg)).max()), 1)})
            i = j + 1
        else:
            i += 1
    return segs


def arch_semitones(st):
    """Größter Bogen: Anstieg von einem früheren Tiefpunkt und anschließender Abfall, kleinere Seite zählt."""
    v = st[~np.isnan(st)]
    best = 0.0
    for j in range(len(v)):
        rise = v[j] - v[:j + 1].min()
        fall = v[j] - v[j:].min()
        best = max(best, min(rise, fall))
    return float(best)


def harmonic_peaks(x, t0, t1, f0):
    """Formant-Schätzung aus der Obertonhüllkurve: Amplituden der Teiltöne k·f0 im Abschnitt, lokale Höchstwerte,
    Lage per Parabel durch drei Nachbarn verfeinert. Robuster als LPC bei F0 über 250 Hz, Genauigkeit etwa ±f0/3."""
    a, b = int(t0 * FS), int(t1 * FS)
    seg = x[a:b] * np.hanning(b - a)
    N = 1 << 16
    S = 20 * np.log10(np.abs(np.fft.rfft(seg, N)) + 1e-12)
    f = np.fft.rfftfreq(N, 1 / FS)
    pts = []
    for k in range(1, int(4500 / f0) + 1):
        sel = (f > (k - 0.3) * f0) & (f < (k + 0.3) * f0)
        i = np.argmax(S[sel])
        pts.append((f[sel][i], S[sel][i]))
    pts = np.array(pts)
    pts = pts[pts[:, 1] > pts[:, 1].max() - 45]                 # fehlende (gerade) Teiltöne beim Dreieck auslassen
    peaks = []
    for i in range(1, len(pts)):                                # der Grundton allein ist kein Formant
        left = pts[i - 1, 1]
        right = pts[i + 1, 1] if i + 1 < len(pts) else -np.inf
        if pts[i, 1] >= left and pts[i, 1] > right:
            if i < len(pts) - 1:
                c = np.polyfit(pts[i - 1:i + 2, 0], pts[i - 1:i + 2, 1], 2)
                fv = -c[1] / (2 * c[0]) if c[0] < 0 else pts[i, 0]
                peaks.append(float(np.clip(fv, pts[i - 1, 0], pts[i + 1, 0])))
            else:
                peaks.append(float(pts[i, 0]))
    return peaks


def formants(x, t0, t1, f0_med):
    """Erste und zweite Spitze der Obertonhüllkurve ab dem 2. Teilton. None = keine Spitze, die Hüllkurve fällt vom
    Grundton an ab (dunkler o/u-artiger Klang, F1 liegt dann beim Grundton)."""
    p = harmonic_peaks(x, t0, t1, f0_med)
    return {"F1_hz": round(p[0]) if p else None, "F2_hz": round(p[1]) if len(p) > 1 else None,
            "f0_hz": round(f0_med)}


def formant_f2_max(x, t, f0, use, segs, win=0.05, hop=0.005):
    """Höchste zweite Spitze der Obertonhüllkurve über alle 50-ms-Abschnitte, die ganz in einem stabilen Ton liegen
    (über den Tonwechsel hinweg passen die Teiltöne nicht zu einem F0). Fehlt eine zweite Spitze, zählt die erste."""
    best = 0.0
    for sg in segs:
        s = sg["von_s"]
        while s + win <= sg["bis_s"] + 1e-9:
            sel = use & (t >= s) & (t <= s + win)
            if sel.sum() >= 3:
                p = harmonic_peaks(x, s, s + win, float(np.median(f0[sel])))
                if p:
                    best = max(best, p[1] if len(p) > 1 else p[0])
            s += hop
    return round(best)


def measure(name, info):
    wav = os.path.join(DIR, name + ".wav")
    x, sr = sf.read(wav)
    assert sr == FS
    t_env, e_env = envelope_db(x)
    on40, off40 = crossings(t_env, e_env, -40)
    on3, off3 = crossings(t_env, e_env, -3)
    on10, off10 = crossings(t_env, e_env, -10)
    m = {"datei": name + ".wav", "abtastwerte": len(x)}
    m["dauer_ueber_-40db_ms"] = round((off40 - on40) * 1000, 1)
    m["kern_ueber_-10db_ms"] = round((off10 - on10) * 1000, 1)
    m["anstieg_-40_bis_-3db_ms"] = round((on3 - on40) * 1000, 1)
    m["ausklang_-3_bis_-40db_ms"] = round((off40 - off3) * 1000, 1)
    m["beginn_ueber_-40db_ms"] = round(on40 * 1000, 1)

    # Grundfrequenz
    t, f0, voiced, prob = pitch_track(x)
    e_at = np.interp(t, t_env, e_env)
    use = voiced & (e_at >= -25) & (prob > 0.1)
    cents = np.where(use, 1200 * np.log2(np.where(use, f0, 1) / 440) + 5700, np.nan)
    segs = stable_segments(t, cents)
    m["stabile_toene"] = segs
    if len(segs) >= 2:
        m["tonwechsel_luecke_ms"] = round((segs[1]["von_s"] - segs[0]["bis_s"]) * 1000, 1)
        m["tonwechsel_luecke_ohne_fenster_ms"] = round(max(0.0, m["tonwechsel_luecke_ms"] - 1024 / FS * 1000), 1)
        m["intervall_halbtoene"] = round(12 * np.log2(segs[1]["f0_median_hz"] / segs[0]["f0_median_hz"]), 2)
    st = cents / 100
    m["bogen_steigend_fallend_halbtoene"] = round(arch_semitones(st), 2)
    # Gleiten: Steigung einer Ausgleichsgeraden über 40-ms-Fenster innerhalb der stabilen Töne (pyin rastert in
    # 10-Cent-Schritten; Differenzen von Frame zu Frame wären reine Rasterung).
    slopes = []
    for s in segs:
        idx = np.where((t >= s["von_s"]) & (t <= s["bis_s"]) & ~np.isnan(st))[0]
        w = int(round(0.040 / (t[1] - t[0])))
        for i in range(0, max(0, len(idx) - w) + 1):
            j = idx[i:i + w]
            if len(j) >= w // 2:
                slopes.append(abs(np.polyfit(t[j], st[j], 1)[0]) / 12)
    m["gleiten_max_in_stabilen_toenen_okt_s"] = round(float(max(slopes)), 2) if slopes else None
    voiced_f0 = f0[use]
    m["f0_min_hz"] = round(float(np.nanmin(voiced_f0)), 1) if len(voiced_f0) else None
    m["f0_max_hz"] = round(float(np.nanmax(voiced_f0)), 1) if len(voiced_f0) else None

    # Spektrum
    bands, centroid = band_energy(x)
    m["bandenergie"] = bands
    m["spektraler_schwerpunkt_hz"] = round(centroid, 0)
    m["klick_max_anteil_ueber_6k_db"] = round(click_check(x), 1)
    m["hnr_median_db"], m["hnr_min_db"] = [round(v, 1) for v in hnr_median(x)]
    m["am_tiefe_15_50hz_prozent"] = round(100 * am_depth(x, t_env, e_env), 1)
    if info.get("klasse") == "stimme":
        fm = {}
        for k, (s0, s1) in info["segmente"].items():
            sel = use & (t >= s0) & (t <= s1)
            fm[k] = formants(x, s0, s1, float(np.median(f0[sel])))
        fm["F2_max_im_kern_hz"] = formant_f2_max(x, t, f0, use, segs)
        m["formanten"] = fm

    # Pegel
    m["spitze_dbfs"] = round(20 * np.log10(np.abs(x).max()), 2)
    m["echte_spitze_dbtp"] = round(true_peak_db(x), 2)
    m["lufs_momentan_max"] = round(momentary_max_lufs(x), 2)
    m["ffmpeg_integriert_lufs"], m["ffmpeg_echte_spitze_dbfs"] = ffmpeg_ebur128(wav)
    m["rms_im_kern_dbfs"] = round(float(db((x[int(on10 * FS):int(off10 * FS)] ** 2).mean())), 1)

    # Grobe Handy-Simulation: Kleinlautsprecher fallen unter etwa 750–800 Hz ab (Hochpass 2. Ordnung bei 800 Hz).
    hp = signal.sosfiltfilt(signal.butter(1, 800, btype="high", fs=FS, output="sos"), x)
    m["handy_lautheitsverlust_db"] = round(momentary_max_lufs(hp) - m["lufs_momentan_max"], 1)
    if len(segs) >= 2:
        def seg_db(y, s):
            """Höchster 10-ms-RMS-Pegel im Abschnitt; der Ausklang zählt so nicht mit."""
            win = int(0.010 * FS)
            a, b = int(s["von_s"] * FS), int(s["bis_s"] * FS)
            c = np.concatenate([[0.0], np.cumsum(y[a:b] ** 2)])
            return float(db(((c[win:] - c[:-win]) / win).max()))
        m["ton2_gegen_ton1_db"] = round(seg_db(x, segs[1]) - seg_db(x, segs[0]), 1)
        m["ton2_gegen_ton1_handy_db"] = round(seg_db(hp, segs[1]) - seg_db(hp, segs[0]), 1)

    # Kodierte Fassungen
    m["kodiert"] = {}
    for ext in ("ogg", "m4a"):
        p = os.path.join(DIR, f"{name}.{ext}")
        if not os.path.exists(p):
            continue
        y = decode(p)
        b, _ = band_energy(y)
        m["kodiert"][ext] = {"bytes": os.path.getsize(p), "dauer_s": round(len(y) / FS, 3),
                             "bandenergie": {k: b[k] for k in ("ueber_6k_db", "ueber_10k_db", "ueber_12k_db")},
                             "klick_max_anteil_ueber_6k_db": round(click_check(y), 1),
                             "echte_spitze_dbtp": round(true_peak_db(y), 2)}

    m["pruefung"] = check(m, info)
    plot(name, info, x, t_env, e_env, t, f0, use, m)
    return m


def check(m, info):
    """Leitplanken 1–9, soweit messbar. True = eingehalten."""
    voice = info.get("klasse") == "stimme"
    segs = m["stabile_toene"]
    r = {}
    r["L1_dauer"] = 200 <= m["dauer_ueber_-40db_ms"] <= 380 and m["kern_ueber_-10db_ms"] <= 300
    lo, hi = (180, 330) if voice else (330, 880)
    r["L2_kontur"] = (1 <= len(segs) <= 2 and all(s["abweichung_max_cent"] <= 30 for s in segs)
                      and m.get("tonwechsel_luecke_ohne_fenster_ms", 0) <= 30
                      and m["bogen_steigend_fallend_halbtoene"] <= 3
                      and (m["gleiten_max_in_stabilen_toenen_okt_s"] or 0) <= 1.0)
    r["L3_grundfrequenz"] = all(lo * 0.99 <= s["f0_median_hz"] <= hi * 1.01 for s in segs)
    if voice:
        fl = m["formanten"]
        r["L4_formanten"] = all((v["F1_hz"] or 0) <= 1000 and (v["F2_hz"] or 0) <= 1500 for k, v in fl.items()
                                if isinstance(v, dict)) and (fl["F2_max_im_kern_hz"] or 0) <= 1800
    b = m["bandenergie"]
    coded_ok = all(c["bandenergie"]["ueber_6k_db"] <= -30 and c["bandenergie"]["ueber_10k_db"] <= -50
                   and c["bandenergie"]["ueber_12k_db"] <= -60 for c in m["kodiert"].values())
    r["L5_obere_grenze"] = b["ueber_6k_db"] <= -30 and b["ueber_10k_db"] <= -50 and b["ueber_12k_db"] <= -60
    r["L5_obere_grenze_kodiert"] = coded_ok
    r["L6_tonal_ohne_klick"] = m["hnr_median_db"] >= 20 and m["klick_max_anteil_ueber_6k_db"] <= -30
    r["L7_keine_modulation"] = m["am_tiefe_15_50hz_prozent"] <= 10 and all(s["abweichung_max_cent"] <= 30 for s in segs)
    a_lo = 20 if voice else 10
    r["L8_huellkurve"] = a_lo <= m["anstieg_-40_bis_-3db_ms"] <= 40 and 60 <= m["ausklang_-3_bis_-40db_ms"] <= 150
    peaks = [m["echte_spitze_dbtp"]] + [c["echte_spitze_dbtp"] for c in m["kodiert"].values()]
    r["L9_spitze"] = max(peaks) <= -6.0
    return r


def plot(name, info, x, t_env, e_env, t, f0, use, m):
    os.makedirs(os.path.join(DIR, "spektrogramme"), exist_ok=True)
    fig, ax = plt.subplots(3, 1, figsize=(9, 9.6), gridspec_kw={"height_ratios": [1.1, 1.3, 0.7]})
    lead = 0.06
    pad = np.concatenate([np.zeros(int(lead * FS)), x, np.zeros(int(lead * FS))])
    for k, (fmax, nfft, label) in enumerate([(24000, 2048, "0–24 kHz, 90 dB Dynamik; Linien bei 5, 6, 10, 12 kHz"),
                                             (6000, 4096, "0–6 kHz, Grundfrequenz (pyin) in Türkis")]):
        f_, t_, S = signal.spectrogram(pad, FS, window="hann", nperseg=nfft, noverlap=nfft - 96, mode="psd")
        S = db(S)
        vmax = S.max()
        sel = f_ <= fmax
        ax[k].pcolormesh((t_ - lead) * 1000, f_[sel] / 1000, S[sel], vmin=vmax - 90, vmax=vmax, cmap="magma",
                         shading="auto")
        ax[k].set_ylabel("kHz")
        ax[k].set_title(label, fontsize=9, loc="left")
        ax[k].set_xlim(-20, len(x) / FS * 1000)
        if k == 0:
            for g, ls in ((5, ":"), (6, "--"), (10, "--"), (12, "--")):
                ax[k].axhline(g, color="cyan", lw=0.6, ls=ls)
        else:
            ax[k].plot(t * 1000, np.where(use, f0, np.nan) / 1000, color="cyan", lw=1.6)
    ax[2].plot(t_env * 1000, e_env, color="k", lw=1)
    for lv in (-3, -10, -40):
        ax[2].axhline(lv, color="gray", lw=0.6, ls="--")
    ax[2].set_ylim(-60, 3)
    ax[2].set_xlim(-20, len(x) / FS * 1000)
    ax[2].set_ylabel("dB")
    ax[2].set_xlabel("ms")
    ax[2].set_title("Hüllkurve (10-ms-RMS), Linien bei −3/−10/−40 dB", fontsize=9, loc="left")
    segs = m["stabile_toene"]
    tones = " → ".join(f"{s['f0_median_hz']:.0f} Hz" for s in segs)
    fig.suptitle(f"{name}: {info['konzept']}\nDauer {m['dauer_ueber_-40db_ms']:.0f} ms · {tones} · "
                 f"Schwerpunkt {m['spektraler_schwerpunkt_hz']:.0f} Hz · über 6 kHz "
                 f"{m['bandenergie']['ueber_6k_db']:.0f} dB · {m['lufs_momentan_max']:.1f} LUFS", fontsize=10)
    fig.tight_layout()
    fig.savefig(os.path.join(DIR, "spektrogramme", name + ".png"), dpi=110)
    plt.close(fig)


def main():
    manifest = json.load(open(os.path.join(DIR, "varianten.json"), encoding="utf-8"))
    results = {}
    for name, info in manifest["varianten"].items():
        m = measure(name, info)
        results[name] = m
        fails = [k for k, v in m["pruefung"].items() if not v]
        tones = " → ".join(f"{s['f0_median_hz']:.0f}" for s in m["stabile_toene"])
        print(f"{name:14s} {m['dauer_ueber_-40db_ms']:5.0f} ms  F0 {tones:12s} Schwerp. {m['spektraler_schwerpunkt_hz']:5.0f} Hz  "
              f">6k {m['bandenergie']['ueber_6k_db']:6.1f} dB  HNR {m['hnr_median_db']:4.1f}  "
              f"Anst. {m['anstieg_-40_bis_-3db_ms']:4.0f}  Ausk. {m['ausklang_-3_bis_-40db_ms']:4.0f}  "
              f"{m['lufs_momentan_max']:5.1f} LUFS  {m['echte_spitze_dbtp']:5.1f} dBTP  "
              f"Handy {m['handy_lautheitsverlust_db']:5.1f} dB, Ton2/Ton1 {m.get('ton2_gegen_ton1_handy_db', 0):5.1f} dB  "
              f"{'alles eingehalten' if not fails else 'VERLETZT: ' + ', '.join(fails)}")
    with open(os.path.join(DIR, "messwerte.json"), "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=1, default=lambda o: o.item() if hasattr(o, "item") else str(o))


if __name__ == "__main__":
    main()
