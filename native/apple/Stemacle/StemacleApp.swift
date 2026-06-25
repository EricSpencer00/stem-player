import SwiftUI
import UniformTypeIdentifiers

@main
struct StemacleApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if os(macOS)
        .defaultSize(width: 460, height: 760)
        #endif
    }
}

/// The first and primary screen on every device: the Stemacle circle, transport,
/// and the four-stem panel — visually aligned with the web gold master.
struct RootView: View {
    @StateObject private var model = StemPlayerViewModel()
    @State private var importing = false
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            Stem.cream.ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape").foregroundStyle(Stem.inkSoft)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 18)
                }
                DeviceCircleView(model: model) { importing = true }
                    .frame(maxWidth: 320)

                TransportView(model: model)

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(Stem.stemOrder, id: \.self) { stem in
                            StemRowView(model: model, stem: stem)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 16)
        }
        .foregroundStyle(Stem.ink)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                Task { await model.loadFile(url) }
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }
}

/// Settings: the htdemucs queue-server URL. When set, separation runs on the
/// server for full quality; when empty, the app separates on-device (DSP).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var serverURL = UserDefaults.standard.string(forKey: "stemacle.serverURL") ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings").font(.title3.weight(.semibold))
                Spacer()
                Button("Done") {
                    UserDefaults.standard.set(serverURL, forKey: "stemacle.serverURL")
                    dismiss()
                }
            }
            Text("Separation server")
                .font(.subheadline.weight(.medium))
            TextField("http://192.168.x.x:8008", text: $serverURL)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            Text("When set, tracks are split with full htdemucs quality on the server. Leave empty to split on-device.")
                .font(.footnote)
                .foregroundStyle(Stem.inkSoft)
            Spacer()
        }
        .padding(24)
        .frame(minWidth: 320, minHeight: 220)
    }
}

/// The warm matte circle — passive physical display + center load/play control.
struct DeviceCircleView: View {
    @ObservedObject var model: StemPlayerViewModel
    var onLoad: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Stem.cream, Stem.creamDeep],
                        center: .center, startRadius: 8, endRadius: 200
                    )
                )
                .overlay(Circle().stroke(Stem.creamDeep, lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 18, y: 8)

            VStack(spacing: 8) {
                if model.isProcessing {
                    ProgressView().controlSize(.large)
                } else {
                    Button(action: model.isReady ? model.togglePlay : onLoad) {
                        Image(systemName: model.isReady ? (model.isPlaying ? "pause.fill" : "play.fill") : "plus.circle")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(Stem.purple)
                    }
                    .buttonStyle(.plain)
                }
                Text(model.status)
                    .font(.footnote)
                    .foregroundStyle(Stem.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .padding(40)
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Circle())
        .onTapGesture { if !model.isReady && !model.isProcessing { onLoad() } }
    }
}

struct TransportView: View {
    @ObservedObject var model: StemPlayerViewModel

    var body: some View {
        HStack(spacing: 28) {
            transportButton("backward.end.fill") { model.stop() }
            transportButton(model.isPlaying ? "pause.fill" : "play.fill") { model.togglePlay() }
            transportButton("stop.fill") { model.stop() }
        }
        .disabled(!model.isReady)
        .opacity(model.isReady ? 1 : 0.35)
    }

    private func transportButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Stem.ink)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
}

/// One stem: name, volume, mute, headphones (solo), and the loop-length buttons.
struct StemRowView: View {
    @ObservedObject var model: StemPlayerViewModel
    let stem: String
    private let bars: [(String, Float)] = [("¼", 0.25), ("½", 0.5), ("1", 1), ("2", 2)]

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(stem.capitalized).font(.subheadline.weight(.medium))
                Spacer()
                iconToggle("speaker.slash.fill", on: model.muted.contains(stem)) { model.toggleMute(stem) }
                iconToggle("headphones", on: model.soloed.contains(stem)) { model.toggleSolo(stem) }
            }
            Slider(
                value: Binding(
                    get: { model.volumes[stem] ?? 0.8 },
                    set: { model.setVolume(stem, $0) }
                ), in: 0...1
            )
            .tint(Stem.purple)

            HStack(spacing: 6) {
                ForEach(bars, id: \.0) { label, value in
                    let active = model.loopBars[stem] == value
                    Button(label) {
                        model.setLoop(stem, bars: active ? nil : value)
                    }
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(active ? Stem.amber.opacity(0.25) : Stem.creamDeep.opacity(0.5))
                    .overlay(active ? Circle().fill(Stem.amber).frame(width: 4, height: 4).offset(y: -12) : nil, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Stem.cream)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Stem.creamDeep, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(model.isReady ? 1 : 0.5)
    }

    private func iconToggle(_ name: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 14))
                .foregroundStyle(on ? Stem.purple : Stem.inkSoft)
                .frame(width: 30, height: 30)
                .background(on ? Stem.purple.opacity(0.12) : .clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
