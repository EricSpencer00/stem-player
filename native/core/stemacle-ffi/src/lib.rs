//! Stable C ABI over `stemacle-dsp`.
//!
//! Hand-written (no bindgen) so the boundary is explicit and stable. Consumed by
//! the Apple `StemacleKit` Swift package (static link) and the Slint desktop
//! shell (dynamic link). The header in `include/stemacle.h` mirrors this exactly
//! and is verified by `tests/header_matches.rs`.
//!
//! Ownership: `stemacle_separate` allocates a [`StemacleStems`] plus four PCM
//! buffers; the caller must release them with `stemacle_stems_free`. All other
//! functions are pure and allocation-free.

use std::os::raw::c_uint;
use std::slice;

use stemacle_dsp::loops::{audible_stem_time, LoopGrid};
use stemacle_dsp::stft::{build_magnitude, frame_count, hann, stft, MODEL_BINS};
use stemacle_dsp::{separate, vocal_mask_weight_for_bin, CoherenceSeparator, PrecomputedMask, StemSplit};

/// Four mono PCM stems plus the detected tempo grid. `*_ptr` buffers each hold
/// `len` `f32` samples at `sample_rate`. Layout is `#[repr(C)]` and matches
/// `StemacleStems` in `stemacle.h`.
#[repr(C)]
pub struct StemacleStems {
    pub drums_ptr: *mut f32,
    pub vocals_ptr: *mut f32,
    pub bass_ptr: *mut f32,
    pub melody_ptr: *mut f32,
    pub len: usize,
    pub sample_rate: c_uint,
    pub bpm: f32,
    pub measure_offset: f32,
    pub beat_offset: f32,
    pub tempo_confidence: f32,
}

fn into_raw_buf(mut v: Vec<f32>) -> *mut f32 {
    v.shrink_to_fit();
    let ptr = v.as_mut_ptr();
    std::mem::forget(v);
    ptr
}

fn box_stems(split: StemSplit, sample_rate: c_uint) -> *mut StemacleStems {
    let out_len = split.drums.len();
    let boxed = Box::new(StemacleStems {
        drums_ptr: into_raw_buf(split.drums),
        vocals_ptr: into_raw_buf(split.vocals),
        bass_ptr: into_raw_buf(split.bass),
        melody_ptr: into_raw_buf(split.melody),
        len: out_len,
        sample_rate,
        bpm: split.tempo.bpm,
        measure_offset: split.tempo.measure_offset,
        beat_offset: split.tempo.beat_offset,
        tempo_confidence: split.tempo.confidence,
    });
    Box::into_raw(boxed)
}

/// # Safety
/// `left`/`right` must each point to `len` valid `f32`s (or be equal for mono).
/// Returns a heap pointer the caller frees via `stemacle_stems_free`; null on
/// invalid input.
#[no_mangle]
pub unsafe extern "C" fn stemacle_separate(
    left: *const f32,
    right: *const f32,
    len: usize,
    sample_rate: c_uint,
) -> *mut StemacleStems {
    if left.is_null() || right.is_null() || len == 0 || sample_rate == 0 {
        return std::ptr::null_mut();
    }
    let l = slice::from_raw_parts(left, len);
    let r = slice::from_raw_parts(right, len);
    let split = separate(l, r, sample_rate as usize, &CoherenceSeparator);
    box_stems(split, sample_rate)
}

/// Number of STFT frames for a signal of `len` samples — the row count the
/// caller must allocate for [`stemacle_magnitudes`] and the vocal mask.
#[no_mangle]
pub extern "C" fn stemacle_frame_count(len: usize) -> usize {
    frame_count(len)
}

/// Estimate tempo (bpm + measure/beat grid) from a mono signal. Used by the
/// Demucs path, which produces stems directly and so needs the tempo/loop grid
/// computed separately (the DSP/Spleeter paths get it from `separate`).
///
/// # Safety
/// `mono` must point to `len` valid `f32`s; the four out pointers must be writable.
#[no_mangle]
pub unsafe extern "C" fn stemacle_estimate_tempo(
    mono: *const f32,
    len: usize,
    sample_rate: c_uint,
    out_bpm: *mut f32,
    out_measure_offset: *mut f32,
    out_beat_offset: *mut f32,
    out_confidence: *mut f32,
) {
    if mono.is_null() || len == 0 || sample_rate == 0 {
        return;
    }
    let s = slice::from_raw_parts(mono, len);
    let t = stemacle_dsp::estimate_tempo(s, sample_rate as f32);
    if !out_bpm.is_null() { *out_bpm = t.bpm; }
    if !out_measure_offset.is_null() { *out_measure_offset = t.measure_offset; }
    if !out_beat_offset.is_null() { *out_beat_offset = t.beat_offset; }
    if !out_confidence.is_null() { *out_confidence = t.confidence; }
}

/// The vocal-mask frequency weight for a bin (keeps sub-bass / high-air out of
/// the vocal stem). Pure; mirrors `vocalMaskWeightForBin` in the web gold master.
#[no_mangle]
pub extern "C" fn stemacle_vocal_mask_weight_for_bin(bin: usize) -> f32 {
    vocal_mask_weight_for_bin(bin)
}

/// Compute per-frame magnitude spectra over the first `MODEL_BINS` bins for the
/// left and right channels, row-major (`out[f*MODEL_BINS + b]`). Each output
/// buffer must hold `stemacle_frame_count(len) * MODEL_BINS` `f32`s. This feeds
/// the neural (Spleeter) mask model on iOS; the mask it produces is then handed
/// back to [`stemacle_separate_with_mask`].
///
/// # Safety
/// `left`/`right` point to `len` `f32`s; `out_mag_l`/`out_mag_r` to
/// `frame_count(len)*MODEL_BINS` writable `f32`s.
#[no_mangle]
pub unsafe extern "C" fn stemacle_magnitudes(
    left: *const f32,
    right: *const f32,
    len: usize,
    out_mag_l: *mut f32,
    out_mag_r: *mut f32,
) {
    if left.is_null() || right.is_null() || out_mag_l.is_null() || out_mag_r.is_null() {
        return;
    }
    let l = slice::from_raw_parts(left, len);
    let r = slice::from_raw_parts(right, len);
    let frames = frame_count(len);
    if frames == 0 {
        return;
    }
    let win = hann(stemacle_dsp::stft::FFT_SIZE);
    let mag_l = build_magnitude(&stft(l, &win));
    let mag_r = build_magnitude(&stft(r, &win));
    let dst_l = slice::from_raw_parts_mut(out_mag_l, frames * MODEL_BINS);
    let dst_r = slice::from_raw_parts_mut(out_mag_r, frames * MODEL_BINS);
    for f in 0..frames.min(mag_l.len()) {
        dst_l[f * MODEL_BINS..(f + 1) * MODEL_BINS].copy_from_slice(&mag_l[f][..MODEL_BINS]);
        dst_r[f * MODEL_BINS..(f + 1) * MODEL_BINS].copy_from_slice(&mag_r[f][..MODEL_BINS]);
    }
}

/// Separate stereo PCM using a caller-supplied vocal mask (`mask_len` must equal
/// `frame_count(len) * MODEL_BINS`, row-major, values in `[0,1]`). This is the
/// neural path: the mask comes from the Spleeter ONNX model on iOS, then the
/// identical DSP pipeline (mask → HPSS → low-pass → ISTFT) produces the stems.
/// Returns a heap pointer freed via `stemacle_stems_free`; null on invalid input.
///
/// # Safety
/// `left`/`right` point to `len` `f32`s; `mask` to `mask_len` `f32`s.
#[no_mangle]
pub unsafe extern "C" fn stemacle_separate_with_mask(
    left: *const f32,
    right: *const f32,
    len: usize,
    sample_rate: c_uint,
    mask: *const f32,
    mask_len: usize,
) -> *mut StemacleStems {
    if left.is_null() || right.is_null() || mask.is_null() || len == 0 || sample_rate == 0 {
        return std::ptr::null_mut();
    }
    let l = slice::from_raw_parts(left, len);
    let r = slice::from_raw_parts(right, len);
    let mask_vec = slice::from_raw_parts(mask, mask_len).to_vec();
    let split = separate(l, r, sample_rate as usize, &PrecomputedMask { mask: mask_vec });
    box_stems(split, sample_rate)
}

/// # Safety
/// `stems` must be a pointer previously returned by `stemacle_separate` (or null).
#[no_mangle]
pub unsafe extern "C" fn stemacle_stems_free(stems: *mut StemacleStems) {
    if stems.is_null() {
        return;
    }
    let s = Box::from_raw(stems);
    let len = s.len;
    drop(Vec::from_raw_parts(s.drums_ptr, len, len));
    drop(Vec::from_raw_parts(s.vocals_ptr, len, len));
    drop(Vec::from_raw_parts(s.bass_ptr, len, len));
    drop(Vec::from_raw_parts(s.melody_ptr, len, len));
}

fn grid(bpm: f32, measure_offset: f32, beat_offset: f32, duration: f32) -> LoopGrid {
    LoopGrid { bpm, measure_offset, beat_offset, duration }
}

/// Snap a transport position up to the next loop-grid boundary. Pure.
#[no_mangle]
pub extern "C" fn stemacle_snap_loop_end(
    bpm: f32,
    measure_offset: f32,
    beat_offset: f32,
    duration: f32,
    current_sec: f32,
    loop_length: f32,
) -> f32 {
    grid(bpm, measure_offset, beat_offset, duration).snap_loop_end(current_sec, loop_length)
}

/// Compute a loop `[start, end)` for the transport position; writes both out
/// params. Returns 1 if the loop fits within the track, 0 if it must be rejected.
///
/// # Safety
/// `out_start`/`out_end` must be valid writable `f32` pointers.
#[no_mangle]
pub unsafe extern "C" fn stemacle_loop_range(
    bpm: f32,
    measure_offset: f32,
    beat_offset: f32,
    duration: f32,
    current_sec: f32,
    loop_length: f32,
    out_start: *mut f32,
    out_end: *mut f32,
) -> c_uint {
    let g = grid(bpm, measure_offset, beat_offset, duration);
    let (start, end) = g.loop_range_for(current_sec, loop_length);
    if !out_start.is_null() {
        *out_start = start;
    }
    if !out_end.is_null() {
        *out_end = end;
    }
    if g.loop_fits(current_sec, loop_length) {
        1
    } else {
        0
    }
}

/// Measure length in seconds for a given BPM. Pure.
#[no_mangle]
pub extern "C" fn stemacle_measure_length(bpm: f32) -> f32 {
    grid(bpm, 0.0, 0.0, 1.0).measure_length()
}

/// Compute a `cols × rows` log-magnitude spectrogram (values 0..1) into the
/// caller-provided `out` buffer (length must be `cols*rows`, column-major:
/// `out[col*rows + row]`). Row 0 is low frequency.
///
/// # Safety
/// `samples` must point to `len` valid `f32`s; `out` to `cols*rows` writable `f32`s.
#[no_mangle]
pub unsafe extern "C" fn stemacle_spectrogram(
    samples: *const f32,
    len: usize,
    cols: usize,
    rows: usize,
    out: *mut f32,
) {
    if samples.is_null() || out.is_null() || cols == 0 || rows == 0 {
        return;
    }
    let s = slice::from_raw_parts(samples, len);
    let grid = stemacle_dsp::viz::spectrogram(s, cols, rows);
    let dst = slice::from_raw_parts_mut(out, cols * rows);
    dst.copy_from_slice(&grid[..dst.len().min(grid.len())]);
}

/// Compute a `cols`-bucket peak waveform envelope (0..1) into `out`.
/// O(n) time and O(cols) extra space — use on iOS instead of `stemacle_spectrogram`
/// to avoid the ~200 MB STFT allocation per stem on long tracks.
///
/// # Safety
/// `samples` must point to `len` valid `f32`s; `out` to `cols` writable `f32`s.
#[no_mangle]
pub unsafe extern "C" fn stemacle_waveform_envelope(
    samples: *const f32,
    len: usize,
    cols: usize,
    out: *mut f32,
) {
    if samples.is_null() || out.is_null() || cols == 0 {
        return;
    }
    let s = slice::from_raw_parts(samples, len);
    let env = stemacle_dsp::viz::waveform_envelope(s, cols);
    let dst = slice::from_raw_parts_mut(out, cols);
    dst.copy_from_slice(&env[..dst.len().min(env.len())]);
}

/// Compute a `cols`-bucket peak+RMS waveform envelope into `out`, interleaved as
/// `[peak_0, rms_0, peak_1, rms_1, …]` (length `cols*2`). Drives the native
/// two-tone stem lane (RMS body + peak tips) at full scroll-window resolution.
///
/// # Safety
/// `samples` must point to `len` valid `f32`s; `out` to `cols*2` writable `f32`s.
#[no_mangle]
pub unsafe extern "C" fn stemacle_waveform_peaks_rms(
    samples: *const f32,
    len: usize,
    cols: usize,
    out: *mut f32,
) {
    if samples.is_null() || out.is_null() || cols == 0 {
        return;
    }
    let s = slice::from_raw_parts(samples, len);
    let env = stemacle_dsp::viz::waveform_peaks_rms(s, cols);
    let dst = slice::from_raw_parts_mut(out, cols * 2);
    dst.copy_from_slice(&env[..dst.len().min(env.len())]);
}

/// Fold a transport position into an active loop window (`active != 0`). Pure.
#[no_mangle]
pub extern "C" fn stemacle_audible_stem_time(
    transport_sec: f32,
    loop_start: f32,
    loop_end: f32,
    active: c_uint,
    duration: f32,
) -> f32 {
    audible_stem_time(transport_sec, loop_start, loop_end, active != 0, duration)
}

#[cfg(test)]
mod tests {
    use super::*;
    use stemacle_dsp::{FFT_SIZE, HOP_SIZE, SR};

    #[test]
    fn separate_and_free_round_trips() {
        let len = FFT_SIZE + 50 * HOP_SIZE;
        let l: Vec<f32> = (0..len).map(|i| (0.02 * i as f32).sin() * 0.5).collect();
        let r = l.clone();
        unsafe {
            let stems = stemacle_separate(l.as_ptr(), r.as_ptr(), len, SR as c_uint);
            assert!(!stems.is_null());
            let s = &*stems;
            assert!(s.len > 0);
            assert!(!s.drums_ptr.is_null() && !s.melody_ptr.is_null());
            assert!(s.bpm >= 60.0 && s.bpm <= 240.0);
            // touch each buffer so ASAN/miri-style misuse would surface
            let _ = slice::from_raw_parts(s.drums_ptr, s.len).iter().sum::<f32>();
            stemacle_stems_free(stems);
        }
    }

    #[test]
    fn magnitudes_and_mask_round_trip() {
        let len = FFT_SIZE + 40 * HOP_SIZE;
        let l: Vec<f32> = (0..len).map(|i| (0.05 * i as f32).sin() * 0.4).collect();
        let r = l.clone();
        let frames = stemacle_frame_count(len);
        assert!(frames > 0);

        // Magnitudes fill the requested shape with finite, non-negative values.
        let mut mag_l = vec![0.0f32; frames * MODEL_BINS];
        let mut mag_r = vec![0.0f32; frames * MODEL_BINS];
        unsafe {
            stemacle_magnitudes(l.as_ptr(), r.as_ptr(), len, mag_l.as_mut_ptr(), mag_r.as_mut_ptr());
        }
        assert!(mag_l.iter().all(|v| v.is_finite() && *v >= 0.0));

        // A supplied mask drives separation and frees cleanly.
        let mask = vec![0.5f32; frames * MODEL_BINS];
        unsafe {
            let stems = stemacle_separate_with_mask(
                l.as_ptr(), r.as_ptr(), len, SR as c_uint, mask.as_ptr(), mask.len());
            assert!(!stems.is_null());
            assert!((*stems).len > 0);
            stemacle_stems_free(stems);
        }
        // Weight helper matches the core.
        assert_eq!(stemacle_vocal_mask_weight_for_bin(0), 0.0);
        assert!(stemacle_vocal_mask_weight_for_bin(80) > 0.9);
    }

    #[test]
    fn estimate_tempo_ffi_writes_plausible_bpm() {
        // A 2 Hz click train → 120 BPM-ish; just assert the out-params get a
        // finite, in-range bpm and the grid offsets are written.
        let sr = SR;
        let len = sr * 4;
        let mut sig = vec![0.0f32; len];
        for i in (0..len).step_by(sr / 2) { sig[i] = 1.0; } // 2 Hz
        let (mut bpm, mut mo, mut bo, mut conf) = (0.0f32, -1.0f32, -1.0f32, -1.0f32);
        unsafe {
            stemacle_estimate_tempo(sig.as_ptr(), len, sr as c_uint,
                                    &mut bpm, &mut mo, &mut bo, &mut conf);
        }
        assert!(bpm >= 60.0 && bpm <= 240.0, "bpm out of range: {bpm}");
        assert!(mo >= 0.0 && bo >= 0.0 && conf >= 0.0, "grid offsets not written");
    }

    #[test]
    fn null_input_returns_null() {
        unsafe {
            assert!(stemacle_separate(std::ptr::null(), std::ptr::null(), 0, 0).is_null());
            // freeing null is a no-op, not a crash
            stemacle_stems_free(std::ptr::null_mut());
        }
    }

    #[test]
    fn loop_helpers_match_core() {
        // 120 BPM, 1-measure (2.0s) loop, transport 2.6s → end 4.0s.
        let end = stemacle_snap_loop_end(120.0, 0.0, 0.0, 60.0, 2.6, 2.0);
        assert!((end - 4.0).abs() < 1e-5);

        let mut start = 0.0f32;
        let mut e = 0.0f32;
        let fits = unsafe {
            stemacle_loop_range(120.0, 0.0, 0.0, 3.0, 2.5, 4.0, &mut start, &mut e)
        };
        assert_eq!(fits, 0, "4s loop must be rejected on a 3s track");

        assert!((stemacle_measure_length(120.0) - 2.0).abs() < 1e-6);
        assert!((stemacle_audible_stem_time(5.5, 2.0, 4.0, 1, 60.0) - 3.5).abs() < 1e-5);
    }
}
