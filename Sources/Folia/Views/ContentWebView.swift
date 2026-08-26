import SwiftUI
import WebKit

/// Hosts the single WKWebView that carries the editor and the preview.
struct ContentWebView: NSViewRepresentable {
    let bridge: WebBridge
    var isHidden = false

    func makeNSView(context: Context) -> WKWebView {
        bridge.webView
    }

    // WKWebView composites its content out-of-process, so SwiftUI's .opacity()
    // doesn't reliably hide it — set AppKit's own isHidden instead.
    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.isHidden = isHidden
    }
}
