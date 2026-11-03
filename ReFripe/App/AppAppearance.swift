import SwiftUI
import UIKit

/// UIKit appearance for the native bars: dynamic colours (light / dark), orange selection, DM Sans.
@MainActor
enum AppAppearance {
    static func configure() {
        let background = RF.U.background
        let text = RF.U.text
        let dim = RF.U.textDim
        let accent = RF.U.accent
        let hairline = RF.U.line

        // Tab bar
        let itemFont = RF.T.ui(.medium, 10, .caption2)
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = background
        tab.shadowColor = hairline
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = dim
            item.normal.titleTextAttributes = [.foregroundColor: dim, .font: itemFont]
            item.selected.iconColor = accent
            item.selected.titleTextAttributes = [.foregroundColor: accent, .font: itemFont]
            item.normal.badgeBackgroundColor = accent
            item.normal.badgeTextAttributes = [.foregroundColor: UIColor.white]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        // Navigation bar
        func navAppearance(hairline shadow: UIColor) -> UINavigationBarAppearance {
            let nav = UINavigationBarAppearance()
            nav.configureWithOpaqueBackground()
            nav.backgroundColor = background
            nav.shadowColor = shadow
            nav.titleTextAttributes = [.foregroundColor: text, .font: RF.T.ui(.semibold, 16, .headline)]
            nav.largeTitleTextAttributes = [.foregroundColor: text, .font: RF.T.ui(.serifSemibold, 30, .largeTitle)]
            return nav
        }
        UINavigationBar.appearance().standardAppearance = navAppearance(hairline: hairline)
        UINavigationBar.appearance().compactAppearance = navAppearance(hairline: hairline)
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance(hairline: .clear)
        UINavigationBar.appearance().tintColor = accent

        // Segmented controls and switches pick up the brand.
        UISegmentedControl.appearance().setTitleTextAttributes([.font: RF.T.ui(.medium, 13, .subheadline)], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: RF.T.ui(.semibold, 13, .subheadline)], for: .selected)
        UISwitch.appearance().onTintColor = RF.U.brandBlue
    }
}
