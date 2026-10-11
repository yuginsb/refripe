import SwiftUI

/// "Mes envies" tab (mockup `screenEnvies`, PANEL `envies`): liked listings with price-drop highlights,
/// removal by heart or swipe, total, sort, and an empty state that sends back to Découvrir.
struct WishlistView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var cache: [UUID: Listing] = [:]
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var sort: WishlistSort = .drops
    @State private var layout: WishlistLayout = .grid

    private var items: [Listing] {
        store.wishlist.compactMap { cache[$0] }.filter { $0.status != .removed }.sorted(by: sort.areInIncreasingOrder)
    }

    var body: some View {
        Group {
            if store.wishlist.isEmpty || (!isLoading && items.isEmpty && loadError == nil) {
                ScrollView { emptyState }
            } else if items.isEmpty && isLoading {
                LoadingView("Chargement de tes envies…")
            } else if items.isEmpty, let loadError {
                ScrollView { ErrorStateView(error: loadError) { Task { await load() } } }
            } else {
                content
            }
        }
        .rfScreenBackground()
        .navigationTitle("Mes envies")
        .toolbar { toolbarItems }
        .task(id: store.wishlist) { await load() }
        .refreshable { await load() }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch layout {
        case .grid:
            ScrollView {
                header
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(items) { listing in
                        WishlistCard(listing: listing) { router.push(.product(listing.id)) }
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, RF.S.gutter)
                .padding(.top, 2)
                footer
            }
            .animation(.snappy, value: items.map(\.id))
        case .list:
            List {
                Section {
                    ForEach(items) { listing in
                        WishlistRow(listing: listing) { router.push(.product(listing.id)) }
                            .listRowBackground(RF.C.paper)
                            .listRowInsets(EdgeInsets(top: 6, leading: RF.S.gutter, bottom: 6, trailing: RF.S.gutter))
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { remove(listing) } label: {
                                    Label("Retirer", systemImage: "heart.slash")
                                }
                                .tint(RF.C.hibiscus)
                            }
                    }
                } header: {
                    header.textCase(nil).listRowInsets(EdgeInsets())
                } footer: {
                    footer.listRowInsets(EdgeInsets())
                }
            }
            .listStyle(.plain)
            .animation(.snappy, value: items.map(\.id))
        }
    }

    /// Mockup `.envies-sub` + summary (count, total, savings from price drops).
    private var header: some View {
        let drops = items.compactMap(\.priceDrop)
        return VStack(alignment: .leading, spacing: 12) {
            Text("On te prévient dès qu'un prix baisse ou qu'une pièce similaire arrive dans ta taille.")
                .font(RF.F.body(11.5))
                .foregroundStyle(RF.C.textDim)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                summaryTile(value: "\(items.count)", label: items.count > 1 ? "articles" : "article")
                summaryTile(value: Fmt.fcfa(items.reduce(0) { $0 + $1.price }), label: "au total")
                if !drops.isEmpty {
                    summaryTile(value: "−" + Fmt.fcfa(drops.reduce(0, +)),
                                label: drops.count > 1 ? "\(drops.count) prix en baisse" : "1 prix en baisse",
                                highlight: true)
                }
            }
        }
        .padding(.horizontal, RF.S.gutter)
        .padding(.bottom, 12)
    }

    private func summaryTile(value: String, label: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(RF.F.mono(13, .semibold))
                .monospacedDigit()
                .foregroundStyle(highlight ? RF.C.moneyDeep : RF.C.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(RF.F.body(10))
                .foregroundStyle(highlight ? RF.C.moneyDeep : RF.C.textDim)
                .lineLimit(1)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlight ? RF.C.money.opacity(0.14) : RF.C.paperDim,
                    in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.badge").font(.system(size: 13)).foregroundStyle(RF.C.marigold)
            Text("Tu seras alerté·e dès qu'un prix baisse.")
                .font(RF.F.body(11.5))
                .foregroundStyle(RF.C.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        EmptyStateView(symbol: "heart",
                       title: "Pas encore d'envies",
                       message: "Ajoute des articles en glissant à droite dans « Pour toi », ou en touchant le cœur sur une annonce. On te prévient dès que leur prix baisse.",
                       actionTitle: "Découvrir des articles") {
            router.selectedTab = .discover
        }
    }

    @ToolbarContentBuilder private var toolbarItems: some ToolbarContent {
        if !items.isEmpty {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Trier", selection: $sort) {
                        ForEach(WishlistSort.allCases) { option in
                            Label(option.label, systemImage: option.symbol).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Trier : \(sort.label)")

                Button {
                    withAnimation(.snappy) { layout = layout == .grid ? .list : .grid }
                } label: {
                    Image(systemName: layout == .grid ? "list.bullet" : "square.grid.2x2")
                }
                .accessibilityLabel(layout == .grid ? "Afficher en liste" : "Afficher en grille")
            }
        }
    }

    // MARK: Data

    /// Loads every liked listing in parallel (keeps already-loaded ones on screen while refreshing).
    private func load() async {
        let ids = store.wishlist
        guard !ids.isEmpty else { loadError = nil; isLoading = false; return }
        isLoading = true
        defer { isLoading = false }
        let repo = store.repo
        let results = await withTaskGroup(of: WishlistFetch.self) { group in
            for id in ids {
                group.addTask {
                    do { return (id: id, result: .success(try await repo.listing(id: id))) }
                    catch { return (id: id, result: .failure(error)) }
                }
            }
            var collected: [WishlistFetch] = []
            for await result in group { collected.append(result) }
            return collected
        }
        var firstError: Error?
        for (id, result) in results {
            switch result {
            case .success(let listing): cache[id] = listing
            case .failure(RepositoryError.notFound): cache[id] = nil      // deleted listing: just hide it
            case .failure(let error): firstError = firstError ?? error
            }
        }
        loadError = firstError
        if let firstError, !cache.isEmpty { store.show(firstError) }
    }

    private func remove(_ listing: Listing) {
        store.setLiked(listing.id, false)
        store.show("Retiré de tes envies")
    }
}

// MARK: - Sort & layout

/// One parallel fetch result: listing id and its outcome.
typealias WishlistFetch = (id: UUID, result: Result<Listing, Error>)

enum WishlistSort: String, CaseIterable, Identifiable {
    case drops, recent, priceAsc, priceDesc
    var id: String { rawValue }

    var label: String {
        switch self {
        case .drops: "Baisses de prix d'abord"
        case .recent: "Plus récents"
        case .priceAsc: "Prix croissant"
        case .priceDesc: "Prix décroissant"
        }
    }
    var symbol: String {
        switch self {
        case .drops: "chart.line.downtrend.xyaxis"
        case .recent: "clock"
        case .priceAsc: "arrow.up"
        case .priceDesc: "arrow.down"
        }
    }

    func areInIncreasingOrder(_ a: Listing, _ b: Listing) -> Bool {
        switch self {
        case .drops:
            let da = a.priceDrop ?? 0, db = b.priceDrop ?? 0
            return da != db ? da > db : a.createdAt > b.createdAt
        case .recent: return a.createdAt > b.createdAt
        case .priceAsc: return a.price != b.price ? a.price < b.price : a.createdAt > b.createdAt
        case .priceDesc: return a.price != b.price ? a.price > b.price : a.createdAt > b.createdAt
        }
    }
}

enum WishlistLayout { case grid, list }

// MARK: - Cells

/// "−2 000 FCFA" pill (green, mockup `.price-drop`, with the amount).
struct WishlistDropBadge: View {
    let amount: FCFA
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.down").font(.system(size: 7, weight: .black))
            Text("−\(Fmt.fcfa(amount))")
        }
        .font(RF.F.body(8.5, .extraBold))
        .foregroundStyle(.white)
        .padding(.vertical, 3)
        .padding(.horizontal, 7)
        .background(Capsule().fill(RF.C.money))
        .accessibilityLabel("Prix baissé de \(Fmt.fcfa(amount))")
    }
}

/// Price + struck-through old price (mockup envies `.price`).
struct WishlistPrice: View {
    let listing: Listing
    var size: CGFloat = 13

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(Fmt.fcfa(listing.price))
                .font(RF.F.mono(size, .semibold))
                .foregroundStyle(listing.priceDrop != nil ? RF.C.moneyDeep : RF.C.text)
            if let old = listing.oldPrice, listing.priceDrop != nil {
                Text(Fmt.fcfa(old))
                    .font(RF.F.mono(size - 3))
                    .strikethrough()
                    .foregroundStyle(RF.C.textDim)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

/// Grid card for envies (mockup `.card` + old price + drop amount).
struct WishlistCard: View {
    let listing: Listing
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ListingPhotoView(photo: listing.photos.first, listingId: listing.id)
                .frame(height: 118)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topLeading) {
                    if let drop = listing.priceDrop { WishlistDropBadge(amount: drop).padding(7) }
                }
                .overlay(alignment: .bottomLeading) {
                    if listing.status != .active { statusBadge.padding(7) }
                }
            VStack(alignment: .leading, spacing: 2) {
                WishlistPrice(listing: listing)
                Text(listing.title)
                    .font(RF.F.body(11))
                    .foregroundStyle(RF.C.textDim)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(EdgeInsets(top: 8, leading: 10, bottom: 11, trailing: 10))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .rfCard()
        .contentShape(RoundedRectangle(cornerRadius: RF.R.lg, style: .continuous))
        .onTapGesture(perform: onTap)
        .overlay(alignment: .topTrailing) { HeartButton(listingId: listing.id).padding(7) }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Ouvrir l'annonce", onTap)
    }

    private var statusBadge: some View {
        Text(listing.status == .sold ? "Vendu" : "Réservé")
            .font(RF.F.body(8, .extraBold))
            .foregroundStyle(RF.C.paper)
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(Capsule().fill(RF.C.ink1))
    }
}

/// List row variant (swipe to remove).
struct WishlistRow: View {
    let listing: Listing
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ListingPhotoView(photo: listing.photos.first, listingId: listing.id)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(listing.title)
                    .font(RF.F.body(12.5, .bold))
                    .foregroundStyle(RF.C.text)
                    .lineLimit(2)
                WishlistPrice(listing: listing)
                HStack(spacing: 6) {
                    if let drop = listing.priceDrop { WishlistDropBadge(amount: drop) }
                    Text("\(listing.sizeLabel) · \(listing.district)")
                        .font(RF.F.body(10))
                        .foregroundStyle(RF.C.textDim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            HeartButton(listingId: listing.id, size: 30)
        }
        .padding(10)
        .rfCard()
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Ouvrir l'annonce", onTap)
    }
}

#Preview {
    NavigationStack {
        WishlistView().withAppRoutes()
    }
    .previewEnvironment()
}
