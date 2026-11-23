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

final class TriWingSmearTests: XCTestCase {
    private let smear = TriWingSmear.compute(radii: 128, angles: 240)
    private let smearBack = TriWingSmear.compute(radii: 128, angles: 240, face: .back)

    private func at(_ r: Float) -> Int { min(smear.radii - 1, Int(r * Float(smear.radii))) }

    func testCoverageIsAFractionAndClassesSumToIt() {
        for i in 0..<smear.radii {
            XCTAssertGreaterThanOrEqual(smear.coverage[i], 0)
            XCTAssertLessThanOrEqual(smear.coverage[i], 1.0001)
            var sum: Float = 0
            for v in smear.classes[i] { sum += v }
            XCTAssertEqual(sum, smear.coverage[i], accuracy: 1e-4)
        }
    }

    func testNothingBeyondTheWingTipAndFullCoverageInTheRing() {
        XCTAssertEqual(smear.coverage[smear.radii - 1], 0, accuracy: 0.02)
        XCTAssertGreaterThan(smear.coverage[at(0.45)], 0.99)
        XCTAssertEqual(smear.coverage[at(0.1)], 0, accuracy: 1e-6)   // the static hub is not smeared
    }

    func testWingsLeaveGapsAtTheTipsAndTheBodyFillsTheMiddle() {
        let mid: Float = smear.coverage[at(0.56)]
        let tipRing: Float = smear.coverage[at(0.97)]
        XCTAssertGreaterThan(mid, 0.7)
        XCTAssertLessThan(tipRing, 0.4)
        XCTAssertGreaterThan(tipRing, 0.02)
        XCTAssertGreaterThan(mid, tipRing)
    }

    func testCoverageNeverIncreasesWithRadiusOutsideTheRing() {
        var prev: Float = 1
        var r: Float = 0.58
        while r < 0.99 {
            let c: Float = smear.coverage[at(r)]
            XCTAssertLessThanOrEqual(c, prev + 0.04)
            prev = c
            r += 0.02
        }
    }

    func testJewelBlueAndGoldAppearOnTheWingRadii() {
        // The jewel setting sits at 113 drawing units: blue near its centre radius, gold around it.
        let rc: Float = 113 * TriWing.unit
        XCTAssertGreaterThan(smear.classes[at(rc)][TriWingSmear.jewel], 0.02)
        XCTAssertGreaterThan(smear.classes[at(rc + 0.06)][TriWingSmear.gold], 0.0)
        // Bearing balls give a steel ring at the ball radius.
        XCTAssertGreaterThan(smear.classes[at(TriWing.ballRingRadius)][TriWingSmear.steel], 0.1)
    }

    func testBossRingIsItsOwnClassSeparateFromThePlate() {
        XCTAssertEqual(TriWingSmear.classCount, 10)
        XCTAssertEqual(TriWingSmear.boss, 9)
        // The boss's polished top ring (between the countersink and the boss edge) lies at 113 +- 12.5 drawing units.
        let rc: Float = 113 * TriWing.unit
        let ringRadius: Float = (TriWing.countersinkTopRadius + TriWing.bossRadius) * 0.5
        let inner: Float = smear.classes[at(rc - ringRadius)][TriWingSmear.boss]
        let outer: Float = smear.classes[at(rc + ringRadius)][TriWingSmear.boss]
        XCTAssertGreaterThan(inner + outer, 0.001)
        // Its share still counts toward the coverage sum (checked for every radius above), and the plate class remains elsewhere.
        var plateTotal: Float = 0
        for i in 0..<smear.radii { plateTotal += smear.classes[i][TriWingSmear.pad] }
        XCTAssertGreaterThan(plateTotal, 0.1)
    }

    func testBearingGapIsAThroughHoleAndTheCageAndBallsCover() {
        // Mid-gap off the balls: nothing covers. Radii inside the gap but beyond the cage and the balls stay open.
        let rGap: Float = 44.1 * TriWing.unit
        XCTAssertLessThan(smear.coverage[at(rGap)], 0.3)
        // The balls' ring and the races cover.
        XCTAssertGreaterThan(smear.coverage[at(TriWing.ballRingRadius)], 0.2)
        // Between the inner race and the cage only the balls cover: the see-through windows stay clearly open.
        let open: Float = smear.coverage[at(48.1 * TriWing.unit)]
        XCTAssertGreaterThan(open, 0.05)
        XCTAssertLessThan(open, 0.6)
        XCTAssertGreaterThan(smear.coverage[at((TriWing.innerRaceInner + TriWing.innerRaceOuter) * 0.5)], 0.95)
        XCTAssertGreaterThan(smear.coverage[at((TriWing.outerRaceInner + TriWing.outerRaceOuter) * 0.5)], 0.95)
        // Cage bars are steel (no gold class anywhere in the bearing band).
        let cageR: Float = TriWing.ballRingRadius + 1.7 * TriWing.unit
        XCTAssertEqual(smear.classes[at(cageR)][TriWingSmear.gold], 0.0, accuracy: 1e-6)
        XCTAssertGreaterThan(smear.classes[at(cageR)][TriWingSmear.steel], 0.0)
        XCTAssertEqual(TriWingSmear.classifyBearing(r: TriWing.ballRingRadius + 1.7 * TriWing.unit, a: Float.pi / 2 + Float.pi / 12), TriWingSmear.steel)
    }

    func testSmearedTubeGlowKeepsSaturatedColours() {
        var lit = 0
        for i in 0..<smear.radii where smear.glow[i] > 0 { lit += 1 }
        XCTAssertGreaterThan(lit, 20)
        // Where only one wing's tubes are lit the glow colour is that wing's pure colour (not a mix toward white).
        var pure = 0
        for i in 0..<smear.radii where smear.glow[i] > 0 {
            let c: SIMD3<Float> = smear.glowColor[i] / smear.glow[i]
            let mx: Float = max(c.x, max(c.y, c.z))
            let mn: Float = min(c.x, min(c.y, c.z))
            if mx - mn > 0.5 { pure += 1 }
        }
        XCTAssertGreaterThan(pure, lit / 2)
    }

    func testTubesGlowOnlyNearTheWingTipRadius() {
        var lit = 0
        for i in 0..<smear.radii where smear.glow[i] > 0 {
            lit += 1
            let r: Float = (Float(i) + 0.5) / Float(smear.radii)
            XCTAssertGreaterThan(r, 0.5)
            XCTAssertLessThanOrEqual(smear.glow[i], 1)
        }
        XCTAssertGreaterThan(lit, 0)
    }

    // MARK: Ring lettering, spanner slots and flutes

    private func binRadius(_ i: Int, _ s: TriWingSmear) -> Float { (Float(i) + 0.5) / Float(s.radii) }

    func testPolishedLetteringStaysRingMetalOnBothFaces() {
        // The letters' floors are bright polished metal now, so no black (dark engraving) share is taken from the ring.
        let r: Float = TriWing.ringInner + TriWing.ringTextBaselineV + TriWing.ringTextCapHeight * 0.5
        let i: Int = at(r)
        XCTAssertEqual(smear.classes[i][TriWingSmear.black], 0, accuracy: 1e-6)
        XCTAssertEqual(smearBack.classes[i][TriWingSmear.black], 0, accuracy: 1e-6)
        for k in 0..<smear.radii {
            XCTAssertEqual(smear.classes[k][TriWingSmear.black], smearBack.classes[k][TriWingSmear.black], accuracy: 1e-6)
            XCTAssertEqual(smear.coverage[k], smearBack.coverage[k], accuracy: 1e-5)
            var sum: Float = 0
            for v in smearBack.classes[k] { sum += v }
            XCTAssertEqual(sum, smearBack.coverage[k], accuracy: 1e-4)
        }
    }

    func testSpannerSlotsMoveFromRingMetalToTheSatinBodyClassOverTheirRadiiOnly() {
        // Over the slots: their share of the circle, notchCount * width / circumference, is satin body metal (the milled
        // floor), not dark and not ring metal.
        let r: Float = 70.0 * TriWing.unit
        let i: Int = at(r)
        let rBin: Float = binRadius(i, smear)
        XCTAssertGreaterThan(rBin, TriWing.slotInnerRadius)
        let expected: Float = Float(TriWing.notchCount) * TriWing.slotWidth / TriWing.ringCircumference
        XCTAssertEqual(smear.classes[i][TriWingSmear.body], expected, accuracy: 0.001)
        XCTAssertEqual(smear.classes[i][TriWingSmear.dark], 0, accuracy: 1e-6)
        XCTAssertEqual(smear.classes[i][TriWingSmear.ring], smear.coverage[i] - expected, accuracy: 0.001)
        // Inboard of the slots' inner end there is no such share.
        let rGap: Float = 64.0 * TriWing.unit
        XCTAssertEqual(smear.classes[at(rGap)][TriWingSmear.body], 0, accuracy: 1e-6)
        XCTAssertEqual(smear.classes[at(TriWing.ringInner + 0.4 * TriWing.unit)][TriWingSmear.body], 0, accuracy: 1e-6)
        XCTAssertEqual(TriWingSmear.ringNotchShare(v: 64.0 * TriWing.unit - TriWing.ringInner), 0, accuracy: 1e-6)
        XCTAssertEqual(TriWingSmear.ringNotchShare(v: 70.0 * TriWing.unit - TriWing.ringInner), expected, accuracy: 1e-6)
    }

    func testFlutesAndLetteringAreRingMetalAtTheFluteRadius() {
        let v: Float = 0.5 * (TriWing.fluteInnerRadius + TriWing.fluteOuterRadius) - TriWing.ringInner
        let i: Int = at(TriWing.ringInner + v)
        XCTAssertGreaterThan(smear.classes[i][TriWingSmear.ring], 0.9)
        XCTAssertGreaterThan(smearBack.classes[i][TriWingSmear.ring], 0.9)
    }

    // MARK: Swept volume (the spinning body seen from the side)

    func testFullCoverageRadiusIsWhereCoverageFirstDropsBelowOne() {
        let rf: Float = smear.fullCoverageRadius(threshold: 0.995)
        XCTAssertGreaterThanOrEqual(rf, TriWing.ringOuter)
        XCTAssertLessThan(rf, 0.95)
        // Every bin from the ring's outer edge up to it is (effectively) full, the first bin at or past it is not.
        var i: Int = Int(TriWing.ringOuter * Float(smear.radii))
        while i < Int(rf * Float(smear.radii)) - 1 {
            XCTAssertGreaterThanOrEqual(smear.coverage[i], 0.995)
            i += 1
        }
        XCTAssertLessThan(smear.coverage[min(smear.radii - 1, Int(rf * Float(smear.radii)) + 1)], 0.995)
    }

    func testSweptShellsRunOutwardFromTheFullRadiusToTheTip() {
        let rf: Float = smear.fullCoverageRadius(threshold: 0.995)
        let shells: [TriWingSmear.SweptShell] = smear.sweptShells(count: 5)
        XCTAssertEqual(shells.count, 5)
        var prev: Float = rf
        for s in shells {
            XCTAssertGreaterThan(s.radius, prev)
            XCTAssertLessThanOrEqual(s.radius, 1.0)
            prev = s.radius
        }
    }

    func testShellOpacitiesAreValid() {
        let shells: [TriWingSmear.SweptShell] = smear.sweptShells(count: 6)
        for s in shells {
            XCTAssertGreaterThan(s.opacity, 0)
            XCTAssertLessThan(s.opacity, 1)
        }
    }

    func testShellHeightsMatchTheBodyAndNeverExceedTheTallestFeature() {
        let shells: [TriWingSmear.SweptShell] = smear.sweptShells(count: 6)
        for s in shells {
            XCTAssertGreaterThanOrEqual(s.halfHeight, TriWing.halfThickness - 0.003 - 1e-6)
            XCTAssertLessThanOrEqual(s.halfHeight, TriWing.halfThickness + TriWing.padHeight + TriWing.bossHeight + 1e-6)
        }
        XCTAssertEqual(smear.coreHalfHeight, TriWing.halfThickness, accuracy: 1e-6)
    }
}
