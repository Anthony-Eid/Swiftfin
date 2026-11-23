//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if !os(tvOS)

import Combine
import FactoryKit
import Foundation
import JellyfinAPI
import Logging
import Network

extension Container {

    var downloadManager: Factory<DownloadManager> {
        self { MainActor.assumeIsolated { DownloadManager() } }.singleton
    }
}

/// Owns the download queue and the downloaded items on disk.
@MainActor
final class DownloadManager: ObservableObject {

    private static let maxConcurrentDownloads = 2

    /// Every record on disk, for all servers and users, oldest first
    @Published
    private(set) var records: [DownloadRecord] = []

    let storage = DownloadStorage()
    let logger = Logger.swiftfin()

    private var transfer: DownloadTransferSession!
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var preparations: [String: Task<Void, Never>] = [:]
    /// Failed downloads to try again when the network is back
    private var networkFailures = Set<String>()
    private var endpoints: [String: DownloadRequestBuilder.Endpoint] = [:]
    private var parents: [String: BaseItemDto] = [:]
    private var hasReconciledTasks = false

    private let pathMonitor = NWPathMonitor()
    private var isPathSatisfied = true
    private var cancellables = Set<AnyCancellable>()
    var isSyncingProgress = false

    init() {
        records = storage.loadRecords()

        transfer = DownloadTransferSession(storage: storage) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
        }

        // Creating the session re-attaches to transfers that ran while the app was not
        transfer.session.getAllTasks { [weak self] tasks in
            let downloads = tasks.compactMap { $0 as? URLSessionDownloadTask }

            Task { @MainActor [weak self] in
                self?.attach(downloads)
            }
        }

        Task { [weak self] in
            // Gives the session time to list its transfers and to report the ones that finished meanwhile
            try? await Task.sleep(for: .seconds(DownloadTransferSession.usesBackgroundSession ? 3 : 1))
            self?.requeueLostTransfers()
        }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let isSatisfied = path.status == .satisfied

            Task { @MainActor [weak self] in
                self?.pathDidChange(isSatisfied: isSatisfied)
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "Swiftfin.DownloadManager.PathMonitor"))

        Notifications[.applicationWillEnterForeground]
            .publisher
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.connectivityMayHaveChanged()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Reading

    func record(for itemID: String?) -> DownloadRecord? {
        guard let itemID else { return nil }
        return records.first { $0.id == itemID }
    }

    func records(for userSession: UserSession) -> [DownloadRecord] {
        records.filter { $0.serverID == userSession.server.id && $0.userID == userSession.user.id }
    }

    /// The local media file, only when the download is complete and the file exists
    func mediaURL(for record: DownloadRecord) -> URL? {
        guard record.state == .completed, let name = record.mediaFileName else { return nil }

        let url = storage.file(name, for: record.id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func imageURL(_ image: DownloadRecord.Image, for record: DownloadRecord) -> URL? {
        guard let name = record.imageFileNames[image] else { return nil }

        let url = storage.file(name, for: record.id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Bytes on disk for the given records
    func storageUsed(by records: [DownloadRecord]) -> Int64 {
        // A finished record carries the size of its file, an unfinished one has nothing in its directory yet
        records.reduce(0) { $0 + ($1.state == .completed ? $1.bytesReceived : 0) }
    }

    // MARK: - Queue

    /// Whether the item itself (a movie or episode) can be downloaded
    static func canDownload(_ item: BaseItemDto) -> Bool {
        guard item.id != nil, item.type == .movie || item.type == .episode else { return false }

        return item.locationType != .virtual && item.mediaType != .audio
    }

    /// Whether the item is a series or season whose episodes can be downloaded
    static func canDownloadChildren(of item: BaseItemDto) -> Bool {
        item.id != nil && (item.type == .series || item.type == .season)
    }

    /// Queues a movie or episode. Does nothing when a record already exists.
    func download(_ item: BaseItemDto, userSession: UserSession) {
        download(item, quality: .original, userSession: userSession)
    }

    func download(_ item: BaseItemDto, quality: DownloadQuality, userSession: UserSession) {
        guard Self.canDownload(item), let itemID = item.id, record(for: itemID) == nil else { return }

        let record = DownloadRecord(
            id: itemID,
            serverID: userSession.server.id,
            userID: userSession.user.id,
            item: item,
            mediaSourceID: nil,
            quality: quality,
            series: nil,
            season: nil,
            state: .queued,
            errorMessage: nil,
            bytesReceived: 0,
            bytesExpected: 0,
            mediaFileName: nil,
            imageFileNames: [:],
            dateCreated: .now,
            dateCompleted: nil,
            localPlaybackPositionTicks: nil,
            localPlaybackDate: nil,
            needsProgressSync: false
        )

        records.append(record)
        persist(record)
        startQueued(userSession: userSession)
    }

    /// Queues every episode of a series or season.
    func downloadChildren(of item: BaseItemDto, userSession: UserSession) async throws {
        try await downloadChildren(of: item, quality: .original, userSession: userSession)
    }

    func downloadChildren(of item: BaseItemDto, quality: DownloadQuality, userSession: UserSession) async throws {
        guard Self.canDownloadChildren(of: item), let itemID = item.id else { return }

        let seriesID: String
        var parameters = Paths.GetEpisodesParameters(userID: userSession.user.id, isMissing: false)

        if item.type == .season {
            guard let id = item.seriesID else { throw ErrorMessage(L10n.unknownError) }

            seriesID = id
            parameters.seasonID = itemID
        } else {
            seriesID = itemID
        }

        let client = userSession.client
        let response = try await client.send(Paths.getEpisodes(seriesID: seriesID, parameters: parameters))

        for episode in response.value.items ?? [] {
            download(episode, quality: quality, userSession: userSession)
        }
    }

    func pause(_ itemID: String) {
        guard let record = record(for: itemID),
              record.supportsPause,
              record.state == .downloading || record.state == .queued else { return }

        preparations.removeValue(forKey: itemID)?.cancel()
        update(itemID) { $0.state = .paused }

        if let task = tasks.removeValue(forKey: itemID) {
            task.cancel { [weak self] data in
                Task { @MainActor [weak self] in
                    guard let self, let data, self.record(for: itemID)?.state == .paused else { return }

                    storage.saveResumeData(data, for: itemID)
                }
            }
        }

        startQueued()
    }

    /// Continues a paused download, or tries a failed one again
    func resume(_ itemID: String) {
        guard let record = record(for: itemID), record.state == .paused || record.state == .failed else { return }

        update(itemID) {
            $0.state = .queued
            $0.errorMessage = nil
        }
        startQueued()
    }

    /// Cancels an unfinished download or deletes a finished one, with its files
    func delete(_ itemID: String) {
        guard let record = record(for: itemID) else { return }

        preparations.removeValue(forKey: itemID)?.cancel()
        tasks.removeValue(forKey: itemID)?.cancel()
        networkFailures.remove(itemID)

        if case let .transcode(playSessionID) = endpoints.removeValue(forKey: itemID),
           let userSession = currentSession(for: record) {
            DownloadRequestBuilder.stopTranscode(playSessionID: playSessionID, userSession: userSession)
        }

        records.removeAll { $0.id == itemID }
        storage.remove(itemID)
        startQueued()
    }

    // MARK: - Session and connectivity

    /// Called when a user session becomes current
    func userSessionDidStart(_ userSession: UserSession) {
        startQueued(userSession: userSession)

        Task {
            await syncPlaybackProgress(userSession: userSession)
        }
    }

    private func pathDidChange(isSatisfied: Bool) {
        let wasSatisfied = isPathSatisfied
        isPathSatisfied = isSatisfied

        if isSatisfied, !wasSatisfied {
            connectivityMayHaveChanged()
        }
    }

    private func connectivityMayHaveChanged() {
        guard let userSession = Container.shared.currentUserSession() else { return }

        let retries = networkFailures
        networkFailures.removeAll()

        for itemID in retries {
            resume(itemID)
        }

        startQueued(userSession: userSession)

        Task {
            await syncPlaybackProgress(userSession: userSession)
        }
    }

    private static func isNetworkFailure(_ error: Error) -> Bool {
        let codes: [URLError.Code] = [
            .notConnectedToInternet,
            .networkConnectionLost,
            .timedOut,
            .cannotConnectToHost,
            .cannotFindHost,
            .dnsLookupFailed,
            .internationalRoamingOff,
            .dataNotAllowed,
        ]

        return (error as? URLError).map { codes.contains($0.code) } ?? false
    }

    private func currentSession(for record: DownloadRecord) -> UserSession? {
        guard let userSession = Container.shared.currentUserSession(),
              userSession.server.id == record.serverID,
              userSession.user.id == record.userID else { return nil }

        return userSession
    }

    // MARK: - Records

    func update(_ itemID: String, persisting: Bool = true, _ mutate: (inout DownloadRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == itemID }) else { return }

        var record = records[index]
        mutate(&record)

        guard record != records[index] else { return }

        records[index] = record

        if persisting {
            persist(record)
        }
    }

    private func persist(_ record: DownloadRecord) {
        do {
            try storage.save(record)
        } catch {
            logger.error("Unable to save download record \(record.id): \(error.localizedDescription)")
        }
    }

    private func fail(_ itemID: String, message: String) {
        logger.error("Download of \(itemID) failed: \(message)")

        tasks[itemID] = nil
        preparations[itemID] = nil
        endpoints[itemID] = nil

        update(itemID) {
            $0.state = .failed
            $0.errorMessage = message
        }
        startQueued()
    }

    // MARK: - Starting

    /// Starts queued downloads of the current user while there are free slots
    private func startQueued(userSession: UserSession? = nil) {
        // Until the session's tasks are known, a "downloading" record may still be running
        guard hasReconciledTasks, let userSession = userSession ?? Container.shared.currentUserSession() else { return }

        var freeSlots = Self.maxConcurrentDownloads - records.filter { $0.state == .downloading }.count

        for record in records where freeSlots > 0 && record.state == .queued {
            guard record.serverID == userSession.server.id, record.userID == userSession.user.id else { continue }

            freeSlots -= 1
            start(record.id, userSession: userSession)
        }
    }

    private func start(_ itemID: String, userSession: UserSession) {
        update(itemID) {
            $0.state = .downloading
            $0.errorMessage = nil
        }

        preparations[itemID] = Task { [weak self] in
            do {
                try await self?.prepare(itemID, userSession: userSession)
                try Task.checkCancellation()
                try self?.startTransfer(itemID, userSession: userSession)
            } catch {
                guard !Task.isCancelled, let self, record(for: itemID)?.state == .downloading else { return }

                if DownloadManager.isNetworkFailure(error) {
                    networkFailures.insert(itemID)
                }

                fail(itemID, message: error.localizedDescription)
            }
        }
    }

    /// Completes the record with everything needed offline before any media is transferred
    private func prepare(_ itemID: String, userSession: UserSession) async throws {
        guard let record = record(for: itemID) else { throw CancellationError() }

        if !record.hasFullMetadata {
            let client = userSession.client
            let userID = userSession.user.id

            var item = try await client.send(Paths.getItem(itemID: itemID, userID: userID)).value
            let series = try await parent(item.type == .episode ? item.seriesID : nil, userSession: userSession)
            let season = try await parent(item.type == .episode ? item.seasonID : nil, userSession: userSession)

            guard let source = item.mediaSources?.first else {
                throw ErrorMessage("Unable to find media source for item")
            }

            var quality = record.quality
            var fileExtension = DownloadRequestBuilder.fileExtension(for: source)

            if let bitrate = quality.bitrate {
                // A copy would not be smaller than the original
                if let sourceBitrate = source.bitrate, sourceBitrate <= bitrate {
                    quality = .original
                } else if userSession.userData.policy?.enableVideoPlaybackTranscoding == false {
                    throw ErrorMessage("This user is not allowed to transcode video on the server.")
                } else {
                    item.mediaSources = [DownloadRequestBuilder.transcodedSource(from: source, quality: quality)]
                    fileExtension = DownloadRequestBuilder.transcodeContainer
                }
            }

            let expected: Int64 = if let bitrate = quality.bitrate {
                Int64(Double(bitrate) / 8 * (Duration.ticks(source.runTimeTicks ?? item.runTimeTicks ?? 0) / .seconds(1)))
            } else {
                Int64(source.size ?? 0)
            }

            if expected > 0, let available = storage.availableCapacity(), available < expected {
                let needed = expected.formatted(.byteCount(style: .file))
                throw ErrorMessage("There is not enough free space for this download (\(needed)).")
            }

            update(itemID) {
                // Positions recorded meanwhile are newer than the fetched ones
                if $0.localPlaybackDate != nil {
                    item.userData = $0.item.userData
                }

                $0.item = item
                $0.series = series
                $0.season = season
                $0.mediaSourceID = source.id
                $0.quality = quality
                $0.mediaFileName = "media.\(fileExtension)"
                $0.bytesExpected = expected
                $0.hasFullMetadata = true
            }
        }

        try Task.checkCancellation()

        if let record = self.record(for: itemID), record.imageFileNames.isEmpty {
            Task { [weak self] in
                await self?.downloadImages(for: itemID, userSession: userSession)
            }
        }

        if let record = self.record(for: itemID),
           record.subtitleFileNames.isEmpty,
           DownloadRequestBuilder.sidecarSubtitles(of: record).isNotEmpty {
            Task { [weak self] in
                await self?.downloadSubtitles(for: itemID, userSession: userSession)
            }
        }
    }

    private func parent(_ id: String?, userSession: UserSession) async throws -> BaseItemDto? {
        guard let id else { return nil }

        if let parent = parents[id] {
            return parent
        }

        let client = userSession.client
        let parent = try await client.send(Paths.getItem(itemID: id, userID: userSession.user.id)).value
        parents[id] = parent

        return parent
    }

    private func downloadImages(for itemID: String, userSession: UserSession) async {
        guard let record = record(for: itemID) else { return }

        let requests = DownloadRequestBuilder.imageRequests(for: record.item, userSession: userSession)
        let storage = storage

        for (image, request) in requests {
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let response = response as? HTTPURLResponse,
                  (200 ..< 300).contains(response.statusCode),
                  data.isNotEmpty else { continue }

            let fileExtension = switch response.mimeType {
            case "image/png": "png"
            case "image/webp": "webp"
            default: "jpg"
            }
            let name = "\(image.rawValue).\(fileExtension)"

            // The download may have been deleted while the image loaded
            guard self.record(for: itemID) != nil,
                  (try? data.write(to: storage.file(name, for: itemID), options: .atomic)) != nil else { continue }

            update(itemID) { $0.imageFileNames[image] = name }
        }
    }

    private func downloadSubtitles(for itemID: String, userSession: UserSession) async {
        guard let record = record(for: itemID) else { return }

        let storage = storage

        for stream in DownloadRequestBuilder.sidecarSubtitles(of: record) {
            guard let index = stream.index,
                  let request = DownloadRequestBuilder.subtitleRequest(for: stream, record: record, userSession: userSession),
                  let (data, response) = try? await URLSession.shared.data(for: request),
                  let response = response as? HTTPURLResponse,
                  (200 ..< 300).contains(response.statusCode),
                  data.isNotEmpty else { continue }

            let name = "subtitle-\(index).\(DownloadRequestBuilder.subtitleFormat(for: stream))"

            // The download may have been deleted while the subtitle loaded
            guard self.record(for: itemID) != nil,
                  (try? data.write(to: storage.file(name, for: itemID), options: .atomic)) != nil else { continue }

            update(itemID) { $0.subtitleFileNames[index] = name }
        }
    }

    private func startTransfer(_ itemID: String, userSession: UserSession) throws {
        guard let record = record(for: itemID), record.state == .downloading else { throw CancellationError() }

        let task: URLSessionDownloadTask

        if let data = storage.takeResumeData(for: itemID) {
            task = transfer.session.downloadTask(withResumeData: data)
        } else {
            let endpoint: DownloadRequestBuilder.Endpoint = if !record.quality.isOriginal {
                .transcode(playSessionID: UUID().uuidString.replacingOccurrences(of: "-", with: ""))
            } else if endpoints[itemID] == nil, userSession.userData.policy?.enableContentDownloading == true {
                .download
            } else {
                .staticStream
            }

            guard let request = DownloadRequestBuilder.mediaRequest(for: record, endpoint: endpoint, userSession: userSession) else {
                throw ErrorMessage("Unable to make download URL")
            }

            endpoints[itemID] = endpoint
            task = transfer.session.downloadTask(with: request)
            update(itemID, persisting: false) { $0.bytesReceived = 0 }
        }

        task.taskDescription = itemID
        tasks[itemID] = task
        preparations[itemID] = nil
        task.resume()
    }

    // MARK: - Transfer events

    /// Adopts the transfers of a previous launch
    private func attach(_ downloads: [URLSessionDownloadTask]) {
        for task in downloads {
            guard let itemID = task.taskDescription,
                  record(for: itemID)?.state == .downloading,
                  tasks[itemID] == nil,
                  task.state == .running || task.state == .suspended
            else {
                if task.state == .running || task.state == .suspended, task.taskDescription.flatMap({ tasks[$0] }) !== task {
                    task.cancel()
                }
                continue
            }

            tasks[itemID] = task
        }
    }

    /// Restarts the downloads whose transfer did not survive the previous launch
    private func requeueLostTransfers() {
        guard !hasReconciledTasks else { return }

        for record in records where record.state == .downloading && tasks[record.id] == nil && preparations[record.id] == nil {
            update(record.id) { $0.state = .queued }
        }

        hasReconciledTasks = true
        startQueued()
    }

    private func handle(_ event: DownloadTransferSession.Event) {
        switch event {
        case let .progress(itemID, received, expected):
            guard tasks[itemID] != nil else { return }

            update(itemID, persisting: false) {
                $0.bytesReceived = received

                if expected > 0 {
                    $0.bytesExpected = expected
                }
            }

        case let .finished(itemID, statusCode):
            transferDidFinish(itemID, statusCode: statusCode)

        case let .failed(itemID, error, data):
            transferDidFail(itemID, error: error, resumeData: data)

        case let .invalidated(error):
            if !fallBackToDefaultSession(after: error) {
                logger.error("Download session became invalid: \(error.localizedDescription)")
            }
        }
    }

    private func transferDidFinish(_ itemID: String, statusCode: Int) {
        let incoming = storage.file(DownloadStorage.incomingFileName, for: itemID)
        let endpoint = endpoints.removeValue(forKey: itemID)
        tasks[itemID] = nil

        guard let record = record(for: itemID), record.state == .downloading, let name = record.mediaFileName else {
            try? FileManager.default.removeItem(at: incoming)
            return
        }

        guard (200 ..< 300).contains(statusCode) else {
            // Servers can refuse the download endpoint while still allowing playback of the original
            if statusCode == 403, endpoint == .download, let userSession = currentSession(for: record) {
                endpoints[itemID] = .staticStream

                do {
                    try startTransfer(itemID, userSession: userSession)
                } catch {
                    fail(itemID, message: error.localizedDescription)
                }
                return
            }

            let message = switch statusCode {
            case 401: "The server rejected the sign in. Sign in again and retry."
            case 403: "This user is not allowed to download this item."
            case 404: "The item no longer exists on the server."
            default: "The server responded with status \(statusCode)."
            }

            fail(itemID, message: message)
            return
        }

        let destination = storage.file(name, for: itemID)

        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: incoming, to: destination)
        } catch {
            fail(itemID, message: error.localizedDescription)
            return
        }

        let size = storage.size(of: destination)

        guard size > 0 else {
            try? FileManager.default.removeItem(at: destination)
            fail(itemID, message: "The server sent an empty file.")
            return
        }

        storage.excludeFromBackup(destination)

        update(itemID) {
            $0.state = .completed
            $0.errorMessage = nil
            $0.bytesReceived = size
            $0.bytesExpected = size
            $0.dateCompleted = .now
        }

        startQueued()
    }

    /// Moves every transfer to an in-process session when the background transfer service cannot be used
    private func fallBackToDefaultSession(after error: Error) -> Bool {
        guard transfer.fallBackToDefaultSession() else { return false }

        logger.warning("Background transfers are unavailable, downloading in-process: \(error.localizedDescription)")

        // Replacing the session cancels every transfer it had
        for record in records where record.state == .downloading && preparations[record.id] == nil {
            tasks[record.id] = nil
            endpoints[record.id] = nil
            update(record.id) { $0.state = .queued }
        }

        hasReconciledTasks = true
        startQueued()
        return true
    }

    private func transferDidFail(_ itemID: String, error: Error, resumeData data: Data?) {
        // Pausing, deleting and replacing a transfer all cancel its task
        if let task = tasks[itemID], task.state == .running || task.state == .suspended {
            return
        }

        // A record that is still preparing has no transfer of its own yet
        guard preparations[itemID] == nil else { return }

        guard let record = record(for: itemID), record.state == .downloading else { return }

        if DownloadTransferSession.isBackgroundServiceFailure(error), fallBackToDefaultSession(after: error) {
            return
        }

        if record.supportsPause {
            storage.saveResumeData(data, for: itemID)
        }

        if Self.isNetworkFailure(error) {
            networkFailures.insert(itemID)
        }

        fail(itemID, message: error.localizedDescription)
    }
}

#endif
