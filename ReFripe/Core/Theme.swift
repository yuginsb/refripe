import SwiftUI
import UIKit

// MARK: - Design tokens (CONTRACT) — v4: light + dark, white base, orange & blue brand, DM Sans / Newsreader.
// Every colour is dynamic: it resolves for the current light/dark appearance (system, or the user's choice
// in Réglages › Apparence). Never use hex literals or Color.white/.black in features: use these tokens.

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
    /// A colour that follows the light/dark appearance.
    static func rf(_ light: UInt32, _ dark: UInt32, alpha: CGFloat = 1, darkAlpha: CGFloat? = nil) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha ?? alpha)
                : UIColor(hex: light, alpha: alpha)
        }
    }
}

/// Light / dark choice stored in Réglages › Apparence (and offered at sign-up).
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    static let storageKey = "appearanceMode"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "Système"
        case .light: "Clair"
        case .dark: "Sombre"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum RF {
    /// UIKit versions of the tokens (bars, appearance proxies).
    enum U {
        static let background = UIColor.rf(0xFFFFFF, 0x0F1013)
        static let surface = UIColor.rf(0xF4F5F7, 0x1B1C21)
        static let text = UIColor.rf(0x15161A, 0xF3F3F5)
        static let textDim = UIColor.rf(0x6A6E76, 0xA3A6AE)
        static let line = UIColor.rf(0x000000, 0xFFFFFF, alpha: 0.08, darkAlpha: 0.12)
        static let accent = UIColor.rf(0xCC4309, 0xE2621B)          // orange — primary actions (white text ≥ 4.5:1 in light)
        static let accentText = UIColor.rf(0xB33A07, 0xFF8F4D)      // orange for text on background
        static let brandOrange = UIColor.rf(0xF26419, 0xFF7A33)     // logo, highlights
        static let brandBlue = UIColor.rf(0x1F5FD6, 0x6EA0FF)       // logo, links, selection
        static let money = UIColor.rf(0x12805C, 0x3CC48F)
    }

    enum C {
        // Surfaces
        static let paper = Color(uiColor: U.background)          // screen background (white / near-black)
        static let paperDim = Color(uiColor: U.surface)           // fields, chips, secondary fills
        static let card = Color(uiColor: UIColor.rf(0xFFFFFF, 0x1B1C21))   // cards and grouped rows
        static let line = Color(uiColor: U.line)                  // hairlines
        static let scrim = Color(uiColor: UIColor.rf(0x000000, 0x000000, alpha: 0.40, darkAlpha: 0.60))

        // Text
        static let text = Color(uiColor: U.text)
        static let textDim = Color(uiColor: U.textDim)

        // Brand & actions
        static let accent = Color(uiColor: U.accent)
        static let accentText = Color(uiColor: U.accentText)
        static let onAccent = Color(uiColor: UIColor.rf(0xFFFFFF, 0xFFFFFF))
        static let brandOrange = Color(uiColor: U.brandOrange)
        static let brandBlue = Color(uiColor: U.brandBlue)
        static let link = Color(uiColor: U.brandBlue)
        /// Tinted background behind accent content (secondary buttons, selected chips).
        static let accentTint = Color(uiColor: UIColor.rf(0xCC4309, 0xE2621B, alpha: 0.10, darkAlpha: 0.20))
        static let blueTint = Color(uiColor: UIColor.rf(0x1F5FD6, 0x6EA0FF, alpha: 0.10, darkAlpha: 0.18))

        // Money / success
        static let money = Color(uiColor: U.money)
        static let moneyDeep = Color(uiColor: UIColor.rf(0x0E6A4C, 0x5AD3A2))
        static let moneyTint = Color(uiColor: UIColor.rf(0x12805C, 0x3CC48F, alpha: 0.10, darkAlpha: 0.16))

        static let marigold = Color(uiColor: UIColor.rf(0xF2A33D, 0xF5B556))   // rating stars

        // Inverse surface (selected chips, splash): dark on light mode, light on dark mode.
        static let ink0 = Color(uiColor: UIColor.rf(0x15161A, 0xF3F3F5))
        static let ink1 = Color(uiColor: UIColor.rf(0x23252B, 0xDCDDE1))
        static let ink2 = Color(uiColor: UIColor.rf(0x30333A, 0xC4C6CC))
        static let textOnInk = Color(uiColor: UIColor.rf(0xFFFFFF, 0x15161A))
        static let textOnInkDim = Color(uiColor: UIColor.rf(0xC9CBD1, 0x4A4D55))
        static let lineOnInk = Color(uiColor: UIColor.rf(0xFFFFFF, 0x000000, alpha: 0.16))

        // LEGACY names, kept so every existing call site compiles; they now map to the v4 palette.
        static let hibiscus = accent
        static let hibiscusText = accentText

        /// Placeholder tile behind a listing photo.
        static func thumb(for id: UUID) -> Color {
            let light: [UInt32] = [0xF1F2F4, 0xEDEFF2, 0xF3F1EE, 0xEEF1F4, 0xF2F0F3, 0xEFF2EF]
            let dark: [UInt32] = [0x22242A, 0x24262C, 0x262422, 0x22262A, 0x26232A, 0x232823]
            let i = Int(id.uuid.15) % light.count                      // stable across launches
            return Color(uiColor: UIColor.rf(light[i], dark[i]))
        }
    }

    /// Typography — DM Sans for the interface (Hinge-like, free alternative to Modern Era) and Newsreader
    /// for large titles (free alternative to Tiempos). Sizes follow Vinted's compact scale and scale with
    /// Dynamic Type through `relativeTo:`.
    enum T {
        enum Face: String {
            case regular = "DMSans-Regular", medium = "DMSans-Medium", semibold = "DMSans-SemiBold", bold = "DMSans-Bold"
            case serif = "Newsreader-Medium", serifSemibold = "Newsreader-SemiBold"
        }
        static func font(_ face: Face, _ size: CGFloat, _ style: Font.TextStyle) -> Font {
            .custom(face.rawValue, size: size, relativeTo: style)
        }

        static let largeTitle = font(.serifSemibold, 30, .largeTitle)   // tab roots
        static let title = font(.serifSemibold, 24, .title2)            // hero titles
        static let title3 = font(.semibold, 18, .title3)                // section titles
        static let headline = font(.semibold, 15, .headline)            // row and card titles
        static let body = font(.regular, 15, .body)
        static let callout = font(.regular, 14, .callout)
        static let subheadline = font(.regular, 13, .subheadline)       // secondary row text
        static let footnote = font(.regular, 12, .footnote)             // metadata
        static let caption = font(.medium, 11, .caption)                // badges
        static let button = font(.semibold, 15, .headline)

        private static func size(for style: Font.TextStyle) -> CGFloat {
            switch style {
            case .largeTitle: 30
            case .title: 26
            case .title2: 22
            case .title3: 18
            case .headline, .body: 15
            case .callout: 14
            case .subheadline: 13
            case .footnote: 12
            case .caption, .caption2: 11
            @unknown default: 15
            }
        }
        private static func face(for weight: Font.Weight) -> Face {
            switch weight {
            case .bold, .heavy, .black: .bold
            case .semibold: .semibold
            case .medium: .medium
            default: .regular
            }
        }

        /// Prices and amounts: tabular digits so columns and steppers don't jitter.
        static func price(_ style: Font.TextStyle = .headline, weight: Font.Weight = .semibold) -> Font {
            font(face(for: weight), size(for: style), style).monospacedDigit()
        }
        /// Counts and stats (dashboard tiles, ratings).
        static func number(_ style: Font.TextStyle = .title2, weight: Font.Weight = .bold) -> Font {
            font(face(for: weight), size(for: style), style).monospacedDigit()
        }
        /// Brand wordmark only (splash, sign-up hero). Never for UI text.
        static func brand(_ size: CGFloat) -> Font { .custom("Unbounded-Black", size: size, relativeTo: .largeTitle) }
        /// UIKit fonts for navigation / tab bars.
        static func ui(_ face: Face, _ size: CGFloat, _ style: UIFont.TextStyle) -> UIFont {
            let base = UIFont(name: face.rawValue, size: size) ?? .systemFont(ofSize: size)
            return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
        }
    }

    /// LEGACY — mockup pixel sizes. Kept only so unconverted call sites compile. Do not use: migrate to `RF.T`.
    enum F {
        static func display(_ size: CGFloat, _ weight: DisplayWeight = .bold) -> Font {
            .custom(T.Face.semibold.rawValue, size: size + 1, relativeTo: .title)
        }
        static func body(_ size: CGFloat, _ weight: BodyWeight = .medium) -> Font {
            .custom(weight.face.rawValue, size: size + 1, relativeTo: .body)
        }
        static func mono(_ size: CGFloat, _ weight: MonoWeight = .medium) -> Font {
            .custom(T.Face.medium.rawValue, size: size + 1, relativeTo: .body).monospacedDigit()
        }
        enum DisplayWeight { case regular, semibold, bold, extraBold, black }
        enum BodyWeight { case regular, medium, semibold, bold, extraBold
            var face: T.Face { switch self { case .regular, .medium: .regular; case .semibold: .medium; case .bold: .semibold; case .extraBold: .bold } } }
        enum MonoWeight { case regular, medium, semibold }
    }

    enum R {
        static let sm: CGFloat = 8, md: CGFloat = 10, lg: CGFloat = 12, xl: CGFloat = 18, sheet: CGFloat = 20
    }

    enum S {
        static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12, lg: CGFloat = 16, xl: CGFloat = 22, xxl: CGFloat = 28
        /// Horizontal screen gutter.
        static let gutter: CGFloat = 16
    }
}

/// The ReFripe logo: « Re » in brand blue, « Fripe » in brand orange.
struct Wordmark: View {
    var size: CGFloat = 22
    var body: some View {
        (Text("Re").foregroundStyle(RF.C.brandBlue) + Text("Fripe").foregroundStyle(RF.C.brandOrange))
            .font(RF.T.brand(size))
            .accessibilityLabel("ReFripe")
    }
}
