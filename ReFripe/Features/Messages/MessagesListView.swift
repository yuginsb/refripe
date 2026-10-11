import SwiftUI

/// Écran 3 — Messages (mockup `screenMessagesList`, PANEL `messagesList`).
/// Conversations triées par date, chacune rattachée à une annonce (miniature), pastille de non-lus,
/// recherche, pull-to-refresh. Re-polle tant que l'écran est visible (pas de temps réel).
@MainActor
struct MessagesListView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var conversations: [Conversation]?
    @State private var profiles: [UUID: UserProfile] = [:]
    @State private var listings: [UUID: Listing] = [:]
    @State private var loadError: Error?
    @State private var query = ""

    var body: some View {
        Group {
            if let conversations {
                if conversations.isEmpty {
                    ScrollView { emptyState }
                        .refreshable { await load() }
                } else {
                    list(conversations)
                }
            } else if let loadError {
                ErrorStateView(error: loadError) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rfScreenBackground()
        .navigationTitle("Messages")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Rechercher une conversation")
        .task {
            await load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { break }
                await load()
            }
        }
    }

    // MARK: Data

    private func load() async {
        do {
            let convs = try await store.repo.conversations()
            let missingUsers = Set(convs.map(\.otherUserId)).subtracting(profiles.keys)
            if !missingUsers.isEmpty {
                let found = (try? await store.repo.profiles(ids: Array(missingUsers))) ?? [:]
                profiles.merge(found) { _, new in new }
                store.cache(found)
            }
            let missingListings = Set(convs.compactMap(\.listingId)).subtracting(listings.keys)
            for id in missingListings {
                let fetched = try? await store.repo.listing(id: id)
                if let fetched { listings[id] = fetched }
            }
            if convs != conversations {
                withAnimation(.snappy) { conversations = convs }
            }
            loadError = nil
            await store.refreshBadges()
        } catch {
            if conversations == nil { loadError = error }
        }
    }

    private func filtered(_ all: [Conversation]) -> [Conversation] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { c in
            let name = profiles[c.otherUserId]?.username ?? ""
            let title = c.listingId.flatMap { listings[$0]?.title } ?? ""
            return [name, title, c.lastMessage].contains { $0.localizedStandardContains(q) }
        }
    }

    // MARK: Views

    private func list(_ all: [Conversation]) -> some View {
        let shown = filtered(all)
        return List {
            ForEach(shown) { c in
                ConversationListRow(conversation: c,
                                    profile: profiles[c.otherUserId],
                                    listing: c.listingId.flatMap { listings[$0] }) {
                    router.push(.chat(c.id))
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(RF.C.paper)
                .listRowSeparatorTint(RF.C.line)
                .alignmentGuide(.listRowSeparatorLeading) { _ in RF.S.gutter }
            }
        }
        .listStyle(.plain)
        .refreshable { await load() }
        .overlay {
            if shown.isEmpty {
                EmptyStateView(symbol: "magnifyingglass", title: "Aucun résultat",
                               message: "Aucune conversation ne correspond à « \(query) ».")
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(symbol: "bubble.left.and.bubble.right",
                       title: "Pas encore de messages",
                       message: "Écris à une vendeuse depuis une annonce : la conversation garde l'article et le prix sous tes yeux jusqu'à l'achat.",
                       actionTitle: "Découvrir des articles") {
            router.selectedTab = .discover
        }
    }
}

// MARK: - Reusable row

/// Conversation row (mockup `.conv`): avatar, pseudo + vérifié, date relative, aperçu,
/// pastille de non-lus, miniature de l'annonce liée.
struct ConversationListRow: View {
    let conversation: Conversation
    let profile: UserProfile?
    let listing: Listing?
    let action: () -> Void

    private var unread: Bool { conversation.unreadCount > 0 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Avatar(profile: profile, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(profile?.username ?? "…")
                            .font(RF.F.body(12.5, .bold))
                            .foregroundStyle(RF.C.text)
                            .lineLimit(1)
                        if profile?.verified == true { VerifiedBadge(size: 11) }
                        Spacer(minLength: 6)
                        Text(Fmt.relative(conversation.lastMessageAt))
                            .font(RF.F.body(10, unread ? .bold : .medium))
                            .foregroundStyle(unread ? RF.C.hibiscus : RF.C.textDim)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text(conversation.lastMessage.isEmpty ? "Nouvelle conversation" : conversation.lastMessage)
                            .font(RF.F.body(11.5, unread ? .bold : .medium))
                            .foregroundStyle(unread ? RF.C.text : RF.C.textDim)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                        if unread {
                            Text("\(conversation.unreadCount)")
                                .font(RF.F.body(9.5, .extraBold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 17, minHeight: 17)
                                .background(Capsule().fill(RF.C.hibiscus))
                        }
                    }
                    if let listing {
                        Text(listing.title)
                            .font(RF.F.body(10))
                            .foregroundStyle(RF.C.textDim)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let listing {
                    ListingPhotoView(photo: listing.photos.first, listingId: listing.id)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, RF.S.gutter)
            .contentShape(Rectangle())
        }
        .buttonStyle(ConversationRowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }

    private var accessibilityText: String {
        var parts = [profile?.username ?? "Conversation"]
        if let listing { parts.append("à propos de \(listing.title)") }
        if unread { parts.append("\(conversation.unreadCount) non lu\(conversation.unreadCount > 1 ? "s" : "")") }
        parts.append(conversation.lastMessage)
        parts.append(Fmt.relative(conversation.lastMessageAt))
        return parts.joined(separator: ", ")
    }
}

/// Row highlight like the mockup's `.conv:active { background: paper-dim }`.
private struct ConversationRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? RF.C.paperDim : Color.clear)
    }
}

// MARK: - Opening a conversation from anywhere

/// Get-or-create the conversation with `userId` about `listingId`, then push `.chat(id)` on the current tab.
/// Use it from any « Contacter » button. It also remembers the conversation so `ChatThreadView` can show
/// its header even before the first message (the repository only lists conversations that have messages).
@MainActor
enum ChatLauncher {
    private(set) static var known: [UUID: Conversation] = [:]

    static func remember(_ conversation: Conversation) { known[conversation.id] = conversation }

    static func open(with userId: UUID, listingId: UUID?, store: AppStore, router: Router) async {
        do {
            let c = try await store.repo.conversation(withUser: userId, listingId: listingId)
            remember(c)
            router.push(.chat(c.id))
        } catch {
            store.show(error)
        }
    }
}

#Preview {
    NavigationStack { MessagesListView() }.previewEnvironment()
}
