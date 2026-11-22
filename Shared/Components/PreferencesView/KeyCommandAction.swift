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

struct KeyCommandAction {

    #if os(macOS)
    typealias ModifierFlags = NSEvent.ModifierFlags
    #else
    typealias ModifierFlags = UIKeyModifierFlags
    #endif

    let title: String
    let subtitle: String?
    let input: String
    let modifierFlags: ModifierFlags
    let action: @MainActor () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        input: String,
        modifierFlags: ModifierFlags = [],
        action: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.input = input
        self.modifierFlags = modifierFlags
        self.action = action
    }
}

extension KeyCommandAction {

    #if os(macOS)
    /// Matches `NSEvent.charactersIgnoringModifiers` for the key.
    static let inputLeftArrow = functionKey(NSLeftArrowFunctionKey)
    static let inputRightArrow = functionKey(NSRightArrowFunctionKey)
    static let inputUpArrow = functionKey(NSUpArrowFunctionKey)
    static let inputDownArrow = functionKey(NSDownArrowFunctionKey)
    static let inputEscape = "\u{1B}"

    private static func functionKey(_ key: Int) -> String {
        UnicodeScalar(key).map { String(Character($0)) } ?? ""
    }
    #elseif os(iOS)
    static let inputLeftArrow = UIKeyCommand.inputLeftArrow
    static let inputRightArrow = UIKeyCommand.inputRightArrow
    static let inputUpArrow = UIKeyCommand.inputUpArrow
    static let inputDownArrow = UIKeyCommand.inputDownArrow
    static let inputEscape = UIKeyCommand.inputEscape
    #endif
}

extension KeyCommandAction: Equatable {

    static func == (lhs: KeyCommandAction, rhs: KeyCommandAction) -> Bool {
        lhs.input == rhs.input
    }
}
