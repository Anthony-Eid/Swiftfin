//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AppKit
import SwiftUI

// The shared layer uses UIKit names for image/color/device APIs. Keep those
// names scoped to the native Mac target instead of leaking AppKit through
// every portable file.
typealias UIImage = NSImage
typealias UIColor = NSColor
typealias UIFont = NSFont

extension NSColor {

    static var secondarySystemBackground: NSColor {
        controlBackgroundColor
    }

    static var tertiarySystemBackground: NSColor {
        underPageBackgroundColor
    }
}

extension NSImage {

    var cgImage: CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }

    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: .zero)
    }

    func pngData() -> Data? {
        guard let cgImage else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
    }

    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let cgImage else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: compressionQuality]
        )
    }
}

extension NSFont {

    static func preferredFont(forTextStyle style: NSFont.TextStyle) -> NSFont {
        preferredFont(forTextStyle: style, options: [:])
    }
}

enum UIBlurEffect {
    enum Style {
        case regular
    }
}

extension ToolbarItemPlacement {
    static var topBarLeading: Self {
        .navigation
    }

    static var topBarTrailing: Self {
        .automatic
    }

    static var navigationBarLeading: Self {
        .navigation
    }

    static var navigationBarTrailing: Self {
        .automatic
    }

    static var bottomBar: Self {
        .status
    }
}

extension View {
    @ViewBuilder
    func prefersStatusBarHidden(_ hidden: Bool = true) -> some View {
        self
    }
}

extension Image {
    init(uiImage: NSImage) {
        self.init(nsImage: uiImage)
    }
}
