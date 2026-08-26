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
    func application(_ application: NSApplication, open urls: [URL]) {
        if let state {
            open(urls, in: state)
        } else {
            pendingOpens.append(contentsOf: urls)
        }
        // WindowGroup opens a fresh window for this event on its own, in
        // parallel with (and regardless of) the above — most visibly when
        // the document is already open, since then this is the only sign
        // anything happened. Fold it back into the one window we actually
        // want; this is a single-window app, tabs carry multiple documents.
        DispatchQueue.main.async { [weak self] in self?.consolidateWindows() }
    }

    /// Closes every window this WindowGroup has opened beyond the one already
    /// on screen, keeping the key one (or the frontmost) if there's a choice.
    /// Settings and panels (alerts, open/save dialogs) aren't affected: they
    /// don't carry the app's own window title, and Settings starts hidden.
    private func consolidateWindows() {
        let contentWindows = NSApp.windows.filter { $0.isVisible && $0.title == "MDApp" }
        guard contentWindows.count > 1 else { return }
        let keep = contentWindows.first { $0.isKeyWindow } ?? contentWindows[0]
        for window in contentWindows where window !== keep { window.close() }
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
        Task { @MainActor in state.open(urls: urls) }
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
