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

import Foundation
import simd

// Spin-blur profile of the Tri-wing. At speed a one-shutter exposure of the part is its angular average: at each radius, the
// fraction of the circle covered by the body, split by what covers it (satin body, ray pad, gold, blue jewel, ...), plus
// the fraction covered by the lit edge-light tubes with their colours. The renderer turns this profile into a smeared disc
// overlay (one texture per metal) that replaces the solid part as it spins up. The profile is sampled from the same
// layout the meshes are built from, so the smear stays true to the geometry.

public struct TriWingSmear {
    public static let classCount: Int = 10
    /// Class indices.
    public static let body = 0, pad = 1, gold = 2, jewel = 3, screw = 4, ring = 5, black = 6, steel = 7, dark = 8, boss = 9

    public let radii: Int
    /// Fraction of the circle covered at radius (i + 0.5) / radii.
    public var coverage: [Float]
    /// Per radius, the share of the circle covered by each class (sums to `coverage`).
    public var classes: [[Float]]
    /// Per radius, the share of the circle covered by lit tubes, and the sum of their colours over the circle.
    public var glow: [Float]
    public var glowColor: [SIMD3<Float>]
    /// Per radius, the share of the circle covered by lit tubes of wing 0, 1 and 2 (x, y, z); sums to `glow`.
    public var glowWing: [SIMD3<Float>] = []

    /// Star-shaped body radius at `angle` (radians), by ray casting against the outline.
    static func radiusTable(_ outline: [P2], count: Int) -> [Float] {
        var table = [Float](repeating: 0, count: count)
        let n: Int = outline.count
        var j: Int = 0
        while j < count {
            let a: Float = Float(j) / Float(count) * 2 * Float.pi
            let dx: Float = cos(a)
            let dy: Float = sin(a)
            var best: Float = 0
            var i: Int = 0
            while i < n {
                let p: P2 = outline[i]
                let q: P2 = outline[(i + 1) % n]
                let ex: Float = q.x - p.x
                let ey: Float = q.y - p.y
                let denom: Float = dx * ey - dy * ex
                if abs(denom) > 1e-12 {
                    let t: Float = (p.x * ey - p.y * ex) / denom
                    let s: Float = (p.x * dy - p.y * dx) / denom
                    if t > 0 && s >= 0 && s <= 1 && t > best { best = t }
                }
                i += 1
            }
            table[j] = best
            j += 1
        }
        return table
    }

    /// `face` is kept for the renderer's per-face call: the polished lettering and the slots are ring/body metal on both faces, so the profile is the same for each.
    public static func compute(radii: Int = 512, angles: Int = 360, face: TriWing.RingFace = .front) -> TriWingSmear {
        let outline: [P2] = TriWing.bodyOutline()
        let pad: [P2] = TriWing.padOutline()
        var padLo = P2(1e9, 1e9)
        var padHi = P2(-1e9, -1e9)
        for q in pad {
            padLo = P2(min(padLo.x, q.x), min(padLo.y, q.y))
            padHi = P2(max(padHi.x, q.x), max(padHi.y, q.y))
        }
        let tableCount: Int = 1440
        let radiusTab: [Float] = radiusTable(outline, count: tableCount)
        var result = TriWingSmear(radii: radii, coverage: [Float](repeating: 0, count: radii),
                                  classes: [[Float]](repeating: [Float](repeating: 0, count: classCount), count: radii),
                                  glow: [Float](repeating: 0, count: radii),
                                  glowColor: [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: radii),
                                  glowWing: [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: radii))
        let tubeColors: [SIMD3<Float>] = [SIMD3<Float>(0.25, 1.0, 0.45), SIMD3<Float>(0.30, 0.75, 1.0), SIMD3<Float>(1.0, 0.50, 0.12)]
        let weight: Float = 1 / Float(angles)
        struct Row { var coverage: Float = 0; var classes: [Float] = [Float](repeating: 0, count: TriWingSmear.classCount); var glow: Float = 0; var glowColor = SIMD3<Float>(0, 0, 0); var glowWing = SIMD3<Float>(0, 0, 0) }
        var rows = [Row](repeating: Row(), count: radii)
        let lock = NSLock()
        let padPoly: [P2] = pad
        let flankPaths: [[P2]] = [TriWing.flankTubePath(side: 1), TriWing.flankTubePath(side: -1)]
        // The three wings' tubes share one radial band. Spun into a blur their colours would average to white, so the
        // smeared ring splits the band into three concentric colour rings (outermost = wing 0's colour) instead.
        var bandLo: Float = 10
        var bandHi: Float = 0
        for path in flankPaths { for q in path { let rq: Float = (q.x * q.x + q.y * q.y).squareRoot(); bandLo = min(bandLo, rq); bandHi = max(bandHi, rq) } }
        let rowWork: (Int) -> Void = { (ri: Int) -> Void in
            var row = Row()
            let r: Float = (Float(ri) + 0.5) / Float(radii)
            var ai: Int = 0
            while ai < angles {
                let a: Float = (Float(ai) + 0.5) / Float(angles) * 2 * Float.pi
                let px: Float = r * cos(a)
                let py: Float = r * sin(a)
                // Wing frame: rotate so the nearest wing points up.
                let turnsFromUp: Float = (a - Float.pi / 2) / (2 * Float.pi / 3)
                let k: Int = ((Int(turnsFromUp.rounded()) % 3) + 3) % 3
                let c: Float = cos(-TriWing.wingAngle(k))
                let s: Float = sin(-TriWing.wingAngle(k))
                let wp = P2(c * px - s * py, s * px + c * py)
                var cls: Int = -1
                if r < TriWing.hubRadius {
                    cls = -1
                } else if r < TriWing.ringInner {
                    cls = classifyBearing(r: r, a: a)
                } else if r <= TriWing.ringOuter {
                    // Ring metal; the engraving and notch shares of this radius are moved out of it after the angle loop.
                    cls = TriWingSmear.ring
                } else {
                    let idx: Int = min(tableCount - 1, Int(a / (2 * Float.pi) * Float(tableCount)))
                    if r > radiusTab[idx] - TriWing.bodyChamfer * 0.5 {
                        cls = -1
                    } else {
                        cls = classifyWing(wp, k: k, padPoly: padPoly, padLo: padLo, padHi: padHi)
                        let lit: Bool = flankPaths.contains { (path: [P2]) -> Bool in
                            TriWingSmear.distanceToPolyline(path, wp) < TriWing.tubeShellRadius * 0.9
                        }
                        if lit {
                            row.glow += weight
                            let f: Float = min(max((r - bandLo) / max(bandHi - bandLo, 1e-6), 0), 0.999)
                            let ci: Int = 2 - Int(f * 3)
                            row.glowColor += tubeColors[ci] * weight
                            row.glowWing[ci] += weight
                        }
                    }
                }
                if cls >= 0 {
                    row.coverage += weight
                    row.classes[cls] += weight
                }
                ai += 1
            }
            if r >= TriWing.ringInner && r <= TriWing.ringOuter {
                TriWingSmear.applyRingShare(&row.classes, v: r - TriWing.ringInner)
            }
            lock.lock(); rows[ri] = row; lock.unlock()
        }
        DispatchQueue.concurrentPerform(iterations: radii, execute: rowWork)
        for i in 0..<radii {
            result.coverage[i] = rows[i].coverage
            result.classes[i] = rows[i].classes
            result.glow[i] = rows[i].glow
            result.glowColor[i] = rows[i].glowColor
            result.glowWing[i] = rows[i].glowWing
        }
        return result
    }

    // MARK: Ring engraving

    /// Share of the circle, at radial offset `v` from the ring's inner edge, covered by the spanner slots. The slots' milled
    /// floors are satin body metal. The letters' floors are polished ring metal and add nothing; neither do the flutes.
    /// Pure and independent of any sampling grid.
    public static func ringNotchShare(v: Float) -> Float {
        let r: Float = TriWing.ringInner + v
        if r >= TriWing.slotInnerRadius { return Float(TriWing.notchCount) * TriWing.slotWidth / TriWing.ringCircumference }
        return 0
    }

    /// Moves the slots' share of a ring row out of the ring-metal class into the satin body class.
    static func applyRingShare(_ classes: inout [Float], v: Float) {
        let metal: Float = classes[ring]
        let slot: Float = min(ringNotchShare(v: v), metal)
        classes[ring] = metal - slot
        classes[TriWingSmear.body] += slot
    }

    // MARK: Swept volume

    /// Half thickness of the opaque swept core (the body plate's half thickness).
    public var coreHalfHeight: Float { TriWing.halfThickness }

    /// One translucent shell of the swept volume outside the full-coverage core: a cylindrical wall at `radius` whose
    /// opacity follows the circle coverage there (never increasing outward) and whose half height follows the body, plus
    /// the pad where pads cover most of the circle at that radius.
    public struct SweptShell {
        public let radius: Float
        public let opacity: Float
        public let halfHeight: Float
    }

    /// Radius (lower edge of the bin) where body coverage first drops below `threshold`, searching outward from the
    /// ring's outer edge. Inside it the spinning body is a solid of revolution; outside it the wings smear.
    public func fullCoverageRadius(threshold: Float = 0.995) -> Float {
        var i: Int = Int(TriWing.ringOuter * Float(radii))
        while i < radii {
            if coverage[i] < threshold { return Float(i) / Float(radii) }
            i += 1
        }
        return 1
    }

    /// Outermost radius whose coverage is still at least `minCoverage` (the overlay drops anything fainter).
    public func tipRadius(minCoverage: Float = 0.04) -> Float {
        var i: Int = radii - 1
        while i > 0 {
            if coverage[i] >= minCoverage { return (Float(i) + 0.5) / Float(radii) }
            i -= 1
        }
        return fullCoverageRadius()
    }

    /// Largest accumulated opacity the shell stack may reach. Just under 1 so the first shells outside the core are not fully
    /// opaque sheets (the stack then reads as a slab that feathers out, not as a wall).
    public static let shellOpacityCap: Float = 0.99

    /// Support function of the body outline: for each of `edgeOnTurnSteps` directions round one turn, the farthest reach of the
    /// outline along that direction. A ray seen edge-on at lateral offset x is blocked by the body exactly while this reach
    /// is at least x (the body is one connected piece that contains the axis).
    static let edgeOnTurnSteps: Int = 720
    static let edgeOnReach: [Float] = {
        let outline: [P2] = TriWing.bodyOutline()
        var table: [Float] = []
        var k: Int = 0
        while k < edgeOnTurnSteps {
            let a: Float = Float(k) / Float(edgeOnTurnSteps) * 2 * Float.pi
            let ux: Float = cos(a)
            let uy: Float = sin(a)
            var best: Float = 0
            var i: Int = 0
            while i < outline.count {
                let d: Float = outline[i].x * ux + outline[i].y * uy
                if d > best { best = d }
                i += 1
            }
            table.append(best)
            k += 1
        }
        return table
    }()

    /// Share of one turn during which the spinning body blocks a ray seen edge-on at lateral offset `x` (in R) from the axis:
    /// the time-averaged opacity of the swept slab at that offset. 1 inside the body's inscribed reach, 0 beyond the tip.
    public static func edgeOnOcclusion(x: Float) -> Float {
        var count: Int = 0
        for h in edgeOnReach where h >= x { count += 1 }
        return Float(count) / Float(edgeOnTurnSteps)
    }

    /// `count` thin shells evenly spaced from just outside the core to the wing tip. A ray seen edge-on at offset x crosses
    /// every shell of radius above x (near side only), so the shell opacities are chosen from the outermost inward such that
    /// the accumulated opacity 1 - product(1 - a) over those shells equals the physical edge-on occlusion at the shell's
    /// inner edge (`edgeOnOcclusion`, capped at `shellOpacityCap`).
    public func sweptShells(count: Int) -> [SweptShell] {
        let rf: Float = fullCoverageRadius()
        let rt: Float = max(tipRadius(), rf + 0.01)
        let dr: Float = (rt - rf) / Float(count)
        var radiiOut: [Float] = []
        var accum: [Float] = []
        var j: Int = 0
        while j < count {
            let r: Float = rf + dr * (Float(j) + 0.5)
            radiiOut.append(r)
            let target: Float = min(TriWingSmear.edgeOnOcclusion(x: r - dr * 0.5), TriWingSmear.shellOpacityCap)
            // Never rises outward, so the shell opacities below are never negative.
            let outer: Float = accum.isEmpty ? target : min(target, accum[accum.count - 1])
            accum.append(outer)
            j += 1
        }
        var out: [SweptShell] = []
        j = 0
        while j < count {
            let own: Float = accum[j]
            let next: Float = j + 1 < count ? accum[j + 1] : 0
            let alpha: Float = 1 - (1 - own) / max(1 - next, 1e-6)
            out.append(SweptShell(radius: radiiOut[j], opacity: max(alpha, 1e-4), halfHeight: sweptHalfHeight(at: radiiOut[j])))
            j += 1
        }
        return out
    }

    /// Bearing ring: polished races and balls are steel, the cage bars steel too; the open gap between
    /// them is a through hole and covers nothing (-1), so the smear lets the background through there.
    static func classifyBearing(r: Float, a: Float) -> Int {
        if r >= TriWing.innerRaceInner && r <= TriWing.innerRaceOuter { return steel }
        if r >= TriWing.outerRaceInner && r <= TriWing.outerRaceOuter { return steel }
        if r > TriWing.innerRaceOuter && r < TriWing.outerRaceInner {
            let px: Float = r * cos(a)
            let py: Float = r * sin(a)
            var nearBall: Bool = false
            var inPocket: Bool = false
            var i: Int = 0
            while i < TriWing.ballCount {
                let ba: Float = Float.pi / 2 + Float(i) * 2 * Float.pi / Float(TriWing.ballCount)
                let bx: Float = TriWing.ballRingRadius * cos(ba)
                let by: Float = TriWing.ballRingRadius * sin(ba)
                let dx: Float = px - bx
                let dy: Float = py - by
                let d: Float = (dx * dx + dy * dy).squareRoot()
                if d < TriWing.ballRadius { nearBall = true }
                if d < TriWing.cagePocketRadius { inPocket = true }
                i += 1
            }
            if nearBall { return steel }
            if r >= TriWing.cageInner && r <= TriWing.cageOuter && !inPocket { return steel }
        }
        return -1
    }

    static func distanceToPolyline(_ path: [P2], _ p: P2) -> Float {
        var best: Float = 1e9
        var i: Int = 0
        while i + 1 < path.count {
            let a: P2 = path[i]
            let b: P2 = path[i + 1]
            let abx: Float = b.x - a.x
            let aby: Float = b.y - a.y
            let l2: Float = max(abx * abx + aby * aby, 1e-12)
            let t: Float = min(max(((p.x - a.x) * abx + (p.y - a.y) * aby) / l2, 0), 1)
            let dx: Float = p.x - (a.x + abx * t)
            let dy: Float = p.y - (a.y + aby * t)
            best = min(best, (dx * dx + dy * dy).squareRoot())
            i += 1
        }
        return best
    }

    static func classifyWing(_ p: P2, k: Int, padPoly: [P2], padLo: P2, padHi: P2) -> Int {
        let inBox: Bool = p.x >= padLo.x && p.x <= padHi.x && p.y >= padLo.y && p.y <= padHi.y
        if !inBox { return body }
        if !polygonContains(padPoly, p) { return body }
        if k == 0 {
            let d: P2 = p - TriWing.patchCentre
            if abs(d.x) < TriWing.patchSize.x * 0.5 && abs(d.y) < TriWing.patchSize.y * 0.5 { return gold }
        }
        let db: P2 = p - TriWing.bossCenter
        let boss: Float = (db.x * db.x + db.y * db.y).squareRoot()
        if boss < TriWing.capRadius { return jewel }
        if boss < TriWing.blockRadius { return gold }
        if boss < TriWing.countersinkTopRadius { return steel }
        if boss < TriWing.bossRadius { return TriWingSmear.boss }
        for sc in TriWing.screwCentres {
            let ds: P2 = p - sc
            let dist: Float = (ds.x * ds.x + ds.y * ds.y).squareRoot()
            if dist < TriWing.screwHeadRadius { return screw }
            if dist < TriWing.countersinkScrewRadius { return steel }
        }
        return pad
    }
}
