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
            MotifPattern(color: RF.C.marigold.opacity(0.09), spacing: 15)
                .ignoresSafeArea()
                .mask {
                    LinearGradient(colors: [.black, .black.opacity(0.35), .clear], startPoint: .top, endPoint: .center)
                        .ignoresSafeArea()
                }

            VStack(spacing: 0) {
                Spacer(minLength: 40)
                brand
                Spacer(minLength: 32)
                methods
                Text("Apple pré-remplit ton prénom — tout reste modifiable ensuite. Ton numéro sert aussi pour Wave et Orange Money au moment de payer.")
                    .font(RF.F.body(10.5))
                    .foregroundStyle(RF.C.textOnInkDim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.top, 16)
                    .padding(.horizontal, 8)
                if store.isDemo {
                    Label("Mode démo — numéro 07 07 07 07 07, code 1234 pour retrouver Awa", systemImage: "sparkles")
                        .font(RF.F.mono(10, .medium))
                        .foregroundStyle(RF.C.marigold)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            if model.isAuthenticating {
                RF.C.scrim.ignoresSafeArea()
                ProgressView().controlSize(.large).tint(RF.C.marigold)
                    .accessibilityLabel("Connexion en cours")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var brand: some View {
        VStack(spacing: 14) {
            (Text("Re").foregroundStyle(RF.C.textOnInk) + Text("Fripe").foregroundStyle(RF.C.marigold))
                .font(RF.F.display(44, .black))
                .accessibilityLabel("ReFripe")
                .accessibilityAddTraits(.isHeader)
            Text("Achète et vends la fripe près de chez toi, en toute confiance.")
                .font(RF.F.body(14, .medium))
                .foregroundStyle(RF.C.textOnInkDim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 20)
            HStack(spacing: 8) {
                Label("Séquestre", systemImage: "lock.shield")
                Label("Wave · OM", systemImage: "iphone")
                Label("Abidjan · Dakar", systemImage: "mappin")
            }
            .font(RF.F.body(10, .bold))
            .foregroundStyle(RF.C.textOnInk)
            .labelStyle(SignupPillLabelStyle())
            .padding(.top, 6)
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
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
            .disabled(model.isAuthenticating)

            RFButton("Continuer avec mon numéro", symbol: "iphone") {
                model.method = .phone
                model.authPath.append(.phone)
            }
            .disabled(model.isAuthenticating)

            SoonMethodButton(title: "Continuer avec Google") {
                Text("G")
                    .font(RF.F.body(14, .extraBold))
                    .foregroundStyle(RF.C.ink0)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.white))
            }
            SoonMethodButton(title: "Continuer avec Facebook") {
                Text("f")
                    .font(RF.F.body(15, .extraBold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color(hex: 0x2B5CB8)))   // mockup `.mi-fb`
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

/// Outlined method button on ink, tagged "Bientôt" (Google / Facebook are not wired on the backend yet).
private struct SoonMethodButton<Icon: View>: View {
    let title: String
    @ViewBuilder var icon: Icon
    @Environment(AppStore.self) private var store

    var body: some View {
        Button {
            Haptics.warning()
            store.show("Bientôt disponible — utilise Apple ou ton numéro pour l'instant.")
        } label: {
            HStack(spacing: 12) {
                icon
                Text(title)
                    .font(RF.F.body(13, .bold))
                    .foregroundStyle(RF.C.textOnInk)
                Spacer(minLength: 4)
                Text("Bientôt")
                    .font(RF.F.body(9, .extraBold))
                    .foregroundStyle(RF.C.ink0)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(Capsule().fill(RF.C.marigold))
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(RF.C.ink1, in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: RF.R.md, style: .continuous).strokeBorder(RF.C.lineOnInk, lineWidth: 1.5))
            .opacity(0.75)
            .contentShape(RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
        }
        .buttonStyle(RFPressStyle())
        .accessibilityLabel("\(title), bientôt disponible")
    }
}

private struct SignupPillLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 10, weight: .semibold)).foregroundStyle(RF.C.marigold)
            configuration.title.lineLimit(1)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 9)
        .background(Capsule().fill(RF.C.textOnInk.opacity(0.08)))
        .overlay(Capsule().strokeBorder(RF.C.lineOnInk, lineWidth: 1))
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
                OnboardingTagline("Ce numéro sert aussi pour Wave et Orange Money au moment de payer.")
                    .padding(.bottom, 22)

                OnboardingField("Numéro mobile", content: {
                    HStack(spacing: 10) {
                        countryMenu
                        Rectangle().fill(RF.C.line).frame(width: 1, height: 22)
                        TextField(model.country.placeholder, text: phoneBinding)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .font(RF.F.mono(15, .medium))
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
                    RFButton("Recevoir le code", symbol: "message", isLoading: isSending) {
                        Task { await sendCode() }
                    }
                    .disabled(!model.isPhoneComplete)
                    .padding(.top, 6)
                    if store.isDemo {
                        Text("Démo : 07 07 07 07 07 te reconnecte en tant qu'Awa ; tout autre numéro crée un nouveau compte.")
                            .font(RF.F.body(10.5))
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
        .navigationTitle("Numéro de téléphone")
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
                    .font(RF.F.mono(15, .medium))
                    .foregroundStyle(RF.C.text)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(RF.C.textDim)
            }
        }
        .disabled(codeSent)
        .accessibilityLabel("Indicatif : \(model.country.name), plus \(model.country.dialCode)")
    }

    private var otpSection: some View {
        VStack(spacing: 0) {
            Text(store.isDemo
                 ? "Code envoyé par SMS au +\(model.country.dialCode) \(model.country.format(model.phoneDigits)) (démo : \(DemoIDs.otpCode))"
                 : "Code envoyé par SMS au +\(model.country.dialCode) \(model.country.format(model.phoneDigits))")
                .font(RF.F.body(11))
                .foregroundStyle(RF.C.textDim)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

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
            .font(RF.F.body(12, .bold))
            .foregroundStyle(RF.C.textDim)
            .padding(.top, 14)
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
                        .font(RF.F.mono(19, .semibold))
                        .foregroundStyle(RF.C.text)
                        .frame(width: 42, height: 50)
                        .background(RF.C.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(isActive ? RF.C.hibiscus : RF.C.line, lineWidth: 1.5)
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
                    Text("Visible sur tes annonces. Lettres, chiffres, « _ » et « . », 3 caractères minimum.")
                        .font(RF.F.body(10.5))
                        .foregroundStyle(RF.C.textDim)
                }

                phoneField

                VStack(alignment: .leading, spacing: 6) {
                    Text("VILLE")
                        .font(RF.F.body(10.5, .bold))
                        .kerning(0.42)
                        .foregroundStyle(RF.C.textDim)
                    HStack(spacing: 8) {
                        ForEach(Catalog.cities, id: \.self) { city in
                            ChoiceChip(title: city, selected: model.signup.city == city) {
                                model.signup.city = city
                            }
                        }
                    }
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
                    Text("Jamais ton adresse exacte : juste de quoi situer tes annonces.")
                        .font(RF.F.body(10.5))
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
                    .font(RF.F.mono(14, .medium))
                    .foregroundStyle(RF.C.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }, trailing: {
                FieldTag(text: "Vérifié", ok: true)
            })
            .accessibilityElement(children: .combine)
        } else {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "iphone").font(.system(size: 13)).foregroundStyle(RF.C.textDim)
                Text("Ton numéro te sera demandé avant ta première vente ou ton premier achat (Wave / Orange Money).")
                    .font(RF.F.body(11))
                    .foregroundStyle(RF.C.textDim)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RF.C.paperDim, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    /// Mockup `.majority-toggle` / `.mt-box`.
    private var majorityToggle: some View {
        let on = model.signup.isAdultConfirmed
        return Button {
            model.signup.isAdultConfirmed.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .opacity(on ? 1 : 0)
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? RF.C.money : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(on ? RF.C.money : RF.C.line, lineWidth: 1.5))
                Text("Je confirme avoir 18 ans ou plus")
                    .font(RF.F.body(12))
                    .foregroundStyle(RF.C.text)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
        .animation(.snappy(duration: 0.15), value: on)
        .accessibilityLabel("Je confirme avoir 18 ans ou plus")
        .accessibilityValue(on ? "Coché" : "Non coché")
        .accessibilityAddTraits(on ? .isSelected : [])
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
