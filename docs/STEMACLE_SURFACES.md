# Stemacle Product Surfaces

Stemacle has one identity across web, desktop, and iOS: the warm matte circle, four-stem controls, loop contract, local-first privacy model, and purple tentacle artwork stay recognizable everywhere. The web app is the gold master. Native surfaces match it first, then add platform-native capabilities that make the same instrument feel more powerful on that device.

## Web App

The web app at `https://stemacle.com/app/` is perfect and canonical. It is the source of truth for the splitter's behavior, pacing, visual hierarchy, and tactile interaction model. Do not change it as part of native polish unless Eric explicitly asks for web-app changes.

`https://ericspencer.us/stem-player` points to `https://stemacle.com/app/`. Treat that legacy URL as a redirect to the perfect canonical web app, not as a second product surface or a forked deployment.

The web app keeps every current player feature: four stems, mute and headphones isolation, volume, spectrogram lanes, loop buttons, all-stem loop row, tempo-grid snapping, Mix/Solo loop monitoring, file-load reset behavior, sample tracks, and browser-only processing.

The browser path uses ONNX Runtime Web when the model loads and falls back to browser DSP when model downloads stall or fail. It does not claim ownership over folders, OS-level background jobs, Finder integration, persistent desktop cache directories, or native iOS navigation.

Best for:

- trying Stemacle immediately from `https://stemacle.com/app/`
- splitting one local file without installing anything
- preserving the full web player contract
- validating UI and loop behavior before native surfaces borrow it

## Desktop App

Desktop is the SwiftUI Stemacle app. The desktop product direction is not an Electron wrapper around a website. SwiftUI owns the native workbench and must make the app feel like the same perfect Stemacle instrument, elevated with desktop power.

The desktop app must match the web app first:

- same warm matte circle as the first visual signal
- same four-stem model: drums, bass, vocals, and melody
- same transport, mute, headphones isolation, volume, loop, Mix/Solo, sample, and reset behavior
- same loop contract, including per-stem independence, all-stem linked loops, tempo-grid snapping, and new-file loop resets
- same tactile restraint: no dashboard chrome competing with the instrument

Then desktop should go above and beyond:

- SwiftUI app shell in `native/macos`
- WKWebView loading of the prepared local `/app/` and `/apps/stem-shuffle/` bundles
- native `NSOpenPanel` file and folder intake
- local library list with reveal-in-Finder actions
- project history and saved loop/shuffle ideas
- background analysis and export queues
- model and tool capability state surfaced as product UI, not a dev console
- durable per-track cache paths and local-first storage clarity
- native menus, keyboard shortcuts, drag/drop, command palette, and desktop notifications
- app sandbox entitlements for App Store packaging
- GitHub Release `.app` zip packaging through `npm run macos:package`
- App Store package path through `npm run macos:appstore`

Any compatibility package that still uses a web workbench should follow this SwiftUI desktop direction where possible and must not redefine the product direction away from SwiftUI parity-plus.

## iOS App

The iOS app is a native SwiftUI Stemacle app. Like desktop, it must match the perfect web app first, then add mobile-native strengths. It boots a SwiftUI shell from `AppDelegate`, uses iOS navigation patterns (`TabView`, `NavigationStack`, menus, sheets, document picker, lists, toggles), and compiles the splitter into Swift through `NativeStemSplitter`. Capacitor remains useful as a packaging/resource legacy, but it is no longer the iOS runtime direction.

iOS must keep the same tactile splitter and visual parity with the web player:

- the Stemacle circle as the first player signal
- warm cream surfaces, restrained purple actions, and matte panel depth
- tentacle assets at the bottom of the screen, including the bottom tentacle border and background texture used by `StemacleBackground`
- four stems: drums, vocals, bass, and melody
- play, pause, stop, restart, seek, elapsed/total time, and bundled sample loading
- per-stem volume, mute, headphones isolation, spectrogram lanes, visible-window scrub seeking, and per-stem play cursors
- persistent global mute without resetting per-stem volume choices
- per-stem `1/4`, `1/2`, `1`, and `2` measure loops
- linked all-stem loops
- Mix/Solo loop monitoring
- tempo detection and loop snapping
- rejection of loops that would run past the end of the track

iOS then goes above and beyond with mobile-native behavior:

- `NativeStemSplitter` uses AVFoundation buffers plus native Swift separation: short clips can run the browser-style spectral DSP path (STFT, vocal masking, HPSS-style masking, bass low-pass, melody residual, ISTFT), while long tracks use a full-duration IIR stem preview branch so iOS does not lock the app during first-run splitting
- the app uses document picker intake and sandboxed app storage instead of drag/drop
- recent projects and lightweight local library built for touch
- share sheet exports and project sharing when added
- haptics, sheet transitions, thumb-reachable controls, and iPad layouts
- no desktop Demucs worker pipeline
- no OS folder recursion
- no reveal in Finder
- Stem Shuffle remains separate from Stem Player for now, with a primitive native shuffle tab for pair picking, crossfade, lead A/B, and stem blend controls

## Navigation Direction

The native app should feel closer to Apple Music, Suno, and CapCut than to a web page in a web view. The first screen is the working Stem Splitter, visually aligned with the perfect web app. Shuffle, Library, Projects, and Settings are native destinations, not stacked marketing routes. Import uses sheets and document picker. Settings use native forms. Project history belongs in a list. Player controls stay tactile and compact instead of becoming a dashboard.

## Release Contract

Every release should verify all surfaces:

- web bundle: `npm run site:prepare`
- canonical web app availability at `https://stemacle.com/app/`
- legacy redirect from `https://ericspencer.us/stem-player` to `https://stemacle.com/app/`
- desktop SwiftUI bundle: `npm run macos:package` on macOS with release signing credentials for distribution
- iOS resources: `npm run native:prepare`
- iOS native compile: `xcodebuild -project native/ios/App/App.xcodeproj -scheme App -configuration Debug -destination 'platform=iOS Simulator,name=<available simulator>' build`
- regression suite: `npm test`

Stemacle.com points at the Cloudflare Pages output in `dist/site`. The current web app remains perfect at `/app/`. Desktop and iOS now compile native SwiftUI surfaces that must match the web app before adding their own platform features.
