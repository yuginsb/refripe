import SwiftUI

/// "Swipe" mode of Découvrir (mockup `swipeSection` + gestures): a stack of up to 3 cards,
/// drag right = like (joins the wishlist), drag left = pass, with ✕ / ♥ buttons below.
struct DiscoverSwipeSection: View {
    let dropDate: Date?
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
                    DropCountdownBanner(date: dropDate)
                        .padding(EdgeInsets(top: 12, leading: RF.S.gutter, bottom: 4, trailing: RF.S.gutter))
                    EmptyStateView(symbol: "sparkles",
                                   title: "Tu as tout vu pour aujourd'hui",
                                   message: "Reviens dans quelques heures pour de nouvelles pièces, ou parcours tout le catalogue en grille dès maintenant.",
                                   actionTitle: "Voir la grille",
                                   action: onShowGrid)
                }
                .refreshable { await load() }
            } else {
                DropCountdownBanner(date: dropDate)
                    .padding(EdgeInsets(top: 12, leading: RF.S.gutter, bottom: 4, trailing: RF.S.gutter))
                stack
                    .padding(EdgeInsets(top: 14, leading: RF.S.gutter, bottom: 0, trailing: RF.S.gutter))
                actions
                    .padding(.top, 16)
                    .padding(.bottom, 14)
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
        .frame(minHeight: 300, idealHeight: 398, maxHeight: 440)
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
        HStack(spacing: 26) {
            Button { fly(liked: false) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(RF.C.hibiscus)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(RF.C.card))
                    .overlay(Circle().strokeBorder(RF.C.line, lineWidth: 2))
                    .shadow(color: RF.C.text.opacity(0.25), radius: 9, y: 6)
            }
            .accessibilityLabel("Passer")

            Button { fly(liked: true) } label: {
                Image(systemName: "heart.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(RF.C.hibiscus))
                    .shadow(color: RF.C.text.opacity(0.3), radius: 9, y: 6)
            }
            .accessibilityLabel("J'aime, ajouter aux envies")
        }
        .buttonStyle(RFPressStyle(scale: 0.88))
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

// MARK: - Card (mockup `.swipe-card`)

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
                    ListingScarcityTag(listing: listing).padding(10)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(Fmt.fcfa(listing.price))
                    .font(RF.F.mono(19, .semibold))
                    .foregroundStyle(RF.C.text)
                Text(listing.title)
                    .font(RF.F.body(13, .bold))
                    .foregroundStyle(RF.C.text)
                    .lineLimit(1)
                Text("\(listing.sizeLabel) · \(listing.locationLabel)")
                    .font(RF.F.body(11))
                    .foregroundStyle(RF.C.textDim)
                    .lineLimit(1)
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RF.C.card)
        }
        .background(RF.C.card)
        .clipShape(shape)
        .overlay(shape.strokeBorder(RF.C.line, lineWidth: 1))
        .overlay(alignment: .topLeading) {
            SwipeStamp(text: "J'AIME", color: RF.C.money, angle: -14)
                .opacity(likeOpacity)
                .padding(EdgeInsets(top: 18, leading: 16, bottom: 0, trailing: 0))
        }
        .overlay(alignment: .topTrailing) {
            SwipeStamp(text: "PASSE", color: RF.C.hibiscus, angle: 14)
                .opacity(passOpacity)
                .padding(EdgeInsets(top: 18, leading: 0, bottom: 0, trailing: 16))
        }
        .shadow(color: RF.C.text.opacity(0.22), radius: 15, y: 12)
        .contentShape(shape)
    }
}

private struct SwipeStamp: View {
    let text: String
    let color: Color
    let angle: Double

    var body: some View {
        Text(text)
            .font(RF.F.display(14, .extraBold))
            .kerning(0.5)
            .foregroundStyle(color)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(color, lineWidth: 3))
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.75)))
            .rotationEffect(.degrees(angle))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Heart burst (mockup `.heart-burst`)

private struct SwipeHeartBurst: View {
    @State private var phase = 0

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 58))
            .foregroundStyle(RF.C.hibiscus)
            .shadow(color: RF.C.hibiscus.opacity(0.35), radius: 10)
            .scaleEffect(phase == 0 ? 0.3 : (phase == 1 ? 1.25 : 1))
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

// MARK: - First-use coach (mockup `swipeCoachHTML`)

private struct SwipeCoachOverlay: View {
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wave = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: RF.R.xl, style: .continuous)
                .fill(RF.C.ink0.opacity(0.58))
            VStack(spacing: 0) {
                Image(systemName: "hand.draw")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(RF.C.hibiscus)
                    .rotationEffect(.degrees(wave ? 7 : -7))
                    .offset(x: wave ? 5 : -5)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(RF.C.paperDim))
                    .padding(.bottom, 12)
                    .accessibilityHidden(true)
                Text("Glisse la carte")
                    .font(RF.F.display(14.5))
                    .foregroundStyle(RF.C.text)
                    .padding(.bottom, 14)
                row(symbol: "arrow.left", tint: RF.C.textDim, text: "Vers la gauche, tu passes l'article")
                row(symbol: "arrow.right", tint: RF.C.hibiscus, text: "Vers la droite, il rejoint tes envies")
                Text("Les deux boutons en dessous font la même chose.")
                    .font(RF.F.body(10.5))
                    .foregroundStyle(RF.C.textDim)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .padding(.bottom, 14)
                RFButton("J'ai compris", action: onDismiss)
            }
            .padding(EdgeInsets(top: 20, leading: 18, bottom: 18, trailing: 18))
            .background(RF.C.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(16)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { wave = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func row(symbol: String, tint: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint))
                .accessibilityHidden(true)
            Text(text)
                .font(RF.F.body(11.5))
                .foregroundStyle(RF.C.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 9)
    }
}

#Preview {
    NavigationStack {
        DiscoverSwipeSection(dropDate: .now.addingTimeInterval(3_600)) {}
            .rfScreenBackground()
            .withAppRoutes()
    }
    .previewEnvironment()
}
