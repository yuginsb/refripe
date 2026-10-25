import SwiftUI

/// Sign-up + onboarding, presented full screen by RootView while `store.needsOnboarding`.
///
/// Three phases:
///  1. **auth** (no session yet): method → phone/OTP → minimal profile (`SignupScreens.swift`);
///  2. **preferences** (signed in, onboarding not completed): categories (required) → sizes → brands;
///  3. **intro**: the 5-page welcome guide. Finishing it sets `onboardingCompleted` + `introGuideSeen`,
///     which makes `store.needsOnboarding` false and closes the cover by itself.
/// An existing account signing back in with a completed onboarding closes the cover right after `didSignIn`.
struct OnboardingFlowView: View {
    @Environment(AppStore.self) private var store
    @State private var model = OnboardingModel()

    private enum Phase: Hashable { case auth, preferences, intro }

    private var phase: Phase {
        // While a sign-in is being finalised (`didSignIn` loads the preferences), stay on the auth phase
        // so an already-onboarded account doesn't flash the category step before the cover closes.
        if store.me == nil || model.isAuthenticating { return .auth }
        return model.showIntro ? .intro : .preferences
    }

    var body: some View {
        ZStack {
            switch phase {
            case .auth:
                SignupAuthStack(model: model)
                    .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)).combined(with: .opacity))
            case .preferences:
                OnboardingPreferencesStack(model: model)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .intro:
                IntroGuideView(onFinish: finish)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.35), value: phase)
        .interactiveDismissDisabled()
    }

    private func finish() {
        store.updatePreferences { p in
            p.onboardingCompleted = true
            p.introGuideSeen = true
        }
        // No reset needed: the cover is dismissed and its @State discarded with it.
    }
}

// MARK: - Flow state

@MainActor
@Observable
final class OnboardingModel {
    enum AuthStep: Hashable { case phone, profile }
    enum PreferenceStep: Hashable { case sizes, brands }

    var authPath: [AuthStep] = []
    var preferencePath: [PreferenceStep] = []

    var method: SignupMethod = .phone
    var country: OnboardingCountry = .ci
    var phoneDigits = ""
    var signup = SignupProfileInput()

    /// True from the moment credentials are submitted until `store.didSignIn` has returned.
    var isAuthenticating = false
    var showIntro = false

    // Preference answers (seeded once from `store.preferences` when the phase starts).
    var preferencesSeeded = false
    var categories: Set<Gender> = []
    var sizes: [SizeType: String] = [:]
    var brands: Set<String> = []

    /// E.164 number sent to the backend, e.g. "+2250707070707".
    var fullPhone: String { "+\(country.dialCode)\(phoneDigits)" }
    var isPhoneComplete: Bool { phoneDigits.count == country.digits }

    /// Called after `sendOTP`/`verifyOTP`/`signInWithApple` returned. Existing profile → session;
    /// nil → the account exists in auth but has no profile yet → profile step.
    func finishAuth(_ profile: UserProfile?, store: AppStore) async {
        if let profile {
            await store.didSignIn(profile)
            Haptics.success()
            isAuthenticating = false
        } else {
            isAuthenticating = false
            if method == .phone { signup.city = country.city }
            authPath.append(.profile)
        }
    }

    func seedPreferences(from prefs: UserPreferences) {
        guard !preferencesSeeded else { return }
        preferencesSeeded = true
        categories = prefs.categories
        sizes = prefs.sizes
        brands = prefs.brands
    }
}

enum OnboardingCountry: String, CaseIterable, Identifiable, Hashable {
    case ci, sn
    var id: String { rawValue }
    var dialCode: String { self == .ci ? "225" : "221" }
    var name: String { self == .ci ? "Côte d'Ivoire" : "Sénégal" }
    var flag: String { self == .ci ? "🇨🇮" : "🇸🇳" }
    /// National number length.
    var digits: Int { self == .ci ? 10 : 9 }
    var placeholder: String { self == .ci ? "07 12 34 56 78" : "77 123 45 67" }
    var city: String { self == .ci ? "Abidjan" : "Dakar" }
    private var groups: [Int] { self == .ci ? [2, 2, 2, 2, 2] : [2, 3, 2, 2] }

    /// "0707070707" → "07 07 07 07 07"
    func format(_ digits: String) -> String {
        var out = ""
        var idx = digits.startIndex
        for g in groups {
            guard idx < digits.endIndex else { break }
            let end = digits.index(idx, offsetBy: g, limitedBy: digits.endIndex) ?? digits.endIndex
            if !out.isEmpty { out.append(" ") }
            out.append(contentsOf: digits[idx..<end])
            idx = end
        }
        if idx < digits.endIndex { out.append(" "); out.append(contentsOf: digits[idx...]) }
        return out
    }
}

// MARK: - Preferences phase (mockup screenOnboardingCategory / Sizes / Brands)

private struct OnboardingPreferencesStack: View {
    @Bindable var model: OnboardingModel
    @Environment(AppStore.self) private var store
    @State private var confirmSwitchAccount = false

    var body: some View {
        NavigationStack(path: $model.preferencePath) {
            OnboardingStepScaffold(step: 0, tagline: "Au moins une, modifiable ensuite.") {
                CategoryPreferenceGrid(categories: $model.categories)
            } actions: {
                RFButton("Continuer") { model.preferencePath.append(.sizes) }
                    .disabled(model.categories.isEmpty)
            }
            .navigationTitle("Que recherches-tu ?")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Changer de compte") { confirmSwitchAccount = true }
                        .font(RF.T.subheadline)
                        .foregroundStyle(RF.C.textDim)
                }
            }
            .confirmationDialog("Te déconnecter et utiliser un autre compte ?", isPresented: $confirmSwitchAccount, titleVisibility: .visible) {
                Button("Changer de compte", role: .destructive) {
                    Task {
                        await store.signOut()
                        model.preferencesSeeded = false
                        model.preferencePath = []
                        model.authPath = []
                    }
                }
                Button("Annuler", role: .cancel) {}
            }
            .navigationDestination(for: OnboardingModel.PreferenceStep.self) { step in
                switch step {
                case .sizes: sizesStep
                case .brands: brandsStep
                }
            }
        }
        .onAppear { model.seedPreferences(from: store.preferences) }
    }

    private var sizesStep: some View {
        OnboardingStepScaffold(step: 1, tagline: "Facultatif. Pour des nouveautés à ta taille.") {
            SizePreferenceRows(sizes: $model.sizes)
        } actions: {
            OnboardingActions(skip: { model.preferencePath.append(.brands) }, primaryTitle: "Continuer") {
                model.preferencePath.append(.brands)
            }
        }
        .navigationTitle("Tes tailles")
    }

    private var brandsStep: some View {
        OnboardingStepScaffold(step: 2, tagline: "Facultatif. Celles que tu portes le plus.") {
            BrandPreferenceChips(brands: $model.brands)
        } actions: {
            OnboardingActions(skip: savePreferencesAndContinue, primaryTitle: "Terminer", primary: savePreferencesAndContinue)
        }
        .navigationTitle("Marques préférées")
    }

    private func savePreferencesAndContinue() {
        let categories = model.categories, sizes = model.sizes, brands = model.brands
        store.updatePreferences { p in
            p.categories = categories
            p.sizes = sizes
            p.brands = brands
        }
        Haptics.success()
        model.showIntro = true
    }
}

/// Paper screen with the 3 progress dots, a tagline, scrollable content and pinned bottom actions.
private struct OnboardingStepScaffold<Content: View, Actions: View>: View {
    let step: Int
    let tagline: String
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                OnboardingProgressDots(count: 3, current: step)
                    .padding(.bottom, RF.S.xl)
                OnboardingTagline(tagline)
                    .padding(.bottom, RF.S.lg)
                content
            }
            .padding(.horizontal, RF.S.gutter)
            .padding(.top, RF.S.lg)
            .padding(.bottom, RF.S.lg)
        }
        .safeAreaInset(edge: .bottom) {
            actions
                .padding(.horizontal, RF.S.gutter)
                .padding(.top, RF.S.md)
                .padding(.bottom, RF.S.sm)
                .background(RF.C.paper)
        }
        .navigationBarTitleDisplayMode(.inline)
        .rfScreenBackground()
    }
}

#Preview("Onboarding (Awa connectée → préférences)") {
    OnboardingFlowView().previewEnvironment()
}
