import { STEMS } from './library.js';

export { STEMS };

const FFT_SIZE = 4096;
const HOP_SIZE = 1024;
const SR = 44100;
const TOT_BINS = FFT_SIZE / 2 + 1;
const MODEL_BINS = 1024;
const SEG_FRAMES = 512;
const BPM_MIN = 60;
const BPM_MAX = 240;
const BPM_FALLBACK = 120;
const BPM_PREFERRED_MIN = 80;
const BPM_PREFERRED_MAX = 180;
const TEMPO_MIN_CONFIDENCE = 0.04;
const DEFAULT_STEM_LEVEL = 0.82;
const DECODE_TIMEOUT_MS = 30000;
const MODEL_DOWNLOAD_IDLE_TIMEOUT_MS = 30000;
const HF = 'https://huggingface.co/csukuangfj/sherpa-onnx-spleeter-2stems/resolve/main/';

let sharedAudioContext = null;
let vocalsSession = null;
let accompanimentSession = null;
let modelLoadPromise = null;

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function wait(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function chooseTempoCandidate(candidates) {
  const sorted = [...candidates].sort((left, right) => right.score - left.score);
  const best = sorted[0];
  const preferred = sorted.find(
    (candidate) => candidate.bpm >= BPM_PREFERRED_MIN && candidate.bpm <= BPM_PREFERRED_MAX,
  );
  return preferred || best;
}

function tempoFallback() {
  return { bpm: BPM_FALLBACK, confidence: 0, beatOffset: 0, measureOffset: 0, offset: 0, downbeatConfidence: 0 };
}

function onsetScoreAt(onset, frames, offset, stride) {
  let score = 0;
  let count = 0;
  for (let index = offset; index < frames; index += stride) {
    score += onset[index] || 0;
    if (index > 0) score += (onset[index - 1] || 0) * 0.5;
    if (index + 1 < frames) score += (onset[index + 1] || 0) * 0.5;
    count += 1;
  }
  return count ? score / count : 0;
}

function estimateMeasureOffset(onset, frames, beatLag, beatOffsetFrame, hopSeconds) {
  const beatOffset = beatOffsetFrame * hopSeconds;
  const measureLag = beatLag * 4;
  if (measureLag >= frames) {
    return { offset: beatOffset, confidence: 0 };
  }

  const phases = [];
  for (let phase = 0; phase < 4; phase += 1) {
    const offsetFrame = beatOffsetFrame + (phase * beatLag);
    phases.push({
      offset: offsetFrame * hopSeconds,
      score: onsetScoreAt(onset, frames, offsetFrame, measureLag),
    });
  }
  phases.sort((left, right) => right.score - left.score);

  const best = phases[0];
  const second = phases[1] || { score: 0 };
  const total = phases.reduce((sum, phase) => sum + phase.score, 0);
  const share = best && total > 0 ? best.score / total : 0;
  const confidence = best && best.score > 0 ? (best.score - second.score) / best.score : 0;
  if (best && confidence >= 0.12 && share >= 0.36) {
    return { offset: best.offset, confidence };
  }
  return { offset: beatOffset, confidence };
}

export function estimateTempo(signal, sampleRate) {
  if (!signal || !signal.length || !sampleRate || sampleRate <= 0) return tempoFallback();
  if (signal.length < sampleRate * 5) return tempoFallback();

  const frame = Math.max(1, Math.floor(sampleRate * 0.03));
  const hop = Math.max(1, Math.floor(sampleRate * 0.01));
  const frames = Math.floor((signal.length - frame) / hop);
  if (frames < 8) return tempoFallback();

  const onset = new Float32Array(frames);
  let smoothed = 0;
  let previous = 0;
  let total = 0;
  for (let frameIndex = 0; frameIndex < frames; frameIndex += 1) {
    let rms = 0;
    const base = frameIndex * hop;
    for (let sampleIndex = 0; sampleIndex < frame; sampleIndex += 1) {
      const sample = signal[base + sampleIndex] || 0;
      rms += sample * sample;
    }
    rms = Math.sqrt(rms / frame);
    smoothed = smoothed * 0.84 + rms * 0.16;
    const delta = smoothed - previous;
    onset[frameIndex] = delta > 0 ? delta : 0;
    previous = smoothed;
    total += onset[frameIndex];
  }
  if (total === 0) return tempoFallback();

  let mean = 0;
  for (let index = 0; index < frames; index += 1) mean += onset[index];
  mean /= frames;

  let energy = 0;
  for (let index = 0; index < frames; index += 1) {
    const distance = onset[index] - mean;
    energy += distance * distance;
  }
  if (energy < 1e-10) return tempoFallback();

  const hopSeconds = hop / sampleRate;
  const minLag = Math.max(1, Math.round((60 / BPM_MAX) / hopSeconds));
  const maxLag = Math.max(minLag + 1, Math.floor((60 / BPM_MIN) / hopSeconds));
  const cappedLag = Math.min(maxLag, frames - 2);
  if (minLag >= cappedLag) return tempoFallback();

  let bestLag = -1;
  let bestScore = -Infinity;
  const candidates = [];
  for (let lag = minLag; lag <= cappedLag; lag += 1) {
    let cross = 0;
    let a2 = 0;
    let b2 = 0;
    for (let index = lag; index < frames; index += 1) {
      const a = onset[index] - mean;
      const b = onset[index - lag] - mean;
      cross += a * b;
      a2 += a * a;
      b2 += b * b;
    }
    const score = cross / Math.sqrt((a2 * b2) + 1e-12);
    let bpm = 60 / (lag * hopSeconds);
    while (bpm < BPM_MIN) bpm *= 2;
    while (bpm > BPM_MAX) bpm /= 2;
    candidates.push({ lag, bpm, score });
    if (score > bestScore) {
      bestScore = score;
      bestLag = lag;
    }
  }

  if (!Number.isFinite(bestScore) || bestLag <= 0 || bestScore < TEMPO_MIN_CONFIDENCE) {
    return tempoFallback();
  }

  const selected = chooseTempoCandidate(candidates);
  let bestOffset = 0;
  let bestOffsetScore = -Infinity;
  for (let offset = 0; offset < selected.lag; offset += 1) {
    let score = 0;
    for (let index = offset; index < frames; index += selected.lag) score += onset[index];
    if (score > bestOffsetScore) {
      bestOffsetScore = score;
      bestOffset = offset;
    }
  }

  const beatOffset = bestOffset * hopSeconds;
  const measureOffset = estimateMeasureOffset(onset, frames, selected.lag, bestOffset, hopSeconds);
  return {
    bpm: clamp(selected.bpm, BPM_MIN, BPM_MAX),
    confidence: selected.score,
    beatOffset,
    measureOffset: measureOffset.offset,
    offset: measureOffset.offset,
    downbeatConfidence: measureOffset.confidence,
  };
}

function hann(length) {
  const window = new Float32Array(length);
  for (let index = 0; index < length; index += 1) {
    window[index] = 0.5 - 0.5 * Math.cos((2 * Math.PI * index) / length);
  }
  return window;
}

function fftIP(real, imaginary) {
  const size = real.length;
  for (let index = 1, j = 0; index < size; index += 1) {
    let bit = size >> 1;
    while (j & bit) bit >>= 1, j ^= bit;
    j ^= bit;
    if (index < j) {
      [real[index], real[j]] = [real[j], real[index]];
      [imaginary[index], imaginary[j]] = [imaginary[j], imaginary[index]];
    }
  }

  for (let length = 2; length <= size; length <<= 1) {
    const angle = (-2 * Math.PI) / length;
    const wr0 = Math.cos(angle);
    const wi0 = Math.sin(angle);
    for (let offset = 0; offset < size; offset += length) {
      let wr = 1;
      let wi = 0;
      for (let index = 0; index < (length >> 1); index += 1) {
        const even = offset + index;
        const odd = even + (length >> 1);
        const tReal = (wr * real[odd]) - (wi * imaginary[odd]);
        const tImaginary = (wr * imaginary[odd]) + (wi * real[odd]);
        real[odd] = real[even] - tReal;
        imaginary[odd] = imaginary[even] - tImaginary;
        real[even] += tReal;
        imaginary[even] += tImaginary;
        const nextWr = (wr * wr0) - (wi * wi0);
        wi = (wr * wi0) + (wi * wr0);
        wr = nextWr;
      }
    }
  }
}

function ifftIP(real, imaginary) {
  for (let index = 0; index < imaginary.length; index += 1) imaginary[index] = -imaginary[index];
  fftIP(real, imaginary);
  const size = real.length;
  for (let index = 0; index < size; index += 1) {
    real[index] /= size;
    imaginary[index] = -imaginary[index] / size;
  }
}

export function estimateKeyClass(signal, sampleRate) {
  if (!signal?.length || !sampleRate) return 0;

  const frameSize = 4096;
  const hopSize = 2048;
  const window = hann(frameSize);
  const real = new Float32Array(frameSize);
  const imaginary = new Float32Array(frameSize);
  const chroma = new Float32Array(12);
  const usableLength = Math.min(signal.length, sampleRate * 24);

  for (let start = 0; start + frameSize < usableLength; start += hopSize) {
    for (let index = 0; index < frameSize; index += 1) {
      real[index] = (signal[start + index] || 0) * window[index];
      imaginary[index] = 0;
    }
    fftIP(real, imaginary);

    for (let bin = 1; bin < frameSize / 2; bin += 1) {
      const frequency = (bin * sampleRate) / frameSize;
      if (frequency < 60 || frequency > 1600) continue;
      const magnitude = Math.hypot(real[bin], imaginary[bin]);
      if (!Number.isFinite(magnitude) || magnitude <= 0) continue;
      const midi = 69 + (12 * Math.log2(frequency / 440));
      const pitchClass = ((Math.round(midi) % 12) + 12) % 12;
      chroma[pitchClass] += magnitude;
    }
  }

  let bestIndex = 0;
  let bestValue = -Infinity;
  for (let index = 0; index < chroma.length; index += 1) {
    if (chroma[index] > bestValue) {
      bestValue = chroma[index];
      bestIndex = index;
    }
  }
  return bestIndex;
}

function timeoutError(message) {
  const error = new Error(message);
  error.name = 'TimeoutError';
  return error;
}

function withTimeout(promise, timeoutMs, message) {
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) return promise;
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(timeoutError(message)), timeoutMs);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

function audioContextNeedsResume(context) {
  return !!context && (context.state === 'suspended' || context.state === 'interrupted') && typeof context.resume === 'function';
}

async function ensureAudioContextRunning(context, timeoutMs = 1000) {
  if (!context) return false;
  if (audioContextNeedsResume(context)) {
    await Promise.race([
      Promise.resolve().then(() => context.resume()).catch(() => {}),
      wait(timeoutMs),
    ]);
  }
  return context.state === 'running';
}

export function createAudioContext() {
  const ContextConstructor =
    globalThis.AudioContext ||
    globalThis.webkitAudioContext ||
    (typeof window !== 'undefined' ? (window.AudioContext || window.webkitAudioContext) : undefined);
  if (!ContextConstructor) throw new Error('Web Audio is not supported in this browser.');
  return new ContextConstructor({ sampleRate: SR });
}

function getSharedAudioContext() {
  sharedAudioContext ||= createAudioContext();
  return sharedAudioContext;
}

function decodeAudioDataWithTimeout(context, arrayBuffer, timeoutMs = DECODE_TIMEOUT_MS) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error(`Audio decoding timed out after ${Math.round(timeoutMs / 1000)} seconds.`));
    }, timeoutMs);

    Promise.resolve()
      .then(() => context.decodeAudioData(arrayBuffer.slice(0)))
      .then((decoded) => {
        clearTimeout(timer);
        resolve(decoded);
      })
      .catch((error) => {
        clearTimeout(timer);
        reject(error);
      });
  });
}

function modelFileName(url) {
  try {
    return new URL(url).pathname.split('/').pop() || 'model weights';
  } catch (_error) {
    return 'model weights';
  }
}

async function downloadModelFile(url, startPercent, endPercent, onStep, options = {}) {
  const timeoutMs = options.timeoutMs ?? MODEL_DOWNLOAD_IDLE_TIMEOUT_MS;
  const fetchFn = options.fetchFn || fetch;
  const controller = options.controller || (typeof AbortController !== 'undefined' ? new AbortController() : null);
  const requestOptions = controller ? { signal: controller.signal } : undefined;
  const name = modelFileName(url);
  let reader = null;

  try {
    const response = await withTimeout(
      fetchFn(url, requestOptions),
      timeoutMs,
      `Model download stalled while opening ${name}.`,
    );
    if (!response.ok) throw new Error(`HTTP ${response.status}`);

    const total = Number(response.headers.get('content-length')) || 0;
    if (!response.body || !response.body.getReader) {
      if (typeof response.arrayBuffer === 'function') {
        return withTimeout(
          response.arrayBuffer(),
          timeoutMs,
          `Model download stalled while reading ${name}.`,
        );
      }
      throw new Error('Streaming model downloads are not supported in this browser.');
    }

    reader = response.body.getReader();
    const chunks = [];
    let loaded = 0;
    let next = startPercent;
    while (true) {
      const { done, value } = await withTimeout(
        reader.read(),
        timeoutMs,
        `Model download stalled while reading ${name}.`,
      );
      if (done) break;
      if (!value) continue;
      chunks.push(value);
      loaded += value.length || value.byteLength || 0;
      if (total) {
        const percent = startPercent + ((endPercent - startPercent) * loaded / total);
        if (percent >= next || percent >= endPercent) {
          next = percent + 1.5;
          await onStep?.(percent, 'Downloading separation models...');
        }
      }
    }

    const bytes = new Uint8Array(loaded);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length || chunk.byteLength || 0;
    }
    return bytes.buffer;
  } catch (error) {
    if (error?.name === 'TimeoutError') {
      try { controller?.abort(); } catch (_ignored) {}
      try { await reader?.cancel?.(); } catch (_ignored) {}
    }
    throw error;
  }
}

async function loadModels(onStep) {
  if (vocalsSession && accompanimentSession) return;
  if (modelLoadPromise) {
    await modelLoadPromise;
    return;
  }

  modelLoadPromise = (async () => {
    if (!globalThis.ort?.InferenceSession) {
      throw new Error('ONNX Runtime Web is not available.');
    }
    globalThis.ort.env.wasm.wasmPaths = 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.17.3/dist/';
    await onStep?.(0, 'Opening vocals model...');
    const vocals = await downloadModelFile(`${HF}vocals.onnx`, 0, 42, onStep);
    await onStep?.(44, 'Preparing vocals model...');
    vocalsSession = await globalThis.ort.InferenceSession.create(vocals, { executionProviders: ['wasm'] });
    await onStep?.(52, 'Opening accompaniment model...');
    const accompaniment = await downloadModelFile(`${HF}accompaniment.onnx`, 52, 92, onStep);
    await onStep?.(94, 'Preparing accompaniment model...');
    accompanimentSession = await globalThis.ort.InferenceSession.create(accompaniment, { executionProviders: ['wasm'] });
    await onStep?.(100, 'Separation models ready.');
  })();

  try {
    await modelLoadPromise;
  } finally {
    modelLoadPromise = null;
  }
}

async function stft(signal, window, onProgress) {
  const frameCount = Math.floor((signal.length - FFT_SIZE) / HOP_SIZE) + 1;
  const realRows = [];
  const imaginaryRows = [];
  const frameReal = new Float32Array(FFT_SIZE);
  const frameImaginary = new Float32Array(FFT_SIZE);
  const stride = Math.max(1, Math.floor(frameCount / 24));

  for (let frameIndex = 0; frameIndex < frameCount; frameIndex += 1) {
    const start = frameIndex * HOP_SIZE;
    for (let index = 0; index < FFT_SIZE; index += 1) {
      frameReal[index] = (start + index < signal.length ? signal[start + index] : 0) * window[index];
      frameImaginary[index] = 0;
    }
    fftIP(frameReal, frameImaginary);
    realRows.push(new Float32Array(frameReal.subarray(0, TOT_BINS)));
    imaginaryRows.push(new Float32Array(frameImaginary.subarray(0, TOT_BINS)));
    if (onProgress && (frameIndex % stride === 0 || frameIndex === frameCount - 1)) {
      await onProgress((frameIndex + 1) / frameCount);
    }
  }

  return { realRows, imaginaryRows, frameCount };
}

async function buildMagnitude(spectrogram, onProgress) {
  const magnitude = [];
  const stride = Math.max(1, Math.floor(spectrogram.frameCount / 24));
  for (let frameIndex = 0; frameIndex < spectrogram.frameCount; frameIndex += 1) {
    const row = new Float32Array(MODEL_BINS);
    for (let bin = 0; bin < MODEL_BINS; bin += 1) {
      row[bin] = Math.hypot(spectrogram.realRows[frameIndex][bin], spectrogram.imaginaryRows[frameIndex][bin]);
    }
    magnitude.push(row);
    if (onProgress && (frameIndex % stride === 0 || frameIndex === spectrogram.frameCount - 1)) {
      await onProgress((frameIndex + 1) / spectrogram.frameCount);
    }
  }
  return magnitude;
}

async function istft(realRows, imaginaryRows, frameCount, window, onProgress) {
  const length = ((frameCount - 1) * HOP_SIZE) + FFT_SIZE;
  const output = new Float32Array(length);
  const normalizer = new Float32Array(length);
  const frameReal = new Float32Array(FFT_SIZE);
  const frameImaginary = new Float32Array(FFT_SIZE);
  const stride = Math.max(1, Math.floor(frameCount / 24));

  for (let frameIndex = 0; frameIndex < frameCount; frameIndex += 1) {
    for (let bin = 0; bin < TOT_BINS; bin += 1) {
      frameReal[bin] = realRows[frameIndex][bin];
      frameImaginary[bin] = imaginaryRows[frameIndex][bin];
    }
    for (let bin = 1; bin < TOT_BINS - 1; bin += 1) {
      frameReal[FFT_SIZE - bin] = frameReal[bin];
      frameImaginary[FFT_SIZE - bin] = -frameImaginary[bin];
    }
    ifftIP(frameReal, frameImaginary);
    const start = frameIndex * HOP_SIZE;
    for (let index = 0; index < FFT_SIZE; index += 1) {
      output[start + index] += frameReal[index] * window[index];
      normalizer[start + index] += window[index] * window[index];
    }
    if (onProgress && (frameIndex % stride === 0 || frameIndex === frameCount - 1)) {
      await onProgress((frameIndex + 1) / frameCount);
    }
  }

  for (let index = 0; index < length; index += 1) {
    if (normalizer[index] > 1e-8) output[index] /= normalizer[index];
  }
  return output;
}

async function medFilter(spec, frameCount, binCount, length, axis, onProgress) {
  const output = new Float32Array(frameCount * binCount);
  const column = new Float32Array(length);
  const half = length >> 1;

  if (axis === 'horizontal') {
    const stride = Math.max(1, Math.floor(binCount / 18));
    for (let bin = 0; bin < binCount; bin += 1) {
      for (let frameIndex = 0; frameIndex < frameCount; frameIndex += 1) {
        for (let index = 0; index < length; index += 1) {
          const frame = frameIndex - half + index;
          column[index] = frame >= 0 && frame < frameCount ? spec[(frame * binCount) + bin] : 0;
        }
        column.sort();
        output[(frameIndex * binCount) + bin] = column[half];
      }
      if (onProgress && (bin % stride === 0 || bin === binCount - 1)) {
        await onProgress((bin + 1) / binCount);
      }
    }
  } else {
    const stride = Math.max(1, Math.floor(frameCount / 18));
    for (let frameIndex = 0; frameIndex < frameCount; frameIndex += 1) {
      for (let bin = 0; bin < binCount; bin += 1) {
        for (let index = 0; index < length; index += 1) {
          const sampleBin = bin - half + index;
          column[index] = sampleBin >= 0 && sampleBin < binCount ? spec[(frameIndex * binCount) + sampleBin] : 0;
        }
        column.sort();
        output[(frameIndex * binCount) + bin] = column[half];
      }
      if (onProgress && (frameIndex % stride === 0 || frameIndex === frameCount - 1)) {
        await onProgress((frameIndex + 1) / frameCount);
      }
    }
  }

  return output;
}

async function hpss(realRows, imaginaryRows, frameCount, binCount, onProgress) {
  const magnitude = new Float32Array(frameCount * binCount);
  const stride = Math.max(1, Math.floor(frameCount / 18));

  for (let frameIndex = 0; frameIndex < frameCount; frameIndex += 1) {
    for (let bin = 0; bin < binCount; bin += 1) {
      magnitude[(frameIndex * binCount) + bin] = (
        realRows[frameIndex][bin] ** 2
      ) + (
        imaginaryRows[frameIndex][bin] ** 2
      );
    }
    if (frameIndex % stride === 0 || frameIndex === frameCount - 1) {
      await onProgress?.(0.12 * (frameIndex + 1) / frameCount, 'Measuring rhythmic energy...');
    }
  }

  const harmonic = await medFilter(magnitude, frameCount, binCount, 17, 'horizontal', (progress) => onProgress?.(0.12 + (0.38 * progress), 'Finding sustained layers...'));
  const percussive = await medFilter(magnitude, frameCount, binCount, 17, 'vertical', (progress) => onProgress?.(0.50 + (0.38 * progress), 'Finding drum transients...'));

  const harmonicReal = realRows.map(() => new Float32Array(binCount));
  const harmonicImaginary = imaginaryRows.map(() => new Float32Array(binCount));
  const percussiveReal = realRows.map(() => new Float32Array(binCount));
  const percussiveImaginary = imaginaryRows.map(() => new Float32Array(binCount));

  for (let frameIndex = 0; frameIndex < frameCount; frameIndex += 1) {
    for (let bin = 0; bin < binCount; bin += 1) {
      const harmonicValue = harmonic[(frameIndex * binCount) + bin];
      const percussiveValue = percussive[(frameIndex * binCount) + bin];
      const denominator = harmonicValue + percussiveValue + 1e-8;
      harmonicReal[frameIndex][bin] = realRows[frameIndex][bin] * harmonicValue / denominator;
      harmonicImaginary[frameIndex][bin] = imaginaryRows[frameIndex][bin] * harmonicValue / denominator;
      percussiveReal[frameIndex][bin] = realRows[frameIndex][bin] * percussiveValue / denominator;
      percussiveImaginary[frameIndex][bin] = imaginaryRows[frameIndex][bin] * percussiveValue / denominator;
    }
    if (frameIndex % stride === 0 || frameIndex === frameCount - 1) {
      await onProgress?.(0.88 + (0.12 * (frameIndex + 1) / frameCount), 'Finishing drum split...');
    }
  }

  return { harmonicReal, harmonicImaginary, percussiveReal, percussiveImaginary };
}

function lowPass(realRows, imaginaryRows, frameCount, binCount, cutoffHz) {
  const cutoff = Math.round(cutoffHz / (SR / FFT_SIZE));
  const lowReal = realRows.map((row) => new Float32Array(row));
  const lowImaginary = imaginaryRows.map((row) => new Float32Array(row));
  const highReal = realRows.map((row) => new Float32Array(row));
  const highImaginary = imaginaryRows.map((row) => new Float32Array(row));

  for (let frameIndex = 0; frameIndex < frameCount; frameIndex += 1) {
    for (let bin = cutoff; bin < binCount; bin += 1) {
      lowReal[frameIndex][bin] = 0;
      lowImaginary[frameIndex][bin] = 0;
    }
    for (let bin = 0; bin < cutoff; bin += 1) {
      highReal[frameIndex][bin] = 0;
      highImaginary[frameIndex][bin] = 0;
    }
  }

  return { lowReal, lowImaginary, highReal, highImaginary };
}

async function separateDecodedAudio(decoded, onProgress) {
  const leftSignal = decoded.getChannelData(0);
  const rightSignal = decoded.numberOfChannels > 1 ? decoded.getChannelData(1) : leftSignal;
  const window = hann(FFT_SIZE);
  const leftSpectrogram = await stft(leftSignal, window, (progress) => onProgress?.(10 + (12 * progress), 'Computing left spectrogram...'));
  const rightSpectrogram = await stft(rightSignal, window, (progress) => onProgress?.(22 + (12 * progress), 'Computing right spectrogram...'));
  const frameCount = leftSpectrogram.frameCount;

  const leftMagnitude = await buildMagnitude(leftSpectrogram, (progress) => onProgress?.(34 + (4 * progress), 'Measuring left channel...'));
  const rightMagnitude = await buildMagnitude(rightSpectrogram, (progress) => onProgress?.(38 + (4 * progress), 'Measuring right channel...'));
  const vocalMask = new Float32Array(frameCount * MODEL_BINS);

  if (vocalsSession && accompanimentSession) {
    const segmentCount = Math.ceil(frameCount / SEG_FRAMES);
    const segmentData = new Float32Array(2 * SEG_FRAMES * MODEL_BINS);
    for (let segment = 0; segment < segmentCount; segment += 1) {
      segmentData.fill(0);
      for (let frameIndex = 0; frameIndex < SEG_FRAMES; frameIndex += 1) {
        const frame = (segment * SEG_FRAMES) + frameIndex;
        if (frame >= frameCount) break;
        const leftBase = frameIndex * MODEL_BINS;
        const rightBase = ((SEG_FRAMES + frameIndex) * MODEL_BINS);
        for (let bin = 0; bin < MODEL_BINS; bin += 1) {
          segmentData[leftBase + bin] = leftMagnitude[frame][bin];
          segmentData[rightBase + bin] = rightMagnitude[frame][bin];
        }
      }

      const vocalsOutput = (await vocalsSession.run({
        x: new globalThis.ort.Tensor('float32', segmentData, [2, 1, SEG_FRAMES, MODEL_BINS]),
      })).y.data;
      const accompanimentOutput = (await accompanimentSession.run({
        x: new globalThis.ort.Tensor('float32', segmentData.slice(), [2, 1, SEG_FRAMES, MODEL_BINS]),
      })).y.data;

      for (let frameIndex = 0; frameIndex < SEG_FRAMES; frameIndex += 1) {
        const frame = (segment * SEG_FRAMES) + frameIndex;
        if (frame >= frameCount) break;
        const leftBase = frameIndex * MODEL_BINS;
        const rightBase = ((SEG_FRAMES + frameIndex) * MODEL_BINS);
        for (let bin = 0; bin < MODEL_BINS; bin += 1) {
          const vocalPower = (vocalsOutput[leftBase + bin] ** 2) + (vocalsOutput[rightBase + bin] ** 2);
          const accompanimentPower = (accompanimentOutput[leftBase + bin] ** 2) + (accompanimentOutput[rightBase + bin] ** 2);
          vocalMask[(frame * MODEL_BINS) + bin] = vocalPower / (vocalPower + accompanimentPower + 1e-10);
        }
      }
      await onProgress?.(44 + (24 * (segment + 1) / segmentCount), `Separating vocals ${segment + 1}/${segmentCount}...`);
    }
  } else {
    const stride = Math.max(1, Math.floor(frameCount / 24));
    for (let frame = 0; frame < frameCount; frame += 1) {
      for (let bin = 0; bin < MODEL_BINS; bin += 1) {
        const leftMagnitudeValue = leftMagnitude[frame][bin];
        const rightMagnitudeValue = rightMagnitude[frame][bin];
        vocalMask[(frame * MODEL_BINS) + bin] = Math.min(leftMagnitudeValue, rightMagnitudeValue) / ((0.5 * (leftMagnitudeValue + rightMagnitudeValue)) + 1e-8);
      }
      if (frame % stride === 0 || frame === frameCount - 1) {
        await onProgress?.(44 + (24 * (frame + 1) / frameCount), 'Separating vocals with browser DSP...');
      }
    }
  }

  const vocalsReal = leftSpectrogram.realRows.map(() => new Float32Array(TOT_BINS));
  const vocalsImaginary = leftSpectrogram.imaginaryRows.map(() => new Float32Array(TOT_BINS));
  const accompanimentReal = leftSpectrogram.realRows.map(() => new Float32Array(TOT_BINS));
  const accompanimentImaginary = leftSpectrogram.imaginaryRows.map(() => new Float32Array(TOT_BINS));
  const maskStride = Math.max(1, Math.floor(frameCount / 24));

  for (let frame = 0; frame < frameCount; frame += 1) {
    for (let bin = 0; bin < TOT_BINS; bin += 1) {
      const mixedReal = (leftSpectrogram.realRows[frame][bin] + rightSpectrogram.realRows[frame][bin]) * 0.5;
      const mixedImaginary = (leftSpectrogram.imaginaryRows[frame][bin] + rightSpectrogram.imaginaryRows[frame][bin]) * 0.5;
      const mask = bin < MODEL_BINS ? vocalMask[(frame * MODEL_BINS) + bin] : 0;
      vocalsReal[frame][bin] = mixedReal * mask;
      vocalsImaginary[frame][bin] = mixedImaginary * mask;
      accompanimentReal[frame][bin] = mixedReal * (1 - mask);
      accompanimentImaginary[frame][bin] = mixedImaginary * (1 - mask);
    }
    if (frame % maskStride === 0 || frame === frameCount - 1) {
      await onProgress?.(70 + (4 * (frame + 1) / frameCount), 'Applying soft masks...');
    }
  }

  const hpssResult = await hpss(accompanimentReal, accompanimentImaginary, frameCount, TOT_BINS, (progress, message) => onProgress?.(74 + (8 * progress), message));
  const lowPassResult = lowPass(hpssResult.harmonicReal, hpssResult.harmonicImaginary, frameCount, TOT_BINS, 300);
  const context = getSharedAudioContext();
  const duration = decoded.duration;

  async function toAudioBuffer(realRows, imaginaryRows, label, startPercent, endPercent) {
    const signal = await istft(realRows, imaginaryRows, frameCount, window, (progress) => onProgress?.(startPercent + ((endPercent - startPercent) * progress), `Synthesizing ${label}...`));
    const audioBuffer = context.createBuffer(1, Math.min(signal.length, Math.ceil(duration * SR)), SR);
    audioBuffer.copyToChannel(signal.subarray(0, audioBuffer.length), 0);
    return audioBuffer;
  }

  return {
    vocals: await toAudioBuffer(vocalsReal, vocalsImaginary, 'vocals', 86, 90),
    drums: await toAudioBuffer(hpssResult.percussiveReal, hpssResult.percussiveImaginary, 'drums', 90, 94),
    bass: await toAudioBuffer(lowPassResult.lowReal, lowPassResult.lowImaginary, 'bass', 94, 97),
    melody: await toAudioBuffer(lowPassResult.highReal, lowPassResult.highImaginary, 'melody', 97, 100),
  };
}

async function loadAudioBytesFromSource(source, onProgress) {
  if (source.file) {
    await onProgress?.(2, 'Reading local file...');
    return source.file.arrayBuffer();
  }
  if (source.url) {
    await onProgress?.(2, 'Fetching sample audio...');
    const response = await fetch(new URL(source.url, import.meta.url));
    if (!response.ok) throw new Error(`Unable to fetch audio source (${response.status}).`);
    return response.arrayBuffer();
  }
  throw new Error('Track source is missing audio input.');
}

export async function analyzeTrackSource(source, onProgress) {
  const report = async (percent, message) => onProgress?.({ percent, message });
  const context = getSharedAudioContext();
  await report(0, 'Preparing track analysis...');
  await ensureAudioContextRunning(context);
  const audioBytes = await loadAudioBytesFromSource(source, report);
  await report(8, 'Decoding audio...');
  const decoded = await decodeAudioDataWithTimeout(context, audioBytes, DECODE_TIMEOUT_MS);

  const leftSignal = decoded.getChannelData(0);
  const rightSignal = decoded.numberOfChannels > 1 ? decoded.getChannelData(1) : leftSignal;
  const mono = new Float32Array(leftSignal.length);
  for (let index = 0; index < leftSignal.length; index += 1) {
    mono[index] = (leftSignal[index] + rightSignal[index]) * 0.5;
  }

  const tempo = estimateTempo(mono, decoded.sampleRate || SR);
  const keyClass = estimateKeyClass(mono, decoded.sampleRate || SR);
  await report(10, 'Loading separation models...');
  try {
    await loadModels((percent, message) => report(percent, message));
  } catch (_error) {
    vocalsSession = null;
    accompanimentSession = null;
    await report(42, 'Model load failed. Falling back to browser DSP.');
  }
  const stemBuffers = await separateDecodedAudio(decoded, (percent, message) => report(percent, message));

  return {
    duration: decoded.duration,
    tempo: tempo.bpm || BPM_FALLBACK,
    keyClass,
    tempoConfidence: tempo.confidence || 0,
    stemBuffers,
  };
}

export function computeDeckMixGains(value) {
  const crossfade = clamp(value, 0, 1);
  return {
    left: Number((1 - crossfade).toFixed(4)),
    right: Number(crossfade.toFixed(4)),
  };
}

function makeDefaultStemLevels() {
  return STEMS.reduce((levels, stem) => ({ ...levels, [stem]: DEFAULT_STEM_LEVEL }), {});
}

function stopSourceMap(sourceMap) {
  Object.values(sourceMap).forEach((source) => {
    try {
      source?.stop?.();
    } catch (_error) {}
  });
}

export function createDeckEngine() {
  const state = {
    pair: null,
    playing: false,
    pauseOffset: 0,
    startTime: 0,
    crossfade: 0.5,
    deckRates: { left: 1, right: 1 },
    stemLevels: {
      left: makeDefaultStemLevels(),
      right: makeDefaultStemLevels(),
    },
    masters: null,
    stemGains: null,
    sources: { left: {}, right: {} },
  };

  function ensureSignalChain() {
    const context = getSharedAudioContext();
    if (state.masters && state.stemGains) return context;

    const leftMaster = context.createGain();
    const rightMaster = context.createGain();
    leftMaster.connect(context.destination);
    rightMaster.connect(context.destination);

    const stemGains = {
      left: {},
      right: {},
    };
    for (const side of ['left', 'right']) {
      for (const stem of STEMS) {
        const gain = context.createGain();
        gain.gain.value = state.stemLevels[side][stem];
        gain.connect(side === 'left' ? leftMaster : rightMaster);
        stemGains[side][stem] = gain;
      }
    }

    state.masters = { left: leftMaster, right: rightMaster };
    state.stemGains = stemGains;
    applyMixGains();
    return context;
  }

  function deckRateFor(track, targetTempo) {
    if (!track?.tempo || !targetTempo) return 1;
    const raw = targetTempo / track.tempo;
    if (!Number.isFinite(raw)) return 1;
    return clamp(raw, 0.94, 1.06);
  }

  function recomputeDeckRates() {
    if (!state.pair) {
      state.deckRates = { left: 1, right: 1 };
      return;
    }
    const targetTempo = (state.pair.left.tempo + state.pair.right.tempo) / 2;
    state.deckRates = {
      left: deckRateFor(state.pair.left, targetTempo),
      right: deckRateFor(state.pair.right, targetTempo),
    };
  }

  function applyMixGains() {
    if (!state.masters) return;
    const gains = computeDeckMixGains(state.crossfade);
    state.masters.left.gain.value = gains.left;
    state.masters.right.gain.value = gains.right;
  }

  function applyStemLevels(side) {
    if (!state.stemGains) return;
    for (const stem of STEMS) {
      state.stemGains[side][stem].gain.value = state.stemLevels[side][stem];
    }
  }

  function buildSourcesForSide(side) {
    const context = getSharedAudioContext();
    const track = state.pair?.[side];
    if (!track?.stemBuffers || !state.stemGains) return;

    const rate = state.deckRates[side];
    for (const stem of STEMS) {
      const source = context.createBufferSource();
      source.buffer = track.stemBuffers[stem];
      source.playbackRate.value = rate;
      source.connect(state.stemGains[side][stem]);
      source.start(0, state.pauseOffset * rate);
      state.sources[side][stem] = source;
    }
  }

  async function play() {
    if (!state.pair) return false;
    const context = ensureSignalChain();
    const running = await ensureAudioContextRunning(context, 1500);
    if (!running) return false;
    stopSourceMap(state.sources.left);
    stopSourceMap(state.sources.right);
    state.sources = { left: {}, right: {} };
    state.startTime = context.currentTime - state.pauseOffset;
    state.playing = true;
    buildSourcesForSide('left');
    buildSourcesForSide('right');
    return true;
  }

  function pause() {
    if (!state.playing) return;
    state.pauseOffset = currentTime();
    stopSourceMap(state.sources.left);
    stopSourceMap(state.sources.right);
    state.sources = { left: {}, right: {} };
    state.playing = false;
  }

  function stop() {
    stopSourceMap(state.sources.left);
    stopSourceMap(state.sources.right);
    state.sources = { left: {}, right: {} };
    state.pauseOffset = 0;
    state.playing = false;
  }

  function currentTime() {
    if (!state.playing) return state.pauseOffset;
    return getSharedAudioContext().currentTime - state.startTime;
  }

  function pairDuration() {
    if (!state.pair) return 0;
    const leftDuration = (state.pair.left.duration || 0) / state.deckRates.left;
    const rightDuration = (state.pair.right.duration || 0) / state.deckRates.right;
    return Math.min(leftDuration || 0, rightDuration || 0);
  }

  function setPair(pair) {
    stop();
    state.pair = pair;
    recomputeDeckRates();
  }

  function setCrossfade(value) {
    state.crossfade = clamp(value, 0, 1);
    applyMixGains();
  }

  function setStemLevel(side, stem, value) {
    state.stemLevels[side][stem] = clamp(value, 0, 1);
    applyStemLevels(side);
  }

  function getSnapshot() {
    return {
      pair: state.pair,
      playing: state.playing,
      crossfade: state.crossfade,
      pauseOffset: state.pauseOffset,
      deckRates: { ...state.deckRates },
      duration: pairDuration(),
      stemLevels: {
        left: { ...state.stemLevels.left },
        right: { ...state.stemLevels.right },
      },
    };
  }

  return {
    play,
    pause,
    stop,
    setPair,
    setCrossfade,
    setStemLevel,
    currentTime,
    isPlaying: () => state.playing,
    duration: pairDuration,
    getSnapshot,
  };
}
