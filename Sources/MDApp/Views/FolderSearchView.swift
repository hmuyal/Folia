import SwiftUI

/// ⇧⌘F — full-text search across the open folder.
struct FolderSearchView: View {
    @ObservedObject var state: AppState
    let palette: Palette
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var searching = false
    @State private var caseSensitive = false
    @State private var generation = 0
    @FocusState private var focused: Bool

    /// Hits grouped by file, preserving the order files were scanned in.
    private var grouped: [(URL, [SearchHit])] {
        var order: [URL] = []
        var byFile: [URL: [SearchHit]] = [:]
        for hit in hits {
            if byFile[hit.url] == nil { order.append(hit.url) }
            byFile[hit.url, default: []].append(hit)
        }
        return order.map { ($0, byFile[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Tok.S.xs) {
                Image(systemName: "text.magnifyingglass").foregroundStyle(palette.textFaint)
                TextField("Find in folder…", text: $query)
                    .textFieldStyle(.plain)
                    .font(Tok.F.body(15))
                    .focused($focused)
                    .onChange(of: query) { _, _ in runSearch() }
                if searching { ProgressView().controlSize(.small) }
                Toggle("Aa", isOn: $caseSensitive)
                    .toggleStyle(.button)
                    .font(Tok.F.body(11, weight: .medium))
                    .help("Match case")
                    .onChange(of: caseSensitive) { _, _ in runSearch() }
            }
            .padding(.horizontal, Tok.S.md)
            .frame(height: 46)

            Divider().overlay(palette.hairline)

            if state.workspace == nil {
                message("Open a folder to search it.")
            } else if query.count < 2 {
                message("Type at least two characters.")
            } else if hits.isEmpty && !searching {
                message("No matches.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(grouped, id: \.0) { url, fileHits in
                            Section {
                                ForEach(fileHits) { hit in hitRow(hit) }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text").font(.system(size: 10))
                                    Text(state.workspace.map {
                                        SearchService.relativePath(url, to: $0.root)
                                    } ?? url.lastPathComponent)
                                        .font(Tok.F.body(11, weight: .medium))
                                    Text("\(fileHits.count)")
                                        .font(Tok.F.body(10))
                                        .foregroundStyle(palette.textFaint)
                                    Spacer()
                                }
                                .foregroundStyle(palette.textMuted)
                                .padding(.horizontal, Tok.S.sm)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(palette.card)
                            }
                        }
                    }
                }
                .frame(maxHeight: 400)

                HStack {
                    Text("\(hits.count) match\(hits.count == 1 ? "" : "es") in \(grouped.count) file\(grouped.count == 1 ? "" : "s")")
                    Spacer()
                }
                .font(Tok.F.body(11))
                .foregroundStyle(palette.textFaint)
                .padding(.horizontal, Tok.S.sm)
                .frame(height: 24)
                .background(palette.chrome)
            }
        }
        .frame(width: 620)
        .background(palette.chrome)
        .onAppear { focused = true }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    @ViewBuilder
    private func hitRow(_ hit: SearchHit) -> some View {
        Button {
            state.store.open(hit.url)
            // Let the document land before jumping to the line.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                state.bridge.scrollToLine(hit.line)
            }
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: Tok.S.xs) {
                Text("\(hit.line + 1)")
                    .font(Tok.F.mono(10))
                    .foregroundStyle(palette.textFaint)
                    .frame(width: 34, alignment: .trailing)
                Text(highlighted(hit))
                    .font(Tok.F.mono(11.5))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Tok.S.sm)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowStyle(palette: palette))
    }

    /// Bolds the matched substring inside the line preview.
    private func highlighted(_ hit: SearchHit) -> AttributedString {
        var attributed = AttributedString(hit.text)
        attributed.foregroundColor = palette.textBody
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        if let range = hit.text.range(of: query, options: options),
           let lower = AttributedString.Index(range.lowerBound, within: attributed),
           let upper = AttributedString.Index(range.upperBound, within: attributed) {
            attributed[lower..<upper].foregroundColor = palette.accent
            attributed[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
        }
        return attributed
    }

    @ViewBuilder
    private func message(_ text: String) -> some View {
        Text(text)
            .font(Tok.F.body(12))
            .foregroundStyle(palette.textFaint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Tok.S.lg)
    }

    private func runSearch() {
        generation += 1
        let mine = generation
        guard let workspace = state.workspace, query.count >= 2 else {
            hits = []; searching = false; return
        }
        searching = true
        SearchService.search(
            query: query,
            in: workspace.index,
            caseSensitive: caseSensitive,
            isCancelled: { mine != generation },
            onProgress: { found in
                guard mine == generation else { return }
                hits = found
                searching = false
            })
    }
}
