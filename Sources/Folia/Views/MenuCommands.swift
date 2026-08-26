import SwiftUI

/// The menu bar. Every command routes through AppState so the same action is
/// reachable from the menu, a shortcut, and the toolbar.
struct MenuCommands: Commands {
    @ObservedObject var state: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") { state.store.newDocument() }
                .keyboardShortcut("n")
            Button("Open…") { state.openPanel() }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(RecentList.files.urls, id: \.self) { url in
                    Button(url.lastPathComponent) { state.store.open(url) }
                }
                if !RecentList.files.urls.isEmpty {
                    Divider()
                    Button("Clear Menu") { RecentList.files.clear() }
                }
            }

            Divider()

            Button("Open Folder…") { state.openFolderPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Menu("Open Recent Folder") {
                ForEach(RecentList.folders.urls, id: \.self) { url in
                    Button(url.lastPathComponent) { state.openFolder(url) }
                }
                if !RecentList.folders.urls.isEmpty {
                    Divider()
                    Button("Clear Menu") { RecentList.folders.clear() }
                }
            }
            .disabled(RecentList.folders.urls.isEmpty)
            Button(state.workspace.map { "Close Folder “\($0.name)”" } ?? "Close Folder") {
                state.closeFolder()
            }
            .disabled(state.workspace == nil)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                if let doc = state.store.active { state.store.saveWithPrompt(doc) }
            }
            .keyboardShortcut("s")
            .disabled(state.store.active == nil)

            Button("Save As…") {
                if let doc = state.store.active { state.store.saveAs(doc) }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(state.store.active == nil)

            Button("Revert to Saved") {
                try? state.store.active?.reloadFromDisk()
            }
            .disabled(state.store.active?.url == nil)

            Divider()

            Button("Close Tab") {
                if let doc = state.store.active { _ = state.store.close(doc) }
            }
            .keyboardShortcut("w")
            .disabled(state.store.active == nil)

            Divider()

            Button("Export as HTML…") { state.exportHTML() }
                .disabled(state.store.active == nil)
            Button("Export as PDF…") { state.exportPDF() }
                .disabled(state.store.active == nil)
            Button("Export as TextBundle…") { state.exportTextBundle() }
                .disabled(state.store.active == nil)
            Button("Copy as Rich Text") { state.copyAsRichText() }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
                .disabled(state.store.active == nil)
            Button("Copy Rendered HTML") { state.copyRenderedHTML() }
                .disabled(state.store.active == nil)

            Divider()

            Button("Reveal in Finder") { state.revealInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(state.store.active?.url == nil)
        }

        CommandGroup(replacing: .printItem) {
            Button("Print…") { state.printDocument() }
                .keyboardShortcut("p")
                .disabled(state.store.active == nil)
        }

        CommandMenu("Format") {
            Button("Bold")   { state.bridge.command("bold")   }.keyboardShortcut("b")
            Button("Italic") { state.bridge.command("italic") }.keyboardShortcut("i")
            Button("Strikethrough") { state.bridge.command("strike") }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Inline Code") { state.bridge.command("code") }
                .keyboardShortcut("e", modifiers: [.command])
            Button("Link…") { state.bridge.command("link") }.keyboardShortcut("k")
            Divider()
            ForEach(1...6, id: \.self) { level in
                Button("Heading \(level)") { state.bridge.command("heading\(level)") }
                    .keyboardShortcut(KeyEquivalent(Character("\(level)")), modifiers: .command)
            }
            Button("Body Text") { state.bridge.command("heading0") }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            Button("Bulleted List") { state.bridge.command("bulletList") }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Numbered List") { state.bridge.command("orderedList") }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Button("Task List") { state.bridge.command("taskList") }
            Button("Blockquote") { state.bridge.command("quote") }
                .keyboardShortcut("'", modifiers: [.command, .shift])
            Button("Code Block") { state.bridge.command("codeBlock") }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Table") { state.bridge.command("table") }
            Button("Horizontal Rule") { state.bridge.command("hr") }
        }

        CommandGroup(after: .toolbar) {
            Picker("View Mode", selection: Binding(
                get: { state.prefs.viewMode }, set: { state.prefs.viewMode = $0 })) {
                ForEach(ViewMode.allCases) { Text($0.label).tag($0) }
            }
            Button("Toggle Sidebar") { state.prefs.showSidebar.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .control])
            Button("Toggle Source / Reader") {
                state.prefs.viewMode = state.prefs.viewMode == .reader ? .split : .reader
            }
            .keyboardShortcut("\\", modifiers: .command)

            Divider()

            Picker("Appearance", selection: Binding(
                get: { state.prefs.appearance }, set: { state.prefs.appearance = $0 })) {
                ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
            }

            Button("Actual Size")  { state.prefs.previewFontSize = 16 }
                .keyboardShortcut("0", modifiers: [.command, .option])
            Button("Zoom In")  { state.prefs.previewFontSize = min(28, state.prefs.previewFontSize + 1) }
                .keyboardShortcut("+", modifiers: [.command, .option])
            Button("Zoom Out") { state.prefs.previewFontSize = max(11, state.prefs.previewFontSize - 1) }
                .keyboardShortcut("-", modifiers: [.command, .option])
        }

        CommandMenu("Navigate") {
            Button("Quick Open…") { state.showQuickOpen = true }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Find in Folder…") { state.showFolderSearch = true }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Divider()
            Button("Find…") { state.bridge.command("find") }
                .keyboardShortcut("f")
            Button("Find and Replace…") { state.bridge.command("replace") }
                .keyboardShortcut("f", modifiers: [.command, .option])
            Divider()
            Button("Next Tab")     { state.store.selectTab(offset: 1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Tab") { state.store.selectTab(offset: -1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
        }
    }
}
