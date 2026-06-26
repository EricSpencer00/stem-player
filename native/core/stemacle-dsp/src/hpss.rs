//! Harmonic/percussive source separation and the bass/melody low-pass split,
//! ported from `hpss` / `medFilter` / `lowPass` in `app/index.html`.

use crate::stft::{Spectrogram, FFT_SIZE, SR, TOT_BINS};

/// Median filter over a power spectrogram laid out as `frames * bins`.
/// `axis = 'h'` filters along time (sustained/harmonic), `'v'` along frequency
/// (transient/percussive). Window length `L`, median at index `L/2`.
fn med_filter(spec: &[f32], frames: usize, bins: usize, l: usize, axis: char) -> Vec<f32> {
    let mut out = vec![0.0f32; frames * bins];
    let h = l >> 1;
    let mut col = vec![0.0f32; l];
    if axis == 'h' {
        for b in 0..bins {
            for f in 0..frames {
                for k in 0..l {
                    let fi = f as isize - h as isize + k as isize;
                    col[k] = if fi >= 0 && (fi as usize) < frames {
                        spec[fi as usize * bins + b]
                    } else {
                        0.0
                    };
                }
                col.sort_by(|a, b| a.partial_cmp(b).unwrap());
                out[f * bins + b] = col[h];
            }
        }
    } else {
        for f in 0..frames {
            for b in 0..bins {
                for k in 0..l {
                    let bi = b as isize - h as isize + k as isize;
                    col[k] = if bi >= 0 && (bi as usize) < bins {
                        spec[f * bins + bi as usize]
                    } else {
                        0.0
                    };
                }
                col.sort_by(|a, b| a.partial_cmp(b).unwrap());
                out[f * bins + b] = col[h];
            }
        }
    }
    out
}

/// Result of HPSS: harmonic (sustained) and percussive (drums) spectrograms.
pub struct HpssResult {
    pub harmonic: Spectrogram,
    pub percussive: Spectrogram,
}

/// Soft-mask HPSS. Port of `hpss(re, im, F, B)` with a 17-tap median window.
pub fn hpss(input: &Spectrogram) -> HpssResult {
    let frames = input.frames;
    let bins = TOT_BINS;
    let mut mag = vec![0.0f32; frames * bins];
    for f in 0..frames {
        for b in 0..bins {
            mag[f * bins + b] = input.re[f][b].powi(2) + input.im[f][b].powi(2);
        }
    }
    let h_spec = med_filter(&mag, frames, bins, 17, 'h');
    let p_spec = med_filter(&mag, frames, bins, 17, 'v');

    let mut harmonic = Spectrogram::zeros(frames);
    let mut percussive = Spectrogram::zeros(frames);
    for f in 0..frames {
        for b in 0..bins {
            let hh = h_spec[f * bins + b];
            let pp = p_spec[f * bins + b];
            let d = hh + pp + 1e-8;
            harmonic.re[f][b] = input.re[f][b] * hh / d;
            harmonic.im[f][b] = input.im[f][b] * hh / d;
            percussive.re[f][b] = input.re[f][b] * pp / d;
            percussive.im[f][b] = input.im[f][b] * pp / d;
        }
    }
    HpssResult {
        harmonic,
        percussive,
    }
}

/// Low-pass split at `hz`. Port of `lowPass`: returns (low, high) spectrograms
/// where the cutoff bin is `round(hz / (SR / FFT_SIZE))`.
pub fn low_pass(input: &Spectrogram, hz: f32) -> (Spectrogram, Spectrogram) {
    let cut = (hz / (SR as f32 / FFT_SIZE as f32)).round() as usize;
    let frames = input.frames;
    let mut low = input.clone();
    let mut high = input.clone();
    for f in 0..frames {
        for b in cut..TOT_BINS {
            low.re[f][b] = 0.0;
            low.im[f][b] = 0.0;
        }
        for b in 0..cut.min(TOT_BINS) {
            high.re[f][b] = 0.0;
            high.im[f][b] = 0.0;
        }
    }
    (low, high)
}

/// Soft bass/melody crossover. Below `low_hz` all energy goes to bass; above
/// `high_hz` all energy goes to melody; between them a cosine crossfade avoids
/// hard-cutting low-mid instruments.
pub fn soft_low_pass(input: &Spectrogram, low_hz: f32, high_hz: f32) -> (Spectrogram, Spectrogram) {
    let frames = input.frames;
    let bin_hz = SR as f32 / FFT_SIZE as f32;
    let mut low = Spectrogram::zeros(frames);
    let mut high = Spectrogram::zeros(frames);
    for f in 0..frames {
        for b in 0..TOT_BINS {
            let freq = b as f32 * bin_hz;
            let low_weight = if freq <= low_hz {
                1.0
            } else if freq >= high_hz {
                0.0
            } else {
                let t = (freq - low_hz) / (high_hz - low_hz);
                0.5 + 0.5 * (std::f32::consts::PI * t).cos()
            };
            let high_weight = 1.0 - low_weight;
            low.re[f][b] = input.re[f][b] * low_weight;
            low.im[f][b] = input.im[f][b] * low_weight;
            high.re[f][b] = input.re[f][b] * high_weight;
            high.im[f][b] = input.im[f][b] * high_weight;
        }
    }
    (low, high)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn low_pass_cutoff_bin_matches_gold_master() {
        // SR/FFT_SIZE = 44100/4096 ≈ 10.7666 Hz/bin; round(300/10.7666) = 28.
        let spec = Spectrogram::zeros(2);
        let (_low, _high) = low_pass(&spec, 300.0);
        let cut = (300.0f32 / (SR as f32 / FFT_SIZE as f32)).round() as usize;
        assert_eq!(cut, 28);
    }

    #[test]
    fn low_pass_partitions_energy() {
        let mut spec = Spectrogram::zeros(1);
        spec.re[0][5] = 1.0; // below cut → bass
        spec.re[0][100] = 1.0; // above cut → melody
        let (low, high) = low_pass(&spec, 300.0);
        assert_eq!(low.re[0][5], 1.0);
        assert_eq!(low.re[0][100], 0.0);
        assert_eq!(high.re[0][5], 0.0);
        assert_eq!(high.re[0][100], 1.0);
    }

    #[test]
    fn hpss_masks_sum_to_input() {
        // Harmonic + percussive soft masks reconstruct the input (mask is a
        // partition of unity up to the 1e-8 epsilon).
        let mut spec = Spectrogram::zeros(8);
        for f in 0..8 {
            for b in 0..TOT_BINS {
                spec.re[f][b] = ((f * 7 + b) as f32 * 0.01).sin();
                spec.im[f][b] = ((f * 3 + b) as f32 * 0.02).cos();
            }
        }
        let res = hpss(&spec);
        for f in 0..8 {
            for b in 0..TOT_BINS {
                let sum_re = res.harmonic.re[f][b] + res.percussive.re[f][b];
                assert!((sum_re - spec.re[f][b]).abs() < 1e-4, "re mismatch {f},{b}");
            }
        }
    }

    #[test]
    fn soft_low_pass_crossfades_and_partitions_energy() {
        let mut spec = Spectrogram::zeros(1);
        let bin_hz = SR as f32 / FFT_SIZE as f32;
        let bin = (330.0 / bin_hz).round() as usize;
        spec.re[0][bin] = 1.0;

        let (low, high) = soft_low_pass(&spec, 220.0, 380.0);

        assert!(low.re[0][bin] > 0.1, "low weight {}", low.re[0][bin]);
        assert!(high.re[0][bin] > 0.1, "high weight {}", high.re[0][bin]);
        assert!((low.re[0][bin] + high.re[0][bin] - 1.0).abs() < 1e-6);
    }
}
