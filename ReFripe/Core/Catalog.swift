import Foundation

// MARK: - Labels, option lists and business rules taken from the mockup (CONTRACT)

extension Gender {
    var label: String {
        switch self { case .femme: "Femme"; case .homme: "Homme"; case .enfant: "Enfants"; case .bebe: "Bébés" }
    }
    var symbol: String {
        switch self { case .femme: "figure.dress.line.vertical.figure"; case .homme: "tshirt"; case .enfant: "figure.child"; case .bebe: "stroller" }
    }
}

extension ItemCondition {
    var label: String {
        switch self {
        case .newWithTags: "Neuf avec étiquette"
        case .excellent: "Excellent état"
        case .veryGood: "Très bon état"
        case .good: "Bon état"
        case .fair: "Satisfaisant"
        }
    }
}

extension SizeType {
    var label: String {
        switch self { case .haut: "Haut"; case .pantalon: "Pantalon"; case .chaussures: "Chaussures"; case .enfant: "Enfant"; case .unique: "Taille unique" }
    }
    var options: [String] {
        switch self {
        case .haut: ["XS", "S", "M", "L", "XL"]
        case .pantalon: ["36", "38", "40", "42", "44"]
        case .chaussures: ["38", "39", "40", "41", "42", "43"]
        case .enfant: ["0-3 mois", "3-6 mois", "6-12 mois", "2 ans", "4 ans", "6 ans", "8 ans", "10 ans", "12 ans"]
        case .unique: ["Taille unique"]
        }
    }
    func displayLabel(for value: String) -> String {
        switch self {
        case .haut, .pantalon: "Taille \(value)"
        case .chaussures: "Pointure \(value)"
        case .enfant, .unique: value
        }
    }
}

extension DeliveryMethod {
    var label: String {
        switch self { case .relais: "Point relais"; case .mainPropre: "Remise en main propre"; case .yango: "Livraison à domicile (Yango)" }
    }
    var subtitle: String {
        switch self {
        case .relais: "Retrait en boutique partenaire, sous 24-48h"
        case .mainPropre: "Rendez-vous direct avec la vendeuse, gratuit"
        case .yango: "Coursier à la demande, remis chez vous en 30 à 60 min"
        }
    }
    var fee: FCFA {
        switch self { case .relais: 1_000; case .mainPropre: 0; case .yango: 2_500 }
    }
    var symbol: String {
        switch self { case .relais: "shippingbox"; case .mainPropre: "hand.raised"; case .yango: "scooter" }
    }
}

extension PaymentMethod {
    var label: String { self == .wave ? "Wave" : "Orange Money" }
    var badge: String { self == .wave ? "WAVE" : "OM" }
    var brandHex: UInt32 { self == .wave ? 0x1DC8E0 : 0xFF6600 }
}

extension OrderStatus {
    var label: String {
        switch self {
        case .paymentPending: "Paiement en attente"
        case .paid: "Paiement confirmé"
        case .awaitingShipment: "Préparation du colis"
        case .shipped: "Colis expédié"
        case .delivered: "Arrivé au point de retrait"
        case .buyerValidation: "En attente de confirmation"
        case .completed: "Commande terminée"
        case .cancelled: "Annulée"
        case .disputed: "Litige en cours"
        case .returnPending: "Retour en cours"
        case .refunded: "Remboursée"
        }
    }
    /// For alternative outcomes: (SF Symbol, title, explanation).
    var alternativeInfo: (symbol: String, title: String, detail: String)? {
        switch self {
        case .cancelled: ("nosign", "Commande annulée", "La commande a été annulée avant expédition. Le paiement, s'il avait été prélevé, est intégralement remboursé à l'acheteuse.")
        case .disputed: ("exclamationmark.triangle", "Litige en cours", "Un litige a été signalé. Les fonds restent bloqués en séquestre pendant que notre équipe médiation examine le dossier (réponse sous 48h).")
        case .returnPending: ("arrow.uturn.backward", "Retour en cours", "L'acheteuse a demandé un retour. Les fonds restent en séquestre jusqu'à réception et vérification de l'article par la vendeuse.")
        case .refunded: ("banknote", "Commande remboursée", "Les fonds ont été recrédités à l'acheteuse sur son compte Wave / Orange Money.")
        default: nil
        }
    }
    enum Tone { case progress, done, cancelled, alert }
    var tone: Tone {
        switch self {
        case .completed: .done
        case .cancelled, .refunded: .cancelled
        case .disputed, .returnPending: .alert
        default: .progress
        }
    }
    /// Lower = more urgent (dashboard ordering).
    var urgencyRank: Int {
        switch self {
        case .disputed, .returnPending: 0
        case .awaitingShipment: 1
        case .shipped: 2
        case .delivered, .buyerValidation: 3
        default: 4
        }
    }
}

extension PhotoFlag {
    var label: String {
        switch self {
        case .blur: "Photo floue"
        case .nudity: "Contenu suggestif détecté"
        case .inappropriate: "Contenu inapproprié détecté"
        case .duplicate: "Photo dupliquée"
        case .screenshot: "Screenshot détecté"
        case .watermark: "Watermark professionnel détecté"
        }
    }
}

enum Catalog {
    static let brands = ["Nike", "Adidas", "Zara", "H&M", "Vintage", "Wax local", "Bazin", "Sans marque précise"]
    static let colors = ["Noir", "Blanc", "Rouge", "Bleu", "Vert", "Jaune", "Orange", "Marron", "Rose", "Multicolore"]
    static let cities = ["Abidjan", "Dakar"]
    static let sellPhotoMin = 1
    static let sellPhotoMax = 8
    /// Escrow auto-release delay after delivery.
    static let escrowAutoReleaseHours = 72
}

// MARK: - Negotiation rules (shared by buyer UI, demo seller bot and the Supabase RPC)

enum OfferRules {
    static let maxBuyerOffers = 3
    static func step(for price: FCFA) -> FCFA { price >= 6_000 ? 500 : 250 }
    static func round(_ value: Double, step: FCFA) -> FCFA { Int((value / Double(step)).rounded()) * step }

    /// Initial amount shown in the offer composer.
    static func initialDraft(listing: Listing, thread: OfferThread?) -> FCFA {
        let step = step(for: listing.price)
        var draft: FCFA
        if let t = thread, let s = t.lastSellerCounter, let b = t.lastBuyerOffer {
            draft = round(Double(b.amount + s.amount) / 2, step: step)
        } else {
            draft = round(Double(listing.price) * 0.75, step: step)
        }
        return max(listing.minOffer ?? 0, min(draft, listing.price - step))
    }

    /// Simulated seller answer (demo mode only; real sellers answer themselves).
    static func simulatedSellerResponse(listing: Listing, thread: OfferThread) -> (OfferAction, FCFA) {
        let step = step(for: listing.price)
        let buyer = thread.lastBuyerOffer?.amount ?? 0
        let highEnough = buyer >= round(Double(listing.price) * 0.9, step: step)
        if highEnough || thread.buyerOfferCount >= maxBuyerOffers {
            return (highEnough || buyer >= (listing.minOffer ?? 0)) ? (.accept, buyer) : (.refuse, buyer)
        }
        var counter = round(Double(buyer + listing.price) / 2, step: step)
        if counter <= buyer { counter = buyer + step }
        if counter >= listing.price { counter = listing.price - step }
        return (.counter, counter)
    }
}

// MARK: - Formatting

enum Fmt {
    private static let grouping: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{202F}"
        f.locale = Locale(identifier: "fr_FR")
        return f
    }()
    /// 4500 → "4 500 FCFA"
    static func fcfa(_ v: FCFA) -> String { "\(grouping.string(from: NSNumber(value: v)) ?? "\(v)") FCFA" }
    static func number(_ v: Int) -> String { grouping.string(from: NSNumber(value: v)) ?? "\(v)" }

    /// "Il y a 30 min", "Hier", "12 juil."
    static func relative(_ date: Date, now: Date = .now) -> String {
        let s = now.timeIntervalSince(date)
        if s < 60 { return "À l'instant" }
        if s < 3600 { return "Il y a \(Int(s / 60)) min" }
        if Calendar.current.isDateInToday(date) { return "Il y a \(Int(s / 3600))h" }
        if Calendar.current.isDateInYesterday(date) { return "Hier" }
        if s < 7 * 86_400 { return "Il y a \(Int(s / 86_400)) jours" }
        return date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR")))
    }

    /// "8 mois", "1 an"
    static func seniority(since date: Date, now: Date = .now) -> String {
        let m = Calendar.current.dateComponents([.month], from: date, to: now).month ?? 0
        if m >= 12 { let y = m / 12; return y == 1 ? "1 an" : "\(y) ans" }
        return m <= 0 ? "Nouveau" : "\(m) mois"
    }
}
