"""Lässt die „Mau!“-Entwürfe vom lokalen Audio-Beschreibungsmodell der Werkstatt beschreiben (Höreindruck-Ersatz).

Modell: Qwen3-Omni-30B-A3B-Captioner (Apache 2.0) in der int8-Fassung der Werkstatt
(E:\\Draw2Race-AudioLab\\cache\\qwen-int8, gebaut von analyse\\qwen_int8.py). Die Werkstatt wird nur gelesen; ihr
caption_qwen.py schreibt nach out\\ und liest clips\\, deshalb dieses eigene Skript.

Speicher: Die MoE-Experten (27 GB int8) bleiben im Arbeitsspeicher (wenn möglich page-locked). Je Rechenschritt
wandern nur die gerade benutzten Experten auf die GPU. Der Rest des Modells (5 GB bf16) liegt auf den GPUs; so reicht
es, wenn je GPU nur etwa 4–6 GB frei sind (z. B. weil nebenher ein anderer Dienst läuft).

Je Datei drei Durchgänge:
  beschreibung     nur der Ton, so wie der Captioner trainiert ist (freie Beschreibung)
  antwort          Ton plus kurze Frage (echte Katze oder Spielton? welche Silbe? süß?); der Captioner ist nicht
                   für Fragen trainiert, beantwortet sie aber meist. Die Frage nennt „cat meowing“ und kann lenken.
  antwort_neutral  Ton plus neutrale Frage nach der Quelle, ohne Tier- oder Silbenvorgabe (ab Runde 2)
Kalibrierung: ein absichtlich katzenartiger Kontrollton (Bogenkontur 550→850→480 Hz, 0,75 s, kleine Formanten,
leichtes Zittern) wird mit beschrieben. Er entsteht nur im Temp-Ordner und gehört nicht zu den Spieltönen.

Aufruf (PowerShell)
  . E:\\Draw2Race-AudioLab\\env.ps1
  E:\\Draw2Race-AudioLab\\analyse\\.venv\\Scripts\\python.exe tools\\describe_mau_sounds.py [runde] [variante ...]
  runde: Name der Prüfrunde (Standard „runde1“); ohne Varianten werden alle aus varianten.json plus Kontrolle beschrieben.
  Statt eines Variantennamens geht auch ein Pfad zu einer .wav-Datei (Versuche); Schlüssel ist dann der Dateiname.
Ergebnis: audio/entwurf/mau/beschreibungen.json (schon beschriebene Dateien einer Runde werden übersprungen).
Dauer: Laden 3–6 min, danach etwa 1–3 min je Datei.
"""
import json
import os
import sys
import tempfile
import time
import types
from pathlib import Path

import numpy as np
import soundfile as sf
import torch

LAB = Path(r"E:\Draw2Race-AudioLab")
sys.path.insert(0, str(LAB / "analyse"))
from qwen_int8 import EXPERTS, INT8_DIR  # noqa: E402  (nur lesen)

ROOT = Path(__file__).resolve().parent.parent
DIR = ROOT / "audio" / "entwurf" / "mau"
OUT = DIR / "beschreibungen.json"
TMP = Path(tempfile.gettempdir()) / "mau_mau_flip_beschreibung"
FS = 48000

QUESTION = ("Listen to this short sound and answer briefly: 1) Is it a real cat meowing, a human voice, a musical "
            "instrument, or a synthesized game sound effect? 2) Which syllable or word does it resemble, if any? "
            "3) Does it sound cute? 4) Could it be mistaken for a real animal call?")
# Neutrale Frage ohne Tier- oder Silbenvorgabe (die erste Frage nennt „cat meowing“ und kann darauf lenken)
NEUTRAL = "What most likely produced this sound? Answer in one short sentence."


# ---------------------------------------------------------------------------------------------------------------
# Modell: Experten im Arbeitsspeicher, Rest auf den GPUs
# ---------------------------------------------------------------------------------------------------------------

def _experts_forward(self, hidden_states, top_k_index, top_k_weights):
    final = torch.zeros_like(hidden_states)
    dev = hidden_states.device
    with torch.no_grad():
        mask = torch.nn.functional.one_hot(top_k_index, num_classes=self.num_experts).permute(2, 1, 0)
        hit = torch.greater(mask.sum(dim=(-1, -2)), 0).nonzero().flatten().tolist()
    for e in hit:
        pos, tok = torch.where(mask[e])
        state = hidden_states[tok]
        gate_up = self.gate_up_cpu[e].to(dev, non_blocking=True).to(state.dtype) * self.gate_up_s[e]
        gate, up = torch.nn.functional.linear(state, gate_up).chunk(2, dim=-1)
        down = self.down_cpu[e].to(dev, non_blocking=True).to(state.dtype) * self.down_s[e]
        out = torch.nn.functional.linear(self.act_fn(gate) * up, down) * top_k_weights[tok, pos, None]
        final.index_add_(0, tok, out.to(final.dtype))
    return final


def load_model(max_memory):
    from accelerate import dispatch_model, infer_auto_device_map, init_empty_weights
    from accelerate.utils import set_module_tensor_to_device
    from safetensors import safe_open
    from transformers import AutoConfig, Qwen3OmniMoeForConditionalGeneration

    config = AutoConfig.from_pretrained(INT8_DIR)
    with init_empty_weights():
        model = Qwen3OmniMoeForConditionalGeneration._from_config(config, dtype=torch.bfloat16,
                                                                  attn_implementation="sdpa")
    experts = {}
    for name, m in model.named_modules():
        if type(m).__name__ == EXPERTS:
            E, I2, H = m.gate_up_proj.shape
            del m.gate_up_proj, m.down_proj
            meta = torch.device("meta")
            m.register_buffer("gate_up_s", torch.empty(E, I2, 1, dtype=torch.bfloat16, device=meta))
            m.register_buffer("down_s", torch.empty(E, H, 1, dtype=torch.bfloat16, device=meta))
            m.forward = types.MethodType(_experts_forward, m)
            experts[name] = m
    model.eval()
    device_map = infer_auto_device_map(model, max_memory=max_memory,
                                       no_split_module_classes=model._no_split_modules)
    placed = {}
    for v in device_map.values():
        placed[str(v)] = placed.get(str(v), 0) + 1
    print("Verteilung (Module je Gerät):", placed, flush=True)

    def device_for(key):
        parts = key.split(".")
        for n in range(len(parts), -1, -1):
            prefix = ".".join(parts[:n])
            if prefix in device_map:
                return device_map[prefix]
        return device_map.get("", 0)

    expected = set(model.state_dict().keys())
    pinned, pageable = 0, 0
    for f in sorted(INT8_DIR.glob("*.safetensors")):
        with safe_open(f, "pt") as s:
            for key in s.keys():
                if key.endswith(".gate_up_q") or key.endswith(".down_q"):
                    mod = experts[key.rsplit(".", 1)[0]]
                    t = s.get_tensor(key)
                    try:
                        t = t.pin_memory()
                        pinned += 1
                    except RuntimeError:
                        pageable += 1
                    setattr(mod, "gate_up_cpu" if key.endswith(".gate_up_q") else "down_cpu", t)
                    continue
                if key not in expected:
                    continue
                dev = device_for(key)
                set_module_tensor_to_device(model, key, "cpu" if dev in ("cpu", "disk") else dev,
                                            value=s.get_tensor(key))
    missing = [m for m in experts.values() if not hasattr(m, "gate_up_cpu") or not hasattr(m, "down_cpu")]
    if missing:
        raise RuntimeError(f"{len(missing)} Expertenblöcke ohne Gewichte")
    print(f"Experten im Arbeitsspeicher: {pinned} page-locked, {pageable} normal", flush=True)
    model.tie_weights()
    return dispatch_model(model, device_map=device_map)


# ---------------------------------------------------------------------------------------------------------------
# Eingaben
# ---------------------------------------------------------------------------------------------------------------

def padded(src, name):
    """Ton mit 0,3 s Stille davor und 0,7 s danach (das Modell bekommt etwas Kontext, der Ton bleibt einzeln)."""
    x, sr = sf.read(src)
    assert sr == FS
    y = np.concatenate([np.zeros(int(0.3 * FS)), x, np.zeros(int(0.7 * FS))])
    TMP.mkdir(parents=True, exist_ok=True)
    out = TMP / f"{name}.wav"
    sf.write(out, y, FS, subtype="PCM_16")
    return out


def control_cat_like():
    """Kalibrierung: absichtlich katzenartiger Laut (nur für das Modell, nie im Spiel). Bogenkontur, 0,75 s,
    Formanten einer kleinen Stimme (F1 um 1,1–1,5 kHz, F2 um 2,5–3 kHz), leichtes Zittern und etwas Hauch."""
    rng = np.random.default_rng(7)
    n = int(0.75 * FS)
    t = np.arange(n) / FS
    u = t / t[-1]
    f0 = 550 + 300 * np.sin(np.pi * np.minimum(u / 0.8, 1.0)) ** 1.5 - 70 * np.maximum(u - 0.8, 0) / 0.2
    jitter = np.convolve(rng.standard_normal(n), np.ones(480) / 480, "same") * 60
    f0 = f0 * (1 + 0.012 * np.sin(2 * np.pi * 6 * t)) + jitter
    F1 = 900 + 600 * np.sin(np.pi * u) ** 2
    F2 = 2200 + 900 * np.sin(np.pi * np.minimum(u * 1.3, 1.0))
    phase = 2 * np.pi * np.cumsum(f0) / FS
    x = np.zeros(n)
    for k in range(1, 25):
        fk = k * f0
        a = k ** -1.0 / np.sqrt((1 - (fk / F1) ** 2) ** 2 + (fk * 200 / F1 ** 2) ** 2)
        a = a / np.sqrt((1 - (fk / F2) ** 2) ** 2 + (fk * 250 / F2 ** 2) ** 2)
        a = a * (fk < 9000)
        x += a * np.sin(k * phase)
    x += 0.02 * np.abs(x).max() * rng.standard_normal(n)
    env = np.minimum(1, t / 0.06) * np.minimum(1, (t[-1] - t) / 0.15)
    x = x * env
    x = 0.3 * x / np.abs(x).max()
    TMP.mkdir(parents=True, exist_ok=True)
    out = TMP / "kontrolle_katzenartig.wav"
    y = np.concatenate([np.zeros(int(0.3 * FS)), x, np.zeros(int(0.7 * FS))])
    sf.write(out, y, FS, subtype="PCM_16")
    return out


# ---------------------------------------------------------------------------------------------------------------
# Beschreiben
# ---------------------------------------------------------------------------------------------------------------

def run(model, processor, wav, question=None, max_new_tokens=400):
    from qwen_omni_utils import process_mm_info
    content = [{"type": "audio", "audio": str(wav)}]
    if question:
        content.append({"type": "text", "text": question})
    conv = [{"role": "user", "content": content}]
    text = processor.apply_chat_template(conv, add_generation_prompt=True, tokenize=False)
    audios, _, _ = process_mm_info(conv, use_audio_in_video=False)
    inputs = processor(text=text, audio=audios, return_tensors="pt", padding=True, use_audio_in_video=False)
    inputs = inputs.to(model.device).to(model.dtype)
    with torch.inference_mode():
        out = model.generate(**inputs, thinker_return_dict_in_generate=True, return_audio=False,
                             thinker_max_new_tokens=max_new_tokens, thinker_do_sample=False)
    seq = out[0].sequences if isinstance(out, tuple) else out.sequences
    return processor.batch_decode(seq[:, inputs["input_ids"].shape[1]:], skip_special_tokens=True)[0].strip()


def main(args):
    round_name = args[0] if args else "runde1"
    manifest = json.loads((DIR / "varianten.json").read_text(encoding="utf-8"))
    names = args[1:] or list(manifest["varianten"]) + ["kontrolle_katzenartig"]
    paths = {Path(a).stem: Path(a) for a in names if a.lower().endswith(".wav")}   # Versuchsdateien per Pfad
    names = [Path(a).stem if a.lower().endswith(".wav") else a for a in names]
    data = json.loads(OUT.read_text(encoding="utf-8")) if OUT.exists() else {}
    data.setdefault("modell", "Qwen3-Omni-30B-A3B-Captioner, int8 (Werkstatt E:\\Draw2Race-AudioLab), gierige Dekodierung")
    data.setdefault("frage", QUESTION)
    data.setdefault("frage_neutral", NEUTRAL)
    results = data.setdefault("runden", {}).setdefault(round_name, {})
    todo = [n for n in names if n not in results]
    if not todo:
        print("nichts zu tun")
        return

    for i in range(torch.cuda.device_count()):
        free, total = torch.cuda.mem_get_info(i)
        print(f"GPU {i}: {free / 2**30:.1f} von {total / 2**30:.1f} GiB frei", flush=True)
    free = [torch.cuda.mem_get_info(i)[0] / 2**30 for i in range(torch.cuda.device_count())]
    max_memory = {i: f"{max(0.0, f - 2.0):.1f}GiB" for i, f in enumerate(free)}
    max_memory["cpu"] = "12GiB"
    t0 = time.time()
    from transformers import Qwen3OmniMoeProcessor
    model = load_model(max_memory)
    processor = Qwen3OmniMoeProcessor.from_pretrained(INT8_DIR)
    print(f"Modell geladen in {time.time() - t0:.0f} s", flush=True)

    for name in todo:
        if name == "kontrolle_katzenartig":
            wav = control_cat_like()
        else:
            wav = padded(paths.get(name, DIR / f"{name}.wav"), name)
        t1 = time.time()
        desc = run(model, processor, wav)
        answer = run(model, processor, wav, QUESTION, max_new_tokens=250)
        neutral = run(model, processor, wav, NEUTRAL, max_new_tokens=80)
        results[name] = {"beschreibung": desc, "antwort": answer, "antwort_neutral": neutral,
                         "sekunden": round(time.time() - t1)}
        OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"=== {name} ({time.time() - t1:.0f} s)\n{desc}\n--- Frage:\n{answer}\n--- Neutral:\n{neutral}\n",
              flush=True)


if __name__ == "__main__":
    main(sys.argv[1:])
