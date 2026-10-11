import SwiftUI

/// Which hat the dashboard shows. Persisted so the profile shortcuts can open it on the right side.
enum DashboardMode: String, CaseIterable, Identifiable {
    case sell, buy
    static let storageKey = "rf.dashboard.mode"
    var id: String { rawValue }
    var label: String { self == .sell ? "Ventes" : "Achats" }
}

/// One dashboard, two hats (mockup `screenDashboard`, PANEL `dashboard`): a segmented switch between
/// the seller view (goal, tier, stats, weekly views, orders to process, recommendations) and the buyer
/// view (spent / saved, pending negotiations, wishlist price drops, orders).
struct DashboardView: View {
    @Environment(AppStore.self) private var store
    @AppStorage(DashboardMode.storageKey) private var mode: DashboardMode = .sell
    @Namespace private var segmentNS

    @State private var data = DashboardData()
    @State private var isLoaded = false
    @State private var loadError: Error?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                segmented
                    .padding(.horizontal, RF.S.gutter)
                    .padding(.top, 14)

                Group {
                    if !isLoaded {
                        if let loadError {
                            ErrorStateView(error: loadError) { Task { await load() } }
                        } else {
                            LoadingView().frame(minHeight: 320)
                        }
                    } else if mode == .sell {
                        DashboardSellerSection(data: data)
                            .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)).combined(with: .opacity))
                    } else {
                        DashboardBuyerSection(data: data)
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)).combined(with: .opacity))
                    }
                }
                .padding(RF.S.gutter)
            }
            .animation(.snappy(duration: 0.3), value: mode)
        }
        .rfScreenBackground()
        .refreshable { await load() }
        .task { await load() }
        .navigationTitle("Tableau de bord")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: mode)
    }

    /// Mockup `.segmented` / `.seg-btn`: paper-dim capsule, white thumb.
    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(DashboardMode.allCases) { m in
                let selected = m == mode
                Button {
                    withAnimation(.snappy(duration: 0.25)) { mode = m }
                } label: {
                    Text(m.label)
                        .font(RF.F.body(12, .bold))
                        .foregroundStyle(selected ? RF.C.text : RF.C.textDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(RF.C.card)
                                    .shadow(color: RF.C.text.opacity(0.1), radius: 3, y: 2)
                                    .matchedGeometryEffect(id: "thumb", in: segmentNS)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(RF.C.paperDim))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Afficher")
    }

    private func load() async {
        do {
            data = try await DashboardData.load(store: store)
            isLoaded = true
            loadError = nil
        } catch {
            if isLoaded { store.show(error) } else { loadError = error }
        }
    }
}

// MARK: - Data

/// Everything both sections need, loaded in one go so switching tabs is instant.
struct DashboardData {
    var stats: SellerStats?
    var recommendations: [SellerRecommendation] = []
    var sellerOrders: [Order] = []
    var buyerOrders: [Order] = []
    var buyerThreads: [OfferThread] = []
    var sellerThreads: [OfferThread] = []
    /// Buyers of `sellerThreads`, for their public handle.
    var buyers: [UUID: UserProfile] = [:]
    /// Listings referenced by buyer threads and the wishlist.
    var listings: [UUID: Listing] = [:]
    var wishlistIds: Set<UUID> = []

    @MainActor
    static func load(store: AppStore) async throws -> DashboardData {
        let repo = store.repo
        async let statsTask = try? repo.sellerStats()
        async let recosTask = try? repo.recommendations()
        async let threadsTask = try? repo.offerThreads(role: .buyer)
        async let sellerThreadsTask = try? repo.offerThreads(role: .seller)
        let sellerOrders = try await repo.orders(role: .seller)
        let buyerOrders = try await repo.orders(role: .buyer)

        var data = DashboardData()
        data.sellerOrders = sellerOrders
        data.buyerOrders = buyerOrders
        data.stats = await statsTask
        data.recommendations = await recosTask ?? []
        data.buyerThreads = (await threadsTask ?? []).sorted { $0.updatedAt > $1.updatedAt }
        data.sellerThreads = (await sellerThreadsTask ?? []).sorted { $0.updatedAt > $1.updatedAt }
        data.wishlistIds = store.wishlist

        let buyerIds = Array(Set(data.receivedOffers.map(\.buyerId)))
        if !buyerIds.isEmpty {
            data.buyers = (try? await repo.profiles(ids: buyerIds)) ?? [:]
            store.cache(data.buyers)
        }

        let ids = Set(data.buyerThreads.map(\.listingId))
            .union(data.receivedOffers.map(\.listingId))
            .union(store.wishlist)
        data.listings = await withTaskGroup(of: Listing?.self) { group in
            for id in ids { group.addTask { try? await repo.listing(id: id) } }
            var out: [UUID: Listing] = [:]
            for await listing in group { if let listing { out[listing.id] = listing } }
            return out
        }
        return data
    }

    // Seller
    var ordersToProcess: [Order] {
        sellerOrders.filter { $0.status.isOpenForDashboard }
            .sorted { a, b in
                a.status.urgencyRank != b.status.urgencyRank
                    ? a.status.urgencyRank < b.status.urgencyRank
                    : a.createdAt > b.createdAt
            }
    }

    /// Offers on my listings waiting for my answer (pending, last round by the buyer).
    var receivedOffers: [OfferThread] {
        sellerThreads.filter { $0.status == .pending && $0.rounds.last?.by == .buyer }
    }

    // Buyer
    var paidOrders: [Order] { buyerOrders.filter { $0.status != .cancelled && $0.status != .refunded && $0.status != .paymentPending } }
    var spent: FCFA { paidOrders.reduce(0) { $0 + $1.total } }
    /// Sum of (listing price − accepted offer) over the negotiations I won.
    var savedByNegotiating: FCFA {
        buyerThreads.reduce(0) { sum, thread in
            guard let accepted = thread.acceptedAmount, let listing = listings[thread.listingId] else { return sum }
            return sum + max(0, listing.price - accepted)
        }
    }
    var pendingThreads: [OfferThread] { buyerThreads.filter { $0.status == .pending } }
    var droppedWishes: [Listing] {
        wishlistIds.compactMap { listings[$0] }
            .filter { $0.priceDrop != nil && $0.status == .active }
            .sorted { ($0.priceDrop ?? 0) > ($1.priceDrop ?? 0) }
    }
    var openPurchases: [Order] {
        buyerOrders.filter { $0.status.isOpenForDashboard }.sorted { $0.status.urgencyRank < $1.status.urgencyRank }
    }
    var pastPurchases: [Order] {
        buyerOrders.filter { !$0.status.isOpenForDashboard }.sorted { $0.createdAt > $1.createdAt }
    }
    var needsConfirmation: Order? {
        buyerOrders.first { $0.status == .buyerValidation || $0.status == .delivered }
    }
}

#Preview {
    NavigationStack { DashboardView().withAppRoutes() }
        .previewEnvironment()
}
