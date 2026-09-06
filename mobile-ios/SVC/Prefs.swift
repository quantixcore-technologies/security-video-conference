import Foundation
import Security

/// Sessiya tokeni — iOS Keychain'da (Android'dagi SharedPreferences'dan xavfsizroq).
/// Token qurilma qulflanganda o'qilmaydi (`WhenUnlockedThisDeviceOnly`), backup'ga tushmaydi.
enum Prefs {
    private static let service = "uz.svc.session"
    private static let account = "bearer-token"
    private static let lastSeenKey = "svc_last_seen_notification"

    static func saveToken(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func token() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8),
              !str.isEmpty
        else { return nil }
        return str
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: lastSeenKey)
    }

    static var lastSeenNotification: Int64 {
        get { Int64(UserDefaults.standard.integer(forKey: lastSeenKey)) }
        set { UserDefaults.standard.set(Int(newValue), forKey: lastSeenKey) }
    }
}
