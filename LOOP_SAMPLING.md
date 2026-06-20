# Loop Sampling Contract

This document is the source of truth for loop behavior in `index.html`.

## What A Loop Is

Looping is stem-local playback repetition, not sample slicing.
Each stem can be looped independently with the `1/4`, `1/2`, `1`, and `2` measure buttons.

## Timing Rules

- Loop length is measured in fractions of a 4/4 measure, using the detected tempo-derived measure length.
- The app assumes common-time `4/4` for loop math through the `BEATS_PER_MEASURE` constant.
- Tempo detection separates beat period, beat phase, and 4/4 measure phase. If the downbeat is ambiguous, measure phase falls back to the detected beat phase instead of inventing a bar line.
- When a loop is enabled, the end point snaps to the next selected subdivision on the detected measure grid: `1/4` to the next beat, `1/2` to the next half-measure, and `1` / `2` to the next measure boundary.
- The looped region is the selected-length segment that is already playing: `loopStart = loopEnd - selectedLength`, clamped to the beginning of the track when needed.
- The stem keeps playing from its current offset when a loop is enabled, then wraps to `loopStart` only after reaching `loopEnd`.
- Loop start is computed from the snapped end, so pressing a loop button partway through a segment lets the current segment play out before repeating that same segment.

## Runtime Behavior

- Loop state is tracked per stem.
- Enabling a loop replaces only that stem source with `AudioBufferSourceNode.loop = true` and applies `loopStart` / `loopEnd`.
- Disabling a loop clears the active loop button for that stem and replaces only that stem source to rejoin the linear transport.
- Loops are applied independently, so one stem can loop while the others continue normally and are never restarted by another stem's loop change.

## Reset Behavior

- Loading a new file clears all loop state.
- Seeking or restarting playback preserves any active loop ranges.
- If a loop is too long to fit before the end of the track, the app rejects it and leaves the stem unlooped.

## Guardrails

Keep these invariants intact when touching loop code:

1. Loop buttons must remain tempo-quantized to the selected subdivision of the detected measure grid.
2. Loop state must stay stem-local.
3. New file loads must reset all active loops.
4. A rejected loop must not leave stale UI state behind.
5. Looping should never silently spill past the end of the track.

## Notes For Future Changes

- `measureLength()` derives a 4/4 measure from precise detected `state.bpm`, clamped to the supported tempo range. Do not round BPM before loop math.
- `state.beatOffset` stores the detected beat-grid phase; `state.measureOffset` stores the selected 4/4 bar phase used by loop snapping.
- The snap logic intentionally chooses the next selected subdivision boundary as the loop end, with a small epsilon so taps already on-grid stay on that boundary.
- The abstract timing invariants are modeled in `specs/LoopTiming.tla`.
- Sample loading and loop clearing live together in the file-load path, so changes there can break both sample selection and looping at once.
