import SwiftUI

/// Écran 4 — Paiement (mockup `screenCheckout`, PANEL `checkout`).
/// Récap article, mode de remise proposé par l'annonce, Wave / Orange Money, note séquestre, total.
/// « Payer » → `repo.createOrder` (en mode réel, le dépôt ouvre l'URL Wave/OM) → suivi de commande.
@MainActor
struct CheckoutView: View {
    let listingId: UUID

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var listing: Listing?
    @State private var seller: UserProfile?
    @State private var loadError: Error?
    @State private var delivery: DeliveryMethod?
    @State private var payment: PaymentMethod = .wave
    @State private var isPaying = false

    var body: some View {
        Group {
            if let listing {
                if let reason = blockReason(for: listing) {
                    blocked(reason, listing: listing)
                } else {
                    content(listing)
                }
            } else if let loadError {
                ErrorStateView(error: loadError) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rfScreenBackground()
        .navigationTitle("Paiement")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: Data

    private var negotiatedPrice: FCFA? { store.negotiatedPrices[listingId] }

    private func itemPrice(_ listing: Listing) -> FCFA { negotiatedPrice ?? listing.price }

    private func methods(_ listing: Listing) -> [DeliveryMethod] {
        listing.deliveryMethods.isEmpty ? [.relais, .mainPropre] : listing.deliveryMethods
    }

    private func load() async {
        loadError = nil
        do {
            let l = try await store.repo.listing(id: listingId)
            listing = l
            let available = methods(l)
            if let current = delivery, available.contains(current) {} else { delivery = available.first }
            seller = await store.profile(l.sellerId)
        } catch {
            if listing == nil { loadError = error } else { store.show(error) }
        }
    }

    private func blockReason(for listing: Listing) -> (symbol: String, title: String, message: String)? {
        if let me = store.me?.id, listing.sellerId == me {
            return ("person.crop.circle.badge.exclamationmark", "C'est ton annonce",
                    "Tu ne peux pas acheter ton propre article.")
        }
        guard listing.status == .active else {
            return ("bag.badge.minus", "Article plus disponible",
                    "Cet article vient d'être réservé ou vendu. Découvre d'autres pièces qui pourraient te plaire.")
        }
        return nil
    }

    private func pay(_ listing: Listing) async {
        guard let delivery, !isPaying else { return }
        isPaying = true
        defer { isPaying = false }
        do {
            let order = try await store.repo.createOrder(listingId: listing.id, delivery: delivery, payment: payment)
            store.negotiatedPrices[listing.id] = nil
            Haptics.success()
            router.pop()
            router.push(.order(order.id))
        } catch {
            Haptics.error()
            store.show(error)
            await load()   // the listing may have been reserved meanwhile
        }
    }

    // MARK: Views

    private func blocked(_ reason: (symbol: String, title: String, message: String), listing: Listing) -> some View {
        ScrollView {
            EmptyStateView(symbol: reason.symbol, title: reason.title, message: reason.message,
                           actionTitle: "Retour") {
                router.pop()
            }
        }
    }

    private func content(_ listing: Listing) -> some View {
        let fee = delivery?.fee ?? 0
        let total = itemPrice(listing) + fee
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summaryRow(listing)

                coLabel("Livraison")
                VStack(spacing: 10) {
                    ForEach(methods(listing)) { method in
                        CheckoutDeliveryOption(method: method, selected: delivery == method) {
                            delivery = method
                        }
                    }
                }

                coLabel("Moyen de paiement")
                VStack(spacing: 10) {
                    ForEach(PaymentMethod.allCases) { method in
                        CheckoutPaymentRow(method: method, selected: payment == method) {
                            payment = method
                        }
                    }
                }

                EscrowLockNote(text: "Fonds bloqués jusqu'à confirmation de réception — libérés automatiquement sous \(Catalog.escrowAutoReleaseHours)h si tout va bien.")
                    .padding(.top, 16)

                HStack(alignment: .firstTextBaseline) {
                    Text("Total")
                        .font(RF.F.body(12.5, .bold))
                        .foregroundStyle(RF.C.textDim)
                    Spacer()
                    Text(Fmt.fcfa(total))
                        .font(RF.F.mono(20, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(RF.C.text)
                        .contentTransition(.numericText(value: Double(total)))
                        .animation(.snappy(duration: 0.2), value: total)
                }
                .padding(.vertical, 18)
                .accessibilityElement(children: .combine)

                RFButton("Payer avec \(payment.label)", symbol: "lock.fill", isLoading: isPaying) {
                    Task { await pay(listing) }
                }
                .disabled(delivery == nil)
            }
            .padding(.horizontal, RF.S.gutter)
            .padding(.vertical, 14)
        }
        .sensoryFeedback(.selection, trigger: delivery)
        .sensoryFeedback(.selection, trigger: payment)
    }

    private func summaryRow(_ listing: Listing) -> some View {
        HStack(spacing: 10) {
            ListingPhotoView(photo: listing.photos.first, listingId: listing.id)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: RF.R.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(listing.title)
                    .font(RF.F.body(12.5, .bold))
                    .foregroundStyle(RF.C.text)
                    .lineLimit(2)
                Text(subtitle(listing))
                    .font(RF.F.body(10.5))
                    .foregroundStyle(RF.C.textDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.fcfa(itemPrice(listing)))
                    .font(RF.F.mono(12.5, .medium))
                    .monospacedDigit()
                    .foregroundStyle(RF.C.text)
                if negotiatedPrice != nil, negotiatedPrice != listing.price {
                    Text(Fmt.fcfa(listing.price))
                        .font(RF.F.mono(10))
                        .strikethrough()
                        .foregroundStyle(RF.C.textDim)
                }
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(RF.C.line).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ listing: Listing) -> String {
        var s = "\(listing.sizeLabel) · vendu par \(seller?.username ?? "…")"
        if negotiatedPrice != nil { s += " · prix négocié" }
        return s
    }

    private func coLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(RF.F.body(11, .bold))
            .kerning(0.66)
            .foregroundStyle(RF.C.textDim)
            .padding(.top, 18)
            .padding(.bottom, 10)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Reusable bits

/// Delivery option button (mockup `.method-btn`): icon, label + subtitle, fee or « Gratuit ».
struct CheckoutDeliveryOption: View {
    let method: DeliveryMethod
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RF.R.md, style: .continuous)
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: method.symbol)
                    .font(.system(size: 17))
                    .frame(width: 22)
                    .foregroundStyle(RF.C.text)
                VStack(alignment: .leading, spacing: 2) {
                    Text(method.label)
                        .font(RF.F.body(13, .bold))
                        .foregroundStyle(RF.C.text)
                    Text(method.subtitle)
                        .font(RF.F.body(10.5))
                        .foregroundStyle(RF.C.textDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                Text(method.fee > 0 ? Fmt.fcfa(method.fee) : "Gratuit")
                    .font(RF.F.mono(12, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(RF.C.text)
                    .fixedSize()
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .background(selected ? RF.C.hibiscus.opacity(0.06) : RF.C.card, in: shape)
            .overlay(shape.strokeBorder(selected ? RF.C.hibiscus : RF.C.line, lineWidth: 1.5))
            .contentShape(shape)
        }
        .buttonStyle(RFPressStyle(scale: 0.98))
        .accessibilityLabel("\(method.label), \(method.fee > 0 ? Fmt.fcfa(method.fee) : "gratuit")")
        .accessibilityHint(method.subtitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Wave / Orange Money row (mockup `.paymethod`): brand-coloured logo tile, name, radio dot.
struct CheckoutPaymentRow: View {
    let method: PaymentMethod
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RF.R.md, style: .continuous)
        Button(action: action) {
            HStack(spacing: 12) {
                PaymentBrandLogo(method: method)
                Text(method.label)
                    .font(RF.F.body(13, .bold))
                    .foregroundStyle(RF.C.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle().strokeBorder(selected ? RF.C.money : RF.C.line, lineWidth: 2)
                    if selected { Circle().fill(RF.C.money).padding(4) }
                }
                .frame(width: 16, height: 16)
            }
            .padding(13)
            .background(selected ? RF.C.money.opacity(0.07) : Color.clear, in: shape)
            .overlay(shape.strokeBorder(selected ? RF.C.money : RF.C.line, lineWidth: 1.5))
            .contentShape(shape)
        }
        .buttonStyle(RFPressStyle(scale: 0.98))
        .accessibilityLabel(method.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Brand tile (mockup `.paylogo`): « WAVE » / « OM » on the brand colour.
struct PaymentBrandLogo: View {
    let method: PaymentMethod
    var size: CGFloat = 30

    var body: some View {
        Text(method.badge)
            .font(.custom(RF.F.MonoWeight.semibold.rawValue, fixedSize: size * 0.3))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: size, height: size)
            .background(Color(hex: method.brandHex), in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Green escrow note with a padlock (mockup `.escrow-note`).
struct EscrowLockNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RF.C.moneyDeep)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(text)
                .font(RF.F.body(11.5, .semibold))
                .lineSpacing(3)
                .foregroundStyle(RF.C.moneyDeep)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(RF.C.money.opacity(0.09), in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RF.R.md, style: .continuous)
            .strokeBorder(RF.C.money.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Paiement") {
    NavigationStack { CheckoutView(listingId: DemoIDs.listing(2)) }.previewEnvironment()
}

#Preview("Propre annonce") {
    NavigationStack { CheckoutView(listingId: DemoIDs.listing(1)) }.previewEnvironment()
}
