import SwiftUI

// MARK: - Preference editor (Réglages › Préférences)

enum PreferenceEditorKind: String, Identifiable, Hashable, CaseIterable {
    case categories, sizes, brands
    var id: String { rawValue }

    var title: String {
        switch self { case .categories: "Catégories"; case .sizes: "Tailles"; case .brands: "Marques" }
    }
    var symbol: String {
        switch self { case .categories: "square.grid.2x2"; case .sizes: "ruler"; case .brands: "tag" }
    }
    /// One line under the editor.
    var hint: String {
        switch self {
        case .categories: "Au moins une. Elles passent en premier dans Découvrir."
        case .sizes: "Pour les alertes « nouveau dans ta taille »."
        case .brands: "Facultatif."
        }
    }

    static func summary(categories: Set<Gender>) -> String {
        let labels = Gender.allCases.filter(categories.contains).map(\.label)
        return labels.isEmpty ? "Aucune" : labels.joined(separator: ", ")
    }
    static func summary(sizes: [SizeType: String]) -> String {
        let parts = OnboardingSizeFields.types.compactMap { t in sizes[t].map { "\(t.label) \($0)" } }
        return parts.isEmpty ? "Non renseignées" : parts.joined(separator: " · ")
    }
    static func summary(brands: Set<String>) -> String {
        let ordered = Catalog.brands.filter(brands.contains) + brands.subtracting(Catalog.brands).sorted()
        return ordered.isEmpty ? "Toutes" : ordered.joined(separator: ", ")
    }

    func summary(_ prefs: UserPreferences) -> String {
        switch self {
        case .categories: Self.summary(categories: prefs.categories)
        case .sizes: Self.summary(sizes: prefs.sizes)
        case .brands: Self.summary(brands: prefs.brands)
        }
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
                VStack(alignment: .leading, spacing: 16) {
                    switch kind {
                    case .categories: CategoryPreferenceGrid(categories: $categories)
                    case .sizes: SizePreferenceRows(sizes: $sizes)
                    case .brands: BrandPreferenceChips(brands: $brands)
                    }
                    Text(kind.hint)
                        .font(RF.T.footnote)
                        .foregroundStyle(RF.C.textDim)
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
                        .disabled(!canSave)
                }
            }
        }
        .tint(RF.C.hibiscus)
        .onAppear {
            guard !seeded else { return }
            seeded = true
            categories = store.preferences.categories
            sizes = store.preferences.sizes
            brands = store.preferences.brands
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
