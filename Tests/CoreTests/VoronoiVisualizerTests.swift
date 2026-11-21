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

final class VoronoiVisualizerTests: XCTestCase {

    private func frame(bands: [Float], beat: Bool = false, intensity: Float = 0) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                   rms: 0, peak: 0, timestamp: 0,
                   beat: beat, beatIntensity: intensity)
    }

    func testCellsModeProducesVertices() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .voronoi
        s.mutateCurrent { $0.voronoiRenderMode = .cells }
        let bands: [Float] = (0..<48).map { _ in 0.6 }
        let viz = VoronoiVisualizer()
        let verts = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        XCTAssertGreaterThan(verts.count, 100, "cells mode should emit many triangles")
        XCTAssertEqual(verts.count % 3, 0, "triangle vertices come in groups of 3")
    }

    func testCellsModeVertexBounds() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .voronoi
        s.mutateCurrent { $0.voronoiRenderMode = .cells }
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let viz = VoronoiVisualizer()
        let verts = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1.6)
        // Voronoi circumcenters can extend slightly outside the seed bounds
        // due to dual geometry. Allow a generous bound; the composite pass
        // will clip anything truly off-screen.
        for v in verts {
            XCTAssertLessThanOrEqual(abs(v.position.x), 3.0)
            XCTAssertLessThanOrEqual(abs(v.position.y), 3.0)
        }
    }

    func testCellsModeDeterministicSeeds() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .voronoi
        s.mutateCurrent { $0.voronoiRenderMode = .cells }
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let v1 = VoronoiVisualizer().makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        let v2 = VoronoiVisualizer().makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        XCTAssertEqual(v1.count, v2.count)
        for i in 0..<v1.count {
            XCTAssertEqual(v1[i].position.x, v2[i].position.x, accuracy: 1e-5)
            XCTAssertEqual(v1[i].position.y, v2[i].position.y, accuracy: 1e-5)
        }
    }

    func testCellsModeBeatBrightensVertices() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .voronoi
        s.mutateCurrent { $0.voronoiRenderMode = .cells }
        let bands: [Float] = (0..<48).map { _ in 0.6 }
        let baseViz = VoronoiVisualizer()
        let beatViz = VoronoiVisualizer()
        let baseVerts = baseViz.makeVertices(frame: frame(bands: bands, beat: false), settings: s, aspect: 1)
        let beatVerts = beatViz.makeVertices(frame: frame(bands: bands, beat: true, intensity: 1.0), settings: s, aspect: 1)
        let baseAvg = baseVerts.map { $0.color.x + $0.color.y + $0.color.z }.reduce(0, +) / Float(baseVerts.count)
        let beatAvg = beatVerts.map { $0.color.x + $0.color.y + $0.color.z }.reduce(0, +) / Float(beatVerts.count)
        XCTAssertGreaterThan(beatAvg, baseAvg, "beat should brighten the average cell color")
    }

    func testBlobsModeReturnsEmptyVertices() {
        // Shader-driven; visualizer emits no vertices. Renderer dispatches to voronoi_fs.
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .voronoi
        s.mutateCurrent { $0.voronoiRenderMode = .blobs }
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let viz = VoronoiVisualizer()
        let verts = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        XCTAssertEqual(verts.count, 0)
    }

    func testSoftCellsModeEmitsSameVerticesAsCellsMode() {
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        var sCells = VisualizerSettings.defaults
        sCells.visualizerStyle = .voronoi
        sCells.mutateCurrent { $0.voronoiRenderMode = .cells }
        var sSoft = VisualizerSettings.defaults
        sSoft.visualizerStyle = .voronoi
        sSoft.mutateCurrent { $0.voronoiRenderMode = .softCells }
        let v1 = VoronoiVisualizer().makeVertices(frame: frame(bands: bands), settings: sCells, aspect: 1)
        let v2 = VoronoiVisualizer().makeVertices(frame: frame(bands: bands), settings: sSoft, aspect: 1)
        XCTAssertEqual(v1.count, v2.count, "cells and softCells emit identical vertices; blur is renderer-side")
    }

    func testFixedModeKeepsCellsConstant() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .voronoi
        s.mutateCurrent { $0.voronoiShapeMode = .fixed; $0.voronoiRenderMode = .cells }
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let viz = VoronoiVisualizer()
        let v1 = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        // Advance many frames — vertices should remain in same screen positions.
        for i in 1...60 {
            _ = viz.makeVertices(frame: AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                                                    rms: 0, peak: 0, timestamp: Double(i) / 60),
                                  settings: s, aspect: 1)
        }
        let vN = viz.makeVertices(frame: AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                                                      rms: 0, peak: 0, timestamp: 1.0),
                                  settings: s, aspect: 1)
        XCTAssertEqual(v1.count, vN.count)
        // Position comparison: same shapes → same positions (colors may differ since beatBoost decays).
        for i in 0..<v1.count {
            XCTAssertEqual(v1[i].position.x, vN[i].position.x, accuracy: 1e-5)
            XCTAssertEqual(v1[i].position.y, vN[i].position.y, accuracy: 1e-5)
        }
    }

    func testPerTrackTriggersFadeOnTrackChange() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .voronoi
        s.mutateCurrent { $0.voronoiShapeMode = .perTrack; $0.voronoiRenderMode = .cells }
        let bands: [Float] = (0..<48).map { _ in 0.5 }

        let viz = VoronoiVisualizer()
        // Warm-up frame: first track ID seen — no transition triggered.
        var f0 = AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                            rms: 0, peak: 0, timestamp: 0)
        f0.trackId = "Track A"
        _ = viz.makeVertices(frame: f0, settings: s, aspect: 1)

        // Change track: next frame should trigger fade-out.
        var f1 = AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                            rms: 0, peak: 0, timestamp: 0.1)
        f1.trackId = "Track B"
        let v1 = viz.makeVertices(frame: f1, settings: s, aspect: 1)
        // Mid-fade-out → colors dimmed.
        let sumBrightness = v1.reduce(Float(0)) { $0 + $1.color.x + $1.color.y + $1.color.z }

        // Reference: fixed mode with no track change (no fade).
        let viz2 = VoronoiVisualizer()
        var sRef = VisualizerSettings.defaults
        sRef.visualizerStyle = .voronoi
        sRef.mutateCurrent { $0.voronoiShapeMode = .fixed; $0.voronoiRenderMode = .cells }
        var fRef = AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                              rms: 0, peak: 0, timestamp: 0)
        fRef.trackId = nil
        let vRef = viz2.makeVertices(frame: fRef, settings: sRef, aspect: 1)
        let refBrightness = vRef.reduce(Float(0)) { $0 + $1.color.x + $1.color.y + $1.color.z }

        XCTAssertLessThan(sumBrightness, refBrightness * 0.9,
                          "fade-out should dim colors relative to a stable non-fading frame")
    }

    func testDriftModeChangesPositionsOverTime() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .voronoi
        s.mutateCurrent { $0.voronoiShapeMode = .drift; $0.voronoiRenderMode = .cells }
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let viz = VoronoiVisualizer()
        let v1 = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        // Advance 120 frames (2s of drift).
        for i in 1...120 {
            _ = viz.makeVertices(frame: AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                                                    rms: 0, peak: 0, timestamp: Double(i) / 60),
                                  settings: s, aspect: 1)
        }
        let vN = viz.makeVertices(frame: AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                                                      rms: 0, peak: 0, timestamp: 2.0),
                                  settings: s, aspect: 1)
        // Positions should have evolved.
        var anyPositionMoved = false
        let n = min(v1.count, vN.count)
        for i in 0..<n {
            if abs(v1[i].position.x - vN[i].position.x) > 0.01 ||
               abs(v1[i].position.y - vN[i].position.y) > 0.01 {
                anyPositionMoved = true; break
            }
        }
        XCTAssertTrue(anyPositionMoved, "drift mode should evolve vertex positions over time")
    }

    // MARK: - Seed count control

    private func cellsSettings() -> VisualizerSettings {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .voronoi
        s.mutateCurrent { $0.voronoiShapeMode = .fixed; $0.voronoiRenderMode = .cells }
        return s
    }

    /// `voronoiSeedCount` drives the number of cells: fewer seeds → fewer
    /// triangles emitted.
    func testSeedCountControlsCellCount() {
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        var sFew = cellsSettings(); sFew.voronoiSeedCount = 10
        var sMany = cellsSettings(); sMany.voronoiSeedCount = 75
        let few = VoronoiVisualizer().makeVertices(frame: frame(bands: bands), settings: sFew, aspect: 1)
        let many = VoronoiVisualizer().makeVertices(frame: frame(bands: bands), settings: sMany, aspect: 1)
        XCTAssertGreaterThan(many.count, few.count, "more seeds should emit more cell geometry")
    }

    /// Changing `voronoiSeedCount` between frames reseeds statefully (the same
    /// visualizer instance rebuilds its seed set).
    func testSeedCountChangeReseedsStatefully() {
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let viz = VoronoiVisualizer()
        var s = cellsSettings(); s.voronoiSeedCount = 75
        let v1 = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        s.voronoiSeedCount = 20
        let v2 = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        XCTAssertNotEqual(v1.count, v2.count, "seed-count change must rebuild the seed set")
    }

    /// Changing `voronoiSeedSpread` reseeds and changes the cell layout.
    func testSeedSpreadChangeReseedsLayout() {
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        var sWide = cellsSettings(); sWide.voronoiSeedSpread = 0.95
        var sNarrow = cellsSettings(); sNarrow.voronoiSeedSpread = 0.5
        let wide = VoronoiVisualizer().makeVertices(frame: frame(bands: bands), settings: sWide, aspect: 1)
        let narrow = VoronoiVisualizer().makeVertices(frame: frame(bands: bands), settings: sNarrow, aspect: 1)
        // Narrower spread pulls seeds toward the center → geometry differs.
        let n = min(wide.count, narrow.count)
        var differs = false
        for i in 0..<n where abs(wide[i].position.x - narrow[i].position.x) > 1e-4 { differs = true; break }
        XCTAssertTrue(differs, "seed spread must change seed positions")
    }

    /// Default seed spread 0.95 keeps every seed within ±0.95 of center (pre
    /// aspect scaling); with aspect 1 the seed point of each fan is at the seed.
    func testSeedSpreadBoundsSeeds() {
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        var s = cellsSettings(); s.voronoiSeedSpread = 0.5
        let verts = VoronoiVisualizer().makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        // The fan apex (every 3rd vertex starting at 0) is a seed position.
        for i in stride(from: 0, to: verts.count, by: 3) {
            XCTAssertLessThanOrEqual(abs(verts[i].position.x), 0.5 + 1e-5)
            XCTAssertLessThanOrEqual(abs(verts[i].position.y), 0.5 + 1e-5)
        }
    }

    // MARK: - Drift control

    /// `voronoiDriftStrength == 0` freezes positions even in drift mode.
    func testDriftStrengthZeroKeepsPositionsConstant() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .voronoi
        s.mutateCurrent { $0.voronoiShapeMode = .drift; $0.voronoiRenderMode = .cells }
        s.voronoiDriftStrength = 0
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let viz = VoronoiVisualizer()
        let v1 = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        for i in 1...120 {
            _ = viz.makeVertices(frame: AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                                                    rms: 0, peak: 0, timestamp: Double(i) / 60),
                                  settings: s, aspect: 1)
        }
        let vN = viz.makeVertices(frame: AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                                                      rms: 0, peak: 0, timestamp: 2.0),
                                  settings: s, aspect: 1)
        XCTAssertEqual(v1.count, vN.count)
        for i in 0..<v1.count {
            XCTAssertEqual(v1[i].position.x, vN[i].position.x, accuracy: 1e-5)
            XCTAssertEqual(v1[i].position.y, vN[i].position.y, accuracy: 1e-5)
        }
    }

    // MARK: - Tint control

    /// `voronoiTintRange == 0` removes per-cell tint variation: with uniform
    /// bands every cell gets the identical color.
    func testTintRangeZeroProducesUniformColors() {
        var s = cellsSettings(); s.voronoiTintRange = 0
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let verts = VoronoiVisualizer().makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        XCTAssertFalse(verts.isEmpty)
        let c0 = verts[0].color
        for v in verts {
            XCTAssertEqual(v.color.x, c0.x, accuracy: 1e-5)
            XCTAssertEqual(v.color.y, c0.y, accuracy: 1e-5)
            XCTAssertEqual(v.color.z, c0.z, accuracy: 1e-5)
        }
    }

    /// Default tint range 0.1 introduces per-cell color variation.
    func testDefaultTintRangeVariesColors() {
        let s = cellsSettings()
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let verts = VoronoiVisualizer().makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        let c0 = verts[0].color
        var varied = false
        for v in verts where abs(v.color.x - c0.x) > 1e-4 || abs(v.color.y - c0.y) > 1e-4 { varied = true; break }
        XCTAssertTrue(varied, "default tint range should vary cell colors")
    }

    // MARK: - CPU beat control

    /// `voronoiCpuBeatBoost == 0` means a beat frame does not brighten cells.
    func testCpuBeatBoostZeroNoBrightnessChange() {
        var s = cellsSettings(); s.voronoiCpuBeatBoost = 0
        let bands: [Float] = (0..<48).map { _ in 0.6 }
        let base = VoronoiVisualizer().makeVertices(frame: frame(bands: bands, beat: false), settings: s, aspect: 1)
        let beat = VoronoiVisualizer().makeVertices(frame: frame(bands: bands, beat: true, intensity: 1.0), settings: s, aspect: 1)
        let baseAvg = base.map { $0.color.x + $0.color.y + $0.color.z }.reduce(0, +) / Float(base.count)
        let beatAvg = beat.map { $0.color.x + $0.color.y + $0.color.z }.reduce(0, +) / Float(beat.count)
        XCTAssertEqual(beatAvg, baseAvg, accuracy: 1e-5, "zero beat boost → no brightening")
    }

    /// A larger `voronoiCpuBeatBoost` brightens cells more on a beat frame.
    func testCpuBeatBoostScalesBrightness() {
        let bands: [Float] = (0..<48).map { _ in 0.6 }
        var sSmall = cellsSettings(); sSmall.voronoiCpuBeatBoost = 0.3
        var sLarge = cellsSettings(); sLarge.voronoiCpuBeatBoost = 2.0
        let small = VoronoiVisualizer().makeVertices(frame: frame(bands: bands, beat: true, intensity: 1.0), settings: sSmall, aspect: 1)
        let large = VoronoiVisualizer().makeVertices(frame: frame(bands: bands, beat: true, intensity: 1.0), settings: sLarge, aspect: 1)
        let smallAvg = small.map { $0.color.x + $0.color.y + $0.color.z }.reduce(0, +) / Float(small.count)
        let largeAvg = large.map { $0.color.x + $0.color.y + $0.color.z }.reduce(0, +) / Float(large.count)
        XCTAssertGreaterThan(largeAvg, smallAvg, "larger beat boost → brighter cells")
    }

    // MARK: - Cycle / fade control

    /// A short `voronoiCyclePeriod` triggers a reshuffle fade sooner than the
    /// default 60s would.
    func testCyclePeriodControlsReshuffleTiming() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .voronoi
        s.mutateCurrent { $0.voronoiShapeMode = .cycle; $0.voronoiRenderMode = .cells }
        s.voronoiCyclePeriod = 1.0
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let viz = VoronoiVisualizer()
        // First frame establishes the cycle start at t=0.
        _ = viz.makeVertices(frame: AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                                                rms: 0, peak: 0, timestamp: 0), settings: s, aspect: 1)
        // Past the 1s period → fade should begin.
        _ = viz.makeVertices(frame: AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                                                rms: 0, peak: 0, timestamp: 2.0), settings: s, aspect: 1)
        XCTAssertLessThan(viz.currentFadeBrightness(), 1.0, "short cycle period should have started a fade")
    }

    /// A shorter `voronoiFadeDuration` makes the fade progress faster (lower
    /// brightness after the same wall-clock step).
    func testFadeDurationControlsFadeRate() {
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        func brightnessAfterFadeStep(fadeDuration: Double) -> Float {
            var s = VisualizerSettings.defaults
            s.visualizerStyle = .voronoi
            s.mutateCurrent { $0.voronoiShapeMode = .cycle; $0.voronoiRenderMode = .cells }
            s.voronoiCyclePeriod = 1.0
            s.voronoiFadeDuration = fadeDuration
            let viz = VoronoiVisualizer()
            _ = viz.makeVertices(frame: AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                                                    rms: 0, peak: 0, timestamp: 0), settings: s, aspect: 1)
            // Trigger fade at t=2.
            _ = viz.makeVertices(frame: AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                                                    rms: 0, peak: 0, timestamp: 2.0), settings: s, aspect: 1)
            // One more 50ms step to advance the fade.
            _ = viz.makeVertices(frame: AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                                                    rms: 0, peak: 0, timestamp: 2.05), settings: s, aspect: 1)
            return viz.currentFadeBrightness()
        }
        let fast = brightnessAfterFadeStep(fadeDuration: 0.1)
        let slow = brightnessAfterFadeStep(fadeDuration: 2.0)
        XCTAssertLessThan(fast, slow, "shorter fade duration → faster (dimmer) fade after same step")
    }

    // MARK: - Tint / RNG parity (regression guard)

    /// Pins the subtlest value-preservation claim: at the default tintRange (0.1)
    /// the refactored per-cell tint reproduces the ORIGINAL `0.9 + factor * 0.2`
    /// formula exactly, AND the RNG draw order is unchanged — every seed position
    /// (two draws each) is consumed BEFORE the tint factors (one draw each), with
    /// no extra draws inserted. The expected tints are derived from the real RNG
    /// stream (`SeededRNG`, seed 0xCE110155 — module-internal, exposed via
    /// @testable) plus the original literal formula; the actual tints are recovered
    /// through the real emit path. A future refactor that shifts the RNG stream,
    /// inserts a draw, or changes the tint formula/default fails here.
    func testTintRngParityThroughEmitPath() {
        let count = 75   // VoronoiVisualizer default seed count

        // Reconstruct the RNG stream EXACTLY as buildSeeds draws it: for each seed,
        // two nextSigned() draws (x, y); THEN — after triangulation, which draws
        // nothing — one nextUnit() per cell tint factor.
        var rng = SeededRNG(seed: 0xCE110155)
        for _ in 0..<count { _ = rng.nextSigned(); _ = rng.nextSigned() }  // positions first
        var factors: [Float] = []
        for _ in 0..<count { factors.append(rng.nextUnit()) }              // then tint factors
        // ORIGINAL pre-refactor tint literal.
        let expectedTints = factors.map { 0.9 + $0 * 0.2 }

        // Pick a uniform band level + channel where the palette sample is small
        // enough that `sample * 1.1` (max tint) stays below 1, so the emit-path
        // `min(1, ...)` clamp never fires and the tint is exactly recoverable.
        let palette = ColorPalette.preset(named: VisualizerSettings.defaults.paletteName) ?? .fallback
        var level: Float = -1, channel = -1, base: Float = 0
        outer: for li in 0...100 {
            let L = Float(li) / 100
            let c = palette.sample(at: L)
            let chans = [c.r, c.g, c.b]
            for (ci, v) in chans.enumerated() where v > 0.02 && v * 1.1 < 0.999 {
                level = L; channel = ci; base = v; break outer
            }
        }
        XCTAssertGreaterThanOrEqual(channel, 0, "need a recoverable palette level/channel (sample*1.1 < 1)")

        // Real emit path, default settings (tintRange 0.1), fixed/cells, no beat
        // (beatMul == 1) and no fade (fadeBrightness == 1), uniform bands so every
        // cell samples the identical palette color `base`.
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .voronoi
        s.mutateCurrent { $0.voronoiShapeMode = .fixed; $0.voronoiRenderMode = .cells }
        let bands = [Float](repeating: level, count: 48)
        let verts = VoronoiVisualizer().makeVertices(frame: frame(bands: bands, beat: false), settings: s, aspect: 1)
        XCTAssertFalse(verts.isEmpty)

        // Recover each cell's tint = color_channel / palette_channel and assert it
        // matches an original-formula tint. Mismatch ⇒ formula or RNG order drifted.
        var distinct = Set<Int>()
        for v in verts {
            let comp = [v.color.x, v.color.y, v.color.z][channel]
            let tint = comp / base
            let matched = expectedTints.contains { abs($0 - tint) < 1e-3 }
            XCTAssertTrue(matched, "emitted tint \(tint) not produced by the original 0.9 + factor*0.2 formula / RNG order")
            distinct.insert(Int((tint * 1e4).rounded()))
        }
        XCTAssertGreaterThanOrEqual(distinct.count, 60, "most of the \(count) cells should be present")
    }
}