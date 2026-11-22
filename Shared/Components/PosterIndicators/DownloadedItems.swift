//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS) || os(macOS)

import Combine
import FactoryKit
import Foundation

/// The items with a finished download, per user.
///
/// Posters observe this instead of the `DownloadManager`
/// so that they are not redrawn on every progress update.
@MainActor
final class DownloadedItems: ObservableObject {

    static let shared = DownloadedItems()

    @Published
    private var itemIDs: [String: Set<String>] = [:]

    private init() {
        Container.shared.downloadManager().$records
            .map { records in
                records
                    .filter { $0.state == .completed }
                    .reduce(into: [String: Set<String>]()) { result, record in
                        result[record.userID, default: []].insert(record.id)
                    }
            }
            .removeDuplicates()
            .assign(to: &$itemIDs)
    }

    func contains(_ itemID: String?) -> Bool {
        guard let itemID,
              itemIDs.isNotEmpty,
              let userID = Container.shared.currentUserSession()?.user.id
        else { return false }

        return itemIDs[userID]?.contains(itemID) == true
    }
}

#endif
