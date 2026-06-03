import Foundation

/// Connection details for the Supabase backend. Loaded from a bundled
/// `Supabase.plist`; absent or placeholder values mean "not configured", in
/// which case the app falls back to the mock service.
struct SupabaseConfig: Equatable {
    let url: URL
    let anonKey: String

    /// Placeholder token used in the checked-in template plist.
    static let placeholder = "<SET_ME>"

    /// Loads config from `Supabase.plist` in the given bundle. Returns `nil` when
    /// the plist is missing, the keys are absent, or either value is still the
    /// `<SET_ME>` placeholder / empty.
    static func load(from bundle: Bundle = .main) -> SupabaseConfig? {
        guard
            let plistURL = bundle.url(forResource: "Supabase", withExtension: "plist"),
            let data = try? Data(contentsOf: plistURL),
            let raw = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dict = raw as? [String: Any]
        else {
            return nil
        }
        return make(from: dict)
    }

    /// Builds a config from a plist-shaped dictionary, validating placeholders.
    /// Exposed for testing without a bundle.
    static func make(from dict: [String: Any]) -> SupabaseConfig? {
        guard
            let urlString = (dict["SupabaseURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            let anonKey = (dict["SupabaseAnonKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return nil
        }

        guard isUsable(urlString), isUsable(anonKey), let url = URL(string: urlString) else {
            return nil
        }

        return SupabaseConfig(url: url, anonKey: anonKey)
    }

    private static func isUsable(_ value: String) -> Bool {
        !value.isEmpty && value != placeholder
    }

    /// The effective config for the running app, or `nil` when unconfigured.
    static var current: SupabaseConfig? { load() }
}
