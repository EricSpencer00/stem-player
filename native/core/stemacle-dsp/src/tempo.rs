//! Tempo / beat / downbeat estimation, ported from `estimateTempo` and helpers
//! in `app/index.html`. Onset envelope (smoothed RMS flux) → autocorrelation →
//! octave-folded BPM candidate selection → beat & measure offsets.

pub const BEATS_PER_MEASURE: usize = 4;
pub const BPM_MIN: f32 = 60.0;
pub const BPM_MAX: f32 = 240.0;
pub const BPM_FALLBACK: f32 = 120.0;
pub const BPM_PREFERRED_MIN: f32 = 80.0;
pub const BPM_PREFERRED_MAX: f32 = 180.0;
pub const TEMPO_MIN_CONFIDENCE: f32 = 0.04;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TempoEstimate {
    pub bpm: f32,
    pub confidence: f32,
    pub beat_offset: f32,
    pub measure_offset: f32,
    pub downbeat_confidence: f32,
}

impl TempoEstimate {
    fn fallback() -> Self {
        TempoEstimate {
            bpm: BPM_FALLBACK,
            confidence: 0.0,
            beat_offset: 0.0,
            measure_offset: 0.0,
            downbeat_confidence: 0.0,
        }
    }
}

#[inline]
pub fn clamp(v: f32, lo: f32, hi: f32) -> f32 {
    if v < lo {
        lo
    } else if v > hi {
        hi
    } else {
        v
    }
}

#[derive(Clone, Copy)]
struct Candidate {
    lag: usize,
    bpm: f32,
    score: f32,
}

fn choose_candidate(candidates: &[Candidate]) -> Candidate {
    let mut sorted: Vec<Candidate> = candidates
        .iter()
        .copied()
        .filter(|c| c.score.is_finite() && c.bpm.is_finite() && c.lag > 0)
        .collect();
    sorted.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap());
    let best = match sorted.first() {
        Some(c) => *c,
        None => Candidate { lag: 0, bpm: BPM_FALLBACK, score: 0.0 },
    };
    let preferred = sorted.iter().find(|c| {
        c.bpm >= BPM_PREFERRED_MIN && c.bpm <= BPM_PREFERRED_MAX && c.score >= best.score * 0.85
    });
    if (best.bpm < BPM_PREFERRED_MIN || best.bpm > BPM_PREFERRED_MAX) && preferred.is_some() {
        return *preferred.unwrap();
    }
    best
}

fn onset_score_at(onset: &[f32], frames: usize, offset: usize, stride: usize) -> f32 {
    let mut score = 0.0f32;
    let mut count = 0usize;
    let mut i = offset;
    while i < frames {
        score += onset[i];
        if i > 0 {
            score += onset[i - 1] * 0.5;
        }
        if i + 1 < frames {
            score += onset[i + 1] * 0.5;
        }
        count += 1;
        i += stride;
    }
    if count > 0 {
        score / count as f32
    } else {
        0.0
    }
}

fn estimate_measure_offset(
    onset: &[f32],
    frames: usize,
    beat_lag: usize,
    beat_offset_frame: usize,
    hop_sec: f32,
) -> (f32, f32) {
    let beat_offset = beat_offset_frame as f32 * hop_sec;
    let measure_lag = beat_lag * BEATS_PER_MEASURE;
    if measure_lag >= frames {
        return (beat_offset, 0.0);
    }
    let mut phases: Vec<(f32, f32)> = Vec::with_capacity(BEATS_PER_MEASURE);
    for phase in 0..BEATS_PER_MEASURE {
        let offset_frame = beat_offset_frame + phase * beat_lag;
        phases.push((
            offset_frame as f32 * hop_sec,
            onset_score_at(onset, frames, offset_frame, measure_lag),
        ));
    }
    phases.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
    let best = phases[0];
    let second = phases.get(1).copied().unwrap_or((0.0, 0.0));
    let total: f32 = phases.iter().map(|p| p.1).sum();
    let share = if total > 0.0 { best.1 / total } else { 0.0 };
    let confidence = if best.1 > 0.0 { (best.1 - second.1) / best.1 } else { 0.0 };
    if confidence >= 0.12 && share >= 0.36 {
        (best.0, confidence)
    } else {
        (beat_offset, confidence)
    }
}

/// Port of `estimateTempo(signal, sampleRate)`.
pub fn estimate_tempo(signal: &[f32], sample_rate: f32) -> TempoEstimate {
    if signal.is_empty() || sample_rate <= 0.0 {
        return TempoEstimate::fallback();
    }
    let min_samples = (sample_rate * 5.0) as usize;
    if signal.len() < min_samples {
        return TempoEstimate::fallback();
    }
    let frame = (sample_rate * 0.03).floor().max(1.0) as usize;
    let hop = (sample_rate * 0.01).floor().max(1.0) as usize;
    if signal.len() <= frame {
        return TempoEstimate::fallback();
    }
    let frames = (signal.len() - frame) / hop;
    if frames < 8 {
        return TempoEstimate::fallback();
    }

    let mut onset = vec![0.0f32; frames];
    let mut sm = 0.0f32;
    let mut prev_sm = 0.0f32;
    let mut total = 0.0f32;
    for i in 0..frames {
        let mut rms = 0.0f32;
        let base = i * hop;
        for j in 0..frame {
            let sample = signal.get(base + j).copied().unwrap_or(0.0);
            rms += sample * sample;
        }
        rms = (rms / frame as f32).sqrt();
        sm = sm * 0.84 + rms * 0.16;
        let v = sm - prev_sm;
        onset[i] = if v > 0.0 { v } else { 0.0 };
        prev_sm = sm;
        total += onset[i];
    }
    if total == 0.0 {
        return TempoEstimate::fallback();
    }

    let mean: f32 = onset.iter().sum::<f32>() / frames as f32;
    let energy: f32 = onset.iter().map(|&o| (o - mean) * (o - mean)).sum();
    if energy < 1e-10 {
        return TempoEstimate::fallback();
    }

    let hop_sec = hop as f32 / sample_rate;
    let min_lag = ((60.0 / BPM_MAX) / hop_sec).round().max(1.0) as usize;
    let max_lag = (((60.0 / BPM_MIN) / hop_sec).floor() as usize).max(min_lag + 1);
    let cap_lag = max_lag.min(frames.saturating_sub(2));
    if min_lag >= cap_lag {
        return TempoEstimate::fallback();
    }

    let mut best_score = f32::NEG_INFINITY;
    let mut best_lag: isize = -1;
    let mut candidates: Vec<Candidate> = Vec::new();
    for lag in min_lag..=cap_lag {
        let mut cross = 0.0f32;
        let mut a2 = 0.0f32;
        let mut b2 = 0.0f32;
        for i in lag..frames {
            let a = onset[i] - mean;
            let b = onset[i - lag] - mean;
            cross += a * b;
            a2 += a * a;
            b2 += b * b;
        }
        let score = cross / ((a2 * b2) + 1e-12).sqrt();
        let mut bpm = 60.0 / (lag as f32 * hop_sec);
        while bpm < BPM_MIN {
            bpm *= 2.0;
        }
        while bpm > BPM_MAX {
            bpm /= 2.0;
        }
        candidates.push(Candidate { lag, bpm, score });
        if score > best_score {
            best_score = score;
            best_lag = lag as isize;
        }
    }

    if !best_score.is_finite() || best_lag <= 0 || best_score < TEMPO_MIN_CONFIDENCE {
        return TempoEstimate::fallback();
    }

    let selected = choose_candidate(&candidates);
    let mut best_offset = 0usize;
    let mut best_offset_score = f32::NEG_INFINITY;
    for o in 0..selected.lag {
        let mut score = 0.0f32;
        let mut i = o;
        while i < frames {
            score += onset[i];
            i += selected.lag;
        }
        if score > best_offset_score {
            best_offset_score = score;
            best_offset = o;
        }
    }
    let beat_offset = best_offset as f32 * hop_sec;
    let (measure_offset, downbeat_confidence) =
        estimate_measure_offset(&onset, frames, selected.lag, best_offset, hop_sec);

    TempoEstimate {
        bpm: clamp(selected.bpm, BPM_MIN, BPM_MAX),
        confidence: selected.score,
        beat_offset,
        measure_offset,
        downbeat_confidence,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn click_track(bpm: f32, secs: f32, sr: f32) -> Vec<f32> {
        let n = (secs * sr) as usize;
        let mut sig = vec![0.0f32; n];
        let period = (60.0 / bpm * sr) as usize;
        let mut i = 0;
        while i < n {
            // a short decaying click
            for k in 0..200usize {
                if i + k < n {
                    sig[i + k] += (1.0 - k as f32 / 200.0) * (k as f32 * 0.4).sin();
                }
            }
            i += period;
        }
        sig
    }

    #[test]
    fn short_signal_falls_back() {
        let sig = vec![0.0f32; 1000];
        let est = estimate_tempo(&sig, 44100.0);
        assert_eq!(est.bpm, BPM_FALLBACK);
        assert_eq!(est.confidence, 0.0);
    }

    #[test]
    fn detects_120_bpm_click_track() {
        let sig = click_track(120.0, 12.0, 44100.0);
        let est = estimate_tempo(&sig, 44100.0);
        // octave-folded detection may land on 120 or a related fold; assert it
        // recovers a strong, plausible tempo near the true value.
        assert!(est.confidence > TEMPO_MIN_CONFIDENCE, "weak confidence {}", est.confidence);
        let near = (est.bpm - 120.0).abs() < 4.0
            || (est.bpm - 60.0).abs() < 4.0
            || (est.bpm - 240.0).abs() < 8.0;
        assert!(near, "unexpected bpm {}", est.bpm);
    }

    #[test]
    fn bpm_stays_in_range() {
        let sig = click_track(90.0, 12.0, 44100.0);
        let est = estimate_tempo(&sig, 44100.0);
        assert!(est.bpm >= BPM_MIN && est.bpm <= BPM_MAX);
    }
}
