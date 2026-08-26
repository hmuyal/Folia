import SwiftUI
import AppKit

/// Menu-facing commands. Kept apart from the wiring in AppState so the state
/// object stays about state.
extension AppState {

    func exportHTML() {
        guard let doc = store.active else { return }
        Task { @MainActor in
            guard let html = await bridge.exportHTML(standalone: true) else {
                statusMessage = "Export failed"
                return
            }
            Exporter.exportHTML(html, suggestedName: doc.displayName)
        }
    }

    func exportPDF() {
        guard let doc = store.active else { return }
        Task { @MainActor in
            guard let html = await bridge.printableHTML() else {
                statusMessage = "Export failed"
                return
            }
            if let message = await Exporter.exportPDF(html, suggestedName: doc.displayName) {
                statusMessage = message
                clearStatusSoon()
            }
        }
    }

    /// Print uses the system dialog so the user gets paper size, printer and
    /// page range. Export-as-PDF takes the renderer path instead, which does
    /// not depend on the print subsystem at all.
    func printDocument() {
        guard let doc = store.active else { return }
        guard NSApp.keyWindow != nil || NSApp.mainWindow != nil else {
            statusMessage = "Open a window before printing"
            clearStatusSoon()
            return
        }
        Task { @MainActor in
            guard let html = await bridge.printableHTML() else { return }
            await Exporter.printHTML(html, jobName: doc.displayName,
                                     saveTo: nil, showPanel: true)
        }
    }

    func copyAsRichText() {
        Task { @MainActor in
            guard let html = await bridge.exportHTML(standalone: true) else { return }
            Exporter.copyAsRichText(html)
            statusMessage = "Copied as rich text"
            clearStatusSoon()
        }
    }

    func copyRenderedHTML() {
        Task { @MainActor in
            guard let html = await bridge.exportHTML(standalone: false) else { return }
            Exporter.copyHTML(html)
            statusMessage = "Copied rendered HTML"
            clearStatusSoon()
        }
    }

    func exportTextBundle() {
        guard let doc = store.active else { return }
        Exporter.exportTextBundle(text: doc.text,
                                  sourceDirectory: doc.baseDirectory,
                                  suggestedName: doc.displayName)
    }

    func clearStatusSoon() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            statusMessage = nil
        }
    }
}
