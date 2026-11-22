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

extension DownloadManager {

    /// The server treats an item as finished from this share of its runtime
    private static let playedPercentage = 90.0

    // MARK: - Playback progress

    /// Remembers the position of local playback until it can be sent to the server
    func recordPlayback(itemID: String, positionTicks: Int) {
        guard record(for: itemID) != nil, positionTicks >= 0 else { return }

        update(itemID) { record in
            let now = Date.now

            record.localPlaybackPositionTicks = positionTicks
            record.localPlaybackDate = now
            record.needsProgressSync = true

            // The downloads list reads the resume position from the item
            var userData = record.item.userData ?? UserItemDataDto(key: itemID)
            let runtime = record.item.runTimeTicks ?? 0
            let percentage = runtime > 0 ? min(100, Double(positionTicks) / Double(runtime) * 100) : 0

            if percentage >= Self.playedPercentage {
                userData.isPlayed = true
                userData.playbackPositionTicks = 0
                userData.playedPercentage = nil
            } else {
                userData.playbackPositionTicks = positionTicks
                userData.playedPercentage = percentage
            }

            userData.lastPlayedDate = now
            record.item.userData = userData
        }
    }

    /// Sends the positions recorded while offline to the server
    func syncPlaybackProgress(userSession: UserSession) async {
        guard !isSyncingProgress else { return }

        isSyncingProgress = true
        defer { isSyncingProgress = false }

        let client = userSession.client
        let userID = userSession.user.id

        for pending in records(for: userSession) where pending.needsProgressSync {
            guard let localData = pending.item.userData, let localDate = pending.localPlaybackDate else {
                update(pending.id) { $0.needsProgressSync = false }
                continue
            }

            do {
                let serverData = try await client.send(Paths.getItemUserData(itemID: pending.id, userID: userID)).value
                let result: UserItemDataDto

                if let serverDate = serverData.lastPlayedDate, serverDate >= localDate {
                    // Something else played the item more recently
                    result = serverData
                } else {
                    var body = UpdateUserItemDataDto()
                    body.playbackPositionTicks = localData.playbackPositionTicks
                    body.lastPlayedDate = localDate

                    if localData.isPlayed == true, localData.playbackPositionTicks == 0 {
                        body.isPlayed = true
                    }

                    result = try await client.send(Paths.updateItemUserData(itemID: pending.id, userID: userID, body)).value
                }

                update(pending.id) {
                    // Playback may have moved on while the request was in flight
                    guard $0.localPlaybackDate == localDate else { return }

                    $0.needsProgressSync = false
                    $0.item.userData = result
                }

                if let token = try? userSession.items.beginRequest() {
                    var result = result
                    result.itemID = result.itemID ?? pending.id
                    try? userSession.items.mergeUserData(result, token: token)
                }
            } catch {
                // Unreachable server, the positions stay pending
                logger.debug("Unable to sync offline playback progress: \(error.localizedDescription)")
                return
            }
        }
    }

    // MARK: - Offline episodes

    /// The downloaded episodes around a downloaded episode, in series order
    func adjacentDownloadedEpisodes(of item: BaseItemDto) -> (previous: BaseItemDto?, next: BaseItemDto?)? {
        guard item.type == .episode,
              let current = record(for: item.id),
              mediaURL(for: current) != nil else { return nil }

        let episodes = records
            .filter {
                $0.serverID == current.serverID
                    && $0.userID == current.userID
                    && $0.item.type == .episode
                    && $0.item.seriesID == current.item.seriesID
                    && mediaURL(for: $0) != nil
            }
            .map(\.item)
            .sorted {
                ($0.parentIndexNumber ?? 0, $0.indexNumber ?? 0) < ($1.parentIndexNumber ?? 0, $1.indexNumber ?? 0)
            }

        guard let index = episodes.firstIndex(where: { $0.id == current.id }) else { return nil }

        return (
            index > 0 ? episodes[index - 1] : nil,
            index + 1 < episodes.count ? episodes[index + 1] : nil
        )
    }
}

#endif
