import SwiftUI

/// "Grille" mode of Découvrir (mockup `grilleSection`): search, category chips, "Filtres" chip with
/// active-count badge, result count and a 2-column grid of `ListingCard`, with pull-to-refresh.
struct DiscoverGridSection: View {
    @Binding var filters: ListingFilters
    let dropDate: Date?

    @Environment(AppStore.self) private var store

    @State private var items: [Listing] = []
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var loadError: Error?
    @State private var showFilters = false
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                DropCountdownBanner(date: dropDate)
                    .padding(EdgeInsets(top: 12, leading: RF.S.gutter, bottom: 4, trailing: RF.S.gutter))
                searchField
                    .padding(EdgeInsets(top: 8, leading: RF.S.gutter, bottom: 4, trailing: RF.S.gutter))
                chips
                resultCount
                content
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await load() }
        .task(id: filters) {
            // Light debounce while typing; filter taps reload immediately.
            if hasLoaded && !filters.query.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                if Task.isCancelled { return }
            }
            await load()
        }
        .sheet(isPresented: $showFilters) {
            DiscoverFilterSheet(filters: $filters, resultCount: items.count, isLoading: isLoading)
        }
    }

    // MARK: Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await store.repo.feed(filters: filters, preferences: store.preferences)
            if Task.isCancelled { return }
            withAnimation(.snappy(duration: 0.25)) { items = result }
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            loadError = error
        }
        hasLoaded = true
    }

    // MARK: Search (mockup `.search-fake`, here a real field)

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RF.C.textDim)
                .accessibilityHidden(true)
            TextField("Robe, Nike, wax…", text: $filters.query)
                .font(RF.F.body(12.5))
                .foregroundStyle(RF.C.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .accessibilityLabel("Rechercher un article")
            if !filters.query.isEmpty {
                Button {
                    filters.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(RF.C.textDim)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effacer la recherche")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(RF.C.paperDim, in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { searchFocused = true }
    }

    // MARK: Chips (mockup `.chips`)

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip("Tout", selected: filters.gender == nil) { setGender(nil) }
                ForEach(Gender.allCases) { g in
                    Chip(g.label, selected: filters.gender == g) { setGender(g) }
                }
                Chip("Filtres", selected: filters.activeCount > 0, badge: filters.activeCount,
                     symbol: "slider.horizontal.3") {
                    searchFocused = false
                    showFilters = true
                }
            }
            .padding(.horizontal, RF.S.gutter)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
    }

    private func setGender(_ g: Gender?) {
        filters.gender = g
    }

    // MARK: Results

    private var resultCount: some View {
        let n = items.count
        let suffix = filters.activeCount > 0 ? " · filtres actifs" : ""
        return HStack(spacing: 6) {
            Text("\(n) article\(n > 1 ? "s" : "")\(suffix)")
                .font(RF.F.body(11, .semibold))
                .foregroundStyle(RF.C.textDim)
            if isLoading && hasLoaded {
                ProgressView().controlSize(.mini).tint(RF.C.textDim)
            }
            Spacer()
        }
        .padding(EdgeInsets(top: 2, leading: RF.S.gutter, bottom: 4, trailing: RF.S.gutter))
        .opacity(hasLoaded ? 1 : 0)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        if !hasLoaded {
            ProgressView()
                .tint(RF.C.hibiscus)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        } else if let loadError, items.isEmpty {
            ErrorStateView(error: loadError) { Task { await load() } }
        } else if items.isEmpty {
            emptyState
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { listing in
                    ListingCard(listing: listing)
                }
            }
            .padding(EdgeInsets(top: 14, leading: RF.S.gutter, bottom: 20, trailing: RF.S.gutter))
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let hasAdvanced = filters.activeCount > 0
        let hasQuery = !filters.query.trimmingCharacters(in: .whitespaces).isEmpty
        if hasAdvanced || hasQuery {
            EmptyStateView(symbol: "magnifyingglass",
                           title: "Aucun article trouvé",
                           message: hasAdvanced
                               ? "Aucun article ne correspond à ces filtres. Essaie d'élargir la fourchette de prix."
                               : "Rien ne correspond à « \(filters.query) » pour l'instant.",
                           actionTitle: hasAdvanced ? "Réinitialiser les filtres" : "Effacer la recherche") {
                withAnimation {
                    if hasAdvanced { filters.resetAdvancedFilters() } else { filters.query = "" }
                }
            }
        } else {
            EmptyStateView(symbol: "tshirt",
                           title: "Pas encore d'articles ici",
                           message: "Pas encore d'articles dans cette catégorie près de chez toi. On te prévient dès qu'il y en a.")
        }
    }
}

extension ListingFilters {
    /// Resets the advanced filters of the sheet (price, condition, brand, negotiable, sort);
    /// category and search are kept, like the mockup's `resetFilters`.
    mutating func resetAdvancedFilters() {
        priceMin = 0
        priceMax = Self.catalogMaxPrice
        conditions = []
        brands = []
        negotiableOnly = false
        sort = .recent
    }
}

private struct DiscoverGridPreview: View {
    @State private var filters = ListingFilters()
    var body: some View {
        NavigationStack {
            DiscoverGridSection(filters: $filters, dropDate: .now.addingTimeInterval(5_000))
                .rfScreenBackground()
                .withAppRoutes()
        }
    }
}

#Preview {
    DiscoverGridPreview().previewEnvironment()
}
