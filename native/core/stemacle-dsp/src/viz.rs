//! Visualization helpers: downsampled spectrogram + waveform envelope used by
//! the native per-stem lanes and the player's radial spectrum (the same data
//! the web gold master draws under each stem).

use crate::stft::{hann, stft, FFT_SIZE, TOT_BINS};

/// Compute a `cols × rows` log-magnitude spectrogram for visualization, values
/// normalized to `0..1`. Columns are time, rows are frequency (row 0 = low).
///
/// Cheap and resolution-independent: the full STFT is averaged into the
/// requested grid, log-scaled, and normalized. Empty/short input yields zeros.
pub fn spectrogram(samples: &[f32], cols: usize, rows: usize) -> Vec<f32> {
    let mut out = vec![0.0f32; cols * rows];
    if cols == 0 || rows == 0 || samples.len() < FFT_SIZE {
        return out;
    }
    let spec = stft(samples, &hann(FFT_SIZE));
    let frames = spec.frames;
    if frames == 0 {
        return out;
    }
    // Use the lower ~3/4 of bins (the visually interesting band).
    let used_bins = (TOT_BINS * 3 / 4).max(rows);

    let mut max_db = f32::NEG_INFINITY;
    // First pass: fill with averaged log-magnitude, track max for normalization.
    for c in 0..cols {
        let f0 = c * frames / cols;
        let f1 = (((c + 1) * frames / cols).max(f0 + 1)).min(frames);
        for r in 0..rows {
            let b0 = r * used_bins / rows;
            let b1 = (((r + 1) * used_bins / rows).max(b0 + 1)).min(used_bins);
            let mut acc = 0.0f32;
            let mut n = 0usize;
            for f in f0..f1 {
                for b in b0..b1 {
                    acc += (spec.re[f][b] * spec.re[f][b] + spec.im[f][b] * spec.im[f][b]).sqrt();
                    n += 1;
                }
            }
            let mag = if n > 0 { acc / n as f32 } else { 0.0 };
            let db = 20.0 * (mag + 1e-6).log10();
            out[c * rows + r] = db;
            if db > max_db {
                max_db = db;
            }
        }
    }
    // Second pass: normalize to 0..1 over a ~70 dB window below the peak.
    let floor = max_db - 70.0;
    for v in out.iter_mut() {
        *v = ((*v - floor) / (max_db - floor).max(1e-6)).clamp(0.0, 1.0);
    }
    out
}

/// Compute a `cols`-bucket peak/RMS waveform envelope in `0..1` (handy for a
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
    }
}
