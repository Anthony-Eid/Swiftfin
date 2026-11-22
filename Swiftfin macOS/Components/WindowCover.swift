//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Presents a route over the whole content of a window.
///
/// AppKit has no full screen cover, and a sheet or a push would leave the
/// tab view chrome around the route. The cover is hosted by `windowCoverHost()`.
@MainActor
final class WindowCoverPresenter: ObservableObject {

    @Published
    fileprivate var presented: NavigationCoordinator.PresentedRoute?

    func present(_ presentedRoute: NavigationCoordinator.PresentedRoute) {
        // The route is the only element of the cover's navigation stack so
        // that the environment's dismiss action pops it, which removes the cover.
        presentedRoute.coordinator.path = [
            NavigationRoute(id: presentedRoute.route.id) {
                presentedRoute.route
                    .destination
                    .navigationBarBackButtonHidden()
                    .toolbar(.hidden, for: .windowToolbar)
            },
        ]

        presented = presentedRoute
    }
}

extension EnvironmentValues {

    @Entry
    var windowCoverPresenter: WindowCoverPresenter? = nil
}

extension View {

    /// Hosts the routes presented through the environment's `WindowCoverPresenter`.
    func windowCoverHost() -> some View {
        modifier(WindowCoverHostModifier())
    }

    /// Presents `item` with the environment's `WindowCoverPresenter`.
    ///
    /// - Parameter fallback: Called if there is no host to present the route.
    func windowCover(
        item: Binding<NavigationCoordinator.PresentedRoute?>,
        fallback: @escaping (NavigationRoute) -> Void
    ) -> some View {
        modifier(WindowCoverPresentationModifier(item: item, fallback: fallback))
    }
}

private struct WindowCoverPresentationModifier: ViewModifier {

    @Environment(\.windowCoverPresenter)
    private var presenter

    @Binding
    var item: NavigationCoordinator.PresentedRoute?

    let fallback: (NavigationRoute) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: item?.id) {
                guard let item else { return }
                self.item = nil

                if let presenter {
                    presenter.present(item)
                } else {
                    fallback(item.route)
                }
            }
    }
}

private struct WindowCoverHostModifier: ViewModifier {

    @StateObject
    private var presenter = WindowCoverPresenter()

    private var isPresented: Bool {
        presenter.presented != nil
    }

    func body(content: Content) -> some View {
        ZStack {
            content
                .accessibilityHidden(isPresented)

            if let presented = presenter.presented {
                WindowCover(coordinator: presented.coordinator) {
                    presenter.presented = nil
                }
                .id(ObjectIdentifier(presented.coordinator))
                .transition(.opacity)
            }
        }
        .toolbar(isPresented ? .hidden : .automatic, for: .windowToolbar)
        .animation(.easeInOut(duration: 0.2), value: isPresented)
        .environment(\.windowCoverPresenter, presenter)
    }
}

private struct WindowCover: View {

    @ObservedObject
    var coordinator: NavigationCoordinator

    let onDismiss: () -> Void

    var body: some View {
        NavigationInjectionView(coordinator: coordinator) {
            Color.black
                .ignoresSafeArea()
                .toolbar(.hidden, for: .windowToolbar)
        }
        .background(.black)
        .onChange(of: coordinator.path.isEmpty) { _, isEmpty in
            if isEmpty {
                onDismiss()
            }
        }
    }
}
