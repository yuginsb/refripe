import SwiftUI

/// Fiche article (v3): full-bleed photo gallery with « 1 / N » and round back / share / heart / ⋯ buttons;
/// price, title, « Taille · État · Marque »; reservation note; green « Paiement protégé » block;
/// delivery line; seller row (★ note (n avis) · répond en ~x min); collapsible description;
/// sticky bar « Faire une offre » (opens the conversation, where offers live) / « Acheter ».
/// The tab bar and the navigation bar are hidden (own round buttons; edge-swipe back still works).
struct ProductView: View {
    let listingId: UUID

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var listing: Listing?
    @State private var seller: UserProfile?
    @State private var thread: OfferThread?
    @State private var loadError: Error?
    @State private var didRecordView = false
    @State private var isOpeningChat = false
    @State private var photoIndex = 0
    /// Seller side: offers waiting for my answer on my own listing.
    @State private var pendingReceivedOffers = 0
    @State private var descriptionExpanded = false
    @State private var showReport = false
    @State private var confirmBlock = false

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
        .overlay(alignment: .top) { topButtons }
        .rfScreenBackground()
        .navigationTitle("Annonce")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task { await load() }
        .sheet(isPresented: $showReport) {
            if let listing {
                ProductReportSheet(listingId: listing.id)
                    .environment(store)
            }
        }
        .confirmationDialog(blockTitle, isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Bloquer", role: .destructive) { block() }
            Button("Annuler", role: .cancel) {}
        }
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

    private var sellerName: String { seller?.username ?? "la vendeuse" }

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
                    $0.listingId == listingId && $0.awaitsSellerAnswer
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
                    statusNote(listing)
                    if !isMine { protectionBlock }
                    deliveryLine(listing)
                    sellerRow(listing)
                    descriptionBlock(listing)
                }
                .padding(EdgeInsets(top: RF.S.lg, leading: RF.S.gutter, bottom: RF.S.xl, trailing: RF.S.gutter))
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar(listing) }
    }

    // MARK: Round buttons over the photo

    private var topButtons: some View {
        HStack(spacing: RF.S.sm) {
            ProductRoundButton(symbol: "chevron.left", label: "Retour") { dismiss() }
            Spacer(minLength: 0)
            if let listing {
                ProductShareButton(listing: listing, round: true)
                if !isMine {
                    HeartButton(listingId: listing.id, size: 44)
                    Menu {
                        Button("Signaler l'annonce", systemImage: "flag") { showReport = true }
                        Button("Bloquer \(sellerName)", systemImage: "hand.raised", role: .destructive) {
                            confirmBlock = true
                        }
                    } label: {
                        ProductRoundIcon(symbol: "ellipsis")
                    }
                    .accessibilityLabel("Plus d'options")
                }
            }
        }
        .padding(.horizontal, RF.S.md)
        .padding(.top, RF.S.xs)
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
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 500)
        .background(RF.C.thumb(for: listing.id))
        .overlay(alignment: .bottomTrailing) {
            if photos.count > 1 {
                Text("\(photoIndex + 1) / \(photos.count)")
                    .font(RF.T.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(RF.C.textOnInk)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 9)
                    .background(Capsule().fill(RF.C.ink0.opacity(0.6)))
                    .padding(RF.S.md)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Photo \(photoIndex + 1) sur \(photos.count)")
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
            Text(attributesLine(listing))
                .font(RF.T.subheadline)
                .foregroundStyle(RF.C.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// « Taille M · Excellent état · Zara »
    private func attributesLine(_ listing: Listing) -> String {
        var parts = [listing.sizeLabel, listing.condition.label]
        let brand = listing.brand.trimmingCharacters(in: .whitespaces)
        if !brand.isEmpty, brand != "Sans marque précise" { parts.append(brand) }
        return parts.joined(separator: " · ")
    }

    // MARK: Reservation / availability

    @ViewBuilder
    private func statusNote(_ listing: Listing) -> some View {
        if listing.status == .sold || listing.status == .removed {
            note(listing.status == .sold ? "Vendu" : "Indisponible", symbol: "nosign")
        } else if listing.isReservedForSomeoneElse(me: store.me?.id), let until = listing.reservedUntil {
            note("Réservé jusqu'à \(ProductTime.hourMinute(until))", symbol: "clock")
                .accessibilityIdentifier("product.reserved")
        } else if !isMine, let until = listing.reservedUntil, until > .now, listing.reservedFor == store.me?.id {
            Label("Pour toi jusqu'à \(ProductTime.hourMinute(until))", systemImage: "checkmark.circle")
                .font(RF.T.subheadline.weight(.semibold))
                .foregroundStyle(RF.C.moneyDeep)
        } else if listing.status == .reserved {
            note("Commande en cours", symbol: "clock")
        }
    }

    private func note(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(RF.T.subheadline)
            .foregroundStyle(RF.C.text)
            .padding(RF.S.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RF.C.paperDim, in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
    }

    // MARK: Paiement protégé

    private var protectionBlock: some View {
        HStack(alignment: .top, spacing: RF.S.md) {
            Image(systemName: "lock.shield.fill")
                .font(RF.T.title3)
                .foregroundStyle(RF.C.moneyDeep)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Paiement protégé")
                    .font(RF.T.subheadline.weight(.semibold))
                    .foregroundStyle(RF.C.moneyDeep)
                Text("Argent bloqué jusqu'à réception.")
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(RF.S.md)
        .background(RF.C.money.opacity(0.10), in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Delivery line

    private func deliveryLine(_ listing: Listing) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: RF.S.md) {
            Image(systemName: "shippingbox")
                .foregroundStyle(RF.C.textDim)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(listing.district)
                    .font(RF.T.subheadline.weight(.semibold))
                    .foregroundStyle(RF.C.text)
                Text(deliverySummary(listing.deliveryMethods))
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// « Main propre gratuite, relais 1 000, Yango 2 500 » (cheapest first).
    private func deliverySummary(_ methods: [DeliveryMethod]) -> String {
        let sorted = methods.sorted { $0.fee < $1.fee }
        guard !sorted.isEmpty else { return "À convenir" }
        let parts = sorted.map { m -> String in
            switch m {
            case .mainPropre: "main propre gratuite"
            case .relais: "relais \(Fmt.number(m.fee))"
            case .yango: "Yango \(Fmt.number(m.fee))"
            }
        }
        let joined = parts.joined(separator: ", ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    // MARK: Seller

    private func sellerRow(_ listing: Listing) -> some View {
        HStack(spacing: RF.S.md) {
            Button {
                router.push(.sellerProfile(listing.sellerId))
            } label: {
                HStack(spacing: RF.S.md) {
                    Avatar(profile: seller, size: 44)
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
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(RFPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Voir le profil de la vendeuse")

            if !isMine {
                Button {
                    openChat(listing)
                } label: {
                    Text("Écrire")
                        .frame(minHeight: 32)
                }
                .font(RF.T.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(RF.C.text)
                .disabled(isOpeningChat)
                .accessibilityLabel("Écrire à \(sellerName)")
            }
        }
        .padding(RF.S.md)
        .background(RF.C.card, in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
    }

    /// « ★ 4,8 (23 avis) · répond en ~15 min »
    private func sellerSubtitle(_ s: UserProfile) -> String {
        var parts: [String] = []
        if s.reviewCount > 0 {
            let rating = s.rating.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_FR")))
            parts.append("★ \(rating) (\(s.reviewCount) avis)")
        } else {
            parts.append("Aucun avis")
        }
        if let minutes = s.responseTimeMinutes, minutes > 0 {
            parts.append(minutes < 60 ? "répond en ~\(minutes) min" : "répond en ~\(max(1, minutes / 60)) h")
        }
        return parts.joined(separator: " · ")
    }

    private func openChat(_ listing: Listing) {
        guard !isOpeningChat else { return }
        isOpeningChat = true
        Task {
            await ChatLauncher.open(with: listing.sellerId, listingId: listing.id, store: store, router: router)
            isOpeningChat = false
        }
    }

    // MARK: Description (collapsible) / defects

    private func descriptionBlock(_ listing: Listing) -> some View {
        let text = listing.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLong = text.count > 140 || text.contains("\n")
        return VStack(alignment: .leading, spacing: RF.S.sm) {
            Text("Description")
                .font(RF.T.footnote.weight(.semibold))
                .foregroundStyle(RF.C.textDim)
                .accessibilityAddTraits(.isHeader)
            Text(text.isEmpty ? "Pas de description." : text)
                .font(RF.T.body)
                .foregroundStyle(text.isEmpty ? RF.C.textDim : RF.C.text)
                .lineLimit(descriptionExpanded || !isLong ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            if isLong {
                Button(descriptionExpanded ? "Voir moins" : "Voir plus") {
                    withAnimation(.snappy) { descriptionExpanded.toggle() }
                }
                .font(RF.T.subheadline.weight(.semibold))
                .foregroundStyle(RF.C.hibiscusText)
                .frame(minHeight: 44, alignment: .leading)
                .buttonStyle(.plain)
            }
            if let defect = listing.defectComment, !defect.isEmpty {
                Label {
                    Text("Défaut : \(defect)")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(RF.T.subheadline)
                .foregroundStyle(RF.C.text)
            }
            let color = listing.color.trimmingCharacters(in: .whitespaces)
            Text(color.isEmpty ? "Publié \(Fmt.relative(listing.createdAt).lowercased())"
                               : "\(color) · publié \(Fmt.relative(listing.createdAt).lowercased())")
                .font(RF.T.footnote)
                .foregroundStyle(RF.C.textDim)
        }
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
            } else if listing.status == .sold || listing.status == .removed {
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

    /// Buying is blocked while another buyer holds the 2 h reservation, or while an order is in progress.
    private func canBuy(_ listing: Listing) -> Bool {
        if listing.isReservedForSomeoneElse(me: store.me?.id) { return false }
        if listing.status == .reserved {
            // Reserved for me after an accepted offer → I can pay; otherwise an order is in progress.
            guard let until = listing.reservedUntil, until > .now else { return false }
            return listing.reservedFor == store.me?.id
        }
        return listing.status == .active
    }

    @ViewBuilder
    private func buyerActions(_ listing: Listing) -> some View {
        let price = negotiatedPrice ?? listing.price
        HStack(spacing: RF.S.md) {
            if listing.negotiable && negotiatedPrice == nil {
                RFButton(thread?.status == .pending ? "Voir l'offre" : "Faire une offre", style: .secondary,
                         isLoading: isOpeningChat) {
                    openChat(listing)
                }
                .accessibilityIdentifier("product.offer")
            }
            RFButton("Acheter") {
                if let negotiated = negotiatedPrice {
                    store.negotiatedPrices[listing.id] = negotiated
                }
                router.push(.checkout(listing.id))
            }
            .disabled(!canBuy(listing))
            .accessibilityLabel("Acheter pour \(Fmt.fcfa(price))")
            .accessibilityIdentifier("product.buy")
        }
    }

    // MARK: Moderation

    private var blockTitle: String { "Bloquer \(sellerName) ?" }

    private func block() {
        guard let listing else { return }
        let name = sellerName
        Task {
            do {
                try await store.repo.block(userId: listing.sellerId)
                Haptics.success()
                store.show("\(name) bloquée")
                dismiss()
            } catch {
                store.show(error)
            }
        }
    }
}

// MARK: - Time formatting

enum ProductTime {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm"
        return f
    }()
    /// « 14:30 »
    static func hourMinute(_ date: Date) -> String { formatter.string(from: date) }
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
