# Stemacle Separation Queue Server

Full-quality htdemucs separation for clients that can't run inference locally
(iOS, and any thin client). Upload audio → a background job runs the real
Demucs → download the four stem WAVs.

## Run

```bash
# deps live in the models venv (Python 3.11)
models/.venv-models/bin/pip install fastapi "uvicorn[standard]" python-multipart
models/.venv-models/bin/uvicorn server.app:app --host 0.0.0.0 --port 8008
```

The model (`htdemucs`) loads once at startup.

## API

| Method | Path | Purpose |
|--------|------|---------|
| `GET`  | `/healthz` | `{ok, model}` |
| `POST` | `/separate` | multipart `file` → `{job_id, status}` |
| `GET`  | `/jobs/{id}` | `{status, stems, error}` (`processing`/`done`/`error`) |
| `GET`  | `/jobs/{id}/{stem}` | `audio/wav` for `drums|vocals|bass|melody` |

## Client

The Apple apps use `StemServerClient` (set the URL in Settings →
`stemacle.serverURL`). When unset, they split on-device with the DSP core.

Measured: a 15 s clip → 4 htdemucs stems in ~12 s; a 3:46 track in ~82 s
(~2.7× realtime on CPU). A GPU host or a job queue scales this for many clients.

## Notes / production

- In-memory job store + local temp files — fine for a single host. For scale,
  swap to a real queue (Redis/RQ or Celery) + object storage, and add auth.
- Stems are 16-bit WAV at the model rate (44.1 kHz).
