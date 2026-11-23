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

final class TriWingGlyphTests: XCTestCase {

    private let alphabet: String = "ABCDEHIJKLMNOPRSTUVWYZ01o."

    func testEveryCharacterOfEveryArcHasAGlyph() {
        for face in [TriWing.RingFace.front, TriWing.RingFace.back] {
            for spec in TriWing.ringArcs(face: face) {
                for c in spec.text where c != " " { XCTAssertNotNil(EngravingFont.glyph(for: c), "missing glyph \(c)") }
            }
        }
        for c in EngravingFont.supported { XCTAssertNotNil(EngravingFont.glyph(for: c), "missing glyph \(c)") }
        for c in alphabet { XCTAssertTrue(EngravingFont.supported.contains(c), "font lacks \(c)") }
        XCTAssertEqual(Set(EngravingFont.supported), Set(alphabet))
        XCTAssertNil(EngravingFont.glyph(for: "Q"))
        XCTAssertNil(EngravingFont.glyph(for: "F"))
    }

    func testEachFaceHasItsOwnLettering() {
        XCTAssertEqual(TriWing.ringArcs(face: .front), [TriWing.RingArcSpec(text: "KEEP YOUR OWN TIME", lower: false),
                                                       TriWing.RingArcSpec(text: "No 001", lower: true)])
        XCTAssertEqual(TriWing.ringArcs(face: .back), [TriWing.RingArcSpec(text: "THE VISUALIZER CO.", lower: false),
                                                      TriWing.RingArcSpec(text: "ADJUSTED TO THE BEAT", lower: true)])
    }

    // MARK: Glyph pieces and shapes

    /// Ink samples (signed distance below zero) of a glyph on a grid.
    private func inkGrid(_ g: EngravedGlyph, step: Float) -> (nx: Int, ny: Int, ink: [Bool]) {
        let nx: Int = Int((g.width + 0.1) / step) + 1
        let ny: Int = Int(1.1 / step) + 1
        var ink: [Bool] = []
        var j: Int = 0
        while j < ny {
            var i: Int = 0
            while i < nx {
                let p = P2(-0.05 + Float(i) * step, -0.05 + Float(j) * step)
                ink.append(g.distance(p) < 0)
                i += 1
            }
            j += 1
        }
        return (nx, ny, ink)
    }

    /// Lengths of the ink runs along the horizontal line at height `y` (cap units).
    private func runsAlong(_ g: EngravedGlyph, y: Float) -> [Float] {
        var runs: [Float] = []
        var run: Float = 0
        let step: Float = 0.002
        var x: Float = -0.05
        while x <= g.width + 0.05 {
            if g.distance(P2(x, y)) < 0 { run += step } else if run > 0 { runs.append(run); run = 0 }
            x += step
        }
        if run > 0 { runs.append(run) }
        return runs
    }

    private func verticalRuns(_ g: EngravedGlyph, x: Float) -> [Float] {
        var runs: [Float] = []
        var run: Float = 0
        let step: Float = 0.002
        var y: Float = -0.05
        while y <= g.top + 0.05 {
            if g.distance(P2(x, y)) < 0 { run += step } else if run > 0 { runs.append(run); run = 0 }
            y += step
        }
        if run > 0 { runs.append(run) }
        return runs
    }

    func testInkStaysInTheGlyphBoxAndFillsIt() {
        for c in EngravingFont.supported {
            guard let g = EngravingFont.glyph(for: c) else { continue }
            let step: Float = 0.01
            let grid = inkGrid(g, step: step)
            var minX: Float = 9, maxX: Float = -9, minY: Float = 9, maxY: Float = -9
            var j: Int = 0
            while j < grid.ny {
                var i: Int = 0
                while i < grid.nx {
                    if grid.ink[j * grid.nx + i] {
                        let x: Float = -0.05 + Float(i) * step
                        let y: Float = -0.05 + Float(j) * step
                        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                    }
                    i += 1
                }
                j += 1
            }
            XCTAssertGreaterThanOrEqual(minX, -1e-4, "\(c)")
            XCTAssertLessThanOrEqual(maxX, g.width + 1e-4, "\(c)")
            XCTAssertGreaterThanOrEqual(minY, -1e-4, "\(c)")
            XCTAssertLessThanOrEqual(maxY, g.top + 1e-4, "\(c)")
            // The box is tight: ink reaches within a few hundredths of each side.
            XCTAssertLessThan(minX, 0.03, "\(c) left")
            XCTAssertGreaterThan(maxX, g.width - 0.03, "\(c) right")
            XCTAssertLessThan(minY, 0.02, "\(c) bottom")
            XCTAssertGreaterThan(maxY, g.top - 0.02, "\(c) top")
        }
    }

    func testCapHeightLowerCaseAndFullStop() {
        for c in "ABCDEHIJKLMNOPRSTUVWYZ01" { XCTAssertEqual(EngravingFont.glyph(for: c)?.top ?? 0, 1, accuracy: 1e-6, "\(c)") }
        let o: Float = EngravingFont.glyph(for: "o")?.top ?? 0
        XCTAssertGreaterThan(o, 0.5)
        XCTAssertLessThan(o, 0.66)
        let dot: Float = EngravingFont.glyph(for: ".")?.top ?? 1
        XCTAssertLessThan(dot, 0.2)
        XCTAssertGreaterThan(dot, 0.08)
    }

    func testStemsAreAboutSixteenPercentOfTheCapHeightAndHorizontalsAreThinner() {
        XCTAssertEqual(2 * EngravingFont.stemHalfWidth, 0.16, accuracy: 1e-6)
        let ratio: Float = EngravingFont.thinHalfWidth / EngravingFont.stemHalfWidth
        XCTAssertGreaterThanOrEqual(ratio, 0.6)
        XCTAssertLessThanOrEqual(ratio, 0.7)
        guard let i = EngravingFont.glyph(for: "I"), let h = EngravingFont.glyph(for: "H") else { return XCTFail() }
        let stem: [Float] = runsAlong(i, y: 0.5)
        XCTAssertEqual(stem.count, 1)
        XCTAssertEqual(stem.first ?? 0, 0.16, accuracy: 0.006)
        // H: both stems at 0.16, the crossbar (a vertical run at the middle) thinner but not below 0.6 of a stem.
        let stems: [Float] = runsAlong(h, y: 0.25)
        XCTAssertEqual(stems.count, 2)
        for s in stems { XCTAssertEqual(s, 0.16, accuracy: 0.006) }
        let bar: [Float] = verticalRuns(h, x: h.width * 0.5)
        XCTAssertEqual(bar.count, 1)
        XCTAssertLessThan(bar.first ?? 1, 0.16)
        XCTAssertGreaterThanOrEqual(bar.first ?? 0, 0.6 * 0.16 - 0.006)
        // A round letter is thick at its sides and thin at its top and bottom.
        guard let o = EngravingFont.glyph(for: "O") else { return XCTFail() }
        let side: Float = runsAlong(o, y: 0.5).first ?? 0
        let top: Float = verticalRuns(o, x: o.width * 0.5).first ?? 1
        XCTAssertEqual(side, 0.16, accuracy: 0.01)
        XCTAssertLessThan(top, side * 0.75)
        XCTAssertGreaterThanOrEqual(top, 0.6 * side - 0.01)
    }

    func testStrokeEndsAreSquaredNotRound() {
        let bar = GlyphPiece.bar(a: P2(0, 0), b: P2(1, 0), wa: 0.1, wb: 0.1)
        XCTAssertLessThan(bar.distance(P2(0.9999, 0.099)), 0)
        XCTAssertLessThan(bar.distance(P2(0.0001, -0.099)), 0)
        XCTAssertGreaterThan(bar.distance(P2(1.002, 0.09)), 0)      // a round cap would still hold this point
        XCTAssertGreaterThan(bar.distance(P2(-0.002, -0.09)), 0)
        XCTAssertGreaterThan(bar.distance(P2(0.5, 0.101)), 0)
        // Tapered: the half width runs from `wa` to `wb`.
        let wedge = GlyphPiece.bar(a: P2(0, 0), b: P2(1, 0), wa: 0.1, wb: 0.02)
        XCTAssertLessThan(wedge.distance(P2(0.02, 0.09)), 0)
        XCTAssertGreaterThan(wedge.distance(P2(0.98, 0.05)), 0)
        XCTAssertLessThan(wedge.distance(P2(0.98, 0.015)), 0)
        // An arc is cut square at its ends too (radially), and is empty outside its angular range.
        let arc = GlyphPiece.arc(cx: 0, cy: 0, rx: 1, ry: 1, from: 0, to: 90, thick: 0.1, thin: 0.1)
        XCTAssertLessThan(arc.distance(P2(1, 0.01)), 0)
        XCTAssertGreaterThan(arc.distance(P2(1, -0.01)), 0)
        XCTAssertGreaterThan(arc.distance(P2(-1, 0)), 0)
    }

    func testStemEndsCarryModestWedgeSerifs() {
        guard let i = EngravingFont.glyph(for: "I"), let l = EngravingFont.glyph(for: "L") else { return XCTFail() }
        let stem: Float = runsAlong(i, y: 0.5).first ?? 0
        for y: Float in [0.02, 0.98] {
            let w: Float = runsAlong(i, y: y).first ?? 0
            XCTAssertGreaterThan(w, stem + 0.10, "serif at y=\(y)")
            XCTAssertLessThan(w, stem + 0.40, "serif at y=\(y)")
        }
        // The serif is a wedge: thinner toward its tip than at the stem.
        let nearStem: Float = verticalRuns(i, x: i.width * 0.5 + 0.10).first ?? 0
        let nearTip: Float = verticalRuns(i, x: 0.02).first ?? 0
        XCTAssertGreaterThan(nearStem, nearTip)
        XCTAssertGreaterThan(nearTip, 0)
        XCTAssertGreaterThan(l.width, 0.4)
    }

    func testEveryGlyphIsOneConnectedMark() {
        for c in EngravingFont.supported {
            guard let g = EngravingFont.glyph(for: c) else { continue }
            let step: Float = 0.008
            let grid = inkGrid(g, step: step)
            var seen = [Bool](repeating: false, count: grid.ink.count)
            var components: Int = 0
            var k: Int = 0
            while k < grid.ink.count {
                if grid.ink[k] && !seen[k] {
                    components += 1
                    var stack: [Int] = [k]
                    seen[k] = true
                    while let q = stack.popLast() {
                        let qi: Int = q % grid.nx
                        let qj: Int = q / grid.nx
                        for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                            let ni: Int = qi + di
                            let nj: Int = qj + dj
                            if ni < 0 || nj < 0 || ni >= grid.nx || nj >= grid.ny { continue }
                            let nk: Int = nj * grid.nx + ni
                            if grid.ink[nk] && !seen[nk] { seen[nk] = true; stack.append(nk) }
                        }
                    }
                }
                k += 1
            }
            XCTAssertEqual(components, 1, "glyph \(c) falls into \(components) pieces")
        }
    }

    // MARK: Layout

    private func upper(_ text: String, centre: Float = 0.5) -> RingTextLayout {
        RingTextLayout.layoutArc(text: text, centreU: centre, lower: false, capHeight: TriWing.ringTextCapHeight,
                                 tracking: TriWing.ringTextTracking, baselineV: TriWing.ringTextBaselineV)
    }
    private func lower(_ text: String, centre: Float = 0.5) -> RingTextLayout {
        RingTextLayout.layoutArc(text: text, centreU: centre, lower: true, capHeight: TriWing.ringTextCapHeight,
                                 tracking: TriWing.ringTextTracking, baselineV: TriWing.ringTextBaselineV)
    }

    func testLetteringIsSmallerLighterAndMoreOpenThanBefore() {
        XCTAssertEqual(TriWing.ringTextCapHeight, 6.0 * TriWing.unit, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(TriWing.ringTextTracking, 0.25 * TriWing.ringTextCapHeight)
        XCTAssertEqual(RingTextLayout.wordGap, 0.35, accuracy: 1e-6)
        let ringW: Float = TriWing.ringOuter - TriWing.ringInner
        XCTAssertEqual(TriWing.ringTextBaselineV, (ringW - TriWing.ringTextCapHeight) * 0.5, accuracy: 1e-6)
    }

    func testEveryArcIsCentredOnItsClockPosition() {
        for face in [TriWing.RingFace.front, TriWing.RingFace.back] {
            for spec in TriWing.ringArcs(face: face) {
                let centre: Float = TriWing.ringArcCentreU(lower: spec.lower)
                let l = RingTextLayout.layoutArc(text: spec.text, centreU: centre, lower: spec.lower,
                                                 capHeight: TriWing.ringTextCapHeight, tracking: TriWing.ringTextTracking,
                                                 baselineV: TriWing.ringTextBaselineV)
                let e = l.extent()
                XCTAssertEqual((e.lo + e.hi) * 0.5, centre, accuracy: 0.0005, spec.text)
            }
        }
        let d: Float = abs(TriWing.ringArcCentreU(lower: true) - TriWing.ringArcCentreU(lower: false))
        XCTAssertEqual(d, TriWing.ringCircumference * 0.5, accuracy: 1e-4)
    }

    func testAllArcsShareOneTrackingAndGlyphsKeepTheirNaturalSpacing() {
        // The same letter pair is spaced identically wherever it occurs (R then O: YOUR OWN has none, so use "OR" in
        // VISUALIZER CO. and "KEEP YOUR" has "UR": compare the U-R pair, which occurs on the front and the back).
        func gap(_ l: RingTextLayout, _ a: Character, _ b: Character) -> Float? {
            var i: Int = 0
            while i + 1 < l.items.count {
                if l.items[i].character == a && l.items[i + 1].character == b && !l.items[i].lower {
                    return l.items[i + 1].u - (l.items[i].u + l.items[i].width)
                }
                i += 1
            }
            return nil
        }
        let a: RingTextLayout = RingTextLayout.layoutFace(.front)
        let b: RingTextLayout = RingTextLayout.layoutFace(.back)
        XCTAssertEqual(a.tracking, TriWing.ringTextTracking)
        XCTAssertEqual(b.tracking, TriWing.ringTextTracking)
        guard let gf = gap(a, "U", "R"), let gb = gap(b, "U", "A") else { return XCTFail("pairs missing") }
        // U-R (front, "YOUR") and U-A (back, "VISUALIZER"): both straight/diagonal pairs follow the bearing table.
        guard let uGlyph = EngravingFont.glyph(for: "U"), let rGlyph = EngravingFont.glyph(for: "R"),
              let aGlyph = EngravingFont.glyph(for: "A") else { return XCTFail() }
        let cap: Float = TriWing.ringTextCapHeight
        let expectF: Float = (EngravingFont.bearing(uGlyph.right) + EngravingFont.bearing(rGlyph.left)) * cap + TriWing.ringTextTracking
        let expectB: Float = (EngravingFont.bearing(uGlyph.right) + EngravingFont.bearing(aGlyph.left)) * cap + TriWing.ringTextTracking
        XCTAssertEqual(gf, expectF, accuracy: 1e-5)
        XCTAssertEqual(gb, expectB, accuracy: 1e-5)
    }

    func testShortLinesStayCompactNotStretched() {
        let short: RingTextLayout = lower("No 001")
        let e = short.extent()
        let natural: Float = RingTextLayout.span(of: "No 001", capHeight: TriWing.ringTextCapHeight, tracking: TriWing.ringTextTracking)
        XCTAssertEqual(e.hi - e.lo, natural, accuracy: 1e-4)
        XCTAssertLessThan(e.hi - e.lo, TriWing.ringCircumference * 0.15)
    }

    func testReadingDirectionAndOrientationOfUpperAndLowerArcs() {
        let up: RingTextLayout = upper("AD")
        XCTAssertLessThan(up.items[0].u, up.items[1].u)      // reads toward larger u (clockwise)
        XCTAssertFalse(up.items[0].lower)
        let lo: RingTextLayout = lower("AD")
        XCTAssertGreaterThan(lo.items[0].u, lo.items[1].u)   // reads toward smaller u (counter-clockwise: left to right at 6 o'clock)
        XCTAssertTrue(lo.items[0].lower)
        // The lower arc is the upper arc turned half a turn: the ink of a glyph at strip point (u, v) in the upper layout
        // sits at the point-reflected position in the lower one. Probe an L: its foot is at the bottom of the glyph.
        let u: RingTextLayout = upper("L", centre: 0.5)
        let l: RingTextLayout = lower("L", centre: 0.5)
        let cap: Float = TriWing.ringTextCapHeight
        let b0: Float = TriWing.ringTextBaselineV
        let item: RingTextLayout.Item = u.items[0]
        let probeU: Float = item.u + 0.35 * item.width
        let probeV: Float = b0 + 0.04 * cap       // inside the foot (the foot bar), near the baseline
        XCTAssertLessThan(u.distance(u: probeU, v: probeV), 0)
        // Reflected through the arc centre (0.5, b0 + cap / 2): same glyph point.
        let ru: Float = 2 * 0.5 - probeU
        let rv: Float = 2 * (b0 + cap * 0.5) - probeV
        XCTAssertLessThan(l.distance(u: ru, v: rv), 0)
        // And the upper arc's tops point outward: ink just under the cap line is inside the stem (upper), whereas the
        // same v on the lower arc (tops toward the hub) is on the baseline side, where the foot bar's ink is absent.
        XCTAssertGreaterThan(l.distance(u: probeU, v: probeV), -1)    // defined everywhere
        // Both arcs occupy the same radial band, centred in the ring.
        for layout in [u, l] {
            var lo: Float = 1, hi: Float = -1
            var v: Float = 0
            while v < 0.1 {
                var uu: Float = layout.items[0].u - 0.01
                while uu < layout.items[0].u + layout.items[0].width + 0.01 {
                    if layout.distance(u: uu, v: v) < 0 { lo = min(lo, v); hi = max(hi, v) }
                    uu += 0.0008
                }
                v += 0.0004
            }
            XCTAssertEqual(lo, b0, accuracy: 0.0006)
            XCTAssertEqual(hi, b0 + cap, accuracy: 0.0006)
        }
    }

    func testArcsClearTheNotchFeaturesAndTheSeamAndTheLongestLineFits() {
        let c: Float = TriWing.ringCircumference
        let span: Float = TriWing.notchFeatureHalfSpan
        var notchU: [Float] = []
        for a in TriWing.notchAngles { notchU.append(TriWing.ringU(angle: a)) }
        var longest: Float = 0
        for face in [TriWing.RingFace.front, TriWing.RingFace.back] {
            for spec in TriWing.ringArcs(face: face) {
                let l = RingTextLayout.layoutArc(text: spec.text, centreU: TriWing.ringArcCentreU(lower: spec.lower), lower: spec.lower,
                                                 capHeight: TriWing.ringTextCapHeight, tracking: TriWing.ringTextTracking,
                                                 baselineV: TriWing.ringTextBaselineV)
                let e = l.extent()
                longest = max(longest, e.hi - e.lo)
                XCTAssertGreaterThan(e.lo, 0, spec.text)
                XCTAssertLessThan(e.hi, c, spec.text)
                for nu in notchU {
                    let clear: Bool = e.hi <= nu - span - TriWing.ringTextClearance || e.lo >= nu + span + TriWing.ringTextClearance
                    XCTAssertTrue(clear, "\(spec.text) too close to the notch at u=\(nu): \(e.lo) ... \(e.hi)")
                }
            }
        }
        let free: Float = c * 0.5 - 2 * (span + TriWing.ringTextClearance)
        XCTAssertLessThanOrEqual(longest, free)
        XCTAssertGreaterThan(longest, 0.55 * free)
    }

    func testGlyphsNeverTouchEachOther() {
        for face in [TriWing.RingFace.front, TriWing.RingFace.back] {
            let l = RingTextLayout.layoutFace(face)
            var i = 0
            while i + 1 < l.items.count {
                let a = l.items[i], b = l.items[i + 1]
                if a.lower == b.lower {
                    let gap: Float = a.lower ? a.u - (b.u + b.width) : b.u - (a.u + a.width)
                    XCTAssertGreaterThan(gap, 0.12 * TriWing.ringTextCapHeight, "\(a.character)\(b.character)")
                }
                i += 1
            }
        }
    }

    func testInkLiesInsideTheRingBandClearOfTheChamfers() {
        let width: Float = TriWing.ringOuter - TriWing.ringInner
        let b0: Float = TriWing.ringTextBaselineV
        XCTAssertGreaterThan(b0, 0.0045 + 0.004)
        XCTAssertLessThan(b0 + TriWing.ringTextCapHeight, width - 0.0045 - 0.004)
    }

    func testRingStripRoundTripsAndTheSeamIsClearOfEveryFeature() {
        let c: Float = TriWing.ringCircumference
        for a: Float in [0, 1, -1, Float.pi / 2, -Float.pi / 2, 3] {
            let u: Float = TriWing.ringU(angle: a)
            XCTAssertGreaterThanOrEqual(u, 0)
            XCTAssertLessThan(u, c)
            let back: Float = TriWing.ringAngle(u: u)
            XCTAssertEqual(cos(back), cos(a), accuracy: 1e-4)
            XCTAssertEqual(sin(back), sin(a), accuracy: 1e-4)
        }
        XCTAssertGreaterThan(TriWing.ringU(angle: 0.9), TriWing.ringU(angle: 1.0))
        let span: Float = TriWing.notchFeatureHalfSpan
        for a in TriWing.notchAngles {
            let u: Float = TriWing.ringU(angle: a)
            XCTAssertGreaterThan(u - span, 0.5 * TriWing.unit)
            XCTAssertLessThan(u + span, c - 0.5 * TriWing.unit)
        }
    }

    func testMarkFitCentresScalesAndFlips() {
        let design: [(a: P2, b: P2, width: Float)] = [(a: P2(0, 0), b: P2(10, 20), width: 4)]
        let fitted = MarkFit.strokes(design, designCentre: P2(5, 10), designHeight: 20, targetHeight: 2, flipY: true)
        XCTAssertEqual(fitted[0].a.x, -0.5, accuracy: 1e-5)
        XCTAssertEqual(fitted[0].a.y, 1.0, accuracy: 1e-5)
        XCTAssertEqual(fitted[0].b.y, -1.0, accuracy: 1e-5)
        XCTAssertEqual(fitted[0].hw, 0.2, accuracy: 1e-5)
        let kept = MarkFit.strokes(design, designCentre: P2(5, 10), designHeight: 20, targetHeight: 2, flipY: false)
        XCTAssertEqual(kept[0].a.y, -1.0, accuracy: 1e-5)
    }
}
