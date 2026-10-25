import SwiftUI

/// Get-or-create the conversation with `userId` about `listingId`, then push `.chat(id)` on the current tab.
/// Use it from any « Contacter » button. It also remembers the conversation so `ChatThreadView` can show
/// its header even before the first message (the repository only lists conversations that have messages).
@MainActor
enum ChatLauncher {
    private(set) static var known: [UUID: Conversation] = [:]

    static func remember(_ conversation: Conversation) { known[conversation.id] = conversation }

    static func open(with userId: UUID, listingId: UUID?, store: AppStore, router: Router) async {
        do {
            let c = try await store.repo.conversation(withUser: userId, listingId: listingId)
            remember(c)
            router.push(.chat(c.id))
        } catch {
            store.show(error)
        }
    }
}
