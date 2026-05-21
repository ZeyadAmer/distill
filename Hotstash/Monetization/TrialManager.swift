import Foundation

// MARK: - TrialManager

/// Tracks the 14-day free trial period.
///
/// `firstLaunchDate` is written to UserDefaults once on the first call to `start()`.
/// StoreKit purchase state is the authoritative unlock signal; trial state is
/// secondary — a fallback when the user has not yet purchased.
final class TrialManager {

    // MARK: Singleton

    static let shared = TrialManager()
    private init() {}

    // MARK: Constants

    private enum Keys {
        static let firstLaunchDate = "com.zeyadamer.hotstash.firstLaunchDate"
    }

    private static let trialDurationDays = 14

    // MARK: - Public API

    /// The date the app was first launched. `nil` only if `start()` has not been called yet.
    private(set) var firstLaunchDate: Date? {
        get { UserDefaults.standard.object(forKey: Keys.firstLaunchDate) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Keys.firstLaunchDate) }
    }

    /// Number of full days remaining in the trial (clamped to 0 when expired).
    var trialDaysRemaining: Int {
        guard let start = firstLaunchDate else { return Self.trialDurationDays }
        let elapsed = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        return max(0, Self.trialDurationDays - elapsed)
    }

    /// `true` while the user still has days left in the trial.
    var isInTrial: Bool {
        trialDaysRemaining > 0
    }

    /// `true` when the trial has expired AND the user has not purchased.
    /// UI should gate restricted features on this flag.
    var isRestricted: Bool {
        !isInTrial && !PurchaseManager.shared.isPurchased
    }

    /// Call once from `applicationDidFinishLaunching`.
    ///
    /// Sets `firstLaunchDate` on the very first run, then checks whether the
    /// trial has just expired and posts `.purchaseStateChanged` if so.
    func start() {
        if firstLaunchDate == nil {
            firstLaunchDate = Date()
        }

        // If the trial is expired (and the user has not purchased), broadcast
        // the state change so the menubar icon can update its badge.
        if isRestricted {
            NotificationCenter.default.post(name: .purchaseStateChanged, object: nil)
        }
    }
}
