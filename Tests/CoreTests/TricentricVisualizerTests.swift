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

final class TricentricVisualizerTests: XCTestCase {

    private func frame(bands: [Float], timestamp: Double = 0) -> AudioFrame {
        AudioFrame(bands: bands, bandsLeft: bands, bandsRight: bands,
                   bandPeaks: bands, waveform: [0, 0], rms: 0.5, peak: 0.5,
                   timestamp: timestamp)
    }

    private func settings(_ mutate: (inout VisualizerSettings) -> Void = { _ in }) -> VisualizerSettings {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .tricentric
        mutate(&s)
        return s
    }

    /// Each ring is a triangle outline: 3 edges × 6 vertices.
    func testEmitsThreeEdgeQuadsPerRing() {
        let s = settings { $0.tricentricRingCount = 8 }
        let verts = TricentricVisualizer().makeVertices(frame: frame(bands: [0.5, 0.5]),
                                                        settings: s, aspect: 1)
        XCTAssertEqual(verts.count, 8 * 3 * 6)
        for v in verts {
            XCTAssertGreaterThanOrEqual(v.position.x, -1)
            XCTAssertLessThanOrEqual(v.position.x, 1)
            XCTAssertGreaterThanOrEqual(v.position.y, -1)
            XCTAssertLessThanOrEqual(v.position.y, 1)
        }
    }

    func testEmptyBandsEmitsNothing() {
        XCTAssertTrue(TricentricVisualizer().makeVertices(frame: frame(bands: []),
                                                          settings: settings(), aspect: 1).isEmpty)
    }

    /// Hot bands scale their ring up; the scale floor keeps silent rings visible.
    func testBandLevelScalesRing() {
        let s = settings { $0.tricentricRingCount = 2 }
        let verts = TricentricVisualizer().makeVertices(frame: frame(bands: [0.9, 0.05]),
                                                        settings: s, aspect: 1)
        let perRing = 3 * 6
        let hot = Array(verts[0..<perRing])
        let cold = Array(verts[perRing..<perRing * 2])
        func maxRadius(_ vs: [BarVertex]) -> Float {
            vs.map { simd_length(SIMD2<Float>($0.position.x, $0.position.y)) }.max() ?? 0
        }
        XCTAssertGreaterThan(maxRadius(hot), maxRadius(cold))
        XCTAssertGreaterThan(maxRadius(cold), 0)  // scale floor
    }

    /// Successive rings shrink toward the center (the 2D stand-in for the
    /// original's receding-z tunnel).
    func testRadiusFalloffShrinksSuccessiveRings() {
        let s = settings { $0.tricentricRingCount = 4 }
        let verts = TricentricVisualizer().makeVertices(frame: frame(bands: [0.5]),
                                                        settings: s, aspect: 1)
        let perRing = 3 * 6
        var radii: [Float] = []
        for r in 0..<4 {
            let ring = Array(verts[r * perRing..<(r + 1) * perRing])
            radii.append(ring.map { simd_length(SIMD2<Float>($0.position.x, $0.position.y)) }.max() ?? 0)
        }
        for i in 1..<radii.count {
            XCTAssertLessThan(radii[i], radii[i - 1])
        }
    }

    /// Loudness rotates the tunnel over time: with audio present, geometry at
    /// a later timestamp is rotated relative to the earlier frame.
    func testLoudnessDrivenRotationAdvancesWithTime() {
        let v = TricentricVisualizer()
        let s = settings { $0.tricentricRingCount = 1 }
        let a = v.makeVertices(frame: frame(bands: [0.8], timestamp: 0), settings: s, aspect: 1)
        let b = v.makeVertices(frame: frame(bands: [0.8], timestamp: 0.5), settings: s, aspect: 1)
        XCTAssertEqual(a.count, b.count)
        var moved = false
        for (x, y) in zip(a, b) where abs(x.position.x - y.position.x) > 1e-4 { _ = (x, y); moved = true }
        XCTAssertTrue(moved, "rotation should displace vertices between frames")
    }

    func testRotationSpeedZeroFreezesGeometry() {
        let v = TricentricVisualizer()
        let s = settings { $0.tricentricRingCount = 1; $0.tricentricRotationSpeed = 0 }
        let a = v.makeVertices(frame: frame(bands: [0.8], timestamp: 0), settings: s, aspect: 1)
        let b = v.makeVertices(frame: frame(bands: [0.8], timestamp: 0.5), settings: s, aspect: 1)
        XCTAssertEqual(a, b)
    }

    func testAlphaKnobScalesOpacity() {
        let full = TricentricVisualizer().makeVertices(frame: frame(bands: [0.5]),
                                                       settings: settings { $0.tricentricAlpha = 1.0 },
                                                       aspect: 1)
        let half = TricentricVisualizer().makeVertices(frame: frame(bands: [0.5]),
                                                       settings: settings { $0.tricentricAlpha = 0.5 },
                                                       aspect: 1)
        XCTAssertFalse(full.isEmpty)
        XCTAssertEqual(half[0].color.w, full[0].color.w * 0.5, accuracy: 1e-5)
    }
}
