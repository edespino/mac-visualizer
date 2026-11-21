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

final class VoronoiUniformsTests: XCTestCase {

    private func frame(bands: [Float], beat: Bool = false, intensity: Float = 0) -> AudioFrame {
        AudioFrame(bands: bands, bandsLeft: bands, bandsRight: bands,
                   bandPeaks: bands, waveform: [],
                   rms: 0, peak: 0, timestamp: 0,
                   beat: beat, beatIntensity: intensity)
    }

    /// Deterministic spread of seeds covering both screen halves (x<0, x>=0).
    private func seeds(_ n: Int) -> [SIMD2<Float>] {
        (0..<n).map { SIMD2<Float>(Float($0) / Float(n) * 2 - 1, 0) }
    }

    private func seedSlot(_ u: VoronoiUniforms, _ i: Int) -> SIMD4<Float> {
        withUnsafeBytes(of: u.seedsAndBands) { raw in
            raw.bindMemory(to: SIMD4<Float>.self)[i]
        }
    }

    /// Default parity: with default settings each shader-side scalar equals the
    /// prior hardcoded `voronoi_fs` / `makeVoronoiUniforms` literal, so the blobs
    /// render mode looks byte-identical until a slider moves.
    func testVoronoiUniformsDefaultParity() {
        let s = VisualizerSettings.defaults
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let u = makeVoronoiUniforms(seeds: seeds(128), fadeBrightness: 1.0,
                                    frame: frame(bands: bands), settings: s)
        XCTAssertEqual(u.K, 12.0, accuracy: 1e-6)
        XCTAssertEqual(u.beatBoost, 0.0, accuracy: 1e-6, "no beat frame -> no boost")
        XCTAssertEqual(u.fadeBrightness, 1.0, accuracy: 1e-6)
        XCTAssertEqual(u.activeCount, 75, "default seed count")
    }

    /// `voronoiEdgeSharpness` maps to the uniform `K` (the `1-exp(-K*dEdge)`
    /// coefficient). Default 12.0 reproduces the prior literal.
    func testVoronoiUniformsEdgeSharpnessMapping() {
        var s = VisualizerSettings.defaults
        s.voronoiEdgeSharpness = 25.0
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let u = makeVoronoiUniforms(seeds: seeds(128), fadeBrightness: 1.0,
                                    frame: frame(bands: bands), settings: s)
        XCTAssertEqual(u.K, 25.0, accuracy: 1e-6)
    }

    /// The shader beat boost uses `voronoiShaderBeatBoost * beatIntensity` on a
    /// beat frame only. Default 0.3 reproduces the prior literal.
    func testVoronoiUniformsShaderBeatBoost() {
        var s = VisualizerSettings.defaults
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        // Default coefficient 0.3 on a full-intensity beat -> 0.3.
        var u = makeVoronoiUniforms(seeds: seeds(128), fadeBrightness: 1.0,
                                    frame: frame(bands: bands, beat: true, intensity: 1.0), settings: s)
        XCTAssertEqual(u.beatBoost, 0.3, accuracy: 1e-6)
        // Half intensity -> 0.15.
        u = makeVoronoiUniforms(seeds: seeds(128), fadeBrightness: 1.0,
                                frame: frame(bands: bands, beat: true, intensity: 0.5), settings: s)
        XCTAssertEqual(u.beatBoost, 0.15, accuracy: 1e-6)
        // Custom coefficient.
        s.voronoiShaderBeatBoost = 2.0
        u = makeVoronoiUniforms(seeds: seeds(128), fadeBrightness: 1.0,
                                frame: frame(bands: bands, beat: true, intensity: 1.0), settings: s)
        XCTAssertEqual(u.beatBoost, 2.0, accuracy: 1e-6)
        // No beat -> 0 regardless of coefficient.
        u = makeVoronoiUniforms(seeds: seeds(128), fadeBrightness: 1.0,
                                frame: frame(bands: bands, beat: false, intensity: 1.0), settings: s)
        XCTAssertEqual(u.beatBoost, 0.0, accuracy: 1e-6)
    }

    /// `fadeBrightness` passes straight through (renderer supplies the live
    /// VoronoiVisualizer fade so cycle/perTrack transitions dim the blobs too).
    func testVoronoiUniformsFadeBrightnessPassThrough() {
        let s = VisualizerSettings.defaults
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let u = makeVoronoiUniforms(seeds: seeds(128), fadeBrightness: 0.42,
                                    frame: frame(bands: bands), settings: s)
        XCTAssertEqual(u.fadeBrightness, 0.42, accuracy: 1e-6)
    }

    /// `voronoiEdgeSharpness` feeds `exp(-K*dEdge)`; a non-positive K would make
    /// the falloff blow up. The builder floors it to a small positive epsilon.
    func testVoronoiUniformsEdgeSharpnessClamp() {
        var s = VisualizerSettings.defaults
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        s.voronoiEdgeSharpness = 0.0
        var u = makeVoronoiUniforms(seeds: seeds(128), fadeBrightness: 1.0,
                                    frame: frame(bands: bands), settings: s)
        XCTAssertGreaterThan(u.K, 0.0)
        s.voronoiEdgeSharpness = -5.0
        u = makeVoronoiUniforms(seeds: seeds(128), fadeBrightness: 1.0,
                                frame: frame(bands: bands), settings: s)
        XCTAssertGreaterThan(u.K, 0.0)
    }

    /// `voronoiSeedCount` becomes the shader loop bound (`activeCount`); the shader
    /// indexes `seedsAndBands[nearestIdx]` so it must be >= 1 and <= capacity.
    func testVoronoiUniformsSeedCountClamp() {
        var s = VisualizerSettings.defaults
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        s.voronoiSeedCount = 0
        var u = makeVoronoiUniforms(seeds: seeds(128), fadeBrightness: 1.0,
                                    frame: frame(bands: bands), settings: s)
        XCTAssertEqual(u.activeCount, 1, "floored to 1")
        s.voronoiSeedCount = 9999
        u = makeVoronoiUniforms(seeds: seeds(128), fadeBrightness: 1.0,
                                frame: frame(bands: bands), settings: s)
        XCTAssertEqual(u.activeCount, Int32(kVoronoiSeedCapacity), "capped to capacity")
        s.voronoiSeedCount = 40
        u = makeVoronoiUniforms(seeds: seeds(128), fadeBrightness: 1.0,
                                frame: frame(bands: bands), settings: s)
        XCTAssertEqual(u.activeCount, 40)
    }

    /// activeCount is also bounded by the supplied seed array length.
    func testVoronoiUniformsSeedCountBoundedBySeedArray() {
        var s = VisualizerSettings.defaults
        s.voronoiSeedCount = 128
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let u = makeVoronoiUniforms(seeds: seeds(30), fadeBrightness: 1.0,
                                    frame: frame(bands: bands), settings: s)
        XCTAssertEqual(u.activeCount, 30)
    }

    /// Each seed slot carries its position and the band level for that seed.
    func testVoronoiUniformsSeedBandAssignment() {
        let s = VisualizerSettings.defaults
        let bands: [Float] = (0..<48).map { Float($0) / 48 }
        let sd = seeds(128)
        let u = makeVoronoiUniforms(seeds: sd, fadeBrightness: 1.0,
                                    frame: frame(bands: bands), settings: s)
        for i in 0..<Int(u.activeCount) {
            let slot = seedSlot(u, i)
            XCTAssertEqual(slot.x, sd[i].x, accuracy: 1e-6)
            XCTAssertEqual(slot.y, sd[i].y, accuracy: 1e-6)
            XCTAssertEqual(slot.z, bands[i % bands.count], accuracy: 1e-6)
        }
    }

    /// Stereo split: cells with x<0 read bandsLeft, x>=0 read bandsRight.
    func testVoronoiUniformsStereoSplit() {
        var s = VisualizerSettings.defaults
        s.useStereoImage = true
        let left: [Float] = (0..<48).map { _ in 0.2 }
        let right: [Float] = (0..<48).map { _ in 0.8 }
        let f = AudioFrame(bands: left, bandsLeft: left, bandsRight: right,
                           bandPeaks: left, waveform: [], rms: 0, peak: 0,
                           timestamp: 0, beat: false, beatIntensity: 0)
        let sd = seeds(128)
        let u = makeVoronoiUniforms(seeds: sd, fadeBrightness: 1.0, frame: f, settings: s)
        for i in 0..<Int(u.activeCount) {
            let slot = seedSlot(u, i)
            let expected: Float = sd[i].x < 0 ? 0.2 : 0.8
            XCTAssertEqual(slot.z, expected, accuracy: 1e-6)
        }
    }

    /// Swift POD and Metal struct must share the exact byte layout: 128 float4
    /// (2048 bytes) + 3 float + 1 int (16 bytes) = stride 2064 so the lone Int32
    /// trails without padding and `setFragmentBytes` ships an identical block.
    func testVoronoiUniformsStrideMatchesMetalLayout() {
        XCTAssertEqual(kVoronoiSeedCapacity, 128)
        XCTAssertEqual(MemoryLayout<VoronoiUniforms>.stride, 2064)
    }

    /// Documents intent: an EMPTY seeds array yields `activeCount == 0` — the
    /// deliberate safe degenerate (a 0-length shader loop), NOT a clamp-to-1 bug.
    /// Looping with no seeds would index uninitialized data. The companion
    /// assertion confirms the normal path still clamps activeCount to >= 1 for a
    /// non-empty array even when the requested count is 0.
    func testEmptySeedsYieldsZeroActiveCount() {
        var s = VisualizerSettings.defaults
        s.voronoiSeedCount = 0
        let bands: [Float] = (0..<48).map { _ in 0.5 }

        // Empty seeds → deliberate 0-length loop.
        let empty = makeVoronoiUniforms(seeds: [], fadeBrightness: 1.0,
                                        frame: frame(bands: bands), settings: s)
        XCTAssertEqual(empty.activeCount, 0, "empty seeds → safe 0-length loop, not a clamp to 1")

        // Non-empty seeds always clamp activeCount to at least 1.
        let one = makeVoronoiUniforms(seeds: [SIMD2<Float>(0, 0)], fadeBrightness: 1.0,
                                      frame: frame(bands: bands), settings: s)
        XCTAssertEqual(one.activeCount, 1, "non-empty seeds clamp activeCount to >= 1")

        // And it never exceeds capacity for an oversized request.
        s.voronoiSeedCount = 9999
        let many = makeVoronoiUniforms(seeds: seeds(128), fadeBrightness: 1.0,
                                       frame: frame(bands: bands), settings: s)
        XCTAssertEqual(many.activeCount, Int32(kVoronoiSeedCapacity), "clamps to capacity")
    }
}
