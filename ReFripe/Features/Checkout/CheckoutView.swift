import SwiftUI

/// Paiement.
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
                    "Il vient d'être réservé ou vendu.")
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
        ContentUnavailableView {
            Label(reason.title, systemImage: reason.symbol)
        } description: {
            Text(reason.message)
        } actions: {
            Button("Retour") { router.pop() }
                .buttonStyle(.bordered)
                .tint(RF.C.hibiscus)
        }
    }

    private func content(_ listing: Listing) -> some View {
        let fee = delivery?.fee ?? 0
        let total = itemPrice(listing) + fee
        let available = methods(listing)
        return ScrollView {
            VStack(alignment: .leading, spacing: RF.S.xl) {
                summaryRow(listing)

                section("Livraison") {
                    ProductGroupedRows(count: available.count) { i in
                        let method = available[i]
                        CheckoutDeliveryOption(method: method, selected: delivery == method) {
                            delivery = method
                        }
                    }
                }

                section("Paiement") {
                    ProductGroupedRows(count: PaymentMethod.allCases.count) { i in
                        let method = PaymentMethod.allCases[i]
                        CheckoutPaymentRow(method: method, selected: payment == method) {
                            payment = method
                        }
                    }
                }

                EscrowLockNote(text: "Payé à la vendeuse après ta confirmation de réception.")
            }
            .padding(EdgeInsets(top: RF.S.lg, leading: RF.S.gutter, bottom: RF.S.xl, trailing: RF.S.gutter))
        }
        // Total + pay button pinned above the tab bar, always visible.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Total")
                        .font(RF.T.body)
                        .foregroundStyle(RF.C.textDim)
                    Spacer()
                    Text(Fmt.fcfa(total))
                        .font(RF.T.price(.title3, weight: .bold))
                        .foregroundStyle(RF.C.text)
                        .contentTransition(.numericText(value: Double(total)))
                        .animation(.snappy(duration: 0.2), value: total)
                }
                .padding(.vertical, RF.S.md)
                .accessibilityElement(children: .combine)

                RFButton("Payer avec \(payment.label)", isLoading: isPaying) {
                    Task { await pay(listing) }
                }
                .disabled(delivery == nil)
            }
            .padding(.horizontal, RF.S.gutter)
            .padding(.bottom, RF.S.sm)
            .background(RF.C.paper)
            .overlay(alignment: .top) { Rectangle().fill(RF.C.line).frame(height: 0.5) }
        }
        .sensoryFeedback(.selection, trigger: delivery)
        .sensoryFeedback(.selection, trigger: payment)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: RF.S.sm) {
            Text(title)
                .font(RF.T.footnote.weight(.semibold))
                .foregroundStyle(RF.C.textDim)
                .padding(.leading, RF.S.lg)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func summaryRow(_ listing: Listing) -> some View {
        HStack(spacing: RF.S.md) {
            ListingPhotoView(photo: listing.photos.first, listingId: listing.id)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(listing.title)
                    .font(RF.T.subheadline.weight(.semibold))
                    .foregroundStyle(RF.C.text)
                    .lineLimit(2)
                Text(subtitle(listing))
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.textDim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.fcfa(itemPrice(listing)))
                    .font(RF.T.price(.subheadline))
                    .foregroundStyle(RF.C.text)
                if negotiatedPrice != nil, negotiatedPrice != listing.price {
                    Text(Fmt.fcfa(listing.price))
                        .font(RF.T.price(.caption, weight: .regular))
                        .strikethrough()
                        .foregroundStyle(RF.C.textDim)
                }
            }
        }
        .padding(RF.S.md)
        .background(RF.C.card, in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ listing: Listing) -> String {
        var s = "\(listing.sizeLabel) · \(seller?.username ?? "…")"
        if negotiatedPrice != nil { s += " · prix négocié" }
        return s
    }
}

// MARK: - Reusable bits

/// Selectable delivery row: icon, label + one short line, fee, checkmark when selected.
struct CheckoutDeliveryOption: View {
    let method: DeliveryMethod
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: RF.S.md) {
                Image(systemName: method.symbol)
                    .foregroundStyle(RF.C.textDim)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(method.shortLabel)
                        .font(RF.T.body)
                        .foregroundStyle(RF.C.text)
                    Text(method.shortSubtitle)
                        .font(RF.T.footnote)
                        .foregroundStyle(RF.C.textDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                Text(method.fee > 0 ? Fmt.fcfa(method.fee) : "Gratuit")
                    .font(RF.T.price(.subheadline, weight: .regular))
                    .foregroundStyle(RF.C.textDim)
                    .fixedSize()
                CheckoutCheckmark(selected: selected)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, RF.S.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(RFPressStyle(scale: 1))
        .accessibilityLabel("\(method.label), \(method.fee > 0 ? Fmt.fcfa(method.fee) : "gratuit")")
        .accessibilityHint(method.subtitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Wave / Orange Money row: brand tile, name, checkmark when selected.
struct CheckoutPaymentRow: View {
    let method: PaymentMethod
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: RF.S.md) {
                PaymentBrandLogo(method: method, size: 28)
                Text(method.label)
                    .font(RF.T.body)
                    .foregroundStyle(RF.C.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                CheckoutCheckmark(selected: selected)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, RF.S.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(RFPressStyle(scale: 1))
        .accessibilityLabel(method.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// iOS-style selection checkmark (hibiscus), keeps its width when hidden so rows don't shift.
private struct CheckoutCheckmark: View {
    let selected: Bool

    var body: some View {
        Image(systemName: "checkmark")
            .font(RF.T.body.weight(.semibold))
            .foregroundStyle(RF.C.hibiscus)
            .opacity(selected ? 1 : 0)
            .frame(width: 22)
            .accessibilityHidden(true)
    }
}

/// Brand tile: « WAVE » / « OM » on the brand colour.
struct PaymentBrandLogo: View {
    let method: PaymentMethod
    var size: CGFloat = 30

    var body: some View {
        Text(method.badge)
            .font(.system(size: size * 0.32, weight: .heavy))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: size, height: size)
            .background(Color(hex: method.brandHex), in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// One-line escrow note with a padlock (green = money held safely).
struct EscrowLockNote: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "lock.fill")
            .font(RF.T.footnote)
            .foregroundStyle(RF.C.moneyDeep)
            .padding(.leading, RF.S.lg)
            .accessibilityElement(children: .combine)
    }
}

#Preview("Paiement") {
    NavigationStack { CheckoutView(listingId: DemoIDs.listing(2)) }.previewEnvironment()
}

#Preview("Propre annonce") {
    NavigationStack { CheckoutView(listingId: DemoIDs.listing(1)) }.previewEnvironment()
}
