import SwiftUI

/// "Grille" mode of Découvrir: search, category chips, "Filtres" chip with active-count badge,
/// result count and a 2-column grid of `ListingCard`, with pull-to-refresh.
struct DiscoverGridSection: View {
    @Binding var filters: ListingFilters

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
                searchField
                    .padding(.horizontal, RF.S.gutter)
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

    // MARK: Search (styled like the native search field)

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(RF.C.textDim)
                .accessibilityHidden(true)
            TextField("Rechercher", text: $filters.query)
                .font(RF.T.body)
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
                        .foregroundStyle(RF.C.textDim)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effacer la recherche")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(RF.C.paperDim, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            .padding(.vertical, RF.S.md)
        }
    }

    private func setGender(_ g: Gender?) {
        filters.gender = g
    }

    // MARK: Results

    private var resultCount: some View {
        let n = items.count
        return HStack(spacing: 6) {
            Text("\(Fmt.number(n)) article\(n > 1 ? "s" : "")")
                .font(RF.T.footnote)
                .foregroundStyle(RF.C.textDim)
                .monospacedDigit()
            if isLoading && hasLoaded {
                ProgressView().controlSize(.mini).tint(RF.C.textDim)
            }
            Spacer()
        }
        .padding(.horizontal, RF.S.gutter)
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
            .padding(EdgeInsets(top: RF.S.sm, leading: RF.S.gutter, bottom: RF.S.xl, trailing: RF.S.gutter))
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let query = filters.query.trimmingCharacters(in: .whitespaces)
        Group {
            if filters.activeCount > 0 {
                ContentUnavailableView {
                    Label("Aucun article", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Élargis tes filtres.")
                } actions: {
                    Button("Réinitialiser les filtres") {
                        withAnimation { filters.resetAdvancedFilters() }
                    }
                    .buttonStyle(.bordered)
                    .tint(RF.C.hibiscus)
                }
            } else if !query.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ContentUnavailableView("Rien ici pour l'instant", systemImage: "tshirt")
            }
        }
        .padding(.top, 40)
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
            DiscoverGridSection(filters: $filters)
                .rfScreenBackground()
                .withAppRoutes()
        }
    }
}

#Preview {
    DiscoverGridPreview().previewEnvironment()
}
