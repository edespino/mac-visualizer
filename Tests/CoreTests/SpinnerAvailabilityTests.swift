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
import simd
import XCTest
@testable import MacVisualizerCore

// The Spinner is unavailable (treated like a disabled style) before macOS 15.
final class SpinnerAvailabilityTests: XCTestCase {
    private var saved: (() -> Bool)!
    override func setUp() { saved = VisualizerStyle.spinnerOSCheck }
    override func tearDown() { VisualizerStyle.spinnerOSCheck = saved }

    func testAvailabilityFollowsHook() {
        VisualizerStyle.spinnerOSCheck = { false }
        XCTAssertFalse(VisualizerStyle.spinner.isAvailable)
        XCTAssertTrue(VisualizerStyle.bars.isAvailable)
        XCTAssertEqual(VisualizerStyle.availableCases.count, VisualizerStyle.allCases.count - 1)
        VisualizerStyle.spinnerOSCheck = { true }
        XCTAssertTrue(VisualizerStyle.spinner.isAvailable)
        XCTAssertEqual(VisualizerStyle.availableCases, VisualizerStyle.allCases)
    }

    func testUnavailableSpinnerAbsentFromCyclingBothDirectionsAndWrap() {
        VisualizerStyle.spinnerOSCheck = { false }
        let s = VisualizerSettings.defaults
        XCTAssertFalse(s.enabledStyles.contains(.spinner))
        XCTAssertEqual(s.enabledStyles.count, VisualizerStyle.allCases.count - 1)
        var cur = VisualizerStyle.bars
        var seen: [VisualizerStyle] = []
        for _ in 0..<s.enabledStyles.count { cur = s.nextEnabledStyle(after: cur); seen.append(cur) }
        XCTAssertFalse(seen.contains(.spinner))
        XCTAssertEqual(Set(seen).count, s.enabledStyles.count)
        // wrap: the style before spinner's neighbour
        XCTAssertEqual(s.nextEnabledStyle(after: .musicalSpectrum), .bars)
        XCTAssertEqual(s.previousEnabledStyle(before: .bars), .musicalSpectrum)
        XCTAssertEqual(VisualizerStyle.musicalSpectrum.next, .bars)
        XCTAssertEqual(VisualizerStyle.bars.previous, .musicalSpectrum)
        // from spinner itself (saved style) stepping lands on an available style
        XCTAssertNotEqual(s.nextEnabledStyle(after: .spinner), .spinner)
        XCTAssertNotEqual(s.previousEnabledStyle(before: .spinner), .spinner)
    }

    func testRandomPickerNeverReturnsUnavailableSpinner() {
        VisualizerStyle.spinnerOSCheck = { false }
        let s = VisualizerSettings.defaults
        for seed in 0..<500 {
            var rng = SplitMix(seed: UInt64(seed))
            XCTAssertNotEqual(s.randomEnabledStyle(excluding: .bars, using: &rng), .spinner)
        }
    }

    func testSavedSpinnerStyleResolvesLikeADisabledStyle() {
        VisualizerStyle.spinnerOSCheck = { false }
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .spinner
        var d = VisualizerSettings.defaults
        d.visualizerStyle = .voronoi
        d.setStyleEnabled(.voronoi, false)
        XCTAssertEqual(s.effectiveStyle, d.effectiveStyle)
        XCTAssertEqual(s.effectiveStyle, .bars)
        VisualizerStyle.spinnerOSCheck = { true }
        XCTAssertEqual(s.effectiveStyle, .spinner)
    }

    func testSettingsRoundTripKeepsSpinnerProfileAndEnabledFlag() throws {
        VisualizerStyle.spinnerOSCheck = { false }
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .spinner
        s.mutateCurrent { $0.gain = 1.7 }
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(back.profiles[.spinner]?.gain, 1.7)
        XCTAssertEqual(back.profiles[.spinner]?.enabled, true)
        XCTAssertFalse(back.isStyleEnabled(.spinner))
        VisualizerStyle.spinnerOSCheck = { true }
        XCTAssertTrue(back.isStyleEnabled(.spinner))
    }

    func testAvailableBehavesAsToday() {
        VisualizerStyle.spinnerOSCheck = { true }
        let s = VisualizerSettings.defaults
        XCTAssertEqual(s.enabledStyles, VisualizerStyle.allCases)
        XCTAssertEqual(s.nextEnabledStyle(after: .musicalSpectrum), .spinner)
        XCTAssertEqual(VisualizerStyle.spinner.next, .bars)
    }
}

private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
