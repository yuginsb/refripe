import SwiftUI

/// Welcome guide (mockup `screenIntroGuide` + `introGuideSteps`): 5 swipeable pages, one per tab,
/// progress dots, a mini tab bar preview, "Passer" / "Suivant" / "Commencer".
/// Shown at the end of onboarding and from the profile ("Revoir le guide").
struct IntroGuideView: View {
    var onFinish: () -> Void = {}

    @State private var page = 0

    private struct Step: Identifiable {
        let id: Int
        let symbol: String
        let tabLabel: String
        let title: String
        let body: String
    }

    private static let steps: [Step] = [
        Step(id: 0, symbol: "house", tabLabel: "Découvrir", title: "Découvrir",
             body: "Swipe à droite pour garder, à gauche pour passer."),
        Step(id: 1, symbol: "heart", tabLabel: "Envies", title: "Envies",
             body: "Tes coups de cœur, avec une alerte si le prix baisse."),
        Step(id: 2, symbol: "plus.circle", tabLabel: "Vendre", title: "Vendre",
             body: "Quelques photos, un prix, c'est en ligne."),
        Step(id: 3, symbol: "tray", tabLabel: "Boîte", title: "Boîte",
             body: "Messages, commandes et notifications au même endroit."),
        Step(id: 4, symbol: "person", tabLabel: "Profil", title: "Profil",
             body: "Ton dressing, tes avis et tes statistiques."),
    ]

    private var isLast: Bool { page == Self.steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressDots(count: Self.steps.count, current: page)
                .padding(.top, RF.S.lg)

            TabView(selection: $page) {
                ForEach(Self.steps) { step in
                    pageContent(step).tag(step.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy, value: page)

            navPreview
                .padding(.horizontal, RF.S.gutter)

            OnboardingActions(skip: finish, primaryTitle: isLast ? "Commencer" : "Suivant") {
                if isLast { finish() } else { withAnimation(.snappy) { page += 1 } }
            }
            .padding(.horizontal, RF.S.gutter)
            .padding(.top, RF.S.xl)
            .padding(.bottom, RF.S.md)
        }
        .rfScreenBackground()
        .sensoryFeedback(.selection, trigger: page)
    }

    private func pageContent(_ step: Step) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            Image(systemName: step.symbol)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(RF.C.hibiscus)
                .frame(height: 56)
                .padding(.bottom, RF.S.xl)
                .accessibilityHidden(true)
            Text(step.title)
                .font(RF.T.title)
                .foregroundStyle(RF.C.text)
                .multilineTextAlignment(.center)
                .padding(.bottom, RF.S.sm)
                .accessibilityAddTraits(.isHeader)
            Text(step.body)
                .font(RF.T.body)
                .foregroundStyle(RF.C.textDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, RF.S.xxl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.title). \(step.body)")
        .accessibilityHint("Page \(step.id + 1) sur \(Self.steps.count)")
    }

    /// Mini tab bar with the current tab highlighted.
    private var navPreview: some View {
        HStack(spacing: 0) {
            ForEach(Self.steps) { step in
                let active = step.id == page
                Button {
                    withAnimation(.snappy) { page = step.id }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: active ? step.symbol + ".fill" : step.symbol)
                            .font(.system(size: 18))
                            .frame(height: 22)
                        Text(step.tabLabel)
                            .font(RF.T.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(active ? RF.C.hibiscus : RF.C.textDim)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Onglet \(step.tabLabel)")
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(RF.C.line).frame(height: 0.5) }
        .animation(.easeOut(duration: 0.15), value: page)
    }

    private func finish() {
        Haptics.success()
        onFinish()
    }
}

#Preview {
    IntroGuideView().previewEnvironment()
}
