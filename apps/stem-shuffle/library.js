export const STEMS = ['vocals', 'melody', 'drums', 'bass'];

export const SAMPLE_TRACKS = [
  {
    id: 'sample-gentleman',
    name: 'Gentleman - cdk feat. QuianaNadine',
    sourceKind: 'sample',
    url: '../../samples/stem-sample-1.mp3',
  },
  {
    id: 'sample-red-light-blues',
    name: 'Red Light Blues - Alex & UnrealDM',
    sourceKind: 'sample',
    url: '../../samples/stem-sample-2.mp3',
  },
  {
    id: 'sample-pyramid',
    name: 'Pyramid - 7OOP3D feat. Mr Yesterday',
    sourceKind: 'sample',
    url: '../../samples/stem-sample-3.mp3',
  },
];

const KEY_NAMES = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];

let trackCounter = 0;
let adapterCounter = 0;

function nextId(prefix) {
  trackCounter += 1;
  return `${prefix}-${trackCounter}`;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

export function keyClassName(keyClass) {
  if (!Number.isFinite(keyClass)) return '?';
  return KEY_NAMES[((Math.round(keyClass) % 12) + 12) % 12];
}

export function createTrackRecord(source) {
  return {
    id: source.id || nextId('track'),
    name: source.name || 'Untitled track',
    sourceKind: source.sourceKind || 'local',
    file: source.file || null,
    url: source.url || null,
    playlistId: source.playlistId || null,
    analysisStatus: source.analysisStatus || 'queued',
    analysisProgress: 0,
    analysisMessage: source.analysisMessage || 'Queued for analysis',
    duration: source.duration || 0,
    tempo: source.tempo || 0,
    keyClass: Number.isFinite(source.keyClass) ? source.keyClass : null,
    stemBuffers: source.stemBuffers || null,
    tempoConfidence: source.tempoConfidence || 0,
    errorMessage: source.errorMessage || '',
  };
}

export function sameTrackIdentity(left, right) {
  if (!left || !right) return false;
  if (left.id && right.id && left.id === right.id) return true;
  if (left.url && right.url && left.url === right.url) return true;
  if (left.file && right.file) {
    return left.file.name === right.file.name && left.file.size === right.file.size;
  }
  return false;
}

export function parseYouTubePlaylistUrl(value) {
  try {
    const url = new URL(value);
    const host = url.hostname.replace(/^www\./, '');
    if (host !== 'youtube.com' && host !== 'm.youtube.com' && host !== 'music.youtube.com') {
      return { playlistId: null, canonicalUrl: null };
    }
    const playlistId = url.searchParams.get('list');
    if (!playlistId) return { playlistId: null, canonicalUrl: null };
    return {
      playlistId,
      canonicalUrl: `https://www.youtube.com/playlist?list=${playlistId}`,
    };
  } catch (_error) {
    return { playlistId: null, canonicalUrl: null };
  }
}

export function createPendingYouTubeAdapter(url) {
  const parsed = parseYouTubePlaylistUrl(url);
  return {
    id: `youtube-${++adapterCounter}`,
    kind: 'youtube',
    label: parsed.playlistId ? `YouTube playlist ${parsed.playlistId}` : 'YouTube playlist',
    status: 'pending',
    url: parsed.canonicalUrl || url,
    playlistId: parsed.playlistId,
    tracks: [],
    message: 'Resolver not configured in-browser yet.',
  };
}

export function keyDistance(left, right) {
  if (!Number.isFinite(left) || !Number.isFinite(right)) return 6;
  const delta = Math.abs(left - right) % 12;
  return Math.min(delta, 12 - delta);
}

export function scoreCompatibility(left, right) {
  if (!left || !right) return -Infinity;
  if (left.analysisStatus !== 'ready' || right.analysisStatus !== 'ready') return -Infinity;

  const tempoDelta = Math.abs((left.tempo || 0) - (right.tempo || 0));
  const keyDelta = keyDistance(left.keyClass, right.keyClass);
  const durationMin = Math.min(left.duration || 0, right.duration || 0);
  const durationMax = Math.max(left.duration || 0, right.duration || 0, 1);
  const durationRatio = durationMin / durationMax;

  const tempoScore = clamp(1 - (tempoDelta / 24), 0, 1);
  const keyScore = clamp(1 - (keyDelta / 6), 0, 1);
  const durationScore = clamp(durationRatio, 0, 1);

  return Number((tempoScore * 60 + keyScore * 30 + durationScore * 10).toFixed(3));
}

export function rankCompatiblePairs(tracks) {
  const readyTracks = tracks.filter((track) => track.analysisStatus === 'ready');
  const pairs = [];

  for (let index = 0; index < readyTracks.length; index += 1) {
    for (let nested = index + 1; nested < readyTracks.length; nested += 1) {
      const left = readyTracks[index];
      const right = readyTracks[nested];
      const score = scoreCompatibility(left, right);
      if (!Number.isFinite(score) || score <= 0) continue;
      pairs.push({
        left,
        right,
        score,
        tempoDelta: Math.abs((left.tempo || 0) - (right.tempo || 0)),
        keyDelta: keyDistance(left.keyClass, right.keyClass),
      });
    }
  }

  pairs.sort((left, right) => {
    if (right.score !== left.score) return right.score - left.score;
    if (left.tempoDelta !== right.tempoDelta) return left.tempoDelta - right.tempoDelta;
    return left.keyDelta - right.keyDelta;
  });

  return pairs;
}

export function pickCompatiblePair(tracks) {
  return rankCompatiblePairs(tracks)[0] || null;
}
