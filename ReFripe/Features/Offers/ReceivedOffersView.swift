import SwiftUI
import UIKit

/// Seller side of the negotiation: every offer thread received on one of MY listings, with
/// Accepter / Refuser / Contre-proposer / Écrire. Re-polls every 2 s while a buyer has to answer
/// (no realtime feed; in demo a buyer bot answers counters after ~2 s).
struct ReceivedOffersView: View {
    let listingId: UUID

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var listing: Listing?
    @State private var threads: [OfferThread] = []
    @State private var buyers: [UUID: UserProfile] = [:]
    @State private var hasLoaded = false
    @State private var loadError: Error?
    @State private var busyThreads: Set<UUID> = []
    @State private var counterEditing: UUID?
    @State private var counterDrafts: [UUID: FCFA] = [:]
    @State private var refusing: OfferThread?
    @State private var updateTick = 0

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
        .navigationTitle("Offres reçues")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.impact(weight: .light), trigger: updateTick)
        .confirmationDialog("Refuser cette offre ?", isPresented: refuseDialogShown, titleVisibility: .visible,
                            presenting: refusing) { thread in
            Button("Refuser l'offre", role: .destructive) { respond(thread, action: .refuse) }
            Button("Annuler", role: .cancel) {}
        } message: { thread in
            Text("\(buyerName(thread.buyerId)) en sera informée.")
        }
        .task {
            await load()
            await poll()
        }
    }

    // MARK: Helpers

    private var refuseDialogShown: Binding<Bool> {
        Binding(get: { refusing != nil }, set: { if !$0 { refusing = nil } })
    }

    private func buyerName(_ id: UUID) -> String { buyers[id]?.username ?? "L'acheteuse" }

    private func awaitingMe(_ t: OfferThread) -> Bool { t.status == .pending && t.rounds.last?.by == .buyer }
    private func awaitingBuyer(_ t: OfferThread) -> Bool { t.status == .pending && t.rounds.last?.by == .seller }

    /// Counter-offer bounds: strictly between the buyer's last offer and the listed price.
    private func counterRange(_ t: OfferThread, listing l: Listing) -> ClosedRange<FCFA>? {
        guard let last = t.lastBuyerOffer?.amount else { return nil }
        let step = OfferRules.step(for: l.price)
        let lower = last + step
        let upper = l.price - step
        return lower <= upper ? lower...upper : nil
    }

    /// Threads waiting for me first, then most recent.
    private func sorted(_ list: [OfferThread]) -> [OfferThread] {
        list.sorted { a, b in
            let ra = awaitingMe(a) ? 0 : (a.status == .pending ? 1 : 2)
            let rb = awaitingMe(b) ? 0 : (b.status == .pending ? 1 : 2)
            return ra != rb ? ra < rb : a.updatedAt > b.updatedAt
        }
    }

    // MARK: Data

    private func load() async {
        do {
            let l = try await store.repo.listing(id: listingId)
            let all = try await store.repo.offerThreads(role: .seller)
            let mine = all.filter { $0.listingId == listingId }
            await loadBuyers(for: mine)
            listing = l
            threads = sorted(mine)
            loadError = nil
        } catch {
            if listing == nil { loadError = error } else { store.show(error) }
        }
        hasLoaded = true
    }

    private func loadBuyers(for list: [OfferThread]) async {
        for id in Set(list.map(\.buyerId)) where buyers[id] == nil {
            if let p = await store.profile(id) { buyers[id] = p }
        }
    }

    private func poll() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            guard threads.contains(where: { awaitingBuyer($0) }) else { continue }
            guard let all = try? await store.repo.offerThreads(role: .seller) else { continue }
            let fresh = all.filter { $0.listingId == listingId }
            if Set(fresh) != Set(threads) {
                await loadBuyers(for: fresh)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { threads = sorted(fresh) }
                updateTick += 1
                await store.refreshBadges()
            }
        }
    }

    private func respond(_ t: OfferThread, action: OfferAction, amount: FCFA? = nil) {
        guard !busyThreads.contains(t.id) else { return }
        busyThreads.insert(t.id)
        Task {
            defer { busyThreads.remove(t.id) }
            do {
                let updated = try await store.repo.respondToOffer(threadId: t.id, action: action, amount: amount)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    if let i = threads.firstIndex(where: { $0.id == updated.id }) { threads[i] = updated }
                    threads = sorted(threads)
                    if counterEditing == t.id { counterEditing = nil }
                }
                switch action {
                case .accept:
                    Haptics.success()
                    store.show("Offre acceptée")
                case .refuse:
                    Haptics.warning()
                    store.show("Offre refusée")
                case .counter:
                    Haptics.success()
                    store.show("Contre-offre envoyée")
                case .offer:
                    break
                }
                await store.refreshBadges()
            } catch {
                Haptics.error()
                store.show(error)
                let all = try? await store.repo.offerThreads(role: .seller)
                if let all { threads = sorted(all.filter { $0.listingId == listingId }) }
            }
        }
    }

    // MARK: Layout

    private func content(_ l: Listing) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RF.S.lg) {
                header(l)
                if threads.isEmpty {
                    ContentUnavailableView {
                        Label("Pas encore d'offre", systemImage: "arrow.left.arrow.right")
                    } description: {
                        Text(l.negotiable ? "Les offres reçues apparaîtront ici." : "Article à prix fixe.")
                    }
                    .padding(.top, RF.S.xl)
                } else {
                    ForEach(threads) { t in
                        threadCard(t, listing: l)
                    }
                }
            }
            .padding(EdgeInsets(top: RF.S.lg, leading: RF.S.gutter, bottom: RF.S.xl, trailing: RF.S.gutter))
        }
        .refreshable { await load() }
    }

    private func header(_ l: Listing) -> some View {
        VStack(alignment: .leading, spacing: RF.S.sm) {
            Button {
                router.push(.product(l.id))
            } label: {
                OfferListingHeader(listing: l, style: .context)
            }
            .buttonStyle(RFPressStyle())
            .accessibilityHint("Ouvrir l'annonce")

            if let floor = l.minOffer {
                Label {
                    Text("Ton plancher : \(Text(Fmt.fcfa(floor)).font(RF.T.price(.footnote))) (privé)")
                } icon: {
                    Image(systemName: "lock")
                }
                .font(RF.T.footnote)
                .foregroundStyle(RF.C.textDim)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func threadCard(_ t: OfferThread, listing l: Listing) -> some View {
        let buyer = buyers[t.buyerId]
        let name = buyerName(t.buyerId)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: RF.S.md) {
                Button {
                    router.push(.sellerProfile(t.buyerId))
                } label: {
                    HStack(spacing: RF.S.md) {
                        Avatar(profile: buyer, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: RF.S.xs) {
                                Text(name).font(RF.T.headline).foregroundStyle(RF.C.text).lineLimit(1)
                                if buyer?.verified == true { VerifiedBadge(size: 12) }
                            }
                            statusLabel(t)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(RFPressStyle())
                .accessibilityElement(children: .combine)
                .accessibilityHint("Voir le profil")
                Spacer(minLength: RF.S.xs)
                Button {
                    Task { await ChatLauncher.open(with: t.buyerId, listingId: l.id, store: store, router: router) }
                } label: {
                    Image(systemName: "bubble.left")
                        .font(RF.T.body)
                        .foregroundStyle(RF.C.text)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RFPressStyle(scale: 0.9))
                .accessibilityLabel("Écrire à \(name)")
            }
            .padding(EdgeInsets(top: RF.S.md, leading: RF.S.lg, bottom: RF.S.sm, trailing: RF.S.sm))

            Rectangle().fill(RF.C.line).frame(height: 0.5).padding(.leading, RF.S.lg)

            OfferRoundsList(rounds: t.rounds, otherName: name, me: .seller,
                            waitingName: awaitingBuyer(t) ? name : nil)

            Group {
                if awaitingMe(t) {
                    actions(t, listing: l, buyerName: name)
                } else {
                    outcome(t)
                }
            }
            .padding(EdgeInsets(top: RF.S.xs, leading: RF.S.lg, bottom: RF.S.lg, trailing: RF.S.lg))
        }
        .background(RF.C.card, in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
    }

    private func statusLabel(_ t: OfferThread) -> some View {
        let (text, color): (String, Color) = {
            switch t.status {
            case .accepted: return ("Acceptée", RF.C.moneyDeep)
            case .refused: return ("Refusée", RF.C.textDim)
            case .expired: return ("Expirée", RF.C.textDim)
            case .pending: return awaitingMe(t) ? ("À toi de répondre", RF.C.hibiscus) : ("En attente", RF.C.textDim)
            }
        }()
        let count = "\(t.buyerOfferCount)/\(OfferRules.maxBuyerOffers) offres"
        return Text("\(text) · \(count)")
            .font(RF.T.footnote)
            .monospacedDigit()
            .foregroundStyle(color)
    }

    @ViewBuilder
    private func outcome(_ t: OfferThread) -> some View {
        switch t.status {
        case .accepted:
            Text("Paiement de \(Text(Fmt.fcfa(t.acceptedAmount ?? 0)).font(RF.T.price(.footnote))) attendu.")
                .font(RF.T.footnote)
                .foregroundStyle(RF.C.moneyDeep)
        case .refused, .expired:
            Text("Négociation close.")
                .font(RF.T.footnote)
                .foregroundStyle(RF.C.textDim)
        case .pending:
            EmptyView()
        }
    }

    @ViewBuilder
    private func actions(_ t: OfferThread, listing l: Listing, buyerName: String) -> some View {
        let lastAmount = t.lastBuyerOffer?.amount ?? 0
        let busy = busyThreads.contains(t.id)
        let range = t.buyerOfferCount < OfferRules.maxBuyerOffers ? counterRange(t, listing: l) : nil
        VStack(spacing: RF.S.sm) {
            if let floor = l.minOffer, lastAmount < floor {
                Label("Sous ton plancher de \(Fmt.fcfa(floor))", systemImage: "exclamationmark.triangle")
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.hibiscus)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if counterEditing == t.id, let range {
                counterEditor(t, range: range, step: OfferRules.step(for: l.price), busy: busy)
            } else {
                RFButton("Accepter", isLoading: busy) {
                    respond(t, action: .accept)
                }
                .accessibilityLabel("Accepter \(Fmt.fcfa(lastAmount))")
                HStack(spacing: RF.S.sm) {
                    if let range {
                        RFButton("Contre-proposer", style: .secondary) {
                            if counterDrafts[t.id] == nil {
                                let mid = OfferRules.round(Double(lastAmount + l.price) / 2, step: OfferRules.step(for: l.price))
                                counterDrafts[t.id] = min(max(mid, range.lowerBound), range.upperBound)
                            }
                            withAnimation(.snappy) { counterEditing = t.id }
                        }
                    }
                    RFButton("Refuser", style: .ghost) { refusing = t }
                }
                .disabled(busy)
                if range == nil {
                    Text(t.buyerOfferCount >= OfferRules.maxBuyerOffers
                         ? "Dernière offre de \(buyerName)."
                         : "Plus de marge pour une contre-offre.")
                        .font(RF.T.footnote)
                        .foregroundStyle(RF.C.textDim)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.top, RF.S.sm)
    }

    private func counterEditor(_ t: OfferThread, range: ClosedRange<FCFA>, step: FCFA, busy: Bool) -> some View {
        let binding = Binding<FCFA>(
            get: { counterDrafts[t.id] ?? range.lowerBound },
            set: { counterDrafts[t.id] = $0 }
        )
        let value = min(max(binding.wrappedValue, range.lowerBound), range.upperBound)
        return VStack(spacing: RF.S.md) {
            Text("Ta contre-offre")
                .font(RF.T.footnote.weight(.semibold))
                .foregroundStyle(RF.C.textDim)
            PriceStepper(value: binding, step: step, range: range)
            Text("Entre \(Fmt.fcfa(range.lowerBound)) et \(Fmt.fcfa(range.upperBound))")
                .font(RF.T.footnote)
                .monospacedDigit()
                .foregroundStyle(RF.C.textDim)
            HStack(spacing: RF.S.sm) {
                RFButton("Annuler", style: .ghost) {
                    withAnimation(.snappy) { counterEditing = nil }
                }
                RFButton("Envoyer", isLoading: busy) {
                    respond(t, action: .counter, amount: value)
                }
                .accessibilityLabel("Envoyer \(Fmt.fcfa(value))")
            }
        }
        .transition(.opacity)
    }
}

#Preview {
    NavigationStack {
        ReceivedOffersView(listingId: DemoIDs.listing(7))
            .withAppRoutes()
    }
    .previewEnvironment()
}
