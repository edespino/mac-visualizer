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

final class StarNestUniformsTests: XCTestCase {
    /// Default parity: with default settings every uniform field equals the
    /// prior hardcoded Star Nest literal, proving the look is unchanged.
    func testStarNestUniformsDefaultParity() {
        let u = makeStarNestUniforms(VisualizerSettings.defaults)
        XCTAssertEqual(u.zoom, 0.78, accuracy: 1e-6)
        XCTAssertEqual(u.speed, 0.18, accuracy: 1e-6)
        XCTAssertEqual(u.formuparam, 0.53, accuracy: 1e-6)
        XCTAssertEqual(u.tile, 0.85, accuracy: 1e-6)
        XCTAssertEqual(u.stepsize, 0.105, accuracy: 1e-6)
        XCTAssertEqual(u.brightness, 0.00095, accuracy: 1e-6)
        XCTAssertEqual(u.darkmatter, 0.34, accuracy: 1e-6)
        XCTAssertEqual(u.distfading, 0.73, accuracy: 1e-6)
        XCTAssertEqual(u.saturation, 0.82, accuracy: 1e-6)
        XCTAssertEqual(u.volsteps, 18)
        XCTAssertEqual(u.iterations, 13)
    }

    func testStarNestUniformsDensityClamp() {
        var s = VisualizerSettings.defaults
        s.starNestVolsteps = 999; s.starNestIterations = 999
        let hi = makeStarNestUniforms(s)
        XCTAssertEqual(hi.volsteps, 26)
        XCTAssertEqual(hi.iterations, 16)
        s.starNestVolsteps = -5; s.starNestIterations = 0
        let lo = makeStarNestUniforms(s)
        XCTAssertEqual(lo.volsteps, 1)
        XCTAssertEqual(lo.iterations, 1)
    }

    /// Each field maps to its own uniform slot (no transposition).
    func testStarNestUniformsFieldMapping() {
        var s = VisualizerSettings.defaults
        s.starNestZoom = 1.1
        s.starNestSpeed = 0.4
        s.starNestFormuparam = 0.6
        s.starNestTile = 1.0
        s.starNestStepsize = 0.2
        s.starNestBrightness = 0.002
        s.starNestDarkmatter = 0.5
        s.starNestDistfading = 0.9
        s.starNestSaturation = 0.3
        s.starNestVolsteps = 20
        s.starNestIterations = 10
        let u = makeStarNestUniforms(s)
        XCTAssertEqual(u.zoom, 1.1, accuracy: 1e-6)
        XCTAssertEqual(u.speed, 0.4, accuracy: 1e-6)
        XCTAssertEqual(u.formuparam, 0.6, accuracy: 1e-6)
        XCTAssertEqual(u.tile, 1.0, accuracy: 1e-6)
        XCTAssertEqual(u.stepsize, 0.2, accuracy: 1e-6)
        XCTAssertEqual(u.brightness, 0.002, accuracy: 1e-6)
        XCTAssertEqual(u.darkmatter, 0.5, accuracy: 1e-6)
        XCTAssertEqual(u.distfading, 0.9, accuracy: 1e-6)
        XCTAssertEqual(u.saturation, 0.3, accuracy: 1e-6)
        XCTAssertEqual(u.volsteps, 20)
        XCTAssertEqual(u.iterations, 10)
    }
}
