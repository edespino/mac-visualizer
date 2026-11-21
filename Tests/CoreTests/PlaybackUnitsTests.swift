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

final class PlaybackUnitsTests: XCTestCase {
    private let spotify = "com.spotify.client"
    private let music = "com.apple.Music"

    func testSpotifyDurationIsAlreadyMilliseconds() {
        // Measured with --nowplaying-probe: a 3:18 track reported 197961.
        XCTAssertEqual(PlaybackUnits.durationMs(raw: 197_961, bundleID: spotify), 197_961)
    }

    func testMusicDurationIsSeconds() {
        XCTAssertEqual(PlaybackUnits.durationMs(raw: 245.3, bundleID: music), 245_300)
    }

    func testUnknownPlayerIsTreatedAsSeconds() {
        XCTAssertEqual(PlaybackUnits.durationMs(raw: 10, bundleID: "com.example.other"), 10_000)
    }

    func testPositionIsSeconds() {
        XCTAssertEqual(PlaybackUnits.positionMs(rawSeconds: 12.5), 12_500)
        XCTAssertEqual(PlaybackUnits.positionMs(rawSeconds: 117.9420013427734), 117_942)
    }

    func testBadValuesAreZero() {
        XCTAssertEqual(PlaybackUnits.durationMs(raw: -5, bundleID: music), 0)
        XCTAssertEqual(PlaybackUnits.durationMs(raw: .nan, bundleID: spotify), 0)
        XCTAssertEqual(PlaybackUnits.durationMs(raw: .infinity, bundleID: music), 0)
        XCTAssertEqual(PlaybackUnits.positionMs(rawSeconds: -1), 0)
        XCTAssertEqual(PlaybackUnits.positionMs(rawSeconds: .nan), 0)
    }
}
