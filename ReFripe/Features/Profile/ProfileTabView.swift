import SwiftUI

/// "Profil" tab: my trust header, dashboard entry, order shortcuts, my listings, editable preferences,
/// welcome guide replay, sign-out. Demo mode is flagged.
struct ProfileTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @AppStorage(DashboardMode.storageKey) private var dashboardMode: DashboardMode = .sell

    @State private var myListings: [Listing]?
    @State private var sellerOrders: [Order] = []
    @State private var buyerOrders: [Order] = []
    @State private var stats: SellerStats?
    @State private var editing: PreferenceEditorKind?
    @State private var showGuide = false
    @State private var confirmSignOut = false
    @State private var isSigningOut = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private static let gridLimit = 6

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let me = store.me {
                    ProfileHeroView(profile: me)
                }
                VStack(spacing: 22) {
                    if store.isDemo { demoBanner }
                    DashboardCTAButton(subtitle: dashboardSubtitle) {
                        router.push(.dashboard)
                    }
                    ordersSection
                    listingsSection
                    preferencesSection
                    accountSection
                }
                .padding(.horizontal, RF.S.gutter)
                .padding(.bottom, 28)
            }
        }
        .rfScreenBackground()
        .refreshable { await load() }
        .task { await load() }
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.push(.notifications) } label: {
                    Image(systemName: store.unreadNotifications > 0 ? "bell.badge" : "bell")
                }
                .accessibilityLabel(store.unreadNotifications > 0
                                    ? "Notifications, \(store.unreadNotifications) non lues" : "Notifications")
            }
            if let me = store.me {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.push(.sellerProfile(me.id)) } label: {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                    }
                    .accessibilityLabel("Voir mon profil public")
                }
            }
        }
        .sheet(item: $editing) { kind in
            PreferenceEditorSheet(kind: kind)
                .environment(store)
                .presentationDetents(kind == .categories ? [.medium, .large] : [.large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showGuide) {
            IntroGuideView { showGuide = false }
        }
        .confirmationDialog("Te déconnecter de ReFripe ?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive) { Task { await signOut() } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(store.isDemo ? "Mode démo : reconnecte-toi avec le 07 07 07 07 07 (code 1234) pour retrouver Awa."
                              : "Tes annonces, envies et commandes restent enregistrées sur ton compte.")
        }
    }

    // MARK: Sections

    private var demoBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RF.C.marigold)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mode démo")
                    .font(RF.F.body(12, .extraBold))
                    .foregroundStyle(RF.C.textOnInk)
                Text("Données fictives tirées de la maquette : aucun paiement réel, les vendeuses sont simulées.")
                    .font(RF.F.body(11))
                    .foregroundStyle(RF.C.textOnInkDim)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RF.C.ink1, in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var dashboardSubtitle: String {
        let sales = stats?.sales ?? sellerOrders.filter { isThisMonth($0.createdAt) }.count
        let purchases = buyerOrders.filter { isThisMonth($0.createdAt) }.count
        return "\(sales) vente\(sales > 1 ? "s" : "") · \(purchases) achat\(purchases > 1 ? "s" : "") ce mois-ci"
    }

    private var toProcess: [Order] {
        sellerOrders.filter { $0.status.isOpenForDashboard }.sorted { $0.status.urgencyRank < $1.status.urgencyRank }
    }
    private var inProgressPurchases: [Order] {
        buyerOrders.filter { $0.status.isOpenForDashboard }.sorted { $0.status.urgencyRank < $1.status.urgencyRank }
    }

    private struct UrgentOrder: Identifiable {
        let order: Order
        let isSale: Bool
        var id: UUID { order.id }
    }

    /// The 3 most urgent open orders, sales and purchases mixed.
    private var urgentOrders: [UrgentOrder] {
        let all = toProcess.map { UrgentOrder(order: $0, isSale: true) }
            + inProgressPurchases.map { UrgentOrder(order: $0, isSale: false) }
        return Array(all.sorted { $0.order.status.urgencyRank < $1.order.status.urgencyRank }.prefix(3))
    }

    private var ordersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Mes commandes")
            HStack(spacing: 10) {
                shortcut(symbol: "shippingbox", title: "Ventes à traiter", count: toProcess.count, mode: .sell)
                shortcut(symbol: "bag", title: "Achats en cours", count: inProgressPurchases.count, mode: .buy)
            }
            let urgent = urgentOrders
            if !urgent.isEmpty {
                VStack(spacing: 0) {
                    ForEach(urgent) { entry in
                        Button { router.push(.order(entry.order.id)) } label: {
                            ProfileOrderLine(order: entry.order,
                                             subtitle: entry.isSale ? "Vente · \(entry.order.buyerName)"
                                                                    : "Achat · \(Fmt.relative(entry.order.createdAt))")
                        }
                        .buttonStyle(.plain)
                        if entry.id != urgent.last?.id { Divider().overlay(RF.C.line) }
                    }
                }
                .padding(.horizontal, 12)
                .rfCard()
            }
        }
    }

    private func shortcut(symbol: String, title: String, count: Int, mode: DashboardMode) -> some View {
        Button {
            dashboardMode = mode
            router.push(.dashboard)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(RF.C.text)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(count)")
                        .font(RF.F.mono(17, .semibold))
                        .foregroundStyle(count > 0 && mode == .sell ? RF.C.hibiscus : RF.C.text)
                    Text(title)
                        .font(RF.F.body(10.5))
                        .foregroundStyle(RF.C.textDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(RF.C.textDim)
            }
            .padding(12)
            .background(RF.C.paperDim, in: RoundedRectangle(cornerRadius: RF.R.lg, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: RF.R.lg, style: .continuous))
        }
        .buttonStyle(RFPressStyle())
        .accessibilityLabel("\(title) : \(count)")
    }

    @ViewBuilder private var listingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Mes annonces")
                if let myListings, myListings.count > Self.gridLimit, let me = store.me {
                    Button("Tout voir (\(myListings.count))") { router.push(.sellerProfile(me.id)) }
                        .font(RF.F.body(11.5, .bold))
                        .foregroundStyle(RF.C.hibiscus)
                        .fixedSize()
                }
            }
            if let myListings {
                if myListings.isEmpty {
                    EmptyStateView(symbol: "hanger", title: "Pas encore d'annonce",
                                   message: "Prends tes photos, fixe ton prix : ton article est en ligne en quelques minutes.",
                                   actionTitle: "Vendre un article") { router.isSellPresented = true }
                        .rfCard()
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(myListings.prefix(Self.gridLimit)) { listing in
                            ListingCard(listing: listing)
                                .overlay(alignment: .topLeading) { statusBadge(listing.status) }
                        }
                    }
                    RFButton("Vendre un autre article", symbol: "plus", style: .ghost) { router.isSellPresented = true }
                }
            } else {
                ProgressView().tint(RF.C.hibiscus).frame(maxWidth: .infinity, minHeight: 80)
            }
        }
    }

    @ViewBuilder private func statusBadge(_ status: ListingStatus) -> some View {
        switch status {
        case .reserved, .sold:
            Text(status == .sold ? "Vendu" : "Réservé")
                .font(RF.F.body(8, .extraBold))
                .foregroundStyle(RF.C.paper)
                .padding(.vertical, 3)
                .padding(.horizontal, 7)
                .background(Capsule().fill(RF.C.ink1))
                .padding(7)
        default:
            EmptyView()
        }
    }

    private var preferencesSection: some View {
        let prefs = store.preferences
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Mes préférences")
            VStack(spacing: 0) {
                preferenceRow(.categories, value: PreferenceEditorKind.summary(categories: prefs.categories))
                Divider().overlay(RF.C.line)
                preferenceRow(.sizes, value: PreferenceEditorKind.summary(sizes: prefs.sizes))
                Divider().overlay(RF.C.line)
                preferenceRow(.brands, value: PreferenceEditorKind.summary(brands: prefs.brands))
            }
            .padding(.horizontal, 14)
            .rfCard()
            Text("Elles réordonnent Découvrir et déclenchent les alertes « nouveautés dans ta taille ».")
                .font(RF.F.body(10.5))
                .foregroundStyle(RF.C.textDim)
        }
    }

    private func preferenceRow(_ kind: PreferenceEditorKind, value: String) -> some View {
        Button { editing = kind } label: {
            HStack(spacing: 12) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(RF.C.text)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(RF.F.body(12.5, .bold))
                        .foregroundStyle(RF.C.text)
                    Text(value)
                        .font(RF.F.body(11))
                        .foregroundStyle(RF.C.textDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(RF.C.textDim)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kind.title) : \(value)")
        .accessibilityHint("Modifier")
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Compte")
            VStack(spacing: 0) {
                accountRow(symbol: "sparkles.rectangle.stack", title: "Revoir le guide de bienvenue") { showGuide = true }
                Divider().overlay(RF.C.line)
                accountRow(symbol: "rectangle.portrait.and.arrow.right", title: "Se déconnecter", destructive: true) {
                    confirmSignOut = true
                }
                .disabled(isSigningOut)
            }
            .padding(.horizontal, 14)
            .rfCard()
            if let me = store.me {
                Text("Connectée en tant que \(me.username)\(store.isDemo ? " · mode démo" : "")")
                    .font(RF.F.mono(10))
                    .foregroundStyle(RF.C.textDim)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
    }

    private func accountRow(symbol: String, title: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .frame(width: 22)
                Text(title)
                    .font(RF.F.body(12.5, .bold))
                Spacer(minLength: 0)
                if !destructive {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(RF.C.textDim)
                }
            }
            .foregroundStyle(destructive ? RF.C.hibiscus : RF.C.text)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Data

    private func isThisMonth(_ date: Date) -> Bool {
        Calendar.current.isDate(date, equalTo: .now, toGranularity: .month)
    }

    private func load() async {
        guard let me = store.me else { return }
        let repo = store.repo
        async let listingsTask = try? repo.listings(sellerId: me.id)
        async let sellerTask = try? repo.orders(role: .seller)
        async let buyerTask = try? repo.orders(role: .buyer)
        async let statsTask = try? repo.sellerStats()
        let (listings, sOrders, bOrders, s) = await (listingsTask, sellerTask, buyerTask, statsTask)
        myListings = (listings ?? [])
            .filter { $0.status != .removed }
            .sorted { a, b in
                let ra = a.status == .active ? 0 : 1
                let rb = b.status == .active ? 0 : 1
                return ra != rb ? ra < rb : a.createdAt > b.createdAt
            }
        sellerOrders = sOrders ?? []
        buyerOrders = bOrders ?? []
        stats = s
    }

    private func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        // AppStore.signOut doesn't touch navigation: reset every tab first.
        for tab in AppTab.allCases { router.popToRoot(tab) }
        router.selectedTab = .discover
        await store.signOut()
        Haptics.tap()
    }
}

// MARK: - Preference editor

enum PreferenceEditorKind: String, Identifiable, Hashable {
    case categories, sizes, brands
    var id: String { rawValue }

    var title: String {
        switch self { case .categories: "Catégories"; case .sizes: "Tailles"; case .brands: "Marques préférées" }
    }
    var symbol: String {
        switch self { case .categories: "square.grid.2x2"; case .sizes: "ruler"; case .brands: "tag" }
    }

    static func summary(categories: Set<Gender>) -> String {
        let labels = Gender.allCases.filter(categories.contains).map(\.label)
        return labels.isEmpty ? "Aucune — choisis-en au moins une" : labels.joined(separator: ", ")
    }
    static func summary(sizes: [SizeType: String]) -> String {
        let parts = OnboardingSizeFields.types.compactMap { t in sizes[t].map { "\(t.label) \($0)" } }
        return parts.isEmpty ? "Non renseignées" : parts.joined(separator: " · ")
    }
    static func summary(brands: Set<String>) -> String {
        let ordered = Catalog.brands.filter(brands.contains) + brands.subtracting(Catalog.brands).sorted()
        return ordered.isEmpty ? "Toutes les marques" : ordered.joined(separator: ", ")
    }
}

struct PreferenceEditorSheet: View {
    let kind: PreferenceEditorKind

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var categories: Set<Gender> = []
    @State private var sizes: [SizeType: String] = [:]
    @State private var brands: Set<String> = []
    @State private var seeded = false

    private var canSave: Bool { kind != .categories || !categories.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    OnboardingTagline(tagline)
                    switch kind {
                    case .categories: CategoryPreferenceGrid(categories: $categories)
                    case .sizes: SizePreferenceRows(sizes: $sizes)
                    case .brands: BrandPreferenceChips(brands: $brands)
                    }
                }
                .padding(RF.S.gutter)
            }
            .rfScreenBackground()
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .font(RF.F.body(14, .bold))
                        .disabled(!canSave)
                }
            }
        }
        .onAppear {
            guard !seeded else { return }
            seeded = true
            categories = store.preferences.categories
            sizes = store.preferences.sizes
            brands = store.preferences.brands
        }
    }

    private var tagline: String {
        switch kind {
        case .categories: "Choisis au moins une catégorie : elles passent en premier dans Découvrir."
        case .sizes: "Facultatif — ça affine les notifications de nouveautés dans ta taille."
        case .brands: "Facultatif — sélectionne celles que tu portes le plus souvent."
        }
    }

    private func save() {
        let c = categories, s = sizes, b = brands
        store.updatePreferences { p in
            switch kind {
            case .categories: p.categories = c
            case .sizes: p.sizes = s
            case .brands: p.brands = b
            }
        }
        Haptics.success()
        store.show("Préférences enregistrées")
        dismiss()
    }
}

#Preview {
    NavigationStack { ProfileTabView().withAppRoutes() }
        .previewEnvironment()
}
