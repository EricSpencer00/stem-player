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
use stemacle_dsp::{separate, CoherenceSeparator};

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
