import Foundation

// MARK: - OneTimeClips

/// Clips that are only useful for a few minutes, such as verification codes
/// and sign-in or signed download links. They are deleted from history
/// `lifetime` after they're copied, unless the user pinned, named, or filed them.
enum OneTimeClips {

    static let lifetime: TimeInterval = 10 * 60
    static let defaultsKey = "expireOneTimeClips"

    /// On by default; toggled in Settings › General.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    /// Query parameters that carry a single-use secret.
    private static let tokenParams: Set<String> = [
        "token", "otp", "magic", "code", "oobcode", "ticket", "signature",
        "sig", "access_token", "login_token", "x-amz-signature",
    ]

    static func isOneTime(_ content: String) -> Bool {
        let s = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // 6–8 digit codes, "123 456" / "123-456", or prefixed like "G-123456".
        // 4–5 digits are left alone: too often years, PINs, or postcodes.
        if s.range(of: #"^(?:[A-Z]{1,3}-)?(?:\d{6,8}|\d{3}[ -]\d{3})$"#, options: .regularExpression) != nil {
            return true
        }
        guard s.hasPrefix("https://") || s.hasPrefix("http://"),
              let items = URLComponents(string: s)?.queryItems else { return false }
        return items.contains { item in
            tokenParams.contains(item.name.lowercased()) && (item.value?.count ?? 0) >= 16
        }
    }

    /// Deletes the clip once it's `lifetime` old. A launch-time sweep catches
    /// clips whose timer didn't fire because the app quit.
    @MainActor
    static func scheduleExpiry() {
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime + 1) {
            ClipboardStore.shared.removeExpiredOneTimeItems()
        }
    }
}
