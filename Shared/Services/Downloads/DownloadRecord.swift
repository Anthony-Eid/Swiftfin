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
    var quality: DownloadQuality = .original

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

    /// Whether `item` and its parents were fetched in full for this record
    var hasFullMetadata: Bool = false

    var progress: Double {
        guard state != .completed else { return 1 }
        guard bytesExpected > 0 else { return 0 }
        // The size of a transcode is an estimate until it finishes
        return min(quality.isOriginal ? 1 : 0.99, Double(bytesReceived) / Double(bytesExpected))
    }

    /// A transcode is produced on demand and cannot be continued from a byte offset
    var supportsPause: Bool {
        quality.isOriginal
    }
}

extension DownloadRecord {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            id: try container.decode(String.self, forKey: .id),
            serverID: try container.decode(String.self, forKey: .serverID),
            userID: try container.decode(String.self, forKey: .userID),
            item: try container.decode(BaseItemDto.self, forKey: .item),
            mediaSourceID: try container.decodeIfPresent(String.self, forKey: .mediaSourceID),
            quality: try container.decodeIfPresent(DownloadQuality.self, forKey: .quality) ?? .original,
            series: try container.decodeIfPresent(BaseItemDto.self, forKey: .series),
            season: try container.decodeIfPresent(BaseItemDto.self, forKey: .season),
            state: try container.decode(State.self, forKey: .state),
            errorMessage: try container.decodeIfPresent(String.self, forKey: .errorMessage),
            bytesReceived: try container.decode(Int64.self, forKey: .bytesReceived),
            bytesExpected: try container.decode(Int64.self, forKey: .bytesExpected),
            mediaFileName: try container.decodeIfPresent(String.self, forKey: .mediaFileName),
            imageFileNames: try container.decodeIfPresent([Image: String].self, forKey: .imageFileNames) ?? [:],
            dateCreated: try container.decode(Date.self, forKey: .dateCreated),
            dateCompleted: try container.decodeIfPresent(Date.self, forKey: .dateCompleted),
            localPlaybackPositionTicks: try container.decodeIfPresent(Int.self, forKey: .localPlaybackPositionTicks),
            localPlaybackDate: try container.decodeIfPresent(Date.self, forKey: .localPlaybackDate),
            needsProgressSync: try container.decodeIfPresent(Bool.self, forKey: .needsProgressSync) ?? false,
            hasFullMetadata: try container.decodeIfPresent(Bool.self, forKey: .hasFullMetadata) ?? false
        )
    }
}

#endif
