"""Reaktionstöne „Heulen“ und „Facepalm“ aus den Aufnahmen des Nutzers (18.10.2026): audio/aufnahmen/Weinen 2.m4a, Facepalm 2.m4a.

Nutzerwunsch: „Beides bitte hochpitchen (Chipmunk).“ Je Aufnahme mehrere Stufen zum Vergleich, Wahl des Nutzers per Hörseite:
  original   unverändert (nur aufbereitet), zum Vergleich
  hoch4 … hoch10   Chipmunk wie ein zu schnell laufendes Band: +4/+6/+8/+10 Halbtöne, entsprechend kürzer
  nur6       +6 Halbtöne, gleiche Länge (Tonhöhe ohne Tempo; etwas künstlicher)
Kette je Stufe (ffmpeg): Ausschnitt mit kurzem Vor- und Nachlauf, Entrauschen (afftdn), Tiefen weg, Tonhöhe, Präsenz 2,2 kHz,
Katzen-Leitplanke (Tiefpass 5,5 kHz zweifach; über 6 kHz höchstens −30 dB Energieanteil – hochgepitchte Stimmen rücken Energie
nach oben), leichte Verdichtung, weiche Ränder; dann wie die übrigen Reaktionstöne (tools/make_ostereier.py) auf −19 LUFS
höchste Momentan-Lautheit (400 ms) und echte Spitze ≤ −1 dBTP, Ogg Vorbis q6 und AAC (Browser), mono 48 kHz. „Wie am Handy“:
make_schnurren.handy_modell, auf gleiche Lautheit gehoben. AudioSet-Prüfung (Katze, Sprache, Top-Klassen) mit --ast in der
analyse-Umgebung (MIT/ast-finetuned-audioset-10-10-0.4593, CPU).

Aufruf (PowerShell):
  . E:\\Draw2Race-AudioLab\\env.ps1
  & 'E:\\Draw2Race-AudioLab\\moss-sfx\\.venv\\Scripts\\python.exe' tools\\make_reaktion_aufnahmen.py           # Töne + Messung
  & 'E:\\Draw2Race-AudioLab\\analyse\\.venv\\Scripts\\python.exe' tools\\make_reaktion_aufnahmen.py --ast     # AudioSet
Ergebnis: audio/entwurf/reaktion_aufnahmen/<ton>_<stufe>.ogg|.m4a, <ton>_<stufe>_handy.ogg, messwerte.json
"""
import argparse
import json
import os
import re
import subprocess
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HIER)
IN = os.path.join(ROOT, "audio", "aufnahmen")
OUT = os.path.join(ROOT, "audio", "entwurf", "reaktion_aufnahmen")
TMP = os.path.join(OUT, "tmp")
FS = 48000
ZIEL_LUFS = -19.0
SPITZE_DBTP = -1.0
ANALYSE_PY = r"E:\Draw2Race-AudioLab\analyse\.venv\Scripts\python.exe"
AST_MODEL = "MIT/ast-finetuned-audioset-10-10-0.4593"

# Ton, Quelle, Anfang, Ende (s; silencedetect −40 dB: Facepalm 0,627–1,605 s, Weinen 0,796–2,803 s; Vorlauf/Ausklang dazu)
QUELLEN = {"facepalm": ("Facepalm 2.m4a", 0.60, 1.70), "heulen": ("Weinen 2.m4a", 0.77, 2.90)}
# Stufe: (Halbtöne, Tempo mitnehmen)
STUFEN = {"original": (0, True), "hoch4": (4, True), "hoch6": (6, True), "hoch8": (8, True), "hoch10": (10, True),
          "nur6": (6, False)}
KATZE = ["Cat", "Meow", "Purr", "Caterwaul", "Roaring cats (lions, tigers)", "Domestic animals, pets"]
SPRACHE = ["Speech", "Male speech, man speaking", "Female speech, woman speaking", "Child speech, kid speaking"]


def ff(*args):
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args], check=True)


def ff_err(*args):
    return subprocess.run(["ffmpeg", "-hide_banner", "-nostats", *args], capture_output=True, text=True,
                          encoding="utf-8", errors="replace").stderr


def kette(st, tempo):
    f = 2.0 ** (st / 12.0)
    teile = ["afftdn=nr=18:nf=-70", "highpass=f=120:poles=2"]
    if st:
        teile += [f"asetrate={FS * f:.0f}", f"aresample={FS}"]
        if not tempo:
            teile.append(f"atempo={1.0 / f:.6f}")
    teile += ["highpass=f=220:poles=2", "equalizer=f=2200:t=q:w=1:g=3", "lowpass=f=5500:poles=2", "lowpass=f=5500:poles=2",
              "acompressor=threshold=0.1:ratio=3:attack=4:release=90:makeup=1.5"]
    return ",".join(teile)


def momentan_max(wav):
    """Höchste Momentan-Lautheit (LUFS, 400 ms) und echte Spitze (dBTP) aus ebur128."""
    log = ff_err("-i", wav, "-af", "ebur128=peak=true", "-f", "null", "-")
    ms = [float(x) for x in re.findall(r"M:\s*(-?\d+(?:\.\d+)?)", log)]
    tp = re.findall(r"Peak:\s*(-?\d+(?:\.\d+)?)\s*dBFS", log)
    return (max(ms) if ms else -70.0), (float(tp[-1]) if tp else 0.0)


def auf_lautheit(src, dst):
    m, _ = momentan_max(src)
    ff("-i", src, "-af", f"volume={ZIEL_LUFS - m:.2f}dB,alimiter=limit={10 ** (SPITZE_DBTP / 20):.4f}:attack=2:release=40:level=disabled",
       "-c:a", "pcm_s16le", "-ar", str(FS), "-ac", "1", dst)
    return momentan_max(dst)


def ueber_6k_db(wav):
    import numpy as np
    from scipy.io import wavfile
    sr, x = wavfile.read(wav)
    x = x.astype(np.float64)
    spec = np.abs(np.fft.rfft(x)) ** 2
    fr = np.fft.rfftfreq(len(x), 1 / sr)
    return round(10 * np.log10(spec[fr > 6000].sum() / max(spec.sum(), 1e-12) + 1e-15), 1)


def handy(src, dst):
    import numpy as np
    from scipy.io import wavfile
    sys.path.insert(0, HIER)
    import make_schnurren as s
    sr, x = wavfile.read(src)
    y = s.handy_modell(x.astype(np.float64) / 32768.0)
    y = y / max(np.max(np.abs(y)), 1e-9) * 0.5
    tmp = dst + ".roh.wav"
    wavfile.write(tmp, sr, (y * 32767).astype(np.int16))
    auf_lautheit(tmp, dst)
    os.remove(tmp)


def kodieren(wav, base):
    ff("-i", wav, "-c:a", "libvorbis", "-q:a", "6", base + ".ogg")
    ff("-i", wav, "-c:a", "aac", "-b:a", "192k", "-cutoff", "8000", "-movflags", "+faststart", base + ".m4a")


def toene():
    os.makedirs(TMP, exist_ok=True)
    mess = {}
    for ton, (datei, anfang, ende) in QUELLEN.items():
        for stufe, (st, tempo) in STUFEN.items():
            name = f"{ton}_{stufe}"
            roh = os.path.join(TMP, name + ".roh.wav")
            dauer = (ende - anfang) / (2.0 ** (st / 12.0) if tempo else 1.0)
            ff("-i", os.path.join(IN, datei), "-af",
               f"atrim=start={anfang}:end={ende},asetpts=PTS-STARTPTS,{kette(st, tempo)},"
               f"afade=t=in:d=0.006,afade=t=out:st={max(0.0, dauer - 0.07):.3f}:d=0.07", "-ar", str(FS), "-ac", "1", roh)
            fertig = os.path.join(TMP, name + ".wav")
            lufs, tp = auf_lautheit(roh, fertig)
            kodieren(fertig, os.path.join(OUT, name))
            hw = os.path.join(TMP, name + "_handy.wav")
            handy(fertig, hw)
            ff("-i", hw, "-c:a", "libvorbis", "-q:a", "6", os.path.join(OUT, name + "_handy.ogg"))
            d = float(re.search(r"Duration: (\d+):(\d+):(\d+\.\d+)", ff_err("-i", fertig)).groups()[2])
            mess[name] = {"ton": ton, "stufe": stufe, "halbtoene": st, "tempo": tempo, "quelle": datei, "dauer_s": round(d, 2),
                          "lufs_momentan_max": round(lufs, 1), "spitze_dbtp": round(tp, 1), "ueber_6k_db": ueber_6k_db(fertig)}
            print(name, mess[name], flush=True)
            os.remove(roh)
    alt = _lesen()
    alt.update({"stand": "18.10.2026", "toene": mess})
    _schreiben(alt)


def ast():
    os.environ["HF_HUB_OFFLINE"] = "1"
    import librosa
    import numpy as np
    import torch
    from transformers import ASTFeatureExtractor, ASTForAudioClassification
    fe = ASTFeatureExtractor.from_pretrained(AST_MODEL)
    model = ASTForAudioClassification.from_pretrained(AST_MODEL).eval()
    labels = model.config.id2label
    idx = {v: int(k) for k, v in labels.items()}
    alt = _lesen()
    for name, m in alt.get("toene", {}).items():
        y, _ = librosa.load(os.path.join(TMP, name + ".wav"), sr=16000, mono=True)
        with torch.no_grad():
            p = torch.sigmoid(model(**fe(y, sampling_rate=16000, return_tensors="pt")).logits)[0].numpy()
        top = np.argsort(p)[::-1][:5]
        m["ast_top"] = [(labels[int(i)], round(float(p[i]), 3)) for i in top]
        m["ast_katze"] = max((round(float(p[idx[k]]), 3), k) for k in KATZE if k in idx)      # (Wert, Klasse)
        m["ast_sprache"] = max((round(float(p[idx[k]]), 3), k) for k in SPRACHE if k in idx)
        print(name, m["ast_top"][:3], "Katze", m["ast_katze"], flush=True)
    _schreiben(alt)


def _lesen():
    p = os.path.join(OUT, "messwerte.json")
    return json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {}


def _schreiben(d):
    with open(os.path.join(OUT, "messwerte.json"), "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--ast", action="store_true", help="nur die AudioSet-Prüfung (analyse-Umgebung)")
    a = ap.parse_args()
    if a.ast:
        ast()
    else:
        os.makedirs(OUT, exist_ok=True)
        toene()
