import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from '../cloudflare/stemacle-api-worker.js';

// Contract tests for the Cloudflare edge Worker (cloudflare/stemacle-api-worker.js),
// the front door for a future hosted Demucs-replacement quality test. The Worker
// is a live deployed service (stemacle-api.stockgenie.workers.dev) with no other
// tests, so these pin its HTTP contract: routes, status codes, response shapes,
// CORS, input validation, and — critically — its HONESTY (it must not advertise a
// GPU/Demucs backend it does not actually have).

const req = (path, init) => new Request(`https://stemacle-api.test${path}`, init);
const jsonReq = (path, body, method = 'POST') =>
  req(path, { method, headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
const validSource = (overrides = {}) => ({
  kind: 'r2',
  bucket: 'stemacle-stems',
  key: 'inputs/song.wav',
  sizeBytes: 48 * 1024 * 1024,
  ...overrides,
});

/** A mock env whose R2 + Queue bindings record what the Worker writes/sends. */
function mockEnv() {
  const puts = [];
  const sends = [];
  const store = new Map();
  return {
    puts, sends, store,
    JOBS_BUCKET: {
      async put(key, value, opts) { puts.push({ key, value, opts }); store.set(key, value); },
      async get(key) {
        if (!store.has(key)) return null;
        const value = store.get(key);
        return { async json() { return JSON.parse(value); } };
      },
    },
    SEPARATION_QUEUE: { async send(msg) { sends.push(msg); } },
  };
}

// --- Routing + CORS ---------------------------------------------------------

test('GET / and /healthz both report healthy', async () => {
  for (const path of ['/', '/healthz']) {
    const res = await worker.fetch(req(path), {});
    assert.equal(res.status, 200, `${path} status`);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.equal(body.service, 'stemacle-api');
  }
});

test('every response carries permissive CORS headers', async () => {
  const res = await worker.fetch(req('/healthz'), {});
  assert.equal(res.headers.get('access-control-allow-origin'), '*');
  assert.match(res.headers.get('access-control-allow-methods'), /POST/);
});

test('OPTIONS preflight returns 204 with CORS and no body', async () => {
  const res = await worker.fetch(req('/separate', { method: 'OPTIONS' }), {});
  assert.equal(res.status, 204);
  assert.equal(res.headers.get('access-control-allow-origin'), '*');
});

test('unknown route returns a structured 404', async () => {
  const res = await worker.fetch(req('/does-not-exist'), {});
  assert.equal(res.status, 404);
  const body = await res.json();
  assert.equal(body.ok, false);
  assert.equal(body.error, 'not_found');
});

// --- Honesty: must not claim a backend it does not have ---------------------

test('/capabilities truthfully reports NO edge Demucs and NO GPU consumer', async () => {
  const res = await worker.fetch(req('/capabilities'), {});
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.demucsOnCloudflareEdge, false, 'must not claim edge Demucs');
  assert.equal(body.currentBackend, 'cloudflare_queue_no_gpu_consumer',
    'must disclose there is no GPU consumer yet');
  assert.ok(Array.isArray(body.nextBackendTargets) && body.nextBackendTargets.length > 0);
  // The documented routes must match what the Worker actually serves.
  assert.deepEqual(Object.keys(body.routes).sort(),
    ['capabilities', 'health', 'job', 'quote', 'separate'].sort());
});

// --- Quote ------------------------------------------------------------------

test('GET /quote returns a bounded estimate and never claims edge Demucs', async () => {
  const res = await worker.fetch(req('/quote?durationSeconds=200'), {});
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.durationSeconds, 200);
  assert.equal(body.cloudflareEdgeDemucs, false);
  assert.equal(body.recommendedExecution, 'external_gpu_worker');
  for (const k of ['gpuSeconds', 'computeUsd', 'outputMegabytes']) {
    assert.ok(Number.isFinite(body.estimate[k]) && body.estimate[k] > 0, `estimate.${k}`);
  }
});

test('POST /quote reads JSON body for duration', async () => {
  const res = await worker.fetch(jsonReq('/quote', { durationSeconds: 300 }), {});
  const body = await res.json();
  assert.equal(body.durationSeconds, 300);
});

test('/quote clamps duration to the 15-minute limit and defaults bad input', async () => {
  const over = await (await worker.fetch(req('/quote?durationSeconds=99999'), {})).json();
  assert.equal(over.durationSeconds, 900, 'clamped to maxDurationSeconds');
  const bad = await (await worker.fetch(req('/quote?durationSeconds=-5'), {})).json();
  assert.equal(bad.durationSeconds, 240, 'non-positive falls back to default');
});

// --- Separate (job dispatch) ------------------------------------------------

test('POST /separate fails closed with 503 when R2/Queue bindings are missing', async () => {
  const res = await worker.fetch(jsonReq('/separate', { filename: 'song.wav' }), {});
  assert.equal(res.status, 503);
  const body = await res.json();
  assert.equal(body.error, 'cloudflare_bindings_missing');
});

test('POST /separate rejects a non-JSON body with 415', async () => {
  const res = await worker.fetch(
    req('/separate', { method: 'POST', headers: { 'content-type': 'text/plain' }, body: 'raw' }),
    mockEnv());
  assert.equal(res.status, 415);
  assert.equal((await res.json()).error, 'json_required');
});

test('POST /separate requires a concrete R2 input source before queueing', async () => {
  const env = mockEnv();
  const res = await worker.fetch(jsonReq('/separate', { filename: 'song.wav' }), env);
  assert.equal(res.status, 400);
  const body = await res.json();
  assert.equal(body.ok, false);
  assert.equal(body.error, 'source_required');
  assert.equal(env.sends.length, 0, 'invalid jobs must not enqueue');
  assert.equal(env.puts.length, 0, 'invalid jobs must not persist');
});

test('POST /separate only accepts inputs from the stemacle-stems R2 bucket', async () => {
  const env = mockEnv();
  const res = await worker.fetch(
    jsonReq('/separate', { filename: 'song.wav', source: validSource({ bucket: 'other-bucket' }) }), env);
  assert.equal(res.status, 400);
  const body = await res.json();
  assert.equal(body.error, 'source_invalid');
  assert.match(body.message, /stemacle-stems/);
  assert.equal(env.sends.length, 0);
  assert.equal(env.puts.length, 0);
});

test('POST /separate rejects source sizes over the advertised upload limit', async () => {
  const env = mockEnv();
  const res = await worker.fetch(
    jsonReq('/separate', {
      filename: 'huge.wav',
      durationSeconds: 226,
      source: validSource({ sizeBytes: 251 * 1024 * 1024 }),
    }),
    env);
  assert.equal(res.status, 413);
  const body = await res.json();
  assert.equal(body.error, 'source_too_large');
  assert.equal(body.maxUploadBytes, 250 * 1024 * 1024);
  assert.equal(env.sends.length, 0);
  assert.equal(env.puts.length, 0);
});

test('POST /separate with bindings queues a job, persists metadata, and returns 202', async () => {
  const env = mockEnv();
  const res = await worker.fetch(
    jsonReq('/separate', {
      filename: 'song.wav',
      durationSeconds: 226,
      quality: 'hq-demucs',
      source: validSource(),
    }),
    env);
  assert.equal(res.status, 202);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.match(body.job_id, /^[0-9a-f-]{36}$/i);
  assert.equal(body.status, 'queued');
  assert.equal(body.poll, `/jobs/${body.job_id}`);
  // It must actually enqueue and persist (the contract iOS would depend on).
  assert.equal(env.sends.length, 1, 'one queue message sent');
  assert.equal(env.sends[0].jobId, body.job_id);
  assert.equal(env.puts.length, 1, 'job metadata persisted to R2');
  assert.equal(env.puts[0].key, `jobs/${body.job_id}.json`);
  // The persisted job must disclose there is no GPU consumer.
  const stored = JSON.parse(env.puts[0].value);
  assert.equal(stored.backend.gpuConsumerConfigured, false);
  assert.equal(stored.status, 'queued');
  assert.deepEqual(stored.source, validSource());
});

// --- Job status -------------------------------------------------------------

test('GET /jobs/:id round-trips a persisted job', async () => {
  const env = mockEnv();
  const created = await (await worker.fetch(
    jsonReq('/separate', { filename: 'a.wav', source: validSource({ key: 'inputs/a.wav' }) }), env)).json();
  const res = await worker.fetch(req(`/jobs/${created.job_id}`), env);
  assert.equal(res.status, 200);
  const job = await res.json();
  assert.equal(job.id, created.job_id);
  assert.equal(job.status, 'queued');
});

test('GET /jobs/:id returns 404 for an unknown but well-formed job id', async () => {
  const env = mockEnv();
  const res = await worker.fetch(req('/jobs/00000000-0000-0000-0000-000000000000'), env);
  assert.equal(res.status, 404);
  assert.equal((await res.json()).error, 'unknown_job');
});

test('GET /jobs/:id rejects a malformed job id as not_found (no 500)', async () => {
  const res = await worker.fetch(req('/jobs/not-a-uuid'), mockEnv());
  assert.equal(res.status, 404);
  assert.equal((await res.json()).error, 'not_found');
});
