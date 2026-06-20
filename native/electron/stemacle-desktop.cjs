const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

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
    description: 'Uses the bundled browser splitter and cached preview stems for immediate playback.',
  },
  {
    id: 'demucs-4stem',
    label: 'High Quality 4-Stem',
    engine: 'demucs',
    model: 'htdemucs_ft',
    stems: 4,
    cached: true,
    offline: true,
    description: 'Runs local Demucs when installed, caches vocals, drums, bass, and other.',
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
    description: 'Optional Demucs six-stem target for guitar and piano-aware sessions.',
  },
];

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

function executableAvailable(name) {
  const result = spawnSync(process.platform === 'win32' ? 'where' : 'which', [name], {
    stdio: 'ignore',
  });
  return result.status === 0;
}

function initialState(paths) {
  return {
    version: 1,
    createdAt: nowIso(),
    updatedAt: nowIso(),
    library: [],
    queue: [],
    sessions: [],
    exports: [],
    recentProjects: [],
    modelCache: {
      cacheRoot: paths.modelCacheRoot,
      demucsAvailable: executableAvailable('demucs'),
      models: MODEL_QUALITY_CATALOG.map((model) => ({
        ...model,
        cachePath: path.join(paths.modelCacheRoot, model.id),
        status: model.engine === 'demucs' && !executableAvailable('demucs') ? 'install demucs to run' : 'ready',
      })),
    },
  };
}

function normalizeState(state, paths) {
  const next = {
    ...initialState(paths),
    ...state,
    modelCache: {
      ...initialState(paths).modelCache,
      ...(state.modelCache || {}),
      cacheRoot: paths.modelCacheRoot,
    },
  };
  next.updatedAt = state.updatedAt || nowIso();
  return next;
}

function createTrackRecord(filePath, paths) {
  const stats = fs.statSync(filePath);
  const id = stableTrackId(filePath, stats);
  const stemDir = path.join(paths.stemCacheRoot, id);

  return {
    id,
    name: path.basename(filePath),
    sourceKind: 'desktop',
    path: path.resolve(filePath),
    size: stats.size,
    lastModified: stats.mtimeMs,
    addedAt: nowIso(),
    updatedAt: nowIso(),
    analysisStatus: 'indexed',
    bpm: null,
    key: null,
    duration: null,
    stemAvailability: {
      preview: false,
      demucs4: false,
      demucs6: false,
    },
    cache: {
      stemDir,
      analysisFile: path.join(paths.analysisCacheRoot, `${id}.json`),
      waveformFile: path.join(paths.analysisCacheRoot, `${id}.waveform.json`),
      exportDir: path.join(paths.exportRoot, id),
    },
  };
}

function createPaths(root) {
  const dataRoot = path.resolve(root);
  return {
    dataRoot,
    stateFile: path.join(dataRoot, 'desktop-state.json'),
    modelCacheRoot: path.join(dataRoot, 'model-cache'),
    stemCacheRoot: path.join(dataRoot, 'stem-cache'),
    analysisCacheRoot: path.join(dataRoot, 'analysis-cache'),
    exportRoot: path.join(dataRoot, 'exports'),
  };
}

function createDesktopStore(root) {
  const paths = createPaths(root);
  for (const dir of [paths.dataRoot, paths.modelCacheRoot, paths.stemCacheRoot, paths.analysisCacheRoot, paths.exportRoot]) {
    ensureDir(dir);
  }

  let state = normalizeState(readJson(paths.stateFile, initialState(paths)), paths);

  function persist() {
    state.updatedAt = nowIso();
    writeJson(paths.stateFile, state);
  }

  function getState() {
    state.modelCache = normalizeState(state, paths).modelCache;
    return JSON.parse(JSON.stringify(state));
  }

  function addLibraryPaths(inputPaths) {
    const audioPaths = scanAudioPaths(inputPaths);
    const existingByPath = new Map(state.library.map((track) => [path.resolve(track.path), track]));
    const added = [];

    for (const audioPath of audioPaths) {
      const resolved = path.resolve(audioPath);
      if (existingByPath.has(resolved)) {
        added.push(existingByPath.get(resolved));
        continue;
      }

      const track = createTrackRecord(resolved, paths);
      ensureDir(track.cache.stemDir);
      ensureDir(track.cache.exportDir);
      state.library.push(track);
      state.recentProjects = [
        { id: track.id, name: track.name, path: track.path, openedAt: nowIso() },
        ...state.recentProjects.filter((project) => project.path !== track.path),
      ].slice(0, 12);
      existingByPath.set(resolved, track);
      added.push(track);
    }

    persist();
    return added;
  }

  function findTrack(trackId) {
    return state.library.find((track) => track.id === trackId);
  }

  function enqueueAnalysis(trackId, options = {}) {
    const track = findTrack(trackId);
    if (!track) throw new Error(`Track not found: ${trackId}`);
    const quality = options.quality || 'fast-preview';
    const model = MODEL_QUALITY_CATALOG.find((entry) => entry.id === quality);
    if (!model) throw new Error(`Unknown quality: ${quality}`);

    const job = {
      id: `job-${crypto.randomUUID ? crypto.randomUUID() : crypto.randomBytes(9).toString('hex')}`,
      trackId,
      trackName: track.name,
      quality,
      status: 'queued',
      progress: 0,
      message: quality === 'fast-preview' ? 'Ready for preview cache.' : `Waiting for local ${model.label}.`,
      createdAt: nowIso(),
      updatedAt: nowIso(),
      cacheTarget: track.cache.stemDir,
    };
    state.queue.push(job);
    track.analysisStatus = 'queued';
    track.updatedAt = nowIso();
    persist();
    return job;
  }

  function saveSession(session) {
    const saved = {
      id: `session-${crypto.randomUUID ? crypto.randomUUID() : crypto.randomBytes(9).toString('hex')}`,
      name: session.name || `Stemacle session ${state.sessions.length + 1}`,
      trackIds: Array.isArray(session.trackIds) ? session.trackIds : [],
      mixer: session.mixer || {},
      loops: session.loops || {},
      deckState: session.deckState || {},
      createdAt: nowIso(),
      updatedAt: nowIso(),
    };
    state.sessions.unshift(saved);
    state.sessions = state.sessions.slice(0, 24);
    persist();
    return saved;
  }

  function planExport(trackId, options = {}) {
    const track = findTrack(trackId);
    if (!track) throw new Error(`Track not found: ${trackId}`);
    const kind = EXPORT_KINDS.has(options.kind) ? options.kind : 'stem-pack';
    const format = EXPORT_FORMATS.has(options.format) ? options.format : 'wav';
    const exportPlan = {
      id: `export-${crypto.randomUUID ? crypto.randomUUID() : crypto.randomBytes(9).toString('hex')}`,
      trackId,
      trackName: track.name,
      kind,
      format,
      status: 'planned',
      createdAt: nowIso(),
      outputPath: path.join(track.cache.exportDir, `${kind}.${format}`),
    };
    state.exports.unshift(exportPlan);
    state.exports = state.exports.slice(0, 48);
    persist();
    return exportPlan;
  }

  function clear() {
    state = initialState(paths);
    persist();
    return getState();
  }

  persist();

  return {
    paths,
    getState,
    addLibraryPaths,
    enqueueAnalysis,
    saveSession,
    planExport,
    clear,
  };
}

module.exports = {
  AUDIO_EXTENSIONS,
  MODEL_QUALITY_CATALOG,
  createDesktopStore,
  createTrackRecord,
  scanAudioPaths,
  stableTrackId,
};
