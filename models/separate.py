#!/usr/bin/env python3
"""High-quality stem separation via the real Demucs (htdemucs).

Used by the desktop app as a subprocess for full htdemucs quality (the native
app decodes audio and hands us a WAV, so we never touch ffmpeg/torchcodec —
audio I/O is libsndfile via soundfile).

Usage:
  separate.py <input.wav> <output_dir> [--model htdemucs] [--shifts N]

Writes <output_dir>/{drums,bass,melody,vocals}.wav at the model's sample rate.
Demucs sources are drums/bass/other/vocals; "other" → Stemacle's "melody".
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

DEMUCS_TO_STEMACLE = {"drums": "drums", "bass": "bass", "other": "melody", "vocals": "vocals"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--model", default="htdemucs")
    ap.add_argument("--shifts", type=int, default=1, help="test-time shift averaging (quality vs speed)")
    ap.add_argument("--overlap", type=float, default=0.25)
    args = ap.parse_args()

    import soundfile as sf
    import torch
    from demucs.apply import apply_model
    from demucs.audio import convert_audio
    from demucs.pretrained import get_model

    in_path, out_dir = Path(args.input), Path(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)

    # Load WAV via libsndfile (no ffmpeg). Shape -> (channels, samples) float32.
    data, sr = sf.read(str(in_path), dtype="float32", always_2d=True)
    wav = torch.from_numpy(data.T).contiguous()  # (C, T)

    model = get_model(args.model).cpu().eval()
    model_sr = int(getattr(model, "samplerate", 44100))
    # Robust resample + channel conversion (same path the demucs CLI uses).
    wav = convert_audio(wav, sr, model_sr, model.audio_channels)
    ref = wav.mean(0)
    wav = (wav - ref.mean()) / (ref.std() + 1e-8)

    print(f"Separating {in_path.name} ({wav.shape[1]/model_sr:.1f}s) with {args.model}…", file=sys.stderr)
    with torch.no_grad():
        sources = apply_model(
            model, wav[None], shifts=args.shifts, overlap=args.overlap,
            progress=True, device="cpu",
        )[0]
    sources = sources * (ref.std() + 1e-8) + ref.mean()

    names = list(model.sources)  # e.g. ['drums','bass','other','vocals']
    for i, name in enumerate(names):
        stem = DEMUCS_TO_STEMACLE.get(name, name)
        out = out_dir / f"{stem}.wav"
        sf.write(str(out), sources[i].T.numpy(), model_sr, subtype="PCM_16")
        print(f"  wrote {out}", file=sys.stderr)
    print("OK", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
