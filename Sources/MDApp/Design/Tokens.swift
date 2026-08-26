import SwiftUI

/// The design system's tokens, mirrored from `web/styles/tokens.css` for
/// native chrome. The two must stay in step: the WebView renders the
/// document, AppKit renders everything around it, and a mismatch shows as a
/// seam.
enum Tok {

    // MARK: Brand & accent
    static let primary          = Color(hex: 0xCC785C)
    static let primaryActive    = Color(hex: 0xA9583E)
    static let primaryDisabled  = Color(hex: 0xE6DFD8)
    static let accentTeal       = Color(hex: 0x5DB8A6)
    static let accentAmber      = Color(hex: 0xE8A55A)

    // MARK: Surfaces
    static let canvas             = Color(hex: 0xFAF9F5)
    static let surfaceSoft        = Color(hex: 0xF5F0E8)
    static let surfaceCard        = Color(hex: 0xEFE9DE)
    static let surfaceCreamStrong = Color(hex: 0xE8E0D2)
    static let surfaceDark        = Color(hex: 0x181715)
    static let surfaceDarkElev    = Color(hex: 0x252320)
    static let surfaceDarkSoft    = Color(hex: 0x1F1E1B)
    static let hairline           = Color(hex: 0xE6DFD8)
    static let hairlineSoft       = Color(hex: 0xEBE6DF)

    // MARK: Text
    static let ink        = Color(hex: 0x141413)
    static let bodyStrong = Color(hex: 0x252523)
    static let body       = Color(hex: 0x3D3D3A)
    static let muted      = Color(hex: 0x6C6A64)
    static let mutedSoft  = Color(hex: 0x8E8B82)
    static let onPrimary  = Color(hex: 0xFFFFFF)
    static let onDark     = Color(hex: 0xFAF9F5)
    static let onDarkSoft = Color(hex: 0xA09D96)

    // MARK: Semantic
    static let success = Color(hex: 0x5DB872)
    static let warning = Color(hex: 0xD4A017)
    static let error   = Color(hex: 0xC64545)

    // MARK: Radius
    enum R {
        static let xs: CGFloat = 4, sm: CGFloat = 6, md: CGFloat = 8
        static let lg: CGFloat = 12, xl: CGFloat = 16, pill: CGFloat = 9999
    }

    // MARK: Spacing — base unit 4
    enum S {
        static let xxs: CGFloat = 4,  xs: CGFloat = 8,  sm: CGFloat = 12
        static let md: CGFloat = 16,  lg: CGFloat = 24, xl: CGFloat = 32
        static let xxl: CGFloat = 48, section: CGFloat = 96
    }

    // MARK: Type
    /// Registered from the bundle at launch by `FontRegistrar`; falls back to
    /// the system faces if registration fails.
    enum F {
        static let bodyName    = "Inter"
        static let displayName = "EB Garamond"
        static let monoName    = "JetBrains Mono"

        static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            FontRegistrar.available(bodyName)
                ? .custom(bodyName, size: size).weight(weight)
                : .system(size: size, weight: weight)
        }
        static func display(_ size: CGFloat) -> Font {
            FontRegistrar.available(displayName)
                ? .custom(displayName, size: size)
                : .system(size: size, design: .serif)
        }
        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            FontRegistrar.available(monoName)
                ? .custom(monoName, size: size).weight(weight)
                : .system(size: size, weight: weight, design: .monospaced)
        }

        // Named roles used throughout the app's native chrome
        static var navLink: Font { body(14, weight: .medium) }
        static var button:  Font { body(14, weight: .medium) }
        static var bodyMD:  Font { body(16) }
        static var bodySM:  Font { body(14) }
        static var caption: Font { body(13, weight: .medium) }
        static var titleSM: Font { body(16, weight: .medium) }
        static var titleMD: Font { body(18, weight: .medium) }
    }
}

/// Palette that follows the active appearance, so chrome and document agree.
struct Palette {
    let isDark: Bool

    var canvas:      Color { isDark ? Tok.surfaceDark      : Tok.canvas }
    var chrome:      Color { isDark ? Color(hex: 0x1C1B19) : Tok.canvas }
    var sidebar:     Color { isDark ? Color(hex: 0x141312) : Tok.surfaceSoft }
    var card:        Color { isDark ? Tok.surfaceDarkElev  : Tok.surfaceCard }
    var raised:      Color { isDark ? Tok.surfaceDarkElev  : Color.white.opacity(0.6) }
    var text:        Color { isDark ? Tok.onDark           : Tok.ink }
    var textBody:    Color { isDark ? Color(hex: 0xD4D0C8) : Tok.body }
    var textMuted:   Color { isDark ? Tok.onDarkSoft       : Tok.muted }
    var textFaint:   Color { isDark ? Color(hex: 0x857F76) : Tok.mutedSoft }
    var hairline:    Color { isDark ? Color.white.opacity(0.10) : Tok.hairline }
    var hairlineSoft:Color { isDark ? Color.white.opacity(0.06) : Tok.hairlineSoft }
    var accent:      Color { isDark ? Color(hex: 0xD98A6D) : Tok.primary }
    var selection:   Color { accent.opacity(isDark ? 0.26 : 0.18) }

    static func forScheme(_ scheme: ColorScheme) -> Palette { Palette(isDark: scheme == .dark) }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >>  8) & 0xFF) / 255,
                  blue:  Double( hex        & 0xFF) / 255,
                  opacity: alpha)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green:   CGFloat((hex >>  8) & 0xFF) / 255,
                  blue:    CGFloat( hex        & 0xFF) / 255,
                  alpha:   alpha)
    }
}
