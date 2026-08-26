import Foundation

enum LineEnding: String {
    case lf = "\n", crlf = "\r\n", cr = "\r"

    /// Whichever terminator dominates the file, so saving does not rewrite
    /// every line of a CRLF document checked out on Windows.
    static func detect(in text: String) -> LineEnding {
        var crlf = 0, cr = 0, lf = 0
        var previousWasCR = false
        for ch in text.unicodeScalars {
            switch ch {
            case "\r":
                if previousWasCR { cr += 1 }
                previousWasCR = true
            case "\n":
                if previousWasCR { crlf += 1; previousWasCR = false } else { lf += 1 }
            default:
                if previousWasCR { cr += 1; previousWasCR = false }
            }
        }
        if previousWasCR { cr += 1 }
        if crlf > lf && crlf > cr { return .crlf }
        if cr > lf && cr > crlf { return .cr }
        return .lf
    }
}

struct LoadedFile {
    var text: String
    var encoding: String.Encoding
    var lineEnding: LineEnding
    var modificationDate: Date?
    /// True when the file was not valid UTF-8 and had to be decoded lossily.
    var hadDecodingIssues: Bool
}

enum FileIOError: LocalizedError {
    case unreadable(URL)
    case undecodable(URL)
    case tooLarge(URL, Int)

    var errorDescription: String? {
        switch self {
        case .unreadable(let u):   return "Could not read \(u.lastPathComponent)."
        case .undecodable(let u):  return "\(u.lastPathComponent) is not readable as text."
        case .tooLarge(let u, let n):
            let mb = Double(n) / 1_048_576
            return String(format: "%@ is %.0f MB, which is too large to open.",
                          u.lastPathComponent, mb)
        }
    }
}

enum FileIO {
    /// Refuse anything absurd rather than hanging the UI on a multi-GB file.
    static let maxBytes = 64 * 1024 * 1024

    static func load(_ url: URL) throws -> LoadedFile {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? Int) ?? 0
        if size > maxBytes { throw FileIOError.tooLarge(url, size) }

        guard let data = try? Data(contentsOf: url) else { throw FileIOError.unreadable(url) }

        var encoding = String.Encoding.utf8
        var lossy = false
        var text: String

        if let s = String(data: data, encoding: .utf8) {
            text = s
        } else if let s = decodeWithBOM(data, encoding: &encoding) {
            text = s
        } else if let s = String(data: data, encoding: .isoLatin1) {
            // Last resort: Latin-1 maps every byte, so this always succeeds and
            // keeps the file openable rather than failing outright.
            text = s
            encoding = .isoLatin1
            lossy = true
        } else {
            throw FileIOError.undecodable(url)
        }

        // Strip a UTF-8 BOM so it does not surface as a stray glyph.
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        return LoadedFile(
            text: text,
            encoding: encoding,
            lineEnding: .detect(in: text),
            modificationDate: attrs?[.modificationDate] as? Date,
            hadDecodingIssues: lossy)
    }

    private static func decodeWithBOM(_ data: Data, encoding: inout String.Encoding) -> String? {
        let candidates: [(prefix: [UInt8], enc: String.Encoding)] = [
            ([0xFF, 0xFE, 0x00, 0x00], .utf32LittleEndian),
            ([0x00, 0x00, 0xFE, 0xFF], .utf32BigEndian),
            ([0xFF, 0xFE],             .utf16LittleEndian),
            ([0xFE, 0xFF],             .utf16BigEndian),
        ]
        for c in candidates where data.starts(with: c.prefix) {
            if let s = String(data: data.dropFirst(c.prefix.count), encoding: c.enc) {
                encoding = c.enc
                return s
            }
        }
        return nil
    }

    /// Atomic write that preserves the file's original encoding and line
    /// endings, and keeps POSIX permissions across the replace.
    static func save(_ text: String, to url: URL,
                     encoding: String.Encoding = .utf8,
                     lineEnding: LineEnding = .lf) throws {
        var out = text.replacingOccurrences(of: "\r\n", with: "\n")
                      .replacingOccurrences(of: "\r", with: "\n")
        if lineEnding != .lf {
            out = out.replacingOccurrences(of: "\n", with: lineEnding.rawValue)
        }

        guard let data = out.data(using: encoding, allowLossyConversion: false)
                ?? out.data(using: .utf8) else {
            throw FileIOError.unreadable(url)
        }

        let fm = FileManager.default
        let permissions = (try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber

        // .atomic swaps via a temp file, so a crash mid-write cannot truncate
        // the user's document.
        try data.write(to: url, options: .atomic)

        if let permissions {
            try? fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }

    static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    static let markdownExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext",
        "rmd", "qmd", "mdx", "mdc", "mermaid", "mmd", "text", "txt",
    ]

    static func isMarkdown(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }

    /// Resolves `path` against `base`, or nil if the result would land outside
    /// `base`. Documents are untrusted input — a relative link or image src
    /// laden with `..` must not be able to walk out of the directory (or the
    /// bundle, or the home folder) it's supposed to be confined to. The
    /// trailing "/" avoids a bare-prefix false match against a sibling
    /// directory that merely shares `base`'s name as a prefix.
    static func contained(_ path: String, within base: URL) -> URL? {
        let root = base.standardizedFileURL
        let target = root.appendingPathComponent(path).standardizedFileURL
        guard target.path == root.path || target.path.hasPrefix(root.path + "/") else { return nil }
        return target
    }
}
