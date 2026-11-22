//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if !os(tvOS)

import Foundation
import JellyfinAPI

/// Everything needed to browse and play one downloaded movie or episode
/// without the server. Stored as a JSON file next to the media file.
struct DownloadRecord: Codable, Hashable, Identifiable {

    enum State: String, Codable {
        case queued
        case downloading
        case paused
        case completed
        case failed
    }

    enum Image: String, Codable, CaseIterable {
        case primary
        case backdrop
        case seriesPrimary
    }

    /// The Jellyfin item ID
    var id: String
    var serverID: String
    var userID: String

    /// The full item, including media sources, media streams and user data
    var item: BaseItemDto
    var mediaSourceID: String?

    /// Parents of an episode, for grouping while offline
    var series: BaseItemDto?
    var season: BaseItemDto?

    var state: State
    var errorMessage: String?

    var bytesReceived: Int64
    var bytesExpected: Int64

    /// File names relative to the record's directory
    var mediaFileName: String?
    var imageFileNames: [Image: String]

    var dateCreated: Date
    var dateCompleted: Date?

    /// The last position played from the local file
    var localPlaybackPositionTicks: Int?
    var localPlaybackDate: Date?
    /// Whether `localPlaybackPositionTicks` still has to be sent to the server
    var needsProgressSync: Bool

    var progress: Double {
        guard bytesExpected > 0 else { return 0 }
        return min(1, Double(bytesReceived) / Double(bytesExpected))
    }
}

#endif
