//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

@main
struct SwiftfinApp: App {

    init() {
        Self.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Deep links go to an open window instead of opening another
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
    }
}
