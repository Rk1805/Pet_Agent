"""Pet Agents voice helper: speaks text in a character's cloned voice (F5-TTS on Apple's MLX).

The voice is cloned from a few seconds of the character's real (English) speech, prepared by
install_voice.sh as voices/<name>/ref.wav. Started by the app only while a character is talking;
JSON lines over stdin/stdout; quits after a few idle minutes so its memory is given back.

Request:  {"id": 1, "character": "naruto", "text": "Rasengan!"}
Reply:    {"id": 1, "path": ".../cache/naruto/<sha1>.wav"}   or   {"id": 1, "error": "..."}

`python voice_server.py --root DIR --voices voices.json --prerender naruto` renders every fixed line;
`--say "text" --prerender naruto` renders one test line."""

import argparse
import hashlib
import json
import os
import select
import sys
import time

IDLE_SECONDS = 180


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def key(text):
    return hashlib.sha1(text.strip().encode("utf-8")).hexdigest()


class Voices:
    def __init__(self, root, voices_path):
        self.root = root
        self.spec = json.load(open(voices_path))
        self.model = None
        self.refs = {}

    def base(self, character):
        for name, v in self.spec.items():
            if name.startswith("_"):
                continue
            if character == name or character in v.get("applies_to", []):
                return name, v
        raise KeyError(f"no voice for {character}")

    def reference(self, name, v):
        if name not in self.refs:
            import mlx.core as mx
            import soundfile as sf
            from f5_tts_mlx.generate import TARGET_RMS
            audio, sr = sf.read(os.path.join(self.root, "voices", name, "ref.wav"))
            audio = mx.array(audio)
            rms = mx.sqrt(mx.mean(mx.square(audio)))
            if rms < TARGET_RMS:
                audio = audio * TARGET_RMS / rms
            self.refs[name] = (audio, v["reference"]["text"])
        return self.refs[name]

    def warm(self, character):
        """Load the model and the character's reference ahead of time (sent when a mission starts)."""
        name, v = self.base(character)
        self.render(character, "Ready.", keep=False)
        self.reference(name, v)

    def render(self, character, text, fast=True, keep=True):
        """fast: Euler 8 steps (~3 s a sentence on an M2) for live replies; otherwise midpoint (~2x slower)
        for the pre-rendered fixed lines. Both came out equally intelligible in testing."""
        name, v = self.base(character)
        text = " ".join(text.split())[:240]
        out_dir = os.path.join(self.root, "cache", name)
        os.makedirs(out_dir, exist_ok=True)
        out = os.path.join(out_dir, key(text) + ".wav")
        if keep and os.path.exists(out):
            return out
        import mlx.core as mx
        import numpy as np
        import soundfile as sf
        from f5_tts_mlx.cfm import F5TTS
        from f5_tts_mlx.generate import FRAMES_PER_SEC, HOP_LENGTH, SAMPLE_RATE, split_sentences
        from f5_tts_mlx.utils import convert_char_to_pinyin
        if self.model is None:
            # f5-tts-mlx 0.2.6 builds noise shapes from MLX scalars, which newer MLX rejects: cast to int.
            if not getattr(mx.random, "_pet_agents_patched", False):
                normal = mx.random.normal
                mx.random.normal = lambda shape=(), *a, **k: normal(tuple(int(d) for d in shape), *a, **k)
                mx.random._pet_agents_patched = True
            self.model = F5TTS.from_pretrained("lucasnewman/f5-tts-mlx")   # safetensors weights, cached by HF
            log("model loaded")
        ref, ref_text = self.reference(name, v)
        pieces = []
        for sentence in split_sentences(text) or [text]:
            # Length = the reference plus the new sentence at a natural pace (~12.5 characters a second).
            # The built-in duration predictor makes short catchphrase-style lines far too short.
            seconds = max(1.0, len(sentence) / 12.5 + 0.35) / v.get("speed", 1.0)
            frames = ref.shape[0] // HOP_LENGTH + int(seconds * FRAMES_PER_SEC)
            wave, _ = self.model.sample(mx.expand_dims(ref, axis=0),
                                        text=convert_char_to_pinyin([ref_text + " " + sentence]),
                                        duration=frames, steps=8, method="euler" if fast else "midpoint",
                                        speed=v.get("speed", 1.0),
                                        cfg_strength=2.0, sway_sampling_coef=-1.0, seed=None)
            wave = wave[ref.shape[0]:]                 # drop the reference part
            mx.eval(wave)
            pieces += [np.array(wave), np.zeros(int(SAMPLE_RATE * 0.12), dtype=np.float32)]
        if not keep:
            return out
        sf.write(out + ".tmp.wav", np.concatenate(pieces), SAMPLE_RATE)
        os.replace(out + ".tmp.wav", out)
        return out


def serve(voices):
    last = time.time()
    while True:
        ready, _, _ = select.select([sys.stdin], [], [], 5)
        if not ready:
            if time.time() - last > IDLE_SECONDS:
                log("idle; quitting")
                return
            continue
        line = sys.stdin.readline()
        if not line:
            return                                  # the app closed the pipe
        last = time.time()
        req = {}
        try:
            req = json.loads(line)
            if req.get("warm"):
                voices.warm(req["character"])
                continue
            reply = {"id": req.get("id"), "path": voices.render(req["character"], req["text"])}
        except Exception as e:                      # keep serving after a bad request
            reply = {"id": req.get("id") if isinstance(req, dict) else None, "error": str(e)}
        print(json.dumps(reply), flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--voices", required=True)
    ap.add_argument("--prerender")
    ap.add_argument("--say")
    a = ap.parse_args()
    os.environ.setdefault("HF_HOME", os.path.join(a.root, "hf"))   # keep the model with the rest of the voice files
    v = Voices(a.root, a.voices)
    if a.say:
        t0 = time.time()
        print(v.render(a.prerender or "naruto", a.say), f"{time.time() - t0:.1f}s")
        return
    if a.prerender:
        name, spec = v.base(a.prerender)
        for event, lines in spec.get("lines", {}).items():
            for t in lines:
                t0 = time.time()
                p = v.render(a.prerender, t, fast=False)
                print(f"{event:14s} {t!r:42s} {time.time() - t0:5.1f}s  {os.path.basename(p)}", flush=True)
        return
    serve(v)


if __name__ == "__main__":
    main()
