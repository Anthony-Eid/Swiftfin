//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS) || os(macOS)

import JellyfinAPI
import SwiftUI

extension DownloadsView {

    struct Row: View {

        let record: DownloadRecord
        let imageURL: URL?
        let canPlay: Bool
        let onSelect: () -> Void
        let onPlay: () -> Void
        let onPause: () -> Void
        let onResume: () -> Void
        let onDelete: () -> Void

        private var posterType: PosterDisplayType {
            record.isEpisode ? .landscape : .portrait
        }

        private var title: String {
            record.item.displayTitle
        }

        private var tint: Color {
            record.state == .failed ? .red : .secondary
        }

        @ContentBuilder
        private var poster: some View {
            ZStack {
                Color.secondarySystemFill

                SystemImageContentView(systemName: record.item.systemImage)

                LocalImageView(url: imageURL, reloadID: record.state.rawValue)
            }
            .posterStyle(posterType)
            .frame(width: posterType == .landscape ? 106 : 60)
        }

        @ContentBuilder
        private var status: some View {
            if record.state == .completed {
                if let resumePosition = record.resumePosition {
                    Label("Resume at \(resumePosition.formatted(.runtime))", systemImage: "play.circle")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                }
            } else {
                if record.state != .failed {
                    if let progress = record.displayProgress {
                        ProgressView(value: progress)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                }

                if let statusLabel = record.statusLabel {
                    Text(statusLabel)
                        .foregroundStyle(tint)
                        .lineLimit(2)
                }
            }
        }

        @ContentBuilder
        private var transferButtons: some View {
            switch record.state {
            case .completed:
                if canPlay {
                    Button(L10n.play, systemImage: "play.fill", action: onPlay)
                }
            case .queued, .downloading:
                if record.supportsPause {
                    Button(L10n.pause, systemImage: "pause.fill", action: onPause)
                }
            case .paused:
                Button(L10n.resume, systemImage: "arrow.down.circle", action: onResume)
            case .failed:
                Button(L10n.retry, systemImage: "arrow.clockwise", action: onResume)
            }
        }

        @ContentBuilder
        private var deleteButton: some View {
            Button(
                record.isInFlight || record.state == .paused ? "Cancel Download" : "Remove Download",
                systemImage: record.state == .completed || record.state == .failed ? "trash" : "xmark.circle",
                role: .destructive,
                action: onDelete
            )
        }

        @ContentBuilder
        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                Button(action: onSelect) {
                    HStack(alignment: .center, spacing: 12) {
                        poster

                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.headline)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Text(record.detailLabels.joined(separator: " \u{2022} "))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            status
                        }
                        .font(.subheadline)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 16) {
                    transferButtons

                    deleteButton
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .font(.title3)
            }
            .contextMenu {
                transferButtons

                Button(L10n.details, systemImage: "info.circle", action: onSelect)

                Divider()

                deleteButton
            }
            .accessibilityElement(children: .contain)
        }
    }
}

#endif
