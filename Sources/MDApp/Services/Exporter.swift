import AppKit
import WebKit
import UniformTypeIdentifiers

/// HTML, PDF, print and rich-text output.
///
/// PDF goes through NSPrintOperation rather than WKWebView.createPDF: the
/// latter renders the whole document as a single enormous page, which is not
/// a usable PDF. The print system paginates properly and honours @page CSS.
@MainActor
enum Exporter {

    // MARK: HTML

    static func exportHTML(_ html: String, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName + ".html"
        panel.allowedContentTypes = [.html]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            presentError(error)
        }
    }

    // MARK: PDF & print

    /// Renders `html` in an offscreen WebView and drives the print system.
    /// The continuation fires once the print job finishes, so the retained
    /// window is released at the right moment.
    /// Set by the self-test to trace where a print job stalls.
    static var trace: ((String) -> Void)?

    static func printHTML(_ html: String,
                          jobName: String,
                          saveTo url: URL?,
                          showPanel: Bool) async {
        trace?("printHTML start")

        // NSPrintOperation needs a visible, active app: with no key window it
        // has nowhere to put its sheet and blocks indefinitely. Refuse rather
        // than wedge the app; the caller falls back to PDF export.
        if showPanel, NSApp.keyWindow == nil, NSApp.mainWindow == nil {
            trace?("no visible window — refusing to print")
            return
        }
        let config = WKWebViewConfiguration()
        let pageSize = NSSize(width: 816, height: 1056)      // US Letter at 96dpi
        let webView = WKWebView(frame: NSRect(origin: .zero, size: pageSize),
                                configuration: config)

        // The window has to be ordered in, not merely created: WebKit's print
        // path waits on a backing store, and an un-ordered window never gets
        // one, so NSPrintOperation.run() blocks forever. Parking it far
        // off-screen keeps it invisible while still real.
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -20_000, y: -20_000),
                                                  size: pageSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.orderBack(nil)

        let loader = LoadWaiter()
        webView.navigationDelegate = loader
        webView.loadHTMLString(html, baseURL: nil)
        trace?("waiting for load")
        await loader.wait()
        trace?("loaded")

        // Give web fonts, KaTeX layout and images a beat to settle.
        try? await Task.sleep(nanoseconds: 600_000_000)

        trace?("building NSPrintInfo")
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false
        info.topMargin = 40; info.bottomMargin = 40
        info.leftMargin = 40; info.rightMargin = 40

        if let url {
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        }
        trace?("NSPrintInfo ready")

        let operation = webView.printOperation(with: info)
        operation.jobTitle = jobName
        operation.showsPrintPanel = showPanel
        operation.showsProgressPanel = showPanel
        // A separate thread would race the offscreen window's teardown.
        operation.canSpawnSeparateThread = false

        trace?("running print operation")
        // runModal(for:) is the callback-based variant; run() spins its own
        // nested loop, which deadlocks when called from an async context.
        // The print panel is presented as a sheet on the host window, so for an
        // interactive Print it must hang off a window the user can actually see
        // — never the off-screen one holding the WebView.
        let sheetHost = showPanel
            ? (NSApp.keyWindow ?? NSApp.mainWindow ?? window)
            : window

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let delegate = PrintCompletion { continuation.resume() }
            printDelegate = delegate
            operation.runModal(for: sheetHost,
                               delegate: delegate,
                               didRun: #selector(PrintCompletion.printOperationDidRun(_:success:contextInfo:)),
                               contextInfo: nil)
        }
        trace?("print operation finished")
        printDelegate = nil
        window.contentView = nil
        window.orderOut(nil)
        window.close()
    }

    /// Export goes through PDFRenderer, not the print system: NSPrintOperation
    /// deadlocks unless the app is visible and active, which makes it both
    /// untestable and a hang risk.
    static func exportPDF(_ html: String, suggestedName: String) async -> String? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName + ".pdf"
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let pages = try await PDFRenderer.render(html: html, to: url)
            return "Exported \(pages) page\(pages == 1 ? "" : "s")"
        } catch {
            presentError(error)
            return nil
        }
    }

    // MARK: Pasteboard

    /// Puts RTF, HTML and plain text on the pasteboard so the result pastes
    /// well into Mail, Pages, Notes and Slack alike.
    static func copyAsRichText(_ html: String) {
        guard let data = html.data(using: .utf8) else { return }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        guard let attributed = try? NSAttributedString(data: data, options: options,
                                                       documentAttributes: nil) else { return }

        let pb = NSPasteboard.general
        pb.clearContents()

        let range = NSRange(location: 0, length: attributed.length)
        if let rtf = try? attributed.data(from: range,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            pb.setData(rtf, forType: .rtf)
        }
        pb.setString(html, forType: .html)
        pb.setString(attributed.string, forType: .string)
    }

    // MARK: TextBundle

    /// Writes a .textbundle package: the Markdown source plus every local
    /// asset it references, so the document travels intact.
    static func exportTextBundle(text: String, sourceDirectory: URL?, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName + ".textbundle"
        panel.canCreateDirectories = true
        panel.message = "Export as a TextBundle package"
        guard panel.runModal() == .OK, let bundleURL = panel.url else { return }

        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: bundleURL.path) {
                try fm.removeItem(at: bundleURL)
            }
            try fm.createDirectory(at: bundleURL, withIntermediateDirectories: true)

            let info: [String: Any] = [
                "version": 2,
                "type": "net.daringfireball.markdown",
                "transient": false,
                "creatorIdentifier": Bundle.main.bundleIdentifier ?? "com.hmuyal.mdapp",
            ]
            let infoData = try JSONSerialization.data(withJSONObject: info,
                                                      options: [.prettyPrinted, .sortedKeys])
            try infoData.write(to: bundleURL.appendingPathComponent("info.json"))
            try text.write(to: bundleURL.appendingPathComponent("text.md"),
                           atomically: true, encoding: .utf8)

            // Copy the assets the document actually references.
            if let sourceDirectory {
                let referenced = localImagePaths(in: text)
                guard !referenced.isEmpty else { return }
                let assets = bundleURL.appendingPathComponent("assets", isDirectory: true)
                try fm.createDirectory(at: assets, withIntermediateDirectories: true)
                for relative in referenced {
                    let from = sourceDirectory.appendingPathComponent(relative).standardizedFileURL
                    guard fm.fileExists(atPath: from.path) else { continue }
                    let to = assets.appendingPathComponent(from.lastPathComponent)
                    if !fm.fileExists(atPath: to.path) { try? fm.copyItem(at: from, to: to) }
                }
            }
        } catch {
            presentError(error)
        }
    }

    /// Relative image targets from Markdown image syntax, ignoring remote URLs.
    private static func localImagePaths(in text: String) -> [String] {
        let pattern = #"!\[[^\]]*\]\(\s*([^)\s]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var found: [String] = []
        for match in regex.matches(in: text, range: range) {
            guard let r = Range(match.range(at: 1), in: text) else { continue }
            let path = String(text[r])
            if path.hasPrefix("http") || path.hasPrefix("data:") || path.hasPrefix("/") { continue }
            found.append(path)
        }
        return Array(Set(found))
    }

    static func copyHTML(_ html: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(html, forType: .string)
    }

    private static func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

/// Retains the print callback target for the life of the operation.
@MainActor private var printDelegate: PrintCompletion?

/// Bridges NSPrintOperation's Objective-C completion selector into async/await.
private final class PrintCompletion: NSObject {
    private let finished: () -> Void
    private var done = false
    init(_ finished: @escaping () -> Void) { self.finished = finished }

    @objc func printOperationDidRun(_ operation: NSPrintOperation,
                                    success: Bool,
                                    contextInfo: UnsafeMutableRawPointer?) {
        guard !done else { return }
        done = true
        finished()
    }
}

/// Bridges WKNavigationDelegate's callback into async/await.
private final class LoadWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var finished = false

    func wait() async {
        if finished { return }
        await withCheckedContinuation { c in
            if finished { c.resume() } else { continuation = c }
        }
    }

    private func complete() {
        guard !finished else { return }
        finished = true
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { complete() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { complete() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) { complete() }
}
