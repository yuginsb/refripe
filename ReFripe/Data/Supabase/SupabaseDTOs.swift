import Foundation

// MARK: - Database rows (snake_case) ↔ contract types (Core/Models.swift)
// Column lists are explicit: `profiles.phone` and `listings.min_offer` are not
// readable by other users, so `select("*")` would fail or leak nothing useful.

/// Builds public URLs for objects of the `listing-photos` bucket.
struct StoragePaths: Sendable {
    static let bucket = "listing-photos"
    let base: URL

    /// Accepts either a storage path ("<uid>/<listing>/0.jpg") or an absolute URL (seed data).
    func publicURL(_ pathOrURL: String) -> URL? {
        if pathOrURL.hasPrefix("http://") || pathOrURL.hasPrefix("https://") {
            return URL(string: pathOrURL)
        }
        var root = base.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        let encoded = pathOrURL.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pathOrURL
        return URL(string: "\(root)/storage/v1/object/public/\(Self.bucket)/\(encoded)")
    }

    func photos(_ paths: [String]) -> [ListingPhoto] {
        paths.compactMap { publicURL($0) }.map { ListingPhoto(url: $0) }
    }
}

// MARK: Profiles

struct ProfileRow: Decodable {
    static let columns = "id,username,first_name,city,district,avatar_url,verified,rating,sales_count,response_time_minutes,created_at"

    let id: UUID
    let username: String
    let firstName: String
    let city: String
    let district: String
    let avatarUrl: String?
    let verified: Bool
    let rating: Double
    let salesCount: Int
    let responseTimeMinutes: Int?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, username, city, district, verified, rating
        case firstName = "first_name"
        case avatarUrl = "avatar_url"
        case salesCount = "sales_count"
        case responseTimeMinutes = "response_time_minutes"
        case createdAt = "created_at"
    }

    var model: UserProfile {
        UserProfile(
            id: id,
            username: username,
            firstName: firstName,
            city: city,
            district: district,
            avatarURL: avatarUrl.flatMap { URL(string: $0) },
            verified: verified,
            rating: rating,
            salesCount: salesCount,
            memberSince: createdAt,
            responseTimeMinutes: responseTimeMinutes
        )
    }
}

// MARK: Preferences

struct PreferencesRow: Codable {
    var userId: UUID
    var categories: [String]
    var sizes: [String: String]
    var brands: [String]
    var isAdultConfirmed: Bool
    var onboardingCompleted: Bool
    var introGuideSeen: Bool
    var swipeCoachSeen: Bool
    var streakDays: Int
    var lastActiveDay: Date?

    enum CodingKeys: String, CodingKey {
        case categories, sizes, brands
        case userId = "user_id"
        case isAdultConfirmed = "is_adult_confirmed"
        case onboardingCompleted = "onboarding_completed"
        case introGuideSeen = "intro_guide_seen"
        case swipeCoachSeen = "swipe_coach_seen"
        case streakDays = "streak_days"
        case lastActiveDay = "last_active_day"
    }

    init(userId: UUID, preferences p: UserPreferences) {
        self.userId = userId
        categories = p.categories.map(\.rawValue).sorted()
        // [SizeType: String] would be encoded as a flat array by JSONEncoder → use string keys.
        sizes = Dictionary(uniqueKeysWithValues: p.sizes.map { ($0.key.rawValue, $0.value) })
        brands = p.brands.sorted()
        isAdultConfirmed = p.isAdultConfirmed
        onboardingCompleted = p.onboardingCompleted
        introGuideSeen = p.introGuideSeen
        swipeCoachSeen = p.swipeCoachSeen
        streakDays = max(0, p.streakDays)
        lastActiveDay = p.lastActiveDay
    }

    var model: UserPreferences {
        var p = UserPreferences()
        p.categories = Set(categories.compactMap(Gender.init(rawValue:)))
        var parsed: [SizeType: String] = [:]
        for (key, value) in sizes {
            if let type = SizeType(rawValue: key) { parsed[type] = value }
        }
        p.sizes = parsed
        p.brands = Set(brands)
        p.isAdultConfirmed = isAdultConfirmed
        p.onboardingCompleted = onboardingCompleted
        p.introGuideSeen = introGuideSeen
        p.swipeCoachSeen = swipeCoachSeen
        p.streakDays = streakDays
        p.lastActiveDay = lastActiveDay
        return p
    }
}

// MARK: Listings

struct ListingRow: Decodable {
    /// Columns of the public view `listings_public` (no min_offer).
    static let publicColumns = "id,seller_id,title,description,price,old_price,size_type,size_label,gender,condition,brand,color,tags,city,district,photos,defect_comment,views_count,favorites_count,is_last_piece,negotiable,delivery_methods,status,created_at"
    /// Columns readable by the seller on the `listings` table.
    static let ownColumns = publicColumns + ",min_offer"

    let id: UUID
    let sellerId: UUID
    let title: String
    let description: String
    let price: FCFA
    let oldPrice: FCFA?
    let sizeType: SizeType
    let sizeLabel: String
    let gender: Gender
    let condition: ItemCondition
    let brand: String
    let color: String
    let tags: [String]
    let city: String
    let district: String
    let photos: [String]
    let defectComment: String?
    let viewsCount: Int
    let favoritesCount: Int
    let isLastPiece: Bool
    let negotiable: Bool
    let minOffer: FCFA?            // only present when read from `listings` by the seller
    let deliveryMethods: [DeliveryMethod]
    let status: ListingStatus
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, description, price, gender, condition, brand, color, tags, city, district, photos, negotiable, status
        case sellerId = "seller_id"
        case oldPrice = "old_price"
        case sizeType = "size_type"
        case sizeLabel = "size_label"
        case defectComment = "defect_comment"
        case viewsCount = "views_count"
        case favoritesCount = "favorites_count"
        case isLastPiece = "is_last_piece"
        case minOffer = "min_offer"
        case deliveryMethods = "delivery_methods"
        case createdAt = "created_at"
    }

    func model(_ storage: StoragePaths) -> Listing {
        Listing(
            id: id,
            sellerId: sellerId,
            title: title,
            description: description,
            price: price,
            oldPrice: oldPrice,
            sizeType: sizeType,
            sizeLabel: sizeLabel,
            gender: gender,
            condition: condition,
            brand: brand,
            color: color,
            tags: tags,
            city: city,
            district: district,
            photos: storage.photos(photos),
            defectComment: defectComment,
            views: viewsCount,
            favoritesCount: favoritesCount,
            isLastPiece: isLastPiece,
            negotiable: negotiable,
            minOffer: minOffer,
            deliveryMethods: deliveryMethods,
            status: status,
            createdAt: createdAt
        )
    }
}

struct ListingInsert: Encodable {
    let id: UUID
    let sellerId: UUID
    let title: String
    let description: String
    let price: FCFA
    let sizeType: SizeType
    let sizeValue: String
    let sizeLabel: String
    let gender: Gender
    let condition: ItemCondition
    let brand: String
    let color: String
    let tags: [String]
    let photos: [String]
    let defectComment: String?
    let negotiable: Bool
    let minOffer: FCFA?
    let deliveryMethods: [DeliveryMethod]

    enum CodingKeys: String, CodingKey {
        case id, title, description, price, gender, condition, brand, color, tags, photos, negotiable
        case sellerId = "seller_id"
        case sizeType = "size_type"
        case sizeValue = "size_value"
        case sizeLabel = "size_label"
        case defectComment = "defect_comment"
        case minOffer = "min_offer"
        case deliveryMethods = "delivery_methods"
    }
}

/// Columns a user may update on their own profile (see the column grant in the RLS migration).
struct ProfileUpdate: Encodable {
    let username: String
    let firstName: String
    let city: String
    let district: String
    enum CodingKeys: String, CodingKey {
        case username, city, district
        case firstName = "first_name"
    }
}

struct PriceUpdate: Encodable {
    let price: FCFA
}

struct ListingIdRow: Decodable {
    let listingId: UUID
    enum CodingKeys: String, CodingKey { case listingId = "listing_id" }
}

struct WishlistInsert: Encodable {
    let userId: UUID
    let listingId: UUID
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case listingId = "listing_id"
    }
}

struct SwipeUpsert: Encodable {
    let userId: UUID
    let listingId: UUID
    let liked: Bool
    enum CodingKeys: String, CodingKey {
        case liked
        case userId = "user_id"
        case listingId = "listing_id"
    }
}

// MARK: Offers

struct OfferRoundRow: Decodable {
    let id: UUID
    let party: OfferParty
    let amount: FCFA
    let action: OfferAction
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, party, amount, action
        case createdAt = "created_at"
    }
}

struct OfferThreadRow: Decodable {
    static let columns = "id,listing_id,buyer_id,seller_id,status,updated_at,offer_rounds(id,party,amount,action,created_at)"

    let id: UUID
    let listingId: UUID
    let buyerId: UUID
    let sellerId: UUID
    let status: OfferStatus
    let updatedAt: Date
    let offerRounds: [OfferRoundRow]

    enum CodingKeys: String, CodingKey {
        case id, status
        case listingId = "listing_id"
        case buyerId = "buyer_id"
        case sellerId = "seller_id"
        case updatedAt = "updated_at"
        case offerRounds = "offer_rounds"
    }

    var model: OfferThread {
        OfferThread(
            id: id,
            listingId: listingId,
            buyerId: buyerId,
            sellerId: sellerId,
            rounds: offerRounds
                .sorted { $0.createdAt < $1.createdAt }
                .map { OfferRound(id: $0.id, by: $0.party, amount: $0.amount, action: $0.action, at: $0.createdAt) },
            status: status,
            updatedAt: updatedAt
        )
    }
}

// MARK: Orders

struct OrderEventRow: Decodable {
    let id: Int
    let status: OrderStatus
    let createdAt: Date
    enum CodingKeys: String, CodingKey {
        case id, status
        case createdAt = "created_at"
    }
}

struct OrderRow: Decodable {
    static let columns = "id,listing_id,seller_id,buyer_id,listing_title,listing_photo,buyer_name,item_price,delivery_fee,delivery,payment,status,created_at,order_events(id,status,created_at)"

    let id: UUID
    let listingId: UUID
    let sellerId: UUID
    let buyerId: UUID
    let listingTitle: String
    let listingPhoto: String?
    let buyerName: String
    let itemPrice: FCFA
    let deliveryFee: FCFA
    let delivery: DeliveryMethod
    let payment: PaymentMethod
    let status: OrderStatus
    let createdAt: Date
    let orderEvents: [OrderEventRow]

    enum CodingKeys: String, CodingKey {
        case id, delivery, payment, status
        case listingId = "listing_id"
        case sellerId = "seller_id"
        case buyerId = "buyer_id"
        case listingTitle = "listing_title"
        case listingPhoto = "listing_photo"
        case buyerName = "buyer_name"
        case itemPrice = "item_price"
        case deliveryFee = "delivery_fee"
        case createdAt = "created_at"
        case orderEvents = "order_events"
    }

    func model(_ storage: StoragePaths) -> Order {
        Order(
            id: id,
            listingId: listingId,
            listingTitle: listingTitle,
            listingPhoto: listingPhoto.flatMap { storage.publicURL($0) }.map { ListingPhoto(url: $0) },
            sellerId: sellerId,
            buyerId: buyerId,
            buyerName: buyerName,
            itemPrice: itemPrice,
            deliveryFee: deliveryFee,
            delivery: delivery,
            payment: payment,
            status: status,
            history: orderEvents.sorted { $0.id < $1.id }.map { OrderEvent(status: $0.status, at: $0.createdAt) },
            createdAt: createdAt
        )
    }
}

// MARK: Messaging

struct ConversationRow: Decodable {
    static let columns = "id,listing_id,other_user_id,last_message,last_message_at,unread_count"

    let id: UUID
    let listingId: UUID?
    let otherUserId: UUID
    let lastMessage: String
    let lastMessageAt: Date
    let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case listingId = "listing_id"
        case otherUserId = "other_user_id"
        case lastMessage = "last_message"
        case lastMessageAt = "last_message_at"
        case unreadCount = "unread_count"
    }

    var model: Conversation {
        Conversation(id: id, listingId: listingId, otherUserId: otherUserId,
                     lastMessage: lastMessage, lastMessageAt: lastMessageAt, unreadCount: unreadCount)
    }
}

struct MessageRow: Decodable {
    static let columns = "id,conversation_id,sender_id,text,created_at"

    let id: UUID
    let conversationId: UUID
    let senderId: UUID
    let text: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, text
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case createdAt = "created_at"
    }

    var model: ChatMessage {
        ChatMessage(id: id, conversationId: conversationId, senderId: senderId, text: text, sentAt: createdAt)
    }
}

struct MessageInsert: Encodable {
    let conversationId: UUID
    let senderId: UUID
    let text: String
    enum CodingKeys: String, CodingKey {
        case text
        case conversationId = "conversation_id"
        case senderId = "sender_id"
    }
}

// MARK: Notifications

struct NotificationDTO: Decodable {
    static let columns = "id,kind,title,body,created_at,read,listing_id,order_id,conversation_id"

    let id: UUID
    let kind: NotificationKind
    let title: String
    let body: String
    let createdAt: Date
    let read: Bool
    let listingId: UUID?
    let orderId: UUID?
    let conversationId: UUID?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, body, read
        case createdAt = "created_at"
        case listingId = "listing_id"
        case orderId = "order_id"
        case conversationId = "conversation_id"
    }

    var model: AppNotification {
        AppNotification(id: id, kind: kind, title: title, body: body, createdAt: createdAt, read: read,
                        listingId: listingId, orderId: orderId, conversationId: conversationId)
    }
}

struct ReadUpdate: Encodable {
    let read: Bool
}

// MARK: - RPC parameters (names match the SQL function arguments)

struct CompleteSignupParams: Encodable {
    let username: String
    let firstName: String
    let city: String
    let district: String
    let isAdult: Bool
    enum CodingKeys: String, CodingKey {
        case username = "p_username"
        case firstName = "p_first_name"
        case city = "p_city"
        case district = "p_district"
        case isAdult = "p_is_adult"
    }
}

struct ListingIdParams: Encodable {
    let listingId: UUID
    enum CodingKeys: String, CodingKey { case listingId = "p_listing_id" }
}

struct SwipeDeckParams: Encodable {
    let limit: Int
    enum CodingKeys: String, CodingKey { case limit = "p_limit" }
}

struct MakeOfferParams: Encodable {
    let listingId: UUID
    let amount: FCFA
    enum CodingKeys: String, CodingKey {
        case listingId = "p_listing_id"
        case amount = "p_amount"
    }
}

struct RespondOfferParams: Encodable {
    let threadId: UUID
    let action: OfferAction
    let amount: FCFA?
    enum CodingKeys: String, CodingKey {
        case threadId = "p_thread_id"
        case action = "p_action"
        case amount = "p_amount"
    }
}

struct CreateOrderParams: Encodable {
    let listingId: UUID
    let delivery: DeliveryMethod
    let payment: PaymentMethod
    enum CodingKeys: String, CodingKey {
        case listingId = "p_listing_id"
        case delivery = "p_delivery"
        case payment = "p_payment"
    }
}

struct AdvanceOrderParams: Encodable {
    let orderId: UUID
    let status: OrderStatus
    enum CodingKeys: String, CodingKey {
        case orderId = "p_order_id"
        case status = "p_status"
    }
}

struct ConversationParams: Encodable {
    let otherUser: UUID
    let listingId: UUID?
    enum CodingKeys: String, CodingKey {
        case otherUser = "p_other_user"
        case listingId = "p_listing_id"
    }
}

struct ConversationIdParams: Encodable {
    let conversationId: UUID
    enum CodingKeys: String, CodingKey { case conversationId = "p_conversation_id" }
}

// MARK: - Edge Functions

struct PaymentInitBody: Encodable {
    let orderId: UUID
    enum CodingKeys: String, CodingKey { case orderId = "order_id" }
}

struct PaymentInitResponse: Decodable {
    let paymentId: String?
    let provider: String?
    let status: String
    let checkoutUrl: String?
    enum CodingKeys: String, CodingKey {
        case provider, status
        case paymentId = "payment_id"
        case checkoutUrl = "checkout_url"
    }
}

struct FunctionErrorBody: Decodable {
    let error: String
    let code: String?
}
