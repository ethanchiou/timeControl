import Foundation

/// The Supabase project the app talks to, read from Info.plist keys that `Config/Supabase.xcconfig`
/// fills in at build time. A build without that file (a fresh clone) leaves the placeholders in,
/// and the app then runs local-only with sync switched off.
nonisolated enum SupabaseConfig {
    static let urlKey = "SupabaseURL"
    static let apiKeyKey = "SupabaseKey"

    static var url: URL? {
        guard let raw = value(for: urlKey), let url = URL(string: raw), url.host != nil else { return nil }
        return url
    }

    static var apiKey: String? { value(for: apiKeyKey) }

    /// Both values present and not the unexpanded `$(…)` placeholders.
    static var isConfigured: Bool { url != nil && apiKey != nil }

    private static func value(for key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }
}
