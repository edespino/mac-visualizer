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

final class PaletteCycleSettingsTests: XCTestCase {
    func testDefaultsFeatureOff() {
        let d = VisualizerSettings.defaults
        XCTAssertFalse(d.paletteCycleEnabled)
        XCTAssertEqual(d.paletteCycleInterval, 60, accuracy: 0)
        XCTAssertEqual(d.paletteCycleFadeDuration, 1.5, accuracy: 0)
    }

    func testRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.paletteCycleEnabled = true
        s.paletteCycleInterval = 30
        s.paletteCycleFadeDuration = 2.0
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(back, s)
    }

    func testLegacyJSONDecodesToFeatureOff() throws {
        // A settings JSON with none of the new keys must decode to the defaults (feature off).
        let legacy = "{}".data(using: .utf8)!
        let s = try JSONDecoder().decode(VisualizerSettings.self, from: legacy)
        XCTAssertFalse(s.paletteCycleEnabled)
        XCTAssertEqual(s.paletteCycleInterval, 60, accuracy: 0)
        XCTAssertEqual(s.paletteCycleFadeDuration, 1.5, accuracy: 0)
    }
}
