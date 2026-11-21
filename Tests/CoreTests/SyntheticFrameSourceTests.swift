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

final class SyntheticFrameSourceTests: XCTestCase {
    func testProducesRequestedBandCounts() {
        let source = SyntheticFrameSource(bandCount: 32)
        let frame = source.frame(at: 0)
        XCTAssertEqual(frame.bands.count, 32)
        XCTAssertEqual(frame.bandPeaks.count, 32)
    }

    func testAllValuesAreInUnitRange() {
        let source = SyntheticFrameSource(bandCount: 48)
        for t in stride(from: 0.0, through: 3.0, by: 0.25) {
            let frame = source.frame(at: t)
            for v in frame.bands { XCTAssertTrue((0...1).contains(v), "band \(v) out of range at t=\(t)") }
            for v in frame.bandPeaks { XCTAssertTrue((0...1).contains(v)) }
        }
    }

    func testAnimatesOverTime() {
        let source = SyntheticFrameSource(bandCount: 16)
        let a = source.frame(at: 0).bands
        let b = source.frame(at: 1).bands
        XCTAssertNotEqual(a, b, "frames should differ as time advances")
    }

    func testPeaksAtLeastBands() {
        let source = SyntheticFrameSource(bandCount: 16)
        let frame = source.frame(at: 0.5)
        for i in 0..<frame.bands.count {
            XCTAssertGreaterThanOrEqual(frame.bandPeaks[i], frame.bands[i] - 1e-6)
        }
    }
}