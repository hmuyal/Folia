import Foundation
import Combine

/// One open document.
///
/// While a document is being edited the authoritative text lives in CodeMirror
/// inside the WebView; this mirror is updated on a debounce and is what gets
/// written to disk. `savedText` is the last thing actually persisted, so
/// dirtiness is a real comparison rather than a flag that can drift.
final class Document: ObservableObject, Identifiable {
    let id = UUID()

    @Published var url: URL?
    @Published var text: String
    @Published private(set) var savedText: String
    @Published var externalChange: ExternalChange?

    var encoding: String.Encoding = .utf8
    var lineEnding: LineEnding = .lf
    var lastKnownModificationDate: Date?
    var hadDecodingIssues = false

    /// Restored when the tab is reactivated or the session reopens.
    var cursorLine: Int = 0
    var scrollLine: Int = 0

    private var watcher: FileWatcher?

    struct ExternalChange: Equatable {
        enum Kind { case modified, deleted }
        var kind: Kind
        var diskText: String?
    }

    init(url: URL? = nil, loaded: LoadedFile? = nil) {
        self.url = url
        self.text = loaded?.text ?? ""
        self.savedText = loaded?.text ?? ""
        self.encoding = loaded?.encoding ?? .utf8
        self.lineEnding = loaded?.lineEnding ?? .lf
        self.lastKnownModificationDate = loaded?.modificationDate
        self.hadDecodingIssues = loaded?.hadDecodingIssues ?? false
        if url != nil { startWatching() }
    }

    var isDirty: Bool { text != savedText }
    var isUntitled: Bool { url == nil }

    var displayName: String {
        url?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }
    var fileName: String { url?.lastPathComponent ?? "Untitled" }

    /// The folder relative paths and images resolve against.
    var baseDirectory: URL? { url?.deletingLastPathComponent() }

    // MARK: Persistence

    func save() throws {
        guard let url else { return }
        stopWatching()
        defer { startWatching() }
        try FileIO.save(text, to: url, encoding: encoding, lineEnding: lineEnding)
        savedText = text
        lastKnownModificationDate = FileIO.modificationDate(of: url)
        externalChange = nil
    }

    func save(to newURL: URL) throws {
        stopWatching()
        try FileIO.save(text, to: newURL, encoding: encoding, lineEnding: lineEnding)
        url = newURL
        savedText = text
        lastKnownModificationDate = FileIO.modificationDate(of: newURL)
        externalChange = nil
        startWatching()
    }

    /// Discards in-memory edits and reloads from disk.
    func reloadFromDisk() throws {
        guard let url else { return }
        let loaded = try FileIO.load(url)
        text = loaded.text
        savedText = loaded.text
        encoding = loaded.encoding
        lineEnding = loaded.lineEnding
        lastKnownModificationDate = loaded.modificationDate
        externalChange = nil
    }

    // MARK: External changes

    private func startWatching() {
        guard let url else { return }
        watcher = FileWatcher(url: url) { [weak self] changed in
            self?.handleExternalChange(at: changed)
        }
    }

    private func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    private func handleExternalChange(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            externalChange = ExternalChange(kind: .deleted, diskText: nil)
            return
        }
        // Ignore the notification our own save produced.
        let modDate = FileIO.modificationDate(of: url)
        if let modDate, let known = lastKnownModificationDate,
           abs(modDate.timeIntervalSince(known)) < 0.001 { return }

        guard let loaded = try? FileIO.load(url) else { return }
        lastKnownModificationDate = modDate

        // Identical content — nothing to tell the user about.
        if loaded.text == text { savedText = loaded.text; return }

        if !isDirty {
            // No local edits to lose: adopt the new content silently.
            text = loaded.text
            savedText = loaded.text
            externalChange = nil
        } else {
            externalChange = ExternalChange(kind: .modified, diskText: loaded.text)
        }
    }

    func acceptExternalChange() {
        guard let disk = externalChange?.diskText else { return }
        text = disk
        savedText = disk
        externalChange = nil
    }

    func dismissExternalChange() {
        // Keep local edits; the file is now considered ahead of disk.
        externalChange = nil
    }

    deinit { stopWatching() }
}
