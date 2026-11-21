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

import XCTest
@testable import MacVisualizerCore

final class LRCLIBMatchTests: XCTestCase {
    private func rec(_ id: Int, _ duration: Double?, synced: String? = "[00:01.00]hola", plain: String? = "hola",
                     instrumental: Bool = false) -> LRCLIBRecord {
        LRCLIBRecord(id: id, duration: duration, instrumental: instrumental, syncedLyrics: synced, plainLyrics: plain)
    }

    // MARK: record -> result

    func testSyncedRecordGivesSyncedResult() {
        XCTAssertEqual(rec(7, 200).result, .synced(lines: [LyricLine(timeMs: 1000, text: "hola")], lrclibId: 7, approximate: false))
    }

    func testInstrumentalWins() {
        XCTAssertEqual(rec(7, 200, instrumental: true).result, .instrumental)
    }

    func testPlainOnlyGivesPlainTrimmedAtTheEnds() {
        let r = rec(7, 200, synced: nil, plain: "\n  a  \n\nb\n\n")
        XCTAssertEqual(r.result, .plain(lines: ["a", "", "b"], lrclibId: 7))
    }

    func testUnparseableSyncedFallsBackToPlain() {
        XCTAssertEqual(rec(7, 200, synced: "no timestamps", plain: "a").result, .plain(lines: ["a"], lrclibId: 7))
    }

    func testEmptyRecordGivesNone() {
        XCTAssertEqual(rec(7, 200, synced: nil, plain: nil).result, LyricsResult.none)
        XCTAssertEqual(rec(7, 200, synced: "", plain: "").result, LyricsResult.none)
    }

    func testDecodesServiceJSON() throws {
        let json = #"[{"id":5,"trackName":"x","duration":229.0,"instrumental":false,"plainLyrics":"a","syncedLyrics":"[00:02.00]a","extra":1},{"id":6}]"#
        let records = try JSONDecoder().decode([LRCLIBRecord].self, from: Data(json.utf8))
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].id, 5)
        XCTAssertEqual(records[0].duration, 229)
        XCTAssertNil(records[1].duration)
        XCTAssertEqual(records[1].result, LyricsResult.none)
    }

    // MARK: choosing a search result

    func testPicksSyncedRecordClosestInDuration() {
        let best = LRCLIBMatch.best([rec(1, 240), rec(2, 282), rec(3, 230), rec(4, 229)], durationMs: 229_400)
        XCTAssertEqual(best?.record.id, 4)
        XCTAssertEqual(best?.approximate, false)
    }

    func testIgnoresRecordsOutsideTolerance() {
        // A different edit of the song: its timestamps would not line up.
        XCTAssertNil(LRCLIBMatch.best([rec(1, 240), rec(2, 282)], durationMs: 229_000))
        XCTAssertEqual(LRCLIBMatch.best([rec(1, 232)], durationMs: 229_000)?.record.id, 1)
        XCTAssertNil(LRCLIBMatch.best([rec(1, 232.5)], durationMs: 229_000))
    }

    func testPrefersSyncedOverCloserPlain() {
        let best = LRCLIBMatch.best([rec(1, 229, synced: nil), rec(2, 231)], durationMs: 229_000)
        XCTAssertEqual(best?.record.id, 2)
    }

    func testFallsBackToUnsyncedWhenNoSyncedMatches() {
        let best = LRCLIBMatch.best([rec(1, 229, synced: nil), rec(2, 260)], durationMs: 229_000)
        XCTAssertEqual(best?.record.id, 1)
        XCTAssertEqual(best?.approximate, false)
    }

    func testIgnoresRecordsWithoutDurationAndEmptyInput() {
        XCTAssertNil(LRCLIBMatch.best([rec(1, nil)], durationMs: 229_000))
        XCTAssertNil(LRCLIBMatch.best([], durationMs: 229_000))
    }

    func testTieKeepsServiceOrder() {
        XCTAssertEqual(LRCLIBMatch.best([rec(1, 229), rec(2, 229)], durationMs: 229_000)?.record.id, 1)
    }

    // MARK: approximate (loose) matching

    func testLooseOffStillRejectsOutsideTolerance() {
        XCTAssertNil(LRCLIBMatch.best([rec(1, 255)], durationMs: 240_000, allowLoose: false))
    }

    func testLooseAcceptsClosestSyncedOutsideTolerance() {
        // The only recording LRCLIB has is 15 s longer: a different edit.
        let best = LRCLIBMatch.best([rec(1, 255), rec(2, 270)], durationMs: 240_000, allowLoose: true)
        XCTAssertEqual(best?.record.id, 1)
        XCTAssertEqual(best?.approximate, true)
    }

    func testLooseStillPrefersAnExactMatchWhenPresent() {
        let best = LRCLIBMatch.best([rec(1, 255), rec(2, 241)], durationMs: 240_000, allowLoose: true)
        XCTAssertEqual(best?.record.id, 2)
        XCTAssertEqual(best?.approximate, false)
    }

    func testLoosePrefersOutOfToleranceSyncedOverExactPlain() {
        // Only synced lyrics scroll, so a loose synced beats an exact plain.
        let best = LRCLIBMatch.best([rec(1, 240, synced: nil), rec(2, 255)], durationMs: 240_000, allowLoose: true)
        XCTAssertEqual(best?.record.id, 2)
        XCTAssertEqual(best?.approximate, true)
    }

    func testLooseRejectsWildlyDifferentLength() {
        // A 7:00 synced entry for a 3:20 track is a different recording.
        XCTAssertNil(LRCLIBMatch.best([rec(1, 420)], durationMs: 200_000, allowLoose: true))
    }

    func testLooseAcceptsWithinLooseCeiling() {
        // 28 s over is a plausible alternate master, inside the 30 s ceiling.
        let best = LRCLIBMatch.best([rec(1, 228)], durationMs: 200_000, allowLoose: true)
        XCTAssertEqual(best?.record.id, 1)
        XCTAssertEqual(best?.approximate, true)
    }

    func testChoiceResultStampsApproximateOntoSynced() {
        let best = LRCLIBMatch.best([rec(5, 255)], durationMs: 240_000, allowLoose: true)
        XCTAssertEqual(best?.result, .synced(lines: [LyricLine(timeMs: 1000, text: "hola")], lrclibId: 5, approximate: true))
    }

    // MARK: mis-timed records ("Audition (The Fools Who Dream)", 228.266 s)
    //
    // LRCLIB's exact match for this song (id 324617) is labelled 228 s but
    // carries the 252 s film version's timings: every line is ~23.5 s late
    // and the last one lands at 248.7 s, past the end of the track. A correct
    // 228 s record (id 7672077) also exists. Timestamps are the real ones;
    // the text is a placeholder.

    private static let auditionMs = 228_266
    private static let goodTimes: [Double] = [0.7, 3.4, 10.3, 22.1, 25.6, 31.9, 42.6, 121.0, 204.2, 217.4, 225.2]
    private static let lateTimes: [Double] = [24.1, 27.2, 33.3, 46.0, 49.0, 55.8, 64.1, 144.4, 227.3, 240.9, 248.7]

    private func lrc(_ seconds: [Double]) -> String {
        seconds.map { t in
            String(format: "[%02d:%05.2f]line", Int(t) / 60, t - Double(Int(t) / 60 * 60))
        }.joined(separator: "\n")
    }
    private var auditionGood: LRCLIBRecord { rec(7_672_077, 228, synced: lrc(Self.goodTimes)) }
    private var auditionLate: LRCLIBRecord { rec(324_617, 228, synced: lrc(Self.lateTimes)) }

    func testRecordWhoseTimingsRunPastItsOwnDurationIsMistimed() {
        XCTAssertTrue(auditionLate.timingOverrunsDuration)
        XCTAssertFalse(auditionGood.timingOverrunsDuration)
    }

    func testLastLineSlightlyPastDurationIsNotMistimed() {
        // A final line a few seconds past a rounded duration is normal.
        XCTAssertFalse(rec(1, 228, synced: lrc([10, 231.5])).timingOverrunsDuration)
        XCTAssertTrue(rec(1, 228, synced: lrc([10, 234])).timingOverrunsDuration)
    }

    func testRecordWithoutDurationOrSyncedLyricsIsNotMistimed() {
        XCTAssertFalse(rec(1, nil, synced: lrc(Self.lateTimes)).timingOverrunsDuration)
        XCTAssertFalse(rec(1, 228, synced: nil).timingOverrunsDuration)
    }

    func testBestSkipsMistimedRecordForOneThatFits() {
        // Service order puts the mis-timed record first; both are 228 s.
        let best = LRCLIBMatch.best([auditionLate, auditionGood], durationMs: Self.auditionMs)
        XCTAssertEqual(best?.record.id, 7_672_077)
        XCTAssertEqual(best?.approximate, false)
    }

    func testExactLookupThatIsMistimedDoesNotSuffice() {
        XCTAssertFalse(LRCLIBMatch.exactSuffices(auditionLate))
        XCTAssertTrue(LRCLIBMatch.exactSuffices(auditionGood))
        XCTAssertTrue(LRCLIBMatch.exactSuffices(rec(1, 228, instrumental: true)))
        XCTAssertFalse(LRCLIBMatch.exactSuffices(rec(1, 228, synced: nil)))
        XCTAssertFalse(LRCLIBMatch.exactSuffices(nil))
    }

    func testResolvePrefersSearchedSyncedOverMistimedExact() {
        let searched = LRCLIBMatch.best([auditionLate, auditionGood], durationMs: Self.auditionMs)?.result ?? .none
        guard case .synced(let lines, let id, let approximate) =
            LRCLIBMatch.resolve(exact: auditionLate, searched: searched) else { return XCTFail("expected synced") }
        XCTAssertEqual(id, 7_672_077)
        XCTAssertFalse(approximate)
        XCTAssertEqual(lines.first?.timeMs, 700)
    }

    func testResolveKeepsMistimedExactMarkedApproximateWhenNothingBetter() {
        guard case .synced(_, let id, let approximate) =
            LRCLIBMatch.resolve(exact: auditionLate, searched: .none) else { return XCTFail("expected synced") }
        XCTAssertEqual(id, 324_617)
        XCTAssertTrue(approximate)
    }

    func testResolveKeepsExactPlainWhenSearchFindsNothingSynced() {
        let plain = rec(9, 228, synced: nil, plain: "hola")
        XCTAssertEqual(LRCLIBMatch.resolve(exact: plain, searched: .none), plain.result)
        XCTAssertEqual(LRCLIBMatch.resolve(exact: nil, searched: .none), LyricsResult.none)
    }

    func testCachedLinesPastTrackEndAreMistimed() {
        XCTAssertTrue(LRCLIBMatch.linesOverrun(lastLineMs: 248_700, trackDurationMs: Self.auditionMs))
        XCTAssertFalse(LRCLIBMatch.linesOverrun(lastLineMs: 225_200, trackDurationMs: Self.auditionMs))
        XCTAssertFalse(LRCLIBMatch.linesOverrun(lastLineMs: 248_700, trackDurationMs: 0))   // unknown length
    }
}
