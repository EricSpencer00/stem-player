# Stemacle Desktop Workbench Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the desktop wrapper into a working local music workbench with real library indexing, queue execution, tool/model detection, downloads, exports, and native handoff into the Stem Splitter route.

**Architecture:** Keep the browser routes intact while moving desktop-only responsibilities into a persistent Electron-side store and job runner. The native shell renders that state and invokes desktop jobs over IPC, while `/app/` consumes native file bytes when launched from the library.

**Tech Stack:** Electron, Node.js built-ins, ffprobe, ffmpeg, optional Demucs, optional yt-dlp, static HTML/CSS/JS, Node test runner

## Global Constraints

- Preserve the existing browser app at `/app/`.
- Keep the existing Stem Shuffle app at `/apps/stem-shuffle/`.
- Desktop-only capabilities must degrade gracefully when native tools are missing.
- Prefer stable per-track cache directories under the desktop data root.
- Cover backend behavior with automated tests before implementation code.

---

### Task 1: Expand desktop-state coverage and native helpers

**Files:**
- Create: `native/electron/desktop-tools.cjs`
- Create: `native/electron/desktop-jobs.cjs`
- Modify: `native/electron/stemacle-desktop.cjs`
- Test: `tests/native-desktop.test.mjs`

**Interfaces:**
- Consumes: `createDesktopStore(root, options?)`
- Produces: richer store state, tool detection helpers, queue runner helpers

- [ ] Add failing tests for library roots, tool detection, and richer cache metadata.
- [ ] Run `npm test -- --test-name-pattern "desktop service"` and confirm the new assertions fail for missing behavior.
- [ ] Implement helper modules and state normalization to include roots, settings, tool state, and richer model rows.
- [ ] Re-run `npm test -- --test-name-pattern "desktop service"` and confirm the new desktop-state assertions pass.

### Task 2: Add real analysis, download, and export jobs

**Files:**
- Modify: `native/electron/desktop-jobs.cjs`
- Modify: `native/electron/stemacle-desktop.cjs`
- Modify: `tests/native-desktop.test.mjs`

**Interfaces:**
- Consumes: queue helpers and executable adapters
- Produces: `enqueueAnalysis()`, `enqueueDownload()`, `enqueueExport()`, `waitForIdle()`

- [ ] Add failing tests for queued jobs completing with fake executables and for graceful failures when tools are missing.
- [ ] Run `npm test -- --test-name-pattern "desktop service"` and confirm job assertions fail first.
- [ ] Implement sequential queue execution, progress updates, state persistence, and test-only injection seams.
- [ ] Re-run `npm test -- --test-name-pattern "desktop service"` and confirm the job assertions pass.

### Task 3: Extend Electron IPC and native app launch integration

**Files:**
- Modify: `native/electron/main.cjs`
- Modify: `native/electron/preload.cjs`
- Modify: `app/index.html`
- Modify: `tests/native-desktop.test.mjs`
- Modify: `tests/stem-player.test.mjs`

**Interfaces:**
- Consumes: desktop store APIs
- Produces: IPC methods for state subscription, downloads, rescans, track file reads, and native desktop handoff into `/app/`

- [ ] Add failing tests for the new preload APIs, IPC channels, and native-track handoff markers in the splitter app.
- [ ] Run `npm test -- --test-name-pattern "electron bridge|native shell|desktop route"` and confirm the new assertions fail.
- [ ] Implement the IPC surface and the pending-track load path in `/app/`.
- [ ] Re-run the targeted tests and confirm the native handoff path is covered.

### Task 4: Turn the native shell into a real workbench UI

**Files:**
- Modify: `native/index.html`
- Modify: `tests/native-desktop.test.mjs`

**Interfaces:**
- Consumes: preload APIs and live desktop state
- Produces: real library controls, URL download intake, queue/export/session views, root management, and track actions

- [ ] Add failing HTML assertions for download controls, roots, cache/status details, and desktop actions.
- [ ] Run `npm test -- --test-name-pattern "desktop shell"` and confirm the UI assertions fail first.
- [ ] Implement the native-shell UI and state subscription wiring.
- [ ] Re-run the targeted tests and confirm the UI assertions pass.

### Task 5: Verify the full desktop pass and document it

**Files:**
- Modify: `docs/STEMACLE_SURFACES.md`
- Modify: `tests/native-desktop.test.mjs`

**Interfaces:**
- Consumes: completed desktop feature set
- Produces: updated product-surface docs and verification coverage

- [ ] Update the product-surface doc so desktop behavior matches the shipped implementation.
- [ ] Run `npm test`, `npm run native:prepare`, and `npm run desktop:pack`.
- [ ] Fix any regressions until the desktop suite, native bundle prep, and desktop packaging succeed.
- [ ] Commit the finished work on a non-`main` branch and push it to GitHub.
