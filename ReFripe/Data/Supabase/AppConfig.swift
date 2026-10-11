import Foundation

/// Supabase connection settings read from Info.plist (filled from Config/Secrets*.xcconfig).
struct SupabaseConfig: Sendable, Hashable {
    let url: URL
    let anonKey: String
}

enum AppConfig {
    /// nil when SUPABASE_URL / SUPABASE_ANON_KEY are missing or empty → the app runs on demo data.
    static let supabase: SupabaseConfig? = load(from: Bundle.main.infoDictionary)

    static var isSupabaseConfigured: Bool { supabase != nil }

    static func load(from info: [String: Any]?) -> SupabaseConfig? {
        guard let info,
              let rawURL = cleaned(info["SUPABASE_URL"]),
              let anonKey = cleaned(info["SUPABASE_ANON_KEY"]),
              let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty
        else { return nil }
        return SupabaseConfig(url: url, anonKey: anonKey)
    }

    /// Empty strings and unresolved build settings ("$(SUPABASE_URL)") count as "not configured".
    private static func cleaned(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }
}
