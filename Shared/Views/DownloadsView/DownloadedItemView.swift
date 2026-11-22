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

/// The details of a downloaded item, from its record and local files only.
struct DownloadedItemView: View {

    @InjectedObject(\.downloadManager)
    private var downloadManager

    @PlayMedia
    private var playMedia

    @Router
    private var router

    @State
    private var isPresentingDeleteConfirmation = false

    let recordID: String

    private var record: DownloadRecord? {
        downloadManager.record(for: recordID)
    }

    private func mediaStreams(for record: DownloadRecord) -> [MediaStream] {
        let mediaSources = record.item.mediaSources ?? []
        let mediaSource = mediaSources.first { $0.id == record.mediaSourceID } ?? mediaSources.first

        return mediaSource?.mediaStreams ?? record.item.mediaStreams ?? []
    }

    @ContentBuilder
    private func streamSection(_ title: String, type: MediaStreamType, in streams: [MediaStream]) -> some View {
        let streams = streams.filter { $0.type == type }

        if streams.isNotEmpty {
            Section(title) {
                ForEach(Array(streams.enumerated()), id: \.offset) { _, stream in
                    Text(stream.displayTitle ?? L10n.unknown)
                }
            }
        }
    }

    @ContentBuilder
    private func backdrop(_ record: DownloadRecord) -> some View {
        let url = downloadManager.imageURL(.backdrop, for: record)
            ?? (record.isEpisode ? downloadManager.imageURL(.primary, for: record) : nil)

        if let url {
            Section {
                Color.secondarySystemFill
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        LocalImageView(url: url, reloadID: record.state.rawValue)
                    }
                    .clipped()
                    .listRowInsets(.zero)
            }
        }
    }

    @ContentBuilder
    private func contentView(_ record: DownloadRecord) -> some View {
        let streams = mediaStreams(for: record)

        Form(systemImage: "arrow.down.circle") {
            backdrop(record)

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.item.displayTitle)
                        .font(.title2)
                        .fontWeight(.semibold)

                    if record.isEpisode {
                        Text(
                            [record.seriesTitle, record.item.seasonEpisodeLabel]
                                .compacted()
                                .joined(separator: " \u{2022} ")
                        )
                        .foregroundStyle(.secondary)
                    } else if let year = record.item.productionYear {
                        Text(String(year))
                            .foregroundStyle(.secondary)
                    }
                }

                if record.state == .completed {
                    Button(
                        record.resumePosition == nil ? L10n.play : L10n.resume,
                        systemImage: "play.fill"
                    ) {
                        playMedia(intent: PlaybackIntent(item: record.item))
                    }
                }
            }

            if let overview = record.item.overview, overview.isNotEmpty {
                Section(L10n.overview) {
                    Text(overview)
                }
            }

            Section(L10n.details) {
                if let runtime = record.item.runTimeLabel {
                    LabeledContent(L10n.runtime, value: runtime)
                }

                if let resumePosition = record.resumePosition {
                    LabeledContent("Resume Position", value: resumePosition.formatted(.runtime))
                }

                LabeledContent(L10n.quality, value: record.quality.displayTitle)

                if let sizeLabel = record.sizeLabel {
                    LabeledContent(L10n.size, value: sizeLabel)
                }

                if let statusLabel = record.statusLabel {
                    LabeledContent(L10n.status, value: statusLabel)
                }
            }
            .monospacedDigit()

            streamSection(L10n.video, type: .video, in: streams)
            streamSection(L10n.audio, type: .audio, in: streams)
            streamSection(L10n.subtitles, type: .subtitle, in: streams)

            Section {
                Button(
                    record.state == .completed || record.state == .failed ? "Remove Download" : "Cancel Download",
                    systemImage: "trash",
                    role: .destructive
                ) {
                    isPresentingDeleteConfirmation = true
                }
            }
        }
    }

    @ContentBuilder
    var body: some View {
        ZStack {
            if let record {
                contentView(record)
            } else {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle"
                )
            }
        }
        .navigationTitle(record?.item.displayTitle ?? L10n.downloads)
        .toolbarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Remove Download",
            isPresented: $isPresentingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.delete, role: .destructive) {
                downloadManager.delete(recordID)
                router.dismiss()
            }

            Button(L10n.cancel, role: .cancel) {}
        }
    }
}

#endif
