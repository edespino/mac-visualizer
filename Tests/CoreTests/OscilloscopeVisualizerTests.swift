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

final class OscilloscopeVisualizerTests: XCTestCase {
    private func frame(_ wave: [Float]) -> AudioFrame {
        AudioFrame(bands: [], bandPeaks: [], waveform: wave, rms: 0, peak: 0, timestamp: 0)
    }

    func testSixVerticesPerSegment() {
        let v = OscilloscopeVisualizer().makeVertices(frame: frame([0, 0.5, -0.5, 0.2]),
                                                      settings: .defaults, aspect: 1)
        XCTAssertEqual(v.count, (4 - 1) * 6)
    }

    func testEmptyOrSingleSampleYieldsNothing() {
        XCTAssertTrue(OscilloscopeVisualizer().makeVertices(frame: frame([]), settings: .defaults, aspect: 1).isEmpty)
        XCTAssertTrue(OscilloscopeVisualizer().makeVertices(frame: frame([0.5]), settings: .defaults, aspect: 1).isEmpty)
    }

    func testAllVerticesInClipSpace() {
        let wave = (0..<128).map { sinf(Float($0) / 128 * 2 * .pi * 4) }
        let v = OscilloscopeVisualizer().makeVertices(frame: frame(wave), settings: .defaults, aspect: 1)
        for vertex in v {
            XCTAssertLessThanOrEqual(abs(vertex.position.x), 1.0001)
            XCTAssertLessThanOrEqual(abs(vertex.position.y), 1.0001)
        }
    }

    func testSilentWaveformIsFlatNearZero() {
        let v = OscilloscopeVisualizer().makeVertices(frame: frame([Float](repeating: 0, count: 64)),
                                                      settings: .defaults, aspect: 1)
        for vertex in v { XCTAssertLessThan(abs(vertex.position.y), 0.02) }
    }
}