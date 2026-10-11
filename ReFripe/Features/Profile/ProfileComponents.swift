import SwiftUI

// Pieces shared by ProfileTabView, SellerProfileView and DashboardView (agent D).

// MARK: - Trust header (mockup `.profile-hero`)

struct ProfileHeroView: View {
    let profile: UserProfile

    private static let frFR = Locale(identifier: "fr_FR")

    private var hasRating: Bool { profile.rating > 0 }
    private var ratingText: String {
        hasRating ? profile.rating.formatted(.number.precision(.fractionLength(1)).locale(Self.frFR)) : "—"
    }
    private var responseText: String {
        guard let m = profile.responseTimeMinutes else { return "—" }
        return m < 60 ? "~\(m) min" : "~\(m / 60) h"
    }
    private var placeText: String {
        profile.district.isEmpty ? profile.city : "\(profile.district), \(profile.city)"
    }
    private var seniorityText: String {
        let s = Fmt.seniority(since: profile.memberSince)
        return s == "Nouveau" ? "nouveau membre" : "sur ReFripe depuis \(s)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Avatar(profile: profile, size: 72)
                .padding(.bottom, 12)

            HStack(spacing: 6) {
                Text(profile.username)
                    .font(RF.F.display(16))
                    .foregroundStyle(RF.C.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if profile.verified { VerifiedBadge(size: 14) }
            }
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            HStack(spacing: 4) {
                Image(systemName: "mappin").font(.system(size: 10))
                Text("\(placeText) · \(seniorityText)")
            }
            .font(RF.F.body(11.5))
            .foregroundStyle(RF.C.textDim)
            .multilineTextAlignment(.center)

            if hasRating {
                RatingStars(rating: profile.rating)
                    .padding(.top, 8)
            }

            HStack(alignment: .top, spacing: 26) {
                stat(value: ratingText, label: "Note", symbol: hasRating ? "star.fill" : nil,
                     a11y: hasRating ? "Note \(ratingText) sur 5" : "Pas encore de note")
                stat(value: Fmt.number(profile.salesCount), label: "Ventes", symbol: nil,
                     a11y: "\(profile.salesCount) ventes")
                stat(value: responseText, label: "Réponse", symbol: nil,
                     a11y: profile.responseTimeMinutes.map { "Répond en \($0) minutes environ" } ?? "Temps de réponse inconnu")
            }
            .padding(.vertical, 18)

            badges
        }
        .padding(EdgeInsets(top: 24, leading: RF.S.gutter, bottom: 16, trailing: RF.S.gutter))
        .frame(maxWidth: .infinity)
    }

    private func stat(value: String, label: String, symbol: String?, a11y: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(RF.C.marigold)
                }
                Text(value)
                    .font(RF.F.mono(17, .medium))
                    .foregroundStyle(RF.C.text)
                    .monospacedDigit()
            }
            Text(label.uppercased())
                .font(RF.F.body(9.5))
                .kerning(0.38)
                .foregroundStyle(RF.C.textDim)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
    }

    @ViewBuilder private var badges: some View {
        let items = badgeItems
        if !items.isEmpty {
            HStack(spacing: 7) {
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(RF.C.money)
                        Text(item.title)
                    }
                    .font(RF.F.body(10, .bold))
                    .foregroundStyle(RF.C.text)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 11)
                    .background(Capsule().fill(RF.C.paperDim))
                }
            }
        }
    }

    private struct TrustBadge: Hashable {
        let symbol: String
        let title: String
    }

    private var badgeItems: [TrustBadge] {
        var out: [TrustBadge] = []
        if profile.verified { out.append(TrustBadge(symbol: "checkmark.seal.fill", title: "Vendeuse vérifiée")) }
        if profile.salesCount >= 100 { out.append(TrustBadge(symbol: "storefront", title: "Boutique Pro")) }
        if let m = profile.responseTimeMinutes, m <= 15 { out.append(TrustBadge(symbol: "bolt.fill", title: "Répond vite")) }
        return out
    }
}

/// Five stars with halves, marigold.
struct RatingStars: View {
    let rating: Double
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: symbol(for: i))
                    .font(.system(size: size))
                    .foregroundStyle(RF.C.marigold)
            }
        }
        .accessibilityHidden(true)
    }

    private func symbol(for index: Int) -> String {
        let value = rating - Double(index - 1)
        if value >= 0.75 { return "star.fill" }
        if value >= 0.25 { return "star.leadinghalf.filled" }
        return "star"
    }
}

// MARK: - Dashboard entry (mockup `.dash-cta`)

struct DashboardCTAButton: View {
    let subtitle: String
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RF.R.lg, style: .continuous)
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tableau de bord")
                        .font(RF.F.body(13, .extraBold))
                    Text(subtitle)
                        .font(RF.F.body(11))
                        .opacity(0.9)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(LinearGradient(colors: [RF.C.hibiscus, RF.C.marigold], startPoint: .topLeading, endPoint: .bottomTrailing), in: shape)
            .contentShape(shape)
        }
        .buttonStyle(RFPressStyle())
        .accessibilityLabel("Tableau de bord, \(subtitle)")
    }
}

// MARK: - Compact order row (mockup `.co-row`)

struct ProfileOrderLine: View {
    let order: Order
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            ListingPhotoView(photo: order.listingPhoto, listingId: order.listingId)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: RF.R.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(order.listingTitle)
                    .font(RF.F.body(12.5, .bold))
                    .foregroundStyle(RF.C.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(RF.F.body(10.5))
                    .foregroundStyle(RF.C.textDim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 5) {
                Text(Fmt.fcfa(order.itemPrice))
                    .font(RF.F.mono(12.5))
                    .foregroundStyle(RF.C.text)
                StatusPill(status: order.status)
            }
            .fixedSize()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension OrderStatus {
    /// Still in progress (shown in "à traiter" / "en cours" lists).
    var isOpenForDashboard: Bool { ![.completed, .cancelled, .refunded].contains(self) }
}

/// Paper-dim card used by the dashboard and the profile (mockup `.dash-card`).
struct DashCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RF.C.paperDim, in: RoundedRectangle(cornerRadius: RF.R.lg, style: .continuous))
    }
}

/// Bold small label inside a dash card (mockup `.dc-label`).
struct DashCardLabel: View {
    let text: String
    var symbol: String?

    init(_ text: String, symbol: String? = nil) {
        self.text = text
        self.symbol = symbol
    }

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(RF.C.marigold)
            }
            Text(text)
                .font(RF.F.body(11.5, .bold))
                .foregroundStyle(RF.C.text)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            ProfileHeroView(profile: UserProfile(id: DemoIDs.awa, username: "Awa_Style225", firstName: "Awa", city: "Abidjan",
                                                 district: "Cocody", avatarURL: nil, verified: true, rating: 4.8, salesCount: 127,
                                                 memberSince: .now.addingTimeInterval(-86_400 * 240), responseTimeMinutes: 10))
            DashboardCTAButton(subtitle: "4 ventes · 3 achats ce mois-ci") {}
                .padding(.horizontal, 16)
        }
    }
    .rfScreenBackground()
    .previewEnvironment()
}
