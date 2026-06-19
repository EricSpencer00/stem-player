# Loop Sampling Contract

This document is the source of truth for loop behavior in `index.html`.

## What A Loop Is

Looping is stem-local playback repetition, not sample slicing.
Each stem can be looped independently with the `1`, `2`, `4`, and `8` bar buttons.

## Timing Rules

- Loop length is measured in bars, using the current tempo-derived bar length.
- When a loop is enabled, the start point snaps to the next bar boundary.
- If playback is already sitting on a boundary, the loop starts there instead of skipping ahead.
- Loop end is computed as `loopStart + barCount * measureLength()`.

## Runtime Behavior

- Loop state is tracked per stem.
- Enabling a loop sets the stem source to `AudioBufferSourceNode.loop = true` and applies `loopStart` / `loopEnd`.
- Disabling a loop clears the active loop button for that stem and returns playback to normal linear transport.
- Loops are applied independently, so one stem can loop while the others continue normally.

## Reset Behavior

- Loading a new file clears all loop state.
- Seeking or restarting playback preserves any active loop ranges.
- If a loop is too long to fit before the end of the track, the app rejects it and leaves the stem unlooped.

## Guardrails

Keep these invariants intact when touching loop code:

1. Loop buttons must remain bar-quantized.
2. Loop state must stay stem-local.
3. New file loads must reset all active loops.
4. A rejected loop must not leave stale UI state behind.
5. Looping should never silently spill past the end of the track.

## Notes For Future Changes

- `measureLength()` currently derives a bar from `state.bpm`.
- The snap logic intentionally allows the loop to begin on the next bar boundary when the transport is between bars.
- Sample loading and loop clearing live together in the file-load path, so changes there can break both sample selection and looping at once.
