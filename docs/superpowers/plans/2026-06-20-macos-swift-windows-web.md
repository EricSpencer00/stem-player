# SwiftUI Desktop Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a SwiftUI desktop app that matches the perfect Stemacle web app first, then adds native desktop features above and beyond the browser.

**Architecture:** Add a SwiftPM desktop app under `native/macos` with SwiftUI chrome and WKWebView-backed local instruments. Preserve `https://stemacle.com/app/` as the gold master, route `https://ericspencer.us/stem-player` to it, and keep the web workbench easy to serve locally while native desktop grows parity-plus features.

**Tech Stack:** SwiftUI, WebKit, AVFoundation, Swift Package Manager, Electron Builder, Node.js scripts, GitHub Actions.

## Global Constraints

- Preserve the perfect browser app at `/app/`.
- Preserve the legacy `ericspencer.us/stem-player` redirect to `https://stemacle.com/app/`.
- Desktop SwiftUI must match the web app's splitter behavior, loop contract, and visual hierarchy before adding native-only features.
- Preserve Stem Shuffle at `/apps/stem-shuffle/`.
- macOS must not package the Electron app.
- Any compatibility web workbench package must not redefine desktop away from the SwiftUI parity-plus direction.
- The visual direction stays warm cream, matte, restrained, and Stemacle-native.
- Use test-first changes for platform packaging behavior.

---

### Task 1: Assert the SwiftUI Desktop Contract

**Files:**
- Modify: `tests/stem-player.test.mjs`

**Interfaces:**
- Consumes: existing package/release tests.
- Produces: failing assertions for the SwiftUI package, scripts, entitlements, web-app preservation, redirect contract, and release workflow.

- [x] Add failing tests for `native/macos/Package.swift`, `StemacleMacApp.swift`, `StemacleMac.entitlements`, platform dispatch scripts, `stemacle.com/app` preservation, redirect behavior, and macOS Swift release artifacts.
- [x] Run `npm test -- --test-name-pattern "macOS packaging uses|release workflow publishes"` and confirm failures mention missing macOS Swift files and old Electron Mac release commands.

### Task 2: Build the macOS SwiftUI Demo

**Files:**
- Create: `native/macos/Package.swift`
- Create: `native/macos/StemacleMac.entitlements`
- Create: `native/macos/Sources/StemacleMac/StemacleMacApp.swift`

**Interfaces:**
- Consumes: prepared local web bundle from `dist/native`.
- Produces: `StemacleMac` Swift executable with SwiftUI workbench, file/folder intake, library list, Finder reveal, and `WKWebView` instruments that match the perfect web app.

- [x] Add SwiftPM package targeting macOS 14.
- [x] Implement SwiftUI sidebar, workbench, library, exports, and instrument routes.
- [x] Implement `NSOpenPanel` file/folder intake and `WKWebView.loadFileURL`.
- [x] Run `swift build --package-path native/macos -c release` and fix compile errors.

### Task 3: Add Fast Demo and Packaging Scripts

**Files:**
- Create: `scripts/desktop-dispatch.mjs`
- Create: `scripts/serve-native.mjs`
- Create: `scripts/package-macos.mjs`
- Modify: `package.json`

**Interfaces:**
- Consumes: `npm run native:prepare`, SwiftPM release binary, Electron Builder.
- Produces: `npm run macos:dev`, `npm run webui:dev`, `npm run macos:package`, `npm run windows:dist`, `npm run linux:dist`, platform-aware `desktop:*`.

- [x] Add desktop dispatch script.
- [x] Add static web workbench server.
- [x] Add macOS app bundle wrapper with signing and App Store package mode.
- [x] Update package scripts and remove Electron macOS build config.
- [x] Run `npm run macos:build` and `npm run webui:dev`.

### Task 4: Update Release and Surface Contracts

**Files:**
- Modify: `.github/workflows/release.yml`
- Modify: `index.html`
- Modify: `docs/STEMACLE_SURFACES.md`

**Interfaces:**
- Consumes: platform scripts from Task 3.
- Produces: public release workflow and docs matching the SwiftUI Mac / Electron Windows-Linux split.

- [x] Update release workflow to call `npm run macos:package`.
- [x] Remove public Mac DMG and Intel Electron links from the landing page.
- [x] Document SwiftUI desktop parity-plus responsibilities.

### Task 5: Verify Live

**Files:**
- No new files expected.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: verified local web demo, Swift build, Swift app launch, visual QA evidence, and full regression status.

- [x] Run `npm test`.
- [x] Run `npm run native:prepare`.
- [x] Run `npm run webui:dev` and inspect with browser automation.
- [x] Run `open -n release/Stemacle.app --args --repo-root "$PWD"` and verify the live SwiftUI shell launches.
- [x] Capture visual QA evidence for the web workbench; OS display capture was blocked, so Mac shell verification used live launch plus signature/process checks.
