//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AppKit
import SwiftUI

extension VideoPlayer {

    /// The shared player views reach their container through this name.
    typealias UIContainerViewController = MacContainerCoordinator

    // MARK: - Container

    struct Container<Player: View, PlaybackControls: View>: View {

        @State
        private var coordinator: MacContainerCoordinator

        private let viewState: ViewState
        private let mediaSession: MediaSession
        private let videoSize: () -> CGSize
        private let player: (VideoLayout) -> Player
        private let playbackControls: PlaybackControls

        init(
            viewState: ViewState,
            mediaSession: MediaSession,
            videoSize: @escaping () -> CGSize,
            @ContentBuilder player: @escaping (VideoLayout) -> Player,
            @ContentBuilder playbackControls: @escaping () -> PlaybackControls
        ) {
            self._coordinator = State(wrappedValue: MacContainerCoordinator(viewState: viewState, mediaSession: mediaSession))
            self.viewState = viewState
            self.mediaSession = mediaSession
            self.videoSize = videoSize
            self.player = player
            self.playbackControls = playbackControls()
        }

        @ContentBuilder
        var body: some View {
            ZStack {
                Color.black

                PlayerSurface(videoSize: videoSize, player: player)

                PointerInputView(coordinator: coordinator)
                    .accessibilityHidden(true)

                playbackControls
            }
            .modifier(KeyCommandsResponder())
            .layoutContainer(size: viewState.layoutSize)
            .environment(viewState)
            .environmentObject(viewState.focusCoordinator)
            .environment(mediaSession)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                coordinator.layoutDidChange(size: size)
            }
            .onChange(of: viewState.presentation == .hidden) {
                coordinator.controlsVisibilityDidChange()
            }
            .onAppear {
                coordinator.attach()
            }
            .onDisappear {
                coordinator.detach()
            }
        }
    }

    // MARK: - PlayerSurface

    private struct PlayerSurface<Player: View>: View {

        @Environment(ViewState.self)
        private var viewState

        let videoSize: () -> CGSize
        let player: (VideoLayout) -> Player

        private var isDimmed: Bool {
            viewState.visibleElements.contains(.dimming)
        }

        @ContentBuilder
        var body: some View {
            VideoViewport(videoSize: videoSize) { videoLayout in
                player(videoLayout)
            }
            .overlay {
                Color.black
                    .opacity(isDimmed ? 0.3 : 0)
            }
            .overlay {
                Group {
                    if viewState.isPresentingFullScreenSupplement {
                        Color.black.opacity(0.8)
                    } else {
                        EasedGradient(
                            colors: [.clear, .black],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    }
                }
                .isVisible(isDimmed)
            }
            .animation(.linear(duration: 0.25), value: isDimmed)
            .animation(.linear(duration: 0.25), value: viewState.isPresentingFullScreenSupplement)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: - MacContainerCoordinator

    /// Connects the SwiftUI container to its window: pointer activity, the cursor,
    /// full screen, and the layout of the supplement panel.
    @MainActor
    final class MacContainerCoordinator {

        typealias ViewState = VideoPlayer.ViewState

        let viewState: ViewState

        private let mediaSession: MediaSession
        private let pointerInteraction = ViewState.Interaction.button(UUID())
        private var isPointerInside = false

        /// Mirrors the interaction held in `viewState`, which every pointer event would otherwise invalidate.
        private var isHoldingControls = false {
            didSet {
                guard isHoldingControls != oldValue else { return }

                viewState.setInteraction(pointerInteraction, active: isHoldingControls)
            }
        }
        private var suppressedPointerLocation: CGPoint?

        fileprivate weak var inputView: NSView?

        init(viewState: ViewState, mediaSession: MediaSession) {
            self.viewState = viewState
            self.mediaSession = mediaSession
        }

        // MARK: Window

        private var window: NSWindow? {
            inputView?.window
        }

        var isFullScreen: Bool {
            window?.styleMask.contains(.fullScreen) == true
        }

        var isCoveredByPresentation: Bool {
            window?.attachedSheet != nil
        }

        func toggleFullScreen() {
            window?.toggleFullScreen(nil)
        }

        // MARK: Lifecycle

        fileprivate func attach() {
            viewState.containerView = self
            viewState.isCompact = false
            viewState.connect(mediaSession: mediaSession)

            updateSupplementLayout(animated: false)
            viewState.showControls()
        }

        fileprivate func detach() {
            isHoldingControls = false
            NSCursor.setHiddenUntilMouseMoves(false)

            didDismiss()

            guard viewState.containerView === self else { return }

            viewState.containerView = nil
            viewState.disconnect()
        }

        /// The player leaves the window only when it is closed, never while it is covered.
        private func didDismiss() {
            guard !viewState.isBeingDismissed else { return }

            viewState.isBeingDismissed = true
            let pictureInPicture = mediaSession.player as? MediaPlayerPictureInPictureProviding

            if pictureInPicture?.isPiPActive != true, pictureInPicture?.isPiPTransitioning != true {
                mediaSession.stop()
            }
        }

        // MARK: Layout

        private var edgePadding: CGFloat {
            ViewLayout.platformDefault.resolving(size: viewState.layoutSize).edgePadding
        }

        private var availableSupplementHeight: CGFloat {
            max(0, viewState.layoutSize.height - viewState.systemInsets.top)
        }

        private var dismissedSupplementHeight: CGFloat {
            min(availableSupplementHeight, 50 + edgePadding * 2)
        }

        private var presentedSupplementHeight: CGFloat {
            if viewState.selectedSupplement?.presentationStyle == .expanded {
                return availableSupplementHeight
            }

            return min(availableSupplementHeight, 200 + edgePadding * 2)
        }

        fileprivate func layoutDidChange(size: CGSize) {
            if viewState.layoutSize != size {
                viewState.layoutSize = size
            }

            updateSystemInsets()
            updateSupplementLayout(animated: false)
        }

        /// A full-size content view extends under the title bar, where the
        /// window buttons would cover the toolbar.
        fileprivate func updateSystemInsets() {
            guard let inputView, let window else { return }

            let frame = inputView.convert(inputView.bounds, to: nil)
            let top = isFullScreen ? 0 : max(0, frame.maxY - window.contentLayoutRect.maxY)
            let insets = EdgeInsets(top: top, leading: 0, bottom: 0, trailing: 0)

            guard viewState.systemInsets != insets else { return }

            viewState.systemInsets = insets
            updateSupplementLayout(animated: false)
        }

        func presentSupplementContainer(_ didPresent: Bool) {
            updateSupplementLayout(animated: true)
        }

        private func updateSupplementLayout(animated: Bool) {
            let presentedHeight = presentedSupplementHeight
            let dismissedHeight = dismissedSupplementHeight
            let visibleHeight = viewState.isPresentingSupplement ? presentedHeight : dismissedHeight

            // Keep the playback buttons centered in the video left above the panel.
            let buttonsInsets = EdgeInsets(top: 0, leading: 0, bottom: max(0, visibleHeight - dismissedHeight), trailing: 0)

            guard viewState.supplementHeight != presentedHeight ||
                viewState.supplementVisibleHeight != visibleHeight ||
                viewState.playbackButtonsInsets != buttonsInsets
            else { return }

            withAnimation(animated ? .spring(response: 0.6, dampingFraction: 0.8) : nil) {
                viewState.supplementHeight = presentedHeight
                viewState.supplementVisibleHeight = visibleHeight
                viewState.playbackButtonsInsets = buttonsInsets
            }
        }

        // MARK: Pointer

        /// Resting the pointer on the toolbar or the progress bar keeps them presented.
        private func isOverControls(_ location: CGPoint, in bounds: CGRect) -> Bool {
            guard viewState.isPresentingControls else { return false }

            let topBand = viewState.systemInsets.top + edgePadding + 60
            let bottomBand = viewState.supplementVisibleHeight + 80

            return location.y < bounds.minY + topBand || location.y > bounds.maxY - bottomBand
        }

        /// - Parameter location: The pointer in the top-left coordinates of `bounds`.
        fileprivate func pointerDidMove(to location: CGPoint, in bounds: CGRect) {
            isPointerInside = true

            // A click that hides the controls must not be undone by the hand settling.
            if let suppressedPointerLocation {
                guard abs(location.x - suppressedPointerLocation.x) > 8 ||
                    abs(location.y - suppressedPointerLocation.y) > 8
                else { return }

                self.suppressedPointerLocation = nil
            }

            viewState.showControls()
            isHoldingControls = isOverControls(location, in: bounds)
        }

        fileprivate func pointerDidExit() {
            isPointerInside = false
            suppressedPointerLocation = nil
            isHoldingControls = false
        }

        fileprivate func pointerDidClick(count: Int, at location: CGPoint) {
            switch count {
            case 1:
                toggleControls(at: location)
            case 2:
                // The first click of the pair has already toggled the controls.
                toggleControls(at: location)
                toggleFullScreen()
            default:
                break
            }
        }

        private func toggleControls(at location: CGPoint) {
            isHoldingControls = false

            if viewState.isPresentingSupplement {
                viewState.selectedSupplementID = nil
            } else if viewState.isPresentingControls {
                suppressedPointerLocation = location
                viewState.hideControls()
            } else {
                suppressedPointerLocation = nil
                viewState.showControls()
            }
        }

        fileprivate func controlsVisibilityDidChange() {
            guard viewState.presentation == .hidden else { return }

            isHoldingControls = false

            if isPointerInside, window?.isKeyWindow == true, !isCoveredByPresentation {
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
    }

    // MARK: - PointerInputView

    /// Receives the clicks that fall through the playback controls and
    /// follows the pointer across the whole player, including over the controls.
    private struct PointerInputView: NSViewRepresentable {

        let coordinator: MacContainerCoordinator

        func makeNSView(context: Context) -> InputView {
            let view = InputView()
            view.coordinator = coordinator
            coordinator.inputView = view

            return view
        }

        func updateNSView(_ nsView: InputView, context: Context) {
            nsView.coordinator = coordinator
            coordinator.inputView = nsView
        }

        final class InputView: NSView {

            weak var coordinator: MacContainerCoordinator?

            private var trackingArea: NSTrackingArea?
            private var windowObservers: [NSObjectProtocol] = []

            override var isFlipped: Bool {
                true
            }

            override func updateTrackingAreas() {
                super.updateTrackingAreas()

                if let trackingArea {
                    removeTrackingArea(trackingArea)
                }

                let trackingArea = NSTrackingArea(
                    rect: .zero,
                    options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                    owner: self
                )

                addTrackingArea(trackingArea)
                self.trackingArea = trackingArea
            }

            override func layout() {
                super.layout()

                coordinator?.updateSystemInsets()
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()

                windowObservers.forEach(NotificationCenter.default.removeObserver)
                windowObservers.removeAll()

                guard let window else {
                    coordinator?.pointerDidExit()
                    return
                }

                // The title bar leaves and returns without resizing this view.
                observe(NSWindow.didEnterFullScreenNotification, of: window) { $0.updateSystemInsets() }
                observe(NSWindow.didExitFullScreenNotification, of: window) { $0.updateSystemInsets() }

                // The tracking area goes quiet in an inactive window without reporting an exit.
                observe(NSWindow.didResignKeyNotification, of: window) { $0.pointerDidExit() }

                coordinator?.updateSystemInsets()
            }

            private func observe(
                _ name: Notification.Name,
                of window: NSWindow,
                perform action: @escaping @MainActor (MacContainerCoordinator) -> Void
            ) {
                let observer = NotificationCenter.default.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let coordinator = self?.coordinator else { return }

                        action(coordinator)
                    }
                }

                windowObservers.append(observer)
            }

            override func mouseEntered(with event: NSEvent) {
                coordinator?.pointerDidMove(to: convert(event.locationInWindow, from: nil), in: bounds)
            }

            override func mouseMoved(with event: NSEvent) {
                coordinator?.pointerDidMove(to: convert(event.locationInWindow, from: nil), in: bounds)
            }

            override func mouseExited(with event: NSEvent) {
                coordinator?.pointerDidExit()
            }

            // Taking the press keeps the release from travelling up the responder chain.
            override func mouseDown(with event: NSEvent) {}

            override func mouseUp(with event: NSEvent) {
                let location = convert(event.locationInWindow, from: nil)

                guard bounds.contains(location) else { return }

                coordinator?.pointerDidClick(count: event.clickCount, at: location)
            }
        }
    }
}
