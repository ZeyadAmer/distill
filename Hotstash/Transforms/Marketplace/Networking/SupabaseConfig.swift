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

// MARK: - DeviceTracker

/// Anonymous, no-login active-user tracking. On launch the app pings the
/// `record_app_open` RPC with a random per-install UUID (no device identifier,
/// no PII) plus platform/version, so we can count users in Supabase across
/// macOS and iOS without requiring a marketplace sign-in. Best-effort and
/// silent — failures never surface, and no clipboard content is ever sent.
enum DeviceTracker {

    private static let installIDKey = "com.zeyadamer.hotstash.installID"
    private static let lastPingKey  = "com.zeyadamer.hotstash.lastOpenPing"

    /// Minimum gap between pings so reopening doesn't spam the backend while
    /// still refreshing `last_seen` on daily use.
    private static let pingThrottle: TimeInterval = 12 * 60 * 60

    /// Stable random id for this install (regenerated only on delete/reinstall).
    static var installID: String {
        if let existing = UserDefaults.standard.string(forKey: installIDKey) {
            return existing
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: installIDKey)
        return id
    }

    private static var platform: String {
        #if os(macOS)
        return "macos"
        #else
        return "ios"
        #endif
    }

    private static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// Fire-and-forget launch ping. Throttled, so it's safe to call on every
    /// launch/foreground.
    static func recordOpen() {
        if let last = UserDefaults.standard.object(forKey: lastPingKey) as? Date,
           Date().timeIntervalSince(last) < pingThrottle {
            return
        }
        guard let config = SupabaseConfig.current,
              let url = URL(string: config.url.absoluteString + "/rest/v1/rpc/record_app_open")
        else { return }

        UserDefaults.standard.set(Date(), forKey: lastPingKey)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "p_device_id":   installID,
            "p_platform":    platform,
            "p_app_version": appVersion ?? "",
            "p_os_version":  osVersion,
        ])

        Task.detached {
            _ = try? await URLSession.shared.data(for: req)
        }
    }
}
