import Foundation

/// In-memory `Repository` seeded with the mockup data. Simulates the other side of the marketplace:
/// seller answers to offers (~1,5 s), payment confirmation, chat replies (~2 s).
/// All state lives in the `DemoState` actor, so this class is safely `Sendable`.
final class DemoRepository: Repository {
    private let state: DemoState

    init(now: Date = .now) {
        state = DemoState(seed: DemoSeed.make(now: now))
    }

    // MARK: Auth & profile
    var currentUserId: UUID? { get async { await state.me } }
    func restoreSession() async -> UserProfile? { await state.restoreSession() }
    func sendOTP(phone: String) async throws { try await state.sendOTP(phone: phone) }
    func verifyOTP(phone: String, code: String) async throws -> UserProfile? { try await state.verifyOTP(phone: phone, code: code) }
    func signInWithApple(idToken: String, nonce: String) async throws -> UserProfile? { try await state.signInWithApple() }
    func completeSignup(_ input: SignupProfileInput) async throws -> UserProfile { try await state.completeSignup(input) }
    func signOut() async throws { await state.signOut() }
    func loadPreferences() async throws -> UserPreferences { try await state.loadPreferences() }
    func savePreferences(_ prefs: UserPreferences) async throws { try await state.savePreferences(prefs) }

    // MARK: Catalog
    func feed(filters: ListingFilters, preferences: UserPreferences?) async throws -> [Listing] {
        await DemoState.latency()
        return await state.feed(filters: filters, preferences: preferences)
    }
    func swipeDeck(preferences: UserPreferences?) async throws -> [Listing] { await state.swipeDeck(preferences: preferences) }
    func listing(id: UUID) async throws -> Listing { try await state.listing(id: id) }
    func listings(sellerId: UUID) async throws -> [Listing] { await state.listings(sellerId: sellerId) }
    func profile(id: UUID) async throws -> UserProfile { try await state.profile(id: id) }
    func profiles(ids: [UUID]) async throws -> [UUID: UserProfile] { await state.profiles(ids: ids) }
    func recordView(listingId: UUID) async { await state.recordView(listingId: listingId) }
    func nextDropDate() async throws -> Date { await state.nextDropDate() }

    // MARK: Wishlist & swipe
    func wishlistIds() async throws -> Set<UUID> { try await state.wishlistIds() }
    func setLiked(listingId: UUID, liked: Bool) async throws { try await state.setLiked(listingId: listingId, liked: liked) }
    func recordSwipe(listingId: UUID, liked: Bool) async throws { try await state.recordSwipe(listingId: listingId, liked: liked) }

    // MARK: Selling
    func publish(_ draft: ListingDraft) async throws -> Listing {
        await DemoState.latency(0.6)
        return try await state.publish(draft)
    }
    func updatePrice(listingId: UUID, price: FCFA) async throws -> Listing { try await state.updatePrice(listingId: listingId, price: price) }

    // MARK: Negotiation
    func offerThread(listingId: UUID) async throws -> OfferThread? { try await state.offerThread(listingId: listingId) }
    func offerThreads(role: OrderRole) async throws -> [OfferThread] { try await state.offerThreads(role: role) }
    func makeOffer(listingId: UUID, amount: FCFA) async throws -> OfferThread { try await state.makeOffer(listingId: listingId, amount: amount) }
    func respondToOffer(threadId: UUID, action: OfferAction, amount: FCFA?) async throws -> OfferThread {
        try await state.respondToOffer(threadId: threadId, action: action, amount: amount)
    }

    // MARK: Orders
    func createOrder(listingId: UUID, delivery: DeliveryMethod, payment: PaymentMethod) async throws -> Order {
        await DemoState.latency(0.5)
        return try await state.createOrder(listingId: listingId, delivery: delivery, payment: payment)
    }
    func orders(role: OrderRole) async throws -> [Order] { try await state.orders(role: role) }
    func order(id: UUID) async throws -> Order { try await state.order(id: id) }
    func advanceOrder(id: UUID, to status: OrderStatus) async throws -> Order { try await state.advanceOrder(id: id, to: status) }

    // MARK: Messaging
    func conversations() async throws -> [Conversation] { try await state.conversations() }
    func messages(conversationId: UUID) async throws -> [ChatMessage] { try await state.messages(conversationId: conversationId) }
    func send(text: String, conversationId: UUID) async throws -> ChatMessage { try await state.send(text: text, conversationId: conversationId) }
    func conversation(withUser userId: UUID, listingId: UUID?) async throws -> Conversation {
        try await state.conversation(withUser: userId, listingId: listingId)
    }
    func markConversationRead(id: UUID) async throws { try await state.markConversationRead(id: id) }

    // MARK: Notifications
    func notifications() async throws -> [AppNotification] { try await state.notifications() }
    func markNotificationsRead() async throws { try await state.markNotificationsRead() }

    // MARK: Dashboard
    func sellerStats() async throws -> SellerStats { state.stats }
    func recommendations() async throws -> [SellerRecommendation] { state.recommendations }
}

// MARK: - State actor

actor DemoState {
    private(set) var me: UUID?
    private var users: [UUID: UserProfile]
    private var preferences: [UUID: UserPreferences]
    private var phones: [String: UUID]
    private var pendingPhone: String?
    private var pendingApple = false
    private var appleUser: UUID?
    private var items: [Listing]
    private var wishlists: [UUID: Set<UUID>]
    private var swiped: [UUID: Set<UUID>] = [:]
    private var threads: [OfferThread]
    private var allOrders: [Order]
    private var convs: [DemoConversation]
    private var messagesByConv: [UUID: [ChatMessage]]
    private var notifs: [UUID: [AppNotification]]
    private var dropDate: Date?
    let stats: SellerStats
    let recommendations: [SellerRecommendation]

    init(seed: DemoSeed) {
        me = DemoIDs.awa
        users = seed.profiles
        preferences = seed.preferences
        phones = seed.phones
        items = seed.listings
        wishlists = seed.wishlists
        threads = seed.threads
        allOrders = seed.orders
        convs = seed.conversations
        messagesByConv = seed.messages
        notifs = seed.notifications
        stats = seed.stats
        recommendations = seed.recommendations
    }

    /// Small artificial delay so loading states are visible in demo mode.
    static func latency(_ seconds: Double = 0.25) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func requireMe() throws -> UUID {
        guard let me else { throw RepositoryError.notAuthenticated }
        return me
    }

    // MARK: Auth

    func restoreSession() -> UserProfile? { me.flatMap { users[$0] } }

    private static func phoneKey(_ phone: String) -> String { String(phone.filter(\.isNumber).suffix(10)) }

    func sendOTP(phone: String) throws {
        guard phone.filter(\.isNumber).count >= 8 else { throw RepositoryError.invalidState("Numéro de téléphone invalide.") }
        pendingPhone = Self.phoneKey(phone)
        pendingApple = false
    }

    func verifyOTP(phone: String, code: String) throws -> UserProfile? {
        guard code.filter(\.isNumber) == DemoIDs.otpCode else {
            throw RepositoryError.invalidState("Code incorrect. En mode démo, le code est \(DemoIDs.otpCode).")
        }
        let key = Self.phoneKey(phone)
        if let id = phones[key], let p = users[id] {
            me = id; pendingPhone = nil
            return p
        }
        pendingPhone = key
        pendingApple = false
        return nil
    }

    func signInWithApple() throws -> UserProfile? {
        if let id = appleUser, let p = users[id] { me = id; return p }
        pendingApple = true
        pendingPhone = nil
        return nil
    }

    func completeSignup(_ input: SignupProfileInput) throws -> UserProfile {
        let first = input.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = input.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty else { throw RepositoryError.invalidState("Indique ton prénom.") }
        guard username.count >= 3 else { throw RepositoryError.invalidState("Ton pseudo doit faire au moins 3 caractères.") }
        guard input.isAdultConfirmed else { throw RepositoryError.invalidState("Tu dois confirmer avoir 18 ans ou plus.") }
        if users.values.contains(where: { $0.username.lowercased() == username.lowercased() }) {
            throw RepositoryError.invalidState("Ce pseudo est déjà pris.")
        }
        let id = UUID()
        let profile = UserProfile(id: id, username: username, firstName: first, city: input.city,
                                  district: input.district.trimmingCharacters(in: .whitespacesAndNewlines),
                                  avatarURL: nil, verified: false, rating: 0, salesCount: 0,
                                  memberSince: .now, responseTimeMinutes: nil)
        users[id] = profile
        var prefs = UserPreferences()
        prefs.isAdultConfirmed = true
        preferences[id] = prefs
        if let phone = pendingPhone { phones[phone] = id }
        if pendingApple { appleUser = id }
        pendingPhone = nil; pendingApple = false
        me = id
        return profile
    }

    func signOut() { me = nil }

    func loadPreferences() throws -> UserPreferences {
        let me = try requireMe()
        return preferences[me] ?? UserPreferences()
    }

    func savePreferences(_ prefs: UserPreferences) throws {
        let me = try requireMe()
        preferences[me] = prefs
    }

    // MARK: Catalog

    private static func matches(_ l: Listing, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let haystack = [l.title, l.brand] + l.tags
        return haystack.contains { $0.range(of: q, options: opts) != nil }
    }

    /// Stable partition: items in the preferred categories first, original order kept otherwise.
    private static func preferredFirst(_ items: [Listing], _ prefs: UserPreferences?) -> [Listing] {
        guard let cats = prefs?.categories, !cats.isEmpty else { return items }
        return items.filter { cats.contains($0.gender) } + items.filter { !cats.contains($0.gender) }
    }

    private static func passes(_ l: Listing, _ f: ListingFilters) -> Bool {
        if l.status != .active { return false }
        if let g = f.gender, l.gender != g { return false }
        if !matches(l, query: f.query) { return false }
        if l.price < f.priceMin || l.price > f.priceMax { return false }
        if !f.conditions.isEmpty && !f.conditions.contains(l.condition) { return false }
        if !f.brands.isEmpty && !f.brands.contains(l.brand) { return false }
        if f.negotiableOnly && !l.negotiable { return false }
        return true
    }

    func feed(filters f: ListingFilters, preferences prefs: UserPreferences?) -> [Listing] {
        var out = items.filter { Self.passes($0, f) }
        switch f.sort {
        case .recent:
            out.sort { $0.createdAt > $1.createdAt }
            if f.gender == nil { out = Self.preferredFirst(out, prefs) }
        case .priceAsc: out.sort { $0.price < $1.price }
        case .priceDesc: out.sort { $0.price > $1.price }
        case .popular: out.sort { $0.views > $1.views }
        }
        return out
    }

    func swipeDeck(preferences prefs: UserPreferences?) -> [Listing] {
        let done = me.flatMap { swiped[$0] } ?? []
        let deck = items
            .filter { $0.status == .active && $0.sellerId != me && !done.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
        return Self.preferredFirst(deck, prefs)
    }

    func listing(id: UUID) throws -> Listing {
        guard let l = items.first(where: { $0.id == id }) else { throw RepositoryError.notFound }
        return l
    }

    func listings(sellerId: UUID) -> [Listing] {
        items.filter { $0.sellerId == sellerId && $0.status != .removed }.sorted { $0.createdAt > $1.createdAt }
    }

    func profile(id: UUID) throws -> UserProfile {
        guard let p = users[id] else { throw RepositoryError.notFound }
        return p
    }

    func profiles(ids: [UUID]) -> [UUID: UserProfile] {
        var out: [UUID: UserProfile] = [:]
        for id in ids { if let p = users[id] { out[id] = p } }
        return out
    }

    func recordView(listingId: UUID) {
        guard let i = index(ofListing: listingId), items[i].sellerId != me else { return }
        items[i].views += 1
    }

    func nextDropDate() -> Date {
        if let d = dropDate { return d }
        let d = Date.now.addingTimeInterval(2 * 3_600 + 14 * 60)
        dropDate = d
        return d
    }

    private func index(ofListing id: UUID) -> Int? { items.firstIndex { $0.id == id } }

    // MARK: Wishlist & swipe

    func wishlistIds() throws -> Set<UUID> {
        let me = try requireMe()
        return wishlists[me] ?? []
    }

    func setLiked(listingId: UUID, liked: Bool) throws {
        let me = try requireMe()
        guard let i = index(ofListing: listingId) else { throw RepositoryError.notFound }
        var set = wishlists[me] ?? []
        let changed = liked ? set.insert(listingId).inserted : (set.remove(listingId) != nil)
        wishlists[me] = set
        if changed { items[i].favoritesCount = max(0, items[i].favoritesCount + (liked ? 1 : -1)) }
    }

    func recordSwipe(listingId: UUID, liked: Bool) throws {
        let me = try requireMe()
        swiped[me, default: []].insert(listingId)
        if liked { try setLiked(listingId: listingId, liked: true) }
    }

    // MARK: Selling

    func publish(_ draft: ListingDraft) throws -> Listing {
        let me = try requireMe()
        guard let profile = users[me] else { throw RepositoryError.notAuthenticated }
        guard !draft.photos.isEmpty else { throw RepositoryError.invalidState("Ajoute au moins une photo.") }
        guard let gender = draft.gender else { throw RepositoryError.invalidState("Choisis une catégorie.") }
        guard let sizeType = draft.sizeType else { throw RepositoryError.invalidState("Choisis une taille.") }
        guard let condition = draft.condition else { throw RepositoryError.invalidState("Indique l'état de l'article.") }
        guard draft.price > 0 else { throw RepositoryError.invalidState("Indique un prix.") }
        guard !draft.delivery.isEmpty else { throw RepositoryError.invalidState("Choisis au moins un mode de remise.") }

        let id = UUID()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("refripe-demo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var photos: [ListingPhoto] = []
        for (n, data) in draft.photos.enumerated() {
            let url = dir.appendingPathComponent("\(id.uuidString)-\(n).jpg")
            do { try data.write(to: url, options: .atomic) } catch {
                throw RepositoryError.invalidState("Impossible d'enregistrer la photo \(n + 1).")
            }
            photos.append(ListingPhoto(url: url))
        }

        let brand = draft.resolvedBrand.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let defect = draft.defectComment.trimmingCharacters(in: .whitespacesAndNewlines)
        let sizeValue = draft.sizeValue ?? sizeType.options.first ?? ""
        let listing = Listing(
            id: id, sellerId: me,
            title: title.isEmpty ? [gender.label, brand].filter { !$0.isEmpty }.joined(separator: " · ") : title,
            description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
            price: draft.price, oldPrice: nil,
            sizeType: sizeType, sizeLabel: sizeType.displayLabel(for: sizeValue),
            gender: gender, condition: condition,
            brand: brand.isEmpty ? "Sans marque précise" : brand,
            color: draft.color ?? "",
            tags: [brand, draft.color ?? ""].filter { !$0.isEmpty },
            city: profile.city, district: profile.district.isEmpty ? profile.city : profile.district,
            photos: photos, defectComment: defect.isEmpty ? nil : defect,
            views: 0, favoritesCount: 0, isLastPiece: false,
            negotiable: draft.negotiable, minOffer: draft.negotiable ? min(draft.minOffer, draft.price) : nil,
            deliveryMethods: DeliveryMethod.allCases.filter { draft.delivery.contains($0) },
            status: .active, createdAt: .now)
        items.insert(listing, at: 0)
        return listing
    }

    func updatePrice(listingId: UUID, price: FCFA) throws -> Listing {
        let me = try requireMe()
        guard let i = index(ofListing: listingId) else { throw RepositoryError.notFound }
        guard items[i].sellerId == me else { throw RepositoryError.invalidState("Seule la vendeuse peut modifier le prix.") }
        guard price > 0 else { throw RepositoryError.invalidState("Indique un prix valide.") }
        var l = items[i]
        let reference = max(l.oldPrice ?? 0, l.price)
        l.oldPrice = price < reference ? reference : nil
        l.price = price
        if let floor = l.minOffer { l.minOffer = min(floor, price) }
        items[i] = l
        return l
    }

    // MARK: Negotiation

    func offerThread(listingId: UUID) throws -> OfferThread? {
        let me = try requireMe()
        return threads.last { $0.listingId == listingId && $0.buyerId == me }
    }

    func offerThreads(role: OrderRole) throws -> [OfferThread] {
        let me = try requireMe()
        return threads
            .filter { role == .buyer ? $0.buyerId == me : $0.sellerId == me }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func makeOffer(listingId: UUID, amount: FCFA) throws -> OfferThread {
        let me = try requireMe()
        let l = try listing(id: listingId)
        guard l.sellerId != me else { throw RepositoryError.invalidState("Tu ne peux pas faire d'offre sur ton propre article.") }
        guard l.status == .active else { throw RepositoryError.invalidState("Cet article n'est plus disponible.") }
        guard l.negotiable else { throw RepositoryError.invalidState("Cette vendeuse n'accepte pas les offres sur cet article.") }
        guard amount > 0 else { throw RepositoryError.invalidState("Indique un montant.") }
        guard amount < l.price else { throw RepositoryError.invalidState("Ton offre doit être inférieure au prix affiché (\(Fmt.fcfa(l.price))).") }

        let now = Date.now
        var thread: OfferThread
        if let i = threads.lastIndex(where: { $0.listingId == listingId && $0.buyerId == me }) {
            thread = threads[i]
            switch thread.status {
            case .accepted: throw RepositoryError.invalidState("Ton offre a déjà été acceptée : tu peux passer au paiement.")
            case .refused, .expired: throw RepositoryError.offerLimitReached
            case .pending: break
            }
            guard thread.buyerOfferCount < OfferRules.maxBuyerOffers else { throw RepositoryError.offerLimitReached }
            if thread.rounds.last?.by == .buyer {
                throw RepositoryError.invalidState("Attends la réponse de la vendeuse avant de refaire une offre.")
            }
            thread.rounds.append(OfferRound(by: .buyer, amount: amount, action: .offer, at: now))
            thread.updatedAt = now
            threads[i] = thread
        } else {
            thread = OfferThread(id: UUID(), listingId: listingId, buyerId: me, sellerId: l.sellerId,
                                 rounds: [OfferRound(by: .buyer, amount: amount, action: .offer, at: now)],
                                 status: .pending, updatedAt: now)
            threads.append(thread)
        }
        let threadId = thread.id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await self.simulateSellerAnswer(threadId: threadId)
        }
        return thread
    }

    private func simulateSellerAnswer(threadId: UUID) async {
        guard let i = threads.firstIndex(where: { $0.id == threadId }),
              threads[i].status == .pending, threads[i].rounds.last?.by == .buyer,
              let l = items.first(where: { $0.id == threads[i].listingId }) else { return }
        let (action, amount) = OfferRules.simulatedSellerResponse(listing: l, thread: threads[i])
        let now = Date.now
        threads[i].rounds.append(OfferRound(by: .seller, amount: amount, action: action, at: now))
        threads[i].updatedAt = now
        switch action {
        case .accept: threads[i].status = .accepted
        case .refuse: threads[i].status = .refused
        default: threads[i].status = .pending
        }
        let seller = users[l.sellerId]?.username ?? "La vendeuse"
        let (title, body): (String, String) = switch action {
        case .accept: ("Offre acceptée", "\(seller) a accepté ton offre de \(Fmt.fcfa(amount)) pour \(l.title)")
        case .refuse: ("Offre refusée", "\(seller) a refusé ton offre pour \(l.title)")
        default: ("Contre-offre reçue", "\(seller) te propose \(Fmt.fcfa(amount)) pour \(l.title)")
        }
        notify(threads[i].buyerId, AppNotification(id: UUID(), kind: .counterOffer, title: title, body: body,
                                                    createdAt: now, read: false, listingId: l.id))
    }

    func respondToOffer(threadId: UUID, action: OfferAction, amount: FCFA?) throws -> OfferThread {
        let me = try requireMe()
        guard let i = threads.firstIndex(where: { $0.id == threadId }) else { throw RepositoryError.notFound }
        var t = threads[i]
        guard t.sellerId == me else { throw RepositoryError.invalidState("Seule la vendeuse peut répondre à cette offre.") }
        guard t.status == .pending, let last = t.lastBuyerOffer, t.rounds.last?.by == .buyer else {
            throw RepositoryError.invalidState("Aucune offre en attente de réponse.")
        }
        let l = try listing(id: t.listingId)
        let now = Date.now
        switch action {
        case .accept:
            t.rounds.append(OfferRound(by: .seller, amount: last.amount, action: .accept, at: now))
            t.status = .accepted
        case .refuse:
            t.rounds.append(OfferRound(by: .seller, amount: last.amount, action: .refuse, at: now))
            t.status = .refused
        case .counter:
            guard let amount, amount > last.amount, amount < l.price else {
                throw RepositoryError.invalidState("Ta contre-offre doit être entre \(Fmt.fcfa(last.amount)) et \(Fmt.fcfa(l.price)).")
            }
            t.rounds.append(OfferRound(by: .seller, amount: amount, action: .counter, at: now))
        case .offer:
            throw RepositoryError.invalidState("Action invalide.")
        }
        t.updatedAt = now
        threads[i] = t
        if t.status == .pending {
            Task {
                try? await Task.sleep(for: .seconds(2))
                await self.simulateBuyerAnswer(threadId: threadId)
            }
        }
        return t
    }

    /// Demo buyer bot (when the signed-in user is the seller): accepts a close counter, else meets halfway.
    private func simulateBuyerAnswer(threadId: UUID) async {
        guard let i = threads.firstIndex(where: { $0.id == threadId }),
              threads[i].status == .pending,
              let counter = threads[i].rounds.last, counter.by == .seller, counter.action == .counter,
              let l = items.first(where: { $0.id == threads[i].listingId }) else { return }
        let step = OfferRules.step(for: l.price)
        let lastBuyer = threads[i].lastBuyerOffer?.amount ?? 0
        let now = Date.now
        if counter.amount - lastBuyer <= 2 * step || threads[i].buyerOfferCount >= OfferRules.maxBuyerOffers {
            threads[i].rounds.append(OfferRound(by: .buyer, amount: counter.amount, action: .accept, at: now))
            threads[i].status = .accepted
        } else {
            let mid = OfferRules.round(Double(lastBuyer + counter.amount) / 2, step: step)
            threads[i].rounds.append(OfferRound(by: .buyer, amount: min(mid, counter.amount - step), action: .offer, at: now))
        }
        threads[i].updatedAt = now
    }

    // MARK: Orders

    func createOrder(listingId: UUID, delivery: DeliveryMethod, payment: PaymentMethod) throws -> Order {
        let me = try requireMe()
        guard let i = index(ofListing: listingId) else { throw RepositoryError.notFound }
        let l = items[i]
        guard l.sellerId != me else { throw RepositoryError.invalidState("Tu ne peux pas acheter ton propre article.") }
        guard l.status == .active else { throw RepositoryError.invalidState("Cet article n'est plus disponible.") }
        guard l.deliveryMethods.contains(delivery) else {
            throw RepositoryError.invalidState("Ce mode de remise n'est pas proposé par la vendeuse.")
        }
        let accepted = threads.last { $0.listingId == listingId && $0.buyerId == me }?.acceptedAmount
        let now = Date.now
        let order = Order(id: UUID(), listingId: l.id, listingTitle: l.title, listingPhoto: l.photos.first,
                          sellerId: l.sellerId, buyerId: me, buyerName: users[me]?.firstName ?? "Moi",
                          itemPrice: accepted ?? l.price, deliveryFee: delivery.fee, delivery: delivery, payment: payment,
                          status: .paymentPending, history: [OrderEvent(status: .paymentPending, at: now)], createdAt: now)
        allOrders.insert(order, at: 0)
        items[i].status = .reserved
        let orderId = order.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await self.simulatePayment(orderId: orderId)
        }
        return order
    }

    /// PAYMENT_PENDING → PAID → AWAITING_SHIPMENT (escrow funded).
    private func simulatePayment(orderId: UUID) async {
        guard let i = allOrders.firstIndex(where: { $0.id == orderId }), allOrders[i].status == .paymentPending else { return }
        let now = Date.now
        allOrders[i].status = .paid
        allOrders[i].history.append(OrderEvent(status: .paid, at: now))
        notify(allOrders[i].buyerId, AppNotification(
            id: UUID(), kind: .orderUpdate, title: "Paiement confirmé",
            body: "\(Fmt.fcfa(allOrders[i].total)) bloqués en séquestre pour \(allOrders[i].listingTitle)",
            createdAt: now, read: false, listingId: allOrders[i].listingId, orderId: orderId))
        try? await Task.sleep(for: .seconds(0.8))
        guard let j = allOrders.firstIndex(where: { $0.id == orderId }), allOrders[j].status == .paid else { return }
        allOrders[j].status = .awaitingShipment
        allOrders[j].history.append(OrderEvent(status: .awaitingShipment, at: .now))
    }

    func orders(role: OrderRole) throws -> [Order] {
        let me = try requireMe()
        return allOrders
            .filter { role == .buyer ? $0.buyerId == me : $0.sellerId == me }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func order(id: UUID) throws -> Order {
        guard let o = allOrders.first(where: { $0.id == id }) else { throw RepositoryError.notFound }
        return o
    }

    private static func canMove(from: OrderStatus, to: OrderStatus) -> Bool {
        let path = OrderStatus.happyPath
        if let a = path.firstIndex(of: from), let b = path.firstIndex(of: to), b == a + 1 { return true }
        switch to {
        case .cancelled: return [.paymentPending, .paid, .awaitingShipment].contains(from)
        case .disputed: return [.shipped, .delivered, .buyerValidation].contains(from)
        case .returnPending: return [.delivered, .buyerValidation, .disputed].contains(from)
        case .refunded: return [.disputed, .returnPending, .cancelled].contains(from)
        case .completed: return from == .disputed          // mediation settled in the seller's favour
        default: return false
        }
    }

    func advanceOrder(id: UUID, to status: OrderStatus) throws -> Order {
        let me = try requireMe()
        guard let i = allOrders.firstIndex(where: { $0.id == id }) else { throw RepositoryError.notFound }
        guard allOrders[i].buyerId == me || allOrders[i].sellerId == me else { throw RepositoryError.notFound }
        let from = allOrders[i].status
        guard Self.canMove(from: from, to: status) else {
            throw RepositoryError.invalidState("Impossible de passer de « \(from.label) » à « \(status.label) ».")
        }
        allOrders[i].status = status
        allOrders[i].history.append(OrderEvent(status: status, at: .now))
        if let li = index(ofListing: allOrders[i].listingId) {
            switch status {
            case .completed: items[li].status = .sold
            case .cancelled, .refunded: items[li].status = .active
            default: break
            }
        }
        return allOrders[i]
    }

    // MARK: Messaging

    private func project(_ c: DemoConversation, for me: UUID) -> Conversation {
        let last = messagesByConv[c.id]?.last
        return Conversation(id: c.id, listingId: c.listingId, otherUserId: c.other(than: me),
                            lastMessage: last?.text ?? "", lastMessageAt: last?.sentAt ?? .now,
                            unreadCount: c.unread[me] ?? 0)
    }

    func conversations() throws -> [Conversation] {
        let me = try requireMe()
        return convs
            .filter { $0.members.contains(me) && !(messagesByConv[$0.id] ?? []).isEmpty }
            .map { project($0, for: me) }
            .sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    func messages(conversationId: UUID) throws -> [ChatMessage] {
        let me = try requireMe()
        guard let c = convs.first(where: { $0.id == conversationId }), c.members.contains(me) else { throw RepositoryError.notFound }
        return (messagesByConv[conversationId] ?? []).sorted { $0.sentAt < $1.sentAt }
    }

    func send(text: String, conversationId: UUID) throws -> ChatMessage {
        let me = try requireMe()
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw RepositoryError.invalidState("Message vide.") }
        guard let i = convs.firstIndex(where: { $0.id == conversationId }), convs[i].members.contains(me) else {
            throw RepositoryError.notFound
        }
        let msg = ChatMessage(id: UUID(), conversationId: conversationId, senderId: me, text: body, sentAt: .now)
        messagesByConv[conversationId, default: []].append(msg)
        let other = convs[i].other(than: me)
        convs[i].unread[other, default: 0] += 1
        Task {
            try? await Task.sleep(for: .seconds(2))
            await self.simulateReply(conversationId: conversationId, from: other, to: me, prompt: body)
        }
        return msg
    }

    private static func cannedReply(to prompt: String) -> String {
        let p = prompt.lowercased()
        if p.contains("prix") || p.contains("dernier") || p.contains("moins") {
            return "Je peux faire un petit geste. Fais-moi une offre directement sur l'annonce."
        }
        if p.contains("dispo") { return "Oui, toujours disponible !" }
        if p.contains("photo") { return "Je t'envoie ça dès que je peux." }
        if p.contains("livr") || p.contains("relais") || p.contains("récup") {
            return "Le point relais c'est le plus simple, sinon on peut se voir à Cocody."
        }
        if p.contains("merci") { return "Avec plaisir, bonne journée !" }
        return ["D'accord, je regarde et je te redis.", "Ça marche !", "Merci pour ton message, je reviens vers toi vite."]
            .randomElement()!
    }

    private func simulateReply(conversationId: UUID, from other: UUID, to me: UUID, prompt: String) async {
        guard let i = convs.firstIndex(where: { $0.id == conversationId }) else { return }
        let now = Date.now
        let reply = ChatMessage(id: UUID(), conversationId: conversationId, senderId: other,
                                text: Self.cannedReply(to: prompt), sentAt: now)
        messagesByConv[conversationId, default: []].append(reply)
        convs[i].unread[me, default: 0] += 1
        convs[i].unread[other] = 0
        let name = users[other]?.username ?? "Quelqu'un"
        notify(me, AppNotification(id: UUID(), kind: .message, title: "Nouveau message", body: "\(name) t'a répondu",
                                   createdAt: now, read: false, listingId: convs[i].listingId, conversationId: conversationId))
    }

    func conversation(withUser userId: UUID, listingId: UUID?) throws -> Conversation {
        let me = try requireMe()
        guard userId != me else { throw RepositoryError.invalidState("Tu ne peux pas t'écrire à toi-même.") }
        guard users[userId] != nil else { throw RepositoryError.notFound }
        if let c = convs.first(where: { Set($0.members) == [me, userId] && $0.listingId == listingId }) {
            return project(c, for: me)
        }
        let c = DemoConversation(id: UUID(), listingId: listingId, members: [me, userId], unread: [:])
        convs.append(c)
        return project(c, for: me)
    }

    func markConversationRead(id: UUID) throws {
        let me = try requireMe()
        guard let i = convs.firstIndex(where: { $0.id == id }) else { throw RepositoryError.notFound }
        convs[i].unread[me] = 0
    }

    // MARK: Notifications

    private func notify(_ user: UUID, _ n: AppNotification) {
        notifs[user, default: []].insert(n, at: 0)
    }

    func notifications() throws -> [AppNotification] {
        let me = try requireMe()
        return (notifs[me] ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    func markNotificationsRead() throws {
        let me = try requireMe()
        notifs[me] = (notifs[me] ?? []).map { var n = $0; n.read = true; return n }
    }
}
