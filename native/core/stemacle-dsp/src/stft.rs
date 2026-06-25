//! STFT / ISTFT and spectral helpers, ported from `app/index.html`.
//!
//! Constants mirror the gold master exactly: `FFT_SIZE = 4096`, `HOP_SIZE = 1024`,
//! `SR = 44100`. A complex spectrogram is stored as per-frame `re`/`im` rows of
//! `TOT_BINS = FFT_SIZE/2 + 1` bins (the non-redundant half spectrum).

use crate::fft::{fft_ip, ifft_ip};

pub const FFT_SIZE: usize = 4096;
pub const HOP_SIZE: usize = 1024;
pub const SR: usize = 44100;
pub const TOT_BINS: usize = FFT_SIZE / 2 + 1; // 2049
pub const MODEL_BINS: usize = 1024;

/// Periodic Hann window, identical to `hann(N)` in the gold master.
pub fn hann(n: usize) -> Vec<f32> {
    (0..n)
        .map(|i| 0.5 - 0.5 * (2.0 * std::f32::consts::PI * i as f32 / n as f32).cos())
        .collect()
}

/// Complex spectrogram: `frames` rows, each `TOT_BINS` long.
#[derive(Clone, Debug)]
pub struct Spectrogram {
    pub re: Vec<Vec<f32>>,
    pub im: Vec<Vec<f32>>,
    pub frames: usize,
}

impl Spectrogram {
    /// Allocate an all-zero spectrogram with `frames` frames of `TOT_BINS` bins.
    pub fn zeros(frames: usize) -> Self {
        Spectrogram {
            re: (0..frames).map(|_| vec![0.0f32; TOT_BINS]).collect(),
            im: (0..frames).map(|_| vec![0.0f32; TOT_BINS]).collect(),
            frames,
        }
    }
}

/// Number of STFT frames for a signal, matching `floor((len-FFT_SIZE)/HOP_SIZE)+1`.
pub fn frame_count(len: usize) -> usize {
    if len < FFT_SIZE {
        return 0;
    }
    (len - FFT_SIZE) / HOP_SIZE + 1
}

/// Forward STFT. Port of `stft(sig, win)` keeping only the lower `TOT_BINS` half.
pub fn stft(signal: &[f32], win: &[f32]) -> Spectrogram {
    let frames = frame_count(signal.len());
    let mut out = Spectrogram::zeros(frames);
    let mut fr = vec![0.0f32; FFT_SIZE];
    let mut fi = vec![0.0f32; FFT_SIZE];
    for f in 0..frames {
        let s = f * HOP_SIZE;
        for i in 0..FFT_SIZE {
            let sample = if s + i < signal.len() { signal[s + i] } else { 0.0 };
            fr[i] = sample * win[i];
            fi[i] = 0.0;
        }
        fft_ip(&mut fr, &mut fi);
        out.re[f].copy_from_slice(&fr[..TOT_BINS]);
        out.im[f].copy_from_slice(&fi[..TOT_BINS]);
    }
    out
}

/// Inverse STFT with overlap-add and window-power normalization. Port of `istft`.
pub fn istft(spec: &Spectrogram, win: &[f32]) -> Vec<f32> {
    let frames = spec.frames;
    let len = if frames == 0 { 0 } else { (frames - 1) * HOP_SIZE + FFT_SIZE };
    let mut out = vec![0.0f32; len];
    let mut nrm = vec![0.0f32; len];
    let mut fr = vec![0.0f32; FFT_SIZE];
    let mut fi = vec![0.0f32; FFT_SIZE];
    for f in 0..frames {
        for b in 0..TOT_BINS {
            fr[b] = spec.re[f][b];
            fi[b] = spec.im[f][b];
        }
        // Hermitian-symmetric upper half.
        for b in 1..TOT_BINS - 1 {
            fr[FFT_SIZE - b] = fr[b];
            fi[FFT_SIZE - b] = -fi[b];
        }
        ifft_ip(&mut fr, &mut fi);
        let s = f * HOP_SIZE;
        for i in 0..FFT_SIZE {
            out[s + i] += fr[i] * win[i];
            nrm[s + i] += win[i] * win[i];
        }
    }
    for i in 0..len {
        if nrm[i] > 1e-8 {
            out[i] /= nrm[i];
        }
    }
    out
}

/// Per-frame magnitude over the first `MODEL_BINS` bins (`buildMagnitude`).
pub fn build_magnitude(spec: &Spectrogram) -> Vec<Vec<f32>> {
    (0..spec.frames)
        .map(|f| {
            (0..MODEL_BINS)
                .map(|b| spec.re[f][b].hypot(spec.im[f][b]))
                .collect()
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frame_count_matches_formula() {
        assert_eq!(frame_count(FFT_SIZE), 1);
        assert_eq!(frame_count(FFT_SIZE + HOP_SIZE), 2);
        assert_eq!(frame_count(FFT_SIZE - 1), 0);
        assert_eq!(frame_count(FFT_SIZE + 5 * HOP_SIZE), 6);
    }

    #[test]
    fn hann_is_symmetric_and_zero_at_edge() {
        let w = hann(FFT_SIZE);
        assert!(w[0].abs() < 1e-6);
        // periodic Hann: w[i] == w[N-i] for i in 1..N
        for i in 1..FFT_SIZE {
            assert!((w[i] - w[FFT_SIZE - i]).abs() < 1e-5, "asymmetry at {i}");
        }
    }

    /// STFT→ISTFT must reconstruct the interior of a signal (COLA for Hann at
    /// 75% overlap), away from the windowed edges.
    #[test]
    fn stft_istft_reconstructs_interior() {
        let len = FFT_SIZE + 40 * HOP_SIZE;
        let orig: Vec<f32> = (0..len)
            .map(|i| (0.02 * i as f32).sin() * 0.6 + (0.005 * i as f32).cos() * 0.3)
            .collect();
        let win = hann(FFT_SIZE);
        let spec = stft(&orig, &win);
        let recon = istft(&spec, &win);
        // Check a stable interior region (skip first/last FFT_SIZE samples).
        let mut max_err = 0.0f32;
        for i in FFT_SIZE..(len - FFT_SIZE) {
            max_err = max_err.max((recon[i] - orig[i]).abs());
        }
        assert!(max_err < 1e-3, "interior reconstruction error {max_err}");
    }

    #[test]
    fn build_magnitude_is_hypot() {
        let mut spec = Spectrogram::zeros(1);
        spec.re[0][3] = 3.0;
        spec.im[0][3] = 4.0;
        let mag = build_magnitude(&spec);
        assert!((mag[0][3] - 5.0).abs() < 1e-5);
    }
}
