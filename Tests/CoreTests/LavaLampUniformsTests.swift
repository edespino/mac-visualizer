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
import simd
@testable import MacVisualizerCore

final class LavaLampUniformsTests: XCTestCase {

    private func frame(bands: [Float], beat: Bool = false, intensity: Float = 0, t: TimeInterval = 0) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                   rms: 0, peak: 0, timestamp: t,
                   beat: beat, beatIntensity: intensity)
    }

    /// Default parity: with default settings each shader-side scalar equals the
    /// prior hardcoded `lavalamp_fs` / `makeLavaLampUniforms` literal, so the
    /// shader render mode looks byte-identical until a slider moves.
    func testLavaLampUniformsDefaultParity() {
        let viz = LavaLampVisualizer()
        let s = VisualizerSettings.defaults
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let u = makeLavaLampUniforms(visualizer: viz, frame: frame(bands: bands), settings: s)
        XCTAssertEqual(u.densityFalloff, 8.0, accuracy: 1e-6)
        XCTAssertEqual(u.brightnessResponse, 0.8, accuracy: 1e-6)
        XCTAssertEqual(u.paletteDensityScale, 0.4, accuracy: 1e-6)
        XCTAssertEqual(u.beatBoost, 0.0, accuracy: 1e-6, "no beat frame -> no boost")
        XCTAssertEqual(u.pointCount, 12, "default blob count")
    }

    /// The shader beat boost uses `lavaLampShaderBeatBoost * beatIntensity` on a
    /// beat frame only. Default 0.5 reproduces the prior literal.
    func testLavaLampUniformsShaderBeatBoost() {
        let viz = LavaLampVisualizer()
        var s = VisualizerSettings.defaults
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        // Default coefficient 0.5 on a full-intensity beat -> 0.5.
        var u = makeLavaLampUniforms(visualizer: viz, frame: frame(bands: bands, beat: true, intensity: 1.0), settings: s)
        XCTAssertEqual(u.beatBoost, 0.5, accuracy: 1e-6)
        // Half intensity -> 0.25.
        u = makeLavaLampUniforms(visualizer: viz, frame: frame(bands: bands, beat: true, intensity: 0.5), settings: s)
        XCTAssertEqual(u.beatBoost, 0.25, accuracy: 1e-6)
        // Custom coefficient.
        s.lavaLampShaderBeatBoost = 2.0
        u = makeLavaLampUniforms(visualizer: viz, frame: frame(bands: bands, beat: true, intensity: 1.0), settings: s)
        XCTAssertEqual(u.beatBoost, 2.0, accuracy: 1e-6)
        // No beat -> 0 regardless of coefficient.
        u = makeLavaLampUniforms(visualizer: viz, frame: frame(bands: bands, beat: false, intensity: 1.0), settings: s)
        XCTAssertEqual(u.beatBoost, 0.0, accuracy: 1e-6)
    }

    /// Each shared field maps to its own uniform slot (no transposition).
    func testLavaLampUniformsFieldMapping() {
        let viz = LavaLampVisualizer()
        var s = VisualizerSettings.defaults
        s.lavaLampDensityFalloff = 12.0
        s.lavaLampBrightnessResponse = 1.5
        s.lavaLampPaletteDensityScale = 0.6
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let u = makeLavaLampUniforms(visualizer: viz, frame: frame(bands: bands), settings: s)
        XCTAssertEqual(u.densityFalloff, 12.0, accuracy: 1e-6)
        XCTAssertEqual(u.brightnessResponse, 1.5, accuracy: 1e-6)
        XCTAssertEqual(u.paletteDensityScale, 0.6, accuracy: 1e-6)
    }

    /// `densityFalloff` multiplies inside `exp(-r2 * K)`; a non-positive K would
    /// invert the Gaussian (density grows without bound). The builder floors it
    /// to a small positive epsilon. The default 8.0 passes through unchanged.
    func testLavaLampUniformsDensityFalloffPositiveFloor() {
        let viz = LavaLampVisualizer()
        var s = VisualizerSettings.defaults
        s.lavaLampDensityFalloff = 0.0
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        XCTAssertEqual(makeLavaLampUniforms(visualizer: viz, frame: frame(bands: bands), settings: s).densityFalloff,
                       1e-4, accuracy: 1e-9)
        s.lavaLampDensityFalloff = -5.0
        XCTAssertEqual(makeLavaLampUniforms(visualizer: viz, frame: frame(bands: bands), settings: s).densityFalloff,
                       1e-4, accuracy: 1e-9)
    }

    /// A nil visualizer yields a zero active point count (nothing to render),
    /// not a crash.
    func testLavaLampUniformsNilVisualizerHasZeroPoints() {
        let s = VisualizerSettings.defaults
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let u = makeLavaLampUniforms(visualizer: nil, frame: frame(bands: bands), settings: s)
        XCTAssertEqual(u.pointCount, 0)
    }

    /// Swift<->Metal layout regression guard: capacity-24 float4 array + the
    /// scalar tail must stride to exactly 432 bytes so `setFragmentBytes` ships
    /// what `LavaLampUniforms` in Shaders.metal expects.
    func testLavaLampUniformsStrideMatchesMetalLayout() {
        XCTAssertEqual(MemoryLayout<LavaLampUniforms>.stride, 432)
    }
}
