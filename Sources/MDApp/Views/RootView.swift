import SwiftUI

struct RootView: View {
    @ObservedObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme

    private var palette: Palette { Palette(isDark: state.isDark) }

    var body: some View {
        HStack(spacing: 0) {
            if state.prefs.showSidebar {
                SidebarView(state: state, palette: palette)
                    .frame(width: 232)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Rectangle().fill(palette.hairline).frame(width: 1)
            }

            VStack(spacing: 0) {
                if state.store.documents.count > 1 || state.prefs.showSidebar {
                    TabBarView(store: state.store, palette: palette)
                }

                ZStack {
                    palette.canvas
                    ContentWebView(bridge: state.bridge)
                    if state.store.documents.isEmpty { EmptyStateView(state: state, palette: palette) }
                }

                if let doc = state.store.active, doc.externalChange != nil {
                    ExternalChangeBar(doc: doc, palette: palette)
                }

                StatusBar(state: state, palette: palette)
            }
        }
        .background(palette.canvas)
        .preferredColorScheme(state.prefs.appearance == .system ? nil
                              : (state.isDark ? .dark : .light))
        .animation(.easeOut(duration: 0.16), value: state.prefs.showSidebar)
        .sheet(isPresented: $state.showQuickOpen) {
            QuickOpenView(state: state, palette: palette)
        }
        .sheet(isPresented: $state.showFolderSearch) {
            FolderSearchView(state: state, palette: palette)
        }
        .alert("Could not open file",
               isPresented: Binding(get: { state.store.lastError != nil },
                                    set: { if !$0 { state.store.lastError = nil } })) {
            Button("OK", role: .cancel) { state.store.lastError = nil }
        } message: {
            Text(state.store.lastError ?? "")
        }
    }
}

/// Shown when no document is open — the WebView sits behind it, empty.
private struct EmptyStateView: View {
    @ObservedObject var state: AppState
    let palette: Palette

    var body: some View {
        VStack(spacing: Tok.S.md) {
            SpikeMark()
                .fill(palette.accent)
                .frame(width: 34, height: 34)
                .opacity(0.85)

            Text("MDApp")
                .font(Tok.F.display(32))
                .foregroundStyle(palette.text)

            Text("Open a Markdown file, or start writing.")
                .font(Tok.F.body(14))
                .foregroundStyle(palette.textMuted)

            HStack(spacing: Tok.S.xs) {
                CoralButton("Open…") { state.openPanel() }
                SecondaryButton("New Document", palette: palette) { state.store.newDocument() }
            }
            .padding(.top, Tok.S.xs)

            if !RecentList.files.urls.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RECENT")
                        .font(Tok.F.body(11, weight: .medium))
                        .tracking(1.5)
                        .foregroundStyle(palette.textFaint)
                        .padding(.bottom, 4)
                    ForEach(RecentList.files.urls.prefix(5), id: \.self) { url in
                        Button {
                            state.store.open(url)
                        } label: {
                            Text(url.lastPathComponent)
                                .font(Tok.F.body(12))
                                .foregroundStyle(palette.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, Tok.S.lg)
            }
        }
        .padding(Tok.S.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.canvas)
    }
}

/// The Anthropic four-spoke mark, used as the app's own glyph.
struct SpikeMark: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = rect.midX, cy = rect.midY
        var p = Path()
        p.move(to: CGPoint(x: cx, y: rect.minY))
        p.addCurve(to: CGPoint(x: rect.maxX, y: cy),
                   control1: CGPoint(x: cx + w * 0.035, y: cy - h * 0.20),
                   control2: CGPoint(x: cx + w * 0.20,  y: cy - h * 0.035))
        p.addCurve(to: CGPoint(x: cx, y: rect.maxY),
                   control1: CGPoint(x: cx + w * 0.20,  y: cy + h * 0.035),
                   control2: CGPoint(x: cx + w * 0.035, y: cy + h * 0.20))
        p.addCurve(to: CGPoint(x: rect.minX, y: cy),
                   control1: CGPoint(x: cx - w * 0.035, y: cy + h * 0.20),
                   control2: CGPoint(x: cx - w * 0.20,  y: cy + h * 0.035))
        p.addCurve(to: CGPoint(x: cx, y: rect.minY),
                   control1: CGPoint(x: cx - w * 0.20,  y: cy - h * 0.035),
                   control2: CGPoint(x: cx - w * 0.035, y: cy - h * 0.20))
        p.closeSubpath()
        return p
    }
}

struct CoralButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Tok.F.button)
                .foregroundStyle(Tok.onPrimary)
                .padding(.horizontal, 20)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: Tok.R.md).fill(Tok.primary))
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    let title: String
    let palette: Palette
    let action: () -> Void
    init(_ title: String, palette: Palette, action: @escaping () -> Void) {
        self.title = title; self.palette = palette; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Tok.F.button)
                .foregroundStyle(palette.text)
                .padding(.horizontal, 20)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: Tok.R.md)
                        .stroke(palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Bar shown when the file changed on disk while it had unsaved edits.
struct ExternalChangeBar: View {
    @ObservedObject var doc: Document
    let palette: Palette

    var body: some View {
        HStack(spacing: Tok.S.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Tok.accentAmber)
            Text(doc.externalChange?.kind == .deleted
                 ? "This file was deleted on disk."
                 : "This file changed on disk while you were editing it.")
                .font(Tok.F.body(12))
                .foregroundStyle(palette.text)
            Spacer()
            if doc.externalChange?.kind == .modified {
                Button("Reload") { doc.acceptExternalChange() }
                    .font(Tok.F.body(12, weight: .medium))
            }
            Button("Keep Mine") { doc.dismissExternalChange() }
                .font(Tok.F.body(12))
        }
        .padding(.horizontal, Tok.S.sm)
        .frame(height: 30)
        .background(Tok.accentAmber.opacity(0.14))
        .overlay(alignment: .top) { Rectangle().fill(Tok.accentAmber.opacity(0.4)).frame(height: 1) }
    }
}
