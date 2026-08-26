import AppKit

/// A most-recently-used list persisted in UserDefaults.
/// Two instances exist: recently opened documents, and recently opened folders.
final class RecentList: ObservableObject {
    static let files   = RecentList(key: "recentFiles.v1",   limit: 20, notesDocumentController: true)
    static let folders = RecentList(key: "recentFolders.v1", limit: 12, notesDocumentController: false)

    @Published private(set) var urls: [URL] = []

    private let key: String
    private let limit: Int
    /// Only documents belong in the system's Open Recent menu.
    private let notesDocumentController: Bool

    private init(key: String, limit: Int, notesDocumentController: Bool) {
        self.key = key
        self.limit = limit
        self.notesDocumentController = notesDocumentController
        reload()
    }

    /// Entries that have since been deleted or unmounted are dropped.
    func reload() {
        urls = (UserDefaults.standard.array(forKey: key) as? [String] ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ url: URL) {
        let std = url.standardizedFileURL
        urls.removeAll { $0.standardizedFileURL == std }
        urls.insert(std, at: 0)
        if urls.count > limit { urls = Array(urls.prefix(limit)) }
        persist()
        if notesDocumentController {
            NSDocumentController.shared.noteNewRecentDocumentURL(std)
        }
    }

    func remove(_ url: URL) {
        let std = url.standardizedFileURL
        urls.removeAll { $0.standardizedFileURL == std }
        persist()
    }

    func clear() { urls = []; persist() }

    private func persist() {
        UserDefaults.standard.set(urls.map(\.path), forKey: key)
    }
}
