import SwiftUI

/// "Swipe" mode of Découvrir: a stack of up to 3 cards,
/// drag right = like (joins the wishlist), drag left = pass, with ✕ / ♥ buttons below.
struct DiscoverSwipeSection: View {
    let onShowGrid: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var deck: [Listing] = []
    @State private var hasLoaded = false
    /// User + categories the deck was loaded for: signing in from the onboarding cover must reload it
    /// (own listings excluded, preferred categories first).
    @State private var loadedFor: String?
    @State private var loadError: Error?
    @State private var drag: CGSize = .zero
    @State private var isFlying = false
    @State private var likeTick = 0
    @State private var passTick = 0
    @State private var burstToken: UUID?

    /// Horizontal distance (pt) past which releasing the card commits the swipe (mockup: 110 px).
    private let threshold: CGFloat = 110

    var body: some View {
        VStack(spacing: 0) {
            if !hasLoaded {
                LoadingView()
            } else if let loadError, deck.isEmpty {
                ErrorStateView(error: loadError) { Task { await load() } }
                Spacer(minLength: 0)
            } else if deck.isEmpty {
                ScrollView {
                    ContentUnavailableView {
                        Label("Tu as tout vu", systemImage: "checkmark.circle")
                    } description: {
                        Text("Reviens plus tard ou parcours la grille.")
                    } actions: {
                        Button("Voir la grille", action: onShowGrid)
                            .buttonStyle(.borderedProminent)
                            .tint(RF.C.hibiscus)
                    }
                    .padding(.top, 40)
                }
                .refreshable { await load() }
            } else {
                stack
                    .padding(EdgeInsets(top: RF.S.sm, leading: RF.S.gutter, bottom: 0, trailing: RF.S.gutter))
                actions
                    .padding(.top, RF.S.lg)
                    .padding(.bottom, RF.S.lg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            if let burstToken {
                SwipeHeartBurst().id(burstToken)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: likeTick)
        .sensoryFeedback(.impact(weight: .light), trigger: passTick)
        .sensoryFeedback(.selection, trigger: crossedSide) { _, new in new != 0 }
        .task(id: deckKey) {
            if !hasLoaded || loadedFor != deckKey { await load() }
        }
    }

    // MARK: Data

    private var deckKey: String {
        "\(store.me?.id.uuidString ?? "-")|\(store.preferences.categories.map(\.rawValue).sorted())"
    }

    private func load() async {
        loadedFor = deckKey
        do {
            let items = try await store.repo.swipeDeck(preferences: store.preferences)
            deck = items
            loadError = nil
        } catch {
            loadError = error
        }
        hasLoaded = true
    }

    // MARK: Card stack

    /// −1 when the top card is past the pass threshold, +1 past the like threshold, else 0.
    private var crossedSide: Int {
        if drag.width > threshold { return 1 }
        if drag.width < -threshold { return -1 }
        return 0
    }

    private var stack: some View {
        let visible = Array(deck.prefix(3).enumerated())
        return ZStack {
            ForEach(visible, id: \.element.id) { pair in
                let depth = pair.offset
                card(pair.element, depth: depth)
            }
            if !store.preferences.swipeCoachSeen {
                SwipeCoachOverlay {
                    withAnimation(.easeOut(duration: 0.2)) {
                        store.updatePreferences { $0.swipeCoachSeen = true }
                    }
                }
                .zIndex(50)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 300, idealHeight: 420, maxHeight: 470)
    }

    @ViewBuilder
    private func card(_ listing: Listing, depth: Int) -> some View {
        let isTop = depth == 0
        let likeOpacity = isTop ? min(1, max(0, drag.width / 90)) : 0
        let passOpacity = isTop ? min(1, max(0, -drag.width / 90)) : 0
        let baseOpacity: Double = depth == 2 ? 0.55 : 1

        SwipeCardView(listing: listing, likeOpacity: likeOpacity, passOpacity: passOpacity)
            .scaleEffect(isTop ? 1 : 1 - CGFloat(depth) * 0.045)
            .offset(y: isTop ? 0 : CGFloat(depth) * 10)
            .offset(isTop ? drag : .zero)
            .rotationEffect(.degrees(isTop ? Double(drag.width / 18) : 0))
            .opacity(isTop && isFlying ? 0 : baseOpacity)
            .zIndex(Double(10 - depth))
            .allowsHitTesting(isTop && !isFlying)
            .transition(.asymmetric(insertion: .opacity, removal: .identity))
            .onTapGesture { router.push(.product(listing.id)) }
            .gesture(dragGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cardAccessibilityLabel(listing))
            .accessibilityHint("Touche deux fois pour ouvrir l'annonce. Utilise les actions pour aimer ou passer.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { router.push(.product(listing.id)) }
            .accessibilityAction(named: "J'aime") { fly(liked: true) }
            .accessibilityAction(named: "Passer") { fly(liked: false) }
            .accessibilityHidden(!isTop)
            .accessibilityIdentifier(isTop ? "discover.swipe.topCard" : "discover.swipe.card")
    }

    private func cardAccessibilityLabel(_ l: Listing) -> String {
        var parts = [l.title, Fmt.fcfa(l.price), l.sizeLabel, l.locationLabel]
        if l.isLastPiece { parts.append("Dernière pièce") }
        else if l.views > 150 { parts.append("\(l.views) vues aujourd'hui") }
        return parts.joined(separator: ", ")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isFlying else { return }
                drag = value.translation
            }
            .onEnded { value in
                guard !isFlying else { return }
                let dx = value.translation.width
                let projected = value.predictedEndTranslation.width
                if dx > threshold || (dx > 40 && projected > threshold * 2.5) {
                    fly(liked: true, dy: value.translation.height)
                } else if dx < -threshold || (dx < -40 && projected < -threshold * 2.5) {
                    fly(liked: false, dy: value.translation.height)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { drag = .zero }
                }
            }
    }

    // MARK: Actions (mockup `.swipe-actions`)

    private var actions: some View {
        HStack(spacing: 32) {
            Button { fly(liked: false) } label: {
                Image(systemName: "xmark")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(RF.C.text)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(RF.C.card))
                    .overlay(Circle().strokeBorder(RF.C.line, lineWidth: 1))
            }
            .accessibilityLabel("Passer")

            Button { fly(liked: true) } label: {
                Image(systemName: "heart.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(RF.C.hibiscus))
            }
            .accessibilityLabel("J'aime, ajouter aux envies")
        }
        .buttonStyle(RFPressStyle(scale: 0.9))
        .disabled(isFlying || deck.isEmpty)
    }

    // MARK: Swipe logic

    private func fly(liked: Bool, dy: CGFloat = 0) {
        guard let top = deck.first, !isFlying else { return }
        if !store.preferences.swipeCoachSeen {
            store.updatePreferences { $0.swipeCoachSeen = true }
        }
        isFlying = true
        if liked { likeTick += 1 } else { passTick += 1 }
        let target = CGSize(width: liked ? 520 : -520, height: dy)
        if reduceMotion {
            drag = target
            commit(top, liked: liked)
            return
        }
        withAnimation(.easeOut(duration: 0.28)) {
            drag = target
        } completion: {
            commit(top, liked: liked)
        }
    }

    private func commit(_ listing: Listing, liked: Bool) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            deck.removeAll { $0.id == listing.id }
            drag = .zero
            isFlying = false
        }
        if liked {
            store.setLiked(listing.id, true)
            burstToken = UUID()
            let token = burstToken
            Task {
                try? await Task.sleep(for: .milliseconds(750))
                if burstToken == token { burstToken = nil }
            }
        }
        Task {
            do { try await store.repo.recordSwipe(listingId: listing.id, liked: liked) }
            catch { store.show(error) }
        }
    }
}

// MARK: - Card

private struct SwipeCardView: View {
    let listing: Listing
    let likeOpacity: Double
    let passOpacity: Double

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RF.R.xl, style: .continuous)
        VStack(spacing: 0) {
            ListingPhotoView(photo: listing.photos.first, listingId: listing.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottomLeading) {
                    ListingScarcityTag(listing: listing).padding(RF.S.md)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.fcfa(listing.price))
                    .font(RF.T.price(.title3))
                    .foregroundStyle(RF.C.text)
                Text(listing.title)
                    .font(RF.T.body)
                    .foregroundStyle(RF.C.text)
                    .lineLimit(1)
                Text("\(listing.sizeLabel) · \(listing.district)")
                    .font(RF.T.footnote)
                    .foregroundStyle(RF.C.textDim)
                    .lineLimit(1)
            }
            .padding(EdgeInsets(top: RF.S.md, leading: RF.S.lg, bottom: RF.S.lg, trailing: RF.S.lg))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RF.C.card)
        }
        .background(RF.C.card)
        .clipShape(shape)
        .overlay(alignment: .topLeading) {
            SwipeStamp(text: "J'aime", color: RF.C.hibiscus, angle: -12)
                .opacity(likeOpacity)
                .padding(EdgeInsets(top: 20, leading: RF.S.lg, bottom: 0, trailing: 0))
        }
        .overlay(alignment: .topTrailing) {
            SwipeStamp(text: "Passer", color: RF.C.text, angle: 12)
                .opacity(passOpacity)
                .padding(EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: RF.S.lg))
        }
        .shadow(color: RF.C.text.opacity(0.12), radius: 12, y: 6)
        .contentShape(shape)
    }
}

private struct SwipeStamp: View {
    let text: String
    let color: Color
    let angle: Double

    var body: some View {
        Text(text)
            .font(RF.T.title3)
            .foregroundStyle(color)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(color, lineWidth: 2))
            .rotationEffect(.degrees(angle))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Heart burst

private struct SwipeHeartBurst: View {
    @State private var phase = 0

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 56))
            .foregroundStyle(RF.C.hibiscus)
            .scaleEffect(phase == 0 ? 0.3 : (phase == 1 ? 1.2 : 1))
            .offset(y: phase == 0 ? 0 : (phase == 1 ? -24 : -90))
            .opacity(phase == 1 ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                withAnimation(.easeOut(duration: 0.25)) { phase = 1 }
                try? await Task.sleep(for: .milliseconds(250))
                withAnimation(.easeIn(duration: 0.45)) { phase = 2 }
            }
    }
}

// MARK: - First-use coach

private struct SwipeCoachOverlay: View {
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wave = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: RF.R.xl, style: .continuous)
                .fill(RF.C.scrim)
            VStack(alignment: .leading, spacing: RF.S.md) {
                HStack(spacing: RF.S.sm) {
                    Image(systemName: "hand.draw")
                        .font(.title3)
                        .foregroundStyle(RF.C.text)
                        .rotationEffect(.degrees(wave ? 7 : -7))
                        .accessibilityHidden(true)
                    Text("Glisse la carte")
                        .font(RF.T.headline)
                        .foregroundStyle(RF.C.text)
                        .accessibilityAddTraits(.isHeader)
                }
                row(symbol: "arrow.left", text: "À gauche : tu passes")
                row(symbol: "arrow.right", text: "À droite : dans tes envies")
                RFButton("J'ai compris", action: onDismiss)
                    .padding(.top, RF.S.xs)
            }
            .padding(RF.S.lg)
            .background(RF.C.card, in: RoundedRectangle(cornerRadius: RF.R.lg, style: .continuous))
            .padding(RF.S.lg)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { wave = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func row(symbol: String, text: String) -> some View {
        Label {
            Text(text).foregroundStyle(RF.C.text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(RF.C.textDim)
        }
        .font(RF.T.subheadline)
    }
}

#Preview {
    NavigationStack {
        DiscoverSwipeSection {}
            .rfScreenBackground()
            .withAppRoutes()
    }
    .previewEnvironment()
}
