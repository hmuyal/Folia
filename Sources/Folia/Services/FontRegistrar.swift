import AppKit
import CoreText

/// Registers the bundled woff2/otf faces with CoreText so native chrome can use
/// the same typefaces as the document. Fonts live in Contents/Resources/Fonts.
enum FontRegistrar {
    private static var registered = Set<String>()
    private static var checked = false

    static func registerBundledFonts() {
        guard !checked else { return }
        checked = true

        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts", isDirectory: true),
              let items = try? FileManager.default.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: nil)
        else { return }

        // CoreText cannot load woff2; the build copies .otf/.ttf alongside for
        // native use while the WebView consumes the woff2 files.
        let loadable = items.filter { ["otf", "ttf", "ttc"].contains($0.pathExtension.lowercased()) }
        guard !loadable.isEmpty else { return }

        CTFontManagerRegisterFontURLs(loadable as CFArray, .process, true) { _, _ in true }

        for family in NSFontManager.shared.availableFontFamilies {
            registered.insert(family)
        }
    }

    /// True when a family is usable, so callers can fall back to system faces.
    static func available(_ family: String) -> Bool {
        registerBundledFonts()
        if registered.contains(family) { return true }
        return NSFont(name: family, size: 12) != nil
    }
}
