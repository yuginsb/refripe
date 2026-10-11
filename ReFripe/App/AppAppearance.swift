import SwiftUI
import UIKit

/// UIKit appearance for the native bars: paper background, hairline, hibiscus selection, brand fonts.
@MainActor
enum AppAppearance {
    static func configure() {
        let paper = UIColor(RF.C.paper)
        let text = UIColor(RF.C.text)
        let dim = UIColor(RF.C.textDim)
        let hibiscus = UIColor(RF.C.hibiscus)
        let hairline = UIColor(RF.C.line)

        // Tab bar (mockup `.bottomnav`)
        let itemFont = scaled("Manrope-Bold", 10, weight: .bold, style: .caption2)
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = paper
        tab.shadowColor = hairline
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = dim
            item.normal.titleTextAttributes = [.foregroundColor: dim, .font: itemFont]
            item.selected.iconColor = hibiscus
            item.selected.titleTextAttributes = [.foregroundColor: hibiscus, .font: itemFont]
            item.normal.badgeBackgroundColor = hibiscus
            item.normal.badgeTextAttributes = [.foregroundColor: UIColor.white]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        // Navigation bar
        func navAppearance(hairline shadow: UIColor) -> UINavigationBarAppearance {
            let nav = UINavigationBarAppearance()
            nav.configureWithOpaqueBackground()
            nav.backgroundColor = paper
            nav.shadowColor = shadow
            nav.titleTextAttributes = [.foregroundColor: text,
                                       .font: scaled("Unbounded-Bold", 15, weight: .bold, style: .headline)]
            nav.largeTitleTextAttributes = [.foregroundColor: text,
                                            .font: scaled("Unbounded-Bold", 26, weight: .bold, style: .largeTitle)]
            return nav
        }
        UINavigationBar.appearance().standardAppearance = navAppearance(hairline: hairline)
        UINavigationBar.appearance().compactAppearance = navAppearance(hairline: hairline)
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance(hairline: .clear)
        UINavigationBar.appearance().tintColor = hibiscus
    }

    private static func scaled(_ name: String, _ size: CGFloat, weight: UIFont.Weight, style: UIFont.TextStyle) -> UIFont {
        let base = UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }
}
