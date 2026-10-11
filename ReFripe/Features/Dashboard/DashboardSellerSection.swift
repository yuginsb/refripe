import SwiftUI
import Charts

/// Seller side of the dashboard (mockup `sellerDashboardSection`).
struct DashboardSellerSection: View {
    let data: DashboardData

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var progressShown = false

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashboardGreeting(symbol: "rosette", title: greetingTitle, subtitle: "Ce mois-ci")

            if let stats = data.stats {
                LazyVGrid(columns: columns, spacing: 10) {
                    StatTile(title: "Ventes", value: Fmt.number(stats.sales), delta: stats.salesDelta, symbol: "bag")
                    StatTile(title: "Gagnés", value: Fmt.fcfa(stats.revenue), delta: stats.revenueDelta, symbol: "banknote")
                    StatTile(title: "Vues", value: Fmt.number(stats.views), delta: stats.viewsDelta, symbol: "eye")
                    StatTile(title: "Favoris", value: Fmt.number(stats.favorites), delta: stats.favoritesDelta, symbol: "heart")
                }
                .padding(.bottom, 16)
            }

            ordersCard

            if let stats = data.stats {
                goalCard(stats)
                tierCard(stats)
                weekChartCard(stats)
            } else {
                DashCard {
                    Text("Tes statistiques de vente apparaîtront ici après ta première annonce.")
                        .font(RF.F.body(11))
                        .foregroundStyle(RF.C.textDim)
                }
                .padding(.bottom, 12)
            }

            recommendationsList
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9).delay(0.15)) { progressShown = true }
        }
    }

    private var greetingTitle: String {
        let name = store.me?.firstName ?? ""
        guard let stats = data.stats else { return "Salut \(name), voici tes ventes" }
        if stats.revenue >= stats.monthlyGoal, stats.monthlyGoal > 0 { return "Objectif atteint, bravo \(name) !" }
        if stats.revenueDelta.hasPrefix("+") { return "Bravo \(name), ton meilleur mois jusqu'ici" }
        return "Salut \(name), voici ton mois"
    }

    // MARK: Orders to process (sorted by urgency)

    private var ordersCard: some View {
        let orders = data.ordersToProcess
        return DashCard {
            HStack {
                DashCardLabel("Commandes à traiter")
                Spacer()
                if !orders.isEmpty {
                    Text("\(orders.count)")
                        .font(RF.F.body(10, .extraBold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Circle().fill(RF.C.hibiscus))
                        .accessibilityLabel("\(orders.count) commandes")
                }
            }
            .padding(.bottom, 4)
            if orders.isEmpty {
                Text("Aucune commande en cours")
                    .font(RF.F.body(10.5))
                    .foregroundStyle(RF.C.textDim)
                    .padding(.top, 6)
            } else {
                ForEach(orders) { order in
                    Button { router.push(.order(order.id)) } label: {
                        ProfileOrderLine(order: order, subtitle: "\(order.buyerName) · \(Fmt.relative(order.history.last?.at ?? order.createdAt))")
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(order.status == .awaitingShipment ? "À expédier" : "Voir la commande")
                    if order.id != orders.last?.id { Divider().overlay(RF.C.line) }
                }
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: Monthly goal (ring)

    private func goalCard(_ stats: SellerStats) -> some View {
        let fraction = stats.monthlyGoal > 0 ? min(1, Double(stats.revenue) / Double(stats.monthlyGoal)) : 0
        let pct = Int((fraction * 100).rounded())
        let remaining = max(0, stats.monthlyGoal - stats.revenue)
        return DashCard {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(RF.C.text.opacity(0.1), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: progressShown ? fraction : 0)
                        .stroke(RF.C.money, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(pct)%")
                        .font(RF.F.mono(13, .semibold))
                        .foregroundStyle(RF.C.text)
                }
                .frame(width: 66, height: 66)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    DashCardLabel("Objectif du mois — \(Fmt.fcfa(stats.monthlyGoal))")
                    Text("\(Fmt.fcfa(stats.revenue)) gagnés")
                        .font(RF.F.mono(15, .semibold))
                        .foregroundStyle(RF.C.moneyDeep)
                    Text(remaining > 0 ? "Encore \(Fmt.fcfa(remaining)) pour atteindre ton objectif." : "Objectif atteint ! Vise plus haut le mois prochain.")
                        .font(RF.F.body(10.5))
                        .foregroundStyle(RF.C.textDim)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(pct) pour cent")
        .padding(.bottom, 12)
    }

    // MARK: Seller tier (gold bar)

    private func tierCard(_ stats: SellerStats) -> some View {
        let fraction = stats.tierSalesNeeded > 0 ? min(1, Double(stats.tierSalesNow) / Double(stats.tierSalesNeeded)) : 0
        let remaining = max(0, stats.tierSalesNeeded - stats.tierSalesNow)
        return DashCard {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "rosette").font(.system(size: 12, weight: .semibold)).foregroundStyle(RF.C.marigold)
                    Text("Palier \(stats.tier)")
                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(RF.C.marigold)
                    Text(stats.nextTier)
                }
                .font(RF.F.body(11.5, .bold))
                .foregroundStyle(RF.C.text)
                Spacer()
                Text("\(stats.tierSalesNow)/\(stats.tierSalesNeeded) ventes")
                    .font(RF.F.mono(11))
                    .foregroundStyle(RF.C.textDim)
            }
            .padding(.bottom, 9)
            DashProgressBar(fraction: progressShown ? fraction : 0, color: RF.C.marigold)
            Text(remaining > 0
                 ? "Encore \(remaining) vente\(remaining > 1 ? "s" : "") pour débloquer la mise en avant automatique dans Découvrir."
                 : "Palier \(stats.nextTier) débloqué : tes annonces sont mises en avant dans Découvrir.")
                .font(RF.F.body(10.5))
                .foregroundStyle(RF.C.textDim)
                .lineSpacing(2)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .padding(.bottom, 12)
    }

    // MARK: Weekly views (Swift Charts)

    private func weekChartCard(_ stats: SellerStats) -> some View {
        DashCard {
            HStack {
                DashCardLabel("Vues cette semaine")
                Spacer()
                Text(Fmt.number(stats.weekViews.reduce(0, +)))
                    .font(RF.F.mono(11))
                    .foregroundStyle(RF.C.textDim)
            }
            .padding(.bottom, 14)
            WeekViewsChart(values: stats.weekViews, revealed: progressShown)
        }
        .padding(.bottom, 6)
    }

    // MARK: Recommendations

    @ViewBuilder private var recommendationsList: some View {
        if !data.recommendations.isEmpty {
            DashCardLabel("Recommandations pour toi")
                .padding(.top, 22)
                .padding(.bottom, 12)
            ForEach(data.recommendations) { reco in
                DashRecoCard(symbol: reco.symbol, title: reco.title, message: reco.body,
                             cta: reco.listingId == nil ? nil : reco.cta,
                             action: recoAction(reco))
            }
        }
    }

    private func recoAction(_ reco: SellerRecommendation) -> (() -> Void)? {
        guard let id = reco.listingId else { return nil }
        return { router.push(.product(id)) }
    }
}

// MARK: - Weekly chart

struct WeekViewsChart: View {
    let values: [Int]
    var revealed: Bool = true

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
                y: .value("Vues", Double(revealed ? point.views : 0)),
                width: .fixed(20)
            )
            .foregroundStyle(point.views == peak ? RF.C.hibiscus : RF.C.marigold)
            .cornerRadius(5)
            .annotation(position: .top, spacing: 3) {
                Text(Fmt.number(point.views))
                    .font(RF.F.mono(9, .semibold))
                    .foregroundStyle(RF.C.hibiscus)
                    .opacity(point.views == peak && revealed ? 1 : 0)
            }
            .accessibilityLabel(point.day)
            .accessibilityValue("\(point.views) vues")
        }
        .chartXScale(domain: Self.days)
        .chartYScale(domain: 0...max(1, Double(peak) * 1.2))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    Text(String((value.as(String.self) ?? "").prefix(1)))
                        .font(RF.F.body(9, .bold))
                        .foregroundStyle(RF.C.textDim)
                }
            }
        }
        .frame(height: 100)
        .animation(.easeOut(duration: 0.7), value: revealed)
    }
}

// MARK: - Shared dashboard bits

struct DashboardGreeting: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(RF.C.hibiscus)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RF.F.display(14.5))
                    .foregroundStyle(RF.C.text)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(RF.F.body(11))
                    .foregroundStyle(RF.C.textDim)
            }
        }
        .padding(.bottom, 18)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct DashProgressBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        Capsule()
            .fill(RF.C.text.opacity(0.1))
            .frame(height: 8)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * max(0, min(1, fraction)))
                }
            }
            .clipShape(Capsule())
            .accessibilityHidden(true)
    }
}

/// Mockup `.reco-card`: marigold icon, title, body, hibiscus CTA with arrow.
struct DashRecoCard: View {
    let symbol: String
    let title: String
    let message: String
    var cta: String?
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { card }
                .buttonStyle(RFPressStyle(scale: 0.98))
                .accessibilityHint(cta ?? "")
        } else {
            card
        }
    }

    private var card: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(RF.C.marigold)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(RF.F.body(12.5, .bold))
                    .foregroundStyle(RF.C.text)
                Text(message)
                    .font(RF.F.body(11))
                    .foregroundStyle(RF.C.textDim)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let cta {
                    HStack(spacing: 5) {
                        Text(cta)
                        Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold))
                    }
                    .font(RF.F.body(10.5, .extraBold))
                    .foregroundStyle(RF.C.hibiscus)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13)
        .background(RF.C.paperDim, in: RoundedRectangle(cornerRadius: RF.R.lg, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: RF.R.lg, style: .continuous))
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            WeekViewsChart(values: [80, 140, 95, 210, 260, 190, 300]).padding()
        }
        .rfScreenBackground()
    }
    .previewEnvironment()
}
