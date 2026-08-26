import Foundation

struct SearchHit: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let line: Int          // 0-based
    let text: String       // the matching line, trimmed
    let matchRange: Range<String.Index>?
}

/// Fuzzy path matching for quick-open, and full-text search across a folder.
enum SearchService {

    // MARK: Fuzzy path matching

    /// Subsequence match with a score; higher is better, nil means no match.
    /// Consecutive characters and matches right after a separator score best,
    /// so "remd" ranks README.md above a file with those letters scattered.
    static func fuzzyScore(_ needle: String, _ haystack: String) -> Int? {
        if needle.isEmpty { return 0 }
        let n = Array(needle.lowercased())
        let h = Array(haystack.lowercased())
        guard n.count <= h.count else { return nil }

        var score = 0
        var ni = 0
        var lastMatch = -1

        for (hi, ch) in h.enumerated() {
            guard ni < n.count, ch == n[ni] else { continue }
            var bonus = 1
            if lastMatch == hi - 1 { bonus += 6 }                       // consecutive
            if hi == 0 { bonus += 8 }                                    // start of string
            else if h[hi - 1] == "/" || h[hi - 1] == "-" ||
                    h[hi - 1] == "_" || h[hi - 1] == " " { bonus += 5 }  // word boundary
            score += bonus
            lastMatch = hi
            ni += 1
        }
        guard ni == n.count else { return nil }
        // Shorter targets are usually the ones you meant.
        return score * 100 - haystack.count
    }

    static func quickOpen(query: String, in urls: [URL], root: URL?, limit: Int = 60) -> [URL] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return Array(urls.prefix(limit))
        }
        let needle = query.replacingOccurrences(of: " ", with: "")

        var scored: [(URL, Int)] = []
        for url in urls {
            let name = url.lastPathComponent
            // Prefer a filename match; fall back to the path.
            let byName = fuzzyScore(needle, name)
            let relative = root.map { relativePath(url, to: $0) } ?? url.path
            let byPath = fuzzyScore(needle, relative)
            guard let best = [byName.map { $0 + 400 }, byPath].compactMap({ $0 }).max() else { continue }
            scored.append((url, best))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    static func relativePath(_ url: URL, to root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count).drop(while: { $0 == "/" }))
    }

    // MARK: Full-text search

    /// Scans the indexed files off the main thread. Cancellable, because the
    /// query changes on every keystroke.
    static func search(query: String,
                       in urls: [URL],
                       caseSensitive: Bool = false,
                       maxHits: Int = 300,
                       isCancelled: @escaping () -> Bool,
                       onProgress: @escaping ([SearchHit]) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { onProgress([]); return }

        DispatchQueue.global(qos: .userInitiated).async {
            var hits: [SearchHit] = []
            let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]

            for url in urls {
                if isCancelled() { return }
                guard hits.count < maxHits else { break }
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                guard content.range(of: trimmed, options: options) != nil else { continue }

                for (index, line) in content.components(separatedBy: "\n").enumerated() {
                    guard hits.count < maxHits else { break }
                    guard let range = line.range(of: trimmed, options: options) else { continue }
                    hits.append(SearchHit(
                        url: url,
                        line: index,
                        text: String(line.prefix(400)).trimmingCharacters(in: .whitespaces),
                        matchRange: range))
                }

                // Stream partial results so the list fills in as it goes.
                if hits.count % 25 == 0 {
                    let snapshot = hits
                    DispatchQueue.main.async { if !isCancelled() { onProgress(snapshot) } }
                }
            }

            let final = hits
            DispatchQueue.main.async { if !isCancelled() { onProgress(final) } }
        }
    }
}
