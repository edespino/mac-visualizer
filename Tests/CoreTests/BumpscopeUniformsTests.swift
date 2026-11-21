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

final class BumpscopeUniformsTests: XCTestCase {
    /// Default parity: with default settings every uniform field is bit-for-bit
    /// identical to the prior hardcoded `bumpscope_fs` literal (all defaults are
    /// double-rounding-safe, so `Float(Double(lit)) == Float(lit)`), proving the
    /// look is byte-identical until a slider moves.
    func testBumpscopeUniformsDefaultParity() {
        let u = makeBumpscopeUniforms(VisualizerSettings.defaults)
        XCTAssertEqual(u.uvClampMin.bitPattern, (0.0 as Float).bitPattern)
        XCTAssertEqual(u.uvClampMax.bitPattern, (1.0 as Float).bitPattern)
        XCTAssertEqual(u.neighborRadius, 1)
        XCTAssertEqual(u.slopeScale.bitPattern, (0.5 as Float).bitPattern)
        XCTAssertEqual(u.surfaceNormalY.bitPattern, (1.0 as Float).bitPattern)
        XCTAssertEqual(u.surfaceNormalZ.bitPattern, (0.0 as Float).bitPattern)
        XCTAssertEqual(u.lightX.bitPattern, (0.5 as Float).bitPattern)
        XCTAssertEqual(u.lightY.bitPattern, (0.7 as Float).bitPattern)
        XCTAssertEqual(u.lightZ.bitPattern, (0.5 as Float).bitPattern)
        XCTAssertEqual(u.diffuseFloor.bitPattern, (0.0 as Float).bitPattern)
        XCTAssertEqual(u.bandGain.bitPattern, (2.0 as Float).bitPattern)
        XCTAssertEqual(u.intensityBias.bitPattern, (0.2 as Float).bitPattern)
        XCTAssertEqual(u.intensityClampMin.bitPattern, (0.0 as Float).bitPattern)
        XCTAssertEqual(u.intensityClampMax.bitPattern, (1.0 as Float).bitPattern)
        XCTAssertEqual(u.alpha.bitPattern, (1.0 as Float).bitPattern)
    }

    /// Each settings field maps to its own uniform slot (no transposition).
    /// Every field gets a distinct, clamp-safe value so a swapped pair would
    /// surface as a mismatch.
    func testBumpscopeUniformsFieldMapping() {
        var s = VisualizerSettings.defaults
        s.bumpscopeUvClampMin = 0.1
        s.bumpscopeUvClampMax = 0.9
        s.bumpscopeNeighborRadius = 4
        s.bumpscopeSlopeScale = 1.5
        s.bumpscopeSurfaceNormalY = 2.0
        s.bumpscopeSurfaceNormalZ = 0.5
        s.bumpscopeLightX = 0.3
        s.bumpscopeLightY = 0.6
        s.bumpscopeLightZ = -0.4
        s.bumpscopeDiffuseFloor = 0.25
        s.bumpscopeBandGain = 3.5
        s.bumpscopeIntensityBias = 0.7
        s.bumpscopeIntensityClampMin = 0.05
        s.bumpscopeIntensityClampMax = 0.85
        s.bumpscopeAlpha = 0.6
        let u = makeBumpscopeUniforms(s)
        XCTAssertEqual(u.uvClampMin, 0.1, accuracy: 1e-6)
        XCTAssertEqual(u.uvClampMax, 0.9, accuracy: 1e-6)
        XCTAssertEqual(u.neighborRadius, 4)
        XCTAssertEqual(u.slopeScale, 1.5, accuracy: 1e-6)
        XCTAssertEqual(u.surfaceNormalY, 2.0, accuracy: 1e-6)
        XCTAssertEqual(u.surfaceNormalZ, 0.5, accuracy: 1e-6)
        XCTAssertEqual(u.lightX, 0.3, accuracy: 1e-6)
        XCTAssertEqual(u.lightY, 0.6, accuracy: 1e-6)
        XCTAssertEqual(u.lightZ, -0.4, accuracy: 1e-6)
        XCTAssertEqual(u.diffuseFloor, 0.25, accuracy: 1e-6)
        XCTAssertEqual(u.bandGain, 3.5, accuracy: 1e-6)
        XCTAssertEqual(u.intensityBias, 0.7, accuracy: 1e-6)
        XCTAssertEqual(u.intensityClampMin, 0.05, accuracy: 1e-6)
        XCTAssertEqual(u.intensityClampMax, 0.85, accuracy: 1e-6)
        XCTAssertEqual(u.alpha, 0.6, accuracy: 1e-6)
    }

    /// `uvClampMin`/`uvClampMax` feed the shader's `clamp(in.uv.x, min, max)`,
    /// undefined when min > max; the builder raises max up to min. Valid
    /// orderings pass through untouched.
    func testBumpscopeUniformsUvClampOrdering() {
        var s = VisualizerSettings.defaults
        s.bumpscopeUvClampMin = 0.8
        s.bumpscopeUvClampMax = 0.2
        let u = makeBumpscopeUniforms(s)
        XCTAssertEqual(u.uvClampMin, 0.8, accuracy: 1e-6)
        XCTAssertEqual(u.uvClampMax, 0.8, accuracy: 1e-6)
        s.bumpscopeUvClampMin = 0.2
        s.bumpscopeUvClampMax = 0.9
        let v = makeBumpscopeUniforms(s)
        XCTAssertEqual(v.uvClampMin, 0.2, accuracy: 1e-6)
        XCTAssertEqual(v.uvClampMax, 0.9, accuracy: 1e-6)
    }

    /// `intensityClampMin`/`intensityClampMax` feed the shader's palette-sample
    /// `clamp(..., min, max)`, undefined when min > max; the builder raises max
    /// up to min. Valid orderings pass through untouched.
    func testBumpscopeUniformsIntensityClampOrdering() {
        var s = VisualizerSettings.defaults
        s.bumpscopeIntensityClampMin = 0.7
        s.bumpscopeIntensityClampMax = 0.3
        let u = makeBumpscopeUniforms(s)
        XCTAssertEqual(u.intensityClampMin, 0.7, accuracy: 1e-6)
        XCTAssertEqual(u.intensityClampMax, 0.7, accuracy: 1e-6)
        s.bumpscopeIntensityClampMin = 0.1
        s.bumpscopeIntensityClampMax = 0.95
        let v = makeBumpscopeUniforms(s)
        XCTAssertEqual(v.intensityClampMin, 0.1, accuracy: 1e-6)
        XCTAssertEqual(v.intensityClampMax, 0.95, accuracy: 1e-6)
    }

    /// `diffuseFloor` is the lower bound on `dot(n, L)`; only 0...1 is meaningful,
    /// so the builder clamps a persisted/hand-edited value into range.
    func testBumpscopeUniformsDiffuseFloorClamp() {
        var s = VisualizerSettings.defaults
        s.bumpscopeDiffuseFloor = 2.0
        XCTAssertEqual(makeBumpscopeUniforms(s).diffuseFloor, 1.0, accuracy: 1e-9)
        s.bumpscopeDiffuseFloor = -1.0
        XCTAssertEqual(makeBumpscopeUniforms(s).diffuseFloor, 0.0, accuracy: 1e-9)
        s.bumpscopeDiffuseFloor = 0.4
        XCTAssertEqual(makeBumpscopeUniforms(s).diffuseFloor, 0.4, accuracy: 1e-6)
    }

    /// `alpha` is the output opacity; the builder clamps a persisted value to the
    /// valid 0...1 range.
    func testBumpscopeUniformsAlphaClamp() {
        var s = VisualizerSettings.defaults
        s.bumpscopeAlpha = 2.0
        XCTAssertEqual(makeBumpscopeUniforms(s).alpha, 1.0, accuracy: 1e-9)
        s.bumpscopeAlpha = -1.0
        XCTAssertEqual(makeBumpscopeUniforms(s).alpha, 0.0, accuracy: 1e-9)
        s.bumpscopeAlpha = 0.5
        XCTAssertEqual(makeBumpscopeUniforms(s).alpha, 0.5, accuracy: 1e-6)
    }

    /// `neighborRadius` indexes `bands[xi ± radius]` (a fixed 16-element array);
    /// the builder clamps a persisted/hand-edited value to 0...15 so the index
    /// can never leave the band domain.
    func testBumpscopeUniformsNeighborRadiusClamp() {
        var s = VisualizerSettings.defaults
        s.bumpscopeNeighborRadius = 99
        XCTAssertEqual(makeBumpscopeUniforms(s).neighborRadius, 15)
        s.bumpscopeNeighborRadius = -5
        XCTAssertEqual(makeBumpscopeUniforms(s).neighborRadius, 0)
        s.bumpscopeNeighborRadius = 6
        XCTAssertEqual(makeBumpscopeUniforms(s).neighborRadius, 6)
    }

    /// Swift<->Metal layout regression guard: the POD must be 15 × 4-byte fields
    /// (14 Float + 1 Int32), tightly packed with no padding, so `setFragmentBytes`
    /// ships exactly what `BumpscopeUniforms` in Shaders.metal expects.
    func testBumpscopeUniformsStrideMatchesMetalLayout() {
        XCTAssertEqual(MemoryLayout<BumpscopeUniforms>.stride, 60)
    }
}
