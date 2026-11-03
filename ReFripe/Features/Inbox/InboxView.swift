import SwiftUI

/// Messages tab root (v3): « À faire » pinned on top when something waits for me (pay, confirm the
/// reception, ship / hand over, answer an offer), then the conversations. No segmented control anymore:
/// notifications live behind the bell on Accueil, orders in Profil › Mon activité.
/// Conversations with blocked members are hidden. Re-polls while visible (no realtime).
@MainActor
struct InboxView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var data: InboxData?
    @State private var loadError: Error?
    @State private var query = ""
    @State private var openingTodo: String?

    var body: some View {
        Group {
            if let data {
                list(data)
            } else if let loadError {
                ErrorStateView(error: loadError) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rfScreenBackground()
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.large)
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
            let fresh = try await InboxData.load(store: store, previous: data)
            withAnimation(.snappy) { data = fresh }
            loadError = nil
            await store.refreshBadges()
        } catch {
            if data == nil { loadError = error }
        }
    }

    private func filtered(_ all: [Conversation], data: InboxData) -> [Conversation] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { c in
            let name = data.people[c.otherUserId]?.username ?? ""
            let title = c.listingId.flatMap { data.listings[$0]?.title } ?? ""
            return [name, title, c.lastMessage].contains { $0.localizedStandardContains(q) }
        }
    }

    // MARK: List

    private func list(_ data: InboxData) -> some View {
        let todos = data.todos()
        let shown = filtered(data.conversations, data: data)
        return List {
            if !data.conversations.isEmpty {
                InboxSearchField(query: $query)
                    .listRowInsets(EdgeInsets(top: 4, leading: RF.S.gutter, bottom: 8, trailing: RF.S.gutter))
                    .listRowBackground(RF.C.paper)
                    .listRowSeparator(.hidden)
            }

            if !todos.isEmpty && query.isEmpty {
                Section {
                    ForEach(todos) { todo in
                        InboxTodoRow(content: content(todo, data: data), isLoading: openingTodo == todo.id) {
                            Task { await open(todo, data: data) }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(RF.C.paper)
                        .listRowSeparatorTint(RF.C.line)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in RF.S.gutter + 44 + 12 }
                    }
                } header: {
                    sectionHeader("À faire", count: todos.count)
                }
            }

            if !shown.isEmpty {
                Section {
                    ForEach(shown) { c in
                        ConversationListRow(conversation: c,
                                            profile: data.people[c.otherUserId],
                                            listing: c.listingId.flatMap { data.listings[$0] }) {
                            ChatLauncher.remember(c)
                            router.push(.chat(c.id))
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(RF.C.paper)
                        .listRowSeparatorTint(RF.C.line)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in RF.S.gutter + 44 + 12 }
                    }
                } header: {
                    if !todos.isEmpty && query.isEmpty { sectionHeader("Conversations", count: nil) }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await load() }
        .overlay {
            if data.conversations.isEmpty && todos.isEmpty {
                ContentUnavailableView {
                    Label("Aucun message", systemImage: "bubble.left.and.bubble.right")
                } actions: {
                    Button("Accueil") { router.selectedTab = .discover }
                        .buttonStyle(.borderedProminent)
                        .tint(RF.C.hibiscus)
                }
            } else if !query.isEmpty && shown.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(RF.T.footnote.weight(.semibold))
                .foregroundStyle(RF.C.textDim)
            if let count {
                Text("\(count)")
                    .font(RF.T.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(RF.C.card)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Capsule().fill(RF.C.hibiscus))
            }
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: To-do rows

    private func content(_ todo: InboxData.Todo, data: InboxData) -> InboxTodoRow.Content {
        switch todo.kind {
        case .payOrder(let o):
            return .init(symbol: "creditcard", title: "Paiement à finir",
                         subtitle: "\(o.listingTitle) · \(Fmt.fcfa(o.total))",
                         photo: o.listingPhoto, photoId: o.listingId, urgent: true)
        case .confirmReception(let o):
            let left = o.escrowReleaseAt.flatMap { EscrowCountdown.text(until: $0) }
            return .init(symbol: "checkmark.circle", title: "Réception à confirmer",
                         subtitle: left.map { "\(o.listingTitle) · \($0)" } ?? o.listingTitle,
                         photo: o.listingPhoto, photoId: o.listingId, urgent: true)
        case .ship(let o):
            return .init(symbol: "shippingbox", title: "À expédier",
                         subtitle: "\(o.listingTitle) · \(o.buyerName)",
                         photo: o.listingPhoto, photoId: o.listingId, urgent: false)
        case .handOff(let o):
            return .init(symbol: "number", title: "Code de retrait",
                         subtitle: "\(o.listingTitle) · \(o.buyerName)",
                         photo: o.listingPhoto, photoId: o.listingId, urgent: false)
        case .answerOffer(let t):
            let l = data.listings[t.listingId]
            let amount = t.lastBuyerOffer.map { " · \(Fmt.fcfa($0.amount))" } ?? ""
            return .init(symbol: "tag", title: "Offre de \(data.name(t.buyerId, fallback: "une acheteuse"))\(amount)",
                         subtitle: l?.title ?? "Ton annonce",
                         photo: l?.photos.first, photoId: t.listingId, urgent: false)
        case .answerCounter(let t):
            let l = data.listings[t.listingId]
            let amount = t.lastSellerCounter.map { " · \(Fmt.fcfa($0.amount))" } ?? ""
            return .init(symbol: "arrow.left.arrow.right",
                         title: "Contre-offre de \(data.name(t.sellerId, fallback: "la vendeuse"))\(amount)",
                         subtitle: l?.title ?? "Annonce",
                         photo: l?.photos.first, photoId: t.listingId, urgent: false)
        case .payAccepted(let t):
            let l = data.listings[t.listingId]
            let until = l?.reservedUntil.map { " · \(Fmt.hourMinute($0))" } ?? ""
            return .init(symbol: "checkmark.seal", title: "Offre acceptée\(until)",
                         subtitle: "\(l?.title ?? "Annonce") · \(Fmt.fcfa(t.acceptedAmount ?? l?.price ?? 0))",
                         photo: l?.photos.first, photoId: t.listingId, urgent: true)
        }
    }

    private func open(_ todo: InboxData.Todo, data: InboxData) async {
        guard openingTodo == nil else { return }
        switch todo.kind {
        case .payOrder(let o), .confirmReception(let o), .ship(let o), .handOff(let o):
            router.push(.order(o.id))
        case .answerOffer(let t):
            await openChat(with: t.buyerId, listingId: t.listingId, data: data, todoId: todo.id,
                           fallback: .receivedOffers(t.listingId))
        case .answerCounter(let t):
            await openChat(with: t.sellerId, listingId: t.listingId, data: data, todoId: todo.id,
                           fallback: .offerThread(t.listingId))
        case .payAccepted(let t):
            if let amount = t.acceptedAmount { store.negotiatedPrices[t.listingId] = amount }
            router.push(.checkout(t.listingId))
        }
    }

    /// Negotiations happen in the conversation (offers as bubbles); falls back to the offer screens.
    private func openChat(with userId: UUID, listingId: UUID, data: InboxData, todoId: String, fallback: Route) async {
        if let c = data.conversation(with: userId, listingId: listingId) {
            ChatLauncher.remember(c)
            router.push(.chat(c.id))
            return
        }
        openingTodo = todoId
        defer { openingTodo = nil }
        do {
            let c = try await store.repo.conversation(withUser: userId, listingId: listingId)
            ChatLauncher.remember(c)
            router.push(.chat(c.id))
        } catch {
            router.push(fallback)
        }
    }
}

// MARK: - Pieces

/// Inline search field (filters the conversations).
struct InboxSearchField: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(RF.C.textDim)
                .accessibilityHidden(true)
            TextField("Rechercher", text: $query)
                .font(RF.T.body)
                .foregroundStyle(RF.C.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Rechercher une conversation")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(RF.C.textDim)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effacer la recherche")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .background(RF.C.paperDim, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// « À faire » row: symbol, one-line title, one-line detail, listing thumbnail.
struct InboxTodoRow: View {
    struct Content {
        var symbol: String
        var title: String
        var subtitle: String
        var photo: ListingPhoto?
        var photoId: UUID
        var urgent: Bool
    }

    let content: Content
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(content.urgent ? RF.C.hibiscus.opacity(0.10) : RF.C.paperDim)
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: content.symbol)
                            .font(RF.T.subheadline.weight(.semibold))
                            .foregroundStyle(content.urgent ? RF.C.hibiscusText : RF.C.text)
                    }
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(content.title)
                        .font(RF.T.subheadline.weight(.semibold))
                        .foregroundStyle(RF.C.text)
                        .lineLimit(1)
                    Text(content.subtitle)
                        .font(RF.T.footnote.monospacedDigit())
                        .foregroundStyle(RF.C.textDim)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ListingPhotoView(photo: content.photo, listingId: content.photoId)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Image(systemName: "chevron.right")
                    .font(RF.T.footnote.weight(.semibold))
                    .foregroundStyle(RF.C.textDim)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, RF.S.gutter)
            .contentShape(Rectangle())
        }
        .buttonStyle(InboxRowPressStyle())
        .disabled(isLoading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(content.title), \(content.subtitle)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

/// Native-looking row highlight.
struct InboxRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? RF.C.paperDim : Color.clear)
    }
}

#Preview {
    NavigationStack { InboxView().withAppRoutes() }
        .previewEnvironment()
}
