import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

// Cross-contract guards for the three separation-server shapes (see
// docs/SEPARATION_CONTRACTS.md). Individual shapes are tested elsewhere
// (server-queue, cloudflare-api, StemacleKit). THIS file pins the relationships
// between them so they cannot silently drift:
//   - the Swift client (#2) must speak the FastAPI server's contract (#1)
//   - the Cloudflare Worker (#3) is intentionally a DIFFERENT shape
//   - the canonical stem set is identical everywhere

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = (...p) => readFileSync(join(root, ...p), 'utf8');

const serverApp = read('server', 'app.py');
const sepCore = read('models', 'stemacle_sep.py');
const swiftClient = read('native', 'apple', 'StemacleKit', 'Sources', 'StemacleKit', 'StemServerClient.swift');
const worker = read('cloudflare', 'stemacle-api-worker.js');
const doc = read('docs', 'SEPARATION_CONTRACTS.md');

const STEMS = ['drums', 'vocals', 'bass', 'melody'];

// --- #1 ↔ #2: FastAPI server and Swift client must agree -------------------

test('Swift client and FastAPI server agree on the three route shapes', () => {
  // Submit: POST /separate (server) ↔ appendingPathComponent("separate") (client).
  assert.match(serverApp, /@app\.post\(["']\/separate["']\)/);
  assert.match(swiftClient, /appendingPathComponent\("separate"\)/);

  // Poll: GET /jobs/{job_id} ↔ jobs/<jobID>.
  assert.match(serverApp, /@app\.get\(["']\/jobs\/\{job_id\}["']\)/);
  assert.match(swiftClient, /appendingPathComponent\("jobs"\)\.appendingPathComponent\(jobID\)/);

  // Download: GET /jobs/{job_id}/{stem} ↔ jobs/<jobID>/<stem> (client call is line-wrapped).
  assert.match(serverApp, /@app\.get\(["']\/jobs\/\{job_id\}\/\{stem\}["']\)/);
  assert.match(swiftClient, /appendingPathComponent\(jobID\)[\s\S]{0,80}\.appendingPathComponent\(stem\)/);
});

test('Swift client decodes the exact fields the FastAPI server returns', () => {
  // Submit response: server returns job_id; client decodes job_id.
  assert.match(serverApp, /["']job_id["']/);
  assert.match(swiftClient, /let job_id: String/);

  // Job status: both name status, stems, error, progress.
  for (const key of ['status', 'stems', 'error', 'progress']) {
    assert.ok(new RegExp(`["']?${key}["']?`).test(serverApp), `server status field ${key}`);
  }
  assert.match(swiftClient, /let status: String/);
  assert.match(swiftClient, /let stems: \[String\]/);
  assert.match(swiftClient, /let error: String\?/);
  assert.match(swiftClient, /let progress: Int\?/);
});

test('Swift client uploads the multipart fields the FastAPI server expects', () => {
  // Server reads Form `model` + UploadFile `file`.
  assert.match(serverApp, /model:\s*str\s*=\s*Form/);
  assert.match(serverApp, /file:\s*UploadFile/);
  // Client sends multipart parts named exactly "model" and "file".
  assert.match(swiftClient, /multipart\/form-data; boundary=/);
  assert.match(swiftClient, /name=\\"model\\"/);
  assert.match(swiftClient, /name=\\"file\\"/);
});

// --- canonical stems identical across every surface -------------------------

test('the four canonical stems match across server, core, and Swift client', () => {
  // server/app.py + stemacle_sep.py STEM_ORDER.
  assert.match(sepCore, /STEM_ORDER\s*=\s*\[\s*["']drums["']\s*,\s*["']vocals["']\s*,\s*["']bass["']\s*,\s*["']melody["']\s*\]/);
  // Swift client downloads stems in the same order.
  assert.match(swiftClient, /\["drums", "vocals", "bass", "melody"\]/);
  // Each stem name appears in all surfaces.
  for (const stem of STEMS) {
    assert.ok(serverApp.includes(stem) || sepCore.includes(stem), `server knows ${stem}`);
    assert.ok(swiftClient.includes(stem), `swift client knows ${stem}`);
  }
});

// --- #3 is intentionally DIFFERENT from #1/#2 -------------------------------

test('Cloudflare Worker is a deliberately distinct contract, not the FastAPI shape', () => {
  // It accepts JSON job metadata, not multipart bytes.
  assert.match(worker, /This edge route accepts JSON job metadata/);
  // It has a JSON job-status route keyed by a uuid, but NOT a per-stem WAV route.
  assert.match(worker, /jobs\\\/\(\[0-9a-f-\]\{36\}\)/, 'JSON job route by uuid');
  assert.doesNotMatch(worker, /jobs\/\$\{[^}]*\}\/\$\{stem\}|\/\{job_id\}\/\{stem\}/,
    'Worker must NOT expose a per-stem WAV download route (that is contract #1)');
  // It must not pretend to do multipart WAV like the FastAPI server.
  assert.doesNotMatch(worker, /UploadFile|multipart\/form-data/);
});

test('the contracts doc documents all three and their incompatibility', () => {
  assert.match(doc, /server\/app\.py/);
  assert.match(doc, /StemServerClient/);
  assert.match(doc, /stemacle-api-worker\.js/);
  assert.match(doc, /not interchangeable/i);
});
