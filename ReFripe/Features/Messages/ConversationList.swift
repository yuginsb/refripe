import SwiftUI

/// Boîte › Messages: conversations sorted by date, each tied to a listing (thumbnail), unread count,
/// search, pull-to-refresh. Re-polls while visible (no realtime).
@MainActor
struct ConversationList: View {
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
                list(conversations)
            } else if let loadError {
                ErrorStateView(error: loadError) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .searchable(text: $query, prompt: "Rechercher")
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
                .alignmentGuide(.listRowSeparatorLeading) { _ in RF.S.gutter + 44 + 12 }
            }
        }
        .listStyle(.plain)
        .refreshable { await load() }
        .overlay {
            if all.isEmpty {
                ContentUnavailableView {
                    Label("Aucun message", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Écris à une vendeuse depuis une annonce.")
                } actions: {
                    Button("Découvrir") { router.selectedTab = .discover }
                        .buttonStyle(.borderedProminent)
                        .tint(RF.C.hibiscus)
                }
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }
}

// MARK: - Reusable row

/// Conversation row: avatar, username + verified, relative date, preview, unread count, listing thumbnail.
struct ConversationListRow: View {
    let conversation: Conversation
    let profile: UserProfile?
    let listing: Listing?
    let action: () -> Void

    private var unread: Bool { conversation.unreadCount > 0 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Avatar(profile: profile, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(profile?.username ?? "…")
                            .font(RF.T.subheadline.weight(.semibold))
                            .foregroundStyle(RF.C.text)
                            .lineLimit(1)
                        if profile?.verified == true { VerifiedBadge(size: 12) }
                        Spacer(minLength: 8)
                        Text(Fmt.relative(conversation.lastMessageAt))
                            .font(RF.T.footnote.monospacedDigit())
                            .foregroundStyle(unread ? RF.C.hibiscus : RF.C.textDim)
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        Text(conversation.lastMessage.isEmpty ? "Nouvelle conversation" : conversation.lastMessage)
                            .font(unread ? RF.T.subheadline.weight(.semibold) : RF.T.subheadline)
                            .foregroundStyle(unread ? RF.C.text : RF.C.textDim)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if unread {
                            Text("\(conversation.unreadCount)")
                                .font(RF.T.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .frame(minWidth: 20, minHeight: 20)
                                .background(Capsule().fill(RF.C.hibiscus))
                        }
                    }
                    if let listing {
                        Text(listing.title)
                            .font(RF.T.footnote)
                            .foregroundStyle(RF.C.textDim)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let listing {
                    ListingPhotoView(photo: listing.photos.first, listingId: listing.id)
                        .frame(width: 44, height: 44)
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

/// Native-looking row highlight.
private struct ConversationRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? RF.C.paperDim : Color.clear)
    }
}

#Preview {
    NavigationStack { ConversationList().navigationTitle("Boîte") }.previewEnvironment()
}
