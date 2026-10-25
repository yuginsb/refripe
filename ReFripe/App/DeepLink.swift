import Foundation

/// URL → navigation. Handles the custom scheme (`refripe://chat/<id>`, `refripe://order/<id>`,
/// `refripe://inbox/orders`, `refripe://notifications`…) and the public links built by `AppLinks`
/// (`https://refripe.app/a/<listing>`, `/u/<user>`).
enum DeepLink: Equatable {
    case route(Route, AppTab)
    case inbox(InboxSegment)

    init?(url: URL) {
        var parts = url.pathComponents.filter { $0 != "/" }
        if url.scheme == "refripe", let host = url.host() { parts.insert(host, at: 0) }
        guard let head = parts.first?.lowercased() else { return nil }
        let id = parts.count > 1 ? UUID(uuidString: parts[1]) : nil

        switch head {
        case "a", "listing", "product":
            guard let id else { return nil }
            self = .route(.product(id), .discover)
        case "u", "user", "profile":
            guard let id else { return nil }
            self = .route(.sellerProfile(id), .discover)
        case "chat", "conversation":
            guard let id else { self = .inbox(.messages); return }
            self = .route(.chat(id), .messages)
        case "order":
            guard let id else { self = .inbox(.orders); return }
            self = .route(.order(id), .messages)
        case "offers":
            guard let id else { self = .inbox(.orders); return }
            self = .route(.receivedOffers(id), .messages)
        case "offer":
            guard let id else { self = .inbox(.orders); return }
            self = .route(.offerThread(id), .messages)
        case "messages":
            self = .inbox(.messages)
        case "orders":
            self = .inbox(.orders)
        case "notifications":
            self = .inbox(.notifications)
        case "inbox":
            let segment = parts.count > 1 ? InboxSegment(rawValue: parts[1].lowercased()) : nil
            self = .inbox(segment ?? .messages)
        case "settings":
            self = .route(.settings, .profile)
        case "stats", "dashboard":
            self = .route(.dashboard, .profile)
        default:
            return nil
        }
    }

    @MainActor
    func apply(to router: Router) {
        router.isSellPresented = false
        switch self {
        case .route(let route, let tab):
            if tab == .messages, case .chat = route { router.inboxSegment = .messages }
            if tab == .messages, case .order = route { router.inboxSegment = .orders }
            router.open(route, in: tab)
        case .inbox(let segment):
            router.openInbox(segment)
        }
    }
}
