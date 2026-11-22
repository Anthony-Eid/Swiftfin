//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AppKit

/// Keeps the guide's scroll views aligned: the program grid scrolls on both
/// axes, the time ruler follows it horizontally and the channel column
/// follows it vertically.
@MainActor
final class EPGScrollProxy: ObservableObject {

    private final class BoundsObservation {

        private var token: NSObjectProtocol?

        @MainActor
        init(_ scrollView: NSScrollView, handler: @escaping (NSScrollView) -> Void) {
            scrollView.contentView.postsBoundsChangedNotifications = true

            token = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: nil
            ) { [weak scrollView] _ in
                guard let scrollView else { return }
                handler(scrollView)
            }
        }

        func invalidate() {
            guard let token else { return }
            NotificationCenter.default.removeObserver(token)
            self.token = nil
        }

        deinit {
            invalidate()
        }
    }

    private weak var contentScrollView: NSScrollView?

    private var didCenter = false
    private var isConnected = true
    private var isSyncingHorizontally = false
    private var isSyncingVertically = false

    private let horizontalScrollViews = NSHashTable<NSScrollView>.weakObjects()
    private let verticalScrollViews = NSHashTable<NSScrollView>.weakObjects()

    private let horizontalObservations = NSMapTable<NSScrollView, BoundsObservation>(
        keyOptions: .weakMemory,
        valueOptions: .strongMemory
    )
    private let verticalObservations = NSMapTable<NSScrollView, BoundsObservation>(
        keyOptions: .weakMemory,
        valueOptions: .strongMemory
    )

    func registerContent(_ scrollView: NSScrollView, centeringOn target: CGFloat?) {
        if contentScrollView !== scrollView {
            didCenter = false
        }

        contentScrollView = scrollView

        registerHorizontal(scrollView)

        if !didCenter, let target, let offset = offset(centering: target) {
            setOffset(
                CGPoint(x: offset, y: scrollView.contentOffset.y),
                of: scrollView,
                animated: false
            )
            didCenter = true
        }
    }

    func registerHorizontal(_ scrollView: NSScrollView) {
        horizontalScrollViews.add(scrollView)

        guard isConnected, horizontalObservations.object(forKey: scrollView) == nil else { return }

        let observation = BoundsObservation(scrollView) { [weak self] scrollView in
            MainActor.assumeIsolated {
                self?.horizontalOffsetDidChange(scrollView)
            }
        }

        horizontalObservations.setObject(observation, forKey: scrollView)

        // A scroll view that joins late starts where the others already are.
        if let contentScrollView, contentScrollView !== scrollView {
            horizontalOffsetDidChange(contentScrollView)
        }
    }

    func registerVertical(_ scrollView: NSScrollView) {
        verticalScrollViews.add(scrollView)

        guard isConnected, verticalObservations.object(forKey: scrollView) == nil else { return }

        let observation = BoundsObservation(scrollView) { [weak self] scrollView in
            MainActor.assumeIsolated {
                self?.verticalOffsetDidChange(scrollView)
            }
        }

        verticalObservations.setObject(observation, forKey: scrollView)
    }

    func reset() {
        didCenter = false

        guard let contentScrollView else { return }

        setOffset(
            CGPoint(x: 0, y: contentScrollView.contentOffset.y),
            of: contentScrollView,
            animated: false
        )
    }

    func connect() {
        isConnected = true

        horizontalScrollViews.allObjects.forEach(registerHorizontal)
        verticalScrollViews.allObjects.forEach(registerVertical)
    }

    func disconnect() {
        isConnected = false

        invalidateObservations(in: horizontalObservations)
        invalidateObservations(in: verticalObservations)
    }

    func scrollTo(centering target: CGFloat) {
        guard let contentScrollView, let offset = offset(centering: target) else { return }

        setOffset(
            CGPoint(x: offset, y: contentScrollView.contentOffset.y),
            of: contentScrollView,
            animated: true
        )
    }

    private func offset(centering target: CGFloat) -> CGFloat? {
        guard let contentScrollView else { return nil }

        let viewport = contentScrollView.contentView.bounds.width
        let contentWidth = contentScrollView.documentView?.frame.width ?? 0

        guard viewport > 0, contentWidth > viewport else { return nil }

        return clamp(
            target - viewport / 2,
            min: 0,
            max: contentWidth - viewport
        )
    }

    private func setOffset(_ offset: CGPoint, of scrollView: NSScrollView, animated: Bool) {
        let clipView = scrollView.contentView

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.allowsImplicitAnimation = true
                clipView.animator().setBoundsOrigin(offset)
                scrollView.reflectScrolledClipView(clipView)
            }
        } else {
            clipView.scroll(to: offset)
            scrollView.reflectScrolledClipView(clipView)
        }
    }

    private func invalidateObservations(
        in observations: NSMapTable<NSScrollView, BoundsObservation>
    ) {
        let observationTokens = observations.objectEnumerator()?.allObjects as? [BoundsObservation] ?? []
        observationTokens.forEach { $0.invalidate() }
        observations.removeAllObjects()
    }

    private func horizontalOffsetDidChange(_ source: NSScrollView) {
        guard !isSyncingHorizontally else { return }

        isSyncingHorizontally = true
        defer { isSyncingHorizontally = false }

        let scrollViews = horizontalObservations.keyEnumerator().allObjects as? [NSScrollView] ?? []

        for scrollView in scrollViews {
            guard scrollView !== source,
                  abs(scrollView.contentOffset.x - source.contentOffset.x) > 0.5
            else { continue }

            setOffset(
                CGPoint(x: source.contentOffset.x, y: scrollView.contentOffset.y),
                of: scrollView,
                animated: false
            )
        }
    }

    private func verticalOffsetDidChange(_ source: NSScrollView) {
        guard !isSyncingVertically else { return }

        isSyncingVertically = true
        defer { isSyncingVertically = false }

        let scrollViews = verticalObservations.keyEnumerator().allObjects as? [NSScrollView] ?? []

        for scrollView in scrollViews {
            guard scrollView !== source,
                  abs(scrollView.contentOffset.y - source.contentOffset.y) > 0.5
            else { continue }

            setOffset(
                CGPoint(x: scrollView.contentOffset.x, y: source.contentOffset.y),
                of: scrollView,
                animated: false
            )
        }
    }
}

private extension NSScrollView {

    var contentOffset: CGPoint {
        contentView.bounds.origin
    }
}
