import SwiftUI

/// "Filtres" sheet of the grid: native Form (sections, steppers, toggle, picker) with chips for
/// conditions and brands. Edits the grid's filters live: the grid reloads behind the sheet and the
/// main button shows the up-to-date result count.
struct DiscoverFilterSheet: View {
    @Binding var filters: ListingFilters
    let resultCount: Int
    let isLoading: Bool

    @Environment(\.dismiss) private var dismiss

    private let priceStep: FCFA = 500

    var body: some View {
        NavigationStack {
            Form {
                Section("Prix") {
                    Stepper(value: $filters.priceMin, in: 0...filters.priceMax, step: priceStep) {
                        LabeledContent("Minimum") {
                            Text(Fmt.fcfa(filters.priceMin)).font(RF.T.price(.body, weight: .regular))
                        }
                    }
                    Stepper(value: $filters.priceMax, in: filters.priceMin...ListingFilters.catalogMaxPrice, step: priceStep) {
                        LabeledContent("Maximum") {
                            Text(Fmt.fcfa(filters.priceMax)).font(RF.T.price(.body, weight: .regular))
                        }
                    }
                }

                Section("État") {
                    DiscoverWrapLayout {
                        ForEach(ItemCondition.allCases) { c in
                            Chip(c.label, selected: filters.conditions.contains(c)) {
                                toggle(c, in: \.conditions)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Marque") {
                    DiscoverWrapLayout {
                        ForEach(Catalog.brands, id: \.self) { b in
                            Chip(b, selected: filters.brands.contains(b)) {
                                toggle(b, in: \.brands)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle("Ouvert aux offres", isOn: $filters.negotiableOnly)
                    Picker("Trier par", selection: $filters.sort) {
                        ForEach(ListingSort.allCases) { s in
                            Text(s.discoverLabel).tag(s)
                        }
                    }
                }
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

    private var footer: some View {
        RFButton(resultTitle, isLoading: isLoading) { dismiss() }
            .padding(EdgeInsets(top: RF.S.md, leading: RF.S.gutter, bottom: RF.S.md, trailing: RF.S.gutter))
            .background(RF.C.paper)
    }

    private var resultTitle: String {
        resultCount == 0 ? "Aucun résultat" : "Afficher \(resultCount) résultat\(resultCount > 1 ? "s" : "")"
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
    /// Labels of the "Trier par" picker.
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
