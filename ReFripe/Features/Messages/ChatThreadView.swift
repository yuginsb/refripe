import SwiftUI

/// Écran 3 — Conversation (mockup `screenChatThread`, PANEL `chatThread`).
/// L'annonce liée reste toujours visible en haut (photo, titre, prix, « Acheter »), bulles me/them,
/// horodatage, « Vu », réponses rapides, défilement auto en bas. Re-polle toutes les 2 s.
@MainActor
struct ChatThreadView: View {
    let conversationId: UUID

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var conversation: Conversation?
    @State private var other: UserProfile?
    @State private var listing: Listing?
    @State private var messages: [ChatMessage] = []
    @State private var loaded = false
    @State private var loadError: Error?
    @State private var draft = ""
    @State private var isSending = false
    @State private var sentTick = 0
    @State private var receivedTick = 0
    @FocusState private var inputFocused: Bool

    private static let quickReplies = ["Toujours dispo ?", "Dernier prix ?", "On se retrouve où ?"]
    private static let fr = Locale(identifier: "fr_FR")
    private static let bottomID = "chat-bottom"

    var body: some View {
        Group {
            if loaded {
                thread
            } else if let loadError {
                ErrorStateView(error: loadError) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rfScreenBackground()
        .navigationTitle(other?.username ?? "Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { titleView }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: sentTick)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: receivedTick)
        .task {
            await load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                await poll()
            }
        }
    }

    // MARK: Data

    private var myId: UUID? { store.me?.id }

    private var iAmSeller: Bool {
        guard let listing, let myId else { return false }
        return listing.sellerId == myId
    }

    private func load() async {
        loadError = nil
        do {
            messages = try await store.repo.messages(conversationId: conversationId)
            await resolveMetadata()
            loaded = true
            await markRead()
        } catch {
            loadError = error
        }
    }

    /// The contract has no `conversation(id:)`: look it up in the list, or in what `ChatLauncher` remembered.
    private func resolveMetadata() async {
        if conversation == nil {
            let all = (try? await store.repo.conversations()) ?? []
            conversation = all.first(where: { $0.id == conversationId }) ?? ChatLauncher.known[conversationId]
        }
        guard let c = conversation else { return }
        if other == nil { other = await store.profile(c.otherUserId) }
        if let lid = c.listingId {
            let fetched = try? await store.repo.listing(id: lid)
            if let fetched { listing = fetched }
        }
    }

    private func poll() async {
        guard let fresh = try? await store.repo.messages(conversationId: conversationId) else { return }
        if conversation == nil { await resolveMetadata() }
        guard fresh != messages else { return }
        let knownIds = Set(messages.map(\.id))
        let incoming = fresh.contains { !knownIds.contains($0.id) && $0.senderId != myId }
        withAnimation(.snappy) { messages = fresh }
        if incoming {
            receivedTick += 1
            await markRead()
        }
    }

    private func markRead() async {
        try? await store.repo.markConversationRead(id: conversationId)
        await store.refreshBadges()
    }

    private func send(_ text: String) async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !isSending else { return }
        let fromDraft = text == draft
        if fromDraft { draft = "" }
        isSending = true
        defer { isSending = false }
        do {
            let msg = try await store.repo.send(text: body, conversationId: conversationId)
            if !messages.contains(where: { $0.id == msg.id }) {
                withAnimation(.snappy) { messages.append(msg) }
            }
            sentTick += 1
            if conversation == nil { await resolveMetadata() }
        } catch {
            if fromDraft && draft.isEmpty { draft = body }
            Haptics.error()
            store.show(error)
        }
    }

    // MARK: Title

    private var titleView: some View {
        Button {
            if let other { router.push(.sellerProfile(other.id)) }
        } label: {
            HStack(spacing: 8) {
                Avatar(profile: other, size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(other?.username ?? "Conversation")
                            .font(RF.F.display(13.5))
                            .foregroundStyle(RF.C.text)
                            .lineLimit(1)
                        if other?.verified == true { VerifiedBadge(size: 11) }
                    }
                    if let minutes = other?.responseTimeMinutes {
                        Text("Répond en ~\(Self.responseLabel(minutes))")
                            .font(RF.F.body(9.5))
                            .foregroundStyle(RF.C.textDim)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(other == nil)
        .accessibilityLabel(other.map { "Profil de \($0.username)" } ?? "Conversation")
    }

    private static func responseLabel(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60)h"
    }

    // MARK: Thread

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if messages.isEmpty {
                        emptyHint
                    }
                    ForEach(rows) { row in
                        rowView(row)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(.horizontal, RF.S.gutter)
                .padding(.top, 4)
                .padding(.bottom, 14)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) {
                withAnimation(.snappy) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
            .onChange(of: inputFocused) {
                guard inputFocused else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    withAnimation(.snappy) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let listing { contextHeader(listing) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
    }

    private var emptyHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 26))
                .foregroundStyle(RF.C.textDim.opacity(0.5))
            Text("Lance la conversation")
                .font(RF.F.display(13))
                .foregroundStyle(RF.C.text)
            Text("L'article reste affiché en haut jusqu'à l'achat. Pour négocier, fais une offre depuis l'annonce : elle reste protégée par le séquestre.")
                .font(RF.F.body(11.5))
                .foregroundStyle(RF.C.textDim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
    }

    private struct Row: Identifiable {
        let message: ChatMessage
        let isMine: Bool
        let dayLabel: String?
        let showTime: Bool
        let receipt: String?
        let gapAbove: CGFloat
        var id: UUID { message.id }
    }

    private var rows: [Row] {
        let cal = Calendar.current
        let lastMineIndex = messages.lastIndex { $0.senderId == myId }
        return messages.indices.map { i -> Row in
            let m = messages[i]
            let prev = i > 0 ? messages[i - 1] : nil
            let next = i + 1 < messages.count ? messages[i + 1] : nil
            let newDay = prev.map { !cal.isDate($0.sentAt, inSameDayAs: m.sentAt) } ?? true
            let sameRunAsPrev = !newDay && prev?.senderId == m.senderId
                && m.sentAt.timeIntervalSince(prev?.sentAt ?? m.sentAt) < 5 * 60
            let endsRun: Bool = {
                guard let next else { return true }
                return next.senderId != m.senderId
                    || !cal.isDate(next.sentAt, inSameDayAs: m.sentAt)
                    || next.sentAt.timeIntervalSince(m.sentAt) >= 5 * 60
            }()
            var receipt: String?
            if i == lastMineIndex {
                let answered = messages[(i + 1)...].contains { $0.senderId != myId }
                receipt = answered ? "Vu" : "Envoyé"
            }
            return Row(message: m,
                       isMine: m.senderId == myId,
                       dayLabel: newDay ? Self.dayLabel(m.sentAt) : nil,
                       showTime: endsRun,
                       receipt: receipt,
                       gapAbove: i == 0 || newDay ? 0 : (sameRunAsPrev ? 3 : 10))
        }
    }

    private static func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Aujourd'hui" }
        if cal.isDateInYesterday(date) { return "Hier" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(fr))
    }

    private static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(fr))
    }

    @ViewBuilder private func rowView(_ row: Row) -> some View {
        if let day = row.dayLabel {
            Text(day)
                .font(RF.F.mono(9.5, .medium))
                .textCase(.uppercase)
                .kerning(0.5)
                .foregroundStyle(RF.C.textDim)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
        }
        VStack(alignment: row.isMine ? .trailing : .leading, spacing: 3) {
            bubble(row)
            if row.showTime || row.receipt != nil {
                HStack(spacing: 4) {
                    if row.showTime { Text(Self.time(row.message.sentAt)) }
                    if let receipt = row.receipt {
                        if row.showTime { Text("·") }
                        Text(receipt).fontWeight(receipt == "Vu" ? .bold : .regular)
                    }
                }
                .font(RF.F.body(9.5))
                .foregroundStyle(RF.C.textDim)
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: row.isMine ? .trailing : .leading)
        .padding(.top, row.gapAbove)
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibility(row))
    }

    private func bubble(_ row: Row) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 16,
                                           bottomLeadingRadius: row.isMine ? 16 : 4,
                                           bottomTrailingRadius: row.isMine ? 4 : 16,
                                           topTrailingRadius: 16,
                                           style: .continuous)
        return Text(row.message.text)
            .font(RF.F.body(12.5))
            .lineSpacing(2)
            .foregroundStyle(row.isMine ? Color.white : RF.C.text)
            .textSelection(.enabled)
            .padding(.vertical, 9)
            .padding(.horizontal, 13)
            .background(row.isMine ? RF.C.hibiscus : RF.C.paperDim, in: shape)
            .containerRelativeFrame(.horizontal, alignment: row.isMine ? .trailing : .leading) { length, _ in
                length * 0.76
            }
    }

    private func accessibility(_ row: Row) -> String {
        let who = row.isMine ? "Toi" : (other?.username ?? "Interlocutrice")
        var parts = [who, row.message.text, Self.time(row.message.sentAt)]
        if let receipt = row.receipt { parts.append(receipt) }
        return parts.joined(separator: ", ")
    }

    // MARK: Listing context (always visible)

    private func contextHeader(_ listing: Listing) -> some View {
        let price = store.negotiatedPrices[listing.id] ?? listing.price
        let canBuy = listing.status == .active && !iAmSeller
        return HStack(spacing: 9) {
            Button {
                router.push(.product(listing.id))
            } label: {
                HStack(spacing: 9) {
                    ListingPhotoView(photo: listing.photos.first, listingId: listing.id)
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(listing.title)
                            .font(RF.F.body(11, .bold))
                            .foregroundStyle(RF.C.text)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Text(Fmt.fcfa(price))
                                .font(RF.F.mono(10.5))
                                .foregroundStyle(RF.C.textDim)
                            if let tag = statusTag(listing) {
                                Text(tag)
                                    .font(RF.F.body(9, .extraBold))
                                    .foregroundStyle(RF.C.textDim)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(RF.C.paper))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(listing.title), \(Fmt.fcfa(price))")
            .accessibilityHint("Ouvre l'annonce")

            if canBuy {
                Button {
                    router.push(.checkout(listing.id))
                } label: {
                    Text("Acheter")
                        .font(RF.F.body(11.5, .extraBold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(RF.C.hibiscus))
                }
                .buttonStyle(RFPressStyle(scale: 0.94))
                .accessibilityLabel("Acheter \(listing.title)")
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, RF.S.gutter)
        .background(RF.C.paperDim, in: RoundedRectangle(cornerRadius: RF.R.md, style: .continuous))
        .padding(.horizontal, RF.S.gutter)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(RF.C.paper)
    }

    private func statusTag(_ listing: Listing) -> String? {
        switch listing.status {
        case .reserved: "Réservé"
        case .sold: "Vendu"
        case .removed: "Retiré"
        case .active: iAmSeller ? "Ton annonce" : (store.negotiatedPrices[listing.id] != nil ? "Prix négocié" : nil)
        }
    }

    // MARK: Input

    private var showQuickReplies: Bool {
        draft.isEmpty && !iAmSeller
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if showQuickReplies {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(Self.quickReplies, id: \.self) { reply in
                            Chip(reply) { Task { await send(reply) } }
                        }
                    }
                    .padding(.horizontal, RF.S.gutter)
                }
                .scrollIndicators(.hidden)
                .disabled(isSending)
                .transition(.opacity)
            }
            HStack(spacing: 8) {
                TextField("Écrire un message…", text: $draft)
                    .font(RF.F.body(12))
                    .foregroundStyle(RF.C.text)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        Task { await send(draft) }
                        inputFocused = true
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Capsule().fill(RF.C.paperDim))
                    .overlay(Capsule().strokeBorder(RF.C.line, lineWidth: 1))
                Button {
                    Task { await send(draft) }
                } label: {
                    Group {
                        if isSending {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(RF.C.hibiscus))
                    .opacity(canSend || isSending ? 1 : 0.45)
                }
                .buttonStyle(RFPressStyle(scale: 0.9))
                .disabled(!canSend)
                .accessibilityLabel("Envoyer")
            }
            .padding(.horizontal, RF.S.gutter)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            RF.C.paper
                .overlay(alignment: .top) { Rectangle().fill(RF.C.line).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(.snappy(duration: 0.2), value: showQuickReplies)
    }
}

#Preview("Fatou K. (Awa vendeuse)") {
    NavigationStack { ChatThreadView(conversationId: DemoIDs.conversationRobeWax) }.previewEnvironment()
}

#Preview("SneakDak (Awa acheteuse)") {
    NavigationStack { ChatThreadView(conversationId: DemoIDs.conversationBaskets) }.previewEnvironment()
}
