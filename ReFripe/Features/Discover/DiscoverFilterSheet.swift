import SwiftUI

/// "Filtres" sheet of the grid (mockup `filterSheetHTML`). Edits the grid's filters live, like the mockup:
/// the grid reloads behind the sheet and the main button shows the up-to-date result count.
struct DiscoverFilterSheet: View {
    @Binding var filters: ListingFilters
    let resultCount: Int
    let isLoading: Bool

    @Environment(\.dismiss) private var dismiss

    private let priceStep: FCFA = 500

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                priceGroup
                group("État") {
                    DiscoverWrapLayout {
                        ForEach(ItemCondition.allCases) { c in
                            DiscoverPill(title: c.label, selected: filters.conditions.contains(c)) {
                                toggle(c, in: \.conditions)
                            }
                        }
                    }
                }
                group("Marque") {
                    DiscoverWrapLayout {
                        ForEach(Catalog.brands, id: \.self) { b in
                            DiscoverPill(title: b, selected: filters.brands.contains(b)) {
                                toggle(b, in: \.brands)
                            }
                        }
                    }
                }
                negotiableToggle
                group("Trier par") {
                    DiscoverWrapLayout {
                        ForEach(ListingSort.allCases) { s in
                            DiscoverPill(title: s.discoverLabel, selected: filters.sort == s) {
                                filters.sort = s
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, RF.S.gutter)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .top, spacing: 0) { titleBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .background(RF.C.card)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(RF.R.sheet)
        .presentationBackground(RF.C.card)
    }

    // MARK: Pieces

    private var titleBar: some View {
        ZStack {
            Text("Filtres")
                .font(RF.F.display(16))
                .foregroundStyle(RF.C.text)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(RF.C.text)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(RF.C.paperDim))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fermer les filtres")
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 8)
        .padding(.horizontal, 6)
        .background(RF.C.card)
    }

    private var priceGroup: some View {
        group("Prix (FCFA)") {
            VStack(spacing: 10) {
                priceRow("Min", value: $filters.priceMin, range: 0...filters.priceMax)
                priceRow("Max", value: $filters.priceMax, range: filters.priceMin...ListingFilters.catalogMaxPrice)
            }
        }
    }

    private func priceRow(_ label: String, value: Binding<FCFA>, range: ClosedRange<FCFA>) -> some View {
        HStack {
            Text(label.uppercased())
                .font(RF.F.body(10.5, .bold))
                .kerning(0.4)
                .foregroundStyle(RF.C.textDim)
                .accessibilityHidden(true)
            Spacer()
            PriceStepper(value: value, step: priceStep, range: range, compact: true)
                .accessibilityLabel("Prix \(label.lowercased())imum")
        }
    }

    private var negotiableToggle: some View {
        Button {
            filters.negotiableOnly.toggle()
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(filters.negotiableOnly ? RF.C.money : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(filters.negotiableOnly ? RF.C.money : RF.C.line, lineWidth: 1.5)
                    )
                    .overlay {
                        if filters.negotiableOnly {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 20, height: 20)
                Text("Ouvert aux offres uniquement")
                    .font(RF.F.body(12, .semibold))
                    .foregroundStyle(RF.C.text)
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: filters.negotiableOnly)
        .accessibilityAddTraits(filters.negotiableOnly ? .isSelected : [])
        .accessibilityHint("Affiche seulement les articles dont la vendeuse accepte les offres")
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Réinitialiser") {
                withAnimation(.snappy) { filters.resetAdvancedFilters() }
            }
            .font(RF.F.body(12, .bold))
            .underline()
            .foregroundStyle(filters.activeCount > 0 ? RF.C.text : RF.C.textDim)
            .disabled(filters.activeCount == 0)
            .buttonStyle(.plain)

            RFButton(resultTitle, isLoading: isLoading) { dismiss() }
        }
        .padding(EdgeInsets(top: 12, leading: RF.S.gutter, bottom: 12, trailing: RF.S.gutter))
        .background(RF.C.card)
        .overlay(alignment: .top) { Rectangle().fill(RF.C.line).frame(height: 1) }
    }

    private var resultTitle: String {
        resultCount == 0 ? "Aucun résultat" : "Afficher \(resultCount) résultat\(resultCount > 1 ? "s" : "")"
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(RF.F.body(11.5, .bold))
                .foregroundStyle(RF.C.text)
                .accessibilityAddTraits(.isHeader)
            content()
        }
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
    /// Labels of the "Trier par" pills.
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
