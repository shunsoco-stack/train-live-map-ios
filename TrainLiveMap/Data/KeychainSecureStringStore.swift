import Foundation
import Security

protocol SecureStringStoring: Sendable {
    func string(forKey key: String) throws -> String?
    func set(_ value: String, forKey key: String) throws
    func removeValue(forKey key: String) throws
}

enum SecureStorageKey {
    static let communityReporterID = "community-reporter-id"
    static let apnsDeviceToken = "apns-device-token"
}

enum SecureStringStoreError: LocalizedError, Equatable {
    case invalidStoredData
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidStoredData:
            "Keychainの保存データを読み取れませんでした。"
        case let .keychainStatus(status):
            SecCopyErrorMessageString(status, nil) as String?
                ?? "Keychainエラー（\(status)）"
        }
    }
}

struct KeychainSecureStringStore: SecureStringStoring {
    static let defaultService = "com.shunsoco.trainlivemap.secure-storage"

    private let service: String

    init(service: String = defaultService) {
        self.service = service
    }

    func string(forKey key: String) throws -> String? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                throw SecureStringStoreError.invalidStoredData
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw SecureStringStoreError.keychainStatus(status)
        }
    }

    func set(_ value: String, forKey key: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(forKey: key)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw SecureStringStoreError.keychainStatus(updateStatus)
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let retryStatus = SecItemUpdate(
                query as CFDictionary,
                attributes as CFDictionary
            )
            guard retryStatus == errSecSuccess else {
                throw SecureStringStoreError.keychainStatus(retryStatus)
            }
            return
        }
        guard addStatus == errSecSuccess else {
            throw SecureStringStoreError.keychainStatus(addStatus)
        }
    }

    func removeValue(forKey key: String) throws {
        let status = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStringStoreError.keychainStatus(status)
        }
    }

    private func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}
