import SwiftUI
import AuthenticationServices
import CryptoKit

// MARK: - Auth phase navigation

/// Method (root) → phone/OTP → profile.
struct SignupAuthStack: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        NavigationStack(path: $model.authPath) {
            SignupMethodScreen(model: model)
                .navigationDestination(for: OnboardingModel.AuthStep.self) { step in
                    switch step {
                    case .phone: SignupPhoneScreen(model: model)
                    case .profile: SignupProfileScreen(model: model)
                    }
                }
        }
        // Light status bar over the ink brand screen; system light appearance (keyboard, menus) elsewhere.
        // RF colors are fixed, so only system chrome follows this.
        .preferredColorScheme(model.authPath.isEmpty ? .dark : .light)
    }
}

// MARK: - Apple nonce

/// Random nonce for Sign in with Apple: the raw value goes to Supabase, its SHA-256 to Apple.
enum AppleSignInNonce {
    static func random(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()   // cryptographically secure on Apple platforms
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - 0a · Method (mockup screenSignupMethod)

struct SignupMethodScreen: View {
    @Bindable var model: OnboardingModel
    @Environment(AppStore.self) private var store
    @State private var currentNonce: String?

    var body: some View {
        ZStack {
            RF.C.ink0.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 40)
                brand
                Spacer(minLength: 32)
                methods
                if store.isDemo {
                    Text("Démo : 07 07 07 07 07, code \(DemoIDs.otpCode)")
                        .font(RF.T.footnote.monospacedDigit())
                        .foregroundStyle(RF.C.textOnInkDim)
                        .multilineTextAlignment(.center)
                        .padding(.top, RF.S.lg)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            if model.isAuthenticating {
                RF.C.scrim.ignoresSafeArea()
                ProgressView().controlSize(.large).tint(RF.C.textOnInk)
                    .accessibilityLabel("Connexion en cours")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var brand: some View {
        VStack(spacing: 12) {
            (Text("Re").foregroundStyle(RF.C.textOnInk) + Text("Fripe").foregroundStyle(RF.C.marigold))
                .font(RF.T.brand(44))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel("ReFripe")
                .accessibilityAddTraits(.isHeader)
            Text("La fripe près de chez toi.")
                .font(RF.T.body)
                .foregroundStyle(RF.C.textOnInkDim)
                .multilineTextAlignment(.center)
        }
    }

    private var methods: some View {
        VStack(spacing: 10) {
            SignInWithAppleButton(.continue) { request in
                let nonce = AppleSignInNonce.random()
                currentNonce = nonce
                request.requestedScopes = [.fullName]
                request.nonce = AppleSignInNonce.sha256(nonce)
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
            .disabled(model.isAuthenticating)

            RFButton("Continuer avec mon numéro", symbol: "phone") {
                model.method = .phone
                model.authPath.append(.phone)
            }
            .disabled(model.isAuthenticating)

            HStack(spacing: 10) {
                SoonMethodButton(title: "Google")
                SoonMethodButton(title: "Facebook")
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                store.show("La connexion avec Apple a échoué. Réessaie.")
                Haptics.error()
                return
            }
            if let given = credential.fullName?.givenName, model.signup.firstName.isEmpty {
                model.signup.firstName = given
            }
            Task { await signInWithApple(idToken: idToken, nonce: nonce) }
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
            if store.isDemo {
                // Simulator without an Apple ID / no team configured: the demo repository ignores the token.
                Task { await signInWithApple(idToken: "demo", nonce: currentNonce ?? "") }
            } else {
                store.show(error)
                Haptics.error()
            }
        }
    }

    private func signInWithApple(idToken: String, nonce: String) async {
        model.method = .apple
        model.isAuthenticating = true
        do {
            let profile = try await store.repo.signInWithApple(idToken: idToken, nonce: nonce)
            await model.finishAuth(profile, store: store)
        } catch {
            model.isAuthenticating = false
            store.show(error)
            Haptics.error()
        }
    }
}

/// Discreet outlined method button on ink, "bientôt" (Google / Facebook are not wired on the backend yet).
private struct SoonMethodButton: View {
    let title: String
    @Environment(AppStore.self) private var store

    var body: some View {
        Button {
            Haptics.warning()
            store.show("Bientôt disponible. Utilise Apple ou ton numéro.")
        } label: {
            VStack(spacing: 1) {
                Text(title).font(RF.T.subheadline.weight(.semibold))
                Text("Bientôt").font(RF.T.caption)
                    .foregroundStyle(RF.C.textOnInkDim)
            }
            .foregroundStyle(RF.C.textOnInk)
            .frame(maxWidth: .infinity, minHeight: 50)
            .overlay(RoundedRectangle(cornerRadius: RF.R.md, style: .continuous).strokeBorder(RF.C.lineOnInk, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
        }
        .buttonStyle(RFPressStyle())
        .accessibilityLabel("Continuer avec \(title), bientôt disponible")
    }
}

// MARK: - 0b · Phone + OTP (mockup screenSignupPhone)

struct SignupPhoneScreen: View {
    @Bindable var model: OnboardingModel
    @Environment(AppStore.self) private var store

    @State private var codeSent = false
    @State private var code = ""
    @State private var isSending = false
    @State private var isVerifying = false
    @State private var resendIn = 0
    @State private var sendCount = 0
    @FocusState private var focus: Field?

    private enum Field: Hashable { case phone, code }

    /// Demo repository uses a 4-digit code (mockup); Supabase SMS OTPs have 6 digits.
    private var codeLength: Int { store.isDemo ? DemoIDs.otpCode.count : 6 }

    private var phoneBinding: Binding<String> {
        Binding(
            get: { model.country.format(model.phoneDigits) },
            set: { model.phoneDigits = String($0.filter(\.isNumber).prefix(model.country.digits)) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                OnboardingTagline("Il sert aussi pour Wave et Orange Money.")
                    .padding(.bottom, RF.S.xl)

                OnboardingField("Numéro mobile", content: {
                    HStack(spacing: 10) {
                        countryMenu
                        Rectangle().fill(RF.C.line).frame(width: 1, height: 22)
                        TextField(model.country.placeholder, text: phoneBinding)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .font(RF.T.body.monospacedDigit())
                            .focused($focus, equals: .phone)
                            .disabled(codeSent)
                            .accessibilityLabel("Numéro mobile")
                    }
                }, trailing: {
                    if codeSent { FieldTag(text: "Code envoyé", ok: true) }
                })
                .padding(.bottom, 14)

                if codeSent {
                    otpSection
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    RFButton("Recevoir le code", isLoading: isSending) {
                        Task { await sendCode() }
                    }
                    .disabled(!model.isPhoneComplete)
                    .padding(.top, 6)
                    if store.isDemo {
                        Text("Démo : 07 07 07 07 07 pour retrouver Awa.")
                            .font(RF.T.footnote)
                            .foregroundStyle(RF.C.textDim)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                    }
                }
            }
            .padding(.horizontal, RF.S.gutter)
            .padding(.vertical, 22)
            .animation(.snappy(duration: 0.3), value: codeSent)
        }
        .scrollDismissesKeyboard(.interactively)
        .rfScreenBackground()
        .navigationTitle("Ton numéro")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if !codeSent { focus = .phone } }
        .onChange(of: code) { _, newValue in
            let digits = String(newValue.filter(\.isNumber).prefix(codeLength))
            if digits != newValue { code = digits; return }
            if digits.count == codeLength, !isVerifying { Task { await verify() } }
        }
        .task(id: sendCount) {
            guard sendCount > 0 else { return }
            resendIn = 30
            while resendIn > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                resendIn -= 1
            }
        }
    }

    private var countryMenu: some View {
        Menu {
            ForEach(OnboardingCountry.allCases) { country in
                Button {
                    model.country = country
                    model.phoneDigits = String(model.phoneDigits.prefix(country.digits))
                } label: {
                    if country == model.country {
                        Label("\(country.flag) \(country.name) (+\(country.dialCode))", systemImage: "checkmark")
                    } else {
                        Text("\(country.flag) \(country.name) (+\(country.dialCode))")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.country.flag)
                Text("+\(model.country.dialCode)")
                    .font(RF.T.body.monospacedDigit())
                    .foregroundStyle(RF.C.text)
                Image(systemName: "chevron.down")
                    .font(RF.T.caption.weight(.semibold))
                    .foregroundStyle(RF.C.textDim)
            }
        }
        .disabled(codeSent)
        .accessibilityLabel("Indicatif : \(model.country.name), plus \(model.country.dialCode)")
    }

    private var otpSection: some View {
        VStack(spacing: 0) {
            Text(store.isDemo
                 ? "Code envoyé au +\(model.country.dialCode) \(model.country.format(model.phoneDigits)) (démo : \(DemoIDs.otpCode))"
                 : "Code envoyé au +\(model.country.dialCode) \(model.country.format(model.phoneDigits))")
                .font(RF.T.footnote.monospacedDigit())
                .foregroundStyle(RF.C.textDim)
                .multilineTextAlignment(.center)
                .padding(.bottom, RF.S.md)

            otpBoxes
                .padding(.bottom, 18)

            RFButton("Valider", isLoading: isVerifying) { Task { await verify() } }
                .disabled(code.count < codeLength)

            HStack(spacing: 18) {
                Button("Modifier le numéro") {
                    codeSent = false
                    code = ""
                    focus = .phone
                }
                Button(resendIn > 0 ? "Renvoyer le code (\(resendIn) s)" : "Renvoyer le code") {
                    Task { await sendCode() }
                }
                .disabled(resendIn > 0 || isSending)
                .contentTransition(.numericText(countsDown: true))
            }
            .font(RF.T.subheadline)
            .foregroundStyle(RF.C.hibiscus)
            .padding(.top, RF.S.lg)
        }
    }

    /// Visible digit boxes over a hidden field that owns the keyboard and the SMS autofill.
    private var otpBoxes: some View {
        let digits = Array(code)
        return ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focus, equals: .code)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(width: 1, height: 1)
                .opacity(0.02)
                .accessibilityLabel("Code de vérification à \(codeLength) chiffres")

            HStack(spacing: codeLength > 4 ? 8 : 10) {
                ForEach(0..<codeLength, id: \.self) { i in
                    let isActive = focus == .code && i == min(digits.count, codeLength - 1)
                    Text(i < digits.count ? String(digits[i]) : "")
                        .font(RF.T.number(.title2, weight: .semibold))
                        .foregroundStyle(RF.C.text)
                        .frame(width: 44, height: 52)
                        .background(RF.C.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(isActive ? RF.C.hibiscus : RF.C.line, lineWidth: isActive ? 1.5 : 1)
                        )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focus = .code }
            .accessibilityHidden(true)
        }
        .animation(.easeOut(duration: 0.12), value: code)
    }

    private func sendCode() async {
        guard model.isPhoneComplete, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await store.repo.sendOTP(phone: model.fullPhone)
            code = ""
            withAnimation { codeSent = true }
            sendCount += 1
            focus = .code
            Haptics.tap()
        } catch {
            store.show(error)
            Haptics.error()
        }
    }

    private func verify() async {
        guard code.count == codeLength, !isVerifying else { return }
        isVerifying = true
        defer { isVerifying = false }
        model.method = .phone
        model.isAuthenticating = true
        do {
            let profile = try await store.repo.verifyOTP(phone: model.fullPhone, code: code)
            focus = nil
            await model.finishAuth(profile, store: store)
        } catch {
            model.isAuthenticating = false
            code = ""
            store.show(error)
            Haptics.error()
        }
    }
}

// MARK: - 0c · Minimal profile (mockup screenSignupProfile)

struct SignupProfileScreen: View {
    @Bindable var model: OnboardingModel
    @Environment(AppStore.self) private var store
    @State private var isSaving = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case firstName, username, district }

    private var trimmedUsername: String { model.signup.username.trimmingCharacters(in: .whitespaces) }
    private var isValid: Bool {
        !model.signup.firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && trimmedUsername.count >= 3
            && !model.signup.district.trimmingCharacters(in: .whitespaces).isEmpty
            && model.signup.isAdultConfirmed
    }

    private var usernameBinding: Binding<String> {
        Binding(
            get: { model.signup.username },
            set: { new in
                // Public handle: letters, digits, "_" and "." only (like "Awa_Style225").
                model.signup.username = String(new.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }.prefix(24))
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingField("Prénom") {
                    TextField("Aïcha", text: $model.signup.firstName)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .focused($focus, equals: .firstName)
                        .onSubmit { focus = .username }
                }

                VStack(alignment: .leading, spacing: 5) {
                    OnboardingField("Pseudonyme public") {
                        TextField("Aicha_K", text: usernameBinding)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focus, equals: .username)
                            .onSubmit { focus = .district }
                    }
                    Text("3 caractères minimum : lettres, chiffres, « _ », « . ».")
                        .font(RF.T.footnote)
                        .foregroundStyle(RF.C.textDim)
                }

                phoneField

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ville")
                        .font(RF.T.footnote.weight(.semibold))
                        .foregroundStyle(RF.C.textDim)
                    Picker("Ville", selection: $model.signup.city) {
                        ForEach(Catalog.cities, id: \.self) { city in
                            Text(city).tag(city)
                        }
                    }
                    .pickerStyle(.segmented)
                    .sensoryFeedback(.selection, trigger: model.signup.city)
                }

                VStack(alignment: .leading, spacing: 5) {
                    OnboardingField("Quartier approximatif") {
                        TextField(model.signup.city == "Dakar" ? "Plateau, Almadies…" : "Cocody, Yopougon…", text: $model.signup.district)
                            .textContentType(.sublocality)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .focused($focus, equals: .district)
                            .onSubmit { focus = nil }
                    }
                    Text("Jamais ton adresse exacte.")
                        .font(RF.T.footnote)
                        .foregroundStyle(RF.C.textDim)
                }

                majorityToggle
                    .padding(.top, 2)
            }
            .padding(.horizontal, RF.S.gutter)
            .padding(.vertical, 22)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            RFButton("Continuer", isLoading: isSaving) { Task { await save() } }
                .disabled(!isValid)
                .padding(.horizontal, RF.S.gutter)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(RF.C.paper)
        }
        .rfScreenBackground()
        .navigationTitle("Ton profil")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSaving)
        .onAppear { if model.signup.firstName.isEmpty { focus = .firstName } }
    }

    @ViewBuilder private var phoneField: some View {
        if model.method == .phone {
            OnboardingField("Téléphone", content: {
                Text("+\(model.country.dialCode) \(model.country.format(model.phoneDigits))")
                    .font(RF.T.body.monospacedDigit())
                    .foregroundStyle(RF.C.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }, trailing: {
                FieldTag(text: "Vérifié", ok: true)
            })
            .accessibilityElement(children: .combine)
        } else {
            Text("Ton numéro te sera demandé avant ton premier paiement.")
                .font(RF.T.footnote)
                .foregroundStyle(RF.C.textDim)
        }
    }

    private var majorityToggle: some View {
        Toggle(isOn: $model.signup.isAdultConfirmed) {
            Text("J'ai 18 ans ou plus")
                .font(RF.T.body)
                .foregroundStyle(RF.C.text)
        }
        .tint(RF.C.hibiscus)
        .padding(.vertical, 4)
        .sensoryFeedback(.selection, trigger: model.signup.isAdultConfirmed)
        .accessibilityLabel("Je confirme avoir 18 ans ou plus")
    }

    private func save() async {
        guard isValid, !isSaving else { return }
        focus = nil
        isSaving = true
        defer { isSaving = false }
        var input = model.signup
        input.firstName = input.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        input.username = trimmedUsername
        input.district = input.district.trimmingCharacters(in: .whitespacesAndNewlines)
        model.isAuthenticating = true
        do {
            let profile = try await store.repo.completeSignup(input)
            await store.didSignIn(profile)
            Haptics.success()
            model.isAuthenticating = false
        } catch {
            model.isAuthenticating = false
            store.show(error)
            Haptics.error()
        }
    }
}

// MARK: - Previews

#Preview("Méthode") {
    NavigationStack { SignupMethodScreen(model: OnboardingModel()) }
        .previewEnvironment()
}

#Preview("Téléphone") {
    NavigationStack { SignupPhoneScreen(model: OnboardingModel()) }
        .previewEnvironment()
}

#Preview("Profil") {
    NavigationStack { SignupProfileScreen(model: OnboardingModel()) }
        .previewEnvironment()
}
