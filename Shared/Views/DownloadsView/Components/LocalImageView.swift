//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS) || os(macOS)

import SwiftUI

/// An image read from a local file, without the image pipeline or the network.
struct LocalImageView: View {

    @State
    private var image: UIImage?

    private let reloadID: String
    private let url: URL?

    /// - Parameter reloadID: changes when the file at `url` may have been written
    init(url: URL?, reloadID: String = "") {
        self.url = url
        self.reloadID = "\(url?.path ?? "")-\(reloadID)"
    }

    private static func load(_ url: URL?) async -> UIImage? {
        guard let url else { return nil }

        return await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path)
        }.value
    }

    @ContentBuilder
    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .task(id: reloadID) {
            image = await Self.load(url)
        }
    }
}

#endif
