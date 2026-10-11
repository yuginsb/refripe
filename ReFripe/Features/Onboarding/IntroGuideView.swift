import SwiftUI

/// Welcome guide (mockup `screenIntroGuide` + `introGuideSteps`): 5 swipeable pages, one per tab,
/// progress dots, a mini tab bar preview, "Passer" / "Suivant" / "C'est parti !".
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
             body: "Swipe à droite pour ajouter un article à tes envies, à gauche pour passer. Le mode grille permet de tout parcourir et de filtrer par catégorie."),
        Step(id: 1, symbol: "heart", tabLabel: "Envies", title: "Tes envies",
             body: "Retrouve tous les articles likés au même endroit, avec une alerte automatique dès que leur prix baisse."),
        Step(id: 2, symbol: "plus", tabLabel: "Vendre", title: "Vendre un article",
             body: "Prends tes photos, remplis quelques infos — catégorie, taille, prix — et publie ton annonce en quelques minutes."),
        Step(id: 3, symbol: "bubble.left", tabLabel: "Messages", title: "Messages",
             body: "Discute directement avec les vendeuses et les acheteuses pour négocier un prix ou organiser la remise."),
        Step(id: 4, symbol: "person", tabLabel: "Profil", title: "Profil & tableau de bord",
             body: "Gère tes ventes et tes achats au même endroit : statistiques, commandes en cours, objectifs du mois."),
    ]

    private var isLast: Bool { page == Self.steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            Text("Bienvenue sur ReFripe")
                .font(RF.F.display(15))
                .foregroundStyle(RF.C.text)
                .padding(.top, 14)
                .padding(.bottom, 18)
                .accessibilityAddTraits(.isHeader)

            OnboardingProgressDots(count: Self.steps.count, current: page)

            TabView(selection: $page) {
                ForEach(Self.steps) { step in
                    pageContent(step).tag(step.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy, value: page)

            navPreview
                .padding(.horizontal, RF.S.gutter)

            OnboardingActions(skip: finish, primaryTitle: isLast ? "C'est parti !" : "Suivant") {
                if isLast { finish() } else { withAnimation(.snappy) { page += 1 } }
            }
            .padding(.horizontal, RF.S.gutter)
            .padding(.top, 22)
            .padding(.bottom, 12)
        }
        .rfScreenBackground()
        .sensoryFeedback(.selection, trigger: page)
    }

    private func pageContent(_ step: Step) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            Image(systemName: step.symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Circle().fill(RF.C.marigold))
                .padding(.bottom, 18)
                .accessibilityHidden(true)
            Text(step.title)
                .font(RF.F.display(17))
                .foregroundStyle(RF.C.text)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)
            OnboardingTagline(step.body)
                .padding(.horizontal, 8)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, RF.S.gutter)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.title). \(step.body)")
        .accessibilityHint("Page \(step.id + 1) sur \(Self.steps.count)")
    }

    /// Mini tab bar with the current tab highlighted (mockup `.intro-nav-preview`).
    private var navPreview: some View {
        HStack(spacing: 0) {
            ForEach(Self.steps) { step in
                let active = step.id == page
                Button {
                    withAnimation(.snappy) { page = step.id }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: step.symbol)
                            .font(.system(size: 18))
                            .frame(height: 20)
                        Text(step.tabLabel)
                            .font(RF.F.body(9, .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(active ? RF.C.hibiscus : RF.C.textDim)
                    .opacity(active ? 1 : 0.5)
                    .scaleEffect(active ? 1.1 : 1)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Onglet \(step.tabLabel)")
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .background(RF.C.paperDim, in: RoundedRectangle(cornerRadius: RF.R.lg, style: .continuous))
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
