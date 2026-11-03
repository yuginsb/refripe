import SwiftUI

/// Tab « Accueil » (v3): ReFripe wordmark + bell, search, Tout/Femme/Homme/Enfants/Bébés tabs,
/// a pinned row with the « Filtres » button and the quick chips (Ma taille, Moins de 5 000, Près de moi),
/// the « Coup de cœur » entry (swipe deck, pushed), then the 2-column grid. The grid is the only main screen.
struct DiscoverView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var filters = ListingFilters()
    @State private var items: [Listing] = []
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var loadError: Error?
    @State private var showFilters = false
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                searchField
                    .padding(EdgeInsets(top: RF.S.xs, leading: RF.S.gutter, bottom: RF.S.xs, trailing: RF.S.gutter))
                Section {
                    if trimmedQuery.isEmpty {
                        coupDeCoeurCard
                            .padding(EdgeInsets(top: RF.S.xs, leading: RF.S.gutter, bottom: RF.S.lg, trailing: RF.S.gutter))
                    }
                    feedHeader
                    content
                } header: {
                    filterBar
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable {
            await load()
            await store.refreshBadges()
        }
        .task(id: filters) {
            // Light debounce while typing; chip taps reload immediately.
            if hasLoaded && !filters.query.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                if Task.isCancelled { return }
            }
            await load()
        }
        .task { await store.refreshBadges() }
        .sheet(isPresented: $showFilters) {
            DiscoverFilterSheet(filters: $filters, resultCount: items.count, isLoading: isLoading,
                                city: store.me?.city ?? "Abidjan")
        }
        .rfScreenBackground()
        .navigationTitle("Accueil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { wordmark }
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
            ToolbarItem(placement: .topBarTrailing) { bellButton }
        }
    }

    // MARK: Header

    private var wordmark: some View {
        Wordmark(size: 20)
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
    }

    private var bellButton: some View {
        let unread = store.unreadNotifications
        return Button {
            searchFocused = false
            router.push(.notifications)
        } label: {
            Image(systemName: "bell")
                .foregroundStyle(RF.C.text)
                .overlay(alignment: .topTrailing) {
                    if unread > 0 {
                        Circle()
                            .fill(RF.C.hibiscus)
                            .frame(width: 8, height: 8)
                            .offset(x: 2, y: -1)
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(unread > 0 ? "Notifications, \(unread) non lue\(unread > 1 ? "s" : "")" : "Notifications")
        .accessibilityIdentifier("home.notifications")
    }

    // MARK: Search (styled like the native search field)

    private var trimmedQuery: String { filters.query.trimmingCharacters(in: .whitespaces) }

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
                        .frame(minWidth: 32, minHeight: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effacer la recherche")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .background(RF.C.paperDim, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { searchFocused = true }
    }

    // MARK: Pinned bar: category tabs + Filtres / quick chips

    private var filterBar: some View {
        VStack(spacing: 0) {
            DiscoverCategoryTabs(selection: $filters.gender)
            chipRow
        }
        .background(RF.C.paper)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            Chip("Filtres", selected: filters.activeCount > 0, badge: filters.activeCount,
                 symbol: "slider.horizontal.3") {
                searchFocused = false
                showFilters = true
            }
            .fixedSize()
            Divider().frame(height: 22)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let label = quick.mySizeLabel {
                        Chip("Ma taille · \(label)", selected: quick.sizeOn(filters)) {
                            withAnimation(.snappy) { quick.toggleSize(&filters) }
                        }
                    }
                    Chip("Moins de \(Fmt.number(DiscoverQuickFilters.budget))", selected: quick.budgetOn(filters)) {
                        withAnimation(.snappy) { quick.toggleBudget(&filters) }
                    }
                    if quick.myDistrict != nil {
                        Chip("Près de moi", selected: quick.nearOn(filters), symbol: "location") {
                            withAnimation(.snappy) { quick.toggleNear(&filters) }
                        }
                    }
                }
                .padding(.trailing, RF.S.gutter)
            }
        }
        .padding(.leading, RF.S.gutter)
        .padding(.vertical, RF.S.sm)
    }

    private var quick: DiscoverQuickFilters {
        DiscoverQuickFilters(preferences: store.preferences, me: store.me)
    }

    // MARK: Coup de cœur entry

    private var coupDeCoeurCard: some View {
        Button {
            searchFocused = false
            router.push(.coupDeCoeur)
        } label: {
            HStack(spacing: RF.S.md) {
                thumbStack
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coup de cœur")
                        .font(RF.T.headline)
                        .foregroundStyle(RF.C.text)
                    Text("Swipe les nouveautés")
                        .font(RF.T.footnote)
                        .foregroundStyle(RF.C.textDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(RF.T.footnote.weight(.semibold))
                    .foregroundStyle(RF.C.textDim)
            }
            .padding(RF.S.md)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .rfCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(RFPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coup de cœur, swipe les nouveautés")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.coupDeCoeur")
    }

    /// Two overlapping thumbnails from the feed (or a heart when the feed is empty).
    private var thumbStack: some View {
        let shown = Array(items.prefix(2))
        return ZStack {
            if shown.isEmpty {
                RoundedRectangle(cornerRadius: RF.R.sm, style: .continuous)
                    .fill(RF.C.hibiscus.opacity(0.10))
                    .frame(width: 44, height: 56)
                Image(systemName: "heart.fill").foregroundStyle(RF.C.hibiscus)
            } else {
                ForEach(Array(shown.enumerated()), id: \.element.id) { pair in
                    ListingPhotoView(photo: pair.element.photos.first, listingId: pair.element.id)
                        .frame(width: 40, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: RF.R.sm, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: RF.R.sm, style: .continuous)
                            .strokeBorder(RF.C.card, lineWidth: 2))
                        .rotationEffect(.degrees(pair.offset == 0 ? 6 : -6))
                        .offset(x: pair.offset == 0 ? 8 : -6)
                        .zIndex(Double(pair.offset == 0 ? 1 : 0))
                }
            }
        }
        .frame(width: 60, height: 60)
        .accessibilityHidden(true)
    }

    // MARK: Results

    private var feedHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(quick.title(for: filters))
                .font(RF.T.headline)
                .foregroundStyle(RF.C.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if isLoading && hasLoaded {
                ProgressView().controlSize(.mini).tint(RF.C.textDim)
            }
            if hasLoaded {
                Text("\(Fmt.number(items.count)) article\(items.count > 1 ? "s" : "")")
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.textDim)
                    .monospacedDigit()
            }
        }
        .padding(EdgeInsets(top: 0, leading: RF.S.gutter, bottom: RF.S.sm, trailing: RF.S.gutter))
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
            LazyVGrid(columns: columns, spacing: RF.S.lg) {
                ForEach(items) { listing in
                    DiscoverListingCard(listing: listing)
                }
            }
            .padding(EdgeInsets(top: RF.S.xs, leading: RF.S.gutter, bottom: RF.S.xl, trailing: RF.S.gutter))
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        Group {
            if filters.activeCount > 0 {
                ContentUnavailableView {
                    Label("Aucun article", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Élargis tes filtres.")
                } actions: {
                    Button("Réinitialiser") {
                        withAnimation { filters.resetAdvancedFilters() }
                    }
                    .buttonStyle(.bordered)
                    .tint(RF.C.hibiscus)
                }
            } else if !trimmedQuery.isEmpty {
                ContentUnavailableView.search(text: trimmedQuery)
            } else {
                ContentUnavailableView("Aucun article", systemImage: "tshirt")
            }
        }
        .padding(.top, 40)
    }

    // MARK: Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await store.repo.feed(filters: filters, preferences: store.preferences)
            if Task.isCancelled { return }
            // Own listings never show in the feed (v3), whatever the backend returns.
            let me = store.me?.id
            withAnimation(.snappy(duration: 0.25)) { items = result.filter { $0.sellerId != me } }
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            loadError = error
        }
        hasLoaded = true
    }
}

// MARK: - Category tabs (plain underlined tabs)

struct DiscoverCategoryTabs: View {
    @Binding var selection: Gender?
    @Namespace private var underline

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                tab("Tout", value: nil)
                ForEach(Gender.allCases) { g in
                    tab(g.label, value: g)
                }
            }
            .padding(.horizontal, RF.S.gutter)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(RF.C.line).frame(height: 0.5)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func tab(_ title: String, value: Gender?) -> some View {
        let selected = selection == value
        return Button {
            withAnimation(.snappy(duration: 0.25)) { selection = value }
        } label: {
            Text(title)
                .font(RF.T.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? RF.C.text : RF.C.textDim)
                .lineLimit(1)
                .frame(minHeight: 44)
                .overlay(alignment: .bottom) {
                    if selected {
                        Rectangle()
                            .fill(RF.C.hibiscus)
                            .frame(height: 2)
                            .matchedGeometryEffect(id: "underline", in: underline)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - « Coup de cœur » (route `.coupDeCoeur`)

/// The swipe deck as a secondary, pushed experience (with its first-use coach).
struct CoupDeCoeurView: View {
    @Environment(Router.self) private var router

    var body: some View {
        DiscoverSwipeSection {
            router.pop()
        }
        .rfScreenBackground()
        .navigationTitle("Coup de cœur")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

#Preview {
    NavigationStack {
        DiscoverView()
            .withAppRoutes()
    }
    .previewEnvironment()
}
