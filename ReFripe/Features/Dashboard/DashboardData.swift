import Foundation

/// Orders and negotiations of the signed-in user, both hats, loaded in one go.
/// Used by Boîte › Commandes (purchases, sales, offers to handle).
struct DashboardData {
    var sellerOrders: [Order] = []
    var buyerOrders: [Order] = []
    var buyerThreads: [OfferThread] = []
    var sellerThreads: [OfferThread] = []
    /// Counterparts of the threads (buyers of my listings, sellers of what I negotiate), for their handle.
    var people: [UUID: UserProfile] = [:]
    /// Listings referenced by the threads.
    var listings: [UUID: Listing] = [:]

    @MainActor
    static func load(store: AppStore) async throws -> DashboardData {
        let repo = store.repo
        async let threadsTask = try? repo.offerThreads(role: .buyer)
        async let sellerThreadsTask = try? repo.offerThreads(role: .seller)
        let sellerOrders = try await repo.orders(role: .seller)
        let buyerOrders = try await repo.orders(role: .buyer)

        var data = DashboardData()
        data.sellerOrders = sellerOrders
        data.buyerOrders = buyerOrders
        data.buyerThreads = (await threadsTask ?? []).sorted { $0.updatedAt > $1.updatedAt }
        data.sellerThreads = (await sellerThreadsTask ?? []).sorted { $0.updatedAt > $1.updatedAt }

        let peopleIds = Set(data.sellerThreads.map(\.buyerId)).union(data.buyerThreads.map(\.sellerId))
        if !peopleIds.isEmpty {
            data.people = (try? await repo.profiles(ids: Array(peopleIds))) ?? [:]
            store.cache(data.people)
        }

        let ids = Set(data.buyerThreads.map(\.listingId)).union(data.sellerThreads.map(\.listingId))
        data.listings = await withTaskGroup(of: Listing?.self) { group in
            for id in ids { group.addTask { try? await repo.listing(id: id) } }
            var out: [UUID: Listing] = [:]
            for await listing in group { if let listing { out[listing.id] = listing } }
            return out
        }
        return data
    }

    // MARK: Offers

    /// Offers on my listings waiting for my answer (pending, last round by the buyer).
    var receivedOffers: [OfferThread] { sellerThreads.filter(\.awaitsSellerAnswer) }
    /// Counter-offers on my offers waiting for my answer.
    var counterOffers: [OfferThread] { buyerThreads.filter(\.awaitsBuyerAnswer) }
    /// My offers waiting for the seller.
    var sentOffers: [OfferThread] { buyerThreads.filter(\.awaitsSellerAnswer) }

    // MARK: Orders

    var openSales: [Order] { Self.open(sellerOrders) }
    var pastSales: [Order] { Self.past(sellerOrders) }
    var openPurchases: [Order] { Self.open(buyerOrders) }
    var pastPurchases: [Order] { Self.past(buyerOrders) }

    private static func open(_ orders: [Order]) -> [Order] {
        orders.filter { $0.status.isOpenForDashboard }
            .sorted { a, b in
                a.status.urgencyRank != b.status.urgencyRank
                    ? a.status.urgencyRank < b.status.urgencyRank
                    : a.createdAt > b.createdAt
            }
    }
    private static func past(_ orders: [Order]) -> [Order] {
        orders.filter { !$0.status.isOpenForDashboard }.sorted { $0.createdAt > $1.createdAt }
    }
}

extension OrderStatus {
    /// Still in progress (shown in the « En cours » lists).
    var isOpenForDashboard: Bool { ![.completed, .cancelled, .refunded].contains(self) }
}
