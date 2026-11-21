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

final class TargetProcessSelectionTests: XCTestCase {
    private let spotify = "com.spotify.client"
    private let music = "com.apple.Music"

    /// Both players running → BOTH ids are tapped, so a switch between them
    /// needs no re-selection: whichever is playing is already in the mixdown.
    func testBothRunningReturnsBothIDs() {
        let running = [
            AudioProcessInfo(id: 11, bundleID: spotify),
            AudioProcessInfo(id: 22, bundleID: music),
        ]
        let ids = TargetProcessSelection.select(from: running, wanted: [spotify, music])
        XCTAssertEqual(ids, [11, 22])
    }

    /// Only one player running → only that id.
    func testOnlyMusicRunningReturnsMusicID() {
        let running = [
            AudioProcessInfo(id: 99, bundleID: "com.apple.Safari"),
            AudioProcessInfo(id: 22, bundleID: music),
        ]
        let ids = TargetProcessSelection.select(from: running, wanted: [spotify, music])
        XCTAssertEqual(ids, [22])
    }

    /// No target running → empty, so the caller parks in `.noTargetProcess`.
    func testNoTargetRunningReturnsEmpty() {
        let running = [AudioProcessInfo(id: 99, bundleID: "com.apple.Safari")]
        let ids = TargetProcessSelection.select(from: running, wanted: [spotify, music])
        XCTAssertTrue(ids.isEmpty)
    }

    /// Order follows `wanted`'s priority regardless of discovery order, so the
    /// built id set is deterministic for change comparison and logging.
    func testOrderFollowsWantedPriorityNotDiscoveryOrder() {
        let running = [
            AudioProcessInfo(id: 22, bundleID: music),
            AudioProcessInfo(id: 11, bundleID: spotify),
        ]
        let ids = TargetProcessSelection.select(from: running, wanted: [spotify, music])
        XCTAssertEqual(ids, [11, 22])
    }

    /// Non-target processes are ignored even when they share nothing with the
    /// wanted list, so unrelated audio apps never widen the tap.
    func testIgnoresNonTargetProcesses() {
        let running = [
            AudioProcessInfo(id: 1, bundleID: "com.apple.Safari"),
            AudioProcessInfo(id: 2, bundleID: "us.zoom.xos"),
            AudioProcessInfo(id: 11, bundleID: spotify),
        ]
        let ids = TargetProcessSelection.select(from: running, wanted: [spotify, music])
        XCTAssertEqual(ids, [11])
    }

    /// Two processes sharing a target bundle id (helper + main) are both tapped.
    func testMultipleProcessesForOneBundleAreAllIncluded() {
        let running = [
            AudioProcessInfo(id: 11, bundleID: spotify),
            AudioProcessInfo(id: 12, bundleID: spotify),
        ]
        let ids = TargetProcessSelection.select(from: running, wanted: [spotify, music])
        XCTAssertEqual(ids, [11, 12])
    }
}
