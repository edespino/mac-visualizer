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

final class LyricsSettingsTests: XCTestCase {
    func testDefaults() {
        let d = LyricsSettings.defaults
        XCTAssertTrue(d.enabled)
        XCTAssertEqual(d.textSize, 28)
        XCTAssertEqual(d.blockWidthFraction, 0.8)
        XCTAssertEqual(d.activeLinePosition, 0.15)
        XCTAssertEqual(d.activeColor.r, 0.290, accuracy: 0.001)
        XCTAssertEqual(d.activeColor.g, 0.871, accuracy: 0.001)
        XCTAssertEqual(d.activeColor.b, 0.502, accuracy: 0.001)
        XCTAssertEqual(d.activeColor.a, 1)
        XCTAssertEqual(d.otherColor, RGBAColor(r: 1, g: 1, b: 1, a: 1))
        XCTAssertEqual(d.otherOpacity, 0.45)
        XCTAssertEqual(d.pastMode, .dim)
        XCTAssertTrue(d.shadowEnabled)
        XCTAssertEqual(d.shadowColor, RGBAColor(r: 0, g: 0, b: 0, a: 1))
        XCTAssertEqual(d.shadowOpacity, 0.8)
        XCTAssertEqual(d.shadowRadius, 4)
        XCTAssertEqual(d.shadowOffsetX, 0)
        XCTAssertEqual(d.shadowOffsetY, 2)
        XCTAssertEqual(d.geminiModel, "gemini-flash-lite-latest")
        XCTAssertTrue(d.acceptApproximateMatches)
        XCTAssertEqual(d.timingOffsetMs, 0)
        XCTAssertEqual(d.localLyricsFolder, "")
    }

    func testSourceFieldsLegacyJSONFillsDefaults() throws {
        let legacy = try JSONDecoder().decode(LyricsSettings.self, from: Data(#"{"enabled":true}"#.utf8))
        XCTAssertTrue(legacy.acceptApproximateMatches)
        XCTAssertEqual(legacy.timingOffsetMs, 0)
        XCTAssertEqual(legacy.localLyricsFolder, "")
        XCTAssertEqual(legacy.activeLinePosition, 0.15)
    }

    func testActiveLinePositionClampsToUnitRange() throws {
        let high = try JSONDecoder().decode(LyricsSettings.self, from: Data(#"{"activeLinePosition":1.5}"#.utf8))
        XCTAssertEqual(high.activeLinePosition, 1)
        let low = try JSONDecoder().decode(LyricsSettings.self, from: Data(#"{"activeLinePosition":-0.2}"#.utf8))
        XCTAssertEqual(low.activeLinePosition, 0)
    }

    func testOpacityPerPhase() {
        var s = LyricsSettings.defaults
        s.otherOpacity = 0.45
        XCTAssertEqual(s.opacity(for: .active), 1.0, accuracy: 0.0001)
        XCTAssertEqual(s.opacity(for: .upcoming), 0.45, accuracy: 0.0001)
        s.pastMode = .dim
        XCTAssertEqual(s.opacity(for: .past), 0.315, accuracy: 0.0001)
        s.pastMode = .bright
        XCTAssertEqual(s.opacity(for: .past), 0.6525, accuracy: 0.0001)
        s.pastMode = .neutral
        XCTAssertEqual(s.opacity(for: .past), 0.45, accuracy: 0.0001)
        s.otherOpacity = 0.9
        s.pastMode = .bright
        XCTAssertEqual(s.opacity(for: .past), 1.0, accuracy: 0.0001)
    }

    func testFadeLinesDefault() {
        XCTAssertEqual(LyricsSettings.defaults.fadeLines, 3)
    }

    func testOpacityFadesWithDistance() {
        var s = LyricsSettings.defaults
        s.otherOpacity = 0.8
        s.pastMode = .neutral
        s.fadeLines = 4
        // The active line is never faded.
        XCTAssertEqual(s.opacity(for: .active, distance: 0), 1.0, accuracy: 0.0001)
        // The nearest line keeps the full other-lines opacity, then it
        // falls off evenly and reaches zero one line past the range.
        XCTAssertEqual(s.opacity(for: .upcoming, distance: 1), 0.8, accuracy: 0.0001)
        XCTAssertEqual(s.opacity(for: .upcoming, distance: 2), 0.6, accuracy: 0.0001)
        XCTAssertEqual(s.opacity(for: .upcoming, distance: 3), 0.4, accuracy: 0.0001)
        XCTAssertEqual(s.opacity(for: .upcoming, distance: 4), 0.2, accuracy: 0.0001)
        XCTAssertEqual(s.opacity(for: .upcoming, distance: 5), 0.0, accuracy: 0.0001)
        XCTAssertEqual(s.opacity(for: .upcoming, distance: 50), 0.0, accuracy: 0.0001)
        // Past lines fade the same way, on top of the past-line treatment.
        XCTAssertEqual(s.opacity(for: .past, distance: 3), 0.4, accuracy: 0.0001)
        s.pastMode = .dim
        XCTAssertEqual(s.opacity(for: .past, distance: 1), 0.56, accuracy: 0.0001)
        XCTAssertEqual(s.opacity(for: .past, distance: 3), 0.28, accuracy: 0.0001)
    }

    func testFadeLinesZeroDisablesDistanceFade() {
        var s = LyricsSettings.defaults
        s.fadeLines = 0
        XCTAssertEqual(s.opacity(for: .upcoming, distance: 1), s.opacity(for: .upcoming), accuracy: 0.0001)
        XCTAssertEqual(s.opacity(for: .upcoming, distance: 40), s.opacity(for: .upcoming), accuracy: 0.0001)
        XCTAssertEqual(s.opacity(for: .past, distance: 40), s.opacity(for: .past), accuracy: 0.0001)
    }

    func testFadeLinesOneShowsOnlyNeighbors() {
        var s = LyricsSettings.defaults
        s.fadeLines = 1
        XCTAssertEqual(s.opacity(for: .upcoming, distance: 1), s.opacity(for: .upcoming), accuracy: 0.0001)
        XCTAssertEqual(s.opacity(for: .upcoming, distance: 2), 0, accuracy: 0.0001)
    }

    func testFadeLinesLegacyAndBadValues() throws {
        let legacy = try JSONDecoder().decode(LyricsSettings.self, from: Data(#"{"enabled":true}"#.utf8))
        XCTAssertEqual(legacy.fadeLines, 3)
        let negative = try JSONDecoder().decode(LyricsSettings.self, from: Data(#"{"fadeLines":-3}"#.utf8))
        XCTAssertEqual(negative.fadeLines, 0)
    }

    func testRoundTrip() throws {
        var s = LyricsSettings.defaults
        s.enabled = true
        s.textSize = 40
        s.blockWidthFraction = 0.5
        s.activeLinePosition = 0.3
        s.activeColor = RGBAColor(r: 0.1, g: 0.2, b: 0.3, a: 1)
        s.otherColor = RGBAColor(r: 0.4, g: 0.5, b: 0.6, a: 1)
        s.otherOpacity = 0.7
        s.pastMode = .bright
        s.shadowEnabled = false
        s.shadowColor = RGBAColor(r: 0.9, g: 0.8, b: 0.7, a: 1)
        s.shadowOpacity = 0.3
        s.shadowRadius = 9
        s.shadowOffsetX = -3
        s.shadowOffsetY = 5
        s.geminiModel = "some-model"
        s.fadeLines = 7
        s.acceptApproximateMatches = false
        s.timingOffsetMs = -1500
        s.localLyricsFolder = "/Users/x/Lyrics"
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(LyricsSettings.self, from: data), s)
    }

    func testPartialJSONFillsDefaults() throws {
        let data = #"{"enabled":true}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(LyricsSettings.self, from: data)
        var expected = LyricsSettings.defaults
        expected.enabled = true
        XCTAssertEqual(s, expected)
    }

    func testEmptyModelFallsBack() throws {
        let data = #"{"geminiModel":""}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(LyricsSettings.self, from: data)
        XCTAssertEqual(s.geminiModel, "gemini-flash-lite-latest")
    }

    func testVisualizerSettingsLegacyJSONWithoutLyrics() throws {
        let data = try JSONEncoder().encode(VisualizerSettings.defaults)
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(obj.removeValue(forKey: "lyrics"))
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let back = try JSONDecoder().decode(VisualizerSettings.self, from: stripped)
        XCTAssertEqual(back.lyrics, .defaults)
        XCTAssertEqual(back, .defaults)
    }

    func testVisualizerSettingsRoundTripsLyrics() throws {
        var s = VisualizerSettings.defaults
        s.lyrics.enabled = true
        s.lyrics.textSize = 40
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(back, s)
        XCTAssertTrue(back.lyrics.enabled)
        XCTAssertEqual(back.lyrics.textSize, 40)
    }

    func testBeatBounceFieldsRoundTrip() throws {
        var s = LyricsSettings.defaults
        s.beatBounceMode = .lift
        s.beatBounceStrength = 2.0
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(LyricsSettings.self, from: data)
        XCTAssertEqual(back.beatBounceMode, .lift)
        XCTAssertEqual(back.beatBounceStrength, 2.0)
        XCTAssertEqual(back, s)
    }

    func testLegacyJSONWithoutBeatBounceDefaults() throws {
        let legacy = try JSONDecoder().decode(LyricsSettings.self, from: Data(#"{"enabled":true}"#.utf8))
        XCTAssertEqual(legacy.beatBounceMode, .both)
        XCTAssertEqual(legacy.beatBounceStrength, 1.0)
    }
}
