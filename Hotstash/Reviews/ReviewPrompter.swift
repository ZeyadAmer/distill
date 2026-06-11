import AppKit
import StoreKit

// MARK: - ReviewPrompter

/// Asks for an App Store rating at a success moment: after enough pastes,
/// a few days after install, at most once per app version. Apple throttles
/// the actual dialog further, so calling is always safe.
@MainActor
final class ReviewPrompter {

    static let shared = ReviewPrompter()

    private static let pasteCountKey = "reviewPasteCount"
    private static let firstLaunchKey = "reviewFirstLaunchDate"
    private static let promptedVersionKey = "reviewPromptedVersion"

    private static let minimumPastes = 20
    private static let minimumDaysInstalled = 3

    private init() {
        if UserDefaults.standard.object(forKey: Self.firstLaunchKey) == nil {
            UserDefaults.standard.set(Date.now, forKey: Self.firstLaunchKey)
        }
    }

    /// Call once per successful paste. Triggers the system review dialog
    /// when all gates pass.
    func recordPaste() {
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: Self.pasteCountKey) + 1
        defaults.set(count, forKey: Self.pasteCountKey)

        guard count >= Self.minimumPastes else { return }

        let firstLaunch = defaults.object(forKey: Self.firstLaunchKey) as? Date ?? .now
        let daysInstalled = Calendar.current
            .dateComponents([.day], from: firstLaunch, to: .now).day ?? 0
        guard daysInstalled >= Self.minimumDaysInstalled else { return }

        let version = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        guard defaults.string(forKey: Self.promptedVersionKey) != version else { return }

        defaults.set(version, forKey: Self.promptedVersionKey)
        SKStoreReviewController.requestReview()
    }
}
