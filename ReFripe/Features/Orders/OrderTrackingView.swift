import SwiftUI

/// Suivi de commande (v3), same screen for buyer and seller (role = `order.sellerId == me`):
/// green escrow banner with a live countdown, listing, 4-step stepper Payé · Expédié · Remis · Terminé,
/// hand-off card (relais / Yango / main propre) with the buyer's 4-digit code — shown big to the BUYER,
/// typed by the SELLER (`confirmHandoff`) — and actions pinned at the bottom. A buyer opening an unpaid
/// order gets the payment flow (`PaymentPendingView`). After completion the buyer rates the seller.
/// The seller can never mark an order DELIVERED herself. Re-polls while the order can still change.
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
    /// nil until the first load; true while a buyer pays an unpaid order from here.
    @State private var paymentFlow: Bool?
    @State private var codeInput = ""
    @State private var isConfirmingCode = false
    @State private var hasReviewed = true
    @State private var showReview = false
    @FocusState private var codeFocused: Bool

    var body: some View {
        Group {
            if let order {
                if paymentFlow == true {
                    PaymentPendingView(order: order) { id in
                        if id == orderId {
                            withAnimation(.snappy) { paymentFlow = false }
                            Task { await refresh() }
                        } else {
                            router.pop()
                            router.push(.order(id))
                        }
                    }
                } else {
                    content(order)
                }
            } else if let loadError {
                ErrorStateView(error: loadError) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rfScreenBackground()
        .navigationTitle(paymentFlow == true ? "Paiement" : (order.map { "Commande \($0.shortNumber)" } ?? "Commande"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(paymentFlow == true ? .hidden : .automatic, for: .tabBar)
        .toolbar {
            if paymentFlow != true, order != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let order { Task { await contact(order) } }
                    } label: {
                        if isOpeningChat { ProgressView() } else { Image(systemName: "bubble.left") }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(role == .buyer ? "Écrire à la vendeuse" : "Écrire à l'acheteuse")
                }
            }
        }
        .sensoryFeedback(.success, trigger: successTick)
        .confirmationDialog(pendingConfirm?.confirmTitle ?? "",
                            isPresented: confirmBinding,
                            titleVisibility: .visible,
                            presenting: pendingConfirm) { action in
            Button(action.confirmButton, role: action.isDestructive ? .destructive : nil) {
                Task { await perform(action) }
            }
            Button("Retour", role: .cancel) {}
        } message: { action in
            if let m = action.confirmMessage(seller: sellerName) { Text(m) }
        }
        .sheet(isPresented: $showReview) {
            if let order {
                ReviewSheet(order: order, sellerName: sellerName) {
                    hasReviewed = true
                }
                .environment(store)
            }
        }
        .task {
            await load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                if paymentFlow == true { continue }                     // PaymentPendingView polls itself
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

    private var confirmBinding: Binding<Bool> {
        Binding(get: { pendingConfirm != nil }, set: { if !$0 { pendingConfirm = nil } })
    }

    // MARK: Data

    private func load() async {
        loadError = nil
        do {
            let o = try await store.repo.order(id: orderId)
            if paymentFlow == nil {
                paymentFlow = o.status == .paymentPending && o.buyerId == store.me?.id
            }
            order = o
            sellerProfile = await store.profile(o.sellerId)
            await checkReview(o)
        } catch {
            if order == nil { loadError = error } else { store.show(error) }
        }
    }

    private func refresh() async {
        guard let fresh = try? await store.repo.order(id: orderId) else { return }
        let previous = order?.status
        if fresh != order { withAnimation(.snappy) { order = fresh } }
        if let previous, previous != fresh.status {
            if [.paid, .delivered, .completed].contains(fresh.status) { successTick += 1 }
            await checkReview(fresh)
            await store.refreshBadges()
        }
    }

    /// Buyer + completed: has she already rated this order?
    private func checkReview(_ o: Order) async {
        guard o.status == .completed, let me = store.me?.id, o.buyerId == me else { return }
        let reviews = (try? await store.repo.reviews(userId: o.sellerId)) ?? []
        hasReviewed = reviews.contains { $0.orderId == o.id && $0.reviewerId == me }
    }

    private func perform(_ action: TrackingAction) async {
        guard var current = order, working == nil else { return }
        working = action
        defer { working = nil }
        do {
            switch action {
            case .ship, .simulateShip:
                current = try await store.repo.advanceOrder(id: current.id, to: .shipped)
            case .simulateHandoff:
                current = try await store.repo.confirmHandoff(orderId: current.id, code: current.handoffCode ?? "")
            case .cancel:
                current = try await store.repo.advanceOrder(id: current.id, to: .cancelled)
            case .confirmReceipt:
                if current.status == .delivered {
                    current = try await store.repo.advanceOrder(id: current.id, to: .buyerValidation)
                }
                current = try await store.repo.advanceOrder(id: current.id, to: .completed)
            case .dispute:
                current = try await store.repo.advanceOrder(id: current.id, to: .disputed)
            case .review:
                showReview = true
                return
            }
            withAnimation(.snappy) { order = current }
            if action.isPositive { successTick += 1 } else { Haptics.warning() }
            store.show(action.doneMessage)
            await store.refreshBadges()
            if action == .confirmReceipt && current.status == .completed {
                hasReviewed = false
                try? await Task.sleep(for: .milliseconds(600))
                showReview = true
            }
        } catch {
            Haptics.error()
            store.show(error)
            await refresh()
        }
    }

    private func submitCode(_ order: Order) async {
        let code = codeInput.filter(\.isNumber)
        guard code.count == Catalog.handoffCodeLength, !isConfirmingCode else { return }
        isConfirmingCode = true
        defer { isConfirmingCode = false }
        do {
            let updated = try await store.repo.confirmHandoff(orderId: order.id, code: code)
            withAnimation(.snappy) { self.order = updated }
            codeInput = ""
            codeFocused = false
            successTick += 1
            store.show("Remise validée")
            await store.refreshBadges()
        } catch {
            Haptics.error()
            store.show(error)
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
            VStack(alignment: .leading, spacing: RF.S.lg) {
                escrowBanner(order)

                if let info = order.status.alternativeInfo {
                    Label(info.title, systemImage: info.symbol)
                        .font(RF.T.headline)
                        .foregroundStyle(order.status.tone == .alert ? RF.C.hibiscusText : RF.C.text)
                        .padding(RF.S.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .rfCard(radius: RF.R.md)
                }

                contextCard(order)

                OrderStepper(order: order)
                    .padding(RF.S.lg)
                    .rfCard(radius: RF.R.md)

                if !order.status.isAlternative && order.status != .paymentPending {
                    handoffCard(order)
                }

                amounts(order)
            }
            .padding(RF.S.gutter)
            .padding(.bottom, RF.S.lg)
            .animation(.snappy, value: order.status)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await refresh() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            let list = availableActions(order)
            if !list.isEmpty {
                actions(list)
                    .padding(.horizontal, RF.S.gutter)
                    .padding(.vertical, 10)
                    .background(RF.C.paper)
                    .overlay(alignment: .top) { Rectangle().fill(RF.C.line).frame(height: 0.5) }
            }
        }
    }

    // MARK: Escrow banner

    @ViewBuilder private func escrowBanner(_ order: Order) -> some View {
        let held: [OrderStatus] = [.paid, .awaitingShipment, .shipped, .delivered, .buyerValidation, .disputed, .returnPending]
        if held.contains(order.status) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let left = order.escrowReleaseAt.flatMap { EscrowCountdown.text(until: $0, now: context.date) }
                let countdownApplies = order.awaitsBuyerConfirmation && left != nil
                let text: String = {
                    if role == .buyer {
                        return countdownApplies ? "Argent bloqué · \(left ?? "")" : "Argent bloqué"
                    }
                    return countdownApplies ? "Versement dans \(left ?? "")" : "Paiement sécurisé"
                }()
                Label(text, systemImage: "lock.fill")
                    .font(RF.T.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(RF.C.moneyDeep)
                    .padding(.vertical, 12)
                    .padding(.horizontal, RF.S.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RF.C.money.opacity(0.12), in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
                    .accessibilityLabel(role == .buyer && countdownApplies
                                        ? "Argent bloqué jusqu'à ta confirmation, versé à \(sellerName) dans \(left ?? "")"
                                        : text)
            }
        }
    }

    // MARK: Listing

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
                    Text(role == .buyer ? sellerName : order.buyerName)
                        .font(RF.T.footnote)
                        .foregroundStyle(RF.C.textDim)
                    Text(Fmt.fcfa(order.total))
                        .font(RF.T.price(.footnote))
                        .foregroundStyle(RF.C.text)
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
        .accessibilityLabel("\(order.listingTitle), \(Fmt.fcfa(order.total))")
        .accessibilityHint("Ouvre l'annonce")
    }

    // MARK: Hand-off

    private func handoffCard(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: RF.S.md) {
            HStack(spacing: RF.S.md) {
                Image(systemName: order.delivery.symbol)
                    .font(RF.T.body)
                    .foregroundStyle(RF.C.text)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(order.delivery.txTitle)
                        .font(RF.T.headline)
                        .foregroundStyle(RF.C.text)
                    Text(placeLine(order.delivery))
                        .font(RF.T.footnote)
                        .foregroundStyle(RF.C.textDim)
                }
                Spacer(minLength: 0)
                if [.delivered, .buyerValidation, .completed].contains(order.status) {
                    Label("Remis", systemImage: "checkmark.circle.fill")
                        .font(RF.T.footnote.weight(.semibold))
                        .foregroundStyle(RF.C.moneyDeep)
                }
            }

            if order.status == .shipped || order.awaitsShipping {
                Rectangle().fill(RF.C.line).frame(height: 0.5)
                if role == .buyer {
                    buyerCode(order)
                } else if order.status == .shipped {
                    sellerCodeInput(order)
                }
            }
        }
        .padding(RF.S.lg)
        .rfCard(radius: RF.R.md)
    }

    /// Placeholders until the relay / courier data exists in the contract.
    private func placeLine(_ d: DeliveryMethod) -> String {
        switch d {
        case .relais: "[Point relais] · [Adresse]"
        case .yango: "Coursier Yango"
        case .mainPropre: "Lieu à convenir"
        }
    }

    @ViewBuilder private func buyerCode(_ order: Order) -> some View {
        if order.status == .shipped, let code = order.handoffCode {
            VStack(spacing: RF.S.xs) {
                Text("Code de retrait")
                    .font(RF.T.footnote.weight(.semibold))
                    .foregroundStyle(RF.C.textDim)
                Text(code)
                    .font(RF.T.number(.largeTitle, weight: .bold))
                    .kerning(8)
                    .foregroundStyle(RF.C.text)
                    .textSelection(.enabled)
                    .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
                Text(codeHint(order.delivery))
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.textDim)
            }
            .frame(maxWidth: .infinity)
        } else {
            Label("Code à l'expédition", systemImage: "number")
                .font(RF.T.footnote)
                .foregroundStyle(RF.C.textDim)
        }
    }

    private func codeHint(_ d: DeliveryMethod) -> String {
        switch d {
        case .relais: "Au point relais, sur place"
        case .yango: "Au livreur, sur place"
        case .mainPropre: "À la vendeuse, sur place"
        }
    }

    private func sellerCodeInput(_ order: Order) -> some View {
        let ready = codeInput.filter(\.isNumber).count == Catalog.handoffCodeLength
        return VStack(alignment: .leading, spacing: RF.S.sm) {
            Text("Code de l'acheteuse")
                .font(RF.T.footnote.weight(.semibold))
                .foregroundStyle(RF.C.textDim)
            HStack(spacing: RF.S.sm) {
                TextField("0000", text: $codeInput)
                    .font(RF.T.number(.title2, weight: .semibold))
                    .kerning(6)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($codeFocused)
                    .padding(.horizontal, RF.S.md)
                    .frame(minHeight: 50)
                    .background(RF.C.paperDim, in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
                    .onChange(of: codeInput) {
                        let digits = String(codeInput.filter(\.isNumber).prefix(Catalog.handoffCodeLength))
                        if digits != codeInput { codeInput = digits }
                    }
                    .accessibilityLabel("Code de l'acheteuse")
                RFButton("Valider", isLoading: isConfirmingCode) {
                    Task { await submitCode(order) }
                }
                .frame(width: 120)
                .disabled(!ready)
            }
        }
    }

    // MARK: Amounts

    private func amounts(_ order: Order) -> some View {
        VStack(spacing: 10) {
            amountRow("Article", Fmt.fcfa(order.itemPrice))
            amountRow("Remise", order.deliveryFee > 0 ? Fmt.fcfa(order.deliveryFee) : "Gratuit")
            Rectangle().fill(RF.C.line).frame(height: 0.5)
            HStack(alignment: .firstTextBaseline) {
                Text("Total").font(RF.T.headline).foregroundStyle(RF.C.text)
                Spacer()
                Text(Fmt.fcfa(order.total)).font(RF.T.price(.headline)).foregroundStyle(RF.C.text)
            }
            .accessibilityElement(children: .combine)
            amountRow("Paiement", order.payment.label)
        }
        .padding(RF.S.lg)
        .rfCard(radius: RF.R.md)
    }

    private func amountRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(RF.T.subheadline).foregroundStyle(RF.C.textDim)
            Spacer(minLength: 12)
            Text(value).font(RF.T.price(.subheadline, weight: .regular)).foregroundStyle(RF.C.text)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func availableActions(_ order: Order) -> [TrackingAction] {
        var list: [TrackingAction] = []
        switch (role, order.status) {
        case (.seller, .paid), (.seller, .awaitingShipment):
            list = [.ship, .cancel]
        case (.buyer, .paid):
            list = [.cancel]
        case (.buyer, .awaitingShipment):
            list = [.cancel]
            if store.isDemo { list.append(.simulateShip) }
        case (.buyer, .shipped):
            list = [.dispute]
            if store.isDemo && order.handoffCode != nil { list.append(.simulateHandoff) }
        case (.buyer, .delivered), (.buyer, .buyerValidation):
            list = [.confirmReceipt, .dispute]
        case (.buyer, .completed):
            if !hasReviewed { list = [.review] }
        default:
            break
        }
        return list
    }

    private func actions(_ list: [TrackingAction]) -> some View {
        let main = list.filter { !$0.isDemo }
        let demo = list.filter(\.isDemo)
        return VStack(spacing: 8) {
            if main.count == 2 {
                HStack(spacing: RF.S.sm) {
                    ForEach(main, id: \.self) { button($0, primary: $0 == main.first && $0.isPositive) }
                }
            } else {
                ForEach(main, id: \.self) { button($0, primary: $0.isPositive) }
            }
            ForEach(demo, id: \.self) { action in
                TrackingDemoButton(title: action.title, isLoading: working == action) { trigger(action) }
            }
        }
        .disabled(working != nil)
    }

    private func button(_ action: TrackingAction, primary: Bool) -> some View {
        RFButton(action.title, style: primary ? .primary : .ghost, isLoading: working == action) { trigger(action) }
    }

    private func trigger(_ action: TrackingAction) {
        if action.needsConfirmation { pendingConfirm = action } else { Task { await perform(action) } }
    }
}

// MARK: - Actions model

private enum TrackingAction: Hashable {
    case ship, cancel, confirmReceipt, dispute, review, simulateShip, simulateHandoff

    var title: String {
        switch self {
        case .ship: "Expédié"
        case .cancel: "Annuler"
        case .confirmReceipt: "Confirmer"
        case .dispute: "Signaler"
        case .review: "Noter"
        case .simulateShip: "Simuler l'envoi (démo)"
        case .simulateHandoff: "Simuler la remise (démo)"
        }
    }
    var isDemo: Bool { self == .simulateShip || self == .simulateHandoff }
    var isPositive: Bool { [.ship, .confirmReceipt, .review, .simulateShip, .simulateHandoff].contains(self) }
    var isDestructive: Bool { self == .cancel || self == .dispute }
    var needsConfirmation: Bool { [.ship, .cancel, .confirmReceipt, .dispute].contains(self) }

    var confirmTitle: String {
        switch self {
        case .ship: "Colis expédié ?"
        case .cancel: "Annuler la commande ?"
        case .confirmReceipt: "Tout est OK ?"
        case .dispute: "Signaler un problème ?"
        default: ""
        }
    }
    func confirmMessage(seller: String) -> String? {
        switch self {
        case .confirmReceipt: "L'argent sera versé à \(seller)."
        case .dispute: "L'argent reste bloqué."
        case .cancel: "Remboursement intégral."
        default: nil
        }
    }
    var confirmButton: String {
        switch self {
        case .ship: "Expédié"
        case .cancel: "Annuler la commande"
        case .confirmReceipt: "Confirmer"
        case .dispute: "Signaler"
        default: title
        }
    }
    var doneMessage: String {
        switch self {
        case .ship, .simulateShip: "Expédiée"
        case .simulateHandoff: "Remise validée"
        case .cancel: "Annulée"
        case .confirmReceipt: "Merci"
        case .dispute: "Litige ouvert"
        case .review: ""
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
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Stepper

/// Horizontal 4-step progress: Payé · Expédié · Remis · Terminé.
struct OrderStepper: View {
    let order: Order

    var body: some View {
        let done = OrderStep.doneCount(for: order)
        let current = order.status.isAlternative ? nil : (done < OrderStep.allCases.count ? done : nil)
        HStack(alignment: .top, spacing: 0) {
            ForEach(OrderStep.allCases, id: \.self) { step in
                let i = step.rawValue
                VStack(spacing: 6) {
                    HStack(spacing: 0) {
                        connector(visible: i > 0, filled: i <= done)
                        dot(done: i < done, current: i == current)
                        connector(visible: i < OrderStep.allCases.count - 1, filled: i + 1 <= done)
                    }
                    Text(step.title)
                        .font(i == current ? RF.T.caption.weight(.semibold) : RF.T.caption)
                        .foregroundStyle(i < done || i == current ? RF.C.text : RF.C.textDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let date = step.date(in: order), i < done {
                        Text(Fmt.relative(date))
                            .font(RF.T.caption.monospacedDigit())
                            .foregroundStyle(RF.C.textDim)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(step.title), \(i < done ? "fait" : (i == current ? "en cours" : "à venir"))")
            }
        }
    }

    private func connector(visible: Bool, filled: Bool) -> some View {
        Rectangle()
            .fill(visible ? (filled ? RF.C.text : RF.C.line) : Color.clear)
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }

    private func dot(done: Bool, current: Bool) -> some View {
        ZStack {
            if done {
                Circle().fill(RF.C.text)
                Image(systemName: "checkmark")
                    .font(RF.T.caption.weight(.bold))
                    .imageScale(.small)
                    .foregroundStyle(RF.C.card)
            } else if current {
                Circle().fill(RF.C.card)
                Circle().strokeBorder(RF.C.hibiscus, lineWidth: 4)
            } else {
                Circle().fill(RF.C.card)
                Circle().strokeBorder(RF.C.line, lineWidth: 2)
            }
        }
        .frame(width: 20, height: 20)
    }
}

// MARK: - Reusable: order row (Mes achats / Mes ventes)

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
            .frame(minHeight: 44)
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
