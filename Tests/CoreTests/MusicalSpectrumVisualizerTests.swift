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

final class MusicalSpectrumVisualizerTests: XCTestCase {

    private func frame(bands: [Float]) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: bands, waveform: [0, 0],
                   rms: 0.5, peak: 0.5, timestamp: 0)
    }

    private func settings(_ mutate: (inout VisualizerSettings) -> Void = { _ in }) -> VisualizerSettings {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .musicalSpectrum
        mutate(&s)
        return s
    }

    func testEmitsOneQuadPerBand() {
        let bands = (0..<24).map { Float($0) / 23 }
        let verts = MusicalSpectrumVisualizer().makeVertices(frame: frame(bands: bands),
                                                             settings: settings(), aspect: 1)
        XCTAssertEqual(verts.count, 24 * 6)
        for v in verts {
            XCTAssertGreaterThanOrEqual(v.position.x, -1)
            XCTAssertLessThanOrEqual(v.position.x, 1)
            XCTAssertGreaterThanOrEqual(v.position.y, -1)
            XCTAssertLessThanOrEqual(v.position.y, 1)
        }
    }

    func testEmptyBandsEmitsNothing() {
        XCTAssertTrue(MusicalSpectrumVisualizer().makeVertices(frame: frame(bands: []),
                                                               settings: settings(), aspect: 1).isEmpty)
    }

    func testBarsSitOnTheBottomEdge() {
        let verts = MusicalSpectrumVisualizer().makeVertices(frame: frame(bands: [0.2, 0.8]),
                                                             settings: settings(), aspect: 1)
        let minY = verts.map { $0.position.y }.min()!
        XCTAssertEqual(minY, -1, accuracy: 1e-5)
    }

    /// Bar height follows the band level.
    func testBarHeightFollowsLevel() {
        let verts = MusicalSpectrumVisualizer().makeVertices(frame: frame(bands: [0.1, 0.9]),
                                                             settings: settings(), aspect: 1)
        let quiet = Array(verts[0..<6])
        let loud = Array(verts[6..<12])
        XCTAssertGreaterThan(loud.map { $0.position.y }.max()!,
                             quiet.map { $0.position.y }.max()! + 0.5)
    }

    /// With pitch-class coloring on, the same note one octave apart shares its
    /// color hue (bands i and i+12).
    func testPitchClassColoringRepeatsEveryOctave() {
        let bands = [Float](repeating: 0.8, count: 24)
        let s = settings { $0.musicalPitchClassColoring = true }
        let verts = MusicalSpectrumVisualizer().makeVertices(frame: frame(bands: bands),
                                                             settings: s, aspect: 1)
        // Same pitch class, same level -> identical colors.
        XCTAssertEqual(verts[0].color, verts[12 * 6].color)
        // Different pitch classes differ (C vs F#, maximally separated).
        XCTAssertNotEqual(verts[0].color, verts[6 * 6].color)
    }

    /// The octave gap leaves extra horizontal space every 12 bars: the gap
    /// between bar 11 and bar 12 exceeds the gap between bar 10 and bar 11.
    func testOctaveGapSeparatesOctaves() {
        let bands = [Float](repeating: 0.5, count: 24)
        let s = settings { $0.musicalOctaveGap = 1.0 }
        let verts = MusicalSpectrumVisualizer().makeVertices(frame: frame(bands: bands),
                                                             settings: s, aspect: 1)
        func barMinX(_ i: Int) -> Float { verts[i * 6..<(i + 1) * 6].map { $0.position.x }.min()! }
        func barMaxX(_ i: Int) -> Float { verts[i * 6..<(i + 1) * 6].map { $0.position.x }.max()! }
        let withinOctave = barMinX(11) - barMaxX(10)
        let acrossOctave = barMinX(12) - barMaxX(11)
        XCTAssertGreaterThan(acrossOctave, withinOctave + 1e-4)
    }

    func testAlphaKnobApplied() {
        let s = settings { $0.musicalAlpha = 0.45 }
        let verts = MusicalSpectrumVisualizer().makeVertices(frame: frame(bands: [0.5, 0.6]),
                                                             settings: s, aspect: 1)
        for v in verts { XCTAssertEqual(v.color.w, 0.45, accuracy: 1e-5) }
    }

    func testDeterministicForSameInput() {
        let bands = (0..<36).map { Float($0 % 7) / 7 }
        let a = MusicalSpectrumVisualizer().makeVertices(frame: frame(bands: bands),
                                                         settings: settings(), aspect: 1)
        let b = MusicalSpectrumVisualizer().makeVertices(frame: frame(bands: bands),
                                                         settings: settings(), aspect: 1)
        XCTAssertEqual(a, b)
    }
}
