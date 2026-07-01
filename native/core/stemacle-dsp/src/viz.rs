//! Visualization helpers: downsampled spectrogram + waveform envelope used by
//! the native per-stem lanes and the player's radial spectrum (the same data
//! the web gold master draws under each stem).

use crate::fft::fft_ip;
use crate::stft::{frame_count, hann, FFT_SIZE, HOP_SIZE, TOT_BINS};

/// Compute a `cols × rows` log-magnitude spectrogram for visualization, values
/// normalized to `0..1`. Columns are time, rows are frequency (row 0 = low).
///
/// **Streaming**: one FFT frame is computed at a time and accumulated straight
/// into the `cols × rows` grid, so memory is `O(cols*rows + FFT_SIZE)` — it never
/// materializes the full STFT. That is what makes the rich colored spectrogram
/// safe to render on iOS for a multi-minute track (the old full-STFT version
/// allocated ~200 MB per stem and was jetsam-killed). Empty/short input → zeros.
pub fn spectrogram(samples: &[f32], cols: usize, rows: usize) -> Vec<f32> {
    let mut out = vec![0.0f32; cols * rows];
    if cols == 0 || rows == 0 || samples.len() < FFT_SIZE {
        return out;
    }
    let frames = frame_count(samples.len());
    if frames == 0 {
        return out;
    }
    // Use the lower ~3/4 of bins (the visually interesting band).
    let used_bins = (TOT_BINS * 3 / 4).max(rows);
    let win = hann(FFT_SIZE);

    // Per-cell running magnitude sum + sample count, filled frame by frame.
    let mut acc = vec![0.0f32; cols * rows];
    let mut cnt = vec![0u32; cols * rows];
    let mut fr = vec![0.0f32; FFT_SIZE];
    let mut fi = vec![0.0f32; FFT_SIZE];

    // Decimate frames so the FFT count is bounded (~8 per column) regardless of
    // track length — the grid only has `cols` columns, so processing every frame
    // of a 10-minute track would burn compute for detail that averages away.
    let stride = (frames / (cols * 8)).max(1);

    for f in (0..frames).step_by(stride) {
        let s = f * HOP_SIZE;
        for i in 0..FFT_SIZE {
            let sample = if s + i < samples.len() { samples[s + i] } else { 0.0 };
            fr[i] = sample * win[i];
            fi[i] = 0.0;
        }
        fft_ip(&mut fr, &mut fi);
        // Which column this frame lands in (inverse of the old col→frame range).
        let c = (f * cols / frames).min(cols - 1);
        for r in 0..rows {
            let b0 = r * used_bins / rows;
            let b1 = (((r + 1) * used_bins / rows).max(b0 + 1)).min(used_bins);
            let mut sum = 0.0f32;
            for b in b0..b1 {
                sum += (fr[b] * fr[b] + fi[b] * fi[b]).sqrt();
            }
            let idx = c * rows + r;
            acc[idx] += sum / (b1 - b0) as f32;
            cnt[idx] += 1;
        }
    }

    // Convert to dB, tracking the peak for normalization.
    let mut max_db = f32::NEG_INFINITY;
    for idx in 0..cols * rows {
        let mag = if cnt[idx] > 0 { acc[idx] / cnt[idx] as f32 } else { 0.0 };
        let db = 20.0 * (mag + 1e-6).log10();
        out[idx] = db;
        if db > max_db {
            max_db = db;
        }
    }
    // Normalize to 0..1 over a ~70 dB window below the peak. Empty columns (no
    // frames) keep their -120 dB floor and clamp to 0.
    let floor = max_db - 70.0;
    for v in out.iter_mut() {
        *v = ((*v - floor) / (max_db - floor).max(1e-6)).clamp(0.0, 1.0);
    }
    out
}

/// Compute a `cols`-bucket peak waveform envelope in `0..1` (handy for a
/// lightweight lane or scrub track).
pub fn waveform_envelope(samples: &[f32], cols: usize) -> Vec<f32> {
    let mut out = vec![0.0f32; cols];
    if cols == 0 || samples.is_empty() {
        return out;
    }
    for c in 0..cols {
        let s0 = c * samples.len() / cols;
        let s1 = (((c + 1) * samples.len() / cols).max(s0 + 1)).min(samples.len());
        let mut peak = 0.0f32;
        for &x in &samples[s0..s1] {
            peak = peak.max(x.abs());
        }
        out[c] = peak.clamp(0.0, 1.0);
    }
    out
}

/// Compute a `cols`-bucket peak+RMS waveform envelope, interleaved as
/// `[peak_0, rms_0, peak_1, rms_1, …]`, each clamped to `0..1`.
///
/// This is the native equivalent of the web gold master's per-pixel `drawWave`
/// (a faint RMS *body* with darker peak *tips*). Precomputing at a fixed high
/// column count lets a zoomed scroll window stay smooth instead of showing a
/// handful of fat bars — the "waveform doesn't flow" gap on iOS. `rms <= peak`
/// per column by construction.
pub fn waveform_peaks_rms(samples: &[f32], cols: usize) -> Vec<f32> {
    let mut out = vec![0.0f32; cols * 2];
    if cols == 0 || samples.is_empty() {
        return out;
    }
    for c in 0..cols {
        let s0 = c * samples.len() / cols;
        let s1 = (((c + 1) * samples.len() / cols).max(s0 + 1)).min(samples.len());
        let n = (s1 - s0).max(1);
        let mut peak = 0.0f32;
        let mut sum_sq = 0.0f32;
        for &x in &samples[s0..s1] {
            let a = x.abs();
            if a > peak {
                peak = a;
            }
            sum_sq += x * x;
        }
        let rms = (sum_sq / n as f32).sqrt();
        out[c * 2] = peak.clamp(0.0, 1.0);
        out[c * 2 + 1] = rms.clamp(0.0, 1.0);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::stft::{HOP_SIZE, SR};

    fn tone(freq: f32, len: usize) -> Vec<f32> {
        (0..len)
            .map(|i| (2.0 * std::f32::consts::PI * freq * i as f32 / SR as f32).sin() * 0.5)
            .collect()
    }

    #[test]
    fn spectrogram_has_requested_shape_and_range() {
        let sig = tone(440.0, FFT_SIZE + 40 * HOP_SIZE);
        let grid = spectrogram(&sig, 64, 32);
        assert_eq!(grid.len(), 64 * 32);
        assert!(grid.iter().all(|&v| (0.0..=1.0).contains(&v)));
        assert!(grid.iter().cloned().fold(0.0f32, f32::max) > 0.5, "should have energy");
    }

    #[test]
    fn low_tone_energy_sits_low_in_the_grid() {
        // A low tone should light up low rows more than high rows.
        let sig = tone(120.0, FFT_SIZE + 60 * HOP_SIZE);
        let (cols, rows) = (32usize, 32usize);
        let grid = spectrogram(&sig, cols, rows);
        let row_sum = |r: usize| (0..cols).map(|c| grid[c * rows + r]).sum::<f32>();
        let low: f32 = (0..rows / 4).map(row_sum).sum();
        let high: f32 = (3 * rows / 4..rows).map(row_sum).sum();
        assert!(low > high, "low band {low} should exceed high band {high}");
    }

    #[test]
    fn empty_input_is_zeros() {
        assert!(spectrogram(&[], 10, 10).iter().all(|&v| v == 0.0));
        assert!(waveform_envelope(&[], 10).iter().all(|&v| v == 0.0));
        assert!(waveform_peaks_rms(&[], 10).iter().all(|&v| v == 0.0));
    }

    #[test]
    fn peaks_rms_shape_and_ordering() {
        let sig = tone(220.0, FFT_SIZE + 40 * HOP_SIZE);
        let cols = 128;
        let env = waveform_peaks_rms(&sig, cols);
        assert_eq!(env.len(), cols * 2, "interleaved peak+rms");
        assert!(env.iter().all(|&v| (0.0..=1.0).contains(&v)));
        // rms never exceeds peak in the same column; some column has energy.
        let mut any_energy = false;
        for c in 0..cols {
            let (peak, rms) = (env[c * 2], env[c * 2 + 1]);
            assert!(rms <= peak + 1e-6, "rms {rms} exceeded peak {peak} at col {c}");
            if peak > 0.1 {
                any_energy = true;
            }
        }
        assert!(any_energy, "a 0.5-amplitude tone should light some columns");
    }
}
