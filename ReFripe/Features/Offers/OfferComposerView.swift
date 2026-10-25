import SwiftUI

/// Compose an offer or a counter-offer.
/// The amount is bounded to [floor … price − step]; the seller's private floor is never displayed.
/// Sending replaces this screen with the negotiation thread.
struct OfferComposerView: View {
    let listingId: UUID

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var listing: Listing?
    @State private var seller: UserProfile?
    @State private var thread: OfferThread?
    @State private var amount: FCFA = 0
    @State private var loadError: Error?
    @State private var isSending = false
    @State private var limitReached = false

    /// The seller opened her own listing's negotiation (e.g. from a "new offer" notification):
    /// show the seller-side screen instead.
    private var isMyListing: Bool {
        guard let listing, let me = store.me?.id else { return false }
        return listing.sellerId == me
    }

    var body: some View {
        if isMyListing {
            ReceivedOffersView(listingId: listingId)
        } else {
            buyerBody
        }
    }

    private var buyerBody: some View {
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
        .navigationTitle(isCounter ? "Contre-proposer" : "Faire une offre")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: Data

    private var isCounter: Bool { !(thread?.rounds.isEmpty ?? true) }
    private var buyerOfferCount: Int { thread?.buyerOfferCount ?? 0 }
    private var offerNumber: Int { buyerOfferCount + 1 }

    private enum Blocker { case ownListing, notNegotiable, unavailable, awaitingSeller, accepted, limit }

    private func blocker(_ l: Listing) -> Blocker? {
        if l.sellerId == store.me?.id { return .ownListing }
        if !l.negotiable { return .notNegotiable }
        if l.status != .active { return .unavailable }
        if let t = thread {
            switch t.status {
            case .accepted: return .accepted
            case .refused, .expired: return .limit
            case .pending:
                if t.rounds.last?.by == .buyer { return .awaitingSeller }
            }
        }
        if limitReached || buyerOfferCount >= OfferRules.maxBuyerOffers { return .limit }
        return nil
    }

    /// Allowed amounts. Lower bound = seller floor when the API exposes it (demo), otherwise 30 % of the
    /// price; always above the buyer's previous offer. Upper bound = price − step.
    private func bounds(_ l: Listing) -> ClosedRange<FCFA> {
        let step = OfferRules.step(for: l.price)
        let upper = max(step, l.price - step)
        var lower = l.minOffer ?? max(step, OfferRules.round(Double(l.price) * 0.3, step: step))
        if let previous = thread?.lastBuyerOffer?.amount { lower = max(lower, previous + step) }
        lower = min(lower, upper)
        return lower...upper
    }

    private func load() async {
        do {
            let l = try await store.repo.listing(id: listingId)
            let t = try await store.repo.offerThread(listingId: listingId)
            thread = t
            seller = await store.profile(l.sellerId)
            let range = bounds(l)
            amount = min(max(OfferRules.initialDraft(listing: l, thread: t), range.lowerBound), range.upperBound)
            listing = l
            loadError = nil
        } catch {
            loadError = error
        }
    }

    private func send(_ l: Listing) {
        guard !isSending else { return }
        isSending = true
        Task {
            defer { isSending = false }
            do {
                _ = try await store.repo.makeOffer(listingId: l.id, amount: amount)
                Haptics.success()
                // Replace the composer with the thread.
                router.pop()
                router.push(.offerThread(l.id))
                await store.refreshBadges()
            } catch RepositoryError.offerLimitReached {
                Haptics.warning()
                withAnimation { limitReached = true }
                store.show(RepositoryError.offerLimitReached)
            } catch {
                Haptics.error()
                store.show(error)
            }
        }
    }

    // MARK: Layout

    private func content(_ l: Listing) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                OfferListingHeader(listing: l)

                if let blocker = blocker(l) {
                    blockedView(blocker, listing: l)
                } else {
                    composer(l)
                }
            }
            .padding(EdgeInsets(top: RF.S.lg, leading: RF.S.gutter, bottom: RF.S.xl, trailing: RF.S.gutter))
        }
    }

    private func composer(_ l: Listing) -> some View {
        let sellerName = seller?.username ?? "La vendeuse"
        return VStack(spacing: 0) {
            OfferCounterPill(used: buyerOfferCount, upcoming: offerNumber)
                .padding(.top, RF.S.xl)

            if let counter = thread?.lastSellerCounter, thread?.rounds.last?.by == .seller {
                Text("\(sellerName) propose \(Text(Fmt.fcfa(counter.amount)).font(RF.T.price(.subheadline)))")
                    .font(RF.T.subheadline)
                    .foregroundStyle(RF.C.textDim)
                    .padding(.top, RF.S.sm)
            }

            PriceStepper(value: $amount, step: OfferRules.step(for: l.price), range: bounds(l))
                .padding(.top, RF.S.xl)

            if let hint = hint(sellerName: sellerName) {
                Text(hint)
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.textDim)
                    .multilineTextAlignment(.center)
                    .padding(.top, RF.S.md)
            }

            RFButton("Envoyer l'offre", isLoading: isSending) {
                send(l)
            }
            .accessibilityLabel("Envoyer l'offre de \(Fmt.fcfa(amount))")
            .padding(.top, RF.S.xl)

            buyAtListedPrice(l)
                .padding(.top, RF.S.sm)
        }
    }

    /// One short line max under the amount.
    private func hint(sellerName: String) -> String? {
        if offerNumber >= OfferRules.maxBuyerOffers { return "C'est ta dernière proposition." }
        if isCounter { return nil }
        return "\(sellerName) peut accepter, refuser ou contre-proposer."
    }

    private func buyAtListedPrice(_ l: Listing) -> some View {
        RFButton("Acheter au prix affiché", style: .ghost) {
            store.negotiatedPrices[l.id] = nil
            router.push(.checkout(l.id))
        }
        .accessibilityLabel("Acheter au prix affiché, \(Fmt.fcfa(l.price))")
    }

    @ViewBuilder
    private func blockedView(_ blocker: Blocker, listing l: Listing) -> some View {
        VStack(spacing: RF.S.sm) {
            switch blocker {
            case .ownListing:
                blockedMessage("C'est ton annonce", symbol: "person.crop.circle")
                RFButton("Statistiques", style: .secondary) { router.push(.dashboard) }
            case .notNegotiable:
                blockedMessage("Prix fixe", symbol: "lock", detail: "Pas d'offre sur cet article.")
                buyAtListedPrice(l)
            case .unavailable:
                blockedMessage("Article indisponible", symbol: "clock", detail: "Réservé ou déjà vendu.")
            case .awaitingSeller:
                blockedMessage("Offre en attente", symbol: "hourglass", detail: "Attends la réponse de la vendeuse.")
                RFButton("Voir la négociation", style: .secondary) { replaceWithThread(l) }
            case .accepted:
                blockedMessage("Offre acceptée", symbol: "checkmark.seal", detail: "Tu peux acheter au prix négocié.")
                RFButton("Voir la négociation") { replaceWithThread(l) }
            case .limit:
                blockedMessage("Limite atteinte", symbol: "nosign",
                               detail: "\(OfferRules.maxBuyerOffers) offres déjà faites sur cet article.")
                buyAtListedPrice(l)
                if thread != nil {
                    RFButton("Voir la négociation", style: .secondary) { replaceWithThread(l) }
                }
            }
        }
    }

    private func blockedMessage(_ title: String, symbol: String, detail: String? = nil) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            if let detail { Text(detail) }
        }
        .padding(.vertical, RF.S.lg)
    }

    private func replaceWithThread(_ l: Listing) {
        router.pop()
        router.push(.offerThread(l.id))
    }
}

// MARK: - Shared offer pieces

/// Listing context row: thumbnail, title, listed price. On a white card.
struct OfferListingHeader: View {
    enum Style { case plain, context }
    let listing: Listing
    var style: Style = .plain

    var body: some View {
        HStack(spacing: RF.S.md) {
            ListingPhotoView(photo: listing.photos.first, listingId: listing.id)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(listing.title)
                    .font(RF.T.subheadline.weight(.semibold))
                    .foregroundStyle(RF.C.text)
                    .lineLimit(1)
                Text(Fmt.fcfa(listing.price))
                    .font(RF.T.price(.footnote, weight: .regular))
                    .foregroundStyle(RF.C.textDim)
                    .accessibilityLabel("Prix affiché : \(Fmt.fcfa(listing.price))")
            }
            Spacer(minLength: 0)
            if style == .context {
                Image(systemName: "chevron.right")
                    .font(RF.T.footnote.weight(.semibold))
                    .foregroundStyle(RF.C.textDim)
                    .accessibilityHidden(true)
            }
        }
        .padding(RF.S.md)
        .background(RF.C.card, in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// "Offre n sur 3" with three small dots (filled = already used).
struct OfferCounterPill: View {
    let used: Int
    let upcoming: Int?

    var body: some View {
        HStack(spacing: RF.S.sm) {
            HStack(spacing: 4) {
                ForEach(0..<OfferRules.maxBuyerOffers, id: \.self) { i in
                    Circle()
                        .fill(i < used || (i == used && upcoming != nil) ? RF.C.hibiscus : RF.C.line)
                        .opacity(i == used && upcoming != nil ? 0.45 : 1)
                        .frame(width: 6, height: 6)
                }
            }
            Text(label)
                .font(RF.T.footnote)
                .monospacedDigit()
                .foregroundStyle(RF.C.textDim)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        if let upcoming { return "Offre \(min(upcoming, OfferRules.maxBuyerOffers)) sur \(OfferRules.maxBuyerOffers)" }
        return "\(used) offre\(used > 1 ? "s" : "") sur \(OfferRules.maxBuyerOffers)"
    }
}

#Preview {
    NavigationStack {
        OfferComposerView(listingId: DemoIDs.listing(3))
            .withAppRoutes()
    }
    .previewEnvironment()
}

#Preview("Contre-proposition") {
    NavigationStack {
        OfferComposerView(listingId: DemoIDs.listing(4))
            .withAppRoutes()
    }
    .previewEnvironment()
}
