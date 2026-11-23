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

final class TriWingLayoutTests: XCTestCase {

    private func maxRadius(_ p: [P2]) -> Float {
        var m: Float = 0
        for q in p { m = max(m, simd_length(q)) }
        return m
    }
    private func minRadius(_ p: [P2]) -> Float {
        var m: Float = 100
        for q in p { m = min(m, simd_length(q)) }
        return m
    }

    func testBodyOutlineIsCounterClockwiseAndReachesTheDiscRadius() {
        let o = TriWing.bodyOutline()
        XCTAssertGreaterThan(polygonSignedArea(o), 0)
        XCTAssertEqual(maxRadius(o), 1.0, accuracy: 0.004)
        XCTAssertLessThan(maxRadius(o), 1.0001)
        XCTAssertGreaterThan(o.count, 150)
    }

    func testBodyOutlineScoopedSidesAndThreeFoldSymmetry() {
        let o = TriWing.bodyOutline()
        XCTAssertEqual(minRadius(o), 80.0 * TriWing.unit, accuracy: 0.03)
        // Rotating by 120 degrees maps the outline onto itself: every rotated vertex lies on the boundary.
        let rot = polygonRotated(o, by: TriWing.wingAngle(1))
        for q in rot.prefix(200) {
            XCTAssertLessThan(polygonBoundaryDistance(o, q), 0.003)
        }
        // Wing 0 points up: the farthest vertex is near +y.
        var best = o[0]
        for q in o where simd_length(q) > simd_length(best) { best = q }
        XCTAssertEqual(best.x, 0, accuracy: 0.05)
        XCTAssertGreaterThan(best.y, 0.95)
    }

    func testPadSitsInsideTheBodyAndClearOfTheRing() {
        let body = TriWing.bodyOutline()
        let pad = TriWing.padOutline()
        XCTAssertGreaterThan(polygonSignedArea(pad), 0)
        for q in pad {
            XCTAssertTrue(polygonContains(body, q))
            XCTAssertGreaterThan(simd_length(q), TriWing.ringOuter + 0.02)
            XCTAssertGreaterThan(polygonBoundaryDistance(body, q), 0.02)
        }
    }

    func testBossScrewsAndPatchLieInsideThePad() {
        let pad = TriWing.padOutline()
        var cs: [P2] = [TriWing.bossCenter]
        cs.append(contentsOf: TriWing.screwCentres)
        for c in cs {
            XCTAssertTrue(polygonContains(pad, c))
        }
        // Boss disc inside the pad.
        let boss = circlePolygon(center: TriWing.bossCenter, radius: TriWing.bossRadius, segments: 48)
        for q in boss { XCTAssertTrue(polygonContains(pad, q)) }
        // Each screw countersink inside the pad with a margin.
        for c in TriWing.screwCentres {
            let ring = circlePolygon(center: c, radius: TriWing.countersinkScrewRadius, segments: 32)
            for q in ring {
                XCTAssertTrue(polygonContains(pad, q))
                XCTAssertGreaterThan(polygonBoundaryDistance(pad, q), 0.002)
            }
        }
        // Patch plate corners inside the pad.
        let half = TriWing.patchSize * 0.5
        let corners: [P2] = [P2(-half.x, -half.y), P2(half.x, -half.y), P2(half.x, half.y), P2(-half.x, half.y)]
        for q in corners { XCTAssertTrue(polygonContains(pad, TriWing.patchCentre + q)) }
    }

    func testScrewCountersinksDoNotOverlapEachOtherTheBossOrThePatch() {
        let cs = TriWing.screwCentres
        let r = TriWing.countersinkScrewRadius
        for i in 0..<cs.count {
            for j in (i + 1)..<cs.count {
                XCTAssertGreaterThan(simd_length(cs[i] - cs[j]), 2 * r + 0.01)
            }
            XCTAssertGreaterThan(simd_length(cs[i] - TriWing.bossCenter), r + TriWing.bossRadius + 0.005)
            // Not under the patch plate (box test with margin).
            let d = cs[i] - TriWing.patchCentre
            let half = TriWing.patchSize * 0.5
            let clear: Bool = abs(d.x) > half.x + r || abs(d.y) > half.y + r
            XCTAssertTrue(clear)
        }
        // The patch sits between the two base screws.
        XCTAssertGreaterThan(cs[0].x, -1)
        XCTAssertLessThan(cs[0].x, TriWing.patchCentre.x - TriWing.patchSize.x * 0.5)
        XCTAssertGreaterThan(cs[1].x, TriWing.patchCentre.x + TriWing.patchSize.x * 0.5)
    }

    func testFlankTubeSlotsLieBetweenThePadAndTheBodyChamfer() {
        let body = TriWing.bodyOutline()
        let inset = polygonOffsetInward(body, by: TriWing.bodyChamfer)
        let pad = TriWing.padOutline()
        for side: Float in [-1, 1] {
            for q in TriWing.flankSlotOutline(side: side) {
                XCTAssertTrue(polygonContains(inset, q), "slot point leaves the body face")
                XCTAssertFalse(polygonContains(pad, q), "slot point is under the pad")
                XCTAssertGreaterThan(polygonBoundaryDistance(pad, q), 0.002)
                XCTAssertGreaterThan(polygonBoundaryDistance(inset, q), 0.001)
            }
        }
    }

    func testFlankTubesAreAsThickAsTheDiscRodsAndLongEnough() {
        XCTAssertEqual(TriWing.tubeShellRadius, 0.0185, accuracy: 1e-6)
        XCTAssertEqual(TriWing.tubeCoreRadius, 0.0115, accuracy: 1e-6)
        XCTAssertGreaterThan(TriWing.tubeSlotHalfWidth, TriWing.tubeShellRadius)
        XCTAssertGreaterThan(TriWing.tubeSlotDepth, 2 * TriWing.tubeShellRadius)
        // The slot is 1.5 times the former depth (2 * shell radius + 4 thousandths) and leaves a solid web between the two faces.
        XCTAssertEqual(TriWing.tubeSlotDepth, 1.5 * (2 * 0.0185 + 0.004), accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(2 * (TriWing.halfThickness - TriWing.tubeSlotDepth), 0.03)
        let path = TriWing.flankTubePath(side: 1)
        var length: Float = 0
        for i in 1..<path.count { length += simd_length(path[i] - path[i - 1]) }
        XCTAssertGreaterThan(length, 0.17, "tube shorter than a disc rod")
        XCTAssertLessThan(length, 0.40)
        let left = TriWing.flankTubePath(side: -1)
        XCTAssertEqual(left[3].x, -path[3].x, accuracy: 1e-6)
        XCTAssertEqual(left[3].y, path[3].y, accuracy: 1e-6)
    }

    func testFlankTubesStayClearOfTheBearingRing() {
        // The slot's inner edge must clear the engraved ring (and the wing's neighbours).
        for side: Float in [-1, 1] {
            for q in TriWing.flankSlotOutline(side: side) {
                XCTAssertGreaterThan(simd_length(q), TriWing.ringOuter + 0.01)
            }
        }
    }

    func testCentreStackIsOrdered() {
        XCTAssertLessThanOrEqual(TriWing.hubRadius, TriWing.innerRaceInner)
        XCTAssertLessThan(TriWing.innerRaceOuter, TriWing.cageInner)
        XCTAssertLessThan(TriWing.cageOuter, TriWing.outerRaceInner)
        XCTAssertLessThan(TriWing.outerRaceOuter, TriWing.wellRadius + 1e-6)
        XCTAssertLessThan(TriWing.wellRadius, TriWing.ringInner)
        XCTAssertLessThan(TriWing.ringOuter + 0.02, 80 * TriWing.unit + 0.03)
        // Balls sit in the raceways: they reach past both lands (see testBallsSinkIntoBothRaceLandsByTheIntendedAmount).
        XCTAssertGreaterThan(TriWing.ballRingRadius + TriWing.ballRadius, TriWing.outerRaceInner)
        XCTAssertLessThan(TriWing.ballRingRadius - TriWing.ballRadius, TriWing.innerRaceOuter)
        // Balls do not touch each other.
        let pitch: Float = 2 * TriWing.ballRingRadius * sin(Float.pi / Float(TriWing.ballCount))
        XCTAssertGreaterThan(pitch, 2 * TriWing.ballRadius)
        // Balls sit at the mid plane and stay below the race tops; the crystal clears the hub and the ring seat.
        XCTAssertEqual(TriWing.ballCentreZ, 0)
        XCTAssertLessThan(TriWing.ballRadius, TriWing.raceTopZ)
        XCTAssertGreaterThan(TriWing.crystalZ - TriWing.crystalThickness, TriWing.hubRimZ)
        XCTAssertLessThan(TriWing.crystalZ, TriWing.halfThickness + TriWing.ringHeight)
        // Cage bars clear the races and each pocket covers its ball.
        XCTAssertGreaterThan(TriWing.cagePocketRadius, TriWing.ballRadius)
        XCTAssertGreaterThan(TriWing.raceTopZ, TriWing.raceShoulder)
    }

    func testBallsSinkIntoBothRaceLandsByTheIntendedAmount() {
        let u: Float = TriWing.unit
        let outer: Float = TriWing.ballRingRadius + TriWing.ballRadius - TriWing.outerRaceInner
        let inner: Float = TriWing.innerRaceOuter - (TriWing.ballRingRadius - TriWing.ballRadius)
        XCTAssertEqual(outer, 1.6 * u, accuracy: 1e-5)
        XCTAssertEqual(inner, 1.6 * u, accuracy: 1e-5)
        XCTAssertEqual(TriWing.ballCount, 12)
        XCTAssertEqual(TriWing.outerRaceInner - TriWing.innerRaceOuter, 6 * u, accuracy: 1e-5)
    }

    func testRacewayArcHugsTheBallAndClearsItByTwoTenthsOfAUnit() {
        let u: Float = TriWing.unit
        XCTAssertEqual(TriWing.racewayRadius - TriWing.ballRadius, 0.2 * u, accuracy: 1e-5)
        let face: [(Float, Float)] = TriWing.raceGapFace()
        XCTAssertGreaterThan(face.count, 16)
        XCTAssertEqual(face.first!.1, 0, accuracy: 1e-6)
        XCTAssertEqual(face.last!.1, TriWing.raceTopZ, accuracy: 1e-5)
        var arcPoints: Int = 0
        for (d, z) in face {
            // Outer race: radius of this point; the ball centre is at (ballRingRadius, 0).
            let r: Float = TriWing.outerRaceInner + d
            let dr: Float = r - TriWing.ballRingRadius
            let dist: Float = (dr * dr + z * z).squareRoot()
            XCTAssertGreaterThanOrEqual(dist, TriWing.ballRadius + 0.2 * u - 1e-5)
            if abs(dist - TriWing.racewayRadius) < 1e-5 { arcPoints += 1 }
        }
        XCTAssertGreaterThan(arcPoints, 12)
        // The groove bottom lies on the ball's equator, beyond the land.
        XCTAssertEqual(face.first!.0, TriWing.ballRingRadius + TriWing.racewayRadius - TriWing.outerRaceInner, accuracy: 1e-5)
        // The arc meets the land at sqrt(4.8^2 - 3^2) = 3.75 units (the bevel sits just above it).
        var landZ: Float = 0
        for (d, z) in face where abs(d) < 1e-6 { landZ = min(landZ == 0 ? z : landZ, z) }
        XCTAssertEqual(landZ, 3.75 * u, accuracy: 0.4 * u)
        // Heights increase monotonically from the groove bottom to the top.
        var k: Int = 1
        while k < face.count { XCTAssertGreaterThanOrEqual(face[k].1, face[k - 1].1 - 1e-7); k += 1 }
    }

    func testRaceTopsAreLowAndRaceLandsAreSymmetricAboutTheBallRing() {
        XCTAssertEqual(TriWing.outerRaceInner - TriWing.ballRingRadius, TriWing.ballRingRadius - TriWing.innerRaceOuter, accuracy: 1e-5)
        XCTAssertGreaterThanOrEqual(TriWing.raceTopZ, 0.050)
        XCTAssertLessThanOrEqual(TriWing.raceTopZ, 0.060)
        XCTAssertLessThan(TriWing.raceTopZ, TriWing.hubRimZ)
    }

    func testCageFitsInsideTheGapWithSlitsOnBothSides() {
        let u: Float = TriWing.unit
        // Open through-slit of at least one unit on each side of the cage.
        XCTAssertGreaterThanOrEqual(TriWing.cageInner - TriWing.innerRaceOuter, 1 * u - 1e-6)
        XCTAssertGreaterThanOrEqual(TriWing.outerRaceInner - TriWing.cageOuter, 1 * u - 1e-6)
        // A proper cage segment: 3.4 to 3.8 units wide, centred on the ball ring.
        let width: Float = TriWing.cageOuter - TriWing.cageInner
        XCTAssertGreaterThanOrEqual(width, 3.4 * u - 1e-6)
        XCTAssertLessThanOrEqual(width, 3.8 * u + 1e-6)
        XCTAssertEqual(TriWing.ballRingRadius - TriWing.cageInner, TriWing.cageOuter - TriWing.ballRingRadius, accuracy: 1e-5)
        // The pockets cut both edges (the width is less than the pocket diameter).
        XCTAssertLessThan(TriWing.ballRingRadius - TriWing.cageInner, TriWing.cagePocketRadius)
        XCTAssertLessThan(TriWing.cageOuter - TriWing.ballRingRadius, TriWing.cagePocketRadius)
    }

    func testCagePocketClearanceThicknessAndBevel() {
        let u: Float = TriWing.unit
        let clearance: Float = TriWing.cagePocketRadius - TriWing.ballRadius
        XCTAssertGreaterThanOrEqual(clearance, 0.2 * u - 1e-6)
        XCTAssertLessThanOrEqual(clearance, 0.3 * u + 1e-6)
        // Thicker than before (0.007), inside the race height, with a bevel smaller than the half thickness.
        XCTAssertGreaterThan(TriWing.cageHalfThickness, 0.012)
        XCTAssertLessThan(TriWing.cageHalfThickness, TriWing.raceTopZ)
        XCTAssertGreaterThan(TriWing.cageBevelDrop, 0)
        XCTAssertLessThan(TriWing.cageBevelDrop, TriWing.cageHalfThickness)
        XCTAssertGreaterThan(TriWing.cageBevelInset, 0)
        XCTAssertLessThan(TriWing.cageBevelInset, 0.5 * (TriWing.cageOuter - TriWing.cageInner))
    }

    func testTwoNotchFeaturesOppositeOnTheHorizontalAxis() {
        XCTAssertEqual(TriWing.notchCount, 2)
        XCTAssertEqual(TriWing.notchAngles.count, 2)
        let d: Float = abs(TriWing.notchAngles[0] - TriWing.notchAngles[1])
        XCTAssertEqual(d, Float.pi, accuracy: 1e-4)
        // Wing 0 points up: the pair sits at 3 and 9 o'clock.
        for a in TriWing.notchAngles { XCTAssertEqual(abs(sin(a)), 0, accuracy: 1e-4) }
        // The slit is open through the ring's outer edge; its inner end is clear of the ring's inner edge.
        XCTAssertGreaterThan(TriWing.slotInnerRadius, TriWing.ringInner)
        XCTAssertGreaterThanOrEqual(TriWing.slotOuterRadius, TriWing.ringOuter)
    }

    func testSpannerSlotIsASquareEndedToolOpening() {
        let u: Float = TriWing.unit
        // About 6 units wide, about 7 deep (open through the ring's outer edge), a wide 1 unit polished chamfer.
        XCTAssertEqual(TriWing.slotWidth, 6 * u, accuracy: 1e-6)
        XCTAssertEqual(TriWing.slotInnerRadius, 66 * u, accuracy: 1e-6)
        XCTAssertEqual(TriWing.slotOuterRadius - TriWing.slotInnerRadius, 7 * u, accuracy: 1e-6)
        XCTAssertEqual(TriWing.notchChamfer, 1 * u, accuracy: 1e-6)
        // The chamfer is narrower than half the slot, so a flat floor remains between the chamfers' feet.
        XCTAssertLessThan(2 * TriWing.notchChamfer, TriWing.slotWidth * 0.5)
        // The pocket reaches about one unit past the ring's outer edge onto the body.
        let over: Float = TriWing.notchPocketOuterRadius - TriWing.ringOuter
        XCTAssertGreaterThanOrEqual(over, 0.8 * u)
        XCTAssertLessThanOrEqual(over, 1.2 * u)
        // Deep enough that the wall reads at pitch 35 (ring height plus 0.025 to 0.04 into the body), with a sound web
        // left between the two faces' pockets.
        XCTAssertGreaterThanOrEqual(TriWing.notchPocketDepth, 0.025)
        XCTAssertLessThanOrEqual(TriWing.notchPocketDepth, 0.040)
        XCTAssertGreaterThanOrEqual(2 * (TriWing.halfThickness - TriWing.notchPocketDepth), 0.15)
        // The contact-shade band is narrow, so most of the milled floor stays light.
        XCTAssertLessThan(TriWing.notchFloorShadeWidth, TriWing.slotWidth * 0.1)
        // At least 6 units of plain ring metal between the slot's inner end (chamfer included) and the ring's inner edge.
        XCTAssertGreaterThanOrEqual((TriWing.slotInnerRadius - TriWing.notchChamfer) - TriWing.ringInner, 6.0 * u)
        // The reserved half span along the circumference covers the chamfered top outline.
        XCTAssertEqual(TriWing.notchFeatureHalfSpan, TriWing.slotWidth * 0.5 + TriWing.notchChamfer, accuracy: 1e-6)
    }

    func testNotchFeaturesClearTheWingPadsAndTheLetteringBand() {
        let ringW: Float = TriWing.ringOuter - TriWing.ringInner
        XCTAssertGreaterThan(TriWing.ringTextBaselineV, 0.0045 + 0.004)
        XCTAssertLessThan(TriWing.ringTextBaselineV + TriWing.ringTextCapHeight, ringW - 0.0045 - 0.004)
        // The pads lie wholly outside the ring, so the notches cannot sit under one.
        var minPad: Float = 1e9
        for q in TriWing.padOutline() { minPad = min(minPad, (q.x * q.x + q.y * q.y).squareRoot()) }
        XCTAssertGreaterThan(minPad, TriWing.ringOuter)
    }

    func testFluteZonesFlankAPlainNumberPanelAndStopShortOfTheNotchFeatures() {
        let zones: [TriWing.FluteZone] = TriWing.fluteZones()
        XCTAssertEqual(zones.count, 2)
        let c6: Float = TriWing.ringArcCentreU(lower: true)
        let a: TriWing.FluteZone = zones[0]
        let b: TriWing.FluteZone = zones[1]
        XCTAssertLessThan(a.u1, b.u0)
        // The pair is mirror symmetric about 6 o'clock.
        XCTAssertEqual(c6 - a.u1, b.u0 - c6, accuracy: 1e-4)
        XCTAssertEqual(c6 - a.u0, b.u1 - c6, accuracy: 1e-4)
        for z in zones {
            XCTAssertEqual(z.u1 - z.u0, Float(z.count) * z.pitch, accuracy: 1e-4)
            XCTAssertGreaterThanOrEqual(z.count, 20)
            XCTAssertEqual(z.pitch, 3 * TriWing.unit, accuracy: 1e-6)
            XCTAssertEqual(z.depth, 0.005, accuracy: 1e-6)
            XCTAssertLessThan(z.depth + TriWing.fluteRidgeDrop, TriWing.ringHeight)
            // Radial band 60 ... 70 units centred in the ring.
            XCTAssertEqual(z.v0 + TriWing.ringInner, 60 * TriWing.unit, accuracy: 1e-5)
            XCTAssertEqual(z.v1 + TriWing.ringInner, 70 * TriWing.unit, accuracy: 1e-5)
            XCTAssertGreaterThan(z.v0, 0.0045 + 0.002)
        }
        // At least 10 units between the outer end of each zone and the nearest notch feature.
        let span: Float = TriWing.notchFeatureHalfSpan
        for na in TriWing.notchAngles {
            let nu: Float = TriWing.ringU(angle: na)
            for z in zones {
                let gap: Float = min(abs(z.u0 - (nu + span)), abs(nu - span - z.u1))
                if gap < TriWing.ringCircumference * 0.2 {
                    XCTAssertGreaterThanOrEqual(gap, 10 * TriWing.unit - 1e-4)
                }
            }
        }
        // The plain panel between the zones holds the number with at least `fluteTextMargin` of plain metal either side.
        let text: RingTextLayout = RingTextLayout.layoutFace(.front)
        var lo: Float = 1e9
        var hi: Float = -1e9
        for it in text.items where it.lower {
            lo = min(lo, it.u)
            hi = max(hi, it.u + it.width)
        }
        XCTAssertLessThan(lo, hi)
        XCTAssertGreaterThanOrEqual(lo - a.u1, TriWing.fluteTextMargin - 1e-4)
        XCTAssertGreaterThanOrEqual(b.u0 - hi, TriWing.fluteTextMargin - 1e-4)
        XCTAssertLessThan(lo - a.u1, TriWing.fluteTextMargin + 1.5 * TriWing.unit)
    }

    func testFloorShadeLoopIsInsideThePocketLoop() {
        for a in TriWing.notchAngles {
            let outer: [P2] = TriWing.notchPocketLoop(angle: a, arcSegments: 32)
            let inner: [P2] = TriWing.notchPocketLoop(angle: a, arcSegments: 32, inset: TriWing.notchFloorShadeWidth)
            for q in inner {
                XCTAssertTrue(polygonContains(outer, q))
                XCTAssertGreaterThan(polygonBoundaryDistance(outer, q), 0.8 * TriWing.notchFloorShadeWidth)
            }
        }
    }

    func testNotchPocketsLieOnBodyMetalClearOfSlotsAndWell() {
        let inset: [P2] = polygonOffsetInward(TriWing.bodyOutline(), by: TriWing.bodyChamfer)
        var slotLoops: [[P2]] = []
        for k in 0..<TriWing.wingCount {
            for side: Float in [-1, 1] {
                slotLoops.append(polygonRotated(TriWing.flankSlotOutline(side: side), by: TriWing.wingAngle(k)))
            }
        }
        for a in TriWing.notchAngles {
            let loop: [P2] = TriWing.notchPocketLoop(angle: a, arcSegments: 24)
            XCTAssertGreaterThan(loop.count, 20)
            for q in loop {
                XCTAssertTrue(polygonContains(inset, q))
                XCTAssertGreaterThan(polygonBoundaryDistance(inset, q), 0.01)
                let r: Float = (q.x * q.x + q.y * q.y).squareRoot()
                XCTAssertGreaterThan(r, TriWing.wellRadius + 0.02)
                for s in slotLoops {
                    XCTAssertFalse(polygonContains(s, q))
                    XCTAssertGreaterThan(polygonBoundaryDistance(s, q), 0.01, "pocket too close to a tube slot")
                }
                for sc in TriWing.screwCentres {
                    for k in 0..<TriWing.wingCount {
                        let c: P2 = TriWing.inWing(sc, k)
                        let dx: Float = q.x - c.x
                        let dy: Float = q.y - c.y
                        XCTAssertGreaterThan((dx * dx + dy * dy).squareRoot(), 0.05)
                    }
                }
            }
        }
    }
}

final class TriWingPadClearanceTests: XCTestCase {
    func testScrewCountersinksAndPatchClearThePadChamferInset() {
        let inset = polygonOffsetInward(TriWing.padOutline(), by: TriWing.padChamfer)
        for c in TriWing.screwCentres {
            for q in circlePolygon(center: c, radius: TriWing.countersinkScrewRadius, segments: 32) {
                XCTAssertTrue(polygonContains(inset, q))
                XCTAssertGreaterThan(polygonBoundaryDistance(inset, q), 0.001)
            }
        }
        let half = TriWing.patchSize * 0.5
        let corners: [P2] = [P2(-half.x, -half.y), P2(half.x, -half.y), P2(half.x, half.y), P2(-half.x, half.y)]
        for q in corners { XCTAssertTrue(polygonContains(inset, TriWing.patchCentre + q)) }
        let boss = circlePolygon(center: TriWing.bossCenter, radius: TriWing.bossRadius, segments: 48)
        for q in boss { XCTAssertTrue(polygonContains(inset, q) || polygonBoundaryDistance(inset, q) < 0.02) }
    }

    func testEdgeLightFilamentCollarAndLipFitTheSlot() {
        // A thin hot filament inside the glass shell, a collar that is wider than the shell but still clears the slot wall.
        XCTAssertGreaterThan(TriWing.tubeFilamentRadius, 0)
        XCTAssertLessThan(TriWing.tubeFilamentRadius, TriWing.tubeCoreRadius)
        XCTAssertGreaterThan(TriWing.tubeCollarRadius, TriWing.tubeShellRadius)
        XCTAssertLessThan(TriWing.tubeCollarRadius, TriWing.tubeSlotHalfWidth)
        XCTAssertGreaterThan(TriWing.tubeCollarLength, TriWing.tubeShellRadius * 0.4)
        // The chamfer is small against the collar, and the collar's end cap stays inside the slot's end.
        XCTAssertGreaterThan(TriWing.tubeCollarChamfer, 0)
        XCTAssertLessThan(TriWing.tubeCollarChamfer, TriWing.tubeCollarRadius * 0.3)
        XCTAssertLessThan(TriWing.tubeCollarCapReach, TriWing.tubeSlotHalfWidth)
        // The collar's top stays below the face.
        XCTAssertLessThan(2 * TriWing.tubeCollarRadius, TriWing.tubeSlotDepth)
    }

    func testSlotLipLineIsThinAndClearsThePadAndTheOtherSlots() {
        XCTAssertGreaterThan(TriWing.slotLipWidth, 0)
        XCTAssertLessThan(TriWing.slotLipWidth, 0.006)
        let pad: [P2] = TriWing.padOutline()
        for side: Float in [-1, 1] {
            let loop: [P2] = TriWing.flankSlotOutline(side: side)
            for q in loop {
                // Lip strip outer edge is `slotLipWidth` beyond the slot: it must not reach the pad.
                if polygonContains(pad, q) { continue }
                XCTAssertGreaterThan(polygonBoundaryDistance(pad, q), TriWing.slotLipWidth * 1.5, "lip strip would touch the pad")
            }
        }
    }
}
