//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

// TODO: protect against holding down

extension VideoPlayer {

    struct KeyCommandsModifier: ViewModifier {

        @Default(.VideoPlayer.jumpBackwardInterval)
        private var jumpBackwardInterval
        @Default(.VideoPlayer.jumpForwardInterval)
        private var jumpForwardInterval

        @Environment(ViewState.self)
        private var viewState

        @Environment(MediaSession.self)
        private var mediaSession

        @Toaster
        private var toaster: ToastProxy

        #if os(macOS)
        @Router
        private var router

        private func adjustVolume(by delta: Double) {
            guard let player = mediaSession.player as? any MediaPlayerVolumeProviding else { return }

            let volume = clamp(player.volume + delta, min: 0, max: 1)
            player.setVolume(volume)

            toaster.present(
                Text(volume, format: .percent.precision(.fractionLength(0))),
                systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill"
            )
        }
        #endif

        @ContentBuilder
        func body(content: Content) -> some View {
            content
                .keyCommands {
                    // MARK: Aspect Fill

                    KeyCommandAction(
                        title: "Aspect Fill",
                        input: "f",
                        modifierFlags: .command
                    ) {
                        viewState.toggleAspectFillBehavior()
                    }

                    KeyCommandAction(
                        title: L10n.playAndPause,
                        input: " "
                    ) {
                        guard mediaSession.canControlPlayback else { return }

                        mediaSession.togglePlayPause()

                        if !viewState.isPresentingControls {
                            if mediaSession.playbackRequestStatus == .paused {
                                toaster.present(
                                    L10n.pause,
                                    systemName: "pause.circle"
                                )
                            } else if mediaSession.playbackRequestStatus == .playing {
                                toaster.present(
                                    L10n.play,
                                    systemName: "play.circle"
                                )
                            }
                        }
                    }

                    // MARK: - Decrease Playback Speed

                    KeyCommandAction(
                        title: "Decrease Playback Speed",
                        input: "[",
                        modifierFlags: .command
                    ) {
                        let newRate = clamp(
                            mediaSession.rate - 0.25,
                            min: 0.25,
                            max: 4
                        )

                        mediaSession.rate = newRate

                        toaster.present(
                            Text(newRate, format: .playbackRate),
                            systemName: VideoPlayerActionButton.playbackSpeed.systemImage
                        )
                    }

                    // MARK: - Increase Playback Speed

                    KeyCommandAction(
                        title: "Increase Playback Speed",
                        input: "]",
                        modifierFlags: .command
                    ) {
                        let newRate = clamp(
                            mediaSession.rate + 0.25,
                            min: 0.25,
                            max: 4
                        )

                        mediaSession.rate = newRate

                        toaster.present(
                            Text(newRate, format: .playbackRate),
                            systemName: VideoPlayerActionButton.playbackSpeed.systemImage
                        )
                    }

                    // MARK: Reset Playback Speed

                    KeyCommandAction(
                        title: "Reset Playback Speed",
                        input: "\\",
                        modifierFlags: .command
                    ) {
                        mediaSession.rate = 1

                        toaster.present(
                            Text(1, format: .playbackRate),
                            systemName: VideoPlayerActionButton.playbackSpeed.systemImage
                        )
                    }

                    // MARK: Play Next Item

                    KeyCommandAction(
                        title: L10n.nextItem,
                        input: KeyCommandAction.inputRightArrow,
                        modifierFlags: .command
                    ) {
                        guard let nextItem = mediaSession.queue?.nextItem else { return }

                        mediaSession.playNewItem(intent: nextItem)
                    }

                    // MARK: Play Previous Item

                    KeyCommandAction(
                        title: L10n.previousItem,
                        input: KeyCommandAction.inputLeftArrow,
                        modifierFlags: .command
                    ) {
                        guard let previousItem = mediaSession.queue?.previousItem else { return }

                        mediaSession.playNewItem(intent: previousItem)
                    }

                    // MARK: - Jump Backward

                    KeyCommandAction(
                        title: L10n.jumpBackward,
                        input: KeyCommandAction.inputLeftArrow
                    ) {
                        guard mediaSession.canSeek else { return }

                        viewState.showProgress()
                        viewState.jumpProgressObserver.jumpBackward()
                        mediaSession.seek(by: .zero - (jumpBackwardInterval.rawValue))

                        toaster.present(
                            Text(
                                jumpBackwardInterval.rawValue * viewState.jumpProgressObserver.jumps,
                                format: .minuteSecondsAbbreviated
                            ),
                            systemName: "gobackward"
                        )
                    }

                    // MARK: - Jump Forward

                    KeyCommandAction(
                        title: L10n.jumpForward,
                        input: KeyCommandAction.inputRightArrow
                    ) {
                        guard mediaSession.canSeek else { return }

                        viewState.showProgress()
                        viewState.jumpProgressObserver.jumpForward()
                        mediaSession.seek(by: jumpForwardInterval.rawValue)

                        toaster.present(
                            Text(
                                jumpForwardInterval.rawValue * viewState.jumpProgressObserver.jumps,
                                format: .minuteSecondsAbbreviated
                            ),
                            systemName: "goforward"
                        )
                    }

                    #if os(macOS)

                    // MARK: - Full Screen

                    KeyCommandAction(
                        title: "Full Screen",
                        input: "f"
                    ) {
                        viewState.containerView?.toggleFullScreen()
                    }

                    // MARK: - Volume

                    KeyCommandAction(
                        title: "Volume Up",
                        input: KeyCommandAction.inputUpArrow
                    ) {
                        adjustVolume(by: 0.05)
                    }

                    KeyCommandAction(
                        title: "Volume Down",
                        input: KeyCommandAction.inputDownArrow
                    ) {
                        adjustVolume(by: -0.05)
                    }

                    // MARK: - Escape

                    KeyCommandAction(
                        title: L10n.close,
                        input: KeyCommandAction.inputEscape
                    ) {
                        if viewState.isScrubbing {
                            viewState.cancelScrub()
                        } else if viewState.containerView?.isFullScreen == true {
                            viewState.containerView?.toggleFullScreen()
                        } else if viewState.isPresentingSupplement {
                            viewState.selectedSupplementID = nil
                        } else {
                            mediaSession.stop()
                            router.dismiss()
                        }
                    }
                    #endif
                }
        }
    }
}
