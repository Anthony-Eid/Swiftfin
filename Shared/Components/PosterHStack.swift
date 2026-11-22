//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
import SwiftUI

struct PosterHStack<
    Data: Collection
>: View where Data.Element: Poster, Data.Index == Int {

    @AdaptiveLayout
    private var viewLayout

    let elements: Data
    let displayType: PosterDisplayType
    let size: PosterDisplayType.Size
    let action: (Data.Element, Namespace.ID) -> Void

    private var layout: CollectionHStackLayout {
        #if os(tvOS)
        .grid(
            columns: displayType == .landscape ? 5 : 7,
            rows: 1,
            columnTrailingInset: 0
        )
        #elseif os(macOS)
        // Desktop density: a fixed tile width lets the visible column count
        // follow the window width instead of a hard-coded phone count.
        let columnWidth: CGFloat = {
            switch (displayType, size) {
            case (.landscape, .small):
                240
            case (.landscape, .medium):
                320
            case (_, .small):
                160
            default:
                200
            }
        }()

        return .minimumWidth(
            columnWidth: columnWidth,
            rows: 1
        )
        #else
        .minimumWidth(
            columnWidth: viewLayout.posterMinimumWidth(for: displayType, size: size),
            rows: 1,
            columnFraction: 0.5
        )
        #endif
    }

    @ContentBuilder
    var body: some View {
        CollectionHStack(
            uniqueElements: elements,
            layout: layout
        ) { item in
            PosterButton(
                item: item,
                displayType: displayType,
                size: size
            ) { namespace in
                action(item, namespace)
            }
        }
        .clipsToBounds(false)
        .insets(horizontal: viewLayout.edgePadding)
        .itemSpacing(viewLayout.itemSpacing)
        .scrollBehavior(.continuousLeadingEdge)
        .contentInsetAdjustmentBehavior(.never)
        .withViewContext(.isThumb)
    }
}
