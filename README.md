# Stemacle

Stemacle is a local-first stem splitter and remix toy. Drop in a song, split it
into drums, vocals, bass, and melody, then mute, solo, loop, and recombine the
pieces without uploading the track anywhere.

The repo has a few surfaces because the project has moved through a few lives:
the browser app, native Apple apps, a Windows/Linux desktop app, the shared DSP
core, and a separation server for full-quality Demucs jobs. The current product
contract is in [PRODUCT.md](./PRODUCT.md), and the current surface map is in
[docs/STEMACLE_SURFACES.md](./docs/STEMACLE_SURFACES.md).

## Current Surfaces

- **Web app:** `app/index.html`, published at `https://stemacle.com/app/`.
  This is the gold master for splitter behavior, loop semantics, visual rhythm,
  and the tactile Stemacle feel.
- **Landing site:** `index.html`, plus `privacy/`, `support/`, `terms/`, and
  `apps/stem-shuffle/`. `npm run site:prepare` builds the Cloudflare Pages
  artifact in `dist/site`.
- **Apple apps:** `native/apple`, generated with XcodeGen. The `StemacleMac`
  and `StemacleiOS` targets share SwiftUI views, `StemacleKit`, and the
  `StemacleCore.xcframework` bridge to the Rust core.
- **Windows/Linux desktop:** `native/desktop`, a Slint UI over the shared Rust
  DSP core with native playback/export plumbing.
- **Shared DSP core:** `native/core/stemacle-dsp`, exposed to Apple through
  `native/core/stemacle-ffi`.
- **Models and queue server:** `models/` contains Demucs conversion/separation
  scripts. `server/` exposes a small FastAPI separation queue for clients that
  need full-quality htdemucs stems.

## Repository Map

- `app/` - canonical browser splitter.
- `apps/stem-shuffle/` - compatibility handoff page for the old shuffle surface.
- `assets/` and `samples/` - visual assets and bundled demo tracks.
- `docs/` - surface contracts, feature matrix, navigation notes, and wishlist.
- `fixtures/` - golden DSP data used by parity tests.
- `models/` - Demucs conversion and local separation helpers.
- `native/apple/` - SwiftUI macOS/iOS app, StemacleKit package, generated Xcode
  project, assets, and xcframework.
- `native/core/` - Rust workspace for DSP and FFI.
- `native/desktop/` - Slint desktop shell for Windows/Linux.
- `server/` - optional separation queue server.
- `specs/` - TLA+ specs for navigation and loop timing.
- `tests/` - Node structural tests, browser parity tests, native guards, and
  server tests.

## Useful Commands

```bash
npm test
npm run site:prepare
npm run core:test
npm run desktop:test
npm run apple:project
npm run apple:xcframework
```

Native Apple builds use the Xcode project in `native/apple`:

```bash
xcodebuild -project native/apple/Stemacle.xcodeproj \
  -scheme StemacleMac \
  -configuration Debug \
  -destination 'platform=macOS' build

xcodebuild -project native/apple/Stemacle.xcodeproj \
  -scheme StemacleiOS \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=<available simulator>' build
```

The old Electron/Capacitor/SwiftPM-macOS scaffolding has been removed: the
`main` entry, `electron`/`@capacitor` deps, the electron-builder `build` block,
and the dead `native:prepare`/`macos:*`/`windows:*`/`linux:*`/`webui:dev`/
`ios:add|sync|open` scripts are gone, along with `scripts/{prepare-native,
package-macos,serve-native,desktop-dispatch}.mjs`. The live release path is
`ios:archive|testflight|publish|validate` (real `xcodebuild` via
`scripts/ios-release.sh`); desktop release packaging is intentionally not wired
up yet. See `docs/SEPARATION_CONTRACTS.md` for the separation-server contracts.

## Tests

The default test command is intentionally lightweight:

```bash
npm test
```

It runs the Node structural and regression tests, plus the Rust core tests
through the native guard suite. For targeted native checks:

```bash
cargo test --manifest-path native/core/Cargo.toml
cargo test --manifest-path native/desktop/Cargo.toml
node --test tests/browser-parity.browser.mjs
```

The browser parity suite skips cleanly when Chromium is not available.

## Product Rules Worth Keeping In Mind

- The web app at `/app/` is canonical.
- Native macOS and iOS are SwiftUI parity-plus surfaces, not web wrappers.
- Windows/Linux is the Slint surface over the same Rust core.
- The four canonical stems are `drums`, `vocals`, `bass`, and `melody`.
- Loop behavior is part of the contract. See [LOOP_SAMPLING.md](./LOOP_SAMPLING.md).
- Privacy is part of the product: local files should stay local unless a user
  explicitly points a client at a separation server.

## More Documentation

- [Product context](./PRODUCT.md)
- [Surface contract](./docs/STEMACLE_SURFACES.md)
- [Developer guide](./docs/DEVELOPMENT.md)
- [Native feature matrix](./docs/FEATURE_MATRIX.md)
- [Navigation notes](./docs/NAVIGATION.md)
- [Stem splitting quality](./docs/STEM_SPLITTING_QUALITY.md)
- [Model notes](./models/README.md)
- [Separation server](./server/README.md)
