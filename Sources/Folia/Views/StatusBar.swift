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
