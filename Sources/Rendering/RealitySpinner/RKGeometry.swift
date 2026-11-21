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
// CPU-only puck geometry . No RealityKit, safe off the main thread.
import Foundation
import simd

import simd
import Foundation

typealias V3 = SIMD3<Float>
typealias V2 = SIMD2<Float>

/// CPU mesh accumulator. `tri` fixes winding from the supplied vertex normals, so winding bugs cannot happen.
struct MB {
    var p: [V3] = [], n: [V3] = [], uv: [V2] = [], t: [V3] = [], b: [V3] = []
    var idx: [UInt32] = []
    var triCount: Int { idx.count / 3 }

    @discardableResult
    @_optimize(speed)
    mutating func v(_ pos: V3, _ nor: V3, _ uv: V2, tan: V3 = V3(1, 0, 0)) -> UInt32 {
        p.append(pos); n.append(nor); self.uv.append(uv); t.append(tan)
        // bitangent = n x t (right-handed frame)
        b.append(simd_normalize(simd_cross(nor, tan)))
        return UInt32(p.count - 1)
    }
    @_optimize(speed)
    mutating func tri(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
        let pa = p[Int(a)], pb = p[Int(b)], pc = p[Int(c)]
        let g = simd_cross(pb - pa, pc - pa)
        if simd_length_squared(g) < 1e-14 { return }            // degenerate
        let nn = n[Int(a)] + n[Int(b)] + n[Int(c)]
        if simd_dot(g, nn) >= 0 { idx += [a, b, c] } else { idx += [a, c, b] }
    }
    @_optimize(speed)
    mutating func quad(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) { tri(a, b, c); tri(a, c, d) }

    @_optimize(speed)
    mutating func append(_ o: MB, transform m: simd_float4x4, normalMatrix nm: simd_float3x3) {
        let base = UInt32(p.count)
        for i in 0..<o.p.count {
            let q = m * V4(o.p[i], 1)
            p.append(V3(q.x, q.y, q.z))
            n.append(simd_normalize(nm * o.n[i])); uv.append(o.uv[i])
            t.append(simd_normalize(nm * o.t[i])); b.append(simd_normalize(nm * o.b[i]))
        }
        idx += o.idx.map { $0 + base }
    }

}
typealias V4 = SIMD4<Float>

/// Angle of sample `j` of `seg` around a full turn: ((j / seg) * 2) * pi, evaluated in that order.
@inline(__always)
func turnAngle(_ j: Int, of seg: Int) -> Float {
    let jf: Float = Float(j)
    let sf: Float = Float(seg)
    let frac: Float = jf / sf
    let doubled: Float = frac * 2
    return doubled * Float.pi
}

struct ProfilePt { var r: Float; var z: Float; var nr: Float; var nz: Float; var v: Float = 0 }

/// Lathe around +Z. Rows = profile points, columns = angle samples.
@_optimize(speed)
func lathe(_ prof: [ProfilePt], seg: Int, uScale: Float = 1) -> MB {
    var m = MB()
    var rows: [[UInt32]] = []
    for pp in prof {
        var row: [UInt32] = []
        for j in 0...seg {
            let th: Float = turnAngle(j, of: seg)
            let c: Float = cos(th)
            let s: Float = sin(th)
            let pos = V3(pp.r * c, pp.r * s, pp.z)
            let rawNormal = V3(pp.nr * c, pp.nr * s, pp.nz)
            let nor: V3 = simd_normalize(rawNormal)
            let jFrac: Float = Float(j) / Float(seg)
            let uvCoord = V2(jFrac * uScale, pp.v)
            let tangent = V3(-s, c, 0)
            row.append(m.v(pos, nor, uvCoord, tan: tangent))
        }
        rows.append(row)
    }
    for i in 0..<(prof.count - 1) {
        for j in 0..<seg { m.quad(rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]) }
    }
    return m
}

/// Flat annulus at height z with normal (0,0,nz); planar uv over the unit square [-1,1]^2.
@_optimize(speed)
func annulus(r0: Float, r1: Float, z: Float, nz: Float, seg: Int, rings: Int) -> MB {
    var m = MB()
    var rows: [[UInt32]] = []
    for i in 0...rings {
        let radialSpan: Float = r1 - r0
        let radialScaled: Float = radialSpan * Float(i)
        let r: Float = r0 + radialScaled / Float(rings)
        var row: [UInt32] = []
        for j in 0...seg {
            let th: Float = turnAngle(j, of: seg)
            let cosTh: Float = cos(th)
            let sinTh: Float = sin(th)
            let x: Float = r * cosTh
            let y: Float = r * sinTh
            let uvX: Float = x * 0.5 + 0.5
            let uvY: Float = 0.5 + y * 0.5
            row.append(m.v(V3(x, y, z), V3(0, 0, nz), V2(uvX, uvY), tan: V3(-sinTh, cosTh, 0)))
        }
        rows.append(row)
    }
    for i in 0..<rings { for j in 0..<seg { m.quad(rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]) } }
    return m
}

/// Tube with hemispherical caps along a centerline polyline. `up` fixes the cross-section frame.
@_optimize(speed)
func capsulePath(center: [V3], radius: Float, up: V3, around: Int = 14, capRings: Int = 6) -> MB {
    var m = MB()
    let n = center.count
    @_optimize(speed)
    func tangent(_ i: Int) -> V3 {
        let a = center[max(i - 1, 0)], b = center[min(i + 1, n - 1)]
        return simd_normalize(b - a)
    }
    struct Ring { var c: V3; var t: V3; var rad: Float; var sph: V3? }  // sph = sphere center for cap rings
    var rings: [Ring] = []
    // start cap (from tip to body)
    let t0 = tangent(0)
    for k in stride(from: capRings, through: 1, by: -1) {
        let phFrac: Float = Float(k) / Float(capRings)
        let halfPi: Float = Float.pi / 2
        let ph: Float = phFrac * halfPi
        let sweepBack: V3 = t0 * radius * sin(ph)
        let ringCenter: V3 = center[0] - sweepBack
        let ringRadius: Float = radius * cos(ph)
        rings.append(Ring(c: ringCenter, t: t0, rad: ringRadius, sph: center[0]))
    }
    for i in 0..<n { rings.append(Ring(c: center[i], t: tangent(i), rad: radius, sph: nil)) }
    let t1 = tangent(n - 1)
    for k in 1...capRings {
        let phFrac: Float = Float(k) / Float(capRings)
        let halfPi: Float = Float.pi / 2
        let ph: Float = phFrac * halfPi
        let sweepFwd: V3 = t1 * radius * sin(ph)
        let ringCenter: V3 = center[n - 1] + sweepFwd
        let ringRadius: Float = radius * cos(ph)
        rings.append(Ring(c: ringCenter, t: t1, rad: ringRadius, sph: center[n - 1]))
    }
    // tip points (radius 0) are degenerate rings: fine (degenerate tris are skipped).
    var grid: [[UInt32]] = []
    for rg in rings {
        let upAlong: Float = simd_dot(up, rg.t)
        var e1: V3 = up - rg.t * upAlong
        e1 = simd_normalize(e1)
        let e2 = simd_cross(rg.t, e1)
        var row: [UInt32] = []
        for j in 0...around {
            let a: Float = turnAngle(j, of: around)
            let dirA: V3 = cos(a) * e1
            let dirB: V3 = sin(a) * e2
            let dir: V3 = dirA + dirB
            let pos: V3 = rg.c + dir * rg.rad
            let nor: V3
            if let s = rg.sph { nor = simd_normalize(pos - s) } else { nor = dir }
            var finalNormal: V3 = dir
            if simd_length(nor) > 0 { finalNormal = nor }
            let uvCoord = V2(Float(j) / Float(around), 0)
            row.append(m.v(pos, finalNormal, uvCoord, tan: rg.t))
        }
        grid.append(row)
    }
    for i in 0..<(grid.count - 1) { for j in 0..<around { m.quad(grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]) } }
    return m
}

/// Flat stroke mesh (stadium) between two 2D points at height function z(x,y).
@_optimize(speed)
func addRKStroke(_ m: inout MB, a: V2, b: V2, w: Float, z: (V2) -> Float, nz: Float = 1) {
    let d = b - a
    let L = simd_length(d)
    let dir = L > 1e-9 ? d / L : V2(1, 0)
    let nrm = V2(-dir.y, dir.x)
    let h = w / 2
    @_optimize(speed)
    func vert(_ q: V2) -> UInt32 { m.v(V3(q.x, q.y, z(q)), V3(0, 0, nz), V2(0, 0)) }
    let q0 = vert(a + nrm * h), q1 = vert(b + nrm * h), q2 = vert(b - nrm * h), q3 = vert(a - nrm * h)
    m.quad(q0, q1, q2, q3)
    for c in [a, b] {
        let cv = vert(c)
        let steps = 14
        let zeroAngle: Float = 0
        let startOffset: V2 = V2(cos(zeroAngle), sin(zeroAngle)) * h
        var prev = vert(c + startOffset)
        for k in 1...steps {
            let t: Float = turnAngle(k, of: steps)
            let rim: V2 = V2(cos(t), sin(t)) * h
            let cur = vert(c + rim)
            m.tri(cv, prev, cur)
            prev = cur
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Pocket / strip machinery. Domain is (w, t): w = row coordinate (radius for faces, z for the wall),
// t = angular coordinate. A pocket is a capsule hole whose half-width in t at row w is hw(w).
// ---------------------------------------------------------------------------------------------

struct VertexInfo { var pos: V3; var nor: V3; var uv: V2; var tan: V3 }

/// One strip of the patch: rows (w, t0, t1); each row gets m+1 columns between t0 and t1.
@_optimize(speed)
func stripMesh(_ m: inout MB, rows: [(w: Float, t0: Float, t1: Float)], cols: Int, map: (Float, Float) -> VertexInfo) {
    var grid: [[UInt32]] = []
    for r in rows {
        var row: [UInt32] = []
        for j in 0...cols {
            let tSpan: Float = r.t1 - r.t0
            let tScaled: Float = tSpan * Float(j)
            let t: Float = r.t0 + tScaled / Float(cols)
            let vi = map(r.w, t)
            row.append(m.v(vi.pos, vi.nor, vi.uv, tan: vi.tan))
        }
        grid.append(row)
    }
    for i in 0..<(rows.count - 1) { for j in 0..<cols { m.quad(grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]) } }
}

/// Row sequence for one pocket family (same w-range): `extra` rows inside the range are added as active rows.
/// Returns (w, active hw or nil), with duplicated entry/exit rows so patches meet the pocket outline exactly.
@_optimize(speed)
func pocketRowSeq(wc: Float, rad: Float, K: Int, hwAt: (Float) -> Float, extra: [Float]) -> [(w: Float, hw: Float?)] {
    var ws: [Float] = []
    for k in 0...K {
        let angle: Float = Float.pi * Float(k) / Float(K)
        let offset: Float = rad * cos(angle)
        ws.append(wc - offset)
    }
    let lowLimit: Float = ws[0] + 1e-5
    let highLimit: Float = ws[K] - 1e-5
    for e in extra where e > lowLimit && e < highLimit { ws.append(e) }
    ws.sort()
    var seq: [(w: Float, hw: Float?)] = []
    seq.append((ws[0], nil))
    for (i, w) in ws.enumerated() {
        let hw: Float = hwAt(w)
        seq.append((w, hw))
    }
    seq.append((ws[ws.count - 1], nil))
    return seq
}

/// Interior of a pocket: floor + walls. rows are the ACTIVE rows (hw non-nil) of the pocket.
@_optimize(speed)
func pocketInterior(_ m: inout MB, rows: [(w: Float, hw: Float)], tc: Float, M: Int = 10,
                    rim: (Float, Float) -> V3, floor: (Float, Float) -> V3, floorN: (Float, Float) -> V3) {
    @_optimize(speed)
    func fv(_ w: Float, _ t: Float) -> UInt32 { m.v(floor(w, t), floorN(w, t), V2(0, 0)) }
    var grid: [[UInt32]] = []
    for r in rows {
        var row: [UInt32] = []
        for j in 0...M {
            let tOffset: Float = 2 * r.hw * Float(j) / Float(M)
            let tCol: Float = tc - r.hw + tOffset
            row.append(fv(r.w, tCol))
        }
        grid.append(row)
    }
    for i in 0..<(rows.count - 1) { for j in 0..<M { m.quad(grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]) } }
    let inside = floor(rows[rows.count / 2].w, tc)
    @_optimize(speed)
    func wallQuad(_ a: V3, _ b: V3, _ fb: V3, _ fa: V3) {
        var n = simd_cross(b - a, fa - a)
        if simd_length_squared(n) < 1e-16 { return }
        n = simd_normalize(n)
        if simd_dot(n, inside - a) < 0 { n = -n }
        let ia = m.v(a, n, V2(0, 0)), ib = m.v(b, n, V2(0, 0)), ic = m.v(fb, n, V2(0, 0)), id = m.v(fa, n, V2(0, 0))
        m.quad(ia, ib, ic, id)
    }
    for i in 0..<(rows.count - 1) {
        let a = rows[i], b = rows[i + 1]
        let signs: [Float] = [-1, 1]
        for sgn in signs {
            let ta: Float = tc + sgn * a.hw
            let tb: Float = tc + sgn * b.hw
            wallQuad(rim(a.w, ta), rim(b.w, tb), floor(b.w, tb), floor(a.w, ta))
        }
    }
    let edgeRows: [(w: Float, hw: Float)] = [rows[0], rows[rows.count - 1]]
    for r in edgeRows {
        for j in 0..<M {
            let off0: Float = 2 * r.hw * Float(j) / Float(M)
            let off1: Float = 2 * r.hw * Float(j + 1) / Float(M)
            let t0: Float = tc - r.hw + off0
            let t1: Float = tc - r.hw + off1
            wallQuad(rim(r.w, t0), rim(r.w, t1), floor(r.w, t1), floor(r.w, t0))
        }
    }
}

@_optimize(speed)
func flatTri(_ m: inout MB, _ a: V3, _ b: V3, _ c: V3, outward: V3) {
    var n = simd_cross(b - a, c - a)
    if simd_length_squared(n) < 1e-16 { return }
    n = simd_normalize(n)
    if simd_dot(n, outward) < 0 { n = -n }
    let crossUp: V3 = simd_cross(n, V3(0, 0, 1))
    let tangentRaw: V3 = crossUp + V3(1e-4, 0, 0)
    let t: V3 = simd_normalize(tangentRaw)
    let ia = m.v(a, n, V2(0, 0), tan: t)
    let ib = m.v(b, n, V2(0, 0), tan: t)
    let ic = m.v(c, n, V2(0, 0), tan: t)
    m.tri(ia, ib, ic)
}

/// Flat ribbon along `path`; `across(i)` gives the unit across-direction at path point i. uv.x runs along the path (0..1), uv.y across (0..1).
@_optimize(speed)
func ribbon(path: [V3], across: (Int) -> V3, halfWidth: Float, normal: (Int) -> V3) -> MB {
    var m = MB()
    var a: [UInt32] = [], b: [UInt32] = []
    let n = path.count - 1
    for i in 0...n {
        let u: Float = Float(i) / Float(n)
        let next: Int = min(i + 1, n)
        let prevIdx: Int = max(i - 1, 0)
        let t: V3 = simd_normalize(path[next] - path[prevIdx])
        let acrossDir: V3 = across(i)
        let nrm: V3 = normal(i)
        let offset: V3 = acrossDir * halfWidth
        a.append(m.v(path[i] + offset, nrm, V2(u, 1), tan: t))
        b.append(m.v(path[i] - offset, nrm, V2(u, 0), tan: t))
    }
    for i in 0..<n { m.quad(a[i], a[i + 1], b[i + 1], b[i]) }
    return m
}

// ---- dimensions (R = 1) ----
enum D {
    static let hW: Float = 0.16            // half thickness of outer wheel
    static let hWeb: Float = 0.09          // half thickness of web
    static let rWheelIn: Float = 0.62
    static let rWebIn: Float = 0.38
    static let cham: Float = 0.03
    static let grooveZ: Float = 0.07       // groove distance from face
    static let grooveHalf: Float = 0.011
    static let hubR: Float = 0.36
    static let hubTop: Float = 0.18        // 0.02 above face
    static let hubDome: Float = 0.008
    static let tubeR: [Float] = [0.69, 0.75, 0.81, 0.87]
    static let slitInner: Float = 0.42, slitOuter: Float = 0.57, slitSweep: Float = 0.2443, slitW: Float = 0.022
    static let slitCount = 12
    static let slitOffset: Float = 0.2
    static let knurlFlutes: Float = 96
    static let bandHalf: Float = hW - cham - grooveZ - grooveHalf   // placeholder, recomputed below
}
let kDelta: Float = Float.pi / 100                    // half pitch of the knurl lattice (100 flutes)
let bandHalfZ: Float = 2.5 * kDelta                  // 0.0785: knurl band half height = 2.5 lattice rows

let tubeColors: [V3] = [V3(0.25, 1.0, 0.45), V3(0.30, 0.75, 1.0), V3(1.0, 0.50, 0.12), V3(0.65, 0.35, 1.0)]
let slotAngles: [Float] = {
    var angles: [Float] = []
    let base: Float = 22.5 * Float.pi / 180
    for i in 0..<8 {
        let step: Float = Float(i) * Float.pi / 4
        angles.append(base + step)
    }
    return angles
}()

// ---- web with 12 swept through-slits ----
struct SlitGeom {
    let h = D.slitW / 2
    let N = 700
    var cl: [V2] = []
    /// Segments are grouped in blocks of `blockSize`; each block carries a bounding circle (centre, radius) so a query can
    /// skip every block that cannot hold the nearest point. Exact (a block is skipped only when its circle is farther than
    /// the best distance found so far); the brute-force scan over 700 segments was the dominant cost of the web mesh.
    static let blockSize = 20
    var blockCenter: [V2] = []
    var blockRadius: [Float] = []
    @_optimize(speed)
    init() {
        for i in 0...N {
            let t = Float(i) / Float(N)
            let radialSpan: Float = D.slitOuter - D.slitInner
            let r: Float = D.slitInner + radialSpan * t
            let a: Float = D.slitSweep * t
            cl.append(V2(r * cos(a), r * sin(a)))
        }
        var first = 0
        while first < N {
            let last: Int = min(first + Self.blockSize, N)       // points first...last
            var sum = V2(0, 0)
            for i in first...last { sum += cl[i] }
            let center: V2 = sum / Float(last - first + 1)
            var radius: Float = 0
            for i in first...last { radius = max(radius, simd_length(cl[i] - center)) }
            blockCenter.append(center)
            blockRadius.append(radius * 1.0001 + 1e-6)
            first = last
        }
    }
    @_optimize(speed)
    func nearest(_ p: V2) -> (d: Float, q: V2) {
        var best: Float = 1e9; var bq = cl[0]
        let blocks: Int = blockCenter.count
        var lower = [Float](repeating: 0, count: blocks)
        for b in 0..<blocks { lower[b] = simd_length(p - blockCenter[b]) - blockRadius[b] }
        var done = [Bool](repeating: false, count: blocks)
        for _ in 0..<blocks {
            var pick = -1
            var pickLower: Float = 1e30
            for b in 0..<blocks where !done[b] && lower[b] < pickLower { pick = b; pickLower = lower[b] }
            if pick < 0 || pickLower >= best { break }
            done[pick] = true
            let first: Int = pick * Self.blockSize
            let last: Int = min(first + Self.blockSize, N)
            for i in first..<last {
                let a: V2 = cl[i]
                let b: V2 = cl[i + 1]
                let ab: V2 = b - a
                let proj: Float = simd_dot(p - a, ab) / simd_dot(ab, ab)
                let t: Float = max(0, min(1, proj))
                let q: V2 = a + ab * t
                let d: Float = simd_length(p - q)
                if d < best { best = d; bq = q }
            }
        }
        return (best, bq)
    }
    /// True when some point of the centre line is within `limit` of `p` (same answer as `nearest(p).d <= limit`).
    @_optimize(speed)
    func within(_ p: V2, _ limit: Float) -> Bool {
        let blocks: Int = blockCenter.count
        for blk in 0..<blocks {
            let lower: Float = simd_length(p - blockCenter[blk]) - blockRadius[blk]
            if lower > limit { continue }
            let first: Int = blk * Self.blockSize
            let last: Int = min(first + Self.blockSize, N)
            for i in first..<last {
                let a: V2 = cl[i]
                let b: V2 = cl[i + 1]
                let ab: V2 = b - a
                let proj: Float = simd_dot(p - a, ab) / simd_dot(ab, ab)
                let t: Float = max(0, min(1, proj))
                let q: V2 = a + ab * t
                let d: Float = simd_length(p - q)
                if d <= limit { return true }
            }
        }
        return false
    }
    @_optimize(speed)
    func inside(_ rho: Float, _ phi: Float) -> Bool {
        let point = V2(rho * cos(phi), rho * sin(phi))
        let slack: Float = 1 + 1e-6
        let limit: Float = h * slack
        return within(point, limit)
    }
    /// angular interval (relative to slit angle 0) at radius rho, nil if outside the slit
    @_optimize(speed)
    func interval(_ rho: Float) -> (lo: Float, hi: Float)? {
        let tIn: Float = D.slitInner - h
        let tOut: Float = D.slitOuter + h
        let rawT: Float = (rho - D.slitInner) / (D.slitOuter - D.slitInner)
        let t: Float = max(0, min(1, rawT))
        let phic: Float = D.slitSweep * t
        let lowEdge: Float = tIn + 1e-6
        let highEdge: Float = tOut - 1e-6
        if rho <= lowEdge || rho >= highEdge {
            var edgeAngle: Float = D.slitSweep
            if rho < D.slitInner { edgeAngle = 0 }
            return (edgeAngle, edgeAngle)
        }
        if !inside(rho, phic) { return nil }
        var a = phic, b = phic + 0.6      // a inside, b outside
        for _ in 0..<45 { let m = (a + b) / 2; if inside(rho, m) { a = m } else { b = m } }
        let hi = a
        a = phic; b = phic - 0.6
        for _ in 0..<45 { let m = (a + b) / 2; if inside(rho, m) { a = m } else { b = m } }
        return (a, hi)
    }
}

@_optimize(speed)
func buildWeb() -> (faceTop: MB, faceBot: MB, walls: MB) {
    let g = SlitGeom()
    let K: Int = D.slitCount
    let m: Int = 4
    let tIn: Float = D.slitInner - g.h
    let tOut: Float = D.slitOuter + g.h
    var radii: [Float] = []
    for i in 0..<6 {
        let span: Float = tIn - D.rWebIn
        let scaled: Float = span * Float(i)
        radii.append(D.rWebIn + scaled / 6)
    }
    let nz = 170
    for j in 0...nz {
        let angle: Float = Float.pi * Float(j) / Float(nz)
        let rise: Float = 1 - cos(angle)
        let span: Float = tOut - tIn
        let scaled: Float = span * rise
        radii.append(tIn + scaled / 2)
    }
    for i in 1...6 {
        let span: Float = D.rWheelIn - tOut
        let scaled: Float = span * Float(i)
        radii.append(tOut + scaled / 6)
    }
    let lowCut: Float = tIn + 1e-6
    let highCut: Float = tOut - 1e-6
    var iv: [(lo: Float, hi: Float)] = []
    for rho in radii {
        if rho < lowCut {
            iv.append((lo: 0, hi: 0))
        } else if rho > highCut {
            iv.append((lo: D.slitSweep, hi: D.slitSweep))
        } else if let found = g.interval(rho) {
            iv.append(found)
        } else {
            iv.append((lo: 0, hi: 0))
        }
    }
    var th: [Float] = []
    for i in 0..<K {
        let turn: Float = Float(i) * 2 * Float.pi / Float(K)
        th.append(D.slitOffset + turn)
    }
    var faces: [MB] = [MB(), MB()]
    var walls = MB()
    for side in 0..<2 {
        let z: Float = side == 0 ? D.hWeb : -D.hWeb, nzv: Float = side == 0 ? 1 : -1
        for k in 0..<K {
            var grid: [[UInt32]] = []
            for (i, rho) in radii.enumerated() {
                let a0: Float = th[k] + iv[i].hi
                let wrap: Float = (k + 1 == K) ? Float.pi * 2 : 0
                let a1: Float = th[(k + 1) % K] + wrap + iv[i].lo
                var row: [UInt32] = []
                for j in 0...m {
                    let aSpan: Float = a1 - a0
                    let aScaled: Float = aSpan * Float(j)
                    let a: Float = a0 + aScaled / Float(m)
                    let x: Float = rho * cos(a)
                    let y: Float = rho * sin(a)
                    let uvX: Float = x * 0.5 + 0.5
                    let uvY: Float = 0.5 + y * 0.5
                    let tangent: V3 = simd_normalize(V3(-y, x, 0))
                    row.append(faces[side].v(V3(x, y, z), V3(0, 0, nzv), V2(uvX, uvY), tan: tangent))
                }
                grid.append(row)
            }
            for i in 0..<(radii.count - 1) { for j in 0..<m {
                faces[side].quad(grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]) } }
        }
    }
    // slit walls along both edges of every slit (shared by both faces)
    let iStart = 6, iEnd = 6 + nz
    for k in 0..<K {
        for edge in 0..<2 {   // 0 = hi side, 1 = lo side
            var tops: [UInt32] = [], bots: [UInt32] = []
            for i in iStart...iEnd {
                let edgeOffset: Float = (edge == 0) ? iv[i].hi : iv[i].lo
                let a: Float = th[k] + edgeOffset
                let rho: Float = radii[i]
                let p = V2(rho * cos(a), rho * sin(a))
                // normal: toward slit centerline (rotate into slit-0 frame)
                let negTh: Float = -th[k]
                let ca: Float = cos(negTh)
                let sa: Float = sin(negTh)
                let plX: Float = ca * p.x - sa * p.y
                let plY: Float = sa * p.x + ca * p.y
                let pl = V2(plX, plY)
                let q: V2 = g.nearest(pl).q
                var dn: V2 = q - pl
                if simd_length(dn) < 1e-7 {
                    let edgeSign: Float = (edge == 0) ? -1 : 1
                    let turned: Float = a + edgeSign * Float.pi / 2
                    dn = V2(cos(turned), sin(turned))
                }
                dn = simd_normalize(dn)
                let cb: Float = cos(th[k])
                let sb: Float = sin(th[k])
                let nwX: Float = cb * dn.x - sb * dn.y
                let nwY: Float = sb * dn.x + cb * dn.y
                let nw = V3(nwX, nwY, 0)
                let uvU: Float = Float(i) / 100
                tops.append(walls.v(V3(p.x, p.y, D.hWeb), nw, V2(uvU, 0), tan: V3(0, 0, 1)))
                bots.append(walls.v(V3(p.x, p.y, -D.hWeb), nw, V2(uvU, 1), tan: V3(0, 0, 1)))
            }
            for i in 0..<(tops.count - 1) { walls.quad(tops[i], tops[i + 1], bots[i + 1], bots[i]) }
        }
    }
    return (faces[0], faces[1], walls)
}

// ---- wheel outline ----
@_optimize(speed)
func normal2(_ a: (Float, Float), _ b: (Float, Float)) -> (Float, Float) {   // outward-right-hand of segment a->b in (r,z), caller picks sign
    let dr: Float = b.0 - a.0
    let dz: Float = b.1 - a.1
    let sumSq: Float = dr * dr + dz * dz
    let l: Float = sqrt(sumSq)
    return (dz / l, -dr / l)
}
@_optimize(speed)
func flank(_ pts: [(Float, Float)], sign: Float, v0: Float = 0, v1: Float = 1) -> [ProfilePt] {
    var out: [ProfilePt] = []
    for (i, p) in pts.enumerated() {
        let a = pts[max(i - 1, 0)], b = pts[min(i + 1, pts.count - 1)]
        let n = normal2(a, b)
        let vSpan: Float = v1 - v0
        let vScaled: Float = vSpan * Float(i)
        let vDen: Float = Float(max(pts.count - 1, 1))
        let vCoord: Float = v0 + vScaled / vDen
        out.append(ProfilePt(r: p.0, z: p.1, nr: n.0 * sign, nz: n.1 * sign, v: vCoord))
    }
    return out
}

@_optimize(speed)
func mirrorZ(_ p: [ProfilePt]) -> [ProfilePt] {
    var out: [ProfilePt] = []
    for q in p { out.append(ProfilePt(r: q.r, z: -q.z, nr: q.nr, nz: -q.nz, v: q.v)) }
    return out
}

@_optimize(speed)
func domeZ(_ r: Float) -> Float {
    let ratio: Float = r / 0.33
    let drop: Float = D.hubDome * ratio * ratio
    return D.hubTop - drop
}

// ---- pockets (rod slots) ----
let pockHs: Float = 0.062, pockRad: Float = 0.026, pockDepth: Float = 0.024        // face pockets
let wPockHs: Float = 0.080, wPockRad: Float = 0.026, wPockDepth: Float = 0.030      // wall pockets
let rodCoreR: Float = 0.0115, rodShellR: Float = 0.0185
let winHalfCols: Float = 4.5                                                          // plate half width in lattice columns
let knurlDepth: Float = 0.016
@_optimize(speed)
func crownR(_ z: Float) -> Float {
    let ratio: Float = z / bandHalfZ
    let drop: Float = 0.006 * ratio * ratio
    return 1.0 - drop
}
@_optimize(speed)
func ctrim(_ x: Float) -> Float { max(-1, min(1, x)) }
@_optimize(speed)
func facePocketHw(_ c: Int) -> (Float) -> Float {
    let rc: Float = D.tubeR[c]
    let hsA: Float = pockHs / rc
    return { (rho: Float) -> Float in
        let sumSq: Float = rho * rho + rc * rc
        let numerator: Float = sumSq - pockRad * pockRad
        let denominator: Float = 2 * rho * rc
        let cosine: Float = ctrim(numerator / denominator)
        return hsA + acos(cosine)
    }
}
@_optimize(speed)
func wallPocketHw(_ z: Float) -> Float {
    let inner: Float = wPockRad * wPockRad - z * z
    let root: Float = sqrt(max(0, inner))
    return wPockHs + root
}
@_optimize(speed)
func knurlH(_ s: Float, _ z: Float) -> Float {
    @_optimize(speed)
    func tri(_ x: Float) -> Float {
        let f: Float = x - floor(x)
        let centered: Float = 2 * f - 1
        return 1 - abs(centered)
    }
    let p: Float = 2 * kDelta
    let plus: Float = tri((s + z) / p)
    let minus: Float = tri((s - z) / p)
    return min(plus, minus)
}
@_optimize(speed)
func knurlP(_ s: Float, _ z: Float, _ h: Float) -> V3 {
    let inset: Float = knurlDepth * (1 - h)
    let r: Float = crownR(z) - inset
    return V3(r * cos(s), r * sin(s), z)
}
@_optimize(speed)
func arcPath(r: Float, a: Float, half: Float, z: Float, n: Int = 14) -> [V3] {
    var pts: [V3] = []
    for i in 0...n {
        let frac: Float = Float(i) / Float(n)
        let centered: Float = frac * 2 - 1
        let t: Float = a + centered * half
        pts.append(V3(r * cos(t), r * sin(t), z))
    }
    return pts
}

let arcLevels = 16, arcSweepStep: Float = 0.1, arcHalfWidth: Float = 0.0165
let shutterSeconds: Float = 0.025                    // 1.5 frames at 60 fps
struct FaceBuild { var face: MB; var pockets: [MB] }

@_optimize(speed)
func buildFace(side: Float) -> FaceBuild {
    let z = side * D.hW
    struct Item { var first: Float; var rows: [(rho: Float, act: [Int: Float])] }
    var items: [Item] = []
    var blocks: [(lo: Float, hi: Float)] = []
    for c in 0..<4 {
        let rc: Float = D.tubeR[c]
        let seq = pocketRowSeq(wc: rc, rad: pockRad, K: 16, hwAt: facePocketHw(c), extra: [])
        var rows: [(rho: Float, act: [Int: Float])] = []
        for entry in seq {
            var active: [Int: Float] = [:]
            if let hwValue = entry.hw { active[c] = hwValue }
            rows.append((rho: entry.w, act: active))
        }
        items.append(Item(first: rows[0].rho, rows: rows))
        let blockLo: Float = rc - pockRad - 0.004
        let blockHi: Float = rc + pockRad + 0.004
        blocks.append((lo: blockLo, hi: blockHi))
    }
    var rho: Float = 0.62
    let rhoLimit: Float = 0.97 + 1e-4
    while rho < rhoLimit {
        let currentRho: Float = rho
        let blocked: Bool = blocks.contains(where: { (blk: (lo: Float, hi: Float)) -> Bool in
            currentRho > blk.lo && currentRho < blk.hi
        })
        if !blocked {
            let plainRow: [(rho: Float, act: [Int: Float])] = [(rho: rho, act: [:])]
            items.append(Item(first: rho, rows: plainRow))
        }
        rho += 0.04
    }
    let hasOuter: Bool = items.contains(where: { (item: Item) -> Bool in abs(item.first - 0.97) < 1e-5 })
    if !hasOuter {
        let outerRow: [(rho: Float, act: [Int: Float])] = [(rho: 0.97, act: [:])]
        items.append(Item(first: 0.97, rows: outerRow))
    }
    items.sort { (l: Item, r: Item) -> Bool in l.first < r.first }
    var rows: [(rho: Float, act: [Int: Float])] = []
    for item in items { rows.append(contentsOf: item.rows) }
    var face = MB()
    let cols = 48
    for j in 0..<8 {
        let aj: Float = Float(j) * Float.pi / 4
        let aj1: Float = Float(j + 1) * Float.pi / 4
        let cj: Int = j % 4
        let cj1: Int = (j + 1) % 4
        var rs: [(w: Float, t0: Float, t1: Float)] = []
        for r in rows {
            let inset0: Float = r.act[cj] ?? 0
            let inset1: Float = r.act[cj1] ?? 0
            rs.append((w: r.rho, t0: aj + inset0, t1: aj1 - inset1))
        }
        stripMesh(&face, rows: rs, cols: cols) { (rho: Float, t: Float) -> VertexInfo in
            let x: Float = rho * cos(t)
            let y: Float = rho * sin(t)
            let uvX: Float = x * 0.5 + 0.5
            let uvY: Float = y * 0.5 + 0.5
            return VertexInfo(pos: V3(x, y, z), nor: V3(0, 0, side), uv: V2(uvX, uvY), tan: V3(-sin(t), cos(t), 0))
        }
    }
    var pk = [MB](repeating: MB(), count: 4)
    for c in 0..<4 {
        let rc: Float = D.tubeR[c]
        let seq = pocketRowSeq(wc: rc, rad: pockRad, K: 16, hwAt: facePocketHw(c), extra: [])
        var act: [(w: Float, hw: Float)] = []
        for e in seq { if let hwValue = e.hw { act.append((w: e.w, hw: hwValue)) } }
        let floorZ: Float = z - side * pockDepth
        for j in stride(from: c, to: 8, by: 4) {
            let tc: Float = Float(j) * Float.pi / 4
            pocketInterior(&pk[c], rows: act, tc: tc,
                           rim: { (w: Float, t: Float) -> V3 in V3(w * cos(t), w * sin(t), z) },
                           floor: { (w: Float, t: Float) -> V3 in V3(w * cos(t), w * sin(t), floorZ) },
                           floorN: { (_: Float, _: Float) -> V3 in V3(0, 0, side) })
        }
    }
    return FaceBuild(face: face, pockets: pk)
}

struct WallBuild { var knurl: MB; var plate: MB; var pockets: [MB] }

@_optimize(speed)
func buildWall() -> WallBuild {
    var kn = MB(), pl = MB()
    var pk = [MB](repeating: MB(), count: 4)
    let b = bandHalfZ
    var latZ: [Float] = []
    for i in 0...5 {
        let drop: Float = Float(i) * kDelta
        latZ.append(b - drop)
    }
    // ---- lattice knurl (flat-shaded diamond pyramids), skipping window columns ----
    @_optimize(speed)
    func isWindowCell(_ i: Int) -> Bool {
        let m: Int = ((i % 25) + 25) % 25
        return m >= 8 && m <= 16
    }
    for i in 0..<200 where !isWindowCell(i) {
        for j in 0..<5 {
            let s0: Float = Float(i) * kDelta
            let s1: Float = Float(i + 1) * kDelta
            let zt: Float = latZ[j]
            let zb: Float = latZ[j + 1]
            let sc: Float = (s0 + s1) / 2
            let zc: Float = (zt + zb) / 2
            let hA: Float = knurlH(s0, zt)
            let hB: Float = knurlH(s1, zt)
            let hC: Float = knurlH(s1, zb)
            let hD: Float = knurlH(s0, zb)
            let hE: Float = knurlH(sc, zc)
            let A: V3 = knurlP(s0, zt, hA)
            let B: V3 = knurlP(s1, zt, hB)
            let C: V3 = knurlP(s1, zb, hC)
            let Dp: V3 = knurlP(s0, zb, hD)
            let E: V3 = knurlP(sc, zc, hE)
            let out = V3(cos(sc), sin(sc), 0)
            let edges: [(V3, V3)] = [(A, B), (B, C), (C, Dp), (Dp, A)]
            for (p, q) in edges { flatTri(&kn, p, q, E, outward: out) }
        }
        // skirts to the groove flank at both band edges
        let skirtEdges: [(Float, Float)] = [(latZ[0], 1), (latZ[5], -1)]
        for (zz, nz) in skirtEdges {
            let s0: Float = Float(i) * kDelta
            let s1: Float = Float(i + 1) * kDelta
            let h0: Float = knurlH(s0, zz)
            let h1: Float = knurlH(s1, zz)
            let p0: V3 = knurlP(s0, zz, h0)
            let p1: V3 = knurlP(s1, zz, h1)
            let q0: V3 = knurlP(s0, zz, 1)
            let q1: V3 = knurlP(s1, zz, 1)
            flatTri(&kn, p0, p1, q1, outward: V3(0, 0, nz)); flatTri(&kn, p0, q1, q0, outward: V3(0, 0, nz))
        }
    }
    // ---- window plates with pockets ----
    let seq = pocketRowSeq(wc: 0, rad: wPockRad, K: 14, hwAt: wallPocketHw, extra: latZ)
    var wrows: [(w: Float, hw: Float?)] = []
    for z in latZ where abs(z) > wPockRad + 1e-5 { wrows.append((z, nil)) }
    // merge: rows below pocket (z<-rad), the pocket sequence, rows above
    var below: [(w: Float, hw: Float?)] = []
    var above: [(w: Float, hw: Float?)] = []
    for r in wrows {
        if r.w < 0 { below.append(r) }
        if r.w > 0 { above.append(r) }
    }
    below.sort { (l: (w: Float, hw: Float?), r: (w: Float, hw: Float?)) -> Bool in l.w < r.w }
    above.sort { (l: (w: Float, hw: Float?), r: (w: Float, hw: Float?)) -> Bool in l.w < r.w }
    var allRows: [(w: Float, hw: Float?)] = below
    allRows.append(contentsOf: seq)
    allRows.append(contentsOf: above)
    for k in 0..<8 {
        let tc: Float = slotAngles[k]
        let c: Int = k % 4
        let plateHalf: Float = winHalfCols * kDelta
        let tl: Float = tc - plateHalf
        let tr: Float = tc + plateHalf
        var left: [(w: Float, t0: Float, t1: Float)] = []
        var right: [(w: Float, t0: Float, t1: Float)] = []
        for row in allRows {
            let halfWidth: Float = row.hw ?? 0
            left.append((w: row.w, t0: tl, t1: tc - halfWidth))
            right.append((w: row.w, t0: tc + halfWidth, t1: tr))
        }
        let map: (Float, Float) -> VertexInfo = { (z: Float, s: Float) -> VertexInfo in
            let r: Float = crownR(z)
            return VertexInfo(pos: V3(r * cos(s), r * sin(s), z), nor: V3(cos(s), sin(s), 0), uv: V2(0, 0), tan: V3(-sin(s), cos(s), 0))
        }
        stripMesh(&pl, rows: left, cols: 8, map: map)
        stripMesh(&pl, rows: right, cols: 8, map: map)
        // boundary walls dropping to the knurl profile
        var zs: [Float] = []
        for row in allRows { zs.append(row.w) }
        let boundaries: [(Float, Float)] = [(tl, -1), (tr, 1)]
        for (s, dirSign) in boundaries {
            for q in 0..<(zs.count - 1) where abs(zs[q + 1] - zs[q]) > 1e-6 {
                let za: Float = zs[q]
                let zb: Float = zs[q + 1]
                let ta: V3 = knurlP(s, za, 1)
                let tb: V3 = knurlP(s, zb, 1)
                let hA: Float = knurlH(s, za)
                let hB: Float = knurlH(s, zb)
                let ba: V3 = knurlP(s, za, hA)
                let bb: V3 = knurlP(s, zb, hB)
                let out: V3 = V3(-sin(s), cos(s), 0) * dirSign
                flatTri(&kn, ta, tb, bb, outward: out); flatTri(&kn, ta, bb, ba, outward: out)
            }
        }
        var act: [(w: Float, hw: Float)] = []
        for e in seq { if let hwValue = e.hw { act.append((w: e.w, hw: hwValue)) } }
        var seen = Set<Float>(); var arows: [(w: Float, hw: Float)] = []
        for a in act where !seen.contains(a.w) { seen.insert(a.w); arows.append(a) }
        pocketInterior(&pk[c], rows: arows, tc: tc,
                       rim: { (z: Float, s: Float) -> V3 in
                           let r: Float = crownR(z)
                           return V3(r * cos(s), r * sin(s), z)
                       },
                       floor: { (z: Float, s: Float) -> V3 in
                           let r: Float = crownR(z) - wPockDepth
                           return V3(r * cos(s), r * sin(s), z)
                       },
                       floorN: { (_: Float, s: Float) -> V3 in V3(cos(s), sin(s), 0) })
    }
    return WallBuild(knurl: kn, plate: pl, pockets: pk)
}

@_optimize(speed)
func planarUV(_ m: inout MB, span: Float) {
    for i in 0..<m.p.count {
        let u: Float = m.p[i].x / span + 0.5
        let v: Float = m.p[i].y / span + 0.5
        m.uv[i] = V2(u, v)
    }
}

// ---- parts ----
enum MatKind: Hashable {
    case faceBrushed, webSatin, chamfer, wallBand, groove, knurl, plate, cutWall, stepWall
    case hubDomeF, hubDomeB, hubChamfer, hubWall
    case pocket(Int), rodCore(Int), rodShell(Int)
    case faceOv, wallOv, webOv
}


/// One CPU mesh part with its material kind. Built off the main thread.
struct RKPartCPU { var mb: MB; var kind: MatKind; var name: String; var group: Int }   // group: 0 spin, 1 hub, 2 overlay
struct RKArcPart { var mb: MB; var material: UInt32; var name: String }
struct RKGeometryCPU {
    var parts: [RKPartCPU] = []
    var faceArcs: [[RKArcPart]] = [], wallArcs: [[RKArcPart]] = []
}

/// The whole puck mesh set as plain arrays (no RealityKit). Safe on any thread.
@_optimize(speed)
func buildPuckCPU() -> RKGeometryCPU {
    var out = RKGeometryCPU()
    @_optimize(speed)
    func add(_ m: MB, _ k: MatKind, _ name: String, hub: Bool = false) {
        if m.idx.isEmpty { return }
        out.parts.append(RKPartCPU(mb: m, kind: k, name: name, group: hub ? 1 : 0))
    }
    @_optimize(speed)
    func addOv(_ m: MB, _ k: MatKind, _ name: String) { out.parts.append(RKPartCPU(mb: m, kind: k, name: name, group: 2)) }
        let seg = 384
        let hW = D.hW
        // faces with pockets
        var pocketAcc = [MB](repeating: MB(), count: 4)
        let topBot: [(Float, String)] = [(1, "Top"), (-1, "Bot")]
        for (side, tag) in topBot {
            let fb = buildFace(side: side)
            add(fb.face, .faceBrushed, "face" + tag)
            for c in 0..<4 { pocketAcc[c].append(fb.pockets[c], transform: matrix_identity_float4x4, normalMatrix: matrix_identity_float3x3) }
        }
        let step = [ProfilePt(r: 0.62, z: hW, nr: -1, nz: 0, v: 0), ProfilePt(r: 0.62, z: D.hWeb, nr: -1, nz: 0, v: 1)]
        add(lathe(step, seg: seg), .stepWall, "stepTop"); add(lathe(mirrorZ(step), seg: seg), .stepWall, "stepBot")
        let inner = [ProfilePt(r: 0.38, z: D.hWeb, nr: -1, nz: 0, v: 0), ProfilePt(r: 0.38, z: -D.hWeb, nr: -1, nz: 0, v: 1)]
        add(lathe(inner, seg: seg), .stepWall, "webInner")
        let ch = [ProfilePt(r: 1 - D.cham, z: hW, nr: 0.7071, nz: 0.7071), ProfilePt(r: 1.0, z: hW - D.cham, nr: 0.7071, nz: 0.7071)]
        add(lathe(ch, seg: seg), .chamfer, "chTop"); add(lathe(mirrorZ(ch), seg: seg), .chamfer, "chBot")
        let zb0 = hW - D.cham, zg = hW - D.grooveZ + D.grooveHalf
        let band = [ProfilePt(r: 1, z: zb0, nr: 1, nz: 0, v: 0), ProfilePt(r: 1, z: zg, nr: 1, nz: 0, v: 1)]
        add(lathe(band, seg: seg), .wallBand, "bandTop"); add(lathe(mirrorZ(band), seg: seg), .wallBand, "bandBot")
        let zc = hW - D.grooveZ
        let crownEdge: Float = crownR(bandHalfZ)
        let g1 = flank([(1.0, zg), (0.989, zc)], sign: 1), g2 = flank([(0.989, zc), (crownEdge, bandHalfZ)], sign: 1)
        let grooveFlanks: [[ProfilePt]] = [g1, g2]
        for (i, f) in grooveFlanks.enumerated() { add(lathe(f, seg: seg), .groove, "g\(i)T"); add(lathe(mirrorZ(f), seg: seg), .groove, "g\(i)B") }
        // wall: relief knurl + plates + window pockets
        let wb = buildWall()
        add(wb.knurl, .knurl, "knurl"); add(wb.plate, .plate, "plate")
        for c in 0..<4 { pocketAcc[c].append(wb.pockets[c], transform: matrix_identity_float4x4, normalMatrix: matrix_identity_float3x3) }
        for c in 0..<4 { add(pocketAcc[c], .pocket(c), "pocket\(c)") }
        // web
        let web = buildWeb()
        add(web.faceTop, .webSatin, "webTop"); add(web.faceBot, .webSatin, "webBot")
        add(web.walls, .cutWall, "slitWalls")
        // rods: core + glass shell, one pair of meshes per colour
        for c in 0..<4 {
            var core = MB(), shell = MB()
            let rc = D.tubeR[c]
            let sides: [Float] = [1, -1]
            for side in sides {
                for j in stride(from: c, to: 8, by: 4) {
                    let a: Float = Float(j) * Float.pi / 4
                    let rodInset: Float = hW - 0.0025 - rodShellR
                    let zz: Float = side * rodInset
                    let path = arcPath(r: rc, a: a, half: pockHs / rc, z: zz)
                    core.append(capsulePath(center: path, radius: rodCoreR, up: V3(0, 0, 1)), transform: matrix_identity_float4x4, normalMatrix: matrix_identity_float3x3)
                    shell.append(capsulePath(center: path, radius: rodShellR, up: V3(0, 0, 1)), transform: matrix_identity_float4x4, normalMatrix: matrix_identity_float3x3)
                }
            }
            for s in stride(from: c, to: 8, by: 4) {
                let rr: Float = crownR(0) - 0.0025 - rodShellR
                let halfSweep: Float = wPockHs / rr
                let path = arcPath(r: rr, a: slotAngles[s], half: halfSweep, z: 0, n: 16)
                core.append(capsulePath(center: path, radius: rodCoreR, up: V3(0, 0, 1)), transform: matrix_identity_float4x4, normalMatrix: matrix_identity_float3x3)
                shell.append(capsulePath(center: path, radius: rodShellR, up: V3(0, 0, 1)), transform: matrix_identity_float4x4, normalMatrix: matrix_identity_float3x3)
            }
            add(core, .rodCore(c), "core\(c)"); add(shell, .rodShell(c), "shell\(c)")
        }

        // ---- blur layers: smeared overlays and arc meshes (see Rig.applyBlur) ----
        let ovSides: [(Float, String)] = [(1, "T"), (-1, "B")]
        for (side, tag) in ovSides {
            let faceZ: Float = side * (hW + 0.0007)
            let webZ: Float = side * (D.hWeb + 0.0007)
            let faceOuter: Float = 1.0 - D.cham
            addOv(annulus(r0: D.rWheelIn, r1: faceOuter, z: faceZ, nz: side, seg: seg, rings: 3), .faceOv, "faceOv" + tag)
            addOv(annulus(r0: D.rWebIn, r1: D.rWheelIn, z: webZ, nz: side, seg: seg, rings: 3), .webOv, "webOv" + tag)
        }
        var wprof: [ProfilePt] = []
        for i in 0...20 {
            let zDrop: Float = 2 * bandHalfZ * Float(i) / 20
            let z: Float = bandHalfZ - zDrop
            let bandSq: Float = bandHalfZ * bandHalfZ
            let dr: Float = -0.012 * z / bandSq
            let n: V2 = simd_normalize(V2(1, -dr))
            let wr: Float = crownR(z) + 0.0007
            let wv: Float = 1 - Float(i) / 20
            wprof.append(ProfilePt(r: wr, z: z, nr: n.x, nz: n.y, v: wv))
        }
        addOv(lathe(wprof, seg: 512), .wallOv, "wallOv")
        // arc levels: sweep = level * arcSweepStep radians
        for lv in 0..<arcLevels {
            let sweep = Float(lv) * arcSweepStep
            var fparts: [RKArcPart] = [], wparts: [RKArcPart] = []
            for c in 0..<4 {
                let rc = D.tubeR[c]
                var fm = MB()
                let baseHalf: Float = (pockHs + rodCoreR) / rc
                let half: Float = baseHalf + sweep / 2
                let faceSides: [Float] = [1, -1]
                for side in faceSides { for j in stride(from: c, to: 8, by: 4) {
                    let a: Float = Float(j) * Float.pi / 4
                    let n: Int = max(8, Int(half * 2 / 0.05))
                    let nF: Float = Float(n)
                    let arcZ: Float = side * (hW + 0.0014)
                    let faceAngle: (Int) -> Float = { (i: Int) -> Float in
                        let frac: Float = Float(i) / nF
                        let centered: Float = frac * 2 - 1
                        return a + centered * half
                    }
                    var path: [V3] = []
                    for i in 0...n {
                        let t: Float = faceAngle(i)
                        path.append(V3(rc * cos(t), rc * sin(t), arcZ))
                    }
                    let faceAcross: (Int) -> V3 = { (i: Int) -> V3 in
                        let t: Float = faceAngle(i)
                        return V3(cos(t), sin(t), 0)
                    }
                    let faceNormal: (Int) -> V3 = { (_: Int) -> V3 in V3(0, 0, side) }
                    fm.append(ribbon(path: path, across: faceAcross, halfWidth: arcHalfWidth, normal: faceNormal),
                              transform: matrix_identity_float4x4, normalMatrix: matrix_identity_float3x3)
                } }
                fparts.append(RKArcPart(mb: fm, material: UInt32(c), name: "arcF\(lv)_\(c)"))
                var wm = MB()
                let rr: Float = crownR(0) + 0.0014
                let wallBaseHalf: Float = (wPockHs + rodCoreR) / rr
                let halfW: Float = wallBaseHalf + sweep / 2
                for s in stride(from: c, to: 8, by: 4) {
                    let n: Int = max(10, Int(halfW * 2 / 0.04))
                    let slotAngle: Float = slotAngles[s]
                    let nF: Float = Float(n)
                    let arcAngle: (Int) -> Float = { (i: Int) -> Float in
                        let frac: Float = Float(i) / nF
                        let centered: Float = frac * 2 - 1
                        return slotAngle + centered * halfW
                    }
                    let path: [V3] = (0...n).map { (i: Int) -> V3 in
                        let t: Float = arcAngle(i)
                        return V3(rr * cos(t), rr * sin(t), 0)
                    }
                    let arcNormal: (Int) -> V3 = { (i: Int) -> V3 in
                        let t: Float = arcAngle(i)
                        return V3(cos(t), sin(t), 0)
                    }
                    wm.append(ribbon(path: path, across: { _ in V3(0, 0, 1) }, halfWidth: arcHalfWidth, normal: arcNormal),
                              transform: matrix_identity_float4x4, normalMatrix: matrix_identity_float3x3)
                }
                wparts.append(RKArcPart(mb: wm, material: UInt32(c), name: "arcW\(lv)_\(c)"))
            }
            out.faceArcs.append(fparts); out.wallArcs.append(wparts)
        }
        // ---- hub (fixed entity) ----
        func hubSide(_ sgn: Float, _ tag: String) {
            var dome: [ProfilePt] = []
            for i in 0...32 {
                let r: Float = 0.33 * Float(i) / 32
                let domeScale: Float = 0.33 * 0.33
                let dz: Float = -2 * D.hubDome * r / domeScale
                let n: V2 = simd_normalize(V2(-dz, 1))
                dome.append(ProfilePt(r: r, z: domeZ(r), nr: n.x, nz: n.y))
            }
            let rimZ: Float = domeZ(0.33)
            let wallTopZ: Float = rimZ - 0.02
            let cham: [ProfilePt] = [ProfilePt(r: 0.33, z: rimZ, nr: 0.5547, nz: 0.8321), ProfilePt(r: 0.36, z: wallTopZ, nr: 0.5547, nz: 0.8321)]
            let wallP: [ProfilePt] = [ProfilePt(r: 0.36, z: wallTopZ, nr: 1, nz: 0), ProfilePt(r: 0.36, z: 0, nr: 1, nz: 0)]
            let f: ([ProfilePt]) -> [ProfilePt] = { (pts: [ProfilePt]) -> [ProfilePt] in sgn > 0 ? pts : mirrorZ(pts) }
            var dm = lathe(f(dome), seg: 256)
            planarUV(&dm, span: 0.72)
            for i in 0..<dm.t.count { dm.t[i] = V3(1, 0, 0); dm.b[i] = simd_normalize(simd_cross(dm.n[i], dm.t[i])) }
            add(dm, sgn > 0 ? .hubDomeF : .hubDomeB, "dome" + tag, hub: true)
            add(lathe(f(cham), seg: 256), .hubChamfer, "hcham" + tag, hub: true)
            add(lathe(f(wallP), seg: 256), .hubWall, "hwall" + tag, hub: true)
        }
        hubSide(1, "F"); hubSide(-1, "B")

    return out
}

// ---- marks (design coordinates of the original 200x200 sketch -> hub-local coordinates) ----
struct RKStroke { var a: V2; var b: V2; var w: Float }
@_optimize(speed)
func markFrontStrokes() -> [RKStroke] {
    var s: [(V2, V2)] = []
    s.append((V2(54, 52), V2(54, 132)))
    s.append((V2(54, 52), V2(120, 52)))
    s.append((V2(54, 92), V2(110, 92)))
    s.append((V2(54, 132), V2(120, 132)))
    let corner = V2(200, 200)
    var out: [RKStroke] = []
    for seg in s { out.append(RKStroke(a: seg.0, b: seg.1, w: 9)) }
    for seg in s { out.append(RKStroke(a: corner - seg.0, b: corner - seg.1, w: 9)) }
    return out
}
/// pieces: 0 dash, 1 pair, 2 "e"
@_optimize(speed)
func markBackStrokes() -> [[RKStroke]] {
    let dash = [RKStroke(a: V2(30, 104), b: V2(50, 104), w: 6)]
    let pair = [RKStroke(a: V2(64, 94), b: V2(92, 94), w: 8), RKStroke(a: V2(64, 112), b: V2(92, 112), w: 8)]
    let c = V2(140, 100), R: Float = 28
    var e: [RKStroke] = [RKStroke(a: V2(112, 100), b: V2(168, 100), w: 10)]
    let endDy: Float = -(121 - 100)
    let endDx: Float = 159 - 140
    let endA: Float = atan2(endDy, endDx)
    let a1: Float = endA + 2 * Float.pi
    let steps = 64
    var prev = c + V2(R, 0)
    for i in 1...steps {
        let al: Float = a1 * Float(i) / Float(steps)
        let q: V2 = c + V2(R * cos(al), -R * sin(al))
        e.append(RKStroke(a: prev, b: q, w: 10)); prev = q
    }
    let lean: Float = 0.17453
    let cl = cos(lean), sl = sin(lean)
    func rot(_ p: V2) -> V2 {
        let d: V2 = p - c
        let rx: Float = cl * d.x - sl * d.y
        let ry: Float = sl * d.x + cl * d.y
        return c + V2(rx, ry)
    }
    var leaned: [RKStroke] = []
    for st in e { leaned.append(RKStroke(a: rot(st.a), b: rot(st.b), w: st.w)) }
    e = leaned
    return [dash, pair, e]
}
let markScaleF: Float = 0.72 * 0.27 / 73, markScaleB: Float = 0.72 * 0.27 / 74
@_optimize(speed)
func hubPiecesFront() -> [(strokes: [(a: V2, b: V2, hw: Float)], gain: Float)] {
    let sF = markScaleF
    var st: [(a: V2, b: V2, hw: Float)] = []
    for stroke in markFrontStrokes() {
        let ax: Float = (stroke.a.x - 100) * sF
        let ay: Float = -(stroke.a.y - 100) * sF
        let bx: Float = (stroke.b.x - 100) * sF
        let by: Float = -(stroke.b.y - 100) * sF
        let hw: Float = stroke.w * sF / 2
        st.append((a: V2(ax, ay), b: V2(bx, by), hw: hw))
    }
    return [(strokes: st, gain: 1.0)]
}
@_optimize(speed)
func hubPiecesBack() -> [(strokes: [(a: V2, b: V2, hw: Float)], gain: Float)] {
    let sB = markScaleB
    let g: [Float] = [0.45, 0.75, 1.0]
    var result: [(strokes: [(a: V2, b: V2, hw: Float)], gain: Float)] = []
    let pieces: [[RKStroke]] = markBackStrokes()
    for (i, piece) in pieces.enumerated() {
        var converted: [(a: V2, b: V2, hw: Float)] = []
        for stroke in piece {
            let ax: Float = (stroke.a.x - 100) * sB
            let ay: Float = (stroke.a.y - 100) * sB
            let bx: Float = (stroke.b.x - 100) * sB
            let by: Float = (stroke.b.y - 100) * sB
            let hw: Float = stroke.w * sB / 2
            converted.append((a: V2(ax, ay), b: V2(bx, by), hw: hw))
        }
        result.append((strokes: converted, gain: g[i]))
    }
    return result
}

