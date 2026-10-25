import SwiftUI
import Charts

/// Profil › Statistiques (`.dashboard` route): the seller dashboard — this month's numbers, monthly goal,
/// seller tier, weekly views and recommendations. Purchases and orders live in Boîte › Commandes.
struct DashboardView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var stats: SellerStats?
    @State private var recommendations: [SellerRecommendation] = []
    @State private var isLoaded = false
    @State private var loadError: Error?

    var body: some View {
        Group {
            if isLoaded {
                list
            } else if let loadError {
                ErrorStateView(error: loadError) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rfScreenBackground()
        .navigationTitle("Statistiques")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var list: some View {
        List {
            if let stats {
                monthSection(stats)
                goalSection(stats)
                tierSection(stats)
                viewsSection(stats)
            } else {
                Section {
                    ContentUnavailableView("Pas encore de statistiques", systemImage: "chart.bar",
                                           description: Text("Elles apparaissent après ta première annonce."))
                }
            }
            recommendationsSection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(24)
        .refreshable { await load() }
    }

    // MARK: Sections

    private func monthSection(_ stats: SellerStats) -> some View {
        Section {
            statRow("Ventes", Fmt.number(stats.sales), delta: stats.salesDelta)
            statRow("Gains", Fmt.fcfa(stats.revenue), delta: stats.revenueDelta)
            statRow("Vues", Fmt.number(stats.views), delta: stats.viewsDelta)
            statRow("Favoris", Fmt.number(stats.favorites), delta: stats.favoritesDelta)
        } header: {
            header("Ce mois-ci")
        }
    }

    private func statRow(_ title: String, _ value: String, delta: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(RF.T.body)
                .foregroundStyle(RF.C.text)
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(RF.T.number(.headline, weight: .semibold))
                    .foregroundStyle(RF.C.text)
                if !delta.isEmpty {
                    Text(delta)
                        .font(RF.T.caption.monospacedDigit())
                        .foregroundStyle(RF.C.textDim)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func goalSection(_ stats: SellerStats) -> some View {
        let fraction = stats.monthlyGoal > 0 ? min(1, Double(stats.revenue) / Double(stats.monthlyGoal)) : 0
        let remaining = max(0, stats.monthlyGoal - stats.revenue)
        return Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.fcfa(stats.revenue))
                        .font(RF.T.number(.title3, weight: .semibold))
                        .foregroundStyle(RF.C.text)
                    Text("sur \(Fmt.fcfa(stats.monthlyGoal))")
                        .font(RF.T.subheadline.monospacedDigit())
                        .foregroundStyle(RF.C.textDim)
                    Spacer()
                    Text("\(Int((fraction * 100).rounded())) %")
                        .font(RF.T.subheadline.monospacedDigit())
                        .foregroundStyle(RF.C.textDim)
                }
                ProgressView(value: fraction)
                    .tint(RF.C.money)
                Text(remaining > 0 ? "Encore \(Fmt.fcfa(remaining))." : "Objectif atteint.")
                    .font(RF.T.footnote.monospacedDigit())
                    .foregroundStyle(RF.C.textDim)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        } header: {
            header("Objectif du mois")
        }
    }

    private func tierSection(_ stats: SellerStats) -> some View {
        let fraction = stats.tierSalesNeeded > 0 ? min(1, Double(stats.tierSalesNow) / Double(stats.tierSalesNeeded)) : 0
        let remaining = max(0, stats.tierSalesNeeded - stats.tierSalesNow)
        return Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(stats.tier) → \(stats.nextTier)")
                        .font(RF.T.headline)
                        .foregroundStyle(RF.C.text)
                    Spacer()
                    Text("\(stats.tierSalesNow)/\(stats.tierSalesNeeded) ventes")
                        .font(RF.T.subheadline.monospacedDigit())
                        .foregroundStyle(RF.C.textDim)
                }
                ProgressView(value: fraction)
                    .tint(RF.C.hibiscus)
                Text(remaining > 0
                     ? "Encore \(remaining) vente\(remaining > 1 ? "s" : "") pour être mise en avant."
                     : "Tes annonces sont mises en avant.")
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.textDim)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        } header: {
            header("Palier")
        }
    }

    private func viewsSection(_ stats: SellerStats) -> some View {
        Section {
            WeekViewsChart(values: stats.weekViews)
                .padding(.vertical, 8)
        } header: {
            HStack {
                header("Vues cette semaine")
                Spacer()
                Text(Fmt.number(stats.weekViews.reduce(0, +)))
                    .font(RF.T.footnote.monospacedDigit())
                    .foregroundStyle(RF.C.textDim)
            }
        }
    }

    @ViewBuilder private var recommendationsSection: some View {
        if !recommendations.isEmpty {
            Section {
                ForEach(recommendations) { reco in
                    if let id = reco.listingId {
                        Button { router.push(.product(id)) } label: { recoRow(reco, chevron: true) }
                            .buttonStyle(.plain)
                    } else {
                        recoRow(reco, chevron: false)
                    }
                }
            } header: {
                header("Conseils")
            }
        }
    }

    private func recoRow(_ reco: SellerRecommendation, chevron: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: reco.symbol)
                .font(RF.T.body)
                .foregroundStyle(RF.C.text)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(reco.title)
                    .font(RF.T.subheadline.weight(.semibold))
                    .foregroundStyle(RF.C.text)
                Text(reco.body)
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.textDim)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(RF.T.footnote.weight(.semibold))
                    .foregroundStyle(RF.C.textDim.opacity(0.6))
                    .padding(.top, 2)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(RF.T.footnote.weight(.semibold))
            .foregroundStyle(RF.C.textDim)
            .textCase(nil)
    }

    // MARK: Data

    private func load() async {
        do {
            let s = try await store.repo.sellerStats()
            let recos = (try? await store.repo.recommendations()) ?? []
            stats = s
            recommendations = recos
            isLoaded = true
            loadError = nil
        } catch {
            if isLoaded { store.show(error) } else { loadError = error }
        }
    }
}

// MARK: - Weekly chart

struct WeekViewsChart: View {
    let values: [Int]

    private static let days = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]

    private struct Point: Identifiable {
        let id: Int
        let day: String
        let views: Int
    }

    private var points: [Point] {
        values.prefix(7).enumerated().map { Point(id: $0.offset, day: Self.days[$0.offset], views: $0.element) }
    }

    var body: some View {
        let peak = values.max() ?? 0
        Chart(points) { point in
            BarMark(
                x: .value("Jour", point.day),
                y: .value("Vues", Double(point.views)),
                width: .fixed(18)
            )
            .foregroundStyle(point.views == peak ? RF.C.hibiscus : RF.C.text.opacity(0.18))
            .cornerRadius(4)
            .accessibilityLabel(point.day)
            .accessibilityValue("\(point.views) vues")
        }
        .chartXScale(domain: Self.days)
        .chartYScale(domain: 0...max(1, Double(peak) * 1.1))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    Text(String((value.as(String.self) ?? "").prefix(1)))
                        .font(RF.T.caption)
                        .foregroundStyle(RF.C.textDim)
                }
            }
        }
        .frame(height: 120)
    }
}

#Preview {
    NavigationStack { DashboardView().withAppRoutes() }
        .previewEnvironment()
}
