import SwiftUI
import UIKit

/// « Confirme dans Wave »: starts (or resumes) the payment of a PAYMENT_PENDING order, opens the Wave /
/// Orange Money app (never a WebView), polls `order(id:)` every 3 s and turns into a receipt once paid.
/// Embedded by `CheckoutView` (after « Payer ») and by `OrderTrackingView` (resume an unpaid order).
/// The host sets the navigation title.
@MainActor
struct PaymentPendingView: View {
    /// Called by « Suivre ma commande » with the (possibly new, after a method switch) order id.
    let onTrack: (UUID) -> Void

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var order: Order
    @State private var session: PaymentSession?
    @State private var startError: Error?
    @State private var isSwitching = false
    @State private var paidTick = 0

    init(order: Order, onTrack: @escaping (UUID) -> Void) {
        _order = State(initialValue: order)
        self.onTrack = onTrack
    }

    private var isPending: Bool { order.status == .paymentPending }
    private var method: PaymentMethod { order.payment }

    var body: some View {
        Group {
            if isPending {
                pending
            } else if order.status == .cancelled || order.status == .refunded {
                failed
            } else {
                receipt
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rfScreenBackground()
        .sensoryFeedback(.success, trigger: paidTick)
        .task(id: order.id) { await run() }
    }

    // MARK: Flow

    private func run() async {
        guard isPending else { return }
        await start()
        while !Task.isCancelled && isPending {
            try? await Task.sleep(for: .seconds(Catalog.paymentPollInterval))
            guard !Task.isCancelled else { return }
            guard let fresh = try? await store.repo.order(id: order.id) else { continue }
            if fresh.status != .paymentPending {
                withAnimation(.snappy) { order = fresh }
                if fresh.status != .cancelled { paidTick += 1 }
                await store.refreshBadges()
            } else if fresh != order {
                order = fresh
            }
        }
    }

    private func start() async {
        startError = nil
        do {
            let s = try await store.repo.startPayment(orderId: order.id)
            session = s
            PaymentPhoneMemory.set(s.maskedPhone, for: s.method)
        } catch {
            startError = error
        }
    }

    private func openProvider() {
        guard let url = session?.checkoutURL else { return }
        UIApplication.shared.open(url)
    }

    private func dial(_ code: String) {
        let encoded = code.replacingOccurrences(of: "#", with: "%23")
        guard let url = URL(string: "tel:\(encoded)") else { return }
        UIApplication.shared.open(url)
    }

    /// Switch Wave ⇄ Orange Money: the order's method is fixed, so cancel it and create a new one.
    private func switchMethod() async {
        guard !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }
        let target = method.other
        do {
            _ = try await store.repo.advanceOrder(id: order.id, to: .cancelled)
            let fresh = try await store.repo.createOrder(listingId: order.listingId, delivery: order.delivery, payment: target)
            session = nil
            withAnimation(.snappy) { order = fresh }   // restarts `.task(id:)`
        } catch {
            Haptics.error()
            store.show(error)
        }
    }

    // MARK: Pending

    private var pending: some View {
        ScrollView {
            VStack(spacing: RF.S.xl) {
                VStack(spacing: RF.S.sm) {
                    PaymentBrandLogo(method: method, size: 64)
                    Text("Confirme dans \(method.label)")
                        .font(RF.T.title3)
                        .foregroundStyle(RF.C.text)
                        .multilineTextAlignment(.center)
                    Text(Fmt.fcfa(session?.amount ?? order.total))
                        .font(RF.T.price(.largeTitle, weight: .bold))
                        .foregroundStyle(RF.C.text)
                    if let phone = session?.maskedPhone {
                        Text("Débité sur \(phone)")
                            .font(RF.T.footnote.monospacedDigit())
                            .foregroundStyle(RF.C.textDim)
                    }
                }
                .padding(.top, RF.S.lg)
                .accessibilityElement(children: .combine)

                steps

                if let code = session?.ussdCode {
                    ussdCard(code)
                }

                if let startError {
                    VStack(spacing: RF.S.sm) {
                        Text(startError.localizedDescription)
                            .font(RF.T.footnote)
                            .foregroundStyle(RF.C.hibiscusText)
                            .multilineTextAlignment(.center)
                        Button("Réessayer") { Task { await start() } }
                            .font(RF.T.subheadline.weight(.semibold))
                            .tint(RF.C.hibiscusText)
                            .frame(minHeight: 44)
                    }
                }
            }
            .padding(.horizontal, RF.S.gutter)
            .padding(.bottom, RF.S.xl)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: RF.S.sm) {
                if session?.checkoutURL != nil {
                    RFButton("Ouvrir \(method.label)", symbol: "arrow.up.forward.app") { openProvider() }
                } else if session == nil && startError == nil {
                    RFButton("Ouvrir \(method.label)", isLoading: true) {}
                }
                RFButton("Payer avec \(method.other.label)", style: .ghost, isLoading: isSwitching) {
                    Task { await switchMethod() }
                }
            }
            .padding(.horizontal, RF.S.gutter)
            .padding(.vertical, RF.S.sm)
            .background(RF.C.paper)
            .overlay(alignment: .top) { Rectangle().fill(RF.C.line).frame(height: 0.5) }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaymentStepRow(title: "Commande créée", state: .done)
            PaymentStepRow(title: "Validation", state: .current)
            PaymentStepRow(title: "Reçu", state: .pending)
        }
        .padding(RF.S.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rfCard(radius: RF.R.md)
    }

    private func ussdCard(_ code: String) -> some View {
        VStack(spacing: RF.S.md) {
            Text("Code USSD")
                .font(RF.T.footnote.weight(.semibold))
                .foregroundStyle(RF.C.textDim)
            Text(code)
                .font(RF.T.price(.title2, weight: .bold))
                .foregroundStyle(RF.C.text)
                .textSelection(.enabled)
            HStack(spacing: RF.S.sm) {
                RFButton("Copier", symbol: "doc.on.doc", style: .secondary) {
                    UIPasteboard.general.string = code
                    Haptics.success()
                    store.show("Copié")
                }
                RFButton("Composer", symbol: "phone", style: .secondary) { dial(code) }
            }
        }
        .padding(RF.S.lg)
        .frame(maxWidth: .infinity)
        .rfCard(radius: RF.R.md)
    }

    // MARK: Receipt

    private var paidAt: Date {
        order.history.first(where: { $0.status == .paid })?.at ?? order.history.last?.at ?? .now
    }

    private var reference: String { order.paymentReference ?? order.shortNumber }

    private var receiptText: String {
        """
        Reçu ReFripe
        \(order.listingTitle)
        Montant : \(Fmt.fcfa(order.total))
        Payé avec \(order.payment.label)
        Référence : \(reference)
        Date : \(Self.dateLabel(paidAt))
        """
    }

    private static func dateLabel(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(Locale(identifier: "fr_FR")))
    }

    private var receipt: some View {
        ScrollView {
            VStack(spacing: RF.S.xl) {
                VStack(spacing: RF.S.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(RF.T.largeTitle)
                        .foregroundStyle(RF.C.money)
                    Text("Paiement reçu")
                        .font(RF.T.title3)
                        .foregroundStyle(RF.C.text)
                }
                .padding(.top, RF.S.xl)
                .accessibilityElement(children: .combine)

                VStack(spacing: 10) {
                    receiptRow("Montant", Fmt.fcfa(order.total))
                    receiptRow("Moyen", order.payment.label)
                    receiptRow("Référence", reference)
                    receiptRow("Date", Self.dateLabel(paidAt))
                    Rectangle().fill(RF.C.line).frame(height: 0.5)
                    ShareLink(item: receiptText) {
                        Label("Partager", systemImage: "square.and.arrow.up")
                            .font(RF.T.subheadline.weight(.semibold))
                            .foregroundStyle(RF.C.hibiscusText)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .padding(RF.S.lg)
                .rfCard(radius: RF.R.md)

                EscrowLockNote(text: "Argent bloqué jusqu'à réception")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, RF.S.gutter)
            .padding(.bottom, RF.S.xl)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RFButton("Suivre ma commande") { onTrack(order.id) }
                .padding(.horizontal, RF.S.gutter)
                .padding(.vertical, RF.S.sm)
                .background(RF.C.paper)
        }
    }

    private func receiptRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(RF.T.subheadline).foregroundStyle(RF.C.textDim)
            Spacer(minLength: 12)
            Text(value).font(RF.T.price(.subheadline, weight: .regular)).foregroundStyle(RF.C.text)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Failed

    private var failed: some View {
        ContentUnavailableView {
            Label("Paiement annulé", systemImage: "xmark.circle")
        } actions: {
            Button("Retour") { router.pop() }
                .buttonStyle(.bordered)
                .tint(RF.C.hibiscus)
        }
    }
}

/// One step of the payment status: done (check), current (spinner), pending (hairline circle).
struct PaymentStepRow: View {
    enum Phase { case done, current, pending }
    let title: String
    let state: Phase

    var body: some View {
        HStack(spacing: RF.S.md) {
            Group {
                switch state {
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(RF.C.money)
                case .current:
                    ProgressView().controlSize(.small)
                case .pending:
                    Image(systemName: "circle").foregroundStyle(RF.C.line)
                }
            }
            .font(RF.T.title3)
            .frame(width: 24, height: 24)
            Text(title)
                .font(state == .current ? RF.T.subheadline.weight(.semibold) : RF.T.subheadline)
                .foregroundStyle(state == .pending ? RF.C.textDim : RF.C.text)
        }
        .accessibilityElement(children: .combine)
    }
}
