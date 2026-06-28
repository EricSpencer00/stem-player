#!/usr/bin/env python3
"""High-quality stem separation via the real Demucs (htdemucs).

Used by the desktop app as a subprocess for full htdemucs quality. The native
app decodes audio and hands us a WAV, so audio I/O is libsndfile (no ffmpeg).

Usage:
  separate.py <input.wav> <output_dir> [--model htdemucs] [--shifts N]

Writes <output_dir>/{drums,bass,melody,vocals}.wav. Demucs sources are
drums/bass/other/vocals; "other" → Stemacle's "melody".
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from stemacle_sep import separate_to_dir  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--model", default="htdemucs")
    ap.add_argument("--shifts", type=int, default=1, help="test-time shift averaging (quality vs speed)")
    ap.add_argument("--overlap", type=float, default=0.25)
    args = ap.parse_args()

    print(f"Separating {Path(args.input).name} with {args.model}…", file=sys.stderr)
    written = separate_to_dir(
        Path(args.input), Path(args.output), args.model, args.shifts, args.overlap
    )
    for p in written:
        print(f"  wrote {p}", file=sys.stderr)
    print("OK", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
