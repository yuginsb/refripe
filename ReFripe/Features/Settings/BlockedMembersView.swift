import SwiftUI

/// Réglages › « Membres bloqués »: who I blocked, with « Débloquer ».
struct BlockedMembersView: View {
    @Environment(AppStore.self) private var store

    @State private var members: [UserProfile]?
    @State private var loadError: Error?
    @State private var unblocking: UUID?

    var body: some View {
        Group {
            if let members {
                if members.isEmpty {
                    EmptyStateView(symbol: "hand.raised", title: "Aucun membre bloqué",
                                   message: "Bloque depuis un profil.")
                } else {
                    List {
                        Section {
                            ForEach(members) { row($0) }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            } else if let loadError {
                ErrorStateView(error: loadError) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .rfScreenBackground()
        .navigationTitle("Membres bloqués")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func row(_ member: UserProfile) -> some View {
        HStack(spacing: 12) {
            Avatar(profile: member, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.username)
                    .font(RF.T.subheadline.weight(.semibold))
                    .foregroundStyle(RF.C.text)
                    .lineLimit(1)
                Text(member.locationLabel)
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.textDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if unblocking == member.id {
                ProgressView()
            } else {
                Button("Débloquer") { Task { await unblock(member) } }
                    .font(RF.T.subheadline.weight(.semibold))
                    .foregroundStyle(RF.C.hibiscusText)
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Débloquer \(member.username)")
            }
        }
    }

    private func load() async {
        do {
            let ids = try await store.repo.blockedUserIds()
            var people: [UUID: UserProfile] = [:]
            if !ids.isEmpty { people = try await store.repo.profiles(ids: Array(ids)) }
            store.cache(people)
            members = people.values.sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
            loadError = nil
        } catch {
            if members == nil { loadError = error } else { store.show(error) }
        }
    }

    private func unblock(_ member: UserProfile) async {
        unblocking = member.id
        defer { unblocking = nil }
        do {
            try await store.repo.unblock(userId: member.id)
            withAnimation { members?.removeAll { $0.id == member.id } }
            Haptics.success()
            store.show("\(member.username) débloqué")
        } catch {
            store.show(error)
        }
    }
}

#Preview {
    NavigationStack { BlockedMembersView() }
        .previewEnvironment()
}
