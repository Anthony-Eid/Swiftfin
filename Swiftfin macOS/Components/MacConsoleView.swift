//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CoreData
import Pulse
import SwiftUI

/// PulseUI does not ship its `ConsoleView` for macOS.
struct MacConsoleView: View {

    let store: LoggerStore

    @FetchRequest
    private var messages: FetchedResults<LoggerMessageEntity>

    init(store: LoggerStore = .shared) {
        self.store = store

        let request = NSFetchRequest<LoggerMessageEntity>(entityName: "LoggerMessageEntity")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \LoggerMessageEntity.createdAt, ascending: false)
        ]
        request.predicate = NSPredicate(format: "task == nil")
        self._messages = FetchRequest(fetchRequest: request)
    }

    var body: some View {
        List {
            if messages.isEmpty {
                Text(L10n.none)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(messages, id: \.objectID) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.text)
                        // developer log console: a file:line:timestamp stamp is
                        // diagnostic output, not localizable prose
                        // swiftlint:disable:next hard_coded_display_string
                        Text("\(message.file):\(message.line) · \(message.formattedTimestamp)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .environment(\.managedObjectContext, store.viewContext)
        .navigationTitle(L10n.logs)
    }
}
