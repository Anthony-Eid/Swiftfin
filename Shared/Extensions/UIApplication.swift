//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if canImport(UIKit)
import UIKit
#elseif os(macOS)
import AppKit
#endif
#if !os(macOS)

extension UIApplication {

    static var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    static var bundleVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    #if DEBUG
    static var gitBranch: String? {
        guard let url = Bundle.main.url(forResource: "GitBranch", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }

        let branch = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty ? nil : branch
    }
    #endif

    var keyWindow: UIWindow? {
        connectedScenes
            .compactMap {
                $0 as? UIWindowScene
            }
            .flatMap(\.windows)
            .first {
                $0.isKeyWindow
            }
    }
}
#else

/// AppKit's `NSApplication` shares little with `UIApplication`; this stands
/// in for the parts of `UIApplication` that the shared layer reads.
@MainActor
final class UIApplication {

    static let shared = UIApplication()

    nonisolated static var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    nonisolated static var bundleVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    #if DEBUG
    nonisolated static var gitBranch: String? {
        guard let url = Bundle.main.url(forResource: "GitBranch", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }

        let branch = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty ? nil : branch
    }
    #endif

    /// - Important: The Mac has no alternate app icons, always `nil`.
    var alternateIconName: String? {
        nil
    }

    /// - Important: The Mac has no alternate app icons, does nothing.
    func setAlternateIconName(_ name: String?) async throws {}

    func canOpenURL(_ url: URL) -> Bool {
        NSWorkspace.shared.urlForApplication(toOpen: url) != nil
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func open(_ url: URL, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(NSWorkspace.shared.open(url))
    }

    @discardableResult
    func open(_ url: URL) async -> Bool {
        NSWorkspace.shared.open(url)
    }
}
#endif
