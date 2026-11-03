import SwiftUI
import PhotosUI
import UIKit

/// Conversation (v3): header (avatar, name + seal, response time), the listing pinned on top with
/// « Acheter » (disabled with the reason when reserved for someone else), a timeline merging text
/// messages, photo messages and **offer rounds as bubbles**, quick replies « Faire une offre » /
/// « On se voit où ? », and a composer (photo, text, send). ⋯ menu: Signaler / Bloquer.
/// No realtime: re-polls messages and the negotiation every 2 s. Tab bar hidden.
@MainActor
struct ChatThreadView: View {
    let conversationId: UUID

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var conversation: Conversation?
    @State private var other: UserProfile?
    @State private var listing: Listing?
    @State private var messages: [ChatMessage] = []
    @State private var thread: OfferThread?
    @State private var loaded = false
    @State private var loadError: Error?
    @State private var draft = ""
    @State private var isSending = false
    @State private var sentTick = 0
    @State private var receivedTick = 0
    @State private var pollCount = 0
    @FocusState private var inputFocused: Bool

    // Photo
    @State private var photoItem: PhotosPickerItem?
    @State private var isSendingPhoto = false

    // Negotiation
    @State private var showOfferComposer = false
    @State private var counterTarget: OfferThread?
    @State private var counterAmount: FCFA = 0
    @State private var refusing: OfferThread?
    @State private var offerBusy = false

    // Moderation
    @State private var showReport = false
    @State private var showBlock = false

    private static let meetReply = "On se voit où ?"
    private static let fr = Locale(identifier: "fr_FR")
    private static let bottomID = "chat-bottom"

    var body: some View {
        Group {
            if loaded {
                timeline
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
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) { titleView }
            ToolbarItem(placement: .topBarTrailing) { moreMenu }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: sentTick)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: receivedTick)
        .sheet(isPresented: $showOfferComposer) { offerComposerSheet }
        .sheet(item: $counterTarget) { t in counterSheet(t) }
        .confirmationDialog("Refuser cette offre ?", isPresented: refuseShown, titleVisibility: .visible,
                            presenting: refusing) { t in
            Button("Refuser l'offre", role: .destructive) { Task { await respond(t, .refuse) } }
            Button("Annuler", role: .cancel) {}
        }
        .confirmationDialog("Signaler \(otherName)", isPresented: $showReport, titleVisibility: .visible) {
            ForEach(ReportReason.allCases) { reason in
                Button(reason.label) { Task { await report(reason) } }
            }
            Button("Annuler", role: .cancel) {}
        }
        .confirmationDialog("Bloquer \(otherName) ?", isPresented: $showBlock, titleVisibility: .visible) {
            Button("Bloquer", role: .destructive) { Task { await block() } }
            Button("Annuler", role: .cancel) {}
        }
        .onChange(of: photoItem) {
            guard let item = photoItem else { return }
            photoItem = nil
            Task { await sendPhoto(item) }
        }
        .task {
            await load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                await poll()
            }
        }
    }

    // MARK: Roles

    private var myId: UUID? { store.me?.id }

    private var iAmSeller: Bool {
        guard let listing, let myId else { return false }
        return listing.sellerId == myId
    }

    private var myParty: OfferParty { iAmSeller ? .seller : .buyer }

    private var otherName: String { other?.username ?? (iAmSeller ? "L'acheteuse" : "La vendeuse") }

    private var otherUserId: UUID? { conversation?.otherUserId ?? other?.id }

    private var purchaseBlocker: PurchaseAvailability.Blocker? {
        guard let listing else { return nil }
        return PurchaseAvailability.blocker(for: listing, me: myId)
    }

    private var refuseShown: Binding<Bool> {
        Binding(get: { refusing != nil }, set: { if !$0 { refusing = nil } })
    }

    // MARK: Data

    private func load() async {
        loadError = nil
        do {
            messages = try await store.repo.messages(conversationId: conversationId)
            await resolveMetadata()
            thread = await fetchThread()
            applyNegotiatedPrice()
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
        await refreshListing()
    }

    private func refreshListing() async {
        guard let lid = conversation?.listingId else { return }
        let fetched = try? await store.repo.listing(id: lid)
        if let fetched, fetched != listing { listing = fetched }
    }

    /// Buyer side: my thread on this listing. Seller side: the thread of this buyer on my listing.
    private func fetchThread() async -> OfferThread? {
        guard let listing, let myId else { return nil }
        if listing.sellerId == myId {
            guard let buyer = otherUserId else { return nil }
            let all = (try? await store.repo.offerThreads(role: .seller)) ?? []
            return all.filter { $0.listingId == listing.id && $0.buyerId == buyer }
                .max { $0.updatedAt < $1.updatedAt }
        }
        let mine = try? await store.repo.offerThread(listingId: listing.id)
        return mine ?? nil
    }

    private func applyNegotiatedPrice() {
        guard !iAmSeller, let listing, let amount = thread?.acceptedAmount else { return }
        store.negotiatedPrices[listing.id] = amount
    }

    private func poll() async {
        pollCount += 1
        if conversation == nil { await resolveMetadata() }
        if pollCount % 3 == 0 { await refreshListing() }

        let freshThread = await fetchThread()
        if freshThread != thread {
            let previous = thread
            withAnimation(.snappy) { thread = freshThread }
            applyNegotiatedPrice()
            if let t = freshThread, t.rounds.count > (previous?.rounds.count ?? 0), t.rounds.last?.by != myParty {
                receivedTick += 1
            }
            await store.refreshBadges()
        }

        guard let fresh = try? await store.repo.messages(conversationId: conversationId) else { return }
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

    // MARK: Sending

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

    private func sendPhoto(_ item: PhotosPickerItem) async {
        guard !isSendingPhoto else { return }
        isSendingPhoto = true
        defer { isSendingPhoto = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = Self.jpeg(image) else {
                store.show("Photo illisible.")
                return
            }
            let msg = try await store.repo.sendPhoto(jpeg, conversationId: conversationId)
            if !messages.contains(where: { $0.id == msg.id }) {
                withAnimation(.snappy) { messages.append(msg) }
            }
            sentTick += 1
        } catch {
            Haptics.error()
            store.show(error)
        }
    }

    /// Downscaled JPEG (longest side ≤ 1600 px).
    private static func jpeg(_ image: UIImage, maxSide: CGFloat = 1_600) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.75)
    }

    // MARK: Negotiation actions

    /// Buyer accepts the seller's counter = offers exactly its amount (the server records an acceptance).
    private func acceptCounter(_ t: OfferThread) async {
        guard let counter = t.lastSellerCounter, !offerBusy else { return }
        offerBusy = true
        defer { offerBusy = false }
        do {
            let updated = try await store.repo.makeOffer(listingId: t.listingId, amount: counter.amount)
            withAnimation(.snappy) { thread = updated }
            applyNegotiatedPrice()
            if updated.status == .accepted { Haptics.success() }
            await refreshListing()
            await store.refreshBadges()
        } catch {
            Haptics.error()
            store.show(error)
            thread = await fetchThread()
        }
    }

    /// Seller answers the buyer's offer.
    private func respond(_ t: OfferThread, _ action: OfferAction, amount: FCFA? = nil) async {
        guard !offerBusy else { return }
        offerBusy = true
        defer { offerBusy = false }
        do {
            let updated = try await store.repo.respondToOffer(threadId: t.id, action: action, amount: amount)
            withAnimation(.snappy) { thread = updated }
            switch action {
            case .accept: Haptics.success(); store.show("Offre acceptée")
            case .refuse: Haptics.warning(); store.show("Offre refusée")
            case .counter: Haptics.success(); store.show("Contre-offre envoyée")
            case .offer: break
            }
            await refreshListing()
            await store.refreshBadges()
        } catch {
            Haptics.error()
            store.show(error)
            thread = await fetchThread()
        }
    }

    private func pay(_ t: OfferThread) {
        if let amount = t.acceptedAmount { store.negotiatedPrices[t.listingId] = amount }
        router.push(.checkout(t.listingId))
    }

    /// Seller counter-offer bounds: strictly between the buyer's last offer and the listed price.
    private func counterRange(_ t: OfferThread) -> ClosedRange<FCFA>? {
        guard let listing, let last = t.lastBuyerOffer?.amount else { return nil }
        let step = OfferRules.step(for: listing.price)
        let lower = last + step
        let upper = listing.price - step
        return lower <= upper ? lower...upper : nil
    }

    private func startCounter(_ t: OfferThread) {
        guard let listing, let range = counterRange(t) else {
            store.show("Pas de marge")
            return
        }
        let step = OfferRules.step(for: listing.price)
        let mid = OfferRules.round(Double((t.lastBuyerOffer?.amount ?? range.lowerBound) + listing.price) / 2, step: step)
        counterAmount = min(max(mid, range.lowerBound), range.upperBound)
        counterTarget = t
    }

    // MARK: Moderation

    private func report(_ reason: ReportReason) async {
        guard let uid = otherUserId else { return }
        do {
            try await store.repo.report(listingId: nil, userId: uid, reason: reason, details: "")
            store.show("Signalement envoyé")
        } catch {
            store.show(error)
        }
    }

    private func block() async {
        guard let uid = otherUserId else { return }
        do {
            try await store.repo.block(userId: uid)
            Haptics.warning()
            store.show("Bloquée")
            await store.refreshBadges()
            router.pop()
        } catch {
            store.show(error)
        }
    }

    // MARK: Title & menu

    private var titleView: some View {
        Button {
            if let other { router.push(.sellerProfile(other.id)) }
        } label: {
            HStack(spacing: 8) {
                Avatar(profile: other, size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(other?.username ?? "Conversation")
                            .font(RF.T.subheadline.weight(.semibold))
                            .foregroundStyle(RF.C.text)
                            .lineLimit(1)
                        if other?.verified == true { VerifiedBadge(size: 11) }
                    }
                    if let minutes = other?.responseTimeMinutes {
                        Text("Répond en ~\(Self.responseLabel(minutes))")
                            .font(RF.T.caption)
                            .foregroundStyle(RF.C.textDim)
                    }
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(other == nil)
        .accessibilityLabel(other.map { "Profil de \($0.username)" } ?? "Conversation")
    }

    private var moreMenu: some View {
        Menu {
            Button("Signaler", systemImage: "flag") { showReport = true }
            Button("Bloquer", systemImage: "hand.raised", role: .destructive) { showBlock = true }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(otherUserId == nil)
        .accessibilityLabel("Plus d'options")
    }

    private static func responseLabel(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h"
    }

    // MARK: Timeline

    private enum ItemKind {
        case message(ChatMessage)
        case offer(OfferThread, Int)
    }

    private struct Item: Identifiable {
        let id: String
        let date: Date
        let kind: ItemKind
        let isMine: Bool
        var dayLabel: String?
        var showTime = true
        var receipt: String?
        var gapAbove: CGFloat = 10
        var senderId: UUID?
    }

    /// Messages and offer rounds merged by date, with day separators, runs and « Vu / Envoyé ».
    private var items: [Item] {
        var list: [Item] = messages.map { m in
            Item(id: m.id.uuidString, date: m.sentAt, kind: .message(m), isMine: m.senderId == myId, senderId: m.senderId)
        }
        if let thread {
            for (i, r) in thread.rounds.enumerated() {
                // Stable id: round ids may be regenerated by the backend mapping.
                list.append(Item(id: "offer-\(thread.id.uuidString)-\(i)", date: r.at, kind: .offer(thread, i),
                                 isMine: r.by == myParty))
            }
        }
        list.sort { $0.date < $1.date }

        let cal = Calendar.current
        let lastMineMessage = list.lastIndex { item in
            if case .message = item.kind { return item.isMine }
            return false
        }
        for i in list.indices {
            let prev = i > 0 ? list[i - 1] : nil
            let next = i + 1 < list.count ? list[i + 1] : nil
            let newDay = prev.map { !cal.isDate($0.date, inSameDayAs: list[i].date) } ?? true
            list[i].dayLabel = newDay ? Self.dayLabel(list[i].date) : nil
            guard case .message = list[i].kind else { continue }
            let sameRun = !newDay && prev?.senderId != nil && prev?.senderId == list[i].senderId
                && list[i].date.timeIntervalSince(prev?.date ?? list[i].date) < 5 * 60
            list[i].gapAbove = i == 0 || newDay ? 0 : (sameRun ? 3 : 10)
            if let next, next.senderId == list[i].senderId, cal.isDate(next.date, inSameDayAs: list[i].date),
               next.date.timeIntervalSince(list[i].date) < 5 * 60 {
                list[i].showTime = false
            }
            if i == lastMineMessage {
                let answered = list[(i + 1)...].contains { item in
                    if case .message = item.kind { return !item.isMine }
                    return false
                }
                list[i].receipt = answered ? "Vu" : "Envoyé"
            }
        }
        return list
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

    private var timeline: some View {
        let all = items
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if all.isEmpty { emptyHint }
                    ForEach(all) { item in
                        itemView(item)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(.horizontal, RF.S.gutter)
                .padding(.top, 4)
                .padding(.bottom, 14)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: all.count) {
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
                .font(RF.T.title)
                .foregroundStyle(RF.C.textDim)
            Text("Nouvelle conversation")
                .font(RF.T.headline)
                .foregroundStyle(RF.C.text)
                    }
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func itemView(_ item: Item) -> some View {
        if let day = item.dayLabel {
            Text(day)
                .font(RF.T.caption.weight(.semibold))
                .foregroundStyle(RF.C.textDim)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
        }
        switch item.kind {
        case .message(let m):
            messageView(m, item: item)
        case .offer(let t, let index):
            ChatOfferBubble(thread: t, index: index, me: myParty, otherName: otherName, listing: listing,
                            busy: offerBusy, canPay: purchaseBlocker == nil,
                            onAccept: {
                                Task {
                                    if myParty == .buyer { await acceptCounter(t) } else { await respond(t, .accept) }
                                }
                            },
                            onPropose: {
                                if myParty == .buyer { showOfferComposer = true } else { startCounter(t) }
                            },
                            onRefuse: { refusing = t },
                            onPay: { pay(t) })
                .padding(.top, item.dayLabel == nil ? 10 : 0)
                .transition(.opacity)
        }
    }

    private func messageView(_ m: ChatMessage, item: Item) -> some View {
        VStack(alignment: item.isMine ? .trailing : .leading, spacing: 3) {
            if m.photo != nil { photoBubble(m, isMine: item.isMine) }
            if !m.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { textBubble(m.text, isMine: item.isMine) }
            if item.showTime || item.receipt != nil {
                HStack(spacing: 4) {
                    if item.showTime { Text(Self.time(m.sentAt)) }
                    if let receipt = item.receipt {
                        if item.showTime { Text("·") }
                        Text(receipt).fontWeight(receipt == "Vu" ? .bold : .regular)
                    }
                }
                .font(RF.T.caption.monospacedDigit())
                .foregroundStyle(RF.C.textDim)
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: item.isMine ? .trailing : .leading)
        .padding(.top, item.gapAbove)
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibility(m, item: item))
    }

    private func textBubble(_ text: String, isMine: Bool) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 16,
                                           bottomLeadingRadius: isMine ? 16 : 4,
                                           bottomTrailingRadius: isMine ? 4 : 16,
                                           topTrailingRadius: 16,
                                           style: .continuous)
        return Text(text)
            .font(RF.T.body)
            .foregroundStyle(RF.C.text)
            .textSelection(.enabled)
            .padding(.vertical, 9)
            .padding(.horizontal, 13)
            .background(isMine ? RF.C.hibiscus.opacity(0.14) : RF.C.paperDim, in: shape)
            .containerRelativeFrame(.horizontal, alignment: isMine ? .trailing : .leading) { length, _ in
                length * 0.76
            }
    }

    private func photoBubble(_ m: ChatMessage, isMine: Bool) -> some View {
        ListingPhotoView(photo: m.photo, listingId: m.id)
            .frame(width: 210, height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(RF.C.line, lineWidth: 1)
            }
    }

    private func accessibility(_ m: ChatMessage, item: Item) -> String {
        let who = item.isMine ? "Toi" : otherName
        var parts = [who]
        if m.photo != nil { parts.append("Photo") }
        if !m.text.isEmpty { parts.append(m.text) }
        parts.append(Self.time(m.sentAt))
        if let receipt = item.receipt { parts.append(receipt) }
        return parts.joined(separator: ", ")
    }

    // MARK: Listing context (always visible)

    private func contextHeader(_ listing: Listing) -> some View {
        let price = iAmSeller ? listing.price : (store.negotiatedPrices[listing.id] ?? listing.price)
        let blocker = purchaseBlocker
        return HStack(spacing: 10) {
            Button {
                router.push(.product(listing.id))
            } label: {
                HStack(spacing: 10) {
                    ListingPhotoView(photo: listing.photos.first, listingId: listing.id)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(listing.title)
                            .font(RF.T.subheadline.weight(.semibold))
                            .foregroundStyle(RF.C.text)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Text(Fmt.fcfa(price))
                                .font(RF.T.price(.footnote))
                                .foregroundStyle(RF.C.text)
                            if price != listing.price {
                                Text(Fmt.fcfa(listing.price))
                                    .font(RF.T.price(.caption, weight: .regular))
                                    .strikethrough()
                                    .foregroundStyle(RF.C.textDim)
                            }
                        }
                        if let tag = statusTag(listing, blocker: blocker) {
                            Text(tag)
                                .font(RF.T.caption)
                                .foregroundStyle(RF.C.textDim)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Ouvre l'annonce")

            if !iAmSeller {
                Button {
                    if let amount = thread?.acceptedAmount { store.negotiatedPrices[listing.id] = amount }
                    router.push(.checkout(listing.id))
                } label: {
                    Text("Acheter")
                        .font(RF.T.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(RF.C.hibiscus))
                        .opacity(blocker == nil ? 1 : 0.4)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RFPressStyle(scale: 0.94))
                .disabled(blocker != nil)
                .accessibilityLabel("Acheter \(listing.title)")
                .accessibilityHint(blocker?.message ?? "")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, RF.S.gutter)
        .background {
            RF.C.card
                .overlay(alignment: .bottom) { Rectangle().fill(RF.C.line).frame(height: 1) }
        }
    }

    /// One short line under the price: why « Acheter » is disabled, or the negotiation state.
    private func statusTag(_ listing: Listing, blocker: PurchaseAvailability.Blocker?) -> String? {
        if iAmSeller {
            switch listing.status {
            case .sold: return "Vendu"
            case .removed: return "Retiré"
            case .reserved: return "Réservé"
            case .active:
                if let until = listing.reservedUntil, until > .now { return "Réservé · \(Fmt.hourMinute(until))" }
                return "Ton annonce"
            }
        }
        if let blocker { return blocker.message }
        if PurchaseAvailability.isReservedForMe(listing, me: myId), let until = listing.reservedUntil {
            return "Réservé pour toi · \(Fmt.hourMinute(until))"
        }
        if store.negotiatedPrices[listing.id] != nil { return "Prix négocié" }
        return nil
    }

    // MARK: Input

    /// « Faire une offre » is offered when the buyer can actually make one now.
    private var canMakeOffer: Bool {
        guard !iAmSeller, let listing, listing.negotiable, purchaseBlocker == nil else { return false }
        guard let thread else { return true }
        return thread.status == .pending && thread.rounds.last?.by == .seller
            && thread.buyerOfferCount < OfferRules.maxBuyerOffers
    }

    private var showQuickReplies: Bool { draft.isEmpty && conversation != nil }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if showQuickReplies {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        if canMakeOffer {
                            Chip("Faire une offre", symbol: "tag") { showOfferComposer = true }
                        }
                        Chip(Self.meetReply) { Task { await send(Self.meetReply) } }
                            .disabled(isSending)
                    }
                    .padding(.horizontal, RF.S.gutter)
                }
                .scrollIndicators(.hidden)
                .transition(.opacity)
            }
            HStack(spacing: 6) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Group {
                        if isSendingPhoto {
                            ProgressView()
                        } else {
                            Image(systemName: "camera")
                                .font(RF.T.body)
                                .foregroundStyle(RF.C.text)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .disabled(isSendingPhoto)
                .accessibilityLabel("Envoyer une photo")

                TextField("Message", text: $draft)
                    .font(RF.T.body)
                    .foregroundStyle(RF.C.text)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        Task { await send(draft) }
                        inputFocused = true
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(RF.C.card))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(RF.C.line, lineWidth: 1))

                Button {
                    Task { await send(draft) }
                } label: {
                    Group {
                        if isSending {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(RF.T.body.weight(.bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(RF.C.hibiscus))
                    .opacity(canSend || isSending ? 1 : 0.45)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RFPressStyle(scale: 0.9))
                .disabled(!canSend)
                .accessibilityLabel("Envoyer")
            }
            .padding(.leading, RF.S.gutter - 8)
            .padding(.trailing, RF.S.gutter - 4)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background {
            RF.C.paper
                .overlay(alignment: .top) { Rectangle().fill(RF.C.line).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(.snappy(duration: 0.2), value: showQuickReplies)
    }

    // MARK: Sheets

    @ViewBuilder private var offerComposerSheet: some View {
        if let lid = listing?.id ?? conversation?.listingId {
            NavigationStack {
                OfferComposerView(listingId: lid,
                                  onSent: { sent in
                                      showOfferComposer = false
                                      withAnimation(.snappy) { thread = sent }
                                  },
                                  onClose: { showOfferComposer = false })
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Fermer") { showOfferComposer = false }
                        }
                    }
            }
            .environment(store)
            .environment(router)
            .presentationDetents([.large])
        }
    }

    private func counterSheet(_ t: OfferThread) -> some View {
        let range = counterRange(t)
        let step = listing.map { OfferRules.step(for: $0.price) } ?? 250
        return NavigationStack {
            VStack(spacing: RF.S.lg) {
                if let last = t.lastBuyerOffer {
                    Text("Son offre : \(Fmt.fcfa(last.amount))")
                        .font(RF.T.subheadline)
                        .foregroundStyle(RF.C.textDim)
                }
                if let range {
                    PriceStepper(value: $counterAmount, step: step, range: range)
                    RFButton("Envoyer", isLoading: offerBusy) {
                        let amount = min(max(counterAmount, range.lowerBound), range.upperBound)
                        Task {
                            await respond(t, .counter, amount: amount)
                            counterTarget = nil
                        }
                    }
                    .accessibilityLabel("Envoyer \(Fmt.fcfa(counterAmount))")
                } else {
                    Text("Pas de marge")
                        .font(RF.T.subheadline)
                        .foregroundStyle(RF.C.textDim)
                }
            }
            .padding(RF.S.gutter)
            .frame(maxHeight: .infinity, alignment: .top)
            .rfScreenBackground()
            .navigationTitle("Contre-offre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { counterTarget = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview("Fatou K. (Awa vendeuse)") {
    NavigationStack { ChatThreadView(conversationId: DemoIDs.conversationRobeWax) }.previewEnvironment()
}

#Preview("SneakDak (Awa acheteuse)") {
    NavigationStack { ChatThreadView(conversationId: DemoIDs.conversationBaskets) }.previewEnvironment()
}
