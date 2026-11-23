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
// Feature builders and the top-level CPU build of the Tri-wing (see RKTriWingGeometry.swift for the helpers).
import Foundation
import simd
import MacVisualizerCore

private let zeroP = P2(0, 0)

/// Rounded rectangle outline (counter-clockwise).
func twRoundedRect(centre: P2, size: P2, corner: Float, segments: Int) -> [P2] {
    var pts: [P2] = []
    let hx: Float = size.x * 0.5 - corner
    let hy: Float = size.y * 0.5 - corner
    let corners: [(P2, Float)] = [(P2(hx, -hy), -Float.pi / 2), (P2(hx, hy), 0), (P2(-hx, hy), Float.pi / 2), (P2(-hx, -hy), Float.pi)]
    for (c, start) in corners {
        var i: Int = 0
        while i <= segments {
            let t: Float = Float(i) / Float(segments)
            let a: Float = start + t * Float.pi / 2
            pts.append(P2(centre.x + c.x + corner * cos(a), centre.y + c.y + corner * sin(a)))
            i += 1
        }
    }
    return pts
}

// MARK: - Wing 0 features

/// Domed polished screw head: height of the crown over the dome's rim, the small chamfer round the rim, and the slot.
private let twScrewDome: Float = 0.0030
private let twScrewChamferWidth: Float = 0.0022
private let twScrewChamferDrop: Float = 0.0014
private let twScrewSlotBelowRim: Float = 0.0016

/// A slotted dome-head screw recessed in its own polished countersink, centred on `c` with the slot at `angle`. The head
/// is a spherical cap with a small chamfer; the slot is cut through it with a real floor and walls.
func twBuildScrew(_ acc: inout TWAccumulator, centre c: P2, angle: Float, zPad: Float) {
    let rt: Float = TriWing.countersinkScrewRadius
    let rf: Float = rt - 0.004
    let zFloor: Float = zPad - TriWing.screwCountersinkDepth
    let rh: Float = TriWing.screwHeadRadius
    let rr: Float = rh - twScrewChamferWidth
    let hw: Float = TriWing.screwSlotHalfWidth
    let zCrown: Float = zPad - TriWing.screwDrop
    let zd0: Float = zCrown - twScrewDome
    let zOuter: Float = zd0 - twScrewChamferDrop
    let zSlot: Float = zd0 - twScrewSlotBelowRim
    let rs: Float = (rr * rr + twScrewDome * twScrewDome) / (2 * twScrewDome)
    let zc: Float = zCrown - rs
    func domeZ(_ r: Float) -> Float {
        let under: Float = max(rs * rs - r * r, 0)
        return zc + under.squareRoot()
    }
    func rimZ(_ r: Float) -> Float {
        if r <= rr { return domeZ(r) }
        let t: Float = min((r - rr) / max(rh - rr, 1e-6), 1)
        return zd0 - twScrewChamferDrop * t
    }
    let place: simd_float4x4 = twTranslate(V3(c.x, c.y, 0))
    var local = TWAccumulator()
    local.add(twLathe([(rf, zFloor), (rt, zPad)], seg: 28), .countersink)
    local.add(twLathe([(0, zFloor), (rf, zFloor)], seg: 28), .countersinkFloor)
    // Dome patches either side of the slot: a grid of columns across x, rows from the slot edge out to the dome's rim.
    let xe: Float = max(rr * rr - hw * hw, 1e-8).squareRoot()
    let cols: Int = 22
    let rowsN: Int = 7
    var dome = MB()
    for side in [Float(1), Float(-1)] {
        var grid: [[UInt32]] = []
        var i: Int = 0
        while i <= cols {
            let x: Float = -xe + 2 * xe * Float(i) / Float(cols)
            let yMax: Float = max(max(rr * rr - x * x, 0).squareRoot(), hw)
            var column: [UInt32] = []
            var j: Int = 0
            while j <= rowsN {
                let y: Float = hw + (yMax - hw) * Float(j) / Float(rowsN)
                let r: Float = (x * x + y * y).squareRoot()
                let z: Float = domeZ(r)
                let nrm: V3 = simd_normalize(V3(x, y * side, z - zc))
                column.append(dome.v(V3(x, y * side, z), nrm, V2(0, 0), tan: V3(1, 0, 0)))
                j += 1
            }
            grid.append(column)
            i += 1
        }
        i = 0
        while i < cols {
            var j: Int = 0
            while j < rowsN { dome.quad(grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]); j += 1 }
            i += 1
        }
    }
    local.add(dome, .screwBlue)
    // Chamfer and side wall outside the slot (two arcs), and the slot's end walls below its floor.
    let a2: Float = asin(min(hw / rr, 0.99))
    let pi: Float = Float.pi
    let arcs: [(Float, Float)] = [(a2, pi - a2), (pi + a2, 2 * pi - a2)]
    for arc in arcs {
        local.add(twLatheArc([(rr, zd0), (rh, zOuter)], from: arc.0, to: arc.1, seg: 14), .screwBlue)
        local.add(twLatheArc([(rh, zOuter), (rh, zFloor)], from: arc.0, to: arc.1, seg: 14), .screwBlue)
    }
    local.add(twLatheArc([(rh, zSlot), (rh, zFloor)], from: -a2, to: a2, seg: 4), .screwSlot)
    local.add(twLatheArc([(rh, zSlot), (rh, zFloor)], from: pi - a2, to: pi + a2, seg: 4), .screwSlot)
    // Slot floor and walls (the walls follow the head's profile along x).
    let xs: Float = max(rh * rh - hw * hw, 1e-8).squareRoot()
    let slotRect: [P2] = [P2(-xs, -hw), P2(xs, -hw), P2(xs, hw), P2(-xs, hw)]
    local.add(twFlat(PolygonTriangulator.triangulate(outer: slotRect, holes: []), z: zSlot, textured: false), .screwSlot)
    var walls = MB()
    let samples: Int = 24
    for side in [Float(1), Float(-1)] {
        let nrm = V3(0, -side, 0)
        let tx = V3(1, 0, 0)
        var k: Int = 0
        while k < samples {
            let x0: Float = -xs + 2 * xs * Float(k) / Float(samples)
            let x1: Float = -xs + 2 * xs * Float(k + 1) / Float(samples)
            let r0: Float = (x0 * x0 + hw * hw).squareRoot()
            let r1: Float = (x1 * x1 + hw * hw).squareRoot()
            let t0: Float = rimZ(r0)
            let t1: Float = rimZ(r1)
            let a = walls.v(V3(x0, hw * side, t0), nrm, V2(0, 0), tan: tx)
            let b = walls.v(V3(x1, hw * side, t1), nrm, V2(1, 0), tan: tx)
            let cc = walls.v(V3(x1, hw * side, zSlot), nrm, V2(1, 1), tan: tx)
            let d = walls.v(V3(x0, hw * side, zSlot), nrm, V2(0, 1), tan: tx)
            walls.quad(a, b, cc, d)
            k += 1
        }
    }
    local.add(walls, .screwSlot)
    // Turn the slot into place (about the screw axis) then move it to the screw's position.
    let rot = twRotZ(angle)
    var rotated = TWAccumulator()
    rotated.merge(local, transform: rot.m, normalMatrix: rot.n)
    acc.merge(rotated, transform: place, normalMatrix: matrix_identity_float3x3)
}

/// Gold block outline: a circle whose radius steps in where a notch rectangle cuts the edge. Counter-clockwise, about the origin.
func twBlockOutline() -> [P2] {
    let r0: Float = TriWing.blockRadius
    let u: Float = TriWing.unit
    // Notch rectangles (design units, y down): two toward the tip, one at the hinge toward the centre.
    let rects: [(Float, Float, Float, Float)] = [(-7.8, -4.6, -10.2, -7.2), (4.6, 7.8, -10.2, -7.2), (-2.1, 2.1, 7.2, 10.2)]
    var out: [P2] = []
    let n: Int = 360
    var i: Int = 0
    while i < n {
        let a: Float = Float(i) / Float(n) * 2 * Float.pi
        let dx: Float = cos(a)
        let dy: Float = sin(a)
        var r: Float = r0
        for rc in rects {
            // Rectangle in R space (y up): x in [x0, x1] u, y in [-y1, -y0] u.
            let x0: Float = rc.0 * u
            let x1: Float = rc.1 * u
            let y0: Float = -rc.3 * u
            let y1: Float = -rc.2 * u
            // Ray-box entry distance.
            var tmin: Float = 0
            var tmax: Float = 100
            var hit: Bool = true
            let axes: [(Float, Float, Float)] = [(dx, x0, x1), (dy, y0, y1)]
            for (d, lo, hi) in axes {
                if abs(d) < 1e-9 {
                    if 0 < lo || 0 > hi { hit = false }
                } else {
                    let ta: Float = lo / d
                    let tb: Float = hi / d
                    tmin = max(tmin, min(ta, tb))
                    tmax = min(tmax, max(ta, tb))
                }
            }
            if hit && tmin < tmax && tmin < r { r = tmin }
        }
        out.append(P2(r * dx, r * dy))
        i += 1
    }
    return out
}

/// The cap jewel: a polished spherical-cap cabochon (uv.y = radial fraction, for the painted depth texture), a straight
/// girdle down into the seat, and a thin polished gold bezel round its base.
func twBuildJewel(_ acc: inout TWAccumulator, blockTop: Float, seatFloor: Float) {
    let a: Float = TriWing.capRadius
    let zr: Float = blockTop + TriWing.jewelRimRise
    let h: Float = TriWing.jewelDomeHeight
    let rs: Float = TriWing.jewelSphereRadius
    let zc: Float = zr + h - rs
    var prof: [ProfilePt] = []
    let steps: Int = 28
    var i: Int = 0
    while i <= steps {
        let t: Float = Float(i) / Float(steps)
        let r: Float = a * t
        let z: Float = zr + TriWing.jewelDomeRise(at: r)
        prof.append(ProfilePt(r: r, z: z, nr: r / rs, nz: (z - zc) / rs, v: t))
        i += 1
    }
    prof.append(ProfilePt(r: a, z: zr, nr: 1, nz: 0, v: 1))
    prof.append(ProfilePt(r: a, z: seatFloor, nr: 1, nz: 0, v: 1))
    acc.add(lathe(prof, seg: 72), .jewelBlue)
    // Bezel: an inner lip standing a little above the stone's rim, a flat top, and a bevel down to the block.
    let lip: Float = zr + TriWing.jewelBezelLip
    let w: Float = TriWing.jewelBezelWidth
    let flat: Float = 0.0012
    let bezel: [(Float, Float)] = [(a, zr), (a, lip), (a, lip), (a + flat, lip), (a + flat, lip), (a + w, blockTop)]
    acc.add(twLathe(bezel, seg: 72), .spring)
}

/// Height of the spring's centre line above the block top at `p` (boss-local): over whatever it lies on, plus half its thickness.
private func twSpringHeight(_ p: P2, halfThick: Float) -> Float {
    let r: Float = simd_length(p)
    return TriWing.jewelSurfaceRise(at: r) + halfThick + 0.00025
}

/// Sideways slope of the surface under the spring at sample `i` (rise per unit across the strip).
private func twSpringLateralSlope(_ path: [P2], _ i: Int, halfThick: Float) -> Float {
    let a: P2 = path[max(i - 1, 0)]
    let b: P2 = path[min(i + 1, path.count - 1)]
    let d: P2 = b - a
    let l: Float = max(simd_length(d), 1e-9)
    let nrm = P2(-d.y / l, d.x / l)
    let e: Float = 0.0006
    let hp: Float = twSpringHeight(path[i] + nrm * e, halfThick: halfThick)
    let hm: Float = twSpringHeight(path[i] - nrm * e, halfThick: halfThick)
    return (hp - hm) / (2 * e)
}

/// The spring clip: a flat, even-width, mirror-symmetric strip. Its arms bear on the stone's shoulder (they follow the
/// dome and its bezel, rolled to lie on them), leave the crown free, and end in hooked feet that step down into the
/// tip-side notches; a stem runs from the fork to a hinge end seated in the centre-side notch.
func twBuildSpring(_ acc: inout TWAccumulator, blockTop: Float, zFloor: Float) {
    let halfThick: Float = 0.0016
    let bevel: Float = 0.0007
    let halfWidth: Float = TriWing.springHalfWidth
    let notchZ: Float = zFloor + halfThick + 0.0004
    let ramp: Float = 2.2 * TriWing.unit
    func build(_ pts: [P2], lift: Float) -> MB {
        var total: Float = 0
        var arc: [Float] = [0]
        var i: Int = 1
        while i < pts.count { total += simd_length(pts[i] - pts[i - 1]); arc.append(total); i += 1 }
        var path: [V3] = []
        var slopes: [Float] = []
        i = 0
        while i < pts.count {
            let flat: Float = blockTop + twSpringHeight(pts[i], halfThick: halfThick) + lift
            let toEnd: Float = min(arc[i], total - arc[i])
            let drop: Float = 1 - ssf(0, ramp, toEnd)
            let z: Float = flat + (notchZ - flat) * drop
            path.append(V3(pts[i].x, pts[i].y, z))
            slopes.append(twSpringLateralSlope(pts, i, halfThick: halfThick) * (1 - drop))
            i += 1
        }
        return twBevelStrip(path, lateralSlope: slopes, halfWidth: halfWidth, halfThick: halfThick, bevel: bevel)
    }
    acc.add(build(TriWing.springArc(), lift: 0), .spring)
    acc.add(build(TriWing.springStem(), lift: -0.0002), .spring)
}

/// The round boss with its shock-spring jewel setting, centred on the origin at the pad height.
func twBuildBoss(_ acc: inout TWAccumulator, zPad: Float) {
    let zT: Float = zPad + TriWing.bossHeight
    let c: Float = TriWing.bossChamfer
    let br: Float = TriWing.bossRadius
    let r1: Float = TriWing.countersinkTopRadius
    let r2: Float = TriWing.countersinkFloorRadius
    let depth: Float = TriWing.countersinkDepth
    let zFloor: Float = zT - depth
    var local = TWAccumulator()
    local.add(twLathe([(r1, zT), (br - c, zT)], seg: 96), .bossTop)
    local.add(twLathe([(br - c, zT), (br, zT - c)], seg: 96), .bossChamfer)
    local.add(twLathe([(br, zT - c), (br, zPad)], seg: 96), .bossWall)
    local.add(twLathe([(r2, zFloor), (r2, zT - depth * 0.5), (r2, zT - depth * 0.5), (r1, zT)], seg: 96), .countersink)
    let blockTop: Float = zT - TriWing.blockDrop
    let blockR: Float = TriWing.blockRadius
    local.add(twLathe([(blockR - 0.0004, zFloor), (r2, zFloor)], seg: 96), .countersinkFloor)
    // Gold block: notched outline with the seat hole, then its walls.
    let outline: [P2] = twBlockOutline()
    let seat: [P2] = circlePolygon(center: zeroP, radius: TriWing.seatRadius, segments: 64)
    let blockTri = PolygonTriangulator.triangulate(outer: outline, holes: [seat])
    local.add(twFlat(blockTri, z: blockTop, textured: false), .gold)
    local.add(twWall(outline, zTop: blockTop, zBottom: zFloor, inward: false), .goldWall)
    let seatFloor: Float = blockTop - TriWing.seatDepth
    local.add(twLathe([(TriWing.seatRadius, seatFloor), (TriWing.seatRadius, blockTop)], seg: 64), .goldWall)
    local.add(twLathe([(0, seatFloor), (TriWing.seatRadius, seatFloor)], seg: 64), .goldDark)
    twBuildJewel(&local, blockTop: blockTop, seatFloor: seatFloor)
    twBuildSpring(&local, blockTop: blockTop, zFloor: zFloor)
    acc.merge(local, transform: matrix_identity_float4x4, normalMatrix: matrix_identity_float3x3)
}


// MARK: - Engraved ring

/// Column coordinates of one fluted zone: a margin of ordinary cells either side, and between `u0` and `u1` a column at
/// every ridge and every valley (half a pitch apart), so the groove profile is exact at the grid vertices.
func twFluteColumns(_ z: TriWing.FluteZone, cell: Float) -> [Float] {
    var xs: [Float] = CutGrid.uniform(z.u0 - 2 * cell, z.u0, step: cell)
    var k: Int = 1
    let half: Float = z.pitch * 0.5
    while k <= 2 * z.count {
        xs.append(z.u0 + Float(k) * half)
        k += 1
    }
    let tail: [Float] = CutGrid.uniform(z.u1, z.u1 + 2 * cell, step: cell)
    xs.append(contentsOf: tail.dropFirst())
    return xs
}

/// Depth of the V groove profile below the ridge line at strip position `u` (0 on a ridge, `depth` in a valley).
func twFluteProfile(_ z: TriWing.FluteZone, _ u: Float) -> Float {
    let phase: Float = (u - z.u0) / z.pitch
    let frac: Float = phase - phase.rounded(.down)
    let tri: Float = 1 - abs(2 * frac - 1)
    return z.depth * tri
}

/// Signed distance (negative inside) to an axis-aligned box in the strip plane.
@inline(__always)
func twBoxDistance(du: Float, dv: Float, halfU: Float, halfV: Float) -> Float {
    let ex: Float = abs(du) - halfU
    let ey: Float = abs(dv) - halfV
    let ox: Float = max(ex, 0)
    let oy: Float = max(ey, 0)
    let outside: Float = (ox * ox + oy * oy).squareRoot()
    let inside: Float = min(max(ex, ey), 0)
    return outside + inside
}

/// The raised bright ring of one face (front layout) with its engraved lettering (polished floors), the two spanner slots,
/// and (front face only) the fluted zones either side of the number panel on the lower arc. Stats: triangles.
func twBuildRing(_ acc: inout TWAccumulator, face: TriWing.RingFace) -> Int {
    let hB: Float = TriWing.halfThickness
    let zTop: Float = hB + TriWing.ringHeight
    let rIn: Float = TriWing.ringInner
    let rOut: Float = TriWing.ringOuter
    let ch: Float = 0.0045
    let width: Float = rOut - rIn
    let rMid: Float = TriWing.ringMidRadius
    let circumference: Float = TriWing.ringCircumference
    let layout: RingTextLayout = RingTextLayout.layoutFace(face)
    // Edges: chamfers and walls (lathes).
    acc.add(twLathe([(rIn, hB), (rIn, zTop - ch), (rIn, zTop - ch), (rIn + ch, zTop)], seg: 192), .ringChamfer)
    // Outer chamfer and wall: arcs between the slots only. The slot's top edge is chamfered, so the arcs stop at the
    // chamfer's outer edge (`halfAngleTop`); the slot itself (shoulders, floor, pocket) is built by `twBuildNotchPocket`.
    let notchChamfer: Float = TriWing.notchChamfer
    let halfAngleTop: Float = (TriWing.slotWidth * 0.5 + notchChamfer) / rMid
    let halfAngleTrue: Float = TriWing.slotWidth * 0.5 / rMid
    var sortedAngles: [Float] = TriWing.notchAngles.map { (a: Float) -> Float in
        var t: Float = a
        while t < 0 { t += 2 * Float.pi }
        while t >= 2 * Float.pi { t -= 2 * Float.pi }
        return t
    }
    sortedAngles.sort()
    let edgePts: [(Float, Float)] = [(rOut - ch, zTop), (rOut, zTop - ch), (rOut, zTop - ch), (rOut, hB)]
    var gi: Int = 0
    while gi < sortedAngles.count {
        let from: Float = sortedAngles[gi] + halfAngleTop
        var to: Float = (gi + 1 < sortedAngles.count ? sortedAngles[gi + 1] : sortedAngles[0] + 2 * Float.pi) - halfAngleTop
        if to < from { to = from }
        let spanTurns: Float = (to - from) / (2 * Float.pi)
        let arcSeg: Int = max(8, Int((spanTurns * 192).rounded(.up)))
        acc.add(twLatheArc(edgePts, from: from, to: to, seg: arcSeg), .ringChamfer)
        gi += 1
    }
    for a in sortedAngles {
        twBuildNotchPocket(&acc, angle: a, halfAngleTop: halfAngleTop, halfAngleTrue: halfAngleTrue)
    }
    // Engraving grid in (u, v): u along the strip, v from the inner edge.
    let notchU: [Float] = TriWing.notchAngles.map { (a: Float) -> Float in TriWing.ringU(angle: a) }
    let slotV0: Float = TriWing.slotInnerRadius - rIn
    // The cut box runs past the grid's outer row, so the slot is open at its outer end.
    let slotV1: Float = TriWing.slotOuterRadius - rIn + 0.05
    let slotHalfU: Float = TriWing.slotWidth * 0.5
    let cell: Float = 0.0026
    // The letters' thinnest strokes are about 1.6 cells wide at `cell`, so the lettering gets finer columns and rows.
    let letterCell: Float = 0.0017
    let margin: Float = 2 * letterCell
    let featureHalf: Float = TriWing.notchFeatureHalfSpan + 2 * cell
    let zones: [TriWing.FluteZone] = (face == .front) ? TriWing.fluteZones() : []
    var fine: [(Float, Float)] = []
    for it in layout.items { fine.append((max(0, it.u - margin), min(circumference, it.u + it.width + margin))) }
    fine.sort { (a: (Float, Float), b: (Float, Float)) -> Bool in a.0 < b.0 }
    var merged: [(Float, Float)] = []
    for iv in fine {
        if let last = merged.last, iv.0 <= last.1 + 1e-6 {
            merged[merged.count - 1] = (last.0, max(last.1, iv.1))
        } else {
            merged.append(iv)
        }
    }
    var segments: [(lo: Float, hi: Float, xs: [Float])] = []
    for iv in merged { segments.append((lo: iv.0, hi: iv.1, xs: CutGrid.uniform(iv.0, iv.1, step: letterCell))) }
    for u in notchU {
        let lo: Float = max(0, u - featureHalf)
        let hi: Float = min(circumference, u + featureHalf)
        segments.append((lo: lo, hi: hi, xs: CutGrid.uniform(lo, hi, step: cell)))
    }
    for z in zones {
        let zx: [Float] = twFluteColumns(z, cell: cell)
        segments.append((lo: zx[0], hi: zx[zx.count - 1], xs: zx))
    }
    segments.sort { (a: (lo: Float, hi: Float, xs: [Float]), b: (lo: Float, hi: Float, xs: [Float])) -> Bool in a.lo < b.lo }
    var active: [Bool] = []
    var cursor: Float = 0
    var xsBuilt: [Float] = [0]
    // Plain stretches between the cut regions are split into columns of at most `maxPlainStep`: a cell is flat, so a long one
    // would cut a chord across the ring's curve and leave a gap at its edges.
    let maxPlainStep: Float = circumference / 144
    func appendPlain(to end: Float) {
        let n: Int = max(1, Int(((end - cursor) / maxPlainStep).rounded(.up)))
        let start: Float = cursor
        var i: Int = 1
        while i <= n {
            xsBuilt.append(start + (end - start) * Float(i) / Float(n))
            active.append(false)
            i += 1
        }
    }
    for seg in segments {
        if seg.lo > cursor + 1e-6 { appendPlain(to: seg.lo) }
        for v in seg.xs {
            if let last = xsBuilt.last, v > last + 1e-6 { xsBuilt.append(v); active.append(true) }
        }
        cursor = max(cursor, seg.hi)
    }
    if cursor < circumference - 1e-6 { appendPlain(to: circumference) }
    let xs: [Float] = xsBuilt
    // Rows: coarse edge band, fine band over the lettering, a medium band up to the outer edge (it carries the slots).
    let fineLo: Float = layout.baselineV - 2 * letterCell
    let fineHi: Float = layout.baselineV + layout.capHeight + 2 * letterCell
    let ys: [Float] = CutGrid.join([
        [ch], CutGrid.uniform(max(ch + 0.004, fineLo - 0.004), fineLo, step: 0.004), CutGrid.uniform(fineLo, fineHi, step: letterCell),
        CutGrid.uniform(fineHi, width - ch, step: cell)])
    // Signed distances: the lettering, the slot outlines (grown by the chamfer: the top edge) and the fluted zones' boxes.
    let lettersD: (Float, Float) -> Float = { (u: Float, v: Float) -> Float in layout.distance(u: u, v: v) }
    let slotD: (Float, Float) -> Float = { (u: Float, v: Float) -> Float in
        var best: Float = 1
        let cy: Float = (slotV0 + slotV1) * 0.5
        let hy: Float = (slotV1 - slotV0) * 0.5
        for nu in notchU {
            var du: Float = abs(u - nu)
            if du > circumference * 0.5 { du = circumference - du }
            let d: Float = twBoxDistance(du: du, dv: v - cy, halfU: slotHalfU, halfV: hy) - notchChamfer
            if d < best { best = d }
        }
        return best
    }
    // Each zone box is grown by a hair so the vertices on its end columns (ridges) are inside, never on the outline.
    let zoneGrow: Float = 1e-4
    let zoneC: [Float] = zones.map { (z: TriWing.FluteZone) -> Float in (z.u0 + z.u1) * 0.5 }
    let zoneHalfU: [Float] = zones.map { (z: TriWing.FluteZone) -> Float in (z.u1 - z.u0) * 0.5 }
    let zoneCV: [Float] = zones.map { (z: TriWing.FluteZone) -> Float in (z.v0 + z.v1) * 0.5 }
    let zoneHalfV: [Float] = zones.map { (z: TriWing.FluteZone) -> Float in (z.v1 - z.v0) * 0.5 }
    let hasZone: Bool = !zones.isEmpty
    let zoneD: (Float, Float) -> Float = { (u: Float, v: Float) -> Float in
        var best: Float = 1
        var k: Int = 0
        while k < zoneC.count {
            let d: Float = twBoxDistance(du: u - zoneC[k], dv: v - zoneCV[k], halfU: zoneHalfU[k], halfV: zoneHalfV[k]) - zoneGrow
            if d < best { best = d }
            k += 1
        }
        return best
    }
    /// The zone whose columns contain `u` (nil between them).
    let zoneAt: (Float) -> TriWing.FluteZone? = { (u: Float) -> TriWing.FluteZone? in
        for z in zones where u >= z.u0 - 1e-3 && u <= z.u1 + 1e-3 { return z }
        return nil
    }
    let sdf: (Float, Float) -> Float = { (u: Float, v: Float) -> Float in
        min(min(lettersD(u, v), slotD(u, v)), zoneD(u, v))
    }
    let grid = RectCutMesher.mesh(xs: xs, ys: ys, activeColumns: active, sdf: sdf)
    // Map (u, v, level) to the ring.
    let cutDepth: Float = TriWing.ringCutDepth
    var top = MB()
    var floorMB = MB()
    var wallMB = MB()
    func mapPoint(_ uv: P2) -> (pos: P2, radial: P2, tangent: P2, radius: Float) {
        let theta: Float = TriWing.ringAngle(u: uv.x)
        let r: Float = rIn + uv.y
        let radial = P2(cos(theta), sin(theta))
        let tangent = P2(sin(theta), -cos(theta))
        return (P2(r * radial.x, r * radial.y), radial, tangent, r)
    }
    var topIdx: [UInt32] = []
    var floorIdx: [UInt32] = []
    var wallIdx: [UInt32] = []
    // Slot pieces: the chamfer on the top edge (45 degrees, from the grown outline at the ring top to the true outline one
    // chamfer lower) and the vertical wall below it, down to the pocket floor in the body.
    let pocketFloorZ: Float = hB - TriWing.notchPocketDepth
    var chamferMB = MB()
    var vwallMB = MB()
    var chamferIdx: [UInt32] = []
    var vwallIdx: [UInt32] = []
    var notchWall: [Bool] = []
    var slotInside: [Bool] = []
    // Fluted zones: their border wall (ring metal) and their floor, which is the groove profile.
    var zoneWallMB = MB()
    var zoneWallIdx: [UInt32] = []
    var zoneWall: [Bool] = []
    var zoneInside: [Bool] = []
    var zonePos: [V3] = []
    var zoneTan: [V3] = []
    let ridgeZ: Float = zTop - TriWing.fluteRidgeDrop
    let notchEps: Float = 1e-3
    let slope: Float = 0.70710678
    for v in grid.vertices {
        let mp = mapPoint(v.uv)
        let hasGradient: Bool = (v.gradient.x != 0 || v.gradient.y != 0)
        let dSlot: Float = slotD(v.uv.x, v.uv.y)
        let dZone: Float = zoneD(v.uv.x, v.uv.y)
        let isNotchWall: Bool = hasGradient && abs(dSlot) < notchEps
        let isZoneWall: Bool = hasGradient && abs(dZone) < notchEps
        notchWall.append(isNotchWall)
        zoneWall.append(isZoneWall)
        slotInside.append(!hasGradient && v.onFloor && dSlot <= notchEps)
        let inZoneFloor: Bool = hasZone && !hasGradient && v.onFloor && dZone <= notchEps
        zoneInside.append(inZoneFloor)
        let z: Float = v.onFloor ? (zTop - cutDepth) : zTop
        // Outward-from-cut wall normal (into the cut), mapped through the inverse transpose of the strip map.
        let gu: Float = v.gradient.x * rMid / mp.radius
        let gv: Float = v.gradient.y
        let nx: Float = -(gu * mp.tangent.x + gv * mp.radial.x)
        let ny: Float = -(gu * mp.tangent.y + gv * mp.radial.y)
        let len: Float = max((nx * nx + ny * ny).squareRoot(), 1e-9)
        let nh = V3(nx / len, ny / len, 0)
        var zp = V3(0, 0, 0)
        var zt = V3(1, 0, 0)
        if inZoneFloor, let zone = zoneAt(v.uv.x) {
            zp = V3(mp.pos.x, mp.pos.y, ridgeZ - twFluteProfile(zone, v.uv.x))
            zt = V3(mp.tangent.x, mp.tangent.y, 0)
        }
        zonePos.append(zp)
        zoneTan.append(zt)
        if isNotchWall {
            // Gradient points out of the cut (into ring metal); the true outline is one chamfer further into the cut.
            let moved = P2(v.uv.x - v.gradient.x * notchChamfer, v.uv.y - v.gradient.y * notchChamfer)
            let mq = mapPoint(moved)
            let nc = V3(nh.x * slope, nh.y * slope, slope)
            let tanW = V3(0, 0, 1)
            if v.onFloor {
                chamferIdx.append(chamferMB.v(V3(mq.pos.x, mq.pos.y, zTop - notchChamfer), nc, V2(0, 0), tan: tanW))
                vwallIdx.append(vwallMB.v(V3(mq.pos.x, mq.pos.y, pocketFloorZ), nh, V2(0, 0), tan: tanW))
            } else {
                chamferIdx.append(chamferMB.v(V3(mp.pos.x, mp.pos.y, zTop), nc, V2(0, 0), tan: tanW))
                vwallIdx.append(vwallMB.v(V3(mq.pos.x, mq.pos.y, zTop - notchChamfer), nh, V2(0, 0), tan: tanW))
            }
            topIdx.append(0); floorIdx.append(0); wallIdx.append(0); zoneWallIdx.append(0)
            continue
        }
        chamferIdx.append(0); vwallIdx.append(0)
        if isZoneWall, let zone = zoneAt(v.uv.x) {
            // The zone's border: a metal wall from the ring top down to the groove profile at this position.
            let zf: Float = v.onFloor ? (ridgeZ - twFluteProfile(zone, v.uv.x)) : zTop
            zoneWallIdx.append(zoneWallMB.v(V3(mp.pos.x, mp.pos.y, zf), nh, V2(0, 0), tan: V3(0, 0, 1)))
            topIdx.append(0); floorIdx.append(0); wallIdx.append(0)
            continue
        }
        zoneWallIdx.append(0)
        if hasGradient {
            wallIdx.append(wallMB.v(V3(mp.pos.x, mp.pos.y, z), nh, V2(0, 0), tan: V3(0, 0, 1)))
            topIdx.append(0); floorIdx.append(0)
        } else {
            let nrm = twUp
            let tan = V3(mp.tangent.x, mp.tangent.y, 0)
            if v.onFloor {
                let skip: Bool = slotInside[slotInside.count - 1] || inZoneFloor
                if skip {
                    floorIdx.append(0)
                } else {
                    floorIdx.append(floorMB.v(V3(mp.pos.x, mp.pos.y, z), nrm, V2(0, 0), tan: tan))
                }
                topIdx.append(0); wallIdx.append(0)
            } else {
                topIdx.append(top.v(V3(mp.pos.x, mp.pos.y, z), nrm, V2(0, 0), tan: tan))
                floorIdx.append(0); wallIdx.append(0)
            }
        }
    }
    // Vertices were appended to the mesh that owns them; triangles refer to the shared grid index, so remap per list.
    func remap(_ list: [UInt32], _ table: [UInt32], into m: inout MB) {
        var k: Int = 0
        while k + 2 < list.count {
            let a: UInt32 = table[Int(list[k])]
            let b: UInt32 = table[Int(list[k + 1])]
            let c: UInt32 = table[Int(list[k + 2])]
            m.tri(a, b, c)
            k += 3
        }
    }
    // The face list may reference wall-top vertices only through wall quads, so build lookup tables per mesh.
    var topTable: [UInt32] = [UInt32](repeating: 0, count: grid.vertices.count)
    var floorTable: [UInt32] = topTable
    var wallTable: [UInt32] = topTable
    for (i, v) in grid.vertices.enumerated() {
        let hasGradient: Bool = (v.gradient.x != 0 || v.gradient.y != 0)
        if hasGradient { wallTable[i] = wallIdx[i] } else if v.onFloor { floorTable[i] = floorIdx[i] } else { topTable[i] = topIdx[i] }
    }
    remap(grid.face, topTable, into: &top)
    // Floor triangles: those wholly inside a slot are dropped (the slot's floor is the pocket in the body), those inside a
    // fluted zone become flat-shaded groove facets, the rest are the letters' floors.
    var keptFloor: [UInt32] = []
    var fluteMB = MB()
    var fk: Int = 0
    while fk + 2 < grid.floor.count {
        let ia: Int = Int(grid.floor[fk])
        let ib: Int = Int(grid.floor[fk + 1])
        let ic: Int = Int(grid.floor[fk + 2])
        if slotInside[ia] && slotInside[ib] && slotInside[ic] {
            // dropped
        } else if zoneInside[ia] && zoneInside[ib] && zoneInside[ic] {
            let pa: V3 = zonePos[ia]
            let pb: V3 = zonePos[ib]
            let pc: V3 = zonePos[ic]
            var n: V3 = simd_cross(pb - pa, pc - pa)
            if simd_length_squared(n) > 1e-18 {
                n = simd_normalize(n)
                if n.z < 0 { n = -n }
                let ta: V3 = zoneTan[ia]
                let va: UInt32 = fluteMB.v(pa, n, V2(0, 0), tan: ta)
                let vb: UInt32 = fluteMB.v(pb, n, V2(0, 0), tan: ta)
                let vc: UInt32 = fluteMB.v(pc, n, V2(0, 0), tan: ta)
                fluteMB.tri(va, vb, vc)
            }
        } else {
            keptFloor.append(contentsOf: [grid.floor[fk], grid.floor[fk + 1], grid.floor[fk + 2]])
        }
        fk += 3
    }
    remap(keptFloor, floorTable, into: &floorMB)
    // Wall triangles: slot walls go to the chamfer and the vertical wall, the zones' border to its metal wall, the rest
    // (the letters' walls) to the polished letter wall.
    var plainWall: [UInt32] = []
    var zoneWallTris: [UInt32] = []
    var wk: Int = 0
    while wk + 2 < grid.wall.count {
        let ia: Int = Int(grid.wall[wk])
        if notchWall[ia] {
            chamferMB.tri(chamferIdx[ia], chamferIdx[Int(grid.wall[wk + 1])], chamferIdx[Int(grid.wall[wk + 2])])
            vwallMB.tri(vwallIdx[ia], vwallIdx[Int(grid.wall[wk + 1])], vwallIdx[Int(grid.wall[wk + 2])])
        } else if zoneWall[ia] {
            zoneWallTris.append(contentsOf: [grid.wall[wk], grid.wall[wk + 1], grid.wall[wk + 2]])
        } else {
            plainWall.append(contentsOf: [grid.wall[wk], grid.wall[wk + 1], grid.wall[wk + 2]])
        }
        wk += 3
    }
    remap(plainWall, wallTable, into: &wallMB)
    remap(zoneWallTris, zoneWallIdx, into: &zoneWallMB)
    acc.add(top, .ringTop)
    acc.add(floorMB, .letterFloor)
    acc.add(wallMB, .letterWall)
    acc.add(chamferMB, .notchChamfer)
    acc.add(vwallMB, .notchWall)
    acc.add(zoneWallMB, .ringWall)
    acc.add(fluteMB, .flute)
    return top.triCount + floorMB.triCount + wallMB.triCount + chamferMB.triCount + vwallMB.triCount + zoneWallMB.triCount
        + fluteMB.triCount
}

/// One spanner slot beyond the grid: the chamfer and wall over the ring's outer chamfer zone, the wall on the body out to
/// the pocket's outer arc (which stands past the ring's outer wall), the sliver of ring wall between the grown and the true
/// outline, the pocket's outer arc wall and its floor. The grid part (ring top, chamfer and wall inside `rOut - ch`) is
/// built in `twBuildRing`. Front layout; the loop of the pocket is `TriWing.notchPocketLoop`, which the body plate also
/// uses for its hole.
func twBuildNotchPocket(_ acc: inout TWAccumulator, angle a: Float, halfAngleTop: Float, halfAngleTrue: Float) {
    let hB: Float = TriWing.halfThickness
    let zTop: Float = hB + TriWing.ringHeight
    let ch: Float = 0.0045
    let c: Float = TriWing.notchChamfer
    let rOut: Float = TriWing.ringOuter
    let rC: Float = rOut - ch
    let rPo: Float = TriWing.notchPocketOuterRadius
    let floorZ: Float = hB - TriWing.notchPocketDepth
    let slope: Float = 0.70710678
    let tanW = V3(0, 0, 1)
    func pt(_ r: Float, _ th: Float, _ z: Float) -> V3 { V3(r * cos(th), r * sin(th), z) }
    var chamfer = MB()
    var wall = MB()
    var sliver = MB()
    for side in [-1, 1] as [Float] {
        let thTop: Float = a + side * halfAngleTop
        let thTrue: Float = a + side * halfAngleTrue
        let nh = V3(side * sin(thTrue), -side * cos(thTrue), 0)
        let nc = V3(nh.x * slope, nh.y * slope, slope)
        // Chamfer across the ring's outer chamfer zone.
        let c0 = chamfer.v(pt(rC, thTop, zTop), nc, V2(0, 0), tan: tanW)
        let c1 = chamfer.v(pt(rOut, thTop, zTop - ch), nc, V2(0, 0), tan: tanW)
        let c2 = chamfer.v(pt(rOut, thTrue, zTop - ch - c), nc, V2(0, 0), tan: tanW)
        let c3 = chamfer.v(pt(rC, thTrue, zTop - c), nc, V2(0, 0), tan: tanW)
        chamfer.quad(c0, c1, c2, c3)
        // Wall below it, down to the floor, then the wall on the body out to the pocket's outer arc.
        let w0 = wall.v(pt(rC, thTrue, floorZ), nh, V2(0, 0), tan: tanW)
        let w1 = wall.v(pt(rC, thTrue, zTop - c), nh, V2(0, 0), tan: tanW)
        let w2 = wall.v(pt(rOut, thTrue, zTop - ch - c), nh, V2(0, 0), tan: tanW)
        let w3 = wall.v(pt(rOut, thTrue, floorZ), nh, V2(0, 0), tan: tanW)
        wall.quad(w0, w1, w2, w3)
        let b0 = wall.v(pt(rOut, thTrue, floorZ), nh, V2(0, 0), tan: tanW)
        let b1 = wall.v(pt(rOut, thTrue, hB), nh, V2(0, 0), tan: tanW)
        let b2 = wall.v(pt(rPo, thTrue, hB), nh, V2(0, 0), tan: tanW)
        let b3 = wall.v(pt(rPo, thTrue, floorZ), nh, V2(0, 0), tan: tanW)
        wall.quad(b0, b1, b2, b3)
        // The ring's outer wall between the grown and the true outline (under the chamfer's slope).
        let nr = V3(cos(thTrue), sin(thTrue), 0)
        let tg = V3(-sin(thTrue), cos(thTrue), 0)
        let s0 = sliver.v(pt(rOut, thTop, hB), nr, V2(0, 0), tan: tg)
        let s1 = sliver.v(pt(rOut, thTop, zTop - ch), nr, V2(0, 0), tan: tg)
        let s2 = sliver.v(pt(rOut, thTrue, zTop - ch - c), nr, V2(0, 0), tan: tg)
        let s3 = sliver.v(pt(rOut, thTrue, hB), nr, V2(0, 0), tan: tg)
        sliver.quad(s0, s1, s2, s3)
    }
    // Outer arc wall of the pocket (faces the pocket's centre).
    let arcSeg: Int = 8
    var top: [UInt32] = []
    var bot: [UInt32] = []
    var i: Int = 0
    while i <= arcSeg {
        let t: Float = Float(i) / Float(arcSeg)
        let th: Float = a - halfAngleTrue + 2 * halfAngleTrue * t
        let n = V3(-cos(th), -sin(th), 0)
        let tg = V3(-sin(th), cos(th), 0)
        top.append(wall.v(pt(rPo, th, hB), n, V2(0, 0), tan: tg))
        bot.append(wall.v(pt(rPo, th, floorZ), n, V2(0, 0), tan: tg))
        i += 1
    }
    i = 0
    while i < arcSeg {
        wall.quad(top[i], top[i + 1], bot[i + 1], bot[i])
        i += 1
    }
    // Floor: the pocket's outline at the floor height.
    let loop: [P2] = TriWing.notchPocketLoop(angle: a, arcSegments: 32)
    let inner: [P2] = TriWing.notchPocketLoop(angle: a, arcSegments: 32, inset: TriWing.notchFloorShadeWidth)
    // Both are built as quad strips straight from the loops (the loops list the inner arc then the outer arc reversed, so
    // point k and point N - 1 - k lie at the same angle).
    let fz: Float = floorZ
    func up(_ m: inout MB, _ q: P2) -> UInt32 { m.v(V3(q.x, q.y, fz), twUp, V2(0, 0), tan: V3(1, 0, 0)) }
    var floorM = MB()
    var bandM = MB()
    let nPts: Int = inner.count
    var fi: [UInt32] = []
    for q in inner { fi.append(up(&floorM, q)) }
    var k: Int = 0
    while k < nPts / 2 - 1 {
        floorM.quad(fi[k], fi[k + 1], fi[nPts - 2 - k], fi[nPts - 1 - k])
        k += 1
    }
    var lo: [UInt32] = []
    var li: [UInt32] = []
    for q in loop { lo.append(up(&bandM, q)) }
    for q in inner { li.append(up(&bandM, q)) }
    k = 0
    while k < nPts {
        let n2: Int = (k + 1) % nPts
        bandM.quad(lo[k], lo[n2], li[n2], li[k])
        k += 1
    }
    acc.add(bandM, .notchFloorShade)
    acc.add(floorM, .notchFloor)
    acc.add(chamfer, .notchChamfer)
    acc.add(sliver, .ringChamfer)
    acc.add(wall, .notchWall)
}

// MARK: - Logo patch

/// Bounding box (min, max) of capsule strokes including their widths.
func twStrokeBounds(_ s: [(a: P2, b: P2, hw: Float)]) -> (lo: P2, hi: P2) {
    var lo = P2(1e9, 1e9)
    var hi = P2(-1e9, -1e9)
    for st in s {
        lo.x = min(lo.x, min(st.a.x, st.b.x) - st.hw)
        lo.y = min(lo.y, min(st.a.y, st.b.y) - st.hw)
        hi.x = max(hi.x, max(st.a.x, st.b.x) + st.hw)
        hi.y = max(hi.y, max(st.a.y, st.b.y) + st.hw)
    }
    return (lo, hi)
}

/// Strokes of the mark for a face: the sign-off mark (front) or the interlocked double-E (back), fitted to the patch and
/// authored for the face seen from the front (wing up, reads correctly).
func twPatchStrokes(interlock: Bool) -> [(a: P2, b: P2, hw: Float)] {
    var design: [(a: P2, b: P2, width: Float)] = []
    if interlock {
        for s in markFrontStrokes() { design.append((a: P2(s.a.x, s.a.y), b: P2(s.b.x, s.b.y), width: s.w)) }
    } else {
        for piece in markBackStrokes() { for s in piece { design.append((a: P2(s.a.x, s.a.y), b: P2(s.b.x, s.b.y), width: s.w)) } }
    }
    var asHW: [(a: P2, b: P2, hw: Float)] = []
    for d in design { asHW.append((a: d.a, b: d.b, hw: d.width * 0.5)) }
    let box = twStrokeBounds(asHW)
    let centre: P2 = (box.lo + box.hi) * 0.5
    let height: Float = box.hi.y - box.lo.y
    return MarkFit.strokes(design, designCentre: centre, designHeight: height, targetHeight: 8.0 * TriWing.unit, flipY: true)
}

/// The gold patch plate with the mark cut in (front layout, wing 0), returning triangle count.
func twBuildPatch(_ acc: inout TWAccumulator, zPad: Float, interlock: Bool) -> Int {
    let centre: P2 = TriWing.patchCentre
    let zT: Float = zPad + TriWing.patchHeight
    let strokes: [(a: P2, b: P2, hw: Float)] = twPatchStrokes(interlock: interlock)
    let box = twStrokeBounds(strokes)
    let m: Float = 0.9 * TriWing.unit
    let cell: Float = 0.0013
    let xs: [Float] = CutGrid.uniform(box.lo.x - m, box.hi.x + m, step: cell)
    let ys: [Float] = CutGrid.uniform(box.lo.y - m, box.hi.y + m, step: cell)
    let sdf: (Float, Float) -> Float = { (x: Float, y: Float) -> Float in
        var best: Float = 1
        for st in strokes {
            let abx: Float = st.b.x - st.a.x
            let aby: Float = st.b.y - st.a.y
            let l2: Float = abx * abx + aby * aby
            var t: Float = 0
            if l2 > 0 { t = min(max(((x - st.a.x) * abx + (y - st.a.y) * aby) / l2, 0), 1) }
            let dx: Float = x - (st.a.x + abx * t)
            let dy: Float = y - (st.a.y + aby * t)
            let d: Float = (dx * dx + dy * dy).squareRoot() - st.hw
            if d < best { best = d }
        }
        return best
    }
    let grid = RectCutMesher.mesh(xs: xs, ys: ys, activeColumns: nil, sdf: sdf)
    var top = MB(), floorMB = MB(), wallMB = MB()
    var topTable = [UInt32](repeating: 0, count: grid.vertices.count)
    var floorTable = topTable
    var wallTable = topTable
    let zFloor: Float = zT - TriWing.markDepth
    for (i, v) in grid.vertices.enumerated() {
        let p = V3(centre.x + v.uv.x, centre.y + v.uv.y, v.onFloor ? zFloor : zT)
        let hasGradient: Bool = (v.gradient.x != 0 || v.gradient.y != 0)
        if hasGradient {
            let n = V3(-v.gradient.x, -v.gradient.y, 0)
            wallTable[i] = wallMB.v(p, n, V2(0, 0), tan: V3(0, 0, 1))
        } else if v.onFloor {
            floorTable[i] = floorMB.v(p, twUp, V2(0, 0), tan: V3(1, 0, 0))
        } else {
            topTable[i] = top.v(p, twUp, V2(0, 0), tan: V3(1, 0, 0))
        }
    }
    func fill(_ list: [UInt32], _ table: [UInt32], _ out: inout MB) {
        var k: Int = 0
        while k + 2 < list.count {
            out.tri(table[Int(list[k])], table[Int(list[k + 1])], table[Int(list[k + 2])])
            k += 3
        }
    }
    fill(grid.face, topTable, &top)
    fill(grid.floor, floorTable, &floorMB)
    fill(grid.wall, wallTable, &wallMB)
    // Plate: rounded rectangle with a bevel, the top face has the mark box as a hole whose boundary matches the grid.
    let plate: [P2] = twRoundedRect(centre: centre, size: TriWing.patchSize, corner: TriWing.patchCorner, segments: 8)
    let bev: Float = 0.002
    let plateIn: [P2] = polygonOffsetInward(plate, by: bev)
    var hole: [P2] = []
    let nx: Int = xs.count
    let ny: Int = ys.count
    for i in 0..<nx { hole.append(P2(centre.x + xs[i], centre.y + ys[0])) }
    for j in 1..<ny { hole.append(P2(centre.x + xs[nx - 1], centre.y + ys[j])) }
    var i2: Int = nx - 2
    while i2 >= 0 { hole.append(P2(centre.x + xs[i2], centre.y + ys[ny - 1])); i2 -= 1 }
    var j2: Int = ny - 2
    while j2 >= 1 { hole.append(P2(centre.x + xs[0], centre.y + ys[j2])); j2 -= 1 }
    let plateTri = PolygonTriangulator.triangulate(outer: plateIn, holes: [hole])
    var out = TWAccumulator()
    out.add(twFlat(plateTri, z: zT, textured: false), .gold)
    out.add(twBevel(outer: plate, inner: plateIn, zLow: zT - bev, zHigh: zT), .gold)
    out.add(twWall(plate, zTop: zT - bev, zBottom: zPad, inward: false), .goldWall)
    out.add(top, .gold)
    out.add(floorMB, .engraveFloor)
    out.add(wallMB, .goldWall)
    acc.merge(out, transform: matrix_identity_float4x4, normalMatrix: matrix_identity_float3x3)
    return plateTri.indices.count / 3 + top.triCount + floorMB.triCount + wallMB.triCount
}

// MARK: - Bearing, hub, crystal

/// Half a ball (z >= 0): the other half comes from the mirrored face.
func twHemisphere(radius: Float, seg: Int, rows: Int) -> MB {
    var prof: [ProfilePt] = []
    var i: Int = 0
    while i <= rows {
        let t: Float = Float(i) / Float(rows)
        let phi: Float = Float.pi / 2 + t * Float.pi / 2
        let s: Float = sin(phi)
        let c: Float = cos(phi)
        prof.append(ProfilePt(r: radius * s, z: -radius * c, nr: s, nz: -c, v: t))
        i += 1
    }
    return lathe(prof, seg: seg)
}

/// Wrap an angle difference into (-pi, pi].
private func twWrapAngle(_ a: Float) -> Float {
    var x: Float = a
    while x > Float.pi { x -= 2 * Float.pi }
    while x <= -Float.pi { x += 2 * Float.pi }
    return x
}

/// One cage bar between two neighbouring balls (ball `i` to ball `i + 1`): an annular piece at the cage radii with a
/// concave pocket arc at each end.
func twCageBar(from i: Int) -> [P2] {
    let n: Int = TriWing.ballCount
    let step: Float = 2 * Float.pi / Float(n)
    let a0: Float = Float.pi / 2 + Float(i) * step
    let a1: Float = a0 + step
    let d: Float = TriWing.ballRingRadius
    let pr: Float = TriWing.cagePocketRadius
    let rin: Float = TriWing.cageInner
    let rout: Float = TriWing.cageOuter
    func delta(_ r: Float) -> Float { acos(min(max((r * r + d * d - pr * pr) / (2 * r * d), -1), 1)) }
    let dIn: Float = delta(rin)
    let dOut: Float = delta(rout)
    func polar(_ r: Float, _ a: Float) -> P2 { P2(r * cos(a), r * sin(a)) }
    func ballC(_ a: Float) -> P2 { P2(d * cos(a), d * sin(a)) }
    var out: [P2] = []
    let arcN: Int = 10
    var k: Int = 0
    while k <= arcN {
        let t: Float = Float(k) / Float(arcN)
        out.append(polar(rout, a0 + dOut + (a1 - dOut - (a0 + dOut)) * t))
        k += 1
    }
    // Around ball i + 1: outer intersection to inner intersection.
    let c1: P2 = ballC(a1)
    let po: P2 = polar(rout, a1 - dOut)
    let pi2: P2 = polar(rin, a1 - dIn)
    let psiO: Float = atan2(po.y - c1.y, po.x - c1.x)
    let psiI: Float = psiO + twWrapAngle(atan2(pi2.y - c1.y, pi2.x - c1.x) - psiO)
    k = 1
    let capN: Int = 6
    while k < capN {
        let psi: Float = psiO + (psiI - psiO) * Float(k) / Float(capN)
        out.append(P2(c1.x + pr * cos(psi), c1.y + pr * sin(psi)))
        k += 1
    }
    k = 0
    while k <= arcN {
        let t: Float = Float(k) / Float(arcN)
        out.append(polar(rin, a1 - dIn + (a0 + dIn - (a1 - dIn)) * t))
        k += 1
    }
    let c0: P2 = ballC(a0)
    let qi: P2 = polar(rin, a0 + dIn)
    let qo: P2 = polar(rout, a0 + dOut)
    let phiI: Float = atan2(qi.y - c0.y, qi.x - c0.x)
    let phiO: Float = phiI + twWrapAngle(atan2(qo.y - c0.y, qo.x - c0.x) - phiI)
    k = 1
    while k < capN {
        let psi: Float = phiI + (phiO - phiI) * Float(k) / Float(capN)
        out.append(P2(c0.x + pr * cos(psi), c0.y + pr * sin(psi)))
        k += 1
    }
    return out
}

func twBuildCentre(_ acc: inout TWAccumulator, faceIndex: Int) {
    let hB: Float = TriWing.halfThickness
    // Well wall in the body (the open bearing below fills it from z = 0 up to the race tops).
    let circle: [P2] = circlePolygon(center: zeroP, radius: TriWing.wellRadius, segments: 120)
    acc.add(twWall(circle, zTop: hB, zBottom: 0, inward: true), .wellWall)
    // Races: polished rings, each a half in this face's layout that meets its mirror at the mid plane (z = 0). The face
    // toward the balls has a raceway groove and a rounded shoulder; the other edges have a small chamfer.
    let top: Float = TriWing.raceTopZ
    let c: Float = 0.004
    let face: [(Float, Float)] = TriWing.raceGapFace()
    let rGapOuterRace: Float = TriWing.outerRaceInner
    let rGapInnerRace: Float = TriWing.innerRaceOuter
    var outerPts: [(Float, Float)] = []
    for (d, z) in face { outerPts.append((rGapOuterRace + d, z)) }
    let rOut: Float = TriWing.outerRaceOuter
    outerPts.append((rOut - c, top))
    outerPts.append((rOut - c, top))
    outerPts.append((rOut, top - c))
    outerPts.append((rOut, top - c))
    outerPts.append((rOut, 0))
    acc.add(twLathe(outerPts, seg: 120), .raceSteel)
    var innerPts: [(Float, Float)] = []
    let rIn: Float = TriWing.innerRaceInner
    innerPts.append((rIn, 0))
    innerPts.append((rIn, top - c))
    innerPts.append((rIn, top - c))
    innerPts.append((rIn + c, top))
    innerPts.append((rIn + c, top))
    for (d, z) in face.reversed() { innerPts.append((rGapInnerRace - d, z)) }
    acc.add(twLathe(innerPts, seg: 120), .innerRace)
    // Cage: steel bars with bevelled edges (one between each pair of balls) between the balls (a half thickness here, the mirror makes the other half).
    let ht: Float = TriWing.cageHalfThickness
    var k: Int = 0
    while k < TriWing.ballCount {
        let bar: [P2] = polygonOriented(twCageBar(from: k), counterClockwise: true)
        let barTop: [P2] = polygonOffsetInward(bar, by: TriWing.cageBevelInset)
        acc.add(twFlat(PolygonTriangulator.triangulate(outer: barTop, holes: []), z: ht, textured: false), .cage)
        acc.add(twBevel(outer: bar, inner: barTop, zLow: ht - TriWing.cageBevelDrop, zHigh: ht), .cage)
        acc.add(twWall(bar, zTop: ht - TriWing.cageBevelDrop, zBottom: 0, inward: false), .cage)
        k += 1
    }
    // Polished balls (upper halves).
    let ball: MB = twHemisphere(radius: TriWing.ballRadius, seg: 40, rows: 12)
    k = 0
    while k < TriWing.ballCount {
        let a: Float = Float.pi / 2 + Float(k) * 2 * Float.pi / Float(TriWing.ballCount)
        acc.add(ball, .ballSteel, transform: twTranslate(V3(TriWing.ballRingRadius * cos(a), TriWing.ballRingRadius * sin(a), 0)))
        k += 1
    }
    // Plain hub: slightly dished, fine concentric turning rings, polished chamfer; solid down to the mid plane.
    let hubR: Float = TriWing.hubRadius
    let rim: Float = TriWing.hubRimZ
    let drop: Float = TriWing.hubDishDrop
    let chamferW: Float = 0.010
    // Turned finish: the concentric turning is a texture on the dish (see `makeTWHubImages`), not geometry, so it cannot alias
    // into moire; the dish itself is smooth. The lathe's v runs 0 at the centre to 1 at the chamfer, linear in radius.
    func dishZ(_ r: Float) -> Float {
        let t: Float = r / hubR
        return rim - drop + drop * t * t
    }
    var profile: [(Float, Float)] = []
    let rEnd: Float = hubR - chamferW
    let steps: Int = 48
    var i: Int = 0
    while i <= steps {
        let r: Float = rEnd * Float(i) / Float(steps)
        profile.append((r, dishZ(r)))
        i += 1
    }
    acc.add(twLathe(profile, seg: 240), .hubTurned)
    let zRimEnd: Float = dishZ(rEnd)
    acc.add(twLathe([(rEnd, zRimEnd), (hubR, zRimEnd - chamferW), (hubR, zRimEnd - chamferW), (hubR, 0)], seg: 120), .hubChamfer)
    // Sapphire-style crystal over the whole bearing and the hub: a clear flat disc seated in the ring's inner edge, with a
    // small polished bevel at its rim (real geometry, bright), the clear top face a low-opacity glossy surface.
    let zc: Float = TriWing.crystalZ
    let rc: Float = TriWing.ringInner - 0.0008
    let bev: Float = TriWing.crystalBevel
    acc.add(annulus(r0: 0, r1: rc - bev, z: zc, nz: 1, seg: 120, rings: 3), .crystal)
    acc.add(twLathe([(rc - bev, zc), (rc, zc - bev), (rc, zc - bev), (rc, zc - TriWing.crystalThickness)], seg: 192), .crystalRim)
    // Reflection overlay: a flat disc just above the crystal whose uv spans 1.7 crystal diameters (see `twGlintImage`).
    let glintCircle: [P2] = circlePolygon(center: zeroP, radius: rc - bev, segments: 64)
    let glintTri = PolygonTriangulator.triangulate(outer: glintCircle, holes: [])
    var glint = MB()
    var gmap: [UInt32] = []
    for q in glintTri.vertices {
        let uv: V2 = V2(q.x / (2 * rc * 1.7) + 0.5, q.y / (2 * rc * 1.7) + 0.5)
        gmap.append(glint.v(V3(q.x, q.y, zc + 0.0004), twUp, uv, tan: V3(1, 0, 0)))
    }
    var gi: Int = 0
    while gi + 2 < glintTri.indices.count {
        glint.tri(gmap[Int(glintTri.indices[gi])], gmap[Int(glintTri.indices[gi + 1])], gmap[Int(glintTri.indices[gi + 2])])
        gi += 3
    }
    acc.add(glint, .glint(faceIndex))
}

// MARK: - Whole part

/// Everything of one face in front layout. `patchInterlock` selects the mark on the logo patch.
func twBuildFace(patchInterlock: Bool, ring: Bool, stats: inout [(String, Int)]) -> TWAccumulator {
    var acc = TWAccumulator()
    let hB: Float = TriWing.halfThickness
    let c: Float = TriWing.bodyChamfer
    // Body plate.
    var outline: [P2] = []
    for col in TriWingWall.columns() { outline.append(col.p) }
    let inset: [P2] = polygonOffsetInward(outline, by: c)
    var holes: [[P2]] = [circlePolygon(center: zeroP, radius: TriWing.wellRadius, segments: 120)]
    var slotLoops: [[P2]] = []
    for k in 0..<TriWing.wingCount {
        for side: Float in [-1, 1] {
            slotLoops.append(polygonRotated(TriWing.flankSlotOutline(side: side), by: TriWing.wingAngle(k)))
        }
    }
    holes.append(contentsOf: slotLoops)
    if ring {
        for na in TriWing.notchAngles { holes.append(TriWing.notchPocketLoop(angle: na, arcSegments: 32)) }
    }
    let bodyTri = PolygonTriangulator.triangulate(outer: inset, holes: holes)
    acc.add(twFlat(bodyTri, z: hB, textured: true), .bodyTop)
    // Edge chamfer, plain wall, waist band with flutes and windows (see `twBuildSideWall`).
    twBuildSideWall(&acc)
    // Tube slots: floor and walls, and the light each wing's tubes throw into its two slots (see `TWKind.slotWall`).
    let slotDepth: Float = TriWing.tubeSlotDepth
    let floorZ: Float = hB - slotDepth
    for (slotIndex, loop) in slotLoops.enumerated() {
        let wingColour: Int = slotIndex / 2
        let ccw: [P2] = polygonOriented(loop, counterClockwise: true)
        // The wall's v runs 0 at the lip to 1 at the floor: the lit material's emissive texture fades the glow up the wall.
        acc.add(twWall(ccw, zTop: hB, zBottom: floorZ, inward: true), .slotWall(wingColour))
        acc.add(twFlat(PolygonTriangulator.triangulate(outer: ccw, holes: []), z: floorZ, textured: false), .slotFloor(wingColour))
        let lipOuter: [P2] = polygonOffsetInward(ccw, by: -TriWing.slotLipWidth)
        acc.add(twBevel(outer: lipOuter, inner: ccw, zLow: hB + 0.0008, zHigh: hB + 0.0008), .slotLip(wingColour))
    }
    // Wing 0: pad, boss and jewel, screws; replicated by rotation.
    var wing = TWAccumulator()
    let padOut: [P2] = TriWing.padOutline()
    let padIn: [P2] = polygonOffsetInward(padOut, by: TriWing.padChamfer)
    let zP: Float = hB + TriWing.padHeight
    var padHoles: [[P2]] = []
    for sc in TriWing.screwCentres {
        padHoles.append(circlePolygon(center: sc, radius: TriWing.countersinkScrewRadius, segments: 28))
    }
    let padTri = PolygonTriangulator.triangulate(outer: padIn, holes: padHoles)
    wing.add(twFlat(padTri, z: zP, textured: true), .padTop)
    wing.add(twBevel(outer: padOut, inner: padIn, zLow: zP - TriWing.padChamfer, zHigh: zP), .padChamfer)
    wing.add(twWall(padOut, zTop: zP - TriWing.padChamfer, zBottom: hB, inward: false), .padWall)
    for (i, sc) in TriWing.screwCentres.enumerated() {
        twBuildScrew(&wing, centre: sc, angle: TriWing.screwSlotAngles[i], zPad: zP)
    }
    var boss = TWAccumulator()
    twBuildBoss(&boss, zPad: zP)
    wing.merge(boss, transform: twTranslate(V3(TriWing.bossCenter.x, TriWing.bossCenter.y, 0)), normalMatrix: matrix_identity_float3x3)
    for k in 0..<TriWing.wingCount {
        let rot = twRotZ(TriWing.wingAngle(k))
        acc.merge(wing, transform: rot.m, normalMatrix: rot.n)
    }
    // The soft tint the slot's light puts on the side of its wing's pad (wall and bevel), strongest where the pad edge runs
    // close to a slot. Built once in wing 0's layout and turned into each wing's own colour.
    let tintMB: MB = twBuildPadTint(padOut: padOut, padIn: padIn, zPad: zP, zBody: hB)
    for k in 0..<TriWing.wingCount {
        let rot = twRotZ(TriWing.wingAngle(k))
        acc.add(tintMB, .padTint(k), transform: rot.m, normalMatrix: rot.n)
    }
    // Patch on wing 0 only.
    let patchTris: Int = twBuildPatch(&acc, zPad: zP, interlock: patchInterlock)
    stats.append(("patch", patchTris))
    // Edge-light tubes: one per flank, two per wing, a colour per wing (staggered along the flank, see `TriWing`). Each rests
    // on its slot floor.
    let tubeZ: Float = floorZ + TriWing.tubeShellRadius + 0.0006
    for k in 0..<TriWing.wingCount {
        let colour: Int = k
        var core = MB()
        var shell = MB()
        var collars = MB()
        for side: Float in [-1, 1] {
            let local: [P2] = TriWing.flankTubePath(side: side)
            var path: [V3] = []
            for p in local {
                let q: P2 = TriWing.inWing(p, k)
                path.append(V3(q.x, q.y, tubeZ))
            }
            core.append(capsulePath(center: path, radius: TriWing.tubeFilamentRadius, up: twUp, around: 12, capRings: 4),
                        transform: matrix_identity_float4x4, normalMatrix: matrix_identity_float3x3)
            shell.append(capsulePath(center: path, radius: TriWing.tubeShellRadius, up: twUp, around: 14, capRings: 4),
                         transform: matrix_identity_float4x4, normalMatrix: matrix_identity_float3x3)
            // Collars: a short polished cylindrical sleeve over each tube end, with a flat end cap and a small chamfer.
            for end in [0, 1] {
                let tipIndex: Int = end == 0 ? 0 : path.count - 1
                let nextIndex: Int = end == 0 ? 1 : path.count - 2
                let tip: V3 = path[tipIndex]
                let toward: V3 = path[nextIndex] - tip
                let along: V3 = simd_normalize(toward)
                let across = V3(along.y, -along.x, 0)
                let basis = simd_float4x4(columns: (SIMD4<Float>(0, 0, 1, 0), SIMD4<Float>(across.x, across.y, 0, 0),
                                                    SIMD4<Float>(along.x, along.y, 0, 0), SIMD4<Float>(tip.x, tip.y, tip.z, 1)))
                let rot = simd_float3x3(columns: (V3(0, 0, 1), across, V3(along.x, along.y, 0)))
                collars.append(twCollarLocal(), transform: basis, normalMatrix: rot)
            }
        }
        acc.add(core, .tubeCore(colour))
        acc.add(shell, .tubeShell(colour))
        acc.add(collars, .collar)
    }
    twBuildCentre(&acc, faceIndex: patchInterlock ? 1 : 0)
    if ring { stats.append(("ring", twBuildRing(&acc, face: patchInterlock ? .back : .front))) }
    return acc
}

/// One tube-end collar in its own frame: axis +z runs from the tube tip toward the tube centre. A polished cylindrical sleeve
/// of `tubeCollarLength` with a flat end cap `tubeCollarCapReach` beyond the tip (so it hides the tube's rounded end), a small
/// chamfer round the cap, and a short step down onto the glass where it meets the tube.
func twCollarLocal() -> MB {
    let rad: Float = TriWing.tubeCollarRadius
    let len: Float = TriWing.tubeCollarLength
    let chamfer: Float = TriWing.tubeCollarChamfer
    let cap: Float = -TriWing.tubeCollarCapReach
    var pts: [(Float, Float)] = []
    pts.append((TriWing.tubeShellRadius * 0.96, len))
    pts.append((rad, len))
    pts.append((rad, len))
    pts.append((rad, cap + chamfer))
    pts.append((rad, cap + chamfer))
    pts.append((rad - chamfer, cap))
    pts.append((rad - chamfer, cap))
    pts.append((0, cap))
    return twLathe(pts, seg: 24)
}

/// Soft tint on the side of a wing pad (wall and bevel) where it faces a tube slot, in wing 0's layout. The texture coordinate
/// carries the intensity (see `TWGlowPt`): strongest where the pad edge is close to a slot, gone a few hundredths away.
func twBuildPadTint(padOut: [P2], padIn: [P2], zPad: Float, zBody: Float) -> MB {
    let slots: [[P2]] = [TriWing.flankTubePath(side: -1), TriWing.flankTubePath(side: 1)]
    let outer: [P2] = polygonOffsetInward(padOut, by: -0.0015)
    let wallBottom: Float = zBody + 0.0008
    let wallTop: Float = zPad - TriWing.padChamfer
    var rings: [[TWGlowPt]] = []
    let rows: Int = 3
    var r: Int = 0
    while r <= rows {
        let h: Float = Float(r) / Float(rows)
        let z: Float = wallBottom + (wallTop - wallBottom) * h
        let heightFactor: Float = 1 - 0.35 * h
        var ring: [TWGlowPt] = []
        for q in outer {
            let d: Float = twDistanceToPaths(q, slots)
            ring.append(TWGlowPt(p: V3(q.x, q.y, z), intensity: twPadTintIntensity(distance: d) * heightFactor))
        }
        rings.append(ring)
        r += 1
    }
    var top: [TWGlowPt] = []
    var i: Int = 0
    while i < padIn.count {
        let q: P2 = padIn[i]
        let d: Float = twDistanceToPaths(outer[i], slots)
        top.append(TWGlowPt(p: V3(q.x, q.y, zPad + 0.0004), intensity: twPadTintIntensity(distance: d) * 0.45))
        i += 1
    }
    rings.append(top)
    return twGlowBand(rings)
}

/// Number of translucent shells in the swept volume outside the opaque core.
let twShellCount: Int = 36

/// The whole Tri-wing as plain arrays (no RealityKit). Safe on any thread.
func buildTriWingCPU() -> TWGeometryCPU {
    var out = TWGeometryCPU()
    let t0 = DispatchTime.now().uptimeNanoseconds
    var stats: [(String, Int)] = []
    let front = twBuildFace(patchInterlock: false, ring: true, stats: &stats)
    let back = twBuildFace(patchInterlock: true, ring: true, stats: &stats)
    var all = TWAccumulator()
    all.merge(front, transform: matrix_identity_float4x4, normalMatrix: matrix_identity_float3x3)
    let flip = twFlipY()
    all.merge(back, transform: flip.m, normalMatrix: flip.n)
    for k in all.order {
        if let mb = all.meshes[k] {
            out.parts.append(TWPart(mb: mb, kind: k, name: "tw\(k)", group: twGroup(k)))
        }
    }
    let ms: Double = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
    let t1 = DispatchTime.now().uptimeNanoseconds
    out.images = makeTWImages()
    let profile: TriWingSmear = TriWingSmear.compute(face: .front)
    let profileBack: TriWingSmear = TriWingSmear.compute(face: .back)
    out.smear = profile
    var glowMax: Float = 0
    var glowAt: Int = 0
    for (i, g) in profile.glow.enumerated() where g > glowMax { glowMax = g; glowAt = i }
    out.timings.append(("tri-wing smear glow max \(glowMax) at r \(Float(glowAt) / Float(profile.radii))", 0))
    out.smearImages = makeTWSmearImages(faces: [profile, profileBack])
    // Spin-blur parts. The time-average of the spinning body is built from: an opaque lathe core (full-coverage radius and
    // inside), a face overlay on each face that hugs the swept height profile (the smear colour image times the zone
    // opacity curve), the same overlay's wing-zone part beyond the full-coverage radius, a stack of thin single-sided
    // shells for the side view, the swept light rings and the side band of light.
    let rFull: Float = profile.fullCoverageRadius()
    let rTip: Float = max(profile.tipRadius(), rFull + 0.01)
    let rCoreIn: Float = TriWing.ringInner
    let hSeat: Float = TriWing.halfThickness - 0.003
    let cc: Float = 0.006
    let coreSeg: Int = 192
    let profileZ: (Float) -> Float = { (r: Float) -> Float in
        r <= rFull ? hSeat : max(hSeat, profile.sweptHalfHeight(at: r))
    }
    let bearingZ: Float = 0.062
    let faceLift: Float = 0.0010
    for (side, tag, faceIndex) in [(Float(1), "F", 0), (Float(-1), "B", 1)] {
        var body = MB()
        body.append(twProfileDisc(r0: TriWing.hubRadius, r1: rCoreIn, side: side, seg: 192, rings: 4, z: { (_: Float) -> Float in bearingZ + faceLift }),
                    transform: matrix_identity_float4x4, normalMatrix: matrix_identity_float3x3)
        body.append(twProfileDisc(r0: rCoreIn, r1: rFull + 0.004, side: side, seg: 192, rings: 4, z: { (_: Float) -> Float in hSeat + faceLift }),
                    transform: matrix_identity_float4x4, normalMatrix: matrix_identity_float3x3)
        out.parts.append(TWPart(mb: body, kind: .smearBody(faceIndex), name: "twsmearBody" + tag, group: .smear))
        let zone: MB = twProfileDisc(r0: rFull, r1: 0.995, side: side, seg: 192, rings: 40, z: { (r: Float) -> Float in profileZ(r) + faceLift })
        out.parts.append(TWPart(mb: zone, kind: .smearZone(faceIndex), name: "twsmearZone" + tag, group: .zone))
    }
    var rings = MB()
    for side in [Float(1), Float(-1)] {
        rings.append(twProfileDisc(r0: 0.5, r1: 0.995, side: side, seg: 192, rings: 40, z: { (r: Float) -> Float in profileZ(r) + faceLift + 0.0016 }),
                     transform: matrix_identity_float4x4, normalMatrix: matrix_identity_float3x3)
    }
    out.parts.append(TWPart(mb: rings, kind: .smearGlow, name: "twsmearGlow", group: .sweptGlow))
    for wingIndex in 0..<3 {
        out.parts.append(TWPart(mb: rings, kind: .smearGlowWing(wingIndex), name: "twsmearGlowWing\(wingIndex)", group: .sweptGlow))
    }
    // Opaque core: flat faces to the full-coverage radius, a small chamfer, and a wall carrying the waist band.
    var coreTop = MB()
    var coreChamfer = MB()
    var coreWall = MB()
    var coreBevel = MB()
    var coreFloor = MB()
    let id4: simd_float4x4 = matrix_identity_float4x4
    let id3: simd_float3x3 = matrix_identity_float3x3
    for side: Float in [1, -1] {
        let h: Float = side * hSeat
        let hc: Float = side * (hSeat - cc)
        if side > 0 {
            coreTop.append(twLathe([(rCoreIn, h), (rFull - cc, h)], seg: coreSeg), transform: id4, normalMatrix: id3)
            coreChamfer.append(twLathe([(rFull - cc, h), (rFull, hc)], seg: coreSeg), transform: id4, normalMatrix: id3)
        } else {
            coreTop.append(twLathe([(rFull - cc, h), (rCoreIn, h)], seg: coreSeg), transform: id4, normalMatrix: id3)
            coreChamfer.append(twLathe([(rFull, hc), (rFull - cc, h)], seg: coreSeg), transform: id4, normalMatrix: id3)
        }
    }
    let wallTop: Float = hSeat - cc
    let bandOpen: Float = TriWingWall.bandOpenHalfHeight
    let bandHalf: Float = TriWingWall.bandHalfHeight
    let recess: Float = TriWingWall.recess
    coreWall.append(twLathe([(rFull, wallTop), (rFull, bandOpen)], seg: coreSeg), transform: id4, normalMatrix: id3)
    coreWall.append(twLathe([(rFull, -bandOpen), (rFull, -wallTop)], seg: coreSeg), transform: id4, normalMatrix: id3)
    coreBevel.append(twLathe([(rFull, bandOpen), (rFull - recess, bandHalf)], seg: coreSeg), transform: id4, normalMatrix: id3)
    coreBevel.append(twLathe([(rFull - recess, -bandHalf), (rFull, -bandOpen)], seg: coreSeg), transform: id4, normalMatrix: id3)
    coreFloor.append(twLathe([(rFull - recess, bandHalf), (rFull - recess, -bandHalf)], seg: coreSeg), transform: id4, normalMatrix: id3)
    coreWall.append(twLathe([(rCoreIn, -hSeat), (rCoreIn, hSeat)], seg: coreSeg), transform: id4, normalMatrix: id3)
    out.parts.append(TWPart(mb: coreTop, kind: .bodyTop, name: "twcoreTop", group: .sweptCore))
    out.parts.append(TWPart(mb: coreChamfer, kind: .bodyChamfer, name: "twcoreChamfer", group: .sweptCore))
    out.parts.append(TWPart(mb: coreWall, kind: .coreWall, name: "twcoreWall", group: .sweptCore))
    out.parts.append(TWPart(mb: coreBevel, kind: .waistBevel, name: "twcoreBevel", group: .sweptCore))
    out.parts.append(TWPart(mb: coreFloor, kind: .waistFloor, name: "twcoreFloor", group: .sweptCore))
    // Side band of light: the edge-light windows swept round the waist, lying just above the recess floor.
    let bandHalfHeight: Float = TriWingWall.windowHalfHeight
    for half in 0..<2 {
        let sgn: Float = half == 0 ? 1 : -1
        out.parts.append(TWPart(mb: twBandWall(radius: rFull - recess + 0.0012, halfHeight: bandHalfHeight, sign: sgn, seg: coreSeg),
                                kind: .sideBand(half), name: "twsideBand\(half)", group: .sweptGlow))
    }
    // Wing zone: many thin single-sided shells (only the near side of a wall is drawn, so no triangle of one shell ever
    // overlaps another of the same shell), each carrying a small optical depth.
    let shells: [TriWingSmear.SweptShell] = profile.sweptShells(count: twShellCount)
    for (i, sh) in shells.enumerated() {
        out.parts.append(TWPart(mb: twShellWall(radius: sh.radius, halfHeight: sh.halfHeight, seg: 144, rows: 6),
                                kind: .sweptShell(i), name: "twshell\(i)", group: .zone))
    }
    out.shellOpacities = shells.map { (s: TriWingSmear.SweptShell) -> Float in s.opacity }
    out.timings.append(("tri-wing swept core to r \(rFull), zone to r \(rTip), \(shells.count) shells", 0))
    out.timings.append(("tri-wing brushed and ray textures", Double(DispatchTime.now().uptimeNanoseconds - t1) / 1e6))
    out.timings.append(("tri-wing meshes (\(out.triangles) triangles)", ms))
    for (n, t) in stats { out.timings.append(("tri-wing \(n) mesh (\(t) triangles, one face)", 0)) }
    return out
}

/// A disc or annulus whose height follows `z(r)` (offset to the face's side), with planar uv over [-1, 1] like the plates
/// and normals from the slope, so the swept face hugs the swept height profile instead of floating above it.
func twProfileDisc(r0: Float, r1: Float, side: Float, seg: Int, rings: Int, z: (Float) -> Float) -> MB {
    var m = MB()
    var rows: [[UInt32]] = []
    var i: Int = 0
    while i <= rings {
        let r: Float = r0 + (r1 - r0) * Float(i) / Float(rings)
        let dr: Float = 0.002
        let slope: Float = (z(r + dr) - z(max(r - dr, 0))) / (2 * dr)
        var row: [UInt32] = []
        var j: Int = 0
        while j <= seg {
            let th: Float = turnAngle(j, of: seg)
            let c: Float = cos(th)
            let s: Float = sin(th)
            let x: Float = r * c
            let y: Float = r * s
            let nor: V3 = simd_normalize(V3(-slope * c, -slope * s, side))
            row.append(m.v(V3(x, y, side * z(r)), nor, V2(x * 0.5 + 0.5, 0.5 + y * 0.5), tan: V3(-s, c, 0)))
            j += 1
        }
        rows.append(row)
        i += 1
    }
    i = 0
    while i < rings {
        var j: Int = 0
        while j < seg { m.quad(rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]); j += 1 }
        i += 1
    }
    return m
}

/// One thin shell of the swept wing zone: a cylinder wall of `radius` from -halfHeight to +halfHeight, outward normals,
/// uv (turn, v) with v running 0 at the bottom to 1 at the top (the vertical alpha strip is read along v).
func twShellWall(radius: Float, halfHeight: Float, seg: Int, rows: Int) -> MB {
    var m = MB()
    var grid: [[UInt32]] = []
    var i: Int = 0
    while i <= rows {
        let v: Float = Float(i) / Float(rows)
        let z: Float = (v * 2 - 1) * halfHeight
        var row: [UInt32] = []
        var j: Int = 0
        while j <= seg {
            let th: Float = turnAngle(j, of: seg)
            let c: Float = cos(th)
            let s: Float = sin(th)
            row.append(m.v(V3(radius * c, radius * s, z), V3(c, s, 0), V2(Float(j) / Float(seg), v), tan: V3(-s, c, 0)))
            j += 1
        }
        grid.append(row)
        i += 1
    }
    i = 0
    while i < rows {
        var j: Int = 0
        while j < seg { m.quad(grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]); j += 1 }
        i += 1
    }
    return m
}

/// Half of the side band of light: a wall at `radius` from the waist (z = 0) to `sign * halfHeight`, uv v 0 at the waist and
/// 1 at the outer edge (the band's fade strip is read along v).
func twBandWall(radius: Float, halfHeight: Float, sign: Float, seg: Int) -> MB {
    var m = MB()
    var grid: [[UInt32]] = []
    let rows: Int = 6
    var i: Int = 0
    while i <= rows {
        let v: Float = Float(i) / Float(rows)
        var row: [UInt32] = []
        var j: Int = 0
        while j <= seg {
            let th: Float = turnAngle(j, of: seg)
            let c: Float = cos(th)
            let s: Float = sin(th)
            row.append(m.v(V3(radius * c, radius * s, sign * v * halfHeight), V3(c, s, 0), V2(Float(j) / Float(seg), v), tan: V3(-s, c, 0)))
            j += 1
        }
        grid.append(row)
        i += 1
    }
    i = 0
    while i < rows {
        var j: Int = 0
        while j < seg { m.quad(grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]); j += 1 }
        i += 1
    }
    return m
}
