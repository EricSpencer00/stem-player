import {
  SAMPLE_TRACKS,
  STEMS,
  createPendingYouTubeAdapter,
  createTrackRecord,
  keyClassName,
  parseYouTubePlaylistUrl,
  rankCompatiblePairs,
  sameTrackIdentity,
} from './library.js';
import { analyzeTrackSource, createDeckEngine } from './audio-core.js';

const state = {
  tracks: [],
  adapters: [],
  pair: null,
  pairCycleIndex: -1,
  analysisChain: Promise.resolve(),
  status: 'Load samples or local audio to build a pair library.',
};

const engine = createDeckEngine();

const refs = {
  libraryList: document.getElementById('libraryList'),
  adapterList: document.getElementById('adapterList'),
  sampleButtonRow: document.getElementById('sampleButtonRow'),
  fileInput: document.getElementById('fileInput'),
  youtubePlaylistUrl: document.getElementById('youtubePlaylistUrl'),
  captureYoutubePlaylist: document.getElementById('captureYoutubePlaylist'),
  globalStatus: document.getElementById('globalStatus'),
  shufflePair: document.getElementById('shufflePair'),
  playPair: document.getElementById('playPair'),
  stopPair: document.getElementById('stopPair'),
  leadLeft: document.getElementById('leadLeft'),
  blendMode: document.getElementById('blendMode'),
  leadRight: document.getElementById('leadRight'),
  flipDecks: document.getElementById('flipDecks'),
  crossfader: document.getElementById('crossfader'),
  crossfaderValue: document.getElementById('crossfaderValue'),
  pairStatus: document.getElementById('pairStatus'),
  compatibilityMeta: document.getElementById('compatibilityMeta'),
  transportClock: document.getElementById('transportClock'),
  leftTrackName: document.getElementById('leftTrackName'),
  leftTrackMeta: document.getElementById('leftTrackMeta'),
  leftTrackRate: document.getElementById('leftTrackRate'),
  leftStemControls: document.getElementById('leftStemControls'),
  rightTrackName: document.getElementById('rightTrackName'),
  rightTrackMeta: document.getElementById('rightTrackMeta'),
  rightTrackRate: document.getElementById('rightTrackRate'),
  rightStemControls: document.getElementById('rightStemControls'),
};

function formatTime(seconds) {
  const safe = Math.max(0, Number.isFinite(seconds) ? seconds : 0);
  const minutes = Math.floor(safe / 60);
  const secs = Math.floor(safe % 60);
  return `${minutes}:${String(secs).padStart(2, '0')}`;
}

function trackMeta(track) {
  if (!track) return 'Waiting for pair';
  if (track.analysisStatus !== 'ready') return track.analysisMessage || track.analysisStatus;
  return `${track.tempo} BPM · ${keyClassName(track.keyClass)} · ${formatTime(track.duration)}`;
}

function hasReadyPair() {
  return !!state.pair?.left && !!state.pair?.right;
}

function renderStatus() {
  refs.globalStatus.textContent = state.status;
}

function renderAdapters() {
  refs.adapterList.innerHTML = '';
  for (const adapter of state.adapters) {
    const card = document.createElement('article');
    card.className = 'adapter-card';
    card.innerHTML = `
      <div class="adapter-card__label">${adapter.label}</div>
      <div class="adapter-card__meta">${adapter.status.toUpperCase()} · ${adapter.message}</div>
    `;
    refs.adapterList.appendChild(card);
  }
}

function renderLibrary() {
  refs.libraryList.innerHTML = '';
  for (const track of state.tracks) {
    const card = document.createElement('article');
    card.className = `track-card track-card--${track.analysisStatus}`;
    const progress = track.analysisStatus === 'analyzing'
      ? `<div class="track-card__progress"><span style="width:${Math.round(track.analysisProgress * 100)}%"></span></div>`
      : '';
    card.innerHTML = `
      <div class="track-card__top">
        <div>
          <h3>${track.name}</h3>
          <p>${trackMeta(track)}</p>
        </div>
        <span class="track-card__source">${track.sourceKind}</span>
      </div>
      ${progress}
      ${track.errorMessage ? `<div class="track-card__error">${track.errorMessage}</div>` : ''}
    `;
    refs.libraryList.appendChild(card);
  }
}

function renderPair() {
  const snapshot = engine.getSnapshot();
  const pair = snapshot.pair;
  refs.leftTrackName.textContent = pair?.left?.name || 'No left deck';
  refs.leftTrackMeta.textContent = pair ? trackMeta(pair.left) : 'Shuffle a compatible pair';
  refs.leftTrackRate.textContent = pair ? `rate ${snapshot.deckRates.left.toFixed(3)}x` : 'rate 1.000x';
  refs.rightTrackName.textContent = pair?.right?.name || 'No right deck';
  refs.rightTrackMeta.textContent = pair ? trackMeta(pair.right) : 'Shuffle a compatible pair';
  refs.rightTrackRate.textContent = pair ? `rate ${snapshot.deckRates.right.toFixed(3)}x` : 'rate 1.000x';

  refs.crossfader.value = String(Math.round(snapshot.crossfade * 100));
  refs.crossfaderValue.textContent = `${Math.round(snapshot.crossfade * 100)} / 100`;
  refs.playPair.textContent = snapshot.playing ? 'Pause pair' : 'Play pair';
  refs.playPair.disabled = !pair;
  refs.stopPair.disabled = !pair;
  refs.leadLeft.disabled = !pair;
  refs.leadRight.disabled = !pair;
  refs.blendMode.disabled = !pair;
  refs.flipDecks.disabled = !pair;
  refs.crossfader.disabled = !pair;

  if (!pair) {
    refs.pairStatus.textContent = 'No compatible pair loaded yet.';
    refs.compatibilityMeta.textContent = 'Analyze at least two tracks to unlock the deck stage.';
    return;
  }

  refs.pairStatus.textContent = `${pair.left.name} into ${pair.right.name}`;
  refs.compatibilityMeta.textContent = `score ${pair.score.toFixed(1)} · ${Math.abs(pair.left.tempo - pair.right.tempo)} BPM delta · ${Math.abs(pair.left.keyClass - pair.right.keyClass)} semitone delta`;
}

function renderStemControls(container, side) {
  const snapshot = engine.getSnapshot();
  container.innerHTML = '';
  for (const stem of STEMS) {
    const row = document.createElement('label');
    row.className = 'stem-control';
    const input = document.createElement('input');
    input.type = 'range';
    input.min = '0';
    input.max = '100';
    input.value = String(Math.round(snapshot.stemLevels[side][stem] * 100));
    input.addEventListener('input', () => {
      engine.setStemLevel(side, stem, Number(input.value) / 100);
    });
    row.innerHTML = `<span>${stem}</span>`;
    row.appendChild(input);
    container.appendChild(row);
  }
}

function renderAll() {
  renderStatus();
  renderAdapters();
  renderLibrary();
  renderPair();
  renderStemControls(refs.leftStemControls, 'left');
  renderStemControls(refs.rightStemControls, 'right');
}

function addTrack(source) {
  const track = createTrackRecord(source);
  const duplicate = state.tracks.find((item) => sameTrackIdentity(item, track));
  if (duplicate) return duplicate;
  state.tracks.push(track);
  renderLibrary();
  scheduleTrackAnalysis(track);
  return track;
}

function scheduleTrackAnalysis(track) {
  state.analysisChain = state.analysisChain.then(async () => {
    track.analysisStatus = 'analyzing';
    track.analysisMessage = 'Preparing analysis...';
    track.analysisProgress = 0;
    renderLibrary();

    try {
      const analysis = await analyzeTrackSource(track, ({ percent, message }) => {
        track.analysisProgress = percent / 100;
        track.analysisMessage = message;
        renderLibrary();
      });
      Object.assign(track, analysis, {
        analysisStatus: 'ready',
        analysisProgress: 1,
        analysisMessage: `${analysis.tempo} BPM · ${keyClassName(analysis.keyClass)}`,
      });
      state.status = `Analyzed ${track.name}.`;
    } catch (error) {
      track.analysisStatus = 'error';
      track.errorMessage = error.message;
      track.analysisMessage = 'Analysis failed';
      state.status = `Could not analyze ${track.name}.`;
    }

    renderAll();
  });
}

function loadBundledSamples() {
  SAMPLE_TRACKS.forEach((track) => addTrack(track));
  state.status = 'Queued bundled samples for analysis.';
  renderStatus();
}

function handleFileSelection(event) {
  const files = Array.from(event.target.files || []);
  files.forEach((file) => {
    addTrack({
      id: `file-${file.name}-${file.size}`,
      name: file.name,
      sourceKind: 'local',
      file,
    });
  });
  if (files.length) {
    state.status = `Queued ${files.length} local track${files.length === 1 ? '' : 's'} for analysis.`;
    renderStatus();
  }
  event.target.value = '';
}

async function setPair(pair) {
  const wasPlaying = engine.isPlaying();
  engine.setPair(pair);
  state.pair = pair;
  renderPair();
  renderStemControls(refs.leftStemControls, 'left');
  renderStemControls(refs.rightStemControls, 'right');
  if (wasPlaying) {
    await engine.play();
    renderPair();
  }
}

async function chooseNextPair() {
  const ranked = rankCompatiblePairs(state.tracks);
  if (!ranked.length) {
    state.status = 'Need at least two analyzed tracks before shuffle can pick a pair.';
    renderStatus();
    return;
  }

  state.pairCycleIndex = (state.pairCycleIndex + 1) % ranked.length;
  const pair = ranked[state.pairCycleIndex];
  state.status = `Loaded pair ${pair.left.name} into ${pair.right.name}.`;
  renderStatus();
  await setPair(pair);
  renderAll();
}

async function togglePlayback() {
  if (!hasReadyPair()) return;
  if (engine.isPlaying()) {
    engine.pause();
    state.status = 'Paused current pair.';
  } else {
    const started = await engine.play();
    state.status = started
      ? `Playing ${state.pair.left.name} into ${state.pair.right.name}.`
      : 'Browser audio is still locked. Press Play pair again after interacting with the page.';
  }
  renderStatus();
  renderPair();
}

function stopPlayback() {
  engine.stop();
  state.status = 'Stopped current pair.';
  renderStatus();
  renderPair();
}

function setCrossfade(percent) {
  engine.setCrossfade(percent / 100);
  renderPair();
}

function captureYouTubePlaylist() {
  const value = refs.youtubePlaylistUrl.value.trim();
  const parsed = parseYouTubePlaylistUrl(value);
  if (!parsed.playlistId) {
    state.status = 'Paste a valid public YouTube playlist URL.';
    renderStatus();
    return;
  }

  state.adapters.push(createPendingYouTubeAdapter(parsed.canonicalUrl));
  refs.youtubePlaylistUrl.value = '';
  state.status = 'Captured YouTube playlist URL. Direct resolver is still deferred.';
  renderAll();
}

function attachEvents() {
  refs.fileInput.addEventListener('change', handleFileSelection);
  refs.captureYoutubePlaylist.addEventListener('click', captureYouTubePlaylist);
  refs.shufflePair.addEventListener('click', chooseNextPair);
  refs.playPair.addEventListener('click', togglePlayback);
  refs.stopPair.addEventListener('click', stopPlayback);
  refs.leadLeft.addEventListener('click', () => setCrossfade(0));
  refs.blendMode.addEventListener('click', () => setCrossfade(50));
  refs.leadRight.addEventListener('click', () => setCrossfade(100));
  refs.flipDecks.addEventListener('click', () => {
    const current = Number(refs.crossfader.value);
    setCrossfade(current < 50 ? 100 : 0);
  });
  refs.crossfader.addEventListener('input', () => setCrossfade(Number(refs.crossfader.value)));
}

function buildSampleButtons() {
  for (const track of SAMPLE_TRACKS) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'sample-pill';
    button.textContent = track.name;
    button.addEventListener('click', () => {
      addTrack(track);
      state.status = `Queued ${track.name}.`;
      renderStatus();
    });
    refs.sampleButtonRow.appendChild(button);
  }
}

function syncTransportClock() {
  const tick = () => {
    const duration = engine.duration();
    const time = engine.currentTime();
    refs.transportClock.textContent = `${formatTime(time)} / ${formatTime(duration)}`;
    if (engine.isPlaying() && duration > 0 && time >= duration) {
      engine.stop();
      renderPair();
    }
    requestAnimationFrame(tick);
  };
  tick();
}

attachEvents();
buildSampleButtons();
renderAll();
syncTransportClock();
