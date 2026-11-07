import SwiftUI

// Screens pushed from Profil › « Mon activité » and « Mon dressing ».

// MARK: - Versements

/// « Versements »: my sales once paid, with the amount and « En attente » (still in escrow) / « Versé » (completed).
/// No payout API yet: the state is derived from the order status.
struct PayoutsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var orders: [Order]?
    @State private var loadError: Error?

    /// Sales whose money is (or was) in escrow: paid and not cancelled / refunded.
    static func payoutOrders(_ sellerOrders: [Order]) -> [Order] {
        sellerOrders
            .filter { ![.paymentPending, .cancelled, .refunded].contains($0.status) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func isPaidOut(_ order: Order) -> Bool { order.status == .completed }

    var body: some View {
        Group {
            if let orders {
                if orders.isEmpty {
                    EmptyStateView(symbol: "banknote", title: "Aucun versement",
                                   message: "Tes ventes payées arrivent ici.")
                } else {
                    list(orders)
                }
            } else if let loadError {
                ErrorStateView(error: loadError) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .rfScreenBackground()
        .navigationTitle("Versements")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func list(_ orders: [Order]) -> some View {
        let paid = orders.filter(Self.isPaidOut).reduce(0) { $0 + $1.itemPrice }
        let pending = orders.filter { !Self.isPaidOut($0) }.reduce(0) { $0 + $1.itemPrice }
        return List {
            Group {
            Section {
                HStack(spacing: 12) {
                    total("Versé", paid, color: RF.C.moneyDeep)
                    Divider().frame(height: 36)
                    total("En attente", pending, color: RF.C.text)
                }
                .padding(.vertical, 4)
            } footer: {
                Text("Hors commission")
            }
            Section("Ventes") {
                ForEach(orders) { order in
                    Button { router.push(.order(order.id)) } label: { row(order) }
                        .buttonStyle(.plain)
                }
            }
                    }
            .listRowBackground(RF.C.card)
        }
        .listStyle(.insetGrouped)
    }

    private func total(_ title: String, _ amount: FCFA, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Fmt.fcfa(amount))
                .font(RF.T.price(.title3))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(RF.T.footnote)
                .foregroundStyle(RF.C.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func row(_ order: Order) -> some View {
        let done = Self.isPaidOut(order)
        return HStack(spacing: 12) {
            ListingPhotoView(photo: order.listingPhoto, listingId: order.listingId)
                .frame(width: 44, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(order.listingTitle)
                    .font(RF.T.subheadline.weight(.semibold))
                    .foregroundStyle(RF.C.text)
                    .lineLimit(1)
                Text("\(order.buyerName) · \(Fmt.relative(order.createdAt))")
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.textDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.fcfa(order.itemPrice))
                    .font(RF.T.price(.subheadline))
                    .foregroundStyle(RF.C.text)
                Text(done ? "Versé" : "En attente")
                    .font(RF.T.caption.weight(.medium))
                    .foregroundStyle(done ? RF.C.moneyDeep : RF.C.textDim)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(order.listingTitle), \(Fmt.fcfa(order.itemPrice)), \(done ? "versé" : "en attente")")
        .accessibilityAddTraits(.isButton)
    }

    private func load() async {
        do {
            orders = Self.payoutOrders(try await store.repo.orders(role: .seller))
            loadError = nil
        } catch {
            if orders == nil { loadError = error } else { store.show(error) }
        }
    }
}

// MARK: - Mon dressing (full grid)

/// « Tout voir » of my dressing: every listing (active first) with « Réservé » / « Vendu » badges.
struct MyDressingView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var listings: [Listing]?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        Group {
            if let listings {
                if listings.isEmpty {
                    EmptyStateView(symbol: "hanger", title: "Ton dressing est vide",
                                   message: "Publie ton premier article.",
                                   actionTitle: "Vendre un article") { router.isSellPresented = true }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(listings) { listing in
                                ListingCard(listing: listing)
                                    .overlay(alignment: .topLeading) { ListingStatusBadge(listing: listing) }
                            }
                        }
                        .padding(.horizontal, RF.S.gutter)
                        .padding(.vertical, RF.S.lg)
                    }
                }
            } else {
                LoadingView()
            }
        }
        .rfScreenBackground()
        .navigationTitle("Mon dressing")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let me = store.me else { listings = []; return }
        do {
            listings = ProfileTabView.sortedDressing(try await store.repo.listings(sellerId: me.id))
        } catch {
            if listings == nil { listings = [] }
            store.show(error)
        }
    }
}

#Preview("Versements") {
    NavigationStack { PayoutsView().withAppRoutes() }
        .previewEnvironment()
}

#Preview("Dressing") {
    NavigationStack { MyDressingView().withAppRoutes() }
        .previewEnvironment()
}
