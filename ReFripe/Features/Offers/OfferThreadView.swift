import SwiftUI
import UIKit

/// Negotiation thread for one listing, buyer side.
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
            VStack(alignment: .leading, spacing: RF.S.lg) {
                Button {
                    router.push(.product(l.id))
                } label: {
                    OfferListingHeader(listing: l, style: .context)
                }
                .buttonStyle(RFPressStyle())
                .accessibilityHint("Ouvrir l'annonce")

                if let thread {
                    OfferCounterPill(used: thread.buyerOfferCount, upcoming: nil)
                    OfferRoundsList(rounds: thread.rounds, otherName: sellerName,
                                    waitingName: waitingForSeller ? sellerName : nil)
                        .background(RF.C.card, in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
                    outcome(thread, listing: l)
                } else {
                    ContentUnavailableView {
                        Label("Pas encore d'offre", systemImage: "arrow.left.arrow.right")
                    } description: {
                        Text("Propose ton prix à \(sellerName).")
                    } actions: {
                        if l.negotiable {
                            Button("Faire une offre") {
                                router.pop()
                                router.push(.offer(l.id))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(RF.C.hibiscus)
                        }
                    }
                }
            }
            .padding(EdgeInsets(top: RF.S.lg, leading: RF.S.gutter, bottom: RF.S.xl, trailing: RF.S.gutter))
        }
        .defaultScrollAnchor(.bottom)
    }

    @ViewBuilder
    private func outcome(_ t: OfferThread, listing l: Listing) -> some View {
        switch t.status {
        case .accepted:
            let amount = t.acceptedAmount ?? t.rounds.last?.amount ?? l.price
            OfferResultCard(accepted: true,
                            title: "Offre acceptée",
                            subtitle: "Prix verrouillé à \(Fmt.fcfa(amount)).") {
                if l.status == .active {
                    RFButton("Acheter") { buy(at: amount) }
                        .accessibilityLabel("Acheter pour \(Fmt.fcfa(amount))")
                } else {
                    Text("Article plus disponible.")
                        .font(RF.T.footnote)
                        .foregroundStyle(RF.C.textDim)
                }
            }
        case .refused, .expired:
            OfferResultCard(accepted: false,
                            title: t.status == .refused ? "Offre refusée" : "Négociation expirée",
                            subtitle: l.status == .active ? "Tu peux toujours acheter au prix affiché." : nil) {
                VStack(spacing: RF.S.sm) {
                    if l.status == .active {
                        RFButton("Acheter au prix affiché") { buy(at: nil) }
                            .accessibilityLabel("Acheter au prix affiché, \(Fmt.fcfa(l.price))")
                    }
                    RFButton("Retour à l'annonce", style: .ghost) { router.pop() }
                }
            }
        case .pending:
            if let counter = pendingCounter {
                VStack(spacing: RF.S.sm) {
                    HStack(spacing: RF.S.md) {
                        if canCounter {
                            RFButton("Contre-proposer", style: .secondary) {
                                router.push(.offer(l.id))
                            }
                        }
                        RFButton("Accepter", isLoading: isAccepting) {
                            acceptCounter(counter)
                        }
                        .accessibilityLabel("Accepter \(Fmt.fcfa(counter.amount))")
                    }
                    if !canCounter {
                        Text("Limite de \(OfferRules.maxBuyerOffers) propositions atteinte.")
                            .font(RF.T.footnote)
                            .foregroundStyle(RF.C.textDim)
                    }
                    if l.status == .active {
                        Button("Acheter au prix affiché") { buy(at: nil) }
                            .font(RF.T.subheadline)
                            .foregroundStyle(RF.C.textDim)
                            .frame(minHeight: 44)
                            .accessibilityLabel("Acheter au prix affiché, \(Fmt.fcfa(l.price))")
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Pieces

/// Rounds of a negotiation as plain rows separated by hairlines (no background: the caller provides it).
struct OfferRoundsList: View {
    let rounds: [OfferRound]
    let otherName: String
    var me: OfferParty = .buyer
    /// Name of the party we are waiting for, if any.
    var waitingName: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rounds.enumerated()), id: \.element.id) { pair in
                if pair.offset > 0 { separator }
                OfferBubble(round: pair.element, otherName: otherName, me: me)
                    .transition(.opacity)
            }
            if let waitingName {
                if !rounds.isEmpty { separator }
                OfferWaitingIndicator(name: waitingName)
                    .transition(.opacity)
            }
        }
    }

    private var separator: some View {
        Rectangle().fill(RF.C.line).frame(height: 0.5).padding(.leading, RF.S.lg)
    }
}

/// One negotiation round as a row: who + when, amount on the right.
struct OfferBubble: View {
    let round: OfferRound
    /// Name of the other party (seller when I am the buyer, buyer when I am the seller).
    let otherName: String
    /// My side of the negotiation.
    var me: OfferParty = .buyer

    private var isMine: Bool { round.by == me }

    private var who: String {
        switch round.action {
        case .offer: return isMine ? "Ton offre" : "Offre de \(otherName)"
        case .counter: return isMine ? "Ta contre-offre" : "Contre-offre de \(otherName)"
        case .accept: return isMine ? "Tu as accepté" : "\(otherName) a accepté"
        case .refuse: return isMine ? "Tu as refusé" : "\(otherName) a refusé"
        }
    }

    private var amountColor: Color {
        switch round.action {
        case .accept: RF.C.moneyDeep
        case .refuse: RF.C.textDim
        default: RF.C.text
        }
    }

    var body: some View {
        HStack(spacing: RF.S.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(who)
                    .font(RF.T.subheadline.weight(isMine ? .regular : .semibold))
                    .foregroundStyle(RF.C.text)
                    .lineLimit(1)
                Text(Fmt.relative(round.at))
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.textDim)
            }
            Spacer(minLength: RF.S.sm)
            Text(Fmt.fcfa(round.amount))
                .font(RF.T.price(.body))
                .strikethrough(round.action == .refuse)
                .foregroundStyle(amountColor)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, RF.S.lg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(who), \(Fmt.fcfa(round.amount)), \(Fmt.relative(round.at))")
    }
}

struct OfferWaitingIndicator: View {
    let name: String

    var body: some View {
        HStack(spacing: RF.S.sm) {
            ProgressView().controlSize(.small)
            Text("\(name) répond…")
                .font(RF.T.subheadline)
                .foregroundStyle(RF.C.textDim)
            Spacer()
        }
        .padding(.vertical, 11)
        .padding(.horizontal, RF.S.lg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("En attente de la réponse de \(name)")
    }
}

private struct OfferResultCard<Actions: View>: View {
    let accepted: Bool
    let title: String
    let subtitle: String?
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: RF.S.md) {
            VStack(spacing: RF.S.xs) {
                Label(title, systemImage: accepted ? "checkmark.circle.fill" : "xmark.circle")
                    .font(RF.T.headline)
                    .foregroundStyle(accepted ? RF.C.moneyDeep : RF.C.text)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(RF.T.footnote)
                        .foregroundStyle(RF.C.textDim)
                        .multilineTextAlignment(.center)
                }
            }
            actions()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, RF.S.sm)
        .transition(.opacity)
    }
}

#Preview {
    NavigationStack {
        OfferThreadView(listingId: DemoIDs.listing(4))
            .withAppRoutes()
    }
    .previewEnvironment()
}
