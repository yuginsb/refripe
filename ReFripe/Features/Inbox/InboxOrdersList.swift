import SwiftUI

/// Boîte › Commandes: « Offres à traiter » on top when some negotiation waits for me, then
/// Achats / Ventes (in progress, then history). Rows open the order tracking or the offer screens.
struct InboxOrdersList: View {
    enum Side: String, CaseIterable, Identifiable {
        case purchases, sales
        static let storageKey = "rf.inbox.orders.side"
        var id: String { rawValue }
        var label: String { self == .purchases ? "Achats" : "Ventes" }
    }

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @AppStorage(Side.storageKey) private var side: Side = .purchases

    @State private var data = DashboardData()
    @State private var isLoaded = false
    @State private var loadError: Error?

    var body: some View {
        Group {
            if isLoaded {
                list
            } else if let loadError {
                ErrorStateView(error: loadError) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await load() }
        .onAppear { if isLoaded { Task { await load() } } }
    }

    // MARK: List

    private var list: some View {
        List {
            offersToHandle

            Section {
                Picker("Commandes", selection: $side) {
                    ForEach(Side.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            switch side {
            case .purchases:
                ordersSection("En cours", data.openPurchases, empty: "Aucun achat en cours")
                sentOffersSection
                ordersSection("Terminés", data.pastPurchases, empty: nil)
            case .sales:
                ordersSection("En cours", data.openSales, empty: "Aucune vente en cours")
                ordersSection("Terminées", data.pastSales, empty: nil)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(24)
        .refreshable { await load() }
        .animation(.snappy(duration: 0.25), value: side)
        .sensoryFeedback(.selection, trigger: side)
    }

    @ViewBuilder private var offersToHandle: some View {
        let seller = data.receivedOffers
        let buyer = data.counterOffers
        if !seller.isEmpty || !buyer.isEmpty {
            Section {
                ForEach(seller) { thread in
                    InboxOfferRow(thread: thread, listing: data.listings[thread.listingId],
                                   subtitle: "Offre de \(name(thread.buyerId, fallback: "une acheteuse"))",
                                   amount: thread.lastBuyerOffer?.amount) {
                        router.push(.receivedOffers(thread.listingId))
                    }
                }
                ForEach(buyer) { thread in
                    InboxOfferRow(thread: thread, listing: data.listings[thread.listingId],
                                   subtitle: "Contre-offre de \(name(thread.sellerId, fallback: "la vendeuse"))",
                                   amount: thread.lastSellerCounter?.amount) {
                        router.push(.offerThread(thread.listingId))
                    }
                }
            } header: {
                header("Offres à traiter")
            }
        }
    }

    @ViewBuilder private var sentOffersSection: some View {
        let sent = data.sentOffers
        if !sent.isEmpty {
            Section {
                ForEach(sent) { thread in
                    InboxOfferRow(thread: thread, listing: data.listings[thread.listingId],
                                   subtitle: "En attente de \(name(thread.sellerId, fallback: "la vendeuse"))",
                                   amount: thread.lastBuyerOffer?.amount) {
                        router.push(.offerThread(thread.listingId))
                    }
                }
            } header: {
                header("Offres envoyées")
            }
        }
    }

    @ViewBuilder private func ordersSection(_ title: String, _ orders: [Order], empty: String?) -> some View {
        if !orders.isEmpty {
            Section {
                ForEach(orders) { OrderListRow(order: $0) }
            } header: {
                header(title)
            }
        } else if let empty {
            Section {
                Text(empty)
                    .font(RF.T.subheadline)
                    .foregroundStyle(RF.C.textDim)
            } header: {
                header(title)
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(RF.T.footnote.weight(.semibold))
            .foregroundStyle(RF.C.textDim)
            .textCase(nil)
    }

    private func name(_ id: UUID, fallback: String) -> String {
        data.people[id]?.username ?? store.cachedProfile(id)?.username ?? fallback
    }

    // MARK: Data

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

// MARK: - Offer row

/// Negotiation row: photo, listing title, who / when, amount on the right.
struct InboxOfferRow: View {
    let thread: OfferThread
    let listing: Listing?
    let subtitle: String
    let amount: FCFA?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ListingPhotoView(photo: listing?.photos.first, listingId: thread.listingId)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(listing?.title ?? "Annonce")
                        .font(RF.T.subheadline.weight(.semibold))
                        .foregroundStyle(RF.C.text)
                        .lineLimit(1)
                    Text("\(subtitle) · \(Fmt.relative(thread.updatedAt))")
                        .font(RF.T.footnote)
                        .foregroundStyle(RF.C.textDim)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let amount {
                    Text(Fmt.fcfa(amount))
                        .font(RF.T.price(.subheadline))
                        .foregroundStyle(RF.C.text)
                        .fixedSize()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    NavigationStack { InboxOrdersList().navigationTitle("Commandes").withAppRoutes() }
        .previewEnvironment()
}
