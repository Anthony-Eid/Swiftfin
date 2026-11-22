//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension View {

    #if os(iOS) || os(macOS)
    @ContentBuilder
    func keyCommands(@ArrayBuilder<KeyCommandAction> _ commands: () -> [KeyCommandAction]) -> some View {
        preference(key: KeyCommandsPreferenceKey.self, value: commands())
    }
    #endif

    #if os(tvOS)
    @ContentBuilder
    func pressCommands(@ArrayBuilder<PressCommandAction> _ commands: () -> [PressCommandAction]) -> some View {
        preference(key: PressCommandsPreferenceKey.self, value: commands())
    }
    #endif

    /// - Important: This does nothing on tvOS and macOS.
    @ContentBuilder
    func supportedOrientations(_ supportedOrientations: UIInterfaceOrientationMask) -> some View {
        #if os(tvOS) || os(macOS)
        self
        #else
        preference(key: SupportedOrientationsPreferenceKey.self, value: supportedOrientations)
        #endif
    }
}
