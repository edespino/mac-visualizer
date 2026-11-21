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

final class ActivePlayerSelectionTests: XCTestCase {
    private let order = ["com.spotify.client", "com.apple.Music"]

    func testPrefersAPlayingPlayer() {
        let snaps = [
            PlayerSnapshot(bundleID: "com.spotify.client", isRunning: true, isPlaying: false),
            PlayerSnapshot(bundleID: "com.apple.Music", isRunning: true, isPlaying: true),
        ]
        XCTAssertEqual(selectActivePlayer(snaps, preferenceOrder: order), "com.apple.Music")
    }

    func testPreferenceOrderBreaksTieAmongPlaying() {
        let snaps = [
            PlayerSnapshot(bundleID: "com.spotify.client", isRunning: true, isPlaying: true),
            PlayerSnapshot(bundleID: "com.apple.Music", isRunning: true, isPlaying: true),
        ]
        XCTAssertEqual(selectActivePlayer(snaps, preferenceOrder: order), "com.spotify.client")
    }

    func testFallsBackToRunningWhenNonePlaying() {
        let snaps = [
            PlayerSnapshot(bundleID: "com.apple.Music", isRunning: true, isPlaying: false),
        ]
        XCTAssertEqual(selectActivePlayer(snaps, preferenceOrder: order), "com.apple.Music")
    }

    func testNilWhenNoneRunning() {
        let snaps = [
            PlayerSnapshot(bundleID: "com.spotify.client", isRunning: false, isPlaying: false),
            PlayerSnapshot(bundleID: "com.apple.Music", isRunning: false, isPlaying: false),
        ]
        XCTAssertNil(selectActivePlayer(snaps, preferenceOrder: order))
    }

    func testIgnoresUnknownBundles() {
        let snaps = [PlayerSnapshot(bundleID: "com.other.app", isRunning: true, isPlaying: true)]
        XCTAssertNil(selectActivePlayer(snaps, preferenceOrder: order))
    }
}