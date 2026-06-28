"""Stemacle separation queue server.

Gives mobile (and any thin client) full htdemucs quality without on-device
inference: upload audio → a background job runs the real Demucs → download the
four stem WAVs. This is the "queue system" for surfaces that can't subprocess.

Run:
  models/.venv-models/bin/uvicorn server.app:app --host 0.0.0.0 --port 8008

Endpoints:
  POST /separate            multipart 'file' → {job_id, status}
  GET  /jobs/{id}           → {status, stems:[...], error?}
  GET  /jobs/{id}/{stem}    → audio/wav   (stem ∈ drums|vocals|bass|melody)
  GET  /healthz             → {ok, model}
"""
from __future__ import annotations

import sys
import tempfile
import time
import uuid
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "models"))
from stemacle_sep import STEM_ORDER, load_model, separate_to_dir  # noqa: E402

from fastapi import BackgroundTasks, FastAPI, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse, JSONResponse

MODEL_NAME = "htdemucs"
ALLOWED_MODELS = {"htdemucs", "htdemucs_ft", "mdx_extra"}
app = FastAPI(title="Stemacle Separation Queue")

# In-memory job store: id -> {status, dir, stems, error}.
JOBS: dict[str, dict] = {}
WORK = Path(tempfile.gettempdir()) / "stemacle-server"
WORK.mkdir(parents=True, exist_ok=True)


@app.on_event("startup")
def _warm() -> None:
    # Load htdemucs once so the first job isn't penalized.
    load_model(MODEL_NAME)


@app.get("/healthz")
def healthz() -> dict:
    return {"ok": True, "model": MODEL_NAME}


def _audio_seconds(path: Path) -> float:
    try:
        with wave.open(str(path), "rb") as w:
            return w.getnframes() / float(w.getframerate() or 44100)
    except Exception:
        return 0.0


# htdemucs runs ~2.7x realtime on CPU; used to estimate progress.
REALTIME_FACTOR = 2.7


def _run_job(job_id: str, in_path: Path, model: str) -> None:
    job = JOBS[job_id]
    job["t0"] = time.monotonic()
    job["est"] = max(2.0, _audio_seconds(in_path) / REALTIME_FACTOR)
    try:
        out_dir = WORK / job_id
        separate_to_dir(in_path, out_dir, model)
        job["dir"] = str(out_dir)
        job["stems"] = STEM_ORDER
        job["status"] = "done"
    except Exception as e:  # surface the failure to the client
        job["status"] = "error"
        job["error"] = str(e)
    finally:
        in_path.unlink(missing_ok=True)


def _progress(job: dict) -> int:
    if job["status"] == "done":
        return 100
    if job["status"] == "error" or "t0" not in job:
        return 0
    elapsed = time.monotonic() - job["t0"]
    return int(min(99, elapsed / job.get("est", 1.0) * 100))


@app.post("/separate")
async def separate(file: UploadFile, background: BackgroundTasks,
                   model: str = Form(MODEL_NAME)) -> JSONResponse:
    chosen = model if model in ALLOWED_MODELS else MODEL_NAME
    job_id = uuid.uuid4().hex
    in_path = WORK / f"{job_id}-in{Path(file.filename or '').suffix or '.wav'}"
    in_path.write_bytes(await file.read())
    JOBS[job_id] = {"status": "processing", "stems": [], "dir": None, "error": None}
    background.add_task(_run_job, job_id, in_path, chosen)
    return JSONResponse({"job_id": job_id, "status": "processing", "model": chosen})


@app.get("/jobs/{job_id}")
def job_status(job_id: str) -> dict:
    job = JOBS.get(job_id)
    if not job:
        raise HTTPException(404, "unknown job")
    return {
        "status": job["status"],
        "stems": job["stems"],
        "error": job["error"],
        "progress": _progress(job),
    }


@app.get("/jobs/{job_id}/{stem}")
def job_stem(job_id: str, stem: str) -> FileResponse:
    job = JOBS.get(job_id)
    if not job or job["status"] != "done":
        raise HTTPException(404, "job not ready")
    if stem not in STEM_ORDER:
        raise HTTPException(400, "unknown stem")
    path = Path(job["dir"]) / f"{stem}.wav"
    if not path.exists():
        raise HTTPException(404, "stem missing")
    return FileResponse(str(path), media_type="audio/wav", filename=f"{stem}.wav")
