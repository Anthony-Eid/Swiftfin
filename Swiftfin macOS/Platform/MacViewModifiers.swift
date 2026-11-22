//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
import CollectionVGrid
import SwiftUI

// macOS spellings of iOS-only SwiftUI modifiers, so that shared call sites
// do not each need a platform branch. Everything here either maps onto the
// macOS equivalent or is a no-op for a concept macOS does not have.

// MARK: - Text input

/// There is no software keyboard to configure on macOS.
enum UIKeyboardType {
    case `default`
    case asciiCapable
    case numbersAndPunctuation
    case URL
    case numberPad
    case phonePad
    case namePhonePad
    case emailAddress
    case decimalPad
    case twitter
    case webSearch
    case asciiCapableNumberPad
}

/// AppKit text fields never auto-capitalize.
struct TextInputAutocapitalization {
    static let never = TextInputAutocapitalization()
    static let words = TextInputAutocapitalization()
    static let sentences = TextInputAutocapitalization()
    static let characters = TextInputAutocapitalization()
}

extension View {

    func keyboardType(_ type: UIKeyboardType) -> some View {
        self
    }

    func textInputAutocapitalization(_ autocapitalization: TextInputAutocapitalization?) -> some View {
        self
    }
}

// MARK: - Pointer

/// AppKit controls draw their own hover state.
struct MacHoverEffect {
    static let automatic = MacHoverEffect()
    static let highlight = MacHoverEffect()
    static let lift = MacHoverEffect()
}

extension View {

    func hoverEffect(_ effect: MacHoverEffect = .automatic) -> some View {
        self
    }
}

extension ContentShapeKinds {

    /// Context menus have no lifted preview on macOS.
    static var contextMenuPreview: ContentShapeKinds {
        []
    }
}

// MARK: - Toolbar

extension ToolbarPlacement {

    static var navigationBar: ToolbarPlacement {
        .windowToolbar
    }
}

// MARK: - Collections

/// AppKit scroll views have no content inset adjustment behavior.
enum MacContentInsetAdjustmentBehavior {
    case automatic
    case scrollableAxes
    case never
    case always
}

extension CollectionHStack {

    func contentInsetAdjustmentBehavior(_ behavior: MacContentInsetAdjustmentBehavior) -> Self {
        self
    }
}

extension CollectionVGrid {

    func contentInsetAdjustmentBehavior(_ behavior: MacContentInsetAdjustmentBehavior) -> Self {
        self
    }
}
