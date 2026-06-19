# Stem Player — Product Context

## Register
product

## Users
Music fans and producers who want to isolate and remix stems from any track.
Primarily YEEZY / Kanye listeners familiar with the physical DONDA stem player device.

## Product Purpose
A browser-only audio stem separator. Drop any audio file; the app splits it into
drums, bass, vocals, and melody using a client-side ML model. Each stem is
independently playable, mutable, and loopable. No accounts, no uploads, no server.

## Feature List
- Load local audio by dropping a file on the device or choosing one through the center control.
- Load bundled sample tracks from the local `samples/` directory for same-origin playback.
- Decode and separate tracks entirely in the browser using ONNX Runtime Web plus browser DSP fallback behavior.
- Render four playable stems: drums, bass, vocals, and melody.
- Play, pause, restart, stop, seek, and view elapsed/total time.
- Control each stem from the device surface: tap to mute, drag diagonally to adjust volume.
- Control each stem from the panel: volume slider, mute, and headphones/solo isolation.
- Reset all silenced tracks with the unsilence control.
- Loop each stem independently with `1/4`, `1/2`, `1`, and `2` measure buttons.
- Detect tempo from the loaded audio, prefer plausible tempo candidates, and use the detected 4/4 measure offset for loop snapping.
- Preserve active loop ranges across seek/restart while clearing all loop state on new file loads.
- Reject loops that would spill past the end of the track and clear stale loop UI/state.

## Brand Tone
Sparse. Functional. Physical. The device IS the interface — no chrome, no marketing.
The aesthetic comes from Ye's product design sensibility: warm off-white, matte texture,
utilitarian clarity. Not sterile white. Not hip-hop loud. The quiet confidence of
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
