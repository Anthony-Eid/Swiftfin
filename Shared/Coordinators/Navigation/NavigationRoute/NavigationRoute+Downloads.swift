//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS) || os(macOS)

import SwiftUI

extension NavigationRoute {

    @MainActor
    static func downloadedItem(recordID: String) -> NavigationRoute {
        NavigationRoute(id: "downloadedItem-\(recordID)") {
            DownloadedItemView(recordID: recordID)
        }
    }
}

#endif
