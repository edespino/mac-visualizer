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

final class WaveformTests: XCTestCase {
    func testAnalyzerEmitsWaveformOf256Points() {
        let a = SpectrumAnalyzer(fftSize: 2048, sampleRate: 48000, settings: .defaults)
        let frame = a.append(SignalGenerators.sine(frequency: 440, sampleRate: 48000, count: 2048))!
        XCTAssertEqual(frame.waveform.count, 256)
        XCTAssertGreaterThan(frame.waveform.map { abs($0) }.max() ?? 0, 0)
    }

    func testAnalyzerSilenceWaveformIsFlat() {
        let a = SpectrumAnalyzer(fftSize: 2048, sampleRate: 48000, settings: .defaults)
        let frame = a.append(SignalGenerators.silence(count: 2048))!
        XCTAssertEqual(frame.waveform.count, 256)
        XCTAssertLessThan(frame.waveform.map { abs($0) }.max() ?? 0, 1e-4)
    }

    func testSyntheticWaveformIsNonEmptyAndAnimates() {
        let s = SyntheticFrameSource(bandCount: 24)
        let w0 = s.frame(at: 0).waveform
        let w1 = s.frame(at: 1).waveform
        XCTAssertFalse(w0.isEmpty)
        XCTAssertNotEqual(w0, w1)
    }
}