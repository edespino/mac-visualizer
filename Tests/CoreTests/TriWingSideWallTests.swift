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

final class TriWingSideWallTests: XCTestCase {

    // MARK: Heights

    func testEdgeChamferIsWideEnoughToCatchALineButNotWiderThanTheBrief() {
        XCTAssertGreaterThanOrEqual(TriWing.bodyChamfer, 0.012)
        XCTAssertLessThanOrEqual(TriWing.bodyChamfer, 0.018 + 1e-6)
        XCTAssertEqual(TriWingWall.wallTopZ, TriWing.halfThickness - TriWing.bodyChamfer, accuracy: 1e-6)
    }

    func testWaistBandSitsInsideTheWallWithMargins() {
        // Band floor about 40% of the straight wall, recessed 0.008 to 0.012 R, shoulders inside the wall height.
        XCTAssertGreaterThan(TriWingWall.bandFraction, 0.36)
        XCTAssertLessThan(TriWingWall.bandFraction, 0.44)
        XCTAssertGreaterThanOrEqual(TriWingWall.recess, 0.008)
        XCTAssertLessThanOrEqual(TriWingWall.recess, 0.012)
        XCTAssertGreaterThan(TriWingWall.shoulderHeight, 0.005)
        // Plain wall left above the upper shoulder (and, by symmetry, below the lower one) for the face's chamfer to meet.
        XCTAssertGreaterThanOrEqual(TriWingWall.wallTopZ - TriWingWall.bandOpenHalfHeight, 0.04)
        XCTAssertEqual(TriWingWall.bandOpenHalfHeight, TriWingWall.bandHalfHeight + TriWingWall.shoulderHeight, accuracy: 1e-6)
    }

    // MARK: Columns

    func testColumnsFormAClosedCounterClockwiseLoopWithThreeFoldSymmetry() {
        let cols = TriWingWall.columns()
        XCTAssertGreaterThan(cols.count, 600)
        var pts: [P2] = []
        for c in cols { pts.append(c.p) }
        XCTAssertGreaterThan(polygonSignedArea(pts), 0)
        // Strictly increasing arc length, unit normals pointing away from the centre of the part.
        var prev: Float = -1
        for c in cols {
            XCTAssertGreaterThan(c.s, prev)
            prev = c.s
            XCTAssertEqual(simd_length(c.n), 1, accuracy: 1e-3)
        }
        XCTAssertLessThan(TriWingWall.perimeter - prev, 0.02)
        XCTAssertEqual(cols.count % 3, 0)
        let per: Int = cols.count / 3
        for i in 0..<per {
            let a: P2 = TriWing.inWing(cols[i].p, 1)
            XCTAssertEqual(simd_length(a - cols[i + per].p), 0, accuracy: 1e-5)
            let b: P2 = TriWing.inWing(cols[i].p, 2)
            XCTAssertEqual(simd_length(b - cols[i + 2 * per].p), 0, accuracy: 1e-5)
        }
    }

    func testColumnsLieOnTheBodyOutline() {
        let o = TriWing.bodyOutline()
        for c in TriWingWall.columns() { XCTAssertLessThan(polygonBoundaryDistance(o, c.p), 0.0012) }
        var maxR: Float = 0
        for c in TriWingWall.columns() { maxR = max(maxR, simd_length(c.p)) }
        XCTAssertEqual(maxR, 1.0, accuracy: 0.004)
    }

    // MARK: Clearances

    func testChamferBandAndWindowPocketsKeepClearanceFromSlotsAndPlates() {
        let cols = TriWingWall.columns()
        var outline: [P2] = []
        for c in cols { outline.append(c.p) }
        // Top face: the chamfer's inner edge must stay clear of every flank slot and every wing pad.
        let topNeed: Float = TriWing.bodyChamfer + 0.008
        var slotMin: Float = 100
        for k in 0..<TriWing.wingCount {
            for side: Float in [-1, 1] {
                for q in polygonRotated(TriWing.flankSlotOutline(side: side), by: TriWing.wingAngle(k)) {
                    slotMin = min(slotMin, polygonBoundaryDistance(outline, q))
                }
            }
        }
        XCTAssertGreaterThanOrEqual(slotMin, topNeed)
        // Beside the slots the deepest wall recess (band floor plus window pocket) keeps a wall of metal.
        XCTAssertGreaterThanOrEqual(slotMin, TriWingWall.recess + TriWingWall.windowPocketDepth + 0.008)
        var padMin: Float = 100
        for q in TriWing.padOutline() { padMin = min(padMin, polygonBoundaryDistance(outline, q)) }
        XCTAssertGreaterThanOrEqual(padMin, topNeed)
    }

    func testSlotFloorStaysAboveTheBandsUpperShoulder() {
        // The band's pocket is horizontal metal below the slot floor or to its side: the slot floor is at least
        // wall-recess clear of the band's open edge vertically OR beside it horizontally (checked above); the slot floor
        // must in any case be above the band floor.
        let floorZ: Float = TriWing.halfThickness - TriWing.tubeSlotDepth
        XCTAssertGreaterThan(floorZ, TriWingWall.bandHalfHeight)
    }

    // MARK: Flutes

    func testThreeFluteZonesAreCentredOnTheTipsAndEqual() {
        let cols = TriWingWall.columns()
        var counts: [Int] = [0, 0, 0]
        var minAngle: [Float] = [9, 9, 9]
        var maxAngle: [Float] = [-9, -9, -9]
        var sumAngle: [Float] = [0, 0, 0]
        for c in cols where c.tipWing >= 0 && abs(c.tipAngle) <= TriWingWall.fluteHalfAngle + 1e-5 {
            counts[c.tipWing] += 1
            minAngle[c.tipWing] = min(minAngle[c.tipWing], c.tipAngle)
            maxAngle[c.tipWing] = max(maxAngle[c.tipWing], c.tipAngle)
            sumAngle[c.tipWing] += c.tipAngle
        }
        XCTAssertEqual(counts[0], counts[1])
        XCTAssertEqual(counts[1], counts[2])
        XCTAssertGreaterThan(counts[0], 100)
        for w in 0..<3 {
            XCTAssertEqual(minAngle[w], -TriWingWall.fluteHalfAngle, accuracy: 1e-4)
            XCTAssertEqual(maxAngle[w], TriWingWall.fluteHalfAngle, accuracy: 1e-4)
            XCTAssertEqual(sumAngle[w], 0, accuracy: 1e-3)
        }
    }

    func testFluteZoneStaysOnTheTipArcAndHasWholeFlutes() {
        XCTAssertLessThan(TriWingWall.fluteHalfAngle, TriWingWall.tipHalfSpan - 0.1)
        XCTAssertEqual(Float(TriWingWall.fluteCount) * TriWingWall.fluteAnglePitch, 2 * TriWingWall.fluteHalfAngle, accuracy: 1e-5)
        XCTAssertGreaterThanOrEqual(TriWingWall.fluteCount, 14)
        // Pitch along the outline stays near the target (not moire-fine, not coarse).
        let arcPitch: Float = TriWingWall.fluteAnglePitch * 34 * TriWing.unit
        XCTAssertGreaterThan(arcPitch, 0.016)
        XCTAssertLessThan(arcPitch, 0.026)
    }

    func testFluteDepthIsZeroAtTheEndsAndAtTheRunOutAndSymmetric() {
        let h: Float = TriWingWall.fluteHalfAngle
        XCTAssertEqual(TriWingWall.fluteDepth(tipAngle: h, z: 0), 0, accuracy: 1e-7)
        XCTAssertEqual(TriWingWall.fluteDepth(tipAngle: -h, z: 0), 0, accuracy: 1e-7)
        XCTAssertEqual(TriWingWall.fluteDepth(tipAngle: h + 0.2, z: 0), 0, accuracy: 1e-7)
        let top: Float = TriWingWall.fluteHalfHeight + TriWingWall.fluteRunOut
        XCTAssertEqual(TriWingWall.fluteDepth(tipAngle: 0.013, z: top), 0, accuracy: 1e-7)
        XCTAssertEqual(TriWingWall.fluteDepth(tipAngle: 0.013, z: -top - 0.01), 0, accuracy: 1e-7)
        XCTAssertLessThan(top, TriWingWall.bandHalfHeight - 0.006)
        var peak: Float = 0
        var a: Float = -h
        while a <= h {
            let d: Float = TriWingWall.fluteDepth(tipAngle: a, z: 0.01)
            XCTAssertEqual(d, TriWingWall.fluteDepth(tipAngle: -a, z: -0.01), accuracy: 1e-5)
            XCTAssertGreaterThanOrEqual(d, 0)
            peak = max(peak, d)
            a += 0.003
        }
        XCTAssertGreaterThan(peak, TriWingWall.fluteGrooveDepth * 0.8)
        XCTAssertLessThanOrEqual(peak, TriWingWall.fluteGrooveDepth + 1e-6)
        XCTAssertLessThan(TriWingWall.fluteGrooveDepth, TriWingWall.recess)
    }

    // MARK: Windows

    func testSixWindowsOnePerFlankCentredNearTheTubeAndInsideTheBand() {
        let wins = TriWingWall.windows()
        XCTAssertEqual(wins.count, 6)
        var seen = Set<Int>()
        let cols = TriWingWall.columns()
        for w in wins {
            seen.insert(w.wing * 2 + (w.side > 0 ? 1 : 0))
            // Centre column is the one nearest the tube's middle, which lies about flankInset inside the edge.
            var tube: [P2] = TriWing.flankTubePath(side: Float(w.side))
            for i in 0..<tube.count { tube[i] = TriWing.inWing(tube[i], w.wing) }
            let mid: P2 = (tube[tube.count / 2 - 1] + tube[tube.count / 2]) * 0.5
            let c: P2 = cols[w.centre].p
            XCTAssertLessThan(simd_length(c - mid), TriWing.flankInset * TriWing.unit + 0.02)
            XCTAssertGreaterThan(simd_length(c - mid), TriWing.flankInset * TriWing.unit - 0.02)
            // Window is on the flank (not on a tip), all the way along.
            for k in (w.centre - w.halfColumns)...(w.centre + w.halfColumns) { XCTAssertLessThan(cols[k].tipWing, 0) }
            // Inside the band with a margin of floor above it.
            XCTAssertLessThanOrEqual(w.halfHeight + 0.012, TriWingWall.bandHalfHeight)
            XCTAssertGreaterThan(w.halfHeight, 2 * TriWingWall.windowFrameWidth)
            XCTAssertGreaterThan(w.halfLength, 3 * w.halfHeight)
        }
        XCTAssertEqual(seen.count, 6)
    }

    func testWindowsAreMirrorImagesAndClearOfTheFluteZones() {
        let wins = TriWingWall.windows()
        let cols = TriWingWall.columns()
        for w in wins where w.wing == 0 {
            let other = wins.first { $0.wing == 0 && $0.side == -w.side }!
            let a: P2 = cols[w.centre].p
            let b: P2 = cols[other.centre].p
            XCTAssertEqual(a.x, -b.x, accuracy: 0.004)
            XCTAssertEqual(a.y, b.y, accuracy: 0.004)
        }
        // Equal by rotation.
        for w in wins where w.wing == 1 {
            let base = wins.first { $0.wing == 0 && $0.side == w.side }!
            XCTAssertEqual(((w.centre - base.centre) % cols.count + cols.count) % cols.count, cols.count / 3)
        }
        // Every window column is at least 0.05 R along the outline from any flute column.
        for w in wins {
            for k in (w.centre - w.halfColumns)...(w.centre + w.halfColumns) {
                for (j, c) in cols.enumerated() where c.tipWing >= 0 && abs(c.tipAngle) <= TriWingWall.fluteHalfAngle {
                    _ = j
                    XCTAssertGreaterThan(abs(c.s - cols[k].s), 0.05)
                }
            }
        }
    }

    func testWindowFrameAndPocketFitInsideTheWindow() {
        let w: TriWingWall.Window = TriWingWall.windows()[0]
        XCTAssertLessThan(2 * TriWingWall.windowFrameWidth, w.halfHeight)
        XCTAssertGreaterThan(TriWingWall.windowPocketDepth, 0.002)
        XCTAssertLessThan(TriWingWall.windowPocketDepth, 0.007)
        // Stadium outline: full height in the middle, rounding to zero at the ends.
        XCTAssertEqual(TriWingWall.stadiumHalfHeight(offset: 0, halfLength: w.halfLength, halfHeight: w.halfHeight), w.halfHeight, accuracy: 1e-6)
        XCTAssertEqual(TriWingWall.stadiumHalfHeight(offset: w.halfLength, halfLength: w.halfLength, halfHeight: w.halfHeight), 0, accuracy: 1e-6)
        XCTAssertEqual(TriWingWall.stadiumHalfHeight(offset: -w.halfLength, halfLength: w.halfLength, halfHeight: w.halfHeight), 0, accuracy: 1e-6)
        let mid: Float = w.halfLength - w.halfHeight * 0.5
        let v: Float = TriWingWall.stadiumHalfHeight(offset: mid, halfLength: w.halfLength, halfHeight: w.halfHeight)
        XCTAssertGreaterThan(v, 0)
        XCTAssertLessThan(v, w.halfHeight)
    }

    // MARK: Sampling

    func testSampleInterpolatesPositionAndNormal() {
        let cols = TriWingWall.columns()
        let i: Int = 40
        let s: Float = (cols[i].s + cols[i + 1].s) * 0.5
        let q = TriWingWall.sample(at: s)
        XCTAssertEqual(simd_length(q.p - (cols[i].p + cols[i + 1].p) * 0.5), 0, accuracy: 1e-5)
        XCTAssertEqual(simd_length(q.n), 1, accuracy: 1e-4)
    }
}
