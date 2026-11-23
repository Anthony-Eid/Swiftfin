# Plan

Status of each milestone from the brief, what is left, and how each piece is checked. `REPORT.md` has the results.

## Milestone 1: native macOS target (done)

- Branch `macos-port` from `origin/main`, with `ComicBit/feature/macos-port` merged as a reference and conflicts resolved to main.
- The "Swiftfin macOS" target is generated into main's project by `Tools/macOS/add_macos_target.py`.
- Checked by building with `Tools/macOS/build.sh` and driving the app against the demo server.

Left to exercise: TV shows and episodes, search, the TV guide, admin and editor screens, subtitles, the AVPlayer backend,
picture-in-picture, multiple windows, the Release configuration.

## Milestone 2: offline downloads (in progress)

| Task | How it is checked |
| --- | --- |
| `DownloadRecord` JSON files and media under Application Support (no CoreStore) | Files on disk after a download |
| Background `URLSession` queue with progress, pause, resume, cancel, delete | Download a short demo item in the app |
| Download quality: original or a bitrate transcoded by the server | 2 Mbps download of a demo film (done, file not yet played) |
| Text subtitles as files next to the media | Needs a server with subtitles; the demo has none |
| Original file from `/Items/{id}/Download`, static stream when the policy forbids it | The demo user has downloading disabled, so the fallback is the path tested |
| Offline metadata and artwork | Downloads screen renders with the network blocked |
| Offline playback with resume position | Play the local file with the network blocked |
| Progress recorded offline and sent when back online | Resume position on the server after reconnecting |
| Download button on movie, episode, season and series pages | Screenshots |
| Downloads screen with storage used and delete | Screenshots |
| Downloaded badge on posters | Screenshots |

Risks:

- A background session may not work in a sandboxed, ad-hoc signed app. The session configuration is a single switch.
- The app may not reach the signed-in screens when the server is unreachable at launch.
- The demo server cannot test the real download endpoint.
- Resume data, network retry, subtitle files and the free-space check were written without a compiler and have not been built.

## Milestone 3: Mac polish (not started)

Menu bar commands, window restoration and downloads on iOS, only once milestone 2 is verified.
