import SwiftUI
import UIKit

/// Shown after `repo.publish` succeeds: check mark + haptic, listing preview, "Voir l'annonce", "Partager".
struct SellSuccessView: View {
    @Bindable var model: SellFlowModel
    let listing: Listing
    let close: () -> Void

    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// Public link of a listing. TODO(contract): domain/universal link to be defined with the backend.
    private var shareURL: URL {
        AppLinks.listing(listing.id)
    }

    private var shareImage: Image {
        if let cover = model.coverImage { return Image(uiImage: cover) }
        return Image(systemName: "tshirt")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(RF.C.money)
                    .symbolEffect(.bounce, value: appeared)
                    .padding(.top, 40)
                    .accessibilityHidden(true)

                Text("Annonce publiée")
                    .font(RF.T.title)
                    .foregroundStyle(RF.C.text)
                    .padding(.top, RF.S.lg)
                    .accessibilityAddTraits(.isHeader)
                Text("En ligne à \(listing.locationLabel).")
                    .font(RF.T.subheadline)
                    .foregroundStyle(RF.C.textDim)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)

                preview.padding(.top, RF.S.xl)

                VStack(spacing: 10) {
                    RFButton("Voir l'annonce") { openListing() }
                    ShareLink(item: shareURL,
                              subject: Text(listing.title),
                              message: Text("Regarde mon article sur ReFripe : \(listing.title) à \(Fmt.fcfa(listing.price))"),
                              preview: SharePreview(listing.title, image: shareImage)) {
                        Label("Partager", systemImage: "square.and.arrow.up")
                            .font(RF.T.button)
                            .foregroundStyle(RF.C.hibiscus)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(RF.C.hibiscus.opacity(0.10),
                                        in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
                    }
                    .buttonStyle(RFPressStyle())
                    Button("Vendre un autre article") {
                        withAnimation(.snappy) { model.reset() }
                    }
                    .font(RF.T.subheadline)
                    .foregroundStyle(RF.C.textDim)
                    .padding(.top, RF.S.sm)
                }
                .padding(.top, RF.S.xl)
            }
            .padding(.horizontal, RF.S.gutter)
            .padding(.bottom, 30)
        }
        .navigationTitle("Publié")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Fermer")
            }
        }
        .onAppear {
            if !reduceMotion { appeared = true }
            UIAccessibility.post(notification: .announcement, argument: "Annonce publiée")
        }
    }

    private var preview: some View {
        HStack(spacing: 12) {
            ListingPhotoView(photo: listing.photos.first, listingId: listing.id)
                .overlay {
                    if listing.photos.isEmpty, let cover = model.coverImage {
                        Image(uiImage: cover).resizable().scaledToFill()
                    }
                }
                .frame(width: 64, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(Fmt.fcfa(listing.price)).font(RF.T.price()).foregroundStyle(RF.C.text)
                Text(listing.title).font(RF.T.subheadline).foregroundStyle(RF.C.text).lineLimit(1)
                Text("\(listing.sizeLabel) · \(listing.condition.label)")
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.textDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .rfCard()
        .accessibilityElement(children: .combine)
    }

    private func openListing() {
        let id = listing.id
        close()
        router.open(.product(id), in: .profile)
    }
}

#Preview {
    let model = SellFlowModel()
    let listing = DemoSeed.make().listings[0]
    return NavigationStack {
        SellSuccessView(model: model, listing: listing, close: {})
    }
    .rfScreenBackground()
    .previewEnvironment()
}
