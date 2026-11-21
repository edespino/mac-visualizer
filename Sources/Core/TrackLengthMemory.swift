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

/// Remembers each track's true length. Spotify's scripted `duration` is the
/// length it will actually PLAY: with Crossfade on, a song queued into another
/// reports its length minus the blend (measured: 228.267 s true, 216.267 s
/// with a 12 s crossfade, 205.185 s inside a playlist), and the value can
/// change mid-song. Lyrics are matched by length, so a trimmed report picks a
/// record for a different cut. Trimming only ever shortens, so the longest
/// report seen is the best local estimate; the length published on the
/// track's public page corrects a song only ever seen trimmed.
public struct TrackLengthMemory {
    /// A published length (whole seconds) replaces the longest report only
    /// when it is clearly longer: within this margin the report is the same
    /// length at millisecond precision.
    static let publishedMarginMs = 1500
    /// Entries kept before the memory is cleared (a long session's bound).
    static let capacity = 2000

    private var longestMs: [String: Int] = [:]
    private var publishedMs: [String: Int] = [:]

    public init() {}

    /// Records `reportedMs` for the track and returns the length to use.
    public mutating func resolve(id: String, reportedMs: Int) -> Int {
        if longestMs.count >= Self.capacity, longestMs[id] == nil { longestMs.removeAll() }
        let longest = max(longestMs[id] ?? 0, reportedMs)
        longestMs[id] = longest
        if let published = publishedMs[id], published > longest + Self.publishedMarginMs { return published }
        return longest
    }

    /// Stores the length published for the track (ignored unless positive).
    public mutating func setPublished(id: String, seconds: Int) {
        guard seconds > 0 else { return }
        if publishedMs.count >= Self.capacity, publishedMs[id] == nil { publishedMs.removeAll() }
        publishedMs[id] = seconds * 1000
    }

    public func hasPublished(id: String) -> Bool { publishedMs[id] != nil }
}

/// Pure helpers for reading a track's length off its public Spotify page
/// (`https://open.spotify.com/track/<id>`), which carries
/// `<meta name="music:duration" content="228"/>` near the top.
public enum SpotifyTrackPage {
    /// The bare track id from a `spotify:track:<id>` URI, or nil for anything
    /// else (episodes, local files) or an id that is not plain base-62.
    public static func trackID(fromURI uri: String) -> String? {
        let prefix = "spotify:track:"
        guard uri.hasPrefix(prefix) else { return nil }
        let id = String(uri.dropFirst(prefix.count))
        guard (16...32).contains(id.count),
              id.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.contains($0) }) else { return nil }
        return id
    }

    public static func url(forTrackID id: String) -> URL? {
        URL(string: "https://open.spotify.com/track/\(id)")
    }

    /// The published length in whole seconds, or nil when absent/invalid.
    public static func durationSeconds(inHTML html: String) -> Int? {
        guard let marker = html.range(of: "music:duration\" content=\"") else { return nil }
        let digits = html[marker.upperBound...].prefix { $0.isNumber }
        guard let seconds = Int(digits), seconds > 0 else { return nil }
        return seconds
    }
}
