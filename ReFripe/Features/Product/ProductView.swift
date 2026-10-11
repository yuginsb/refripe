import SwiftUI
import UIKit

/// Product page (mockup `screenProduct` + `shareSheetHTML`): photo gallery, price, details, seller card,
/// delivery options and a sticky action bar (Acheter / Faire une offre, or "C'est ton annonce").
struct ProductView: View {
    let listingId: UUID

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var listing: Listing?
    @State private var seller: UserProfile?
    @State private var thread: OfferThread?
    @State private var loadError: Error?
    @State private var didRecordView = false
    @State private var isOpeningChat = false
    @State private var photoIndex = 0

    var body: some View {
        Group {
            if let listing {
                content(listing)
            } else if let loadError {
                ErrorStateView(error: loadError) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rfScreenBackground()
        .navigationTitle("Annonce")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let listing {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ProductShareButton(listing: listing)
                    Button {
                        copyLink(for: listing)
                    } label: {
                        Image(systemName: "link")
                    }
                    .accessibilityLabel("Copier le lien de l'annonce")
                }
            }
        }
        .task { await load() }
    }

    // MARK: Data

    private var isMine: Bool {
        guard let listing, let me = store.me?.id else { return false }
        return listing.sellerId == me
    }

    /// Accepted offer amount, from this session or from the server thread.
    private var negotiatedPrice: FCFA? {
        store.negotiatedPrices[listingId] ?? thread?.acceptedAmount
    }

    private func load() async {
        do {
            let l = try await store.repo.listing(id: listingId)
            listing = l
            loadError = nil
            seller = await store.profile(l.sellerId)
            if l.sellerId != store.me?.id, l.negotiable {
                thread = try? await store.repo.offerThread(listingId: listingId)
            }
            if !didRecordView {
                didRecordView = true
                await store.repo.recordView(listingId: listingId)
            }
        } catch {
            if listing == nil { loadError = error } else { store.show(error) }
        }
    }

    // MARK: Layout

    private func content(_ listing: Listing) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                gallery(listing)
                VStack(alignment: .leading, spacing: 0) {
                    priceBlock(listing)
                    if listing.status != .active { unavailableBanner(listing).padding(.top, 12) }
                    ProductTags(listing: listing, negotiated: negotiatedPrice != nil)
                        .padding(.top, 10)
                    sellerCard(listing)
                        .padding(.top, 18)
                    descriptionBlock(listing)
                        .padding(.top, 20)
                    if let defect = listing.defectComment, !defect.isEmpty {
                        defectBlock(defect).padding(.top, 14)
                    }
                    ProductDeliveryList(methods: listing.deliveryMethods)
                        .padding(.top, 20)
                    escrowNote.padding(.top, 14)
                }
                .padding(RF.S.gutter)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar(listing) }
    }

    // MARK: Gallery (mockup `.pd-hero`)

    private func gallery(_ listing: Listing) -> some View {
        let photos: [ListingPhoto?] = listing.photos.isEmpty ? [nil] : listing.photos.map { Optional($0) }
        return TabView(selection: $photoIndex) {
            ForEach(Array(photos.enumerated()), id: \.offset) { pair in
                ListingPhotoView(photo: pair.element, listingId: listing.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(pair.offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
        .frame(height: 340)
        .background(RF.C.thumb(for: listing.id))
        .overlay(alignment: .bottomLeading) {
            Text(listing.condition.label)
                .font(RF.F.body(10.5, .bold))
                .foregroundStyle(.white)
                .padding(.vertical, 5)
                .padding(.horizontal, 11)
                .background(Capsule().fill(RF.C.money))
                .padding(.leading, 16)
                .padding(.bottom, 12)
                .accessibilityLabel("État : \(listing.condition.label)")
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 5) {
                Image(systemName: "eye.fill").font(.system(size: 10))
                Text("\(Fmt.number(listing.views)) vues").font(RF.F.body(9.5, .bold))
            }
            .foregroundStyle(.white)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(Capsule().fill(RF.C.ink0.opacity(0.65)))
            .padding(.trailing, 16)
            .padding(.bottom, 12)
            .accessibilityElement(children: .combine)
        }
        .overlay(alignment: .topLeading) {
            ListingScarcityTag(listing: listing).padding(12)
        }
        .overlay(alignment: .topTrailing) {
            HeartButton(listingId: listing.id, size: 38).padding(12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Photos de l'article, \(listing.photos.count) photo\(listing.photos.count > 1 ? "s" : "")")
    }

    // MARK: Price & title

    private func priceBlock(_ listing: Listing) -> some View {
        let shown = negotiatedPrice ?? listing.price
        let strike: FCFA? = negotiatedPrice != nil ? listing.price : listing.oldPrice
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Fmt.fcfa(shown))
                    .font(RF.F.mono(24, .semibold))
                    .foregroundStyle(RF.C.text)
                if let strike, strike > shown {
                    Text(Fmt.fcfa(strike))
                        .font(RF.F.body(13))
                        .strikethrough()
                        .foregroundStyle(RF.C.textDim)
                        .accessibilityLabel("au lieu de \(Fmt.fcfa(strike))")
                }
                if negotiatedPrice != nil {
                    ProductTag(text: "Prix négocié", symbol: "checkmark", style: .negotiable)
                } else if let drop = listing.priceDrop {
                    Text("−\(Fmt.fcfa(drop))")
                        .font(RF.F.body(10, .extraBold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(Capsule().fill(RF.C.money))
                        .accessibilityLabel("Prix baissé de \(Fmt.fcfa(drop))")
                }
            }
            .accessibilityElement(children: .combine)
            Text(listing.title)
                .font(RF.F.body(15, .bold))
                .foregroundStyle(RF.C.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 4) {
                Text("\(listing.sizeLabel) · \(listing.condition.label) · ")
                Image(systemName: "mappin").font(.system(size: 10))
                Text(listing.locationLabel)
            }
            .font(RF.F.body(11.5, .semibold))
            .foregroundStyle(RF.C.textDim)
            .lineLimit(2)
            .accessibilityElement(children: .combine)
        }
    }

    private func unavailableBanner(_ listing: Listing) -> some View {
        let text: String = switch listing.status {
        case .reserved: "Article réservé : une commande est en cours."
        case .sold: "Cet article a été vendu."
        default: "Cet article n'est plus disponible."
        }
        return Label(text, systemImage: "clock.badge.exclamationmark")
            .font(RF.F.body(12, .bold))
            .foregroundStyle(RF.C.text)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RF.C.marigold.opacity(0.2), in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
    }

    // MARK: Seller (mockup `.pd-seller`)

    private func sellerCard(_ listing: Listing) -> some View {
        HStack(spacing: 10) {
            Button {
                router.push(.sellerProfile(listing.sellerId))
            } label: {
                HStack(spacing: 10) {
                    Avatar(profile: seller, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(seller?.username ?? "Vendeuse")
                                .font(RF.F.body(12.5, .bold))
                                .foregroundStyle(RF.C.text)
                                .lineLimit(1)
                            if seller?.verified == true { VerifiedBadge() }
                        }
                        if let seller {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(RF.C.marigold)
                                Text(sellerSubtitle(seller))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .font(RF.F.body(10.5))
                            .foregroundStyle(RF.C.textDim)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RFPressStyle(scale: 0.98))
            .accessibilityElement(children: .combine)
            .accessibilityHint("Voir le profil de la vendeuse")

            if !isMine {
                Button {
                    openChat(listing)
                } label: {
                    HStack(spacing: 5) {
                        if isOpeningChat {
                            ProgressView().controlSize(.small).tint(RF.C.text)
                        } else {
                            Image(systemName: "bubble.left").font(.system(size: 12, weight: .semibold))
                        }
                        Text("Écrire").font(RF.F.body(12, .extraBold))
                    }
                    .foregroundStyle(RF.C.text)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 12)
                    .background(Capsule().fill(RF.C.card))
                    .overlay(Capsule().strokeBorder(RF.C.line, lineWidth: 1.5))
                    .contentShape(Capsule())
                }
                .buttonStyle(RFPressStyle(scale: 0.94))
                .disabled(isOpeningChat)
                .accessibilityLabel("Écrire à \(seller?.username ?? "la vendeuse")")
            }
        }
        .padding(12)
        .background(RF.C.paperDim, in: RoundedRectangle(cornerRadius: RF.R.lg, style: .continuous))
    }

    private func sellerSubtitle(_ s: UserProfile) -> String {
        let rating = s.rating.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_FR")))
        let seniority = Fmt.seniority(since: s.memberSince)
        let since = seniority == "Nouveau" ? "Nouvelle sur ReFripe" : "Membre depuis \(seniority)"
        return "\(rating) · \(s.salesCount) vente\(s.salesCount > 1 ? "s" : "") · \(since)"
    }

    private func openChat(_ listing: Listing) {
        isOpeningChat = true
        Task {
            defer { isOpeningChat = false }
            do {
                let conv = try await store.repo.conversation(withUser: listing.sellerId, listingId: listing.id)
                router.push(.chat(conv.id))
            } catch {
                store.show(error)
            }
        }
    }

    // MARK: Description / defects

    private func descriptionBlock(_ listing: Listing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Description")
            Text(listing.description.isEmpty ? "La vendeuse n'a pas ajouté de description." : listing.description)
                .font(RF.F.body(12.5))
                .foregroundStyle(RF.C.textDim)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func defectBlock(_ defect: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(RF.C.hibiscus)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Défaut signalé par la vendeuse")
                    .font(RF.F.body(12, .bold))
                    .foregroundStyle(RF.C.text)
                Text(defect)
                    .font(RF.F.body(12))
                    .foregroundStyle(RF.C.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RF.C.hibiscus.opacity(0.08), in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var escrowNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 15))
                .foregroundStyle(RF.C.money)
                .accessibilityHidden(true)
            Text("Paiement protégé : ton argent reste en séquestre jusqu'à ce que tu confirmes la réception (libération automatique \(Catalog.escrowAutoReleaseHours) h après la livraison).")
                .font(RF.F.body(11))
                .foregroundStyle(RF.C.textDim)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RF.C.money.opacity(0.08), in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Sticky action bar (mockup `.pd-actions`)

    @ViewBuilder
    private func actionBar(_ listing: Listing) -> some View {
        VStack(spacing: 8) {
            if isMine {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                    Text("C'est ton annonce")
                }
                .font(RF.F.body(12, .bold))
                .foregroundStyle(RF.C.textDim)
                .accessibilityElement(children: .combine)
                RFButton("Voir mon tableau de bord", symbol: "chart.bar.fill", style: .ink) {
                    router.push(.dashboard)
                }
            } else if listing.status != .active {
                RFButton("Article indisponible", style: .secondary) {}
                    .disabled(true)
            } else {
                buyerActions(listing)
            }
        }
        .padding(EdgeInsets(top: 12, leading: RF.S.gutter, bottom: 10, trailing: RF.S.gutter))
        .background(RF.C.paper)
        .overlay(alignment: .top) { Rectangle().fill(RF.C.line).frame(height: 1) }
    }

    @ViewBuilder
    private func buyerActions(_ listing: Listing) -> some View {
        let price = negotiatedPrice ?? listing.price
        HStack(spacing: 10) {
            if listing.negotiable && negotiatedPrice == nil {
                if let thread, thread.status == .pending {
                    RFButton("Négociation", symbol: "bubble.left.and.bubble.right", style: .ghost) {
                        router.push(.offerThread(listing.id))
                    }
                    .accessibilityLabel("Voir la négociation en cours")
                } else if thread == nil {
                    RFButton("Faire une offre", symbol: "arrow.left.arrow.right", style: .ghost) {
                        router.push(.offer(listing.id))
                    }
                }
            }
            RFButton("Acheter · \(Fmt.fcfa(price))") {
                if let negotiated = negotiatedPrice {
                    store.negotiatedPrices[listing.id] = negotiated
                }
                router.push(.checkout(listing.id))
            }
            .accessibilityLabel("Acheter pour \(Fmt.fcfa(price))")
        }
    }

    // MARK: Share

    private func copyLink(for listing: Listing) {
        UIPasteboard.general.url = ProductShareButton.url(for: listing)
        Haptics.success()
        store.show("Lien copié")
    }
}

#Preview {
    NavigationStack {
        ProductView(listingId: DemoIDs.listing(3))
            .withAppRoutes()
    }
    .previewEnvironment()
}

#Preview("Mon annonce") {
    NavigationStack {
        ProductView(listingId: DemoIDs.listing(1))
            .withAppRoutes()
    }
    .previewEnvironment()
}
