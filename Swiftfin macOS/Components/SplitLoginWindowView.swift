//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct SplitLoginWindowView<Leading: View, Trailing: View>: View {

    private let isLoading: Bool
    private let leadingContentView: Leading
    private let trailingContentView: Trailing
    private let backgroundImageSource: ImageSource?

    init(
        isLoading: Bool = false,
        backgroundImageSource: ImageSource? = nil,
        @ViewBuilder leadingContentView: @escaping () -> Leading,
        @ViewBuilder trailingContentView: @escaping () -> Trailing
    ) {
        self.isLoading = isLoading
        self.backgroundImageSource = backgroundImageSource
        self.leadingContentView = leadingContentView()
        self.trailingContentView = trailingContentView()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            Form {
                leadingContentView
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            Form {
                trailingContentView
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 800, height: 500)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if isLoading {
                    ProgressView()
                }
            }
        }
        .background {
            if let backgroundImageSource {
                ZStack {
                    ImageView(backgroundImageSource)
                        .aspectRatio(contentMode: .fill)
                        .id(backgroundImageSource)
                        .transition(.opacity)
                        .animation(.linear, value: backgroundImageSource)

                    Color.black.opacity(0.9)
                }
                .ignoresSafeArea()
            }
        }
    }
}
