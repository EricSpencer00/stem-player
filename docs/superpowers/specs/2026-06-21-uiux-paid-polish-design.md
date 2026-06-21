# Stemacle UI/UX Polish for a Paid ($3) Release — Design

**Date:** 2026-06-21
**Register:** product
**Surfaces:** iOS (native SwiftUI), Desktop (macOS SwiftUI + Electron shell)
**Out of scope:** the canonical web app at `/app/` (gold master — untouched)

## Why

Stemacle is moving to a **paid-upfront $2.99** App Store tier. The app must feel
correct, fast, and worth paying for. An audit of desktop + iOS surfaced concrete
gaps in the four areas the owner flagged (caching, worker jobs, library, reviews)
plus correctness bugs that make the app feel broken or unfinished.

Monetization decision: **paid upfront** (price tier set in App Store Connect). No
StoreKit purchase/paywall code is written; the only StoreKit usage is the native
review prompt.

## Findings → Fixes (this pass)

### iOS

1. **Audio session (P0).** No `AVAudioSession` is configured, so `AVAudioEngine`
   runs under the default `.soloAmbient` category and is **silenced by the ring/
   silent switch** and stops on lock. Fix: configure `.playback` + `setActive`,
   handle interruptions, add `UIBackgroundModes: [audio]` so playback survives
   lock/background.

2. **Dead Settings toggles (P0).** `keepScreenAwake`, `preferSoloLoopMonitor`,
   `showWaveformHints` are shown but never read. Fix: wire each —
   - `keepScreenAwake` → `UIApplication.shared.isIdleTimerDisabled` while playing.
   - `preferSoloLoopMonitor` → default loop monitor mode on new track loads.
   - `showWaveformHints` → gate the in-player hint copy.

3. **Stem caching (P1).** Reopening a library track re-runs full ONNX separation
   every time. Fix: a `StemResultCache` that persists per-track stem buffers
   (`.caf`) + a `meta.json` (duration, tempo, overview) under Application Support.
   `load()` checks the cache first; reopen becomes near-instant.

4. **Cancelable processing (P1).** The full-screen `ProcessingOverlay` has no way
   out. Fix: `cancelLoad()` on the view model + a Cancel button in the overlay.

5. **Haptics (P2).** Zero haptics despite the "physical device" thesis. Fix: a
   `StemacleHaptics` helper fired on play/pause, loop engage, mute, split success,
   and errors.

6. **Native review prompt (P2).** "Leave a Review" only opens a URL. Fix: StoreKit
   `requestReview` after the user's 3rd successful split (once per app version),
   and point the Settings link at the App Store write-review deep link.

### Desktop (Demucs onboarding)

7. **Honest high-quality onboarding.** High-quality Demucs only runs in the
   non-sandboxed downloadable desktop build; the App Store macOS build is
   fast-preview/on-device. Today this is silent ("install demucs to run"). Fix:
   - Electron `native/index.html`: when Demucs is unavailable, show an actionable
     card — copyable install command, a re-check action, and a setup guide link.
   - macOS SwiftUI Settings: a short, honest "High-quality engine" explainer with
     a guide link (no fake detection inside the sandbox).

## Testing

This repo verifies native surfaces with Node `node:test` source-pattern assertions
(`tests/native-ios.test.mjs`, `tests/native-desktop.test.mjs`). Each fix above adds
or extends an assertion locking in the new contract. `npm test` is the gate;
`swift build --package-path native/macos` and the iOS `xcodebuild` compile are the
secondary checks per the release contract.

## Invariants preserved

- Loop contract (`LOOP_SAMPLING.md`) untouched.
- Web app `/app/` untouched.
- Local-first: cache lives on-device under Application Support; no uploads.
