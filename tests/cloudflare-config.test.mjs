import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const config = readFileSync(new URL('../wrangler.api.toml', import.meta.url), 'utf8');
const worker = readFileSync(new URL('../cloudflare/stemacle-api-worker.js', import.meta.url), 'utf8');

test('Cloudflare API config deploys the Worker source with workers.dev enabled', () => {
  assert.match(config, /^name = "stemacle-api"$/m);
  assert.match(config, /^main = "cloudflare\/stemacle-api-worker\.js"$/m);
  assert.match(config, /^workers_dev = true$/m);
});

test('Cloudflare API config binds the queue producer the Worker requires', () => {
  assert.match(worker, /env\.SEPARATION_QUEUE/);
  assert.match(config, /\[\[queues\.producers\]\][\s\S]*queue = "stemacle-separation-jobs"[\s\S]*binding = "SEPARATION_QUEUE"/);
  assert.doesNotMatch(config, /\[\[queues\.consumers\]\]/,
    'No Cloudflare queue consumer is configured until a real GPU/backend worker exists');
});

test('Cloudflare API config binds both R2 buckets the Worker contract advertises', () => {
  assert.match(worker, /env\.JOBS_BUCKET/);
  assert.match(worker, /stemacle-stems/);
  assert.match(config, /\[\[r2_buckets\]\][\s\S]*bucket_name = "stemacle-jobs"[\s\S]*binding = "JOBS_BUCKET"/);
  assert.match(config, /\[\[r2_buckets\]\][\s\S]*bucket_name = "stemacle-stems"[\s\S]*binding = "STEMS_BUCKET"/);
});
