# Loop Sampling Contract

This document is the source of truth for loop behavior in `index.html`.

## What A Loop Is

Looping is stem-local playback repetition, not sample slicing.
Each stem can be looped independently with the `1/4`, `1/2`, `1`, and `2` measure buttons.

## Timing Rules

- Loop length is measured in fractions of a 4/4 measure, using the current tempo-derived measure length.
- When a loop is enabled, the start point snaps down to the current quarter-note boundary.
- The stem keeps playing from its current offset when a loop is enabled, then wraps to `loopStart` only after reaching `loopEnd`.
- Loop end is computed as `loopStart + measureCount * measureLength()`.

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

1. Loop buttons must remain tempo-quantized to quarter-note boundaries.
2. Loop state must stay stem-local.
3. New file loads must reset all active loops.
4. A rejected loop must not leave stale UI state behind.
5. Looping should never silently spill past the end of the track.

## Notes For Future Changes

- `measureLength()` currently derives a 4/4 measure from `state.bpm`.
- The snap logic intentionally chooses the current quarter-note partition, not the next measure.
- Sample loading and loop clearing live together in the file-load path, so changes there can break both sample selection and looping at once.
