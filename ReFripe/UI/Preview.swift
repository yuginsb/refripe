import SwiftUI

/// Injects a demo `AppStore` (signed in as Awa, bootstrapped) and a `Router` for `#Preview`s.
/// Usage: `#Preview { NavigationStack { ProductView(listingId: DemoIDs.listing(1)) }.previewEnvironment() }`
@MainActor
private struct PreviewEnvironment: ViewModifier {
    @State private var store = AppStore(repo: DemoRepository(), isDemo: true)
    @State private var router = Router()

    func body(content: Content) -> some View {
        content
            .environment(store)
            .environment(router)
            .tint(RF.C.hibiscus)
            .preferredColorScheme(.light)
            .rfToastHost()
            .task { await store.bootstrap() }
    }
}

extension View {
    func previewEnvironment() -> some View {
        modifier(PreviewEnvironment())
    }
}
