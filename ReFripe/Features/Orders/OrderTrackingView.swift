import SwiftUI

/// Order tracking, same screen for buyer and seller (role = `order.sellerId == store.me?.id`):
/// listing, status + one line, timeline, escrow note, amounts, actions by role and status.
/// No realtime: re-polls while the order can still change.
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
            VStack(alignment: .leading, spacing: 24) {
                contextCard(order)

                VStack(alignment: .leading, spacing: 4) {
                    Text(headline(order))
                        .font(RF.T.title3)
                        .foregroundStyle(RF.C.text)
                    Text(statusLine(order))
                        .font(RF.T.subheadline)
                        .foregroundStyle(RF.C.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                OrderTimeline(order: order)
                    .padding(16)
                    .rfCard(radius: RF.R.md)

                if !order.status.isAlternative && order.status != .completed {
                    escrowNote
                }

                amounts(order)
            }
            .padding(RF.S.gutter)
            .padding(.bottom, 16)
            .animation(.snappy, value: order.status)
        }
        .refreshable { await refresh() }
        // Actions pinned above the tab bar so the next step is always visible.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                actions(order)
                RFButton(role == .buyer ? "Écrire à la vendeuse" : "Écrire à l'acheteuse",
                         symbol: "bubble.left", style: .ghost, isLoading: isOpeningChat) {
                    Task { await contact(order) }
                }
            }
            .padding(.horizontal, RF.S.gutter)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background(RF.C.paper)
            .overlay(alignment: .top) { Divider().overlay(RF.C.line) }
        }
    }

    private func contextCard(_ order: Order) -> some View {
        Button {
            router.push(.product(order.listingId))
        } label: {
            HStack(spacing: 12) {
                ListingPhotoView(photo: order.listingPhoto, listingId: order.listingId)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(order.listingTitle)
                        .font(RF.T.subheadline.weight(.semibold))
                        .foregroundStyle(RF.C.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(role == .buyer ? "Chez \(sellerName)" : "Vente à \(order.buyerName)")
                        .font(RF.T.footnote)
                        .foregroundStyle(RF.C.textDim)
                    Text("\(order.delivery.label) · \(Fmt.relative(order.createdAt))")
                        .font(RF.T.footnote)
                        .foregroundStyle(RF.C.textDim)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(RF.T.footnote.weight(.semibold))
                    .foregroundStyle(RF.C.textDim)
            }
            .padding(12)
            .rfCard(radius: RF.R.md)
            .contentShape(RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(order.listingTitle), \(order.delivery.label)")
        .accessibilityHint("Ouvre l'annonce")
    }

    private func headline(_ order: Order) -> String {
        switch order.status {
        case .cancelled: "Commande annulée"
        case .refunded: "Commande remboursée"
        default: order.status.label
        }
    }

    /// One short line under the status, per role.
    private func statusLine(_ order: Order) -> String {
        let buyer = role == .buyer
        switch order.status {
        case .paymentPending:
            return buyer ? "Valide le paiement dans \(order.payment.label)." : "En attente du paiement de l'acheteuse."
        case .paid, .awaitingShipment:
            return buyer ? "\(sellerName) prépare ton colis." : "Expédie le colis puis marque-le comme expédié."
        case .shipped:
            return buyer ? "Ton colis est en route." : "Le colis est en route."
        case .delivered, .buyerValidation:
            return buyer ? "Confirme la réception pour libérer les fonds." : "En attente de la confirmation de l'acheteuse."
        case .completed:
            return buyer ? "Fonds versés à \(sellerName)." : "Fonds versés sur ton compte \(order.payment.label)."
        case .cancelled:
            return "Le paiement est remboursé à l'acheteuse."
        case .disputed:
            return "Fonds bloqués pendant la médiation, réponse sous 48 h."
        case .returnPending:
            return "Fonds bloqués jusqu'au retour de l'article."
        case .refunded:
            return "Fonds recrédités à l'acheteuse."
        }
    }

    private var escrowNote: some View {
        Label {
            Text("Fonds en séquestre jusqu'à la confirmation, ou \(Catalog.escrowAutoReleaseHours) h après la livraison.")
        } icon: {
            Image(systemName: "lock.fill").foregroundStyle(RF.C.moneyDeep)
        }
        .font(RF.T.footnote)
        .foregroundStyle(RF.C.textDim)
    }

    private func amounts(_ order: Order) -> some View {
        VStack(spacing: 10) {
            amountRow("Article", Fmt.fcfa(order.itemPrice))
            amountRow("Livraison", order.deliveryFee > 0 ? Fmt.fcfa(order.deliveryFee) : "Gratuite")
            Divider().overlay(RF.C.line)
            HStack(alignment: .firstTextBaseline) {
                Text("Total")
                    .font(RF.T.headline)
                    .foregroundStyle(RF.C.text)
                Spacer()
                Text(Fmt.fcfa(order.total))
                    .font(RF.T.price(.headline))
                    .foregroundStyle(RF.C.text)
            }
            .accessibilityElement(children: .combine)
            amountRow("Paiement", order.payment.label)
        }
        .padding(16)
        .rfCard(radius: RF.R.md)
    }

    private func amountRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(RF.T.subheadline)
                .foregroundStyle(RF.C.textDim)
            Spacer(minLength: 12)
            Text(value)
                .font(RF.T.price(.subheadline, weight: .regular))
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
        let all = availableActions(order)
        let list = all.filter { !$0.isDemo } + all.filter(\.isDemo)   // demo helpers last
        if !list.isEmpty {
            VStack(spacing: 12) {
                ForEach(list, id: \.self) { action in
                    if action.isDemo {
                        TrackingDemoButton(title: action.title, isLoading: working == action) { trigger(action) }
                    } else {
                        RFButton(action.title, style: action == list.first(where: { !$0.isDemo }) && action.isPositive ? .primary : .secondary,
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
        case .ship: "Marquer comme expédiée"
        case .cancel: "Annuler la commande"
        case .confirmReceipt: "Confirmer la réception"
        case .dispute: "Signaler un problème"
        case .requestReturn: "Demander un retour"
        case .simulateShip: "Simuler l'expédition (démo)"
        case .simulateDeliver: "Simuler la livraison (démo)"
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
        case .cancel: "L'article est remis en vente et l'acheteuse remboursée."
        case .confirmReceipt: "Les fonds seront versés à la vendeuse."
        case .dispute: "Les fonds restent bloqués pendant la médiation, réponse sous 48 h."
        case .requestReturn: "Les fonds restent bloqués jusqu'au retour de l'article."
        default: ""
        }
    }
    var confirmButton: String {
        switch self {
        case .cancel: "Annuler la commande"
        case .confirmReceipt: "Confirmer"
        case .dispute: "Ouvrir un litige"
        case .requestReturn: "Demander le retour"
        default: title
        }
    }
    var doneMessage: String {
        switch self {
        case .ship, .simulateShip: "Commande expédiée"
        case .simulateDeliver: "Colis arrivé au point de retrait"
        case .cancel: "Commande annulée"
        case .confirmReceipt: "Réception confirmée"
        case .dispute: "Litige ouvert"
        case .requestReturn: "Demande de retour envoyée"
        }
    }
}

/// Discreet demo-only button (simulates the other party).
private struct TrackingDemoButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading { ProgressView().controlSize(.small) }
                Text(title)
            }
            .font(RF.T.footnote.weight(.semibold))
            .foregroundStyle(RF.C.textDim)
            .frame(maxWidth: .infinity, minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Reusable: timeline

/// Vertical happy-path timeline: done = filled check, current = hibiscus ring, pending = hairline.
/// For alternative outcomes, every step reached before the divergence is shown as done.
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

    /// Short step names (the full `OrderStatus.label` is used for the screen headline).
    static func shortLabel(_ status: OrderStatus) -> String {
        switch status {
        case .paymentPending: "Paiement"
        case .paid: "Payée"
        case .awaitingShipment: "Préparation"
        case .shipped: "Expédiée"
        case .delivered: "Livrée"
        case .buyerValidation: "Confirmation"
        case .completed: "Terminée"
        default: status.label
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, status in
                row(status, state: state(at: i), next: i + 1 < steps.count ? state(at: i + 1) : nil)
            }
        }
    }

    private func row(_ status: OrderStatus, state: StepState, next: StepState?) -> some View {
        let date = order.history.last(where: { $0.status == status })?.at
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(Self.shortLabel(status))
                .font(state == .current ? RF.T.subheadline.weight(.semibold) : RF.T.subheadline)
                .foregroundStyle(state == .pending ? RF.C.textDim : RF.C.text)
            Spacer(minLength: 8)
            if let date, state != .pending {
                Text(Fmt.relative(date))
                    .font(RF.T.footnote.monospacedDigit())
                    .foregroundStyle(RF.C.textDim)
            }
        }
        .padding(.leading, 28)
        .padding(.bottom, next == nil ? 0 : 20)
        .background(alignment: .topLeading) {
            ZStack(alignment: .top) {
                if next != nil {
                    Rectangle()
                        .fill(next == .pending ? RF.C.line : RF.C.text)
                        .frame(width: 2)
                        .padding(.top, 16)
                        .padding(.bottom, -4)
                }
                dot(state).padding(.top, 2)
            }
            .frame(width: 16)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibility(status, state: state, date: date))
    }

    private func dot(_ state: StepState) -> some View {
        ZStack {
            switch state {
            case .done:
                Circle().fill(RF.C.text)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
            case .current:
                Circle().fill(RF.C.card)
                Circle().strokeBorder(RF.C.hibiscus, lineWidth: 4)
            case .pending:
                Circle().fill(RF.C.card)
                Circle().strokeBorder(RF.C.line, lineWidth: 2)
            }
        }
        .frame(width: 16, height: 16)
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

// MARK: - Reusable: order row (Boîte › Commandes)

/// Compact order row for lists: photo, title, counterpart + date, total and `StatusPill`.
/// Tapping pushes `.order(id)` unless `onTap` is provided. No background: embed it in a List / card.
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
        if isSale { return order.buyerName }
        return store.cachedProfile(order.sellerId)?.username ?? "…"
    }

    var body: some View {
        Button {
            if let onTap { onTap() } else { router.push(.order(order.id)) }
        } label: {
            HStack(spacing: 12) {
                ListingPhotoView(photo: order.listingPhoto, listingId: order.listingId)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(order.listingTitle)
                        .font(RF.T.subheadline.weight(.semibold))
                        .foregroundStyle(RF.C.text)
                        .lineLimit(1)
                    Text("\(counterpart) · \(Fmt.relative(order.history.last?.at ?? order.createdAt))")
                        .font(RF.T.footnote)
                        .foregroundStyle(RF.C.textDim)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(Fmt.fcfa(order.total))
                        .font(RF.T.price(.subheadline))
                        .foregroundStyle(RF.C.text)
                    StatusPill(status: order.status)
                }
                .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: order.sellerId) {
            if !isSale { _ = await store.profile(order.sellerId) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(order.listingTitle), \(isSale ? "vente à" : "achat chez") \(counterpart), \(Fmt.fcfa(order.total)), \(order.status.label)")
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
