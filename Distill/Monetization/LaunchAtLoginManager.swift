import ServiceManagement

// MARK: - LaunchAtLoginManager

/// Thin wrapper around `SMAppService` for registering and unregistering
/// the app as a login item.
///
/// Failures are intentionally silent — the user can always configure login
/// items manually in System Settings > General > Login Items.
struct LaunchAtLoginManager {

    // MARK: - Query

    /// `true` when the app is registered as a launch-at-login item.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    // MARK: - Mutations

    /// Registers or unregisters the app as a launch-at-login item.
    ///
    /// - Parameter enabled: `true` to register, `false` to unregister.
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // SMAppService errors are expected in certain sandbox/entitlement
            // configurations during development; swallow silently in production.
        }
    }
}
