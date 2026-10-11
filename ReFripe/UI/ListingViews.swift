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
                .font(.system(size: max(12, min(38, geo.size.width * 0.32))))
                .foregroundStyle(RF.C.textDim.opacity(0.4))
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Heart toggle bound to the global wishlist (`store.toggleLike`). Mockup `.card .heart`.
struct HeartButton: View {
    let listingId: UUID
    var size: CGFloat

    @Environment(AppStore.self) private var store

    init(listingId: UUID, size: CGFloat = 22) {
        self.listingId = listingId
        self.size = size
    }

    var body: some View {
        let liked = store.isLiked(listingId)
        Button {
            store.toggleLike(listingId)
        } label: {
            Image(systemName: "heart.fill")
                .font(.system(size: size * 0.55, weight: .semibold))
                .foregroundStyle(liked ? RF.C.hibiscus : RF.C.textDim)
                .symbolEffect(.bounce, value: liked)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(liked ? 1 : 0.85)))
                .contentShape(Circle())
        }
        .buttonStyle(RFPressStyle(scale: 0.85))
        .sensoryFeedback(.impact(weight: .light), trigger: liked)
        .accessibilityLabel(liked ? "Retirer des envies" : "Ajouter aux envies")
        .accessibilityAddTraits(liked ? .isSelected : [])
    }
}

/// Green "Prix baissé" badge (mockup `.price-drop`).
struct PriceDropBadge: View {
    var body: some View {
        Text("Prix baissé")
            .font(RF.F.body(8, .extraBold))
            .foregroundStyle(.white)
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(Capsule().fill(RF.C.money))
    }
}

/// Grid card (mockup `.card`): 118 pt photo, heart, price-drop badge, mono price, title, location.
/// Tapping pushes `.product(id)` on the current tab unless `onTap` is provided.
struct ListingCard: View {
    let listing: Listing
    var onTap: (() -> Void)?

    @Environment(Router.self) private var router

    init(listing: Listing, onTap: (() -> Void)? = nil) {
        self.listing = listing
        self.onTap = onTap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ListingPhotoView(photo: listing.photos.first, listingId: listing.id)
                .frame(height: 118)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topLeading) {
                    if listing.priceDrop != nil { PriceDropBadge().padding(7) }
                }
            info
        }
        .rfCard()
        .contentShape(RoundedRectangle(cornerRadius: RF.R.lg, style: .continuous))
        .onTapGesture(perform: openListing)
        .overlay(alignment: .topTrailing) {
            HeartButton(listingId: listing.id).padding(7)
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Fmt.fcfa(listing.price))
                .font(RF.F.mono(13, .semibold))
                .foregroundStyle(RF.C.text)
            Text(listing.title)
                .font(RF.F.body(11))
                .foregroundStyle(RF.C.textDim)
                .lineLimit(2)
                .padding(.top, 2)
            HStack(spacing: 3) {
                Image(systemName: "mappin").font(.system(size: 9))
                Text(listing.locationLabel).lineLimit(1)
            }
            .font(RF.F.body(9.5))
            .foregroundStyle(RF.C.textDim)
            .padding(.top, 4)
        }
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 11, trailing: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openListing() }
    }

    private var accessibilityText: String {
        var parts = [listing.title, Fmt.fcfa(listing.price), listing.locationLabel]
        if let drop = listing.priceDrop { parts.insert("Prix baissé de \(Fmt.fcfa(drop))", at: 2) }
        return parts.joined(separator: ", ")
    }

    private func openListing() {
        if let onTap { onTap() } else { router.push(.product(listing.id)) }
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
