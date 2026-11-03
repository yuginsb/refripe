import Foundation

/// Everything the Messages tab needs, loaded in one go: conversations (blocked members hidden),
/// orders and negotiations on both sides, plus the profiles / listings they reference.
struct InboxData {
    var conversations: [Conversation] = []
    var buyerOrders: [Order] = []
    var sellerOrders: [Order] = []
    var buyerThreads: [OfferThread] = []
    var sellerThreads: [OfferThread] = []
    var blocked: Set<UUID> = []
    var people: [UUID: UserProfile] = [:]
    var listings: [UUID: Listing] = [:]

    /// Loads only what `parts` asks for (the orders lists of the Profile don't need conversations).
    struct Parts: OptionSet {
        let rawValue: Int
        static let conversations = Parts(rawValue: 1)
        static let orders = Parts(rawValue: 2)
        static let offers = Parts(rawValue: 4)
        static let all: Parts = [.conversations, .orders, .offers]
    }

    @MainActor
    static func load(store: AppStore, parts: Parts = .all, previous: InboxData? = nil) async throws -> InboxData {
        let repo = store.repo
        var data = InboxData()
        data.people = previous?.people ?? [:]
        data.listings = previous?.listings ?? [:]

        if parts.contains(.conversations) {
            data.blocked = (try? await repo.blockedUserIds()) ?? []
            data.conversations = try await repo.conversations()
                .filter { !data.blocked.contains($0.otherUserId) }
                .sorted { $0.lastMessageAt > $1.lastMessageAt }
        }
        if parts.contains(.orders) {
            data.buyerOrders = try await repo.orders(role: .buyer)
            data.sellerOrders = try await repo.orders(role: .seller)
        }
        if parts.contains(.offers) {
            data.buyerThreads = ((try? await repo.offerThreads(role: .buyer)) ?? []).sorted { $0.updatedAt > $1.updatedAt }
            data.sellerThreads = ((try? await repo.offerThreads(role: .seller)) ?? []).sorted { $0.updatedAt > $1.updatedAt }
        }

        // Profiles (counterparts) and listings referenced by the rows.
        var peopleIds = Set(data.conversations.map(\.otherUserId))
        peopleIds.formUnion(data.sellerThreads.map(\.buyerId))
        peopleIds.formUnion(data.buyerThreads.map(\.sellerId))
        peopleIds.formUnion(data.buyerOrders.map(\.sellerId))
        let missingPeople = peopleIds.subtracting(data.people.keys)
        if !missingPeople.isEmpty {
            let found = (try? await repo.profiles(ids: Array(missingPeople))) ?? [:]
            data.people.merge(found) { _, new in new }
            store.cache(found)
        }

        var listingIds = Set(data.conversations.compactMap(\.listingId))
        listingIds.formUnion(data.buyerThreads.map(\.listingId))
        listingIds.formUnion(data.sellerThreads.map(\.listingId))
        let missingListings = listingIds.subtracting(data.listings.keys)
        if !missingListings.isEmpty {
            let fetched = await withTaskGroup(of: Listing?.self) { group in
                for id in missingListings { group.addTask { try? await repo.listing(id: id) } }
                var out: [UUID: Listing] = [:]
                for await listing in group { if let listing { out[listing.id] = listing } }
                return out
            }
            data.listings.merge(fetched) { _, new in new }
        }
        return data
    }

    func name(_ id: UUID, fallback: String) -> String { people[id]?.username ?? fallback }

    /// Conversation with `userId` about `listingId`, when it already exists (has messages).
    func conversation(with userId: UUID, listingId: UUID) -> Conversation? {
        conversations.first { $0.otherUserId == userId && $0.listingId == listingId }
    }

    // MARK: Orders lists (Profil › Mes achats / Mes ventes)

    func orders(_ role: OrderRole) -> [Order] { role == .buyer ? buyerOrders : sellerOrders }

    func openOrders(_ role: OrderRole) -> [Order] {
        orders(role).filter(\.isOpen).sorted { a, b in
            a.status.urgencyRank != b.status.urgencyRank ? a.status.urgencyRank < b.status.urgencyRank : a.createdAt > b.createdAt
        }
    }

    func pastOrders(_ role: OrderRole) -> [Order] {
        orders(role).filter { !$0.isOpen }.sorted { $0.createdAt > $1.createdAt }
    }

    /// My negotiations still going on, as a buyer (waiting for the seller or for me).
    var openBuyerThreads: [OfferThread] { buyerThreads.filter { $0.status == .pending } }

    // MARK: « À faire »

    enum TodoKind: Hashable {
        case payOrder(Order)               // buyer, PAYMENT_PENDING → resume payment
        case confirmReception(Order)       // buyer, DELIVERED / BUYER_VALIDATION → countdown
        case ship(Order)                   // seller, PAID / AWAITING_SHIPMENT
        case handOff(Order)                // seller, SHIPPED → type the buyer's code
        case answerOffer(OfferThread)      // seller: an offer waits for my answer
        case answerCounter(OfferThread)    // buyer: a counter-offer waits for me
        case payAccepted(OfferThread)      // buyer: offer accepted, item reserved for me, not ordered yet
    }

    struct Todo: Identifiable, Hashable {
        let kind: TodoKind
        let date: Date
        var id: String {
            switch kind {
            case .payOrder(let o): "pay-\(o.id)"
            case .confirmReception(let o): "confirm-\(o.id)"
            case .ship(let o): "ship-\(o.id)"
            case .handOff(let o): "handoff-\(o.id)"
            case .answerOffer(let t): "offer-\(t.id)"
            case .answerCounter(let t): "counter-\(t.id)"
            case .payAccepted(let t): "accepted-\(t.id)"
            }
        }
    }

    func todos(now: Date = .now) -> [Todo] {
        var out: [Todo] = []
        for o in buyerOrders {
            if o.status == .paymentPending { out.append(Todo(kind: .payOrder(o), date: o.createdAt)) }
            if o.awaitsBuyerConfirmation { out.append(Todo(kind: .confirmReception(o), date: o.escrowReleaseAt ?? o.createdAt)) }
        }
        for o in sellerOrders {
            if o.awaitsShipping { out.append(Todo(kind: .ship(o), date: o.history.last?.at ?? o.createdAt)) }
            if o.status == .shipped { out.append(Todo(kind: .handOff(o), date: o.history.last?.at ?? o.createdAt)) }
        }
        for t in sellerThreads where t.awaitsSellerAnswer {
            out.append(Todo(kind: .answerOffer(t), date: t.updatedAt))
        }
        for t in buyerThreads where t.awaitsBuyerAnswer {
            out.append(Todo(kind: .answerCounter(t), date: t.updatedAt))
        }
        // Accepted offer, reservation still running, no order yet → « Payer ».
        let ordered = Set(buyerOrders.filter { $0.status != .cancelled }.map(\.listingId))
        for t in buyerThreads where t.status == .accepted && !ordered.contains(t.listingId) {
            if let l = listings[t.listingId], let until = l.reservedUntil, until > now, l.reservedFor == t.buyerId {
                out.append(Todo(kind: .payAccepted(t), date: t.updatedAt))
            }
        }
        return out.sorted { Self.rank($0.kind) != Self.rank($1.kind) ? Self.rank($0.kind) < Self.rank($1.kind) : $0.date > $1.date }
    }

    private static func rank(_ kind: TodoKind) -> Int {
        switch kind {
        case .payOrder, .payAccepted: 0
        case .confirmReception: 1
        case .answerOffer, .answerCounter: 2
        case .ship, .handOff: 3
        }
    }
}

extension Order {
    /// Still in progress (« En cours »).
    var isOpen: Bool { ![.completed, .cancelled, .refunded].contains(status) }
}
