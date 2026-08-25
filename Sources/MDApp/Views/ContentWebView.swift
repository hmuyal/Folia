import SwiftUI
import WebKit

/// Hosts the single WKWebView that carries the editor and the preview.
struct ContentWebView: NSViewRepresentable {
    let bridge: WebBridge

    func makeNSView(context: Context) -> WKWebView {
        bridge.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) { }
}
