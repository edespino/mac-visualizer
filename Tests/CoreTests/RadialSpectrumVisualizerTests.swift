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

final class RadialSpectrumVisualizerTests: XCTestCase {
    private func frame(_ bands: [Float]) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: bands, waveform: [], rms: 0, peak: 0, timestamp: 0)
    }
    private func settings(_ n: Int) -> VisualizerSettings {
        var s = VisualizerSettings.defaults; s.barCount = n; return s
    }

    func testSixVerticesPerBand() {
        let v = RadialSpectrumVisualizer().makeVertices(frame: frame([0.2, 0.5, 0.9]),
                                                        settings: settings(3), aspect: 1)
        XCTAssertEqual(v.count, 3 * 6)
    }

    func testAllVerticesInClipSpace() {
        for aspect: Float in [0.5, 1, 2] {
            let v = RadialSpectrumVisualizer().makeVertices(frame: frame([1, 1, 1, 1]),
                                                            settings: settings(4), aspect: aspect)
            for vertex in v {
                XCTAssertLessThanOrEqual(abs(vertex.position.x), 1.0001, "x out at aspect \(aspect)")
                XCTAssertLessThanOrEqual(abs(vertex.position.y), 1.0001, "y out at aspect \(aspect)")
            }
        }
    }

    func testWideAspectStaysRound() {
        let v = RadialSpectrumVisualizer().makeVertices(frame: frame([1, 1, 1, 1, 1, 1, 1, 1]),
                                                        settings: settings(8), aspect: 2)
        let maxX = v.map { abs($0.position.x) }.max()!
        let maxY = v.map { abs($0.position.y) }.max()!
        XCTAssertLessThan(maxX, maxY)
    }

    func testZeroBandsCollapseToInnerRadius() {
        let v = RadialSpectrumVisualizer().makeVertices(frame: frame([0, 0, 0, 0]),
                                                        settings: settings(4), aspect: 1)
        let maxR = v.map { sqrt($0.position.x * $0.position.x + $0.position.y * $0.position.y) }.max()!
        XCTAssertEqual(maxR, 0.25, accuracy: 0.02)
    }

    func testStereoPanOffCentersAtZero() {
        var s = VisualizerSettings.defaults
        s.useStereoImage = false
        let bands = [Float](repeating: 0.5, count: 32)
        let f = AudioFrame(bands: bands, bandsLeft: bands, bandsRight: bands,
                           bandPeaks: bands, waveform: [], rms: 0, peak: 0, timestamp: 0)
        let viz = RadialSpectrumVisualizer()
        let verts = viz.makeVertices(frame: f, settings: s, aspect: 1)
        // Center of mass of the X positions should be near 0.
        let mean = verts.map(\.position.x).reduce(0, +) / Float(verts.count)
        XCTAssertEqual(mean, 0, accuracy: 0.05)
    }

    func testStereoPanHardLeftShiftsCenterNegative() {
        var s = VisualizerSettings.defaults
        s.useStereoImage = true
        let L = [Float](repeating: 0.8, count: 32)
        let R = [Float](repeating: 0.0, count: 32)
        let bands = zip(L, R).map { ($0 + $1) / 2 }
        let f = AudioFrame(bands: bands, bandsLeft: L, bandsRight: R,
                           bandPeaks: bands, waveform: [], rms: 0, peak: 0, timestamp: 0)
        let viz = RadialSpectrumVisualizer()
        let verts = viz.makeVertices(frame: f, settings: s, aspect: 1)
        let mean = verts.map(\.position.x).reduce(0, +) / Float(verts.count)
        XCTAssertLessThan(mean, -0.02)
    }
}