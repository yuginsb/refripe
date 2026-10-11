import Foundation

// MARK: - Shared domain model (CONTRACT — do not rename fields without updating every feature)
// Money is always an Int amount in FCFA (XOF has no minor unit).

typealias FCFA = Int

enum Gender: String, Codable, CaseIterable, Identifiable, Hashable {
    case femme, homme, enfant, bebe
    var id: String { rawValue }
}

enum ItemCondition: String, Codable, CaseIterable, Identifiable, Hashable {
    case newWithTags = "new_with_tags"
    case excellent
    case veryGood = "very_good"
    case good
    case fair
    var id: String { rawValue }
}

enum SizeType: String, Codable, CaseIterable, Identifiable, Hashable {
    case haut, pantalon, chaussures, enfant, unique
    var id: String { rawValue }
}

enum DeliveryMethod: String, Codable, CaseIterable, Identifiable, Hashable {
    case relais
    case mainPropre = "main_propre"
    case yango
    var id: String { rawValue }
}

enum PaymentMethod: String, Codable, CaseIterable, Identifiable, Hashable {
    case wave
    case orangeMoney = "orange_money"
    var id: String { rawValue }
}

enum ListingStatus: String, Codable, Hashable {
    case active, reserved, sold, removed
}

/// A listing photo: either a bundled asset (demo data) or a remote URL (Supabase Storage).
struct ListingPhoto: Codable, Hashable {
    var url: URL?
    var assetName: String?
    init(url: URL) { self.url = url; self.assetName = nil }
    init(assetName: String) { self.url = nil; self.assetName = assetName }
}

struct Listing: Identifiable, Codable, Hashable {
    let id: UUID
    var sellerId: UUID
    var title: String
    var description: String
    var price: FCFA
    var oldPrice: FCFA?            // set when the price dropped → "Prix en baisse" badge
    var sizeType: SizeType
    var sizeLabel: String          // display string, e.g. "Taille M", "Pointure 42", "4 ans"
    var gender: Gender
    var condition: ItemCondition
    var brand: String
    var color: String
    var tags: [String]
    var city: String               // "Abidjan"
    var district: String           // "Cocody"
    var photos: [ListingPhoto]
    var defectComment: String?
    var views: Int
    var favoritesCount: Int
    var isLastPiece: Bool
    var negotiable: Bool
    var minOffer: FCFA?            // seller's private floor; never shown to buyers
    var deliveryMethods: [DeliveryMethod]
    var status: ListingStatus
    var createdAt: Date

    var locationLabel: String { "\(district), \(city)" }
    var priceDrop: FCFA? { oldPrice.map { $0 - price }.flatMap { $0 > 0 ? $0 : nil } }
}

struct UserProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var username: String           // public handle, e.g. "Awa_Style225"
    var firstName: String
    var city: String
    var district: String
    var avatarURL: URL?
    var verified: Bool
    var rating: Double             // 0…5
    var salesCount: Int
    var memberSince: Date
    var responseTimeMinutes: Int?

    var initial: String { String(username.prefix(1)).uppercased() }
    var locationLabel: String { "\(city), \(district)" }
}

/// Private data about the signed-in user (onboarding answers, gamification).
struct UserPreferences: Codable, Hashable {
    var categories: Set<Gender> = []
    var sizes: [SizeType: String] = [.haut: "M", .pantalon: "38", .chaussures: "40"]
    var brands: Set<String> = []
    var isAdultConfirmed: Bool = false
    var onboardingCompleted: Bool = false
    var introGuideSeen: Bool = false
    var swipeCoachSeen: Bool = false
    var streakDays: Int = 0
    var lastActiveDay: Date?
}

// MARK: Discover filters

enum ListingSort: String, CaseIterable, Identifiable, Hashable {
    case recent, priceAsc, priceDesc, popular
    var id: String { rawValue }
}

struct ListingFilters: Hashable {
    static let catalogMaxPrice: FCFA = 15_000
    var gender: Gender? = nil      // nil = "Tout"
    var query: String = ""
    var priceMin: FCFA = 0
    var priceMax: FCFA = ListingFilters.catalogMaxPrice
    var conditions: Set<ItemCondition> = []
    var brands: Set<String> = []
    var negotiableOnly: Bool = false
    var sort: ListingSort = .recent

    /// Number of non-default advanced filters (badge on the "Filtres" chip). Gender/query excluded.
    var activeCount: Int {
        var n = 0
        if priceMin > 0 || priceMax < Self.catalogMaxPrice { n += 1 }
        if !conditions.isEmpty { n += 1 }
        if !brands.isEmpty { n += 1 }
        if negotiableOnly { n += 1 }
        if sort != .recent { n += 1 }
        return n
    }
}

// MARK: Negotiation (max 3 buyer offers, stays inside escrow)

enum OfferParty: String, Codable, Hashable { case buyer, seller }
enum OfferAction: String, Codable, Hashable { case offer, counter, accept, refuse }
enum OfferStatus: String, Codable, Hashable { case pending, accepted, refused, expired }

struct OfferRound: Codable, Hashable, Identifiable {
    var id = UUID()
    var by: OfferParty
    var amount: FCFA
    var action: OfferAction
    var at: Date
}

struct OfferThread: Identifiable, Codable, Hashable {
    let id: UUID
    var listingId: UUID
    var buyerId: UUID
    var sellerId: UUID
    var rounds: [OfferRound]
    var status: OfferStatus
    var updatedAt: Date

    var buyerOfferCount: Int { rounds.filter { $0.by == .buyer }.count }
    var acceptedAmount: FCFA? {
        status == .accepted ? rounds.last(where: { $0.action == .accept })?.amount : nil
    }
    var lastSellerCounter: OfferRound? { rounds.last(where: { $0.by == .seller && $0.action == .counter }) }
    var lastBuyerOffer: OfferRound? { rounds.last(where: { $0.by == .buyer }) }
}

// MARK: Orders (escrow lifecycle)

enum OrderStatus: String, Codable, CaseIterable, Hashable {
    case paymentPending = "PAYMENT_PENDING"
    case paid = "PAID"
    case awaitingShipment = "AWAITING_SHIPMENT"
    case shipped = "SHIPPED"
    case delivered = "DELIVERED"
    case buyerValidation = "BUYER_VALIDATION"
    case completed = "COMPLETED"
    case cancelled = "CANCELLED"
    case disputed = "DISPUTED"
    case returnPending = "RETURN_PENDING"
    case refunded = "REFUNDED"

    static let happyPath: [OrderStatus] = [.paymentPending, .paid, .awaitingShipment, .shipped, .delivered, .buyerValidation, .completed]
    var isAlternative: Bool { !Self.happyPath.contains(self) }
}

struct OrderEvent: Codable, Hashable {
    var status: OrderStatus
    var at: Date
}

struct Order: Identifiable, Codable, Hashable {
    let id: UUID
    var listingId: UUID
    var listingTitle: String
    var listingPhoto: ListingPhoto?
    var sellerId: UUID
    var buyerId: UUID
    var buyerName: String
    var itemPrice: FCFA            // negotiated price if an offer was accepted
    var deliveryFee: FCFA
    var delivery: DeliveryMethod
    var payment: PaymentMethod
    var status: OrderStatus
    var history: [OrderEvent]
    var createdAt: Date

    var total: FCFA { itemPrice + deliveryFee }
}

enum OrderRole: Hashable { case buyer, seller }

// MARK: Messaging (each conversation is tied to a listing)

struct Conversation: Identifiable, Codable, Hashable {
    let id: UUID
    var listingId: UUID?
    var otherUserId: UUID
    var lastMessage: String
    var lastMessageAt: Date
    var unreadCount: Int
}

struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    var conversationId: UUID
    var senderId: UUID
    var text: String
    var sentAt: Date
}

// MARK: Notifications

enum NotificationKind: String, Codable, Hashable {
    case counterOffer = "counter_offer", priceDrop = "price_drop", newInSize = "new_in_size"
    case message, streak, orderUpdate = "order_update"
}

struct AppNotification: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: NotificationKind
    var title: String
    var body: String
    var createdAt: Date
    var read: Bool
    var listingId: UUID?
    var orderId: UUID?
    var conversationId: UUID?
}

// MARK: Dashboard

struct SellerStats: Codable, Hashable {
    var sales: Int, salesDelta: String
    var revenue: FCFA, revenueDelta: String
    var views: Int, viewsDelta: String
    var favorites: Int, favoritesDelta: String
    var monthlyGoal: FCFA
    var tier: String, nextTier: String
    var tierSalesNow: Int, tierSalesNeeded: Int
    var weekViews: [Int]           // 7 values, Monday → Sunday
}

struct SellerRecommendation: Identifiable, Codable, Hashable {
    var id = UUID()
    var symbol: String             // SF Symbol name
    var title: String
    var body: String
    var cta: String?
    var listingId: UUID?
}

// MARK: Sell flow

struct ListingDraft: Hashable {
    var photos: [Data] = []        // JPEG data, already passed the quality check
    var defectComment: String = ""
    var gender: Gender?
    var brand: String?
    var brandCustom: String = ""
    var sizeType: SizeType?
    var sizeValue: String?
    var condition: ItemCondition?
    var color: String?
    var title: String = ""
    var description: String = ""
    var price: FCFA = 5_000
    var negotiable: Bool = false
    var minOffer: FCFA = 4_000
    var delivery: Set<DeliveryMethod> = [.relais]

    var resolvedBrand: String { brand == "Autre" ? brandCustom : (brand ?? "") }
}

enum PhotoFlag: String, CaseIterable, Hashable {
    case blur, nudity, inappropriate, duplicate, screenshot, watermark
}

// MARK: Auth

enum SignupMethod: String, Hashable { case phone, apple, google, facebook }

struct SignupProfileInput: Hashable {
    var firstName: String = ""
    var username: String = ""
    var city: String = "Abidjan"
    var district: String = ""
    var isAdultConfirmed: Bool = false
}
