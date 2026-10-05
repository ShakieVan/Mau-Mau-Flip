"""Erzeugt Entwürfe für den „Mau!“-Ton von Mau-Mau Flip.

Zweck
  Wer seine vorletzte Karte legt, drückt „Mau!“. Dazu erklingt ein kurzes, süßes „Mauzen“, das echte Katzen weder
  anlocken noch verwirren soll. Das Skript baut die Varianten rein synthetisch mit numpy und scipy: keine Aufnahmen,
  keine fremden Samples, keine KI-Generatoren, kein Zufall. Gleiche Eingabe ergibt bitgleiche WAV-Dateien.

Varianten (Buchstaben wie die Konzepte der Recherche)
  a_blubb        A  weicher Synth (Sinus + Dreieck) mit Formant-Filter m→a→(o)u, C4→E4 (große Terz aufwärts, „Tag“)
  a_blubb_nacht  A  dieselbe Idee dunkler, D4→H3 (kleine Terz abwärts, „Nacht“)
  b_gesungen     B  stilisierte Stimme in Menschengröße (additive Formant-Synthese, heller Sprachchip-Klang),
                    H3→E4 (Quarte aufwärts)
  c_spieluhr     C  Celesta-artiger Zweiklang C5→E5 mit sich öffnendem und schließendem Tiefpass
  d_kalimba      D  zwei warme Zupftöne F4→C5, Tiefpass öffnet („ma“) und schließt („u“)

Aufruf (PowerShell, gekapselte Werkstatt E:\\Draw2Race-AudioLab)
  . E:\\Draw2Race-AudioLab\\env.ps1
  E:\\Draw2Race-AudioLab\\analyse\\.venv\\Scripts\\python.exe tools\\make_mau_sounds.py [ausgabeordner]
  Standard-Ausgabe: audio/entwurf/mau/. Benötigt numpy und scipy, für .ogg und .m4a ffmpeg im PATH.
  Danach prüfen: tools/measure_mau_sounds.py (Messwerte, Spektrogramme), tools/describe_mau_sounds.py (Modell).

Ergebnis je Variante: <name>.wav (48 kHz, mono, 16 Bit), <name>.ogg (Vorbis, für Godot und Browser),
<name>.m4a (AAC, für Safari); dazu varianten.json mit den Entwurfswerten.

Pegel: Alle Varianten gleich laut, Ziel −18 LUFS (höchste Momentan-Lautheit, 400-ms-Fenster nach ITU-R BS.1770),
echte Spitze höchstens −6 dBFS (Leitplanke 9). Ist die Spitze die Grenze, bleibt die Datei leiser als −18 LUFS.

Leitplanken (Kurzfassung der Recherche zum Mau-Ton; Prüfung und Ergebnisse in audio/entwurf/mau/README.md)
  1   Dauer 200–380 ms über −40 dB, tonaler Kern ≤ 300 ms
  2   höchstens 2 stabile Töne (je ≥ 80 ms, ±30 Cent), Tonwechsel ≤ 30 ms, kein Bogen steigend-fallend > 3 Halbtöne
  3   Stimme: F0 180–330 Hz; Instrument: Grundton 330–880 Hz, perkussiv, ohne Vokal-Formanten
  4   Formanten in Menschengröße: F1 ≤ 1000 Hz, F2 ≤ 1500 Hz (nie über 1,8 kHz), Weg m→a→u, kein [i]
  5   Tiefpass 5 kHz (hier 8. Ordnung, 48 dB/Oktave); Energie über 6/10/12 kHz ≤ −30/−50/−60 dB gegenüber gesamt
  6   kein Rauschen, keine Zischlaute, keine Klicks; HNR ≥ 20 dB; Ein- und Ausblenden ≥ 5 ms
  7   keine Modulation 15–50 Hz, kein Vibrato, keine Pulsfolge
  8   Anstieg −40 → −3 dB in 10–40 ms, Ausklang 60–150 ms, kein harter Schnitt
  9   Spitze ≤ −6 dBFS
  10  ein Ton je Ansage, keine Schleife, kein Echo (Regel für den Spielcode)
  11  immer dieselbe Datei, kein Zufall; höchstens zwei feste Varianten (Tag/Nacht)
  12  weicht in mindestens 3 von 5 Achsen von echten Katzenrufen ab
"""
import json
import os
import shutil
import subprocess
import sys
import wave

import numpy as np
from scipy import signal

FS = 48000
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "audio", "entwurf", "mau")

TARGET_LUFS = -18.0
PEAK_LIMIT_DB = -6.0
LOWPASS_HZ = 5000.0
TAIL_S = 0.02            # Stille am Dateiende, damit Kodierer den Ausklang nicht abschneiden

# Tonhöhen (gleichstufig, A4 = 440 Hz)
NOTE = {"H3": 246.94, "C4": 261.63, "D4": 293.66, "E4": 329.63, "F4": 349.23, "C5": 523.25, "E5": 659.26}


# ---------------------------------------------------------------------------------------------------------------
# Bausteine
# ---------------------------------------------------------------------------------------------------------------

def t_axis(n):
    return np.arange(n) / FS


def path(n, points):
    """Verlauf aus Stützpunkten [(Zeit s, Wert), ...]: zwischen zwei Punkten weicher Kosinus-Übergang, danach Halten."""
    t = t_axis(n)
    out = np.full(n, float(points[0][1]))
    for (t0, v0), (t1, v1) in zip(points, points[1:]):
        m = (t >= t0) & (t < t1)
        u = (t[m] - t0) / max(t1 - t0, 1e-9)
        out[m] = v0 + (v1 - v0) * (0.5 - 0.5 * np.cos(np.pi * u))
        out[t >= t1] = v1
    return out


def amp_envelope(n, attack, hold_until, release):
    """Hüllkurve: Kosinus-Anstieg 0 → 1 in `attack` s, Halten bis `hold_until`, Kosinus-Ausklang in `release` s."""
    t = t_axis(n)
    env = np.ones(n)
    a = t < attack
    env[a] = 0.5 - 0.5 * np.cos(np.pi * t[a] / attack)
    r = t >= hold_until
    u = np.clip((t[r] - hold_until) / release, 0, 1)
    env[r] = 0.5 + 0.5 * np.cos(np.pi * u)
    return env


def resonance(f, F, B):
    """Betrag eines Kaskaden-Resonators (Formant) mit Mittenfrequenz F und Bandbreite B; Gleichanteil 1."""
    return 1.0 / np.sqrt((1.0 - (f / F) ** 2) ** 2 + (f * B / F ** 2) ** 2)


def bandpass(f, F, Q):
    """Betrag eines Bandpasses 2. Ordnung, Spitze 1 bei F."""
    f = np.maximum(f, 1.0)
    return 1.0 / np.sqrt(1.0 + Q ** 2 * (f / F - F / f) ** 2)


def lowpass_mag(f, fc, order=2):
    """Betrag eines Butterworth-Tiefpasses (nicht resonant)."""
    return 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def band_taper(f, lo, hi):
    """1 unterhalb lo, weicher Abfall auf 0 bis hi: Teiltöne verschwinden ohne Knacken, wenn die Tonhöhe wechselt."""
    u = np.clip((f - lo) / (hi - lo), 0, 1)
    return 0.5 + 0.5 * np.cos(np.pi * u)


def phone_weight(f, fc=800.0):
    """Leistungsgewicht für den Pegelausgleich: halb voller Frequenzgang, halb Handy-Lautsprecher (Hochpass 800 Hz).
    Ohne das wäre das u (Energie fast nur im Grundton) auf dem Handy viel leiser als das a."""
    hp = (f / fc) ** 4 / (1.0 + (f / fc) ** 4)
    return 0.5 + 0.5 * hp


def additive(f0, partial_amp, level_db, max_f=4500.0, taper=800.0):
    """Harmonische Synthese: Teilton k hat die Frequenz k·f0(t) und die Amplitude partial_amp(k, fk) (je Abtastwert).
    Teiltöne über max_f fehlen ganz; das Spektrum ist dadurch schon vor dem Tiefpass bandbegrenzt.
    Die Summe wird je Abtastwert auf die (mit phone_weight gewichtete) Leistung level_db gebracht: Laute mit offenem
    Mund (a) sind sonst viel lauter als m und u. So bestimmt level_db den Pegelverlauf, die Formanten die Klangfarbe."""
    phase = 2 * np.pi * np.cumsum(f0) / FS
    out = np.zeros_like(f0)
    power = np.zeros_like(f0)
    k = 1
    while k * f0.min() < max_f:
        fk = k * f0
        a = partial_amp(k, fk) * band_taper(fk, max_f - taper, max_f)
        out += a * np.sin(k * phase)
        power += 0.5 * a ** 2 * phone_weight(fk)
        k += 1
    return out / np.sqrt(power + 1e-12) * 10 ** (level_db / 20)


def semitones_to_hz(base_hz, st):
    return base_hz * 2.0 ** (st / 12.0)


def struck_note(n, t_on, f, partials, attack, gain=1.0, damp_at=None, damp_tau=0.03, fc=None):
    """Angeschlagener Ton (Celesta, Kalimba): Teiltöne (Verhältnis, Stärke, Abklingzeit) mit Kosinus-Anstieg.
    damp_at: ab hier zusätzlich schnell abdämpfen (der nächste Ton übernimmt). fc: Tiefpass-Verlauf je Abtastwert."""
    t = t_axis(n) - t_on
    on = t >= 0
    tt = np.where(on, t, 0.0)
    att = np.where(tt < attack, 0.5 - 0.5 * np.cos(np.pi * tt / attack), 1.0) * on
    damp = np.ones(n)
    if damp_at is not None:
        d = t_axis(n) >= damp_at
        damp[d] = np.exp(-(t_axis(n)[d] - damp_at) / damp_tau)
    x = np.zeros(n)
    for ratio, amp, tau in partials:
        fk = f * ratio
        a = amp * np.exp(-tt / tau)
        if fc is not None:
            a = a * lowpass_mag(fk, fc)
        x += a * np.sin(2 * np.pi * fk * tt)
    return gain * x * att * damp


def final_lowpass(x, fc=LOWPASS_HZ):
    """Butterworth 4. Ordnung vor- und rückwärts: zusammen 8. Ordnung (48 dB/Oktave), ohne Phasenverschiebung."""
    sos = signal.butter(4, fc, btype="low", fs=FS, output="sos")
    return signal.sosfiltfilt(sos, x)


# ---------------------------------------------------------------------------------------------------------------
# Lautheit (ITU-R BS.1770, K-Bewertung bei 48 kHz) und Pegel
# ---------------------------------------------------------------------------------------------------------------

K_SHELF = ([1.53512485958697, -2.69169618940638, 1.19839281085285], [1.0, -1.69065929318241, 0.73248077421585])
K_HIGHPASS = ([1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621])


def momentary_max_lufs(x):
    """Höchste Momentan-Lautheit (400-ms-Fenster, Schritt 10 ms). Für kurze Töne aussagekräftiger als integriert."""
    pad = np.zeros(int(0.4 * FS))
    y = np.concatenate([pad, x, pad])
    y = signal.lfilter(*K_SHELF, y)
    y = signal.lfilter(*K_HIGHPASS, y)
    win, hop = int(0.4 * FS), int(0.01 * FS)
    c = np.concatenate([[0.0], np.cumsum(y ** 2)])
    ms = (c[win::hop] - c[:-win:hop]) / win
    return -0.691 + 10 * np.log10(ms.max() + 1e-20)


def true_peak_db(x):
    """Echte Spitze über 4-fache Überabtastung (wie BS.1770)."""
    return 20 * np.log10(np.abs(signal.resample_poly(x, 4, 1)).max() + 1e-20)


def level(x):
    """Gleiche Lautheit für alle Varianten; die echte Spitze begrenzt (Leitplanke 9)."""
    g_lufs = 10 ** ((TARGET_LUFS - momentary_max_lufs(x)) / 20)
    g_peak = 10 ** ((PEAK_LIMIT_DB - 0.2 - true_peak_db(x)) / 20)
    return x * min(g_lufs, g_peak)


# ---------------------------------------------------------------------------------------------------------------
# Varianten
# ---------------------------------------------------------------------------------------------------------------

def blubb(night=False):
    """A „Blubb-Mau“: Sinus plus Dreieck (mit etwas Rechteck, damit das a durchkommt), zwei parallele
    Formant-Bandpässe wandern m→a→o→u;
    das u schließt sich erst im Ausklang, damit der zweite Ton auch auf Handy-Lautsprechern hörbar bleibt.
    Tag: C4 mit kleinem „Plopp“ (2 Halbtöne von oben, fällt mit 7 ms Zeitkonstante, liegt in der Anstiegszeit),
    dann große Terz aufwärts auf E4. Nacht: D4 → H3 (kleine Terz abwärts), dunklere Formanten und Klangfarbe."""
    if not night:
        dur, base, step, change = 0.31, NOTE["C4"], 4.0, (0.125, 0.150)
        f1 = [(0, 300), (0.012, 300), (0.055, 800), (0.120, 800), (0.165, 560), (0.270, 380)]
        f2 = [(0, 900), (0.012, 900), (0.055, 1300), (0.120, 1300), (0.165, 1050), (0.270, 850)]
        sine, tri, sq, gains, attack, hold, release = 0.20, 0.9, 0.10, (11.0, 4.0), 0.030, 0.180, 0.120
        lvl = [(0, -1.0), (0.055, 0.0), (0.125, 0.0), (0.165, -1.0)]
    else:
        dur, base, step, change = 0.33, NOTE["D4"], -3.0, (0.130, 0.155)
        f1 = [(0, 290), (0.012, 290), (0.060, 860), (0.125, 860), (0.170, 520), (0.290, 360)]
        f2 = [(0, 850), (0.012, 850), (0.060, 1150), (0.125, 1150), (0.170, 980), (0.290, 800)]
        sine, tri, sq, gains, attack, hold, release = 0.20, 0.9, 0.08, (10.0, 3.5), 0.032, 0.190, 0.125
        lvl = [(0, -1.0), (0.060, 0.0), (0.130, 0.0), (0.170, -1.5)]
    n = int(dur * FS)
    t = t_axis(n)
    st = path(n, [(0, 0.0), (change[0], 0.0), (change[1], step)]) + 2.0 * np.exp(-t / 0.007)
    f0 = semitones_to_hz(base, st)
    F1, F2 = path(n, f1), path(n, f2)
    level_db = path(n, lvl)

    def amp(k, fk):
        if k % 2 == 0:
            return 0.0 * fk                                        # nur ungerade Teiltöne: hohl und rund
        shape = 0.15 + gains[0] * bandpass(fk, F1, 6.0) + gains[1] * bandpass(fk, F2, 5.0)
        src = tri * (8 / np.pi ** 2) / k ** 2 + sq / k             # Dreieck plus etwas weiches Rechteck
        return sine + src * shape if k == 1 else src * shape

    x = additive(f0, amp, level_db, max_f=4000.0 if night else 4500.0)
    x *= amp_envelope(n, attack, hold, release)
    x = final_lowpass(x, 4000.0 if night else LOWPASS_HZ)
    info = {
        "konzept": "A „Blubb-Mau“" + (" (Nacht)" if night else " (Tag)"),
        "klasse": "stimme",
        "toene": ["D4", "H3"] if night else ["C4", "E4"],
        "toene_hz": [round(base, 2), round(semitones_to_hz(base, step), 2)],
        "intervall": "kleine Terz abwärts" if night else "große Terz aufwärts",
        "formanten_soll": {"m": [f1[0][1], f2[0][1]], "a": [f1[2][1], f2[2][1]], "o": [f1[4][1], f2[4][1]],
                           "u_ende": [f1[5][1], f2[5][1]]},
        "segmente": {"a": [0.065, 0.120], "o": [0.170, 0.215]},
        "tiefpass_hz": 4000 if night else 5000,
        "plopp": "Einschwingen 2 Halbtöne von oben, Zeitkonstante 7 ms (innerhalb der Anstiegszeit)",
    }
    return x, info


def sung(tilt=1.0, base="H3", step=5.0, morph=1.0, bw=1.0, f0_scale=1.0, upper_bw=None):
    """B „Gesungenes Mau“: additive Formant-Synthese mit stimmähnlicher Quelle, aber ohne Atem, Rauschen und Vibrato.
    Gesummtes m, dann a auf dem ersten Ton, dann eine Quarte höher ein o, das sich im Ausklang zum u schließt.
    Formanten F1/F2 wie eine erwachsene Menschenstimme.
    tilt: Abfall der Obertöne (k^−tilt; kleiner = heller, synthetischer). Runde 1 hatte tilt=1.6 (weich, „sanfte
    Stimme“); das Beschreibungsmodell hörte darin das Miau einer Hauskatze. Mit tilt=1.0 klingt B wie ein
    Spielzeug-Sprachchip („Boing“, „Partytröte“) und wird nicht mehr als Tier erkannt. Die hellere Quelle hob aber F3
    (2,3–2,7 kHz) als eigene Spitze hervor, nahe am F2 eines Katzen-Miaus (etwa 3 kHz); deshalb nur F1 und F2.
    So hört das Modell eine Kinderstimme, die „Mao“ sagt, bzw. eine Partytröte, und keinen Tierruf.
    morph: Dauer der Formant-Übergänge relativ (kleiner = sprunghafter). bw: Faktor für die Formant-Bandbreiten.
    f0_scale: Tonhöhe verschieben (Versuch mit A3 → D4 klang für das Modell nach Kinderstimme, verworfen).
    upper_bw: Faktor für die Bandbreiten von F3/F4 (größer = flacher); None = ohne F3/F4 (Standard)."""
    dur = 0.33
    n = int(dur * FS)
    st = path(n, [(0, 0.0), (0.140, 0.0), (0.165, step)])
    f0 = semitones_to_hz(NOTE[base] * f0_scale, st)

    def m(t0, t1):                                                 # Übergang t0 → t1, mit morph verkürzt
        return t0, t0 + (t1 - t0) * morph

    a0, a1 = m(0.028, 0.062)
    o0, o1 = m(0.140, 0.185)
    F1 = path(n, [(0, 280), (a0, 280), (a1, 820), (o0, 820), (o1, 560), (0.290, 400)])
    F2 = path(n, [(0, 1100), (a0, 1100), (a1, 1250), (o0, 1250), (o1, 1050), (0.290, 880)])
    F3 = path(n, [(0, 2650), (o0, 2650), (o1, 2500)])
    F4 = np.full(n, 3500.0)
    nasal = path(n, [(0, 1.0), (a0, 1.0), (m(0.028, 0.054)[1], 0.0)])   # Anteil des gesummten m
    level_db = path(n, [(0, -2.5), (a0, -2.5), (m(0.028, 0.060)[1], 0.0), (o0, 0.0), (o1, -1.5)])

    def amp(k, fk):
        source = k ** -tilt
        vowel = resonance(fk, F1, 90 * bw) * resonance(fk, F2, 110 * bw)
        if upper_bw is not None:
            vowel = vowel * resonance(fk, F3, 170 * bw * upper_bw) * resonance(fk, F4, 250 * bw * upper_bw)
        hum = resonance(fk, 260.0, 90) * lowpass_mag(fk, 420.0, 3)
        return source * ((1 - nasal) * vowel + nasal * hum)

    x = additive(f0, amp, level_db, max_f=4500.0)
    x *= amp_envelope(n, 0.030, 0.205, 0.120)
    x = final_lowpass(x)
    hz = [round(NOTE[base] * f0_scale, 2), round(semitones_to_hz(NOTE[base] * f0_scale, step), 2)]
    info = {
        "konzept": "B „Gesungenes Mau“",
        "klasse": "stimme",
        "toene": [base, "E4"] if (base, step, f0_scale) == ("H3", 5.0, 1.0) else [f"{hz[0]} Hz", f"{hz[1]} Hz"],
        "toene_hz": hz,
        "intervall": "Quarte aufwärts" if step == 5.0 else f"{step:+.0f} Halbtöne",
        "formanten_soll": {"m": [260, None], "a": [820, 1250], "o": [560, 1050], "u_ende": [400, 880]},
        "segmente": {"a": [0.065, 0.135], "o": [0.185, 0.235]},
        "tiefpass_hz": 5000,
        "parameter": {"tilt": tilt, "morph": morph, "bw": bw, "upper_bw": upper_bw},
    }
    return x, info


def music_box():
    """C „Spieluhr-Mau“: zwei angeschlagene, Celesta-artige Töne C5 → E5 (fast nur Grundton und Oktave), weicher
    Anschlag (18 ms). Ein nicht resonanter Tiefpass öffnet sich 500 → 1250 Hz („ma“) und schließt wieder auf 500 Hz („u“)."""
    dur = 0.34
    n = int(dur * FS)
    fc = path(n, [(0, 500), (0.060, 1250), (0.150, 1100), (0.280, 500)])
    partials = [(1.0, 1.0, 0.35), (2.0, 0.22, 0.09), (3.0, 0.06, 0.05)]
    x = struck_note(n, 0.0, NOTE["C5"], partials, 0.018, 1.0, damp_at=0.135, damp_tau=0.025, fc=fc)
    x += struck_note(n, 0.130, NOTE["E5"], partials, 0.018, 0.95, fc=fc)
    x *= amp_envelope(n, 0.001, 0.240, 0.100)
    x = final_lowpass(x)
    info = {
        "konzept": "C „Spieluhr-Mau“",
        "klasse": "instrument",
        "toene": ["C5", "E5"],
        "toene_hz": [NOTE["C5"], NOTE["E5"]],
        "intervall": "große Terz aufwärts",
        "filterweg_hz": [500, 1250, 1100, 500],
        "tiefpass_hz": 5000,
    }
    return x, info


def kalimba():
    """D „Kalimba-Pfoten-Mau“: zwei warme Zupftöne F4 → C5 (Quinte aufwärts), Teiltöne 1, 2, 3, 4 wie ein weich
    angeschlagener Holz- oder Metallstab. Tiefpass öffnet beim ersten Ton („ma“), schließt beim zweiten („u“).
    Rezept nannte D4 → A4; eine Quarte höher, damit der Grundton im Instrumentenbereich 330–880 Hz liegt."""
    dur = 0.32
    n = int(dur * FS)
    fc = path(n, [(0, 450), (0.030, 1800), (0.125, 1800), (0.240, 600)])
    partials = [(1.0, 1.0, 0.25), (2.0, 0.18, 0.07), (3.0, 0.08, 0.045), (4.0, 0.12, 0.025)]
    x = struck_note(n, 0.0, NOTE["F4"], partials, 0.018, 1.0, damp_at=0.125, damp_tau=0.020, fc=fc)
    x += struck_note(n, 0.120, NOTE["C5"], partials, 0.018, 0.95, fc=fc)
    x *= amp_envelope(n, 0.001, 0.215, 0.095)
    x = final_lowpass(x)
    info = {
        "konzept": "D „Kalimba-Pfoten-Mau“",
        "klasse": "instrument",
        "toene": ["F4", "C5"],
        "toene_hz": [NOTE["F4"], NOTE["C5"]],
        "intervall": "Quinte aufwärts",
        "filterweg_hz": [450, 1800, 1800, 600],
        "tiefpass_hz": 5000,
    }
    return x, info


def simon_style(tilt=1.15):
    """E „Mau im Stil der Nutzervorlage“ (04.10.2026): Der Nutzer gab als Stilvorlage ein „Mau“ aus einem bekannten
    Zeichentrickfilm (audio/referenz/, nicht im Repo, nicht verwendet, nur vermessen): eine Menschenstimme, die „mau“
    sagt – 0,44 s, F0 287 → 318 Hz sanft steigend und dann fast gleichbleibend, dunkler Vokal (F1 ≈ 400–430 Hz,
    F2 ≈ 800–1100 Hz), saubere Obertöne bis etwa 4 kHz, kein Rauschen. Nachgebaut werden nur diese Merkmale, gekürzt
    auf die Leitplanken: 0,34 s, ein einziger Ton mit kleinem Anstieg (+1,8 Halbtöne in 150 ms ≈ 1 Oktave/s),
    F0 ≤ 330 Hz, Formanten in Menschengröße, Weg m → a → o → u, Tiefpass 5 kHz."""
    dur = 0.34
    n = int(dur * FS)
    st = path(n, [(0, 0.0), (0.035, 0.0), (0.170, 1.8), (0.270, 1.6)])   # 287 Hz → 318 Hz, am Ende minimal zurück
    f0 = semitones_to_hz(287.0, st)
    F1 = path(n, [(0, 280), (0.028, 280), (0.062, 680), (0.135, 600), (0.205, 450), (0.285, 400)])
    F2 = path(n, [(0, 1050), (0.028, 1050), (0.062, 1150), (0.135, 1080), (0.205, 900), (0.285, 800)])
    nasal = path(n, [(0, 1.0), (0.028, 1.0), (0.054, 0.0)])
    level_db = path(n, [(0, -3.0), (0.028, -3.0), (0.060, 0.0), (0.215, -0.5), (0.270, -1.5)])

    def amp(k, fk):
        source = k ** -tilt
        vowel = resonance(fk, F1, 85) * resonance(fk, F2, 110)
        hum = resonance(fk, 260.0, 90) * lowpass_mag(fk, 420.0, 3)
        return source * ((1 - nasal) * vowel + nasal * hum)

    x = additive(f0, amp, level_db, max_f=4200.0)
    x *= amp_envelope(n, 0.030, 0.215, 0.105)
    x = final_lowpass(x)
    info = {
        "konzept": "E „Mau im Stil der Nutzervorlage“ (Menschenstimme, dunkles mao/mou)",
        "klasse": "stimme",
        "toene_hz": [287.0, round(semitones_to_hz(287.0, 1.8), 2)],
        "intervall": "sanfter Anstieg +1,8 Halbtöne, kein Bogen",
        "formanten_soll": {"m": [260, None], "a": [680, 1150], "o": [450, 900], "u_ende": [400, 800]},
        "segmente": {"a": [0.062, 0.135], "o": [0.205, 0.270]},
        "toene": ["287 Hz", "318 Hz"],
        "tiefpass_hz": 5000,
        "vorlage": "nur Merkmale vermessen (Dauer, F0-Verlauf, Formanten); die Aufnahme selbst wird nicht verwendet",
        "parameter": {"tilt": tilt},
    }
    return x, info


VARIANTS = {
    "a_blubb": lambda: blubb(False),
    "a_blubb_nacht": lambda: blubb(True),
    "b_gesungen": sung,
    "c_spieluhr": music_box,
    "d_kalimba": kalimba,
    "e_vorlage_stil": simon_style,
}


# ---------------------------------------------------------------------------------------------------------------
# Ausgabe
# ---------------------------------------------------------------------------------------------------------------

def write_wav(path_, x):
    q = np.round(np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path_, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(FS)
        wf.writeframes(q.tobytes())


def encode(wav_path):
    """OGG Vorbis (Godot, Chrome, Firefox) und M4A/AAC (Safari) aus der WAV-Datei."""
    if not shutil.which("ffmpeg"):
        print("  ffmpeg fehlt: nur WAV geschrieben")
        return
    base = wav_path[:-4]
    common = ["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-map_metadata", "-1"]
    subprocess.run(common + ["-c:a", "libvorbis", "-q:a", "6", base + ".ogg"], check=True)
    subprocess.run(common + ["-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", base + ".m4a"], check=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = {"abtastrate": FS, "bit": 16, "kanaele": 1, "ziel_lufs_momentan": TARGET_LUFS,
                "spitze_max_dbtp": PEAK_LIMIT_DB, "herkunft": "synthetisch, eigenes Skript tools/make_mau_sounds.py",
                "varianten": {}}
    for name, build in VARIANTS.items():
        x, info = build()
        x = level(x)
        x = np.concatenate([x, np.zeros(int(TAIL_S * FS))])
        wav = os.path.join(OUT, name + ".wav")
        write_wav(wav, x)
        encode(wav)
        info["lufs_momentan_max"] = round(momentary_max_lufs(x), 2)
        info["echte_spitze_dbtp"] = round(true_peak_db(x), 2)
        info["laenge_datei_s"] = round(len(x) / FS, 3)
        manifest["varianten"][name] = info
        print(f"{name:15s} {info['lufs_momentan_max']:6.1f} LUFS  Spitze {info['echte_spitze_dbtp']:6.1f} dBTP  "
              f"{info['laenge_datei_s']:.3f} s")
    with open(os.path.join(OUT, "varianten.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    print("Mau-Töne:", len(VARIANTS), "Varianten in", OUT)


if __name__ == "__main__":
    main()
