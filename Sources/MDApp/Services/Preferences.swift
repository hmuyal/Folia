import SwiftUI
import Combine

/// Renderer options. Field names match `web/src/render/options.js` exactly —
/// this struct is JSON-encoded straight into the WebView, and
/// `Tools/check-options-parity.sh` fails the build if the two drift apart.
struct RenderOptions: Codable, Equatable {
    // cmark-gfm equivalents
    var table            = true
    var strikethrough    = true
    var taskList         = true
    var autolink         = true
    var footnotes        = true
    var allowHTML        = true
    var sanitizeHTML     = true

    // QLMarkdown's custom extensions
    var highlight        = true
    var subscriptText    = true
    var superscriptText  = true
    var inserted         = true
    var emoji            = true
    var headsAnchors     = true
    var yamlHeader       = true
    var inlineImages     = true
    var math             = true
    var mermaid          = true
    var syntaxHighlight  = true

    // extras
    var deflist          = true
    var abbr             = true
    var attrs            = true
    var containers       = true
    var alerts           = true
    var wikiLinks        = false

    // display
    var lineNumbers      = true
    var wrapCode         = false
    var smartQuotes      = true
    var hardBreak        = false
    var noSoftBreak      = false
    var renderAsSource   = false
    var tocDepth         = 3

    // security
    var allowRemoteContent = false

    // `subscript` and `superscript` are Swift keywords.
    enum CodingKeys: String, CodingKey {
        case table, strikethrough, taskList, autolink, footnotes
        case allowHTML, sanitizeHTML, highlight
        case subscriptText = "subscript"
        case superscriptText = "superscript"
        case inserted, emoji, headsAnchors, yamlHeader, inlineImages
        case math, mermaid, syntaxHighlight
        case deflist, abbr, attrs, containers, alerts, wikiLinks
        case lineNumbers, wrapCode, smartQuotes, hardBreak, noSoftBreak
        case renderAsSource, tocDepth, allowRemoteContent
    }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum ViewMode: String, Codable, CaseIterable, Identifiable {
    case split, reader, source
    var id: String { rawValue }
    var label: String {
        switch self {
        case .split:  return "Split"
        case .reader: return "Reader"
        case .source: return "Source"
        }
    }
    var symbol: String {
        switch self {
        case .split:  return "rectangle.split.2x1"
        case .reader: return "doc.richtext"
        case .source: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// Everything persisted between launches.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @Published var render = RenderOptions()          { didSet { save() } }
    @Published var appearance: AppearanceMode = .system { didSet { save() } }
    @Published var viewMode: ViewMode = .split       { didSet { save() } }

    @Published var editorFontSize: Double = 14       { didSet { save() } }
    @Published var previewFontSize: Double = 16      { didSet { save() } }
    @Published var measure: Double = 760             { didSet { save() } }
    @Published var tabWidth: Int = 4                 { didSet { save() } }
    @Published var showLineNumbersInEditor = true    { didSet { save() } }
    @Published var wrapEditorLines = true            { didSet { save() } }
    @Published var typewriterMode = false            { didSet { save() } }
    @Published var focusMode = false                 { didSet { save() } }
    @Published var vimMode = false                   { didSet { save() } }
    @Published var autosave = true                   { didSet { save() } }
    @Published var scrollSync = true                 { didSet { save() } }
    @Published var showSidebar = true                { didSet { save() } }
    @Published var splitRatio: Double = 0.5          { didSet { save() } }
    @Published var customCSS: String = ""            { didSet { save() } }

    private var loading = false
    private let key = "preferences.v1"

    private init() { load() }

    /// The options blob handed to the WebView on every render.
    var webOptions: [String: Any] {
        var dict = (try? JSONSerialization.jsonObject(
            with: JSONEncoder().encode(render))) as? [String: Any] ?? [:]
        dict["previewFontSize"] = previewFontSize
        dict["measure"] = measure
        return dict
    }

    private struct Stored: Codable {
        var render: RenderOptions
        var appearance: AppearanceMode
        var viewMode: ViewMode
        var editorFontSize: Double
        var previewFontSize: Double
        var measure: Double
        var tabWidth: Int
        var showLineNumbersInEditor: Bool
        var wrapEditorLines: Bool
        var typewriterMode: Bool
        var focusMode: Bool
        var vimMode: Bool
        var autosave: Bool
        var scrollSync: Bool
        var showSidebar: Bool
        var splitRatio: Double
        var customCSS: String
    }

    private func save() {
        guard !loading else { return }
        let stored = Stored(
            render: render, appearance: appearance, viewMode: viewMode,
            editorFontSize: editorFontSize, previewFontSize: previewFontSize,
            measure: measure, tabWidth: tabWidth,
            showLineNumbersInEditor: showLineNumbersInEditor,
            wrapEditorLines: wrapEditorLines, typewriterMode: typewriterMode,
            focusMode: focusMode, vimMode: vimMode, autosave: autosave,
            scrollSync: scrollSync, showSidebar: showSidebar, splitRatio: splitRatio, customCSS: customCSS)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        loading = true
        render = s.render; appearance = s.appearance; viewMode = s.viewMode
        editorFontSize = s.editorFontSize; previewFontSize = s.previewFontSize
        measure = s.measure; tabWidth = s.tabWidth
        showLineNumbersInEditor = s.showLineNumbersInEditor
        wrapEditorLines = s.wrapEditorLines; typewriterMode = s.typewriterMode
        focusMode = s.focusMode; vimMode = s.vimMode; autosave = s.autosave
        scrollSync = s.scrollSync
        showSidebar = s.showSidebar; splitRatio = s.splitRatio; customCSS = s.customCSS
        loading = false
    }

    func resetRenderOptions() { render = RenderOptions() }
}
