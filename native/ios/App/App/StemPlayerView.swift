import SwiftUI
import UIKit
import UniformTypeIdentifiers

private let READY_HINT = "Use the mixer rows to mute, solo, change volume, and loop stems"

struct StemPlayerView: View {
    @ObservedObject var viewModel: StemPlayerViewModel
    @State private var showingImporter = false

    private let webRowOrder: [Stem] = [.drums, .bass, .vocals, .melody]

    var body: some View {
        StemacleScreen {
            ScrollView {
                VStack(spacing: 0) {
                    StemacleWordmark()
                        .padding(.top, 16)
                        .padding(.bottom, 28)

                    StemacleDeviceView(viewModel: viewModel) {
                        showingImporter = true
                    }
                    .padding(.bottom, 22)

                    Text(viewModel.isReady ? READY_HINT : "Drop a track to begin")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(StemacleDesign.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, viewModel.isReady ? 20 : 10)

                    StemLocalProjectHint(viewModel: viewModel) {
                        showingImporter = true
                    }
                    .padding(.bottom, 12)

                    StemPlaybar(viewModel: viewModel)
                        .padding(.bottom, 18)

                    StemPanelView(viewModel: viewModel, webRowOrder: webRowOrder)
                        .padding(.bottom, 140)

                    Text("local separation - HPSS - NativeStemSplitter")
                        .font(.caption2)
                        .foregroundStyle(StemacleDesign.inkGhost)
                        .padding(.bottom, 24)
                }
                .frame(width: max(280, min(UIScreen.main.bounds.width - 28, 760)))
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StemacleTabBarClearance()
            }
        }
        .navigationTitle("Stem Splitter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    viewModel.toggleGlobalMute()
                } label: {
                    Label(viewModel.globalMuted ? "Unmute all" : "Mute all", systemImage: viewModel.globalMuted ? "speaker.slash.fill" : "speaker.wave.2")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import Audio", systemImage: "doc.badge.plus")
                    }
                    ForEach(viewModel.samples) { sample in
                        Button(sample.title) {
                            viewModel.loadSample(sample)
                        }
                    }
                    Divider()
                    Button("Reset Mixer") {
                        viewModel.resetMixer()
                    }
                    Button("Clear Loops") {
                        viewModel.clearLoops()
                    }
                } label: {
                    Label("Add", systemImage: "plus.circle")
                }
            }
        }
        .overlay {
            if viewModel.isProcessing {
                ProcessingOverlay(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showingImporter) {
            DocumentPicker { url in
                showingImporter = false
                viewModel.load(audioAt: url)
            }
        }
    }
}

private struct StemacleTabBarClearance: View {
    var body: some View {
        StemacleDesign.paper
            .frame(height: 96)
    }
}

struct StemacleWordmark: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(StemacleDesign.inkGhost)
                .frame(width: 20, height: 1)
            StemacleAppIconMark(size: 34)
            VStack(spacing: 2) {
                Text("Stemacle")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(StemacleDesign.inkSoft)
                Text("Local-first stem splitter")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(StemacleDesign.inkGhost)
            }
            Rectangle()
                .fill(StemacleDesign.inkGhost)
                .frame(width: 20, height: 1)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

struct StemLocalProjectHint: View {
    @ObservedObject var viewModel: StemPlayerViewModel
    @State private var samplesExpanded = false
    var openImporter: () -> Void

    var body: some View {
        if !viewModel.isReady && !viewModel.isProcessing {
            StemaclePanel {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Label("Local project", systemImage: "folder.badge.plus")
                            .font(.caption.weight(.bold))
                            .textCase(.uppercase)
                            .foregroundStyle(StemacleDesign.inkSoft)
                        Spacer()
                        Label("On-device split", systemImage: "lock")
                            .font(.caption2.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(StemacleDesign.inkGhost)
                    }

                    HStack(spacing: 8) {
                        Button {
                            openImporter()
                        } label: {
                            Label("Import from Files", systemImage: "doc.badge.plus")
                                .font(.caption2.weight(.bold))
                                .textCase(.uppercase)
                                .frame(maxWidth: .infinity, minHeight: 42)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(StemacleDesign.paper)
                        .background(Capsule().fill(StemacleDesign.ink))

                        Button {
                            withAnimation(.easeOut(duration: 0.16)) {
                                samplesExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Label("Try a sample", systemImage: "waveform")
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.bold))
                                    .rotationEffect(.degrees(samplesExpanded ? 180 : 0))
                            }
                            .font(.caption2.weight(.bold))
                            .textCase(.uppercase)
                            .frame(maxWidth: .infinity, minHeight: 42)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(StemacleDesign.inkSoft)
                        .overlay(Capsule().stroke(StemacleDesign.track, lineWidth: 1))
                    }

                    if samplesExpanded {
                        StemSampleRows(viewModel: viewModel)
                            .padding(.top, 2)
                    }
                }
            }
            .frame(maxWidth: 560)
        }
    }
}

struct StemacleDeviceView: View {
    @ObservedObject var viewModel: StemPlayerViewModel
    var openImporter: () -> Void

    var body: some View {
        let bands = viewModel.levelMeterBands()

        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [StemacleDesign.deviceInner, StemacleDesign.deviceOuter],
                        center: UnitPoint(x: 0.38, y: 0.32),
                        startRadius: 8,
                        endRadius: 260
                    )
                )
                .shadow(color: Color.white.opacity(0.42), radius: 3, y: -2)
                .shadow(color: StemacleDesign.shadow, radius: 28, y: 16)

            Circle()
                .stroke(StemacleDesign.track, lineWidth: 2)
                .padding(10)

            Circle()
                .trim(from: 0, to: CGFloat(playbackProgress))
                .stroke(StemacleDesign.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(10)

            LevelMeterRing(
                bass: bands.bass,
                treble: bands.treble,
                wave: bands.wave
            )
            .padding(54)

            Button {
                if viewModel.isReady {
                    viewModel.togglePlay()
                } else {
                    openImporter()
                }
            } label: {
                VStack(spacing: 7) {
                    Image(systemName: centerSymbol)
                        .font(.system(size: 22, weight: .medium))
                    Text(centerHint)
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                }
                .foregroundStyle(StemacleDesign.inkSoft)
                .frame(width: 92, height: 92)
                .background(
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 0.84, green: 0.79, blue: 0.68), StemacleDesign.center],
                                center: UnitPoint(x: 0.4, y: 0.35),
                                startRadius: 4,
                                endRadius: 68
                            )
                        )
                        .shadow(color: StemacleDesign.shadow, radius: 10, y: 3)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isReady ? "Play or pause" : "Choose an audio file to separate")
        }
        .frame(width: 282, height: 282)
    }

    private var playbackProgress: Double {
        guard viewModel.duration > 0 else {
            return viewModel.isProcessing ? max(0.04, viewModel.progress) : 0
        }
        return min(1, max(0, viewModel.currentTime / viewModel.duration))
    }

    private var centerSymbol: String {
        if !viewModel.isReady { return "arrow.down.to.line.compact" }
        return viewModel.isPlaying ? "pause.fill" : "play.fill"
    }

    private var centerHint: String {
        if !viewModel.isReady { return "drop audio" }
        return viewModel.isPlaying ? "playing" : "play"
    }
}

struct LevelMeterRing: View {
    var bass: Double
    var treble: Double
    var wave: Double

    var body: some View {
        Canvas { context, size in
            drawRing(context: &context, size: size)
        }
    }

    private func drawRing(context: inout GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let base = side * 0.36
        let thickness = side * 0.046
        let paths = ringPaths(center: center, base: base, thickness: thickness, side: side)
        let centerRect = CGRect(x: center.x - base, y: center.y - base, width: base * 2, height: base * 2)

        context.stroke(paths.outer, with: .color(StemacleDesign.ink.opacity(0.58)), lineWidth: 2)
        context.stroke(paths.inner, with: .color(StemacleDesign.inkGhost.opacity(0.48)), lineWidth: 1)
        context.stroke(Path(ellipseIn: centerRect), with: .color(StemacleDesign.ink.opacity(0.18)), lineWidth: 1)
    }

    private func ringPaths(center: CGPoint, base: CGFloat, thickness: CGFloat, side: CGFloat) -> (outer: Path, inner: Path) {
        let count = 112
        var outer = Path()
        var inner = Path()

        for index in 0...count {
            let angle = (-Double.pi / 2) + (Double(index) / Double(count)) * Double.pi * 2
            let lowSide = cos(angle) < 0
            let band = CGFloat(lowSide ? bass : treble)
            let ripple = CGFloat((sin(Double(index) * 0.41 + wave * 3.0) + 1) * 0.5)
            let displacement = side * (0.01 + band * 0.034 + ripple * CGFloat(wave) * 0.036)
            let radius = base + displacement
            let outerPoint = ringPoint(center: center, angle: angle, radius: radius)
            let innerPoint = ringPoint(center: center, angle: angle, radius: radius - thickness)

            if index == 0 {
                outer.move(to: outerPoint)
                inner.move(to: innerPoint)
            } else {
                outer.addLine(to: outerPoint)
                inner.addLine(to: innerPoint)
            }
        }

        return (outer, inner)
    }

    private func ringPoint(center: CGPoint, angle: Double, radius: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + CGFloat(cos(angle)) * radius,
            y: center.y + CGFloat(sin(angle)) * radius
        )
    }
}

struct StemSampleRows: View {
    @ObservedObject var viewModel: StemPlayerViewModel

    var body: some View {
        if !viewModel.isReady && !viewModel.isProcessing {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                ForEach(viewModel.samples) { sample in
                    Button {
                        viewModel.loadSample(sample)
                    } label: {
                        Text(sample.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(StemacleDesign.inkSoft)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.86)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain)
                    .background(Capsule().fill(Color.clear))
                    .overlay(Capsule().stroke(StemacleDesign.track, lineWidth: 1))
                }
            }
        }
    }
}

struct StemPlaybar: View {
    @ObservedObject var viewModel: StemPlayerViewModel

    var body: some View {
        if viewModel.isReady || viewModel.isProcessing {
            VStack(spacing: 10) {
                Text(viewModel.title)
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(StemacleDesign.inkSoft)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Slider(value: Binding(
                    get: { viewModel.currentTime },
                    set: { viewModel.seek(to: $0) }
                ), in: 0...max(0.1, viewModel.duration))
                .tint(StemacleDesign.ink)

                HStack {
                    Text(viewModel.formatted(viewModel.currentTime))
                    Spacer()
                    Text(viewModel.formatted(viewModel.duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(StemacleDesign.inkGhost)

                HStack(spacing: 8) {
                    TransportButton(title: "restart", systemImage: "backward.end.fill") {
                        viewModel.restart()
                    }
                    TransportButton(title: viewModel.isPlaying ? "pause" : "play", systemImage: viewModel.isPlaying ? "pause.fill" : "play.fill", primary: true) {
                        viewModel.togglePlay()
                    }
                    TransportButton(title: "stop", systemImage: "stop.fill") {
                        viewModel.stop()
                    }
                }
            }
        }
    }
}

struct TransportButton: View {
    var title: String
    var systemImage: String
    var primary = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.plain)
        .foregroundStyle(primary ? StemacleDesign.paper : StemacleDesign.inkSoft)
        .background(Capsule().fill(primary ? StemacleDesign.ink : Color.clear))
        .overlay(Capsule().stroke(primary ? StemacleDesign.ink : StemacleDesign.track, lineWidth: 1))
    }
}

struct StemPanelView: View {
    @ObservedObject var viewModel: StemPlayerViewModel
    let webRowOrder: [Stem]

    var body: some View {
        if viewModel.isReady {
            VStack(spacing: 0) {
                StemToolbar(viewModel: viewModel)
                    .padding(.bottom, 14)

                SpectralRuler(viewModel: viewModel)

                ForEach(webRowOrder) { stem in
                    StemControlRow(viewModel: viewModel, stem: stem)
                }

                AllStemLoopRow(viewModel: viewModel)
            }
        }
    }
}

struct StemToolbar: View {
    @ObservedObject var viewModel: StemPlayerViewModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.toggleGlobalMute()
            } label: {
                Text(viewModel.globalMuted ? "unmute all" : "mute all")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.plain)
            .foregroundStyle(StemacleDesign.inkSoft)
            .overlay(Capsule().stroke(StemacleDesign.track, lineWidth: 1))

            Picker("Loop monitor", selection: Binding(
                get: { viewModel.loopMonitorMode },
                set: { viewModel.setLoopMonitorMode($0) }
            )) {
                Text("mix").tag(LoopMonitorMode.mix)
                Text("solo").tag(LoopMonitorMode.solo)
            }
            .pickerStyle(.segmented)
            .frame(width: 112)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }
}

struct SpectralRuler: View {
    @ObservedObject var viewModel: StemPlayerViewModel

    var body: some View {
        HStack {
            Text(viewModel.formatted(viewModel.spectralWindow.start))
            Spacer()
            Text(viewModel.spectralWindow.mode.rawValue)
                .foregroundStyle(StemacleDesign.inkSoft)
            Spacer()
            Text(viewModel.formatted(viewModel.spectralWindow.end))
        }
        .font(.caption2.weight(.semibold))
        .textCase(.uppercase)
        .foregroundStyle(StemacleDesign.inkGhost)
        .padding(.vertical, 9)
        .overlay(StemacleHairline(), alignment: .top)
    }
}

struct StemControlRow: View {
    @ObservedObject var viewModel: StemPlayerViewModel
    let stem: Stem

    var body: some View {
        VStack(spacing: 0) {
            StemControlStrip(viewModel: viewModel, stem: stem)
                .padding(.vertical, 8)
            StemSpectrogramLane(
                values: viewModel.spectralValues(for: stem, bucketCount: 96),
                cursor: viewModel.cursorRatio(for: stem),
                window: viewModel.spectralWindow,
                markers: viewModel.spectralGridMarkers()
            ) { ratio in
                viewModel.seek(to: viewModel.spectralTimeFromRatio(ratio))
            }
            .frame(height: 84)
        }
        .overlay(StemacleHairline(), alignment: .top)
    }
}

struct StemControlStrip: View {
    @ObservedObject var viewModel: StemPlayerViewModel
    let stem: Stem

    private var control: StemPlaybackControl {
        viewModel.controls[stem] ?? StemPlaybackControl()
    }

    private var loop: StemLoop {
        viewModel.loops[stem] ?? .inactive
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(stem.title)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(StemacleDesign.inkSoft)
                    .frame(width: 72, alignment: .leading)

                Slider(value: Binding(
                    get: { Double(control.volume) },
                    set: { viewModel.setVolume(stem: stem, value: Float($0)) }
                ), in: 0...1)
                .tint(control.isMuted ? StemacleDesign.inkGhost : StemacleDesign.ink)

                HStack(spacing: 6) {
                    StemIconButton(
                        systemName: control.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        active: control.isMuted,
                        label: "Mute \(stem.title)"
                    ) {
                        viewModel.toggleMute(stem: stem)
                    }
                    StemIconButton(
                        systemName: control.isHeadphones ? "headphones.circle.fill" : "headphones",
                        active: control.isHeadphones,
                        label: "Solo \(stem.title)"
                    ) {
                        viewModel.setHeadphones(stem: stem)
                    }
                }
            }

            LoopControlRow(
                selectedIndex: loop.selectedIndex,
                options: viewModel.loopDurations
            ) { index in
                viewModel.applyLoop(stem: stem, index: index)
            }
        }
    }
}

struct StemIconButton: View {
    var systemName: String
    var active: Bool
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 48, height: 42)
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? StemacleDesign.paper : StemacleDesign.inkSoft)
        .background(Capsule().fill(active ? StemacleDesign.inkSoft : Color.clear))
        .overlay(Capsule().stroke(active ? StemacleDesign.inkSoft : StemacleDesign.track, lineWidth: 1))
        .accessibilityLabel(label)
    }
}

struct WebLoopButtonRow: View {
    var selectedIndex: Int?
    var options: [(label: String, measures: Double)]
    var apply: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    apply(index)
                } label: {
                    Text(option.label)
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedIndex == index ? StemacleDesign.amber : StemacleDesign.inkSoft)
                .background(Capsule().fill(StemacleDesign.paper.opacity(0.28)))
                .overlay(Capsule().stroke(selectedIndex == index ? StemacleDesign.amber : StemacleDesign.track, lineWidth: 1))
            }
        }
    }
}

struct AllStemLoopRow: View {
    @ObservedObject var viewModel: StemPlayerViewModel

    private var allLoopIndex: Int? {
        let active = Stem.allCases.compactMap { viewModel.loops[$0]?.selectedIndex }
        guard active.count == Stem.allCases.count, let first = active.first else { return nil }
        return active.allSatisfy { $0 == first } ? first : nil
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("All")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(StemacleDesign.inkSoft)
                    .frame(width: 72, alignment: .leading)
                Text("linked loop")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(StemacleDesign.inkGhost)
                Spacer()
            }
            LoopControlRow(selectedIndex: allLoopIndex, options: viewModel.loopDurations) { index in
                viewModel.applyLoopToAll(index: index)
            }
        }
        .padding(.vertical, 10)
        .overlay(StemacleHairline(), alignment: .top)
    }
}

struct LoopControlRow: View {
    var selectedIndex: Int?
    var options: [(label: String, measures: Double)]
    var apply: (Int) -> Void

    var body: some View {
        WebLoopButtonRow(selectedIndex: selectedIndex, options: options, apply: apply)
    }
}

struct StemSpectrogramLane: View {
    var values: [Float]
    var cursor: Double
    var window: SpectralWindow
    var markers: [SpectralGridMarker]
    var seek: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                context.fill(Path(rect), with: .linearGradient(
                    Gradient(colors: [
                        StemacleDesign.deviceInner.opacity(0.18),
                        StemacleDesign.rowGlow,
                        StemacleDesign.deviceInner.opacity(0.18),
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                ))

                for step in 0...8 {
                    let x = size.width * CGFloat(step) / 8
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: 0))
                    line.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(line, with: .color(Color.white.opacity(0.20)), lineWidth: 1)
                }

                var mid = Path()
                mid.move(to: CGPoint(x: 0, y: size.height * 0.5))
                mid.addLine(to: CGPoint(x: size.width, y: size.height * 0.5))
                context.stroke(mid, with: .color(StemacleDesign.ink.opacity(0.10)), lineWidth: 2)

                let safeValues = values.isEmpty ? placeholder : values
                let barWidth = max(1, size.width / CGFloat(safeValues.count))
                for (index, value) in safeValues.enumerated() {
                    let v = min(1, max(0, CGFloat(value)))
                    let x = CGFloat(index) * barWidth
                    let soft = max(1, v * size.height * 0.92)
                    let hard = max(1, v * size.height * 0.52)
                    let softRect = CGRect(x: x, y: (size.height - soft) / 2, width: max(1, barWidth), height: soft)
                    let hardRect = CGRect(x: x, y: (size.height - hard) / 2, width: max(1, barWidth), height: hard)
                    context.fill(Path(softRect), with: .color(StemacleDesign.inkGhost.opacity(0.58)))
                    context.fill(Path(hardRect), with: .color(StemacleDesign.ink.opacity(0.42)))
                }

                var lastMarkerLabelX = -CGFloat.infinity
                for marker in markers {
                    let span = max(0.001, window.end - window.start)
                    let x = size.width * CGFloat((marker.time - window.start) / span)
                    guard x >= 0, x <= size.width else { continue }
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: 0))
                    line.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(line, with: .color(StemacleDesign.ink.opacity(marker.weight)), lineWidth: marker.label == "1" ? 1.5 : 1)
                    if shouldDrawMarkerLabel(marker, x: x, lastLabelX: lastMarkerLabelX) {
                        context.draw(
                            markerLabel(marker),
                            at: CGPoint(x: x, y: 10)
                        )
                        lastMarkerLabelX = x
                    }
                }

                let cursorX = min(size.width, max(0, size.width * CGFloat(cursor)))
                var cursorPath = Path()
                cursorPath.move(to: CGPoint(x: cursorX, y: 0))
                cursorPath.addLine(to: CGPoint(x: cursorX, y: size.height))
                context.stroke(cursorPath, with: .color(StemacleDesign.ink.opacity(0.78)), lineWidth: 2)
                context.fill(Path(ellipseIn: CGRect(x: cursorX - 6, y: size.height / 2 - 6, width: 12, height: 12)), with: .color(StemacleDesign.ink))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let ratio = min(1, max(0, value.location.x / max(1, proxy.size.width)))
                        seek(ratio)
                    }
            )
        }
    }

    private var placeholder: [Float] {
        (0..<96).map { index in
            Float(0.12 + (sin(Double(index) * 0.44) + 1) * 0.16)
        }
    }

    private func shouldDrawMarkerLabel(_ marker: SpectralGridMarker, x: CGFloat, lastLabelX: CGFloat) -> Bool {
        marker.label == "1" && x - lastLabelX >= 72
    }

    private func markerLabel(_ marker: SpectralGridMarker) -> Text {
        Text(marker.label)
            .font(.caption2)
            .foregroundColor(StemacleDesign.ink.opacity(min(0.68, marker.weight + 0.16)))
    }

}

struct ProcessingOverlay: View {
    @ObservedObject var viewModel: StemPlayerViewModel

    var body: some View {
        ZStack {
            StemacleDesign.paper.opacity(0.93)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Processing")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(StemacleDesign.inkSoft)
                ProgressView(value: viewModel.progress)
                    .tint(StemacleDesign.ink)
                    .frame(width: 252)
                Text(viewModel.status)
                    .font(.caption2)
                    .foregroundStyle(StemacleDesign.inkGhost)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            .padding(28)
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
