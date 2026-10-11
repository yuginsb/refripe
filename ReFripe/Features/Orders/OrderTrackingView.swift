import SwiftUI

/// Écran 4b — Suivi de commande (mockup `screenCheckoutSuccess`, PANEL `checkoutSuccess`).
/// Même écran pour l'acheteuse et la vendeuse (rôle = `order.sellerId == store.me?.id`).
/// Frise du chemin heureux ou carte d'issue alternative, récap montants, actions selon rôle et statut.
/// Pas de temps réel : l'écran re-polle tant que la commande peut encore évoluer.
@MainActor
struct OrderTrackingView: View {
    let orderId: UUID

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var order: Order?
    @State private var sellerProfile: UserProfile?
    @State private var loadError: Error?
    @State private var working: TrackingAction?
    @State private var pendingConfirm: TrackingAction?
    @State private var isOpeningChat = false
    @State private var successTick = 0

    var body: some View {
        Group {
            if let order {
                content(order)
            } else if let loadError {
                ErrorStateView(error: loadError) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rfScreenBackground()
        .navigationTitle(order.map { "Commande \(Self.shortNumber($0.id))" } ?? "Commande")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: successTick)
        .confirmationDialog(pendingConfirm?.confirmTitle ?? "",
                            isPresented: confirmBinding,
                            titleVisibility: .visible,
                            presenting: pendingConfirm) { action in
            Button(action.confirmButton, role: action.isDestructive ? .destructive : nil) {
                Task { await perform(action) }
            }
            Button("Annuler", role: .cancel) {}
        } message: { action in
            Text(action.confirmMessage)
        }
        .task {
            await load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                if let o = order, Self.isSettled(o.status) { continue }
                await refresh()
            }
        }
    }

    // MARK: Role & state

    private var role: OrderRole {
        guard let order, let me = store.me?.id else { return .buyer }
        return order.sellerId == me ? .seller : .buyer
    }

    private var sellerName: String { sellerProfile?.username ?? "la vendeuse" }

    private static func isSettled(_ s: OrderStatus) -> Bool { [.completed, .cancelled, .refunded].contains(s) }

    /// "#1" for demo ids, "#3FA2B9" for random UUIDs.
    static func shortNumber(_ id: UUID) -> String {
        let tail = id.uuidString.suffix(6).drop(while: { $0 == "0" })
        return "#" + (tail.isEmpty ? "0" : String(tail))
    }

    private var confirmBinding: Binding<Bool> {
        Binding(get: { pendingConfirm != nil }, set: { if !$0 { pendingConfirm = nil } })
    }

    // MARK: Data

    private func load() async {
        loadError = nil
        do {
            let o = try await store.repo.order(id: orderId)
            order = o
            sellerProfile = await store.profile(o.sellerId)
        } catch {
            if order == nil { loadError = error } else { store.show(error) }
        }
    }

    private func refresh() async {
        guard let fresh = try? await store.repo.order(id: orderId) else { return }
        let previous = order?.status
        if fresh != order { order = fresh }
        if let previous, previous != fresh.status {
            if [.paid, .completed].contains(fresh.status) { successTick += 1 }
            await store.refreshBadges()
        }
    }

    private func perform(_ action: TrackingAction) async {
        guard var current = order, working == nil else { return }
        working = action
        defer { working = nil }
        do {
            switch action {
            case .ship, .simulateShip:
                current = try await store.repo.advanceOrder(id: current.id, to: .shipped)
            case .simulateDeliver:
                current = try await store.repo.advanceOrder(id: current.id, to: .delivered)
            case .cancel:
                current = try await store.repo.advanceOrder(id: current.id, to: .cancelled)
            case .confirmReceipt:
                if current.status == .delivered {
                    current = try await store.repo.advanceOrder(id: current.id, to: .buyerValidation)
                }
                current = try await store.repo.advanceOrder(id: current.id, to: .completed)
            case .dispute:
                current = try await store.repo.advanceOrder(id: current.id, to: .disputed)
            case .requestReturn:
                current = try await store.repo.advanceOrder(id: current.id, to: .returnPending)
            }
            withAnimation(.snappy) { order = current }
            if action.isPositive { successTick += 1 } else { Haptics.warning() }
            store.show(action.doneMessage)
            await store.refreshBadges()
        } catch {
            Haptics.error()
            store.show(error)
            await refresh()
        }
    }

    private func contact(_ order: Order) async {
        guard let me = store.me?.id, !isOpeningChat else { return }
        isOpeningChat = true
        defer { isOpeningChat = false }
        let other = order.sellerId == me ? order.buyerId : order.sellerId
        await ChatLauncher.open(with: other, listingId: order.listingId, store: store, router: router)
    }

    // MARK: Layout

    private func content(_ order: Order) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(role == .buyer ? "Ton achat" : "Vente à \(order.buyerName)")
                    .font(RF.F.body(10.5, .extraBold))
                    .kerning(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(RF.C.textDim)
                Text("Commande passée \(Self.placedLabel(order.createdAt))")
                    .font(RF.F.body(11))
                    .foregroundStyle(RF.C.textDim)
                    .padding(.top, 2)

                contextCard(order)
                    .padding(.top, 14)
                    .padding(.bottom, 4)

                hero(order)

                if let alt = order.status.alternativeInfo {
                    alternativeBanner(order.status, alt)
                }

                OrderTimeline(order: order)
                    .padding(.top, 22)
                    .padding(.bottom, 4)

                if order.status.alternativeInfo == nil && order.status != .completed {
                    escrowNote.padding(.top, 18)
                }

                amounts(order).padding(.top, 18)

                actions(order).padding(.top, 20)

                RFButton(role == .buyer ? "Contacter la vendeuse" : "Contacter l'acheteuse",
                         symbol: "bubble.left.and.bubble.right", style: .ghost, isLoading: isOpeningChat) {
                    Task { await contact(order) }
                }
                .padding(.top, 18)
            }
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 30, trailing: 20))
            .animation(.snappy, value: order.status)
        }
        .refreshable { await refresh() }
    }

    private static func placedLabel(_ date: Date) -> String {
        let rel = Fmt.relative(date)
        let lower = rel.lowercased()
        if lower.hasPrefix("il y a") || lower.hasPrefix("à l'instant") || lower == "hier" { return lower }
        return "le \(rel)"
    }

    private func contextCard(_ order: Order) -> some View {
        Button {
            router.push(.product(order.listingId))
        } label: {
            HStack(spacing: 10) {
                ListingPhotoView(photo: order.listingPhoto, listingId: order.listingId)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(order.listingTitle)
                        .font(RF.F.body(12, .bold))
                        .foregroundStyle(RF.C.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(Fmt.fcfa(order.itemPrice)) · \(role == .buyer ? sellerName : order.buyerName)")
                        .font(RF.F.mono(10.5))
                        .foregroundStyle(RF.C.textDim)
                    Label(order.delivery.label, systemImage: order.delivery.symbol)
                        .font(RF.F.body(10.5))
                        .foregroundStyle(RF.C.textDim)
                        .labelStyle(TrackingLabelStyle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(RF.C.textDim)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(RF.C.paperDim, in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
        }
        .buttonStyle(RFPressStyle(scale: 0.98))
        .accessibilityLabel("\(order.listingTitle), \(Fmt.fcfa(order.itemPrice)), \(order.delivery.label)")
        .accessibilityHint("Ouvre l'annonce")
    }

    /// Success header: fresh purchase (payment pending / confirmed) or completed order.
    @ViewBuilder private func hero(_ order: Order) -> some View {
        let fresh = role == .buyer
            && [.paymentPending, .paid, .awaitingShipment].contains(order.status)
            && Date.now.timeIntervalSince(order.createdAt) < 15 * 60
        if order.status == .completed {
            heroBlock(pending: false, title: "Commande terminée",
                      message: role == .buyer
                        ? "Merci pour ton achat ! Les fonds ont été libérés à \(sellerName)."
                        : "Les fonds ont été versés sur ton compte \(order.payment.label).")
        } else if fresh && order.status == .paymentPending {
            heroBlock(pending: true, title: "Paiement en cours",
                      message: "Valide le paiement dans ton app \(order.payment.label). Cet écran se met à jour tout seul.")
        } else if fresh {
            heroBlock(pending: false, title: "Paiement confirmé !",
                      message: "\(Fmt.fcfa(order.total)) sont bloqués en séquestre. \(sellerName) prépare ton colis.")
        }
    }

    private func heroBlock(pending: Bool, title: String, message: String) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(pending ? RF.C.marigold : RF.C.money)
                if pending {
                    ProgressView().controlSize(.large).tint(.white)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 74, height: 74)
            .padding(.top, 22)
            .padding(.bottom, 12)
            .accessibilityHidden(true)
            Text(title)
                .font(RF.F.display(17))
                .foregroundStyle(RF.C.text)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)
            Text(message)
                .font(RF.F.body(12.5))
                .lineSpacing(4)
                .foregroundStyle(RF.C.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func alternativeBanner(_ status: OrderStatus, _ alt: (symbol: String, title: String, detail: String)) -> some View {
        let isNegative = status == .cancelled || status == .refunded
        let shape = RoundedRectangle(cornerRadius: RF.R.lg, style: .continuous)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: alt.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isNegative ? RF.C.hibiscus : RF.C.marigold)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(alt.title)
                    .font(RF.F.body(13.5, .extraBold))
                    .foregroundStyle(RF.C.text)
                Text(alt.detail)
                    .font(RF.F.body(11.5))
                    .lineSpacing(3)
                    .foregroundStyle(RF.C.textDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(RF.C.paperDim, in: shape)
        .overlay(shape.strokeBorder(isNegative ? RF.C.hibiscus.opacity(0.35) : RF.C.marigold.opacity(0.55), lineWidth: 1))
        .padding(.top, 18)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }

    private var escrowNote: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RF.C.moneyDeep)
                .padding(.top, 2)
                .accessibilityHidden(true)
            (Text("Les fonds sont bloqués en séquestre jusqu'à la validation de l'acheteuse, ou automatiquement sous ")
             + Text("\(Catalog.escrowAutoReleaseHours)h").bold()
             + Text(" après la remise du colis si aucun litige n'est signalé."))
                .font(RF.F.body(11))
                .lineSpacing(3)
                .foregroundStyle(RF.C.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RF.C.paperDim, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func amounts(_ order: Order) -> some View {
        VStack(spacing: 9) {
            amountRow("Article", Fmt.fcfa(order.itemPrice))
            amountRow("Livraison · \(order.delivery.label)", order.deliveryFee > 0 ? Fmt.fcfa(order.deliveryFee) : "Gratuit")
            Rectangle().fill(RF.C.line).frame(height: 1)
            HStack(alignment: .firstTextBaseline) {
                Text("Total")
                    .font(RF.F.body(12.5, .bold))
                    .foregroundStyle(RF.C.textDim)
                Spacer()
                Text(Fmt.fcfa(order.total))
                    .font(RF.F.mono(17, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(RF.C.text)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 8) {
                PaymentBrandLogo(method: order.payment, size: 20)
                Text(role == .buyer ? "Payé avec \(order.payment.label)" : "Payé par l'acheteuse avec \(order.payment.label)")
                    .font(RF.F.body(11))
                    .foregroundStyle(RF.C.textDim)
                Spacer()
                StatusPill(status: order.status)
            }
        }
        .padding(14)
        .rfCard()
    }

    private func amountRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(RF.F.body(12))
                .foregroundStyle(RF.C.textDim)
            Spacer(minLength: 12)
            Text(value)
                .font(RF.F.mono(12.5))
                .monospacedDigit()
                .foregroundStyle(RF.C.text)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func availableActions(_ order: Order) -> [TrackingAction] {
        var list: [TrackingAction] = []
        switch (role, order.status) {
        case (.seller, .awaitingShipment):
            list = [.ship, .cancel]
        case (.seller, .paymentPending), (.seller, .paid):
            list = [.cancel]
        case (.buyer, .paymentPending), (.buyer, .paid):
            list = [.cancel]
        case (.buyer, .awaitingShipment):
            list = [.cancel]
            if store.isDemo { list.insert(.simulateShip, at: 0) }
        case (.buyer, .shipped):
            list = [.dispute]
        case (.buyer, .delivered), (.buyer, .buyerValidation):
            list = [.confirmReceipt, .dispute, .requestReturn]
        default:
            break
        }
        if store.isDemo && order.status == .shipped { list.insert(.simulateDeliver, at: 0) }
        return list
    }

    @ViewBuilder private func actions(_ order: Order) -> some View {
        let list = availableActions(order)
        if !list.isEmpty {
            VStack(spacing: 10) {
                ForEach(list, id: \.self) { action in
                    if action.isDemo {
                        TrackingDemoButton(title: action.title, isLoading: working == action) { trigger(action) }
                    } else {
                        RFButton(action.title, symbol: action.symbol, style: action == list.first && action.isPositive ? .primary : .ghost,
                                 isLoading: working == action) { trigger(action) }
                    }
                }
            }
            .disabled(working != nil)
        }
    }

    private func trigger(_ action: TrackingAction) {
        if action.needsConfirmation { pendingConfirm = action } else { Task { await perform(action) } }
    }
}

// MARK: - Actions model

private enum TrackingAction: Hashable {
    case ship, cancel, confirmReceipt, dispute, requestReturn, simulateShip, simulateDeliver

    var title: String {
        switch self {
        case .ship: "Marquer comme expédié"
        case .cancel: "Annuler la commande"
        case .confirmReceipt: "Confirmer la réception"
        case .dispute: "Signaler un problème"
        case .requestReturn: "Demander un retour"
        case .simulateShip: "Simuler l'expédition par la vendeuse (démo)"
        case .simulateDeliver: "Simuler la livraison (démo)"
        }
    }
    var symbol: String? {
        switch self {
        case .ship: "shippingbox"
        case .confirmReceipt: "checkmark.seal"
        case .dispute: "exclamationmark.bubble"
        case .requestReturn: "arrow.uturn.backward"
        default: nil
        }
    }
    var isDemo: Bool { self == .simulateShip || self == .simulateDeliver }
    var isPositive: Bool { [.ship, .confirmReceipt, .simulateShip, .simulateDeliver].contains(self) }
    var isDestructive: Bool { self == .cancel || self == .dispute }
    var needsConfirmation: Bool { [.cancel, .confirmReceipt, .dispute, .requestReturn].contains(self) }

    var confirmTitle: String {
        switch self {
        case .cancel: "Annuler cette commande ?"
        case .confirmReceipt: "Tu as bien reçu l'article ?"
        case .dispute: "Signaler un problème ?"
        case .requestReturn: "Demander un retour ?"
        default: ""
        }
    }
    var confirmMessage: String {
        switch self {
        case .cancel: "L'article sera remis en vente et le paiement intégralement remboursé à l'acheteuse."
        case .confirmReceipt: "Les fonds seront libérés à la vendeuse. Cette action est définitive."
        case .dispute: "Les fonds restent bloqués en séquestre pendant que notre équipe médiation examine le dossier (réponse sous 48h)."
        case .requestReturn: "Les fonds restent en séquestre jusqu'à réception et vérification de l'article par la vendeuse."
        default: ""
        }
    }
    var confirmButton: String {
        switch self {
        case .cancel: "Annuler la commande"
        case .confirmReceipt: "Oui, libérer les fonds"
        case .dispute: "Ouvrir un litige"
        case .requestReturn: "Demander le retour"
        default: title
        }
    }
    var doneMessage: String {
        switch self {
        case .ship, .simulateShip: "Colis marqué comme expédié"
        case .simulateDeliver: "Colis arrivé au point de retrait"
        case .cancel: "Commande annulée"
        case .confirmReceipt: "Réception confirmée, fonds libérés"
        case .dispute: "Litige ouvert, la médiation te recontacte sous 48h"
        case .requestReturn: "Demande de retour envoyée"
        }
    }
}

/// Discreet dashed demo button (mockup `.order-demo-btn`).
private struct TrackingDemoButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RF.R.md, style: .continuous)
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().tint(RF.C.textDim)
                } else {
                    Image(systemName: "wand.and.stars").font(.system(size: 12, weight: .semibold))
                }
                Text(title).font(RF.F.body(11, .extraBold))
            }
            .foregroundStyle(RF.C.text.opacity(0.8))
            .frame(maxWidth: .infinity, minHeight: 20)
            .padding(11)
            .overlay(shape.strokeBorder(RF.C.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .contentShape(shape)
        }
        .buttonStyle(RFPressStyle())
        .accessibilityLabel(title)
    }
}

private struct TrackingLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 9.5))
            configuration.title
        }
    }
}

// MARK: - Reusable: timeline

/// Vertical happy-path timeline (mockup `.order-timeline`): done = green check, current = marigold halo,
/// pending = grey. For alternative outcomes, every step reached before the divergence is shown as done.
struct OrderTimeline: View {
    let order: Order

    private enum StepState { case done, current, pending }

    private var steps: [OrderStatus] { OrderStatus.happyPath }

    private func state(at i: Int) -> StepState {
        let path = steps
        if order.status.isAlternative {
            let reached = order.history.compactMap { path.firstIndex(of: $0.status) }.max() ?? 1
            return i <= reached ? .done : .pending
        }
        let idx = path.firstIndex(of: order.status) ?? 0
        if i < idx { return .done }
        if i == idx { return order.status == .completed ? .done : .current }
        return .pending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, status in
                row(status, state: state(at: i), isLast: i == steps.count - 1)
            }
        }
    }

    private func row(_ status: OrderStatus, state: StepState, isLast: Bool) -> some View {
        let date = order.history.last(where: { $0.status == status })?.at
        return HStack(alignment: .top, spacing: 12) {
            dot(state)
            VStack(alignment: .leading, spacing: 1) {
                Text(status.label)
                    .font(RF.F.body(13, state == .pending ? .semibold : .bold))
                    .foregroundStyle(state == .pending ? RF.C.textDim : RF.C.text)
                if let date {
                    Text(Fmt.relative(date))
                        .font(RF.F.body(10.5))
                        .foregroundStyle(RF.C.textDim)
                }
            }
            .padding(.top, 1)
            .padding(.bottom, isLast ? 0 : 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(alignment: .topLeading) {
            if !isLast {
                Rectangle()
                    .fill(state == .done ? RF.C.money : RF.C.line)
                    .frame(width: 2)
                    .padding(.top, 22)
                    .padding(.bottom, -2)
                    .padding(.leading, 9)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibility(status, state: state, date: date))
    }

    private func dot(_ state: StepState) -> some View {
        ZStack {
            switch state {
            case .done:
                Circle().fill(RF.C.money)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
            case .current:
                Circle().fill(RF.C.marigold.opacity(0.22)).padding(-4)
                Circle().fill(RF.C.marigold)
            case .pending:
                Circle().fill(RF.C.paper)
                Circle().strokeBorder(RF.C.line, lineWidth: 2)
            }
        }
        .frame(width: 20, height: 20)
    }

    private func accessibility(_ status: OrderStatus, state: StepState, date: Date?) -> String {
        let s: String
        switch state {
        case .done: s = "terminé"
        case .current: s = "en cours"
        case .pending: s = "à venir"
        }
        return [status.label, s, date.map { Fmt.relative($0) }].compactMap { $0 }.joined(separator: ", ")
    }
}

// MARK: - Reusable: order row (dashboard lists)

/// Compact order row for lists (dashboard « Ventes » / « Achats »): photo, title, counterpart + date,
/// amount and `StatusPill`. Tapping pushes `.order(id)` unless `onTap` is provided. No background:
/// embed it in a card / list as needed.
struct OrderListRow: View {
    let order: Order
    var onTap: (() -> Void)?

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    init(order: Order, onTap: (() -> Void)? = nil) {
        self.order = order
        self.onTap = onTap
    }

    private var isSale: Bool { order.sellerId == store.me?.id }

    private var counterpart: String {
        if isSale { return "Vente à \(order.buyerName)" }
        return "Achat chez \(store.cachedProfile(order.sellerId)?.username ?? "…")"
    }

    var body: some View {
        Button {
            if let onTap { onTap() } else { router.push(.order(order.id)) }
        } label: {
            HStack(spacing: 10) {
                ListingPhotoView(photo: order.listingPhoto, listingId: order.listingId)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: RF.R.sm, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(order.listingTitle)
                        .font(RF.F.body(12.5, .bold))
                        .foregroundStyle(RF.C.text)
                        .lineLimit(1)
                    Text("\(counterpart) · \(Fmt.relative(order.history.last?.at ?? order.createdAt))")
                        .font(RF.F.body(10.5))
                        .foregroundStyle(RF.C.textDim)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(Fmt.fcfa(order.total))
                        .font(RF.F.mono(12.5))
                        .monospacedDigit()
                        .foregroundStyle(RF.C.text)
                    StatusPill(status: order.status)
                }
                .fixedSize()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(RFPressStyle(scale: 0.98))
        .task(id: order.sellerId) {
            if !isSale { _ = await store.profile(order.sellerId) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(order.listingTitle), \(counterpart), \(Fmt.fcfa(order.total)), \(order.status.label)")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("Vendeuse — à expédier") {
    NavigationStack { OrderTrackingView(orderId: DemoIDs.order(1)) }.previewEnvironment()
}

#Preview("Acheteuse — à confirmer") {
    NavigationStack { OrderTrackingView(orderId: DemoIDs.order(3)) }.previewEnvironment()
}

#Preview("Terminée") {
    NavigationStack { OrderTrackingView(orderId: DemoIDs.order(4)) }.previewEnvironment()
}

#Preview("OrderListRow") {
    VStack(spacing: 0) {
        OrderListRowPreviewLoader()
    }
    .padding(16)
    .rfScreenBackground()
    .previewEnvironment()
}

private struct OrderListRowPreviewLoader: View {
    @Environment(AppStore.self) private var store
    @State private var orders: [Order] = []

    var body: some View {
        VStack(spacing: 0) {
            ForEach(orders) { OrderListRow(order: $0) }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            let sales = (try? await store.repo.orders(role: .seller)) ?? []
            let buys = (try? await store.repo.orders(role: .buyer)) ?? []
            orders = sales + buys
        }
    }
}
