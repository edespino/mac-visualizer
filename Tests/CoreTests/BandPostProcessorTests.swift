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

final class BandPostProcessorTests: XCTestCase {
    func testSilenceProducesZeroBands() {
        let p = BandPostProcessor(bandCount: 4, gain: 1, smoothing: 0, peakDecay: 0.9)
        let result = p.process([0, 0, 0, 0])
        for v in result.bands { XCTAssertEqual(v, 0, accuracy: 1e-4) }
    }

    func testOutputIsClampedToUnitRange() {
        let p = BandPostProcessor(bandCount: 2, gain: 100, smoothing: 0, peakDecay: 0.9)
        let result = p.process([10, 10])
        for v in result.bands {
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThanOrEqual(v, 1)
        }
    }

    func testHigherGainGivesHigherOrEqualOutput() {
        let low = BandPostProcessor(bandCount: 1, gain: 1, smoothing: 0, peakDecay: 0.9)
        let high = BandPostProcessor(bandCount: 1, gain: 2, smoothing: 0, peakDecay: 0.9)
        let input: [Float] = [0.01]
        let lowOut = low.process(input).bands[0]
        let highOut = high.process(input).bands[0]
        XCTAssertGreaterThan(highOut, lowOut)
    }

    func testSmoothingConvergesTowardSteadyInput() {
        let p = BandPostProcessor(bandCount: 1, gain: 1, smoothing: 0.5, peakDecay: 0.9)
        let input: [Float] = [1.0]
        var last: Float = 0
        for _ in 0..<50 { last = p.process(input).bands[0] }
        let target = p.process(input).bands[0] // already converged
        XCTAssertEqual(last, target, accuracy: 0.01)
        XCTAssertGreaterThan(last, 0.5) // moved well off zero toward steady value
    }

    func testPeakIsAtLeastCurrentBand() {
        let p = BandPostProcessor(bandCount: 1, gain: 1, smoothing: 0, peakDecay: 0.5)
        let result = p.process([1.0])
        XCTAssertGreaterThanOrEqual(result.peaks[0], result.bands[0] - 1e-4)
    }

    func testPeakDecaysWhenInputDrops() {
        let p = BandPostProcessor(bandCount: 1, gain: 1, smoothing: 0, peakDecay: 0.5)
        _ = p.process([1.0])               // establish a high peak
        let afterDrop = p.process([0.0])   // input gone
        let afterMore = p.process([0.0])
        XCTAssertLessThan(afterMore.peaks[0], afterDrop.peaks[0])
    }
}