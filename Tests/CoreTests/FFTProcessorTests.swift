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

final class FFTProcessorTests: XCTestCase {
    func testMagnitudeLengthIsHalfTheInput() {
        let fft = FFTProcessor(size: 2048)
        let input = SignalGenerators.silence(count: 2048)
        XCTAssertEqual(fft.magnitudes(of: input).count, 1024)
    }

    func testSineWavePeaksInExpectedBin() {
        let size = 2048
        let sampleRate: Float = 48000
        let frequency: Float = 1000
        let fft = FFTProcessor(size: size)
        let window = makeHannWindow(size)

        let raw = SignalGenerators.sine(frequency: frequency, sampleRate: sampleRate, count: size)
        let windowed = zip(raw, window).map(*)

        let mags = fft.magnitudes(of: windowed)
        let peakBin = SignalGenerators.argmax(mags)

        let expectedBin = Int((frequency * Float(size) / sampleRate).rounded())
        XCTAssertEqual(peakBin, expectedBin, accuracy: 1)
    }

    func testSilenceProducesNearZeroMagnitudes() {
        let fft = FFTProcessor(size: 1024)
        let mags = fft.magnitudes(of: SignalGenerators.silence(count: 1024))
        XCTAssertLessThan(mags.max() ?? 0, 1e-5)
    }
}