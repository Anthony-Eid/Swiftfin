//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if !os(tvOS)

import Foundation
import Get
import JellyfinAPI

/// Builds the requests of a download. The access token only ever travels in the
/// `Authorization` header, never in a URL or in a record.
@MainActor
enum DownloadRequestBuilder {

    enum Endpoint: Equatable {

        /// `/Items/{id}/Download`, which needs the content downloading permission
        case download
        /// The original file through the direct play endpoint
        case staticStream
        case transcode(playSessionID: String)
    }

    /// Plays reliably from a file written by a non-seekable transcode
    static let transcodeContainer = "ts"

    static func authorization(for userSession: UserSession) -> String {
        let configuration = userSession.client.configuration

        // Same fields as JellyfinClient sends
        let fields = [
            "DeviceId": configuration.deviceID,
            "Device": configuration.deviceName,
            "Client": configuration.client,
            "Version": configuration.version,
            "Token": configuration.accessToken ?? userSession.user.accessToken,
        ]

        return "MediaBrowser " + fields.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
    }

    static func request(
        path: String,
        query: [(String, String?)] = [],
        userSession: UserSession
    ) -> URLRequest? {
        let url = userSession.server.effectiveServerURL.appendingPathComponent(path)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        let items = query.compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
        if items.isNotEmpty {
            components.queryItems = (components.queryItems ?? []) + items
        }

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(authorization(for: userSession), forHTTPHeaderField: "Authorization")
        return request
    }

    static func mediaRequest(
        for record: DownloadRecord,
        endpoint: Endpoint,
        userSession: UserSession
    ) -> URLRequest? {
        let source = mediaSource(of: record)
        let sourceID = record.mediaSourceID ?? record.id

        switch endpoint {
        case .download:
            // Alternate versions are items of their own
            return request(path: "Items/\(sourceID)/Download", userSession: userSession)

        case .staticStream:
            return request(
                path: "Videos/\(record.id)/stream",
                query: [
                    ("static", "true"),
                    ("mediaSourceId", sourceID),
                    ("tag", source?.eTag),
                ],
                userSession: userSession
            )

        case let .transcode(playSessionID):
            guard let target = TranscodeTarget(quality: record.quality) else { return nil }

            let audioIndex = source?.mediaStreams?.first { $0.type == .audio }?.index

            return request(
                path: "Videos/\(record.id)/stream.\(transcodeContainer)",
                query: [
                    ("static", "false"),
                    ("mediaSourceId", sourceID),
                    ("deviceId", userSession.client.configuration.deviceID),
                    ("playSessionId", playSessionID),
                    ("videoCodec", "h264"),
                    ("audioCodec", "aac"),
                    ("videoBitRate", String(target.videoBitrate)),
                    ("audioBitRate", String(target.audioBitrate)),
                    ("maxAudioChannels", "2"),
                    ("maxWidth", target.maxSize.map { String($0.width) }),
                    ("maxHeight", target.maxSize.map { String($0.height) }),
                    ("audioStreamIndex", audioIndex.map(String.init)),
                    ("subtitleMethod", "Drop"),
                    ("allowVideoStreamCopy", "false"),
                    ("allowAudioStreamCopy", "false"),
                ],
                userSession: userSession
            )
        }
    }

    /// Tells the server to stop a transcode nobody reads anymore
    static func stopTranscode(playSessionID: String, userSession: UserSession) {
        let client = userSession.client
        let request = Request<Void>(
            path: "/Videos/ActiveEncodings",
            method: "DELETE",
            query: [("deviceId", client.configuration.deviceID), ("playSessionId", playSessionID)]
        )

        Task {
            _ = try? await client.send(request)
        }
    }

    static func imageRequests(for item: BaseItemDto, userSession: UserSession) -> [DownloadRecord.Image: URLRequest] {
        guard let itemID = item.id else { return [:] }

        var requests: [DownloadRecord.Image: URLRequest] = [:]

        func image(_ type: ImageType, itemID: String, tag: String?, maxWidth: Int) -> URLRequest? {
            request(
                path: "Items/\(itemID)/Images/\(type.rawValue)",
                query: [("tag", tag), ("maxWidth", String(maxWidth)), ("quality", "90")],
                userSession: userSession
            )
        }

        if let tag = item.imageTags?[ImageType.primary.rawValue] {
            requests[.primary] = image(.primary, itemID: itemID, tag: tag, maxWidth: 800)
        }

        if let tag = item.backdropImageTags?.first {
            requests[.backdrop] = image(.backdrop, itemID: itemID, tag: tag, maxWidth: 1920)
        } else if let parentID = item.parentBackdropItemID, let tag = item.parentBackdropImageTags?.first {
            requests[.backdrop] = image(.backdrop, itemID: parentID, tag: tag, maxWidth: 1920)
        }

        if item.type == .episode, let seriesID = item.seriesID {
            requests[.seriesPrimary] = image(.primary, itemID: seriesID, tag: item.seriesPrimaryImageTag, maxWidth: 800)
        }

        return requests
    }

    // MARK: - Media sources

    static func mediaSource(of record: DownloadRecord) -> MediaSourceInfo? {
        let sources = record.item.mediaSources ?? []
        return sources.first { $0.id == record.mediaSourceID } ?? sources.first
    }

    static func fileExtension(for source: MediaSourceInfo?) -> String {
        if let pathExtension = source?.path.flatMap({ URL(fileURLWithPath: $0).pathExtension.nilIfBlank }),
           pathExtension.count <= 5 {
            return pathExtension.lowercased()
        }

        // A container can be a list such as "mov,mp4,m4a"
        if let container = source?.container?.split(separator: ",").first.map(String.init), container.isNotEmpty {
            return container == "matroska" ? "mkv" : container.lowercased()
        }

        return "mp4"
    }

    /// Describes the file a transcode produces: one video and one audio stream, no subtitles
    static func transcodedSource(from source: MediaSourceInfo, quality: DownloadQuality) -> MediaSourceInfo {
        guard let target = TranscodeTarget(quality: quality) else { return source }

        var source = source
        let streams = source.mediaStreams ?? []

        var kept: [MediaStream] = []

        if var video = streams.first(where: { $0.type == .video }) {
            if let maxSize = target.maxSize, let width = video.width, let height = video.height, width > 0, height > 0 {
                let scale = min(1, Double(maxSize.width) / Double(width), Double(maxSize.height) / Double(height))
                video.width = Int(Double(width) * scale)
                video.height = Int(Double(height) * scale)
            }

            video.codec = "h264"
            video.bitRate = target.videoBitrate
            video.bitDepth = 8
            video.isAVC = true
            video.profile = nil
            video.level = nil
            video.codecTag = nil
            video.pixelFormat = nil
            video.videoRange = .sdr
            video.videoRangeType = .sdr
            video.videoDoViTitle = nil
            video.dvProfile = nil
            video.displayTitle = video.height.map { "\($0)p H264 SDR" } ?? "H264 SDR"
            kept.append(video)
        }

        if var audio = streams.first(where: { $0.type == .audio }) {
            audio.codec = "aac"
            audio.bitRate = target.audioBitrate
            audio.channels = min(audio.channels ?? 2, 2)
            audio.channelLayout = audio.channels == 1 ? "mono" : "stereo"
            audio.profile = nil
            audio.audioSpatialFormat = nil
            audio.isDefault = true
            audio.displayTitle = [audio.language?.uppercased(), "AAC", audio.channels == 1 ? "Mono" : "Stereo"]
                .compactMap { $0 }
                .joined(separator: " - ")
            source.defaultAudioStreamIndex = audio.index
            kept.append(audio)
        }

        source.mediaStreams = kept
        source.mediaAttachments = nil
        source.defaultSubtitleStreamIndex = nil
        source.container = transcodeContainer
        source.bitrate = target.videoBitrate + target.audioBitrate
        source.size = nil
        source.path = nil
        source.eTag = nil

        return source
    }

    struct TranscodeTarget {

        let videoBitrate: Int
        let audioBitrate: Int
        let maxSize: (width: Int, height: Int)?

        init?(quality: DownloadQuality) {
            guard let bitrate = quality.bitrate else { return nil }

            audioBitrate = bitrate >= 4_000_000 ? 192_000 : 128_000
            videoBitrate = max(bitrate - audioBitrate, 200_000)

            maxSize = switch bitrate {
            case 15_000_000...:
                nil
            case 5_000_000...:
                (1920, 1080)
            case 2_000_000...:
                (1280, 720)
            default:
                (854, 480)
            }
        }
    }
}

#endif
