//
//  KeychainHelper.swift
//  HarvestPlus
//
//  Thin wrapper around Keychain Services. Uses the **data-protection
//  keychain** (the same API as iOS) rather than macOS's legacy
//  SecKeychain – that's the single change that makes credential reads
//  silent across Debug builds, Release builds, ad-hoc re-signs, and any
//  future signature rotation.
//
//  Why the data-protection keychain?
//  ---------------------------------
//  Legacy macOS keychain uses per-binary ACLs (SecAccessCreate +
//  kSecAttrAccess). Every time the binary's code signature changes,
//  macOS challenges the user with a password prompt – even with an
//  "empty trusted-apps" SecAccess (which, contrary to lore, is not
//  actually "allow all"; it's treated like nil in practice and falls
//  back to "only the creator binary").
//
//  The data-protection keychain replaces per-binary ACLs with **access
//  groups**. Access is granted to any binary that:
//    - is signed with the same Apple team ID, and
//    - declares the same access group via the `keychain-access-groups`
//      entitlement.
//
//  Our entitlement declares `$(AppIdentifierPrefix)com.qampo.HarvestPlus`
//  which Xcode expands at signing time to `PA8H58YHD6.com.qampo.HarvestPlus`.
//  Both Debug (Apple Development cert) and Release (Developer ID
//  Application cert) signatures carry team `PA8H58YHD6`, so both
//  binaries see the same keychain items without prompting.
//

import Foundation
import Security

// MARK: - Keychain Helper

enum KeychainHelper {

    private static let service = "com.harvestplus"

    /// Base attributes shared by every operation. The
    /// `kSecUseDataProtectionKeychain` flag routes the call to the modern
    /// keychain on macOS; without it Keychain Services falls back to the
    /// legacy SecKeychain.
    private static var baseQuery: [String: Any] {
        [
            kSecClass as String:                     kSecClassGenericPassword,
            kSecAttrService as String:               service,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    // MARK: - Save

    static func save(key: String, data: Data) throws {
        var lookup = baseQuery
        lookup[kSecAttrAccount as String] = key

        // Update path: change the stored value only. The data-protection
        // keychain doesn't need an ACL to be passed on every save, so this
        // is a single SecItemUpdate with no extra flags.
        let updateAttribs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(lookup as CFDictionary, updateAttribs as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // First time creating the item – add it with an accessibility
            // class that survives reboot once the user logs in, and doesn't
            // sync to iCloud.
            var addQuery = lookup
            addQuery[kSecValueData as String]      = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
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
        var query = baseQuery
        query[kSecAttrAccount as String] = key
        query[kSecReturnData as String]  = true
        query[kSecMatchLimit as String]  = kSecMatchLimitOne

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
        var query = baseQuery
        query[kSecAttrAccount as String] = key

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
