# iOS Local Model Splitter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the weak iOS heuristic splitter with a local ONNX-backed stem separation path that stays in sync and stops maxing out the spectrogram lanes.

**Architecture:** Use ONNX Runtime Swift Package Manager on iOS to mirror the web app's local model path, then keep the existing STFT/HPSS/bass-melody post-processing so timing and buffer lengths remain stable. Preserve the current SwiftUI playback contract, but switch the split source from heuristic preview stems to model-produced vocal/accompaniment separation with deterministic trimming and normalization.

**Tech Stack:** Swift, SwiftUI, AVFoundation, ONNX Runtime Swift Package Manager, XCTest

## Global Constraints

- Stay fully local/offline after model download and cache warmup.
- Preserve four stems: drums, vocals, bass, and melody.
- Keep buffer lengths phase-locked to the source track duration.
- Reuse the web app's split contract: STFT, vocal masking, HPSS-style masking, bass low-pass, melody residual, ISTFT.
- Keep the iOS app native; do not reintroduce a web runtime.

---

### Task 1: Add regression tests for the iOS local model path

**Files:**
- Modify: `tests/native-ios.test.mjs`

**Interfaces:**
- Consumes: `NativeStemSplitter.swift`, `StemPlayerViewModel.swift`
- Produces: test coverage for model-backed separation, split contract stability, and non-saturated spectral output

- [ ] **Step 1: Write the failing test**

Add assertions that the native splitter references ONNX Runtime Swift Package Manager and no longer depends on the old long-track IIR preview branch.

- [ ] **Step 2: Run the targeted test to verify it fails**

Run: `npm test -- tests/native-ios.test.mjs`
Expected: FAIL because the ONNX-backed model path is not yet present.

- [ ] **Step 3: Add a spectrogram scaling regression**

Assert that `spectralOverview` or its replacement uses compressed, non-peak-only normalization so lanes do not clamp to 1.0 for every stem.

- [ ] **Step 4: Verify the new test fails for the current code**

Run: `npm test -- tests/native-ios.test.mjs`
Expected: FAIL on the new normalization assertions.

### Task 2: Wire ONNX Runtime into the iOS app target

**Files:**
- Modify: `native/ios/App/App.xcodeproj/project.pbxproj` or the Xcode-managed package references if needed
- Modify: `native/ios/App/CapApp-SPM/Package.swift`
- Modify: `native/ios/App/App/NativeStemSplitter.swift`

**Interfaces:**
- Consumes: ONNX Runtime Swift APIs (`ORTEnv`, `ORTSessionOptions`, `ORTSession`, `ORTValue`)
- Produces: a cached, local inference session for the vocal separation model

- [ ] **Step 1: Add the failing build expectation**

Make the tests look for ONNX Runtime symbols and model-loading code paths that do not exist yet.

- [ ] **Step 2: Add the dependency**

Add the Swift package dependency for `https://github.com/microsoft/onnxruntime-swift-package-manager` and link the runtime into the app target.

- [ ] **Step 3: Implement a model cache**

Store downloaded model bytes in app storage so first-run download is one-time and future runs stay offline.

- [ ] **Step 4: Create the session**

Build a reusable ONNX session object during splitter setup and keep it alive across splits.

- [ ] **Step 5: Run the iOS tests**

Run: `npm test -- tests/native-ios.test.mjs`
Expected: PASS for dependency and symbol checks once the runtime is wired correctly.

### Task 3: Replace heuristic splitting with the model-backed web-style pipeline

**Files:**
- Modify: `native/ios/App/App/NativeStemSplitter.swift`

**Interfaces:**
- Consumes: ONNX vocal/accompaniment model outputs
- Produces: `StemSplitResult` with better-aligned stems and unchanged consumer APIs

- [ ] **Step 1: Port the web segmentation flow**

Implement 512-frame segments, 1024 model bins, and the same magnitude/mask shaping used by the web splitter.

- [ ] **Step 2: Keep the post-processing contract**

Run HPSS on the accompaniment branch, then derive bass with a low-pass spectral split and melody from the high residual.

- [ ] **Step 3: Trim and pad to the decoded source length**

Ensure all stem buffers are trimmed or padded to exactly match the input duration so playback scheduling stays in sync.

- [ ] **Step 4: Remove or bypass the old long-track IIR preview branch**

Delete the fallback that was producing phase drift and weak stem separation.

- [ ] **Step 5: Run the splitter contract tests**

Run: `npm test -- tests/native-ios.test.mjs`
Expected: PASS for the split pipeline and sync-related assertions.

### Task 4: Fix spectral lane normalization

**Files:**
- Modify: `native/ios/App/App/NativeStemSplitter.swift`
- Modify: `native/ios/App/App/StemPlayerViewModel.swift`

**Interfaces:**
- Consumes: per-stem buffers and windowed playback position
- Produces: spectral values that reflect dynamics instead of flatlined full-scale bars

- [ ] **Step 1: Write the failing normalization check**

Add a test that catches the current maxed-out display behavior on stems with broad energy.

- [ ] **Step 2: Implement compressed overview values**

Use a log or root-compressed amplitude metric, then normalize against a robust per-stem percentile instead of raw peak-only scaling.

- [ ] **Step 3: Keep the moving window logic**

Retain the existing windowed spectral view and cursor behavior so the display still tracks playback correctly.

- [ ] **Step 4: Verify the lane values now have range**

Run: `npm test -- tests/native-ios.test.mjs`
Expected: PASS, with the spectrogram regression now satisfied.

### Task 5: Build and sanity-check the iOS target

**Files:**
- Modify: whatever the compiler reports if platform-specific fixes are needed

**Interfaces:**
- Consumes: the updated splitter and runtime integration
- Produces: a buildable iOS app with the new local model path

- [ ] **Step 1: Run the focused test file**

Run: `npm test -- tests/native-ios.test.mjs`

- [ ] **Step 2: Run the iOS simulator build**

Run: `xcodebuild -project native/ios/App/App.xcodeproj -scheme App -configuration Debug -destination 'platform=iOS Simulator,name=<available simulator>' build`

- [ ] **Step 3: Fix any compile or runtime integration issues**

Only touch the smallest set of files needed to restore a green build.

- [ ] **Step 4: Final verification**

Run the focused test suite again and confirm the app build remains green.
