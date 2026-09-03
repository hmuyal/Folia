import SwiftUI

struct StatusBar: View {
    @ObservedObject var state: AppState
    let palette: Palette

    var body: some View {
        HStack(spacing: Tok.S.md) {
            if let doc = state.store.active {
                Text(doc.url?.path.replacingOccurrences(
                        of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
                     ?? "Untitled")
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(palette.textFaint)
                if doc.isDirty {
                    Text("Edited").foregroundStyle(palette.accent)
                }
            }

            Spacer(minLength: Tok.S.md)

            if let message = state.statusMessage {
                Text(message).foregroundStyle(palette.accent).lineLimit(1)
            }

            Text("\(state.words) words")
            Text("\(state.characters) chars")
            if state.readingMinutes > 0 {
                Text("\(state.readingMinutes) min read")
            }

            ZoomControl(state: state)

            Picker("", selection: Binding(
                get: { state.prefs.viewMode },
                set: { state.prefs.viewMode = $0 })) {
                ForEach(ViewMode.allCases) { mode in
                    Image(systemName: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 108)
        }
        .font(Tok.F.body(11))
        .foregroundStyle(palette.textMuted)
        .padding(.horizontal, Tok.S.sm)
        .frame(height: 26)
        .background(palette.chrome)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.hairline).frame(height: 1)
        }
    }
}

/// Preview zoom, without a trip to the View menu. Mirrors Actual Size / Zoom
/// In / Zoom Out exactly — same range, same reset point.
private struct ZoomControl: View {
    @ObservedObject var state: AppState

    private var percent: Int {
        Int(round(state.prefs.previewFontSize / AppState.defaultPreviewFontSize * 100))
    }

    var body: some View {
        HStack(spacing: 2) {
            Button(action: state.zoomOut) {
                Image(systemName: "minus")
            }
            .disabled(state.prefs.previewFontSize <= AppState.minPreviewFontSize)
            .help("Zoom Out (⌥⌘-)")

            Button(action: state.resetZoom) {
                Text("\(percent)%").frame(minWidth: 34)
            }
            .help("Actual Size (⌥⌘0)")

            Button(action: state.zoomIn) {
                Image(systemName: "plus")
            }
            .disabled(state.prefs.previewFontSize >= AppState.maxPreviewFontSize)
            .help("Zoom In (⌥⌘+)")
        }
        .buttonStyle(.plain)
    }
}
