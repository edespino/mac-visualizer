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

final class HannWindowTests: XCTestCase {
    func testLength() {
        XCTAssertEqual(makeHannWindow(2048).count, 2048)
    }

    func testEndpointsNearZeroCenterNearOne() {
        let w = makeHannWindow(1024)
        XCTAssertEqual(w.first!, 0, accuracy: 0.001)
        XCTAssertEqual(w.last!, 0, accuracy: 0.01)
        XCTAssertEqual(w[w.count / 2], 1, accuracy: 0.001)
    }

    func testApproximatelySymmetric() {
        // vDSP's window convention makes endpoints differ by up to one sample's
        // worth; a generous tolerance keeps this robust across conventions.
        let w = makeHannWindow(256)
        for i in 0..<(w.count / 2) {
            XCTAssertEqual(w[i], w[w.count - 1 - i], accuracy: 0.02)
        }
    }
}