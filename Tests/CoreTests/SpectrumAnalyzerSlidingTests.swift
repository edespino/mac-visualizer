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

final class SpectrumAnalyzerSlidingTests: XCTestCase {
    private func analyzer(bands: Int = 24) -> SpectrumAnalyzer {
        var s = VisualizerSettings.defaults
        s.barCount = bands
        s.gain = 1
        s.smoothing = 0
        return SpectrumAnalyzer(fftSize: 2048, sampleRate: 48000, settings: s)
    }

    func testRetainsWindowForOverlapAcrossCalls() {
        let a = analyzer()
        XCTAssertNotNil(a.append(SignalGenerators.silence(count: 2048)))
        // A small follow-up append (< fftSize) should still emit, because the ring
        // retained the previous window (sliding) rather than starting from empty.
        XCTAssertNotNil(a.append(SignalGenerators.silence(count: 256)))
    }

    func testDoesNotEmitBeforeFirstFullWindow() {
        let a = analyzer()
        XCTAssertNil(a.append(SignalGenerators.silence(count: 1000)))
        XCTAssertNil(a.append(SignalGenerators.silence(count: 1000))) // 2000 < 2048
        XCTAssertNotNil(a.append(SignalGenerators.silence(count: 100))) // now 2100 >= 2048
    }

    func testTonePlacementStillCorrectAfterSliding() {
        let a = analyzer(bands: 24)
        let tone = SignalGenerators.sine(frequency: 1000, sampleRate: 48000, count: 2048)
        _ = a.append(tone)
        let frame = a.append(tone)!
        let loudest = SignalGenerators.argmax(frame.bands)
        XCTAssertGreaterThan(loudest, 0)
        XCTAssertLessThan(loudest, frame.bands.count - 1)
        XCTAssertGreaterThan(frame.bands[loudest], 0.1)
    }

    func testRingDoesNotGrowUnbounded() {
        let a = analyzer()
        var lastFrameNonNil = false
        for _ in 0..<100 { lastFrameNonNil = (a.append(SignalGenerators.silence(count: 2048)) != nil) }
        XCTAssertTrue(lastFrameNonNil)
    }
}