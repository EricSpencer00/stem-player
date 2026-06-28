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

/// Frequency weighting for the fallback vocal mask. Pure stereo coherence marks
/// every centered source as "vocal"; this keeps low bass and high air out of the
/// vocal stem before accompaniment is split into drums/bass/melody.
pub fn vocal_mask_weight_for_bin(bin: usize) -> f32 {
    let freq = bin as f32 * SR as f32 / FFT_SIZE as f32;
    if freq < 120.0 {
        0.0
    } else if freq < 240.0 {
        (freq - 120.0) / 120.0
    } else if freq <= 3400.0 {
        1.0
    } else if freq < 6000.0 {
        1.0 - (freq - 3400.0) / 2600.0
    } else {
        0.0
    }
}

fn transient_weights(mag_l: &[Vec<f32>], mag_r: &[Vec<f32>], frames: usize) -> Vec<f32> {
    let mut weights = vec![0.0f32; frames];
    let mut prev = vec![0.0f32; MODEL_BINS];
    for f in 0..frames {
        let mut flux = 0.0f32;
        let mut energy = 0.0f32;
        for b in 4..MODEL_BINS {
            let cur = (mag_l[f][b] + mag_r[f][b]) * 0.5;
            energy += cur;
            flux += (cur - prev[b]).max(0.0);
            prev[b] = cur;
        }
        let novelty = flux / (energy + 1e-8);
        weights[f] = ((novelty - 0.18) / 0.42).clamp(0.0, 1.0);
    }
    weights
}

impl Separator for CoherenceSeparator {
    fn vocal_mask(&self, mag_l: &[Vec<f32>], mag_r: &[Vec<f32>], frames: usize) -> Vec<f32> {
        let mut mask = vec![0.0f32; frames * MODEL_BINS];
        let transient = transient_weights(mag_l, mag_r, frames);
        for f in 0..frames {
            for b in 0..MODEL_BINS {
                let l = mag_l[f][b];
                let r = mag_r[f][b];
                let centered = l.min(r) / (0.5 * (l + r) + 1e-8);
                let attack_duck = 1.0 - 0.9 * transient[f];
                mask[f * MODEL_BINS + b] = centered * vocal_mask_weight_for_bin(b) * attack_duck;
            }
        }
        mask
    }
}

/// Run the full Stemacle separation pipeline on stereo PCM, mirroring
/// `separateAudio` end-to-end with a pluggable vocal [`Separator`].
///
/// `sig_r` may equal `sig_l` for mono input.
pub fn separate(
    sig_l: &[f32],
    sig_r: &[f32],
    sample_rate: usize,
    sep: &dyn Separator,
) -> StemSplit {
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
            let vm = if b < MODEL_BINS {
                v_mask[f * MODEL_BINS + b]
            } else {
                0.0
            };
            vocal.re[f][b] = m_re * vm;
            vocal.im[f][b] = m_im * vm;
            accomp.re[f][b] = m_re * (1.0 - vm);
            accomp.im[f][b] = m_im * (1.0 - vm);
        }
    }

    // Accompaniment → HPSS → percussive = drums, harmonic → low-pass split.
    let split = hpss::hpss(&accomp);
    let (bass_spec, melody_spec) = hpss::soft_low_pass(&split.harmonic, 220.0, 380.0);

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

    fn sine(len: usize, hz: f32, amp: f32) -> Vec<f32> {
        (0..len)
            .map(|i| {
                let t = i as f32 / SR as f32;
                (2.0 * std::f32::consts::PI * hz * t).sin() * amp
            })
            .collect()
    }

    fn rms(samples: &[f32]) -> f32 {
        let start = samples.len().min(FFT_SIZE);
        let end = samples.len().saturating_sub(FFT_SIZE);
        if end <= start {
            return 0.0;
        }
        let sum = samples[start..end].iter().map(|v| v * v).sum::<f32>();
        (sum / (end - start) as f32).sqrt()
    }

    fn peak(samples: &[f32]) -> f32 {
        samples.iter().fold(0.0f32, |acc, v| acc.max(v.abs()))
    }

    #[test]
    fn stems_constant_matches_order() {
        assert_eq!(STEMS, ["drums", "vocals", "bass", "melody"]);
    }

    #[test]
    fn vocal_mask_weight_rejects_sub_bass_and_high_air() {
        assert_eq!(vocal_mask_weight_for_bin(0), 0.0);
        assert_eq!(vocal_mask_weight_for_bin(8), 0.0);
        assert!(vocal_mask_weight_for_bin(80) > 0.9);
        assert_eq!(vocal_mask_weight_for_bin(900), 0.0);
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

    #[test]
    fn centered_low_bass_goes_to_bass_not_vocals() {
        let len = FFT_SIZE + 90 * HOP_SIZE;
        let bass = sine(len, 88.0, 0.5);

        let split = separate(&bass, &bass, SR, &CoherenceSeparator);

        let bass_rms = rms(&split.bass);
        let vocal_rms = rms(&split.vocals);
        assert!(
            bass_rms > vocal_rms * 4.0,
            "expected centered low bass in bass stem, bass rms {bass_rms}, vocal rms {vocal_rms}"
        );
    }

    #[test]
    fn centered_percussive_burst_goes_to_drums_not_vocals() {
        let len = FFT_SIZE + 90 * HOP_SIZE;
        let mut burst = vec![0.0f32; len];
        let center = FFT_SIZE + 35 * HOP_SIZE;
        for i in 0..96 {
            let t = i as f32 / SR as f32;
            let env = 1.0 - i as f32 / 96.0;
            burst[center + i] = (2.0 * std::f32::consts::PI * 180.0 * t).sin() * env * 0.9;
        }

        let split = separate(&burst, &burst, SR, &CoherenceSeparator);

        let drum_peak = peak(&split.drums);
        let vocal_peak = peak(&split.vocals);
        assert!(
            drum_peak > vocal_peak * 2.0,
            "expected centered transient in drums, drum peak {drum_peak}, vocal peak {vocal_peak}"
        );
    }

    #[test]
    fn low_mid_crossover_keeps_some_energy_in_bass_and_melody() {
        let len = FFT_SIZE + 90 * HOP_SIZE;
        let tone = sine(len, 330.0, 0.5);
        let silent = vec![0.0f32; len];

        let split = separate(&tone, &silent, SR, &CoherenceSeparator);

        let bass_rms = rms(&split.bass);
        let melody_rms = rms(&split.melody);
        assert!(
            bass_rms > melody_rms * 0.12 && melody_rms > bass_rms * 0.12,
            "expected soft crossover energy in bass and melody, bass rms {bass_rms}, melody rms {melody_rms}"
        );
    }

    // -------------------------------------------------------------------------
    // New tests: edge cases and routing precision
    // -------------------------------------------------------------------------

    /// All-zero (silent) input must not panic and must produce finite stems.
    /// Exercises the epsilon guards in CoherenceSeparator and HPSS.
    #[test]
    fn separate_silent_input_yields_finite_stems() {
        let len = FFT_SIZE + 60 * HOP_SIZE;
        let silence = vec![0.0f32; len];
        let split = separate(&silence, &silence, SR, &CoherenceSeparator);

        for stem in [&split.drums, &split.vocals, &split.bass, &split.melody] {
            assert!(!stem.is_empty(), "stem should still have frames");
            assert!(
                stem.iter().all(|v| v.is_finite()),
                "silent input produced non-finite sample in a stem"
            );
        }
    }

    /// Input shorter than FFT_SIZE produces empty stems (zero STFT frames).
    /// Must not panic.
    #[test]
    fn separate_sub_fft_size_input_returns_empty_stems() {
        let short = vec![0.5f32; FFT_SIZE - 1]; // one sample shy of one frame
        let split = separate(&short, &short, SR, &CoherenceSeparator);
        assert!(split.drums.is_empty(), "expected empty drums for sub-FFT input");
        assert!(split.vocals.is_empty());
        assert!(split.bass.is_empty());
        assert!(split.melody.is_empty());
    }

    /// Vocal mask weight piecewise function: verify exact transition boundaries.
    ///
    /// bin_hz = 44100 / 4096 ≈ 10.77 Hz/bin
    ///  - bin 11 → 118.5 Hz  < 120  → weight 0.0 (below ramp start)
    ///  - bin 12 → 129.3 Hz  ∈ ramp → weight > 0
    ///  - bin 23 → 247.8 Hz  ≥ 240  → weight 1.0 (flat top)
    ///  - bin 315 → 3391 Hz  ≤ 3400 → weight 1.0
    ///  - bin 316 → 3402 Hz  > 3400 → weight just below 1.0 (ramp down starts)
    ///  - bin 558 → 6008 Hz  ≥ 6000 → weight 0.0 (above ramp end)
    #[test]
    fn vocal_mask_weight_exact_transition_boundaries() {
        assert_eq!(vocal_mask_weight_for_bin(11), 0.0, "below 120 Hz");
        assert!(vocal_mask_weight_for_bin(12) > 0.0, "just above 120 Hz start");
        assert!(vocal_mask_weight_for_bin(12) < 0.15, "still low on ramp");
        assert_eq!(vocal_mask_weight_for_bin(23), 1.0, "above 240 Hz → full weight");
        assert_eq!(vocal_mask_weight_for_bin(315), 1.0, "below 3400 Hz → full weight");
        let at_3402 = vocal_mask_weight_for_bin(316); // ≈ 3402.6 Hz
        assert!(at_3402 < 1.0, "above 3400 Hz → ramp down should start");
        assert!(at_3402 > 0.99, "only 2.6 Hz into the 2600-Hz ramp");
        assert_eq!(vocal_mask_weight_for_bin(558), 0.0, "above 6000 Hz → zero");
    }

    /// Centered (mono) voice-range tone goes primarily to the vocal stem.
    /// With L == R, coherence = 1.0 for all bins; voice-range weight = 1.0
    /// → the 1 kHz energy should dominate the vocal stem.
    #[test]
    fn centered_voice_range_tone_goes_to_vocals() {
        let len = FFT_SIZE + 90 * HOP_SIZE;
        let voice = sine(len, 1000.0, 0.5);

        let split = separate(&voice, &voice, SR, &CoherenceSeparator);

        let vocal_rms = rms(&split.vocals);
        let bass_rms = rms(&split.bass);
        let melody_rms = rms(&split.melody);
        assert!(
            vocal_rms > bass_rms * 3.0,
            "1 kHz mono should dominate vocals over bass: vocal={vocal_rms}, bass={bass_rms}"
        );
        assert!(
            vocal_rms > melody_rms * 3.0,
            "1 kHz mono should dominate vocals over melody: vocal={vocal_rms}, melody={melody_rms}"
        );
    }

    /// Stem count and sample-rate are preserved through the pipeline.
    #[test]
    fn separate_output_sample_rate_matches_input() {
        let len = FFT_SIZE + 20 * HOP_SIZE;
        let sig = sine(len, 440.0, 0.3);
        let split = separate(&sig, &sig, SR, &CoherenceSeparator);
        assert_eq!(split.sample_rate, SR, "sample rate must pass through unchanged");
    }
}
