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
import MacVisualizerCore

// The Tri-wing's side wall in front layout, half above the mid plane (the back face is this half turned about y, so the two
// halves meet at z = 0 in the middle of the waist band). Layout and dimensions: `TriWingWall`. From the top: the edge
// chamfer, the plain wall, the upper shoulder of the waist band, the recessed band floor with its grip flutes (round each
// tip) and its six edge-light windows (frame and lens).

/// Texture-coordinate scale along the outline for the wall parts (the band floor's turned finish reads the v coordinate).
let twWallUVPerR: Float = 6.0

func twBuildSideWall(_ acc: inout TWAccumulator) {
    let cols: [TriWingWall.Column] = TriWingWall.columns()
    let n: Int = cols.count
    let hB: Float = TriWing.halfThickness
    let c: Float = TriWing.bodyChamfer
    let wallTop: Float = TriWingWall.wallTopZ
    let open: Float = TriWingWall.bandOpenHalfHeight
    let band: Float = TriWingWall.bandHalfHeight
    let recess: Float = TriWingWall.recess
    let r2: Float = 0.70710678

    func pos(_ i: Int, _ a: Float, _ z: Float) -> V3 {
        let q = cols[i]
        return V3(q.p.x - q.n.x * a, q.p.y - q.n.y * a, z)
    }
    func tangent(_ i: Int) -> V3 { V3(-cols[i].n.y, cols[i].n.x, 0) }
    func ring(_ m: inout MB, a: Float, z: Float, nh: Float, nz: Float, v: Float) -> [UInt32] {
        var ids: [UInt32] = []
        ids.reserveCapacity(n)
        for i in 0..<n {
            let q = cols[i]
            ids.append(m.v(pos(i, a, z), V3(q.n.x * nh, q.n.y * nh, nz), V2(q.s * twWallUVPerR, v), tan: tangent(i)))
        }
        return ids
    }
    func connect(_ m: inout MB, _ top: [UInt32], _ bot: [UInt32], skip: (Int, Int) -> Bool = { _, _ in false }) {
        for i in 0..<n {
            let j: Int = (i + 1) % n
            if skip(i, j) { continue }
            m.quad(top[i], top[j], bot[j], bot[i])
        }
    }

    // Edge chamfer (45 degrees, polished) and plain wall.
    var chamfer = MB()
    let chTop: [UInt32] = ring(&chamfer, a: c, z: hB, nh: r2, nz: r2, v: 0)
    let chBot: [UInt32] = ring(&chamfer, a: 0, z: wallTop, nh: r2, nz: r2, v: 1)
    connect(&chamfer, chTop, chBot)
    acc.add(chamfer, .bodyChamfer)

    var wall = MB()
    let wTop: [UInt32] = ring(&wall, a: 0, z: wallTop, nh: 1, nz: 0, v: 0)
    let wBot: [UInt32] = ring(&wall, a: 0, z: open, nh: 1, nz: 0, v: 1)
    connect(&wall, wTop, wBot)
    acc.add(wall, .bodyWall)

    // Upper shoulder of the band: an overhang, so it faces outward and down.
    var shoulder = MB()
    let sTop: [UInt32] = ring(&shoulder, a: 0, z: open, nh: r2, nz: -r2, v: 0)
    let sBot: [UInt32] = ring(&shoulder, a: recess, z: band, nh: r2, nz: -r2, v: 1)
    connect(&shoulder, sTop, sBot)
    acc.add(shoulder, .waistBevel)

    // Band floor. Window columns stop at the lens opening's top edge; flute columns are rebuilt with their grooves below.
    let wins: [TriWingWall.Window] = TriWingWall.windows()
    var lower: [Float] = [Float](repeating: 0, count: n)
    for w in wins {
        for k in (-w.halfColumns)...(w.halfColumns) {
            let i: Int = w.centre + k
            lower[i] = TriWingWall.stadiumHalfHeight(offset: cols[i].s - cols[w.centre].s, halfLength: w.halfLength, halfHeight: w.halfHeight)
        }
    }
    func inZone(_ i: Int) -> Bool {
        cols[i].tipWing >= 0 && abs(cols[i].tipAngle) <= TriWingWall.fluteHalfAngle + 1e-5
    }
    var floorMesh = MB()
    let fTop: [UInt32] = ring(&floorMesh, a: recess, z: band, nh: 1, nz: 0, v: band * twWallUVPerR)
    var fBot: [UInt32] = []
    fBot.reserveCapacity(n)
    for i in 0..<n {
        let q = cols[i]
        fBot.append(floorMesh.v(pos(i, recess, lower[i]), V3(q.n.x, q.n.y, 0), V2(q.s * twWallUVPerR, lower[i] * twWallUVPerR), tan: tangent(i)))
    }
    connect(&floorMesh, fTop, fBot, skip: { (i: Int, j: Int) -> Bool in inZone(i) && inZone(j) })
    acc.add(floorMesh, .waistFloor)

    // Flutes: rows from the band top down to the mid plane, with a run-out so the grooves end cleanly.
    var flute = MB()
    let rowsZ: [Float] = [band, fluteTopRow(), 0.0375, 0.035, 0.0325, TriWingWall.fluteHalfHeight, 0]
    let rf: Float = TriWingWall.tipRadius - recess
    var fluteRows: [Int: [UInt32]] = [:]
    for i in 0..<n where inZone(i) {
        let q = cols[i]
        let phi: Float = q.tipAngle
        var ids: [UInt32] = []
        for z in rowsZ {
            let d: Float = TriWingWall.fluteDepth(tipAngle: phi, z: z)
            let h: Float = 0.0004
            let ds: Float = (TriWingWall.fluteDepth(tipAngle: phi + h, z: z) - TriWingWall.fluteDepth(tipAngle: phi - h, z: z)) / (2 * h * rf)
            let hz: Float = 0.0004
            let dz: Float = (TriWingWall.fluteDepth(tipAngle: phi, z: z + hz) - TriWingWall.fluteDepth(tipAngle: phi, z: max(z - hz, 0) )) / (z + hz - max(z - hz, 0))
            let t: V3 = tangent(i)
            let nor: V3 = simd_normalize(V3(q.n.x + ds * t.x, q.n.y + ds * t.y, dz))
            ids.append(flute.v(pos(i, recess + d, z), nor, V2(q.s * twWallUVPerR, z * twWallUVPerR), tan: t))
        }
        fluteRows[i] = ids
    }
    for i in 0..<n {
        let j: Int = (i + 1) % n
        guard let a = fluteRows[i], let b = fluteRows[j] else { continue }
        var r: Int = 0
        while r + 1 < rowsZ.count {
            flute.quad(a[r], b[r], b[r + 1], a[r + 1])
            r += 1
        }
    }
    acc.add(flute, .waistFlute)

    // Windows: polished frame (a bevel down to the lens plane) and the lens, in the lens colour of the window's wing.
    let pocket: Float = TriWingWall.windowPocketDepth
    let fw: Float = TriWingWall.windowFrameWidth
    for w in wins {
        let m: Int = w.halfColumns
        let sc: Float = cols[w.centre].s
        let lw: Float = w.halfLength
        let hw: Float = w.halfHeight
        let li: Float = lw - fw
        let hi: Float = hw - fw
        func point(_ s: Float, _ z: Float, _ a: Float) -> (p: V3, n: V3) {
            let q = TriWingWall.sample(at: s)
            return (V3(q.p.x - q.n.x * a, q.p.y - q.n.y * a, z), V3(q.n.x, q.n.y, 0))
        }
        var outer: [V3] = []
        var inner: [V3] = []
        var innerZ: [Float] = []
        var offs: [Float] = []
        var k: Int = -m
        while k <= m {
            let i: Int = w.centre + k
            let off: Float = cols[i].s - sc
            let z: Float = TriWingWall.stadiumHalfHeight(offset: off, halfLength: lw, halfHeight: hw)
            outer.append(pos(i, recess, z))
            let zi: Float = z * hi / hw
            innerZ.append(zi)
            let offIn: Float = off * li / lw
            offs.append(offIn)
            inner.append(point(sc + offIn, zi, recess + pocket).p)
            k += 1
        }
        var frame = MB()
        var q: Int = 0
        while q + 1 < outer.count {
            let p0: V3 = outer[q], p1: V3 = outer[q + 1], p2: V3 = inner[q + 1], p3: V3 = inner[q]
            var nor: V3 = simd_cross(p2 - p0, p3 - p1)
            let len: Float = simd_length(nor)
            if len > 1e-12 {
                nor = nor / len
                let mid: P2 = TriWingWall.sample(at: sc + (offs[q] + offs[q + 1]) * 0.5).n
                if simd_dot(nor, V3(mid.x, mid.y, 0)) < 0 { nor = -nor }
                let tan: V3 = simd_normalize(p1 - p0)
                let a = frame.v(p0, nor, V2(0, 0), tan: tan)
                let b = frame.v(p1, nor, V2(1, 0), tan: tan)
                let cc = frame.v(p2, nor, V2(1, 1), tan: tan)
                let d = frame.v(p3, nor, V2(0, 1), tan: tan)
                frame.quad(a, b, cc, d)
            }
            q += 1
        }
        acc.add(frame, .windowFrame)
        // Lens: a grid over the inner outline (columns follow the window's, rows from the mid plane up to the inner edge).
        var lens = MB()
        let rows: Int = 4
        var grid: [[UInt32]] = []
        var idx: Int = 0
        while idx < inner.count {
            var col: [UInt32] = []
            var r: Int = 0
            while r <= rows {
                let z: Float = innerZ[idx] * Float(r) / Float(rows)
                let pt = point(sc + offs[idx], z, recess + pocket)
                let u: Float = (offs[idx] + li) / (2 * li)
                col.append(lens.v(pt.p, pt.n, V2(u, innerZ[idx] > 0 ? z / hi : 0), tan: V3(-pt.n.y, pt.n.x, 0)))
                r += 1
            }
            grid.append(col)
            idx += 1
        }
        idx = 0
        while idx + 1 < grid.count {
            var r: Int = 0
            while r < rows {
                lens.quad(grid[idx][r], grid[idx + 1][r], grid[idx + 1][r + 1], grid[idx][r + 1])
                r += 1
            }
            idx += 1
        }
        acc.add(lens, .windowLens(w.wing))
    }
}

private func fluteTopRow() -> Float { TriWingWall.fluteHalfHeight + TriWingWall.fluteRunOut }
