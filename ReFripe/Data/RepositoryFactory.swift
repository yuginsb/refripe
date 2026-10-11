import Foundation

// STUB — owned by the Backend agent. RootView/ReFripeApp call this once at launch.
// Returns SupabaseRepository when SUPABASE_URL / SUPABASE_ANON_KEY are set in Info.plist, else DemoRepository.
@MainActor
func makeRepository() -> (repo: any Repository, isDemo: Bool) {
    (DemoRepository(), true)
}
