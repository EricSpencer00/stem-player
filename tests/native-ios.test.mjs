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
  assert.match(splitter, /import OnnxRuntimeBindings/);
  assert.match(splitter, /ORTEnv/);
  assert.match(splitter, /ORTSession/);
  assert.match(splitter, /ORTValue/);
  assert.match(splitter, /func stft\(/);
  assert.match(splitter, /func istft\(/);
  assert.match(splitter, /func hpss\(/);
  assert.match(splitter, /func buildVocalMask\(/);
  assert.match(splitter, /func lowPassSpectrogram\(/);
  assert.match(splitter, /func spectralOverview\(/);
  assert.match(splitter, /downloadModelFile\(/);
  assert.match(splitter, /modelCache/);
  assert.doesNotMatch(splitter, /fastFullTrackFallback/);
  assert.doesNotMatch(splitter, /bandPass\(centered/);
});

test('ios HPSS uses true median filters so vocals do not smear into drum stems', () => {
  const splitter = swift('NativeStemSplitter.swift');
  const medFilter = splitter.match(/private func medFilter\([\s\S]*?private func lowPassSpectrogram/)?.[0] ?? '';

  assert.match(medFilter, /var windowSamples = \[Float\]\(repeating:\s*0,\s*count:\s*length\)/);
  assert.match(medFilter, /windowSamples\.sort\(\)/);
  assert.match(medFilter, /output\[\(frame \* binCount\) \+ bin\] = windowSamples\[half\]/);
  assert.match(medFilter, /sampleFrame >= 0 && sampleFrame < frameCount/);
  assert.match(medFilter, /sampleBin >= 0 && sampleBin < binCount/);
  assert.doesNotMatch(medFilter, /prefix\[/);
  assert.doesNotMatch(medFilter, /\/ Float\(length\)/);
});

test('ios stem overview compresses dynamics before drawing spectrogram lanes', () => {
  const splitter = swift('NativeStemSplitter.swift');
  const overview = splitter.match(/private func spectralOverview\([\s\S]*?private func emptyRows/)?.[0] ?? '';

  assert.match(overview, /log1p|log10/);
  assert.match(overview, /sorted\(\)/);
  assert.match(overview, /percentile|reference/);
  assert.doesNotMatch(overview, /peak \* 2\.2/);
  assert.doesNotMatch(overview, /rms \* 5\.8/);
});

test('native splitter cancels stale background imports instead of burning CPU', () => {
  const splitter = swift('NativeStemSplitter.swift');

  assert.match(splitter, /withTaskCancellationHandler/);
  assert.match(splitter, /task\.cancel\(\)/);
  assert.match(splitter, /Task\.checkCancellation\(\)/);
});

test('native stem player exposes the original web player controls with iOS elements', () => {
  const root = swift('StemacleRootView.swift');
  const player = swift('StemPlayerView.swift');
  const viewModel = swift('StemPlayerViewModel.swift');
  const audioEngine = swift('StemAudioEngine.swift');

  assert.match(root, /switch selectedTab/);
  assert.doesNotMatch(root, /TabView/);
  assert.match(root, /NavigationStack/);
  assert.match(root, /return "Stem Splitter"/);
  assert.match(root, /return "Shuffle"/);
  assert.match(root, /return "Library"/);
  assert.match(root, /return "Settings"/);
  assert.match(root, /StemLibraryView\(viewModel:\s*player\)/);
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

test('ios audio engine routes through the playback session so the silent switch and lock screen do not kill sound', () => {
  const audioEngine = swift('StemAudioEngine.swift');
  const info = swift('Info.plist');

  assert.match(audioEngine, /AVAudioSession\.sharedInstance\(\)/);
  assert.match(audioEngine, /setCategory\(\.playback/);
  assert.match(audioEngine, /setActive\(true/);
  assert.match(audioEngine, /AVAudioSession\.interruptionNotification/);
  assert.match(audioEngine, /var onInterruption/);
  assert.match(info, /<key>UIBackgroundModes<\/key>/);
  assert.match(info, /<string>audio<\/string>/);
});

test('native audio engine binds each player output to the loaded stem buffer format before scheduling', () => {
  const audioEngine = swift('StemAudioEngine.swift');

  assert.doesNotMatch(audioEngine, /engine\.connect\(player,\s*to:\s*mixer,\s*format:\s*nil\)/);
  assert.match(audioEngine, /configurePlayerFormats\(\)/);
  assert.match(audioEngine, /engine\.disconnectNodeOutput\(player\)/);
  assert.match(audioEngine, /engine\.connect\(player,\s*to:\s*mixer,\s*format:\s*buffer\.format\)/);
});

test('native audio engine keeps looped stems phase locked to the transport', () => {
  const audioEngine = swift('StemAudioEngine.swift');

  assert.match(audioEngine, /synchronizedStartTime/);
  assert.match(audioEngine, /players\[stem\]\?\.play\(at:\s*startTime\)/);
  assert.match(audioEngine, /wrappedLoopStartFrame\(/);
  assert.match(audioEngine, /\(startFrame - loopStart\)\s*%\s*loopLength/);
  assert.doesNotMatch(audioEngine, /let firstStart = min\(max\(loopStart,\s*startFrame\),\s*loopEnd - 1\)/);
});

test('native partial reschedules compensate for host-time delay before rejoining live stems', () => {
  const audioEngine = swift('StemAudioEngine.swift');

  assert.match(audioEngine, /let startDelay = synchronizedStartDelay/);
  assert.match(audioEngine, /let scheduleOffset = reschedulingEveryStem \? offset : min\(duration,\s*offset \+ startDelay\)/);
  assert.match(audioEngine, /schedule\(buffer: buffer,\s*on: player,\s*from: scheduleOffset,\s*loop:/);
  assert.match(audioEngine, /players\[stem\]\?\.play\(at:\s*startTime\)/);
  assert.match(audioEngine, /startDate = reschedulingEveryStem \? Date\(\)\.addingTimeInterval\(startDelay\) : Date\(\)/);
});

test('native loop edits keep the loaded track and reschedule only changed stems', () => {
  const viewModel = swift('StemPlayerViewModel.swift');
  const audioEngine = swift('StemAudioEngine.swift');

  assert.match(viewModel, /private var loadTask: Task<Void, Never>\?/);
  assert.match(viewModel, /private var activeLoadID = UUID\(\)/);
  assert.match(viewModel, /loadTask\?\.cancel\(\)/);
  assert.match(viewModel, /guard activeLoadID == loadID else \{ return \}/);
  assert.doesNotMatch(viewModel, /func play\(\) \{\s*guard isReady else \{\s*if let first = samples\.first/s);
  assert.match(viewModel, /replayIfNeeded\(changedStems:\s*\[stem\]\)/);
  assert.match(audioEngine, /func reschedule\(/);
  assert.match(audioEngine, /for stem in Stem\.allCases where stems\.contains\(stem\)/);
});

test('native playback UI ticks are throttled for smoother loop controls', () => {
  const viewModel = swift('StemPlayerViewModel.swift');

  assert.match(viewModel, /withTimeInterval:\s*0\.12/);
  assert.match(viewModel, /tolerance\s*=\s*0\.03/);
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

test('ios stem spectrogram draws the moving visible window instead of the full overview', () => {
  const player = swift('StemPlayerView.swift');
  const viewModel = swift('StemPlayerViewModel.swift');

  assert.match(player, /values:\s*viewModel\.spectralValues\(for:\s*stem,\s*bucketCount:\s*96\)/);
  assert.doesNotMatch(player, /values:\s*viewModel\.overview\[stem\] \?\? \[\]/);
  assert.match(viewModel, /func spectralValues\(for stem: Stem,\s*bucketCount: Int\) -> \[Float\]/);
  assert.match(viewModel, /let windowStart = spectralWindow\.start \/ safeDuration/);
  assert.match(viewModel, /let windowEnd = spectralWindow\.end \/ safeDuration/);
  assert.match(viewModel, /interpolatedOverviewValue/);
});

test('ios device waveform meter follows stem energy instead of synthetic sine motion', () => {
  const player = swift('StemPlayerView.swift');
  const viewModel = swift('StemPlayerViewModel.swift');

  assert.match(player, /let bands = viewModel\.levelMeterBands\(\)/);
  assert.match(player, /LevelMeterRing\(\s*bass:\s*bands\.bass,\s*treble:\s*bands\.treble,\s*wave:\s*bands\.wave/s);
  assert.doesNotMatch(player, /sin\(viewModel\.currentTime/);
  assert.match(viewModel, /struct LevelMeterBands: Equatable/);
  assert.match(viewModel, /func levelMeterBands\(\) -> LevelMeterBands/);
  assert.match(viewModel, /stemEnergy\(stem:\s*\.bass/);
  assert.match(viewModel, /stemEnergy\(stem:\s*\.drums/);
});

test('ios first-run sample choices live under Try a Sample instead of the page bottom', () => {
  const player = swift('StemPlayerView.swift');
  const rootBody = player.match(/struct StemPlayerView: View \{[\s\S]*?private struct StemacleTabBarClearance/)?.[0] ?? '';
  const localHint = player.match(/struct StemLocalProjectHint: View \{[\s\S]*?struct StemacleDeviceView/)?.[0] ?? '';

  assert.doesNotMatch(rootBody, /StemSampleRows\(viewModel:\s*viewModel\)/);
  assert.match(localHint, /@State private var samplesExpanded = false/);
  assert.match(localHint, /Label\("Try a sample",\s*systemImage:\s*"waveform"\)/);
  assert.match(localHint, /StemSampleRows\(viewModel:\s*viewModel\)/);
  assert.doesNotMatch(localHint, /viewModel\.samples\.first/);
  assert.match(player, /GridItem\(\.adaptive\(minimum:\s*160\),\s*spacing:\s*8\)/);
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
  assert.match(player, /^\s*StemacleAppIconMark\(size: 34\)/m);
  assert.match(player, /^\s*Text\("Local-first stem splitter"\)/m);
  assert.doesNotMatch(player, /\/\/\s*StemacleAppIconMark\(size: 34\)/);
  assert.doesNotMatch(player, /\/\/\s*Text\("Local-first stem splitter"\)/);
  assert.match(root, /toolbarBackground\(StemacleDesign\.paper/);
  assert.match(root, /toolbarColorScheme\(\.light/);
});

test('ios native shell keeps system bars opaque so artwork cannot clash behind chrome', () => {
  const appDelegate = swift('AppDelegate.swift');
  const root = swift('StemacleRootView.swift');
  const design = swift('StemacleDesign.swift');

  assert.match(appDelegate, /configureSystemBarAppearance\(\)/);
  assert.match(appDelegate, /window\.backgroundColor =/);
  assert.match(appDelegate, /configureWithOpaqueBackground\(\)/);
  assert.match(appDelegate, /UINavigationBar\.appearance\(\)\.scrollEdgeAppearance/);
  assert.match(appDelegate, /UITabBar\.appearance\(\)\.scrollEdgeAppearance/);
  assert.match(appDelegate, /UITabBar\.appearance\(\)\.isTranslucent\s*=\s*false/);
  assert.match(appDelegate, /tabs\.backgroundEffect\s*=\s*nil/);
  assert.match(appDelegate, /normal\.iconColor\s*=\s*muted/);
  assert.match(appDelegate, /selected\.iconColor\s*=\s*purple/);
  assert.match(design, /\.frame\(maxWidth:\s*\.infinity,\s*maxHeight:\s*\.infinity/);
  assert.match(root, /\.background\(StemacleDesign\.paper\.ignoresSafeArea\(\)\)/);
  assert.match(root, /StemacleRootTabBar\(selection:\s*\$selectedTab,\s*showTopDivider:/);
  assert.match(root, /toolbar\(\.hidden,\s*for:\s*\.tabBar\)/);
  assert.match(root, /safeAreaInset\(edge:\s*\.bottom,\s*spacing:\s*0\)/);
  assert.match(root, /toolbarBackground\(\.visible,\s*for:\s*\.navigationBar,\s*\.tabBar\)/);
  assert.doesNotMatch(root, /@ViewBuilder\s*\n\s*@ViewBuilder/);
});

test('ios stem player reserves bottom space so controls do not slide under the tab bar', () => {
  const player = swift('StemPlayerView.swift');

  assert.match(player, /safeAreaInset\(edge:\s*\.bottom,\s*spacing:\s*0\)/);
  assert.match(player, /StemacleTabBarClearance/);
  assert.match(player, /StemacleDesign\.paper\s*\.frame\(height:\s*96\)/);
  assert.doesNotMatch(player, /Color\.clear\s*\.frame\(height:\s*96\)/);
});

test('ios spectrogram labels only render major markers to avoid text collisions', () => {
  const player = swift('StemPlayerView.swift');

  assert.match(player, /shouldDrawMarkerLabel\(/);
  assert.match(player, /marker\.label == "1"/);
  assert.match(player, /lastMarkerLabelX/);
  assert.match(player, /x - lastLabelX >= 72/);
  assert.doesNotMatch(player, /context\.draw\(\s*Text\(marker\.label\)/);
});

test('ios loading a new file clears stale loop and monitoring state', () => {
  const viewModel = swift('StemPlayerViewModel.swift');

  assert.match(viewModel, /private func resetTrackStateForNewFile\(\)/);
  assert.match(viewModel, /loops = Dictionary\(uniqueKeysWithValues: Stem\.allCases\.map \{ \(\$0, StemLoop\.inactive\) \}\)/);
  assert.match(viewModel, /headphonesStem = nil/);
  assert.match(viewModel, /loopMonitorMode = preferSoloLoopMonitor \? \.solo : \.mix/);
  assert.match(viewModel, /func load\(audioAt url: URL,\s*persistToLibrary: Bool = true,\s*displayTitle: String\? = nil,\s*sourceName: String\? = nil,\s*cacheKey: String\? = nil\) \{/);
  assert.match(viewModel, /Preparing local import and split|Loading on-device splitter/);
  assert.match(viewModel, /Importing audio into the local library/);
  assert.match(viewModel, /stop\(\)[\s\S]*resetTrackStateForNewFile\(\)/);
});

test('ios persists separated stems so reopening a library track is instant', () => {
  const cache = swift('StemResultCache.swift');
  const viewModel = swift('StemPlayerViewModel.swift');

  assert.match(cache, /struct StemResultCache/);
  assert.match(cache, /func cachedResult\(/);
  assert.match(cache, /func store\(/);
  assert.match(cache, /AVAudioFile\(forWriting/);
  assert.match(cache, /AVAudioFile\(forReading/);
  assert.match(cache, /meta\.json/);
  assert.match(cache, /applicationSupportDirectory/);

  assert.match(viewModel, /private let stemCache = StemResultCache\(\)/);
  // Cache is consulted before paying for a full separation, and filled after one.
  assert.match(viewModel, /loadCachedResult\(/);
  assert.match(viewModel, /storeResult\(/);
  assert.match(viewModel, /func load\(audioAt url: URL,[\s\S]*?cacheKey: String\?/);
});

test('ios fires haptics so the device feels physical', () => {
  const haptics = swift('StemacleHaptics.swift');
  const viewModel = swift('StemPlayerViewModel.swift');

  assert.match(haptics, /enum StemacleHaptics/);
  assert.match(haptics, /UIImpactFeedbackGenerator/);
  assert.match(haptics, /UINotificationFeedbackGenerator/);
  assert.match(viewModel, /StemacleHaptics\./);
});

test('ios asks for an App Store rating at a happy moment with the native prompt', () => {
  const player = swift('StemPlayerView.swift');
  const viewModel = swift('StemPlayerViewModel.swift');
  const settings = swift('StemacleSettingsView.swift');

  // Native StoreKit review prompt, gated on repeated successful splits.
  assert.match(player, /import StoreKit/);
  assert.match(player, /requestReview/);
  assert.match(viewModel, /successfulSplitCount/);
  assert.match(viewModel, /shouldRequestReview/);
  // Settings link points at the real App Store write-review deep link.
  assert.match(settings, /apps\.apple\.com\/app\/id6782539749/);
  assert.match(settings, /action=write-review/);
});

test('ios processing overlay can be cancelled instead of trapping the user', () => {
  const player = swift('StemPlayerView.swift');
  const viewModel = swift('StemPlayerViewModel.swift');

  assert.match(viewModel, /func cancelLoad\(\)/);
  assert.match(viewModel, /loadTask\?\.cancel\(\)/);
  const overlay = player.match(/struct ProcessingOverlay: View \{[\s\S]*?^}/m)?.[0] ?? '';
  assert.match(overlay, /viewModel\.cancelLoad\(\)/);
  assert.match(overlay, /Cancel/);
});

test('ios settings toggles are actually wired into playback behavior', () => {
  const player = swift('StemPlayerView.swift');
  const viewModel = swift('StemPlayerViewModel.swift');

  // Keep screen awake controls the idle timer while a track is playing.
  assert.match(player, /@AppStorage\("stemacle\.keepScreenAwake"\)/);
  assert.match(player, /isIdleTimerDisabled/);
  // Waveform scrub hint visibility is gated by its setting.
  assert.match(player, /@AppStorage\("stemacle\.showWaveformHints"\)/);
  assert.match(player, /showWaveformHints/);
  // Solo-loop-monitor preference feeds the default monitor mode on new tracks.
  assert.match(player, /@AppStorage\("stemacle\.preferSoloLoopMonitor"\)/);
  assert.match(viewModel, /var preferSoloLoopMonitor/);
  assert.match(viewModel, /loopMonitorMode = preferSoloLoopMonitor \? \.solo : \.mix/);
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
  assert.match(shuffle, /rankCompatiblePairs/);
  assert.match(shuffle, /scoreCompatibility/);
  assert.match(shuffle, /MixLeadMode/);
  assert.match(shuffle, /compatibilityMeta/);
  assert.match(shuffle, /MixStatusBar/);
  assert.match(shuffle, /MixPadGrid/);
  assert.match(shuffle, /TrackSettingsSheet/);
  assert.match(shuffle, /Lead 1/);
  assert.match(shuffle, /Blend/);
  assert.match(shuffle, /Lead 2/);
  assert.match(shuffle, /Bring in a stronger local match/);
  assert.match(root, /StemShuffleView\(\)/);
  assert.doesNotMatch(shuffle, /StemPlayerViewModel/);
  assert.doesNotMatch(shuffle, /Primitive shuffle/);
  assert.doesNotMatch(shuffle, /Bool\.random/);
});

test('ios utility tabs use compact native density instead of large zoomed panels', () => {
  const root = swift('StemacleRootView.swift');
  const shuffle = swift('StemShuffleView.swift');
  const settings = swift('StemacleSettingsView.swift');

  assert.match(root, /navigationBarTitleDisplayMode\(\.inline\)/);
  assert.match(shuffle, /StemacleScreen\(showsTentacleFooter:\s*true\)/);
  assert.match(shuffle, /LazyVGrid\(columns: columns,\s*spacing:\s*8\)/);
  assert.match(shuffle, /TrackSettingsSheet/);
  assert.match(shuffle, /presentationDetents\(\[\.medium\]\)/);
  assert.match(shuffle, /frame\(maxWidth:\s*\.infinity,\s*minHeight:\s*76,\s*alignment:\s*\.leading\)/);
  assert.doesNotMatch(shuffle, /\.largeTitle/);
  assert.doesNotMatch(shuffle, /\.padding\(18\)/);
  assert.match(settings, /StemacleIdentityPanel\(\)/);
  assert.match(settings, /StemacleAppIconMark\(size:\s*44\)/);
  assert.match(settings, /Privacy Policy/);
  assert.match(settings, /Leave a Review/);
  assert.match(settings, /stemacle\.com\/privacy/);
  assert.doesNotMatch(settings, /StemacleAppIconMark\(size:\s*64\)/);
});

test('ios native surfaces use Stemacle assets and document the new direction', () => {
  const design = swift('StemacleDesign.swift');
  const settings = swift('StemacleSettingsView.swift');
  const doc = readRepo('docs/STEMACLE_SURFACES.md');
  const prepareNative = readRepo('scripts/prepare-native.mjs');

  assert.match(design, /enum StemacleAsset/);
  assert.match(design, /case bottomBorder/);
  assert.match(design, /case background/);
  assert.match(design, /tentacle-bottom-border\.png/);
  assert.match(design, /suction-cup-pattern-bg\.png|tentacle-ink-plume-bg\.png/);
  assert.match(design, /var label: String/);
  assert.match(design, /Bottom tentacle border/);
  assert.match(design, /Background texture/);
  assert.match(design, /private let backgroundArtworkLift: CGFloat = -62/);
  assert.match(design, /\.offset\(y:\s*backgroundArtworkLift\)/);
  assert.match(design, /TentacleFooter/);
  assert.match(design, /StemacleBackground/);
  assert.match(settings, /StemacleIdentityPanel/);
  assert.match(settings, /Privacy Policy/);
  assert.match(settings, /Leave a Review/);
  assert.match(settings, /All local for now/);
  assert.doesNotMatch(settings, /AssetManifestSection/);
  assert.doesNotMatch(settings, /NativeStemSplitter/);
  assert.match(doc, /native Swift/i);
  assert.match(doc, /SwiftUI/i);
  assert.match(doc, /NativeStemSplitter/i);
  assert.match(doc, /bottom tentacle border/i);
  assert.match(doc, /background texture/i);
  assert.match(doc, /Stem Shuffle remains separate/i);
  assert.doesNotMatch(doc, /iOS app uses the Capacitor bundle/i);
  assert.match(prepareNative, /await copyIntoBundle\('assets'\)/);
  assert.match(prepareNative, /await copyIntoBundle\('privacy'\)/);
  assert.match(prepareNative, /await copyIntoBundle\('support'\)/);
  assert.ok(existsSync(new URL('assets/tentacle-b-roll/graphics/tentacle-bottom-border.png', repoRoot)));
  assert.ok(existsSync(new URL('assets/tentacle-b-roll/graphics/suction-cup-pattern-bg.png', repoRoot)));
});
