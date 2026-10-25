import SwiftUI
import UIKit

// MARK: - Design tokens from the mockup (CONTRACT)

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum RF {
    enum C {
        static let ink0 = Color(hex: 0x150C1A)
        static let ink1 = Color(hex: 0x221430)
        static let ink2 = Color(hex: 0x2F1C3D)
        static let paper = Color(hex: 0xFBF3E6)
        static let paperDim = Color(hex: 0xEFE3D1)
        static let marigold = Color(hex: 0xF2A33D)
        static let hibiscus = Color(hex: 0xE1483A)
        static let money = Color(hex: 0x1E9E73)
        static let moneyDeep = Color(hex: 0x136E51)
        static let textOnInk = Color(hex: 0xF4EAD9)
        static let textOnInkDim = Color(hex: 0xC9B8C9)
        static let text = Color(hex: 0x241527)         // text on paper
        static let textDim = Color(hex: 0x7A6A72)      // secondary text on paper
        static let lineOnInk = Color(hex: 0xF4EAD9, opacity: 0.14)
        static let line = Color(hex: 0x241527, opacity: 0.10)  // hairline on paper
        static let card = Color.white
        static let scrim = Color(hex: 0x150C1A, opacity: 0.45)

        /// Placeholder tile behind a listing photo (mockup's thumbColor).
        static func thumb(for id: UUID) -> Color {
            let palette: [UInt32] = [0xF4E3C4, 0xF0D9C8, 0xE8DFC9, 0xF2E0D6, 0xE6DDC6, 0xF0D8B8]
            return Color(hex: palette[Int(id.uuid.15) % palette.count])   // stable across launches
        }
    }

    /// Typography — San Francisco (system font) with native text styles, so Dynamic Type works.
    /// Use these everywhere. Numbers: `RF.T.price` / `RF.T.number` (tabular digits, no mono font).
    enum T {
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title = Font.title2.weight(.bold)          // 22 — screen hero titles
        static let title3 = Font.title3.weight(.semibold)     // 20 — section titles in content
        static let headline = Font.headline                   // 17 semibold — row titles, card titles
        static let body = Font.body                           // 17
        static let callout = Font.callout                     // 16
        static let subheadline = Font.subheadline             // 15 — secondary row text
        static let footnote = Font.footnote                   // 13 — metadata
        static let caption = Font.caption                     // 12 — badges, tiny labels (use sparingly)
        static let button = Font.headline                     // primary buttons

        /// Prices and amounts: tabular digits so columns and steppers don't jitter.
        static func price(_ style: Font.TextStyle = .headline, weight: Font.Weight = .semibold) -> Font {
            Font.system(style, weight: weight).monospacedDigit()
        }
        /// Counts and stats (dashboard tiles, ratings).
        static func number(_ style: Font.TextStyle = .title2, weight: Font.Weight = .bold) -> Font {
            Font.system(style, weight: weight).monospacedDigit()
        }
        /// Brand wordmark only (splash, sign-up hero). Never for UI text.
        static func brand(_ size: CGFloat) -> Font { .custom("Unbounded-Black", size: size, relativeTo: .largeTitle) }
    }

    /// LEGACY — mockup pixel sizes. Kept only so unconverted call sites compile; they now render in SF.
    /// Do not use in new code: migrate to `RF.T`.
    enum F {
        static func display(_ size: CGFloat, _ weight: DisplayWeight = .bold) -> Font {
            .system(size: scaled(size + 3), weight: weight.system)
        }
        static func body(_ size: CGFloat, _ weight: BodyWeight = .medium) -> Font {
            .system(size: scaled(size + 2), weight: weight.system)
        }
        static func mono(_ size: CGFloat, _ weight: MonoWeight = .medium) -> Font {
            .system(size: scaled(size + 2), weight: weight.system).monospacedDigit()
        }
        private static func scaled(_ size: CGFloat) -> CGFloat { UIFontMetrics.default.scaledValue(for: size) }
        enum DisplayWeight { case regular, semibold, bold, extraBold, black
            var system: Font.Weight { switch self { case .regular: .regular; case .semibold: .semibold; case .bold: .bold; case .extraBold: .heavy; case .black: .black } } }
        enum BodyWeight { case regular, medium, semibold, bold, extraBold
            var system: Font.Weight { switch self { case .regular: .regular; case .medium: .regular; case .semibold: .medium; case .bold: .semibold; case .extraBold: .bold } } }
        enum MonoWeight { case regular, medium, semibold
            var system: Font.Weight { switch self { case .regular: .regular; case .medium: .medium; case .semibold: .semibold } } }
    }

    enum R {
        static let sm: CGFloat = 9, md: CGFloat = 12, lg: CGFloat = 14, xl: CGFloat = 20, sheet: CGFloat = 22
    }

    enum S {
        static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12, lg: CGFloat = 16, xl: CGFloat = 22, xxl: CGFloat = 28
        /// Horizontal screen gutter used across the mockup.
        static let gutter: CGFloat = 16
    }
}
