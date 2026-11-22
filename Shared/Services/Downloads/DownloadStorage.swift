//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if !os(tvOS)

import Foundation
import Logging

/// The files of every download: one directory per item with its record, media and images.
struct DownloadStorage: Sendable {

    static let recordFileName = "record.json"
    static let incomingFileName = "incoming.download"

    let root: URL

    init() {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        root = applicationSupport
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Swiftfin", isDirectory: true)
            .appendingPathComponent("Downloads", isDirectory: true)
    }

    func directory(for itemID: String) -> URL {
        // Item IDs come from the server, so keep them from escaping the root
        let name = itemID.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: "_")
        return root.appendingPathComponent(name, isDirectory: true)
    }

    func file(_ name: String, for itemID: String) -> URL {
        directory(for: itemID).appendingPathComponent(name, isDirectory: false)
    }

    func loadRecords() -> [DownloadRecord] {
        let logger = Logger.swiftfin()
        let directories = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        let decoder = JSONDecoder()

        return directories
            .compactMap { directory -> DownloadRecord? in
                let file = directory.appendingPathComponent(Self.recordFileName)
                guard let data = try? Data(contentsOf: file) else { return nil }

                do {
                    return try decoder.decode(DownloadRecord.self, from: data)
                } catch {
                    logger.error("Skipping unreadable download record at \(directory.lastPathComponent): \(error.localizedDescription)")
                    return nil
                }
            }
            .sorted { $0.dateCreated < $1.dateCreated }
    }

    func save(_ record: DownloadRecord) throws {
        let directory = directory(for: record.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try JSONEncoder().encode(record)
        try data.write(to: directory.appendingPathComponent(Self.recordFileName), options: .atomic)
    }

    func remove(_ itemID: String) {
        try? FileManager.default.removeItem(at: directory(for: itemID))
    }

    func size(of url: URL) -> Int64 {
        let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        return size?.int64Value ?? 0
    }

    /// Downloaded media can be fetched again, so keep it out of device backups
    func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}

#endif
