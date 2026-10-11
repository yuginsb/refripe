import SwiftUI

// MARK: - Share (mockup `shareSheetHTML` → native iOS share sheet)

/// Native share sheet (covers WhatsApp status/chat, Facebook, Messages, AirDrop, copy…) with a rich
/// preview: "<title> · <price>" + the first photo when it is a bundled asset.
struct ProductShareButton: View {
    let listing: Listing

    static func url(for listing: Listing) -> URL {
        AppLinks.listing(listing.id)
    }

    private var title: String { "\(listing.title) · \(Fmt.fcfa(listing.price))" }
    private var message: Text {
        Text("Regarde cette pièce sur ReFripe : \(listing.title) à \(Fmt.fcfa(listing.price)), \(listing.district).")
    }

    var body: some View {
        Group {
            if let asset = listing.photos.first?.assetName {
                ShareLink(item: Self.url(for: listing), subject: Text(listing.title), message: message,
                          preview: SharePreview(title, image: Image(asset))) {
                    shareIcon
                }
            } else {
                ShareLink(item: Self.url(for: listing), subject: Text(listing.title), message: message,
                          preview: SharePreview(title)) {
                    shareIcon
                }
            }
        }
        .accessibilityLabel("Partager l'annonce")
    }

    private var shareIcon: some View {
        Image(systemName: "square.and.arrow.up")
    }
}

// MARK: - Tags (mockup `.pd-tags` / `.tag`)

struct ProductTag: View {
    enum Style { case plain, negotiable, fixed, alert }

    let text: String
    var symbol: String?
    var style: Style = .plain

    private var colors: (bg: Color, fg: Color) {
        switch style {
        case .plain: (RF.C.paperDim, RF.C.text)
        case .negotiable: (RF.C.money.opacity(0.14), RF.C.moneyDeep)
        case .fixed: (RF.C.text.opacity(0.08), RF.C.textDim)
        case .alert: (RF.C.hibiscus.opacity(0.12), RF.C.hibiscus)
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
            }
            Text(text).font(RF.F.body(11, .semibold)).lineLimit(1)
        }
        .foregroundStyle(colors.fg)
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(colors.bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ProductTags: View {
    let listing: Listing
    /// When a price has been negotiated the "offres" badge is hidden (mockup).
    let negotiated: Bool

    private var freeTags: [String] {
        var seen = Set<String>()
        let candidates = [listing.brand, listing.color] + listing.tags
        return candidates.compactMap { raw in
            let t = raw.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, t != "Sans marque précise", seen.insert(t.lowercased()).inserted else { return nil }
            return t
        }
    }

    var body: some View {
        DiscoverWrapLayout(spacing: 8, lineSpacing: 8) {
            ProductTag(text: listing.sizeLabel, symbol: "ruler")
            if !negotiated {
                if listing.negotiable {
                    ProductTag(text: "Ouvert aux offres", symbol: "arrow.left.arrow.right", style: .negotiable)
                } else {
                    ProductTag(text: "Prix fixe", symbol: "lock.fill", style: .fixed)
                }
            }
            if listing.isLastPiece {
                ProductTag(text: "Dernière pièce", symbol: "flame.fill", style: .alert)
            }
            ForEach(freeTags, id: \.self) { tag in
                ProductTag(text: tag)
            }
        }
    }
}

// MARK: - Delivery options

struct ProductDeliveryList: View {
    let methods: [DeliveryMethod]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Livraison")
            VStack(spacing: 0) {
                ForEach(Array(methods.enumerated()), id: \.element) { pair in
                    row(pair.element)
                    if pair.offset < methods.count - 1 {
                        Rectangle().fill(RF.C.line).frame(height: 1).padding(.leading, 50)
                    }
                }
            }
            .rfCard()
        }
    }

    private func row(_ m: DeliveryMethod) -> some View {
        HStack(spacing: 12) {
            Image(systemName: m.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RF.C.text)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.label)
                    .font(RF.F.body(12.5, .bold))
                    .foregroundStyle(RF.C.text)
                Text(m.subtitle)
                    .font(RF.F.body(10.5))
                    .foregroundStyle(RF.C.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(m.fee == 0 ? "Gratuit" : Fmt.fcfa(m.fee))
                .font(RF.F.mono(12, .semibold))
                .foregroundStyle(m.fee == 0 ? RF.C.moneyDeep : RF.C.text)
        }
        .padding(12)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let listing = DemoSeed.make().listings[2]
    return ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            ProductTags(listing: listing, negotiated: false)
            ProductDeliveryList(methods: DeliveryMethod.allCases)
            ProductShareButton(listing: listing)
        }
        .padding()
    }
    .rfScreenBackground()
    .previewEnvironment()
}
