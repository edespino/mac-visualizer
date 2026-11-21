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

final class IrisVisualizerTests: XCTestCase {

    private func frame(bands: [Float], left: [Float]? = nil, right: [Float]? = nil) -> AudioFrame {
        AudioFrame(bands: bands, bandsLeft: left ?? bands, bandsRight: right ?? bands,
                   bandPeaks: bands, waveform: [0, 0], rms: 0.5, peak: 0.5, timestamp: 0)
    }

    private func settings(_ mutate: (inout VisualizerSettings) -> Void = { _ in }) -> VisualizerSettings {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .iris
        mutate(&s)
        return s
    }

    func testEmitsOneQuadPerPetal() {
        let s = settings { $0.irisPetalCount = 32 }
        let verts = IrisVisualizer().makeVertices(frame: frame(bands: [0.5, 0.5, 0.5, 0.5]),
                                                  settings: s, aspect: 1)
        XCTAssertEqual(verts.count, 32 * 6)
        for v in verts {
            XCTAssertGreaterThanOrEqual(v.position.x, -1)
            XCTAssertLessThanOrEqual(v.position.x, 1)
            XCTAssertGreaterThanOrEqual(v.position.y, -1)
            XCTAssertLessThanOrEqual(v.position.y, 1)
        }
    }

    func testEmptyBandsEmitsNothing() {
        XCTAssertTrue(IrisVisualizer().makeVertices(frame: frame(bands: []),
                                                    settings: settings(), aspect: 1).isEmpty)
    }

    /// Mono content is mirror-symmetric: for every petal there is a twin whose
    /// x coordinates are negated (the Vissonance Iris pairs petals ±angle).
    func testMonoPetalsAreMirrorSymmetric() {
        let s = settings { $0.irisPetalCount = 16 }
        let verts = IrisVisualizer().makeVertices(frame: frame(bands: [0.2, 0.5, 0.8, 0.4]),
                                                  settings: s, aspect: 1)
        XCTAssertEqual(verts.count, 16 * 6)
        // Petal quads come in +angle/-angle pairs: quad 2k and 2k+1.
        for k in 0..<8 {
            let plus = Array(verts[(2 * k) * 6..<(2 * k) * 6 + 6])
            let minus = Array(verts[(2 * k + 1) * 6..<(2 * k + 1) * 6 + 6])
            for (p, m) in zip(plus, minus) {
                XCTAssertEqual(p.position.x, -m.position.x, accuracy: 1e-5)
                XCTAssertEqual(p.position.y, m.position.y, accuracy: 1e-5)
            }
        }
    }

    /// Louder bands extend their petals: a hot band's petal tip reaches
    /// farther from center than a quiet band's.
    func testBandLevelExtendsPetalLength() {
        let s = settings { $0.irisPetalCount = 8 }
        let quiet = IrisVisualizer().makeVertices(frame: frame(bands: [0.05, 0.05]), settings: s, aspect: 1)
        let loud = IrisVisualizer().makeVertices(frame: frame(bands: [0.9, 0.9]), settings: s, aspect: 1)
        func maxRadius(_ vs: [BarVertex]) -> Float {
            vs.map { simd_length(SIMD2<Float>($0.position.x, $0.position.y)) }.max() ?? 0
        }
        XCTAssertGreaterThan(maxRadius(loud), maxRadius(quiet) + 0.1)
    }

    /// With the stereo image on, a hard-left signal lengthens only the x<0
    /// petals (x<0 -> bandsLeft, x>=0 -> bandsRight convention).
    func testStereoSplitDrivesHalvesIndependently() {
        let s = settings { $0.irisPetalCount = 16; $0.useStereoImage = true }
        let f = frame(bands: [0.5, 0.5], left: [1.0, 1.0], right: [0.0, 0.0])
        let verts = IrisVisualizer().makeVertices(frame: f, settings: s, aspect: 1)
        var leftMax: Float = 0, rightMax: Float = 0
        for v in verts {
            let r = simd_length(SIMD2<Float>(v.position.x, v.position.y))
            if v.position.x < -1e-4 { leftMax = max(leftMax, r) }
            if v.position.x > 1e-4 { rightMax = max(rightMax, r) }
        }
        XCTAssertGreaterThan(leftMax, rightMax + 0.1)
    }

    /// Inner vertices are dimmed relative to the tip (the port of the original
    /// depth-gradient fragment shader).
    func testInnerVerticesDimmerThanTips() {
        let s = settings { $0.irisPetalCount = 8; $0.irisInnerDim = 0.3 }
        let verts = IrisVisualizer().makeVertices(frame: frame(bands: [0.7, 0.7]), settings: s, aspect: 1)
        XCTAssertFalse(verts.isEmpty)
        func brightness(_ v: BarVertex) -> Float { v.color.x + v.color.y + v.color.z }
        // Each quad: inner pair carries the dim color, outer pair the full color.
        let quad = Array(verts[0..<6])
        let radii = quad.map { simd_length(SIMD2<Float>($0.position.x, $0.position.y)) }
        let inner = zip(quad, radii).min { $0.1 < $1.1 }!.0
        let outer = zip(quad, radii).max { $0.1 < $1.1 }!.0
        XCTAssertLessThan(brightness(inner), brightness(outer) * 0.5)
    }

    func testAlphaKnobApplied() {
        let s = settings { $0.irisAlpha = 0.35 }
        let verts = IrisVisualizer().makeVertices(frame: frame(bands: [0.5, 0.5]), settings: s, aspect: 1)
        for v in verts { XCTAssertEqual(v.color.w, 0.35, accuracy: 1e-5) }
    }

    func testDeterministicForSameInput() {
        let f = frame(bands: [0.1, 0.6, 0.3, 0.9])
        let a = IrisVisualizer().makeVertices(frame: f, settings: settings(), aspect: 1)
        let b = IrisVisualizer().makeVertices(frame: f, settings: settings(), aspect: 1)
        XCTAssertEqual(a, b)
    }
}
