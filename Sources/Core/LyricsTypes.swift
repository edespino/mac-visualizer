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

/// One timed lyric line.
public struct LyricLine: Codable, Equatable {
    public var timeMs: Int
    public var text: String

    public init(timeMs: Int, text: String) {
        self.timeMs = timeMs
        self.text = text
    }
}

/// What the lyrics service returned for a track. `lrclibId` is the LRCLIB
/// numeric id of the entry, kept so a wrong entry can be flagged later.
/// `approximate` on a synced result means the lyrics came from a recording
/// whose length differs from the playing track (a different edit), so the
/// timestamps may drift; it is always false for an exact match.
public enum LyricsResult: Equatable {
    case synced(lines: [LyricLine], lrclibId: Int?, approximate: Bool)
    case plain(lines: [String], lrclibId: Int?)
    case instrumental
    case none
}

/// Per-fetch configuration taken from the user's lyrics settings. A value
/// type so it can cross from the main-actor model into an off-actor fetch.
public struct LyricsFetchOptions: Equatable, Sendable {
    /// A local `.lrc` folder to consult before the remote service; nil or
    /// empty uses only the remote service.
    public var localFolder: String?
    /// Accept a close-but-not-exact-length LRCLIB recording when the exact
    /// length is unavailable.
    public var allowApproximateMatch: Bool

    public init(localFolder: String? = nil, allowApproximateMatch: Bool = false) {
        self.localFolder = localFolder
        self.allowApproximateMatch = allowApproximateMatch
    }
}

/// The identity of a track for lyric lookup and caching.
public struct LyricsTrack: Equatable {
    public var title: String
    public var artist: String
    public var album: String
    public var durationMs: Int

    public init(title: String, artist: String, album: String, durationMs: Int) {
        self.title = title
        self.artist = artist
        self.album = album
        self.durationMs = durationMs
    }

    /// True when there is enough identity to look lyrics up: a title, an
    /// artist, and a known duration. Ads, podcasts and radio streams
    /// usually fail this.
    public var isLookupable: Bool {
        let ws = CharacterSet.whitespacesAndNewlines
        return !title.trimmingCharacters(in: ws).isEmpty
            && !artist.trimmingCharacters(in: ws).isEmpty
            && durationMs > 0
    }
}

/// One poll of the active player. Published whether playing or paused.
public struct PlaybackSnapshot: Equatable {
    public var track: LyricsTrack
    public var positionMs: Int
    public var isPlaying: Bool
    /// Monotonic clock reading (ms) taken when the position was read.
    public var sampledAtMs: Double

    public init(track: LyricsTrack, positionMs: Int, isPlaying: Bool, sampledAtMs: Double) {
        self.track = track
        self.positionMs = positionMs
        self.isPlaying = isPlaying
        self.sampledAtMs = sampledAtMs
    }
}

/// Unit conversion for the raw values the players report over scripting.
public enum PlaybackUnits {
    static let spotifyBundle = "com.spotify.client"

    /// Converts a player's raw track `duration` to milliseconds. Spotify
    /// reports milliseconds (measured: a 3:18 track reported 197961, even
    /// though its scripting dictionary says seconds); Music reports seconds.
    public static func durationMs(raw: Double, bundleID: String) -> Int {
        guard raw.isFinite, raw > 0 else { return 0 }
        return bundleID == spotifyBundle ? Int(raw.rounded()) : Int((raw * 1000).rounded())
    }

    /// Converts a player's raw `player position` (seconds) to milliseconds.
    public static func positionMs(rawSeconds: Double) -> Int {
        guard rawSeconds.isFinite, rawSeconds > 0 else { return 0 }
        return Int((rawSeconds * 1000).rounded())
    }
}
