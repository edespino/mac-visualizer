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

final class PaletteUniformParityTests: XCTestCase {
    // With the feature OFF, the engine output must be a pure passthrough, so the
    // bound palette equals the named palette exactly for all original presets.
    func testFeatureOffPassthroughForOriginalEight() {
        let e = PaletteCycleEngine(); var rng = SystemRandomNumberGenerator()
        for name in ["classic","phosphor","synthwave","inferno","aurora","ember","ice","mono"] {
            let o = e.advance(dt: 0.016, enabled: false, interval: 60, fadeDuration: 1.5,
                              currentPaletteName: name, availableNames: ColorPalette.orderedPresetNames, rng: &rng)
            XCTAssertEqual(o.currentName, name)
            XCTAssertNil(o.nextName)
            XCTAssertEqual(o.mix, 0, accuracy: 0)
            // The build site uses currentName + (nextName,mix); with mix==0 it must bind `name` verbatim.
            let bound = ColorPalette.preset(named: o.currentName)!
            XCTAssertEqual(bound.stops, ColorPalette.preset(named: name)!.stops)
        }
    }
}
