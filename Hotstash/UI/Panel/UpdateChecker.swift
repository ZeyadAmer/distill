import Foundation

/// Checks the Mac App Store for a newer version of the app via Apple's public
/// iTunes lookup API and compares it to the running build.
///
/// No backend, no push entitlement, no permission prompt — the panel shows a
/// dismissible "Update available" strip when `check()` reports one. Results are
/// throttled in-memory so opening the panel repeatedly doesn't hammer the API.
enum UpdateChecker {

    struct Result {
        /// Newest version string on the App Store (e.g. "7.0.0").
        let latest: String
        /// Deep link that opens the app's App Store page (App Store app, not browser).
        let pageURL: URL
    }

    /// Bundle id used to look the app up. Matches the main app's identifier.
    private static let bundleID = "com.zeyadamer.hotstash"

    /// Re-check at most this often per launch.
    private static let throttle: TimeInterval = 6 * 60 * 60

    // ponytail: in-memory cache only — one lookup per launch (per throttle
    // window) is plenty for App Store update cadence; no need to persist.
    private static var lastCheck: Date?
    private static var cached: Result?

    /// Returns an available update, or nil when up to date / offline / throttled
    /// with no cached hit. Never throws — failures resolve to "no banner".
    static func availableUpdate() async -> Result? {
        if let lastCheck, Date().timeIntervalSince(lastCheck) < throttle {
            return cached
        }
        let result = await fetchLatest()
        lastCheck = Date()
        cached = result
        return result
    }

    private static func fetchLatest() async -> Result? {
        guard let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              var comps = URLComponents(string: "https://itunes.apple.com/lookup")
        else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "entity", value: "macSoftware"),
        ]
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.cachePolicy = .reloadIgnoringLocalCacheData

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (obj["results"] as? [[String: Any]])?.first,
              let latest = first["version"] as? String,
              let trackURL = first["trackViewUrl"] as? String
        else { return nil }

        guard isNewer(latest, than: current) else { return nil }
        return Result(latest: latest, pageURL: appStoreDeepLink(from: trackURL))
    }

    /// True when `latest` is a higher version than `current`, compared
    /// component-wise and numerically (so "10.0" > "9.0", not the reverse).
    static func isNewer(_ latest: String, than current: String) -> Bool {
        latest.compare(current, options: .numeric) == .orderedDescending
    }

    /// Prefer the `macappstore://` scheme so the link opens the App Store app
    /// directly instead of bouncing through the browser. Falls back to the
    /// original https URL if it can't be parsed.
    private static func appStoreDeepLink(from trackViewUrl: String) -> URL {
        if let https = URL(string: trackViewUrl),
           var comps = URLComponents(url: https, resolvingAgainstBaseURL: false) {
            comps.scheme = "macappstore"
            if let deep = comps.url { return deep }
        }
        return URL(string: trackViewUrl) ?? URL(string: "macappstore://apps.apple.com")!
    }
}
