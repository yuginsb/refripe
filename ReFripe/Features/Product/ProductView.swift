import SwiftUI

/// Product page: big photo, price + title, attributes, description, seller row, delivery rows and a
/// sticky action bar (Faire une offre + Acheter; on my own listing: Offres reçues + Statistiques).
struct ProductView: View {
    let listingId: UUID

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var listing: Listing?
    @State private var seller: UserProfile?
    @State private var thread: OfferThread?
    @State private var loadError: Error?
    @State private var didRecordView = false
    @State private var isOpeningChat = false
    @State private var photoIndex = 0
    /// Seller side: offers waiting for my answer on my own listing.
    @State private var pendingReceivedOffers = 0

    var body: some View {
        Group {
            if let listing {
                content(listing)
            } else if let loadError {
                ErrorStateView(error: loadError) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rfScreenBackground()
        .navigationTitle("Annonce")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let listing {
                ToolbarItem(placement: .topBarTrailing) {
                    ProductShareButton(listing: listing)
                }
            }
        }
        .task { await load() }
    }

    // MARK: Data

    private var isMine: Bool {
        guard let listing, let me = store.me?.id else { return false }
        return listing.sellerId == me
    }

    /// Accepted offer amount, from this session or from the server thread.
    private var negotiatedPrice: FCFA? {
        store.negotiatedPrices[listingId] ?? thread?.acceptedAmount
    }

    private func load() async {
        do {
            let l = try await store.repo.listing(id: listingId)
            listing = l
            loadError = nil
            seller = await store.profile(l.sellerId)
            if l.sellerId != store.me?.id, l.negotiable {
                thread = try? await store.repo.offerThread(listingId: listingId)
            } else if l.sellerId == store.me?.id {
                let received = (try? await store.repo.offerThreads(role: .seller)) ?? []
                pendingReceivedOffers = received.filter {
                    $0.listingId == listingId && $0.status == .pending && $0.rounds.last?.by == .buyer
                }.count
            }
            if !didRecordView {
                didRecordView = true
                await store.repo.recordView(listingId: listingId)
            }
        } catch {
            if listing == nil { loadError = error } else { store.show(error) }
        }
    }

    // MARK: Layout

    private func content(_ listing: Listing) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                gallery(listing)
                VStack(alignment: .leading, spacing: RF.S.xl) {
                    priceBlock(listing)
                    if listing.status != .active { unavailableNote(listing) }
                    ProductAttributes(listing: listing)
                    descriptionBlock(listing)
                    sellerRow(listing)
                    section("Livraison") {
                        ProductDeliveryList(methods: listing.deliveryMethods)
                    }
                    escrowNote
                }
                .padding(EdgeInsets(top: RF.S.lg, leading: RF.S.gutter, bottom: RF.S.xl, trailing: RF.S.gutter))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar(listing) }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: RF.S.sm) {
            Text(title)
                .font(RF.T.footnote.weight(.semibold))
                .foregroundStyle(RF.C.textDim)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    // MARK: Gallery

    private func gallery(_ listing: Listing) -> some View {
        let photos: [ListingPhoto?] = listing.photos.isEmpty ? [nil] : listing.photos.map { Optional($0) }
        return TabView(selection: $photoIndex) {
            ForEach(Array(photos.enumerated()), id: \.offset) { pair in
                ListingPhotoView(photo: pair.element, listingId: listing.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(pair.offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
        .frame(height: 440)
        .background(RF.C.thumb(for: listing.id))
        .overlay(alignment: .bottomLeading) {
            ListingScarcityTag(listing: listing).padding(RF.S.md)
        }
        .overlay(alignment: .topTrailing) {
            HeartButton(listingId: listing.id, size: 36).padding(RF.S.md)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Photos de l'article, \(listing.photos.count) photo\(listing.photos.count > 1 ? "s" : "")")
    }

    // MARK: Price & title

    private func priceBlock(_ listing: Listing) -> some View {
        let shown = negotiatedPrice ?? listing.price
        let strike: FCFA? = negotiatedPrice != nil ? listing.price : listing.oldPrice
        return VStack(alignment: .leading, spacing: RF.S.xs) {
            HStack(alignment: .firstTextBaseline, spacing: RF.S.sm) {
                Text(Fmt.fcfa(shown))
                    .font(RF.T.price(.title2, weight: .bold))
                    .foregroundStyle(RF.C.text)
                if let strike, strike > shown {
                    Text(Fmt.fcfa(strike))
                        .font(RF.T.price(.subheadline, weight: .regular))
                        .strikethrough()
                        .foregroundStyle(RF.C.textDim)
                        .accessibilityLabel("au lieu de \(Fmt.fcfa(strike))")
                }
                if negotiatedPrice != nil {
                    Text("Prix négocié")
                        .font(RF.T.footnote.weight(.semibold))
                        .foregroundStyle(RF.C.moneyDeep)
                }
            }
            .accessibilityElement(children: .combine)
            Text(listing.title)
                .font(RF.T.title3)
                .foregroundStyle(RF.C.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(metaLine(listing))
                .font(RF.T.footnote)
                .foregroundStyle(RF.C.textDim)
                .lineLimit(2)
        }
    }

    private func metaLine(_ listing: Listing) -> String {
        var parts = [listing.locationLabel, Fmt.relative(listing.createdAt)]
        if negotiatedPrice == nil, !isMine { parts.append(listing.negotiable ? "Ouvert aux offres" : "Prix fixe") }
        return parts.joined(separator: " · ")
    }

    private func unavailableNote(_ listing: Listing) -> some View {
        let text: String = switch listing.status {
        case .reserved: "Réservé : une commande est en cours."
        case .sold: "Vendu."
        default: "Plus disponible."
        }
        return Label(text, systemImage: "clock")
            .font(RF.T.subheadline)
            .foregroundStyle(RF.C.text)
            .padding(RF.S.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RF.C.paperDim, in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
    }

    // MARK: Seller

    private func sellerRow(_ listing: Listing) -> some View {
        HStack(spacing: RF.S.md) {
            Button {
                router.push(.sellerProfile(listing.sellerId))
            } label: {
                HStack(spacing: RF.S.md) {
                    Avatar(profile: seller, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: RF.S.xs) {
                            Text(seller?.username ?? "Vendeuse")
                                .font(RF.T.headline)
                                .foregroundStyle(RF.C.text)
                                .lineLimit(1)
                            if seller?.verified == true { VerifiedBadge() }
                        }
                        if let seller {
                            Text(sellerSubtitle(seller))
                                .font(RF.T.footnote)
                                .foregroundStyle(RF.C.textDim)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RFPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Voir le profil de la vendeuse")

            if !isMine {
                Button {
                    openChat(listing)
                } label: {
                    if isOpeningChat {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Écrire")
                    }
                }
                .font(RF.T.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(RF.C.text)
                .disabled(isOpeningChat)
                .accessibilityLabel("Écrire à \(seller?.username ?? "la vendeuse")")
            }
        }
        .padding(RF.S.md)
        .background(RF.C.card, in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
    }

    private func sellerSubtitle(_ s: UserProfile) -> String {
        let rating = s.rating.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_FR")))
        return "★ \(rating) · \(s.salesCount) vente\(s.salesCount > 1 ? "s" : "")"
    }

    private func openChat(_ listing: Listing) {
        isOpeningChat = true
        Task {
            defer { isOpeningChat = false }
            do {
                let conv = try await store.repo.conversation(withUser: listing.sellerId, listingId: listing.id)
                router.push(.chat(conv.id))
            } catch {
                store.show(error)
            }
        }
    }

    // MARK: Description / defects

    private func descriptionBlock(_ listing: Listing) -> some View {
        section("Description") {
            VStack(alignment: .leading, spacing: RF.S.md) {
                Text(listing.description.isEmpty ? "Pas de description." : listing.description)
                    .font(RF.T.body)
                    .foregroundStyle(listing.description.isEmpty ? RF.C.textDim : RF.C.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let defect = listing.defectComment, !defect.isEmpty {
                    Label {
                        Text("Défaut signalé : \(defect)")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .font(RF.T.subheadline)
                    .foregroundStyle(RF.C.text)
                }
            }
        }
    }

    private var escrowNote: some View {
        Label("Paiement protégé jusqu'à la réception", systemImage: "lock.shield")
            .font(RF.T.footnote)
            .foregroundStyle(RF.C.moneyDeep)
    }

    // MARK: Sticky action bar

    @ViewBuilder
    private func actionBar(_ listing: Listing) -> some View {
        VStack(spacing: RF.S.sm) {
            if isMine {
                HStack(spacing: RF.S.md) {
                    if listing.negotiable {
                        RFButton(receivedOffersTitle, style: pendingReceivedOffers > 0 ? .primary : .secondary) {
                            router.push(.receivedOffers(listing.id))
                        }
                    }
                    RFButton("Statistiques", style: listing.negotiable ? .ghost : .secondary) {
                        router.push(.dashboard)
                    }
                }
            } else if listing.status != .active {
                RFButton("Indisponible", style: .secondary) {}
                    .disabled(true)
            } else {
                buyerActions(listing)
            }
        }
        .padding(EdgeInsets(top: RF.S.md, leading: RF.S.gutter, bottom: RF.S.sm, trailing: RF.S.gutter))
        .background(RF.C.paper)
        .overlay(alignment: .top) { Rectangle().fill(RF.C.line).frame(height: 0.5) }
    }

    private var receivedOffersTitle: String {
        let n = pendingReceivedOffers
        return n == 0 ? "Offres reçues" : "Offres reçues (\(n))"
    }

    @ViewBuilder
    private func buyerActions(_ listing: Listing) -> some View {
        let price = negotiatedPrice ?? listing.price
        HStack(spacing: RF.S.md) {
            if listing.negotiable && negotiatedPrice == nil {
                if let thread, thread.status == .pending {
                    RFButton("Négociation", style: .secondary) {
                        router.push(.offerThread(listing.id))
                    }
                    .accessibilityLabel("Voir la négociation en cours")
                } else if thread == nil {
                    RFButton("Faire une offre", style: .secondary) {
                        router.push(.offer(listing.id))
                    }
                }
            }
            RFButton("Acheter") {
                if let negotiated = negotiatedPrice {
                    store.negotiatedPrices[listing.id] = negotiated
                }
                router.push(.checkout(listing.id))
            }
            .accessibilityLabel("Acheter pour \(Fmt.fcfa(price))")
            .accessibilityIdentifier("product.buy")
        }
    }
}

#Preview {
    NavigationStack {
        ProductView(listingId: DemoIDs.listing(3))
            .withAppRoutes()
    }
    .previewEnvironment()
}

#Preview("Mon annonce") {
    NavigationStack {
        ProductView(listingId: DemoIDs.listing(1))
            .withAppRoutes()
    }
    .previewEnvironment()
}
