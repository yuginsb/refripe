import SwiftUI
import UIKit

/// Negotiation thread for one listing, buyer side (mockup `screenOfferThread`).
/// No realtime feed: while the last round is the buyer's and the thread is pending, the screen re-polls
/// the repository every 1.5 s (the demo seller answers after ~1.5 s).
struct OfferThreadView: View {
    let listingId: UUID

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var listing: Listing?
    @State private var seller: UserProfile?
    @State private var thread: OfferThread?
    @State private var hasLoaded = false
    @State private var loadError: Error?
    @State private var isAccepting = false

    var body: some View {
        Group {
            if let listing, hasLoaded {
                content(listing)
            } else if let loadError {
                ErrorStateView(error: loadError) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rfScreenBackground()
        .navigationTitle("Négociation")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.impact(weight: .light), trigger: thread?.rounds.count ?? 0)
        .task {
            await load()
            await poll()
        }
    }

    // MARK: State helpers

    private var sellerName: String { seller?.username ?? "La vendeuse" }

    private var waitingForSeller: Bool {
        guard let t = thread else { return false }
        return t.status == .pending && t.rounds.last?.by == .buyer
    }

    /// Seller countered and it's the buyer's turn.
    private var pendingCounter: OfferRound? {
        guard let t = thread, t.status == .pending, let last = t.rounds.last,
              last.by == .seller, last.action == .counter else { return nil }
        return last
    }

    private var canCounter: Bool {
        pendingCounter != nil && (thread?.buyerOfferCount ?? 0) < OfferRules.maxBuyerOffers
    }

    // MARK: Data

    private func load() async {
        do {
            let l = try await store.repo.listing(id: listingId)
            let t = try await store.repo.offerThread(listingId: listingId)
            seller = await store.profile(l.sellerId)
            listing = l
            apply(t)
            loadError = nil
        } catch {
            if listing == nil { loadError = error } else { store.show(error) }
        }
        hasLoaded = true
    }

    /// Re-polls while waiting for the seller (no realtime channel in the repository contract).
    private func poll() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            guard waitingForSeller else { continue }
            guard let fresh = try? await store.repo.offerThread(listingId: listingId) else { continue }
            if fresh != thread {
                let previous = thread
                apply(fresh)
                announce(fresh, previous: previous)
                await store.refreshBadges()
            }
        }
    }

    private func apply(_ t: OfferThread?) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { thread = t }
        if let amount = t?.acceptedAmount {
            store.negotiatedPrices[listingId] = amount
        }
    }

    private func announce(_ t: OfferThread, previous: OfferThread?) {
        guard t.rounds.count > (previous?.rounds.count ?? 0), let last = t.rounds.last, last.by == .seller else { return }
        switch last.action {
        case .accept:
            Haptics.success()
            UIAccessibility.post(notification: .announcement, argument: "\(sellerName) a accepté ton offre de \(Fmt.fcfa(last.amount))")
        case .refuse:
            Haptics.error()
            UIAccessibility.post(notification: .announcement, argument: "\(sellerName) a refusé ton offre")
        case .counter:
            Haptics.warning()
            UIAccessibility.post(notification: .announcement, argument: "\(sellerName) te propose \(Fmt.fcfa(last.amount))")
        case .offer:
            break
        }
    }

    // MARK: Actions

    /// Accepting a counter = offering exactly its amount; the server records it as an acceptance.
    private func acceptCounter(_ counter: OfferRound) {
        guard !isAccepting else { return }
        isAccepting = true
        Task {
            defer { isAccepting = false }
            do {
                let t = try await store.repo.makeOffer(listingId: listingId, amount: counter.amount)
                apply(t)
                if t.status == .accepted { Haptics.success() }
                await store.refreshBadges()
            } catch {
                Haptics.error()
                store.show(error)
                let fresh = try? await store.repo.offerThread(listingId: listingId)
                if let fresh { apply(fresh) }
            }
        }
    }

    private func buy(at price: FCFA?) {
        if let price { store.negotiatedPrices[listingId] = price } else { store.negotiatedPrices[listingId] = nil }
        router.push(.checkout(listingId))
    }

    // MARK: Layout

    private func content(_ l: Listing) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Button {
                    router.push(.product(l.id))
                } label: {
                    OfferListingHeader(listing: l, style: .context)
                }
                .buttonStyle(RFPressStyle(scale: 0.98))
                .accessibilityHint("Ouvrir l'annonce")
                .padding(.horizontal, RF.S.gutter)
                .padding(.top, 10)

                if let thread {
                    OfferCounterPill(used: thread.buyerOfferCount, upcoming: nil)
                        .padding(.top, 14)
                    timeline(thread)
                    outcome(thread, listing: l)
                } else {
                    EmptyStateView(symbol: "arrow.left.arrow.right",
                                   title: "Pas encore de négociation",
                                   message: "Propose ton prix à \(sellerName) : jusqu'à \(OfferRules.maxBuyerOffers) offres, sans jamais sortir du séquestre.",
                                   actionTitle: l.negotiable ? "Faire une offre" : nil) {
                        router.pop()
                        router.push(.offer(l.id))
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .defaultScrollAnchor(.bottom)
    }

    private func timeline(_ t: OfferThread) -> some View {
        VStack(spacing: 10) {
            ForEach(t.rounds) { round in
                OfferBubble(round: round, sellerName: sellerName)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
            if waitingForSeller {
                OfferWaitingIndicator(sellerName: sellerName)
                    .transition(.opacity)
            }
        }
        .padding(EdgeInsets(top: 14, leading: RF.S.gutter, bottom: 14, trailing: RF.S.gutter))
    }

    @ViewBuilder
    private func outcome(_ t: OfferThread, listing l: Listing) -> some View {
        switch t.status {
        case .accepted:
            let amount = t.acceptedAmount ?? t.rounds.last?.amount ?? l.price
            OfferResultCard(accepted: true,
                            title: "Offre acceptée à \(Fmt.fcfa(amount))",
                            subtitle: "Le prix est verrouillé pour ta commande. Paiement sécurisé par séquestre.") {
                if l.status == .active {
                    RFButton("Acheter à \(Fmt.fcfa(amount))", symbol: "lock.fill") { buy(at: amount) }
                } else {
                    Text("Cet article n'est plus disponible.")
                        .font(RF.F.body(11.5, .semibold))
                        .foregroundStyle(RF.C.textDim)
                }
            }
        case .refused, .expired:
            OfferResultCard(accepted: false,
                            title: t.status == .refused ? "Offre refusée" : "Négociation expirée",
                            subtitle: "\(sellerName) n'a pas donné suite à cette proposition. L'article reste achetable au prix affiché.") {
                VStack(spacing: 10) {
                    if l.status == .active {
                        RFButton("Acheter au prix affiché · \(Fmt.fcfa(l.price))") { buy(at: nil) }
                    }
                    RFButton("Retour à l'annonce", style: .ghost) { router.pop() }
                }
            }
        case .pending:
            if let counter = pendingCounter {
                VStack(spacing: 10) {
                    RFButton("Accepter \(Fmt.fcfa(counter.amount))", symbol: "checkmark", isLoading: isAccepting) {
                        acceptCounter(counter)
                    }
                    if canCounter {
                        RFButton("Contre-proposer", symbol: "arrow.left.arrow.right", style: .ghost) {
                            router.push(.offer(l.id))
                        }
                    } else {
                        Text("Limite de \(OfferRules.maxBuyerOffers) propositions atteinte : il ne reste plus qu'à accepter.")
                            .font(RF.F.body(11.5))
                            .foregroundStyle(RF.C.textDim)
                            .multilineTextAlignment(.center)
                    }
                    if l.status == .active {
                        Button {
                            buy(at: nil)
                        } label: {
                            Text("Ou acheter au prix affiché · \(Fmt.fcfa(l.price))")
                                .font(RF.F.body(12, .bold))
                                .underline()
                                .foregroundStyle(RF.C.textDim)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, RF.S.gutter)
                .padding(.top, 4)
            } else if waitingForSeller {
                Text("L'article reste achetable au prix affiché par n'importe qui pendant la négociation.")
                    .font(RF.F.body(11))
                    .foregroundStyle(RF.C.textDim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
    }
}

// MARK: - Pieces (mockup `.offer-bubble`, `.offer-waiting`, `.offer-result`)

private struct OfferBubble: View {
    let round: OfferRound
    let sellerName: String

    private var isBuyer: Bool { round.by == .buyer }

    private var who: String {
        let name = isBuyer ? "Toi" : sellerName
        switch round.action {
        case .offer: return name
        case .counter: return "\(name) · contre-offre"
        case .accept: return isBuyer ? "\(name) · as accepté" : "\(name) · a accepté"
        case .refuse: return isBuyer ? "\(name) · as refusé" : "\(name) · a refusé"
        }
    }

    var body: some View {
        HStack {
            if isBuyer { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 2) {
                Text(who.uppercased())
                    .font(RF.F.body(9.5, .bold))
                    .kerning(0.4)
                    .opacity(0.75)
                HStack(spacing: 5) {
                    if round.action == .accept {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                    } else if round.action == .refuse {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                    }
                    Text(Fmt.fcfa(round.amount))
                        .font(RF.F.mono(15, .semibold))
                        .strikethrough(round.action == .refuse)
                }
                Text(Fmt.relative(round.at))
                    .font(RF.F.body(9))
                    .opacity(0.6)
            }
            .foregroundStyle(isBuyer ? Color.white : RF.C.text)
            .padding(.vertical, 10)
            .padding(.horizontal, 13)
            .background(isBuyer ? RF.C.hibiscus : RF.C.paperDim, in: UnevenRoundedRectangle(
                topLeadingRadius: 14,
                bottomLeadingRadius: isBuyer ? 14 : 4,
                bottomTrailingRadius: isBuyer ? 4 : 14,
                topTrailingRadius: 14,
                style: .continuous))
            if !isBuyer { Spacer(minLength: 60) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(who), \(Fmt.fcfa(round.amount)), \(Fmt.relative(round.at))")
    }
}

private struct OfferWaitingIndicator: View {
    let sellerName: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(RF.C.marigold)
                .frame(width: 8, height: 8)
                .phaseAnimator([false, true]) { dot, on in
                    dot.opacity(on ? 1 : 0.3).scaleEffect(on ? 1.1 : 0.85)
                } animation: { _ in
                    .easeInOut(duration: 0.55)
                }
            Text("\(sellerName) répond…")
                .font(RF.F.body(11.5))
                .foregroundStyle(RF.C.textDim)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("En attente de la réponse de \(sellerName)")
    }
}

private struct OfferResultCard<Actions: View>: View {
    let accepted: Bool
    let title: String
    let subtitle: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: accepted ? "checkmark" : "xmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(accepted ? RF.C.money : RF.C.hibiscus))
                .padding(.bottom, 14)
                .accessibilityHidden(true)
            Text(title)
                .font(RF.F.display(15))
                .foregroundStyle(RF.C.text)
                .multilineTextAlignment(.center)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(RF.F.body(11.5))
                .foregroundStyle(RF.C.textDim)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.bottom, 14)
                .fixedSize(horizontal: false, vertical: true)
            actions()
        }
        .padding(EdgeInsets(top: 26, leading: RF.S.gutter, bottom: 16, trailing: RF.S.gutter))
        .frame(maxWidth: .infinity)
        .background {
            if accepted {
                RoundedRectangle(cornerRadius: RF.R.lg, style: .continuous)
                    .fill(RF.C.money.opacity(0.08))
                    .padding(.horizontal, RF.S.gutter / 2)
            }
        }
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }
}

#Preview {
    NavigationStack {
        OfferThreadView(listingId: DemoIDs.listing(4))
            .withAppRoutes()
    }
    .previewEnvironment()
}
