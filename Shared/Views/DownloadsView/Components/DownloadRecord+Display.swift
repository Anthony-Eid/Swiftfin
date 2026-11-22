//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS) || os(macOS)

import Foundation
import JellyfinAPI

extension DownloadRecord {

    var isInFlight: Bool {
        state == .queued || state == .downloading
    }

    var isEpisode: Bool {
        item.type == .episode
    }

    var seriesTitle: String {
        series?.displayTitle ?? item.seriesName ?? L10n.unknown
    }

    var seasonTitle: String? {
        if let season {
            return season.displayTitle
        }

        if let seasonName = item.seasonName {
            return seasonName
        }

        return item.parentIndexNumber.map { "\(L10n.season) \($0)" }
    }

    var percentLabel: String {
        progress.formatted(.percent.precision(.fractionLength(0)))
    }

    /// The size of the file, or what is known of it while downloading
    var sizeLabel: String? {
        let bytes = state == .completed || bytesExpected <= 0 || !quality.isOriginal ? bytesReceived : bytesExpected

        guard bytes > 0 else { return nil }

        return bytes.formatted(.byteCount(style: .file))
    }

    /// The fraction to draw, `nil` when it is not known
    var displayProgress: Double? {
        guard state != .queued, bytesExpected > 0 else { return nil }

        return progress
    }

    var statusLabel: String? {
        switch state {
        case .queued:
            return "Queued"
        case .downloading:
            guard bytesExpected > 0 else {
                return bytesReceived > 0 ? bytesReceived.formatted(.byteCount(style: .file)) : "Downloading"
            }

            // The total of a transcode is an estimate
            guard quality.isOriginal else { return percentLabel }

            let received = bytesReceived.formatted(.byteCount(style: .file))
            let expected = bytesExpected.formatted(.byteCount(style: .file))

            return "\(received) of \(expected)"
        case .paused:
            return bytesExpected > 0 ? "Paused, \(percentLabel)" : "Paused"
        case .failed:
            return errorMessage ?? L10n.taskFailed
        case .completed:
            return nil
        }
    }

    var resumePosition: Duration? {
        guard let ticks = localPlaybackPositionTicks ?? item.userData?.playbackPositionTicks, ticks > 0 else { return nil }

        return Duration.ticks(ticks)
    }

    /// Episode number, runtime, size and quality
    var detailLabels: [String] {
        var labels: [String] = []

        if isEpisode, let label = item.seasonEpisodeLabel ?? item.episodeLocator {
            labels.append(label)
        }

        if let runtime = item.runTimeLabel {
            labels.append(runtime)
        }

        if let sizeLabel {
            labels.append(sizeLabel)
        }

        labels.append(quality.displayTitle)

        return labels
    }
}

#endif
