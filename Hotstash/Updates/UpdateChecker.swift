import AppKit

// MARK: - UpdateChecker

/// Checks the Mac App Store for a newer version of Hotstash and, if one exists,
/// prompts the user to update. Because Hotstash is sandboxed and distributed via
/// the App Store, it cannot self-update — the prompt just sends the user to the
/// store listing.
@MainActor
enum UpdateChecker {

    private enum Keys {
        static let lastPromptedVersion = "lastPromptedUpdateVersion"
    }

    private static let bundleID = "com.zeyadamer.hotstash"
    private static let lookupURL = "https://itunes.apple.com/lookup?bundleId=\(bundleID)"

    struct AppStoreInfo {
        let version: String
        let listingURL: URL
    }

    // MARK: - Entry point

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

    // MARK: - Network

    private static func fetchAppStoreInfo() async -> AppStoreInfo? {
        guard let url = URL(string: lookupURL) else { return nil }
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

    // MARK: - Prompt

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

    // MARK: - Version helpers

    private static func currentVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Compares dotted numeric version strings (e.g. "5.0.1" > "5.0").
    static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
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
