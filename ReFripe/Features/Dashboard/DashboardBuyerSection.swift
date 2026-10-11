import SwiftUI

/// Buyer side of the dashboard (mockup `buyerDashboardSection` + `computeBuyerStats`).
struct DashboardBuyerSection: View {
    let data: DashboardData

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashboardGreeting(symbol: "bag", title: "Bienvenue \(store.me?.firstName ?? ""), voici ton activité",
                              subtitle: "Tes achats et tes négociations")

            LazyVGrid(columns: columns, spacing: 10) {
                StatTile(title: "Achats", value: Fmt.number(data.paidOrders.count), symbol: "cart")
                StatTile(title: "Dépensé", value: Fmt.fcfa(data.spent), symbol: "banknote")
                StatTile(title: "Économisé en négociant", value: Fmt.fcfa(data.savedByNegotiating), symbol: "arrow.left.arrow.right")
                StatTile(title: "Envies", value: Fmt.number(store.wishlist.count), symbol: "heart")
            }
            .padding(.bottom, 16)

            forYou
            negotiationsCard
            priceDrops
            ordersCard(title: "Commandes en cours", orders: data.openPurchases,
                       empty: "Aucune commande en cours. Tes achats apparaîtront ici, paiement protégé par séquestre.")
            if !data.pastPurchases.isEmpty {
                ordersCard(title: "Historique", orders: data.pastPurchases, empty: "")
            }
        }
    }

    // MARK: "Pour toi"

    @ViewBuilder private var forYou: some View {
        DashCardLabel("Pour toi")
            .padding(.bottom, 12)
        if let order = data.needsConfirmation {
            DashRecoCard(symbol: "shippingbox", title: "Une commande attend ta confirmation",
                         message: "\(order.listingTitle) a été livrée — confirme la réception pour libérer le paiement à la vendeuse.",
                         cta: "Voir la commande") { router.push(.order(order.id)) }
        }
        if let drop = data.droppedWishes.first {
            DashRecoCard(symbol: "chart.line.downtrend.xyaxis", title: "Le prix de \(drop.title) a baissé",
                         message: "Passé à \(Fmt.fcfa(drop.price)), directement depuis ta liste d'envies.",
                         cta: "Voir l'annonce") { router.push(.product(drop.id)) }
        }
        if let thread = data.pendingThreads.first {
            let count = data.pendingThreads.count
            DashRecoCard(symbol: "arrow.left.arrow.right",
                         title: count > 1 ? "\(count) négociations en attente" : "Une négociation en attente",
                         message: thread.lastSellerCounter != nil && thread.rounds.last?.by == .seller
                            ? "La vendeuse t'a fait une contre-offre : à toi de répondre."
                            : "La vendeuse n'a pas encore répondu à ta dernière offre.",
                         cta: "Voir la négociation") { router.push(.offerThread(thread.listingId)) }
        }
        DashRecoCard(symbol: "sparkles", title: newInSizeTitle,
                     message: "Des vendeuses près de chez toi ont publié cette semaine — direction Découvrir pour y jeter un œil.",
                     cta: "Découvrir") {
            router.popToRoot(.discover)
            router.selectedTab = .discover
        }
    }

    private var newInSizeTitle: String {
        if let size = store.preferences.sizes[.haut] { return "Nouveautés en taille \(size)" }
        return "Nouveautés près de chez toi"
    }

    // MARK: Pending negotiations

    @ViewBuilder private var negotiationsCard: some View {
        let threads = data.pendingThreads
        if !threads.isEmpty {
            DashCard {
                DashCardLabel("Négociations en attente", symbol: "arrow.left.arrow.right")
                    .padding(.bottom, 4)
                ForEach(threads) { thread in
                    Button { router.push(.offerThread(thread.listingId)) } label: {
                        negotiationRow(thread)
                    }
                    .buttonStyle(.plain)
                    if thread.id != threads.last?.id { Divider().overlay(RF.C.line) }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
    }

    private func negotiationRow(_ thread: OfferThread) -> some View {
        let listing = data.listings[thread.listingId]
        let sellerTurn = thread.rounds.last?.by == .buyer
        return HStack(spacing: 10) {
            ListingPhotoView(photo: listing?.photos.first, listingId: thread.listingId)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: RF.R.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(listing?.title ?? "Article")
                    .font(RF.F.body(12.5, .bold))
                    .foregroundStyle(RF.C.text)
                    .lineLimit(1)
                Text(sellerTurn
                     ? "Ton offre · en attente de la vendeuse"
                     : "Contre-offre reçue · \(Fmt.relative(thread.updatedAt))")
                    .font(RF.F.body(10.5))
                    .foregroundStyle(sellerTurn ? RF.C.textDim : RF.C.hibiscus)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                if let last = thread.rounds.last {
                    Text(Fmt.fcfa(last.amount))
                        .font(RF.F.mono(12.5))
                        .foregroundStyle(RF.C.text)
                }
                if let price = listing?.price {
                    Text(Fmt.fcfa(price))
                        .font(RF.F.mono(10))
                        .strikethrough()
                        .foregroundStyle(RF.C.textDim)
                }
            }
            .fixedSize()
            Text("\(thread.buyerOfferCount)/\(OfferRules.maxBuyerOffers)")
                .font(RF.F.mono(9.5, .semibold))
                .foregroundStyle(RF.C.textDim)
                .padding(.vertical, 2)
                .padding(.horizontal, 5)
                .background(Capsule().fill(RF.C.card))
                .accessibilityLabel("\(thread.buyerOfferCount) offres sur \(OfferRules.maxBuyerOffers)")
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Wishlist price drops

    @ViewBuilder private var priceDrops: some View {
        let drops = data.droppedWishes
        if !drops.isEmpty {
            HStack {
                DashCardLabel("Tes envies en baisse", symbol: "chart.line.downtrend.xyaxis")
                Spacer()
                Button("Toutes mes envies") {
                    router.popToRoot(.wishlist)
                    router.selectedTab = .wishlist
                }
                .font(RF.F.body(11, .bold))
                .foregroundStyle(RF.C.hibiscus)
            }
            .padding(.top, 10)
            .padding(.bottom, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(drops) { listing in
                        VStack(alignment: .leading, spacing: 4) {
                            ListingCard(listing: listing)
                            if let drop = listing.priceDrop {
                                Text("−\(Fmt.fcfa(drop))")
                                    .font(RF.F.mono(10, .semibold))
                                    .foregroundStyle(RF.C.moneyDeep)
                                    .padding(.leading, 4)
                            }
                        }
                        .frame(width: 150)
                    }
                }
                .padding(.horizontal, RF.S.gutter)
            }
            .padding(.horizontal, -RF.S.gutter)
            .padding(.bottom, 16)
        }
    }

    // MARK: Orders

    private func ordersCard(title: String, orders: [Order], empty: String) -> some View {
        DashCard {
            DashCardLabel(title)
                .padding(.bottom, 4)
            if orders.isEmpty {
                Text(empty)
                    .font(RF.F.body(10.5))
                    .foregroundStyle(RF.C.textDim)
                    .lineSpacing(2)
                    .padding(.top, 6)
            } else {
                ForEach(orders) { order in
                    Button { router.push(.order(order.id)) } label: {
                        ProfileOrderLine(order: order, subtitle: "\(order.delivery.label) · \(Fmt.relative(order.createdAt))")
                    }
                    .buttonStyle(.plain)
                    if order.id != orders.last?.id { Divider().overlay(RF.C.line) }
                }
            }
        }
        .padding(.bottom, 12)
    }
}

#Preview {
    NavigationStack {
        ScrollView { DashboardBuyerSection(data: DashboardData()).padding() }
            .rfScreenBackground()
            .withAppRoutes()
    }
    .previewEnvironment()
}
