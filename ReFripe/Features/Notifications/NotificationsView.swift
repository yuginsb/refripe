import SwiftUI
import UIKit
import UserNotifications

/// Notifications (mockup `screenNotifications`, PANEL `notifications`): grouped list, unread highlight,
/// marked read on open, deep links on tap, and a card asking for push permission when undetermined.
struct NotificationsView: View {
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
                ScrollView { ErrorStateView(error: loadError) { Task { await load() } } }
            } else {
                list
            }
        }
        .rfScreenBackground()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .task { await refreshPushStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshPushStatus() } }
        }
        .refreshable { await load() }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let pushStatus, pushStatus == .notDetermined || pushStatus == .denied {
                    PushPermissionCard(status: pushStatus) { await requestPush() }
                        .padding(.bottom, 14)
                }
                if items.isEmpty {
                    EmptyStateView(symbol: "bell",
                                   title: "Rien de neuf pour l'instant",
                                   message: "Baisse de prix sur une envie, nouvelle pièce dans ta taille, message reçu : tout arrivera ici.",
                                   actionTitle: "Découvrir des articles") {
                        open(tab: .discover)
                    }
                } else {
                    section("Aujourd'hui", today)
                    section("Plus tôt", earlier)
                }
            }
            .padding(.horizontal, RF.S.gutter)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder private func section(_ title: String, _ notifications: [AppNotification]) -> some View {
        if !notifications.isEmpty {
            SectionLabel(title)
                .padding(.top, 12)
                .padding(.bottom, 2)
            ForEach(notifications) { notification in
                NotificationRow(notification: notification) { handleTap(notification) }
                if notification.id != notifications.last?.id {
                    Rectangle().fill(RF.C.line).frame(height: 1)
                }
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
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        pushStatus = settings.authorizationStatus
    }

    private func requestPush() async {
        if pushStatus == .denied {
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
        await refreshPushStatus()
    }
}

// MARK: - Row

/// Mockup `.notif`: icon, title, text, relative time; unread = tinted background + dot.
struct NotificationRow: View {
    let notification: AppNotification
    let onTap: () -> Void

    var body: some View {
        let style = NotificationStyle(kind: notification.kind)
        let unread = !notification.read
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: style.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(style.color)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(style.color.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(notification.title)
                        .font(RF.F.body(12.5, unread ? .extraBold : .bold))
                        .foregroundStyle(RF.C.text)
                    Text(notification.body)
                        .font(RF.F.body(11.5))
                        .foregroundStyle(RF.C.textDim)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(Fmt.relative(notification.createdAt))
                        .font(RF.F.body(9.5, unread ? .bold : .medium))
                        .foregroundStyle(unread ? RF.C.hibiscus : RF.C.textDim)
                        .lineLimit(1)
                    if unread {
                        Circle().fill(RF.C.hibiscus).frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 1)
            }
            .padding(.vertical, 13)
            .padding(.horizontal, unread ? 10 : 0)
            .background {
                if unread {
                    RoundedRectangle(cornerRadius: RF.R.md, style: .continuous).fill(RF.C.marigold.opacity(0.12))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RFPressStyle(scale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(unread ? "Non lue. " : "")\(notification.title). \(notification.body). \(Fmt.relative(notification.createdAt))")
        .accessibilityAddTraits(.isButton)
    }
}

/// SF Symbol + colour per notification kind (mockup `ICON[n.icon]`).
struct NotificationStyle {
    let symbol: String
    let color: Color

    init(kind: NotificationKind) {
        switch kind {
        case .counterOffer: symbol = "arrow.left.arrow.right"; color = RF.C.marigold
        case .priceDrop: symbol = "chart.line.downtrend.xyaxis"; color = RF.C.money
        case .newInSize: symbol = "sparkles"; color = RF.C.marigold
        case .message: symbol = "bubble.left.fill"; color = RF.C.ink2
        case .streak: symbol = "flame.fill"; color = RF.C.hibiscus
        case .orderUpdate: symbol = "shippingbox.fill"; color = RF.C.moneyDeep
        }
    }
}

// MARK: - Push permission card

/// "Active les alertes" — asks for push permission, or points to Settings if it was refused.
struct PushPermissionCard: View {
    let status: UNAuthorizationStatus
    let action: () async -> Void
    @State private var working = false

    private var denied: Bool { status == .denied }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: denied ? "bell.slash.fill" : "bell.badge.fill")
                .font(.system(size: 18))
                .foregroundStyle(RF.C.marigold)
                .frame(width: 36, height: 36)
                .background(Circle().fill(RF.C.ink2))
            VStack(alignment: .leading, spacing: 4) {
                Text(denied ? "Alertes désactivées" : "Active les alertes")
                    .font(RF.F.display(13, .bold))
                    .foregroundStyle(RF.C.textOnInk)
                Text(denied
                     ? "Tu rates les baisses de prix et les contre-offres. Réactive les notifications dans Réglages."
                     : "Sois prévenu·e d'une baisse de prix sur tes envies, d'une contre-offre ou d'un message, même appli fermée.")
                    .font(RF.F.body(11.5))
                    .foregroundStyle(RF.C.textOnInkDim)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    working = true
                    Task {
                        await action()
                        working = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if working { ProgressView().tint(RF.C.ink0).controlSize(.small) }
                        Text(denied ? "Ouvrir les Réglages" : "Activer")
                    }
                    .font(RF.F.body(12, .extraBold))
                    .foregroundStyle(RF.C.ink0)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Capsule().fill(RF.C.marigold))
                }
                .buttonStyle(RFPressStyle(scale: 0.95))
                .disabled(working)
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RF.C.ink1, in: RoundedRectangle(cornerRadius: RF.R.lg, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    NavigationStack {
        NotificationsView().withAppRoutes()
    }
    .previewEnvironment()
}
