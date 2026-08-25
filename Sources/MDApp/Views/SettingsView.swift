import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        TabView {
            GeneralSettings(state: state)
                .tabItem { Label("General", systemImage: "gearshape") }
            MarkdownSettings(prefs: state.prefs)
                .tabItem { Label("Markdown", systemImage: "text.badge.checkmark") }
            PreviewSettings(prefs: state.prefs)
                .tabItem { Label("Preview", systemImage: "doc.richtext") }
            EditorSettings(prefs: state.prefs)
                .tabItem { Label("Editor", systemImage: "square.and.pencil") }
            SecuritySettings(prefs: state.prefs)
                .tabItem { Label("Security", systemImage: "lock.shield") }
        }
        .frame(width: 520, height: 430)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var state: AppState
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        Form {
            Picker("Appearance", selection: $prefs.appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
            }
            Picker("Open documents in", selection: $prefs.viewMode) {
                ForEach(ViewMode.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Save automatically", isOn: $prefs.autosave)
            Toggle("Synchronise editor and preview scrolling", isOn: $prefs.scrollSync)
            Toggle("Show sidebar", isOn: $prefs.showSidebar)

            Section {
                HStack {
                    Text("Default Markdown application")
                    Spacer()
                    Button("Make MDApp the Default") { makeDefaultHandler() }
                }
                Text("Applies to .md, .markdown, .mdown, .mkd, .rmd, .qmd, .mdx and .mdc files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func makeDefaultHandler() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        for uti in ["net.daringfireball.markdown", "com.hmuyal.mdapp.markdown-variant"] {
            LSSetDefaultRoleHandlerForContentType(uti as CFString, .all, bundleID as CFString)
        }
        state.statusMessage = "MDApp is now the default Markdown app"
        state.clearStatusSoon()
    }
}

// MARK: - Markdown extensions

private struct MarkdownSettings: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tok.S.lg) {
                group("Core syntax") {
                    row("Tables", "GitHub pipe-table syntax", $prefs.render.table)
                    row("Strikethrough", "~~text~~", $prefs.render.strikethrough)
                    row("Task lists", "- [ ] and - [x] checkboxes", $prefs.render.taskList)
                    row("Autolink", "Turn bare URLs and emails into links", $prefs.render.autolink)
                    row("Footnotes", "text[^1] with [^1]: definitions", $prefs.render.footnotes)
                }
                group("Extended inline") {
                    row("Highlight", "==marked text==", $prefs.render.highlight)
                    row("Subscript", "H~2~O", $prefs.render.subscriptText)
                    row("Superscript", "E = mc^2^", $prefs.render.superscriptText)
                    row("Inserted", "++underlined++", $prefs.render.inserted)
                    row("Emoji", "Convert :shortcodes: to glyphs", $prefs.render.emoji)
                    row("Definition lists", "Term followed by : definition", $prefs.render.deflist)
                    row("Abbreviations", "*[HTML]: HyperText Markup Language", $prefs.render.abbr)
                }
                group("Blocks") {
                    row("GitHub alerts", "> [!NOTE], [!TIP], [!WARNING]…", $prefs.render.alerts)
                    row("Containers", ":::note fenced blocks", $prefs.render.containers)
                    row("Attributes", "{.class #id} on elements", $prefs.render.attrs)
                    row("Wiki links", "[[Page name]] links between files", $prefs.render.wikiLinks)
                }
                group("Document structure") {
                    row("Heading anchors", "A linkable #slug for every heading", $prefs.render.headsAnchors)
                    row("YAML front matter", "Render --- metadata --- as a table", $prefs.render.yamlHeader)
                }
                HStack {
                    Spacer()
                    Button("Restore Defaults") { prefs.resetRenderOptions() }
                }
            }
            .padding(Tok.S.lg)
        }
    }

    @ViewBuilder
    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Tok.S.xs) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder
    private func row(_ title: String, _ detail: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

private struct PreviewSettings: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section("Rich content") {
                Toggle("Math with KaTeX", isOn: $prefs.render.math)
                Toggle("Mermaid diagrams", isOn: $prefs.render.mermaid)
                Toggle("Syntax highlighting", isOn: $prefs.render.syntaxHighlight)
                Toggle("Line numbers in code blocks", isOn: $prefs.render.lineNumbers)
                Toggle("Wrap long code lines", isOn: $prefs.render.wrapCode)
                Toggle("Load local images", isOn: $prefs.render.inlineImages)
            }
            Section("Typography") {
                Toggle("Smart quotes and dashes", isOn: $prefs.render.smartQuotes)
                Toggle("Treat every newline as a line break", isOn: $prefs.render.hardBreak)
                Toggle("Collapse newlines into spaces", isOn: $prefs.render.noSoftBreak)
                Toggle("Render as source instead of formatting", isOn: $prefs.render.renderAsSource)
            }
            Section("Layout") {
                LabeledContent("Text size") {
                    HStack {
                        Slider(value: $prefs.previewFontSize, in: 12...24, step: 1)
                        Text("\(Int(prefs.previewFontSize)) pt").monospacedDigit().frame(width: 42)
                    }
                }
                LabeledContent("Reading width") {
                    HStack {
                        Slider(value: $prefs.measure, in: 560...1100, step: 20)
                        Text("\(Int(prefs.measure)) px").monospacedDigit().frame(width: 52)
                    }
                }
            }
            Section("Custom CSS") {
                TextEditor(text: $prefs.customCSS)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 80)
                Text("Applied on top of the built-in theme.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Editor

private struct EditorSettings: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section("Appearance") {
                LabeledContent("Font size") {
                    HStack {
                        Slider(value: $prefs.editorFontSize, in: 10...22, step: 1)
                        Text("\(Int(prefs.editorFontSize)) pt").monospacedDigit().frame(width: 42)
                    }
                }
                Toggle("Show line numbers", isOn: $prefs.showLineNumbersInEditor)
                Toggle("Wrap long lines", isOn: $prefs.wrapEditorLines)
            }
            Section("Behaviour") {
                Picker("Tab width", selection: $prefs.tabWidth) {
                    ForEach([2, 4, 8], id: \.self) { Text("\($0) spaces").tag($0) }
                }
                Toggle("Typewriter mode", isOn: $prefs.typewriterMode)
                Toggle("Focus mode", isOn: $prefs.focusMode)
                Toggle("Vim key bindings", isOn: $prefs.vimMode)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Security

private struct SecuritySettings: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section {
                Toggle("Allow HTML in documents", isOn: $prefs.render.allowHTML)
                Toggle("Sanitise HTML", isOn: $prefs.render.sanitizeHTML)
                    .disabled(!prefs.render.allowHTML)
            } header: {
                Text("HTML")
            } footer: {
                Text(prefs.render.allowHTML && !prefs.render.sanitizeHTML
                     ? "⚠︎ Unsanitised HTML is rendered exactly as written, including scripts. Only turn this off for documents you wrote yourself."
                     : "HTML is rendered but scripts, event handlers and unsafe URLs are stripped — the same approach GitHub takes.")
                    .font(.caption)
                    .foregroundStyle(prefs.render.allowHTML && !prefs.render.sanitizeHTML
                                     ? Color(nsColor: .systemRed) : .secondary)
            }

            Section {
                Toggle("Allow documents to load remote content", isOn: $prefs.render.allowRemoteContent)
            } header: {
                Text("Network")
            } footer: {
                Text("Off by default. Maths, diagrams, syntax highlighting and every font ship inside the app, so documents render fully offline. Turning this on lets a document fetch images from the internet, which reveals that you opened it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
