import SwiftUI

/// Tab "Découvrir": native large title, Swipe / Grille segmented control, one discreet
/// "nouveaux arrivages" line, then the swipe deck or the filterable grid.
/// Alerts live in the "Boîte" tab, so there is no bell here.
struct DiscoverView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case swipe, grid
        var id: String { rawValue }
        var title: String { self == .swipe ? "Swipe" : "Grille" }
    }

    @Environment(AppStore.self) private var store

    @State private var mode: Mode = .swipe
    @State private var filters = ListingFilters()
    @State private var dropDate: Date?

    var body: some View {
        VStack(spacing: 0) {
            controls
            switch mode {
            case .swipe:
                DiscoverSwipeSection {
                    withAnimation(.snappy) { mode = .grid }
                }
                .transition(.opacity)
            case .grid:
                DiscoverGridSection(filters: $filters)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .rfScreenBackground()
        .navigationTitle("Découvrir")
        .navigationBarTitleDisplayMode(.large)
        .task {
            if dropDate == nil { dropDate = try? await store.repo.nextDropDate() }
            await store.refreshBadges()
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: RF.S.sm) {
            Picker("Affichage", selection: $mode.animation(.snappy(duration: 0.25))) {
                ForEach(Mode.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)
            DropCountdownLine(date: dropDate)
        }
        .padding(EdgeInsets(top: 4, leading: RF.S.gutter, bottom: RF.S.sm, trailing: RF.S.gutter))
        .sensoryFeedback(.selection, trigger: mode)
    }
}

#Preview {
    NavigationStack {
        DiscoverView()
            .withAppRoutes()
    }
    .previewEnvironment()
}
