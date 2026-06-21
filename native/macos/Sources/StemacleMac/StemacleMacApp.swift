import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WebKit

@main
struct StemacleMacApp: App {
    @StateObject private var bridge = StemacleNativeBridge()

    var body: some Scene {
        WindowGroup("Stemacle") {
            StemacleDesktopWorkbench(bridge: bridge)
                .frame(minWidth: 1120, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Stemacle") {
                Button("Command Palette") {
                    bridge.sendCommand("command-palette")
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Add Audio Files") {
                    bridge.chooseAudioFilesFromMenu()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Add Folder") {
                    bridge.chooseAudioFolderFromMenu()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Rescan Library") {
                    bridge.rescanLibraryFromMenu()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("Open Stem Splitter") {
                    bridge.navigate(to: "stemacle://app/app/index.html")
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Open Stem Shuffle") {
                    bridge.navigate(to: "stemacle://app/apps/stem-shuffle/index.html")
                }
                .keyboardShortcut("2", modifiers: [.command])

                Divider()

                Button("Reveal Stemacle Data") {
                    bridge.revealApplicationSupportFromMenu()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Reload Instrument") {
                    bridge.reloadInstrumentFromMenu()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Clear Desktop State") {
                    bridge.clearDesktopStateFromMenu()
                }
            }
        }
    }
}

struct StemacleDesktopWorkbench: View {
    @ObservedObject var bridge: StemacleNativeBridge

    var body: some View {
        StemacleWebInstrument(bridge: bridge)
            .ignoresSafeArea()
            .safeAreaInset(edge: .top, spacing: 0) {
                StemacleDesktopTitleBar(
                    summary: bridge.desktopSummary,
                    openSplitter: {
                        bridge.navigate(to: "stemacle://app/app/index.html")
                    },
                    openShuffle: {
                        bridge.navigate(to: "stemacle://app/apps/stem-shuffle/index.html")
                    },
                    openPalette: {
                        bridge.sendCommand("command-palette")
                    }
                )
            }
            .safeAreaInset(edge: .bottom) {
                StemacleDesktopStatusBar(
                    summary: bridge.desktopSummary,
                    addFiles: bridge.chooseAudioFilesFromMenu,
                    addFolder: bridge.chooseAudioFolderFromMenu,
                    revealData: bridge.revealApplicationSupportFromMenu
                )
            }
    }
}

struct StemacleDesktopTitleBar: View {
    let summary: StemacleDesktopSummary
    let openSplitter: () -> Void
    let openShuffle: () -> Void
    let openPalette: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                StemacleDesktopAppIcon(size: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Stemacle")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(red: 0.15, green: 0.12, blue: 0.15))
                    Text(summary.storageReady ? "Local-first desktop workbench" : "Preparing local storage")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(red: 0.46, green: 0.41, blue: 0.39))
                }

                Spacer(minLength: 16)

                Button(action: openSplitter) {
                    Label("Splitter", systemImage: "waveform")
                }
                .help("Open Stem Splitter")

                Button(action: openShuffle) {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .help("Open Stem Shuffle")

                Button(action: openPalette) {
                    Label("Palette", systemImage: "command")
                }
                .help("Open command palette")
            }
            .buttonStyle(.plain)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(red: 0.94, green: 0.90, blue: 0.80).opacity(0.96))

            Divider()
                .overlay(Color(red: 0.72, green: 0.66, blue: 0.56).opacity(0.62))
        }
    }
}

struct StemacleDesktopAppIcon: View {
    var size: CGFloat = 30

    var body: some View {
        Group {
            if let image = NSImage(contentsOf: StemaclePaths.webRoot().appendingPathComponent("assets/stemacle-tentacle.png")) {
                Image(nsImage: image)
                    .resizable()
            } else {
                Image(systemName: "waveform.circle.fill")
                    .resizable()
            }
        }
        .aspectRatio(contentMode: .fill)
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(9, size * 0.28), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: max(9, size * 0.28), style: .continuous)
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.22, green: 0.17, blue: 0.12).opacity(0.18), radius: 6, y: 2)
        .accessibilityLabel("Stemacle app icon")
    }
}

struct StemacleDesktopStatusBar: View {
    let summary: StemacleDesktopSummary
    let addFiles: () -> Void
    let addFolder: () -> Void
    let revealData: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 14) {
                Label(summary.statusText, systemImage: summary.storageReady ? "internaldrive.fill" : "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(summary.storageReady ? Color.primary : Color.orange)

                Text(summary.countText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 16)

                Button(action: addFiles) {
                    Label("Audio", systemImage: "waveform.badge.plus")
                }
                .help("Add local audio files")

                Button(action: addFolder) {
                    Label("Folder", systemImage: "folder.badge.plus")
                }
                .help("Add a local music folder")

                Button(action: revealData) {
                    Label("Data", systemImage: "folder")
                }
                .help(summary.dataRoot)
            }
            .buttonStyle(.borderless)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color(red: 0.94, green: 0.90, blue: 0.80).opacity(0.96))
        }
    }
}

struct StemacleWebInstrument: NSViewRepresentable {
    @ObservedObject var bridge: StemacleNativeBridge

    func makeCoordinator() -> Coordinator {
        Coordinator(
            schemeHandler: StemacleSchemeHandler(root: StemaclePaths.webRoot()),
            navigationDelegate: StemacleNavigationDelegate()
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.setURLSchemeHandler(context.coordinator.schemeHandler, forURLScheme: "stemacle")
        configuration.userContentController.addUserScript(WKUserScript(
            source: StemacleNativeBridge.injectedJavaScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        configuration.userContentController.addScriptMessageHandler(
            bridge,
            contentWorld: .page,
            name: "stemacleNative"
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator.navigationDelegate
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
        bridge.attach(webView)
        webView.load(URLRequest(url: URL(string: "stemacle://app/")!))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        bridge.attach(webView)
    }

    final class Coordinator {
        let schemeHandler: StemacleSchemeHandler
        let navigationDelegate: StemacleNavigationDelegate

        init(schemeHandler: StemacleSchemeHandler, navigationDelegate: StemacleNavigationDelegate) {
            self.schemeHandler = schemeHandler
            self.navigationDelegate = navigationDelegate
        }
    }
}

final class StemacleNavigationDelegate: NSObject, WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if url.scheme == "stemacle" {
            decisionHandler(.allow)
            return
        }

        if let internalURL = internalStemacleRoute(for: url) {
            webView.load(URLRequest(url: internalURL))
            decisionHandler(.cancel)
            return
        }

        if url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    private func internalStemacleRoute(for url: URL) -> URL? {
        guard url.scheme == "https" || url.scheme == "http",
              url.host == "stemacle.com"
        else {
            return nil
        }

        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty || path == "app" || path == "app/index.html" {
            return URL(string: "stemacle://app/app/index.html")
        }

        if path == "apps/stem-shuffle" || path == "apps/stem-shuffle/index.html" {
            return URL(string: "stemacle://app/apps/stem-shuffle/index.html")
        }

        return nil
    }
}

final class StemacleSchemeHandler: NSObject, WKURLSchemeHandler {
    private let root: URL

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              let fileURL = fileURL(for: requestURL)
        else {
            urlSchemeTask.didFailWithError(StemacleSchemeError.notFound)
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let response = URLResponse(
                url: requestURL,
                mimeType: mimeType(for: fileURL),
                expectedContentLength: data.count,
                textEncodingName: textEncodingName(for: fileURL)
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func fileURL(for requestURL: URL) -> URL? {
        var path = requestURL.path
        if path.isEmpty || path == "/" {
            path = "/index.html"
        } else if path.hasSuffix("/") {
            path += "index.html"
        }

        let relativePath = String(path.drop(while: { $0 == "/" }))
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : "\(root.path)/"
        guard candidate.path.hasPrefix(rootPath) else { return nil }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                let index = candidate.appendingPathComponent("index.html")
                return FileManager.default.fileExists(atPath: index.path) ? index : nil
            }
            return candidate
        }

        return nil
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": return "text/html"
        case "js", "mjs": return "text/javascript"
        case "css": return "text/css"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg": return "image/svg+xml"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "wasm": return "application/wasm"
        default: return "application/octet-stream"
        }
    }

    private func textEncodingName(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "html", "js", "mjs", "css", "json": return "utf-8"
        default: return nil
        }
    }
}

enum StemacleSchemeError: LocalizedError {
    case notFound

    var errorDescription: String? {
        "Stemacle could not find that bundled app resource."
    }
}

@MainActor
final class StemacleNativeBridge: NSObject, ObservableObject, WKScriptMessageHandlerWithReply {
    static let injectedJavaScript = """
    (() => {
      if (window.stemacleNative) return;

      const stateListeners = new Set();
      const commandListeners = new Set();
      const invoke = (name, ...args) => window.webkit.messageHandlers.stemacleNative.postMessage({ name, args });

      window.stemacleNative = {
        platform: 'darwin',
        getDesktopState: () => invoke('getDesktopState'),
        pickAudioFiles: () => invoke('pickAudioFiles'),
        pickAudioFolder: () => invoke('pickAudioFolder'),
        addLibraryPaths: (paths) => invoke('addLibraryPaths', paths),
        rescanLibrary: () => invoke('rescanLibrary'),
        enqueueAnalysis: (trackId, options) => invoke('enqueueAnalysis', trackId, options || {}),
        enqueueDownload: (url) => invoke('enqueueDownload', url),
        saveSession: (session) => invoke('saveSession', session || {}),
        exportTrack: (trackId, options) => invoke('exportTrack', trackId, options || {}),
        readTrackFile: (trackId) => invoke('readTrackFile', trackId),
        revealPath: (path) => invoke('revealPath', path),
        clearDesktopState: () => invoke('clearDesktopState'),
        onStateChanged: (handler) => {
          stateListeners.add(handler);
          invoke('getDesktopState').then((state) => handler(state));
          return () => stateListeners.delete(handler);
        },
        onCommand: (handler) => {
          commandListeners.add(handler);
          return () => commandListeners.delete(handler);
        }
      };

      window.__stemacleNativeStateChanged = (state) => {
        stateListeners.forEach((handler) => handler(state));
      };

      window.__stemacleNativeCommand = (command) => {
        commandListeners.forEach((handler) => handler(command));
      };
    })();
    """

    @Published private(set) var desktopSummary = StemacleDesktopSummary()

    private weak var webView: WKWebView?
    private var tracks: [StemacleTrack] = []
    private var roots: [StemacleRoot] = []
    private var queue: [[String: Any]] = []
    private var sessions: [[String: Any]] = []
    private var exports: [[String: Any]] = []
    private let createdAt = ISO8601DateFormatter().string(from: Date())
    private let fileManager = FileManager.default
    private let appSupportRoot: URL

    override init() {
        appSupportRoot = Self.defaultApplicationSupportRoot()
        super.init()
        _ = prepareApplicationSupportDirectories()
        refreshDesktopSummary(from: desktopState())
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func navigate(to urlString: String) {
        guard let url = URL(string: urlString) else { return }
        webView?.load(URLRequest(url: url))
    }

    func sendCommand(_ command: String) {
        evaluate("__stemacleNativeCommand(\(jsonString(command)))")
    }

    func chooseAudioFilesFromMenu() {
        _ = chooseAudioFiles()
    }

    func chooseAudioFolderFromMenu() {
        _ = chooseAudioFolder()
    }

    func rescanLibraryFromMenu() {
        _ = rescanLibrary()
    }

    func revealApplicationSupportFromMenu() {
        _ = revealPath(appSupportRoot.path)
    }

    func reloadInstrumentFromMenu() {
        webView?.reload()
    }

    func clearDesktopStateFromMenu() {
        tracks.removeAll()
        roots.removeAll()
        queue.removeAll()
        sessions.removeAll()
        exports.removeAll()
        emitState()
    }

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        Task { @MainActor in
            let result = self.handle(message.body)
            replyHandler(result.value, result.error)
        }
    }

    private func handle(_ body: Any) -> (value: Any?, error: String?) {
        guard let payload = body as? [String: Any],
              let name = payload["name"] as? String
        else {
            return (nil, "Invalid native bridge message.")
        }
        let args = payload["args"] as? [Any] ?? []

        switch name {
        case "getDesktopState":
            return (desktopState(), nil)
        case "pickAudioFiles":
            return (chooseAudioFiles(), nil)
        case "pickAudioFolder":
            return (chooseAudioFolder(), nil)
        case "addLibraryPaths":
            let paths = args.first as? [String] ?? []
            return (addLibraryPaths(paths), nil)
        case "rescanLibrary":
            return (rescanLibrary(), nil)
        case "enqueueAnalysis":
            let trackId = args.first as? String ?? ""
            let options = args.dropFirst().first as? [String: Any] ?? [:]
            return (enqueueAnalysis(trackId: trackId, options: options), nil)
        case "enqueueDownload":
            let url = args.first as? String ?? ""
            return (enqueueDownload(url: url), nil)
        case "saveSession":
            let session = args.first as? [String: Any] ?? [:]
            return (saveSession(session), nil)
        case "exportTrack":
            let trackId = args.first as? String ?? ""
            let options = args.dropFirst().first as? [String: Any] ?? [:]
            return (exportTrack(trackId: trackId, options: options), nil)
        case "readTrackFile":
            let trackId = args.first as? String ?? ""
            return readTrackFile(trackId)
        case "revealPath":
            let path = args.first as? String ?? ""
            return (revealPath(path), nil)
        case "clearDesktopState":
            clearDesktopStateFromMenu()
            return (desktopState(), nil)
        default:
            return (nil, "Unknown native bridge action: \(name)")
        }
    }

    private func chooseAudioFiles() -> [[String: Any]] {
        let panel = NSOpenPanel()
        panel.title = "Add audio to Stemacle Library"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK else { return [] }
        return addURLs(panel.urls)
    }

    private func chooseAudioFolder() -> [[String: Any]] {
        let panel = NSOpenPanel()
        panel.title = "Add Stemacle Music Folder"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK else { return [] }

        for url in panel.urls {
            roots.append(StemacleRoot(url: url))
        }
        return addURLs(panel.urls.flatMap(audioFiles(in:)))
    }

    private func addLibraryPaths(_ paths: [String]) -> [[String: Any]] {
        let urls = paths.map { URL(fileURLWithPath: $0) }
        let audioURLs = urls.flatMap { url in
            isDirectory(url) ? audioFiles(in: url) : [url]
        }
        return addURLs(audioURLs)
    }

    private func addURLs(_ urls: [URL]) -> [[String: Any]] {
        var added: [StemacleTrack] = []
        for url in urls where isAudioFile(url) {
            let standardized = url.standardizedFileURL
            if !tracks.contains(where: { $0.url == standardized }) {
                let track = StemacleTrack(url: standardized)
                tracks.append(track)
                added.append(track)
            }
        }
        tracks.sort { $0.addedAt > $1.addedAt }
        emitState()
        return added.map { $0.dictionary(paths: cachePaths(for: $0)) }
    }

    private func rescanLibrary() -> [String: Any] {
        let rescanned = roots.flatMap { audioFiles(in: $0.url) }
        _ = addURLs(rescanned)
        return desktopState()
    }

    private func enqueueAnalysis(trackId: String, options: [String: Any]) -> [String: Any] {
        let quality = options["quality"] as? String ?? "fast-preview"
        var job = jobRecord(kind: "analysis", trackId: trackId)
        job["quality"] = quality
        job["status"] = "completed"
        job["progress"] = 1
        job["message"] = quality == "fast-preview"
            ? "Preview analysis is ready in the bundled splitter."
            : "High quality native analysis is queued for the desktop worker path."
        queue.insert(job, at: 0)
        emitState()
        return job
    }

    private func enqueueDownload(url: String) -> [String: Any] {
        var job = jobRecord(kind: "download", trackId: nil)
        job["url"] = url
        job["status"] = "failed"
        job["progress"] = 1
        job["message"] = "URL downloads need yt-dlp outside the App Store sandbox."
        job["error"] = "Install the Windows/Linux workbench or use a local audio file on macOS."
        queue.insert(job, at: 0)
        emitState()
        return job
    }

    private func saveSession(_ session: [String: Any]) -> [String: Any] {
        var record = session
        record["id"] = "session-\(Int(Date().timeIntervalSince1970 * 1000))"
        record["name"] = record["name"] ?? "Stemacle Mac session"
        record["savedAt"] = timestamp()
        sessions.insert(record, at: 0)
        emitState()
        return record
    }

    private func exportTrack(trackId: String, options: [String: Any]) -> [String: Any] {
        let record: [String: Any] = [
            "id": "export-\(Int(Date().timeIntervalSince1970 * 1000))",
            "trackId": trackId,
            "trackName": tracks.first(where: { $0.id == trackId })?.name ?? trackId,
            "kind": options["kind"] as? String ?? "stem-pack",
            "format": options["format"] as? String ?? "wav",
            "status": "planned",
            "createdAt": timestamp()
        ]
        exports.insert(record, at: 0)
        emitState()
        return record
    }

    private func readTrackFile(_ trackId: String) -> (value: Any?, error: String?) {
        guard let track = tracks.first(where: { $0.id == trackId }) else {
            return (nil, "Track was not found in the Mac library.")
        }

        do {
            let data = try Data(contentsOf: track.url)
            return ([
                "name": track.url.lastPathComponent,
                "mimeType": mimeType(for: track.url),
                "bytes": Array(data)
            ], nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private func revealPath(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }

    private func desktopState() -> [String: Any] {
        let appRoot = applicationSupportRoot()
        let updatedAt = timestamp()
        refreshDesktopSummary(from: [
            "updatedAt": updatedAt,
            "library": tracks,
            "libraryRoots": roots,
            "queue": queue,
            "sessions": sessions,
            "exports": exports,
            "paths": ["dataRoot": appRoot.path],
            "storageReady": prepareApplicationSupportDirectories()
        ])

        return [
            "version": 4,
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "platform": "macos",
            "localFirst": true,
            "storageReady": desktopSummary.storageReady,
            "library": tracks.map { $0.dictionary(paths: cachePaths(for: $0)) },
            "libraryRoots": roots.map { $0.dictionary(trackCount: tracks(in: $0).count) },
            "queue": queue,
            "sessions": sessions,
            "exports": exports,
            "recentProjects": sessions,
            "tools": [
                "ffmpeg": ["available": false, "command": NSNull()],
                "ffprobe": ["available": false, "command": NSNull()],
                "demucs": ["available": false, "command": NSNull()],
                "ytDlp": ["available": false, "command": NSNull()]
            ],
            "paths": [
                "dataRoot": appRoot.path,
                "modelCacheRoot": appRoot.appendingPathComponent("model-cache").path,
                "stemCacheRoot": appRoot.appendingPathComponent("stem-cache").path,
                "analysisCacheRoot": appRoot.appendingPathComponent("analysis-cache").path,
                "exportRoot": appRoot.appendingPathComponent("exports").path,
                "downloadRoot": appRoot.appendingPathComponent("downloads").path
            ],
            "settings": [
                "downloadRoot": appRoot.appendingPathComponent("downloads").path,
                "localFirst": true
            ],
            "desktop": [
                "storageReady": desktopSummary.storageReady,
                "localFirst": true,
                "statusText": desktopSummary.statusText,
                "libraryCount": desktopSummary.libraryCount,
                "libraryRootCount": desktopSummary.libraryRootCount,
                "queueCount": desktopSummary.queueCount,
                "sessionCount": desktopSummary.sessionCount,
                "exportCount": desktopSummary.exportCount
            ],
            "modelCache": [
                "cacheRoot": appRoot.appendingPathComponent("model-cache").path,
                "models": [
                    ["id": "fast-preview", "label": "Fast Preview", "stems": 4, "status": "ready", "available": true],
                    ["id": "demucs-4stem", "label": "High Quality 4-Stem", "stems": 4, "status": "external", "available": false],
                    ["id": "demucs-6stem", "label": "High Quality 6-Stem", "stems": 6, "status": "external", "available": false],
                    ["id": "mdx-extra-q", "label": "MDX Extra Q", "stems": 4, "status": "external", "available": false]
                ]
            ]
        ]
    }

    private func emitState() {
        guard let json = jsonLiteral(desktopState()) else { return }
        evaluate("__stemacleNativeStateChanged(\(json))")
    }

    private func evaluate(_ source: String) {
        webView?.evaluateJavaScript("window.\(source);", completionHandler: nil)
    }

    private func jobRecord(kind: String, trackId: String?) -> [String: Any] {
        var record: [String: Any] = [
            "id": "\(kind)-\(Int(Date().timeIntervalSince1970 * 1000))",
            "kind": kind,
            "status": "queued",
            "progress": 0,
            "message": "",
            "createdAt": timestamp(),
            "startedAt": timestamp(),
            "finishedAt": timestamp()
        ]
        if let trackId {
            record["trackId"] = trackId
            record["trackName"] = tracks.first(where: { $0.id == trackId })?.name ?? trackId
        }
        return record
    }

    private func audioFiles(in folder: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL, isAudioFile(url) else { return nil }
            return url
        }
    }

    private func isAudioFile(_ url: URL) -> Bool {
        ["mp3", "wav", "m4a", "aac", "ogg", "flac", "opus", "aiff", "aif"]
            .contains(url.pathExtension.lowercased())
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func tracks(in root: StemacleRoot) -> [StemacleTrack] {
        tracks.filter { $0.url.path.hasPrefix(root.url.path) }
    }

    private static func defaultApplicationSupportRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("Stemacle", isDirectory: true)
    }

    private func applicationSupportRoot() -> URL {
        _ = prepareApplicationSupportDirectories()
        return appSupportRoot
    }

    private func prepareApplicationSupportDirectories() -> Bool {
        let directories = [
            appSupportRoot,
            appSupportRoot.appendingPathComponent("model-cache", isDirectory: true),
            appSupportRoot.appendingPathComponent("stem-cache", isDirectory: true),
            appSupportRoot.appendingPathComponent("analysis-cache", isDirectory: true),
            appSupportRoot.appendingPathComponent("exports", isDirectory: true),
            appSupportRoot.appendingPathComponent("downloads", isDirectory: true)
        ]

        do {
            for directory in directories {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            return true
        } catch {
            return false
        }
    }

    private func refreshDesktopSummary(from state: [String: Any]) {
        let paths = state["paths"] as? [String: Any]
        desktopSummary = StemacleDesktopSummary(
            libraryCount: countItems(in: state["library"], fallback: tracks.count),
            libraryRootCount: countItems(in: state["libraryRoots"], fallback: roots.count),
            queueCount: countItems(in: state["queue"], fallback: queue.count),
            sessionCount: countItems(in: state["sessions"], fallback: sessions.count),
            exportCount: countItems(in: state["exports"], fallback: exports.count),
            dataRoot: paths?["dataRoot"] as? String ?? appSupportRoot.path,
            storageReady: state["storageReady"] as? Bool ?? false,
            lastUpdatedAt: state["updatedAt"] as? String ?? timestamp()
        )
    }

    private func countItems(in value: Any?, fallback: Int) -> Int {
        if let items = value as? [Any] {
            return items.count
        }
        return fallback
    }

    private func cachePaths(for track: StemacleTrack) -> [String: Any] {
        let root = applicationSupportRoot()
        let id = track.id.replacingOccurrences(of: "/", with: "-")
        let stemDir = root.appendingPathComponent("stem-cache").appendingPathComponent(id)
        let analysisRoot = root.appendingPathComponent("analysis-cache")
        let exportDir = root.appendingPathComponent("exports").appendingPathComponent(id)
        return [
            "stemDir": stemDir.path,
            "analysisFile": analysisRoot.appendingPathComponent("\(id).json").path,
            "manifestFile": analysisRoot.appendingPathComponent("\(id).manifest.json").path,
            "waveformFile": analysisRoot.appendingPathComponent("\(id).waveform.json").path,
            "exportDir": exportDir.path,
            "stemSets": [:]
        ]
    }

    private func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "m4a", "aac": return "audio/mp4"
        case "flac": return "audio/flac"
        case "ogg", "opus": return "audio/ogg"
        case "aiff", "aif": return "audio/aiff"
        default: return "application/octet-stream"
        }
    }

    private func jsonString(_ value: String) -> String {
        jsonLiteral(value) ?? "\"\""
    }

    private func jsonLiteral(_ value: Any) -> String? {
        if let string = value as? String,
           let data = try? JSONEncoder().encode(string) {
            return String(data: data, encoding: .utf8)
        }

        guard JSONSerialization.isValidJSONObject(["value": value]),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [])
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

struct StemacleDesktopSummary: Equatable {
    var libraryCount = 0
    var libraryRootCount = 0
    var queueCount = 0
    var sessionCount = 0
    var exportCount = 0
    var dataRoot = ""
    var storageReady = false
    var lastUpdatedAt = ""

    var statusText: String {
        storageReady ? "Local library ready" : "Preparing local storage"
    }

    var countText: String {
        "\(libraryCount) tracks • \(libraryRootCount) folders • \(queueCount) jobs • \(sessionCount) sessions • \(exportCount) exports"
    }
}

struct StemacleTrack: Equatable {
    let url: URL
    let addedAt = Date()

    var id: String { url.standardizedFileURL.path }
    var name: String { url.lastPathComponent }

    func dictionary(paths: [String: Any]) -> [String: Any] {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return [
            "id": id,
            "name": name,
            "sourceKind": "macos",
            "path": url.path,
            "size": values?.fileSize ?? 0,
            "lastModified": values?.contentModificationDate?.timeIntervalSince1970 ?? 0,
            "addedAt": ISO8601DateFormatter().string(from: addedAt),
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "analysisStatus": "indexed",
            "duration": NSNull(),
            "sampleRate": NSNull(),
            "channels": NSNull(),
            "bpm": NSNull(),
            "key": NSNull(),
            "stemAvailability": [
                "preview": false,
                "demucs4": false,
                "demucs6": false,
                "mdxExtraQ": false
            ],
            "cache": paths,
            "analysis": [
                "lastQuality": NSNull(),
                "lastRunAt": NSNull(),
                "error": NSNull()
            ],
            "download": NSNull(),
            "errors": []
        ]
    }
}

struct StemacleRoot {
    let url: URL
    let addedAt = Date()

    func dictionary(trackCount: Int) -> [String: Any] {
        [
            "id": url.standardizedFileURL.path,
            "path": url.path,
            "addedAt": ISO8601DateFormatter().string(from: addedAt),
            "lastIndexedAt": ISO8601DateFormatter().string(from: Date()),
            "trackCount": trackCount
        ]
    }
}

enum StemaclePaths {
    static func webRoot() -> URL {
        let repo = repoRoot()
        let sourceDist = repo.appendingPathComponent("dist/native", isDirectory: true)
        if FileManager.default.fileExists(atPath: sourceDist.appendingPathComponent("index.html").path) {
            return sourceDist
        }

        if let resourceRoot = Bundle.main.resourceURL?.appendingPathComponent("repo/dist/native", isDirectory: true),
           FileManager.default.fileExists(atPath: resourceRoot.appendingPathComponent("index.html").path) {
            return resourceRoot
        }

        return repo.appendingPathComponent("native", isDirectory: true)
    }

    static func repoRoot() -> URL {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--repo-root"),
           arguments.indices.contains(index + 1) {
            return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        }

        if let envRoot = ProcessInfo.processInfo.environment["STEMACLE_REPO_ROOT"],
           !envRoot.isEmpty {
            return URL(fileURLWithPath: envRoot, isDirectory: true)
        }

        if let resourceRoot = Bundle.main.resourceURL?.appendingPathComponent("repo", isDirectory: true),
           FileManager.default.fileExists(atPath: resourceRoot.path) {
            return resourceRoot
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}
