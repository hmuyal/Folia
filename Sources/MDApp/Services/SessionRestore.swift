import Foundation

/// Remembers which documents were open, where the caret was, and which folder
/// was in the sidebar, so relaunching picks up where you left off.
enum SessionRestore {
    private static let key = "session.v1"

    struct Snapshot: Codable {
        struct Entry: Codable {
            var path: String
            var cursorLine: Int
            var scrollLine: Int
        }
        var open: [Entry] = []
        var activePath: String?
        var workspacePath: String?
    }

    static func save(store: DocumentStore, workspace: Workspace?) {
        var snapshot = Snapshot()
        // Untitled documents have nothing on disk to point back to.
        snapshot.open = store.documents.compactMap { doc in
            guard let path = doc.url?.path else { return nil }
            return Snapshot.Entry(path: path,
                                  cursorLine: doc.cursorLine,
                                  scrollLine: doc.scrollLine)
        }
        snapshot.activePath = store.active?.url?.path
        snapshot.workspacePath = workspace?.root.path

        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> Snapshot? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return nil }
        return snapshot
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
