import SwiftUI
import UIKit

struct StemacleSettingsView: View {
    @AppStorage("stemacle.keepScreenAwake") private var keepScreenAwake = true
    @AppStorage("stemacle.preferSoloLoopMonitor") private var preferSoloLoopMonitor = false
    @AppStorage("stemacle.showWaveformHints") private var showWaveformHints = true
    @Environment(\.openURL) private var openURL

    var body: some View {
        StemacleScreen(showsTentacleFooter: false) {
            List {
                Section {
                    StemacleIdentityPanel()
                        .padding(.vertical, 4)
                }

                Section("Player") {
                    Toggle("Keep screen awake while playing", isOn: $keepScreenAwake)
                    Toggle("Prefer solo loop monitoring", isOn: $preferSoloLoopMonitor)
                    Toggle("Show waveform scrub hints", isOn: $showWaveformHints)
                }

                Section("App Store") {
                    Button {
                        openURL(URL(string: "https://stemacle.com/privacy/")!)
                    } label: {
                        SettingsLinkRow(label: "Privacy Policy", value: "stemacle.com/privacy")
                    }

                    Button {
                        openURL(URL(string: "https://stemacle.com/support/")!)
                    } label: {
                        SettingsLinkRow(label: "Support", value: "stemacle.com/support")
                    }

                    Button {
                        openURL(URL(string: "https://apps.apple.com/app/id6782539749?action=write-review")!)
                    } label: {
                        SettingsLinkRow(label: "Leave a Review", value: "Rate Stemacle on the App Store")
                    }
                }

                Section("Splitter") {
                    SettingsValueRow(label: "Engine", value: "On-device separation")
                    SettingsValueRow(label: "Stems", value: "Drums, vocals, bass, melody")
                    SettingsValueRow(label: "Processing", value: "On device")
                }

                Section("Build") {
                    SettingsValueRow(label: "Version", value: bundleVersion)
                    SettingsValueRow(label: "Build", value: buildVersion)
                    SettingsValueRow(label: "Storage", value: "All local for now")
                }
            }
            .stemacleCompactList()
            .background(StemacleDesign.paper)
        }
    }

    private var bundleVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

private struct StemacleIdentityPanel: View {
    var body: some View {
        HStack(spacing: 14) {
            StemacleAppIconMark(size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("Stemacle")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(StemacleDesign.ink)
                Text("Local-first stem splitter")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StemacleDesign.mutedInk)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct SettingsValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(StemacleDesign.ink)
            Spacer()
            Text(value)
                .foregroundStyle(StemacleDesign.mutedInk)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

private struct SettingsLinkRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(StemacleDesign.ink)
            Spacer()
            Text(value)
                .foregroundStyle(StemacleDesign.mutedInk)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}
