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

final class PlasmaUniformsTests: XCTestCase {
    /// Default parity: with default settings every uniform field is bit-for-bit
    /// identical to the prior hardcoded `plasma_fs` literal (all 15 defaults are
    /// double-rounding-safe, so `Float(Double(lit)) == Float(lit)`), proving the
    /// look is byte-identical until a slider moves.
    func testPlasmaUniformsDefaultParity() {
        let u = makePlasmaUniforms(VisualizerSettings.defaults)
        XCTAssertEqual(u.coordinateScale.bitPattern, (2.0 as Float).bitPattern)
        XCTAssertEqual(u.coordinateOffset.bitPattern, (1.0 as Float).bitPattern)
        XCTAssertEqual(u.xFrequency.bitPattern, (8.0 as Float).bitPattern)
        XCTAssertEqual(u.yFrequency.bitPattern, (6.0 as Float).bitPattern)
        XCTAssertEqual(u.diagonalFrequency.bitPattern, (5.0 as Float).bitPattern)
        XCTAssertEqual(u.xTimeScale.bitPattern, (1.0 as Float).bitPattern)
        XCTAssertEqual(u.yTimeScale.bitPattern, (1.3 as Float).bitPattern)
        XCTAssertEqual(u.diagonalTimeScale.bitPattern, (0.7 as Float).bitPattern)
        XCTAssertEqual(u.waveDivisor.bitPattern, (3.0 as Float).bitPattern)
        XCTAssertEqual(u.contrast.bitPattern, (0.5 as Float).bitPattern)
        XCTAssertEqual(u.brightnessBias.bitPattern, (0.5 as Float).bitPattern)
        XCTAssertEqual(u.energyResponse.bitPattern, (0.3 as Float).bitPattern)
        XCTAssertEqual(u.clampMin.bitPattern, (0.0 as Float).bitPattern)
        XCTAssertEqual(u.clampMax.bitPattern, (1.0 as Float).bitPattern)
        XCTAssertEqual(u.alpha.bitPattern, (1.0 as Float).bitPattern)
    }

    /// Each settings field maps to its own uniform slot (no transposition).
    /// Every field gets a distinct, clamp-safe value so a swapped pair would
    /// surface as a mismatch.
    func testPlasmaUniformsFieldMapping() {
        var s = VisualizerSettings.defaults
        s.plasmaCoordinateScale = 2.5
        s.plasmaCoordinateOffset = 1.1
        s.plasmaXFrequency = 8.1
        s.plasmaYFrequency = 6.1
        s.plasmaDiagonalFrequency = 5.1
        s.plasmaXTimeScale = 1.1
        s.plasmaYTimeScale = 1.4
        s.plasmaDiagonalTimeScale = 0.8
        s.plasmaWaveDivisor = 3.1
        s.plasmaContrast = 0.6
        s.plasmaBrightnessBias = 0.4
        s.plasmaEnergyResponse = 0.31
        s.plasmaClampMin = 0.1
        s.plasmaClampMax = 0.9
        s.plasmaAlpha = 0.95
        let u = makePlasmaUniforms(s)
        XCTAssertEqual(u.coordinateScale, 2.5, accuracy: 1e-6)
        XCTAssertEqual(u.coordinateOffset, 1.1, accuracy: 1e-6)
        XCTAssertEqual(u.xFrequency, 8.1, accuracy: 1e-6)
        XCTAssertEqual(u.yFrequency, 6.1, accuracy: 1e-6)
        XCTAssertEqual(u.diagonalFrequency, 5.1, accuracy: 1e-6)
        XCTAssertEqual(u.xTimeScale, 1.1, accuracy: 1e-6)
        XCTAssertEqual(u.yTimeScale, 1.4, accuracy: 1e-6)
        XCTAssertEqual(u.diagonalTimeScale, 0.8, accuracy: 1e-6)
        XCTAssertEqual(u.waveDivisor, 3.1, accuracy: 1e-6)
        XCTAssertEqual(u.contrast, 0.6, accuracy: 1e-6)
        XCTAssertEqual(u.brightnessBias, 0.4, accuracy: 1e-6)
        XCTAssertEqual(u.energyResponse, 0.31, accuracy: 1e-6)
        XCTAssertEqual(u.clampMin, 0.1, accuracy: 1e-6)
        XCTAssertEqual(u.clampMax, 0.9, accuracy: 1e-6)
        XCTAssertEqual(u.alpha, 0.95, accuracy: 1e-6)
    }

    /// `coordinateScale` multiplies the UV before recentring (`in.uv * scale -
    /// offset`) and acts as zoom; a value of 0 or negative is meaningless, so the
    /// builder floors a persisted/hand-edited value up to a small positive epsilon
    /// while in-range values pass through.
    func testPlasmaUniformsCoordinateScaleFloorClamp() {
        var s = VisualizerSettings.defaults
        s.plasmaCoordinateScale = 0.0
        XCTAssertEqual(makePlasmaUniforms(s).coordinateScale, 1e-3, accuracy: 1e-9)
        s.plasmaCoordinateScale = -4.0
        XCTAssertEqual(makePlasmaUniforms(s).coordinateScale, 1e-3, accuracy: 1e-9)
        s.plasmaCoordinateScale = 3.0
        XCTAssertEqual(makePlasmaUniforms(s).coordinateScale, 3.0, accuracy: 1e-6)
    }

    /// `waveDivisor` is a divisor (v / divisor); the builder floors it to 0.1 so a
    /// persisted 0 can never reach the GPU and divide by zero.
    func testPlasmaUniformsWaveDivisorFloorClamp() {
        var s = VisualizerSettings.defaults
        s.plasmaWaveDivisor = 0.0
        XCTAssertEqual(makePlasmaUniforms(s).waveDivisor, 0.1, accuracy: 1e-9)
        s.plasmaWaveDivisor = 0.05
        XCTAssertEqual(makePlasmaUniforms(s).waveDivisor, 0.1, accuracy: 1e-9)
        s.plasmaWaveDivisor = 4.0
        XCTAssertEqual(makePlasmaUniforms(s).waveDivisor, 4.0, accuracy: 1e-6)
    }

    /// The shader's `clamp(v, min, max)` is undefined when min > max; the builder
    /// raises max up to min to keep the clamp well-defined. Valid orderings pass
    /// through untouched.
    func testPlasmaUniformsClampOrdering() {
        var s = VisualizerSettings.defaults
        s.plasmaClampMin = 0.8
        s.plasmaClampMax = 0.2
        let u = makePlasmaUniforms(s)
        XCTAssertEqual(u.clampMin, 0.8, accuracy: 1e-6)
        XCTAssertEqual(u.clampMax, 0.8, accuracy: 1e-6)
        s.plasmaClampMin = 0.2
        s.plasmaClampMax = 0.9
        let v = makePlasmaUniforms(s)
        XCTAssertEqual(v.clampMin, 0.2, accuracy: 1e-6)
        XCTAssertEqual(v.clampMax, 0.9, accuracy: 1e-6)
    }

    /// `alpha` is the output opacity; the builder clamps a persisted value to the
    /// valid 0...1 range.
    func testPlasmaUniformsAlphaClamp() {
        var s = VisualizerSettings.defaults
        s.plasmaAlpha = 2.0
        XCTAssertEqual(makePlasmaUniforms(s).alpha, 1.0, accuracy: 1e-9)
        s.plasmaAlpha = -1.0
        XCTAssertEqual(makePlasmaUniforms(s).alpha, 0.0, accuracy: 1e-9)
        s.plasmaAlpha = 0.5
        XCTAssertEqual(makePlasmaUniforms(s).alpha, 0.5, accuracy: 1e-6)
    }

    /// Swift<->Metal layout regression guard: the POD must be 15 Float (4 bytes
    /// each), tightly packed with no trailing padding, so `setFragmentBytes`
    /// ships exactly what `PlasmaUniforms` in Shaders.metal expects.
    func testPlasmaUniformsStrideMatchesMetalLayout() {
        XCTAssertEqual(MemoryLayout<PlasmaUniforms>.stride, 60)
    }
}
