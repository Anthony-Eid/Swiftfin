//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if !os(tvOS)

import FactoryKit
import Foundation
import JellyfinAPI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Builds a playable item from a finished download without asking the server for anything.
@MainActor
enum DownloadedMediaPlayerItemResolver {

    /// Returns `nil` when the intent has to be resolved by the server
    static func resolve(
        _ intent: PlaybackIntent,
        for profile: PlaybackProfile,
        userSession: UserSession
    ) throws -> MediaPlayerItem? {
        // Only a local player can open a file
        guard !profile.requiresHLS, let itemID = intent.item.id else { return nil }

        let downloadManager = Container.shared.downloadManager()

        guard let record = downloadManager.record(for: itemID),
              record.serverID == userSession.server.id,
              record.userID == userSession.user.id,
              let url = downloadManager.mediaURL(for: record),
              var mediaSource = DownloadRequestBuilder.mediaSource(of: record) else { return nil }

        var configuration = intent.configuration

        // Another version of the item was asked for than the downloaded one
        if let requestedSource = intent.mediaSource?.id,
           configuration.mediaSourceID != nil,
           requestedSource != mediaSource.id {
            return nil
        }

        try Task.checkCancellation()

        // Sidecar files are not downloaded, only the tracks inside the file exist
        mediaSource.mediaStreams = mediaSource.mediaStreams?
            .filter { $0.isExternal != true }
            .map { stream in
                var stream = stream
                stream.deliveryURL = nil
                stream.deliveryMethod = stream.type == .subtitle ? .embed : nil
                return stream
            }
        mediaSource.transcodingURL = nil
        mediaSource.liveStreamID = nil
        mediaSource.isSupportsDirectPlay = true

        let streams = mediaSource.mediaStreams ?? []

        if let defaultSubtitle = mediaSource.defaultSubtitleStreamIndex,
           !streams.contains(where: { $0.type == .subtitle && $0.index == defaultSubtitle }) {
            mediaSource.defaultSubtitleStreamIndex = nil
        }

        if let audio = configuration.audioStreamIndex,
           !streams.contains(where: { $0.type == .audio && $0.index == audio }),
           let fallback = streams.first(where: { $0.type == .audio })?.index {
            configuration.selectTracks(audio: fallback, preservingPreferences: true)
        }

        if let subtitle = configuration.subtitleStreamIndex,
           subtitle >= 0,
           !streams.contains(where: { $0.type == .subtitle && $0.index == subtitle }) {
            configuration.selectTracks(subtitle: -1, preservingPreferences: true)
        }

        var item = record.item
        item.mediaSources = [mediaSource]
        item.runTimeTicks = mediaSource.runTimeTicks ?? item.runTimeTicks
        item.userData = resumeUserData(record: record, shared: intent.entry.value?.userData)

        configuration.prepare(for: item, source: mediaSource, profile: profile)

        let deviceProfile = profile.deviceProfile(
            configuration: configuration,
            maxBitrate: Int(Int32.max),
            mediaSource: mediaSource
        )

        configuration.finish(source: mediaSource, initialSource: mediaSource)

        let client = userSession.client
        // Chapter and trickplay images stay on the server and are loaded lazily when it is reachable
        let chapters = item.fullChapterInfo(using: client)
        let temporaryFiles = PlaybackTemporaryFiles(accessToken: client.accessToken)

        let previewImageProvider = PreviewImageProvider(
            option: configuration.previewImageScrubbing,
            item: item,
            mediaSourceID: mediaSource.id,
            chapters: chapters,
            client: client,
            resolveImage: temporaryFiles.image(for:)
        )

        let artwork = downloadManager.imageURL(.primary, for: record) ?? downloadManager.imageURL(.backdrop, for: record)

        return MediaPlayerItem(
            baseItem: item,
            mediaSource: mediaSource,
            playSessionID: "local-\(UUID().uuidString)",
            url: url,
            configuration: configuration,
            deviceProfile: deviceProfile,
            chapters: chapters,
            temporaryFiles: temporaryFiles,
            previewImageProvider: previewImageProvider,
            thumbnailProvider: {
                if let artwork, let image = UIImage(contentsOfFile: artwork.path) {
                    return image
                }

                return await item.getNowPlayingImage()
            }
        )
    }

    /// The newer of the position recorded with the download and the one the app last got from the server
    private static func resumeUserData(record: DownloadRecord, shared: UserItemDataDto?) -> UserItemDataDto? {
        let local = record.item.userData

        guard let shared else { return local }
        guard let local, !record.needsProgressSync else { return local ?? shared }

        return (shared.lastPlayedDate ?? .distantPast) > (local.lastPlayedDate ?? .distantPast) ? shared : local
    }
}

#endif
