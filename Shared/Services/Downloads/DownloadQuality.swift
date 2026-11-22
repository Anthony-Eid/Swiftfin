//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if !os(tvOS)

import Foundation

/// The original file, or a copy transcoded by the server to a total bitrate
struct DownloadQuality: Codable, Hashable, Identifiable {

    /// Total bits per second, `nil` for the original file
    let bitrate: Int?

    static let original = DownloadQuality(bitrate: nil)

    static var allOptions: [DownloadQuality] {
        let bitrates: [PlaybackBitrate] = [.mbps20, .mbps10, .mbps6, .mbps4, .mbps2, .mbps1]

        return [.original] + bitrates.map { DownloadQuality(bitrate: $0.rawValue) }
    }

    var id: String {
        bitrate.map(String.init) ?? "original"
    }

    var isOriginal: Bool {
        bitrate == nil
    }

    var displayTitle: String {
        guard let bitrate else { return "Original" }

        return PlaybackBitrate(rawValue: bitrate)?.displayTitle ?? bitrate.formatted(.bitRate)
    }
}

#endif
