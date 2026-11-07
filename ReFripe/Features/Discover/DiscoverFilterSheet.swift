import SwiftUI

/// « Filtres » sheet of Accueil: Type d'article, Taille, Budget, Commune, État, Ouvert aux offres, Trier par.
/// Edits the feed's filters live: the grid reloads behind the sheet and the main button shows the
/// up-to-date count (« Afficher N articles »).
struct DiscoverFilterSheet: View {
    @Binding var filters: ListingFilters
    let resultCount: Int
    let isLoading: Bool
    var city: String = "Abidjan"

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Group {
                Section("Type") {
                    chips(ItemType.allCases, label: { $0.filterLabel }, keyPath: \.itemTypes)
                }

                Section("Taille") {
                    chips(DiscoverFilterOptions.letterSizes, label: { $0 }, keyPath: \.sizes)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pointures")
                            .font(RF.T.footnote)
                            .foregroundStyle(RF.C.textDim)
                        chips(DiscoverFilterOptions.shoeSizes, label: { $0 }, keyPath: \.sizes)
                    }
                }

                Section("Budget") {
                    DiscoverWrapLayout {
                        ForEach(DiscoverFilterOptions.budgets, id: \.self) { max in
                            Chip("Moins de \(Fmt.number(max))", selected: isBudget(max)) { setBudget(max) }
                        }
                        Chip("Tous les prix", selected: isBudget(ListingFilters.catalogMaxPrice)) {
                            setBudget(ListingFilters.catalogMaxPrice)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Commune") {
                    chips(districtOptions, label: { $0 }, keyPath: \.districts)
                }

                Section("État") {
                    chips(ItemCondition.allCases, label: { $0.label }, keyPath: \.conditions)
                }

                Section {
                    Toggle("Ouvert aux offres", isOn: $filters.negotiableOnly)
                    Picker("Tri", selection: $filters.sort) {
                        ForEach(ListingSort.allCases) { s in
                            Text(s.discoverLabel).tag(s)
                        }
                    }
                }
                            }
                .listRowBackground(RF.C.card)
            }
            .font(RF.T.body)
            .scrollContentBackground(.hidden)
            .background(RF.C.paper)
            .navigationTitle("Filtres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer les filtres", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Réinitialiser") {
                        withAnimation(.snappy) { filters.resetAdvancedFilters() }
                    }
                    .disabled(filters.activeCount == 0)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
        .tint(RF.C.hibiscus)
        .sensoryFeedback(.selection, trigger: filters.negotiableOnly)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Pieces

    private func chips<T: Hashable>(_ options: [T], label: @escaping (T) -> String,
                                    keyPath: WritableKeyPath<ListingFilters, Set<T>>) -> some View {
        DiscoverWrapLayout {
            ForEach(options, id: \.self) { option in
                Chip(label(option), selected: filters[keyPath: keyPath].contains(option)) {
                    toggle(option, in: keyPath)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// The user's city districts, plus any district already selected elsewhere (e.g. « Près de moi »).
    private var districtOptions: [String] {
        var list = DiscoverFilterOptions.districts(city: city)
        for d in filters.districts.sorted() where !list.contains(d) { list.insert(d, at: 0) }
        return list
    }

    private var footer: some View {
        RFButton(resultTitle, isLoading: isLoading) { dismiss() }
            .padding(EdgeInsets(top: RF.S.md, leading: RF.S.gutter, bottom: RF.S.md, trailing: RF.S.gutter))
            .background(RF.C.paper)
    }

    private var resultTitle: String {
        resultCount == 0 ? "Aucun article" : "Afficher \(Fmt.number(resultCount)) article\(resultCount > 1 ? "s" : "")"
    }

    // MARK: Budget

    private func isBudget(_ max: FCFA) -> Bool {
        filters.priceMin == 0 && filters.priceMax == max
    }

    private func setBudget(_ max: FCFA) {
        filters.priceMin = 0
        filters.priceMax = max
    }

    private func toggle<T: Hashable>(_ value: T, in keyPath: WritableKeyPath<ListingFilters, Set<T>>) {
        if filters[keyPath: keyPath].contains(value) {
            filters[keyPath: keyPath].remove(value)
        } else {
            filters[keyPath: keyPath].insert(value)
        }
    }
}

extension ListingSort {
    /// Labels of the « Trier par » picker.
    var discoverLabel: String {
        switch self {
        case .recent: "Plus récents"
        case .priceAsc: "Prix croissant"
        case .priceDesc: "Prix décroissant"
        case .popular: "Populaires"
        }
    }
}

private struct DiscoverFilterSheetPreview: View {
    @State private var filters = ListingFilters(conditions: [.excellent], sort: .priceAsc)
    var body: some View {
        Color.clear.sheet(isPresented: .constant(true)) {
            DiscoverFilterSheet(filters: $filters, resultCount: 6, isLoading: false)
        }
    }
}

#Preview {
    DiscoverFilterSheetPreview().previewEnvironment()
}
