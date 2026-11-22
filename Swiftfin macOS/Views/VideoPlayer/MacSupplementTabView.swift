//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Supplements are selected from their tabs with the pointer, so there is no pager to swipe.
struct SupplementTabView<Content: View>: View {

    let data: [any VideoPlayerSupplement]
    let selection: Binding<String?>

    @ContentBuilder
    let content: (any VideoPlayerSupplement) -> Content

    @State
    private var presentedID: String?

    private var presented: (any VideoPlayerSupplement)? {
        data.first { $0.id == presentedID }
    }

    @ContentBuilder
    var body: some View {
        ZStack {
            // The last selection stays mounted while its panel slides away.
            if let presented {
                content(presented)
                    .id(presented.id)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: selection.wrappedValue, initial: true) { _, newValue in
            if let newValue {
                presentedID = newValue
            }
        }
    }
}
