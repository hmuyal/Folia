import AppKit
import WebKit
import CoreGraphics

/// Headless integration check: boots the real WebView, serves the real bundle
/// over folia://, pushes a document through the real bridge, then inspects the
/// resulting DOM. Run with `Folia --selftest <file.md>`.
///
/// This is the only way to verify the Swift/JS seam without a visible window,
/// and it doubles as the project's smoke test.
@MainActor
enum SelfTest {

    static var isRequested: Bool {
        CommandLine.arguments.contains("--selftest")
    }

    static func run() async -> Never {
        // stdout is a pipe when run from a script, so it block-buffers and a
        // hang would look like total silence. Turn buffering off.
        setvbuf(stdout, nil, _IONBF, 0)

        // Hard stop: a wedged WebView must not leave a stray process behind.
        Task.detached {
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            FileHandle.standardError.write(Data("\nself-test timed out after 45s\n".utf8))
            exit(2)
        }

        var failures = 0
        func check(_ label: String, _ ok: Bool, _ detail: String = "") {
            let mark = ok ? "\u{001B}[32m✓\u{001B}[0m" : "\u{001B}[31m✗\u{001B}[0m"
            print("  \(mark) \(label)\(detail.isEmpty ? "" : "  — \(detail)")")
            if !ok { failures += 1 }
        }

        let path = CommandLine.arguments
            .drop(while: { $0 != "--selftest" })
            .dropFirst()
            .first

        print("\nFolia self-test")
        print("───────────────")

        let bridge = WebBridge()
        var ready = false
        var outlineCount = 0
        var statsWords = 0

        // The export path asks the host to read assets; without this the
        // font and image inlining checks would be meaningless.
        bridge.onRequest = { type, payload in
            await MainActor.run { () -> Any? in
                switch type {
                case "readAsset":
                    guard let url = payload["url"] as? String else { return nil }
                    return bridge.schemeHandler.text(for: url).map { ["text": $0] }
                case "inlineAssets":
                    guard let urls = payload["urls"] as? [String] else { return nil }
                    var out: [String: String] = [:]
                    for url in urls.prefix(400) {
                        if let dataURI = bridge.schemeHandler.dataURI(for: url) { out[url] = dataURI }
                    }
                    return out
                default:
                    return nil
                }
            }
        }

        bridge.onEvent = { event in
            switch event {
            case .ready:              ready = true
            case .outline(let items): outlineCount = items.count
            case .stats(let w, _, _): statsWords = w
            case .log(let level, let message): print("     [web:\(level)] \(message)")
            default: break
            }
        }

        // The view must be in a window for WebKit to lay out and run scripts.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = bridge.webView
        window.orderBack(nil)

        bridge.loadShell()

        let readyDeadline = Date().addingTimeInterval(10)
        while !ready && Date() < readyDeadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        check("web shell loads over folia://", ready,
              ready ? "" : "Folia.ready() never fired — check Resources/web")
        guard ready else { flush(failures); exit(1) }

        // --- push a document -------------------------------------------------
        let url = path.map { URL(fileURLWithPath: $0) }
        let text: String
        if let url, let loaded = try? FileIO.load(url) {
            text = loaded.text
            check("document loads from disk", true, "\(loaded.text.count) chars")
        } else {
            text = "# Hello\n\nSome **bold** text and `code`.\n"
            check("document loads from disk", path == nil, path == nil ? "using built-in sample" : "could not read \(path!)")
        }

        bridge.schemeHandler.documentBaseDirectory = url?.deletingLastPathComponent()
        bridge.setOptions(Preferences.shared.webOptions)
        bridge.setDocument(id: "selftest", text: text, path: url?.path,
                           baseDirectory: url?.deletingLastPathComponent(),
                           cursorLine: 0, scrollLine: 0)

        // Mermaid resolves asynchronously; give the page time to settle.
        try? await Task.sleep(nanoseconds: 2_500_000_000)

        // --- inspect the rendered DOM ---------------------------------------
        let probe = """
        const q = (s) => document.querySelectorAll(s).length;
        const mermaid = [...document.querySelectorAll('.mermaid-block')];
        return {
          headings:   q('.md-doc h1, .md-doc h2, .md-doc h3'),
          codeWindows:q('.code-window'),
          tables:     q('.md-doc table'),
          katex:      q('.katex'),
          mermaidOK:  mermaid.filter(b => b.dataset.state === 'done').length,
          mermaidAll: mermaid.length,
          admonitions:q('.admonition'),
          footnotes:  q('.footnotes'),
          taskBoxes:  q('.task-list-item-checkbox'),
          frontMatter:q('.frontmatter'),
          images:     q('.md-doc img'),
          brokenImgs: q('.md-image-error'),
          inlineScripts: q('script:not([src])'),
          editorLines: q('.cm-line'),
          editorText: (window.Folia?.getText() || '').length,
          docChars:   document.querySelector('.md-doc')?.innerText.length || 0,
          breakout:   q('.breakout'),
        };
        """

        let result = await withCheckedContinuation { (c: CheckedContinuation<[String: Any]?, Never>) in
            bridge.webView.callAsyncJavaScript(probe, arguments: [:], in: nil, in: .page) { r in
                switch r {
                case .success(let value): c.resume(returning: value as? [String: Any])
                case .failure(let e): print("     probe failed: \(e)"); c.resume(returning: nil)
                }
            }
        }

        guard let dom = result else {
            check("DOM probe", false, "callAsyncJavaScript returned nothing")
            flush(failures); exit(1)
        }

        func num(_ key: String) -> Int { (dom[key] as? Int) ?? 0 }

        check("markdown renders",        num("docChars") > 200, "\(num("docChars")) chars of text")
        check("editor holds the source", num("editorText") == text.count,
              "\(num("editorText")) vs \(text.count)")
        check("editor lines drawn",      num("editorLines") > 0, "\(num("editorLines")) visible")
        check("headings",                num("headings") > 0, "\(num("headings"))")
        check("code windows",            num("codeWindows") > 0, "\(num("codeWindows"))")
        check("tables",                  num("tables") > 0, "\(num("tables"))")
        check("KaTeX math",              num("katex") > 0, "\(num("katex")) nodes")
        check("Mermaid diagrams",        num("mermaidAll") == 0 || num("mermaidOK") == num("mermaidAll"),
              "\(num("mermaidOK"))/\(num("mermaidAll")) rendered")
        check("admonitions",             num("admonitions") > 0, "\(num("admonitions"))")
        check("footnotes",               num("footnotes") > 0)
        check("task checkboxes",         num("taskBoxes") > 0, "\(num("taskBoxes"))")
        check("front matter card",       num("frontMatter") > 0)
        check("local image served",      num("images") > 0 && num("brokenImgs") < num("images"),
              "\(num("images")) images, \(num("brokenImgs")) broken")
        check("no inline scripts survive", num("inlineScripts") == 0,
              num("inlineScripts") == 0 ? "sanitiser held" : "LEAK")
        check("outline reached the host", outlineCount > 0, "\(outlineCount) headings")
        check("stats reached the host",   statsWords > 0, "\(statsWords) words")
        check("conditional breakout",     num("breakout") >= 0, "\(num("breakout")) wide blocks")

        // --- export ----------------------------------------------------------
        let html = await bridge.exportHTML(standalone: true)
        let exported = html ?? ""
        check("standalone HTML export", exported.count > 1000, "\(exported.count) bytes")
        check("export inlines fonts",   exported.contains("data:font") || exported.contains("data:application/font"),
              exported.contains("data:font") ? "" : "no font data URI found")
        // Report what is actually unresolved rather than just that something is.
        let leftovers = Self.leftoverReferences(in: exported)
        check("export has no folia:// left", leftovers.isEmpty,
              leftovers.isEmpty ? "" : leftovers.joined(separator: ", "))

        if !leftovers.isEmpty {
            let dump = FileManager.default.temporaryDirectory
                .appendingPathComponent("folia-export-dump.html")
            try? exported.write(to: dump, atomically: true, encoding: .utf8)
            print("     export written to \(dump.path)")
        }

        // --- PDF ------------------------------------------------------------
        // Print is the only path that produces a paginated PDF, so it is worth
        // proving end to end rather than assuming.
        // --- PDF --------------------------------------------------------------
        if let printable = await bridge.printableHTML() {
            let pdfURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("folia-selftest.pdf")
            try? FileManager.default.removeItem(at: pdfURL)

            do {
                let pages = try await PDFRenderer.render(html: printable, to: pdfURL)
                var actualPages = 0
                var size = CGSize.zero
                if let doc = CGPDFDocument(pdfURL as CFURL) {
                    actualPages = doc.numberOfPages
                    if let first = doc.page(at: 1) {
                        size = first.getBoxRect(.mediaBox).size
                    }
                }
                check("PDF export", actualPages > 0, "\(actualPages) pages")
                check("PDF paginates", actualPages > 1,
                      actualPages > 1 ? "reported \(pages)" : "only one page")
                check("PDF page size is Letter",
                      abs(size.width - 612) < 2 && abs(size.height - 792) < 2,
                      "\(Int(size.width))×\(Int(size.height)) pt")
                print("     PDF at \(pdfURL.path)")
            } catch {
                check("PDF export", false, error.localizedDescription)
            }
        } else {
            check("PDF export", false, "printableHTML returned nothing")
        }

        flush(failures)
        exit(failures == 0 ? 0 : 1)
    }

    /// Unresolved folia:// *references* in exported HTML.
    /// Deliberately ignores the string appearing inside a CSS selector such as
    /// `img[src^="folia://blocked"]`, which is a rule, not a dangling asset.
    private static func leftoverReferences(in html: String) -> [String] {
        let patterns = [
            #"(?:src|href|poster)\s*=\s*"folia://[^"]*""#,
            #"url\(\s*['"]?folia://[^)]*\)"#,
        ]
        var found: Set<String> = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            for match in regex.matches(in: html, range: range).prefix(5) {
                if let r = Range(match.range, in: html) {
                    found.insert(String(html[r].prefix(80)))
                }
            }
        }
        return found.sorted()
    }

    private static func flush(_ failures: Int) {
        print(failures == 0
              ? "\n\u{001B}[32mall checks passed\u{001B}[0m\n"
              : "\n\u{001B}[31m\(failures) check(s) failed\u{001B}[0m\n")
        fflush(stdout)
    }
}
