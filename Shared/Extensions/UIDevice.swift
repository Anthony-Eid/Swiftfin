//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension UIDevice {

    static var vendorUUIDString: String {
        #if os(macOS)
        // AppKit has no vendor identifier, so persist one per install
        let key = "deviceIdentifier"
        if let identifier = UserDefaults.standard.string(forKey: key), !identifier.isEmpty {
            return identifier
        }

        let identifier = UUID().uuidString
        UserDefaults.standard.set(identifier, forKey: key)
        return identifier
        #else
        current.identifierForVendor!.uuidString
        #endif
    }

    static var isPad: Bool {
        #if os(macOS)
        false
        #else
        current.userInterfaceIdiom == .pad
        #endif
    }

    static var isPhone: Bool {
        #if os(macOS)
        false
        #else
        current.userInterfaceIdiom == .phone
        #endif
    }

    static var isTV: Bool {
        #if os(macOS)
        false
        #else
        current.userInterfaceIdiom == .tv
        #endif
    }

    static let supportsLiquidGlass: Bool = {
        #if os(tvOS)
        var systemInfo = utsname()
        uname(&systemInfo)
        let model = withUnsafeBytes(of: systemInfo.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        // Apple TV HD and Apple TV 4K (1st gen) run tvOS 26 without Liquid Glass
        // - https://support.apple.com/en-us/106336
        // - See tvOS 26, footnote 2
        return !["AppleTV5,3", "AppleTV6,2"].contains(model)
        #else
        if #available(iOS 26.0, *) {
            return true
        } else {
            return false
        }
        #endif
    }()

    static var platform: String {
        #if os(tvOS)
        L10n.tvOS
        #elseif os(macOS)
        "macOS"
        #else
        if UIDevice.isPad {
            L10n.iPadOS
        } else {
            L10n.iOS
        }
        #endif
    }

    /// - Important: Does nothing on non-iOS platforms.
    ///
    /// - Note: For real-time interactions, manually manage a
    ///         `UIImpactFeedbackGenerator` with `prepare()`.
    static func feedback(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(type)
        #endif
    }

    // TODO: make more custom feedback types with Core Haptics
    //       - soft with intensity
    /// - Important: Does nothing on non-iOS platforms.
    ///
    /// - Note: For real-time interactions, manually manage a
    ///         `UIImpactFeedbackGenerator` with `prepare()`.
    static func impact(_ type: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: type).impactOccurred()
        #endif
    }
}

#if os(tvOS)
enum UINotificationFeedbackGenerator {

    enum FeedbackType {

        case success
        case warning
        case error
    }
}

enum UIImpactFeedbackGenerator {

    enum FeedbackStyle {

        case light
        case medium
        case heavy
    }
}
#endif

#if os(macOS)
/// The Mac has no vendor identifier or haptics; this stands in for
/// the parts of `UIDevice` that the shared layer reads.
final class UIDevice {

    static let current = UIDevice()

    let name: String = Host.current().localizedName ?? "Mac"
}

enum UINotificationFeedbackGenerator {

    enum FeedbackType {

        case success
        case warning
        case error
    }
}

/// - Important: Does nothing on macOS.
final class UIImpactFeedbackGenerator {

    enum FeedbackStyle {

        case light
        case medium
        case heavy
        case soft
        case rigid
    }

    init(style: FeedbackStyle) {}

    func prepare() {}
    func impactOccurred() {}
    func impactOccurred(intensity: CGFloat) {}
}
#endif
