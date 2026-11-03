import SwiftUI

/// « Profil » tab (v3): my public profile (header, Modifier / Partager), « Mon dressing » preview,
/// then « Mon activité » (Mes achats, Mes ventes, Versements, Statistiques, Aide sur WhatsApp). The gear opens Réglages.
struct ProfileTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var myListings: [Listing]?
    @State private var buyerOrders: [Order] = []
    @State private var sellerOrders: [Order] = []
    @State private var isEditing = false
    @State private var showReviews = false

    private static let previewCount = 3

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let me = store.me {
                    VStack(spacing: 16) {
                        ProfileHeroView(profile: me) { showReviews = true }
                        actions(me)
                    }
                    .padding(.top, 8)
                }
                dressing
                activity
            }
            .padding(.horizontal, RF.S.gutter)
            .padding(.bottom, 24)
        }
        .rfScreenBackground()
        .refreshable { await load() }
        .task { await load() }
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.push(.settings) } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Réglages")
            }
        }
        .navigationDestination(isPresented: $showReviews) {
            if let me = store.me { ReviewsListView(userId: me.id) }
        }
        .sheet(isPresented: $isEditing) {
            ProfileEditSheet()
                .environment(store)
                .presentationDetents([.large])
        }
    }

    // MARK: Header actions

    private func actions(_ me: UserProfile) -> some View {
        HStack(spacing: 12) {
            Button { isEditing = true } label: {
                Text("Modifier le profil").frame(maxWidth: .infinity)
            }
            ShareLink(item: AppLinks.profile(me.id),
                      message: Text("Mon dressing sur ReFripe")) {
                Label("Partager", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
        }
        .font(RF.T.subheadline.weight(.semibold))
        .foregroundStyle(RF.C.text)
        .buttonStyle(ProfileOutlineButtonStyle())
    }

    // MARK: Mon dressing (preview)

    @ViewBuilder private var dressing: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mon dressing")
                    .font(RF.T.title3)
                    .foregroundStyle(RF.C.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let myListings, !myListings.isEmpty {
                    NavigationLink {
                        MyDressingView()
                    } label: {
                        Text("Tout voir (\(myListings.count))")
                            .font(RF.T.subheadline.weight(.semibold))
                            .foregroundStyle(RF.C.hibiscusText)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("profile.dressing.all")
                }
            }
            if let myListings {
                if myListings.isEmpty {
                    ContentUnavailableView {
                        Label("Ton dressing est vide", systemImage: "hanger")
                    } description: {
                        Text("Publie ton premier article.")
                    } actions: {
                        Button("Vendre un article") { router.isSellPresented = true }
                            .buttonStyle(.borderedProminent)
                            .tint(RF.C.hibiscus)
                    }
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(myListings.prefix(Self.previewCount)) { listing in
                            thumbnail(listing)
                        }
                        // Keep thumbnails the same width when there are fewer than 3 listings.
                        ForEach(0..<max(0, Self.previewCount - myListings.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
        }
    }

    private func thumbnail(_ listing: Listing) -> some View {
        Button { router.push(.product(listing.id)) } label: {
            VStack(alignment: .leading, spacing: 4) {
                ListingPhotoView(photo: listing.photos.first, listingId: listing.id)
                    .aspectRatio(0.8, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        ListingStatusBadge(listing: listing)
                            .scaleEffect(0.9, anchor: .topLeading)
                    }
                Text(Fmt.fcfa(listing.price))
                    .font(RF.T.price(.footnote))
                    .foregroundStyle(RF.C.text)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(RFPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(listing.title), \(Fmt.fcfa(listing.price))\(statusSuffix(listing))")
        .accessibilityAddTraits(.isButton)
    }

    private func statusSuffix(_ listing: Listing) -> String {
        switch ListingStatusBadge(listing: listing).status {
        case .sold: ", vendu"
        case .reserved: ", réservé"
        default: ""
        }
    }

    // MARK: Mon activité

    private var openPurchases: Int { buyerOrders.filter { $0.status.isOpenForDashboard }.count }
    private var salesToShip: Int { sellerOrders.filter { [.paid, .awaitingShipment].contains($0.status) }.count }
    private var paidOut: FCFA {
        PayoutsView.payoutOrders(sellerOrders).filter(PayoutsView.isPaidOut).reduce(0) { $0 + $1.itemPrice }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mon activité")
                .font(RF.T.title3)
                .foregroundStyle(RF.C.text)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                NavigationLink {
                    PurchasesListView()
                } label: {
                    ActivityRow(symbol: "bag", title: "Mes achats",
                                detail: openPurchases > 0 ? "\(openPurchases) en cours" : nil)
                }
                .accessibilityIdentifier("profile.activity.purchases")
                divider
                NavigationLink {
                    SalesListView()
                } label: {
                    ActivityRow(symbol: "shippingbox", title: "Mes ventes",
                                detail: salesToShip > 0 ? "\(salesToShip) à expédier" : nil,
                                highlight: salesToShip > 0)
                }
                .accessibilityIdentifier("profile.activity.sales")
                divider
                NavigationLink {
                    PayoutsView()
                } label: {
                    ActivityRow(symbol: "banknote", title: "Versements",
                                detail: paidOut > 0 ? Fmt.fcfa(paidOut) : nil)
                }
                .accessibilityIdentifier("profile.activity.payouts")
                divider
                Button { router.push(.dashboard) } label: {
                    ActivityRow(symbol: "chart.bar", title: "Statistiques", detail: nil)
                }
                .accessibilityIdentifier("profile.activity.stats")
                divider
                SupportWhatsAppButton {
                    ActivityRow(symbol: "message", title: "Aide sur WhatsApp", detail: nil, external: true)
                }
                .accessibilityIdentifier("profile.activity.help")
            }
            .buttonStyle(.plain)
            .rfCard()
        }
    }

    private var divider: some View {
        Divider().overlay(RF.C.line).padding(.leading, 52)
    }

    // MARK: Data

    /// Active first, then reserved / sold; newest first inside each group. Removed listings are hidden.
    static func sortedDressing(_ listings: [Listing]) -> [Listing] {
        listings
            .filter { $0.status != .removed }
            .sorted { a, b in
                let ra = a.status == .active ? 0 : 1
                let rb = b.status == .active ? 0 : 1
                return ra != rb ? ra < rb : a.createdAt > b.createdAt
            }
    }

    private func load() async {
        guard let me = store.me else { return }
        let repo = store.repo
        async let listingsTask = try? repo.listings(sellerId: me.id)
        async let buyerTask = try? repo.orders(role: .buyer)
        async let sellerTask = try? repo.orders(role: .seller)
        let (listings, bought, sold) = await (listingsTask, buyerTask, sellerTask)
        myListings = Self.sortedDressing(listings ?? [])
        buyerOrders = bought ?? []
        sellerOrders = sold ?? []
    }
}

/// One row of « Mon activité »: icon, title, optional detail, chevron (or an external-link arrow).
private struct ActivityRow: View {
    let symbol: String
    let title: String
    let detail: String?
    var highlight = false
    var external = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(RF.T.body)
                .foregroundStyle(RF.C.textDim)
                .frame(width: 28)
            Text(title)
                .font(RF.T.body)
                .foregroundStyle(RF.C.text)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(RF.T.subheadline.monospacedDigit())
                    .foregroundStyle(highlight ? RF.C.hibiscusText : RF.C.textDim)
                    .lineLimit(1)
            }
            Image(systemName: external ? "arrow.up.right" : "chevron.right")
                .font(RF.T.footnote.weight(.semibold))
                .foregroundStyle(RF.C.textDim.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.map { "\(title), \($0)" } ?? title)
    }
}

#Preview {
    NavigationStack { ProfileTabView().withAppRoutes() }
        .previewEnvironment()
}


/// Light outlined button for the profile header (white fill, hairline), lighter than `.bordered`.
private struct ProfileOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 11)
            .background(RF.C.card, in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: RF.R.md, style: .continuous).strokeBorder(RF.C.line))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
