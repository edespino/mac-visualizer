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

final class PlaybackPositionTrackerTests: XCTestCase {
    func testNoDataIsZero() {
        XCTAssertEqual(PlaybackPositionTracker().position(atMs: 5000), 0)
    }

    func testInterpolatesForwardWhilePlaying() {
        var t = PlaybackPositionTracker()
        t.update(polledPositionMs: 10000, isPlaying: true, nowMs: 1000)
        XCTAssertEqual(t.position(atMs: 1000), 10000)
        XCTAssertEqual(t.position(atMs: 2500), 11500)
    }

    func testDoesNotAdvanceWhilePaused() {
        var t = PlaybackPositionTracker()
        t.update(polledPositionMs: 10000, isPlaying: false, nowMs: 1000)
        XCTAssertEqual(t.position(atMs: 5000), 10000)
    }

    func testKeepsInterpolationWhenPollAgreesWithinThreshold() {
        var t = PlaybackPositionTracker()
        t.update(polledPositionMs: 10000, isPlaying: true, nowMs: 0)
        t.update(polledPositionMs: 12000, isPlaying: true, nowMs: 3000)
        XCTAssertEqual(t.position(atMs: 3000), 13000)
    }

    func testSnapsOnSeek() {
        var t = PlaybackPositionTracker()
        t.update(polledPositionMs: 10000, isPlaying: true, nowMs: 0)
        t.update(polledPositionMs: 60000, isPlaying: true, nowMs: 3000)
        XCTAssertEqual(t.position(atMs: 3000), 60000)
        XCTAssertEqual(t.position(atMs: 4000), 61000)
    }

    func testSnapsBackwardSeeks() {
        var t = PlaybackPositionTracker()
        t.update(polledPositionMs: 60000, isPlaying: true, nowMs: 0)
        t.update(polledPositionMs: 5000, isPlaying: true, nowMs: 1000)
        XCTAssertEqual(t.position(atMs: 1000), 5000)
    }

    func testSnapsOnPlayPauseChange() {
        var t = PlaybackPositionTracker()
        t.update(polledPositionMs: 10000, isPlaying: true, nowMs: 0)
        t.update(polledPositionMs: 10500, isPlaying: false, nowMs: 1000)
        XCTAssertEqual(t.position(atMs: 9999), 10500)
        t.update(polledPositionMs: 10500, isPlaying: true, nowMs: 20000)
        XCTAssertEqual(t.position(atMs: 21000), 11500)
    }

    func testReset() {
        var t = PlaybackPositionTracker()
        t.update(polledPositionMs: 10000, isPlaying: true, nowMs: 0)
        t.reset()
        XCTAssertEqual(t.position(atMs: 5000), 0)
    }
}
