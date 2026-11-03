import Foundation

/// Can the signed-in user buy this listing right now? Shared by the chat « Acheter » button and Checkout.
/// Rules (DESIGN-v3): not my own listing; not sold / removed; an accepted offer reserves the item 2 h for
/// one buyer (`reservedFor` / `reservedUntil`), nobody else can buy meanwhile.
enum PurchaseAvailability {
    struct Blocker: Hashable {
        var symbol: String
        var title: String
        var message: String
    }

    static func blocker(for listing: Listing, me: UUID?, now: Date = .now) -> Blocker? {
        if let me, listing.sellerId == me {
            return Blocker(symbol: "person.crop.circle", title: "Ton annonce",
                           message: "Ton propre article")
        }
        if listing.isReserved(forSomeoneOtherThan: me, at: now), let until = listing.reservedUntil {
            return Blocker(symbol: "clock", title: "Réservé",
                           message: "Réservé · \(Fmt.hourMinute(until))")
        }
        switch listing.status {
        case .active:
            return nil
        case .reserved:
            // Reserved for me (accepted offer) → I can pay.
            if isReservedForMe(listing, me: me, now: now) { return nil }
            return Blocker(symbol: "bag.badge.minus", title: "Réservé",
                           message: "Commande en cours")
        case .sold:
            return Blocker(symbol: "bag.badge.minus", title: "Vendu", message: "Déjà vendu")
        case .removed:
            return Blocker(symbol: "bag.badge.minus", title: "Retiré", message: "Plus en vente")
        }
    }

    static func isReservedForMe(_ listing: Listing, me: UUID?, now: Date = .now) -> Bool {
        guard let me, listing.reservedFor == me, let until = listing.reservedUntil else { return false }
        return until > now
    }
}

// MARK: - Short labels used by Checkout / payment / tracking

extension DeliveryMethod {
    /// 1–2 words: « Point relais », « Main propre », « Yango ».
    var txTitle: String {
        switch self {
        case .relais: "Point relais"
        case .mainPropre: "Main propre"
        case .yango: "Yango"
        }
    }
    var txFeeLabel: String { fee > 0 ? Fmt.fcfa(fee) : "Gratuit" }
}

extension PaymentMethod {
    var other: PaymentMethod { self == .wave ? .orangeMoney : .wave }
}

/// Last masked phone seen per payment method (shown in Checkout « Payer avec »). Per-device convenience.
enum PaymentPhoneMemory {
    private static func key(_ m: PaymentMethod) -> String { "rf.pay.maskedPhone.\(m.rawValue)" }
    static func get(_ m: PaymentMethod) -> String? { UserDefaults.standard.string(forKey: key(m)) }
    static func set(_ phone: String?, for m: PaymentMethod) {
        guard let phone, !phone.isEmpty else { return }
        UserDefaults.standard.set(phone, forKey: key(m))
    }
}
