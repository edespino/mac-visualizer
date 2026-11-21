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

/// One lyrics record as LRCLIB returns it (from `/api/get` or as an
/// element of `/api/search`). Unknown fields are ignored.
public struct LRCLIBRecord: Decodable, Equatable {
    public var id: Int?
    /// Track length in seconds.
    public var duration: Double?
    public var instrumental: Bool?
    public var syncedLyrics: String?
    public var plainLyrics: String?

    public init(id: Int?, duration: Double?, instrumental: Bool?, syncedLyrics: String?, plainLyrics: String?) {
        self.id = id
        self.duration = duration
        self.instrumental = instrumental
        self.syncedLyrics = syncedLyrics
        self.plainLyrics = plainLyrics
    }

    /// True when the record carries timed lyrics that actually parse.
    var hasSyncedLyrics: Bool {
        guard instrumental != true, let synced = syncedLyrics, !synced.isEmpty else { return false }
        return !LRCParser.parse(synced).isEmpty
    }

    /// True when the timed lyrics run past the record's own stated length by
    /// more than `LRCLIBMatch.overrunToleranceMs`: the timings belong to a
    /// longer cut filed under the wrong duration, so every line is shifted.
    /// (Seen on "Audition (The Fools Who Dream)": a 228 s record carrying the
    /// 252 s film version's timings, ~23.5 s late.) A shifted record that
    /// still ends inside the track is not detectable this way.
    public var timingOverrunsDuration: Bool {
        guard let seconds = duration, seconds.isFinite, instrumental != true,
              let synced = syncedLyrics,
              let last = LRCParser.parse(synced).map(\.timeMs).max() else { return false }
        return LRCLIBMatch.linesOverrun(lastLineMs: last, trackDurationMs: Int((seconds * 1000).rounded()))
    }

    /// The record as a lyrics result: instrumental, then synced, then
    /// plain (lines trimmed; blank lines dropped only at the start and
    /// end), else none.
    public var result: LyricsResult {
        if instrumental == true { return .instrumental }
        if let synced = syncedLyrics, !synced.isEmpty {
            let lines = LRCParser.parse(synced)
            if !lines.isEmpty { return .synced(lines: lines, lrclibId: id, approximate: false) }
        }
        if let plain = plainLyrics, !plain.isEmpty {
            var lines = plain.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespaces) }
            while lines.first?.isEmpty == true { lines.removeFirst() }
            while lines.last?.isEmpty == true { lines.removeLast() }
            if !lines.isEmpty { return .plain(lines: lines, lrclibId: id) }
        }
        return .none
    }
}

/// Chooses a record from LRCLIB search results. The exact lookup
/// (`/api/get`) needs title, artist, album and duration to all match, and
/// misses whenever the player's album name differs from LRCLIB's (deluxe
/// editions, compilations, remasters). Search is by title and artist only;
/// this picks the result that is safe to show.
public enum LRCLIBMatch {
    /// Timestamps only line up with the same recording, so a candidate
    /// must be within this many milliseconds of the playing track's length.
    public static let toleranceMs = 3000

    /// Ceiling for an approximate (loose) match: a synced recording farther
    /// than this from the playing track's length is a different recording
    /// (an extended, live or wholly different cut), not a slightly different
    /// master, so it is rejected even when loose matching is on. Generous at
    /// ten times the exact tolerance, which covers remasters and radio edits
    /// while rejecting, say, a 7:00 cut standing in for a 3:20 track.
    public static let looseToleranceMs = 30_000

    /// How far past the track's end a final lyric line may sit before the
    /// timings are judged to belong to a different, longer cut.
    public static let overrunToleranceMs = 5000

    /// True when lyrics whose last line is at `lastLineMs` cannot belong to a
    /// track of `trackDurationMs` (unknown length, <= 0, never overruns).
    public static func linesOverrun(lastLineMs: Int, trackDurationMs: Int) -> Bool {
        trackDurationMs > 0 && lastLineMs > trackDurationMs + overrunToleranceMs
    }

    /// Whether the exact lookup's record can be shown without consulting
    /// search: correctly-timed synced lyrics, or an instrumental.
    public static func exactSuffices(_ exact: LRCLIBRecord?) -> Bool {
        guard let exact else { return false }
        if exact.instrumental == true { return true }
        return exact.hasSyncedLyrics && !exact.timingOverrunsDuration
    }

    /// The result to show once search has been consulted. A synced search
    /// result wins; otherwise the exact record stands, with a mis-timed one
    /// stamped approximate so the UI flags it (wrong timing beats no lyrics,
    /// but it must not pass as an exact match).
    public static func resolve(exact: LRCLIBRecord?, searched: LyricsResult) -> LyricsResult {
        if case .synced = searched { return searched }
        guard let exact else { return searched }
        let exactResult = exact.result
        if case .none = exactResult { return searched }
        if exact.timingOverrunsDuration { return Choice(record: exact, approximate: true).result }
        return exactResult
    }

    /// A chosen record plus whether it is an approximate (out-of-tolerance)
    /// match: a different-length recording whose timestamps may drift.
    public struct Choice: Equatable {
        public var record: LRCLIBRecord
        public var approximate: Bool

        public init(record: LRCLIBRecord, approximate: Bool) {
            self.record = record
            self.approximate = approximate
        }

        /// The chosen record as a lyrics result, stamping `approximate`
        /// onto a synced result (it is meaningless for plain/instrumental).
        public var result: LyricsResult {
            let base = record.result
            if case .synced(let lines, let id, _) = base {
                return .synced(lines: lines, lrclibId: id, approximate: approximate)
            }
            return base
        }
    }

    /// The record closest in duration to the playing track. Within
    /// tolerance it is an exact match (synced preferred over unsynced; ties
    /// keep the service's order). When nothing synced is within tolerance
    /// and `allowLoose` is set, the closest synced recording of any length
    /// is returned marked approximate — this is how a song LRCLIB only has
    /// under a different edit still shows. An out-of-tolerance synced match
    /// is preferred over an exact unsynced one, since only synced lyrics
    /// scroll.
    public static func best(_ records: [LRCLIBRecord], durationMs: Int,
                            allowLoose: Bool = false) -> Choice? {
        func closest(_ candidates: [LRCLIBRecord]) -> (record: LRCLIBRecord, delta: Double)? {
            var best: (record: LRCLIBRecord, delta: Double)?
            for record in candidates {
                guard let seconds = record.duration, seconds.isFinite else { continue }
                let delta = abs(seconds * 1000 - Double(durationMs))
                if best == nil || delta < best!.delta { best = (record, delta) }
            }
            return best
        }
        // A record whose timings overrun its own length is mis-timed: never a match.
        let synced = closest(records.filter { $0.hasSyncedLyrics && !$0.timingOverrunsDuration })
        if let synced, synced.delta <= Double(toleranceMs) {
            return Choice(record: synced.record, approximate: false)
        }
        if allowLoose, let synced, synced.delta <= Double(looseToleranceMs) {
            return Choice(record: synced.record, approximate: true)
        }
        if let unsynced = closest(records.filter { !$0.hasSyncedLyrics }),
           unsynced.delta <= Double(toleranceMs) {
            return Choice(record: unsynced.record, approximate: false)
        }
        return nil
    }
}
