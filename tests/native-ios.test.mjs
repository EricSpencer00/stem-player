import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import test from 'node:test';

const repoRoot = new URL('../', import.meta.url);

function readRepo(path) {
  return readFileSync(new URL(path, repoRoot), 'utf8');
}

function swift(path) {
  return readRepo(`native/ios/App/App/${path}`);
}

test('ios app boots a native SwiftUI shell instead of the Capacitor web view', () => {
  const appDelegate = swift('AppDelegate.swift');
  const mainStoryboard = readRepo('native/ios/App/App/Base.lproj/Main.storyboard');
  const info = swift('Info.plist');

  assert.match(appDelegate, /import SwiftUI/);
  assert.match(appDelegate, /UIHostingController\(rootView:\s*StemacleRootView\(/);
  assert.match(appDelegate, /window\?\.makeKeyAndVisible\(\)/);
  assert.doesNotMatch(mainStoryboard, /CAPBridgeViewController/);
  assert.doesNotMatch(info, /UIMainStoryboardFile/);
});

test('ios app compiles the stem splitter into Swift and keeps the web split contract', () => {
  const splitter = swift('NativeStemSplitter.swift');

  assert.match(splitter, /final class NativeStemSplitter/);
  assert.match(splitter, /enum Stem: String, CaseIterable, Identifiable/);
  assert.match(splitter, /func split\(audioAt url: URL/);
  assert.match(splitter, /AVAudioPCMBuffer/);
  assert.match(splitter, /estimateTempo/);
  assert.match(splitter, /drums/);
  assert.match(splitter, /vocals/);
  assert.match(splitter, /bass/);
  assert.match(splitter, /melody/);
  assert.match(splitter, /progress\(/);
});

test('ios native splitter ports the browser spectral separation pipeline', () => {
  const splitter = swift('NativeStemSplitter.swift');

  assert.match(splitter, /fftSize\s*=\s*4096/);
  assert.match(splitter, /hopSize\s*=\s*1024/);
  assert.match(splitter, /modelBins\s*=\s*1024/);
  assert.match(splitter, /func stft\(/);
  assert.match(splitter, /func istft\(/);
  assert.match(splitter, /func hpss\(/);
  assert.match(splitter, /func buildVocalMask\(/);
  assert.match(splitter, /func lowPassSpectrogram\(/);
  assert.match(splitter, /func spectralOverview\(/);
  assert.match(splitter, /webDSPFallback/);
  assert.doesNotMatch(splitter, /bandPass\(centered/);
  assert.doesNotMatch(splitter, /Finding drum transients/);
});

test('native stem player exposes the original web player controls with iOS elements', () => {
  const root = swift('StemacleRootView.swift');
  const player = swift('StemPlayerView.swift');
  const viewModel = swift('StemPlayerViewModel.swift');
  const audioEngine = swift('StemAudioEngine.swift');

  assert.match(root, /TabView/);
  assert.match(root, /NavigationStack/);
  assert.match(root, /Label\("Stem Splitter"/);
  assert.match(root, /Label\("Shuffle"/);
  assert.match(root, /Label\("Library"/);
  assert.match(root, /Label\("Settings"/);
  assert.match(player, /StemacleDeviceView/);
  assert.match(player, /StemControlRow/);
  assert.match(player, /LoopControlRow/);
  assert.match(player, /DocumentPicker/);
  assert.match(viewModel, /loopDurations/);
  assert.match(viewModel, /toggleGlobalMute/);
  assert.match(viewModel, /setHeadphones/);
  assert.match(viewModel, /applyLoop\(stem:/);
  assert.match(viewModel, /applyLoopToAll/);
  assert.match(audioEngine, /scheduleBuffer/);
  assert.match(audioEngine, /looping/);
  assert.match(audioEngine, /updateMix/);
});

test('native stem player mirrors the web UI elements one to one', () => {
  const player = swift('StemPlayerView.swift');
  const viewModel = swift('StemPlayerViewModel.swift');

  assert.match(player, /StemacleAppIconMark/);
  assert.match(player, /StemacleWordmark/);
  assert.match(player, /StemacleDeviceView/);
  assert.match(player, /StemSampleRows/);
  assert.match(player, /StemPlaybar/);
  assert.match(player, /StemToolbar/);
  assert.match(player, /SpectralRuler/);
  assert.match(player, /StemSpectrogramLane/);
  assert.match(player, /StemControlStrip/);
  assert.match(player, /WebLoopButtonRow/);
  assert.match(player, /AllStemLoopRow/);
  assert.match(player, /LevelMeterRing/);
  assert.match(player, /webRowOrder/);
  assert.match(player, /\.drums,\s*\.bass,\s*\.vocals,\s*\.melody/s);
  assert.match(viewModel, /spectralWindow/);
  assert.match(viewModel, /SPECTRAL_MIN_WINDOW_SEC/);
  assert.match(viewModel, /spectralWindowFor/);
  assert.match(viewModel, /audibleStemTime/);
  assert.match(viewModel, /spectralTimeFromRatio/);
});

test('ios native polish uses the app icon as a real brand control', () => {
  const design = swift('StemacleDesign.swift');
  const player = swift('StemPlayerView.swift');
  const root = swift('StemacleRootView.swift');

  assert.match(design, /case appIcon/);
  assert.match(design, /struct StemacleAppIconMark: View/);
  assert.match(design, /StemacleAssetImage\(asset: \.appIcon\)/);
  assert.match(design, /stemacle-tentacle\.png/);
  assert.match(design, /accessibilityLabel\("Stemacle app icon"\)/);
  assert.match(player, /StemacleAppIconMark\(size: 34\)/);
  assert.match(player, /Local-first stem splitter/);
  assert.match(root, /toolbarBackground\(StemacleDesign\.paper/);
  assert.match(root, /toolbarColorScheme\(\.light/);
});

test('ios loading a new file clears stale loop and monitoring state', () => {
  const viewModel = swift('StemPlayerViewModel.swift');

  assert.match(viewModel, /private func resetTrackStateForNewFile\(\)/);
  assert.match(viewModel, /loops = Dictionary\(uniqueKeysWithValues: Stem\.allCases\.map \{ \(\$0, StemLoop\.inactive\) \}\)/);
  assert.match(viewModel, /headphonesStem = nil/);
  assert.match(viewModel, /loopMonitorMode = \.mix/);
  assert.match(viewModel, /func load\(audioAt url: URL\) \{\s*stop\(\)\s*resetTrackStateForNewFile\(\)/s);
});

test('native stem player explains the local-first import path on first run', () => {
  const player = swift('StemPlayerView.swift');

  assert.match(player, /StemLocalProjectHint/);
  assert.match(player, /Local project/);
  assert.match(player, /Import from Files/);
  assert.match(player, /Try a sample/);
  assert.match(player, /On-device split/);
  assert.match(player, /if !viewModel\.isReady && !viewModel\.isProcessing/);
});

test('native stem shuffle stays focused and separate from the stem player', () => {
  const shuffle = swift('StemShuffleView.swift');
  const root = swift('StemacleRootView.swift');

  assert.match(shuffle, /struct StemShuffleView/);
  assert.match(shuffle, /shufflePair/);
  assert.match(shuffle, /crossfade/);
  assert.match(shuffle, /DeckCard/);
  assert.match(root, /StemShuffleView\(\)/);
  assert.doesNotMatch(shuffle, /StemPlayerViewModel/);
  assert.doesNotMatch(shuffle, /Primitive shuffle/);
});

test('ios native surfaces use Stemacle assets and document the new direction', () => {
  const design = swift('StemacleDesign.swift');
  const settings = swift('StemacleSettingsView.swift');
  const doc = readRepo('docs/STEMACLE_SURFACES.md');

  assert.match(design, /enum StemacleAsset/);
  assert.match(design, /case bottomBorder/);
  assert.match(design, /case background/);
  assert.match(design, /tentacle-bottom-border\.png/);
  assert.match(design, /suction-cup-pattern-bg\.png|tentacle-ink-plume-bg\.png/);
  assert.match(design, /var label: String/);
  assert.match(design, /Bottom tentacle border/);
  assert.match(design, /Background texture/);
  assert.match(design, /TentacleFooter/);
  assert.match(design, /StemacleBackground/);
  assert.match(settings, /TentacleFooter/);
  assert.match(settings, /StemacleIdentityPanel/);
  assert.doesNotMatch(settings, /AssetManifestSection/);
  assert.doesNotMatch(settings, /NativeStemSplitter/);
  assert.match(doc, /native Swift/i);
  assert.match(doc, /SwiftUI/i);
  assert.match(doc, /NativeStemSplitter/i);
  assert.match(doc, /bottom tentacle border/i);
  assert.match(doc, /background texture/i);
  assert.match(doc, /Stem Shuffle remains separate/i);
  assert.doesNotMatch(doc, /iOS app uses the Capacitor bundle/i);
  assert.ok(existsSync(new URL('native/ios/App/App/public/assets/tentacle-b-roll/graphics/tentacle-bottom-border.png', repoRoot)));
  assert.ok(existsSync(new URL('native/ios/App/App/public/assets/tentacle-b-roll/graphics/suction-cup-pattern-bg.png', repoRoot)));
});
