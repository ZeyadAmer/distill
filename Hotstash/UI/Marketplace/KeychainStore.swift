import Foundation
import Security

/// Tiny string-keyed Keychain wrapper for the marketplace session tokens.
///
/// ponytail: generic-password items keyed by an account string; no access
/// group, no iCloud sync. Single-app, local session storage — that's all the
/// auth flow needs. Tokens belong in the Keychain, never `UserDefaults`.
enum KeychainStore {

    private static let service = "com.zeyadamer.hotstash.auth"

    /// Stores (or, when `value` is nil, removes) a string for `account`.
    static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        // Available after first unlock so a refresh can run without the user
        // re-entering credentials, but never when the device is locked.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    /// Reads the stored string for `account`, or nil if absent/unreadable.
    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }
}
