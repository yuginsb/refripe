import SwiftUI
import UIKit

/// Splash while the session is restored, then the 5-tab shell. Onboarding/sign-up is presented
/// full screen whenever there is no session or onboarding isn't completed.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        ZStack {
            if store.isBootstrapping {
                SplashView().transition(.opacity)
            } else {
                MainTabView().transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.35), value: store.isBootstrapping)
        .onOpenURL { url in
            DeepLink(url: url)?.apply(to: router)
        }
        .fullScreenCover(isPresented: onboardingPresented) {
            OnboardingFlowView()
                .environment(store)
                .environment(router)
                .rfToastHost()
        }
    }

    private var onboardingPresented: Binding<Bool> {
        Binding(get: { !store.isBootstrapping && store.needsOnboarding }, set: { _ in })
    }
}

// MARK: - Splash

struct SplashView: View {
    var body: some View {
        ZStack {
            RF.C.ink0.ignoresSafeArea()
            (Text("Re").foregroundStyle(RF.C.textOnInk) + Text("Fripe").foregroundStyle(RF.C.marigold))
                .font(RF.T.brand(34))
            VStack {
                Spacer()
                ProgressView()
                    .tint(RF.C.marigold)
                    .padding(.bottom, 48)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ReFripe, chargement")
    }
}

// MARK: - Tabs
// Découvrir · Envies · Vendre (+) · Boîte (Messages, Commandes, Notifications) · Profil

struct MainTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: tabSelection) {
            stack(.discover) { DiscoverView() }
                .tabItem { Label("Découvrir", systemImage: "house") }
                .tag(AppTab.discover)

            stack(.wishlist) { WishlistView() }
                .tabItem { Label("Envies", systemImage: "heart") }
                .tag(AppTab.wishlist)

            // "Vendre" never becomes the selected tab: selecting it presents the sell flow.
            RF.C.paper
                .tabItem {
                    Label {
                        Text("Vendre")
                    } icon: {
                        Image(uiImage: SellTabIcon.image).renderingMode(.original)
                    }
                }
                .tag(AppTab.sell)
                .accessibilityLabel("Vendre un article")

            stack(.messages) { InboxView() }
                .tabItem { Label("Boîte", systemImage: "tray") }
                .tag(AppTab.messages)
                .badge(store.inboxBadge)

            stack(.profile) { ProfileTabView() }
                .tabItem { Label("Profil", systemImage: "person") }
                .tag(AppTab.profile)
        }
        .rfToastHost(bottomPadding: 60)
        .sensoryFeedback(.selection, trigger: router.selectedTab)
        .onChange(of: router.selectedTab) {
            Task { await store.refreshBadges() }
        }
        .fullScreenCover(isPresented: $router.isSellPresented) {
            SellFlowView()
                .environment(store)
                .environment(router)
                .rfToastHost()
        }
    }

    private func stack<Root: View>(_ tab: AppTab, @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: router.binding(for: tab)) {
            root()
                .withAppRoutes()
        }
    }

    /// Intercepts "Vendre" and pops to root when the current tab is re-selected.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { router.selectedTab },
            set: { newTab in
                if newTab == .sell {
                    router.isSellPresented = true
                } else if newTab == router.selectedTab {
                    router.popToRoot(newTab)
                } else {
                    router.selectedTab = newTab
                }
            }
        )
    }
}

/// Hibiscus disc with a white "+" (mockup `.navbtn.sell .sellcircle`), drawn once as an original-colour image.
@MainActor
enum SellTabIcon {
    static let image: UIImage = {
        let size = CGSize(width: 32, height: 32)
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(RF.C.hibiscus).setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
            if let plus = UIImage(systemName: "plus", withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let s = plus.size
                plus.draw(in: CGRect(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2,
                                     width: s.width, height: s.height))
            }
        }
        return rendered.withRenderingMode(.alwaysOriginal)
    }()
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView().previewEnvironment()
    }
}
