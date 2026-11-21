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

final class SpectrumAnalyzerStereoTests: XCTestCase {

    private func sineBuffer(freq: Float, sampleRate: Float, samples: Int, amplitude: Float = 1.0) -> [Float] {
        var out = [Float](repeating: 0, count: samples)
        for i in 0..<samples {
            out[i] = amplitude * sinf(2 * .pi * freq * Float(i) / sampleRate)
        }
        return out
    }

    func testMonoAppendMatchesPreviousBehavior() {
        // Feeding identical L and R should yield bandsLeft == bandsRight == bands.
        let s = VisualizerSettings.defaults
        let analyzer = SpectrumAnalyzer(fftSize: 1024, sampleRate: 48000, settings: s)
        let pcm = sineBuffer(freq: 440, sampleRate: 48000, samples: 1024)
        guard let frame = analyzer.append(left: pcm, right: pcm) else {
            return XCTFail("expected a frame on full window")
        }
        XCTAssertEqual(frame.bandsLeft, frame.bandsRight)
        XCTAssertEqual(frame.bandsLeft, frame.bands)
    }

    /// With the notes band mapping active, frame.bands becomes one value per
    /// semitone: a 440 Hz tone peaks in A4's slot and the count matches the
    /// configured note range. Switching back to logSpaced restores barCount
    /// bands.
    func testNoteMappingProducesPerSemitoneBands() {
        let s = VisualizerSettings.defaults
        let analyzer = SpectrumAnalyzer(fftSize: 4096, sampleRate: 48000, settings: s)
        analyzer.setBandMapping(.notes(minMidi: 36, count: 72))
        let pcm = sineBuffer(freq: 440, sampleRate: 48000, samples: 4096)
        guard let frame = analyzer.append(left: pcm, right: pcm) else {
            return XCTFail("expected a frame")
        }
        XCTAssertEqual(frame.bands.count, 72)
        let hot = frame.bands.firstIndex(of: frame.bands.max()!)!
        XCTAssertEqual(hot, 69 - 36, "440 Hz must peak in A4's semitone band")

        analyzer.setBandMapping(.logSpaced)
        guard let back = analyzer.append(left: pcm, right: pcm) else {
            return XCTFail("expected a frame")
        }
        XCTAssertEqual(back.bands.count, s.barCount)
    }

    /// Distinct channel content must surface as distinct per-channel waveforms
    /// (the XY scope plots L against R sample-by-sample), while identical
    /// channels yield identical waveforms equal to the mono waveform.
    func testStereoWaveformsFollowChannelContent() {
        let s = VisualizerSettings.defaults
        let analyzer = SpectrumAnalyzer(fftSize: 1024, sampleRate: 48000, settings: s)
        let pcm = sineBuffer(freq: 440, sampleRate: 48000, samples: 1024)
        let silence = [Float](repeating: 0, count: 1024)
        guard let frame = analyzer.append(left: pcm, right: silence) else {
            return XCTFail("expected a frame")
        }
        XCTAssertEqual(frame.waveformLeft.count, frame.waveform.count)
        XCTAssertEqual(frame.waveformRight.count, frame.waveform.count)
        XCTAssertEqual(frame.waveformLeft, frame.waveform)  // waveform is L-derived
        XCTAssertGreaterThan(frame.waveformLeft.map(abs).max() ?? 0, 0.1)
        XCTAssertEqual(frame.waveformRight.map(abs).max() ?? 1, 0, accuracy: 1e-6)

        let analyzer2 = SpectrumAnalyzer(fftSize: 1024, sampleRate: 48000, settings: s)
        guard let mono = analyzer2.append(left: pcm, right: pcm) else {
            return XCTFail("expected a frame")
        }
        XCTAssertEqual(mono.waveformLeft, mono.waveformRight)
    }

    func testHardLeftMeansRightIsSilent() {
        let s = VisualizerSettings.defaults
        let analyzer = SpectrumAnalyzer(fftSize: 1024, sampleRate: 48000, settings: s)
        let pcm = sineBuffer(freq: 440, sampleRate: 48000, samples: 1024)
        let silence = [Float](repeating: 0, count: 1024)
        guard let frame = analyzer.append(left: pcm, right: silence) else {
            return XCTFail("expected a frame")
        }
        let leftSum = frame.bandsLeft.reduce(0, +)
        let rightSum = frame.bandsRight.reduce(0, +)
        XCTAssertGreaterThan(leftSum, 0)
        XCTAssertEqual(rightSum, 0, accuracy: 1e-3)
        // Mean invariant.
        for i in 0..<frame.bands.count {
            XCTAssertEqual(frame.bands[i], (frame.bandsLeft[i] + frame.bandsRight[i]) / 2, accuracy: 1e-6)
        }
    }

    func testHardRightMeansLeftIsSilent() {
        let s = VisualizerSettings.defaults
        let analyzer = SpectrumAnalyzer(fftSize: 1024, sampleRate: 48000, settings: s)
        let pcm = sineBuffer(freq: 440, sampleRate: 48000, samples: 1024)
        let silence = [Float](repeating: 0, count: 1024)
        guard let frame = analyzer.append(left: silence, right: pcm) else {
            return XCTFail("expected a frame")
        }
        let leftSum = frame.bandsLeft.reduce(0, +)
        let rightSum = frame.bandsRight.reduce(0, +)
        XCTAssertEqual(leftSum, 0, accuracy: 1e-3)
        XCTAssertGreaterThan(rightSum, 0)
    }
}