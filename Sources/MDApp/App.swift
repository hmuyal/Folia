import SwiftUI
import AppKit

@main
struct MDAppMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView(state: state)
                .frame(minWidth: 680, minHeight: 420)
                .onAppear {
                    FontRegistrar.registerBundledFonts()
                    delegate.state = state
                    // Only restore when nothing was opened from Finder, so a
                    // double-clicked file does not arrive buried under tabs.
                    if !delegate.flushPendingOpens() && state.store.documents.isEmpty {
                        state.restoreSession()
                    }
                }
        }
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1180, height: 780)
        .commands { MenuCommands(state: state) }

        Settings {
            SettingsView(state: state)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?
    private var pendingOpens: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard SelfTest.isRequested else { return }
        // Headless: no dock icon, no visible window.
        NSApp.setActivationPolicy(.accessory)
        for window in NSApp.windows { window.orderOut(nil) }
        Task { @MainActor in await SelfTest.run() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !SelfTest.isRequested
    }

    /// Finder double-click, Open With, and files dropped on the Dock icon.
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        if let state {
            open(urls, in: state)
        } else {
            pendingOpens.append(contentsOf: urls)
        }
        sender.reply(toOpenOrPrint: .success)
    }

    /// Returns true when files were waiting to be opened.
    @discardableResult
    func flushPendingOpens() -> Bool {
        guard let state, !pendingOpens.isEmpty else { return false }
        let urls = pendingOpens
        pendingOpens.removeAll()
        open(urls, in: state)
        return true
    }

    private func open(_ urls: [URL], in state: AppState) {
        Task { @MainActor in
            for url in urls {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                if isDir.boolValue { state.openFolder(url) } else { state.store.open(url) }
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        state?.saveSession()
        guard let state, state.store.hasUnsavedChanges else { return .terminateNow }
        let dirty = state.store.documents.filter(\.isDirty)

        let alert = NSAlert()
        alert.messageText = dirty.count == 1
            ? "Save changes to “\(dirty[0].fileName)” before quitting?"
            : "You have \(dirty.count) documents with unsaved changes."
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: dirty.count == 1 ? "Save" : "Save All")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            state.store.saveAll()
            return state.store.hasUnsavedChanges ? .terminateCancel : .terminateNow
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}
