//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AppKit
import SwiftUI

/// Reports how far across the view it backs the pointer currently is.
struct PointerProgressReader: NSViewRepresentable {

    @MainActor
    final class Proxy {

        fileprivate weak var view: NSView?

        var progress: Double? {
            guard let view, let window = view.window, view.bounds.width > 0 else { return nil }

            let location = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            let progress = clamp(location.x / view.bounds.width, min: 0, max: 1)

            return view.userInterfaceLayoutDirection == .rightToLeft ? 1 - progress : progress
        }
    }

    let proxy: Proxy

    func makeNSView(context: Context) -> NSView {
        let view = ReaderView()
        proxy.view = view

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        proxy.view = nsView
    }

    private final class ReaderView: NSView {

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
