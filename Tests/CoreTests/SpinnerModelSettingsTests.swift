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

final class SpinnerModelSettingsTests: XCTestCase {

    private func decode(_ json: String) throws -> SpinnerSettings {
        try JSONDecoder().decode(SpinnerSettings.self, from: Data(json.utf8))
    }

    func testModelDefaultsToDiscAndEdgeLightsOn() {
        let s = SpinnerSettings()
        XCTAssertEqual(s.model, .disc)
        XCTAssertTrue(s.edgeLights)
    }

    func testModelRawValuesIndicesAndNames() {
        XCTAssertEqual(SpinnerModel.disc.rawValue, "disc")
        XCTAssertEqual(SpinnerModel.triWing.rawValue, "triWing")
        XCTAssertEqual(SpinnerModel.disc.index, 0)
        XCTAssertEqual(SpinnerModel.triWing.index, 1)
        XCTAssertEqual(SpinnerModel.disc.displayName, "Disc")
        XCTAssertEqual(SpinnerModel.triWing.displayName, "Tri-wing")
        XCTAssertEqual(SpinnerModel.allCases.count, 2)
    }

    func testModelNextWraps() {
        XCTAssertEqual(SpinnerModel.disc.next, .triWing)
        XCTAssertEqual(SpinnerModel.triWing.next, .disc)
    }

    func testModelPreviousWrapsAndInvertsNext() {
        XCTAssertEqual(SpinnerModel.disc.previous, .triWing)
        XCTAssertEqual(SpinnerModel.triWing.previous, .disc)
        for m in SpinnerModel.allCases {
            XCTAssertEqual(m.next.previous, m)
            XCTAssertEqual(m.previous.next, m)
        }
    }

    func testRoundTrip() throws {
        var s = SpinnerSettings()
        s.model = .triWing
        s.edgeLights = false
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(SpinnerSettings.self, from: data)
        XCTAssertEqual(back, s)
        XCTAssertEqual(back.model, .triWing)
        XCTAssertFalse(back.edgeLights)
    }

    func testModelEncodesAsStableString() throws {
        var s = SpinnerSettings()
        s.model = .triWing
        let data = try JSONEncoder().encode(s)
        let text: String = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"model\":\"triWing\""))
    }

    func testLegacyJSONWithoutNewKeysDecodesToDefaults() throws {
        let s = try decode("{\"metal\":\"brass\"}")
        XCTAssertEqual(s.metal, .brass)
        XCTAssertEqual(s.model, .disc)
        XCTAssertTrue(s.edgeLights)
    }

    func testUnknownModelStringFallsBackToDisc() throws {
        let s = try decode("{\"model\":\"quadWing\",\"edgeLights\":false}")
        XCTAssertEqual(s.model, .disc)
        XCTAssertFalse(s.edgeLights)
    }

    func testStyleProfileEqualityNoticesModel() {
        var a = StyleProfile.defaults(for: .spinner)
        let b = a
        a.spinner.model = .triWing
        XCTAssertNotEqual(a, b)
    }

    // MARK: Beat lights

    func testBeatLightDefaults() {
        let s = SpinnerSettings()
        XCTAssertFalse(s.beatLights)
        XCTAssertEqual(s.restingGlow, 0.5, accuracy: 1e-12)
        XCTAssertEqual(s.beatGlow, 1.0, accuracy: 1e-12)
        XCTAssertEqual(SpinnerSettings.restingGlowRange, 0...1)
        XCTAssertEqual(SpinnerSettings.beatGlowRange, 0...1)
    }

    func testBeatLightRoundTrip() throws {
        var s = SpinnerSettings()
        s.beatLights = true
        s.restingGlow = 0.25
        s.beatGlow = 0.75
        let back = try JSONDecoder().decode(SpinnerSettings.self, from: try JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
        XCTAssertTrue(back.beatLights)
        XCTAssertEqual(back.restingGlow, 0.25, accuracy: 1e-12)
        XCTAssertEqual(back.beatGlow, 0.75, accuracy: 1e-12)
    }

    func testBeatLightLegacyJSONDecodesToDefaults() throws {
        let s = try decode("{\"metal\":\"brass\"}")
        XCTAssertFalse(s.beatLights)
        XCTAssertEqual(s.restingGlow, 0.5, accuracy: 1e-12)
        XCTAssertEqual(s.beatGlow, 1.0, accuracy: 1e-12)
    }

    func testBeatLightValuesClampOnDecodeAndOnSet() throws {
        let s = try decode("{\"restingGlow\":3,\"beatGlow\":-2}")
        XCTAssertEqual(s.restingGlow, 1.0, accuracy: 1e-12)
        XCTAssertEqual(s.beatGlow, 0.0, accuracy: 1e-12)
        var t = SpinnerSettings()
        t.restingGlow = -1
        t.beatGlow = 9
        XCTAssertEqual(t.restingGlow, 0.0, accuracy: 1e-12)
        XCTAssertEqual(t.beatGlow, 1.0, accuracy: 1e-12)
    }

    func testBeatLightNaNFallsBackToDefaults() {
        var t = SpinnerSettings()
        t.restingGlow = Double.nan
        t.beatGlow = Double.nan
        XCTAssertEqual(t.restingGlow, 0.5, accuracy: 1e-12)
        XCTAssertEqual(t.beatGlow, 1.0, accuracy: 1e-12)
    }
}
