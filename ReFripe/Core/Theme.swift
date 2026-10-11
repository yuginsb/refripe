import SwiftUI

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

    /// Fonts — PostScript names of the bundled TTFs. Sizes are in points.
    enum F {
        static func display(_ size: CGFloat, _ weight: DisplayWeight = .bold) -> Font {
            .custom(weight.rawValue, size: size, relativeTo: .title)
        }
        static func body(_ size: CGFloat, _ weight: BodyWeight = .medium) -> Font {
            .custom(weight.rawValue, size: size, relativeTo: .body)
        }
        static func mono(_ size: CGFloat, _ weight: MonoWeight = .medium) -> Font {
            .custom(weight.rawValue, size: size, relativeTo: .body)
        }
        enum DisplayWeight: String { case regular = "Unbounded-Regular", semibold = "Unbounded-SemiBold", bold = "Unbounded-Bold", extraBold = "Unbounded-ExtraBold", black = "Unbounded-Black" }
        enum BodyWeight: String { case regular = "Manrope-Regular", medium = "Manrope-Medium", semibold = "Manrope-SemiBold", bold = "Manrope-Bold", extraBold = "Manrope-ExtraBold" }
        enum MonoWeight: String { case regular = "IBMPlexMono-Regular", medium = "IBMPlexMono-Medium", semibold = "IBMPlexMono-SemiBold" }
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
