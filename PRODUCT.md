# Stemacle — Product Context

## Register
product

## Users
Music fans and producers who want to isolate and remix stems from any track.
People who want a tactile, local way to split, loop, and recombine music without uploading files.

## Product Purpose
A browser-only audio stem separator. Drop any audio file; Stemacle splits it into
drums, bass, vocals, and melody using a client-side ML model. Each stem is
independently playable, mutable, and loopable. No accounts, no uploads, no server.

## Feature List
- Load local audio by dropping a file on the device or choosing one through the center control.
- Load bundled sample tracks from the local `samples/` directory for same-origin playback.
- Decode and separate tracks entirely in the browser using ONNX Runtime Web plus browser DSP fallback behavior.
- Recover from stalled remote model downloads by timing out the stream and continuing with browser DSP fallback.
- Render four playable stems: drums, bass, vocals, and melody, with a full-width visible-window audio overview, per-stem play cursor, and quarter/half/measure grid markers.
- Play, pause, restart, stop, seek, and view elapsed/total time.
- Keep the top circle as a passive physical display: center load/play control plus a bass/treble level meter, not a hidden mixer surface.
- Control each stem from the panel: volume slider, icon mute, icon headphones/solo isolation, and a dedicated spectrogram rail.
- Mute or unmute all stems from one persistent global toggle without resetting individual volume choices.
- Loop each stem independently with `1/4`, `1/2`, `1`, and `2` measure buttons, or use the All row to apply one linked loop across every stem.
- Swap loop monitoring between Mix mode, where looped stems play against the full track, and Solo mode, where the looped stem is cued through the headphones layer without mutating mute state.
- Keep the stem overview focused on the relevant audible window: normal playback follows a rolling slice, while active loops expand the window to include the earliest looped stem and current transport.
- Clicking an empty part of a stem overview seeks within the visible window; looping remains on the explicit quantized buttons.
- Detect tempo from the loaded audio, prefer plausible tempo candidates, and use the detected 4/4 measure offset for loop snapping.
- Preserve active loop ranges across seek/restart while clearing all loop state on new file loads.
- Reject loops that would spill past the end of the track and clear stale loop UI/state.

## Brand Tone
Sparse. Functional. Physical. The device IS the interface — no chrome, no marketing.
The aesthetic is warm off-white, matte texture, purple thick-line tentacle artwork, and
utilitarian clarity. Not sterile white. Not loud nightlife software. The quiet confidence of
something that doesn't need to explain itself.

## Anti-References
- Spotify / SoundCloud: too commercial, too colorful
- "Pro audio" tools (Audacity, Reaper): too utilitarian in the wrong way — industrial, not minimal
- Typical AI tools: cream-on-black with gradient borders
- Nightclub / neon / dark-mode DJ vibes

## Color Strategy
Restrained. The surface is warm cream throughout. No colored quadrants, no accent hues.
Depth through shadow and tone variation only. The one allowed exception: loop dots
may glow a very muted warm amber when active — like a recessed LED behind frosted material.

## Strategic Principles
- The circle is the product. It should feel like you're holding a physical object.
- No numbers, no labels that feel like software.
- Interactions should feel tactile: dragging adjusts volume like rubbing a surface.
- Every pixel of chrome removed is a pixel of music added.

## Loop Contract
- Loop behavior is documented in [LOOP_SAMPLING.md](./LOOP_SAMPLING.md).
- Treat loop timing, per-stem independence, and file-load resets as invariants.
