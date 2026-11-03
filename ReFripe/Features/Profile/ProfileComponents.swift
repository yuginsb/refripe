import SwiftUI

// Pieces shared by ProfileTabView and SellerProfileView.

// MARK: - Profile header

/// Avatar, username + seal, « Cocody, Abidjan · depuis 8 mois », then ★ rating (n avis) / ventes / réponse.
/// When `onShowReviews` is set, the rating column is a button (opens the reviews list).
struct ProfileHeroView: View {
    let profile: UserProfile
    var onShowReviews: (() -> Void)? = nil

    private static let frFR = Locale(identifier: "fr_FR")

    private var hasRating: Bool { profile.rating > 0 }
    private var ratingText: String {
        hasRating ? profile.rating.formatted(.number.precision(.fractionLength(1)).locale(Self.frFR)) : "–"
    }
    private var reviewsText: String {
        profile.reviewCount == 0 ? "Pas d'avis" : "\(Fmt.number(profile.reviewCount)) avis"
    }
    private var responseText: String {
        guard let m = profile.responseTimeMinutes else { return "–" }
        return m < 60 ? "~\(m) min" : "~\(m / 60) h"
    }
    private var placeText: String {
        let place = profile.district.isEmpty ? profile.city : "\(profile.district), \(profile.city)"
        let s = Fmt.seniority(since: profile.memberSince)
        return s == "Nouveau" ? "\(place) · nouveau membre" : "\(place) · depuis \(s)"
    }

    var body: some View {
        VStack(spacing: 12) {
            Avatar(profile: profile, size: 80)

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(profile.username)
                        .font(RF.T.title)
                        .foregroundStyle(RF.C.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if profile.verified { VerifiedSeal(size: 16) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                Text(placeText)
                    .font(RF.T.subheadline)
                    .foregroundStyle(RF.C.textDim)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 0) {
                ratingColumn
                Divider().frame(height: 28).overlay(RF.C.line)
                stat(label: profile.salesCount > 1 ? "ventes" : "vente", a11y: "\(profile.salesCount) ventes") {
                    Text(Fmt.number(profile.salesCount))
                }
                Divider().frame(height: 28).overlay(RF.C.line)
                stat(label: "réponse",
                     a11y: profile.responseTimeMinutes.map { "Répond en \($0) minutes environ" } ?? "Temps de réponse inconnu") {
                    Text(responseText)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var ratingColumn: some View {
        let a11y = hasRating ? "Note \(ratingText) sur 5, \(reviewsText)" : "Pas encore de note"
        let column = stat(label: reviewsText, a11y: a11y) {
            HStack(spacing: 3) {
                if hasRating {
                    Image(systemName: "star.fill")
                        .font(RF.T.footnote)
                        .foregroundStyle(RF.C.marigold)
                }
                Text(ratingText)
            }
        }
        if let onShowReviews {
            Button(action: onShowReviews) {
                column
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RFPressStyle())
            .accessibilityHint("Voir les avis")
            .accessibilityIdentifier("profile.reviews")
        } else {
            column
        }
    }

    private func stat<Value: View>(label: String, a11y: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(spacing: 2) {
            value()
                .font(RF.T.number(.headline, weight: .semibold))
                .foregroundStyle(RF.C.text)
            Text(label)
                .font(RF.T.footnote)
                .foregroundStyle(RF.C.textDim)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
    }
}

/// « Réservé » / « Vendu » pill over a listing photo (nothing for active listings).
struct ListingStatusBadge: View {
    let status: ListingStatus

    init(status: ListingStatus) { self.status = status }

    /// v3: an active listing under a 2 h reservation (accepted offer) also shows « Réservé ».
    init(listing: Listing, now: Date = .now) {
        if listing.status == .active, let until = listing.reservedUntil, until > now {
            self.status = .reserved
        } else {
            self.status = listing.status
        }
    }

    var body: some View {
        switch status {
        case .reserved, .sold:
            Text(status == .sold ? "Vendu" : "Réservé")
                .font(RF.T.caption.weight(.semibold))
                .foregroundStyle(RF.C.textOnInk)
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(Capsule().fill(RF.C.ink1))
                .padding(8)
        default:
            EmptyView()
        }
    }
}

#Preview {
    ScrollView {
        ProfileHeroView(profile: UserProfile(id: DemoIDs.awa, username: "Awa_Style225", firstName: "Awa", city: "Abidjan",
                                             district: "Cocody", avatarURL: nil, verified: true, rating: 4.8, salesCount: 127,
                                             memberSince: .now.addingTimeInterval(-86_400 * 240), responseTimeMinutes: 10))
            .padding()
    }
    .rfScreenBackground()
    .previewEnvironment()
}
