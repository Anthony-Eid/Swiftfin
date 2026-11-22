//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension NavigationCoordinator {

    @MainActor
    struct Router {

        let navigationCoordinator: NavigationCoordinator?
        let isRootOfPath: Bool

        func route(
            to route: NavigationRoute,
            transition: NavigationRoute.TransitionType? = nil,
            in namespace: Namespace.ID? = nil
        ) {
            var route = route
            route.namespace = namespace
            route.transitionType = transition ?? route.transitionType
            navigationCoordinator?.push(route)
        }
    }
}

@propertyWrapper
struct Router: DynamicProperty {

    @MainActor
    struct Wrapper {

        let router: NavigationCoordinator.Router
        #if os(macOS)
        let dismiss: DismissRouteAction
        #else
        let dismiss: DismissAction
        #endif

        var isRootOfPath: Bool {
            router.isRootOfPath
        }

        func route(
            to route: NavigationRoute,
            in namespace: Namespace.ID? = nil
        ) {
            router.route(
                to: route,
                transition: nil,
                in: namespace
            )
        }

        func route(
            to route: NavigationRoute,
            style: NavigationRoute.TransitionStyle,
            in namespace: Namespace.ID? = nil
        ) {
            router.route(
                to: route,
                transition: .automatic(style),
                in: namespace
            )
        }

        func route(
            to route: NavigationRoute,
            withNamespace: @escaping (Namespace.ID) -> NavigationRoute.TransitionStyle,
            in namespace: Namespace.ID? = nil
        ) {
            router.route(
                to: route,
                transition: .withNamespace(withNamespace),
                in: namespace
            )
        }
    }

    /// `.dismiss` causes changes on disappear
    @Environment(\.self)
    private var environment

    private let wrapperBox: PublishedBox<Wrapper?> = .init(initialValue: nil)

    var wrappedValue: Wrapper {
        if let wrapper = wrapperBox.value {
            return wrapper
        }

        #if os(macOS)
        let value = Wrapper(
            router: environment.router,
            dismiss: .init(
                dismiss: environment.dismiss,
                dismissPresentation: environment.router.isRootOfPath ? environment.dismissPresentation : nil
            )
        )
        #else
        let value = Wrapper(
            router: environment.router,
            dismiss: environment.dismiss
        )
        #endif
        wrapperBox.value = value
        return value
    }
}

extension EnvironmentValues {

    @Entry
    var router: NavigationCoordinator.Router = .init(
        navigationCoordinator: nil,
        isRootOfPath: false
    )
}

#if os(macOS)

/// On macOS, `DismissAction` at the root of a `NavigationStack`
/// does not close the sheet that hosts the stack, so the root
/// of a presented stack closes its presentation directly.
@MainActor
struct DismissRouteAction {

    let dismiss: DismissAction
    let dismissPresentation: (() -> Void)?

    func callAsFunction() {
        if let dismissPresentation {
            dismissPresentation()
        } else {
            dismiss()
        }
    }
}

extension EnvironmentValues {

    @Entry
    var dismissPresentation: (() -> Void)? = nil
}
#endif
