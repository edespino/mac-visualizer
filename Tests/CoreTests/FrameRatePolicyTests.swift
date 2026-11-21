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

final class FrameRatePolicyTests: XCTestCase {
    func testUsesGlobalRateWithoutOverride() {
        XCTAssertEqual(FrameRatePolicy.rate(globalFPS: 60, styleOverride: nil, idleSeconds: nil), 60)
        XCTAssertEqual(FrameRatePolicy.rate(globalFPS: 120, styleOverride: nil, idleSeconds: nil), 120)
    }

    func testStyleOverrideWinsEitherDirection() {
        XCTAssertEqual(FrameRatePolicy.rate(globalFPS: 60, styleOverride: 30, idleSeconds: nil), 30)
        XCTAssertEqual(FrameRatePolicy.rate(globalFPS: 30, styleOverride: 60, idleSeconds: nil), 60)
    }

    func testActiveRateIsNeverBelowThirty() {
        XCTAssertEqual(FrameRatePolicy.rate(globalFPS: 0, styleOverride: nil, idleSeconds: nil), 30)
        XCTAssertEqual(FrameRatePolicy.rate(globalFPS: 60, styleOverride: 5, idleSeconds: nil), 30)
    }

    func testIdleDropsToIdleRateOnlyAfterTheFadeOut() {
        // The scene takes ~2 s to fade out once inactive; keep full rate until it has.
        XCTAssertEqual(FrameRatePolicy.rate(globalFPS: 60, styleOverride: nil, idleSeconds: 0), 60)
        XCTAssertEqual(FrameRatePolicy.rate(globalFPS: 60, styleOverride: nil, idleSeconds: 2.9), 60)
        XCTAssertEqual(FrameRatePolicy.rate(globalFPS: 60, styleOverride: nil, idleSeconds: 3), FrameRatePolicy.idleFPS)
        XCTAssertEqual(FrameRatePolicy.rate(globalFPS: 60, styleOverride: 120, idleSeconds: 600), FrameRatePolicy.idleFPS)
    }

    func testEffectiveRateOnSettingsFollowsTheActiveStyle() {
        var s = VisualizerSettings.defaults
        s.targetFPS = 60
        s.visualizerStyle = .lavaLamp
        s.mutateCurrent { $0.frameRateOverride = 30 }
        XCTAssertEqual(s.activeFrameRate, 30)
        s.visualizerStyle = .particles
        XCTAssertEqual(s.activeFrameRate, 60)
    }

    func testOverrideRoundTripsAndIsAbsentByDefault() throws {
        XCTAssertNil(StyleProfile.defaults.frameRateOverride)
        var p = StyleProfile.defaults
        p.frameRateOverride = 30
        let data = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(StyleProfile.self, from: data).frameRateOverride, 30)
        let plain = try JSONEncoder().encode(StyleProfile.defaults)
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("frameRateOverride"))
        XCTAssertNil(try JSONDecoder().decode(StyleProfile.self, from: Data("{}".utf8)).frameRateOverride)
    }

    func testLegacyPerStyleTargetFPSIsNotTreatedAsAnOverride() throws {
        // Profiles from before frame rate went app-wide carried "targetFPS".
        let legacy = Data(#"{"targetFPS": 30}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(StyleProfile.self, from: legacy).frameRateOverride)
    }

    func testOverrideSurvivesAFullSettingsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .plasma
        s.mutateCurrent { $0.frameRateOverride = 30 }
        let back = try JSONDecoder().decode(VisualizerSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.profiles[.plasma]?.frameRateOverride, 30)
    }
}
