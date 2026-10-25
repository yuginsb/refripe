import SwiftUI

/// « Profil » tab: my public profile as others see it (header, edit / share), « Statistiques » entry,
/// then « Mon dressing ». The gear opens Réglages.
struct ProfileTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var myListings: [Listing]?
    @State private var stats: SellerStats?
    @State private var isEditing = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let me = store.me {
                    VStack(spacing: 16) {
                        ProfileHeroView(profile: me)
                        actions(me)
                    }
                    .padding(.top, 8)
                }
                statsEntry
                dressing
            }
            .padding(.horizontal, RF.S.gutter)
            .padding(.bottom, 24)
        }
        .rfScreenBackground()
        .refreshable { await load() }
        .task { await load() }
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.push(.settings) } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Réglages")
            }
        }
        .sheet(isPresented: $isEditing) {
            ProfileEditSheet()
                .environment(store)
                .presentationDetents([.large])
        }
    }

    // MARK: Header actions

    private func actions(_ me: UserProfile) -> some View {
        HStack(spacing: 12) {
            Button { isEditing = true } label: {
                Text("Modifier le profil").frame(maxWidth: .infinity)
            }
            ShareLink(item: AppLinks.profile(me.id),
                      message: Text("Mon dressing sur ReFripe")) {
                Label("Partager", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
        }
        .font(RF.T.subheadline.weight(.semibold))
        .foregroundStyle(RF.C.text)
        .buttonStyle(ProfileOutlineButtonStyle())
    }

    // MARK: Statistiques

    private var statsEntry: some View {
        Button { router.push(.dashboard) } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar")
                    .font(RF.T.body)
                    .foregroundStyle(RF.C.text)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Statistiques")
                        .font(RF.T.subheadline.weight(.semibold))
                        .foregroundStyle(RF.C.text)
                    Text(statsSubtitle)
                        .font(RF.T.footnote.monospacedDigit())
                        .foregroundStyle(RF.C.textDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(RF.T.footnote.weight(.semibold))
                    .foregroundStyle(RF.C.textDim)
            }
            .padding(12)
            .rfCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var statsSubtitle: String {
        guard let stats else { return "Ventes, vues et objectif du mois" }
        return "\(stats.sales) vente\(stats.sales > 1 ? "s" : "") · \(Fmt.number(stats.views)) vues ce mois-ci"
    }

    // MARK: Mon dressing

    @ViewBuilder private var dressing: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mon dressing")
                    .font(RF.T.title3)
                    .foregroundStyle(RF.C.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let myListings, !myListings.isEmpty {
                    Text("\(myListings.count) article\(myListings.count > 1 ? "s" : "")")
                        .font(RF.T.footnote.monospacedDigit())
                        .foregroundStyle(RF.C.textDim)
                }
            }
            if let myListings {
                if myListings.isEmpty {
                    ContentUnavailableView {
                        Label("Ton dressing est vide", systemImage: "hanger")
                    } description: {
                        Text("Publie ton premier article.")
                    } actions: {
                        Button("Vendre un article") { router.isSellPresented = true }
                            .buttonStyle(.borderedProminent)
                            .tint(RF.C.hibiscus)
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(myListings) { listing in
                            ListingCard(listing: listing)
                                .overlay(alignment: .topLeading) { ListingStatusBadge(status: listing.status) }
                        }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
        }
    }

    // MARK: Data

    private func load() async {
        guard let me = store.me else { return }
        let repo = store.repo
        async let listingsTask = try? repo.listings(sellerId: me.id)
        async let statsTask = try? repo.sellerStats()
        let (listings, s) = await (listingsTask, statsTask)
        myListings = (listings ?? [])
            .filter { $0.status != .removed }
            .sorted { a, b in
                let ra = a.status == .active ? 0 : 1
                let rb = b.status == .active ? 0 : 1
                return ra != rb ? ra < rb : a.createdAt > b.createdAt
            }
        stats = s
    }
}

#Preview {
    NavigationStack { ProfileTabView().withAppRoutes() }
        .previewEnvironment()
}


/// Light outlined button for the profile header (white fill, hairline), lighter than `.bordered`.
private struct ProfileOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 11)
            .background(RF.C.card, in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: RF.R.md, style: .continuous).strokeBorder(RF.C.line))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
