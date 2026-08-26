import WebKit
import AppKit
import Combine

/// Messages the page sends up to the host.
enum WebEvent {
    case ready
    case textChanged(id: String, text: String, cursorLine: Int)
    case outline([OutlineItem])
    case cursorMoved(line: Int)
    case openExternal(URL)
    case openRelative(String)
    case toggleTask(index: Int, checked: Bool)
    case requestSave
    case stats(words: Int, characters: Int, readingMinutes: Int)
    case log(level: String, message: String)
}

struct OutlineItem: Identifiable, Equatable, Codable {
    var id: String { "\(line)-\(slug)" }
    var level: Int
    var text: String
    var slug: String
    var line: Int
}

/// Owns the WKWebView and the protocol spoken across it.
final class WebBridge: NSObject, ObservableObject {
    let webView: WKWebView
    let schemeHandler: AppSchemeHandler

    /// Set by the owner before the first document is pushed.
    var onEvent: ((WebEvent) -> Void)?

    /// Round-trip requests from the page that need an answer.
    /// Returns a JSON-encodable value, or nil to reject.
    var onRequest: ((String, [String: Any]) async -> Any?)?

    @Published private(set) var isReady = false
    private var pendingWork: [() -> Void] = []

    override init() {
        let handler = AppSchemeHandler()
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        config.userContentController = controller
        config.suppressesIncrementalRendering = false

        // Everything the page loads comes through this handler; no file:// and
        // no network origin is ever reachable from the document.
        config.setURLSchemeHandler(handler, forURLScheme: AppSchemeHandler.scheme)

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        self.schemeHandler = handler
        self.webView = WKWebView(frame: .zero, configuration: config)

        super.init()

        // The document paints its own background; a white flash between
        // renders would break the cream canvas.
        webView.underPageBackgroundColor = .clear
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false

        controller.add(MessageProxy(self), name: "folia")
        controller.addScriptMessageHandler(ReplyProxy(self), contentWorld: .page, name: "foliaAsync")
        webView.navigationDelegate = self
        webView.uiDelegate = self

        if ProcessInfo.processInfo.environment["FOLIA_INSPECT"] != nil {
            webView.isInspectable = true
        }
    }

    func loadShell() {
        guard let url = URL(string: "folia://asset/index.html") else { return }
        webView.load(URLRequest(url: url))
    }

    // MARK: Host -> page

    /// Queues work until the page reports ready, so early calls are not lost.
    private func run(_ block: @escaping () -> Void) {
        if isReady { block() } else { pendingWork.append(block) }
    }

    private func call(_ function: String, _ argument: Any? = nil) {
        run { [weak self] in
            guard let self else { return }
            let json = argument.map(Self.jsonLiteral) ?? ""
            self.webView.evaluateJavaScript("window.Folia && Folia.\(function)(\(json));") { _, error in
                if let error { NSLog("Folia JS error in \(function): \(error)") }
            }
        }
    }

    func setDocument(id: String, text: String, path: String?, baseDirectory: URL?,
                     cursorLine: Int, scrollLine: Int) {
        schemeHandler.documentBaseDirectory = baseDirectory
        call("setDocument", [
            "id": id, "text": text, "path": path ?? "",
            "cursorLine": cursorLine, "scrollLine": scrollLine,
        ])
    }

    func setOptions(_ options: [String: Any]) { call("setOptions", options) }
    func setTheme(dark: Bool)                 { call("setTheme", dark ? "dark" : "light") }
    func setViewMode(_ mode: String)          { call("setViewMode", mode) }
    func setEditorPrefs(_ prefs: [String: Any]) { call("setEditorPrefs", prefs) }
    func setCustomCSS(_ css: String)          { call("setCustomCSS", css) }
    func command(_ name: String)              { call("command", name) }
    func scrollToLine(_ line: Int)            { call("scrollToLine", line) }
    func replaceText(_ text: String)          { call("replaceText", text) }

    /// Async round-trips use callAsyncJavaScript so there is no request-id dance.
    @MainActor
    func exportHTML(standalone: Bool) async -> String? {
        await callAsync("return await Folia.exportHTML(standalone);",
                        args: ["standalone": standalone]) as? String
    }

    @MainActor
    func currentText() async -> String? {
        await callAsync("return Folia.getText();") as? String
    }

    @MainActor
    func printableHTML() async -> String? {
        await callAsync("return await Folia.exportHTML(true, { print: true });") as? String
    }

    /// Already on the main actor, so the continuation can call straight into
    /// WebKit without a queue hop.
    @MainActor
    private func callAsync(_ body: String, args: [String: Any] = [:]) async -> Any? {
        await withCheckedContinuation { continuation in
            webView.callAsyncJavaScript(body, arguments: args, in: nil, in: .page) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error):
                    NSLog("Folia async JS error: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func jsonLiteral(_ value: Any) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value],
                                                  options: [.fragmentsAllowed]),
           let text = String(data: data, encoding: .utf8) {
            return String(text.dropFirst().dropLast())   // unwrap the array
        }
        return "null"
    }

    // MARK: Page -> host

    fileprivate func handle(message body: Any) {
        guard let dict = body as? [String: Any],
              let type = dict["type"] as? String else { return }

        switch type {
        case "ready":
            isReady = true
            let queued = pendingWork
            pendingWork.removeAll()
            queued.forEach { $0() }
            onEvent?(.ready)

        case "textChanged":
            onEvent?(.textChanged(
                id: dict["id"] as? String ?? "",
                text: dict["text"] as? String ?? "",
                cursorLine: dict["cursorLine"] as? Int ?? 0))

        case "outline":
            let raw = dict["items"] as? [[String: Any]] ?? []
            onEvent?(.outline(raw.map {
                OutlineItem(level: $0["level"] as? Int ?? 1,
                            text:  $0["text"]  as? String ?? "",
                            slug:  $0["slug"]  as? String ?? "",
                            line:  $0["line"]  as? Int ?? 0)
            }))

        case "cursor":
            onEvent?(.cursorMoved(line: dict["line"] as? Int ?? 0))

        case "openExternal":
            if let href = dict["href"] as? String, let url = URL(string: href) {
                onEvent?(.openExternal(url))
            }

        case "openRelative":
            if let href = dict["href"] as? String { onEvent?(.openRelative(href)) }

        case "toggleTask":
            onEvent?(.toggleTask(index: dict["index"] as? Int ?? -1,
                                 checked: dict["checked"] as? Bool ?? false))

        case "requestSave":
            onEvent?(.requestSave)

        case "stats":
            onEvent?(.stats(words: dict["words"] as? Int ?? 0,
                            characters: dict["characters"] as? Int ?? 0,
                            readingMinutes: dict["readingMinutes"] as? Int ?? 0))

        case "log":
            onEvent?(.log(level: dict["level"] as? String ?? "log",
                          message: dict["message"] as? String ?? ""))

        default:
            break
        }
    }
}

// MARK: - Navigation policy

extension WebBridge: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }

        // The shell itself is the only thing allowed to navigate the frame.
        if url.scheme == AppSchemeHandler.scheme {
            return decisionHandler(.allow)
        }
        // Anything else is a document link: hand it to the host instead.
        if action.navigationType == .linkActivated {
            onEvent?(.openExternal(url))
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("Folia shell navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        NSLog("Folia shell failed to load: \(error.localizedDescription)")
    }

    /// window.open and target=_blank both route to the default browser.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { onEvent?(.openExternal(url)) }
        return nil
    }
}

/// Breaks the retain cycle WKUserContentController would otherwise create.
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: WebBridge?
    init(_ target: WebBridge) { self.target = target }
    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.handle(message: message.body)
    }
}

/// Handles page requests that expect a value back; the JS side awaits these.
private final class ReplyProxy: NSObject, WKScriptMessageHandlerWithReply {
    weak var target: WebBridge?
    init(_ target: WebBridge) { self.target = target }

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let dict = message.body as? [String: Any],
              let type = dict["type"] as? String,
              let handler = target?.onRequest else {
            replyHandler(nil, "unsupported request")
            return
        }
        Task {
            let result = await handler(type, dict)
            await MainActor.run { replyHandler(result, nil) }
        }
    }
}
