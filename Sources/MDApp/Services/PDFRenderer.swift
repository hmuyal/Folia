import AppKit
import WebKit
import CoreGraphics

/// Paginated PDF export built on `WKWebView.createPDF`.
///
/// NSPrintOperation would paginate for us, but it deadlocks whenever the app
/// is not a visible, active GUI app — which makes it impossible to test and
/// risky to rely on. createPDF is async, dependable, and returns instantly
/// even offscreen. The cost is that it captures one flat image of the page, so
/// pagination is done here: measure the laid-out document, choose break points
/// that never cut through a block, capture one slice per page, and compose the
/// slices onto properly sized pages.
@MainActor
enum PDFRenderer {

    struct PageSetup {
        var pageWidth: CGFloat = 612      // US Letter, points
        var pageHeight: CGFloat = 792
        var margin: CGFloat = 46

        var contentWidth: CGFloat { pageWidth - margin * 2 }
        var contentHeight: CGFloat { pageHeight - margin * 2 }
    }

    enum RenderError: LocalizedError {
        case layoutFailed
        case captureFailed(page: Int)
        case documentTooLong(CGFloat)
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .layoutFailed:            return "The document could not be laid out for printing."
            case .captureFailed(let page): return "Page \(page) could not be rendered."
            case .documentTooLong(let h):  return "The document is too long to export (\(Int(h)) points)."
            case .writeFailed:             return "The PDF could not be written."
            }
        }
    }

    /// Renders `html` and writes a paginated PDF. Returns the page count.
    @discardableResult
    static func render(html: String, to url: URL, setup: PageSetup = PageSetup()) async throws -> Int {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: setup.contentWidth, height: setup.contentHeight),
            configuration: config)

        // Off-screen but ordered in: WebKit needs a backing store to render.
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000,
                                width: setup.contentWidth, height: setup.contentHeight),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.orderBack(nil)
        defer {
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }

        let loader = PDFLoadWaiter()
        webView.navigationDelegate = loader
        webView.loadHTMLString(html, baseURL: nil)
        await loader.wait()
        try? await Task.sleep(nanoseconds: 500_000_000)   // fonts, KaTeX, images

        // --- measure -------------------------------------------------------
        guard let layout = await measure(webView, setup: setup) else { throw RenderError.layoutFailed }
        guard layout.total > 0 else { throw RenderError.layoutFailed }
        guard layout.total < 80_000 else { throw RenderError.documentTooLong(layout.total) }

        // The whole document must be in-bounds for createPDF to capture it.
        webView.frame = NSRect(x: 0, y: 0, width: setup.contentWidth, height: layout.total)
        window.setContentSize(NSSize(width: setup.contentWidth, height: layout.total))
        try? await Task.sleep(nanoseconds: 250_000_000)

        // --- capture one slice per page -------------------------------------
        var pages: [CGPDFPage] = []
        for (index, start) in layout.breaks.enumerated() {
            let end = index + 1 < layout.breaks.count ? layout.breaks[index + 1] : layout.total
            let height = min(end - start, setup.contentHeight)
            guard height > 1 else { continue }

            let config = WKPDFConfiguration()
            config.rect = CGRect(x: 0, y: start, width: setup.contentWidth, height: height)

            guard let data = await capture(webView, configuration: config),
                  let provider = CGDataProvider(data: data as CFData),
                  let document = CGPDFDocument(provider),
                  let page = document.page(at: 1)
            else { throw RenderError.captureFailed(page: index + 1) }

            pages.append(page)
        }
        guard !pages.isEmpty else { throw RenderError.layoutFailed }

        // --- compose ---------------------------------------------------------
        var mediaBox = CGRect(x: 0, y: 0, width: setup.pageWidth, height: setup.pageHeight)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { throw RenderError.writeFailed }

        for page in pages {
            let slice = page.getBoxRect(.mediaBox)
            context.beginPDFPage(nil)
            context.saveGState()
            // Slices are top-anchored on the page; PDF origin is bottom-left.
            context.translateBy(x: setup.margin,
                                y: setup.pageHeight - setup.margin - slice.height)
            context.drawPDFPage(page)
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()

        return pages.count
    }

    // MARK: Measuring

    private struct Layout {
        var total: CGFloat
        var breaks: [CGFloat]
    }

    /// Asks the page where it can be cut. Breaks land between top-level blocks
    /// so a code window, table or diagram is never sliced in half; a block
    /// taller than one page is cut on page boundaries because it has to be.
    private static func measure(_ webView: WKWebView, setup: PageSetup) async -> Layout? {
        let script = """
        const pageHeight = pageH;
        const doc = document.querySelector('.md-doc') || document.body;
        const total = Math.ceil(doc.getBoundingClientRect().height + doc.offsetTop);
        const breaks = [0];
        let start = 0;

        for (const el of doc.children) {
          const rect = el.getBoundingClientRect();
          const top = rect.top + window.scrollY;
          const bottom = top + rect.height;
          if (rect.height === 0) continue;

          if (bottom - start > pageHeight) {
            if (rect.height > pageHeight) {
              // Taller than a page: cut it on page boundaries.
              let cut = Math.max(start + pageHeight, top);
              while (bottom - cut > 0 && cut < bottom) {
                breaks.push(cut);
                start = cut;
                cut += pageHeight;
              }
            } else if (top > start) {
              breaks.push(top);
              start = top;
            }
          }
        }
        return { total, breaks };
        """

        let result = await withCheckedContinuation { (c: CheckedContinuation<Any?, Never>) in
            webView.callAsyncJavaScript(script,
                                        arguments: ["pageH": setup.contentHeight],
                                        in: nil, in: .page) { r in
                switch r {
                case .success(let value): c.resume(returning: value)
                case .failure(let e):
                    NSLog("PDF measure failed: \(e)")
                    c.resume(returning: nil)
                }
            }
        }

        guard let dict = result as? [String: Any],
              let total = (dict["total"] as? NSNumber)?.doubleValue,
              let rawBreaks = dict["breaks"] as? [NSNumber]
        else { return nil }

        // Deduplicate and sort defensively — the walk can emit a repeat when a
        // tall block starts exactly on a boundary.
        let breaks = Array(Set(rawBreaks.map { CGFloat($0.doubleValue) })).sorted()
        return Layout(total: CGFloat(total), breaks: breaks.isEmpty ? [0] : breaks)
    }

    private static func capture(_ webView: WKWebView,
                                configuration: WKPDFConfiguration) async -> Data? {
        await withCheckedContinuation { c in
            webView.createPDF(configuration: configuration) { result in
                switch result {
                case .success(let data): c.resume(returning: data)
                case .failure(let error):
                    NSLog("createPDF failed: \(error)")
                    c.resume(returning: nil)
                }
            }
        }
    }
}

private final class PDFLoadWaiter: NSObject, WKNavigationDelegate {
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
