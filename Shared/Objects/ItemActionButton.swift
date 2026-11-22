//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

enum ItemActionButton: String, CaseIterable, Displayable, Equatable, Identifiable, Storable, SystemImageable {

    case played
    case favorited
    case trailers
    case playback
    case shuffle
    case record
    case subtitles
    case refresh
    case delete
    #if os(iOS) || os(macOS)
    case editMetadata
    case download
    #endif

    var displayTitle: String {
        switch self {
        case .played:
            L10n.played
        case .favorited:
            L10n.favorited
        case .trailers:
            L10n.trailers
        case .playback:
            L10n.playback
        case .shuffle:
            L10n.shuffle
        case .record:
            L10n.record
        case .refresh:
            L10n.refreshMetadata
        case .subtitles:
            L10n.subtitles
        case .delete:
            L10n.delete
        #if os(iOS) || os(macOS)
        case .editMetadata:
            L10n.edit
        case .download:
            L10n.download
        #endif
        }
    }

    var id: String {
        rawValue
    }

    var systemImage: String {
        switch self {
        case .played:
            "checkmark"
        case .favorited:
            "heart.fill"
        case .trailers:
            "movieclapper"
        case .playback:
            "list.and.film"
        case .shuffle:
            "shuffle"
        case .record:
            "record.circle.fill"
        case .refresh:
            "arrow.clockwise"
        case .subtitles:
            "captions.bubble"
        case .delete:
            "trash"
        #if os(iOS) || os(macOS)
        case .editMetadata:
            "pencil"
        case .download:
            "arrow.down.circle"
        #endif
        }
    }

    var secondarySystemImage: String {
        switch self {
        case .favorited:
            "heart"
        case .record:
            "record.circle"
        default:
            systemImage
        }
    }

    var activeColor: Color? {
        switch self {
        case .played:
            .jellyfinPurple
        case .favorited:
            .pink
        case .record:
            .red
        #if os(iOS) || os(macOS)
        case .download:
            .green
        #endif
        default:
            nil
        }
    }

    static let defaultBarActionButtons: [ItemActionButton] = {
        var buttons: [ItemActionButton] = [
            .played,
            .favorited,
            .shuffle,
            .record,
            .trailers,
            .playback
        ]

        // Early enough to stay within `ItemActionButtons.maximumButtons`
        #if os(iOS) || os(macOS)
        buttons.insert(.download, at: 2)
        #endif

        return buttons
    }()

    static let defaultMenuActionButtons: [ItemActionButton] = [
        .refresh,
        .subtitles,
        .delete
    ]
        #if os(iOS) || os(macOS)
            .prepending(.editMetadata)
        #endif
}
