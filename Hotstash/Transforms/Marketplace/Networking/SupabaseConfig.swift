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

// MARK: - RemoteFlags

/// Server-controlled feature flags, read from a single `app_config` row in
/// Supabase so behaviour can change without shipping a new build.
///
/// The value is cached in `UserDefaults` and **fails closed**: until a fetch
/// succeeds and returns `true`, the flag stays `false`. A blocked or failed
/// network call therefore never turns the feature on.
enum RemoteFlags {

    private static let onboardingKey = "com.zeyadamer.hotstash.remote.onboardingEnabled"
    private static let pasteStackStepKey = "com.zeyadamer.hotstash.remote.pasteStackStepEnabled"

    /// Whether the first-run guided tour (and its About replay button) is shown.
    static var onboardingEnabled: Bool {
        UserDefaults.standard.bool(forKey: onboardingKey) // absent == false
    }

    /// Whether the tour's Paste Stack step is shown. Ships off; flip the
    /// `paste_stack_step_enabled` column in `app_config` to reveal it OTA.
    static var pasteStackStepEnabled: Bool {
        UserDefaults.standard.bool(forKey: pasteStackStepKey) // absent == false
    }

    /// Fire-and-forget fetch of the flags row. Best-effort and silent — on any
    /// failure the last cached value is kept.
    static func refresh() {
        Task.detached { await fetchAndCache() }
    }

    /// Awaitable fetch with a timeout, for decisions that cannot wait for a
    /// background refresh (e.g. showing the tour on the very first launch,
    /// when nothing is cached yet). On timeout/failure the cached values stand.
    static func refreshAwaiting(timeout: TimeInterval = 3) async {
        let fetch = Task { await fetchAndCache() }
        let watchdog = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            fetch.cancel()
        }
        await fetch.value
        watchdog.cancel()
    }

    private static func fetchAndCache() async {
        guard let config = SupabaseConfig.current,
              let url = URL(string: config.url.absoluteString
                            + "/rest/v1/app_config?select=onboarding_enabled,paste_stack_step_enabled&limit=1")
        else { return }

        var req = URLRequest(url: url)
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let row = rows.first
        else { return }
        if let ob = row["onboarding_enabled"] as? Bool {
            UserDefaults.standard.set(ob, forKey: onboardingKey)
        }
        if let ps = row["paste_stack_step_enabled"] as? Bool {
            UserDefaults.standard.set(ps, forKey: pasteStackStepKey)
        }
    }
}
