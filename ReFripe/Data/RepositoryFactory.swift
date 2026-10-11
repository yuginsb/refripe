import Foundation

// Owned by the Backend agent. RootView/ReFripeApp call this once at launch.
// Returns SupabaseRepository when SUPABASE_URL / SUPABASE_ANON_KEY are set in Info.plist
// (see Config/Secrets.local.xcconfig and docs/BACKEND.md), else DemoRepository.
@MainActor
func makeRepository() -> (repo: any Repository, isDemo: Bool) {
    if let config = AppConfig.supabase {
        return (SupabaseRepository(config: config), false)
    }
    return (DemoRepository(), true)
}
