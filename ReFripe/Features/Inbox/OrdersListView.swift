import SwiftUI

/// Profil › Mon activité › « Mes achats ».
struct PurchasesListView: View {
    var body: some View { OrdersListView(role: .buyer) }
}

/// Profil › Mon activité › « Mes ventes ».
struct SalesListView: View {
    var body: some View { OrdersListView(role: .seller) }
}

/// My orders on one side: « En cours » (most urgent first), my negotiations (buyer side), then history.
/// Rows open the order tracking (or the conversation for a negotiation). Pushed screen with its own title.
@MainActor
struct OrdersListView: View {
    let role: OrderRole

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var data: InboxData?
    @State private var loadError: Error?

    var body: some View {
        Group {
            if let data {
                list(data)
            } else if let loadError {
                ErrorStateView(error: loadError) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rfScreenBackground()
        .navigationTitle(role == .buyer ? "Mes achats" : "Mes ventes")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onAppear { if data != nil { Task { await load() } } }
    }

    private func load() async {
        do {
            let parts: InboxData.Parts = role == .buyer ? [.orders, .offers] : [.orders]
            data = try await InboxData.load(store: store, parts: parts, previous: data)
            loadError = nil
        } catch {
            if data == nil { loadError = error } else { store.show(error) }
        }
    }

    // MARK: List

    private func list(_ data: InboxData) -> some View {
        let open = data.openOrders(role)
        let past = data.pastOrders(role)
        let threads = role == .buyer ? data.openBuyerThreads : []
        return List {
            Group {
            if !open.isEmpty {
                Section {
                    ForEach(open) { OrderListRow(order: $0) }
                } header: { header("En cours") }
            }
            if !threads.isEmpty {
                Section {
                    ForEach(threads) { t in
                        OrdersOfferRow(thread: t, listing: data.listings[t.listingId],
                                       subtitle: t.awaitsBuyerAnswer
                                           ? "Contre-offre"
                                           : "En attente",
                                       amount: t.rounds.last?.amount) {
                            router.push(.offerThread(t.listingId))
                        }
                    }
                } header: { header("Offres") }
            }
            if !past.isEmpty {
                Section {
                    ForEach(past) { OrderListRow(order: $0) }
                } header: { header(role == .buyer ? "Terminés" : "Terminées") }
            }
                    }
            .listRowBackground(RF.C.card)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(24)
        .scrollContentBackground(.hidden)
        .refreshable { await load() }
        .overlay {
            if open.isEmpty && past.isEmpty && threads.isEmpty {
                ContentUnavailableView {
                    Label(role == .buyer ? "Aucun achat" : "Aucune vente",
                          systemImage: role == .buyer ? "bag" : "tag")
                }
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(RF.T.footnote.weight(.semibold))
            .foregroundStyle(RF.C.textDim)
            .textCase(nil)
    }
}

/// Negotiation row: photo, listing title, who / when, amount on the right.
struct OrdersOfferRow: View {
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
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("Mes achats") {
    NavigationStack { PurchasesListView().withAppRoutes() }
        .previewEnvironment()
}

#Preview("Mes ventes") {
    NavigationStack { SalesListView().withAppRoutes() }
        .previewEnvironment()
}
