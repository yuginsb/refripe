import SwiftUI
import UIKit

/// Listing image: bundled asset (demo), local file (freshly published in demo) or remote URL (Supabase),
/// on the mockup's placeholder tile colour, with an icon fallback. Fills the frame given by the caller.
struct ListingPhotoView: View {
    let photo: ListingPhoto?
    let listingId: UUID

    var body: some View {
        RF.C.thumb(for: listingId)
            .overlay { content }
            .clipped()
            .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        if let name = photo?.assetName {
            Image(name).resizable().scaledToFill()
        } else if let url = photo?.url {
            if url.isFileURL {
                if let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    fallback
                }
            } else {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .empty: ProgressView().tint(RF.C.textDim)
                    default: fallback
                    }
                }
            }
        } else {
            fallback
        }
    }

    private var fallback: some View {
        GeometryReader { geo in
            Image(systemName: "photo")
                .font(RFSymbol.font(for: geo.size.width * 0.32))
                .foregroundStyle(RF.C.textDim.opacity(0.35))
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Heart toggle bound to the global wishlist (`store.toggleLike`).
/// The visible circle is `size`; the tap target is always at least 44 × 44 pt.
struct HeartButton: View {
    let listingId: UUID
    var size: CGFloat

    @Environment(AppStore.self) private var store

    init(listingId: UUID, size: CGFloat = 28) {
        self.listingId = listingId
        self.size = size
    }

    var body: some View {
        let liked = store.isLiked(listingId)
        Button {
            store.toggleLike(listingId)
        } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(RFSymbol.font(for: size * 0.5))
                .foregroundStyle(liked ? RF.C.hibiscus : RF.C.text)
                .symbolEffect(.bounce, value: liked)
                .frame(width: size, height: size)
                .background(Circle().fill(RF.C.card.opacity(0.92)))
                .frame(width: max(44, size), height: max(44, size))
                .contentShape(Rectangle())
        }
        .buttonStyle(RFPressStyle(scale: 0.9))
        .sensoryFeedback(.impact(weight: .light), trigger: liked)
        .accessibilityLabel(liked ? "Retirer des favoris" : "Ajouter aux favoris")
        .accessibilityAddTraits(liked ? .isSelected : [])
    }
}

/// Small "Prix en baisse" badge (the only badge a card shows).
struct PriceDropBadge: View {
    var body: some View {
        Text("Prix en baisse")
            .font(RF.T.caption.weight(.semibold))
            .foregroundStyle(RF.C.moneyDeep)
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(Capsule().fill(RF.C.card.opacity(0.95)))
    }
}

/// Grid card: 4:5 photo with heart and at most one badge, then price, « taille · quartier », one-line title.
/// No shadow, no frame. Tapping pushes `.product(id)` on the current tab unless `onTap` is provided.
struct ListingCard: View {
    let listing: Listing
    var onTap: (() -> Void)?

    @Environment(Router.self) private var router

    init(listing: Listing, onTap: (() -> Void)? = nil) {
        self.listing = listing
        self.onTap = onTap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ListingPhotoView(photo: listing.photos.first, listingId: listing.id)
                .aspectRatio(0.8, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if listing.priceDrop != nil { PriceDropBadge().padding(8) }
                }
            info
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: openListing)
        .overlay(alignment: .topTrailing) {
            // 28-pt circle centred in a 44-pt tap target → the circle sits 8 pt from the corner.
            HeartButton(listingId: listing.id)
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Fmt.fcfa(listing.price))
                .font(RF.T.price(.subheadline))
                .foregroundStyle(RF.C.text)
            Text(listing.cardSizeDistrict)
                .font(RF.T.footnote)
                .foregroundStyle(RF.C.textDim)
                .lineLimit(1)
            Text(listing.title)
                .font(RF.T.subheadline)
                .foregroundStyle(RF.C.text)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openListing() }
    }

    private var accessibilityText: String {
        var parts = [listing.title, Fmt.fcfa(listing.price), "Taille \(listing.cardSize)", listing.locationLabel]
        if let drop = listing.priceDrop { parts.insert("Prix baissé de \(Fmt.fcfa(drop))", at: 2) }
        return parts.joined(separator: ", ")
    }

    private func openListing() {
        if let onTap { onTap() } else { router.push(.product(listing.id)) }
    }
}

extension Listing {
    /// Short size for cards: "M", "38", "42", "4 ans", "TU" (taille unique).
    var cardSize: String {
        let value = sizeValue
        if sizeType == .unique || value.lowercased() == "taille unique" { return "TU" }
        return value.isEmpty ? sizeLabel : value
    }
    /// "M · Cocody" — the line under the price on grid cards.
    var cardSizeDistrict: String {
        district.isEmpty ? cardSize : "\(cardSize) · \(district)"
    }
}

struct ListingCard_Previews: PreviewProvider {
    static var previews: some View {
        let repo = DemoSeed.make()
        return ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(repo.listings) { ListingCard(listing: $0) }
            }
            .padding(16)
        }
        .rfScreenBackground()
        .previewEnvironment()
    }
}
