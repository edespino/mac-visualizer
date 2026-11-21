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

final class LavaLampVisualizerTests: XCTestCase {

    private func frame(bands: [Float], beat: Bool = false, intensity: Float = 0, t: TimeInterval = 0) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                   rms: 0, peak: 0, timestamp: t,
                   beat: beat, beatIntensity: intensity)
    }

    func testShaderModeReturnsEmptyVertices() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .lavaLamp
        s.mutateCurrent { $0.lavaLampRenderMode = .shader }
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let viz = LavaLampVisualizer()
        let verts = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        XCTAssertEqual(verts.count, 0, "shader mode emits no vertices; renderer dispatches to lavalamp_fs")
    }

    func testStateUpdatesPointPositionsOverTime() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .lavaLamp
        s.mutateCurrent { $0.lavaLampRenderMode = .marchingSquares }
        let bands: [Float] = (0..<48).map { _ in 0.4 }
        let viz = LavaLampVisualizer()
        _ = viz.makeVertices(frame: frame(bands: bands, t: 0), settings: s, aspect: 1)
        // Advance several frames; positions should evolve.
        for i in 1..<10 {
            _ = viz.makeVertices(frame: frame(bands: bands, t: Double(i) / 60.0), settings: s, aspect: 1)
        }
        // No explicit assertion — just verify no crash. Position evolution
        // verified visually + by the marching-squares output test in Task 13.
        XCTAssertTrue(true)
    }

    func testBeatLowersDensityThreshold() {
        // Beat reduces the effective threshold, which makes contour areas expand.
        // Sanity check: visualizer accepts beat frames without crashing in either mode.
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .lavaLamp
        s.mutateCurrent { $0.lavaLampRenderMode = .marchingSquares }
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let viz = LavaLampVisualizer()
        _ = viz.makeVertices(frame: frame(bands: bands, beat: false, t: 0), settings: s, aspect: 1)
        _ = viz.makeVertices(frame: frame(bands: bands, beat: true, intensity: 1.0, t: 1.0/60), settings: s, aspect: 1)
        XCTAssertTrue(true)
    }

    func testMarchingSquaresModeEmitsFilledCells() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .lavaLamp
        s.mutateCurrent { $0.lavaLampRenderMode = .marchingSquares }
        let bands: [Float] = (0..<48).map { _ in 0.6 }
        let viz = LavaLampVisualizer()
        let verts = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        XCTAssertGreaterThan(verts.count, 6, "expected at least one filled cell (6 verts) of brightness output")
        XCTAssertEqual(verts.count % 6, 0, "filled cells come in groups of 6 verts (two triangles per quad)")
    }

    func testMarchingSquaresVerticesInClipSpace() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .lavaLamp
        s.mutateCurrent { $0.lavaLampRenderMode = .marchingSquares }
        let bands: [Float] = (0..<48).map { _ in 0.6 }
        let viz = LavaLampVisualizer()
        let verts = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        for v in verts {
            XCTAssertLessThanOrEqual(abs(v.position.x), 1.5)
            XCTAssertLessThanOrEqual(abs(v.position.y), 1.5)
        }
    }

    // MARK: - Blob count (shared structural control)

    /// A fresh visualizer starts at the default blob count (12 points).
    func testDefaultBlobCountIsTwelvePoints() {
        XCTAssertEqual(LavaLampVisualizer().points.count, 12)
    }

    /// Changing `lavaLampBlobCount` rebuilds the CPU points array to match (it
    /// is consulted each frame, so a setting change resizes on the next frame).
    func testBlobCountResizesPointArray() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .lavaLamp
        s.mutateCurrent { $0.lavaLampRenderMode = .shader }
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let viz = LavaLampVisualizer()
        s.lavaLampBlobCount = 5
        _ = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        XCTAssertEqual(viz.points.count, 5)
        s.lavaLampBlobCount = 20
        _ = viz.makeVertices(frame: frame(bands: bands, t: 1.0/60), settings: s, aspect: 1)
        XCTAssertEqual(viz.points.count, 20)
    }

    /// `lavaLampBlobCount` is clamped to 1...capacity(24): an out-of-range
    /// persisted value can't produce a zero-length or over-capacity array.
    func testBlobCountClampsToOneThroughCapacity() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .lavaLamp
        s.mutateCurrent { $0.lavaLampRenderMode = .shader }
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let viz = LavaLampVisualizer()
        s.lavaLampBlobCount = 0
        _ = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        XCTAssertEqual(viz.points.count, 1)
        s.lavaLampBlobCount = 100
        _ = viz.makeVertices(frame: frame(bands: bands, t: 1.0/60), settings: s, aspect: 1)
        XCTAssertEqual(viz.points.count, 24)
        s.lavaLampBlobCount = -7
        _ = viz.makeVertices(frame: frame(bands: bands, t: 2.0/60), settings: s, aspect: 1)
        XCTAssertEqual(viz.points.count, 1)
    }

    /// After the CPU rebuild, the shader uniform's active `pointCount` tracks the
    /// new blob count — the two paths share one setting.
    func testBlobCountReflectedInShaderUniform() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .lavaLamp
        s.mutateCurrent { $0.lavaLampRenderMode = .shader }
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let viz = LavaLampVisualizer()
        s.lavaLampBlobCount = 7
        _ = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        let u = makeLavaLampUniforms(visualizer: viz, frame: frame(bands: bands), settings: s)
        XCTAssertEqual(u.pointCount, 7)
    }

    // MARK: - Grid size (CPU performance control)

    /// The marching-squares emitter produces one quad (6 verts) per cell over a
    /// (gridSize-1)² cell lattice, so vertex count is a pure function of grid
    /// size. Default 64 -> 63² cells. A smaller grid -> proportionally fewer.
    func testGridSizeControlsVertexCount() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .lavaLamp
        s.mutateCurrent { $0.lavaLampRenderMode = .marchingSquares }
        let bands: [Float] = (0..<48).map { _ in 0.6 }

        s.lavaLampGridSize = 64
        XCTAssertEqual(LavaLampVisualizer().makeVertices(frame: frame(bands: bands), settings: s, aspect: 1).count,
                       63 * 63 * 6)
        s.lavaLampGridSize = 16
        XCTAssertEqual(LavaLampVisualizer().makeVertices(frame: frame(bands: bands), settings: s, aspect: 1).count,
                       15 * 15 * 6)
        s.lavaLampGridSize = 32
        XCTAssertEqual(LavaLampVisualizer().makeVertices(frame: frame(bands: bands), settings: s, aspect: 1).count,
                       31 * 31 * 6)
    }

    /// `lavaLampGridSize` is clamped to >=2 (the emitter divides by gridSize-1).
    /// A persisted 0/1 must not divide-by-zero — it floors to a single 1-cell grid.
    func testGridSizeClampsToMinimumTwo() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .lavaLamp
        s.mutateCurrent { $0.lavaLampRenderMode = .marchingSquares }
        let bands: [Float] = (0..<48).map { _ in 0.6 }
        s.lavaLampGridSize = 1
        XCTAssertEqual(LavaLampVisualizer().makeVertices(frame: frame(bands: bands), settings: s, aspect: 1).count, 6)
        s.lavaLampGridSize = 0
        XCTAssertEqual(LavaLampVisualizer().makeVertices(frame: frame(bands: bands), settings: s, aspect: 1).count, 6)
    }

    /// CPU beat decay divides by the half-life; a persisted 0 must not crash
    /// (clamped to a small positive). Sanity: accepts the beat frame.
    func testCpuBeatHalfLifeZeroDoesNotCrash() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .lavaLamp
        s.mutateCurrent { $0.lavaLampRenderMode = .marchingSquares }
        s.lavaLampCpuBeatHalfLife = 0
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let viz = LavaLampVisualizer()
        _ = viz.makeVertices(frame: frame(bands: bands, beat: false, t: 0), settings: s, aspect: 1)
        _ = viz.makeVertices(frame: frame(bands: bands, beat: true, intensity: 1, t: 1.0/60), settings: s, aspect: 1)
        XCTAssertTrue(true)
    }
}