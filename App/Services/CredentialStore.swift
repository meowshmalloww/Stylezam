import Foundation
import Observation
import Security

@MainActor
@Observable
final class CredentialStore {
    private(set) var revision = 0

    private let service = "com.stylezam.app.search-providers"

    func hasCredential(_ kind: SearchCredentialKind) -> Bool {
        (try? credential(for: kind))?.isEmpty == false
    }

    func credential(for kind: SearchCredentialKind) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            throw CredentialStoreError.keychain(status)
        }
        return value
    }

    func setCredential(_ value: String, for kind: SearchCredentialKind) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try removeCredential(kind)
            return
        }
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.rawValue,
        ]
        let data = Data(trimmed.utf8)
        let updateStatus = SecItemUpdate(
            key as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var insert = key
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw CredentialStoreError.keychain(insertStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw CredentialStoreError.keychain(updateStatus)
        }
        revision &+= 1
    }

    func removeCredential(_ kind: SearchCredentialKind) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
        revision &+= 1
    }

    /// Debug device launches can inject values from a local, ignored `.env` file.
    /// Values are immediately moved into the device-only Keychain and never logged.
    func importDebugEnvironment() {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        for kind in SearchCredentialKind.allCases {
            guard let value = environment[kind.environmentKey], !value.isEmpty else { continue }
            try? setCredential(value, for: kind)
        }
#endif
    }
}

enum CredentialStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .keychain(status):
            "The device Keychain returned error \(status)."
        }
    }
}
