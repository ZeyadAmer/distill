import Foundation

// MARK: - LinkCleaner

/// Strips tracking/analytics parameters from shared links and unwraps common
/// redirect wrappers (e.g. `l.facebook.com/l.php?u=…`) so the real destination
/// is copied instead of the tracking URL.
///
/// `clean(_:)` is pure/offline — it handles the Instagram/Threads/Facebook share
/// cases where the destination is a query parameter. `resolveAndClean(_:)` adds a
/// network round-trip to follow HTTP redirects (t.co, bit.ly, fb.me, …) before
/// cleaning.
enum LinkCleaner {

    /// Query parameter names removed wholesale. Matched case-insensitively, plus
    /// any parameter beginning with `utm_`.
    private static let trackingKeys: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "wbraid", "gbraid",
        "igshid", "igsh", "mibextid", "mc_eid", "mc_cid",
        "yclid", "twclid", "ttclid", "msclkid", "vero_id", "oly_enc_id",
        "oly_anon_id", "_hsenc", "_hsmi", "hsctatracking",
        "ref", "ref_src", "ref_url", "source", "s_kwcid",
        "spm", "scm", "_ga", "_gl", "trk", "trkcampaign",
        "si",           // youtube/spotify share tracking
    ]

    /// Hosts that wrap the real URL in a query parameter, with the parameter that
    /// holds the (percent-encoded) destination.
    private static let redirectParamHosts: [String: String] = [
        "l.facebook.com": "u",
        "lm.facebook.com": "u",
        "l.instagram.com": "u",
        "l.messenger.com": "u",
        "away.vk.com": "to",
        "out.reddit.com": "url",
        "www.google.com": "url",   // /url?q= or /url?url=
        "news.url.google.com": "url",
    ]

    // MARK: - Offline

    /// Returns a cleaned copy of `url`: unwraps a known redirect wrapper (once),
    /// then removes tracking parameters. Returns `url` unchanged if it isn't a
    /// web URL or nothing needed cleaning.
    static func clean(_ url: URL) -> URL {
        let unwrapped = unwrapRedirect(url) ?? url
        return stripTrackingParams(from: unwrapped)
    }

    /// String convenience: trims, parses, cleans, returns absolute string.
    /// Non-URL input is returned trimmed but otherwise unchanged.
    static func clean(_ string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme == "http" || url.scheme == "https" else { return trimmed }
        return clean(url).absoluteString
    }

    private static func unwrapRedirect(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              let param = redirectParamHosts[host],
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              // Google uses both `url` and `q`; accept either.
              let target = comps.queryItems?.first(where: { $0.name == param || $0.name == "q" })?.value,
              let targetURL = URL(string: target),
              targetURL.scheme == "http" || targetURL.scheme == "https"
        else { return nil }
        return targetURL
    }

    private static func stripTrackingParams(from url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems, !items.isEmpty else { return url }

        let kept = items.filter { !isTracking($0.name) }
        comps.queryItems = kept.isEmpty ? nil : kept
        return comps.url ?? url
    }

    private static func isTracking(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("utm_") || trackingKeys.contains(lower)
    }

    // MARK: - Network resolve

    /// Follows HTTP redirects to the final destination, then cleans it. Falls
    /// back to offline `clean(url)` on any network failure. Best-effort.
    static func resolveAndClean(_ url: URL) async -> URL {
        // If it's already a known param-wrapper, offline unwrap is enough.
        if let unwrapped = unwrapRedirect(url) { return clean(unwrapped) }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        if let (_, response) = try? await session.data(for: request),
           let finalURL = response.url {
            return clean(finalURL)
        }
        return clean(url)
    }
}
