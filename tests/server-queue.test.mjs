import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

// Contract guards for the iOS/mobile separation queue server (`server/app.py`)
// and its shared Demucs core (`models/stemacle_sep.py`). These lock the HTTP
// contract that `StemServerClient` (Swift) depends on, without a pytest suite or
// a live htdemucs run — matching the Node-only test toolchain. They are
// source-contract guards: each assertion targets a specific endpoint, status
// string, allowlist member, or stem mapping that the Swift client relies on.

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const r = (...p) => join(root, ...p);
const read = (...p) => readFileSync(r(...p), 'utf8');

const app = read('server', 'app.py');
const sep = read('models', 'stemacle_sep.py');

// SERVER-001 — health endpoint
test('server exposes a health endpoint reporting the model', () => {
  assert.match(app, /@app\.get\(["']\/healthz["']\)/, 'GET /healthz route');
  assert.match(app, /return\s*\{\s*["']ok["']\s*:\s*True\s*,\s*["']model["']/, 'reports {ok, model}');
  assert.match(app, /MODEL_NAME\s*=\s*["']htdemucs["']/, 'default model is htdemucs');
});

// SERVER-002 — submit separation job
test('server accepts a multipart upload and returns a job id + status', () => {
  assert.match(app, /@app\.post\(["']\/separate["']\)/, 'POST /separate route');
  assert.match(app, /file:\s*UploadFile/, 'accepts an uploaded file');
  assert.match(app, /background\.add_task\(\s*_run_job/, 'runs separation off the request thread');
  // Response shape consumed by StemServerClient.submit → decodes `job_id`.
  assert.match(app, /JSONResponse\(\{\s*["']job_id["']/, 'returns {job_id, ...}');
  assert.match(app, /["']status["']\s*:\s*["']processing["']/, 'initial status is processing');
});

// SERVER-003 — allowed server models (must include every model the client offers)
test('server enforces a model allowlist and falls back to the default', () => {
  assert.match(app, /ALLOWED_MODELS\s*=\s*\{[^}]*htdemucs[^}]*\}/, 'allowlist defined');
  for (const model of ['htdemucs', 'htdemucs_ft', 'mdx_extra']) {
    assert.ok(new RegExp(`["']${model}["']`).test(app), `allowlist contains ${model}`);
  }
  // Unknown models resolve to the default instead of erroring.
  assert.match(app, /model\s+if\s+model\s+in\s+ALLOWED_MODELS\s+else\s+MODEL_NAME/,
    'unknown model falls back to MODEL_NAME');
});

// SERVER-004 — polling job status
test('server reports job status, stems, error and progress', () => {
  assert.match(app, /@app\.get\(["']\/jobs\/\{job_id\}["']\)/, 'GET /jobs/{id} route');
  // The exact keys StemServerClient.JobStatus decodes.
  for (const key of ['status', 'stems', 'error', 'progress']) {
    assert.ok(new RegExp(`["']${key}["']`).test(app), `status response includes ${key}`);
  }
  assert.match(app, /raise HTTPException\(404,\s*["']unknown job["']\)/, 'unknown job → 404');
});

test('progress estimator is bounded and uses a realtime factor', () => {
  assert.match(app, /REALTIME_FACTOR\s*=\s*2\.7/, 'documented realtime factor');
  // done → 100, no-start/error → 0, otherwise capped at 99 while running.
  assert.match(app, /if job\["status"\]\s*==\s*["']done["']:\s*\n\s*return 100/, 'done is 100%');
  assert.match(app, /min\(99,/, 'running progress capped below 100');
});

// SERVER-005 — download stem WAV (route + canonical stem ordering)
test('server streams each stem as audio/wav with guarded preconditions', () => {
  assert.match(app, /@app\.get\(["']\/jobs\/\{job_id\}\/\{stem\}["']\)/, 'GET /jobs/{id}/{stem} route');
  assert.match(app, /media_type=["']audio\/wav["']/, 'serves audio/wav');
  assert.match(app, /job\["status"\]\s*!=\s*["']done["']/, 'rejects download before job is done');
  assert.match(app, /stem not in STEM_ORDER/, 'rejects unknown stem name');
  assert.match(app, /raise HTTPException\(400/, 'unknown stem → 400');
});

test('shared core defines canonical stem order and maps Demucs other→melody', () => {
  // The order the Swift client downloads stems in must match the server's.
  assert.match(sep, /STEM_ORDER\s*=\s*\[\s*["']drums["']\s*,\s*["']vocals["']\s*,\s*["']bass["']\s*,\s*["']melody["']\s*\]/,
    'canonical stem order drums, vocals, bass, melody');
  assert.match(sep, /["']other["']\s*:\s*["']melody["']/, 'Demucs "other" maps to melody');
  // The model is loaded once and cached (server warms it at startup).
  assert.match(sep, /def load_model\(/, 'load_model helper exists');
  assert.match(sep, /_MODELS\[name\]\s*=/, 'caches the loaded model');
});
