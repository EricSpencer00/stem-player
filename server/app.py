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
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "models"))
from stemacle_sep import STEM_ORDER, load_model, separate_to_dir  # noqa: E402

from fastapi import BackgroundTasks, FastAPI, HTTPException, UploadFile
from fastapi.responses import FileResponse, JSONResponse

MODEL_NAME = "htdemucs"
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


def _run_job(job_id: str, in_path: Path) -> None:
    job = JOBS[job_id]
    try:
        out_dir = WORK / job_id
        separate_to_dir(in_path, out_dir, MODEL_NAME)
        job["dir"] = str(out_dir)
        job["stems"] = STEM_ORDER
        job["status"] = "done"
    except Exception as e:  # surface the failure to the client
        job["status"] = "error"
        job["error"] = str(e)
    finally:
        in_path.unlink(missing_ok=True)


@app.post("/separate")
async def separate(file: UploadFile, background: BackgroundTasks) -> JSONResponse:
    job_id = uuid.uuid4().hex
    in_path = WORK / f"{job_id}-in{Path(file.filename or '').suffix or '.wav'}"
    in_path.write_bytes(await file.read())
    JOBS[job_id] = {"status": "processing", "stems": [], "dir": None, "error": None}
    background.add_task(_run_job, job_id, in_path)
    return JSONResponse({"job_id": job_id, "status": "processing"})


@app.get("/jobs/{job_id}")
def job_status(job_id: str) -> dict:
    job = JOBS.get(job_id)
    if not job:
        raise HTTPException(404, "unknown job")
    return {"status": job["status"], "stems": job["stems"], "error": job["error"]}


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
