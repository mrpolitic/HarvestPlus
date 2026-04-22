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
        // Delete any existing item first
        try? delete(key: key)

        var query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String:   data
        ]

        // Attach an "allow all" access ACL so the keychain item survives
        // app updates without triggering a password prompt each time.
        //
        // Why this is needed:
        //   HarvestPlus is ad-hoc signed — every new build produces a unique
        //   code signature. Without an explicit kSecAttrAccess, macOS records
        //   the creating binary's signature in the item's ACL. Any subsequent
        //   binary (even a rebuilt copy of the same app) is then treated as an
        //   "untrusted" accessor and the user sees "HarvestPlus wants to use
        //   your confidential information stored in 'com.harvestplus' in your
        //   keychain." on every install.
        //
        // Fix:
        //   SecAccessCreate with an empty (non-nil) trusted-applications array
        //   creates an access object with no per-application restriction —
        //   any process running as the current user can read the item without
        //   prompting. This is appropriate for user-owned credentials stored in
        //   the user's own login keychain; the item never leaves the device.
        var access: SecAccess?
        let accessStatus = SecAccessCreate(
            "HarvestPlus credentials" as CFString,
            [] as CFArray,          // empty = any app; nil = calling app only
            &access
        )
        if accessStatus == errSecSuccess, let access {
            query[kSecAttrAccess as String] = access
        }
        // If SecAccessCreate fails (shouldn't, but be defensive), we fall
        // through without kSecAttrAccess — same as the old behaviour.

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
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

    // MARK: - Migration

    /// Re-save every known keychain item so it picks up the "allow all"
    /// access ACL introduced in 1.0.3. Call once at app launch (idempotent).
    ///
    /// Items created before 1.0.3 have the old binary's code signature baked
    /// into their ACL; re-saving them with the updated `save()` replaces that
    /// with the unrestricted access object. The user may see one last prompt
    /// per item during this migration run — subsequent launches and updates
    /// will be prompt-free.
    static func migrateToAllowAllAccess() {
        let keys = [KeychainKey.harvestToken, KeychainKey.harvestAccountId]
        for key in keys {
            guard let data = try? load(key: key) else { continue }
            try? save(key: key, data: data)
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
