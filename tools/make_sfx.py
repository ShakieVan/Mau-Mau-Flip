"""Erzeugt die Spieltöne von Mau-Mau Flip (außer dem Mau-Ton) im Stil „Papier & Neon“.

Zweck
  Kurze, angenehme Töne für Karte legen, ziehen, mischen, Flip, Sieg, Fehler und „Du bist dran“. Rein synthetisch mit
  numpy und scipy: keine Aufnahmen, keine fremden Samples, keine KI-Generatoren. Rauschen kommt aus einem Zufallsgenerator
  mit festem Startwert; gleiche Eingabe ergibt bitgleiche Rohdaten.

Töne
  karte    Karte legen: weiches Papierklatschen (gefiltertes Rauschen + leiser tiefer „Plopp“), etwa 120 ms
  ziehen   Karte ziehen: weiches Gleiten (wandernder Bandpass, ohne Zischen) mit leisem Aufsetzen, etwa 280 ms
  mischen  kurzes Riffle: unregelmäßige Folge kleiner Papierklapse, am Ende ein weiches Zusammenschieben, 400 ms
  flip     Wusch (Bandpass hell → dunkel) und kurzer Glanz (A5 → E5 → C5 abwärts, a-Moll: Tag → Nacht), 600 ms
  sieg     kleine Fanfare im Glockenspiel-/Marimba-Klang: G4 C5 E5 G5, dann C6 mit C-Dur-Akkord, 1,2 s
  fehler   weiches tiefes „nö“: stilisierte Stimme B3 → G3 (n → ö), 150 ms
  dran     sanfter Zweiklang E5 → A5 (Vibraphon-artig), 250 ms

Aufruf (PowerShell, gekapselte Werkstatt E:\\Draw2Race-AudioLab, wird nur gelesen)
  . E:\\Draw2Race-AudioLab\\env.ps1
  E:\\Draw2Race-AudioLab\\analyse\\.venv\\Scripts\\python.exe tools\\make_sfx.py
  Benötigt numpy, scipy und ffmpeg im PATH. Schreibt keine Zwischendateien: ffmpeg bekommt die Abtastwerte über stdin,
  die Messung der kodierten Dateien dekodiert über stdout.

Ausgabe
  game/assets/sfx/<name>.ogg     Ogg Vorbis q6 (Godot)
  webclient/sfx/<name>.ogg       dieselbe Datei für den Browser-Client
  webclient/sfx/<name>.m4a       AAC 128 kbit/s mit Tiefpass 6 kHz (ffmpeg lowpass + Kodierer-Grenze 6 kHz), für Safari
  Auf stdout: Messtabelle (Markdown) für audio/sfx_README.md.

Leitplanken (sinngemäß aus audio/entwurf/mau/README.md, Katzen im Raum)
  - Tiefpass: Butterworth 4. Ordnung vor- und rückwärts (zusammen 8. Ordnung) bei 5 kHz; Energie über 6/10/12 kHz
    ≤ −30/−50/−60 dB gegenüber gesamt, auch in OGG und M4A.
  - Keine Quiek- oder Piep-Töne bei 3–4 kHz: Teiltöne über 2,6 kHz werden weich ausgeblendet, Rauschen ist bandbegrenzt.
  - Weicher Einsatz (Kosinus-Anstieg ≥ 3 ms, Klapse ≥ 1 ms), weicher Ausklang, kein harter Schnitt, keine Schleife.
  - Pegel: Bezug ist der Mau-Ton (Datei −18 LUFS, im Spiel −6 dB → −24 LUFS). Die übrigen Töne spielen mit −8 dB,
    ihre Dateien liegen 0–2 dB unter bzw. bei −16 LUFS, damit im Spiel kein Ton leiser als nötig und keiner lauter als
    der Mau-Ton ist (Sieg = Mau). Spitze höchstens −4 dBTP; kurze Klapse bleiben dadurch etwas leiser als ihr Ziel.
"""
import json
import os
import shutil
import subprocess
import sys

import numpy as np
from scipy import signal

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_mau_sounds import (FS, amp_envelope, band_taper, lowpass_mag, momentary_max_lufs, path, resonance,  # noqa: E402
                             semitones_to_hz, t_axis, true_peak_db)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME_SFX = os.path.join(ROOT, "game", "assets", "sfx")
WEB_SFX = os.path.join(ROOT, "webclient", "sfx")

LOWPASS_HZ = 5000.0
PEAK_LIMIT_DB = -4.0
TAIL_S = 0.02                  # Stille am Ende, damit Kodierer den Ausklang nicht abschneiden
PARTIAL_TOP = (2200.0, 2600.0)  # Teiltöne darüber weich ausblenden (kein Piepen bei 3–4 kHz)

# Ziel-Lautheit der Dateien (höchste Momentan-Lautheit, 400 ms, BS.1770). Mau-Datei: −18 LUFS bei −6 dB im Spiel.
TARGET_LUFS = {"karte": -18.0, "ziehen": -19.0, "mischen": -18.0, "flip": -17.0, "sieg": -16.0, "fehler": -16.5,
               "dran": -17.0}

NOTE = {"G3": 196.00, "B3": 233.08, "C4": 261.63, "G4": 392.00, "C5": 523.25, "E5": 659.26, "G5": 783.99,
        "A5": 880.00, "C6": 1046.50}


# ---------------------------------------------------------------------------------------------------------------
# Bausteine
# ---------------------------------------------------------------------------------------------------------------

def noise(n, seed):
    return np.random.default_rng(seed).standard_normal(n)


def butter(x, kind, f, order=2):
    sos = signal.butter(order, f, btype=kind, fs=FS, output="sos")
    return signal.sosfilt(sos, x)


def final_lowpass(x, fc=LOWPASS_HZ):
    """Butterworth 4. Ordnung vor- und rückwärts: zusammen 8. Ordnung (48 dB/Oktave), ohne Phasenverschiebung."""
    sos = signal.butter(4, fc, btype="low", fs=FS, output="sos")
    return signal.sosfiltfilt(sos, x)


def svf_bandpass(x, fc, q):
    """Zustandsvariablen-Bandpass (TPT) mit Mittenfrequenz je Abtastwert, Spitze 1. Für Wusch und Gleiten."""
    g = np.tan(np.pi * np.clip(fc, 20.0, FS * 0.45) / FS)
    k = 1.0 / q
    a1 = 1.0 / (1.0 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    y = np.zeros_like(x)
    ic1 = ic2 = 0.0
    for i in range(len(x)):
        v3 = x[i] - ic2
        v1 = a1[i] * ic1 + a2[i] * v3
        v2 = ic2 + a2[i] * ic1 + a3[i] * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        y[i] = k * v1
    return y


def decay_env(n, t_on, attack, tau):
    """Kosinus-Anstieg in `attack` s ab t_on, danach exponentielles Abklingen (Zeitkonstante tau)."""
    t = t_axis(n) - t_on
    on = t >= 0
    tt = np.where(on, t, 0.0)
    att = np.where(tt < attack, 0.5 - 0.5 * np.cos(np.pi * tt / attack), 1.0)
    rel = np.exp(-np.maximum(tt - attack, 0.0) / tau)
    return att * rel * on


def paper_noise(n, seed, lo, hi):
    """Rauschen für Papierklänge: Bandpass lo–hi, dazu Tiefpass 2,4 kHz (6. Ordnung, 36 dB/Oktave) gegen Zischen und
    gegen Energie bei 3–4 kHz; auf Streuung 1 gebracht."""
    y = butter(noise(n, seed), "bandpass", [lo, hi], 2)
    y = butter(y, "low", 2400, 6)
    return y / np.std(y)


def soft_clip(x, drive=2.0):
    """Weiche Sättigung (tanh) auf Spitze 1 bezogen: senkt den Scheitelfaktor kurzer Klapse, damit sie bei gleicher
    Spitze lauter wirken. Die entstehenden Obertöne nimmt der Tiefpass am Ende wieder weg."""
    p = np.abs(x).max() + 1e-12
    return np.tanh(drive * x / p) / np.tanh(drive)


def fade_out(x, start, length):
    """Weicher Ausklang ab `start` s über `length` s (Kosinus), danach Stille."""
    n = len(x)
    t = t_axis(n)
    u = np.clip((t - start) / length, 0, 1)
    return x * (0.5 + 0.5 * np.cos(np.pi * u))


def tone(n, t_on, f, partials, attack, gain=1.0, glide=None):
    """Angeschlagener Ton: Teiltöne (Verhältnis, Stärke, Abklingzeit). Teiltöne über PARTIAL_TOP verschwinden weich.
    glide: optional (Halbtöne, Zeitkonstante) – Tonhöhe fällt von oben ein (weicher Schlägelkontakt)."""
    t = t_axis(n) - t_on
    on = t >= 0
    tt = np.where(on, t, 0.0)
    att = np.where(tt < attack, 0.5 - 0.5 * np.cos(np.pi * tt / attack), 1.0) * on
    x = np.zeros(n)
    for ratio, amp, tau in partials:
        fk = f * ratio
        w = amp * band_taper(np.array(fk), *PARTIAL_TOP)
        if w <= 1e-6:
            continue
        if glide is not None:
            st = glide[0] * np.exp(-tt / glide[1])
            ph = 2 * np.pi * np.cumsum(fk * 2.0 ** (st / 12.0) * on) / FS
        else:
            ph = 2 * np.pi * fk * tt
        x += w * np.exp(-tt / tau) * np.sin(ph)
    return gain * x * att


MARIMBA = [(1.0, 1.0, 0.32), (4.0, 0.10, 0.045), (10.0, 0.02, 0.02)]           # Holzstab: Grundton, 4., 10. Teilton
GLOCKE = [(1.0, 1.0, 0.55), (2.76, 0.16, 0.12), (5.4, 0.04, 0.05)]             # Glockenspiel, weich angeschlagen
CELESTA = [(1.0, 1.0, 0.30), (2.0, 0.20, 0.08), (3.0, 0.05, 0.04)]
VIBRAPHON = [(1.0, 1.0, 0.22), (2.0, 0.10, 0.07), (4.0, 0.03, 0.03)]


# ---------------------------------------------------------------------------------------------------------------
# Töne
# ---------------------------------------------------------------------------------------------------------------

def karte():
    """Papierklatschen: bandbegrenztes Rauschen (700–2800 Hz) mit 3 ms Anstieg und 16 ms Abklingen, dazu ein dunkler
    Luftstoß (Tiefpass 900 Hz) und ein leiser tiefer Plopp (170 → 105 Hz). Etwa 120 ms über −40 dB."""
    n = int(0.15 * FS)
    t = t_axis(n)
    slap = paper_noise(n, 11, 600, 2400) * decay_env(n, 0.0, 0.003, 0.020)
    air = butter(noise(n, 12), "low", 900, 2)
    air = air / np.std(air) * decay_env(n, 0.0, 0.004, 0.028)
    f = 105 + 65 * np.exp(-t / 0.025)
    thump = np.sin(2 * np.pi * np.cumsum(f) / FS) * decay_env(n, 0.0, 0.004, 0.024)
    x = soft_clip(1.0 * slap + 0.55 * air + 1.1 * thump, 2.2)
    x = fade_out(x, 0.11, 0.035)
    return final_lowpass(x), {"dauer_soll_ms": "80–150", "bestandteile": "Rauschen 600–2400 Hz, Luftstoß < 900 Hz, Plopp 170→105 Hz"}


def ziehen():
    """Weiches Gleiten: Rauschen durch einen wandernden Bandpass 450 → 1300 → 900 Hz (Q 1,3), danach Tiefpass 2,4 kHz
    gegen jedes Zischen (6. Ordnung). Darunter ein sehr leiser Gleitton G4 → C5 (Neon), am Ende leises Aufsetzen. Etwa 280 ms."""
    n = int(0.30 * FS)
    fc = path(n, [(0, 450), (0.17, 1300), (0.26, 900)])
    swish = svf_bandpass(noise(n, 21), fc, 1.3)
    swish = butter(swish, "low", 2400, 6)
    swish *= amp_envelope(n, 0.040, 0.150, 0.110) / np.std(swish)
    st = path(n, [(0, 0.0), (0.04, 0.0), (0.20, 5.0)])
    f0 = semitones_to_hz(NOTE["G4"], st)
    ph = 2 * np.pi * np.cumsum(f0) / FS
    glide = (np.sin(ph) + 0.12 * np.sin(3 * ph)) * amp_envelope(n, 0.060, 0.170, 0.090) * 0.22
    tick = paper_noise(n, 22, 900, 2300) * decay_env(n, 0.205, 0.0015, 0.009) * 0.55
    x = swish + glide + tick
    x = fade_out(x, 0.25, 0.04)
    return final_lowpass(x), {"dauer_soll_ms": "etwa 250–300", "bandpass_hz": [450, 1300, 900], "tiefpass_rauschen_hz": 2400}


def mischen():
    """Kurzes Riffle: 26 kleine Papierklapse (je 1 ms Anstieg, 3,5 ms Abklingen, Bandpass 1,0–2,4 kHz) in
    unregelmäßigen Abständen (mittlere Rate ≈ 85/s, also keine Pulsfolge im Bereich 15–50 Hz), Lautstärke an- und
    abschwellend; am Ende ein weiches Zusammenschieben (Luftstoß + tiefer Plopp). 400 ms."""
    n = int(0.40 * FS)
    rng = np.random.default_rng(31)
    count = 26
    base = np.linspace(0.015, 0.315, count)
    times = base + rng.uniform(-0.0045, 0.0045, count)
    times[0] = 0.015
    x = np.zeros(n)
    for i, t0 in enumerate(times):
        lo = rng.uniform(1000, 1400)
        flap = paper_noise(n, 100 + i, lo, lo * rng.uniform(1.5, 1.75))
        shape = np.sin(np.pi * (i + 0.5) / count) ** 0.7
        x += flap * decay_env(n, t0, 0.001, 0.0035) * shape * rng.uniform(0.75, 1.0)
    x = soft_clip(x, 1.8)
    t = t_axis(n)
    air = butter(noise(n, 33), "low", 800, 2)
    air = air / np.std(air) * decay_env(n, 0.322, 0.006, 0.028) * 0.25
    f = 100 + 55 * np.exp(-np.maximum(t - 0.322, 0) / 0.03)
    thump = np.sin(2 * np.pi * np.cumsum(f) / FS) * decay_env(n, 0.322, 0.005, 0.026) * 0.35
    x = x + air + thump
    x = fade_out(x, 0.37, 0.03)
    return final_lowpass(x), {"dauer_soll_ms": 400, "klapse": count, "mittlere_rate_hz": round(count / 0.30, 1)}


def flip():
    """Wusch und Glanz, Tag → Nacht: Rauschen durch einen Bandpass, der 350 → 1700 Hz aufgeht und auf 450 Hz zufällt
    (hell → dunkel), Tiefpass 2,4 kHz. Ab 200 ms ein kurzer Glanz: drei Celesta-Töne A5, E5, C5 abwärts (a-Moll),
    der letzte klingt aus. Darunter ein leiser tiefer Gleitton D4 → A3 (Nacht). 600 ms."""
    n = int(0.60 * FS)
    fc = path(n, [(0, 350), (0.21, 1700), (0.46, 450)])
    whoosh = svf_bandpass(noise(n, 41), fc, 1.5)
    whoosh = butter(whoosh, "low", 2400, 6)
    swell = path(n, [(0, 0.0), (0.20, 1.0), (0.30, 0.75), (0.48, 0.0)])
    whoosh = whoosh / np.std(whoosh) * swell
    shine = (tone(n, 0.200, NOTE["A5"], CELESTA, 0.006, 0.55)
             + tone(n, 0.265, NOTE["E5"], CELESTA, 0.006, 0.60)
             + tone(n, 0.330, NOTE["C5"], CELESTA, 0.006, 0.70))
    st = path(n, [(0, 0.0), (0.22, 0.0), (0.50, -5.0)])
    f0 = semitones_to_hz(293.66, st)
    dark = np.sin(2 * np.pi * np.cumsum(f0) / FS) * amp_envelope(n, 0.12, 0.42, 0.14) * path(n, [(0, 0), (0.22, 0.25)])
    x = 0.55 * whoosh + 0.55 * shine + 0.35 * dark
    x = fade_out(x, 0.50, 0.095)
    return final_lowpass(x), {"dauer_soll_ms": 600, "bandpass_hz": [350, 1700, 450], "glanz": ["A5", "E5", "C5"]}


def sieg():
    """Kleine Fanfare: Marimba G4, C5, E5, G5 im Abstand von 100 ms, dann bei 420 ms C6 im Glockenspiel-Klang über
    einem C-Dur-Akkord (C4 Marimba, C5/E5/G5 Glocke). Ausklang bis 1,2 s."""
    n = int(1.20 * FS)
    x = np.zeros(n)
    for i, name in enumerate(["G4", "C5", "E5", "G5"]):
        x += tone(n, 0.100 * i, NOTE[name], MARIMBA, 0.006, 0.75 + 0.05 * i, glide=(0.4, 0.004))
    t_chord = 0.42
    x += tone(n, t_chord, NOTE["C6"], GLOCKE, 0.006, 0.80)
    for name, g in (("C5", 0.38), ("E5", 0.34), ("G5", 0.32)):
        x += tone(n, t_chord + 0.008, NOTE[name], GLOCKE, 0.008, g)
    x += tone(n, t_chord, NOTE["C4"], [(1.0, 1.0, 0.45), (4.0, 0.08, 0.05)], 0.006, 0.55)
    x = fade_out(x, 1.02, 0.17)
    return final_lowpass(x), {"dauer_soll_ms": 1200, "melodie": ["G4", "C5", "E5", "G5", "C6 + C-Dur"]}


def fehler():
    """Weiches tiefes „nö“: harmonische Quelle (Obertöne k^−1, bis 2 kHz, damit es auch auf Handy-Lautsprechern hörbar ist) mit Formanten n (Nasal 260 Hz) → ö
    (F1 460 Hz, F2 1350 Hz), Tonhöhe B3 → G3 sanft fallend. Anstieg 14 ms, Ausklang 60 ms, 150 ms."""
    n = int(0.15 * FS)
    st = path(n, [(0, 0.0), (0.03, 0.0), (0.12, -4.0)])
    f0 = semitones_to_hz(NOTE["B3"], st)
    ph = 2 * np.pi * np.cumsum(f0) / FS
    nasal = path(n, [(0, 1.0), (0.018, 1.0), (0.045, 0.0)])
    x = np.zeros(n)
    k = 1
    while k * f0.min() < 2000.0:
        fk = k * f0
        vowel = resonance(fk, 460.0, 110.0) * resonance(fk, 1350.0, 140.0)
        hum = resonance(fk, 260.0, 90.0) * lowpass_mag(fk, 450.0, 3)
        a = k ** -1.0 * ((1 - nasal) * vowel + nasal * hum) * band_taper(fk, 1600.0, 2000.0)
        x += a * np.sin(k * ph)
        k += 1
    x *= amp_envelope(n, 0.014, 0.090, 0.058)
    return final_lowpass(x), {"dauer_soll_ms": 150, "toene": ["B3", "G3"], "formanten_hz": {"n": 260, "ö": [460, 1350]}}


def dran():
    """Sanfter Zweiklang: Vibraphon-artige Töne E5 und 90 ms später A5 (Quarte aufwärts), weicher Anschlag,
    der erste Ton klingt unter dem zweiten weiter. Anschlag 7 ms. 250 ms."""
    n = int(0.25 * FS)
    x = tone(n, 0.0, NOTE["E5"], VIBRAPHON, 0.007, 0.85) + tone(n, 0.090, NOTE["A5"], VIBRAPHON, 0.007, 0.80)
    x = fade_out(x, 0.17, 0.08)
    return final_lowpass(x), {"dauer_soll_ms": 250, "toene": ["E5", "A5"]}


SOUNDS = {"karte": karte, "ziehen": ziehen, "mischen": mischen, "flip": flip, "sieg": sieg, "fehler": fehler, "dran": dran}


# ---------------------------------------------------------------------------------------------------------------
# Pegel und Messung
# ---------------------------------------------------------------------------------------------------------------

def level(x, target):
    g_lufs = 10 ** ((target - momentary_max_lufs(x)) / 20)
    g_peak = 10 ** ((PEAK_LIMIT_DB - 0.2 - true_peak_db(x)) / 20)
    return x * min(g_lufs, g_peak), g_peak < g_lufs


def envelope_db(x, win_ms=1.0):
    w = max(1, int(win_ms * FS / 1000))
    p = np.convolve(x ** 2, np.ones(w) / w, mode="same")
    return 10 * np.log10(p + 1e-20)


def measure(x):
    """Messwerte: Dauer über −40 dB, Anstieg des ersten Einsatzes (−40 dB bis 3 dB unter dem Höchstwert der ersten 60 ms), Lautheit, Spitze, Energieanteile über 6/10/12 kHz, Anteil
    und stärkste Spektralspitze im Bereich 3–4 kHz (gegenüber der stärksten Spitze überhaupt)."""
    env = envelope_db(x, 2.0)
    top = env.max()
    above = np.nonzero(env > top - 40)[0]
    start, end = above[0], above[-1]
    first = env[start:start + int(0.06 * FS)]                       # erster Einsatz: Höchstwert der ersten 60 ms
    rise = np.nonzero(first > first.max() - 3)[0][0]
    f, p = signal.welch(x, FS, nperseg=4096, noverlap=3072, window="hann")
    total = p.sum()

    def share(lo, hi=FS / 2):
        m = (f >= lo) & (f < hi)
        return round(10 * np.log10(p[m].sum() / total + 1e-20), 1)

    band = (f >= 3000) & (f < 4000)
    centroid = float((f * p).sum() / total)
    rms_core = 10 * np.log10(np.mean(x[start:end + 1] ** 2) + 1e-20)
    phone = butter(x, "high", 800, 2)                                # Handy-Lautsprecher wie im Mau-README (12 dB/Okt.)
    return {
        "handy_db": round(momentary_max_lufs(phone) - momentary_max_lufs(x), 1),
        "dauer_ms": round((end - start) / FS * 1000),
        "anstieg_ms": round(rise / FS * 1000, 1),
        "lufs_momentan_max": round(momentary_max_lufs(x), 1),
        "spitze_dbtp": round(true_peak_db(x), 1),
        "rms_dbfs": round(rms_core, 1),
        "schwerpunkt_hz": round(centroid),
        "ueber_6k_db": share(6000), "ueber_10k_db": share(10000), "ueber_12k_db": share(12000),
        "anteil_3_4k_db": share(3000, 4000),
        "spitze_3_4k_db": round(10 * np.log10(p[band].max() / p.max() + 1e-20), 1),
    }


def to_pcm16(x):
    return np.round(np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()


def encode(pcm, ogg_paths, m4a_path):
    """Kodiert aus den Abtastwerten (stdin) nach OGG (q6) und M4A (AAC 128 kbit/s, Tiefpass 6 kHz)."""
    inp = ["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(FS), "-ac", "1", "-i", "pipe:0",
           "-map_metadata", "-1"]
    for p in ogg_paths:
        subprocess.run(inp + ["-c:a", "libvorbis", "-q:a", "6", p], input=pcm, check=True)
    subprocess.run(inp + ["-af", "lowpass=f=6000:poles=2", "-c:a", "aac", "-b:a", "128k", "-cutoff", "6000",
                          "-movflags", "+faststart", m4a_path], input=pcm, check=True)


def decode(file_path):
    out = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", file_path, "-f", "f32le", "-ac", "1", "-ar", str(FS),
                          "pipe:1"], capture_output=True, check=True).stdout
    return np.frombuffer(out, dtype="<f4").astype(np.float64)


def main():
    if not shutil.which("ffmpeg"):
        sys.exit("ffmpeg fehlt im PATH (vorher . E:\\Draw2Race-AudioLab\\env.ps1)")
    os.makedirs(GAME_SFX, exist_ok=True)
    os.makedirs(WEB_SFX, exist_ok=True)
    rows = {}
    for name, build in SOUNDS.items():
        x, info = build()
        x, peak_bound = level(x, TARGET_LUFS[name])
        x = np.concatenate([x, np.zeros(int(TAIL_S * FS))])
        pcm = to_pcm16(x)
        ogg_game = os.path.join(GAME_SFX, name + ".ogg")
        ogg_web = os.path.join(WEB_SFX, name + ".ogg")
        m4a_web = os.path.join(WEB_SFX, name + ".m4a")
        encode(pcm, [ogg_game, ogg_web], m4a_web)
        m = measure(np.frombuffer(pcm, dtype="<i2") / 32768.0)
        m["ziel_lufs"] = TARGET_LUFS[name]
        m["spitze_begrenzt"] = bool(peak_bound)
        m["datei_s"] = round(len(x) / FS, 3)
        for label, fp in (("ogg", ogg_game), ("m4a", m4a_web)):
            y = decode(fp)
            mm = measure(y)
            m[label] = {k: mm[k] for k in ("lufs_momentan_max", "spitze_dbtp", "ueber_6k_db", "ueber_10k_db",
                                           "ueber_12k_db", "spitze_3_4k_db")}
            m[label]["bytes"] = os.path.getsize(fp)
        m["entwurf"] = info
        rows[name] = m
    ref = os.path.join(GAME_SFX, "mau_stimme.ogg")
    if os.path.exists(ref):
        mm = measure(decode(ref))
        rows["mau_stimme (Bezug)"] = mm
    print(json.dumps(rows, ensure_ascii=False, indent=1))
    print()
    print("| Ton | Dauer | Anstieg | LUFS (Ziel) | Spitze | RMS | Schwerpunkt | Handy | > 6/10/12 kHz | 3–4 kHz Anteil / Spitze | OGG > 6 kHz, Spitze | M4A > 6 kHz, Spitze |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for name, m in rows.items():
        o = m.get("ogg", {})
        a = m.get("m4a", {})
        print(f"| `{name}` | {m['dauer_ms']} ms | {m['anstieg_ms']} ms | {m['lufs_momentan_max']}"
              f" ({m.get('ziel_lufs', '–')}) | {m['spitze_dbtp']} dBTP | {m['rms_dbfs']} dBFS | {m['schwerpunkt_hz']} Hz"
              f" | {m['handy_db']} dB"
              f" | {m['ueber_6k_db']}/{m['ueber_10k_db']}/{m['ueber_12k_db']} dB"
              f" | {m['anteil_3_4k_db']} / {m['spitze_3_4k_db']} dB"
              f" | {o.get('ueber_6k_db', '–')} dB, {o.get('spitze_dbtp', '–')} dBTP"
              f" | {a.get('ueber_6k_db', '–')} dB, {a.get('spitze_dbtp', '–')} dBTP |")


if __name__ == "__main__":
    main()
