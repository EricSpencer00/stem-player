# Stemacle Separation Models

The native apps ship with **platform-best** neural separation, now that we're not
constrained by the web's download budget:

| Platform | Runtime | Artifact |
|----------|---------|----------|
| macOS / iOS | CoreML (Neural Engine) | `build/HTDemucs.mlpackage` |
| Windows / Linux | ONNX Runtime | `build/htdemucs.onnx` |

Both are produced from **Demucs `htdemucs`** (4-stem, waveform-domain). Demucs
outputs `drums, bass, other, vocals` directly; `other` → Stemacle's **melody**.

## Building the models

`convert_demucs.py` requires a **torch-supported Python (3.11 or 3.12)** — note
the repo's system Python is 3.14, which has **no torch wheels**, so use a venv:

```bash
python3.12 -m venv .venv-models
source .venv-models/bin/activate
pip install demucs torch coremltools onnx
python models/convert_demucs.py            # both ONNX + CoreML
python models/convert_demucs.py --onnx     # ONNX only
```

The script is dependency-checked and side-effect-free until run, so it is safe
to keep in the repo on environments without torch.

## Integration status

- The shared Rust core (`native/core/stemacle-dsp`) exposes a `Separator` trait.
  The default `CoherenceSeparator` is the **deterministic DSP fallback** ported
  from the web gold master, and is fully tested.
- The neural separators are injected per platform:
  - Apple: a CoreML-backed `Separator` in `StemacleKit` (loads `.mlpackage`).
  - Win/Linux: an ONNX Runtime (`ort`)-backed `Separator` in the desktop crate.
- Until a converted model is present, every app runs the DSP path and stays
  fully functional — the model is a **quality upgrade**, never a hard dependency.

> Demucs replaces the whole spectrogram-mask path when present (it produces the
> four stems directly), while the core still owns STFT spectrograms, tempo
> detection, and the loop contract. The model output is gated by **quality**
> tests (stem mapping, energy/SDR, no-clip) rather than byte-parity with the web
> pipeline, because Demucs is intentionally better than the tiny web model.
