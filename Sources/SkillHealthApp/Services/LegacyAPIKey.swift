import Foundation
import Security

/// From 2026-10-04 to the redesign the same day, checks could run in the app with the person's own
/// Anthropic API key, kept in the keychain. Checks run in Claude Code now, so a key saved then is
/// deleted on launch instead of being left in the keychain with nothing to use it. Remove this
/// file one release after the redesign ships.
enum LegacyAPIKey {
    static func remove() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "com.mvoshell.skillhealth.anthropic-api-key",
                                    kSecAttrAccount as String: "default"]
        SecItemDelete(query as CFDictionary)
    }
}
