import SwiftUI

/// Public seller profile (mockup `screenProfile`, PANEL `profil`): trust header (avatar, verified, rating,
/// sales, seniority, response time, city), "Écrire" → conversation, grid of the seller's active listings.
struct SellerProfileView: View {
    let userId: UUID

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var profile: UserProfile?
    @State private var listings: [Listing] = []
    @State private var loadError: Error?
    @State private var isOpeningChat = false

    private var isMe: Bool { store.me?.id == userId }
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        Group {
            if let profile {
                content(profile)
            } else if let loadError {
                ErrorStateView(error: loadError) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .rfScreenBackground()
        .navigationTitle(isMe ? "Mon profil public" : "Profil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let profile {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: AppLinks.profile(profile.id),
                              message: Text("Découvre la boutique de \(profile.username) sur ReFripe — fripe à \(profile.city), paiement sécurisé Wave / Orange Money.")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Partager ce profil")
                }
            }
        }
        .task { await load() }
    }

    private func content(_ profile: UserProfile) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ProfileHeroView(profile: profile)

                if isMe {
                    DashboardCTAButton(subtitle: "Tes ventes et tes achats au même endroit") {
                        router.push(.dashboard)
                    }
                    .padding(.horizontal, RF.S.gutter)
                    .padding(.bottom, 6)
                } else {
                    RFButton("Écrire à \(profile.firstName.isEmpty ? profile.username : profile.firstName)",
                             symbol: "bubble.left", style: .ink, isLoading: isOpeningChat) {
                        Task { await openChat() }
                    }
                    .padding(.horizontal, RF.S.gutter)
                    .padding(.bottom, 6)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text((isMe ? "Mes articles" : "Ses articles").uppercased())
                            .font(RF.F.body(11, .bold))
                            .kerning(0.55)
                            .foregroundStyle(RF.C.textDim)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        if !listings.isEmpty {
                            Text("\(listings.count) en vente")
                                .font(RF.F.mono(11))
                                .foregroundStyle(RF.C.textDim)
                        }
                    }
                    if listings.isEmpty {
                        if isMe {
                            EmptyStateView(symbol: "hanger", title: "Aucun article en vente",
                                           message: "Publie ton premier article en quelques minutes.",
                                           actionTitle: "Vendre un article") { router.isSellPresented = true }
                        } else {
                            EmptyStateView(symbol: "hanger", title: "Aucun article en vente",
                                           message: "Reviens bientôt : les nouveautés arrivent vite.")
                        }
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(listings) { ListingCard(listing: $0) }
                        }
                    }
                }
                .padding(.horizontal, RF.S.gutter)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
        }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            let p = try await store.repo.profile(id: userId)
            let items = try await store.repo.listings(sellerId: userId)
            store.cache([p.id: p])
            profile = p
            listings = items.filter { $0.status == .active }.sorted { $0.createdAt > $1.createdAt }
            loadError = nil
        } catch {
            if profile == nil { loadError = error } else { store.show(error) }
        }
    }

    private func openChat() async {
        guard !isOpeningChat else { return }
        isOpeningChat = true
        defer { isOpeningChat = false }
        do {
            let conversation = try await store.repo.conversation(withUser: userId, listingId: nil)
            Haptics.tap()
            router.push(.chat(conversation.id))
        } catch {
            store.show(error)
        }
    }
}

#Preview("Vendeuse") {
    NavigationStack { SellerProfileView(userId: DemoIDs.sneak) }
        .previewEnvironment()
}

#Preview("Moi") {
    NavigationStack { SellerProfileView(userId: DemoIDs.awa) }
        .previewEnvironment()
}
