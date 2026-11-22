//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if !os(tvOS)

import Foundation

/// Owns the `URLSession` that transfers media files and turns its delegate
/// callbacks into a few throttled events.
final class DownloadTransferSession: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    /// A background session keeps transferring while the app is suspended or not running.
    /// Set to `false` to transfer in-process with a default session instead.
    static let usesBackgroundSession = true

    static let identifier = "\(Bundle.main.bundleIdentifier ?? "org.jellyfin.swiftfin").downloads"

    private static let progressInterval: TimeInterval = 0.5

    enum Event: Sendable {

        case progress(itemID: String, received: Int64, expected: Int64)
        /// The file was moved to `DownloadStorage.incomingFileName` in the item's directory
        case finished(itemID: String, statusCode: Int)
        case failed(itemID: String, error: Error, resumeData: Data?)
        /// The system gave up on the session itself
        case invalidated(error: Error)
    }

    private let storage: DownloadStorage
    private let onEvent: @Sendable (Event) -> Void

    // Only touched on the delegate queue
    private var lastProgress: [Int: Date] = [:]
    private var moved: [Int: Result<Int, Error>] = [:]

    private(set) var isBackground = DownloadTransferSession.usesBackgroundSession

    private(set) lazy var session: URLSession = makeSession()

    /// The background transfer service refuses some processes, an in-process session always works
    static func isBackgroundServiceFailure(_ error: Error) -> Bool {
        let codes: [URLError.Code] = [
            .backgroundSessionRequiresSharedContainer,
            .backgroundSessionInUseByAnotherProcess,
            .backgroundSessionWasDisconnected,
        ]

        return (error as? URLError).map { codes.contains($0.code) } ?? false
    }

    /// Returns whether the session was replaced
    func fallBackToDefaultSession() -> Bool {
        guard isBackground else { return false }

        isBackground = false
        session.invalidateAndCancel()
        session = makeSession()
        return true
    }

    private func makeSession() -> URLSession {
        let configuration: URLSessionConfiguration

        if isBackground {
            configuration = .background(withIdentifier: Self.identifier)
            configuration.isDiscretionary = false
            configuration.sessionSendsLaunchEvents = true
        } else {
            configuration = .default
            configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
        }

        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        // A transcode can take a while to produce its first bytes
        configuration.timeoutIntervalForRequest = 120
        configuration.allowsCellularAccess = true

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        return URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    init(storage: DownloadStorage, onEvent: @escaping @Sendable (Event) -> Void) {
        self.storage = storage
        self.onEvent = onEvent
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        guard let error, session === self.session else { return }

        onEvent(.invalidated(error: error))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let itemID = downloadTask.taskDescription else { return }

        let now = Date.now
        if let last = lastProgress[downloadTask.taskIdentifier], now.timeIntervalSince(last) < Self.progressInterval {
            return
        }

        // The body of an error response is not progress of the media file
        if let statusCode = (downloadTask.response as? HTTPURLResponse)?.statusCode, !(200 ..< 300).contains(statusCode) {
            return
        }

        lastProgress[downloadTask.taskIdentifier] = now
        onEvent(.progress(itemID: itemID, received: totalBytesWritten, expected: totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let itemID = downloadTask.taskDescription else { return }

        // The temporary file is deleted when this method returns
        let statusCode = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200 ..< 300).contains(statusCode) else {
            moved[downloadTask.taskIdentifier] = .success(statusCode)
            return
        }

        do {
            let directory = storage.directory(for: itemID)
            let destination = storage.file(DownloadStorage.incomingFileName, for: itemID)

            // A missing directory means the download was deleted meanwhile
            guard FileManager.default.fileExists(atPath: directory.path) else {
                moved[downloadTask.taskIdentifier] = .failure(CancellationError())
                return
            }

            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            moved[downloadTask.taskIdentifier] = .success(statusCode)
        } catch {
            moved[downloadTask.taskIdentifier] = .failure(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result = moved.removeValue(forKey: task.taskIdentifier)
        lastProgress[task.taskIdentifier] = nil

        guard let itemID = task.taskDescription else { return }

        if let error {
            let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            onEvent(.failed(itemID: itemID, error: error, resumeData: resumeData))
            return
        }

        switch result {
        case let .success(statusCode):
            onEvent(.finished(itemID: itemID, statusCode: statusCode))
        case let .failure(error):
            onEvent(.failed(itemID: itemID, error: error, resumeData: nil))
        case nil:
            onEvent(.failed(itemID: itemID, error: URLError(.cannotCreateFile), resumeData: nil))
        }
    }
}

#endif
