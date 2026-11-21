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

final class MirroredBarsVisualizerTests: XCTestCase {
    private func frame(_ bands: [Float]) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: bands, waveform: [], rms: 0, peak: 0, timestamp: 0)
    }
    private func settings(_ n: Int) -> VisualizerSettings {
        var s = VisualizerSettings.defaults; s.barCount = n; return s
    }

    func testTwelveVerticesPerBand() {
        let v = MirroredBarsVisualizer().makeVertices(frame: frame([0.3, 0.7]),
                                                      settings: settings(2), aspect: 1)
        XCTAssertEqual(v.count, 2 * 12)
    }

    func testSymmetricAboutCenter() {
        let v = MirroredBarsVisualizer().makeVertices(frame: frame([0.5, 0.9, 0.2]),
                                                      settings: settings(3), aspect: 1)
        for vertex in v {
            let mirrored = v.contains { other in
                abs(other.position.x - vertex.position.x) < 1e-5 &&
                abs(other.position.y + vertex.position.y) < 1e-5
            }
            XCTAssertTrue(mirrored, "no mirror for (\(vertex.position.x), \(vertex.position.y))")
        }
    }

    func testAllVerticesInClipSpace() {
        let v = MirroredBarsVisualizer().makeVertices(frame: frame([1, 1, 1, 1]),
                                                      settings: settings(4), aspect: 1)
        for vertex in v {
            XCTAssertLessThanOrEqual(abs(vertex.position.x), 1.0001)
            XCTAssertLessThanOrEqual(abs(vertex.position.y), 1.0001)
        }
    }

    func testZeroLevelCollapsesToCenter() {
        let v = MirroredBarsVisualizer().makeVertices(frame: frame([0, 0]),
                                                      settings: settings(2), aspect: 1)
        for vertex in v { XCTAssertEqual(vertex.position.y, 0, accuracy: 1e-5) }
    }
}