#!/usr/bin/env python3
"""Convert a Demucs (htdemucs) 4-stem model to the formats the native apps use.

Outputs, under ./build:
  - htdemucs.onnx          ONNX Runtime model for the Windows/Linux desktop app
  - HTDemucs.mlpackage     CoreML model for the Apple apps (Neural Engine)

Demucs is a waveform-domain model that outputs four sources directly
(drums, bass, other, vocals); "other" maps to Stemacle's "melody" stem. This
gives a real quality jump over the web's tiny spectrogram-mask ONNX models,
which we can now afford because native apps bundle the model instead of
streaming it.

Requires a Torch-supported Python (3.11/3.12 — NOT 3.14, which has no torch
wheels yet) with:  pip install demucs torch coremltools onnx

This script is intentionally dependency-checked and side-effect-free until run
so it can live in the repo without breaking environments that lack torch.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parent / "build"
# Demucs source order; index 2 ("other") is Stemacle's "melody".
DEMUCS_SOURCES = ["drums", "bass", "other", "vocals"]
STEMACLE_STEMS = ["drums", "bass", "melody", "vocals"]


def _require(mod: str) -> None:
    try:
        __import__(mod)
    except ImportError:
        sys.exit(
            f"missing dependency '{mod}'. Use a torch-supported Python and run:\n"
            f"  pip install demucs torch coremltools onnx"
        )


def export_onnx(model, example, path: Path) -> None:
    import torch

    path.parent.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(
        model,
        example,
        str(path),
        input_names=["mix"],
        output_names=["stems"],
        dynamic_axes={"mix": {0: "batch", 2: "time"}, "stems": {0: "batch", 3: "time"}},
        opset_version=17,
    )
    print(f"  wrote {path}")


def export_coreml(model, example, path: Path) -> None:
    import coremltools as ct
    import torch

    # htdemucs has data-dependent transformer paths, so the trace sanity check
    # (which re-runs and diffs graphs) fails spuriously; the traced graph is
    # still valid for a fixed-length input.
    traced = torch.jit.trace(model, example, check_trace=False, strict=False)
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="mix", shape=example.shape)],
        compute_units=ct.ComputeUnit.ALL,  # prefer the Neural Engine
        minimum_deployment_target=ct.target.iOS16,
    )
    mlmodel.short_description = "Stemacle 4-stem separator (Demucs htdemucs)"
    mlmodel.save(str(path))
    print(f"  wrote {path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seconds", type=float, default=10.0,
                        help="example clip length used to trace the model")
    parser.add_argument("--onnx", action="store_true")
    parser.add_argument("--coreml", action="store_true")
    args = parser.parse_args()
    if not (args.onnx or args.coreml):
        args.onnx = args.coreml = True

    for mod in ["torch", "demucs"]:
        _require(mod)
    import torch
    from demucs.pretrained import get_model

    print("Loading htdemucs…")
    bag = get_model("htdemucs").cpu().eval()
    # get_model returns a BagOfModels whose forward defers to apply_model; the
    # exportable module is the single inner HTDemucs.
    model = bag.models[0].cpu().eval() if hasattr(bag, "models") else bag
    sr = int(getattr(bag, "samplerate", 44100))  # 44100
    # HTDemucs has a fixed processing segment; the traced input must match it
    # exactly (it reshapes by training_length internally).
    seg = float(getattr(model, "segment", getattr(bag, "segment", 7.8)))
    example = torch.zeros(1, 2, int(round(seg * sr)))
    print(f"  segment {seg}s → example {tuple(example.shape)}")

    OUT.mkdir(parents=True, exist_ok=True)
    print(f"Stem mapping: {dict(zip(DEMUCS_SOURCES, STEMACLE_STEMS))}")
    if args.onnx:
        _require("onnx")
        print("Exporting ONNX…")
        export_onnx(model, example, OUT / "htdemucs.onnx")
    if args.coreml:
        _require("coremltools")
        print("Exporting CoreML…")
        export_coreml(model, example, OUT / "HTDemucs.mlpackage")
    print("Done.")


if __name__ == "__main__":
    main()
