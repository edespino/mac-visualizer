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

final class OctaveMeatballsUniformsTests: XCTestCase {
    /// Default parity: with default settings every uniform field equals the
    /// prior hardcoded Octave Meatballs shader literal, proving the look is
    /// byte-identical until a slider moves.
    func testOctaveMeatballsUniformsDefaultParity() {
        let u = makeOctaveMeatballsUniforms(VisualizerSettings.defaults)
        // Pattern & Scale
        XCTAssertEqual(u.scale, 10.0, accuracy: 1e-6)
        XCTAssertEqual(u.ballDivisor, 10.0, accuracy: 1e-6)
        // Background color
        XCTAssertEqual(u.backgroundR, 0.005, accuracy: 1e-6)
        XCTAssertEqual(u.backgroundG, 0.0, accuracy: 1e-6)
        XCTAssertEqual(u.backgroundB, 0.01, accuracy: 1e-6)
        // Shimmer & Drift
        XCTAssertEqual(u.octavePhase, 0.1, accuracy: 1e-6)
        XCTAssertEqual(u.shimmerOctaveScale, 0.5, accuracy: 1e-6)
        XCTAssertEqual(u.shimmerTimeScale, 0.1, accuracy: 1e-6)
        XCTAssertEqual(u.lifeTimeScale, 0.1, accuracy: 1e-6)
        XCTAssertEqual(u.pulseEdge0, 0.4, accuracy: 1e-6)
        XCTAssertEqual(u.pulseEdge1, 0.8, accuracy: 1e-6)
        XCTAssertEqual(u.lifeOctaveScale, 0.02, accuracy: 1e-6)
        XCTAssertEqual(u.lifeDenomBase, 0.02, accuracy: 1e-6)
        XCTAssertEqual(u.lifeDenomRadius, 0.001, accuracy: 1e-6)
        XCTAssertEqual(u.lifeDenomScale, 60.0, accuracy: 1e-6)
        // Metaball field
        XCTAssertEqual(u.distanceFloor, 0.001, accuracy: 1e-6)
        XCTAssertEqual(u.ballStrength, 0.01, accuracy: 1e-6)
        XCTAssertEqual(u.ballBase, 0.35, accuracy: 1e-6)
        // Red glow color
        XCTAssertEqual(u.redGlowR, 0.03, accuracy: 1e-6)
        XCTAssertEqual(u.redGlowG, 0.0, accuracy: 1e-6)
        XCTAssertEqual(u.redGlowB, 0.0, accuracy: 1e-6)
        // Palette
        XCTAssertEqual(u.paletteFieldGain, 1.5, accuracy: 1e-6)
        XCTAssertEqual(u.paletteGain, 2.0, accuracy: 1e-6)
        // Audio coefficients
        XCTAssertEqual(u.bandPhase, 2.0, accuracy: 1e-6)
        XCTAssertEqual(u.bandBrightness, 1.6, accuracy: 1e-6)
        XCTAssertEqual(u.energyBrightness, 0.6, accuracy: 1e-6)
        XCTAssertEqual(u.paletteEnergy, 0.2, accuracy: 1e-6)
        // Structural
        XCTAssertEqual(u.octaves, 24)
    }

    /// Each settings field maps to its own uniform slot (no transposition).
    /// Every field gets a distinct value so a swapped pair would surface as a
    /// mismatch. Values are chosen to pass the builder's clamps unchanged.
    func testOctaveMeatballsUniformsFieldMapping() {
        var s = VisualizerSettings.defaults
        s.octaveMeatballsScale = 11.0
        s.octaveMeatballsBallDivisor = 12.0
        s.octaveMeatballsBackgroundR = 0.006
        s.octaveMeatballsBackgroundG = 0.002
        s.octaveMeatballsBackgroundB = 0.011
        s.octaveMeatballsOctavePhase = 0.12
        s.octaveMeatballsShimmerOctaveScale = 0.51
        s.octaveMeatballsShimmerTimeScale = 0.11
        s.octaveMeatballsLifeTimeScale = 0.13
        s.octaveMeatballsPulseEdge0 = 0.41
        s.octaveMeatballsPulseEdge1 = 0.81
        s.octaveMeatballsLifeOctaveScale = 0.021
        s.octaveMeatballsLifeDenomBase = 0.022
        s.octaveMeatballsLifeDenomRadius = 0.0011
        s.octaveMeatballsLifeDenomScale = 61.0
        s.octaveMeatballsDistanceFloor = 0.0012
        s.octaveMeatballsBallStrength = 0.011
        s.octaveMeatballsBallBase = 0.36
        s.octaveMeatballsRedGlowR = 0.031
        s.octaveMeatballsRedGlowG = 0.001
        s.octaveMeatballsRedGlowB = 0.002
        s.octaveMeatballsPaletteFieldGain = 1.51
        s.octaveMeatballsPaletteGain = 2.01
        s.octaveMeatballsBandPhase = 2.1
        s.octaveMeatballsBandBrightness = 1.61
        s.octaveMeatballsEnergyBrightness = 0.61
        s.octaveMeatballsPaletteEnergy = 0.21
        s.octaveMeatballsOctaves = 20
        let u = makeOctaveMeatballsUniforms(s)
        XCTAssertEqual(u.scale, 11.0, accuracy: 1e-6)
        XCTAssertEqual(u.ballDivisor, 12.0, accuracy: 1e-6)
        XCTAssertEqual(u.backgroundR, 0.006, accuracy: 1e-6)
        XCTAssertEqual(u.backgroundG, 0.002, accuracy: 1e-6)
        XCTAssertEqual(u.backgroundB, 0.011, accuracy: 1e-6)
        XCTAssertEqual(u.octavePhase, 0.12, accuracy: 1e-6)
        XCTAssertEqual(u.shimmerOctaveScale, 0.51, accuracy: 1e-6)
        XCTAssertEqual(u.shimmerTimeScale, 0.11, accuracy: 1e-6)
        XCTAssertEqual(u.lifeTimeScale, 0.13, accuracy: 1e-6)
        XCTAssertEqual(u.pulseEdge0, 0.41, accuracy: 1e-6)
        XCTAssertEqual(u.pulseEdge1, 0.81, accuracy: 1e-6)
        XCTAssertEqual(u.lifeOctaveScale, 0.021, accuracy: 1e-6)
        XCTAssertEqual(u.lifeDenomBase, 0.022, accuracy: 1e-6)
        XCTAssertEqual(u.lifeDenomRadius, 0.0011, accuracy: 1e-6)
        XCTAssertEqual(u.lifeDenomScale, 61.0, accuracy: 1e-6)
        XCTAssertEqual(u.distanceFloor, 0.0012, accuracy: 1e-6)
        XCTAssertEqual(u.ballStrength, 0.011, accuracy: 1e-6)
        XCTAssertEqual(u.ballBase, 0.36, accuracy: 1e-6)
        XCTAssertEqual(u.redGlowR, 0.031, accuracy: 1e-6)
        XCTAssertEqual(u.redGlowG, 0.001, accuracy: 1e-6)
        XCTAssertEqual(u.redGlowB, 0.002, accuracy: 1e-6)
        XCTAssertEqual(u.paletteFieldGain, 1.51, accuracy: 1e-6)
        XCTAssertEqual(u.paletteGain, 2.01, accuracy: 1e-6)
        XCTAssertEqual(u.bandPhase, 2.1, accuracy: 1e-6)
        XCTAssertEqual(u.bandBrightness, 1.61, accuracy: 1e-6)
        XCTAssertEqual(u.energyBrightness, 0.61, accuracy: 1e-6)
        XCTAssertEqual(u.paletteEnergy, 0.21, accuracy: 1e-6)
        XCTAssertEqual(u.octaves, 20)
    }

    /// `octaves` is the dynamic loop bound and divides `float(octaves)`, so it
    /// must clamp to 1...32: 0/negative -> 1, oversized -> 32, in-range passes.
    func testOctaveMeatballsUniformsOctavesClamp() {
        var s = VisualizerSettings.defaults
        s.octaveMeatballsOctaves = 0
        XCTAssertEqual(makeOctaveMeatballsUniforms(s).octaves, 1)
        s.octaveMeatballsOctaves = -5
        XCTAssertEqual(makeOctaveMeatballsUniforms(s).octaves, 1)
        s.octaveMeatballsOctaves = 40
        XCTAssertEqual(makeOctaveMeatballsUniforms(s).octaves, 32)
        s.octaveMeatballsOctaves = 16
        XCTAssertEqual(makeOctaveMeatballsUniforms(s).octaves, 16)
    }

    /// `pulseEdge0/1` feed `smoothstep(edge0, edge1, ...)`, undefined for
    /// equal/inverted edges. The builder raises edge1 to at least edge0 + 0.01
    /// while leaving a valid pair untouched.
    func testOctaveMeatballsUniformsPulseEdgeOrdering() {
        var s = VisualizerSettings.defaults
        // Inverted: edge1 < edge0 -> raised to edge0 + 0.01.
        s.octaveMeatballsPulseEdge0 = 0.6
        s.octaveMeatballsPulseEdge1 = 0.2
        var u = makeOctaveMeatballsUniforms(s)
        XCTAssertEqual(u.pulseEdge0, 0.6, accuracy: 1e-6)
        XCTAssertEqual(u.pulseEdge1, 0.61, accuracy: 1e-6)
        // Equal: edge1 == edge0 -> raised to edge0 + 0.01.
        s.octaveMeatballsPulseEdge0 = 0.5
        s.octaveMeatballsPulseEdge1 = 0.5
        u = makeOctaveMeatballsUniforms(s)
        XCTAssertEqual(u.pulseEdge1, 0.51, accuracy: 1e-6)
        // Valid pair: untouched.
        s.octaveMeatballsPulseEdge0 = 0.3
        s.octaveMeatballsPulseEdge1 = 0.9
        u = makeOctaveMeatballsUniforms(s)
        XCTAssertEqual(u.pulseEdge0, 0.3, accuracy: 1e-6)
        XCTAssertEqual(u.pulseEdge1, 0.9, accuracy: 1e-6)
    }

    /// Denominators and divisors that reach 0 would divide-by-zero on the GPU.
    /// The builder floors each to a small positive epsilon (1e-4).
    func testOctaveMeatballsUniformsPositiveFloors() {
        var s = VisualizerSettings.defaults
        s.octaveMeatballsScale = 0.0
        s.octaveMeatballsBallDivisor = 0.0
        s.octaveMeatballsLifeDenomBase = 0.0
        s.octaveMeatballsLifeDenomScale = 0.0
        s.octaveMeatballsDistanceFloor = 0.0
        let u = makeOctaveMeatballsUniforms(s)
        XCTAssertEqual(u.scale, 1e-4, accuracy: 1e-9)
        XCTAssertEqual(u.ballDivisor, 1e-4, accuracy: 1e-9)
        XCTAssertEqual(u.lifeDenomBase, 1e-4, accuracy: 1e-9)
        XCTAssertEqual(u.lifeDenomScale, 1e-4, accuracy: 1e-9)
        XCTAssertEqual(u.distanceFloor, 1e-4, accuracy: 1e-9)
        // Negative inputs are floored too.
        s.octaveMeatballsScale = -3.0
        XCTAssertEqual(makeOctaveMeatballsUniforms(s).scale, 1e-4, accuracy: 1e-9)
    }

    /// `lifeDenomRadius` scales `l` inside the drift denominator
    /// `(lifeDenomBase + l * lifeDenomRadius) * lifeDenomScale`. A negative
    /// radius could drive that to zero for some radial distance `l`, so the
    /// builder clamps it to a nonnegative floor. With `lifeDenomBase >= 1e-4`
    /// and `l >= 0`, a nonnegative radius keeps the denominator strictly
    /// positive. The default 0.001 passes through unchanged.
    func testOctaveMeatballsUniformsLifeDenomRadiusNonnegative() {
        var s = VisualizerSettings.defaults
        s.octaveMeatballsLifeDenomRadius = -0.5
        XCTAssertEqual(makeOctaveMeatballsUniforms(s).lifeDenomRadius, 0.0, accuracy: 1e-9)
        s.octaveMeatballsLifeDenomRadius = 0.001
        XCTAssertEqual(makeOctaveMeatballsUniforms(s).lifeDenomRadius, 0.001, accuracy: 1e-9)
    }

    /// Swift<->Metal layout regression guard: the POD must be 29 Float (4 bytes
    /// each) + 1 Int32 (4 bytes), tightly packed with no trailing padding, so
    /// `setFragmentBytes` ships exactly what `OctaveMeatballsUniforms` in
    /// Shaders.metal expects.
    func testOctaveMeatballsUniformsStrideMatchesMetalLayout() {
        XCTAssertEqual(MemoryLayout<OctaveMeatballsUniforms>.stride, 120)
    }

    func testContentOffsetDefaultsToZeroAndPassesThrough() {
        let d = makeOctaveMeatballsUniforms(VisualizerSettings.defaults)
        XCTAssertEqual(d.offsetX, 0, accuracy: 1e-6)
        XCTAssertEqual(d.offsetY, 0, accuracy: 1e-6)
        let shifted = makeOctaveMeatballsUniforms(VisualizerSettings.defaults, offsetX: -0.2, offsetY: -0.45)
        XCTAssertEqual(shifted.offsetX, -0.2, accuracy: 1e-6)
        XCTAssertEqual(shifted.offsetY, -0.45, accuracy: 1e-6)
    }
}
