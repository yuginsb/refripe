import SwiftUI

/// Tab "Découvrir" (mockup `screenDecouvrir`): greeting + streak + bell, Swipe / Grille switch,
/// live "nouveaux arrivages" countdown, then the swipe deck or the filterable grid.
struct DiscoverView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case swipe, grid
        var id: String { rawValue }
        var title: String { self == .swipe ? "Swipe" : "Grille" }
    }

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var mode: Mode = .swipe
    @State private var filters = ListingFilters()
    @State private var dropDate: Date?
    @Namespace private var segmentNS

    var body: some View {
        VStack(spacing: 0) {
            header
            segmented
            switch mode {
            case .swipe:
                DiscoverSwipeSection(dropDate: dropDate) {
                    withAnimation(.snappy) { mode = .grid }
                }
                .transition(.opacity)
            case .grid:
                DiscoverGridSection(filters: $filters, dropDate: dropDate)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .rfScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("Découvrir")
        .task {
            if dropDate == nil { dropDate = try? await store.repo.nextDropDate() }
            await store.refreshBadges()
        }
    }

    // MARK: Header (mockup `.disc-header`)

    private var firstName: String {
        let name = store.me?.firstName.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? (store.me?.username ?? "toi") : name
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Salut \(firstName)")
                    .font(RF.F.display(15))
                    .foregroundStyle(RF.C.text)
                    .accessibilityAddTraits(.isHeader)
                if store.preferences.streakDays > 0 {
                    let n = store.preferences.streakDays
                    HStack(spacing: 5) {
                        Image(systemName: "flame.fill").font(.system(size: 11))
                        Text("Série de \(n) jour\(n > 1 ? "s" : "") de découverte")
                            .font(RF.F.body(10.5, .bold))
                    }
                    .foregroundStyle(RF.C.hibiscus)
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer()
            bellButton
        }
        .padding(EdgeInsets(top: 14, leading: RF.S.gutter, bottom: 2, trailing: RF.S.gutter))
    }

    private var bellButton: some View {
        let unread = store.unreadNotifications
        return Button {
            router.push(.notifications)
        } label: {
            Image(systemName: "bell")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RF.C.text)
                .frame(width: 34, height: 34)
                .background(Circle().fill(RF.C.paperDim))
                .overlay(alignment: .topTrailing) {
                    if unread > 0 {
                        Circle()
                            .fill(RF.C.hibiscus)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().strokeBorder(RF.C.paperDim, lineWidth: 1.5))
                            .offset(x: -6, y: 6)
                            .transition(.scale)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(RFPressStyle(scale: 0.9))
        .frame(minWidth: 44, minHeight: 44)
        .animation(.spring(response: 0.3), value: unread)
        .accessibilityLabel(unread > 0 ? "Notifications, \(unread) non lue\(unread > 1 ? "s" : "")" : "Notifications")
    }

    // MARK: Segmented control (mockup `.segmented`)

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(Mode.allCases) { m in
                let active = mode == m
                Button {
                    withAnimation(.snappy(duration: 0.25)) { mode = m }
                } label: {
                    Text(m.title)
                        .font(RF.F.body(12, .bold))
                        .foregroundStyle(active ? RF.C.text : RF.C.textDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if active {
                                Capsule()
                                    .fill(RF.C.card)
                                    .shadow(color: RF.C.text.opacity(0.1), radius: 3, y: 2)
                                    .matchedGeometryEffect(id: "segment", in: segmentNS)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(RF.C.paperDim))
        .padding(EdgeInsets(top: 10, leading: RF.S.gutter, bottom: 2, trailing: RF.S.gutter))
        .sensoryFeedback(.selection, trigger: mode)
    }
}

#Preview {
    NavigationStack {
        DiscoverView()
            .withAppRoutes()
    }
    .previewEnvironment()
}
