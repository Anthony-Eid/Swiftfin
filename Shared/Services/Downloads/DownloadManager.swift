//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if !os(tvOS)

import Combine
import FactoryKit
import Foundation
import JellyfinAPI

extension Container {

    var downloadManager: Factory<DownloadManager> {
        self { MainActor.assumeIsolated { DownloadManager() } }.singleton
    }
}

/// Owns the download queue and the downloaded items on disk.
@MainActor
final class DownloadManager: ObservableObject {

    /// Every record on disk, for all servers and users, oldest first
    @Published
    private(set) var records: [DownloadRecord] = []

    init() {}

    // MARK: - Reading

    func record(for itemID: String?) -> DownloadRecord? {
        guard let itemID else { return nil }
        return records.first { $0.id == itemID }
    }

    func records(for userSession: UserSession) -> [DownloadRecord] {
        records.filter { $0.serverID == userSession.server.id && $0.userID == userSession.user.id }
    }

    /// The local media file, only when the download is complete and the file exists
    func mediaURL(for record: DownloadRecord) -> URL? {
        nil
    }

    func imageURL(_ image: DownloadRecord.Image, for record: DownloadRecord) -> URL? {
        nil
    }

    /// Bytes on disk for the given records
    func storageUsed(by records: [DownloadRecord]) -> Int64 {
        0
    }

    // MARK: - Queue

    /// Whether the item itself (a movie or episode) can be downloaded
    static func canDownload(_ item: BaseItemDto) -> Bool {
        false
    }

    /// Whether the item is a series or season whose episodes can be downloaded
    static func canDownloadChildren(of item: BaseItemDto) -> Bool {
        false
    }

    /// Queues a movie or episode. Does nothing when a record already exists.
    func download(_ item: BaseItemDto, userSession: UserSession) {}

    /// Queues every episode of a series or season.
    func downloadChildren(of item: BaseItemDto, userSession: UserSession) async throws {}

    func pause(_ itemID: String) {}

    func resume(_ itemID: String) {}

    /// Cancels an unfinished download or deletes a finished one, with its files
    func delete(_ itemID: String) {}

    // MARK: - Playback progress

    /// Remembers the position of local playback until it can be sent to the server
    func recordPlayback(itemID: String, positionTicks: Int) {}

    /// Sends the positions recorded while offline to the server
    func syncPlaybackProgress(userSession: UserSession) async {}
}

#endif
