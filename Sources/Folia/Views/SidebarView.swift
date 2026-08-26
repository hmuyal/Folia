import SwiftUI

/// Folder tree + document outline. Both are optional; the sidebar hides itself
/// entirely when neither has anything to show.
struct SidebarView: View {
    @ObservedObject var state: AppState
    let palette: Palette

    @State private var section: Section = .files
    enum Section: String, CaseIterable { case files = "Files", outline = "Outline" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) {
                ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Tok.S.xs)
            .padding(.vertical, 6)

            Divider().overlay(palette.hairline)

            switch section {
            case .files:   fileTree
            case .outline: outlineList
            }
        }
        .background(palette.sidebar)
    }

    @ViewBuilder
    private var fileTree: some View {
        if let workspace = state.workspace {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(workspace.tree) { node in
                        FileRow(node: node, depth: 0, state: state, palette: palette)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 28)      // clear the pinned footer
            }
            .overlay(alignment: .bottom) {
                WorkspaceFooter(workspace: workspace, state: state, palette: palette)
            }
        } else {
            emptyState("No folder open",
                       detail: "Open a folder to browse its Markdown files.",
                       action: "Open Folder…") { state.openFolderPanel() }
        }
    }

    @ViewBuilder
    private var outlineList: some View {
        if state.outline.isEmpty {
            emptyState("No headings", detail: "Headings in the document appear here.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(state.outline) { item in
                        Button {
                            state.bridge.scrollToLine(item.line)
                        } label: {
                            Text(item.text.isEmpty ? "—" : item.text)
                                .font(Tok.F.body(item.level <= 2 ? 12 : 11.5,
                                                 weight: item.level == 1 ? .medium : .regular))
                                .lineLimit(1)
                                .foregroundStyle(item.level <= 2 ? palette.text : palette.textMuted)
                                .padding(.leading, CGFloat(item.level - 1) * 11)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 3)
                                .padding(.horizontal, Tok.S.xs)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(SidebarRowStyle(palette: palette))
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func emptyState(_ title: String, detail: String,
                            action: String? = nil,
                            perform: (() -> Void)? = nil) -> some View {
        VStack(spacing: Tok.S.xs) {
            Spacer()
            Text(title).font(Tok.F.body(12, weight: .medium)).foregroundStyle(palette.textMuted)
            Text(detail)
                .font(Tok.F.body(11))
                .foregroundStyle(palette.textFaint)
                .multilineTextAlignment(.center)
            if let action, let perform {
                Button(action, action: perform)
                    .buttonStyle(.plain)
                    .font(Tok.F.body(11, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .padding(.top, 2)
            }
            Spacer()
        }
        .padding(Tok.S.md)
        .frame(maxWidth: .infinity)
    }
}

private struct FileRow: View {
    @ObservedObject var node: FileNode
    let depth: Int
    @ObservedObject var state: AppState
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: activate) {
                HStack(spacing: 5) {
                    if node.isDirectory {
                        Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .frame(width: 9)
                            .foregroundStyle(palette.textFaint)
                    } else {
                        Spacer().frame(width: 9)
                    }
                    Image(systemName: node.isDirectory ? "folder" : "doc.text")
                        .font(.system(size: 10))
                        .foregroundStyle(node.isDirectory ? palette.textFaint : palette.accent.opacity(0.75))
                    Text(node.name)
                        .font(Tok.F.body(12))
                        .lineLimit(1)
                        .foregroundStyle(isOpen ? palette.text : palette.textBody)
                    Spacer(minLength: 0)
                }
                .padding(.leading, CGFloat(depth) * 12 + Tok.S.xs)
                .padding(.trailing, Tok.S.xs)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(SidebarRowStyle(palette: palette, selected: isOpen))

            if node.isDirectory, node.isExpanded, let children = node.children {
                ForEach(children) { child in
                    FileRow(node: child, depth: depth + 1, state: state, palette: palette)
                }
            }
        }
    }

    private var isOpen: Bool {
        state.store.active?.url?.standardizedFileURL == node.url.standardizedFileURL
    }

    private func activate() {
        if node.isDirectory {
            node.loadChildrenIfNeeded()
            withAnimation(.easeOut(duration: 0.12)) { node.isExpanded.toggle() }
        } else {
            state.store.open(node.url)
        }
    }
}

struct SidebarRowStyle: ButtonStyle {
    let palette: Palette
    var selected: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Tok.R.sm)
                    .fill(selected ? palette.accent.opacity(0.14)
                          : configuration.isPressed ? palette.hairline.opacity(0.6) : .clear)
                    .padding(.horizontal, 4)
            )
    }
}


/// The sidebar's footer doubles as the workspace control: it names the open
/// folder and is the one obvious place to switch or close it.
private struct WorkspaceFooter: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var state: AppState
    let palette: Palette

    /// Observed so the Recent Folders submenu stays current.
    @ObservedObject private var recentFolders = RecentList.folders
    @State private var hovering = false

    var body: some View {
        Menu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([workspace.root])
            }
            Button("Refresh") { workspace.refresh() }

            Divider()

            Button("Open Folder…") { state.openFolderPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])

            let others = recentFolders.urls.filter {
                $0.standardizedFileURL != workspace.root.standardizedFileURL
            }
            if !others.isEmpty {
                Menu("Recent Folders") {
                    ForEach(others, id: \.self) { url in
                        Button(url.lastPathComponent) { state.openFolder(url) }
                    }
                }
            }

            Divider()

            Button("Close Folder") { state.closeFolder() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                Text(workspace.name).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .opacity(hovering ? 1 : 0.45)
                Spacer(minLength: 0)
                if workspace.isIndexing {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("\(workspace.index.count)")
                }
            }
            .font(Tok.F.body(11))
            .foregroundStyle(hovering ? palette.text : palette.textFaint)
            .padding(.horizontal, Tok.S.xs)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .onHover { hovering = $0 }
        .help("\(workspace.root.path) — click to switch or close")
        .background(hovering ? palette.card : palette.sidebar)
        .overlay(alignment: .top) { Rectangle().fill(palette.hairlineSoft).frame(height: 1) }
    }
}
