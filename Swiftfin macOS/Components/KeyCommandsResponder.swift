//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AppKit
import SwiftUI

/// Serves the `keyCommands` declared by its content from the key events of its own window.
struct KeyCommandsResponder: ViewModifier {

    @ContentBuilder
    func body(content: Content) -> some View {
        content
            .backgroundPreferenceValue(KeyCommandsPreferenceKey.self) { commands in
                KeyCommandsMonitor(commands: commands)
                    .accessibilityHidden(true)
            }
            // An enclosing responder must not perform the same commands again.
            .transformPreference(KeyCommandsPreferenceKey.self) { $0 = [] }
    }
}

private struct KeyCommandsMonitor: NSViewRepresentable {

    let commands: [KeyCommandAction]

    func makeNSView(context: Context) -> MonitorView {
        MonitorView()
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.commands = commands
    }

    static func dismantleNSView(_ nsView: MonitorView, coordinator: ()) {
        nsView.removeMonitor()
    }

    final class MonitorView: NSView {

        var commands: [KeyCommandAction] = []

        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            removeMonitor()

            guard window != nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.perform(event) == true ? nil : event
            }
        }

        func removeMonitor() {
            guard let monitor else { return }

            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        private func perform(_ event: NSEvent) -> Bool {
            // Sheets, popovers and menus are other windows and keep their own keys.
            guard commands.isNotEmpty,
                  let window,
                  event.window === window,
                  window.attachedSheet == nil
            else { return false }

            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])

            if modifiers.isDisjoint(with: [.command, .control]), window.firstResponder is NSText {
                return false
            }

            guard let input = event.charactersIgnoringModifiers?.lowercased(),
                  let command = commands.first(where: { $0.input == input && $0.modifierFlags == modifiers })
            else { return false }

            // Only the arrow keys repeat while held.
            if event.isARepeat, !event.modifierFlags.contains(.function) {
                return true
            }

            command.action()

            return true
        }
    }
}
