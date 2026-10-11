import SwiftUI
import UIKit

/// Shown after `repo.publish` succeeds: confetti + haptic, listing preview, "Voir mon annonce", "Partager".
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
        ZStack {
            ScrollView {
                VStack(spacing: 0) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(RF.C.money))
                        .scaleEffect(appeared ? 1 : 0.4)
                        .opacity(appeared ? 1 : 0)
                        .padding(.top, 36)
                        .accessibilityHidden(true)

                    Text("Annonce publiée !")
                        .font(RF.F.display(22, .extraBold))
                        .foregroundStyle(RF.C.text)
                        .padding(.top, 20)
                        .accessibilityAddTraits(.isHeader)
                    Text("Ton article est en ligne à \(listing.locationLabel). On te prévient dès qu'une acheteuse le met en envie ou fait une offre.")
                        .font(RF.F.body(12.5))
                        .foregroundStyle(RF.C.textDim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, 8)
                        .padding(.horizontal, 12)

                    preview.padding(.top, 26)

                    VStack(spacing: 10) {
                        RFButton("Voir mon annonce", symbol: "eye") { openListing() }
                        ShareLink(item: shareURL,
                                  subject: Text(listing.title),
                                  message: Text("Regarde mon article sur ReFripe : \(listing.title) à \(Fmt.fcfa(listing.price))"),
                                  preview: SharePreview(listing.title, image: shareImage)) {
                            HStack(spacing: 7) {
                                Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .semibold))
                                Text("Partager").font(RF.F.body(13.5, .extraBold))
                            }
                            .foregroundStyle(RF.C.text)
                            .frame(maxWidth: .infinity, minHeight: 20)
                            .padding(13)
                            .overlay(RoundedRectangle(cornerRadius: RF.R.md, style: .continuous)
                                .strokeBorder(RF.C.line, lineWidth: 1.5))
                            .contentShape(RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
                        }
                        .buttonStyle(RFPressStyle())
                        Button("Vendre un autre article") {
                            withAnimation(.snappy) { model.reset() }
                        }
                        .font(RF.F.body(12.5, .bold))
                        .foregroundStyle(RF.C.textDim)
                        .padding(.top, 6)
                    }
                    .padding(.top, 26)
                }
                .padding(.horizontal, RF.S.gutter)
                .padding(.bottom, 30)
            }

            if !reduceMotion { SellConfettiView().ignoresSafeArea() }
        }
        .navigationTitle("Publié")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                }
                .accessibilityLabel("Fermer")
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) { appeared = true }
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
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(Fmt.fcfa(listing.price)).font(RF.F.mono(14, .semibold)).foregroundStyle(RF.C.text)
                Text(listing.title).font(RF.F.body(12, .bold)).foregroundStyle(RF.C.text).lineLimit(2)
                Text("\(listing.sizeLabel) · \(listing.condition.label)")
                    .font(RF.F.body(10.5))
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
