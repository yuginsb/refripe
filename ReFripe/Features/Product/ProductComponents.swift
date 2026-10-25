import SwiftUI

// MARK: - Share (native iOS share sheet)

/// Native share sheet (covers WhatsApp status/chat, Facebook, Messages, AirDrop, copy…) with a rich
/// preview: "<title> · <price>" + the first photo when it is a bundled asset.
struct ProductShareButton: View {
    let listing: Listing

    static func url(for listing: Listing) -> URL {
        AppLinks.listing(listing.id)
    }

    private var title: String { "\(listing.title) · \(Fmt.fcfa(listing.price))" }
    private var message: Text {
        Text("\(listing.title) à \(Fmt.fcfa(listing.price)) sur ReFripe")
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

// MARK: - Attributes (taille, état, marque, couleur)

/// Compact grouped list of the listing's attributes, styled like an inset-grouped `List`.
struct ProductAttributes: View {
    let listing: Listing

    private var rows: [(label: String, value: String)] {
        var r: [(label: String, value: String)] = [(label: "Taille", value: listing.sizeLabel),
                                                   (label: "État", value: listing.condition.label)]
        let brand = listing.brand.trimmingCharacters(in: .whitespaces)
        if !brand.isEmpty, brand != "Sans marque précise" { r.append((label: "Marque", value: brand)) }
        let color = listing.color.trimmingCharacters(in: .whitespaces)
        if !color.isEmpty { r.append((label: "Couleur", value: color)) }
        return r
    }

    var body: some View {
        ProductGroupedRows(count: rows.count) { i in
            LabeledContent(rows[i].label, value: rows[i].value)
                .font(RF.T.body)
                .foregroundStyle(RF.C.text)
                .padding(.vertical, 11)
                .padding(.horizontal, RF.S.lg)
        }
    }
}

// MARK: - Delivery options (plain rows)

struct ProductDeliveryList: View {
    let methods: [DeliveryMethod]

    var body: some View {
        ProductGroupedRows(count: methods.count) { i in
            let m = methods[i]
            HStack(spacing: RF.S.md) {
                Image(systemName: m.symbol)
                    .foregroundStyle(RF.C.textDim)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(m.shortLabel)
                    .font(RF.T.body)
                    .foregroundStyle(RF.C.text)
                Spacer(minLength: RF.S.sm)
                Text(m.fee == 0 ? "Gratuit" : Fmt.fcfa(m.fee))
                    .font(RF.T.price(.subheadline, weight: .regular))
                    .foregroundStyle(RF.C.textDim)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, RF.S.lg)
            .accessibilityElement(children: .combine)
        }
    }
}

/// White rounded container with hairline separators between rows (inset-grouped look).
struct ProductGroupedRows<Row: View>: View {
    let count: Int
    @ViewBuilder let row: (Int) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                row(i)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if i < count - 1 {
                    Rectangle().fill(RF.C.line).frame(height: 0.5).padding(.leading, RF.S.lg)
                }
            }
        }
        .background(RF.C.card, in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
    }
}

extension DeliveryMethod {
    /// Short row label (the long Catalog label includes the carrier).
    var shortLabel: String {
        switch self {
        case .relais: "Point relais"
        case .mainPropre: "Main propre"
        case .yango: "Livraison Yango"
        }
    }
    /// One short line under the label (checkout).
    var shortSubtitle: String {
        switch self {
        case .relais: "Retrait sous 24-48 h"
        case .mainPropre: "Rendez-vous avec la vendeuse"
        case .yango: "Chez toi en 30 à 60 min"
        }
    }
}

#Preview {
    let listing = DemoSeed.make().listings[2]
    return ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            ProductAttributes(listing: listing)
            ProductDeliveryList(methods: DeliveryMethod.allCases)
            ProductShareButton(listing: listing)
        }
        .padding()
    }
    .rfScreenBackground()
    .previewEnvironment()
}
