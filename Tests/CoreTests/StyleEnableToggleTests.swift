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

/// Per-style enable/disable resolution on VisualizerSettings: the enabled-style
/// list, effective-style fallback, cycling that skips disabled styles, and the
/// never-empty invariant (all-disabled JSON resolves to .bars).
final class StyleEnableToggleTests: XCTestCase {

    // MARK: - Enabled list

    func testAllStylesEnabledByDefault() {
        let s = VisualizerSettings.defaults
        XCTAssertEqual(s.enabledStyles, VisualizerStyle.allCases)
        for style in VisualizerStyle.allCases {
            XCTAssertTrue(s.isStyleEnabled(style), "\(style) should default to enabled")
        }
    }

    func testDisablingOneStyleFiltersEnabledList() {
        var s = VisualizerSettings.defaults
        s.setStyleEnabled(.voronoi, false)
        XCTAssertFalse(s.isStyleEnabled(.voronoi))
        XCTAssertEqual(s.enabledStyles, VisualizerStyle.allCases.filter { $0 != .voronoi })
    }

    func testEnabledListPreservesCaseOrder() {
        var s = VisualizerSettings.defaults
        s.setStyleEnabled(.bars, false)
        s.setStyleEnabled(.plasma, false)
        s.setStyleEnabled(.musicalSpectrum, false)
        let expected = VisualizerStyle.allCases.filter {
            $0 != .bars && $0 != .plasma && $0 != .musicalSpectrum
        }
        XCTAssertEqual(s.enabledStyles, expected)
    }

    // MARK: - Per-profile independence

    func testDisablingOneStyleDoesNotAffectOthers() {
        var s = VisualizerSettings.defaults
        // Set the style BEFORE mutateCurrent so the right profile is mutated.
        s.visualizerStyle = .voronoi
        s.mutateCurrent { $0.enabled = false }
        XCTAssertFalse(s.isStyleEnabled(.voronoi))
        for style in VisualizerStyle.allCases where style != .voronoi {
            XCTAssertTrue(s.isStyleEnabled(style), "\(style) must stay enabled")
        }
    }

    func testSetStyleEnabledPreservesOtherProfileFields() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .plasma
        s.mutateCurrent { $0.gain = 3.0 }
        s.setStyleEnabled(.plasma, false)
        s.setStyleEnabled(.plasma, true)
        XCTAssertEqual(s.profiles[.plasma]?.gain, 3.0)
        XCTAssertEqual(s.profiles[.plasma]?.enabled, true)
    }

    // MARK: - Effective style

    func testEffectiveStyleIsCurrentWhenEnabled() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .plasma
        XCTAssertEqual(s.effectiveStyle, .plasma)
    }

    func testEffectiveStyleFallsBackToFirstEnabledInCaseOrder() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .plasma
        s.setStyleEnabled(.plasma, false)
        XCTAssertEqual(s.effectiveStyle, .bars)

        // With the head of the case order disabled too, fallback moves to the
        // first style that is still enabled.
        s.setStyleEnabled(.bars, false)
        s.setStyleEnabled(.radial, false)
        XCTAssertEqual(s.effectiveStyle, .mirrored)
    }

    // MARK: - Never-empty invariant

    func testAllDisabledFallsBackToBars() {
        var s = VisualizerSettings.defaults
        for style in VisualizerStyle.allCases { s.setStyleEnabled(style, false) }
        XCTAssertEqual(s.enabledStyles, [.bars])
        XCTAssertEqual(s.effectiveStyle, .bars)
    }

    func testAllDisabledPersistedJSONFallsBackToBars() throws {
        // Hand-edited settings.json with every style disabled must not crash
        // or render nothing: resolution falls back to .bars.
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .voronoi
        for style in VisualizerStyle.allCases { s.setStyleEnabled(style, false) }
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.enabledStyles, [.bars])
        XCTAssertEqual(decoded.effectiveStyle, .bars)
    }

    func testEnabledFlagRoundTripsThroughVisualizerSettings() throws {
        var s = VisualizerSettings.defaults
        s.setStyleEnabled(.heightfield, false)
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertFalse(decoded.isStyleEnabled(.heightfield))
        XCTAssertTrue(decoded.isStyleEnabled(.bars))
    }

    // MARK: - Missing profile

    func testMissingProfileCountsAsEnabled() {
        // A style with no entry in the profiles dictionary (possible via
        // hand-edited JSON) counts as enabled everywhere.
        var s = VisualizerSettings.defaults
        s.profiles.removeValue(forKey: .voronoi)
        XCTAssertTrue(s.isStyleEnabled(.voronoi))
        XCTAssertTrue(s.enabledStyles.contains(.voronoi))
        s.visualizerStyle = .voronoi
        XCTAssertEqual(s.effectiveStyle, .voronoi)
    }

    // MARK: - Hand-written JSON (pins the on-disk format, not encoder output)

    func testHandWrittenJSONDisabledActiveStyleFallsBack() throws {
        // Literal persisted shape: profiles are a flat [key, value, ...] array.
        // Unknown keys are ignored, a profile without "enabled" stays enabled,
        // absent profiles default to enabled, and a disabled active style
        // resolves to the first enabled style in case order.
        let json = """
        {
          "visualizerStyle": "voronoi",
          "someFutureTopLevelKey": 42,
          "profiles": [
            "bars",    { "enabled": false },
            "radial",  { "gain": 2.0 },
            "voronoi", { "enabled": false, "someFutureProfileKey": true }
          ]
        }
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(s.visualizerStyle, .voronoi)
        XCTAssertFalse(s.isStyleEnabled(.bars))
        XCTAssertFalse(s.isStyleEnabled(.voronoi))
        XCTAssertTrue(s.isStyleEnabled(.radial), "profile without enabled key stays enabled")
        XCTAssertEqual(s.profiles[.radial]?.gain, 2.0)
        XCTAssertTrue(s.isStyleEnabled(.mirrored), "absent profile counts as enabled")
        XCTAssertEqual(s.effectiveStyle, .radial)
    }

    func testHandWrittenJSONEveryStyleDisabledFallsBackToBars() throws {
        // Every style disabled in raw persisted text (including the legacy
        // "siri" key for ribbonWave). Resolution must fall back to .bars —
        // no crash, never an empty enabled set.
        let json = """
        {
          "visualizerStyle": "plasma",
          "profiles": [
            "bars", { "enabled": false },
            "radial", { "enabled": false },
            "mirrored", { "enabled": false },
            "oscilloscope", { "enabled": false },
            "particles", { "enabled": false },
            "fountain", { "enabled": false },
            "fireworks", { "enabled": false },
            "siri", { "enabled": false },
            "wireframe", { "enabled": false },
            "plasma", { "enabled": false },
            "bumpscope", { "enabled": false },
            "joyPlot", { "enabled": false },
            "heightfield", { "enabled": false },
            "voronoi", { "enabled": false },
            "lavaLamp", { "enabled": false },
            "beatCounter", { "enabled": false },
            "polartone", { "enabled": false },
            "octaveMeatballs", { "enabled": false },
            "starNest", { "enabled": false },
            "outrunRain", { "enabled": false },
            "xyScope", { "enabled": false },
            "iris", { "enabled": false },
            "tricentric", { "enabled": false },
            "musicalSpectrum", { "enabled": false },
            "spinner", { "enabled": false }
          ]
        }
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertFalse(s.isStyleEnabled(.ribbonWave), "legacy siri key must map to ribbonWave")
        XCTAssertEqual(s.enabledStyles, [.bars])
        XCTAssertEqual(s.effectiveStyle, .bars)
    }

    // MARK: - Cycling skips disabled styles

    func testNextEnabledStyleMatchesPlainNextWhenAllEnabled() {
        let s = VisualizerSettings.defaults
        XCTAssertEqual(s.nextEnabledStyle(after: .bars), .radial)
        XCTAssertEqual(s.nextEnabledStyle(after: .spinner), .bars)
    }

    func testNextEnabledStyleSkipsDisabled() {
        var s = VisualizerSettings.defaults
        s.setStyleEnabled(.radial, false)
        s.setStyleEnabled(.mirrored, false)
        XCTAssertEqual(s.nextEnabledStyle(after: .bars), .oscilloscope)
    }

    func testNextEnabledStyleWrapsAroundSkippingDisabled() {
        var s = VisualizerSettings.defaults
        s.setStyleEnabled(.bars, false)
        XCTAssertEqual(s.nextEnabledStyle(after: .spinner), .radial)
    }

    func testPreviousEnabledStyleSkipsDisabled() {
        var s = VisualizerSettings.defaults
        s.setStyleEnabled(.fountain, false)
        XCTAssertEqual(s.previousEnabledStyle(before: .fireworks), .particles)
    }

    func testPreviousEnabledStyleWrapsAroundSkippingDisabled() {
        var s = VisualizerSettings.defaults
        s.setStyleEnabled(.spinner, false)
        XCTAssertEqual(s.previousEnabledStyle(before: .bars), .musicalSpectrum)
    }

    func testCyclingWithSingleEnabledStyleStaysPut() {
        var s = VisualizerSettings.defaults
        for style in VisualizerStyle.allCases where style != .plasma {
            s.setStyleEnabled(style, false)
        }
        XCTAssertEqual(s.nextEnabledStyle(after: .plasma), .plasma)
        XCTAssertEqual(s.previousEnabledStyle(before: .plasma), .plasma)
    }

    func testCyclingWithAllDisabledFallsBackToBars() {
        var s = VisualizerSettings.defaults
        for style in VisualizerStyle.allCases { s.setStyleEnabled(style, false) }
        XCTAssertEqual(s.nextEnabledStyle(after: .voronoi), .bars)
        XCTAssertEqual(s.previousEnabledStyle(before: .voronoi), .bars)
    }
}
