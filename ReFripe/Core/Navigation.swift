import SwiftUI

// MARK: - Navigation (CONTRACT)
// One NavigationStack per tab. Push with `router.push(.product(id))` from anywhere.
// "Vendre" is not a real tab: tapping it presents SellFlowView full screen.
// Signup/onboarding is presented full screen by RootView when there is no session.

enum AppTab: Hashable, CaseIterable {
    case discover, wishlist, sell, messages, profile
}

enum Route: Hashable {
    case product(UUID)              // listing id
    case offer(UUID)                // listing id — compose an offer / counter-offer
    case offerThread(UUID)          // listing id — negotiation thread (buyer side)
    case receivedOffers(UUID)       // listing id — offers received on MY listing (seller side: accept / refuse / counter)
    case checkout(UUID)             // listing id
    case order(UUID)                // order id — tracking (buyer & seller)
    case chat(UUID)                 // conversation id
    case sellerProfile(UUID)        // user id
    case dashboard
    case notifications
}

@MainActor
@Observable
final class Router {
    var selectedTab: AppTab = .discover
    var paths: [AppTab: NavigationPath] = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, NavigationPath()) })
    var isSellPresented = false

    func push(_ route: Route) {
        paths[selectedTab, default: NavigationPath()].append(route)
    }
    func pop() {
        guard var p = paths[selectedTab], !p.isEmpty else { return }
        p.removeLast(); paths[selectedTab] = p
    }
    func popToRoot(_ tab: AppTab? = nil) {
        paths[tab ?? selectedTab] = NavigationPath()
    }
    /// Switch tab, reset it, then push (used by notifications / deep links / dashboard CTAs).
    func open(_ route: Route, in tab: AppTab) {
        selectedTab = tab
        paths[tab] = NavigationPath([route])
    }
    func binding(for tab: AppTab) -> Binding<NavigationPath> {
        Binding(get: { self.paths[tab] ?? NavigationPath() }, set: { self.paths[tab] = $0 })
    }
}

extension View {
    /// Every tab's NavigationStack root applies this so any screen can push any route.
    func withAppRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .product(let id): ProductView(listingId: id)
            case .offer(let id): OfferComposerView(listingId: id)
            case .offerThread(let id): OfferThreadView(listingId: id)
            case .receivedOffers(let id): ReceivedOffersView(listingId: id)
            case .checkout(let id): CheckoutView(listingId: id)
            case .order(let id): OrderTrackingView(orderId: id)
            case .chat(let id): ChatThreadView(conversationId: id)
            case .sellerProfile(let id): SellerProfileView(userId: id)
            case .dashboard: DashboardView()
            case .notifications: NotificationsView()
            }
        }
    }
}
