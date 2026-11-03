import SwiftUI

// Pieces of the Accueil feed: the grid card (size + district), the quick chips logic,
// option lists for the filter sheet, and small Listing helpers shared with Favoris / Fiche.

// MARK: - Grid card

/// Accueil grid card: 4:5 photo, heart, at most one badge (Réservé, else Prix en baisse),
/// then price, « M · Cocody », one-line title. Tapping pushes `.product(id)` on the current tab.
struct DiscoverListingCard: View {
    let listing: Listing

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: RF.S.sm) {
            ListingPhotoView(photo: listing.photos.first, listingId: listing.id)
                .aspectRatio(0.8, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
                .overlay(alignment: .bottomLeading) { badge.padding(RF.S.sm) }
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.fcfa(listing.price))
                    .font(RF.T.price(.subheadline))
                    .foregroundStyle(RF.C.text)
                    .lineLimit(1)
                Text(listing.sizeDistrictLabel)
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.textDim)
                    .lineLimit(1)
                Text(listing.title)
                    .font(RF.T.subheadline)
                    .foregroundStyle(RF.C.text)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
        .overlay(alignment: .topTrailing) {
            HeartButton(listingId: listing.id, size: 32).padding(6)
        }
    }

    @ViewBuilder private var badge: some View {
        if listing.isReservedForSomeoneElse(me: store.me?.id) {
            DiscoverStatusBadge(text: "Réservé")
        } else if listing.priceDrop != nil {
            PriceDropBadge()
        }
    }

    private var accessibilityText: String {
        var parts = [listing.title, Fmt.fcfa(listing.price), listing.sizeLabel, listing.district]
        if let drop = listing.priceDrop { parts.append("prix baissé de \(Fmt.fcfa(drop))") }
        if listing.isReservedForSomeoneElse(me: store.me?.id) { parts.append("réservé") }
        return parts.joined(separator: ", ")
    }

    private func open() { router.push(.product(listing.id)) }
}

/// Small dark capsule (« Réservé », « Vendu »).
struct DiscoverStatusBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(RF.T.caption.weight(.semibold))
            .foregroundStyle(RF.C.textOnInk)
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(Capsule().fill(RF.C.ink1))
    }
}

// MARK: - Quick chips (Ma taille · Moins de 5 000 · Près de moi)

/// Maps the quick chips of Accueil onto `ListingFilters` (sizes / priceMax / districts), so the
/// « Filtres » sheet and the chips always agree.
struct DiscoverQuickFilters {
    static let budget: FCFA = 5_000

    let mySizes: Set<String>
    let mySizeLabel: String?
    let myDistrict: String?

    init(preferences: UserPreferences, me: UserProfile?) {
        let values = preferences.sizes.values
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        mySizes = Set(values)
        if let top = preferences.sizes[.haut], !top.isEmpty {
            mySizeLabel = top
        } else {
            mySizeLabel = values.sorted().first
        }
        let district = me?.district.trimmingCharacters(in: .whitespaces) ?? ""
        myDistrict = district.isEmpty ? nil : district
    }

    func sizeOn(_ f: ListingFilters) -> Bool { !mySizes.isEmpty && f.sizes == mySizes }
    func budgetOn(_ f: ListingFilters) -> Bool { f.priceMin == 0 && f.priceMax == Self.budget }
    func nearOn(_ f: ListingFilters) -> Bool {
        guard let myDistrict else { return false }
        return f.districts == [myDistrict]
    }

    func toggleSize(_ f: inout ListingFilters) {
        f.sizes = sizeOn(f) ? [] : mySizes
    }
    func toggleBudget(_ f: inout ListingFilters) {
        let on = budgetOn(f)
        f.priceMin = 0
        f.priceMax = on ? ListingFilters.catalogMaxPrice : Self.budget
    }
    func toggleNear(_ f: inout ListingFilters) {
        guard let myDistrict else { return }
        f.districts = nearOn(f) ? [] : [myDistrict]
    }

    /// « Dans ta taille, près de toi », « Moins de 5 000 FCFA », « Tous les articles »…
    func title(for f: ListingFilters) -> String {
        if !f.query.trimmingCharacters(in: .whitespaces).isEmpty { return "Résultats" }
        var parts: [String] = []
        if sizeOn(f) { parts.append("dans ta taille") }
        if nearOn(f) { parts.append("près de toi") }
        if budgetOn(f) { parts.append("moins de \(Fmt.fcfa(Self.budget))") }
        guard let first = parts.first else { return "Tous les articles" }
        parts[0] = first.prefix(1).uppercased() + first.dropFirst()
        return parts.joined(separator: ", ")
    }
}

// MARK: - Option lists for the filter sheet

enum DiscoverFilterOptions {
    static let letterSizes = ["XS", "S", "M", "L", "XL"]
    static let shoeSizes = ["37", "38", "39", "40", "41", "42", "43"]
    /// « Moins de 2 000 / 5 000 / 10 000 »; « Tous les prix » = `ListingFilters.catalogMaxPrice` (no limit).
    static let budgets: [FCFA] = [2_000, 5_000, 10_000]

    /// Districts (communes) offered in the sheet for the user's city.
    static func districts(city: String) -> [String] {
        switch city.lowercased() {
        case "dakar":
            ["Plateau", "Médina", "Mermoz", "Ouakam", "Almadies", "Point E", "Sacré-Cœur", "Yoff", "Grand Yoff", "Parcelles Assainies"]
        default:
            ["Cocody", "Plateau", "Marcory", "Yopougon", "Treichville", "Koumassi", "Adjamé", "Abobo", "Port-Bouët", "Bingerville"]
        }
    }
}

extension ItemType {
    /// Chip label in Accueil › Filtres.
    var filterLabel: String {
        switch self {
        case .robe: "Robe"
        case .pagne: "Pagne"
        case .ensemble: "Ensemble"
        case .haut: "Haut"
        case .chemise: "Chemise"
        case .pantalon: "Pantalon"
        case .jean: "Jean"
        case .jupe: "Jupe"
        case .chaussures: "Chaussures"
        case .sac: "Sac"
        case .accessoire: "Accessoire"
        case .autre: "Autre"
        }
    }
}

extension ListingFilters {
    /// Resets everything the « Filtres » sheet and the quick chips control; category and search are kept.
    mutating func resetAdvancedFilters() {
        priceMin = 0
        priceMax = Self.catalogMaxPrice
        conditions = []
        brands = []
        negotiableOnly = false
        sort = .recent
        itemTypes = []
        sizes = []
        districts = []
    }
}

// MARK: - Listing helpers

extension Listing {
    /// « M », « 42 », « 4 ans », « Taille unique » (the « Taille » / « Pointure » prefix dropped).
    var shortSizeLabel: String {
        guard sizeType != .unique else { return sizeLabel }
        for prefix in ["Taille ", "Pointure "] where sizeLabel.hasPrefix(prefix) {
            return String(sizeLabel.dropFirst(prefix.count))
        }
        return sizeLabel
    }

    /// « M · Cocody »
    var sizeDistrictLabel: String { "\(shortSizeLabel) · \(district)" }

    /// Reserved (2 h after an accepted offer) for another buyer.
    func isReservedForSomeoneElse(me: UUID?, now: Date = .now) -> Bool {
        guard let until = reservedUntil, until > now else { return false }
        guard let holder = reservedFor else { return true }
        return holder != me
    }
}

#Preview {
    let repo = DemoSeed.make()
    return ScrollView {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
            ForEach(repo.listings) { DiscoverListingCard(listing: $0) }
        }
        .padding(16)
    }
    .rfScreenBackground()
    .previewEnvironment()
}
