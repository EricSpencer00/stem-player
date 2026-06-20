const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');

const AUDIO_EXTENSIONS = new Set([
  '.mp3',
  '.wav',
  '.m4a',
  '.aac',
  '.ogg',
  '.flac',
  '.opus',
  '.aiff',
  '.aif',
]);

const EXPORT_KINDS = new Set([
  'individual-stems',
  'stem-pack',
  'full-mixdown',
  'current-loop',
  'deck-transition',
]);

const EXPORT_FORMATS = new Set(['wav', 'flac', 'mp3']);

const MODEL_QUALITY_CATALOG = [
  {
    id: 'fast-preview',
    label: 'Fast Preview',
    engine: 'browser-dsp-onnx',
    stems: 4,
    cached: true,
    offline: true,
    description: 'Metadata-first preview flow for immediate desktop handoff into the browser splitter.',
  },
  {
    id: 'demucs-4stem',
    label: 'High Quality 4-Stem',
    engine: 'demucs',
    model: 'htdemucs_ft',
    stems: 4,
    cached: true,
    offline: true,
    description: 'Local Demucs htdemucs_ft for vocals, drums, bass, and other.',
  },
  {
    id: 'demucs-6stem',
    label: 'Experimental 6-Stem',
    engine: 'demucs',
    model: 'htdemucs_6s',
    stems: 6,
    cached: true,
    offline: true,
    optional: true,
    description: 'Optional Demucs six-stem split for guitar and piano-aware sessions.',
  },
  {
    id: 'mdx-extra-q',
    label: 'MDX Extra Q',
    engine: 'demucs',
    model: 'mdx_extra_q',
    stems: 4,
    cached: true,
    offline: true,
    optional: true,
    description: 'Alternative Demucs model with a sharper 4-stem bias for difficult material.',
  },
];

const TOOL_DEFINITIONS = {
  ffmpeg: { executable: 'ffmpeg', label: 'ffmpeg' },
  ffprobe: { executable: 'ffprobe', label: 'ffprobe' },
  demucs: { executable: 'demucs', label: 'Demucs' },
  ytDlp: { executable: 'yt-dlp', label: 'yt-dlp' },
};

function nowIso() {
  return new Date().toISOString();
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (_error) {
    return fallback;
  }
}

function writeJson(file, value) {
  ensureDir(path.dirname(file));
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
}

function safeStat(filePath) {
  try {
    return fs.statSync(filePath);
  } catch (_error) {
    return null;
  }
}

function isAudioPath(filePath) {
  return AUDIO_EXTENSIONS.has(path.extname(filePath).toLowerCase());
}

function scanAudioPaths(entries) {
  const results = [];
  const stack = [...entries];

  while (stack.length) {
    const next = stack.shift();
    const stats = safeStat(next);
    if (!stats) continue;

    if (stats.isDirectory()) {
      for (const child of fs.readdirSync(next)) {
        stack.push(path.join(next, child));
      }
      continue;
    }

    if (stats.isFile() && isAudioPath(next)) {
      results.push(path.resolve(next));
    }
  }

  return results;
}

function stableTrackId(filePath, stats) {
  return crypto
    .createHash('sha256')
    .update(path.resolve(filePath))
    .update(String(stats.size))
    .update(String(Math.round(stats.mtimeMs)))
    .digest('hex')
    .slice(0, 18);
}

function stableRootId(rootPath) {
  return crypto.createHash('sha1').update(path.resolve(rootPath)).digest('hex').slice(0, 12);
}

function resolveExecutable(name, options = {}) {
  const executable = TOOL_DEFINITIONS[name]?.executable || name;
  const result = spawnSync(process.platform === 'win32' ? 'where' : 'which', [executable], {
    stdio: ['ignore', 'pipe', 'ignore'],
    encoding: 'utf8',
    env: options.env || process.env,
  });

  if (result.status !== 0) return null;
  const firstLine = String(result.stdout || '').split(/\r?\n/).find(Boolean);
  return firstLine ? firstLine.trim() : executable;
}

function detectToolState(options = {}) {
  const state = {};
  const overrides = options.toolState || {};

  for (const [name, definition] of Object.entries(TOOL_DEFINITIONS)) {
    const override = overrides[name];
    if (override) {
      state[name] = {
        label: definition.label,
        command: override.command || null,
        available: Boolean(override.available),
      };
      continue;
    }

    const command = resolveExecutable(name, options);
    state[name] = {
      label: definition.label,
      command,
      available: Boolean(command),
    };
  }

  return state;
}

function createModelRows(modelCacheRoot, toolState) {
  return MODEL_QUALITY_CATALOG.map((model) => {
    const available = model.engine === 'demucs' ? Boolean(toolState.demucs?.available) : true;
    return {
      ...model,
      available,
      cachePath: path.join(modelCacheRoot, model.id),
      status: available ? 'ready' : 'install demucs to run',
    };
  });
}

function detectMimeType(filePath) {
  const extension = path.extname(filePath).toLowerCase();
  switch (extension) {
    case '.mp3':
      return 'audio/mpeg';
    case '.wav':
      return 'audio/wav';
    case '.m4a':
      return 'audio/mp4';
    case '.aac':
      return 'audio/aac';
    case '.ogg':
      return 'audio/ogg';
    case '.flac':
      return 'audio/flac';
    case '.opus':
      return 'audio/ogg';
    case '.aiff':
    case '.aif':
      return 'audio/aiff';
    default:
      return 'application/octet-stream';
  }
}

function normalizeMetadata(metadata = {}) {
  return {
    duration: Number.isFinite(metadata.duration) ? metadata.duration : null,
    sampleRate: Number.isFinite(metadata.sampleRate) ? metadata.sampleRate : null,
    channels: Number.isFinite(metadata.channels) ? metadata.channels : null,
    bpm: Number.isFinite(metadata.bpm) ? metadata.bpm : null,
    key: typeof metadata.key === 'string' && metadata.key ? metadata.key : null,
  };
}

async function readMetadata(filePath, context = {}) {
  if (context.adapters?.readMetadata) {
    return normalizeMetadata(await context.adapters.readMetadata(filePath, context));
  }

  const toolState = context.toolState || detectToolState(context);
  if (!toolState.ffprobe?.available || !toolState.ffprobe.command) {
    return normalizeMetadata({});
  }

  const result = spawnSync(
    toolState.ffprobe.command,
    ['-v', 'error', '-print_format', 'json', '-show_streams', '-show_format', filePath],
    {
      encoding: 'utf8',
      maxBuffer: 10 * 1024 * 1024,
      env: context.env || process.env,
    }
  );

  if (result.status !== 0) {
    return normalizeMetadata({});
  }

  try {
    const payload = JSON.parse(result.stdout || '{}');
    const audioStream = Array.isArray(payload.streams)
      ? payload.streams.find((stream) => stream.codec_type === 'audio') || payload.streams[0]
      : null;
    const format = payload.format || {};
    const tags = {
      ...(audioStream?.tags || {}),
      ...(format.tags || {}),
    };
    const bpm = Number(tags.BPM || tags.TBPM || tags.bpm || tags.tbpm);
    const key = tags.initialkey || tags.INITIALKEY || tags.key || tags.KEY || null;
    return normalizeMetadata({
      duration: Number(format.duration),
      sampleRate: Number(audioStream?.sample_rate),
      channels: Number(audioStream?.channels),
      bpm,
      key,
    });
  } catch (_error) {
    return normalizeMetadata({});
  }
}

function runCommand(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: options.cwd,
      env: options.env || process.env,
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => {
      stdout += String(chunk);
    });
    child.stderr.on('data', (chunk) => {
      stderr += String(chunk);
    });
    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0) {
        resolve({ stdout, stderr });
        return;
      }

      const message = stderr.trim() || stdout.trim() || `${command} exited with code ${code}`;
      reject(new Error(message));
    });
  });
}

function copyFile(inputPath, outputPath) {
  ensureDir(path.dirname(outputPath));
  fs.copyFileSync(inputPath, outputPath);
  return { outputPath };
}

function listAudioFiles(root) {
  const stack = [root];
  const results = [];

  while (stack.length) {
    const next = stack.shift();
    const stats = safeStat(next);
    if (!stats) continue;
    if (stats.isDirectory()) {
      for (const child of fs.readdirSync(next)) {
        stack.push(path.join(next, child));
      }
      continue;
    }
    if (stats.isFile() && isAudioPath(next)) {
      results.push(path.resolve(next));
    }
  }

  return results;
}

async function runDemucsSeparation(options, context = {}) {
  if (context.adapters?.runDemucs) {
    return context.adapters.runDemucs(options, context);
  }

  const toolState = context.toolState || detectToolState(context);
  if (!toolState.demucs?.available || !toolState.demucs.command) {
    throw new Error('Demucs is not installed.');
  }

  const tempRoot = path.join(options.outputDir, '__demucs-tmp');
  ensureDir(tempRoot);
  await runCommand(
    toolState.demucs.command,
    ['-n', options.model, '-o', tempRoot, options.inputPath],
    { env: context.env }
  );

  const produced = listAudioFiles(tempRoot);
  if (!produced.length) {
    throw new Error('Demucs did not produce any stem files.');
  }

  ensureDir(options.outputDir);
  const stemFiles = {};
  for (const file of produced) {
    const stemName = path.basename(file, path.extname(file));
    const target = path.join(options.outputDir, `${stemName}.wav`);
    fs.copyFileSync(file, target);
    stemFiles[stemName] = target;
  }
  return { stemFiles };
}

async function runDownload(options, context = {}) {
  if (context.adapters?.runDownload) {
    return context.adapters.runDownload(options, context);
  }

  const toolState = context.toolState || detectToolState(context);
  if (!toolState.ytDlp?.available || !toolState.ytDlp.command) {
    throw new Error('yt-dlp is not installed.');
  }

  ensureDir(options.outputDir);
  const before = new Set(listAudioFiles(options.outputDir));
  await runCommand(
    toolState.ytDlp.command,
    [
      '-x',
      '--audio-format',
      'mp3',
      '--output',
      '%(title)s [%(id)s].%(ext)s',
      '--paths',
      options.outputDir,
      options.url,
    ],
    { env: context.env }
  );
  const after = listAudioFiles(options.outputDir);
  const filePath = after.find((candidate) => !before.has(candidate)) || after.sort().pop();
  if (!filePath) {
    throw new Error('yt-dlp completed without creating an audio file.');
  }
  return { filePath, title: path.basename(filePath) };
}

async function convertAudio(options, context = {}) {
  if (context.adapters?.convertAudio) {
    return context.adapters.convertAudio(options, context);
  }

  const inputExtension = path.extname(options.inputPath).toLowerCase();
  const outputExtension = path.extname(options.outputPath).toLowerCase();
  if (inputExtension === outputExtension || (!outputExtension && options.format === 'wav')) {
    return copyFile(options.inputPath, options.outputPath);
  }

  const toolState = context.toolState || detectToolState(context);
  if (!toolState.ffmpeg?.available || !toolState.ffmpeg.command) {
    throw new Error('ffmpeg is not installed.');
  }

  ensureDir(path.dirname(options.outputPath));
  await runCommand(
    toolState.ffmpeg.command,
    ['-y', '-i', options.inputPath, options.outputPath],
    { env: context.env }
  );
  return { outputPath: options.outputPath };
}

module.exports = {
  AUDIO_EXTENSIONS,
  EXPORT_FORMATS,
  EXPORT_KINDS,
  MODEL_QUALITY_CATALOG,
  TOOL_DEFINITIONS,
  createModelRows,
  detectMimeType,
  detectToolState,
  ensureDir,
  isAudioPath,
  listAudioFiles,
  normalizeMetadata,
  nowIso,
  readJson,
  readMetadata,
  runDemucsSeparation,
  runDownload,
  convertAudio,
  safeStat,
  scanAudioPaths,
  stableRootId,
  stableTrackId,
  writeJson,
};
