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

final class ColorPaletteBlendTests: XCTestCase {
    func testEndpointsExact() {
        let a = ColorPalette.preset(named: "classic")!
        let b = ColorPalette.preset(named: "inferno")!
        XCTAssertEqual(ColorPalette.blend(a, b, 0).stops, a.stops)
        XCTAssertEqual(ColorPalette.blend(a, b, 1).stops, b.stops)
    }

    func testSelfBlendIsIdentity() {
        let a = ColorPalette.preset(named: "aurora")!
        XCTAssertEqual(ColorPalette.blend(a, a, 0.5).stops, a.stops)
    }

    func testMidpointIsComponentwiseMean() {
        let a = ColorPalette.preset(named: "ice")!
        let b = ColorPalette.preset(named: "ember")!
        let mid = ColorPalette.blend(a, b, 0.5).stops
        for i in mid.indices {
            // Real component accessors (Task 0): RGBAColor.r/.g/.b/.a
            XCTAssertEqual(mid[i].r, (a.stops[i].r + b.stops[i].r) / 2, accuracy: 1e-6)
            XCTAssertEqual(mid[i].g, (a.stops[i].g + b.stops[i].g) / 2, accuracy: 1e-6)
            XCTAssertEqual(mid[i].b, (a.stops[i].b + b.stops[i].b) / 2, accuracy: 1e-6)
            XCTAssertEqual(mid[i].a, (a.stops[i].a + b.stops[i].a) / 2, accuracy: 1e-6)
        }
    }

    func testClampsOutOfRangeT() {
        let a = ColorPalette.preset(named: "classic")!
        let b = ColorPalette.preset(named: "mono")!
        XCTAssertEqual(ColorPalette.blend(a, b, -5).stops, a.stops)
        XCTAssertEqual(ColorPalette.blend(a, b, 5).stops, b.stops)
    }
}
