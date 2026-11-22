//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS) || os(macOS)

import Defaults
import FactoryKit
import JellyfinAPI
import SwiftUI

extension Defaults.Keys {

    /// The bitrate of the last chosen download quality, `nil` for the original file
    static let downloadQualityBitrate: Key<Int?> = Key("downloadQualityBitrate", suite: .appSuite)
}

extension ItemActionButtons {

    struct Download: View {

        enum Status: Equatable {

            case none
            case queued
            case downloading(progress: Double?)
            case paused
            case failed(message: String?)
            case completed
        }

        @AdaptiveLayout
        private var viewLayout

        @Default(.downloadQualityBitrate)
        private var lastQualityBitrate

        @EnvironmentObject
        private var provider: ItemContentGroupProvider

        @InjectedObject(\.downloadManager)
        private var downloadManager

        @ViewContextContains(.isInMenu)
        private var isInMenu

        private var item: BaseItemDto {
            provider.item
        }

        private var isContainer: Bool {
            DownloadManager.canDownloadChildren(of: item)
        }

        private var records: [DownloadRecord] {
            Self.records(for: item, in: downloadManager)
        }

        /// The item's own record, or those of its episodes for a series or season
        static func records(for item: BaseItemDto, in downloadManager: DownloadManager) -> [DownloadRecord] {
            guard let itemID = item.id,
                  let userSession = Container.shared.currentUserSession()
            else { return [] }

            let records = downloadManager.records(for: userSession)

            guard DownloadManager.canDownloadChildren(of: item) else {
                return records.filter { $0.id == itemID }
            }

            return records.filter { record in
                record.item.seriesID == itemID ||
                    record.item.seasonID == itemID ||
                    record.series?.id == itemID ||
                    record.season?.id == itemID
            }
        }

        static func status(of records: [DownloadRecord]) -> Status {
            guard records.isNotEmpty else { return .none }

            let inFlight = records.filter(\.isInFlight)

            if inFlight.isNotEmpty {
                if records.count == 1, records[0].state == .queued {
                    return .queued
                }

                let isProgressKnown = records.contains { $0.displayProgress != nil || $0.state == .completed }
                let progress = records.reduce(0) { $0 + $1.progress } / Double(records.count)

                return .downloading(progress: isProgressKnown ? progress : nil)
            }

            if records.contains(where: { $0.state == .paused }) {
                return .paused
            }

            if let failed = records.first(where: { $0.state == .failed }) {
                return .failed(message: failed.errorMessage)
            }

            return .completed
        }

        private func title(for status: Status) -> String {
            switch status {
            case .none:
                ItemActionButton.download.displayTitle
            case .queued:
                "Download Queued"
            case let .downloading(progress):
                if let progress {
                    "Downloading \(progress.formatted(.percent.precision(.fractionLength(0))))"
                } else {
                    "Downloading"
                }
            case .paused:
                "Download Paused"
            case .failed:
                "Download Failed"
            case .completed:
                "Downloaded"
            }
        }

        private func systemImage(for status: Status) -> String {
            switch status {
            case .none:
                ItemActionButton.download.systemImage
            case .queued, .downloading:
                "arrow.down.circle.dotted"
            case .paused:
                "pause.circle"
            case .failed:
                "exclamationmark.circle"
            case .completed:
                "checkmark.circle.fill"
            }
        }

        private func start(_ quality: DownloadQuality) {
            guard let userSession = Container.shared.currentUserSession() else { return }

            lastQualityBitrate = quality.bitrate

            if isContainer {
                Task {
                    do {
                        try await downloadManager.downloadChildren(of: item, quality: quality, userSession: userSession)
                    } catch {
                        provider.actionError = error
                    }
                }
            } else {
                downloadManager.download(item, quality: quality, userSession: userSession)
            }
        }

        // MARK: - Label

        /// A progress ring drawn into an `Image`, as menu labels
        /// only render text and images on some platforms.
        private func progressImage(_ progress: Double) -> Image {
            let size: CGFloat = 24
            let lineWidth: CGFloat = 2.5

            return Image(size: CGSize(width: size, height: size)) { context in
                let rect = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: lineWidth, dy: lineWidth)

                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(.gray.opacity(0.5)),
                    lineWidth: lineWidth
                )

                var arc = Path()
                arc.addArc(
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: rect.width / 2,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * max(0.02, min(1, progress))),
                    clockwise: false
                )

                context.stroke(
                    arc,
                    with: .foreground,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

                let stop = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.36, dy: size * 0.36)

                context.fill(
                    Path(roundedRect: stop, cornerRadius: 1.5),
                    with: .foreground
                )
            }
        }

        @ContentBuilder
        private func label(for status: Status) -> some View {
            // Menus only show the title and a symbol, so the progress is in the title there
            if !isInMenu, case let .downloading(progress?) = status {
                Label {
                    Text(title(for: status))
                } icon: {
                    progressImage(progress)
                }
            } else {
                Label(title(for: status), systemImage: systemImage(for: status))
            }
        }

        // MARK: - Menu

        @ContentBuilder
        private var qualityButtons: some View {
            ForEach(DownloadQuality.allOptions) { quality in
                Button {
                    start(quality)
                } label: {
                    if quality.bitrate == lastQualityBitrate {
                        Label(quality.displayTitle, systemImage: "checkmark")
                    } else {
                        Text(quality.displayTitle)
                    }
                }
            }
        }

        @ContentBuilder
        private func transferButtons(for records: [DownloadRecord]) -> some View {
            let pausable = records.filter { $0.isInFlight && $0.supportsPause }
            let paused = records.filter { $0.state == .paused }
            let failed = records.filter { $0.state == .failed }

            if pausable.isNotEmpty {
                Button(L10n.pause, systemImage: "pause.fill") {
                    pausable.forEach { downloadManager.pause($0.id) }
                }
            }

            if paused.isNotEmpty {
                Button(L10n.resume, systemImage: "arrow.down.circle") {
                    paused.forEach { downloadManager.resume($0.id) }
                }
            }

            if failed.isNotEmpty {
                Section {
                    Button(L10n.retry, systemImage: "arrow.clockwise") {
                        failed.forEach { downloadManager.resume($0.id) }
                    }
                } header: {
                    Text(failed.first?.errorMessage ?? L10n.taskFailed)
                }
            }
        }

        @ContentBuilder
        private func menuContent(status: Status, records: [DownloadRecord]) -> some View {
            if status == .none {
                Section(L10n.quality) {
                    qualityButtons
                }
            } else {
                transferButtons(for: records)

                if isContainer {
                    Menu("Download Episodes", systemImage: ItemActionButton.download.systemImage) {
                        qualityButtons
                    }
                }

                Divider()

                // Hosted by `ItemView`, as this view goes away with the menu
                Button(
                    removalTitle(status: status, count: records.count),
                    systemImage: status == .completed ? "trash" : "xmark.circle",
                    role: .destructive
                ) {
                    provider.isPresentingDownloadRemovalConfirmation = true
                }
            }
        }

        private func removalTitle(status: Status, count: Int) -> String {
            switch status {
            case .queued, .downloading, .paused:
                count > 1 ? "Cancel Downloads" : "Cancel Download"
            default:
                count > 1 ? "Remove Downloads" : "Remove Download"
            }
        }

        @ContentBuilder
        var body: some View {
            let records = records
            let status = Self.status(of: records)

            Menu {
                menuContent(status: status, records: records)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary)
            } label: {
                label(for: status)
            }
            .if(!isInMenu && viewLayout.isLarge) { menu in
                menu.menuStyle(.button)
            }
            .isSelected(status == .completed)
        }
    }
}

// MARK: - Removal Confirmation

private struct DownloadRemovalConfirmationModifier: ViewModifier {

    @ObservedObject
    var provider: ItemContentGroupProvider

    @ContentBuilder
    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Remove Download",
                isPresented: $provider.isPresentingDownloadRemovalConfirmation,
                titleVisibility: .visible
            ) {
                Button(L10n.confirm, role: .destructive) {
                    let downloadManager = Container.shared.downloadManager()

                    ItemActionButtons.Download
                        .records(for: provider.item, in: downloadManager)
                        .forEach { downloadManager.delete($0.id) }
                }

                Button(L10n.cancel, role: .cancel) {}
            } message: {
                Text("\(provider.item.displayTitle) will be removed from this device.")
            }
    }
}

extension View {

    @ContentBuilder
    func downloadRemovalConfirmation(provider: ItemContentGroupProvider) -> some View {
        modifier(DownloadRemovalConfirmationModifier(provider: provider))
    }
}

#endif
