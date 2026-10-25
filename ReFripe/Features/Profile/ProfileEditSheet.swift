import SwiftUI

/// « Modifier le profil »: username, first name, city, district.
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
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await store.repo.updateProfile(
                username: trimmedUsername,
                firstName: trimmedFirstName,
                city: city,
                district: district
            )
            await store.didSignIn(saved)
            Haptics.success()
            store.show("Profil mis à jour")
            dismiss()
        } catch {
            store.show(error)
        }
    }
}

#Preview {
    ProfileEditSheet().previewEnvironment()
}
