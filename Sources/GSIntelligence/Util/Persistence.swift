import Foundation
import Security

/// Keychain-backed storage for the long-lived `true_device_id`. The Keychain
/// survives app reinstall, giving a stable device identity for HC126
/// ("same device, multiple users"). When `persistence` is disabled (GDPR mode)
/// the SDK returns an ephemeral per-session UUID and never writes to Keychain.
enum Persistence {
    private static let service = "com.gammasweep.gsintelligence"
    private static let account = "true_device_id"

    /// Returns the stored device id, generating + persisting one on first use.
    /// The `present` flag reports whether the id already existed before this call
    /// (drives `storage.persistent_id_present`).
    static func trueDeviceId(persist: Bool) -> (id: String, present: Bool) {
        guard persist else {
            return (GSRandom.uuid(), false)
        }
        if let existing = read() {
            return (existing, true)
        }
        let fresh = GSRandom.uuid()
        write(fresh)
        return (fresh, false)
    }

    private static func read() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private static func write(_ value: String) {
        let data = Data(value.utf8)
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(attributes as CFDictionary)
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
