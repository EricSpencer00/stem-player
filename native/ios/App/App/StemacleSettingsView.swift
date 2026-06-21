import SwiftUI

struct StemacleSettingsView: View {
    @AppStorage("stemacle.keepScreenAwake") private var keepScreenAwake = true
    @AppStorage("stemacle.preferSoloLoopMonitor") private var preferSoloLoopMonitor = false
    @AppStorage("stemacle.showWaveformHints") private var showWaveformHints = true

    var body: some View {
        StemacleScreen {
            Form {
                Section {
                    StemacleIdentityPanel()
                }

                Section("Player") {
                    Toggle("Keep screen awake while playing", isOn: $keepScreenAwake)
                    Toggle("Prefer solo loop monitoring", isOn: $preferSoloLoopMonitor)
                    Toggle("Show waveform scrub hints", isOn: $showWaveformHints)
                }

                Section("Splitter") {
                    SettingsValueRow(label: "Engine", value: "On-device separation")
                    SettingsValueRow(label: "Stems", value: "Drums, vocals, bass, melody")
                    SettingsValueRow(label: "Processing", value: "On device")
                }

                Section {
                    TentacleFooter(opacity: 0.34)
                        .frame(height: 96)
                        .listRowBackground(StemacleDesign.paper.opacity(0.4))
                }
            }
            .background(StemacleDesign.paper)
        }
        .navigationTitle("Settings")
    }
}

private struct StemacleIdentityPanel: View {
    var body: some View {
        HStack(spacing: 16) {
            StemacleAppIconMark(size: 64)
            VStack(alignment: .leading, spacing: 5) {
                Text("Stemacle")
                    .font(.headline)
                Text("Local files, four stems, no upload")
                    .font(.caption)
                    .foregroundStyle(StemacleDesign.mutedInk)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

private struct SettingsValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(StemacleDesign.mutedInk)
                .multilineTextAlignment(.trailing)
        }
    }
}
