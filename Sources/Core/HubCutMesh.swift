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

// Real-geometry hub marks for the Spinner (pure CPU, no RealityKit types).
//
// The mark is a union of capsule strokes. `HubCutField` samples its signed distance on a Cartesian grid over the mark's
// bounding rectangle, finds where the outline crosses every grid edge (linear estimate, then regula-falsi refinement on
// the true distance, so crossing vertices sit on the real outline), and `mesh(insideDz:mirrorZ:)` builds from it:
//
//   * `face`:   the hub face OUTSIDE the mark at dome height (the grid's outside cells, the outside part of boundary
//               cells, and a strip of quads that carries the rectangle out to the rim circle, so the face meets the hub
//               rim exactly with no T-junction),
//   * `floors`: the region INSIDE the mark, offset from the dome by `insideDz` (negative cuts a channel, positive
//               raises the mark), one triangle list per mark piece,
//   * `walls`:  vertical quads along the outline between the two levels, one list per piece, with their own vertices
//               (hard edge, horizontal normals from the distance gradient: round caps shade round).
//
// Every outline vertex is created once per grid edge and shared by the face polygon, the floor polygon and the wall
// quad, so there are no cracks. Winding is fixed from the vertex normals (never dropping a triangle), so no triangle
// is lost and every interior edge is matched by exactly one neighbour.

/// One capsule stroke of a hub mark in hub-local coordinates (x right, y up), tagged with the piece it belongs to.
public struct HubCutStroke {
    public var a: SIMD2<Float>
    public var b: SIMD2<Float>
    public var hw: Float
    public var piece: Int
    public init(a: SIMD2<Float>, b: SIMD2<Float>, hw: Float, piece: Int) {
        self.a = a
        self.b = b
        self.hw = hw
        self.piece = piece
    }
}

/// Hub dome profile and meshing resolution.
public struct HubCutParams {
    /// Radius of the hub face disc (the dome's rim).
    public var rimRadius: Float
    /// Dome height at the centre and its drop at the rim (z = domeTop - domeDrop * (r / rimRadius)^2).
    public var domeTop: Float
    public var domeDrop: Float
    /// Grid cell size over the mark's bounding rectangle.
    public var cell: Float
    /// Radial rings of the strip that stitches the rectangle to the rim circle.
    public var rings: Int
    public init(rimRadius: Float, domeTop: Float, domeDrop: Float, cell: Float = 0.0033, rings: Int = 6) {
        self.rimRadius = rimRadius
        self.domeTop = domeTop
        self.domeDrop = domeDrop
        self.cell = cell
        self.rings = rings
    }
}

/// Result of one meshing pass. Triangle indices refer to `positions` / `normals`.
public struct HubCutMesh {
    public var positions: [SIMD3<Float>] = []
    public var normals: [SIMD3<Float>] = []
    public var face: [UInt32] = []
    public var floors: [[UInt32]] = []
    public var walls: [[UInt32]] = []
    /// Rim vertices (xy, on the rim circle, counter-clockwise) and the dome height there (already mirrored if asked).
    public var rim: [SIMD2<Float>] = []
    public var rimZ: Float = 0
    public init() {}
    public var triangleCount: Int {
        var n: Int = face.count / 3
        for f in floors { n += f.count / 3 }
        for w in walls { n += w.count / 3 }
        return n
    }
}

private struct HubCrossing {
    var x: Float
    var y: Float
    var gx: Float
    var gy: Float
    var piece: Int
}

public final class HubCutField {
    public let params: HubCutParams
    public let pieceCount: Int
    private let strokes: [HubCutStroke]
    // Stroke data flattened for the sampling loops.
    private var ax: [Float] = [], ay: [Float] = [], bx: [Float] = [], by: [Float] = [], hws: [Float] = []
    private var loX: [Float] = [], loY: [Float] = [], hiX: [Float] = [], hiY: [Float] = []
    private var pcs: [Int] = []
    // Grid: vertices i0...i1 x j0...j1 at (i * cell, j * cell).
    public let i0: Int, i1: Int, j0: Int, j1: Int
    private let gw: Int, gh: Int
    private var dist: [Float] = []
    private var owner: [Int] = []
    private var crossings: [HubCrossing] = []
    private var edgeH: [Int32] = []          // crossing on the edge (i, j)-(i+1, j), -1 when none
    private var edgeV: [Int32] = []          // crossing on the edge (i, j)-(i, j+1)

    /// Signed-distance sample (outside positive): distance, outward unit direction, owning piece.
    @inline(__always)
    private func sample(_ px: Float, _ py: Float) -> (d: Float, gx: Float, gy: Float, piece: Int) {
        var best: Float = 1
        var bgx: Float = 1
        var bgy: Float = 0
        var bp: Int = 0
        var s = 0
        let n: Int = ax.count
        while s < n {
            if px < loX[s] || px > hiX[s] || py < loY[s] || py > hiY[s] { s += 1; continue }
            let abx: Float = bx[s] - ax[s]
            let aby: Float = by[s] - ay[s]
            let l2: Float = abx * abx + aby * aby
            var t: Float = 0
            if l2 > 0 {
                let dxa: Float = px - ax[s]
                let dya: Float = py - ay[s]
                let dotAB: Float = dxa * abx + dya * aby
                let proj: Float = dotAB / l2
                t = proj < 0 ? 0 : (proj > 1 ? 1 : proj)
            }
            let vx: Float = px - (ax[s] + abx * t)
            let vy: Float = py - (ay[s] + aby * t)
            let len: Float = (vx * vx + vy * vy).squareRoot()
            let d: Float = len - hws[s]
            if d < best {
                best = d
                bp = pcs[s]
                if len > 1e-9 {
                    bgx = vx / len
                    bgy = vy / len
                } else {
                    bgx = 1
                    bgy = 0
                }
            }
            s += 1
        }
        return (best, bgx, bgy, bp)
    }

    /// Signed distance (outside positive, clipped to 1 far from every stroke) for tests.
    public func signedDistance(x: Float, y: Float) -> Float { sample(x, y).d }

    public init(strokes: [HubCutStroke], params: HubCutParams) {
        self.params = params
        self.strokes = strokes
        var maxPiece: Int = 0
        var minX: Float = 9, minY: Float = 9, maxX: Float = -9, maxY: Float = -9
        let cull: Float = 0.01
        for s in strokes {
            ax.append(s.a.x); ay.append(s.a.y); bx.append(s.b.x); by.append(s.b.y); hws.append(s.hw)
            let pad: Float = s.hw + cull
            loX.append(min(s.a.x, s.b.x) - pad)
            loY.append(min(s.a.y, s.b.y) - pad)
            hiX.append(max(s.a.x, s.b.x) + pad)
            hiY.append(max(s.a.y, s.b.y) + pad)
            pcs.append(s.piece)
            maxPiece = max(maxPiece, s.piece)
            minX = min(minX, min(s.a.x, s.b.x) - s.hw)
            minY = min(minY, min(s.a.y, s.b.y) - s.hw)
            maxX = max(maxX, max(s.a.x, s.b.x) + s.hw)
            maxY = max(maxY, max(s.a.y, s.b.y) + s.hw)
        }
        pieceCount = strokes.isEmpty ? 1 : maxPiece + 1
        let h: Float = params.cell
        let margin: Int = 3
        if strokes.isEmpty {
            minX = 0; minY = 0; maxX = 0; maxY = 0
        }
        i0 = min(Int((minX / h).rounded(.down)) - margin, -margin)
        i1 = max(Int((maxX / h).rounded(.up)) + margin, margin)
        j0 = min(Int((minY / h).rounded(.down)) - margin, -margin)
        j1 = max(Int((maxY / h).rounded(.up)) + margin, margin)
        gw = i1 - i0 + 1
        gh = j1 - j0 + 1
        buildDistance()
        buildCrossings()
    }

    @inline(__always)
    private func gi(_ i: Int, _ j: Int) -> Int { (j - j0) * gw + (i - i0) }

    /// Distance and owner at every grid vertex, evaluated only near each stroke (everything else is "far outside").
    private func buildDistance() {
        let h: Float = params.cell
        dist = [Float](repeating: 1, count: gw * gh)
        owner = [Int](repeating: 0, count: gw * gh)
        var s = 0
        while s < ax.count {
            let pad: Float = hws[s] + 2 * h
            let lx: Float = min(ax[s], bx[s]) - pad
            let hx: Float = max(ax[s], bx[s]) + pad
            let ly: Float = min(ay[s], by[s]) - pad
            let hy: Float = max(ay[s], by[s]) + pad
            let iLo: Int = max(i0, Int((lx / h).rounded(.down)))
            let iHi: Int = min(i1, Int((hx / h).rounded(.up)))
            let jLo: Int = max(j0, Int((ly / h).rounded(.down)))
            let jHi: Int = min(j1, Int((hy / h).rounded(.up)))
            let abx: Float = bx[s] - ax[s]
            let aby: Float = by[s] - ay[s]
            let l2: Float = abx * abx + aby * aby
            var j: Int = jLo
            while j <= jHi {
                var i: Int = iLo
                while i <= iHi {
                    let px: Float = Float(i) * h
                    let py: Float = Float(j) * h
                    var t: Float = 0
                    if l2 > 0 {
                        let dxa: Float = px - ax[s]
                        let dya: Float = py - ay[s]
                        let dotAB: Float = dxa * abx + dya * aby
                        let proj: Float = dotAB / l2
                        t = proj < 0 ? 0 : (proj > 1 ? 1 : proj)
                    }
                    let vx: Float = px - (ax[s] + abx * t)
                    let vy: Float = py - (ay[s] + aby * t)
                    let d: Float = (vx * vx + vy * vy).squareRoot() - hws[s]
                    let k: Int = gi(i, j)
                    if d < dist[k] {
                        dist[k] = d
                        owner[k] = pcs[s]
                    }
                    i += 1
                }
                j += 1
            }
            s += 1
        }
        // The outermost ring of vertices is always outside: the strip to the rim hangs off it.
        var i: Int = i0
        while i <= i1 {
            dist[gi(i, j0)] = max(dist[gi(i, j0)], 1e-3)
            dist[gi(i, j1)] = max(dist[gi(i, j1)], 1e-3)
            i += 1
        }
        var j: Int = j0
        while j <= j1 {
            dist[gi(i0, j)] = max(dist[gi(i0, j)], 1e-3)
            dist[gi(i1, j)] = max(dist[gi(i1, j)], 1e-3)
            j += 1
        }
    }

    /// Refined outline crossing on the segment (x0, y0)-(x1, y1) whose end distances d0, d1 differ in sign.
    private func refine(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ d0: Float, _ d1: Float) -> HubCrossing {
        var ta: Float = 0
        var fa: Float = d0
        var tb: Float = 1
        var fb: Float = d1
        var iter = 0
        while iter < 4 {
            let denom: Float = fa - fb
            let t: Float = denom == 0 ? 0.5 : ta + (tb - ta) * fa / denom
            let sx: Float = x0 + (x1 - x0) * t
            let sy: Float = y0 + (y1 - y0) * t
            let s = sample(sx, sy)
            if (s.d < 0) == (fa < 0) {
                ta = t
                fa = s.d
            } else {
                tb = t
                fb = s.d
            }
            iter += 1
        }
        let denom: Float = fa - fb
        var t: Float = denom == 0 ? 0.5 : ta + (tb - ta) * fa / denom
        // Keep the vertex off the grid corner so no triangle collapses (at most 0.02 cell from the outline).
        t = min(max(t, 0.02), 0.98)
        let x: Float = x0 + (x1 - x0) * t
        let y: Float = y0 + (y1 - y0) * t
        let s = sample(x, y)
        return HubCrossing(x: x, y: y, gx: s.gx, gy: s.gy, piece: s.piece)
    }

    private func buildCrossings() {
        let h: Float = params.cell
        edgeH = [Int32](repeating: -1, count: gw * gh)
        edgeV = [Int32](repeating: -1, count: gw * gh)
        var j: Int = j0
        while j <= j1 {
            var i: Int = i0
            while i <= i1 {
                let k: Int = gi(i, j)
                let din: Bool = dist[k] < 0
                let px: Float = Float(i) * h
                let py: Float = Float(j) * h
                if i < i1 {
                    let k2: Int = gi(i + 1, j)
                    if (dist[k2] < 0) != din {
                        edgeH[k] = Int32(crossings.count)
                        crossings.append(refine(px, py, px + h, py, dist[k], dist[k2]))
                    }
                }
                if j < j1 {
                    let k2: Int = gi(i, j + 1)
                    if (dist[k2] < 0) != din {
                        edgeV[k] = Int32(crossings.count)
                        crossings.append(refine(px, py, px, py + h, dist[k], dist[k2]))
                    }
                }
                i += 1
            }
            j += 1
        }
    }

    /// Half extent of the grid rectangle (largest corner radius), for the caller's sanity check against the rim.
    public var cornerRadius: Float {
        let h: Float = params.cell
        let xs: [Float] = [Float(i0) * h, Float(i1) * h]
        let ys: [Float] = [Float(j0) * h, Float(j1) * h]
        var r: Float = 0
        for x in xs { for y in ys { r = max(r, (x * x + y * y).squareRoot()) } }
        return r
    }

    // ---------------------------------------------------------------------------------------------------------
    // meshing
    // ---------------------------------------------------------------------------------------------------------
    /// Builds the mesh. `insideDz` < 0 cuts the mark into the face, > 0 raises it. `mirrorZ` builds the back hub: the
    /// same outline at negated heights, triangles still wound against their normals.
    public func mesh(insideDz: Float, mirrorZ: Bool) -> HubCutMesh {
        let builder = HubCutBuilder(field: self, insideDz: insideDz, mirrorZ: mirrorZ)
        return builder.run()
    }

    // Internal accessors for the builder (same file).
    fileprivate var gridWidth: Int { gw }
    fileprivate func vertexIndex(_ i: Int, _ j: Int) -> Int { gi(i, j) }
    fileprivate func distanceAt(_ i: Int, _ j: Int) -> Float { dist[gi(i, j)] }
    fileprivate func ownerAt(_ i: Int, _ j: Int) -> Int { owner[gi(i, j)] }
    fileprivate func crossingH(_ i: Int, _ j: Int) -> Int { Int(edgeH[gi(i, j)]) }
    fileprivate func crossingV(_ i: Int, _ j: Int) -> Int { Int(edgeV[gi(i, j)]) }
    fileprivate func crossing(_ c: Int) -> HubCrossing { crossings[c] }
    fileprivate var crossingCount: Int { crossings.count }
    fileprivate func centreInside(_ x: Float, _ y: Float) -> Bool { sample(x, y).d < 0 }
}

private final class HubCutBuilder {
    let f: HubCutField
    let p: HubCutParams
    let insideDz: Float
    let zs: Float
    let wallSign: Float
    var out = HubCutMesh()
    var faceV: [Int32]
    var inV: [Int32]
    var crossFace: [Int32]
    var crossIn: [Int32]
    var wallFaceV: [Int32]
    var wallInV: [Int32]

    init(field: HubCutField, insideDz: Float, mirrorZ: Bool) {
        f = field
        p = field.params
        self.insideDz = insideDz
        zs = mirrorZ ? -1 : 1
        wallSign = insideDz < 0 ? -1 : 1
        let n: Int = (field.i1 - field.i0 + 1) * (field.j1 - field.j0 + 1)
        faceV = [Int32](repeating: -1, count: n)
        inV = [Int32](repeating: -1, count: n)
        crossFace = [Int32](repeating: -1, count: field.crossingCount)
        crossIn = [Int32](repeating: -1, count: field.crossingCount)
        wallFaceV = [Int32](repeating: -1, count: field.crossingCount)
        wallInV = [Int32](repeating: -1, count: field.crossingCount)
        out.floors = [[UInt32]](repeating: [], count: field.pieceCount)
        out.walls = [[UInt32]](repeating: [], count: field.pieceCount)
    }

    // ---- dome profile ----
    @inline(__always)
    func domeZ(_ r: Float) -> Float {
        let ratio: Float = r / p.rimRadius
        let drop: Float = p.domeDrop * ratio * ratio
        return p.domeTop - drop
    }
    @inline(__always)
    func faceZ(_ x: Float, _ y: Float) -> Float {
        let r: Float = (x * x + y * y).squareRoot()
        return domeZ(r)
    }
    @inline(__always)
    func domeNormal(_ x: Float, _ y: Float) -> SIMD3<Float> {
        let k: Float = 2 * p.domeDrop / (p.rimRadius * p.rimRadius)
        let n = SIMD3<Float>(k * x, k * y, 1)
        let len2: Float = n.x * n.x + n.y * n.y + n.z * n.z
        let inv: Float = 1 / len2.squareRoot()
        return SIMD3<Float>(n.x * inv, n.y * inv, n.z * inv * zs)
    }

    func add(_ pos: SIMD3<Float>, _ nor: SIMD3<Float>) -> Int32 {
        out.positions.append(pos)
        out.normals.append(nor)
        return Int32(out.positions.count - 1)
    }

    // ---- shared vertices ----
    func faceVertex(_ i: Int, _ j: Int) -> UInt32 {
        let k: Int = f.vertexIndex(i, j)
        if faceV[k] < 0 {
            let x: Float = Float(i) * p.cell
            let y: Float = Float(j) * p.cell
            faceV[k] = add(SIMD3<Float>(x, y, faceZ(x, y) * zs), domeNormal(x, y))
        }
        return UInt32(faceV[k])
    }
    func inVertex(_ i: Int, _ j: Int) -> UInt32 {
        let k: Int = f.vertexIndex(i, j)
        if inV[k] < 0 {
            let x: Float = Float(i) * p.cell
            let y: Float = Float(j) * p.cell
            inV[k] = add(SIMD3<Float>(x, y, (faceZ(x, y) + insideDz) * zs), domeNormal(x, y))
        }
        return UInt32(inV[k])
    }
    func crossFaceVertex(_ c: Int) -> UInt32 {
        if crossFace[c] < 0 {
            let q = f.crossing(c)
            crossFace[c] = add(SIMD3<Float>(q.x, q.y, faceZ(q.x, q.y) * zs), domeNormal(q.x, q.y))
        }
        return UInt32(crossFace[c])
    }
    func crossInVertex(_ c: Int) -> UInt32 {
        if crossIn[c] < 0 {
            let q = f.crossing(c)
            crossIn[c] = add(SIMD3<Float>(q.x, q.y, (faceZ(q.x, q.y) + insideDz) * zs), domeNormal(q.x, q.y))
        }
        return UInt32(crossIn[c])
    }
    func wallNormal(_ c: Int) -> SIMD3<Float> {
        let q = f.crossing(c)
        return SIMD3<Float>(q.gx * wallSign, q.gy * wallSign, 0)
    }
    func wallFaceVertex(_ c: Int) -> UInt32 {
        if wallFaceV[c] < 0 {
            let q = f.crossing(c)
            wallFaceV[c] = add(SIMD3<Float>(q.x, q.y, faceZ(q.x, q.y) * zs), wallNormal(c))
        }
        return UInt32(wallFaceV[c])
    }
    func wallInVertex(_ c: Int) -> UInt32 {
        if wallInV[c] < 0 {
            let q = f.crossing(c)
            wallInV[c] = add(SIMD3<Float>(q.x, q.y, (faceZ(q.x, q.y) + insideDz) * zs), wallNormal(c))
        }
        return UInt32(wallInV[c])
    }

    // ---- triangle emission: winding fixed against the vertex normals, nothing dropped ----
    enum Target { case face, floor, wall }
    func tri(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ target: Target, _ piece: Int) {
        let pa: SIMD3<Float> = out.positions[Int(a)]
        let pb: SIMD3<Float> = out.positions[Int(b)]
        let pc: SIMD3<Float> = out.positions[Int(c)]
        let g: SIMD3<Float> = simd_cross(pb - pa, pc - pa)
        let nn: SIMD3<Float> = out.normals[Int(a)] + out.normals[Int(b)] + out.normals[Int(c)]
        let forward: Bool = simd_dot(g, nn) >= 0
        let i0: UInt32 = a
        let i1: UInt32 = forward ? b : c
        let i2: UInt32 = forward ? c : b
        switch target {
        case .face: out.face.append(contentsOf: [i0, i1, i2])
        case .floor: out.floors[piece].append(contentsOf: [i0, i1, i2])
        case .wall: out.walls[piece].append(contentsOf: [i0, i1, i2])
        }
    }
    func fan(_ poly: [UInt32], _ target: Target, _ piece: Int) {
        if poly.count < 3 { return }
        var k = 1
        while k + 1 < poly.count {
            tri(poly[0], poly[k], poly[k + 1], target, piece)
            k += 1
        }
    }
    func wallQuad(_ ca: Int, _ cb: Int) {
        let piece: Int = f.crossing(ca).piece
        let a0: UInt32 = wallFaceVertex(ca)
        let b0: UInt32 = wallFaceVertex(cb)
        let b1: UInt32 = wallInVertex(cb)
        let a1: UInt32 = wallInVertex(ca)
        tri(a0, b0, b1, .wall, piece)
        tri(a0, b1, a1, .wall, piece)
    }

    func run() -> HubCutMesh {
        let i0: Int = f.i0, i1: Int = f.i1, j0: Int = f.j0, j1: Int = f.j1
        let h: Float = p.cell
        var j: Int = j0
        while j < j1 {
            var i: Int = i0
            while i < i1 {
                processCell(i, j, h)
                i += 1
            }
            j += 1
        }
        buildStrip()
        return out
    }

    func processCell(_ i: Int, _ j: Int, _ h: Float) {
        let ci: [Int] = [i, i + 1, i + 1, i]
        let cj: [Int] = [j, j, j + 1, j + 1]
        var ins: [Bool] = [false, false, false, false]
        var count = 0
        var k = 0
        while k < 4 {
            ins[k] = f.distanceAt(ci[k], cj[k]) < 0
            if ins[k] { count += 1 }
            k += 1
        }
        if count == 0 {
            fan([faceVertex(ci[0], cj[0]), faceVertex(ci[1], cj[1]), faceVertex(ci[2], cj[2]), faceVertex(ci[3], cj[3])], .face, 0)
            return
        }
        // Crossing index on each edge (edge k joins corner k and corner k + 1).
        let cx: [Int] = [f.crossingH(i, j), f.crossingV(i + 1, j), f.crossingH(i, j + 1), f.crossingV(i, j)]
        // Owner piece of the inside corner with the smallest distance.
        var piece: Int = 0
        var bestD: Float = 1
        k = 0
        while k < 4 {
            let d: Float = f.distanceAt(ci[k], cj[k])
            if ins[k] && d < bestD {
                bestD = d
                piece = f.ownerAt(ci[k], cj[k])
            }
            k += 1
        }
        if count == 4 {
            fan([inVertex(ci[0], cj[0]), inVertex(ci[1], cj[1]), inVertex(ci[2], cj[2]), inVertex(ci[3], cj[3])], .floor, piece)
            return
        }
        let saddle: Bool = (count == 2) && (ins[0] == ins[2])
        if !saddle {
            var outPoly: [UInt32] = []
            var inPoly: [UInt32] = []
            var wallA: Int = -1
            var wallB: Int = -1
            k = 0
            while k < 4 {
                if ins[k] { inPoly.append(inVertex(ci[k], cj[k])) } else { outPoly.append(faceVertex(ci[k], cj[k])) }
                if ins[k] != ins[(k + 1) % 4] {
                    outPoly.append(crossFaceVertex(cx[k]))
                    inPoly.append(crossInVertex(cx[k]))
                    if wallA < 0 { wallA = cx[k] } else { wallB = cx[k] }
                }
                k += 1
            }
            fan(outPoly, .face, 0)
            fan(inPoly, .floor, piece)
            wallQuad(wallA, wallB)
            return
        }
        // Saddle: two diagonal corners inside. The cell centre decides whether the inside corners are connected.
        let centreX: Float = (Float(i) + 0.5) * h
        let centreY: Float = (Float(j) + 0.5) * h
        let connected: Bool = f.centreInside(centreX, centreY)
        if connected {
            var inPoly: [UInt32] = []
            k = 0
            while k < 4 {
                if ins[k] { inPoly.append(inVertex(ci[k], cj[k])) }
                inPoly.append(crossInVertex(cx[k]))
                k += 1
            }
            fan(inPoly, .floor, piece)
            k = 0
            while k < 4 {
                if !ins[k] {
                    let prev: Int = cx[(k + 3) % 4]
                    let next: Int = cx[k]
                    fan([crossFaceVertex(prev), faceVertex(ci[k], cj[k]), crossFaceVertex(next)], .face, 0)
                    wallQuad(prev, next)
                }
                k += 1
            }
        } else {
            var outPoly: [UInt32] = []
            k = 0
            while k < 4 {
                if !ins[k] { outPoly.append(faceVertex(ci[k], cj[k])) }
                outPoly.append(crossFaceVertex(cx[k]))
                k += 1
            }
            fan(outPoly, .face, 0)
            k = 0
            while k < 4 {
                if ins[k] {
                    let prev: Int = cx[(k + 3) % 4]
                    let next: Int = cx[k]
                    let pc: Int = f.ownerAt(ci[k], cj[k])
                    fan([crossInVertex(prev), inVertex(ci[k], cj[k]), crossInVertex(next)], .floor, pc)
                    wallQuad(prev, next)
                }
                k += 1
            }
        }
    }

    /// Quads from the grid rectangle's boundary vertices out to the rim circle along radial lines, so the face is
    /// complete up to the rim and the rim vertices (shared with the chamfer built by the caller) are single points.
    func buildStrip() {
        let i0: Int = f.i0, i1: Int = f.i1, j0: Int = f.j0, j1: Int = f.j1
        var ring: [(Int, Int)] = []
        var i: Int = i0
        while i < i1 { ring.append((i, j0)); i += 1 }
        var j: Int = j0
        while j < j1 { ring.append((i1, j)); j += 1 }
        i = i1
        while i > i0 { ring.append((i, j1)); i -= 1 }
        j = j1
        while j > j0 { ring.append((i0, j)); j -= 1 }
        let m: Int = max(1, p.rings)
        let rimZValue: Float = domeZ(p.rimRadius)
        var rows: [[UInt32]] = []          // rows[s][k]: s = 0 is the grid boundary, s = m the rim
        var rimPoints: [SIMD2<Float>] = []
        var s = 0
        while s <= m {
            var row: [UInt32] = []
            row.reserveCapacity(ring.count)
            var k = 0
            while k < ring.count {
                let px: Float = Float(ring[k].0) * p.cell
                let py: Float = Float(ring[k].1) * p.cell
                if s == 0 {
                    row.append(faceVertex(ring[k].0, ring[k].1))
                } else {
                    let len: Float = (px * px + py * py).squareRoot()
                    let cxr: Float = px / len * p.rimRadius
                    let cyr: Float = py / len * p.rimRadius
                    if s == m {
                        row.append(UInt32(add(SIMD3<Float>(cxr, cyr, rimZValue * zs), domeNormal(cxr, cyr))))
                        rimPoints.append(SIMD2<Float>(cxr, cyr))
                    } else {
                        let t: Float = Float(s) / Float(m)
                        let qx: Float = px + (cxr - px) * t
                        let qy: Float = py + (cyr - py) * t
                        row.append(UInt32(add(SIMD3<Float>(qx, qy, faceZ(qx, qy) * zs), domeNormal(qx, qy))))
                    }
                }
                k += 1
            }
            rows.append(row)
            s += 1
        }
        s = 0
        while s < m {
            var k = 0
            while k < ring.count {
                let k2: Int = (k + 1) % ring.count
                let a: UInt32 = rows[s][k]
                let b: UInt32 = rows[s][k2]
                let c: UInt32 = rows[s + 1][k2]
                let d: UInt32 = rows[s + 1][k]
                tri(a, b, c, .face, 0)
                tri(a, c, d, .face, 0)
                k += 1
            }
            s += 1
        }
        out.rim = rimPoints
        out.rimZ = rimZValue * zs
    }
}
