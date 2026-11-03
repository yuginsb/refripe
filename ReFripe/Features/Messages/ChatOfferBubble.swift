import SwiftUI

/// One negotiation round shown as a bubble inside the conversation (DESIGN-v3 « offres en bulles »).
/// Mine on the right (hibiscus tint), the other party's on the left (white card). Only the LAST round
/// carries the actions: buyer → Accepter / Proposer a counter-offer; seller → Accepter / Contre-proposer /
/// Refuser; accepted → « Accepté · réservé pour toi jusqu'à HH:mm » + Payer.
struct ChatOfferBubble: View {
    let thread: OfferThread
    let index: Int
    /// My side in this negotiation.
    let me: OfferParty
    let otherName: String
    let listing: Listing?
    let busy: Bool
    /// Buyer side: the item can be paid now (not reserved for someone else, not sold).
    let canPay: Bool
    var onAccept: () -> Void = {}
    var onPropose: () -> Void = {}
    var onRefuse: () -> Void = {}
    var onPay: () -> Void = {}

    private var round: OfferRound { thread.rounds[index] }
    private var isMine: Bool { round.by == me }
    private var isLast: Bool { index == thread.rounds.count - 1 }

    /// « n sur 3 » for buyer offers (counted up to this round).
    private var buyerOfferNumber: Int {
        thread.rounds.prefix(index + 1).filter { $0.by == .buyer && $0.action == .offer }.count
    }

    private var title: String {
        switch round.action {
        case .offer:
            let n = "\(buyerOfferNumber) sur \(OfferRules.maxBuyerOffers)"
            return isMine ? "Ton offre · \(n)" : "Offre · \(n)"
        case .counter:
            return "Contre-offre"
        case .accept:
            return "Accepté"
        case .refuse:
            return "Refusé"
        }
    }

    private var symbol: String {
        switch round.action {
        case .offer: "tag"
        case .counter: "arrow.left.arrow.right"
        case .accept: "checkmark.circle.fill"
        case .refuse: "xmark.circle"
        }
    }

    private var tint: Color {
        switch round.action {
        case .accept: RF.C.moneyDeep
        case .refuse: RF.C.textDim
        default: isMine ? RF.C.hibiscusText : RF.C.text
        }
    }

    private var background: Color {
        switch round.action {
        case .accept: RF.C.money.opacity(0.10)
        default: isMine ? RF.C.hibiscus.opacity(0.08) : RF.C.card
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(RF.T.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(Fmt.fcfa(round.amount))
                .font(RF.T.price(.title3, weight: .bold))
                .strikethrough(round.action == .refuse)
                .foregroundStyle(round.action == .refuse ? RF.C.textDim : RF.C.text)
            if isLast { footer }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(RF.C.line, lineWidth: 1)
        }
        .containerRelativeFrame(.horizontal, alignment: isMine ? .trailing : .leading) { length, _ in
            length * 0.78
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        .accessibilityElement(children: .contain)
    }

    // MARK: Footer (last round only)

    @ViewBuilder private var footer: some View {
        switch thread.status {
        case .pending:
            if isMine {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("En attente")
                }
                .font(RF.T.footnote)
                .foregroundStyle(RF.C.textDim)
            } else if me == .buyer && round.action == .counter {
                let canPropose = thread.buyerOfferCount < OfferRules.maxBuyerOffers
                HStack(spacing: 8) {
                    ChatBubbleButton(title: "Accepter", style: .filled, isLoading: busy, action: onAccept)
                        .accessibilityLabel("Accepter \(Fmt.fcfa(round.amount))")
                    if canPropose {
                        ChatBubbleButton(title: "Proposer", style: .tinted, action: onPropose)
                            .disabled(busy)
                    }
                }
                if !canPropose {
                    Text("3 offres utilisées")
                        .font(RF.T.footnote)
                        .foregroundStyle(RF.C.textDim)
                }
            } else if me == .seller && round.by == .buyer {
                VStack(alignment: .leading, spacing: 8) {
                    ChatBubbleButton(title: "Accepter", style: .filled, isLoading: busy, action: onAccept)
                        .accessibilityLabel("Accepter \(Fmt.fcfa(round.amount))")
                    HStack(spacing: 8) {
                        if thread.buyerOfferCount < OfferRules.maxBuyerOffers {
                            ChatBubbleButton(title: "Contre-offre", style: .tinted, action: onPropose)
                        }
                        ChatBubbleButton(title: "Refuser", style: .plain, action: onRefuse)
                    }
                    .disabled(busy)
                    if let floor = listing?.minOffer, round.amount < floor {
                        Label("Sous ton minimum", systemImage: "exclamationmark.triangle")
                            .font(RF.T.footnote)
                            .foregroundStyle(RF.C.hibiscusText)
                    }
                }
            }
        case .accepted:
            let until = reservationEnd
            VStack(alignment: .leading, spacing: 8) {
                if until > .now {
                    Text(me == .buyer
                         ? "Réservé pour toi · \(Fmt.hourMinute(until))"
                         : "Réservé · \(Fmt.hourMinute(until))")
                        .font(RF.T.footnote.monospacedDigit())
                        .foregroundStyle(RF.C.moneyDeep)
                } else {
                    Text("Réservation finie")
                        .font(RF.T.footnote)
                        .foregroundStyle(RF.C.textDim)
                }
                if me == .buyer && canPay {
                    ChatBubbleButton(title: "Payer", style: .filled, action: onPay)
                        .accessibilityLabel("Payer \(Fmt.fcfa(thread.acceptedAmount ?? round.amount))")
                }
            }
        case .refused, .expired:
            Text("Négociation close")
                .font(RF.T.footnote)
                .foregroundStyle(RF.C.textDim)
        }
    }

    /// End of the 2 h reservation: the listing's when it is held for this buyer, else computed.
    private var reservationEnd: Date {
        if let listing, listing.reservedFor == thread.buyerId, let until = listing.reservedUntil { return until }
        let acceptedAt = thread.rounds.last(where: { $0.action == .accept })?.at ?? thread.updatedAt
        return acceptedAt.addingTimeInterval(Catalog.reservationDuration)
    }
}

/// Compact capsule button used inside bubbles (44 pt tall).
struct ChatBubbleButton: View {
    enum Style { case filled, tinted, plain }
    let title: String
    var style: Style = .filled
    var isLoading = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading { ProgressView().controlSize(.small).tint(style == .filled ? .white : RF.C.text) }
                Text(title)
                    .font(RF.T.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(backgroundView)
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(RFPressStyle(scale: 0.96))
        .disabled(isLoading)
    }

    private var foreground: Color {
        switch style {
        case .filled: .white
        case .tinted: RF.C.hibiscusText
        case .plain: RF.C.text
        }
    }

    @ViewBuilder private var backgroundView: some View {
        switch style {
        case .filled: Capsule().fill(RF.C.hibiscus)
        case .tinted: Capsule().fill(RF.C.hibiscus.opacity(0.10))
        case .plain: Capsule().strokeBorder(RF.C.line, lineWidth: 1)
        }
    }
}
