import SwiftUI
import UserNotifications

/// Réglages (pushed from Profil): account, preferences, notifications, confidentiality (blocked members),
/// help (guide, support, CGU, confidentialité), sign-out and account deletion.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    @State private var editing: PreferenceEditorKind?
    @State private var showGuide = false
    @State private var confirmSignOut = false
    @State private var isSigningOut = false
    @State private var pushStatus: UNAuthorizationStatus?
    @State private var confirmDelete = false
    @State private var confirmDeleteFinal = false
    @State private var isDeleting = false
    @AppStorage(AppearanceMode.storageKey) private var appearance: AppearanceMode = .system

    var body: some View {
        Form {
            account
            preferences
            appearanceSection
            notifications
            privacy
            help
            signOutSection
            deleteSection
        }
        .formStyle(.grouped)
        .font(RF.T.body)
        .rfScreenBackground()
        .navigationTitle("Réglages")
        .navigationBarTitleDisplayMode(.inline)
        .task { pushStatus = await PushPermission.status() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { pushStatus = await PushPermission.status() } }
        }
        .sheet(item: $editing) { kind in
            PreferenceEditorSheet(kind: kind)
                .environment(store)
                .presentationDetents(kind == .categories ? [.medium, .large] : [.large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showGuide) {
            IntroGuideView { showGuide = false }
        }
        .confirmationDialog("Te déconnecter ?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive) { Task { await signOut() } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(store.isDemo ? "Démo : 07 07 07 07 07, code 1234."
                              : "Tout reste sur ton compte.")
        }
        .confirmationDialog("Supprimer ton compte ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Continuer", role: .destructive) { confirmDeleteFinal = true }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Annonces retirées, profil effacé.")
        }
        .alert("Supprimer définitivement ?", isPresented: $confirmDeleteFinal) {
            Button("Supprimer", role: .destructive) { Task { await deleteAccount() } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("C'est définitif.")
        }
    }

    // MARK: Sections

    @ViewBuilder private var account: some View {
        Section {
            if let me = store.me {
                LabeledContent("Pseudo", value: me.username)
                LabeledContent("Prénom", value: me.firstName)
                LabeledContent("Ville", value: me.city)
                LabeledContent("Quartier", value: me.district.isEmpty ? "–" : me.district)
            }
        } header: {
            header("Compte")
        }
    }

    private var preferences: some View {
        Section {
            ForEach(PreferenceEditorKind.allCases) { kind in
                Button { editing = kind } label: {
                    HStack(spacing: 12) {
                        Label(kind.title, systemImage: kind.symbol)
                            .foregroundStyle(RF.C.text)
                        Spacer(minLength: 8)
                        Text(kind.summary(store.preferences))
                            .font(RF.T.subheadline)
                            .foregroundStyle(RF.C.textDim)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(RF.T.footnote.weight(.semibold))
                            .foregroundStyle(RF.C.textDim.opacity(0.6))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(kind.title) : \(kind.summary(store.preferences))")
                .accessibilityHint("Modifier")
            }
        } header: {
            header("Préférences")
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker(selection: $appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
            } label: {
                Label("Apparence", systemImage: "circle.lefthalf.filled")
                    .foregroundStyle(RF.C.text)
            }
            .accessibilityIdentifier("settings.appearance")
        }
    }

    private var notifications: some View {
        Section {
            Button {
                Task {
                    await PushPermission.request(store: store)
                    pushStatus = await PushPermission.status()
                }
            } label: {
                HStack {
                    Label("Alertes", systemImage: "bell")
                        .foregroundStyle(RF.C.text)
                    Spacer()
                    Text(pushLabel)
                        .foregroundStyle(RF.C.textDim)
                    Image(systemName: "chevron.right")
                        .font(RF.T.footnote.weight(.semibold))
                        .foregroundStyle(RF.C.textDim.opacity(0.6))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(pushStatus == .notDetermined ? "Activer les alertes" : "Ouvre les réglages de l'iPhone")
        } header: {
            header("Notifications")
        }
    }

    private var pushLabel: String {
        guard let status = pushStatus else { return "" }
        switch status {
        case .authorized, .provisional, .ephemeral: return "Activées"
        case .denied: return "Désactivées"
        case .notDetermined: return "Activer"
        @unknown default: return ""
        }
    }

    private var privacy: some View {
        Section {
            NavigationLink {
                BlockedMembersView()
            } label: {
                Label("Membres bloqués", systemImage: "hand.raised")
                    .foregroundStyle(RF.C.text)
            }
            .accessibilityIdentifier("settings.blocked")
        } header: {
            header("Confidentialité")
        }
    }

    private var help: some View {
        Section {
            Button { showGuide = true } label: {
                Label("Guide de bienvenue", systemImage: "questionmark.circle")
                    .foregroundStyle(RF.C.text)
            }
            SupportWhatsAppButton {
                rowLabel("Support WhatsApp", symbol: "message", trailing: "arrow.up.right")
            }
            .accessibilityIdentifier("settings.support")
            Link(destination: Legal.termsURL) {
                rowLabel("Conditions d'utilisation", symbol: "doc.text", trailing: "arrow.up.right")
            }
            Link(destination: Legal.privacyURL) {
                rowLabel("Confidentialité", symbol: "lock.shield", trailing: "arrow.up.right")
            }
        } header: {
            header("Aide")
        }
    }

    private func rowLabel(_ title: String, symbol: String, trailing: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
                .foregroundStyle(RF.C.text)
            Spacer()
            Image(systemName: trailing)
                .font(RF.T.footnote.weight(.semibold))
                .foregroundStyle(RF.C.textDim.opacity(0.6))
        }
        .contentShape(Rectangle())
    }

    private var signOutSection: some View {
        Section {
            Button("Se déconnecter", role: .destructive) { confirmSignOut = true }
                .disabled(isSigningOut)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("ReFripe \(Self.version)")
                if store.isDemo {
                    Text("Mode démo")
                }
            }
            .font(RF.T.footnote.monospacedDigit())
            .padding(.top, 8)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) { confirmDelete = true } label: {
                HStack {
                    Text("Supprimer mon compte")
                        .foregroundStyle(RF.C.hibiscusText)
                    if isDeleting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isDeleting || isSigningOut)
            .accessibilityIdentifier("settings.deleteAccount")
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(RF.T.footnote.weight(.semibold))
            .foregroundStyle(RF.C.textDim)
            .textCase(nil)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }

    // MARK: Sign-out

    private func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        resetNavigation()
        await store.signOut()
        Haptics.tap()
    }

    /// AppStore.signOut doesn't touch navigation: reset every tab first.
    private func resetNavigation() {
        for tab in AppTab.allCases { router.popToRoot(tab) }
        router.selectedTab = .discover
        router.inboxSegment = .messages
    }

    // MARK: Account deletion (App Store 5.1.1(v))

    private func deleteAccount() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await store.repo.deleteAccount()
            SellDraftStore.clear()
            resetNavigation()
            await store.signOut()
            Haptics.success()
            store.show("Ton compte a été supprimé")
        } catch {
            Haptics.error()
            store.show(error)
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .previewEnvironment()
}
