const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-allow-headers": "content-type, authorization",
};

const LIMITS = {
  maxUploadBytes: 250 * 1024 * 1024,
  maxDurationSeconds: 15 * 60,
  includedHqSplits: 3,
};

function json(body, init = {}) {
  return new Response(JSON.stringify(body, null, 2), {
    ...init,
    headers: {
      ...JSON_HEADERS,
      ...(init.headers || {}),
    },
  });
}

function notFound(pathname) {
  return json(
    {
      ok: false,
      error: "not_found",
      message: `No Stemacle API route exists at ${pathname}`,
    },
    { status: 404 },
  );
}

function jobKey(jobId) {
  return `jobs/${jobId}.json`;
}

async function readJson(request) {
  const contentType = request.headers.get("content-type") || "";
  if (!contentType.includes("application/json")) return null;
  return request.json().catch(() => null);
}

function validateSource(source) {
  if (!source || typeof source !== "object") {
    return json(
      {
        ok: false,
        error: "source_required",
        message: "Queue jobs require an R2 input source before Cloudflare can dispatch them.",
      },
      { status: 400 },
    );
  }

  if (
    source.kind !== "r2" ||
    source.bucket !== "stemacle-stems" ||
    typeof source.key !== "string" ||
    !source.key.startsWith("inputs/")
  ) {
    return json(
      {
        ok: false,
        error: "source_invalid",
        message: "Source must be an R2 object in the stemacle-stems bucket under inputs/.",
      },
      { status: 400 },
    );
  }

  if (Number.isFinite(source.sizeBytes) && source.sizeBytes > LIMITS.maxUploadBytes) {
    return json(
      {
        ok: false,
        error: "source_too_large",
        maxUploadBytes: LIMITS.maxUploadBytes,
      },
      { status: 413 },
    );
  }

  return null;
}

function parseDuration(value) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return 240;
  return Math.min(n, LIMITS.maxDurationSeconds);
}

async function quote(request) {
  let durationSeconds = 240;
  let quality = "hq-demucs";

  if (request.method === "GET") {
    const url = new URL(request.url);
    durationSeconds = parseDuration(url.searchParams.get("durationSeconds"));
    quality = url.searchParams.get("quality") || quality;
  } else {
    const body = await request.json().catch(() => ({}));
    durationSeconds = parseDuration(body.durationSeconds);
    quality = body.quality || quality;
  }

  // Conservative planning numbers, not billing. Real pricing depends on the GPU
  // backend; the edge Worker is only the front door.
  const gpuSeconds = Math.ceil(durationSeconds * 0.35 + 20);
  const estimatedComputeUsd = Math.max(0.01, (gpuSeconds / 3600) * 0.9);
  const estimatedOutputMb = Math.ceil((durationSeconds / 60) * 32);

  return json({
    ok: true,
    quality,
    durationSeconds,
    cloudflareEdgeDemucs: false,
    recommendedExecution: "external_gpu_worker",
    estimate: {
      gpuSeconds,
      computeUsd: Number(estimatedComputeUsd.toFixed(4)),
      outputMegabytes: estimatedOutputMb,
    },
    pricingGuardrail: {
      lifetimeAppPriceUsd: 2.99,
      unlimitedCloudSplitsRecommended: false,
      includedHqSplits: LIMITS.includedHqSplits,
    },
  });
}

function capabilities() {
  return json({
    ok: true,
    service: "stemacle-api",
    role: "cloudflare-edge-front-door",
    demucsOnCloudflareEdge: false,
    currentBackend: "cloudflare_queue_no_gpu_consumer",
    supportedNow: [
      "health checks",
      "capability discovery",
      "per-track cost quotes",
      "stable queue API shape for iOS integration",
      "R2-backed job metadata",
      "Cloudflare Queue job dispatch",
    ],
    nextBackendTargets: [
      "RunPod Serverless",
      "Modal GPU function",
      "AWS Batch or ECS on g5 spot once usage is predictable",
    ],
    limits: LIMITS,
    routes: {
      health: "GET /healthz",
      capabilities: "GET /capabilities",
      quote: "GET /quote?durationSeconds=240 or POST /quote",
      separate: "POST /separate",
      job: "GET /jobs/:jobId",
    },
  });
}

function health() {
  return json({
    ok: true,
    service: "stemacle-api",
    timestamp: new Date().toISOString(),
  });
}

async function separate(request, env) {
  if (!env.JOBS_BUCKET || !env.SEPARATION_QUEUE) {
    return json(
      {
        ok: false,
        error: "cloudflare_bindings_missing",
        message: "The Worker is live, but R2/Queue bindings are not configured.",
      },
      { status: 503 },
    );
  }

  const body = await readJson(request);
  if (!body) {
    return json(
      {
        ok: false,
        error: "json_required",
        message:
          "This edge route accepts JSON job metadata now. Upload bytes should go to R2 via a signed upload URL in the next iteration.",
        example: {
          filename: "song.wav",
          durationSeconds: 226,
          source: { kind: "r2", bucket: "stemacle-stems", key: "inputs/example.wav" },
        },
      },
      { status: 415 },
    );
  }

  const sourceError = validateSource(body.source);
  if (sourceError) return sourceError;

  const jobId = crypto.randomUUID();
  const now = new Date().toISOString();
  const durationSeconds = parseDuration(body.durationSeconds);
  const job = {
    id: jobId,
    status: "queued",
    createdAt: now,
    updatedAt: now,
    filename: String(body.filename || "untitled-audio"),
    durationSeconds,
    source: body.source,
    quality: body.quality || "hq-demucs",
    backend: {
      frontDoor: "cloudflare-worker",
      queue: "stemacle-separation-jobs",
      gpuConsumerConfigured: false,
    },
    stems: [],
    error: null,
  };

  await env.JOBS_BUCKET.put(jobKey(jobId), JSON.stringify(job, null, 2), {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
  });
  await env.SEPARATION_QUEUE.send({
    jobId,
    source: job.source,
    durationSeconds,
    quality: job.quality,
  });

  return json(
    {
      ok: true,
      job_id: jobId,
      status: "queued",
      poll: `/jobs/${jobId}`,
      message:
        "Job accepted by Cloudflare. Attach a GPU consumer to process the queue before exposing HQ splits to users.",
      acceptedBackendKinds: ["runpod_serverless", "modal_gpu", "aws_batch_gpu"],
    },
    { status: 202 },
  );
}

async function jobStatus(jobId, env) {
  if (!env.JOBS_BUCKET) {
    return json({ ok: false, error: "jobs_bucket_missing" }, { status: 503 });
  }
  const object = await env.JOBS_BUCKET.get(jobKey(jobId));
  if (!object) return json({ ok: false, error: "unknown_job" }, { status: 404 });
  return json(await object.json());
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: JSON_HEADERS });
    }

    const url = new URL(request.url);
    if (url.pathname === "/" || url.pathname === "/healthz") return health();
    if (url.pathname === "/capabilities") return capabilities();
    if (url.pathname === "/quote") return quote(request);
    if (url.pathname === "/separate" && request.method === "POST") return separate(request, env);
    const jobMatch = url.pathname.match(/^\/jobs\/([0-9a-f-]{36})$/i);
    if (jobMatch && request.method === "GET") return jobStatus(jobMatch[1], env);
    return notFound(url.pathname);
  },
};
