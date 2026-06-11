import AppKit
import Foundation

// MARK: - ExclusionList

/// Per-app capture exclusions. Copies made while an excluded app is frontmost
/// are never recorded. Stored as bundle identifiers in UserDefaults.
@MainActor
final class ExclusionList {

    static let shared = ExclusionList()

    private static let defaultsKey = "excludedBundleIDs"

    private init() {}

    /// Bundle identifiers the user excluded, sorted for stable display.
    var excludedBundleIDs: [String] {
        (UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []).sorted()
    }

    func isExcluded(bundleID: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? [])
            .contains(bundleID)
    }

    func add(bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var current = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        guard !current.contains(trimmed) else { return }
        current.append(trimmed)
        UserDefaults.standard.set(current, forKey: Self.defaultsKey)
    }

    func remove(bundleID: String) {
        let current = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        UserDefaults.standard.set(current.filter { $0 != bundleID }, forKey: Self.defaultsKey)
    }

    /// Currently running apps with a UI, for the "add app" picker.
    /// Excludes Hotstash itself and apps already on the list.
    func candidateRunningApps() -> [(name: String, bundleID: String, icon: NSImage?)] {
        let excluded = Set(excludedBundleIDs)
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier,
                      id != Bundle.main.bundleIdentifier,
                      !excluded.contains(id) else { return nil }
                return (app.localizedName ?? id, id, app.icon)
            }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    /// Display name + icon for a stored bundle id (best effort).
    func displayInfo(for bundleID: String) -> (name: String, icon: NSImage?) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
            return (name, NSWorkspace.shared.icon(forFile: url.path))
        }
        return (bundleID, nil)
    }
}
