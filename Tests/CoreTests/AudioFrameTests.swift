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

final class AudioFrameStereoWaveformTests: XCTestCase {
    /// Mono init duplicates the waveform into both channel waveforms, mirroring
    /// the bands convention (`bandsLeft == bandsRight == bands`).
    func testMonoInitDuplicatesWaveformIntoBothChannels() {
        let f = AudioFrame(bands: [0.5], bandPeaks: [0.5], waveform: [0.1, -0.2, 0.3],
                           rms: 0, peak: 0, timestamp: 0)
        XCTAssertEqual(f.waveformLeft, [0.1, -0.2, 0.3])
        XCTAssertEqual(f.waveformRight, [0.1, -0.2, 0.3])
    }

    /// Stereo init without explicit channel waveforms falls back to the mono
    /// waveform (so existing constructors keep working and mono sources yield
    /// a degenerate-but-correct XY trace).
    func testStereoInitDefaultsChannelWaveformsToMono() {
        let f = AudioFrame(bands: [0.5], bandsLeft: [1], bandsRight: [0],
                           bandPeaks: [0.5], waveform: [0.4, 0.5],
                           rms: 0, peak: 0, timestamp: 0)
        XCTAssertEqual(f.waveformLeft, [0.4, 0.5])
        XCTAssertEqual(f.waveformRight, [0.4, 0.5])
    }

    /// Explicit stereo waveforms are stored verbatim.
    func testStereoInitStoresExplicitChannelWaveforms() {
        let f = AudioFrame(bands: [0.5], bandsLeft: [1], bandsRight: [0],
                           bandPeaks: [0.5], waveform: [0.4],
                           waveformLeft: [1, 2], waveformRight: [3, 4],
                           rms: 0, peak: 0, timestamp: 0)
        XCTAssertEqual(f.waveformLeft, [1, 2])
        XCTAssertEqual(f.waveformRight, [3, 4])
    }
}

final class AudioFrameTests: XCTestCase {
    func testSilentHasZeroEnergyAndNoBands() {
        let frame = AudioFrame.silent
        XCTAssertEqual(frame.rms, 0)
        XCTAssertEqual(frame.peak, 0)
        XCTAssertTrue(frame.bands.isEmpty)
        XCTAssertTrue(frame.bandPeaks.isEmpty)
        XCTAssertTrue(frame.waveform.isEmpty)
        XCTAssertEqual(frame.timestamp, 0)
    }

    func testInitStoresValues() {
        let frame = AudioFrame(bands: [0.1, 0.2], bandPeaks: [0.15, 0.25],
                               waveform: [0.0, 0.5, -0.5], rms: 0.4, peak: 0.9, timestamp: 12.5)
        XCTAssertEqual(frame.bands, [0.1, 0.2])
        XCTAssertEqual(frame.bandPeaks, [0.15, 0.25])
        XCTAssertEqual(frame.waveform, [0.0, 0.5, -0.5])
        XCTAssertEqual(frame.rms, 0.4)
        XCTAssertEqual(frame.peak, 0.9)
        XCTAssertEqual(frame.timestamp, 12.5)
    }

    func testBeatFieldsDefaultToFalseZero() {
        let f = AudioFrame(bands: [0.1, 0.2], bandPeaks: [0.1, 0.2], waveform: [],
                           rms: 0, peak: 0, timestamp: 0)
        XCTAssertEqual(f.beat, false)
        XCTAssertEqual(f.beatIntensity, 0)
    }

    func testBeatFieldsAcceptExplicitValues() {
        let f = AudioFrame(bands: [], bandPeaks: [], waveform: [],
                           rms: 0, peak: 0, timestamp: 0,
                           beat: true, beatIntensity: 0.7)
        XCTAssertEqual(f.beat, true)
        XCTAssertEqual(f.beatIntensity, 0.7, accuracy: 1e-6)
    }

    func testBandsLeftRightDefaultToBands() {
        let bands: [Float] = [0.1, 0.2, 0.3]
        let f = AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                           rms: 0, peak: 0, timestamp: 0)
        XCTAssertEqual(f.bandsLeft, bands)
        XCTAssertEqual(f.bandsRight, bands)
    }

    func testBandsLeftRightExplicit() {
        let L: [Float] = [1.0, 0.0]
        let R: [Float] = [0.0, 1.0]
        let f = AudioFrame(bands: [0.5, 0.5], bandsLeft: L, bandsRight: R,
                           bandPeaks: [0.5, 0.5], waveform: [],
                           rms: 0, peak: 0, timestamp: 0)
        XCTAssertEqual(f.bandsLeft, L)
        XCTAssertEqual(f.bandsRight, R)
        // Mean invariant.
        for i in 0..<2 {
            XCTAssertEqual(f.bands[i], (L[i] + R[i]) / 2, accuracy: 1e-6)
        }
    }
}