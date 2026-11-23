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

final class TriWingSweptTests: XCTestCase {
    private let smear = TriWingSmear.compute(radii: 128, angles: 240)

    // MARK: Ramp

    func testRampEndpoints() {
        let a = TriWingSwept.ramp(0)
        XCTAssertEqual(a.solid, 1, accuracy: 1e-6)
        XCTAssertEqual(a.core, 0, accuracy: 1e-6)
        XCTAssertEqual(a.zone, 0, accuracy: 1e-6)
        let b = TriWingSwept.ramp(1)
        XCTAssertEqual(b.solid, 0, accuracy: 1e-6)
        XCTAssertEqual(b.core, 1, accuracy: 1e-6)
        XCTAssertEqual(b.zone, 1, accuracy: 1e-6)
    }

    func testZoneComesInLateAndNeverBeforeTheCore() {
        var t: Float = 0
        var prevZone: Float = 0
        var prevCore: Float = 0
        while t <= 1.0001 {
            let r = TriWingSwept.ramp(t)
            XCTAssertLessThanOrEqual(r.zone, r.core + 1e-6)
            XCTAssertGreaterThanOrEqual(r.zone, prevZone - 1e-6)
            XCTAssertGreaterThanOrEqual(r.core, prevCore - 1e-6)
            prevZone = r.zone
            prevCore = r.core
            t += 0.03125
        }
        // Halfway up the ramp the swept wing zone is still faint (no ripple rings outside the solid's outline).
        XCTAssertLessThan(TriWingSwept.ramp(0.5).zone, 0.15)
        XCTAssertLessThan(TriWingSwept.ramp(0.4).zone, 0.08)
    }

    func testSolidStaysOpaqueUntilTheCoreIsMostlyIn() {
        XCTAssertEqual(TriWingSwept.ramp(0.69).solid, 1, accuracy: 1e-6)
        XCTAssertLessThan(TriWingSwept.ramp(0.9).solid, 0.5)
        // No hole: where the solid has faded to half, the core overlay is already mostly in.
        let r = TriWingSwept.ramp(0.85)
        XCTAssertGreaterThan(r.core, 0.8)
    }

    // MARK: Opacity curve

    func testZoneOpacityCurve() {
        XCTAssertEqual(TriWingSwept.zoneOpacity(coverage: 0), 0, accuracy: 1e-6)
        XCTAssertEqual(TriWingSwept.zoneOpacity(coverage: 0.005), 0, accuracy: 1e-6)
        XCTAssertEqual(TriWingSwept.zoneOpacity(coverage: 1), 1, accuracy: 1e-6)
        var prev: Float = 0
        var c: Float = 0
        while c <= 1.0001 {
            let o = TriWingSwept.zoneOpacity(coverage: c)
            XCTAssertGreaterThanOrEqual(o, prev - 1e-6)
            XCTAssertLessThanOrEqual(o, 1.0001)
            if c > 0.05 && c < 0.99 { XCTAssertGreaterThan(o, c) }   // lifted so the zone reads on a dark backdrop
            prev = o
            c += 0.01
        }
    }

    func testZoneOpacityHasNoHardEdge() {
        var prev: Float = 0
        var c: Float = 0
        while c <= 0.1 {
            let o = TriWingSwept.zoneOpacity(coverage: c)
            XCTAssertLessThan(o - prev, 0.06)
            prev = o
            c += 0.001
        }
    }

    // MARK: Shells and heights

    func testManyShellsStayBelowOpaqueAndStackToTheEdgeOnOcclusion() {
        let shells = smear.sweptShells(count: 36)
        XCTAssertEqual(shells.count, 36)
        for s in shells {
            XCTAssertGreaterThan(s.opacity, 0)
            XCTAssertLessThan(s.opacity, 0.7)   // no single shell is an opaque sheet (the largest steps sit where the stack nears its cap, where transmittance is tiny)
        }
        // A ray seen edge-on at offset x crosses every shell of radius above x.
        let dr: Float = shells[1].radius - shells[0].radius
        for x: Float in [0.65, 0.75, 0.85, 0.92] {
            var through: Float = 1
            for s in shells where s.radius - dr * 0.5 >= x - 1e-4 { through *= 1 - s.opacity }
            let target: Float = min(TriWingSmear.edgeOnOcclusion(x: x), TriWingSmear.shellOpacityCap)
            XCTAssertEqual(1 - through, target, accuracy: 0.08, "x = \(x)")
        }
    }

    func testEdgeOnOcclusionIsOneInsideMonotoneAndZeroBeyondTheTip() {
        XCTAssertEqual(TriWingSmear.edgeOnOcclusion(x: 0), 1, accuracy: 1e-6)
        XCTAssertEqual(TriWingSmear.edgeOnOcclusion(x: smear.fullCoverageRadius() - 0.01), 1, accuracy: 1e-6)
        XCTAssertEqual(TriWingSmear.edgeOnOcclusion(x: 1.2), 0, accuracy: 1e-6)
        var prev: Float = 1
        var x: Float = 0
        while x <= 1.1 {
            let t: Float = TriWingSmear.edgeOnOcclusion(x: x)
            XCTAssertLessThanOrEqual(t, prev + 1e-6)
            prev = t
            x += 0.01
        }
    }

    func testEdgeOnOcclusionMeasuredValuesForThreeWings() {
        let t8: Float = TriWingSmear.edgeOnOcclusion(x: 0.8)
        let t9: Float = TriWingSmear.edgeOnOcclusion(x: 0.9)
        XCTAssertGreaterThan(t8, 0.5)
        XCTAssertLessThan(t8, 0.95)
        XCTAssertGreaterThan(t9, 0.3)
        XCTAssertLessThan(t9, 0.7)
        XCTAssertGreaterThan(t8, t9)
    }

    func testSweptHeightIsSmoothAndWithinTheBodyAndPad() {
        var prev: Float = smear.sweptHalfHeight(at: smear.fullCoverageRadius())
        var r: Float = smear.fullCoverageRadius()
        let top: Float = TriWing.halfThickness + TriWing.padHeight + TriWing.bossHeight
        while r < smear.tipRadius() {
            let h = smear.sweptHalfHeight(at: r)
            XCTAssertGreaterThanOrEqual(h, TriWing.halfThickness - 0.003 - 1e-6)
            XCTAssertLessThanOrEqual(h, top + 1e-6)
            XCTAssertLessThan(abs(h - prev), 0.0022)
            prev = h
            r += 0.004
        }
    }

    // MARK: Light rings and side band

    func testGlowRingsAreVividSoftAndSaturated() {
        let ring = smear.glowRing()
        XCTAssertEqual(ring.opacity.count, smear.radii)
        var peak: Float = 0
        var peakAt: Int = 0
        for (i, o) in ring.opacity.enumerated() {
            XCTAssertLessThanOrEqual(o, TriWingSwept.ringPeakOpacity + 1e-6)
            if o > peak { peak = o; peakAt = i }
            if i > 0 { XCTAssertLessThan(abs(o - ring.opacity[i - 1]), 0.25) }
        }
        XCTAssertGreaterThan(peak, 0.6)
        // Colour at the peak is a saturated wing colour, not grey.
        let c = ring.colour[peakAt]
        let hi: Float = max(c.x, max(c.y, c.z))
        let lo: Float = min(c.x, min(c.y, c.z))
        XCTAssertGreaterThan(hi, 0.9)
        XCTAssertLessThan(lo, 0.6 * hi)
    }

    func testGlowRingsHaveThreeColourBands() {
        let ring = smear.glowRing()
        var hues = Set<Int>()
        for (i, o) in ring.opacity.enumerated() where o > 0.4 {
            let c = ring.colour[i]
            if c.y >= c.x && c.y >= c.z && c.x < c.z + 0.4 { hues.insert(1) }       // green / cyan side
            if c.x > c.y && c.x > c.z { hues.insert(2) }                              // orange
            if c.z > c.x && c.z >= c.y * 0.9 { hues.insert(3) }                       // cyan / blue
        }
        XCTAssertGreaterThanOrEqual(hues.count, 2)
    }

    func testSideBandSharesAndColours() {
        let band = TriWingSwept.sideBand(waistRadius: 0.6)
        XCTAssertGreaterThan(band.share, 0.15)
        XCTAssertLessThan(band.share, 0.6)
        XCTAssertGreaterThan(band.halfHeight, 0.01)
        XCTAssertLessThan(band.halfHeight, TriWingWall.bandHalfHeight)
        for c in [band.upper, band.lower] {
            XCTAssertGreaterThan(max(c.x, max(c.y, c.z)), 0.5)
        }
    }

    func testSaturationLiftIncreasesChroma() {
        let grey = SIMD3<Float>(0.5, 0.75, 0.5)
        let lifted = TriWingSwept.liftSaturation(grey, 1.8)
        XCTAssertGreaterThan(lifted.y - lifted.x, grey.y - grey.x)
        XCTAssertGreaterThanOrEqual(min(lifted.x, min(lifted.y, lifted.z)), 0)
    }
}
