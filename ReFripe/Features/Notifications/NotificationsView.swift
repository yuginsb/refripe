import SwiftUI
import UIKit
import UserNotifications

/// `.notifications` route: the same list as Boîte › Notifications, as a pushed screen.
struct NotificationsView: View {
    var body: some View {
        NotificationsList()
            .rfScreenBackground()
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Boîte › Notifications: grouped list (Aujourd'hui / Plus tôt), unread dot, marked read on open,
/// deep links on tap, and a one-line row asking for push permission when it isn't granted.
struct NotificationsList: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    @State private var items: [AppNotification] = []
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var pushStatus: UNAuthorizationStatus?

    private var today: [AppNotification] { items.filter { Calendar.current.isDateInToday($0.createdAt) } }
    private var earlier: [AppNotification] { items.filter { !Calendar.current.isDateInToday($0.createdAt) } }

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                LoadingView()
            } else if let loadError, items.isEmpty {
                ErrorStateView(error: loadError) { Task { await load() } }
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await load() }
        .task { await refreshPushStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshPushStatus() } }
        }
    }

    private var list: some View {
        List {
            if let pushStatus, pushStatus == .notDetermined || pushStatus == .denied {
                Section {
                    PushPermissionRow(status: pushStatus) { await requestPush() }
                }
            }
            section("Aujourd'hui", today)
            section("Plus tôt", earlier)
        }
        .listStyle(.plain)
        .refreshable { await load() }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Rien de neuf", systemImage: "bell",
                                       description: Text("Baisses de prix, offres et messages arrivent ici."))
            }
        }
    }

    @ViewBuilder private func section(_ title: String, _ notifications: [AppNotification]) -> some View {
        if !notifications.isEmpty {
            Section {
                ForEach(notifications) { notification in
                    NotificationRow(notification: notification) { handleTap(notification) }
                        .listRowBackground(RF.C.paper)
                        .listRowSeparatorTint(RF.C.line)
                }
            } header: {
                Text(title)
                    .font(RF.T.footnote.weight(.semibold))
                    .foregroundStyle(RF.C.textDim)
                    .textCase(nil)
            }
        }
    }

    // MARK: Data

    private func load() async {
        do {
            // Keep the "unread" state of this fetch for display, then mark everything read server-side.
            items = try await store.repo.notifications()
            loadError = nil
            isLoading = false
            if items.contains(where: { !$0.read }) {
                try await store.repo.markNotificationsRead()
                await store.refreshBadges()
            }
        } catch {
            isLoading = false
            if items.isEmpty { loadError = error } else { store.show(error) }
        }
    }

    // MARK: Deep links

    private func handleTap(_ n: AppNotification) {
        if let i = items.firstIndex(where: { $0.id == n.id }) { items[i].read = true }
        switch n.kind {
        case .counterOffer:
            if let id = n.listingId { router.push(.offerThread(id)) } else { fallback(n) }
        case .orderUpdate:
            if let id = n.orderId { router.push(.order(id)) } else { fallback(n) }
        case .message:
            if let id = n.conversationId { router.push(.chat(id)) } else { fallback(n) }
        case .streak:
            open(tab: .discover)
        case .priceDrop, .newInSize:
            fallback(n)
        }
    }

    /// Generic routing on whatever target the notification carries.
    private func fallback(_ n: AppNotification) {
        if let id = n.orderId { router.push(.order(id)) }
        else if let id = n.conversationId { router.push(.chat(id)) }
        else if let id = n.listingId { router.push(.product(id)) }
        else { open(tab: .discover) }
    }

    private func open(tab: AppTab) {
        router.popToRoot(router.selectedTab)
        router.popToRoot(tab)
        router.selectedTab = tab
    }

    // MARK: Push permission

    private func refreshPushStatus() async {
        pushStatus = await PushPermission.status()
    }

    private func requestPush() async {
        await PushPermission.request(store: store)
        await refreshPushStatus()
    }
}

// MARK: - Push permission (shared with Réglages)

@MainActor
enum PushPermission {
    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks for permission the first time; afterwards opens the app's notification settings.
    static func request(store: AppStore) async {
        let current = await status()
        guard current == .notDetermined else {
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                _ = await UIApplication.shared.open(url)
            }
            return
        }
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                Haptics.success()
                store.show("Alertes activées")
            }
        } catch {
            store.show(error)
        }
    }
}

// MARK: - Row

/// Icon, title, text, relative time; unread = hibiscus dot.
struct NotificationRow: View {
    let notification: AppNotification
    let onTap: () -> Void

    var body: some View {
        let unread = !notification.read
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: NotificationStyle(kind: notification.kind).symbol)
                    .font(RF.T.body)
                    .foregroundStyle(RF.C.text)
                    .frame(width: 24)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(notification.title)
                            .font(RF.T.subheadline.weight(.semibold))
                            .foregroundStyle(RF.C.text)
                        Spacer(minLength: 8)
                        Text(Fmt.relative(notification.createdAt))
                            .font(RF.T.footnote.monospacedDigit())
                            .foregroundStyle(RF.C.textDim)
                            .lineLimit(1)
                    }
                    Text(notification.body)
                        .font(RF.T.subheadline)
                        .foregroundStyle(RF.C.textDim)
                        .lineLimit(3)
                }
                .multilineTextAlignment(.leading)
            }
            .padding(.vertical, 4)
            .overlay(alignment: .leading) {
                if unread {
                    Circle().fill(RF.C.hibiscus).frame(width: 8, height: 8).offset(x: -12)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(unread ? "Non lue. " : "")\(notification.title). \(notification.body). \(Fmt.relative(notification.createdAt))")
        .accessibilityAddTraits(.isButton)
    }
}

/// SF Symbol per notification kind.
struct NotificationStyle {
    let symbol: String

    init(kind: NotificationKind) {
        switch kind {
        case .counterOffer: symbol = "arrow.left.arrow.right"
        case .priceDrop: symbol = "tag"
        case .newInSize: symbol = "sparkles"
        case .message: symbol = "bubble.left"
        case .streak: symbol = "flame"
        case .orderUpdate: symbol = "shippingbox"
        }
    }
}

// MARK: - Push permission row

/// « Active les alertes » — asks for push permission, or points to Settings if it was refused.
struct PushPermissionRow: View {
    let status: UNAuthorizationStatus
    let action: () async -> Void
    @State private var working = false

    private var denied: Bool { status == .denied }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: denied ? "bell.slash" : "bell.badge")
                .font(RF.T.body)
                .foregroundStyle(RF.C.text)
                .frame(width: 24)
            Text(denied ? "Alertes désactivées" : "Active les alertes")
                .font(RF.T.subheadline.weight(.semibold))
                .foregroundStyle(RF.C.text)
            Spacer(minLength: 8)
            Button {
                working = true
                Task {
                    await action()
                    working = false
                }
            } label: {
                if working { ProgressView().controlSize(.small) } else { Text(denied ? "Réglages" : "Activer") }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(RF.C.hibiscus)
            .disabled(working)
        }
        .listRowBackground(RF.C.paper)
    }
}

#Preview {
    NavigationStack {
        NotificationsView().withAppRoutes()
    }
    .previewEnvironment()
}
