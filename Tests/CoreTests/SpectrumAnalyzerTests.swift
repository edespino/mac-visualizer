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

final class SpectrumAnalyzerTests: XCTestCase {
    private func makeAnalyzer(bands: Int = 24) -> SpectrumAnalyzer {
        var settings = VisualizerSettings.defaults
        settings.barCount = bands
        settings.gain = 1
        settings.smoothing = 0   // deterministic: output = current frame
        return SpectrumAnalyzer(fftSize: 2048, sampleRate: 48000, settings: settings)
    }

    func testReturnsNilUntilEnoughSamples() {
        let analyzer = makeAnalyzer()
        let half = SignalGenerators.silence(count: 1024)
        XCTAssertNil(analyzer.append(half))
    }

    func testEmitsFrameWithRequestedBandCount() {
        let analyzer = makeAnalyzer(bands: 24)
        let frame = analyzer.append(SignalGenerators.silence(count: 2048))
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame!.bands.count, 24)
        XCTAssertEqual(frame!.bandPeaks.count, 24)
    }

    func testSilenceYieldsZeroEnergy() {
        let analyzer = makeAnalyzer()
        let frame = analyzer.append(SignalGenerators.silence(count: 2048))!
        XCTAssertEqual(frame.rms, 0, accuracy: 1e-4)
        XCTAssertEqual(frame.peak, 0, accuracy: 1e-4)
        XCTAssertEqual(frame.bands.max() ?? 0, 0, accuracy: 1e-3)
        XCTAssertEqual(frame.bandPeaks.max() ?? 0, 0, accuracy: 1e-3)
    }

    func testToneEnergyConcentratesInExpectedBand() {
        let analyzer = makeAnalyzer(bands: 24)
        let tone = SignalGenerators.sine(frequency: 1000, sampleRate: 48000, count: 2048)
        let frame = analyzer.append(tone)!

        let loudest = SignalGenerators.argmax(frame.bands)
        // 1 kHz must not land in the lowest band (sub-bass) nor the very top band.
        XCTAssertGreaterThan(loudest, 0)
        XCTAssertLessThan(loudest, frame.bands.count - 1)
        XCTAssertGreaterThan(frame.bands[loudest], 0.1)
        XCTAssertGreaterThan(frame.rms, 0)
    }

    func testAccumulatesAcrossMultipleAppends() {
        let analyzer = makeAnalyzer()
        XCTAssertNil(analyzer.append(SignalGenerators.silence(count: 1024)))
        let frame = analyzer.append(SignalGenerators.silence(count: 1024))
        XCTAssertNotNil(frame)
    }

    func testAnalyzerAttachesBeatInfoToFrame() {
        let s = VisualizerSettings.defaults
        let analyzer = SpectrumAnalyzer(fftSize: 1024, sampleRate: 48000, settings: s)
        // First buffer of silence to fill the FFT window.
        let silent = [Float](repeating: 0, count: 1024)
        _ = analyzer.append(silent)
        // Now a loud impulse: ramp to 1 in one window. Expect at least one beat
        // attached to a returned frame over 30 windows.
        var beats = 0
        for w in 0..<30 {
            let pcm: [Float] = (w == 3) ? [Float](repeating: 1.0, count: 1024) : silent
            if let frame = analyzer.append(pcm) {
                if frame.beat { beats += 1 }
            }
        }
        XCTAssertGreaterThan(beats, 0, "expected analyzer to attach at least one beat across 30 windows")
    }

    func testBassEnergyHigherForLowFrequencyInput() {
        // A ~60 Hz tone sits inside the follower's ~30–150 Hz window; a ~4 kHz
        // tone of equal amplitude sits far outside it.
        let lowTone = SignalGenerators.sine(frequency: 60, sampleRate: 48000, count: 2048)
        let highTone = SignalGenerators.sine(frequency: 4000, sampleRate: 48000, count: 2048)
        let lowEnergy = makeAnalyzer().append(lowTone)!.bassEnergy
        let highEnergy = makeAnalyzer().append(highTone)!.bassEnergy
        XCTAssertGreaterThan(lowEnergy, highEnergy)
    }

    func testBassEnergyIndependentOfBandMappingAndBarCount() {
        // bassEnergy comes off the raw FFT magnitudes, so the same samples must
        // yield the same value whatever the band mapping / barCount is.
        let signal = SignalGenerators.sine(frequency: 60, sampleRate: 48000, count: 2048)
        let analyzer = makeAnalyzer(bands: 16)
        let e1 = analyzer.append(signal)!.bassEnergy
        analyzer.reconfigure(barCount: 128)
        analyzer.setBandMapping(.notes(minMidi: 36, count: 96))
        let e2 = analyzer.append(signal)!.bassEnergy
        XCTAssertGreaterThan(e1, 0)
        XCTAssertEqual(e1, e2, accuracy: 1e-6)
    }
}