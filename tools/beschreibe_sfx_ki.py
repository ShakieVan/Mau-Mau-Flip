"""Beschreibt die KI-Tonkandidaten in audio/sfx_ki/ mit zwei lokalen Modellen der Werkstatt (Ersatz fürs Anhören).

Zweck
  Niemand im Team hat die Kandidaten aus tools/make_sfx_moss.py gehört. Dieses Skript lässt sie von zwei
  Audio-Modellen beschreiben, damit sich offensichtliche Fehlgriffe (Stimmen, Tierlaute, Musik, Rauschen,
  Verzerrung, falsches Geräusch) ohne Ohren aussortieren lassen. Es ersetzt den Hörtest nicht.

Modelle (beide in der Werkstatt E:\\Draw2Race-AudioLab, offline)
  qwen  Qwen3-Omni-30B-A3B-Captioner (Apache 2.0), int8-Variante aus analyse/qwen_int8.py, braucht beide GPUs.
        Je Kandidat zwei Durchgänge: freie Beschreibung (nur Audio) und eine gezielte Frage (FRAGE unten).
  ast   AudioSet-Klassifikator MIT/ast-finetuned-audioset-10-10-0.4593 (BSD-3), CPU. Liefert die stärksten
        AudioSet-Klassen und die Werte der Warnklassen (Sprache, Tier, Katze, Musik, Rauschen, Verzerrung …).

Aufruf (PowerShell)
  . E:\\Draw2Race-AudioLab\\env.ps1
  $py = 'E:\\Draw2Race-AudioLab\\analyse\\.venv\\Scripts\\python.exe'
  & $py tools\\beschreibe_sfx_ki.py ast                 # schnell, CPU
  & $py tools\\beschreibe_sfx_ki.py qwen                # alle bearbeiteten Kandidaten (*.wav), etwa 1–2 min je Kandidat
  & $py tools\\beschreibe_sfx_ki.py qwen karte_0*.wav   # nur diese
  Bereits beschriebene Kandidaten werden übersprungen (Ergebnis wird nach jedem Kandidaten gespeichert).

Ausgabe
  audio/sfx_ki/beschreibungen.json  {id: {"frei": …, "frage": …, "qwen_s": …}}
  audio/sfx_ki/tags_ast.json        {id: {"ast_top": [[Klasse, p] …], "ast_warn": {Klasse: p}}}
"""
import json
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SFX = ROOT / "audio" / "sfx_ki"
OUT = SFX / "beschreibungen.json"
OUT_AST = SFX / "tags_ast.json"
ANALYSE = Path(os.environ.get("AUDIOLAB", r"E:\Draw2Race-AudioLab")) / "analyse"

FRAGE = ("This is a candidate sound effect for a card game app. What exactly is audible? How high-quality and "
         "realistic does it sound? Are there any unwanted elements: background noise, hiss, hum, distortion, "
         "clipping, digital artifacts, music, voices or speech, animal sounds? Answer in 3 to 5 short sentences.")
MAX_FREI = 450
MAX_FRAGE = 220

AST_MODEL = "MIT/ast-finetuned-audioset-10-10-0.4593"
AST_WARN = ["Speech", "Human voice", "Animal", "Cat", "Meow", "Purr", "Bird", "Dog", "Music", "Musical instrument",
            "Noise", "White noise", "Pink noise", "Static", "Hiss", "Hum", "Buzz", "Distortion", "Mains hum",
            "Silence", "Beep, bleep", "Whistle", "Squeak", "Chirp, tweet"]


def load(path=OUT):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def save(res, path=OUT):
    path.write_text(json.dumps(dict(sorted(res.items())), ensure_ascii=False, indent=1), encoding="utf-8")


def files(patterns):
    pats = patterns or ["*.wav"]
    return sorted({p for pat in pats for p in SFX.glob(pat) if p.suffix == ".wav"})


def schneller_decode(model):
    """Ersetzt in den int8-Experten (qwen_int8.py) den Schritt für 1–2 Token durch Gather + bmm.

    Die Schleife über die getroffenen Experten in qwen_int8 synchronisiert je Experte mit der CPU (nonzero/where);
    beim Erzeugen (1 Token je Schritt) bestimmt das die Laufzeit. Hier werden die k Experten des Tokens auf einmal
    geholt, entquantisiert und multipliziert. Rechnerisch dasselbe (bf16), nur ohne Schleife. Längere Eingaben
    (Prefill) laufen weiter über die ursprüngliche Funktion.
    """
    import types

    import torch

    def forward(self, hidden_states, top_k_index, top_k_weights):
        t, k = top_k_index.shape
        if t > 2:
            return self._int8_schleife(hidden_states, top_k_index, top_k_weights)
        idx = top_k_index.reshape(-1)
        x = hidden_states.repeat_interleave(k, dim=0).unsqueeze(-1)
        gu = self.gate_up_q[idx].to(hidden_states.dtype) * self.gate_up_s[idx]
        gate, up = torch.bmm(gu, x).squeeze(-1).chunk(2, dim=-1)
        a = (self.act_fn(gate) * up).unsqueeze(-1)
        d = self.down_q[idx].to(hidden_states.dtype) * self.down_s[idx]
        o = torch.bmm(d, a).squeeze(-1) * top_k_weights.reshape(-1, 1)
        return o.view(t, k, -1).sum(dim=1).to(hidden_states.dtype)

    n = 0
    for m in model.modules():
        if hasattr(m, "gate_up_q") and not hasattr(m, "_int8_schleife"):
            attr = "_old_forward" if hasattr(m, "_old_forward") else "forward"  # accelerate-Hook beibehalten
            m._int8_schleife = getattr(m, attr)
            setattr(m, attr, types.MethodType(forward, m))
            n += 1
    return n


def run_qwen(patterns):
    sys.path.insert(0, str(ANALYSE))
    import torch
    from qwen_int8 import INT8_DIR, load_int8
    from qwen_omni_utils import process_mm_info
    from transformers import Qwen3OmniMoeProcessor

    res = load()
    todo = [f for f in files(patterns) if not res.get(f.stem, {}).get("frage")]
    if not todo:
        print("nichts zu tun", flush=True)
        return
    t0 = time.time()
    model = load_int8()
    if os.environ.get("LANGSAM") != "1":
        print(f"schneller Decode-Pfad in {schneller_decode(model)} Expertenblöcken", flush=True)
    processor = Qwen3OmniMoeProcessor.from_pretrained(INT8_DIR)
    print(f"geladen in {time.time() - t0:.0f} s", flush=True)

    def ask(path, question, max_new):
        content = [{"type": "audio", "audio": str(path)}]
        if question:
            content.append({"type": "text", "text": question})
        conv = [{"role": "user", "content": content}]
        text = processor.apply_chat_template(conv, add_generation_prompt=True, tokenize=False)
        audios, _, _ = process_mm_info(conv, use_audio_in_video=False)
        inputs = processor(text=text, audio=audios, return_tensors="pt", padding=True, use_audio_in_video=False)
        inputs = inputs.to(model.device).to(model.dtype)
        torch.manual_seed(1234)
        with torch.inference_mode():
            out = model.generate(**inputs, thinker_return_dict_in_generate=True, return_audio=False,
                                 thinker_max_new_tokens=max_new)
        seq = out[0].sequences if isinstance(out, tuple) else out.sequences
        new = seq[:, inputs["input_ids"].shape[1]:]
        txt = processor.batch_decode(new, skip_special_tokens=True)[0].strip()
        return txt, int(new.shape[1]) >= max_new

    for f in todo:
        entry = res.get(f.stem, {})
        t1 = time.time()
        if not entry.get("frei"):
            entry["frei"], entry["frei_abgeschnitten"] = ask(f, None, MAX_FREI)
        entry["frage"], entry["frage_abgeschnitten"] = ask(f, FRAGE, MAX_FRAGE)
        entry["qwen_s"] = round(time.time() - t1, 1)
        res[f.stem] = entry
        save(res)
        print(f"=== {f.stem} ({entry['qwen_s']:.0f} s)\n{entry['frei']}\n--- Frage:\n{entry['frage']}\n", flush=True)


def run_ast(patterns):
    import librosa
    import numpy as np
    import torch
    from transformers import ASTFeatureExtractor, ASTForAudioClassification

    fe = ASTFeatureExtractor.from_pretrained(AST_MODEL)
    model = ASTForAudioClassification.from_pretrained(AST_MODEL).eval()
    labels = model.config.id2label
    idx = {v: int(k) for k, v in labels.items()}
    res = load(OUT_AST)
    for f in files(patterns):
        y, _ = librosa.load(f, sr=16000, mono=True)
        inp = fe(y, sampling_rate=16000, return_tensors="pt")
        with torch.no_grad():
            p = torch.sigmoid(model(**inp).logits)[0].numpy()
        top = np.argsort(p)[::-1][:8]
        entry = res.get(f.stem, {})
        entry["ast_top"] = [(labels[int(i)], round(float(p[i]), 3)) for i in top]
        entry["ast_warn"] = {k: round(float(p[idx[k]]), 3) for k in AST_WARN if k in idx}
        res[f.stem] = entry
        print(f.stem, entry["ast_top"][:5], flush=True)
    save(res, OUT_AST)


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ("qwen", "ast"):
        sys.exit(__doc__)
    {"qwen": run_qwen, "ast": run_ast}[sys.argv[1]](sys.argv[2:])
