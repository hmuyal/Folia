import SwiftUI

/// ⇧⌘P — fuzzy-match a file in the open folder and jump to it.
struct QuickOpenView: View {
    @ObservedObject var state: AppState
    let palette: Palette
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var results: [URL] {
        SearchService.quickOpen(
            query: query,
            in: state.workspace?.index ?? recentFallback,
            root: state.workspace?.root)
    }

    private var recentFallback: [URL] { RecentList.files.urls }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Tok.S.xs) {
                Image(systemName: "magnifyingglass").foregroundStyle(palette.textFaint)
                TextField("Go to file…", text: $query)
                    .textFieldStyle(.plain)
                    .font(Tok.F.body(15))
                    .focused($focused)
                    .onSubmit(openSelected)
                    .onChange(of: query) { _, _ in selection = 0 }
            }
            .padding(.horizontal, Tok.S.md)
            .frame(height: 46)

            Divider().overlay(palette.hairline)

            if results.isEmpty {
                Text(state.workspace == nil
                     ? "Open a folder to search it."
                     : "No matching files.")
                    .font(Tok.F.body(12))
                    .foregroundStyle(palette.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Tok.S.lg)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element) { index, url in
                                row(url, index: index)
                                    .id(index)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 340)
                    .onChange(of: selection) { _, new in
                        withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(new, anchor: .center) }
                    }
                }
            }
        }
        .frame(width: 540)
        .background(palette.chrome)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow)   { move(-1); return .handled }
        .onKeyPress(.escape)    { dismiss(); return .handled }
    }

    @ViewBuilder
    private func row(_ url: URL, index: Int) -> some View {
        let isSelected = index == selection
        let relative = state.workspace.map { SearchService.relativePath(url, to: $0.root) }
            ?? url.deletingLastPathComponent().lastPathComponent

        Button { open(url) } label: {
            HStack(spacing: Tok.S.xs) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? palette.accent : palette.textFaint)
                Text(url.lastPathComponent)
                    .font(Tok.F.body(13, weight: .medium))
                    .foregroundStyle(palette.text)
                Text(relative)
                    .font(Tok.F.body(11))
                    .foregroundStyle(palette.textFaint)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Tok.S.sm)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Tok.R.sm)
                    .fill(isSelected ? palette.accent.opacity(0.14) : .clear)
                    .padding(.horizontal, 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + delta, 0), results.count - 1)
    }

    private func openSelected() {
        guard results.indices.contains(selection) else { return }
        open(results[selection])
    }

    private func open(_ url: URL) {
        state.store.open(url)
        dismiss()
    }
}
