import SwiftUI
import Combine
import AppKit

/// Wires the document store, preferences and the WebView together.
@MainActor
final class AppState: ObservableObject {
    let store = DocumentStore()
    let prefs = Preferences.shared
    let bridge = WebBridge()

    @Published var outline: [OutlineItem] = []
    @Published var words = 0
    @Published var characters = 0
    @Published var readingMinutes = 0
    @Published var systemIsDark = false
    @Published var workspace: Workspace?
    @Published var statusMessage: String?
    @Published var showQuickOpen = false
    @Published var showFolderSearch = false

    private var cancellables = Set<AnyCancellable>()
    private var pushedDocumentID: UUID?
    private var suppressPush = false
    private var appearanceObserver: NSKeyValueObservation?
    private var autosaveTask: Task<Void, Never>?

    var isDark: Bool {
        switch prefs.appearance {
        case .system: return systemIsDark
        case .light:  return false
        case .dark:   return true
        }
    }

    init() {
        systemIsDark = Self.detectSystemDark()

        bridge.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        bridge.onRequest = { [weak self] type, payload in
            await self?.handleRequest(type, payload)
        }
        bridge.loadShell()

        // Push the active document whenever the selection changes.
        store.$activeID
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.pushActiveDocument() }
            }
            .store(in: &cancellables)

        // Renderer options and appearance flow straight through.
        prefs.$render
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.pushOptions() }
            }
            .store(in: &cancellables)

        prefs.$appearance
            .sink { [weak self] _ in
                Task { @MainActor in self?.pushTheme() }
            }
            .store(in: &cancellables)

        prefs.$viewMode
            .sink { [weak self] mode in
                Task { @MainActor in self?.bridge.setViewMode(mode.rawValue) }
            }
            .store(in: &cancellables)

        for publisher in [prefs.$editorFontSize, prefs.$previewFontSize, prefs.$measure] {
            publisher.dropFirst()
                .sink { [weak self] _ in Task { @MainActor in self?.pushEditorPrefs() } }
                .store(in: &cancellables)
        }

        DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.systemIsDark = Self.detectSystemDark()
                    self?.pushTheme()
                }
            }
    }

    private static func detectSystemDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
    }

    // MARK: Pushing state into the page

    func pushAll() {
        pushOptions()
        pushTheme()
        pushEditorPrefs()
        bridge.setViewMode(prefs.viewMode.rawValue)
        bridge.setCustomCSS(prefs.customCSS)
        pushActiveDocument(force: true)
    }

    func pushActiveDocument(force: Bool = false) {
        guard let doc = store.active else {
            // No document is active (e.g. the last tab was just closed) — forget
            // what's on screen so the next document opened always gets pushed,
            // even if it's the same one that was just showing.
            pushedDocumentID = nil
            return
        }
        guard force || pushedDocumentID != doc.id else { return }
        pushedDocumentID = doc.id
        suppressPush = true
        bridge.setDocument(
            id: doc.id.uuidString,
            text: doc.text,
            path: doc.url?.path,
            baseDirectory: doc.baseDirectory,
            cursorLine: doc.cursorLine,
            scrollLine: doc.scrollLine)
        suppressPush = false
    }

    func pushOptions() { bridge.setOptions(prefs.webOptions) }
    func pushTheme()   { bridge.setTheme(dark: isDark) }

    func pushEditorPrefs() {
        bridge.setEditorPrefs([
            "fontSize":        prefs.editorFontSize,
            "previewFontSize": prefs.previewFontSize,
            "measure":         prefs.measure,
            "tabWidth":        prefs.tabWidth,
            "lineNumbers":     prefs.showLineNumbersInEditor,
            "wrap":            prefs.wrapEditorLines,
            "typewriter":      prefs.typewriterMode,
            "focus":           prefs.focusMode,
            "vim":             prefs.vimMode,
            "scrollSync":      prefs.scrollSync,
            "splitRatio":      prefs.splitRatio,
        ])
    }

    // MARK: Events from the page

    private func handle(_ event: WebEvent) {
        switch event {
        case .ready:
            pushAll()

        case .textChanged(let id, let text, let cursorLine):
            guard !suppressPush,
                  let doc = store.documents.first(where: { $0.id.uuidString == id })
            else { return }
            doc.text = text
            doc.cursorLine = cursorLine
            scheduleAutosave(for: doc)

        case .outline(let items):
            outline = items

        case .cursorMoved(let line):
            store.active?.cursorLine = line

        case .openExternal(let url):
            openExternal(url)

        case .openRelative(let href):
            openRelative(href)

        case .toggleTask(let index, let checked):
            toggleTask(at: index, checked: checked)

        case .requestSave:
            if let doc = store.active { store.saveWithPrompt(doc) }

        case .stats(let w, let c, let m):
            words = w; characters = c; readingMinutes = m

        case .log(let level, let message):
            NSLog("[web:\(level)] \(message)")
        }
    }

    private func openExternal(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto", "tel"].contains(scheme) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openRelative(_ href: String) {
        guard let base = store.active?.baseDirectory else { return }
        let cleaned = href.components(separatedBy: "#").first ?? href
        let decoded = cleaned.removingPercentEncoding ?? cleaned
        // The document is untrusted input — a `..`-laden link must not be able
        // to walk out of its folder and have us open (or launch) something
        // elsewhere on disk.
        guard var target = FileIO.contained(decoded, within: base) else {
            statusMessage = "Not found: \(decoded)"
            return
        }

        // [[Wiki links]] and bare names get a .md extension if that resolves.
        if !FileManager.default.fileExists(atPath: target.path),
           target.pathExtension.isEmpty {
            let withExt = target.appendingPathExtension("md")
            if FileManager.default.fileExists(atPath: withExt.path) { target = withExt }
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir) else {
            statusMessage = "Not found: \(decoded)"
            return
        }
        if isDir.boolValue {
            openFolder(target)
        } else if FileIO.isMarkdown(target) {
            store.open(target)
        } else {
            NSWorkspace.shared.open(target)
        }
    }

    /// Flips the nth "- [ ]" in the source. Index comes from the preview's
    /// checkbox order, which matches source order.
    private func toggleTask(at index: Int, checked: Bool) {
        guard index >= 0, let doc = store.active else { return }
        var lines = doc.text.components(separatedBy: "\n")
        var seen = -1
        let pattern = try? NSRegularExpression(
            pattern: #"^(\s*(?:[-*+]|\d+[.)])\s+\[)([ xX])(\])"#)

        for i in lines.indices {
            let line = lines[i]
            let range = NSRange(line.startIndex..., in: line)
            guard let match = pattern?.firstMatch(in: line, range: range) else { continue }
            seen += 1
            guard seen == index else { continue }
            guard let r = Range(match.range(at: 2), in: line) else { return }
            lines[i] = line.replacingCharacters(in: r, with: checked ? "x" : " ")
            doc.text = lines.joined(separator: "\n")
            bridge.replaceText(doc.text)
            if prefs.autosave, doc.url != nil { try? doc.save() }
            return
        }
    }

    // MARK: Autosave

    /// Writes the document a beat after typing stops. Untitled documents are
    /// skipped — autosave must never put up a save panel unprompted.
    private func scheduleAutosave(for doc: Document) {
        autosaveTask?.cancel()
        guard prefs.autosave, doc.url != nil else { return }

        autosaveTask = Task { @MainActor [weak self, weak doc] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled, let self, let doc,
                  doc.isDirty, doc.url != nil,
                  doc.externalChange == nil       // never overwrite a conflict
            else { return }
            do {
                try doc.save()
            } catch {
                self.statusMessage = "Autosave failed: \(error.localizedDescription)"
                self.clearStatusSoon()
            }
        }
    }

    // MARK: Requests that need an answer

    private func handleRequest(_ type: String, _ payload: [String: Any]) async -> Any? {
        switch type {
        case "saveImage":
            return saveImage(payload)
        case "setSplitRatio":
            if let ratio = payload["ratio"] as? Double { prefs.splitRatio = ratio }
            return ["ok": true]

        case "readAsset":
            // fetch() does not resolve custom schemes inside WKWebView, so the
            // page asks Swift for asset contents instead.
            guard let url = payload["url"] as? String else { return nil }
            return bridge.schemeHandler.text(for: url).map { ["text": $0] }

        case "inlineAssets":
            guard let urls = payload["urls"] as? [String] else { return nil }
            var out: [String: String] = [:]
            var budget = 24 * 1024 * 1024      // cap the whole export, not just each file
            for url in urls.prefix(400) {
                guard let dataURI = bridge.schemeHandler.dataURI(for: url) else { continue }
                budget -= dataURI.utf8.count
                if budget < 0 { break }
                out[url] = dataURI
            }
            return out
        default:
            return nil
        }
    }

    /// Writes a pasted or dropped image beside the document and returns the
    /// relative path to insert. Untitled documents have nowhere to put it, so
    /// the caller falls back to a data URI.
    private func saveImage(_ payload: [String: Any]) -> [String: Any]? {
        guard let base64 = payload["data"] as? String,
              let data = Data(base64Encoded: base64),
              let base = store.active?.baseDirectory
        else { return nil }

        let suggested = (payload["suggestedName"] as? String) ?? "image"
        let mime = (payload["mimeType"] as? String) ?? "image/png"
        let ext = Self.extensionFor(mime: mime, fallbackName: suggested)

        let assets = base.appendingPathComponent("assets", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        } catch {
            statusMessage = "Could not create assets folder"
            return nil
        }

        let stem = Self.sanitize(
            (suggested as NSString).deletingPathExtension.isEmpty
                ? "image" : (suggested as NSString).deletingPathExtension)

        // Never clobber an existing asset.
        var target = assets.appendingPathComponent("\(stem).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = assets.appendingPathComponent("\(stem)-\(counter).\(ext)")
            counter += 1
        }

        do {
            try data.write(to: target, options: .atomic)
        } catch {
            statusMessage = "Could not save image"
            return nil
        }
        return ["path": "assets/\(target.lastPathComponent)"]
    }

    private static func extensionFor(mime: String, fallbackName: String) -> String {
        switch mime.lowercased() {
        case "image/png":  return "png"
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/gif":  return "gif"
        case "image/webp": return "webp"
        case "image/svg+xml": return "svg"
        case "image/heic": return "heic"
        case "image/tiff": return "tiff"
        default:
            let ext = (fallbackName as NSString).pathExtension.lowercased()
            return ext.isEmpty ? "png" : ext
        }
    }

    private static func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(cleaned).replacingOccurrences(of: "--", with: "-")
                              .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                              .isEmpty ? "image" : String(cleaned)
    }

    // MARK: Commands

    /// Opens each URL as a folder (in the sidebar) or a document, whichever it is.
    /// Shared by Finder/Dock opens and by dropping files onto the window.
    func open(urls: [URL]) {
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue { openFolder(url) } else { store.open(url) }
        }
    }

    func openFolder(_ url: URL) {
        let std = url.standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: std.path, isDirectory: &isDir),
              isDir.boolValue else {
            statusMessage = "That folder no longer exists"
            RecentList.folders.remove(std)
            clearStatusSoon()
            return
        }
        workspace = Workspace(root: std)
        RecentList.folders.add(std)
        prefs.showSidebar = true
    }

    /// Folder-only picker, so ⇧⌘O is unambiguous next to ⌘O.
    func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"
        panel.message = "Choose a folder to browse in the sidebar"
        if let current = workspace?.root { panel.directoryURL = current.deletingLastPathComponent() }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFolder(url)
    }

    /// Closes the sidebar folder. Open documents are left alone — they are not
    /// owned by the workspace, and closing a folder should not close your work.
    func closeFolder() {
        workspace = nil
        showQuickOpen = false
        showFolderSearch = false
    }

    // MARK: Session

    /// Reopens last session's documents. Files that have since been deleted or
    /// moved are skipped silently rather than throwing an error per file.
    func restoreSession() {
        guard let snapshot = SessionRestore.load() else { return }

        if let path = snapshot.workspacePath {
            let url = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                workspace = Workspace(root: url)
            }
        }

        for entry in snapshot.open {
            let url = URL(fileURLWithPath: entry.path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if let doc = store.open(url) {
                doc.cursorLine = entry.cursorLine
                doc.scrollLine = entry.scrollLine
            }
        }

        if let active = snapshot.activePath,
           let match = store.documents.first(where: { $0.url?.path == active }) {
            store.activeID = match.id
        }
        pushActiveDocument(force: true)
    }

    func saveSession() {
        SessionRestore.save(store: store, workspace: workspace)
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Open a Markdown file or a folder"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue { openFolder(url) } else { store.open(url) }
        }
    }

    func revealInFinder() {
        guard let url = store.active?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
