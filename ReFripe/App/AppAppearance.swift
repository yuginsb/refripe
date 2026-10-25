import SwiftUI
import UIKit

/// UIKit appearance for the native bars: paper background, hairline, hibiscus selection, system font.
@MainActor
enum AppAppearance {
    static func configure() {
        let paper = UIColor(RF.C.paper)
        let text = UIColor(RF.C.text)
        let dim = UIColor(RF.C.textDim)
        let hibiscus = UIColor(RF.C.hibiscus)
        let hairline = UIColor(RF.C.line)

        // Tab bar (mockup `.bottomnav`)
        let itemFont = UIFont.preferredFont(forTextStyle: .caption2)
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
                                       .font: UIFont.preferredFont(forTextStyle: .headline)]
            nav.largeTitleTextAttributes = [.foregroundColor: text,
                                            .font: bold(.largeTitle)]
            return nav
        }
        UINavigationBar.appearance().standardAppearance = navAppearance(hairline: hairline)
        UINavigationBar.appearance().compactAppearance = navAppearance(hairline: hairline)
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance(hairline: .clear)
        UINavigationBar.appearance().tintColor = hibiscus
    }

    private static func bold(_ style: UIFont.TextStyle) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let d = base.fontDescriptor.withSymbolicTraits(.traitBold) ?? base.fontDescriptor
        return UIFont(descriptor: d, size: 0)
    }
}
