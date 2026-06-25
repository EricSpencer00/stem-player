"""Shared Demucs separation core, used by both the CLI (separate.py) and the
queue server (server/app.py). Keeps model loading in one place so the server
can load htdemucs once at startup instead of per request.
"""
from __future__ import annotations

from pathlib import Path

DEMUCS_TO_STEMACLE = {"drums": "drums", "bass": "bass", "other": "melody", "vocals": "vocals"}
STEM_ORDER = ["drums", "vocals", "bass", "melody"]

_MODELS: dict[str, object] = {}


def load_model(name: str = "htdemucs"):
    """Load (and cache) a Demucs model on CPU."""
    if name not in _MODELS:
        from demucs.pretrained import get_model

        _MODELS[name] = get_model(name).cpu().eval()
    return _MODELS[name]


def separate_to_dir(in_path: Path, out_dir: Path, model_name: str = "htdemucs",
                    shifts: int = 1, overlap: float = 0.25) -> list[Path]:
    """Separate `in_path` and write {drums,bass,melody,vocals}.wav to `out_dir`.

    Returns the written paths. Audio I/O is libsndfile (no ffmpeg); resampling
    and channel conversion use demucs' own `convert_audio`.
    """
    import soundfile as sf
    import torch
    from demucs.apply import apply_model
    from demucs.audio import convert_audio

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    model = load_model(model_name)
    model_sr = int(getattr(model, "samplerate", 44100))

    data, sr = sf.read(str(in_path), dtype="float32", always_2d=True)
    wav = torch.from_numpy(data.T).contiguous()
    wav = convert_audio(wav, sr, model_sr, model.audio_channels)
    ref = wav.mean(0)
    wav = (wav - ref.mean()) / (ref.std() + 1e-8)

    with torch.no_grad():
        sources = apply_model(
            model, wav[None], shifts=shifts, overlap=overlap, progress=False, device="cpu",
        )[0]
    sources = sources * (ref.std() + 1e-8) + ref.mean()

    written = []
    for i, name in enumerate(model.sources):
        stem = DEMUCS_TO_STEMACLE.get(name, name)
        path = out_dir / f"{stem}.wav"
        sf.write(str(path), sources[i].T.numpy(), model_sr, subtype="PCM_16")
        written.append(path)
    return written
