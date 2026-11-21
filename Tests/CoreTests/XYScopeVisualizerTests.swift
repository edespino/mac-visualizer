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

final class XYScopeVisualizerTests: XCTestCase {

    private func frame(left: [Float], right: [Float],
                       beat: Bool = false, beatIntensity: Float = 0,
                       timestamp: Double = 0) -> AudioFrame {
        AudioFrame(bands: [0.5], bandsLeft: [0.5], bandsRight: [0.5],
                   bandPeaks: [0.5], waveform: left,
                   waveformLeft: left, waveformRight: right,
                   rms: 0.5, peak: 0.5, timestamp: timestamp,
                   beat: beat, beatIntensity: beatIntensity)
    }

    private func settings(_ mutate: (inout VisualizerSettings) -> Void = { _ in }) -> VisualizerSettings {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .xyScope
        mutate(&s)
        return s
    }

    func testEmitsOneQuadPerSegment() {
        let v = XYScopeVisualizer()
        let f = frame(left: [0.1, 0.3, -0.2, 0.4], right: [-0.1, 0.2, 0.3, -0.4])
        let verts = v.makeVertices(frame: f, settings: settings(), aspect: 1)
        XCTAssertEqual(verts.count, 3 * 6)
        for vert in verts {
            XCTAssertGreaterThanOrEqual(vert.position.x, -1)
            XCTAssertLessThanOrEqual(vert.position.x, 1)
            XCTAssertGreaterThanOrEqual(vert.position.y, -1)
            XCTAssertLessThanOrEqual(vert.position.y, 1)
        }
    }

    func testFewerThanTwoPointsEmitsNothing() {
        let v = XYScopeVisualizer()
        XCTAssertTrue(v.makeVertices(frame: frame(left: [0.5], right: [0.5]),
                                     settings: settings(), aspect: 1).isEmpty)
        XCTAssertTrue(v.makeVertices(frame: frame(left: [], right: []),
                                     settings: settings(), aspect: 1).isEmpty)
    }

    /// The default 45° rotation is the goniometer convention: identical L and R
    /// (mono) collapse onto the vertical axis.
    func testMonoCollapsesToVerticalLineAtDefaultRotation() {
        let v = XYScopeVisualizer()
        let mono: [Float] = [0.1, 0.5, -0.3, 0.7, -0.6]
        let verts = v.makeVertices(frame: frame(left: mono, right: mono),
                                   settings: settings(), aspect: 1)
        XCTAssertFalse(verts.isEmpty)
        // Segment quads offset perpendicular to a vertical line — in x — by the
        // half-thickness, so |x| stays within that offset.
        let halfThickness = Float(VisualizerSettings.defaults.xyScopeLineHalfThickness)
        for vert in verts {
            XCTAssertLessThanOrEqual(abs(vert.position.x), halfThickness + 1e-5)
        }
    }

    /// Rotation 0 is the raw Lissajous convention: left drives x, right drives y.
    func testZeroRotationPlotsLeftOnXRightOnY() {
        let v = XYScopeVisualizer()
        let s = settings { $0.xyScopeRotationDegrees = 0 }
        // Right channel silent: the trace hugs the x axis.
        let verts = v.makeVertices(frame: frame(left: [0.2, 0.6, -0.4], right: [0, 0, 0]),
                                   settings: s, aspect: 1)
        XCTAssertFalse(verts.isEmpty)
        let halfThickness = Float(VisualizerSettings.defaults.xyScopeLineHalfThickness)
        for vert in verts {
            XCTAssertLessThanOrEqual(abs(vert.position.y), halfThickness + 1e-5)
        }
        XCTAssertGreaterThan(verts.map { abs($0.position.x) }.max() ?? 0, 0.3)
    }

    func testGainScalesDeflection() {
        let f = frame(left: [0.1, 0.2, -0.15], right: [-0.1, 0.15, 0.2])
        let small = XYScopeVisualizer().makeVertices(frame: f, settings: settings { $0.xyScopeGain = 0.5 }, aspect: 1)
        let large = XYScopeVisualizer().makeVertices(frame: f, settings: settings { $0.xyScopeGain = 2.0 }, aspect: 1)
        let smallMax = small.map { max(abs($0.position.x), abs($0.position.y)) }.max() ?? 0
        let largeMax = large.map { max(abs($0.position.x), abs($0.position.y)) }.max() ?? 0
        XCTAssertGreaterThan(largeMax, smallMax * 2)
    }

    func testAspectCorrectionKeepsScopeSquare() {
        let f = frame(left: [0.5, -0.5], right: [0, 0])
        let s = settings { $0.xyScopeRotationDegrees = 0 }
        let square = XYScopeVisualizer().makeVertices(frame: f, settings: s, aspect: 1)
        let wide = XYScopeVisualizer().makeVertices(frame: f, settings: s, aspect: 2)
        let squareMaxX = square.map { abs($0.position.x) }.max() ?? 0
        let wideMaxX = wide.map { abs($0.position.x) }.max() ?? 0
        XCTAssertEqual(wideMaxX, squareMaxX / 2, accuracy: 1e-5)
    }

    func testSampleCountLimitsSegments() {
        let n = 64
        let left = (0..<n).map { Float(sin(Double($0) * 0.3)) }
        let right = (0..<n).map { Float(cos(Double($0) * 0.3)) }
        let s = settings { $0.xyScopeSampleCount = 8 }
        let verts = XYScopeVisualizer().makeVertices(frame: frame(left: left, right: right),
                                                     settings: s, aspect: 1)
        XCTAssertEqual(verts.count, 7 * 6)
    }

    func testAlphaKnobAppliedToColors() {
        let f = frame(left: [0.3, -0.3, 0.2], right: [0.2, 0.1, -0.2])
        let s = settings { $0.xyScopeAlpha = 0.4 }
        let verts = XYScopeVisualizer().makeVertices(frame: f, settings: s, aspect: 1)
        XCTAssertFalse(verts.isEmpty)
        for vert in verts {
            XCTAssertEqual(vert.color.w, 0.4, accuracy: 1e-5)
        }
    }

    func testDeterministicForSameInput() {
        let f = frame(left: [0.1, 0.4, -0.2, 0.3], right: [-0.3, 0.2, 0.25, -0.1])
        let a = XYScopeVisualizer().makeVertices(frame: f, settings: settings(), aspect: 1)
        let b = XYScopeVisualizer().makeVertices(frame: f, settings: settings(), aspect: 1)
        XCTAssertEqual(a, b)
    }

    /// A beat frame expands the trace by 1 + boost×intensity; the boost decays
    /// on subsequent frames with the configured half-life.
    func testBeatBoostExpandsTraceAndDecays() {
        let v = XYScopeVisualizer()
        let s = settings { $0.xyScopeBeatBoost = 1.0; $0.xyScopeBeatHalfLife = 0.1 }
        let quiet = v.makeVertices(frame: frame(left: [0.2, -0.2], right: [0.1, -0.1], timestamp: 0),
                                   settings: s, aspect: 1)
        let onBeat = v.makeVertices(frame: frame(left: [0.2, -0.2], right: [0.1, -0.1],
                                                 beat: true, beatIntensity: 1, timestamp: 0.016),
                                    settings: s, aspect: 1)
        let quietMax = quiet.map { abs($0.position.y) }.max() ?? 0
        let beatMax = onBeat.map { abs($0.position.y) }.max() ?? 0
        XCTAssertGreaterThan(beatMax, quietMax * 1.5)

        // Several half-lives later the boost has decayed back toward baseline.
        let later = v.makeVertices(frame: frame(left: [0.2, -0.2], right: [0.1, -0.1], timestamp: 1.5),
                                   settings: s, aspect: 1)
        let laterMax = later.map { abs($0.position.y) }.max() ?? 0
        XCTAssertLessThan(laterMax, beatMax * 0.7)
    }
}
