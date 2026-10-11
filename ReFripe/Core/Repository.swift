import Foundation

// MARK: - Data access (CONTRACT)
// Two implementations:
//   • DemoRepository   (Data/Demo)     — in-memory, seeded from the mockup, simulates the seller/payment side.
//   • SupabaseRepository (Data/Supabase) — real backend.
// Screens never talk to Supabase directly; they go through AppStore.repo (or AppStore helpers).

enum RepositoryError: LocalizedError {
    case notAuthenticated
    case notFound
    case offerLimitReached
    case invalidState(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "Connecte-toi pour continuer."
        case .notFound: "Élément introuvable."
        case .offerLimitReached: "Tu as déjà fait 3 offres sur cet article."
        case .invalidState(let m): m
        case .network(let m): "Problème de connexion : \(m)"
        }
    }
}

protocol Repository: AnyObject, Sendable {
    // Auth & profile
    var currentUserId: UUID? { get async }
    func restoreSession() async -> UserProfile?
    func sendOTP(phone: String) async throws
    func verifyOTP(phone: String, code: String) async throws -> UserProfile?   // nil → new user, needs profile
    func signInWithApple(idToken: String, nonce: String) async throws -> UserProfile?
    func completeSignup(_ input: SignupProfileInput) async throws -> UserProfile
    func signOut() async throws
    func loadPreferences() async throws -> UserPreferences
    func savePreferences(_ prefs: UserPreferences) async throws

    // Catalog
    func feed(filters: ListingFilters, preferences: UserPreferences?) async throws -> [Listing]
    func swipeDeck(preferences: UserPreferences?) async throws -> [Listing]   // not yet swiped by me
    func listing(id: UUID) async throws -> Listing
    func listings(sellerId: UUID) async throws -> [Listing]
    func profile(id: UUID) async throws -> UserProfile
    func profiles(ids: [UUID]) async throws -> [UUID: UserProfile]
    func recordView(listingId: UUID) async
    /// When the next drop ("nouveaux arrivages") goes live.
    func nextDropDate() async throws -> Date

    // Wishlist & swipe
    func wishlistIds() async throws -> Set<UUID>
    func setLiked(listingId: UUID, liked: Bool) async throws
    func recordSwipe(listingId: UUID, liked: Bool) async throws

    // Selling
    func publish(_ draft: ListingDraft) async throws -> Listing
    func updatePrice(listingId: UUID, price: FCFA) async throws -> Listing

    // Negotiation
    func offerThread(listingId: UUID) async throws -> OfferThread?             // my thread as buyer
    func offerThreads(role: OrderRole) async throws -> [OfferThread]
    func makeOffer(listingId: UUID, amount: FCFA) async throws -> OfferThread
    func respondToOffer(threadId: UUID, action: OfferAction, amount: FCFA?) async throws -> OfferThread   // seller side

    // Orders & escrow
    func createOrder(listingId: UUID, delivery: DeliveryMethod, payment: PaymentMethod) async throws -> Order
    func orders(role: OrderRole) async throws -> [Order]
    func order(id: UUID) async throws -> Order
    func advanceOrder(id: UUID, to status: OrderStatus) async throws -> Order    // seller: ship; buyer: confirm/dispute/return

    // Messaging
    func conversations() async throws -> [Conversation]
    func messages(conversationId: UUID) async throws -> [ChatMessage]
    func send(text: String, conversationId: UUID) async throws -> ChatMessage
    func conversation(withUser userId: UUID, listingId: UUID?) async throws -> Conversation   // get or create
    func markConversationRead(id: UUID) async throws

    // Notifications
    func notifications() async throws -> [AppNotification]
    func markNotificationsRead() async throws

    // Dashboard
    func sellerStats() async throws -> SellerStats
    func recommendations() async throws -> [SellerRecommendation]
}
