import SwiftUI

/// « Avis » of a member (pushed from the rating of a profile): average, then one row per review.
struct ReviewsListView: View {
    let userId: UUID

    @Environment(AppStore.self) private var store

    @State private var reviews: [Review]?
    @State private var reviewers: [UUID: UserProfile] = [:]
    @State private var profile: UserProfile?
    @State private var loadError: Error?

    private static let frFR = Locale(identifier: "fr_FR")

    var body: some View {
        Group {
            if let reviews {
                if reviews.isEmpty {
                    EmptyStateView(symbol: "star", title: "Pas encore d'avis",
                                   message: "Ils arrivent après chaque vente.")
                } else {
                    list(reviews)
                }
            } else if let loadError {
                ErrorStateView(error: loadError) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .rfScreenBackground()
        .navigationTitle("Avis")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func list(_ reviews: [Review]) -> some View {
        List {
            Group {
            Section {
                summary(reviews)
            }
            Section {
                ForEach(reviews) { review in
                    row(review)
                }
            }
                    }
            .listRowBackground(RF.C.card)
        }
        .listStyle(.insetGrouped)
    }

    private func summary(_ reviews: [Review]) -> some View {
        let computed = Double(reviews.map(\.rating).reduce(0, +)) / Double(max(1, reviews.count))
        let stored = profile?.rating ?? 0
        let average = stored > 0 ? stored : computed
        let count = max(profile?.reviewCount ?? 0, reviews.count)
        let text = average.formatted(.number.precision(.fractionLength(1)).locale(Self.frFR))
        return HStack(spacing: 12) {
            Text(text)
                .font(RF.T.number(.largeTitle))
                .foregroundStyle(RF.C.text)
            VStack(alignment: .leading, spacing: 4) {
                RatingStars(rating: average, size: 14)
                Text("\(Fmt.number(count)) avis")
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.textDim)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Note \(text) sur 5, \(count) avis")
    }

    private func row(_ review: Review) -> some View {
        let reviewer = reviewers[review.reviewerId]
        let name = reviewer?.username ?? "Membre ReFripe"
        return HStack(alignment: .top, spacing: 12) {
            Avatar(profile: reviewer, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name)
                        .font(RF.T.subheadline.weight(.semibold))
                        .foregroundStyle(RF.C.text)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Fmt.relative(review.createdAt))
                        .font(RF.T.footnote)
                        .foregroundStyle(RF.C.textDim)
                }
                RatingStars(rating: Double(review.rating))
                if !review.comment.isEmpty {
                    Text(review.comment)
                        .font(RF.T.subheadline)
                        .foregroundStyle(RF.C.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(review.rating) étoiles sur 5, \(Fmt.relative(review.createdAt)). \(review.comment)")
    }

    private func load() async {
        do {
            let items = try await store.repo.reviews(userId: userId)
            let ids = Array(Set(items.map(\.reviewerId)))
            var people: [UUID: UserProfile] = [:]
            if !ids.isEmpty { people = (try? await store.repo.profiles(ids: ids)) ?? [:] }
            store.cache(people)
            profile = await store.profile(userId)
            reviewers = people
            reviews = items.sorted { $0.createdAt > $1.createdAt }
            loadError = nil
        } catch {
            if reviews == nil { loadError = error } else { store.show(error) }
        }
    }
}

#Preview {
    NavigationStack { ReviewsListView(userId: DemoIDs.awa) }
        .previewEnvironment()
}
