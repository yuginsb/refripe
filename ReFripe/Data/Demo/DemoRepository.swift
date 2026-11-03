import Foundation

/// In-memory `Repository` seeded with the mockup data. Simulates the other side of the marketplace:
/// seller answers to offers (~1,5 s), payment confirmation (~4 s after `startPayment`), shipping by the
/// other seller (~8 s after payment), chat replies (~2 s).
/// All state lives in the `DemoState` actor, so this class is safely `Sendable`.
final class DemoRepository: Repository {
    private let state: DemoState

    /// - Parameters:
    ///   - clock: current date used by the business rules (2 h reservation, 72 h escrow). Injectable for tests.
    ///   - paymentDelay: seconds between `startPayment` and PAID.
    ///   - shipDelay: seconds after AWAITING_SHIPMENT before a simulated seller ships my purchase (nil = never).
    init(now: Date = .now, clock: @escaping @Sendable () -> Date = { Date() },
         paymentDelay: Double = 4, shipDelay: Double? = 8) {
        state = DemoState(seed: DemoSeed.make(now: now), clock: clock, paymentDelay: paymentDelay, shipDelay: shipDelay)
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
    func updateProfile(username: String, firstName: String, city: String, district: String) async throws -> UserProfile {
        try await state.updateProfile(username: username, firstName: firstName, city: city, district: district)
    }

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

    // MARK: v3
    func startPayment(orderId: UUID) async throws -> PaymentSession {
        await DemoState.latency(0.4)
        return try await state.startPayment(orderId: orderId)
    }
    func confirmHandoff(orderId: UUID, code: String) async throws -> Order { try await state.confirmHandoff(orderId: orderId, code: code) }
    func submitReview(orderId: UUID, rating: Int, comment: String) async throws -> Review {
        try await state.submitReview(orderId: orderId, rating: rating, comment: comment)
    }
    func reviews(userId: UUID) async throws -> [Review] { await state.reviews(userId: userId) }
    func sendPhoto(_ jpeg: Data, conversationId: UUID) async throws -> ChatMessage { try await state.sendPhoto(jpeg, conversationId: conversationId) }
    func report(listingId: UUID?, userId: UUID?, reason: ReportReason, details: String) async throws {
        try await state.report(listingId: listingId, userId: userId, reason: reason, details: details)
    }
    func block(userId: UUID) async throws { try await state.block(userId: userId) }
    func unblock(userId: UUID) async throws { try await state.unblock(userId: userId) }
    func blockedUserIds() async throws -> Set<UUID> { try await state.blockedUserIds() }
    func deleteAccount() async throws {
        await DemoState.latency(0.5)
        try await state.deleteAccount()
    }
}

/// A report filed through `report(...)` (kept in memory in demo mode).
struct DemoReport: Hashable {
    var reporterId: UUID
    var listingId: UUID?
    var userId: UUID?
    var reason: ReportReason
    var details: String
    var createdAt: Date
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
    // v3
    private var allReviews: [Review]
    private var blocks: [UUID: Set<UUID>] = [:]
    private(set) var reports: [DemoReport] = []
    private var paymentsStarted: Set<UUID> = []
    private let clock: @Sendable () -> Date
    private let paymentDelay: Double
    private let shipDelay: Double?
    let stats: SellerStats
    let recommendations: [SellerRecommendation]

    init(seed: DemoSeed, clock: @escaping @Sendable () -> Date = { Date() },
         paymentDelay: Double = 4, shipDelay: Double? = 8) {
        self.clock = clock
        self.paymentDelay = paymentDelay
        self.shipDelay = shipDelay
        allReviews = seed.reviews
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

    func updateProfile(username: String, firstName: String, city: String, district: String) throws -> UserProfile {
        let me = try requireMe()
        guard var p = users[me] else { throw RepositoryError.notFound }
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let handle = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty else { throw RepositoryError.invalidState("Indique ton prénom.") }
        guard handle.count >= 3 else { throw RepositoryError.invalidState("Ton pseudo doit faire au moins 3 caractères.") }
        if users.values.contains(where: { $0.id != me && $0.username.lowercased() == handle.lowercased() }) {
            throw RepositoryError.invalidState("Ce pseudo est déjà pris.")
        }
        p.username = handle
        p.firstName = first
        p.city = city
        p.district = district.trimmingCharacters(in: .whitespacesAndNewlines)
        users[me] = p
        return p
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
        // "15 000 +": the top of the slider means no upper bound.
        if l.price < f.priceMin || (f.priceMax < ListingFilters.catalogMaxPrice && l.price > f.priceMax) { return false }
        if !f.conditions.isEmpty && !f.conditions.contains(l.condition) { return false }
        if !f.brands.isEmpty && !f.brands.contains(l.brand) { return false }
        if f.negotiableOnly && !l.negotiable { return false }
        if !f.itemTypes.isEmpty && !f.itemTypes.contains(l.itemType) { return false }
        if !l.matchesSize(f.sizes) { return false }
        if !f.districts.isEmpty {
            let mine = l.district.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let wanted = f.districts.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
            if !wanted.contains(mine) { return false }
        }
        return true
    }

    /// Sellers whose listings I must not see: me (own listings are not in my feed) and blocked members.
    private func hiddenSellers() -> Set<UUID> {
        guard let me else { return [] }
        var hidden = blocks[me] ?? []
        hidden.insert(me)
        // A member who blocked me doesn't show up either.
        for (blocker, blocked) in blocks where blocked.contains(me) { hidden.insert(blocker) }
        return hidden
    }

    /// What the signed-in user may see of a listing: `minOffer` is the seller's private floor,
    /// and an expired reservation is cleared.
    private func visible(_ l: Listing) -> Listing {
        var out = l
        if out.sellerId != me { out.minOffer = nil }
        if let until = out.reservedUntil, until <= clock() {
            out.reservedUntil = nil
            out.reservedFor = nil
        }
        return out
    }

    func feed(filters f: ListingFilters, preferences prefs: UserPreferences?) -> [Listing] {
        let hidden = hiddenSellers()
        var out = items.filter { !hidden.contains($0.sellerId) && Self.passes($0, f) }
        switch f.sort {
        case .recent:
            out.sort { $0.createdAt > $1.createdAt }
            if f.gender == nil { out = Self.preferredFirst(out, prefs) }
        case .priceAsc: out.sort { $0.price < $1.price }
        case .priceDesc: out.sort { $0.price > $1.price }
        case .popular: out.sort { $0.views > $1.views }
        }
        return out.map { visible($0) }
    }

    func swipeDeck(preferences prefs: UserPreferences?) -> [Listing] {
        let done = me.flatMap { swiped[$0] } ?? []
        let hidden = hiddenSellers()
        let deck = items
            .filter { $0.status == .active && $0.sellerId != me && !hidden.contains($0.sellerId) && !done.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
        return Self.preferredFirst(deck, prefs).map { visible($0) }
    }

    func listing(id: UUID) throws -> Listing {
        guard let l = items.first(where: { $0.id == id }) else { throw RepositoryError.notFound }
        return visible(l)
    }

    func listings(sellerId: UUID) -> [Listing] {
        items.filter { $0.sellerId == sellerId && $0.status != .removed }
            .sorted { $0.createdAt > $1.createdAt }
            .map { visible($0) }
    }

    /// Raw (unprojected) listing, for internal rules.
    private func rawListing(_ id: UUID) throws -> Listing {
        guard let l = items.first(where: { $0.id == id }) else { throw RepositoryError.notFound }
        return l
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
            title: title.isEmpty ? [draft.itemType?.label ?? gender.label, brand].filter { !$0.isEmpty }.joined(separator: " · ") : title,
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
            negotiable: draft.negotiable,
            minOffer: draft.negotiable && draft.minOffer > 0 ? min(draft.minOffer, draft.price) : nil,
            deliveryMethods: DeliveryMethod.allCases.filter { draft.delivery.contains($0) },
            status: .active, createdAt: clock(), itemType: draft.itemType ?? .autre)
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

    /// v3: an accepted offer reserves the item 2 h for the buyer (unless it is already held by someone else).
    private func reserve(listingId: UUID, for buyer: UUID, at date: Date) {
        guard let i = index(ofListing: listingId), !items[i].isReserved(forSomeoneOtherThan: buyer, at: date) else { return }
        items[i].reservedUntil = date.addingTimeInterval(Catalog.reservationDuration)
        items[i].reservedFor = buyer
    }

    private func username(_ id: UUID, fallback: String) -> String { users[id]?.username ?? fallback }

    func makeOffer(listingId: UUID, amount: FCFA) throws -> OfferThread {
        let me = try requireMe()
        let l = try rawListing(listingId)
        guard l.sellerId != me else { throw RepositoryError.invalidState("Tu ne peux pas faire d'offre sur ton propre article.") }
        guard l.status == .active else { throw RepositoryError.invalidState("Cet article n'est plus disponible.") }
        guard l.negotiable else { throw RepositoryError.invalidState("Cette vendeuse n'accepte pas les offres sur cet article.") }
        guard amount > 0 else { throw RepositoryError.invalidState("Indique un montant.") }
        guard amount < l.price else { throw RepositoryError.invalidState("Ton offre doit être inférieure au prix affiché (\(Fmt.fcfa(l.price))).") }

        let now = clock()
        var thread: OfferThread
        if let i = threads.lastIndex(where: { $0.listingId == listingId && $0.buyerId == me }) {
            thread = threads[i]
            switch thread.status {
            case .accepted: throw RepositoryError.invalidState("Ton offre a déjà été acceptée : tu peux passer au paiement.")
            case .refused, .expired: throw RepositoryError.invalidState("La vendeuse a décliné ton offre. Tu peux toujours acheter au prix affiché.")
            case .pending: break
            }
            guard thread.buyerOfferCount < OfferRules.maxBuyerOffers else { throw RepositoryError.offerLimitReached }
            if thread.rounds.last?.by == .buyer {
                throw RepositoryError.invalidState("Attends la réponse de la vendeuse avant de refaire une offre.")
            }
            // Same rule as the Supabase `make_offer` RPC: a new offer must beat the buyer's previous one.
            if let previous = thread.lastBuyerOffer?.amount, amount <= previous {
                throw RepositoryError.invalidState("Ta nouvelle offre doit dépasser la précédente (\(Fmt.fcfa(previous))).")
            }
            // Same rule as the Supabase `make_offer` RPC: meeting the seller's pending counter accepts it.
            if let counter = thread.rounds.last, counter.by == .seller, counter.action == .counter, amount >= counter.amount {
                if l.isReserved(forSomeoneOtherThan: me, at: now), let until = l.reservedUntil {
                    throw RepositoryError.invalidState("Article déjà réservé pour une autre acheteuse jusqu'à \(Fmt.hourMinute(until)).")
                }
                thread.rounds.append(OfferRound(by: .buyer, amount: counter.amount, action: .accept, at: now))
                thread.status = .accepted
                thread.updatedAt = now
                threads[i] = thread
                reserve(listingId: listingId, for: me, at: now)
                notify(l.sellerId, AppNotification(
                    id: UUID(), kind: .offerAccepted, title: "Contre-offre acceptée",
                    body: "\(username(me, fallback: "L'acheteuse")) accepte \(Fmt.fcfa(counter.amount)) pour \(l.title)",
                    createdAt: now, read: false, listingId: l.id))
                return thread
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
        notify(l.sellerId, AppNotification(
            id: UUID(), kind: .offerReceived, title: "Nouvelle offre",
            body: "\(username(me, fallback: "Une acheteuse")) propose \(Fmt.fcfa(amount)) pour \(l.title)",
            createdAt: now, read: false, listingId: l.id))
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
        let now = clock()
        threads[i].rounds.append(OfferRound(by: .seller, amount: amount, action: action, at: now))
        threads[i].updatedAt = now
        switch action {
        case .accept:
            threads[i].status = .accepted
            reserve(listingId: l.id, for: threads[i].buyerId, at: now)
        case .refuse: threads[i].status = .refused
        default: threads[i].status = .pending
        }
        notifyBuyerOfSellerAnswer(threads[i], listing: l, action: action, amount: amount, at: now)
    }

    private func notifyBuyerOfSellerAnswer(_ t: OfferThread, listing l: Listing, action: OfferAction, amount: FCFA, at now: Date) {
        let seller = username(l.sellerId, fallback: "La vendeuse")
        let (kind, title, body): (NotificationKind, String, String) = switch action {
        case .accept: (.offerAccepted, "Offre acceptée",
                       "\(seller) a accepté ton offre de \(Fmt.fcfa(amount)) pour \(l.title). Article réservé pour toi \(Catalog.reservationHours) h.")
        case .refuse: (.offerRefused, "Offre refusée", "\(seller) a refusé ton offre pour \(l.title)")
        default: (.counterOffer, "Contre-offre reçue", "\(seller) te propose \(Fmt.fcfa(amount)) pour \(l.title)")
        }
        notify(t.buyerId, AppNotification(id: UUID(), kind: kind, title: title, body: body,
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
        let l = try rawListing(t.listingId)
        let now = clock()
        switch action {
        case .accept:
            if l.isReserved(forSomeoneOtherThan: t.buyerId, at: now), let until = l.reservedUntil {
                throw RepositoryError.invalidState("Article déjà réservé pour une autre acheteuse jusqu'à \(Fmt.hourMinute(until)).")
            }
            t.rounds.append(OfferRound(by: .seller, amount: last.amount, action: .accept, at: now))
            t.status = .accepted
            reserve(listingId: l.id, for: t.buyerId, at: now)
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
        if let answer = t.rounds.last {
            notifyBuyerOfSellerAnswer(t, listing: l, action: answer.action, amount: answer.amount, at: now)
        }
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
        let now = clock()
        let buyer = username(threads[i].buyerId, fallback: "L'acheteuse")
        if counter.amount - lastBuyer <= 2 * step || threads[i].buyerOfferCount >= OfferRules.maxBuyerOffers {
            threads[i].rounds.append(OfferRound(by: .buyer, amount: counter.amount, action: .accept, at: now))
            threads[i].status = .accepted
            reserve(listingId: l.id, for: threads[i].buyerId, at: now)
            notify(l.sellerId, AppNotification(
                id: UUID(), kind: .offerAccepted, title: "Contre-offre acceptée",
                body: "\(buyer) accepte \(Fmt.fcfa(counter.amount)) pour \(l.title)",
                createdAt: now, read: false, listingId: l.id))
        } else {
            let mid = OfferRules.round(Double(lastBuyer + counter.amount) / 2, step: step)
            let amount = min(mid, counter.amount - step)
            threads[i].rounds.append(OfferRound(by: .buyer, amount: amount, action: .offer, at: now))
            notify(l.sellerId, AppNotification(
                id: UUID(), kind: .offerReceived, title: "Nouvelle offre",
                body: "\(buyer) propose \(Fmt.fcfa(amount)) pour \(l.title)",
                createdAt: now, read: false, listingId: l.id))
        }
        threads[i].updatedAt = now
    }

    // MARK: Orders

    /// What the signed-in user may see of an order: the hand-off code is the buyer's secret.
    private func visible(_ o: Order) -> Order {
        var out = o
        if out.buyerId != me { out.handoffCode = nil }
        return out
    }

    func createOrder(listingId: UUID, delivery: DeliveryMethod, payment: PaymentMethod) throws -> Order {
        let me = try requireMe()
        guard let i = index(ofListing: listingId) else { throw RepositoryError.notFound }
        let l = items[i]
        let now = clock()
        guard l.sellerId != me else { throw RepositoryError.invalidState("Tu ne peux pas acheter ton propre article.") }
        guard l.status == .active else { throw RepositoryError.invalidState("Cet article n'est plus disponible.") }
        if l.isReserved(forSomeoneOtherThan: me, at: now), let until = l.reservedUntil {
            throw RepositoryError.invalidState("Réservé pour une autre acheteuse jusqu'à \(Fmt.hourMinute(until)).")
        }
        if hiddenSellers().contains(l.sellerId) {
            throw RepositoryError.invalidState("Tu ne peux pas acheter à ce membre.")
        }
        guard l.deliveryMethods.contains(delivery) else {
            throw RepositoryError.invalidState("Ce mode de remise n'est pas proposé par la vendeuse.")
        }
        let accepted = threads.last { $0.listingId == listingId && $0.buyerId == me }?.acceptedAmount
        let order = Order(id: UUID(), listingId: l.id, listingTitle: l.title, listingPhoto: l.photos.first,
                          sellerId: l.sellerId, buyerId: me, buyerName: users[me]?.firstName ?? "Moi",
                          itemPrice: min(accepted ?? l.price, l.price), deliveryFee: delivery.fee, delivery: delivery, payment: payment,
                          status: .paymentPending, history: [OrderEvent(status: .paymentPending, at: now)], createdAt: now)
        allOrders.insert(order, at: 0)
        items[i].status = .reserved
        items[i].reservedUntil = nil
        items[i].reservedFor = nil
        // v3: payment only starts with `startPayment` (guided Wave / Orange Money screen).
        return visible(order)
    }

    /// "0707070707" → "07 07 •• •• 07" (number shown on the payment screen).
    static func maskedPhone(_ phone: String) -> String? {
        let digits = Array(phone.filter(\.isNumber).suffix(10))
        guard digits.count == 10 else { return nil }
        let pairs = stride(from: 0, to: 10, by: 2).map { String(digits[$0..<$0 + 2]) }
        return [pairs[0], pairs[1], "••", "••", pairs[4]].joined(separator: " ")
    }

    func startPayment(orderId: UUID) throws -> PaymentSession {
        let me = try requireMe()
        guard let i = allOrders.firstIndex(where: { $0.id == orderId }), allOrders[i].buyerId == me else {
            throw RepositoryError.notFound
        }
        let o = allOrders[i]
        guard o.status == .paymentPending else {
            throw RepositoryError.invalidState("Cette commande n'est plus en attente de paiement.")
        }
        let phone = phones.first { $0.value == me }?.key
        let token = o.id.uuidString.lowercased()
        let session = PaymentSession(
            orderId: o.id, method: o.payment, amount: o.total,
            checkoutURL: o.payment == .wave ? URL(string: "https://pay.wave.com/c/demo-\(token)") : nil,
            ussdCode: o.payment == .orangeMoney ? "#144*82#" : nil,
            maskedPhone: phone.flatMap { Self.maskedPhone($0) })
        if paymentsStarted.insert(o.id).inserted {
            let delay = paymentDelay
            Task {
                try? await Task.sleep(for: .seconds(delay))
                await self.simulatePayment(orderId: orderId)
            }
        }
        return session
    }

    /// PAYMENT_PENDING → PAID → AWAITING_SHIPMENT (escrow funded), then the other seller ships (demo bot).
    private func simulatePayment(orderId: UUID) async {
        guard let i = allOrders.firstIndex(where: { $0.id == orderId }), allOrders[i].status == .paymentPending else { return }
        let now = clock()
        let o = allOrders[i]
        allOrders[i].status = .paid
        allOrders[i].history.append(OrderEvent(status: .paid, at: now))
        let ref = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).uppercased()
        allOrders[i].paymentReference = "\(o.payment == .wave ? "WAVE" : "OM")-\(ref)"
        notify(o.buyerId, AppNotification(
            id: UUID(), kind: .orderUpdate, title: "Paiement confirmé",
            body: "\(Fmt.fcfa(o.total)) bloqués en séquestre pour \(o.listingTitle)",
            createdAt: now, read: false, listingId: o.listingId, orderId: orderId))
        notify(o.sellerId, AppNotification(
            id: UUID(), kind: .newSale, title: "Nouvelle vente",
            body: "\(o.listingTitle) a été payé (\(Fmt.fcfa(o.itemPrice))). Prépare la remise.",
            createdAt: now, read: false, listingId: o.listingId, orderId: orderId))
        try? await Task.sleep(for: .seconds(0.8))
        guard let j = allOrders.firstIndex(where: { $0.id == orderId }), allOrders[j].status == .paid else { return }
        allOrders[j].status = .awaitingShipment
        allOrders[j].history.append(OrderEvent(status: .awaitingShipment, at: clock()))
        guard let shipDelay, allOrders[j].sellerId != me else { return }
        try? await Task.sleep(for: .seconds(shipDelay))
        guard let k = allOrders.firstIndex(where: { $0.id == orderId }), allOrders[k].status == .awaitingShipment,
              allOrders[k].sellerId != me else { return }
        apply(.shipped, toOrderAt: k)
    }

    func orders(role: OrderRole) throws -> [Order] {
        let me = try requireMe()
        return allOrders
            .filter { role == .buyer ? $0.buyerId == me : $0.sellerId == me }
            .sorted { $0.createdAt > $1.createdAt }
            .map { visible($0) }
    }

    func order(id: UUID) throws -> Order {
        guard let o = allOrders.first(where: { $0.id == id }) else { throw RepositoryError.notFound }
        return visible(o)
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

    static func makeHandoffCode() -> String {
        let n = String(Int.random(in: 0..<10_000))
        return String(repeating: "0", count: max(0, Catalog.handoffCodeLength - n.count)) + n
    }

    /// Applies a status change and its side effects (history, hand-off code, escrow deadline, listing status,
    /// notifications). DELIVERED chains to BUYER_VALIDATION, like `private.transition_order` in SQL.
    private func apply(_ status: OrderStatus, toOrderAt i: Int) {
        let now = clock()
        allOrders[i].status = status
        allOrders[i].history.append(OrderEvent(status: status, at: now))
        let o = allOrders[i]
        switch status {
        case .shipped:
            allOrders[i].handoffCode = Self.makeHandoffCode()
            notify(o.buyerId, AppNotification(
                id: UUID(), kind: .orderUpdate, title: "Colis expédié",
                body: "\(o.listingTitle) est en route. Montre ton code de remise à la réception.",
                createdAt: now, read: false, listingId: o.listingId, orderId: o.id))
        case .delivered:
            allOrders[i].escrowReleaseAt = now.addingTimeInterval(TimeInterval(Catalog.escrowAutoReleaseHours * 3_600))
            allOrders[i].status = .buyerValidation
            allOrders[i].history.append(OrderEvent(status: .buyerValidation, at: now))
            notify(o.buyerId, AppNotification(
                id: UUID(), kind: .orderUpdate, title: "Confirme la réception",
                body: "\(o.listingTitle) t'a été remis. Sans réponse sous \(Catalog.escrowAutoReleaseHours) h, les fonds seront libérés.",
                createdAt: now, read: false, listingId: o.listingId, orderId: o.id))
        default: break
        }
        if let li = index(ofListing: o.listingId) {
            switch status {
            case .completed: items[li].status = .sold
            case .cancelled, .refunded: items[li].status = .active
            default: break
            }
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
        // v3: the hand-off is proven by the buyer's code (confirmHandoff), never declared by the seller alone.
        if status == .delivered && allOrders[i].sellerId == me {
            throw RepositoryError.invalidState("Saisis le code de remise de l'acheteuse pour confirmer la remise.")
        }
        if status == .shipped && allOrders[i].sellerId != me {
            throw RepositoryError.invalidState("Seule la vendeuse peut marquer la commande comme expédiée.")
        }
        apply(status, toOrderAt: i)
        return visible(allOrders[i])
    }

    func confirmHandoff(orderId: UUID, code: String) throws -> Order {
        let me = try requireMe()
        guard let i = allOrders.firstIndex(where: { $0.id == orderId }),
              allOrders[i].buyerId == me || allOrders[i].sellerId == me else { throw RepositoryError.notFound }
        guard allOrders[i].sellerId == me else {
            throw RepositoryError.invalidState("Le code se donne à la vendeuse, au point relais ou au coursier.")
        }
        guard allOrders[i].status == .shipped else {
            throw RepositoryError.invalidState("Cette commande n'attend pas de remise (« \(allOrders[i].status.label) »).")
        }
        let typed = code.filter(\.isNumber)
        guard let expected = allOrders[i].handoffCode, typed == expected else {
            throw RepositoryError.invalidState("Code incorrect. Demande à l'acheteuse son code à \(Catalog.handoffCodeLength) chiffres.")
        }
        apply(.delivered, toOrderAt: i)
        return visible(allOrders[i])
    }

    // MARK: Reviews

    func submitReview(orderId: UUID, rating: Int, comment: String) throws -> Review {
        let me = try requireMe()
        guard let o = allOrders.first(where: { $0.id == orderId }), o.buyerId == me || o.sellerId == me else {
            throw RepositoryError.notFound
        }
        guard o.buyerId == me else { throw RepositoryError.invalidState("Seule l'acheteuse peut noter la vendeuse.") }
        guard o.status == .completed else {
            throw RepositoryError.invalidState("Tu pourras noter la vendeuse une fois la commande terminée.")
        }
        guard (1...5).contains(rating) else { throw RepositoryError.invalidState("Choisis une note de 1 à 5 étoiles.") }
        guard !allReviews.contains(where: { $0.orderId == orderId && $0.reviewerId == me }) else {
            throw RepositoryError.invalidState("Tu as déjà noté cette commande.")
        }
        let text = String(comment.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        let review = Review(id: UUID(), orderId: orderId, reviewerId: me, revieweeId: o.sellerId,
                            rating: rating, comment: text, createdAt: clock())
        allReviews.append(review)
        if var seller = users[o.sellerId] {
            // Running average over the seller's (aggregate) review count, same result as the SQL trigger.
            let count = max(0, seller.reviewCount)
            let total = seller.rating * Double(count) + Double(rating)
            seller.reviewCount = count + 1
            seller.rating = min(5, max(0, total / Double(count + 1)))
            users[o.sellerId] = seller
        }
        return review
    }

    func reviews(userId: UUID) -> [Review] {
        allReviews.filter { $0.revieweeId == userId }.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: Messaging

    private func project(_ c: DemoConversation, for me: UUID) -> Conversation {
        let last = messagesByConv[c.id]?.last
        let preview = (last?.text.isEmpty ?? false) && last?.photo != nil ? "Photo" : (last?.text ?? "")
        return Conversation(id: c.id, listingId: c.listingId, otherUserId: c.other(than: me),
                            lastMessage: preview, lastMessageAt: last?.sentAt ?? clock(),
                            unreadCount: c.unread[me] ?? 0)
    }

    /// Blocked either way (I blocked them, or they blocked me).
    private func isBlocked(between a: UUID, and b: UUID) -> Bool {
        (blocks[a]?.contains(b) ?? false) || (blocks[b]?.contains(a) ?? false)
    }

    func conversations() throws -> [Conversation] {
        let me = try requireMe()
        return convs
            .filter { $0.members.contains(me) && !(messagesByConv[$0.id] ?? []).isEmpty
                && !isBlocked(between: me, and: $0.other(than: me)) }
            .map { project($0, for: me) }
            .sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    func messages(conversationId: UUID) throws -> [ChatMessage] {
        let me = try requireMe()
        guard let c = convs.first(where: { $0.id == conversationId }), c.members.contains(me) else { throw RepositoryError.notFound }
        return (messagesByConv[conversationId] ?? []).sorted { $0.sentAt < $1.sentAt }
    }

    /// Checks membership and blocks, returns the conversation index and the other member.
    private func writableConversation(_ conversationId: UUID, me: UUID) throws -> (Int, UUID) {
        guard let i = convs.firstIndex(where: { $0.id == conversationId }), convs[i].members.contains(me) else {
            throw RepositoryError.notFound
        }
        let other = convs[i].other(than: me)
        if isBlocked(between: me, and: other) {
            throw RepositoryError.invalidState("Tu ne peux plus échanger de messages avec ce membre.")
        }
        return (i, other)
    }

    func send(text: String, conversationId: UUID) throws -> ChatMessage {
        let me = try requireMe()
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw RepositoryError.invalidState("Message vide.") }
        let (i, other) = try writableConversation(conversationId, me: me)
        let msg = ChatMessage(id: UUID(), conversationId: conversationId, senderId: me, text: String(body.prefix(2000)), sentAt: clock())
        messagesByConv[conversationId, default: []].append(msg)
        convs[i].unread[other, default: 0] += 1
        Task {
            try? await Task.sleep(for: .seconds(2))
            await self.simulateReply(conversationId: conversationId, from: other, to: me, prompt: body)
        }
        return msg
    }

    func sendPhoto(_ jpeg: Data, conversationId: UUID) throws -> ChatMessage {
        let me = try requireMe()
        guard !jpeg.isEmpty else { throw RepositoryError.invalidState("Photo vide.") }
        let (i, other) = try writableConversation(conversationId, me: me)
        let id = UUID()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("refripe-demo-chat", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(id.uuidString).jpg")
        do { try jpeg.write(to: url, options: .atomic) } catch {
            throw RepositoryError.invalidState("Impossible d'envoyer la photo.")
        }
        let msg = ChatMessage(id: id, conversationId: conversationId, senderId: me, text: "", sentAt: clock(),
                              photo: ListingPhoto(url: url))
        messagesByConv[conversationId, default: []].append(msg)
        convs[i].unread[other, default: 0] += 1
        Task {
            try? await Task.sleep(for: .seconds(2))
            await self.simulateReply(conversationId: conversationId, from: other, to: me, prompt: "photo reçue merci")
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
        guard let i = convs.firstIndex(where: { $0.id == conversationId }), !isBlocked(between: me, and: other) else { return }
        let now = clock()
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
        if isBlocked(between: me, and: userId) {
            throw RepositoryError.invalidState("Tu ne peux plus échanger de messages avec ce membre.")
        }
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

    // MARK: Moderation & account (v3)

    func report(listingId: UUID?, userId: UUID?, reason: ReportReason, details: String) throws {
        let me = try requireMe()
        guard listingId != nil || userId != nil else { throw RepositoryError.invalidState("Que veux-tu signaler ?") }
        if let listingId, index(ofListing: listingId) == nil { throw RepositoryError.notFound }
        if let userId {
            guard users[userId] != nil else { throw RepositoryError.notFound }
            guard userId != me else { throw RepositoryError.invalidState("Tu ne peux pas te signaler toi-même.") }
        }
        let text = String(details.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        reports.append(DemoReport(reporterId: me, listingId: listingId, userId: userId, reason: reason,
                                  details: text, createdAt: clock()))
    }

    func block(userId: UUID) throws {
        let me = try requireMe()
        guard userId != me else { throw RepositoryError.invalidState("Tu ne peux pas te bloquer toi-même.") }
        guard users[userId] != nil else { throw RepositoryError.notFound }
        blocks[me, default: []].insert(userId)
        // Pending negotiations between us stop.
        for i in threads.indices where threads[i].status == .pending
            && Set([threads[i].buyerId, threads[i].sellerId]) == Set([me, userId]) {
            threads[i].status = .expired
            threads[i].updatedAt = clock()
        }
    }

    func unblock(userId: UUID) throws {
        let me = try requireMe()
        blocks[me]?.remove(userId)
    }

    func blockedUserIds() throws -> Set<UUID> {
        let me = try requireMe()
        return blocks[me] ?? []
    }

    /// Demo equivalent of the `delete_account` RPC: my listings are withdrawn, my profile and private data
    /// removed, past orders keep an anonymised buyer name, then the session ends.
    func deleteAccount() throws {
        let me = try requireMe()
        // Unlike the SQL RPC (which refuses while escrow is in flight), the demo always lets you delete.
        for i in items.indices where items[i].sellerId == me && items[i].status != .sold {
            items[i].status = .removed
        }
        for i in allOrders.indices where allOrders[i].buyerId == me {
            allOrders[i].buyerName = "Compte supprimé"
        }
        for i in threads.indices where threads[i].status == .pending && (threads[i].buyerId == me || threads[i].sellerId == me) {
            threads[i].status = .expired
        }
        users[me] = nil
        preferences[me] = nil
        wishlists[me] = nil
        swiped[me] = nil
        notifs[me] = nil
        blocks[me] = nil
        phones = phones.filter { $0.value != me }
        if appleUser == me { appleUser = nil }
        self.me = nil
    }
}
