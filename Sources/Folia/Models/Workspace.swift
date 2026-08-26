import Foundation
import Combine

/// A folder opened in the sidebar. Loads lazily: a directory's children are
/// only read when it is first expanded, so opening a large repo is cheap.
final class FileNode: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    let name: String

    @Published var children: [FileNode]?
    @Published var isExpanded = false

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
        self.name = url.lastPathComponent
    }

    var isMarkdown: Bool { !isDirectory && FileIO.isMarkdown(url) }

    func loadChildrenIfNeeded() {
        guard isDirectory, children == nil else { return }
        children = Workspace.readDirectory(url)
    }

    func reload() {
        guard isDirectory else { return }
        children = Workspace.readDirectory(url)
    }
}

final class Workspace: ObservableObject {
    let root: URL
    @Published var tree: [FileNode] = []
    @Published var isIndexing = false

    /// Paths of every markdown file below the root, for quick-open and search.
    @Published private(set) var index: [URL] = []

    init(root: URL) {
        self.root = root
        tree = Self.readDirectory(root)
        buildIndex()
    }

    var name: String { root.lastPathComponent }

    private static let ignored: Set<String> = [
        ".git", ".svn", ".hg", "node_modules", ".build", "build", "dist",
        ".next", ".venv", "venv", "__pycache__", ".DS_Store", "Pods",
        ".gradle", "target", ".idea", ".vscode", ".cache",
    ]

    static func readDirectory(_ url: URL) -> [FileNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }

        let nodes: [FileNode] = items.compactMap { child in
            let name = child.lastPathComponent
            if ignored.contains(name) { return nil }
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            // Show every folder, but only text-ish files.
            if !isDir && !FileIO.isMarkdown(child) { return nil }
            return FileNode(url: child, isDirectory: isDir)
        }

        // Folders first, then files; both case-insensitively alphabetical.
        return nodes.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Walks the tree off the main thread so a large folder does not stall the UI.
    private func buildIndex() {
        isIndexing = true
        let root = self.root
        DispatchQueue.global(qos: .utility).async {
            var found: [URL] = []
            let keys: [URLResourceKey] = [.isDirectoryKey]
            if let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let url as URL in walker {
                    if Self.ignored.contains(url.lastPathComponent) {
                        walker.skipDescendants()
                        continue
                    }
                    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    if !isDir && FileIO.isMarkdown(url) { found.append(url) }
                    if found.count > 20_000 { break }
                }
            }
            let sorted = found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            DispatchQueue.main.async {
                self.index = sorted
                self.isIndexing = false
            }
        }
    }

    func refresh() {
        tree = Self.readDirectory(root)
        buildIndex()
    }

    func relativePath(of url: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count).drop(while: { $0 == "/" }))
    }
}
