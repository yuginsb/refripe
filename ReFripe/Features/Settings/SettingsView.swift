import SwiftUI
import UserNotifications

/// Réglages (pushed from Profil): account, preferences, notifications, help, sign-out.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    @State private var editingProfile = false
    @State private var editing: PreferenceEditorKind?
    @State private var showGuide = false
    @State private var confirmSignOut = false
    @State private var isSigningOut = false
    @State private var pushStatus: UNAuthorizationStatus?

    var body: some View {
        Form {
            account
            preferences
            notifications
            help
            signOutSection
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
        .sheet(isPresented: $editingProfile) {
            ProfileEditSheet()
                .environment(store)
                .presentationDetents([.large])
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
            Text(store.isDemo ? "Démo : reconnecte-toi avec le 07 07 07 07 07, code 1234."
                              : "Tes annonces et commandes restent sur ton compte.")
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
            Button("Modifier le profil") { editingProfile = true }
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
        } footer: {
            Text("Elles trient Découvrir et tes alertes.")
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

    private var help: some View {
        Section {
            Button { showGuide = true } label: {
                Label("Revoir le guide de bienvenue", systemImage: "questionmark.circle")
                    .foregroundStyle(RF.C.text)
            }
        } header: {
            header("Aide")
        }
    }

    private var signOutSection: some View {
        Section {
            Button("Se déconnecter", role: .destructive) { confirmSignOut = true }
                .disabled(isSigningOut)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("ReFripe \(Self.version)")
                if store.isDemo {
                    Text("Mode démo : données fictives, aucun paiement réel.")
                }
            }
            .font(RF.T.footnote.monospacedDigit())
            .padding(.top, 8)
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
        // AppStore.signOut doesn't touch navigation: reset every tab first.
        for tab in AppTab.allCases { router.popToRoot(tab) }
        router.selectedTab = .discover
        router.inboxSegment = .messages
        await store.signOut()
        Haptics.tap()
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .previewEnvironment()
}
