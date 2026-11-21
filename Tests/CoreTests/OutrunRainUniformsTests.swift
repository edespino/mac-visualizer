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

final class OutrunRainUniformsTests: XCTestCase {
    /// `horizon` feeds `smoothstep(0.0, horizon, uv.y)` in the shader; a value of
    /// 0 makes edge0 == edge1 (undefined in Metal). The builder clamps a
    /// persisted/hand-edited 0 or negative up to a small positive floor, while
    /// in-range values pass through unchanged.
    func testOutrunRainUniformsHorizonFloorClamp() {
        var s = VisualizerSettings.defaults
        s.outrunHorizon = 0.0
        XCTAssertEqual(makeOutrunRainUniforms(s).horizon, 0.05, accuracy: 1e-6)
        s.outrunHorizon = -1.0
        XCTAssertEqual(makeOutrunRainUniforms(s).horizon, 0.05, accuracy: 1e-6)
        s.outrunHorizon = 0.8
        XCTAssertEqual(makeOutrunRainUniforms(s).horizon, 0.8, accuracy: 1e-6)
    }

    /// Default parity: with default settings every uniform field equals the
    /// prior hardcoded Outrun the Rain literal, proving the look is unchanged.
    func testOutrunRainUniformsDefaultParity() {
        let u = makeOutrunRainUniforms(VisualizerSettings.defaults)
        // Horizon & Backdrop
        XCTAssertEqual(u.horizon, 0.80, accuracy: 1e-6)
        XCTAssertEqual(u.horizonGlowScale, 6.0, accuracy: 1e-6)
        XCTAssertEqual(u.horizonGlowBase, 0.6, accuracy: 1e-6)
        XCTAssertEqual(u.horizonBassGlow, 0.5, accuracy: 1e-6)
        XCTAssertEqual(u.lowMidBackdrop, 0.1, accuracy: 1e-6)
        XCTAssertEqual(u.backgroundBrightness, 0.25, accuracy: 1e-6)
        XCTAssertEqual(u.backgroundGlow, 1.2, accuracy: 1e-6)
        // Rain Motion
        XCTAssertEqual(u.leanBase, 0.12, accuracy: 1e-6)
        XCTAssertEqual(u.leanLowMid, 0.15, accuracy: 1e-6)
        XCTAssertEqual(u.fallBase, 1.1, accuracy: 1e-6)
        XCTAssertEqual(u.fallBass, 1.6, accuracy: 1e-6)
        XCTAssertEqual(u.fallEnergy, 0.8, accuracy: 1e-6)
        XCTAssertEqual(u.density, 70.0, accuracy: 1e-6)
        // Depth Layer 0
        XCTAssertEqual(u.layer0ColumnScale, 0.6, accuracy: 1e-6)
        XCTAssertEqual(u.layer0FallScale, 0.80, accuracy: 1e-6)
        XCTAssertEqual(u.layer0Seed, 0.0, accuracy: 1e-6)
        XCTAssertEqual(u.layer0Thickness, 140.0, accuracy: 1e-6)
        XCTAssertEqual(u.layer0Weight, 0.7, accuracy: 1e-6)
        // Depth Layer 1
        XCTAssertEqual(u.layer1ColumnScale, 1.0, accuracy: 1e-6)
        XCTAssertEqual(u.layer1FallScale, 1.00, accuracy: 1e-6)
        XCTAssertEqual(u.layer1Seed, 1.0, accuracy: 1e-6)
        XCTAssertEqual(u.layer1Thickness, 220.0, accuracy: 1e-6)
        XCTAssertEqual(u.layer1Weight, 1.0, accuracy: 1e-6)
        // Depth Layer 2
        XCTAssertEqual(u.layer2ColumnScale, 1.6, accuracy: 1e-6)
        XCTAssertEqual(u.layer2FallScale, 1.25, accuracy: 1e-6)
        XCTAssertEqual(u.layer2Seed, 2.0, accuracy: 1e-6)
        XCTAssertEqual(u.layer2Thickness, 320.0, accuracy: 1e-6)
        XCTAssertEqual(u.layer2Weight, 0.6, accuracy: 1e-6)
        // Sparkle Layer
        XCTAssertEqual(u.sparkleColumnScale, 2.4, accuracy: 1e-6)
        XCTAssertEqual(u.sparkleFallScale, 1.50, accuracy: 1e-6)
        XCTAssertEqual(u.sparkleSeed, 3.0, accuracy: 1e-6)
        XCTAssertEqual(u.sparkleThickness, 520.0, accuracy: 1e-6)
        XCTAssertEqual(u.sparkleBase, 0.3, accuracy: 1e-6)
        XCTAssertEqual(u.sparkleTreble, 1.8, accuracy: 1e-6)
        // Rain Shape & Color
        XCTAssertEqual(u.rainVerticalBase, 0.35, accuracy: 1e-6)
        XCTAssertEqual(u.rainVerticalY, 0.9, accuracy: 1e-6)
        XCTAssertEqual(u.rainColorBase, 0.55, accuracy: 1e-6)
        XCTAssertEqual(u.rainColorTreble, 0.4, accuracy: 1e-6)
        XCTAssertEqual(u.rainColorEnergy, 0.2, accuracy: 1e-6)
        // Brightness & Reflection
        XCTAssertEqual(u.rainBrightnessBase, 1.6, accuracy: 1e-6)
        XCTAssertEqual(u.rainBrightnessEnergy, 1.5, accuracy: 1e-6)
        XCTAssertEqual(u.rainBrightnessTreble, 1.2, accuracy: 1e-6)
        XCTAssertEqual(u.reflectionWidth, 3.0, accuracy: 1e-6)
        XCTAssertEqual(u.reflectionBass, 0.6, accuracy: 1e-6)
    }

    /// Each settings field maps to its own uniform slot (no transposition). Every
    /// field gets a distinct value so a swapped pair would surface as a mismatch.
    func testOutrunRainUniformsFieldMapping() {
        var s = VisualizerSettings.defaults
        s.outrunHorizon = 0.71
        s.outrunHorizonGlowScale = 5.1
        s.outrunHorizonGlowBase = 0.61
        s.outrunHorizonBassGlow = 0.51
        s.outrunLowMidBackdrop = 0.11
        s.outrunBackgroundBrightness = 0.26
        s.outrunBackgroundGlow = 1.21
        s.outrunLeanBase = 0.13
        s.outrunLeanLowMid = 0.16
        s.outrunFallBase = 1.11
        s.outrunFallBass = 1.61
        s.outrunFallEnergy = 0.81
        s.outrunDensity = 71.0
        s.outrunLayer0ColumnScale = 0.61
        s.outrunLayer0FallScale = 0.81
        s.outrunLayer0Seed = 0.01
        s.outrunLayer0Thickness = 141.0
        s.outrunLayer0Weight = 0.71
        s.outrunLayer1ColumnScale = 1.01
        s.outrunLayer1FallScale = 1.01
        s.outrunLayer1Seed = 1.01
        s.outrunLayer1Thickness = 221.0
        s.outrunLayer1Weight = 1.01
        s.outrunLayer2ColumnScale = 1.61
        s.outrunLayer2FallScale = 1.26
        s.outrunLayer2Seed = 2.01
        s.outrunLayer2Thickness = 321.0
        s.outrunLayer2Weight = 0.61
        s.outrunSparkleColumnScale = 2.41
        s.outrunSparkleFallScale = 1.51
        s.outrunSparkleSeed = 3.01
        s.outrunSparkleThickness = 521.0
        s.outrunSparkleBase = 0.31
        s.outrunSparkleTreble = 1.81
        s.outrunRainVerticalBase = 0.36
        s.outrunRainVerticalY = 0.91
        s.outrunRainColorBase = 0.56
        s.outrunRainColorTreble = 0.41
        s.outrunRainColorEnergy = 0.21
        s.outrunRainBrightnessBase = 1.62
        s.outrunRainBrightnessEnergy = 1.52
        s.outrunRainBrightnessTreble = 1.22
        s.outrunReflectionWidth = 3.1
        s.outrunReflectionBass = 0.62
        let u = makeOutrunRainUniforms(s)
        XCTAssertEqual(u.horizon, 0.71, accuracy: 1e-6)
        XCTAssertEqual(u.horizonGlowScale, 5.1, accuracy: 1e-6)
        XCTAssertEqual(u.horizonGlowBase, 0.61, accuracy: 1e-6)
        XCTAssertEqual(u.horizonBassGlow, 0.51, accuracy: 1e-6)
        XCTAssertEqual(u.lowMidBackdrop, 0.11, accuracy: 1e-6)
        XCTAssertEqual(u.backgroundBrightness, 0.26, accuracy: 1e-6)
        XCTAssertEqual(u.backgroundGlow, 1.21, accuracy: 1e-6)
        XCTAssertEqual(u.leanBase, 0.13, accuracy: 1e-6)
        XCTAssertEqual(u.leanLowMid, 0.16, accuracy: 1e-6)
        XCTAssertEqual(u.fallBase, 1.11, accuracy: 1e-6)
        XCTAssertEqual(u.fallBass, 1.61, accuracy: 1e-6)
        XCTAssertEqual(u.fallEnergy, 0.81, accuracy: 1e-6)
        XCTAssertEqual(u.density, 71.0, accuracy: 1e-6)
        XCTAssertEqual(u.layer0ColumnScale, 0.61, accuracy: 1e-6)
        XCTAssertEqual(u.layer0FallScale, 0.81, accuracy: 1e-6)
        XCTAssertEqual(u.layer0Seed, 0.01, accuracy: 1e-6)
        XCTAssertEqual(u.layer0Thickness, 141.0, accuracy: 1e-6)
        XCTAssertEqual(u.layer0Weight, 0.71, accuracy: 1e-6)
        XCTAssertEqual(u.layer1ColumnScale, 1.01, accuracy: 1e-6)
        XCTAssertEqual(u.layer1FallScale, 1.01, accuracy: 1e-6)
        XCTAssertEqual(u.layer1Seed, 1.01, accuracy: 1e-6)
        XCTAssertEqual(u.layer1Thickness, 221.0, accuracy: 1e-6)
        XCTAssertEqual(u.layer1Weight, 1.01, accuracy: 1e-6)
        XCTAssertEqual(u.layer2ColumnScale, 1.61, accuracy: 1e-6)
        XCTAssertEqual(u.layer2FallScale, 1.26, accuracy: 1e-6)
        XCTAssertEqual(u.layer2Seed, 2.01, accuracy: 1e-6)
        XCTAssertEqual(u.layer2Thickness, 321.0, accuracy: 1e-6)
        XCTAssertEqual(u.layer2Weight, 0.61, accuracy: 1e-6)
        XCTAssertEqual(u.sparkleColumnScale, 2.41, accuracy: 1e-6)
        XCTAssertEqual(u.sparkleFallScale, 1.51, accuracy: 1e-6)
        XCTAssertEqual(u.sparkleSeed, 3.01, accuracy: 1e-6)
        XCTAssertEqual(u.sparkleThickness, 521.0, accuracy: 1e-6)
        XCTAssertEqual(u.sparkleBase, 0.31, accuracy: 1e-6)
        XCTAssertEqual(u.sparkleTreble, 1.81, accuracy: 1e-6)
        XCTAssertEqual(u.rainVerticalBase, 0.36, accuracy: 1e-6)
        XCTAssertEqual(u.rainVerticalY, 0.91, accuracy: 1e-6)
        XCTAssertEqual(u.rainColorBase, 0.56, accuracy: 1e-6)
        XCTAssertEqual(u.rainColorTreble, 0.41, accuracy: 1e-6)
        XCTAssertEqual(u.rainColorEnergy, 0.21, accuracy: 1e-6)
        XCTAssertEqual(u.rainBrightnessBase, 1.62, accuracy: 1e-6)
        XCTAssertEqual(u.rainBrightnessEnergy, 1.52, accuracy: 1e-6)
        XCTAssertEqual(u.rainBrightnessTreble, 1.22, accuracy: 1e-6)
        XCTAssertEqual(u.reflectionWidth, 3.1, accuracy: 1e-6)
        XCTAssertEqual(u.reflectionBass, 0.62, accuracy: 1e-6)
    }
}
