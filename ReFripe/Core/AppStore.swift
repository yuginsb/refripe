import SwiftUI

// MARK: - Global app state shared across features (CONTRACT)
// Inject once at the root: `.environment(store)`; read with `@Environment(AppStore.self) private var store`.
// Feature-local data (a feed, a thread, an order) stays in the screen's own @State and is loaded via `store.repo`.

@MainActor
@Observable
final class AppStore {
    let repo: any Repository
    let isDemo: Bool

    // Session
    private(set) var me: UserProfile?
    var preferences = UserPreferences()
    var isBootstrapping = true
    var needsOnboarding: Bool { me == nil || !preferences.onboardingCompleted }

    // Cross-screen state
    private(set) var wishlist: Set<UUID> = []
    private(set) var unreadNotifications = 0
    private(set) var unreadMessages = 0
    /// Negotiations waiting for MY answer: offers on my listings + counter-offers on my offers.
    private(set) var offersAwaitingMe = 0
    /// « Boîte » tab badge.
    var inboxBadge: Int { unreadMessages + offersAwaitingMe + unreadNotifications }
    /// Accepted offer amounts, by listing id → used by Checkout.
    var negotiatedPrices: [UUID: FCFA] = [:]
    /// Simple profile cache so cards/rows can show seller names without refetching.
    private(set) var profileCache: [UUID: UserProfile] = [:]

    // Transient UI feedback (rendered by RootView as a toast pill above the tab bar).
    var toast: String?

    init(repo: any Repository, isDemo: Bool) {
        self.repo = repo
        self.isDemo = isDemo
    }

    // MARK: Lifecycle
    func bootstrap() async {
        defer { isBootstrapping = false }
        me = await repo.restoreSession()
        guard me != nil else { return }
        preferences = (try? await repo.loadPreferences()) ?? UserPreferences()
        bumpStreak()
        await refreshBadges()
        wishlist = (try? await repo.wishlistIds()) ?? []
    }

    func didSignIn(_ profile: UserProfile) async {
        me = profile
        profileCache[profile.id] = profile
        preferences = (try? await repo.loadPreferences()) ?? preferences
        wishlist = (try? await repo.wishlistIds()) ?? []
        await refreshBadges()
    }

    func signOut() async {
        try? await repo.signOut()
        me = nil; preferences = UserPreferences(); wishlist = []; negotiatedPrices = [:]
    }

    func updatePreferences(_ change: (inout UserPreferences) -> Void) {
        change(&preferences)
        let snapshot = preferences
        Task { try? await repo.savePreferences(snapshot) }
    }

    // MARK: Streak ("Série de N jours")
    private func bumpStreak() {
        let today = Calendar.current.startOfDay(for: .now)
        updatePreferences { p in
            if let last = p.lastActiveDay.map({ Calendar.current.startOfDay(for: $0) }) {
                let gap = Calendar.current.dateComponents([.day], from: last, to: today).day ?? 0
                if gap == 1 { p.streakDays += 1 } else if gap > 1 { p.streakDays = 1 }
            } else { p.streakDays = 1 }
            p.lastActiveDay = today
        }
    }

    // MARK: Wishlist
    func isLiked(_ id: UUID) -> Bool { wishlist.contains(id) }

    func toggleLike(_ id: UUID) {
        let liked = !wishlist.contains(id)
        setLiked(id, liked)
    }

    func setLiked(_ id: UUID, _ liked: Bool) {
        if liked { wishlist.insert(id) } else { wishlist.remove(id) }
        Task {
            do { try await repo.setLiked(listingId: id, liked: liked) }
            catch { if liked { wishlist.remove(id) } else { wishlist.insert(id) }; show(error) }
        }
    }

    // MARK: Badges
    func refreshBadges() async {
        unreadNotifications = ((try? await repo.notifications()) ?? []).filter { !$0.read }.count
        unreadMessages = ((try? await repo.conversations()) ?? []).reduce(0) { $0 + $1.unreadCount }
        let asSeller = ((try? await repo.offerThreads(role: .seller)) ?? []).filter(\.awaitsSellerAnswer)
        let asBuyer = ((try? await repo.offerThreads(role: .buyer)) ?? []).filter(\.awaitsBuyerAnswer)
        offersAwaitingMe = asSeller.count + asBuyer.count
    }

    // MARK: Profiles
    func profile(_ id: UUID) async -> UserProfile? {
        if let p = profileCache[id] { return p }
        guard let p = try? await repo.profile(id: id) else { return nil }
        profileCache[id] = p
        return p
    }
    func cachedProfile(_ id: UUID) -> UserProfile? { profileCache[id] }
    func cache(_ profiles: [UUID: UserProfile]) { profileCache.merge(profiles) { _, new in new } }

    // MARK: Feedback
    func show(_ message: String) {
        toast = message
        Task { try? await Task.sleep(for: .seconds(2.2)); if toast == message { toast = nil } }
    }
    func show(_ error: Error) { show(error.localizedDescription) }
}

extension OfferThread {
    /// Pending and the buyer spoke last → the seller has to accept / refuse / counter.
    var awaitsSellerAnswer: Bool { status == .pending && rounds.last?.by == .buyer }
    /// Pending and the seller countered last → the buyer has to answer.
    var awaitsBuyerAnswer: Bool { status == .pending && rounds.last?.by == .seller }
}
