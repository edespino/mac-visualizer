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

final class SpectrumAnalyzerReconfigureTests: XCTestCase {
    private func analyzer(bands: Int = 24, sr: Float = 48000) -> SpectrumAnalyzer {
        var s = VisualizerSettings.defaults
        s.barCount = bands
        s.gain = 1
        s.smoothing = 0
        return SpectrumAnalyzer(fftSize: 2048, sampleRate: sr, settings: s)
    }

    func testReconfigureBarCountChangesEmittedBandCount() {
        let a = analyzer(bands: 24)
        XCTAssertEqual(a.append(SignalGenerators.silence(count: 2048))!.bands.count, 24)
        a.reconfigure(barCount: 48)
        XCTAssertEqual(a.append(SignalGenerators.silence(count: 2048))!.bands.count, 48)
    }

    func testReconfigureSampleRateShiftsToneBand() {
        // The signal is a fixed 1 kHz tone sampled at 48 kHz (FFT bin ~43, fixed).
        // Telling the mapper the rate is higher labels that bin as a higher frequency,
        // so the tone lands in a HIGHER band index.
        let a = analyzer(bands: 32, sr: 48000)
        let tone = SignalGenerators.sine(frequency: 1000, sampleRate: 48000, count: 2048)
        let bandAt48k = SignalGenerators.argmax(a.append(tone)!.bands)

        a.reconfigure(sampleRate: 96000)
        let bandAt96k = SignalGenerators.argmax(a.append(tone)!.bands)

        XCTAssertGreaterThan(bandAt96k, bandAt48k)
    }

    func testReconfigureAfterUpdateWorks() {
        // Reconfiguring after update() must not crash or zero things out, and must
        // honor the new bar count while still producing output.
        let a = analyzer(bands: 8)
        a.update(gain: 3, smoothing: 0.5, peakHoldEnabled: true)
        a.reconfigure(barCount: 16)
        let frame = a.append(SignalGenerators.sine(frequency: 2000, sampleRate: 48000, count: 2048))!
        XCTAssertEqual(frame.bands.count, 16)
        XCTAssertGreaterThan(frame.bands.max() ?? 0, 0)
    }
}