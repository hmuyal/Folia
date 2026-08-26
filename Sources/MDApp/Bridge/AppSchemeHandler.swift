import WebKit
import UniformTypeIdentifiers

/// Serves everything the WebView loads over a private `mdapp://` scheme, so the
/// page never touches `file://` and the CSP can name a single origin.
///
///   mdapp://asset/<path>   bundled JS, CSS and fonts
///   mdapp://doc/<rel>      resolved against the current document's folder
///   mdapp://file/<abs>     an absolute path (leading slash dropped)
///   mdapp://home/<rel>     relative to the user's home directory
///   mdapp://blocked/<url>  a deliberately refused asset
final class AppSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mdapp"

    /// Folder that relative document assets resolve against. Set per active tab.
    var documentBaseDirectory: URL?

    /// Extra folders the user has explicitly opened, so a document may
    /// reference images inside its own workspace.
    var allowedRoots: [URL] = []

    private let assetRoot: URL? = Bundle.main.resourceURL?
        .appendingPathComponent("web", isDirectory: true)

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return respondNotFound(task, nil) }

        if url.host == "blocked" { return respondStatus(403, task: task, url: url) }
        guard let file = fileURL(for: url) else { return respondNotFound(task, url) }

        let cache = url.host == "asset"
            ? "public, max-age=31536000, immutable"
            : "no-store"
        serveFile(file, task: task, url: url, cache: cache)
    }

    /// Maps an mdapp:// URL onto a real file, or nil when it does not resolve.
    /// Shared by the scheme handler and by asset inlining during export.
    func fileURL(for url: URL) -> URL? {
        let host = url.host ?? ""
        let raw = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        let path = raw.removingPercentEncoding ?? raw
        if path.isEmpty { return nil }

        switch host {
        case "asset":
            guard let assetRoot else { return nil }
            return FileIO.contained(path, within: assetRoot)
        case "doc":
            guard let base = documentBaseDirectory else { return nil }
            return FileIO.contained(path, within: base)
        case "file":
            return URL(fileURLWithPath: "/" + path).standardizedFileURL
        case "home":
            return FileIO.contained(path, within: FileManager.default.homeDirectoryForCurrentUser)
        default:
            return nil
        }
    }

    /// Reads an mdapp:// asset as a data: URI, for self-contained export.
    func dataURI(for urlString: String, maxBytes: Int = 8 * 1024 * 1024) -> String? {
        guard let url = URL(string: urlString), url.scheme == Self.scheme,
              let file = fileURL(for: url),
              let data = try? Data(contentsOf: file),
              data.count <= maxBytes
        else { return nil }
        return "data:\(mimeType(for: file));base64,\(data.base64EncodedString())"
    }

    /// Plain-text contents of an mdapp:// asset (used for the stylesheet).
    func text(for urlString: String) -> String? {
        guard let url = URL(string: urlString), url.scheme == Self.scheme,
              let file = fileURL(for: url) else { return nil }
        return try? String(contentsOf: file, encoding: .utf8)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) { }

    // MARK: Serving

    private func serveFile(_ fileURL: URL, task: WKURLSchemeTask, url: URL,
                           cache: String = "no-store") {
        let resolved = fileURL.standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir),
              !isDir.boolValue,
              let data = try? Data(contentsOf: resolved)
        else { return respondNotFound(task, url) }

        let headers = [
            "Content-Type": mimeType(for: resolved),
            "Content-Length": String(data.count),
            "Cache-Control": cache,
            "Access-Control-Allow-Origin": "*",
        ]
        guard let response = HTTPURLResponse(url: url, statusCode: 200,
                                             httpVersion: "HTTP/1.1", headerFields: headers)
        else { return respondNotFound(task, url) }

        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func respondNotFound(_ task: WKURLSchemeTask, _ url: URL?) {
        respondStatus(404, task: task, url: url)
    }

    private func respondStatus(_ code: Int, task: WKURLSchemeTask, url: URL?) {
        guard let url,
              let response = HTTPURLResponse(url: url, statusCode: code,
                                             httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Length": "0"]) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        task.didReceive(response)
        task.didReceive(Data())
        task.didFinish()
    }

    func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        // Explicit table first: UTType guesses poorly for web assets.
        switch ext {
        case "js", "mjs":  return "text/javascript; charset=utf-8"
        case "css":        return "text/css; charset=utf-8"
        case "html":       return "text/html; charset=utf-8"
        case "json", "map":return "application/json; charset=utf-8"
        case "woff2":      return "font/woff2"
        case "woff":       return "font/woff"
        case "ttf":        return "font/ttf"
        case "otf":        return "font/otf"
        case "svg":        return "image/svg+xml"
        case "md", "markdown", "txt": return "text/plain; charset=utf-8"
        default:
            if let type = UTType(filenameExtension: ext),
               let mime = type.preferredMIMEType { return mime }
            return "application/octet-stream"
        }
    }
}
