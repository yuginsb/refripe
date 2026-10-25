import SwiftUI

/// Public seller profile: header (avatar, verified, rating, sales, response time, city),
/// « Écrire » → conversation, grid of the seller's active listings.
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
        .navigationTitle(profile?.username ?? "Profil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let profile {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: AppLinks.profile(profile.id),
                              message: Text("Le dressing de \(profile.username) sur ReFripe")) {
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
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    ProfileHeroView(profile: profile)
                    if !isMe {
                        RFButton("Écrire à \(profile.firstName.isEmpty ? profile.username : profile.firstName)",
                                 symbol: "bubble.left", style: .primary, isLoading: isOpeningChat) {
                            Task { await openChat() }
                        }
                    }
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(isMe ? "Mon dressing" : "Son dressing")
                            .font(RF.T.title3)
                            .foregroundStyle(RF.C.text)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        if !listings.isEmpty {
                            Text("\(listings.count) en vente")
                                .font(RF.T.footnote.monospacedDigit())
                                .foregroundStyle(RF.C.textDim)
                        }
                    }
                    if listings.isEmpty {
                        ContentUnavailableView("Aucun article en vente", systemImage: "hanger",
                                               description: Text(isMe ? "Publie ton premier article." : "Reviens bientôt."))
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(listings) { ListingCard(listing: $0) }
                        }
                    }
                }
            }
            .padding(.horizontal, RF.S.gutter)
            .padding(.bottom, 24)
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
