const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { createJobRunner } = require('./desktop-jobs.cjs');
const {
  AUDIO_EXTENSIONS,
  EXPORT_FORMATS,
  EXPORT_KINDS,
  MODEL_QUALITY_CATALOG,
  createModelRows,
  detectMimeType,
  detectToolState,
  ensureDir,
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
} = require('./desktop-tools.cjs');

function availabilityKeyForQuality(quality) {
  switch (quality) {
    case 'fast-preview':
      return 'preview';
    case 'demucs-4stem':
      return 'demucs4';
    case 'demucs-6stem':
      return 'demucs6';
    case 'mdx-extra-q':
      return 'mdxExtraQ';
    default:
      return quality.replace(/[^a-z0-9]+/gi, '');
  }
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
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
    downloadRoot: path.join(dataRoot, 'downloads'),
  };
}

function initialState(paths, toolState) {
  return {
    version: 2,
    createdAt: nowIso(),
    updatedAt: nowIso(),
    library: [],
    libraryRoots: [],
    queue: [],
    sessions: [],
    exports: [],
    recentProjects: [],
    tools: clone(toolState),
    paths: clone(paths),
    settings: {
      downloadRoot: paths.downloadRoot,
    },
    modelCache: {
      cacheRoot: paths.modelCacheRoot,
      models: createModelRows(paths.modelCacheRoot, toolState),
    },
  };
}

function normalizeState(state, paths, toolState) {
  const next = {
    ...initialState(paths, toolState),
    ...state,
    tools: {
      ...clone(toolState),
      ...(state.tools || {}),
    },
    paths: {
      ...clone(paths),
      ...(state.paths || {}),
    },
    settings: {
      downloadRoot: paths.downloadRoot,
      ...(state.settings || {}),
    },
    modelCache: {
      cacheRoot: paths.modelCacheRoot,
      models: createModelRows(paths.modelCacheRoot, toolState),
      ...(state.modelCache || {}),
    },
  };

  next.paths = clone(paths);
  next.tools = clone(toolState);
  next.settings.downloadRoot = paths.downloadRoot;
  next.modelCache.cacheRoot = paths.modelCacheRoot;
  next.modelCache.models = createModelRows(paths.modelCacheRoot, toolState);
  return next;
}

function createTrackRecord(filePath, paths, metadata = {}, overrides = {}) {
  const stats = fs.statSync(filePath);
  const id = stableTrackId(filePath, stats);
  const stemDir = path.join(paths.stemCacheRoot, id);

  return {
    id,
    name: path.basename(filePath),
    sourceKind: overrides.sourceKind || 'desktop',
    path: path.resolve(filePath),
    size: stats.size,
    lastModified: stats.mtimeMs,
    addedAt: overrides.addedAt || nowIso(),
    updatedAt: nowIso(),
    analysisStatus: overrides.analysisStatus || 'indexed',
    duration: metadata.duration ?? null,
    sampleRate: metadata.sampleRate ?? null,
    channels: metadata.channels ?? null,
    bpm: metadata.bpm ?? null,
    key: metadata.key ?? null,
    stemAvailability: {
      preview: false,
      demucs4: false,
      demucs6: false,
      mdxExtraQ: false,
      ...(overrides.stemAvailability || {}),
    },
    cache: {
      stemDir,
      analysisFile: path.join(paths.analysisCacheRoot, `${id}.json`),
      manifestFile: path.join(paths.analysisCacheRoot, `${id}.manifest.json`),
      waveformFile: path.join(paths.analysisCacheRoot, `${id}.waveform.json`),
      exportDir: path.join(paths.exportRoot, id),
      stemSets: clone(overrides.cache?.stemSets || {}),
    },
    analysis: {
      lastQuality: null,
      lastRunAt: null,
      error: null,
      ...(overrides.analysis || {}),
    },
    download: overrides.download || null,
    errors: Array.isArray(overrides.errors) ? overrides.errors : [],
  };
}

function updateTrackRecord(track, metadata = {}, overrides = {}) {
  if (Number.isFinite(metadata.duration)) track.duration = metadata.duration;
  if (Number.isFinite(metadata.sampleRate)) track.sampleRate = metadata.sampleRate;
  if (Number.isFinite(metadata.channels)) track.channels = metadata.channels;
  if (Number.isFinite(metadata.bpm)) track.bpm = metadata.bpm;
  if (typeof metadata.key === 'string' && metadata.key) track.key = metadata.key;
  if (overrides.sourceKind) track.sourceKind = overrides.sourceKind;
  if (overrides.download) track.download = overrides.download;
  track.updatedAt = nowIso();
}

function createDesktopStore(root, options = {}) {
  const paths = createPaths(root);
  for (const dir of [
    paths.dataRoot,
    paths.modelCacheRoot,
    paths.stemCacheRoot,
    paths.analysisCacheRoot,
    paths.exportRoot,
    paths.downloadRoot,
  ]) {
    ensureDir(dir);
  }

  const listeners = new Set();
  const toolState = detectToolState(options);
  let state = normalizeState(readJson(paths.stateFile, initialState(paths, toolState)), paths, toolState);

  function refreshCapabilities() {
    state = normalizeState(state, paths, detectToolState(options));
  }

  function emitState() {
    const snapshot = getState();
    for (const listener of listeners) listener(snapshot);
  }

  function persist() {
    state.updatedAt = nowIso();
    refreshCapabilities();
    writeJson(paths.stateFile, state);
    emitState();
  }

  function getState() {
    refreshCapabilities();
    return clone(state);
  }

  function subscribe(listener) {
    listeners.add(listener);
    return () => listeners.delete(listener);
  }

  function findTrack(trackId) {
    return state.library.find((track) => track.id === trackId);
  }

  function findTrackByPath(filePath) {
    const resolved = path.resolve(filePath);
    return state.library.find((track) => path.resolve(track.path) === resolved);
  }

  function upsertLibraryRoot(rootPath) {
    const resolved = path.resolve(rootPath);
    const existing = state.libraryRoots.find((rootRecord) => path.resolve(rootRecord.path) === resolved);
    if (existing) {
      existing.lastIndexedAt = nowIso();
      return existing;
    }

    const created = {
      id: stableRootId(resolved),
      path: resolved,
      addedAt: nowIso(),
      lastIndexedAt: nowIso(),
      trackCount: 0,
    };
    state.libraryRoots.push(created);
    return created;
  }

  function refreshRootCounts() {
    for (const rootRecord of state.libraryRoots) {
      rootRecord.trackCount = state.library.filter((track) => track.path.startsWith(`${path.resolve(rootRecord.path)}${path.sep}`) || path.resolve(track.path) === path.resolve(rootRecord.path)).length;
      rootRecord.lastIndexedAt = nowIso();
    }
  }

  async function indexTrack(audioPath, overrides = {}) {
    const resolved = path.resolve(audioPath);
    const stats = safeStat(resolved);
    if (!stats || !stats.isFile()) return null;

    const metadata = await readMetadata(resolved, {
      adapters: options.adapters,
      env: options.env,
      toolState: state.tools,
    });

    const existing = findTrackByPath(resolved);
    if (existing) {
      existing.size = stats.size;
      existing.lastModified = stats.mtimeMs;
      updateTrackRecord(existing, metadata, overrides);
      ensureDir(existing.cache.stemDir);
      ensureDir(existing.cache.exportDir);
      return existing;
    }

    const track = createTrackRecord(resolved, paths, metadata, overrides);
    ensureDir(track.cache.stemDir);
    ensureDir(track.cache.exportDir);
    state.library.push(track);
    return track;
  }

  function pushRecentProject(track) {
    state.recentProjects = [
      { id: track.id, name: track.name, path: track.path, openedAt: nowIso() },
      ...state.recentProjects.filter((project) => project.path !== track.path),
    ].slice(0, 16);
  }

  async function addLibraryPaths(inputPaths) {
    const directoryEntries = inputPaths.filter((entry) => safeStat(entry)?.isDirectory());
    for (const rootPath of directoryEntries) {
      upsertLibraryRoot(rootPath);
    }

    const audioPaths = scanAudioPaths(inputPaths);
    const added = [];
    for (const audioPath of audioPaths) {
      const track = await indexTrack(audioPath);
      if (!track) continue;
      pushRecentProject(track);
      added.push(track);
    }

    refreshRootCounts();
    persist();
    return added;
  }

  async function rescanLibrary() {
    const roots = state.libraryRoots.map((rootRecord) => rootRecord.path);
    if (!roots.length) return getState();
    await addLibraryPaths(roots);
    return getState();
  }

  function updateJob(job, patch = {}) {
    Object.assign(job, patch);
    persist();
  }

  function createJob(kind, payload = {}) {
    return {
      id: `job-${crypto.randomUUID ? crypto.randomUUID() : crypto.randomBytes(9).toString('hex')}`,
      kind,
      status: 'queued',
      progress: 0,
      message: payload.message || 'Queued',
      createdAt: nowIso(),
      startedAt: null,
      finishedAt: null,
      trackId: payload.trackId || null,
      trackName: payload.trackName || null,
      quality: payload.quality || null,
      url: payload.url || null,
      format: payload.format || null,
      exportId: payload.exportId || null,
      outputPath: payload.outputPath || null,
      error: null,
    };
  }

  async function writeTrackManifest(track, payload) {
    writeJson(track.cache.analysisFile, payload);
    writeJson(track.cache.manifestFile, payload);
  }

  async function runAnalysisJob(job) {
    const track = findTrack(job.trackId);
    if (!track) throw new Error(`Track not found: ${job.trackId}`);
    const model = MODEL_QUALITY_CATALOG.find((entry) => entry.id === job.quality);
    if (!model) throw new Error(`Unknown quality: ${job.quality}`);

    updateJob(job, {
      status: 'running',
      progress: 10,
      startedAt: nowIso(),
      message: 'Reading track metadata...',
    });

    const metadata = await readMetadata(track.path, {
      adapters: options.adapters,
      env: options.env,
      toolState: state.tools,
    });
    updateTrackRecord(track, metadata);

    if (job.quality === 'fast-preview') {
      track.analysisStatus = 'preview-ready';
      track.analysis.lastQuality = job.quality;
      track.analysis.lastRunAt = nowIso();
      track.analysis.error = null;
      await writeTrackManifest(track, {
        trackId: track.id,
        quality: job.quality,
        generatedAt: nowIso(),
        metadata,
        stemFiles: {},
      });
      updateJob(job, {
        status: 'completed',
        progress: 100,
        finishedAt: nowIso(),
        message: 'Preview metadata ready.',
      });
      persist();
      return;
    }

    if (!state.tools.demucs?.available) {
      throw new Error('Demucs is not installed.');
    }

    const qualityDir = path.join(track.cache.stemDir, job.quality);
    ensureDir(qualityDir);
    updateJob(job, {
      progress: 35,
      message: `Running ${model.label}...`,
    });

    const result = await runDemucsSeparation(
      {
        inputPath: track.path,
        outputDir: qualityDir,
        model: model.model,
        quality: job.quality,
      },
      {
        adapters: options.adapters,
        env: options.env,
        toolState: state.tools,
      }
    );

    const availabilityKey = availabilityKeyForQuality(job.quality);
    track.stemAvailability[availabilityKey] = true;
    track.cache.stemSets[job.quality] = clone(result.stemFiles || {});
    track.analysisStatus = 'ready';
    track.analysis.lastQuality = job.quality;
    track.analysis.lastRunAt = nowIso();
    track.analysis.error = null;
    track.updatedAt = nowIso();

    await writeTrackManifest(track, {
      trackId: track.id,
      quality: job.quality,
      generatedAt: nowIso(),
      metadata: {
        duration: track.duration,
        sampleRate: track.sampleRate,
        channels: track.channels,
        bpm: track.bpm,
        key: track.key,
      },
      stemFiles: track.cache.stemSets[job.quality],
    });

    updateJob(job, {
      status: 'completed',
      progress: 100,
      finishedAt: nowIso(),
      outputPath: qualityDir,
      message: `${model.label} cache ready.`,
    });
    persist();
  }

  async function runDownloadJob(job) {
    if (!state.tools.ytDlp?.available) {
      throw new Error('yt-dlp is not installed.');
    }

    updateJob(job, {
      status: 'running',
      progress: 15,
      startedAt: nowIso(),
      message: 'Downloading source audio...',
    });

    const result = await runDownload(
      {
        url: job.url,
        outputDir: state.settings.downloadRoot,
      },
      {
        adapters: options.adapters,
        env: options.env,
        toolState: state.tools,
      }
    );

    updateJob(job, {
      progress: 70,
      message: 'Indexing downloaded audio...',
      outputPath: result.filePath,
    });

    const indexedTrack = await indexTrack(result.filePath, {
      sourceKind: 'download',
      download: {
        sourceUrl: job.url,
        downloadedAt: nowIso(),
      },
    });
    if (!indexedTrack) {
      throw new Error('Downloaded audio could not be indexed.');
    }

    pushRecentProject(indexedTrack);
    updateJob(job, {
      status: 'completed',
      progress: 100,
      finishedAt: nowIso(),
      trackId: indexedTrack.id,
      trackName: indexedTrack.name,
      message: 'Download indexed into library.',
    });
    persist();
  }

  function findStemSet(track, preferredQuality) {
    if (preferredQuality && track.cache.stemSets[preferredQuality]) {
      return { quality: preferredQuality, files: track.cache.stemSets[preferredQuality] };
    }

    for (const quality of ['demucs-6stem', 'demucs-4stem', 'mdx-extra-q']) {
      if (track.cache.stemSets[quality]) {
        return { quality, files: track.cache.stemSets[quality] };
      }
    }

    return null;
  }

  async function runExportJob(job) {
    const track = findTrack(job.trackId);
    if (!track) throw new Error(`Track not found: ${job.trackId}`);
    const exportRecord = state.exports.find((item) => item.id === job.exportId);
    if (!exportRecord) throw new Error(`Export not found: ${job.exportId}`);
    if (!EXPORT_KINDS.has(exportRecord.kind)) {
      throw new Error(`Unsupported export kind: ${exportRecord.kind}`);
    }
    if (!EXPORT_FORMATS.has(exportRecord.format)) {
      throw new Error(`Unsupported export format: ${exportRecord.format}`);
    }

    const stemSet = findStemSet(track, exportRecord.quality);
    if (!stemSet) {
      throw new Error('No cached stems available. Run analysis first.');
    }

    if (!['stem-pack', 'individual-stems'].includes(exportRecord.kind)) {
      throw new Error(`${exportRecord.kind} export is not implemented yet.`);
    }

    updateJob(job, {
      status: 'running',
      progress: 15,
      startedAt: nowIso(),
      message: 'Preparing cached stems...',
    });
    exportRecord.status = 'running';

    const outputDir = path.join(track.cache.exportDir, exportRecord.kind);
    ensureDir(outputDir);
    const outputs = [];
    const entries = Object.entries(stemSet.files);
    let index = 0;
    for (const [stemName, inputPath] of entries) {
      const outputPath = path.join(outputDir, `${stemName}.${exportRecord.format}`);
      await convertAudio(
        {
          inputPath,
          outputPath,
          format: exportRecord.format,
        },
        {
          adapters: options.adapters,
          env: options.env,
          toolState: state.tools,
        }
      );
      outputs.push(outputPath);
      index += 1;
      updateJob(job, {
        progress: Math.round(15 + (80 * index) / entries.length),
        message: `Exporting ${stemName}...`,
      });
    }

    exportRecord.status = 'completed';
    exportRecord.outputPath = outputDir;
    exportRecord.outputs = outputs;
    exportRecord.updatedAt = nowIso();
    updateJob(job, {
      status: 'completed',
      progress: 100,
      finishedAt: nowIso(),
      outputPath: outputDir,
      message: 'Export ready.',
    });
    persist();
  }

  async function runJob(job) {
    try {
      if (job.kind === 'analysis') {
        await runAnalysisJob(job);
        return;
      }
      if (job.kind === 'download') {
        await runDownloadJob(job);
        return;
      }
      if (job.kind === 'export') {
        await runExportJob(job);
        return;
      }
      throw new Error(`Unsupported job kind: ${job.kind}`);
    } catch (error) {
      if (job.kind === 'analysis' && job.trackId) {
        const track = findTrack(job.trackId);
        if (track) {
          track.analysisStatus = 'error';
          track.analysis.error = error.message;
        }
      }
      if (job.kind === 'export' && job.exportId) {
        const exportRecord = state.exports.find((item) => item.id === job.exportId);
        if (exportRecord) {
          exportRecord.status = 'failed';
          exportRecord.error = error.message;
          exportRecord.updatedAt = nowIso();
        }
      }
      updateJob(job, {
        status: 'failed',
        progress: 100,
        finishedAt: nowIso(),
        error: error.message,
        message: error.message,
      });
    }
  }

  const runner = createJobRunner({
    getNextJob: () => state.queue.find((job) => job.status === 'queued'),
    runJob,
    onError: () => {},
  });

  function enqueueAnalysis(trackId, optionsForJob = {}) {
    const track = findTrack(trackId);
    if (!track) throw new Error(`Track not found: ${trackId}`);
    const quality = optionsForJob.quality || 'fast-preview';
    const job = createJob('analysis', {
      trackId,
      trackName: track.name,
      quality,
      message: quality === 'fast-preview' ? 'Preview analysis queued.' : `${quality} queued.`,
    });
    track.analysisStatus = 'queued';
    track.updatedAt = nowIso();
    state.queue.push(job);
    persist();
    runner.schedule();
    return job;
  }

  function enqueueDownload(url) {
    if (!url || typeof url !== 'string') throw new Error('A download URL is required.');
    const job = createJob('download', {
      url,
      message: 'Download queued.',
    });
    state.queue.push(job);
    persist();
    runner.schedule();
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

  function enqueueExport(trackId, optionsForJob = {}) {
    const track = findTrack(trackId);
    if (!track) throw new Error(`Track not found: ${trackId}`);
    const kind = EXPORT_KINDS.has(optionsForJob.kind) ? optionsForJob.kind : 'stem-pack';
    const format = EXPORT_FORMATS.has(optionsForJob.format) ? optionsForJob.format : 'wav';
    const quality = optionsForJob.quality || null;
    const exportRecord = {
      id: `export-${crypto.randomUUID ? crypto.randomUUID() : crypto.randomBytes(9).toString('hex')}`,
      trackId,
      trackName: track.name,
      kind,
      quality,
      format,
      status: 'queued',
      createdAt: nowIso(),
      updatedAt: nowIso(),
      outputPath: path.join(track.cache.exportDir, kind),
      outputs: [],
      error: null,
    };
    state.exports.unshift(exportRecord);
    state.exports = state.exports.slice(0, 48);

    const job = createJob('export', {
      trackId,
      trackName: track.name,
      format,
      exportId: exportRecord.id,
      message: 'Export queued.',
    });
    state.queue.push(job);
    persist();
    runner.schedule();
    return job;
  }

  function planExport(trackId, optionsForJob = {}) {
    return enqueueExport(trackId, optionsForJob);
  }

  function readTrackFile(trackId) {
    const track = findTrack(trackId);
    if (!track) throw new Error(`Track not found: ${trackId}`);
    return {
      id: track.id,
      name: track.name,
      mimeType: detectMimeType(track.path),
      bytes: fs.readFileSync(track.path),
    };
  }

  function clear() {
    state = initialState(paths, detectToolState(options));
    persist();
    return getState();
  }

  persist();

  return {
    paths,
    subscribe,
    getState,
    addLibraryPaths,
    rescanLibrary,
    enqueueAnalysis,
    enqueueDownload,
    enqueueExport,
    planExport,
    saveSession,
    readTrackFile,
    clear,
    waitForIdle: () => runner.waitForIdle(),
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
