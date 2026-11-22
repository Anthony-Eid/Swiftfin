//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftUI

enum AppStartupError: Error {

    case dataStack(Error)
}

@MainActor
@Stateful
final class RootCoordinator: ObservableObject {

    @CasePathable
    enum Action {

        case start

        var transition: Transition {
            switch self {
            case .start:
                .to(.ready)
            }
        }
    }

    enum State {

        case initial
        case error
        case ready
    }

    private var started = false

    #if os(macOS)
    /// Every window has its own coordinator, while the data stack is set up once.
    private static var dataStackSetup: Task<Void, Error>?
    #endif

    @Function(\Action.Cases.start)
    private func _start() async throws {
        guard !started else { return }

        started = true

        do {
            #if os(macOS)
            let setup = Self.dataStackSetup ?? Task {
                try await SwiftfinStore.setupDataStack()
            }
            Self.dataStackSetup = setup
            try await setup.value
            #else
            try await SwiftfinStore.setupDataStack()
            #endif
        } catch {
            throw AppStartupError.dataStack(error)
        }
    }
}
