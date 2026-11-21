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

/// Layout + builder tests for the pipeline-level POD uniforms shared by every
/// fullscreen shader pass (`composite_fs`, the shader-driven visualizers'
/// buffer 0/1 bindings). These previously lived private in MetalRenderer with
/// no coverage; they follow the VoronoiUniforms/LavaLampUniforms pattern —
/// struct + pure builder in Core, renderer as a thin caller.
final class RenderPipelineUniformsTests: XCTestCase {

    // MARK: - CompositeUniforms

    /// Swift<->Metal layout guard: 6 × 4-byte fields (5 Float + 1 Int32),
    /// tightly packed, matching `CompositeUniforms` in Shaders.metal.
    func testCompositeUniformsStrideMatchesMetalLayout() {
        XCTAssertEqual(MemoryLayout<CompositeUniforms>.stride, 24)
        XCTAssertEqual(MemoryLayout<CompositeUniforms>.offset(of: \.intensity), 0)
        XCTAssertEqual(MemoryLayout<CompositeUniforms>.offset(of: \.vignetteAmount), 4)
        XCTAssertEqual(MemoryLayout<CompositeUniforms>.offset(of: \.time), 8)
        XCTAssertEqual(MemoryLayout<CompositeUniforms>.offset(of: \.kaleidoscopeFolds), 12)
        XCTAssertEqual(MemoryLayout<CompositeUniforms>.offset(of: \.perPixelAlphaMode), 16)
        XCTAssertEqual(MemoryLayout<CompositeUniforms>.offset(of: \.brightness), 20)
    }

    /// The dimmer flows through to the uniform, defaults to a 1.0 no-op, and is
    /// clamped so a persisted value can never invert or blow out the output.
    func testCompositeUniformsBrightnessMappingAndClamp() {
        var s = VisualizerSettings.defaults
        XCTAssertEqual(makeCompositeUniforms(intensity: 0, settings: s, time: 0).brightness, 1.0)
        s.outputBrightness = 0.35
        XCTAssertEqual(makeCompositeUniforms(intensity: 0, settings: s, time: 0).brightness,
                       0.35, accuracy: 1e-6)
        s.outputBrightness = 5.0
        XCTAssertEqual(makeCompositeUniforms(intensity: 0, settings: s, time: 0).brightness, 1.0)
        s.outputBrightness = -2.0
        XCTAssertEqual(makeCompositeUniforms(intensity: 0, settings: s, time: 0).brightness, 0.0)
        s.outputBrightness = Double.nan
        XCTAssertEqual(makeCompositeUniforms(intensity: 0, settings: s, time: 0).brightness, 1.0)
    }

    func testCompositeUniformsFieldMapping() {
        var s = VisualizerSettings.defaults
        s.vignetteAmount = 0.35
        s.kaleidoscopeFolds = 6
        s.windowTransparencyMode = .perPixelAlpha
        let u = makeCompositeUniforms(intensity: 0.8, settings: s, time: 12.5)
        XCTAssertEqual(u.intensity, 0.8, accuracy: 1e-6)
        XCTAssertEqual(u.vignetteAmount, 0.35, accuracy: 1e-6)
        XCTAssertEqual(u.time, 12.5, accuracy: 1e-6)
        XCTAssertEqual(u.kaleidoscopeFolds, 6)
        XCTAssertEqual(u.perPixelAlphaMode, 1.0)
    }

    func testCompositeUniformsPerPixelAlphaOffForOtherModes() {
        var s = VisualizerSettings.defaults
        s.windowTransparencyMode = .opaque
        XCTAssertEqual(makeCompositeUniforms(intensity: 0, settings: s, time: 0).perPixelAlphaMode, 0.0)
        s.windowTransparencyMode = .windowOpacity
        XCTAssertEqual(makeCompositeUniforms(intensity: 0, settings: s, time: 0).perPixelAlphaMode, 0.0)
    }

    /// The shader treats folds as 0 = off, 2...12 = N-fold; the builder clamps
    /// persisted/hand-edited values into 0...12.
    func testCompositeUniformsKaleidoscopeFoldsClamp() {
        var s = VisualizerSettings.defaults
        s.kaleidoscopeFolds = 99
        XCTAssertEqual(makeCompositeUniforms(intensity: 0, settings: s, time: 0).kaleidoscopeFolds, 12)
        s.kaleidoscopeFolds = -3
        XCTAssertEqual(makeCompositeUniforms(intensity: 0, settings: s, time: 0).kaleidoscopeFolds, 0)
    }

    // MARK: - ShaderInputs

    /// Swift<->Metal layout guard: time(0), energy(4), bands[16](8..72) —
    /// stride 72, matching `ShaderInputs` in Shaders.metal.
    func testShaderInputsStrideMatchesMetalLayout() {
        XCTAssertEqual(MemoryLayout<ShaderInputs>.stride, 72)
        XCTAssertEqual(MemoryLayout<ShaderInputs>.offset(of: \.time), 0)
        XCTAssertEqual(MemoryLayout<ShaderInputs>.offset(of: \.energy), 4)
        XCTAssertEqual(MemoryLayout<ShaderInputs>.offset(of: \.bands), 8)
    }

    private func frame(bands: [Float], rms: Float = 0) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: bands,
                   waveform: [0, 0], rms: rms, peak: 0, timestamp: 0)
    }

    /// 32 bands fold into 16 buckets of 2, each the bucket mean.
    func testShaderInputsAveragesBandsIntoSixteenBuckets() {
        let bands: [Float] = (0..<32).map { Float($0) }
        let u = makeShaderInputs(frame: frame(bands: bands, rms: 0.4), time: 7.0)
        XCTAssertEqual(u.time, 7.0, accuracy: 1e-6)
        XCTAssertEqual(u.energy, 0.4, accuracy: 1e-6)
        // Bucket i = mean(bands[2i], bands[2i+1]) = 2i + 0.5.
        XCTAssertEqual(u.bands.0, 0.5, accuracy: 1e-6)
        XCTAssertEqual(u.bands.1, 2.5, accuracy: 1e-6)
        XCTAssertEqual(u.bands.15, 30.5, accuracy: 1e-6)
    }

    /// Fewer than 16 bands: empty buckets sample the nearest band (hi == lo
    /// path), so no bucket is left at zero when audio is present.
    func testShaderInputsFewBandsFillAllBuckets() {
        let u = makeShaderInputs(frame: frame(bands: [1, 2, 3, 4]), time: 0)
        // 16 buckets over 4 bands: each band covers 4 buckets.
        XCTAssertEqual(u.bands.0, 1, accuracy: 1e-6)
        XCTAssertEqual(u.bands.4, 2, accuracy: 1e-6)
        XCTAssertEqual(u.bands.8, 3, accuracy: 1e-6)
        XCTAssertEqual(u.bands.15, 4, accuracy: 1e-6)
    }

    func testShaderInputsEmptyBandsYieldZeros() {
        let u = makeShaderInputs(frame: frame(bands: []), time: 0)
        XCTAssertEqual(u.bands.0, 0)
        XCTAssertEqual(u.bands.15, 0)
    }

    // MARK: - PaletteUniform

    /// Swift<->Metal layout guard: stops[8] of 4 packed floats (128 bytes)
    /// then Int32 stopCount — stride 132, matching Shaders.metal.
    func testPaletteUniformStrideMatchesMetalLayout() {
        XCTAssertEqual(MemoryLayout<PaletteStopUniform>.stride, 16)
        XCTAssertEqual(MemoryLayout<PaletteUniform>.offset(of: \.stops), 0)
        XCTAssertEqual(MemoryLayout<PaletteUniform>.offset(of: \.stopCount), 128)
        XCTAssertEqual(MemoryLayout<PaletteUniform>.stride, 132)
    }

    /// Stops copy through with evenly distributed positions (matching the
    /// Swift ColorPalette.sample semantics the shader mirrors).
    func testPaletteUniformCopiesStopsWithEvenPositions() {
        let palette = ColorPalette(stops: [
            RGBAColor(r: 1, g: 0, b: 0, a: 1),
            RGBAColor(r: 0, g: 1, b: 0, a: 1),
            RGBAColor(r: 0, g: 0, b: 1, a: 1),
        ])
        let u = makePaletteUniform(from: palette)
        XCTAssertEqual(u.stopCount, 3)
        XCTAssertEqual(u.stops.0.r, 1); XCTAssertEqual(u.stops.0.position, 0)
        XCTAssertEqual(u.stops.1.g, 1); XCTAssertEqual(u.stops.1.position, 0.5, accuracy: 1e-6)
        XCTAssertEqual(u.stops.2.b, 1); XCTAssertEqual(u.stops.2.position, 1.0, accuracy: 1e-6)
    }

    /// The uniform holds at most 8 stops; longer palettes truncate.
    func testPaletteUniformClampsToEightStops() {
        let stops = (0..<12).map { RGBAColor(r: Float($0), g: 0, b: 0, a: 1) }
        let u = makePaletteUniform(from: ColorPalette(stops: stops))
        XCTAssertEqual(u.stopCount, 8)
        XCTAssertEqual(u.stops.7.r, 7)
    }

    /// Unknown palette names bind the fallback palette, never garbage.
    func testPaletteUniformUnknownNameUsesFallback() {
        let u = makePaletteUniform(named: "not-a-palette")
        let f = makePaletteUniform(from: .fallback)
        XCTAssertEqual(u.stopCount, f.stopCount)
        XCTAssertEqual(u.stops.0.r, f.stops.0.r)
        XCTAssertEqual(u.stops.0.g, f.stops.0.g)
        XCTAssertEqual(u.stops.0.b, f.stops.0.b)
    }
}
