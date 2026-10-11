import SwiftUI

@main
@MainActor
struct ReFripeApp: App {
    @State private var store: AppStore
    @State private var router = Router()

    init() {
        let (repo, isDemo) = makeRepository()
        _store = State(initialValue: AppStore(repo: repo, isDemo: isDemo))
        AppAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .tint(RF.C.hibiscus)
                .preferredColorScheme(.light)
                .task {
                    // UI tests: `-uiTestingSignedOut` starts the demo signed out, so the sign-up flow is shown.
                    if store.isDemo && ProcessInfo.processInfo.arguments.contains("-uiTestingSignedOut") {
                        try? await store.repo.signOut()
                    }
                    await store.bootstrap()
                }
        }
    }
}
