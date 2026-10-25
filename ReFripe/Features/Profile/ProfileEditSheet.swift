import SwiftUI

/// « Modifier le profil »: username, first name, city, district.
///
/// TODO(contract): `Repository` has no profile-update method yet, so the edit only updates the
/// current session (`AppStore.me` via `didSignIn`). Add `updateProfile(_:) async throws -> UserProfile`
/// to the contract (+ Demo / Supabase) and call it in `save()`.
struct ProfileEditSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var firstName = ""
    @State private var city = Catalog.cities.first ?? "Abidjan"
    @State private var district = ""
    @State private var seeded = false
    @State private var isSaving = false

    private var trimmedUsername: String { username.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedFirstName: String { firstName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { trimmedUsername.count >= 3 && !trimmedFirstName.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Pseudo", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Prénom", text: $firstName)
                        .textContentType(.givenName)
                } footer: {
                    Text("Ton pseudo est public.")
                }
                Section {
                    Picker("Ville", selection: $city) {
                        ForEach(Catalog.cities, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Quartier", text: $district)
                }
            }
            .font(RF.T.body)
            .rfScreenBackground()
            .navigationTitle("Modifier le profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
        }
        .tint(RF.C.hibiscus)
        .onAppear(perform: seed)
    }

    private func seed() {
        guard !seeded, let me = store.me else { return }
        seeded = true
        username = me.username
        firstName = me.firstName
        city = Catalog.cities.contains(me.city) ? me.city : (Catalog.cities.first ?? me.city)
        district = me.district
    }

    private func save() async {
        guard var updated = store.me, canSave else { return }
        isSaving = true
        defer { isSaving = false }
        updated.username = trimmedUsername
        updated.firstName = trimmedFirstName
        updated.city = city
        updated.district = district.trimmingCharacters(in: .whitespacesAndNewlines)
        await store.didSignIn(updated)
        Haptics.success()
        store.show("Profil mis à jour")
        dismiss()
    }
}

#Preview {
    ProfileEditSheet().previewEnvironment()
}
