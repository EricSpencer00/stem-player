# Stemacle macOS Swift / Windows Web Design

## Goal

Lock the desktop direction around a native SwiftUI workbench that matches the perfect Stemacle web app first, then adds desktop capabilities above and beyond the browser.

`https://stemacle.com/app/` is perfect and canonical. `https://ericspencer.us/stem-player` points to that app. Desktop work must not change the web app or use native polish as a reason to drift from the working splitter.

## Chosen Approach

Use a hybrid SwiftUI desktop app. SwiftUI owns the desktop UI: windows, menus, sidebar navigation, file/folder intake, local library list, Finder reveal, packaging entitlements, and the calm Stemacle physical frame. The existing local web instruments stay embedded through `WKWebView` for Stem Splitter and Stem Shuffle until native implementations reach full parity.

This is best for speed, usability, and design because it gives desktop a native SwiftUI product shell while preserving the perfect web app's instrument contract. The goal is not a prettier wrapper. The goal is parity with the web app plus desktop-native library, project, queue, export, and file-system power.

## Platform Responsibilities

Desktop SwiftUI owns:

- SwiftUI workbench and navigation
- local file/folder intake through `NSOpenPanel`
- library list and Finder reveal
- bundled local web instruments through `WKWebView`
- App Store sandbox entitlements
- GitHub Release `.app` zip packaging
- project history, saved loop/shuffle ideas, export state, and native shortcuts
- future native splitter and shuffle views only when they match the web app first

Web owns:

- `/app/` perfect browser splitter
- `/apps/stem-shuffle/`
- public landing page and release download routing
- legacy `https://ericspencer.us/stem-player` redirect to `https://stemacle.com/app/`

## Design Direction

DNA: technical product with Stemacle's physical warmth. The desktop app should feel native and quiet, not like a framed webpage. Use the warm cream/plum Stemacle palette, native SF typography, matte circle as the main visual object, and dense but calm library controls.

The web instrument should remain visually identical inside the native shell until a SwiftUI instrument matches it. The SwiftUI shell should add confidence around it: native menus, consistent sidebar, real file actions, project recall, and a first screen that looks designed even before audio is loaded.

## Packaging

Local iteration:

- `npm run webui:dev` serves the bundled web workbench quickly.
- `npm run macos:dev` launches the SwiftUI Mac app.

Release:

- `npm run macos:package` builds and wraps the SwiftUI app bundle into `release/Stemacle-mac-arm64.zip`.
- `npm run macos:appstore` uses the same app bundle path with App Store distribution flags and installer signing.
- Any compatibility packages should follow the SwiftUI desktop product direction and must not redefine desktop away from parity-plus.

## Testing

Tests should assert the platform split directly:

- package scripts dispatch desktop to the SwiftUI Mac workbench
- macOS Swift package exists and imports SwiftUI/WebKit
- Mac entitlements include app sandbox and user-selected file access
- release workflow no longer builds Electron macOS DMGs
- docs preserve the contract that `stemacle.com/app` is the perfect canonical app and `ericspencer.us/stem-player` redirects to it

## Success Criteria

- The Mac app builds with SwiftPM.
- `npm run macos:dev` opens a usable native shell.
- The desktop shell preserves the perfect web app's splitter behavior and visual hierarchy.
- `npm run webui:dev` serves the web workbench for fast visual iteration.
- The release workflow uses the SwiftUI Mac package.
- `npm test` passes after the pre-existing iOS native test failures are closed.
