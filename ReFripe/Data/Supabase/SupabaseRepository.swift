import Foundation
import Supabase
#if canImport(UIKit)
import UIKit
#endif

/// Real backend: Supabase (Postgres + RLS + RPC, Storage, Edge Functions).
/// Business rules live in SQL (supabase/migrations); this class only maps rows to the contract types.
final class SupabaseRepository: Repository, @unchecked Sendable {
    private let client: SupabaseClient
    private let storage: StoragePaths

    init(config: SupabaseConfig) {
        client = SupabaseClient(supabaseURL: config.url, supabaseKey: config.anonKey)
        storage = StoragePaths(base: config.url)
    }

    // MARK: - Auth & profile

    var currentUserId: UUID? {
        get async { await client.auth.currentUser?.id }
    }

    func restoreSession() async -> UserProfile? {
        // `session` refreshes an expired access token if needed; nil if signed out.
        guard (try? await client.auth.session) != nil else { return nil }
        return try? await myProfile()
    }

    func sendOTP(phone: String) async throws {
        try await run {
            try await client.auth.signInWithOTP(phone: Self.normalizedPhone(phone))
        }
    }

    func verifyOTP(phone: String, code: String) async throws -> UserProfile? {
        try await run {
            _ = try await client.auth.verifyOTP(
                phone: Self.normalizedPhone(phone),
                token: code.trimmingCharacters(in: .whitespacesAndNewlines),
                type: .sms
            )
            return try await myProfile()
        }
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> UserProfile? {
        try await run {
            _ = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
            )
            return try await myProfile()
        }
    }

    func completeSignup(_ input: SignupProfileInput) async throws -> UserProfile {
        try await run {
            _ = try await requireUser()
            let params = CompleteSignupParams(
                username: input.username.trimmingCharacters(in: .whitespacesAndNewlines),
                firstName: input.firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                city: input.city,
                district: input.district.trimmingCharacters(in: .whitespacesAndNewlines),
                isAdult: input.isAdultConfirmed
            )
            let row: ProfileRow = try await client.rpc("complete_signup", params: params).execute().value
            return row.model
        }
    }

    func signOut() async throws {
        try await run { try await client.auth.signOut() }
    }

    func loadPreferences() async throws -> UserPreferences {
        try await run {
            let uid = try await requireUser()
            let rows: [PreferencesRow] = try await client.from("preferences")
                .select()
                .eq("user_id", value: uid)
                .limit(1)
                .execute().value
            return rows.first?.model ?? UserPreferences()
        }
    }

    func savePreferences(_ prefs: UserPreferences) async throws {
        try await run {
            let uid = try await requireUser()
            try await client.from("preferences")
                .upsert(PreferencesRow(userId: uid, preferences: prefs), onConflict: "user_id", returning: .minimal)
                .execute()
        }
    }

    // MARK: - Catalog

    func feed(filters: ListingFilters, preferences: UserPreferences?) async throws -> [Listing] {
        try await run {
            var query = client.from("listings_public")
                .select(ListingRow.publicColumns)
                .eq("status", value: ListingStatus.active.rawValue)
            if let gender = filters.gender {
                query = query.eq("gender", value: gender.rawValue)
            }
            let term = Self.sanitizedSearch(filters.query)
            if !term.isEmpty {
                query = query.or("title.ilike.*\(term)*,brand.ilike.*\(term)*,description.ilike.*\(term)*")
            }
            if filters.priceMin > 0 {
                query = query.gte("price", value: filters.priceMin)
            }
            if filters.priceMax < ListingFilters.catalogMaxPrice {
                query = query.lte("price", value: filters.priceMax)
            }
            if !filters.conditions.isEmpty {
                query = query.in("condition", values: filters.conditions.map(\.rawValue).sorted())
            }
            if !filters.brands.isEmpty {
                query = query.in("brand", values: filters.brands.sorted())
            }
            if filters.negotiableOnly {
                query = query.eq("negotiable", value: true)
            }

            let ordered: PostgrestTransformBuilder
            switch filters.sort {
            case .recent: ordered = query.order("created_at", ascending: false)
            case .priceAsc: ordered = query.order("price", ascending: true)
            case .priceDesc: ordered = query.order("price", ascending: false)
            case .popular: ordered = query.order("views_count", ascending: false)
            }
            let rows: [ListingRow] = try await ordered.limit(200).execute().value
            let listings = rows.map { $0.model(storage) }

            // Personalisation: with the default sort, preferred categories come first (stable).
            guard filters.sort == .recent, filters.gender == nil,
                  let categories = preferences?.categories, !categories.isEmpty else { return listings }
            return listings.filter { categories.contains($0.gender) } + listings.filter { !categories.contains($0.gender) }
        }
    }

    func swipeDeck(preferences: UserPreferences?) async throws -> [Listing] {
        // Preferred categories are read server-side from the `preferences` table.
        try await run {
            let rows: [ListingRow] = try await client
                .rpc("swipe_deck", params: SwipeDeckParams(limit: 40))
                .select(ListingRow.publicColumns)
                .execute().value
            return rows.map { $0.model(storage) }
        }
    }

    func listing(id: UUID) async throws -> Listing {
        try await run {
            let me = await client.auth.currentUser?.id
            let publicRows: [ListingRow] = try await client.from("listings_public")
                .select(ListingRow.publicColumns)
                .eq("id", value: id)
                .limit(1)
                .execute().value
            if let row = publicRows.first, row.sellerId != me {
                return row.model(storage)
            }
            // My own listing (or a removed one): read the table to get min_offer.
            guard me != nil else { throw RepositoryError.notFound }
            let ownRows: [ListingRow] = try await client.from("listings")
                .select(ListingRow.ownColumns)
                .eq("id", value: id)
                .limit(1)
                .execute().value
            guard let own = ownRows.first ?? publicRows.first else { throw RepositoryError.notFound }
            return own.model(storage)
        }
    }

    func listings(sellerId: UUID) async throws -> [Listing] {
        try await run {
            let me = await client.auth.currentUser?.id
            let rows: [ListingRow]
            if sellerId == me {
                rows = try await client.from("listings")
                    .select(ListingRow.ownColumns)
                    .eq("seller_id", value: sellerId)
                    .neq("status", value: ListingStatus.removed.rawValue)
                    .order("created_at", ascending: false)
                    .execute().value
            } else {
                rows = try await client.from("listings_public")
                    .select(ListingRow.publicColumns)
                    .eq("seller_id", value: sellerId)
                    .order("created_at", ascending: false)
                    .execute().value
            }
            return rows.map { $0.model(storage) }
        }
    }

    func profile(id: UUID) async throws -> UserProfile {
        try await run {
            guard let row = try await fetchProfile(id) else { throw RepositoryError.notFound }
            return row.model
        }
    }

    func profiles(ids: [UUID]) async throws -> [UUID: UserProfile] {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [:] }
        return try await run {
            let rows: [ProfileRow] = try await client.from("profiles")
                .select(ProfileRow.columns)
                .in("id", values: unique.map(\.uuidString))
                .execute().value
            return Dictionary(rows.map { ($0.id, $0.model) }, uniquingKeysWith: { first, _ in first })
        }
    }

    func recordView(listingId: UUID) async {
        _ = try? await client.rpc("record_view", params: ListingIdParams(listingId: listingId)).execute()
    }

    func nextDropDate() async throws -> Date {
        try await run {
            let date: Date = try await client.rpc("next_drop").execute().value
            return date
        }
    }

    // MARK: - Wishlist & swipe

    func wishlistIds() async throws -> Set<UUID> {
        try await run {
            let uid = try await requireUser()
            let rows: [ListingIdRow] = try await client.from("wishlist")
                .select("listing_id")
                .eq("user_id", value: uid)
                .execute().value
            return Set(rows.map(\.listingId))
        }
    }

    func setLiked(listingId: UUID, liked: Bool) async throws {
        try await run {
            let uid = try await requireUser()
            if liked {
                try await client.from("wishlist")
                    .upsert(WishlistInsert(userId: uid, listingId: listingId),
                            onConflict: "user_id,listing_id", returning: .minimal, ignoreDuplicates: true)
                    .execute()
            } else {
                try await client.from("wishlist")
                    .delete(returning: .minimal)
                    .eq("user_id", value: uid)
                    .eq("listing_id", value: listingId)
                    .execute()
            }
        }
    }

    func recordSwipe(listingId: UUID, liked: Bool) async throws {
        try await run {
            let uid = try await requireUser()
            try await client.from("swipes")
                .upsert(SwipeUpsert(userId: uid, listingId: listingId, liked: liked),
                        onConflict: "user_id,listing_id", returning: .minimal)
                .execute()
            if liked {
                // A right swipe adds the item to "Mes envies" (idempotent).
                try await client.from("wishlist")
                    .upsert(WishlistInsert(userId: uid, listingId: listingId),
                            onConflict: "user_id,listing_id", returning: .minimal, ignoreDuplicates: true)
                    .execute()
            }
        }
    }

    // MARK: - Selling

    func publish(_ draft: ListingDraft) async throws -> Listing {
        try await run {
            let uid = try await requireUser()
            guard let gender = draft.gender, let sizeType = draft.sizeType, let condition = draft.condition else {
                throw RepositoryError.invalidState("Complète toutes les étapes avant de publier.")
            }
            guard draft.photos.count >= Catalog.sellPhotoMin else {
                throw RepositoryError.invalidState("Ajoute au moins une photo.")
            }
            guard !draft.delivery.isEmpty else {
                throw RepositoryError.invalidState("Choisis au moins un mode de livraison.")
            }
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.count >= 3 else {
                throw RepositoryError.invalidState("Donne un titre à ton article (3 caractères minimum).")
            }

            let listingId = UUID()
            // Storage RLS: the first folder must be auth.uid() (lowercase, as Postgres prints UUIDs).
            let folder = "\(uid.uuidString.lowercased())/\(listingId.uuidString.lowercased())"
            var uploaded: [String] = []
            do {
                for (index, data) in draft.photos.prefix(Catalog.sellPhotoMax).enumerated() {
                    let path = "\(folder)/\(index).jpg"
                    _ = try await client.storage.from(StoragePaths.bucket).upload(
                        path,
                        data: data,
                        options: FileOptions(cacheControl: "31536000", contentType: "image/jpeg", upsert: true)
                    )
                    uploaded.append(path)
                }

                let sizeValue = draft.sizeValue ?? (sizeType == .unique ? "Taille unique" : "")
                let defect = draft.defectComment.trimmingCharacters(in: .whitespacesAndNewlines)
                let brand = draft.resolvedBrand.trimmingCharacters(in: .whitespacesAndNewlines)
                let color = draft.color ?? ""
                let insert = ListingInsert(
                    id: listingId,
                    sellerId: uid,
                    title: title,
                    description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
                    price: draft.price,
                    sizeType: sizeType,
                    sizeValue: sizeValue,
                    sizeLabel: sizeType.displayLabel(for: sizeValue),
                    gender: gender,
                    condition: condition,
                    brand: brand,
                    color: color,
                    tags: [brand, color].filter { !$0.isEmpty },
                    photos: uploaded,
                    defectComment: defect.isEmpty ? nil : defect,
                    negotiable: draft.negotiable,
                    minOffer: draft.negotiable && draft.minOffer > 0 && draft.minOffer < draft.price ? draft.minOffer : nil,
                    deliveryMethods: DeliveryMethod.allCases.filter { draft.delivery.contains($0) }
                )
                let rows: [ListingRow] = try await client.from("listings")
                    .insert(insert, returning: .representation)
                    .select(ListingRow.ownColumns)
                    .execute().value
                guard let row = rows.first else { throw RepositoryError.notFound }
                return row.model(storage)
            } catch {
                if !uploaded.isEmpty {
                    _ = try? await client.storage.from(StoragePaths.bucket).remove(paths: uploaded)
                }
                throw error
            }
        }
    }

    func updatePrice(listingId: UUID, price: FCFA) async throws -> Listing {
        guard price > 0 else { throw RepositoryError.invalidState("Le prix doit être positif.") }
        return try await run {
            let rows: [ListingRow] = try await client.from("listings")
                .update(PriceUpdate(price: price), returning: .representation)
                .eq("id", value: listingId)
                .select(ListingRow.ownColumns)
                .execute().value
            guard let row = rows.first else {
                throw RepositoryError.invalidState("Seules tes annonces en vente peuvent changer de prix.")
            }
            return row.model(storage)
        }
    }

    // MARK: - Negotiation

    func offerThread(listingId: UUID) async throws -> OfferThread? {
        try await run {
            let uid = try await requireUser()
            let rows: [OfferThreadRow] = try await client.from("offer_threads")
                .select(OfferThreadRow.columns)
                .eq("listing_id", value: listingId)
                .eq("buyer_id", value: uid)
                .limit(1)
                .execute().value
            return rows.first?.model
        }
    }

    func offerThreads(role: OrderRole) async throws -> [OfferThread] {
        try await run {
            let uid = try await requireUser()
            let rows: [OfferThreadRow] = try await client.from("offer_threads")
                .select(OfferThreadRow.columns)
                .eq(role == .buyer ? "buyer_id" : "seller_id", value: uid)
                .order("updated_at", ascending: false)
                .execute().value
            return rows.map(\.model)
        }
    }

    func makeOffer(listingId: UUID, amount: FCFA) async throws -> OfferThread {
        try await run {
            let threadId: UUID = try await client
                .rpc("make_offer", params: MakeOfferParams(listingId: listingId, amount: amount))
                .execute().value
            return try await fetchThread(threadId)
        }
    }

    func respondToOffer(threadId: UUID, action: OfferAction, amount: FCFA?) async throws -> OfferThread {
        try await run {
            let id: UUID = try await client
                .rpc("respond_offer", params: RespondOfferParams(threadId: threadId, action: action,
                                                                 amount: action == .counter ? amount : nil))
                .execute().value
            return try await fetchThread(id)
        }
    }

    // MARK: - Orders & escrow

    func createOrder(listingId: UUID, delivery: DeliveryMethod, payment: PaymentMethod) async throws -> Order {
        try await run {
            let orderId: UUID = try await client
                .rpc("create_order", params: CreateOrderParams(listingId: listingId, delivery: delivery, payment: payment))
                .execute().value

            let response: PaymentInitResponse
            do {
                response = try await client.functions.invoke(
                    "payment-init",
                    options: FunctionInvokeOptions(body: PaymentInitBody(orderId: orderId))
                )
            } catch {
                // Payment could not start: release the item instead of leaving it reserved.
                _ = try? await client
                    .rpc("advance_order", params: AdvanceOrderParams(orderId: orderId, status: .cancelled))
                    .execute()
                throw error
            }

            #if canImport(UIKit)
            // Live mode: hand over to the Wave / Orange Money checkout (nil in sandbox).
            if let raw = response.checkoutUrl, let url = URL(string: raw) {
                await MainActor.run { UIApplication.shared.open(url) }
            }
            #endif

            return try await fetchOrder(orderId)
        }
    }

    func orders(role: OrderRole) async throws -> [Order] {
        try await run {
            let uid = try await requireUser()
            let rows: [OrderRow] = try await client.from("orders")
                .select(OrderRow.columns)
                .eq(role == .buyer ? "buyer_id" : "seller_id", value: uid)
                .order("created_at", ascending: false)
                .execute().value
            return rows.map { $0.model(storage) }
        }
    }

    func order(id: UUID) async throws -> Order {
        try await run { try await fetchOrder(id) }
    }

    func advanceOrder(id: UUID, to status: OrderStatus) async throws -> Order {
        try await run {
            try await client
                .rpc("advance_order", params: AdvanceOrderParams(orderId: id, status: status))
                .execute()
            return try await fetchOrder(id)
        }
    }

    // MARK: - Messaging

    func conversations() async throws -> [Conversation] {
        try await run {
            _ = try await requireUser()
            let rows: [ConversationRow] = try await client.from("my_conversations")
                .select(ConversationRow.columns)
                .order("last_message_at", ascending: false)
                .execute().value
            return rows.map(\.model)
        }
    }

    func messages(conversationId: UUID) async throws -> [ChatMessage] {
        try await run {
            let rows: [MessageRow] = try await client.from("messages")
                .select(MessageRow.columns)
                .eq("conversation_id", value: conversationId)
                .order("created_at", ascending: true)
                .limit(500)
                .execute().value
            return rows.map(\.model)
        }
    }

    func send(text: String, conversationId: UUID) async throws -> ChatMessage {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RepositoryError.invalidState("Écris un message.") }
        return try await run {
            let uid = try await requireUser()
            let rows: [MessageRow] = try await client.from("messages")
                .insert(MessageInsert(conversationId: conversationId, senderId: uid, text: String(trimmed.prefix(2000))),
                        returning: .representation)
                .select(MessageRow.columns)
                .execute().value
            guard let row = rows.first else { throw RepositoryError.notFound }
            return row.model
        }
    }

    func conversation(withUser userId: UUID, listingId: UUID?) async throws -> Conversation {
        try await run {
            let id: UUID = try await client
                .rpc("get_or_create_conversation", params: ConversationParams(otherUser: userId, listingId: listingId))
                .execute().value
            let rows: [ConversationRow] = try await client.from("my_conversations")
                .select(ConversationRow.columns)
                .eq("id", value: id)
                .limit(1)
                .execute().value
            guard let row = rows.first else { throw RepositoryError.notFound }
            return row.model
        }
    }

    func markConversationRead(id: UUID) async throws {
        try await run {
            try await client
                .rpc("mark_conversation_read", params: ConversationIdParams(conversationId: id))
                .execute()
        }
    }

    // MARK: - Notifications

    func notifications() async throws -> [AppNotification] {
        try await run {
            _ = try await requireUser()
            let rows: [NotificationRow] = try await client.from("notifications")
                .select(NotificationRow.columns)
                .order("created_at", ascending: false)
                .limit(100)
                .execute().value
            return rows.map(\.model)
        }
    }

    func markNotificationsRead() async throws {
        try await run {
            let uid = try await requireUser()
            try await client.from("notifications")
                .update(ReadUpdate(read: true), returning: .minimal)
                .eq("user_id", value: uid)
                .eq("read", value: false)
                .execute()
        }
    }

    // MARK: - Dashboard

    func sellerStats() async throws -> SellerStats {
        // The RPC returns an object whose keys are exactly SellerStats' property names.
        try await run {
            let stats: SellerStats = try await client.rpc("seller_stats").execute().value
            return stats
        }
    }

    func recommendations() async throws -> [SellerRecommendation] {
        try await run {
            let items: [SellerRecommendation] = try await client.rpc("seller_recommendations").execute().value
            return items
        }
    }

    // MARK: - Helpers

    private func requireUser() async throws -> UUID {
        guard let id = await client.auth.currentUser?.id else { throw RepositoryError.notAuthenticated }
        return id
    }

    private func fetchProfile(_ id: UUID) async throws -> ProfileRow? {
        let rows: [ProfileRow] = try await client.from("profiles")
            .select(ProfileRow.columns)
            .eq("id", value: id)
            .limit(1)
            .execute().value
        return rows.first
    }

    /// Profile of the signed-in user; nil when the account exists but signup isn't completed.
    private func myProfile() async throws -> UserProfile? {
        let uid = try await requireUser()
        return try await fetchProfile(uid)?.model
    }

    private func fetchThread(_ id: UUID) async throws -> OfferThread {
        let rows: [OfferThreadRow] = try await client.from("offer_threads")
            .select(OfferThreadRow.columns)
            .eq("id", value: id)
            .limit(1)
            .execute().value
        guard let row = rows.first else { throw RepositoryError.notFound }
        return row.model
    }

    private func fetchOrder(_ id: UUID) async throws -> Order {
        let rows: [OrderRow] = try await client.from("orders")
            .select(OrderRow.columns)
            .eq("id", value: id)
            .limit(1)
            .execute().value
        guard let row = rows.first else { throw RepositoryError.notFound }
        return row.model(storage)
    }

    /// Runs a backend call and converts SDK errors into `RepositoryError`.
    private func run<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw Self.map(error)
        }
    }

    static func map(_ error: Error) -> Error {
        if error is RepositoryError || error is CancellationError { return error }

        if let e = error as? PostgrestError {
            switch e.hint {
            case "offer_limit_reached": return RepositoryError.offerLimitReached
            case "not_authenticated": return RepositoryError.notAuthenticated
            case "not_found": return RepositoryError.notFound
            default: break
            }
            switch e.code {
            case "PGRST116": return RepositoryError.notFound
            case "PGRST301", "PGRST302", "PGRST303": return RepositoryError.notAuthenticated
            case "42501": return RepositoryError.invalidState("Action non autorisée.")
            case "23505": return RepositoryError.invalidState("Cet élément existe déjà.")
            case "23514": return RepositoryError.invalidState("Certaines informations ne sont pas valides.")
            default: break
            }
            // Business errors raised by the RPC carry a French, user-facing message.
            if e.code == "P0001" { return RepositoryError.invalidState(e.message) }
            return RepositoryError.invalidState("Opération impossible pour le moment.")
        }

        if let e = error as? AuthError {
            switch e.errorCode {
            case .sessionNotFound: return RepositoryError.notAuthenticated
            case .otpExpired, .invalidCredentials: return RepositoryError.invalidState("Code incorrect ou expiré.")
            case .overSMSSendRateLimit: return RepositoryError.invalidState("Trop de demandes de code. Réessaie dans une minute.")
            case .smsSendFailed: return RepositoryError.invalidState("L’envoi du SMS a échoué. Vérifie ton numéro.")
            case .phoneProviderDisabled, .otpDisabled: return RepositoryError.invalidState("La connexion par SMS n’est pas encore disponible.")
            case .validationFailed: return RepositoryError.invalidState("Numéro de téléphone invalide.")
            default: return RepositoryError.invalidState(e.message)
            }
        }

        if let e = error as? FunctionsError {
            switch e {
            case let .httpError(code, data):
                if let body = try? JSONDecoder().decode(FunctionErrorBody.self, from: data) {
                    return code == 401 ? RepositoryError.notAuthenticated : RepositoryError.invalidState(body.error)
                }
                return RepositoryError.network("erreur \(code)")
            case .relayError:
                return RepositoryError.network("service de paiement injoignable")
            @unknown default:
                return RepositoryError.network(e.localizedDescription)
            }
        }

        if let e = error as? URLError {
            return RepositoryError.network(e.localizedDescription)
        }
        if error is DecodingError {
            return RepositoryError.invalidState("Réponse inattendue du serveur.")
        }
        return RepositoryError.network(error.localizedDescription)
    }

    /// "+225 07 00 00 00 01" / "00225…" → "+2250700000001" (E.164).
    static func normalizedPhone(_ raw: String) -> String {
        var digits = raw.filter { $0.isNumber || $0 == "+" }
        if digits.hasPrefix("00") { digits = "+" + digits.dropFirst(2) }
        if !digits.hasPrefix("+") { digits = "+" + digits }
        return digits
    }

    /// Keeps PostgREST `or=(...)` syntax safe: drops reserved characters.
    static func sanitizedSearch(_ raw: String) -> String {
        let reserved = Set(",()*:\"\\%.'")
        let cleaned = raw.filter { !reserved.contains($0) }
        return String(cleaned.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
    }
}
