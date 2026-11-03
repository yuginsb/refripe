import SwiftUI

/// Paiement (v3): article (« Prix négocié » when an offer was accepted), Remise (radios, cheapest
/// preselected), Payer avec (Wave / Orange Money + masked number when known), recap Article / Remise /
/// Total, one green line, pinned « Payer avec … ». On pay: `createOrder` → the same screen switches to
/// `PaymentPendingView` (startPayment, open Wave, poll, receipt). Tab bar hidden.
@MainActor
struct CheckoutView: View {
    let listingId: UUID

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var listing: Listing?
    @State private var seller: UserProfile?
    @State private var negotiated: FCFA?
    @State private var loadError: Error?
    @State private var delivery: DeliveryMethod?
    @State private var payment: PaymentMethod = .wave
    @State private var isPaying = false
    @State private var pendingOrder: Order?

    var body: some View {
        Group {
            if let pendingOrder {
                PaymentPendingView(order: pendingOrder) { orderId in
                    router.pop()
                    router.push(.order(orderId))
                }
            } else if let listing {
                if let blocker = PurchaseAvailability.blocker(for: listing, me: store.me?.id) {
                    blocked(blocker)
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
        .toolbar(.hidden, for: .tabBar)
        .task { await load() }
    }

    // MARK: Data

    private func itemPrice(_ listing: Listing) -> FCFA { min(negotiated ?? listing.price, listing.price) }

    private func methods(_ listing: Listing) -> [DeliveryMethod] {
        let list = listing.deliveryMethods.isEmpty ? [DeliveryMethod.mainPropre] : listing.deliveryMethods
        return list.sorted { $0.fee < $1.fee }
    }

    private func load() async {
        guard pendingOrder == nil else { return }
        loadError = nil
        do {
            let l = try await store.repo.listing(id: listingId)
            // Accepted offer → negotiated price (also when Checkout is opened from the listing page).
            let thread = try? await store.repo.offerThread(listingId: listingId)
            negotiated = (thread ?? nil)?.acceptedAmount ?? store.negotiatedPrices[listingId]
            let available = methods(l)
            if let current = delivery, available.contains(current) {} else { delivery = available.first }
            listing = l
            seller = await store.profile(l.sellerId)
        } catch {
            if listing == nil { loadError = error } else { store.show(error) }
        }
    }

    private func pay(_ listing: Listing) async {
        guard let delivery, !isPaying else { return }
        isPaying = true
        defer { isPaying = false }
        do {
            let order = try await store.repo.createOrder(listingId: listing.id, delivery: delivery, payment: payment)
            store.negotiatedPrices[listing.id] = nil
            Haptics.success()
            withAnimation(.snappy) { pendingOrder = order }
            await store.refreshBadges()
        } catch {
            Haptics.error()
            store.show(error)
            await load()   // the listing may have been reserved meanwhile
        }
    }

    // MARK: Views

    private func blocked(_ blocker: PurchaseAvailability.Blocker) -> some View {
        ContentUnavailableView {
            Label(blocker.title, systemImage: blocker.symbol)
        } description: {
            Text(blocker.message)
        } actions: {
            Button("Retour") { router.pop() }
                .buttonStyle(.bordered)
                .tint(RF.C.hibiscus)
        }
    }

    private func content(_ listing: Listing) -> some View {
        let fee = delivery?.fee ?? 0
        let price = itemPrice(listing)
        let total = price + fee
        let available = methods(listing)
        return ScrollView {
            VStack(alignment: .leading, spacing: RF.S.xl) {
                articleCard(listing)

                section("Remise") {
                    CheckoutGroup(count: available.count) { i in
                        let method = available[i]
                        CheckoutRadioRow(selected: delivery == method,
                                         title: method.txTitle,
                                         detail: nil,
                                         trailing: method.txFeeLabel,
                                         symbol: method.symbol) {
                            delivery = method
                        }
                    }
                }

                section("Payer avec") {
                    CheckoutGroup(count: PaymentMethod.allCases.count) { i in
                        let method = PaymentMethod.allCases[i]
                        CheckoutRadioRow(selected: payment == method,
                                         title: method.label,
                                         detail: PaymentPhoneMemory.get(method),
                                         trailing: nil,
                                         logo: method) {
                            payment = method
                        }
                    }
                }

                VStack(spacing: 10) {
                    recapRow("Article", Fmt.fcfa(price))
                    recapRow("Remise", fee > 0 ? Fmt.fcfa(fee) : "Gratuit")
                    Rectangle().fill(RF.C.line).frame(height: 0.5)
                    HStack(alignment: .firstTextBaseline) {
                        Text("Total").font(RF.T.headline).foregroundStyle(RF.C.text)
                        Spacer()
                        Text(Fmt.fcfa(total))
                            .font(RF.T.price(.headline, weight: .bold))
                            .foregroundStyle(RF.C.text)
                            .contentTransition(.numericText(value: Double(total)))
                            .animation(.snappy(duration: 0.2), value: total)
                    }
                    .accessibilityElement(children: .combine)
                }
                .padding(RF.S.lg)
                .rfCard(radius: RF.R.md)

                EscrowLockNote(text: "Argent bloqué jusqu'à réception")
            }
            .padding(EdgeInsets(top: RF.S.lg, leading: RF.S.gutter, bottom: RF.S.xl, trailing: RF.S.gutter))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RFButton("Payer avec \(payment.label)", isLoading: isPaying) {
                Task { await pay(listing) }
            }
            .accessibilityLabel("Payer avec \(payment.label), \(Fmt.fcfa(total))")
            .disabled(delivery == nil)
            .padding(.horizontal, RF.S.gutter)
            .padding(.vertical, RF.S.sm)
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

    private func recapRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(RF.T.subheadline).foregroundStyle(RF.C.textDim)
            Spacer(minLength: 12)
            Text(value).font(RF.T.price(.subheadline, weight: .regular)).foregroundStyle(RF.C.text)
        }
        .accessibilityElement(children: .combine)
    }

    private func articleCard(_ listing: Listing) -> some View {
        let price = itemPrice(listing)
        let isNegotiated = price < listing.price
        return HStack(spacing: RF.S.md) {
            ListingPhotoView(photo: listing.photos.first, listingId: listing.id)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(listing.title)
                    .font(RF.T.subheadline.weight(.semibold))
                    .foregroundStyle(RF.C.text)
                    .lineLimit(2)
                Text("\(listing.sizeLabel) · \(seller?.username ?? "…")")
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.textDim)
                    .lineLimit(1)
                if isNegotiated {
                    Text("Prix négocié")
                        .font(RF.T.caption.weight(.semibold))
                        .foregroundStyle(RF.C.moneyDeep)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.fcfa(price))
                    .font(RF.T.price(.subheadline))
                    .foregroundStyle(RF.C.text)
                if isNegotiated {
                    Text(Fmt.fcfa(listing.price))
                        .font(RF.T.price(.caption, weight: .regular))
                        .strikethrough()
                        .foregroundStyle(RF.C.textDim)
                }
            }
        }
        .padding(RF.S.md)
        .rfCard(radius: RF.R.md)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Reusable bits

/// White grouped card with hairlines between rows.
struct CheckoutGroup<Row: View>: View {
    let count: Int
    @ViewBuilder let row: (Int) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                row(i)
                if i < count - 1 {
                    Rectangle().fill(RF.C.line).frame(height: 0.5).padding(.leading, 52)
                }
            }
        }
        .background(RF.C.card, in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
    }
}

/// Radio row: radio circle, symbol or brand tile, title (+ one short detail), trailing value.
struct CheckoutRadioRow: View {
    let selected: Bool
    let title: String
    var detail: String?
    var trailing: String?
    var symbol: String?
    var logo: PaymentMethod?
    let action: () -> Void

    init(selected: Bool, title: String, detail: String?, trailing: String?, symbol: String? = nil,
         logo: PaymentMethod? = nil, action: @escaping () -> Void) {
        self.selected = selected
        self.title = title
        self.detail = detail
        self.trailing = trailing
        self.symbol = symbol
        self.logo = logo
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: RF.S.md) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(RF.T.title3)
                    .foregroundStyle(selected ? RF.C.hibiscus : RF.C.textDim)
                    .frame(width: 24)
                if let logo {
                    PaymentBrandLogo(method: logo, size: 28)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(RF.T.body)
                        .foregroundStyle(RF.C.textDim)
                        .frame(width: 28)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(RF.T.body).foregroundStyle(RF.C.text)
                    if let detail {
                        Text(detail).font(RF.T.footnote.monospacedDigit()).foregroundStyle(RF.C.textDim)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let trailing {
                    Text(trailing)
                        .font(RF.T.price(.subheadline, weight: .regular))
                        .foregroundStyle(RF.C.textDim)
                        .fixedSize()
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, RF.S.md)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(RFPressStyle(scale: 1))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Payment brand tile (« WAVE » / « OM »). Neutral tokens only (dark-mode ready).
struct PaymentBrandLogo: View {
    let method: PaymentMethod
    var size: CGFloat = 30

    var body: some View {
        Text(method.badge)
            .font(size >= 48 ? RF.T.headline.weight(.heavy) : RF.T.caption.weight(.heavy))
            .foregroundStyle(RF.C.text)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(4)
            .frame(width: size, height: size)
            .background(RF.C.paperDim, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
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
    NavigationStack { CheckoutView(listingId: DemoIDs.listing(2)).withAppRoutes() }.previewEnvironment()
}

#Preview("Propre annonce") {
    NavigationStack { CheckoutView(listingId: DemoIDs.listing(1)) }.previewEnvironment()
}
