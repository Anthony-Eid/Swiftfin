//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

#if os(macOS)
/// There is no hosting controller to configure on macOS. Key commands are the
/// only preference with an equivalent, and are served by the enclosing window.
struct PreferencesView<Content: View>: View {

    private let content: Content

    init(@ContentBuilder content: () -> Content) {
        self.content = content()
    }

    @ContentBuilder
    var body: some View {
        content
            .modifier(KeyCommandsResponder())
    }
}
#else
struct PreferencesView<Content: View>: UIViewControllerRepresentable {

    private let content: Content

    init(@ContentBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIViewController(context: Context) -> UIPreferencesHostingController {
        UIPreferencesHostingController {
            HostingEnvironmentView(content: content, environment: context.environment)
        }
    }

    func updateUIViewController(_ uiViewController: UIPreferencesHostingController, context: Context) {
        uiViewController.setContent {
            HostingEnvironmentView(content: content, environment: context.environment)
        }
    }
}
#endif
