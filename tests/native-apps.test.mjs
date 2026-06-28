import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

// Structural guards for the native-rewrite architecture: a shared Rust core
// with native UI shells per platform (Apple SwiftUI, Win/Linux Slint) and a
// per-OS model pipeline. Replaces the old WKWebView/Capacitor/Electron shell
// tests, which asserted code removed in the native rewrite.

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const r = (...p) => join(root, ...p);
const read = (...p) => readFileSync(r(...p), 'utf8');

test('shared Rust core workspace has the DSP + FFI crates', () => {
  const ws = read('native', 'core', 'Cargo.toml');
  assert.match(ws, /stemacle-dsp/);
  assert.match(ws, /stemacle-ffi/);
  for (const f of ['fft.rs', 'stft.rs', 'hpss.rs', 'tempo.rs', 'loops.rs', 'lib.rs']) {
    assert.ok(existsSync(r('native', 'core', 'stemacle-dsp', 'src', f)), `dsp/${f}`);
  }
  // The Separator seam exists so neural models can be injected per platform.
  assert.match(read('native', 'core', 'stemacle-dsp', 'src', 'lib.rs'), /trait Separator/);
});

test('C ABI header mirrors the FFI surface', () => {
  const h = read('native', 'core', 'stemacle-ffi', 'include', 'stemacle.h');
  const rs = read('native', 'core', 'stemacle-ffi', 'src', 'lib.rs');
  for (const sym of [
    'stemacle_separate',
    'stemacle_stems_free',
    'stemacle_snap_loop_end',
    'stemacle_loop_range',
    'stemacle_measure_length',
    'stemacle_audible_stem_time',
  ]) {
    assert.match(h, new RegExp(sym), `header declares ${sym}`);
    assert.match(rs, new RegExp(`extern "C" fn ${sym}`), `ffi defines ${sym}`);
  }
});

test('Apple apps are native SwiftUI over StemacleKit, not a webview shell', () => {
  const project = read('native', 'apple', 'project.yml');
  assert.match(project, /StemacleMac:/);
  assert.match(project, /StemacleiOS:/);
  assert.match(project, /platform: macOS/);
  assert.match(project, /platform: iOS/);
  assert.match(project, /package: StemacleKit/);

  const app = read('native', 'apple', 'Stemacle', 'StemacleApp.swift');
  assert.match(app, /import SwiftUI/);
  assert.doesNotMatch(app, /WKWebView|WebKit/);

  // StemacleKit binds the shared Rust core via the XCFramework.
  const pkg = read('native', 'apple', 'StemacleKit', 'Package.swift');
  assert.match(pkg, /StemacleCore\.xcframework/);
  assert.match(read('native', 'apple', 'StemacleKit', 'Sources', 'StemacleKit', 'StemacleKit.swift'),
    /stemacle_separate/);

  // Proper asset catalog with an AppIcon + brand accent.
  assert.ok(existsSync(r('native', 'apple', 'Stemacle', 'Resources', 'Assets.xcassets', 'AppIcon.appiconset', 'Contents.json')));
  assert.ok(existsSync(r('native', 'apple', 'Stemacle', 'Resources', 'Assets.xcassets', 'AccentColor.colorset', 'Contents.json')));
});

test('Apple project keeps signing and App Store bundle resources installable', () => {
  const project = read('native', 'apple', 'project.yml');
  const generated = read('native', 'apple', 'Stemacle.xcodeproj', 'project.pbxproj');

  assert.match(project, /DEVELOPMENT_TEAM:\s*QAWD9U9CF6/);
  assert.match(generated, /DEVELOPMENT_TEAM = QAWD9U9CF6;/);
  assert.doesNotMatch(project, /DEVELOPMENT_TEAM:\s*""/);
  assert.doesNotMatch(generated, /DEVELOPMENT_TEAM = "";/);

  assert.match(project, /Resources\/Info-iOS\.plist/);
  assert.match(project, /Resources\/Info-macOS\.plist/);
  assert.match(project, /UIRequiresFullScreen:\s*true/);
  assert.doesNotMatch(generated, /Info-iOS\.plist in Resources/);
  assert.doesNotMatch(generated, /Info-macOS\.plist in Resources/);
});

test('Apple app mounts the implemented Stem Shuffle tab', () => {
  const app = read('native', 'apple', 'Stemacle', 'StemacleApp.swift');
  assert.match(app, /enum Tab: Hashable \{ case library, splitter, shuffle, settings \}/);
  assert.match(app, /@StateObject private var mixer = MixerViewModel\(\)/);
  assert.match(app, /MixerView\(library: library,\s*mixer: mixer\)/s);
  assert.match(app, /\.tabItem \{ Label\("Shuffle", systemImage: "shuffle"\) \}/);
  assert.match(app, /\.tag\(Tab\.shuffle\)/);
});

test('Apple native surfaces are distinct from the canonical web app', () => {
  const product = read('PRODUCT.md');
  const surfaces = read('docs', 'STEMACLE_SURFACES.md');
  const project = read('native', 'apple', 'project.yml');

  assert.match(product, /Web app, native desktop macOS app, and native iOS app are three distinct product\s+surfaces/);
  assert.match(product, /The web app is not the macOS app/);
  assert.match(surfaces, /native desktop macOS app is the SwiftUI `StemacleMac` target in\s+`native\/apple`/);
  assert.match(surfaces, /native iOS app is the SwiftUI `StemacleiOS` target in `native\/apple`/);
  assert.doesNotMatch(surfaces, /Desktop is the SwiftUI Mac app in `native\/macos`/);
  assert.doesNotMatch(surfaces, /The iOS app is the SwiftUI mobile app in `native\/ios`/);
  assert.match(project, /StemacleMac:/);
  assert.match(project, /StemacleiOS:/);
});

test('native macOS splitter supports desktop file intake without extra chrome', () => {
  const app = read('native', 'apple', 'Stemacle', 'StemacleApp.swift');

  assert.match(app, /@State private var dropTargeted = false/);
  assert.match(app, /\.keyboardShortcut\("o", modifiers: \.command\)/);
  assert.match(app, /\.onDrop\(of: \[\.fileURL, \.audio\], isTargeted: \$dropTargeted\)/);
  assert.match(app, /private func handleDrop\(_ providers: \[NSItemProvider\]\) -> Bool/);
  assert.match(app, /provider\.loadItem\(forTypeIdentifier: UTType\.fileURL\.identifier/);
  assert.match(app, /await model\.loadFile\(url\)/);
  assert.doesNotMatch(app, /Text\("Drag.*drop/i);
});

test('Apple decoder drains the full file and keeps playback bounds tied to decoded duration', () => {
  const vm = read('native', 'apple', 'Stemacle', 'StemPlayerViewModel.swift');
  const engine = read('native', 'apple', 'Stemacle', 'StemAudioEngine.swift');

  assert.match(vm, /struct DecodedAudio/);
  assert.match(vm, /private func decodeStereo44k\(_ url: URL\) throws -> DecodedAudio/);
  assert.match(vm, /while true\s*\{[\s\S]*converter\.convert\(to: out, error: &error, withInputFrom: inputBlock\)/);
  assert.match(vm, /case \.endOfStream:\s*break conversionLoop/);
  assert.match(vm, /finishLoading\(dict, bpm:[\s\S]*duration: decoded\.duration[\s\S]*quality: (?:"on-device"|quality)\)/);
  assert.match(vm, /finishLoading\(dict, bpm: project\.bpm[\s\S]*duration: project\.duration[\s\S]*persist: false\)/);
  assert.doesNotMatch(vm, /quality: modelChoice|StemServerClient\.configured|awaitStems/);

  assert.match(engine, /func load\(stems split: \[String: \[Float\]\], durationSeconds expectedDuration: Double\? = nil\)/);
  assert.match(engine, /let computedDuration = Double\(maxFrames\) \/ Self\.sampleRate/);
  assert.match(engine, /durationSeconds = max\(computedDuration, expectedDuration \?\? 0\)/);
});

test('Apple settings are public App Store settings without server controls', () => {
  const app = read('native', 'apple', 'Stemacle', 'StemacleApp.swift');
  const vm = read('native', 'apple', 'Stemacle', 'StemPlayerViewModel.swift');

  assert.match(app, /import StoreKit/);
  assert.match(app, /@Environment\(\\.requestReview\) private var requestReview/);
  assert.match(app, /SettingsRow\(title: "App Settings", systemImage: "gearshape"/);
  assert.match(app, /SettingsLinkRow\(title: "Privacy Policy", systemImage: "hand.raised"/);
  assert.match(app, /SettingsLinkRow\(title: "Support", systemImage: "questionmark.circle"/);
  assert.match(app, /SettingsRow\(title: "Rate Stemacle", systemImage: "star"/);
  assert.match(app, /requestReview\(\)/);
  assert.match(app, /Your music stays on this device/);
  assert.doesNotMatch(app, /SepModel|settings\.model|settings\.serverURL|Separation model|Separation server|server address|htdemucs|mdx_extra/);
  assert.doesNotMatch(vm, /stemacle\.model|stemacle\.serverURL|StemServerClient\.configured|server\.submit|awaitStems/);
});

test('Apple separation runs through a serial device queue off the main actor', () => {
  const vm = read('native', 'apple', 'Stemacle', 'StemPlayerViewModel.swift');

  assert.match(vm, /private final class DeviceSeparationQueue/);
  assert.match(vm, /private let queue = OperationQueue\(\)/);
  assert.match(vm, /queue\.name = "com\.stemacle\.device-separation"/);
  assert.match(vm, /queue\.maxConcurrentOperationCount = 1/);
  assert.match(vm, /queue\.qualityOfService = \.userInitiated/);
  assert.match(vm, /private static let separationQueue = DeviceSeparationQueue\(\)/);
  // On-device separation always runs through the serial queue (the call may be
  // line-wrapped or used as the `async let` analysis task alongside a Demucs tier).
  assert.match(vm, /Self\.separationQueue\.separate\(\s*\n?\s*left: left, right: right, sampleRate: 44100\)/);
  assert.match(vm, /queue\.addOperation \{[\s\S]*Stemacle\.separate\(left: left, right: right, sampleRate: sampleRate\)/);
  assert.doesNotMatch(vm, /Task\.detached[\s\S]*Stemacle\.separate/);
});

test('Apple splitter top geometry is compact and text is bounded', () => {
  const app = read('native', 'apple', 'Stemacle', 'StemacleApp.swift');
  const tokens = read('native', 'apple', 'Stemacle', 'DesignTokens.swift');

  assert.match(app, /enum PlayerHeaderMetrics/);
  assert.match(app, /static let readyDiameter: CGFloat = 156/);
  assert.match(app, /static let idleDiameter: CGFloat = 220/);
  assert.match(app, /static let masterLaneHeight: CGFloat = 34/);
  assert.match(app, /static let transportSpacing: CGFloat = 22/);
  assert.doesNotMatch(app, /\.frame\(height: \(model\.isReady \? 190 : 240\) \* headerScale\)/);
  assert.match(app, /Text\(model\.isReady && !model\.songTitle\.isEmpty \? model\.songTitle : "stemacle"\)[\s\S]*\.lineLimit\(1\)[\s\S]*\.minimumScaleFactor\(0\.75\)/);
  assert.match(app, /Text\(model\.status\)[\s\S]*\.lineLimit\(2\)[\s\S]*\.minimumScaleFactor\(0\.75\)/);
  assert.match(tokens, /static let minimumHitTarget: CGFloat = 44/);
});

test('native surfaces carry visual contracts against overlap-prone chrome', () => {
  const app = read('native', 'apple', 'Stemacle', 'StemacleApp.swift');
  const desktop = read('native', 'desktop', 'ui', 'stemacle.slint');

  assert.match(app, /\.accessibilityIdentifier\("splitter\.title"\)/);
  assert.match(app, /\.accessibilityIdentifier\("splitter\.header"\)/);
  assert.match(app, /\.accessibilityIdentifier\("splitter\.overview"\)/);
  assert.match(app, /\.accessibilityIdentifier\("loop\.bar"\)/);
  assert.ok(app.includes('.accessibilityIdentifier("stem.row.\\(stem)")'));
  assert.match(app, /layoutPriority\(1\)/);

  assert.match(desktop, /property <length> header-circle-size: 220px/);
  assert.match(desktop, /property <length> minimum-hit-target: 44px/);
  assert.match(desktop, /height: 34px;[\s\S]*overflow: elide;/);
  assert.doesNotMatch(desktop, /height:\s*280px/);
});

test('Apple playback engine keeps on-device audio safe and loop phase tempo-aligned', () => {
  const engine = read('native', 'apple', 'Stemacle', 'StemAudioEngine.swift');

  assert.match(engine, /static let outputCeiling: Float = 0\.95/);
  assert.match(engine, /private static func sanitizedStems\(_ split: \[String: \[Float\]\]\) -> \[String: \[Float\]\]/);
  assert.match(engine, /mixPeak = max\(mixPeak, abs\(sum\)\)/);
  assert.match(engine, /let gain = outputCeiling \/ mixPeak/);
  assert.match(engine, /Stemacle\.audibleStemTime\(/);
  assert.match(engine, /if start > s \{[\s\S]*node\.scheduleBuffer\(Self\.slice\(buf, from: start, to: e\), at: nil\)[\s\S]*\}/);
  assert.match(engine, /node\.scheduleBuffer\(Self\.slice\(buf, from: s, to: e\), at: nil, options: \.loops\)/);
  assert.doesNotMatch(engine, /cyclicSlice/);
});

test('Apple WAV helpers decode stereo stems as mono mixes instead of malformed left-only audio', () => {
  // The WAV codec + server client moved into StemacleKit so they are unit-testable.
  const client = read('native', 'apple', 'StemacleKit', 'Sources', 'StemacleKit', 'StemServerClient.swift');

  assert.match(client, /var sum = 0\.0 as Float/);
  assert.match(client, /for ch in 0..<channels/);
  assert.match(client, /out\[f\] = sum \/ Float\(channels\)/);
  assert.doesNotMatch(client, /out\[f\] = Float\(s\) \/ 32768\.0/);
});

test('Apple controls stay inert until ready and headphones behave like the web single-solo control', () => {
  const vm = read('native', 'apple', 'Stemacle', 'StemPlayerViewModel.swift');
  const app = read('native', 'apple', 'Stemacle', 'StemacleApp.swift');

  for (const fn of ['setVolume', 'toggleMute', 'toggleSolo', 'toggleGlobalMute', 'setLoopMonitoring', 'setLoop', 'setAllLoop']) {
    assert.match(vm, new RegExp(`func ${fn}[\\s\\S]*guard controlsEnabled else \\{ return \\}`), `${fn} is readiness guarded`);
  }
  assert.match(vm, /private var controlsEnabled: Bool \{ isReady && !isProcessing \}/);
  assert.match(vm, /soloed\.removeAll\(\)[\s\S]*soloed\.insert\(stem\)/);
  assert.match(app, /LoopControlBar\(model: model\)[\s\S]*\.disabled\(!model\.isReady \|\| model\.isProcessing\)/);
  assert.match(app, /StemRowView\(model: model, stem: stem\)[\s\S]*\.disabled\(!model\.isReady \|\| model\.isProcessing\)/);
});

test('Windows/Linux app is a Slint shell over the shared core', () => {
  const cargo = read('native', 'desktop', 'Cargo.toml');
  assert.match(cargo, /slint/);
  assert.match(cargo, /stemacle-dsp/);
  assert.doesNotMatch(cargo, /electron/);
  assert.ok(existsSync(r('native', 'desktop', 'ui', 'stemacle.slint')));
  assert.match(read('native', 'desktop', 'src', 'player.rs'), /fn export_stems/);
});

test('model pipeline targets CoreML + ONNX from Demucs', () => {
  const py = read('models', 'convert_demucs.py');
  assert.match(py, /htdemucs/);
  assert.match(py, /coreml/i);
  assert.match(py, /onnx/i);
  // other -> melody stem mapping is explicit
  assert.match(py, /STEMACLE_STEMS/);
});
