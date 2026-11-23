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
import simd
@testable import MacVisualizerCore

final class TriWingJewelTests: XCTestCase {
    private let u: Float = TriWing.unit

    func testDomeIsASphericalCapRisingByTheStatedHeight() {
        XCTAssertEqual(TriWing.jewelDomeHeight, 0.012, accuracy: 1e-6)
        XCTAssertEqual(TriWing.jewelDomeRise(at: 0), TriWing.jewelDomeHeight, accuracy: 1e-6)
        XCTAssertEqual(TriWing.jewelDomeRise(at: TriWing.capRadius), 0, accuracy: 1e-6)
        let rs: Float = TriWing.jewelSphereRadius
        // Every point lies on one sphere of radius rs centred rs - height below the crown.
        for k in 0...10 {
            let r: Float = TriWing.capRadius * Float(k) / 10
            let z: Float = TriWing.jewelDomeRise(at: r) - TriWing.jewelDomeHeight + rs
            XCTAssertEqual((r * r + z * z).squareRoot(), rs, accuracy: 1e-5)
        }
        var prev: Float = 1
        for k in 0...10 {
            let v = TriWing.jewelDomeRise(at: TriWing.capRadius * Float(k) / 10)
            XCTAssertLessThanOrEqual(v, prev)
            prev = v
        }
    }

    func testSurfaceRiseFollowsDomeThenBezelThenBlock() {
        let rim: Float = TriWing.jewelRimRise
        XCTAssertEqual(TriWing.jewelSurfaceRise(at: 0), rim + TriWing.jewelDomeHeight, accuracy: 1e-6)
        XCTAssertEqual(TriWing.jewelSurfaceRise(at: TriWing.capRadius - 1e-5), rim, accuracy: 2e-4)
        XCTAssertGreaterThan(TriWing.jewelSurfaceRise(at: TriWing.capRadius + 0.0005), rim)   // the bezel lip stands above the stone's rim
        XCTAssertEqual(TriWing.jewelSurfaceRise(at: TriWing.capRadius + TriWing.jewelBezelWidth + 0.01), 0, accuracy: 1e-6)
    }

    func testSpringArcIsMirrorSymmetricAndEvenlySpaced() {
        let arc: [P2] = TriWing.springArc()
        XCTAssertGreaterThan(arc.count, 40)
        for i in 0..<arc.count {
            let a: P2 = arc[i]
            let b: P2 = arc[arc.count - 1 - i]
            XCTAssertEqual(a.x, -b.x, accuracy: 1e-5)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-5)
        }
        for i in 1..<arc.count {
            let d: Float = simd_length(arc[i] - arc[i - 1])
            XCTAssertGreaterThan(d, 0.05 * u)
            XCTAssertLessThan(d, 0.75 * u)
        }
    }

    func testSpringFeetSitInTheTipSideNotchesAndLeaveTheCrownClear() {
        let arc: [P2] = TriWing.springArc()
        let first: P2 = arc[0]
        let last: P2 = arc[arc.count - 1]
        for end in [first, last] {
            XCTAssertGreaterThan(abs(end.x), 4.6 * u)
            XCTAssertLessThan(abs(end.x), 7.8 * u)
            XCTAssertGreaterThan(end.y, 7.2 * u)         // R y is up: the tip side is +y
            XCTAssertLessThan(end.y, 10.2 * u)
        }
        // The crown of the stone (everything inside the shoulder ring) is never covered.
        let clear: Float = TriWing.springHalfWidth + 3.0 * u
        for p in arc where p.y < 6 * u { XCTAssertGreaterThan(simd_length(p), clear - 0.001) }
        // The arms bear on the stone's shoulder: some centreline point sits at the shoulder radius.
        var near: Float = 100
        for p in arc { near = min(near, abs(simd_length(p) - TriWing.springShoulderRadius)) }
        XCTAssertLessThan(near, 0.1 * u)
    }

    func testSpringStemRunsFromTheForkToTheHingeNotch() {
        let stem: [P2] = TriWing.springStem()
        XCTAssertGreaterThan(stem.count, 4)
        let end: P2 = stem[stem.count - 1]
        XCTAssertLessThan(abs(end.x), 2.1 * u)
        XCTAssertLessThan(end.y, -7.2 * u)               // hinge toward the part's centre (-y)
        XCTAssertGreaterThan(end.y, -10.2 * u)
        for p in stem { XCTAssertEqual(p.x, 0, accuracy: 1e-6) }
        XCTAssertEqual(TriWing.springHalfWidth * 2, 1.6 * u, accuracy: 1e-6)
    }
}
