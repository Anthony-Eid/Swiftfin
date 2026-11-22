//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import KeychainSwift
import Security

/// Stores secrets in the data protection keychain when the app is signed
/// with a team, and in a private file in the app's container otherwise.
///
/// The default file-based macOS keychain ties an item's access to the
/// code signature that created it. An ad-hoc signed build has a new
/// signature on every build, so every launch would block on a system
/// password prompt. The data protection keychain has no such prompt but
/// requires an application identifier entitlement that ad-hoc signing
/// cannot provide.
final class MacKeychain: KeychainSwift {

    private let lock = NSLock()

    private let service = Bundle.main.bundleIdentifier ?? "org.jellyfin.swiftfin"

    /// Reading can report "not found" without the entitlement, so only
    /// a successful write shows that the keychain is usable.
    private lazy var usesDataProtectionKeychain: Bool = {
        var query = baseQuery(for: "availability-probe")
        query[kSecValueData as String] = Data()

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { return false }

        SecItemDelete(baseQuery(for: "availability-probe") as CFDictionary)
        return true
    }()

    private func baseQuery(for key: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true,
        ]

        if let key {
            query[kSecAttrAccount as String] = key
        }

        return query
    }

    // MARK: - KeychainSwift

    @discardableResult
    override func set(
        _ value: Data,
        forKey key: String,
        withAccess access: KeychainSwiftAccessOptions? = nil
    ) -> Bool {
        lock.withLock {
            guard usesDataProtectionKeychain else {
                var contents = fileContents
                contents[key] = value
                return write(contents)
            }

            SecItemDelete(baseQuery(for: key) as CFDictionary)

            var query = baseQuery(for: key)
            query[kSecValueData as String] = value
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

            lastResultCode = SecItemAdd(query as CFDictionary, nil)
            return lastResultCode == errSecSuccess
        }
    }

    override func getData(_ key: String, asReference: Bool = false) -> Data? {
        lock.withLock {
            guard usesDataProtectionKeychain else {
                return fileContents[key]
            }

            var query = baseQuery(for: key)
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecReturnData as String] = true

            var result: AnyObject?
            lastResultCode = SecItemCopyMatching(query as CFDictionary, &result)

            return lastResultCode == errSecSuccess ? result as? Data : nil
        }
    }

    @discardableResult
    override func delete(_ key: String) -> Bool {
        lock.withLock {
            guard usesDataProtectionKeychain else {
                var contents = fileContents
                contents[key] = nil
                return write(contents)
            }

            lastResultCode = SecItemDelete(baseQuery(for: key) as CFDictionary)
            return lastResultCode == errSecSuccess
        }
    }

    @discardableResult
    override func clear() -> Bool {
        lock.withLock {
            guard usesDataProtectionKeychain else {
                return write([:])
            }

            lastResultCode = SecItemDelete(baseQuery(for: nil) as CFDictionary)
            return lastResultCode == errSecSuccess
        }
    }

    // MARK: - File store

    private var fileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: service, directoryHint: .isDirectory)
            .appending(path: "credentials.plist")
    }

    private var fileContents: [String: Data] {
        guard let data = try? Data(contentsOf: fileURL),
              let contents = try? PropertyListDecoder().decode([String: Data].self, from: data)
        else { return [:] }

        return contents
    }

    private func write(_ contents: [String: Data]) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary

            try encoder.encode(contents).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)

            return true
        } catch {
            return false
        }
    }
}
