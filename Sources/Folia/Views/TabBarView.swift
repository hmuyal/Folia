import SwiftUI

struct TabBarView: View {
    @ObservedObject var store: DocumentStore
    let palette: Palette

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(store.documents) { doc in
                        TabItem(doc: doc,
                                isActive: doc.id == store.activeID,
                                palette: palette,
                                onSelect: { store.activeID = doc.id },
                                onClose:  { _ = store.close(doc) })
                            .id(doc.id)
                    }
                    Button(action: { store.newDocument() }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.textMuted)
                    .help("New document (⌘N)")
                    Spacer(minLength: 0)
                }
            }
            .onChange(of: store.activeID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .frame(height: 34)
        .background(palette.chrome)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.hairline).frame(height: 1)
        }
    }
}

private struct TabItem: View {
    @ObservedObject var doc: Document
    let isActive: Bool
    let palette: Palette
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            // The dot doubles as the close target on hover — the pattern most
            // Mac editors use, and it keeps the tab narrow.
            Button(action: onClose) {
                ZStack {
                    if hovering {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    } else if doc.isDirty {
                        Circle().frame(width: 6, height: 6)
                    }
                }
                .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(doc.isDirty && !hovering ? palette.accent : palette.textMuted)
            .opacity(hovering || doc.isDirty ? 1 : 0)

            Text(doc.displayName)
                .font(Tok.F.body(12, weight: isActive ? .medium : .regular))
                .lineLimit(1)
                .foregroundStyle(isActive ? palette.text : palette.textMuted)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .frame(minWidth: 92, maxWidth: 200)
        .background(isActive ? palette.canvas : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isActive ? palette.accent : .clear)
                .frame(height: 2)
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(palette.hairlineSoft).frame(width: 1).padding(.vertical, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .help(doc.url?.path ?? "Untitled")
        .contextMenu {
            Button("Close") { onClose() }
            if let url = doc.url {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                }
            }
        }
    }
}
