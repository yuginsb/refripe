import SwiftUI

/// Compose an offer or a counter-offer (mockup `openOfferComposer` / `screenOffer`).
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
                OfferListingHeader(listing: l, style: .plain)
                    .padding(.bottom, 8)

                if let blocker = blocker(l) {
                    blockedView(blocker, listing: l)
                } else {
                    composer(l)
                }
            }
            .padding(EdgeInsets(top: 14, leading: RF.S.gutter, bottom: 24, trailing: RF.S.gutter))
        }
    }

    private func composer(_ l: Listing) -> some View {
        let sellerName = seller?.username ?? "La vendeuse"
        let isLast = offerNumber >= OfferRules.maxBuyerOffers
        return VStack(spacing: 0) {
            OfferCounterPill(used: buyerOfferCount, upcoming: offerNumber)
                .padding(.top, 10)

            if let counter = thread?.lastSellerCounter, thread?.rounds.last?.by == .seller {
                Text("\(sellerName) te propose \(Fmt.fcfa(counter.amount))")
                    .font(RF.F.body(12, .semibold))
                    .foregroundStyle(RF.C.textDim)
                    .padding(.top, 14)
            }

            PriceStepper(value: $amount, step: OfferRules.step(for: l.price), range: bounds(l))
                .padding(.top, 24)
                .padding(.bottom, 10)

            Text(hint(sellerName: sellerName, isLast: isLast))
                .font(RF.F.body(11.5))
                .foregroundStyle(RF.C.textDim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 6)
                .padding(.bottom, 22)
                .fixedSize(horizontal: false, vertical: true)

            RFButton("Envoyer l'offre · \(Fmt.fcfa(amount))", symbol: "paperplane.fill", isLoading: isSending) {
                send(l)
            }

            buyAtListedPrice(l)
                .padding(.top, 10)
        }
    }

    private func hint(sellerName: String, isLast: Bool) -> String {
        if isCounter {
            return isLast
                ? "C'est ta 3e et dernière proposition sur cette annonce : ensuite, il faudra accepter ou laisser tomber. L'article reste achetable au prix affiché en attendant."
                : "C'est ta \(offerNumber)e proposition sur \(OfferRules.maxBuyerOffers) possibles. L'article reste achetable au prix affiché en attendant."
        }
        return "\(sellerName) peut accepter, refuser ou te faire une contre-proposition. Tu peux faire jusqu'à \(OfferRules.maxBuyerOffers) offres, et l'article reste achetable au prix affiché en attendant."
    }

    private func buyAtListedPrice(_ l: Listing) -> some View {
        RFButton("Acheter au prix affiché · \(Fmt.fcfa(l.price))", style: .ghost) {
            store.negotiatedPrices[l.id] = nil
            router.push(.checkout(l.id))
        }
    }

    @ViewBuilder
    private func blockedView(_ blocker: Blocker, listing l: Listing) -> some View {
        switch blocker {
        case .ownListing:
            EmptyStateView(symbol: "person.crop.circle", title: "C'est ton annonce",
                           message: "Tu ne peux pas faire d'offre sur ton propre article.",
                           actionTitle: "Voir mon tableau de bord") { router.push(.dashboard) }
        case .notNegotiable:
            EmptyStateView(symbol: "lock", title: "Prix fixe",
                           message: "La vendeuse n'accepte pas les offres sur cet article.")
            buyAtListedPrice(l)
        case .unavailable:
            EmptyStateView(symbol: "clock", title: "Article indisponible",
                           message: "Cet article est réservé ou déjà vendu.")
        case .awaitingSeller:
            EmptyStateView(symbol: "hourglass", title: "Offre en attente",
                           message: "Attends la réponse de la vendeuse avant de refaire une proposition.",
                           actionTitle: "Voir la négociation") { replaceWithThread(l) }
        case .accepted:
            EmptyStateView(symbol: "checkmark.seal", title: "Offre acceptée",
                           message: "Ton offre a déjà été acceptée : tu peux acheter au prix négocié.",
                           actionTitle: "Voir la négociation") { replaceWithThread(l) }
        case .limit:
            EmptyStateView(symbol: "nosign", title: "Limite atteinte",
                           message: "Tu as déjà fait \(OfferRules.maxBuyerOffers) offres sur cet article. Il reste toujours achetable au prix affiché.")
            buyAtListedPrice(l)
            if thread != nil {
                RFButton("Voir la négociation", style: .secondary) { replaceWithThread(l) }
                    .padding(.top, 10)
            }
        }
    }

    private func replaceWithThread(_ l: Listing) {
        router.pop()
        router.push(.offerThread(l.id))
    }
}

// MARK: - Shared offer pieces

/// Listing context row (mockup `.co-row` in the composer, `.chat-context` in the thread).
struct OfferListingHeader: View {
    enum Style { case plain, context }
    let listing: Listing
    var style: Style = .plain

    var body: some View {
        let thumb: CGFloat = style == .plain ? 44 : 34
        HStack(spacing: 10) {
            ListingPhotoView(photo: listing.photos.first, listingId: listing.id)
                .frame(width: thumb, height: thumb)
                .clipShape(RoundedRectangle(cornerRadius: style == .plain ? RF.R.sm : 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(listing.title)
                    .font(RF.F.body(style == .plain ? 12.5 : 11, .bold))
                    .foregroundStyle(RF.C.text)
                    .lineLimit(1)
                Text("Prix affiché : \(Fmt.fcfa(listing.price))")
                    .font(style == .plain ? RF.F.body(10.5) : RF.F.mono(10.5))
                    .foregroundStyle(RF.C.textDim)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, style == .plain ? 10 : 9)
        .padding(.horizontal, style == .plain ? 0 : 12)
        .background {
            if style == .context {
                RoundedRectangle(cornerRadius: RF.R.md, style: .continuous).fill(RF.C.paperDim)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Offre n/3" with three dots (filled = already used).
struct OfferCounterPill: View {
    let used: Int
    let upcoming: Int?

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<OfferRules.maxBuyerOffers, id: \.self) { i in
                    Circle()
                        .fill(i < used ? RF.C.hibiscus : (i == used && upcoming != nil ? RF.C.marigold : RF.C.line))
                        .frame(width: 7, height: 7)
                }
            }
            Text(label)
                .font(RF.F.mono(11, .semibold))
                .foregroundStyle(RF.C.text)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Capsule().fill(RF.C.paperDim))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.replacingOccurrences(of: "/", with: " sur "))
    }

    private var label: String {
        if let upcoming { return "Offre \(min(upcoming, OfferRules.maxBuyerOffers))/\(OfferRules.maxBuyerOffers)" }
        return "\(used)/\(OfferRules.maxBuyerOffers) offres"
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
