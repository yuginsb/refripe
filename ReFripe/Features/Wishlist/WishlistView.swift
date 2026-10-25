import SwiftUI

/// "Mes envies" tab: grid of liked listings, price drops flagged by a small badge, sort menu,
/// native empty state that sends back to Découvrir.
struct WishlistView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var cache: [UUID: Listing] = [:]
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var sort: WishlistSort = .drops

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var items: [Listing] {
        store.wishlist.compactMap { cache[$0] }.filter { $0.status != .removed }.sorted(by: sort.areInIncreasingOrder)
    }

    var body: some View {
        Group {
            if store.wishlist.isEmpty || (!isLoading && items.isEmpty && loadError == nil) {
                ScrollView { emptyState }
            } else if items.isEmpty && isLoading {
                LoadingView()
            } else if items.isEmpty, let loadError {
                ScrollView { ErrorStateView(error: loadError) { Task { await load() } } }
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rfScreenBackground()
        .navigationTitle("Mes envies")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarItems }
        .task(id: store.wishlist) { await load() }
        .refreshable { await load() }
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RF.S.md) {
                summary
                LazyVGrid(columns: columns, spacing: RF.S.lg) {
                    ForEach(items) { listing in
                        WishlistCard(listing: listing) { router.push(.product(listing.id)) }
                            .transition(.opacity)
                    }
                }
            }
            .padding(EdgeInsets(top: RF.S.xs, leading: RF.S.gutter, bottom: RF.S.xl, trailing: RF.S.gutter))
            .animation(.snappy, value: items.map(\.id))
        }
    }

    /// One short line: count and price drops.
    private var summary: some View {
        let n = items.count
        let drops = items.filter { $0.priceDrop != nil }.count
        var text = "\(n) article\(n > 1 ? "s" : "")"
        if drops > 0 { text += " · \(drops) prix en baisse" }
        return Text(text)
            .font(RF.T.footnote)
            .monospacedDigit()
            .foregroundStyle(RF.C.textDim)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Pas encore d'envies", systemImage: "heart")
        } description: {
            Text("Touche le cœur sur une annonce pour la garder ici.")
        } actions: {
            Button("Découvrir") { router.selectedTab = .discover }
                .buttonStyle(.borderedProminent)
                .tint(RF.C.hibiscus)
        }
        .padding(.top, 60)
    }

    @ToolbarContentBuilder private var toolbarItems: some ToolbarContent {
        if !items.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Trier", selection: $sort) {
                        ForEach(WishlistSort.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Trier : \(sort.label)")
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
}

// MARK: - Sort

/// One parallel fetch result: listing id and its outcome.
typealias WishlistFetch = (id: UUID, result: Result<Listing, Error>)

enum WishlistSort: String, CaseIterable, Identifiable {
    case drops, recent, priceAsc, priceDesc
    var id: String { rawValue }

    var label: String {
        switch self {
        case .drops: "Baisses de prix"
        case .recent: "Plus récents"
        case .priceAsc: "Prix croissant"
        case .priceDesc: "Prix décroissant"
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

// MARK: - Cells

/// Small green "−2 000 FCFA" badge.
struct WishlistDropBadge: View {
    let amount: FCFA
    var body: some View {
        Text("−\(Fmt.fcfa(amount))")
            .font(RF.T.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(Capsule().fill(RF.C.money))
            .accessibilityLabel("Prix baissé de \(Fmt.fcfa(amount))")
    }
}

/// Grid card: photo, one badge max (status, else price drop), heart, price (+ old price), title, size · district.
struct WishlistCard: View {
    let listing: Listing
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RF.S.sm) {
            ListingPhotoView(photo: listing.photos.first, listingId: listing.id)
                .frame(height: 190)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
                .overlay(alignment: .bottomLeading) { badge.padding(RF.S.sm) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: RF.S.xs) {
                    Text(Fmt.fcfa(listing.price))
                        .font(RF.T.price(.subheadline))
                        .foregroundStyle(RF.C.text)
                    if let old = listing.oldPrice, listing.priceDrop != nil {
                        Text(Fmt.fcfa(old))
                            .font(RF.T.price(.caption, weight: .regular))
                            .strikethrough()
                            .foregroundStyle(RF.C.textDim)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Text(listing.title)
                    .font(RF.T.subheadline)
                    .foregroundStyle(RF.C.text)
                    .lineLimit(1)
                Text("\(listing.sizeLabel) · \(listing.district)")
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.textDim)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap() }
        .overlay(alignment: .topTrailing) { HeartButton(listingId: listing.id).padding(RF.S.sm) }
    }

    @ViewBuilder private var badge: some View {
        if listing.status != .active {
            Text(listing.status == .sold ? "Vendu" : "Réservé")
                .font(RF.T.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.vertical, 3)
                .padding(.horizontal, 7)
                .background(Capsule().fill(RF.C.ink1))
        } else if let drop = listing.priceDrop {
            WishlistDropBadge(amount: drop)
        }
    }

    private var accessibilityText: String {
        var parts = [listing.title, Fmt.fcfa(listing.price), listing.sizeLabel, listing.district]
        if let drop = listing.priceDrop { parts.append("prix baissé de \(Fmt.fcfa(drop))") }
        if listing.status == .sold { parts.append("vendu") } else if listing.status == .reserved { parts.append("réservé") }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    NavigationStack {
        WishlistView().withAppRoutes()
    }
    .previewEnvironment()
}
