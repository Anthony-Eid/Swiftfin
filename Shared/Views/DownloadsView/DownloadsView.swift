//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS) || os(macOS)

import FactoryKit
import JellyfinAPI
import SwiftUI

/// Everything downloaded by the current user. Only reads the
/// download records and local files, so it works without the server.
struct DownloadsView: View {

    struct EpisodeGroup: Identifiable {

        let id: String
        let title: String
        let records: [DownloadRecord]
    }

    @InjectedObject(\.downloadManager)
    private var downloadManager

    @PlayMedia
    private var playMedia

    @Router
    private var router

    @State
    private var completedStorage: Int64 = 0
    @State
    private var recordPendingDeletion: DownloadRecord?

    private var records: [DownloadRecord] {
        guard let userSession = Container.shared.currentUserSession() else { return [] }

        return downloadManager.records(for: userSession)
    }

    private func movies(in records: [DownloadRecord]) -> [DownloadRecord] {
        records
            .filter { !$0.isEpisode }
            .sorted { lhs, rhs in
                lhs.item.displayTitle.localizedStandardCompare(rhs.item.displayTitle) == .orderedAscending
            }
    }

    /// Episodes by series then season, in index order
    private func episodeGroups(in records: [DownloadRecord]) -> [EpisodeGroup] {
        let episodes = records
            .filter(\.isEpisode)
            .sorted { lhs, rhs in
                let seriesOrder = lhs.seriesTitle.localizedStandardCompare(rhs.seriesTitle)

                if seriesOrder != .orderedSame {
                    return seriesOrder == .orderedAscending
                }

                let lhsIndex = (lhs.item.parentIndexNumber ?? .max, lhs.item.indexNumber ?? .max)
                let rhsIndex = (rhs.item.parentIndexNumber ?? .max, rhs.item.indexNumber ?? .max)

                return lhsIndex < rhsIndex
            }

        var groups: [EpisodeGroup] = []
        var current: (id: String, title: String, records: [DownloadRecord])?

        for episode in episodes {
            let seriesID = episode.item.seriesID ?? episode.series?.id ?? episode.seriesTitle
            let seasonID = episode.item.seasonID ?? episode.season?.id ?? "\(episode.item.parentIndexNumber ?? -1)"
            let id = "\(seriesID)-\(seasonID)"

            if current?.id == id {
                current?.records.append(episode)
            } else {
                if let current {
                    groups.append(EpisodeGroup(id: current.id, title: current.title, records: current.records))
                }

                let title = [episode.seriesTitle, episode.seasonTitle]
                    .compacted()
                    .joined(separator: " \u{2022} ")

                current = (id, title, [episode])
            }
        }

        if let current {
            groups.append(EpisodeGroup(id: current.id, title: current.title, records: current.records))
        }

        return groups
    }

    private func storageUsed(by records: [DownloadRecord]) -> Int64 {
        completedStorage + records
            .filter { $0.state != .completed }
            .reduce(0) { $0 + $1.bytesReceived }
    }

    private func imageURL(for record: DownloadRecord) -> URL? {
        if record.isEpisode {
            downloadManager.imageURL(.primary, for: record) ?? downloadManager.imageURL(.backdrop, for: record)
        } else {
            downloadManager.imageURL(.primary, for: record)
        }
    }

    @ContentBuilder
    private func row(_ record: DownloadRecord) -> some View {
        Row(
            record: record,
            imageURL: imageURL(for: record),
            canPlay: record.state == .completed,
            onSelect: {
                router.route(to: .downloadedItem(recordID: record.id))
            },
            onPlay: {
                playMedia(intent: PlaybackIntent(item: record.item))
            },
            onPause: {
                downloadManager.pause(record.id)
            },
            onResume: {
                downloadManager.resume(record.id)
            },
            onDelete: {
                recordPendingDeletion = record
            }
        )
    }

    @ContentBuilder
    private func contentView(_ records: [DownloadRecord]) -> some View {
        let movies = movies(in: records)
        let episodeGroups = episodeGroups(in: records)

        Form(systemImage: "arrow.down.circle") {
            Section {
                LabeledContent(
                    "Storage Used",
                    value: storageUsed(by: records).formatted(.byteCount(style: .file))
                )
                .monospacedDigit()

                LabeledContent(
                    L10n.downloads,
                    value: records.count.formatted()
                )
            }

            if movies.isNotEmpty {
                Section(L10n.movies) {
                    ForEach(movies, content: row)
                }
            }

            ForEach(episodeGroups) { group in
                Section(group.title) {
                    ForEach(group.records, content: row)
                }
            }
        }
    }

    @ContentBuilder
    var body: some View {
        let records = records

        ZStack {
            if records.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Movies and episodes that you download can be played here without a connection to the server.")
                )
            } else {
                contentView(records)
            }
        }
        .navigationTitle(L10n.downloads)
        // Only finished files are measured, and only when that set changes
        .task(id: records.filter { $0.state == .completed }.map(\.id)) {
            completedStorage = downloadManager.storageUsed(by: records.filter { $0.state == .completed })
        }
        .confirmationDialog(
            "Remove Download",
            isPresented: Binding(
                get: { recordPendingDeletion != nil },
                set: { if !$0 { recordPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: recordPendingDeletion
        ) { record in
            Button(
                record.state == .completed || record.state == .failed ? L10n.delete : "Cancel Download",
                role: .destructive
            ) {
                downloadManager.delete(record.id)
            }

            Button(L10n.cancel, role: .cancel) {}
        } message: { record in
            Text("\(record.item.displayTitle) will be removed from this device.")
        }
    }
}

#endif
