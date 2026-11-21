//
// Copyright 2026 Ed Espino
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
// implied. See the License for the specific language governing
// permissions and limitations under the License.
//

import Foundation
import MacVisualizerCore

/// CLI verification for the lyrics path: reads the active player's track,
/// looks its lyrics up on LRCLIB, and prints what came back. Prints counts
/// and classifications only, never lyric text or the API key. Makes no
/// translation request.
enum LyricsProbe {
    static func run() {
        let order = [PlayerReader.spotifyBundle, PlayerReader.musicBundle]
        let snaps = order.map { PlayerReader.snapshot($0) }
        guard let active = selectActivePlayer(snaps, preferenceOrder: order),
              let info = PlayerReader.track(active) else {
            print("active: none")
            return
        }
        let reportedMs = PlaybackUnits.durationMs(raw: PlayerReader.rawDuration(active) ?? 0, bundleID: active)
        // Same correction the app applies: Spotify trims its reported length under Crossfade.
        var memory = TrackLengthMemory()
        var publishedSeconds: Int?
        var trackID: String?
        if active == PlayerReader.spotifyBundle, let uri = PlayerReader.spotifyTrackURI(),
           let id = SpotifyTrackPage.trackID(fromURI: uri) {
            trackID = id
            let wait = DispatchSemaphore(value: 0)
            Task.detached {
                publishedSeconds = await SpotifyTrackLengthFetcher.durationSeconds(trackID: id)
                wait.signal()
            }
            _ = wait.wait(timeout: .now() + 25)
            if let publishedSeconds { memory.setPublished(id: id, seconds: publishedSeconds) }
        }
        let track = LyricsTrack(
            title: info.title ?? "", artist: info.artist ?? "", album: info.album ?? "",
            durationMs: trackID.map { memory.resolve(id: $0, reportedMs: reportedMs) } ?? reportedMs)
        print("active: \(active)")
        print("  reportedMs: \(reportedMs)  published: \(publishedSeconds.map { "\($0) s" } ?? "n/a")")
        print("  durationMs: \(track.durationMs)  lookupable: \(track.isLookupable)")
        print("  positionMs: \(PlaybackUnits.positionMs(rawSeconds: PlayerReader.rawPlayerPosition(active) ?? 0))")
        print("  cache key:  \(LyricsCacheKey.make(for: track))")
        let cache = LyricsCacheStore(directory: LyricsCacheStore.defaultDirectory())
        print("  cached:     \(cache.read(track) != nil)")
        print("  gemini key: \(GeminiKeyStore(fileURL: GeminiKeyStore.defaultFileURL()).read() != nil ? "set" : "not set")")
        guard track.isLookupable else { return }

        let done = DispatchSemaphore(value: 0)
        Task.detached {
            defer { done.signal() }
            do {
                switch try await LRCLIBClient().fetch(track: track, options: LyricsFetchOptions(allowApproximateMatch: true)) {
                case .synced(let lines, let id, let approximate):
                    let text = lines.map(\.text).joined(separator: "\n")
                    print("  lrclib:     synced\(approximate ? " (approximate)" : ""), \(lines.count) lines, id \(id.map(String.init) ?? "nil")")
                    print("  first/last: \(lines.first?.timeMs ?? 0) ms / \(lines.last?.timeMs ?? 0) ms")
                    print("  english:    \(EnglishLyricsDetector.isEnglish(text))")
                case .plain(let lines, _):
                    print("  lrclib:     plain (unsynced), \(lines.count) lines")
                case .instrumental:
                    print("  lrclib:     instrumental")
                case .none:
                    print("  lrclib:     none")
                }
            } catch {
                print("  lrclib:     error \(error)")
            }
        }
        _ = done.wait(timeout: .now() + 30)
    }
}
