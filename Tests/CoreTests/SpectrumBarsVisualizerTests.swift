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

final class SpectrumBarsVisualizerTests: XCTestCase {
    private func settings(bands: Int, peakHold: Bool, palette: String = "classic") -> VisualizerSettings {
        var s = VisualizerSettings.defaults
        s.barCount = bands
        s.peakHoldEnabled = peakHold
        s.paletteName = palette
        return s
    }

    private func frame(bands: [Float], peaks: [Float]) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: peaks, waveform: [], rms: 0, peak: 0, timestamp: 0)
    }

    func testSixVerticesPerBarWithoutPeakHold() {
        let viz = SpectrumBarsVisualizer()
        let f = frame(bands: [0.2, 0.5, 0.9], peaks: [0.3, 0.6, 1.0])
        let verts = viz.makeVertices(frame: f, settings: settings(bands:3, peakHold: false), aspect: 1)
        XCTAssertEqual(verts.count, 3 * 6)
    }

    func testTwelveVerticesPerBarWithPeakHold() {
        let viz = SpectrumBarsVisualizer()
        let f = frame(bands: [0.2, 0.5, 0.9], peaks: [0.3, 0.6, 1.0])
        let verts = viz.makeVertices(frame: f, settings: settings(bands:3, peakHold: true), aspect: 1)
        XCTAssertEqual(verts.count, 3 * 12)
    }

    func testAllVerticesAreInsideClipSpace() {
        let viz = SpectrumBarsVisualizer()
        let f = frame(bands: [0, 0.5, 1.0], peaks: [0.1, 0.6, 1.0])
        let verts = viz.makeVertices(frame: f, settings: settings(bands:3, peakHold: true), aspect: 1)
        for v in verts {
            XCTAssertTrue((-1...1).contains(v.position.x), "x \(v.position.x) out of clip space")
            XCTAssertTrue((-1...1).contains(v.position.y), "y \(v.position.y) out of clip space")
        }
    }

    func testTallerBarReachesHigher() {
        let viz = SpectrumBarsVisualizer()
        let f = frame(bands: [0.2, 0.8], peaks: [0.2, 0.8])
        let verts = viz.makeVertices(frame: f, settings: settings(bands:2, peakHold: false), aspect: 1)
        let bar0Top = verts[0..<6].map { $0.position.y }.max()!
        let bar1Top = verts[6..<12].map { $0.position.y }.max()!
        XCTAssertGreaterThan(bar1Top, bar0Top)
    }

    func testZeroLevelBarHasZeroHeight() {
        let viz = SpectrumBarsVisualizer()
        let f = frame(bands: [0.0], peaks: [0.0])
        let verts = viz.makeVertices(frame: f, settings: settings(bands:1, peakHold: false), aspect: 1)
        let ys = verts.map { $0.position.y }
        for y in ys { XCTAssertEqual(y, -1, accuracy: 1e-5) }
    }

    func testBottomVertexUsesPaletteBottomColor() {
        let viz = SpectrumBarsVisualizer()
        let f = frame(bands: [1.0], peaks: [1.0])
        let verts = viz.makeVertices(frame: f, settings: settings(bands:1, peakHold: false, palette: "phosphor"), aspect: 1)
        let bottomColor = ColorPalette.preset(named: "phosphor")!.sample(at: 0)
        let bottom = verts.first { abs($0.position.y - (-1)) < 1e-5 }!
        XCTAssertEqual(bottom.color.x, bottomColor.r, accuracy: 1e-4)
        XCTAssertEqual(bottom.color.y, bottomColor.g, accuracy: 1e-4)
        XCTAssertEqual(bottom.color.z, bottomColor.b, accuracy: 1e-4)
    }

    func testStereoModeSplitsLeftRight() {
        var s = VisualizerSettings.defaults
        s.useStereoImage = true
        let L: [Float] = [Float](repeating: 0.8, count: 24)
        let R: [Float] = [Float](repeating: 0.0, count: 24)
        let bands: [Float] = (0..<24).map { _ in 0.4 }   // (L+R)/2
        let frame = AudioFrame(bands: bands, bandsLeft: L, bandsRight: R,
                               bandPeaks: bands, waveform: [],
                               rms: 0.3, peak: 0.8, timestamp: 0)
        let viz = SpectrumBarsVisualizer()
        let verts = viz.makeVertices(frame: frame, settings: s, aspect: 1)
        // With hard-left input, left-half bars should reach much higher than right-half.
        let leftMaxY = verts.filter { $0.position.x < 0 }.map(\.position.y).max() ?? -10
        let rightMaxY = verts.filter { $0.position.x >= 0 }.map(\.position.y).max() ?? -10
        XCTAssertGreaterThan(leftMaxY, rightMaxY + 0.1, "hard-left should drive only the left half")
    }

    func testStereoModeBassAtEdges() {
        var s = VisualizerSettings.defaults
        s.useStereoImage = true
        s.peakHoldEnabled = false
        // bands[0] = bass loud, bands[count-1] = treble quiet on the LEFT channel.
        let bassLoudOnLeft = Array(stride(from: Float(1.0), to: 0.0, by: -1.0/24.0))   // 1.0, 0.96, 0.92, ..., 0.04
        let silence = [Float](repeating: 0, count: 24)
        let bands = zip(bassLoudOnLeft, silence).map { ($0 + $1) / 2 }
        let frame = AudioFrame(bands: bands, bandsLeft: bassLoudOnLeft, bandsRight: silence,
                               bandPeaks: bands, waveform: [], rms: 0.3, peak: 0.8, timestamp: 0)
        let viz = SpectrumBarsVisualizer()
        let verts = viz.makeVertices(frame: frame, settings: s, aspect: 1)
        // Left-half bars: each bar's level should DECREASE as we move toward the center.
        // The leftmost bar (x near -1) should be tallest; the rightmost bar of the left half (x near 0) should be shortest.
        let leftHalfBars = verts.filter { $0.position.x < -0.01 }
        let farLeftMax = leftHalfBars.filter { $0.position.x < -0.5 }.map(\.position.y).max() ?? -10
        let nearCenterMax = leftHalfBars.filter { $0.position.x > -0.3 && $0.position.x < -0.01 }.map(\.position.y).max() ?? -10
        XCTAssertGreaterThan(farLeftMax, nearCenterMax + 0.2, "bass should be at the far-left edge, not near the center")
    }

    func testStereoModePeakHoldEmitsCaps() {
        var s = VisualizerSettings.defaults
        s.useStereoImage = true
        s.peakHoldEnabled = true
        let bands = [Float](repeating: 0.5, count: 24)
        let peaks = [Float](repeating: 0.8, count: 24)
        let frame = AudioFrame(bands: bands, bandsLeft: bands, bandsRight: bands,
                               bandPeaks: peaks, waveform: [], rms: 0.3, peak: 0.8, timestamp: 0)
        let viz = SpectrumBarsVisualizer()
        let verts = viz.makeVertices(frame: frame, settings: s, aspect: 1)
        // With peak hold on, vertex count is 12 per bar (6 main + 6 cap). 24 bars per half × 2 halves × 12 verts = 576.
        XCTAssertEqual(verts.count, 24 * 2 * 12)
    }

    func testStereoModeOffMatchesPriorBehavior() {
        var s = VisualizerSettings.defaults
        s.useStereoImage = false
        s.peakHoldEnabled = false
        let bands: [Float] = (0..<24).map { Float($0) / 24 }
        let frame = AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                               rms: 0, peak: 0, timestamp: 0)
        let viz = SpectrumBarsVisualizer()
        let verts = viz.makeVertices(frame: frame, settings: s, aspect: 1)
        XCTAssertEqual(verts.count, 24 * 6)
    }
}