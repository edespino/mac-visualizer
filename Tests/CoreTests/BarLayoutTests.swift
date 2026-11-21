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

final class BarLayoutTests: XCTestCase {
    func testBarsPartitionFullWidthWhenNoGap() {
        let layout = BarLayout(barCount: 4, gapFraction: 0)
        XCTAssertEqual(layout.barXRange(0).start, 0, accuracy: 1e-6)
        XCTAssertEqual(layout.barXRange(3).end, 1, accuracy: 1e-6)
        XCTAssertEqual(layout.barXRange(0).end, layout.barXRange(1).start, accuracy: 1e-6)
    }

    func testGapReducesBarWidth() {
        let layout = BarLayout(barCount: 4, gapFraction: 0.5)
        let width = layout.barXRange(0).end - layout.barXRange(0).start
        XCTAssertEqual(width, 0.25 * 0.5, accuracy: 1e-6)
    }

    func testBarsAreCenteredInTheirSlot() {
        let layout = BarLayout(barCount: 4, gapFraction: 0.2)
        let r = layout.barXRange(0)
        XCTAssertEqual((r.start + r.end) / 2, 0.125, accuracy: 1e-6)
    }

    func testBarsDoNotOverlap() {
        let layout = BarLayout(barCount: 16, gapFraction: 0.2)
        for i in 0..<15 {
            XCTAssertLessThanOrEqual(layout.barXRange(i).end, layout.barXRange(i + 1).start + 1e-6)
        }
    }
}