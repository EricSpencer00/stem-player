//! Stemacle shared DSP core.
//!
//! A faithful Rust port of the deterministic signal processing in the web gold
//! master (`app/index.html`): FFT, STFT/ISTFT, HPSS, the bass/melody low-pass
//! split, tempo/beat detection, and the loop-boundary contract. This is the
//! single, exhaustively-tested implementation of "core functionality" shared by
//! every native surface (Apple via FFI, Windows/Linux via Slint).
//!
//! Neural separation (Demucs through CoreML / ONNX Runtime) is *not* here. It is
//! injected by each platform behind the [`Separator`] trait so the heavy model
//! runs on the platform-best runtime while this crate stays deterministic and
//! golden-testable.

pub mod fft;
pub mod hpss;
pub mod loops;
pub mod stft;
pub mod tempo;
pub mod viz;

pub use loops::{LoopGrid, LOOP_BARS};
pub use stft::{Spectrogram, FFT_SIZE, HOP_SIZE, MODEL_BINS, SR, TOT_BINS};
pub use tempo::{estimate_tempo, TempoEstimate};

/// The four stems Stemacle produces, in canonical order.
pub const STEMS: [&str; 4] = ["drums", "vocals", "bass", "melody"];

/// Mono PCM stems plus the analysis used to drive the UI.
#[derive(Clone, Debug)]
pub struct StemSplit {
    pub drums: Vec<f32>,
    pub vocals: Vec<f32>,
    pub bass: Vec<f32>,
    pub melody: Vec<f32>,
    pub sample_rate: usize,
    pub tempo: TempoEstimate,
}

/// A vocal soft-mask provider over the first [`MODEL_BINS`] bins.
///
/// The web DSP fallback ([`CoherenceSeparator`]) implements this with stereo
/// coherence; Phase 2 platform separators implement it with Demucs. The rest of
/// the pipeline (mask application, HPSS, low-pass, ISTFT) is identical either
/// way, which is exactly what keeps the surfaces in parity.
pub trait Separator {
    /// Return `frames * MODEL_BINS` vocal mask values in `[0, 1]`, row-major.
    fn vocal_mask(&self, mag_l: &[Vec<f32>], mag_r: &[Vec<f32>], frames: usize) -> Vec<f32>;
}

/// Browser-DSP fallback: `min(L,R) / (0.5*(L+R))` per bin. Port of the `else`
/// branch in `separateAudio`.
pub struct CoherenceSeparator;

impl Separator for CoherenceSeparator {
    fn vocal_mask(&self, mag_l: &[Vec<f32>], mag_r: &[Vec<f32>], frames: usize) -> Vec<f32> {
        let mut mask = vec![0.0f32; frames * MODEL_BINS];
        for f in 0..frames {
            for b in 0..MODEL_BINS {
                let l = mag_l[f][b];
                let r = mag_r[f][b];
                mask[f * MODEL_BINS + b] = l.min(r) / (0.5 * (l + r) + 1e-8);
            }
        }
        mask
    }
}

/// Run the full Stemacle separation pipeline on stereo PCM, mirroring
/// `separateAudio` end-to-end with a pluggable vocal [`Separator`].
///
/// `sig_r` may equal `sig_l` for mono input.
pub fn separate(sig_l: &[f32], sig_r: &[f32], sample_rate: usize, sep: &dyn Separator) -> StemSplit {
    // Tempo from the mono mixdown.
    let mono: Vec<f32> = sig_l
        .iter()
        .zip(sig_r.iter())
        .map(|(&l, &r)| (l + r) * 0.5)
        .collect();
    let tempo = estimate_tempo(&mono, sample_rate as f32);

    let win = stft::hann(FFT_SIZE);
    let st_l = stft::stft(sig_l, &win);
    let st_r = stft::stft(sig_r, &win);
    let frames = st_l.frames;

    let mag_l = stft::build_magnitude(&st_l);
    let mag_r = stft::build_magnitude(&st_r);
    let v_mask = sep.vocal_mask(&mag_l, &mag_r, frames);

    // Apply the vocal mask against the stereo-mean spectrum; high bins (>=
    // MODEL_BINS) go entirely to accompaniment.
    let mut vocal = Spectrogram::zeros(frames);
    let mut accomp = Spectrogram::zeros(frames);
    for f in 0..frames {
        for b in 0..TOT_BINS {
            let m_re = (st_l.re[f][b] + st_r.re[f][b]) * 0.5;
            let m_im = (st_l.im[f][b] + st_r.im[f][b]) * 0.5;
            let vm = if b < MODEL_BINS { v_mask[f * MODEL_BINS + b] } else { 0.0 };
            vocal.re[f][b] = m_re * vm;
            vocal.im[f][b] = m_im * vm;
            accomp.re[f][b] = m_re * (1.0 - vm);
            accomp.im[f][b] = m_im * (1.0 - vm);
        }
    }

    // Accompaniment → HPSS → percussive = drums, harmonic → low-pass split.
    let split = hpss::hpss(&accomp);
    let (bass_spec, melody_spec) = hpss::low_pass(&split.harmonic, 300.0);

    StemSplit {
        drums: stft::istft(&split.percussive, &win),
        vocals: stft::istft(&vocal, &win),
        bass: stft::istft(&bass_spec, &win),
        melody: stft::istft(&melody_spec, &win),
        sample_rate,
        tempo,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stems_constant_matches_order() {
        assert_eq!(STEMS, ["drums", "vocals", "bass", "melody"]);
    }

    /// End-to-end smoke: a synthetic stereo signal separates into four equal-
    /// length stems whose sum approximately reconstructs the input mix (the
    /// pipeline is mask-conservative up to HPSS/low-pass leakage).
    #[test]
    fn separate_produces_four_aligned_stems() {
        let len = FFT_SIZE + 60 * HOP_SIZE;
        let sig_l: Vec<f32> = (0..len)
            .map(|i| (0.02 * i as f32).sin() * 0.5 + (0.2 * i as f32).sin() * 0.2)
            .collect();
        let sig_r: Vec<f32> = (0..len)
            .map(|i| (0.02 * i as f32).sin() * 0.5 - (0.2 * i as f32).sin() * 0.2)
            .collect();

        let split = separate(&sig_l, &sig_r, SR, &CoherenceSeparator);

        let n = split.drums.len();
        assert!(n > 0);
        assert_eq!(split.vocals.len(), n);
        assert_eq!(split.bass.len(), n);
        assert_eq!(split.melody.len(), n);

        // Reconstruct mix from stems and compare to the input mean over a stable
        // interior region. Stems partition the mean spectrum, so the sum should
        // track the input closely.
        let mut max_err = 0.0f32;
        for i in FFT_SIZE..(n.min(len) - FFT_SIZE) {
            let mix = (sig_l[i] + sig_r[i]) * 0.5;
            let sum = split.drums[i] + split.vocals[i] + split.bass[i] + split.melody[i];
            max_err = max_err.max((sum - mix).abs());
        }
        assert!(max_err < 0.05, "stem sum diverged from mix: {max_err}");
    }
}
