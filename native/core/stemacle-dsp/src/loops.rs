//! Loop-boundary math — the invariant heart of the player. Ported from
//! `snapLoopEnd` / `snapLoopStart` / `loopRangeFor` / `audibleStemTime` in
//! `app/index.html` and the contract in `LOOP_SAMPLING.md`.
//!
//! These are pure functions of the transport position and the detected tempo
//! grid, so they are covered exhaustively with hand-computed expectations.

use crate::tempo::{clamp, BEATS_PER_MEASURE, BPM_FALLBACK, BPM_MAX, BPM_MIN};

/// The bar fractions exposed as loop buttons: 1/4, 1/2, 1, 2 measures.
pub const LOOP_BARS: [f32; 4] = [0.25, 0.5, 1.0, 2.0];

/// Tempo grid context needed to snap loops. Mirrors the relevant `state` fields.
#[derive(Clone, Copy, Debug)]
pub struct LoopGrid {
    pub bpm: f32,
    pub measure_offset: f32,
    pub beat_offset: f32,
    pub duration: f32,
}

impl LoopGrid {
    pub fn measure_length(&self) -> f32 {
        let bpm = if self.bpm.is_finite() {
            clamp(self.bpm, BPM_MIN, BPM_MAX)
        } else {
            BPM_FALLBACK
        };
        (60.0 / bpm) * BEATS_PER_MEASURE as f32
    }

    pub fn beat_length(&self) -> f32 {
        self.measure_length() / BEATS_PER_MEASURE as f32
    }

    /// Loop length in seconds for a given `LOOP_BARS` fraction.
    pub fn loop_length_for(&self, bars: f32) -> f32 {
        bars * self.measure_length()
    }

    /// Port of `snapLoopEnd`: snap the transport position up to the next grid
    /// boundary (or back to the boundary if within epsilon).
    pub fn snap_loop_end(&self, current_sec: f32, loop_length: f32) -> f32 {
        let measure = self.measure_length();
        if measure == 0.0 || !current_sec.is_finite() || self.duration == 0.0 {
            return 0.0;
        }
        let active_length = if loop_length.is_finite() && loop_length > 0.0 {
            loop_length
        } else {
            measure
        };
        let grid = measure.min(active_length);
        let raw_offset = if self.measure_offset.is_finite() {
            self.measure_offset
        } else if self.beat_offset.is_finite() {
            self.beat_offset
        } else {
            0.0
        };
        let offset = clamp(raw_offset, 0.0, (measure - 1e-6).max(0.0));
        let boundary = offset + ((current_sec - offset) / grid).floor() * grid;
        let next_boundary = boundary + grid;
        let epsilon = 0.03f32.min(grid * 0.25);
        if boundary >= 0.0 && (current_sec - boundary).abs() <= epsilon {
            return boundary;
        }
        next_boundary.max(0.0)
    }

    /// Port of `snapLoopStart`.
    pub fn snap_loop_start(&self, current_sec: f32, loop_length: f32) -> f32 {
        let end = self.snap_loop_end(current_sec, loop_length);
        let len = if loop_length.is_finite() && loop_length > 0.0 {
            loop_length
        } else {
            self.measure_length()
        };
        (end - len).max(0.0)
    }

    /// Port of `loopRangeFor`: returns `(start, end)` clamped so a loop never
    /// starts before zero.
    pub fn loop_range_for(&self, current_sec: f32, loop_length: f32) -> (f32, f32) {
        let length = if loop_length.is_finite() && loop_length > 0.0 {
            loop_length
        } else {
            self.measure_length()
        };
        let mut end = self.snap_loop_end(current_sec, length);
        let mut start = end - length;
        if start < 0.0 {
            start = 0.0;
            end = length;
        }
        (start, end)
    }

    /// Whether a snapped loop would run past the end of the track and must be
    /// rejected (mirrors the gold master's loop-rejection invariant).
    pub fn loop_fits(&self, current_sec: f32, loop_length: f32) -> bool {
        let (_, end) = self.loop_range_for(current_sec, loop_length);
        end <= self.duration + 1e-6
    }
}

/// Port of `audibleStemTime`: fold the transport position into an active loop
/// range so a looping stem repeats its window. `loop_dot >= 0` means active.
pub fn audible_stem_time(
    transport_sec: f32,
    loop_start: f32,
    loop_end: f32,
    loop_active: bool,
    duration: f32,
) -> f32 {
    let playback_offset = |sec: f32| -> f32 {
        let safe = if sec.is_finite() { sec } else { 0.0 };
        if duration == 0.0 {
            safe.max(0.0)
        } else {
            safe.max(0.0).min(duration)
        }
    };
    let mut audible = playback_offset(transport_sec);
    let loop_length = loop_end - loop_start;
    if loop_active && loop_length > 0.0 && audible >= loop_end {
        audible = loop_start + ((audible - loop_start) % loop_length);
    }
    playback_offset(audible)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn grid_120() -> LoopGrid {
        // 120 BPM → measure length = (60/120)*4 = 2.0s, beat = 0.5s.
        LoopGrid { bpm: 120.0, measure_offset: 0.0, beat_offset: 0.0, duration: 60.0 }
    }

    #[test]
    fn measure_and_beat_length() {
        let g = grid_120();
        assert!((g.measure_length() - 2.0).abs() < 1e-6);
        assert!((g.beat_length() - 0.5).abs() < 1e-6);
    }

    #[test]
    fn snap_end_rounds_up_to_grid() {
        let g = grid_120();
        let one_measure = g.loop_length_for(1.0); // 2.0s
        // At 2.6s, next 2.0s boundary is 4.0s.
        assert!((g.snap_loop_end(2.6, one_measure) - 4.0).abs() < 1e-6);
        // Within epsilon of a boundary snaps back to it.
        assert!((g.snap_loop_end(4.01, one_measure) - 4.0).abs() < 1e-6);
    }

    #[test]
    fn loop_range_never_starts_negative() {
        let g = grid_120();
        let two_measures = g.loop_length_for(2.0); // 4.0s
        let (start, end) = g.loop_range_for(1.0, two_measures);
        assert_eq!(start, 0.0);
        assert!((end - 4.0).abs() < 1e-6);
    }

    #[test]
    fn quarter_bar_loop_grid() {
        let g = grid_120();
        let quarter = g.loop_length_for(0.25); // 0.5s
        // grid = min(measure=2.0, 0.5) = 0.5; at 1.2s → next boundary 1.5s.
        assert!((g.snap_loop_end(1.2, quarter) - 1.5).abs() < 1e-6);
    }

    #[test]
    fn loop_rejected_past_end_of_track() {
        let mut g = grid_120();
        g.duration = 3.0;
        let two_measures = g.loop_length_for(2.0); // 4.0s > 3.0s track
        assert!(!g.loop_fits(2.5, two_measures));
        // A one-measure (2.0s) loop near the start still fits.
        assert!(g.loop_fits(0.5, g.loop_length_for(1.0)));
    }

    #[test]
    fn measure_offset_shifts_grid() {
        let mut g = grid_120();
        g.measure_offset = 0.3; // downbeat at 0.3s
        let one_measure = g.loop_length_for(1.0);
        // boundaries at 0.3, 2.3, 4.3 ... at 1.0s → next boundary 2.3s.
        assert!((g.snap_loop_end(1.0, one_measure) - 2.3).abs() < 1e-5);
    }

    #[test]
    fn corrupt_tempo_metadata_falls_back_to_finite_loop_grid() {
        let g = LoopGrid {
            bpm: f32::NAN,
            measure_offset: f32::NAN,
            beat_offset: f32::NAN,
            duration: 30.0,
        };
        let measure = g.measure_length();
        assert!(measure.is_finite());
        assert!((measure - 2.0).abs() < 1e-6);

        let (start, end) = g.loop_range_for(3.0, f32::NAN);
        assert!(start.is_finite());
        assert!(end.is_finite());
        assert!((start - 2.0).abs() < 1e-6);
        assert!((end - 4.0).abs() < 1e-6);
    }

    #[test]
    fn adversarial_loop_grids_stay_finite_and_monotonic() {
        let bpms = [f32::NAN, f32::INFINITY, 0.0, 59.0, 60.0, 91.0, 240.0, 999.0];
        let offsets = [f32::NAN, f32::NEG_INFINITY, -1.0, 0.0, 0.25, 99.0];
        let durations = [0.0, 0.1, 3.0, 30.0, f32::NAN];
        let currents = [f32::NAN, f32::NEG_INFINITY, -2.0, 0.0, 0.03, 2.999, 400.0];
        let lengths = [f32::NAN, f32::INFINITY, -1.0, 0.0, 0.25, 0.5, 2.0, 999.0];

        for bpm in bpms {
            for measure_offset in offsets {
                for duration in durations {
                    let grid = LoopGrid { bpm, measure_offset, beat_offset: measure_offset, duration };
                    assert!(grid.measure_length().is_finite());
                    for current in currents {
                        for length in lengths {
                            let snap = grid.snap_loop_end(current, length);
                            assert!(snap.is_finite(), "snap bpm={bpm} offset={measure_offset} duration={duration} current={current} length={length}");

                            let (start, end) = grid.loop_range_for(current, length);
                            assert!(start.is_finite(), "start bpm={bpm} offset={measure_offset} duration={duration} current={current} length={length}");
                            assert!(end.is_finite(), "end bpm={bpm} offset={measure_offset} duration={duration} current={current} length={length}");
                            assert!(start >= 0.0, "start before zero: {start}");
                            assert!(end >= start, "end before start: {start}..{end}");

                            if grid.loop_fits(current, length) {
                                assert!(duration.is_finite() && duration >= 0.0);
                                assert!(end <= duration + 1e-6, "fit loop exceeds duration: {end} > {duration}");
                            }
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn audible_time_folds_into_active_loop() {
        // loop [2.0, 4.0); transport 5.5 → 2.0 + (3.5 % 2.0) = 3.5.
        let a = audible_stem_time(5.5, 2.0, 4.0, true, 60.0);
        assert!((a - 3.5).abs() < 1e-6);
        // inactive loop passes through.
        let b = audible_stem_time(5.5, 2.0, 4.0, false, 60.0);
        assert!((b - 5.5).abs() < 1e-6);
    }
}
