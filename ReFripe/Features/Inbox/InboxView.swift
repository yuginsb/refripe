import SwiftUI

/// « Boîte » tab: Messages · Commandes · Notifications. The selected segment lives in the router so
/// deep links and notifications can open the right one (`router.openInbox(.orders)`).
struct InboxView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        Group {
            switch router.inboxSegment {
            case .messages: ConversationList()
            case .orders: InboxOrdersList()
            case .notifications: NotificationsList()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Afficher", selection: $router.inboxSegment) {
                ForEach(InboxSegment.allCases) { segment in
                    Text(segment.label).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, RF.S.gutter)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .background(RF.C.paper)
        }
        .rfScreenBackground()
        .navigationTitle("Boîte")
        // Inline: a large title collapses unpredictably above the pinned segmented control.
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: router.inboxSegment)
        .task(id: router.inboxSegment) { await store.refreshBadges() }
    }
}

#Preview {
    NavigationStack { InboxView().withAppRoutes() }
        .previewEnvironment()
}
