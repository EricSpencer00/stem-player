# Separation server contracts

Stemacle separates audio **on-device** by default (the Rust DSP core on every
surface; a local htdemucs subprocess on macOS — see
[`project-native-rewrite`]). Audio is never uploaded by the shipping apps.

Three *server* contracts also exist in the repo. They are **not interchangeable**,
and conflating them is the classic trap for a new contributor. This file is the
source of truth; the guard `tests/separation-contracts.test.mjs` enforces it.

## 1. Local FastAPI queue — `server/app.py`  (LIVE, real htdemucs)

The working high-quality path for dev/desktop. Binary WAV over HTTP.

| Step | Request | Response |
|---|---|---|
| Submit | `POST /separate` — multipart form, fields `file` (audio) + `model` | `{ job_id, status, model }` |
| Poll | `GET /jobs/{job_id}` | `{ status, stems, error, progress }` |
| Download | `GET /jobs/{job_id}/{stem}` | `audio/wav` bytes |

- Stems: `drums, vocals, bass, melody` (canonical order), `other → melody`.
- Models allow-list: `htdemucs, htdemucs_ft, mdx_extra`; unknown → default.
- Guarded by `tests/server-queue.test.mjs`.

## 2. Swift `StemServerClient`  (client for contract #1, currently unwired)

Lives in `StemacleKit`. Speaks **exactly** contract #1 (multipart upload,
`{job_id}`, `/jobs/{id}` JSON status, per-stem `/jobs/{id}/{stem}` WAV download).
Retained + unit-tested for a possible future opt-in, but **not wired into the
app** (on-device-only privacy posture). Guarded by `StemacleKitTests`.

> If you wire the app to a server, it must speak contract #1. Pointing the Swift
> client at the Cloudflare Worker (contract #3) will **not** work — different shape.

## 3. Cloudflare edge Worker — `cloudflare/stemacle-api-worker.js`  (SKELETON)

A front door for a *future* hosted Demucs-replacement quality test. **No GPU
consumer is attached**, so it cannot actually separate yet — it only enqueues.

| Step | Request | Response |
|---|---|---|
| Health | `GET /` or `/healthz` | `{ ok, service, timestamp }` |
| Capabilities | `GET /capabilities` | discloses `demucsOnCloudflareEdge:false`, `currentBackend:"cloudflare_queue_no_gpu_consumer"` |
| Quote | `GET/POST /quote` | cost estimate (planning only) |
| Submit | `POST /separate` — **JSON** body + R2 source (not multipart) | `202 { job_id, status, poll }` |
| Poll | `GET /jobs/{uuid}` | **JSON job record** (no per-stem WAV route) |

Key divergences from contract #1 (deliberate): **JSON job metadata + R2**, not
multipart bytes; `/jobs/{id}` returns a JSON record, and there is **no
`/jobs/{id}/{stem}` WAV route**. Guarded by `tests/cloudflare-api.test.mjs`.

[`project-native-rewrite`]: ../README.md
