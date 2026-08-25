import SwiftUI
import Combine
import UniformTypeIdentifiers

/// Open documents and which one is frontmost.
final class DocumentStore: ObservableObject {
    @Published private(set) var documents: [Document] = []
    @Published var activeID: UUID?
    @Published var lastError: String?

    private var cancellables: [UUID: AnyCancellable] = [:]

    var active: Document? {
        guard let activeID else { return nil }
        return documents.first { $0.id == activeID }
    }

    var hasUnsavedChanges: Bool { documents.contains { $0.isDirty } }

    // MARK: Opening

    @discardableResult
    func newDocument() -> Document {
        let doc = Document()
        attach(doc)
        return doc
    }

    /// Opens a file, or focuses it if it is already open.
    @discardableResult
    func open(_ url: URL) -> Document? {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL

        if let existing = documents.first(where: {
            $0.url?.resolvingSymlinksInPath().standardizedFileURL == resolved
        }) {
            activeID = existing.id
            return existing
        }

        do {
            let loaded = try FileIO.load(resolved)
            let doc = Document(url: resolved, loaded: loaded)
            attach(doc)
            RecentList.files.add(resolved)
            return doc
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func attach(_ doc: Document) {
        // An untitled, untouched document is a placeholder — replace it rather
        // than leaving an empty tab behind.
        if let only = documents.first, documents.count == 1,
           only.isUntitled, !only.isDirty, only.text.isEmpty {
            detach(only)
        }
        documents.append(doc)
        activeID = doc.id
        cancellables[doc.id] = doc.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
    }

    private func detach(_ doc: Document) {
        cancellables[doc.id]?.cancel()
        cancellables[doc.id] = nil
        documents.removeAll { $0.id == doc.id }
    }

    // MARK: Closing

    /// Returns false when the caller should stop (the user cancelled).
    @discardableResult
    func close(_ doc: Document, promptIfDirty: Bool = true) -> Bool {
        if promptIfDirty && doc.isDirty {
            switch confirmClose(doc) {
            case .cancel: return false
            case .discard: break
            case .save:
                if !saveWithPrompt(doc) { return false }
            }
        }
        let index = documents.firstIndex { $0.id == doc.id }
        detach(doc)
        if activeID == doc.id {
            activeID = documents.indices.contains(index ?? 0)
                ? documents[min(index ?? 0, documents.count - 1)].id
                : documents.last?.id
        }
        return true
    }

    private enum CloseChoice { case save, discard, cancel }

    private func confirmClose(_ doc: Document) -> CloseChoice {
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(doc.fileName)” before closing?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:  return .save
        case .alertSecondButtonReturn: return .discard
        default:                       return .cancel
        }
    }

    // MARK: Saving

    /// Saves, prompting for a location when the document is untitled.
    @discardableResult
    func saveWithPrompt(_ doc: Document) -> Bool {
        if doc.url == nil { return saveAs(doc) }
        do {
            try doc.save()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func saveAs(_ doc: Document) -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = doc.url?.lastPathComponent ?? "Untitled.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try doc.save(to: url)
            RecentList.files.add(url)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func saveAll() {
        for doc in documents where doc.isDirty { saveWithPrompt(doc) }
    }

    // MARK: Tab navigation

    func selectTab(offset: Int) {
        guard let activeID, let i = documents.firstIndex(where: { $0.id == activeID }),
              !documents.isEmpty else { return }
        let next = (i + offset + documents.count) % documents.count
        self.activeID = documents[next].id
    }

    func selectTab(index: Int) {
        guard documents.indices.contains(index) else { return }
        activeID = documents[index].id
    }
}
