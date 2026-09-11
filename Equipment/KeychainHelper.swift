import Foundation
import Security

/// Minimal Keychain wrapper — used only for the Hugging Face API token,
/// so it never sits as plain text in a source file. The token lives
/// only in the device's Keychain, entered once from within the app,
/// and is read at request time.
enum KeychainHelper {
    enum Key: String {
        case huggingFaceToken = "gymapp.huggingface.token"
    }

    static func save(_ value: String, key: Key) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func read(key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
