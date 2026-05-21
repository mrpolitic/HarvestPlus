//
//  KeychainHelper.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//

import Foundation
import Security

// MARK: - Keychain Helper

enum KeychainHelper {

    private static let service = "com.harvestplus"

    // MARK: - Save

    static func save(key: String, data: Data) throws {
        let lookupQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        // UPDATE PATH — change the stored value only. Critically, we do NOT
        // include kSecAttrAccess here. Passing an ACL to SecItemUpdate is
        // treated by macOS as a request to modify the item's access controls,
        // which is a privileged operation and unconditionally triggers a
        // "change access permissions" / "change the owner" password prompt
        // every single time. By updating only the data, the existing ACL
        // (set on creation) keeps working and the user sees no dialog.
        let updateAttribs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(lookupQuery as CFDictionary, updateAttribs as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // ADD PATH — the item doesn't exist yet, so create it. This is
            // the *only* place we attach an ACL. SecAccessCreate with an
            // empty trusted-applications array tells macOS "any process
            // running as the current user may access this item" — so the
            // keychain doesn't keep challenging us when the app's signature
            // changes between builds. SecItemAdd on a brand-new item doesn't
            // prompt: there's no existing ACL to override.
            var access: SecAccess?
            SecAccessCreate("HarvestPlus credentials" as CFString, [] as CFArray, &access)

            var addQuery = lookupQuery
            addQuery[kSecValueData as String] = data
            if let access { addQuery[kSecAttrAccess as String] = access }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.saveFailed(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.saveFailed(updateStatus)
        }
    }

    static func save(key: String, string: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try save(key: key, data: data)
    }

    // MARK: - Load

    static func load(key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status)
        }

        return result as? Data
    }

    static func loadString(key: String) throws -> String? {
        guard let data = try load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Delete

    static func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

}

// MARK: - Keychain Keys

enum KeychainKey {
    static let harvestToken     = "harvest_api_token"
    static let harvestAccountId = "harvest_account_id"
}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Keychain save failed (status: \(status))"
        case .loadFailed(let status):
            return "Keychain load failed (status: \(status))"
        case .deleteFailed(let status):
            return "Keychain delete failed (status: \(status))"
        case .encodingFailed:
            return "Failed to encode string for Keychain"
        }
    }
}
