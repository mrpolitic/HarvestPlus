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
        // Build an "allow all" access ACL so the item survives ad-hoc re-signs
        // without prompting. SecAccessCreate with an empty (non-nil) trusted-
        // applications array means any process running as the current user can
        // access the item — no per-binary ACL restriction.
        var access: SecAccess?
        SecAccessCreate("HarvestPlus credentials" as CFString, [] as CFArray, &access)

        let lookupQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        // Prefer SecItemUpdate over delete+add. Deleting an existing item goes
        // through the same ACL check as reading it, so a delete-then-add
        // strategy triggers two prompts per item (one read, one delete) instead
        // of one. SecItemUpdate modifies the item in place — if the session-
        // level "Allow" from the preceding read covers the update (which macOS
        // treats as the same access right), the user sees only the read prompt.
        var updateAttribs: [String: Any] = [kSecValueData as String: data]
        if let access { updateAttribs[kSecAttrAccess as String] = access }

        let updateStatus = SecItemUpdate(lookupQuery as CFDictionary, updateAttribs as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item does not exist yet — add it fresh with the allow-all ACL.
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
