import AppKit

// MARK: - UpdateChecker

/// Mac App Store update check via Apple's public iTunes lookup API. Two entry
/// points share the lookup + version-compare logic:
///   - `checkOnLaunch()` — fire-and-forget; presents an NSAlert once per version.
///   - `availableUpdate()` — throttled query the clipboard panel uses to show a
///     dismissible "Update available" strip.
///
/// No backend, no push entitlement, no permission prompt. Sandboxed + App Store
/// distributed, so it can't self-update — it just points the user at the listing.
@MainActor
enum UpdateChecker {

    private static let bundleID = "com.zeyadamer.hotstash"

    private enum Keys {
        static let lastPromptedVersion = "lastPromptedUpdateVersion"
    }

    // MARK: - Launch prompt

    struct AppStoreInfo {
        let version: String
        let listingURL: URL
    }

    /// Fire-and-forget launch check.
    static func checkOnLaunch() {
        Task { await check() }
    }

    static func check() async {
        guard let info = await fetchAppStoreInfo() else { return }

        let current = currentVersion()
        guard isVersion(info.version, newerThan: current) else { return }

        // Only nag once per available version.
        let lastPrompted = UserDefaults.standard.string(forKey: Keys.lastPromptedVersion)
        guard lastPrompted != info.version else { return }
        UserDefaults.standard.set(info.version, forKey: Keys.lastPromptedVersion)

        presentPrompt(current: current, info: info)
    }

    private static func fetchAppStoreInfo() async -> AppStoreInfo? {
        guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleID)") else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = json["results"] as? [[String: Any]],
            let first = results.first,
            let version = first["version"] as? String
        else { return nil }

        let urlString = (first["trackViewUrl"] as? String) ?? "macappstore://apps.apple.com/app/id\(first["trackId"] as? Int ?? 0)"
        guard let listingURL = URL(string: urlString) else { return nil }

        return AppStoreInfo(version: version, listingURL: listingURL)
    }

    private static func presentPrompt(current: String, info: AppStoreInfo) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Hotstash \(info.version) is available — you have \(current). Update from the App Store to get the latest features and fixes."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "View in App Store")
        alert.addButton(withTitle: "Later")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(info.listingURL)
        }
    }

    // MARK: - Panel strip

    struct Result {
        /// Newest version string on the App Store (e.g. "7.0.0").
        let latest: String
        /// Deep link that opens the app's App Store page (App Store app, not browser).
        let pageURL: URL
    }

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

    // MARK: - Version helpers

    private static func currentVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// True when `latest` is a higher version than `current`, compared
    /// component-wise and numerically (so "10.0" > "9.0", not the reverse).
    /// `nonisolated` so tests and non-main callers can compare synchronously.
    nonisolated static func isNewer(_ latest: String, than current: String) -> Bool {
        latest.compare(current, options: .numeric) == .orderedDescending
    }

    /// Compares dotted numeric version strings (e.g. "5.0.1" > "5.0").
    nonisolated static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let a = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let b = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(a.count, b.count)
        for i in 0 ..< count {
            let l = i < a.count ? a[i] : 0
            let r = i < b.count ? b[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
