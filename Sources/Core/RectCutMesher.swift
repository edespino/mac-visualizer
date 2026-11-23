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

// Marching-squares mesher over a RECTILINEAR grid (columns and rows may be spaced unevenly) for flat plates with cut
// regions. It generalises the idea of `HubCutField`: the plate's top face is meshed everywhere the signed distance field is
// positive (outside the cut), the cut region's floor is meshed where it is negative, and vertical walls join the two along
// the outline. Every outline crossing is created once per grid edge and shared by the face polygon, the floor polygon and
// the wall quad, so there are no cracks. The caller maps the (u, v) parameter plane to the world (a straight plate, or a
// polar strip such as the engraved ring) and chooses the heights, so one mesher serves the ring lettering and the logo patch.
//
// Parameter space (u, v): triangles are emitted counter-clockwise in that plane; the caller fixes the final winding from
// its vertex normals.

public struct CutVertex {
    public var uv: P2
    /// True when the vertex lies on the cut floor (face level otherwise).
    public var onFloor: Bool
    /// Outward gradient of the signed distance (unit length) for wall vertices, zero elsewhere.
    public var gradient: P2
    public init(uv: P2, onFloor: Bool, gradient: P2) {
        self.uv = uv
        self.onFloor = onFloor
        self.gradient = gradient
    }
}

public struct CutGridMesh {
    public var vertices: [CutVertex] = []
    public var face: [UInt32] = []
    public var floor: [UInt32] = []
    public var wall: [UInt32] = []
    public init() {}
    public var triangleCount: Int { (face.count + floor.count + wall.count) / 3 }
}

public enum RectCutMesher {

    /// Meshes the grid with vertices at (xs[i], ys[j]). `sdf` is the signed distance (negative inside the cut). Columns
    /// marked inactive (`activeColumns[i]` false, for the cell column between xs[i] and xs[i+1]) are never sampled: they
    /// must not touch the cut. The outermost vertices must lie outside the cut.
    public static func mesh(xs: [Float], ys: [Float], activeColumns: [Bool]?, sdf: @escaping (Float, Float) -> Float) -> CutGridMesh {
        let builder = RectCutBuilder(xs: xs, ys: ys, activeColumns: activeColumns, sdf: sdf)
        return builder.run()
    }
}

private final class RectCutBuilder {
    let xs: [Float]
    let ys: [Float]
    let nx: Int            // vertex columns
    let ny: Int            // vertex rows
    let sdf: (Float, Float) -> Float
    var dist: [Float]
    var out = CutGridMesh()
    var faceV: [Int32]
    var floorV: [Int32]
    var crossH: [Int32]    // crossing on the edge (i, j)-(i+1, j)
    var crossV: [Int32]    // crossing on the edge (i, j)-(i, j+1)
    var crossPos: [P2] = []
    var crossGrad: [P2] = []
    var crossFaceV: [Int32] = []
    var crossFloorV: [Int32] = []
    var wallTopV: [Int32] = []
    var wallBotV: [Int32] = []

    init(xs: [Float], ys: [Float], activeColumns: [Bool]?, sdf: @escaping (Float, Float) -> Float) {
        self.xs = xs
        self.ys = ys
        self.nx = xs.count
        self.ny = ys.count
        self.sdf = sdf
        let total: Int = nx * ny
        dist = [Float](repeating: 1, count: total)
        faceV = [Int32](repeating: -1, count: total)
        floorV = [Int32](repeating: -1, count: total)
        crossH = [Int32](repeating: -1, count: total)
        crossV = [Int32](repeating: -1, count: total)
        // Distance at every vertex touched by an active column.
        var i: Int = 0
        while i < nx {
            let leftActive: Bool = i > 0 && (activeColumns?[i - 1] ?? true)
            let rightActive: Bool = i < nx - 1 && (activeColumns?[i] ?? true)
            if leftActive || rightActive {
                var j: Int = 0
                while j < ny {
                    dist[j * nx + i] = sdf(xs[i], ys[j])
                    j += 1
                }
            }
            i += 1
        }
    }

    @inline(__always) func gi(_ i: Int, _ j: Int) -> Int { j * nx + i }

    func gradient(at p: P2) -> P2 {
        let h: Float = 0.0004
        let gx: Float = sdf(p.x + h, p.y) - sdf(p.x - h, p.y)
        let gy: Float = sdf(p.x, p.y + h) - sdf(p.x, p.y - h)
        let len: Float = (gx * gx + gy * gy).squareRoot()
        if len < 1e-9 { return P2(1, 0) }
        return P2(gx / len, gy / len)
    }

    func makeCrossing(_ a: P2, _ b: P2, _ da: Float, _ db: Float) -> Int32 {
        var ta: Float = 0
        var fa: Float = da
        var tb: Float = 1
        var fb: Float = db
        var iter: Int = 0
        while iter < 5 {
            let denom: Float = fa - fb
            let t: Float = denom == 0 ? 0.5 : ta + (tb - ta) * fa / denom
            let q: P2 = a + (b - a) * t
            let s: Float = sdf(q.x, q.y)
            if (s < 0) == (fa < 0) {
                ta = t
                fa = s
            } else {
                tb = t
                fb = s
            }
            iter += 1
        }
        let denom: Float = fa - fb
        var t: Float = denom == 0 ? 0.5 : ta + (tb - ta) * fa / denom
        t = min(max(t, 0.02), 0.98)
        let pos: P2 = a + (b - a) * t
        crossPos.append(pos)
        crossGrad.append(gradient(at: pos))
        crossFaceV.append(-1)
        crossFloorV.append(-1)
        wallTopV.append(-1)
        wallBotV.append(-1)
        return Int32(crossPos.count - 1)
    }

    func buildCrossings() {
        var j: Int = 0
        while j < ny {
            var i: Int = 0
            while i < nx {
                let k: Int = gi(i, j)
                let inside: Bool = dist[k] < 0
                let p: P2 = P2(xs[i], ys[j])
                if i < nx - 1 {
                    let k2: Int = gi(i + 1, j)
                    if (dist[k2] < 0) != inside {
                        crossH[k] = makeCrossing(p, P2(xs[i + 1], ys[j]), dist[k], dist[k2])
                    }
                }
                if j < ny - 1 {
                    let k2: Int = gi(i, j + 1)
                    if (dist[k2] < 0) != inside {
                        crossV[k] = makeCrossing(p, P2(xs[i], ys[j + 1]), dist[k], dist[k2])
                    }
                }
                i += 1
            }
            j += 1
        }
    }

    // ---- vertices ----
    func addVertex(_ p: P2, floor: Bool, gradient: P2) -> UInt32 {
        out.vertices.append(CutVertex(uv: p, onFloor: floor, gradient: gradient))
        return UInt32(out.vertices.count - 1)
    }
    func faceVertex(_ i: Int, _ j: Int) -> UInt32 {
        let k: Int = gi(i, j)
        if faceV[k] < 0 { faceV[k] = Int32(addVertex(P2(xs[i], ys[j]), floor: false, gradient: P2(0, 0))) }
        return UInt32(faceV[k])
    }
    func floorVertex(_ i: Int, _ j: Int) -> UInt32 {
        let k: Int = gi(i, j)
        if floorV[k] < 0 { floorV[k] = Int32(addVertex(P2(xs[i], ys[j]), floor: true, gradient: P2(0, 0))) }
        return UInt32(floorV[k])
    }
    func crossFace(_ c: Int) -> UInt32 {
        if crossFaceV[c] < 0 { crossFaceV[c] = Int32(addVertex(crossPos[c], floor: false, gradient: P2(0, 0))) }
        return UInt32(crossFaceV[c])
    }
    func crossFloor(_ c: Int) -> UInt32 {
        if crossFloorV[c] < 0 { crossFloorV[c] = Int32(addVertex(crossPos[c], floor: true, gradient: P2(0, 0))) }
        return UInt32(crossFloorV[c])
    }
    func wallTop(_ c: Int) -> UInt32 {
        if wallTopV[c] < 0 { wallTopV[c] = Int32(addVertex(crossPos[c], floor: false, gradient: crossGrad[c])) }
        return UInt32(wallTopV[c])
    }
    func wallBot(_ c: Int) -> UInt32 {
        if wallBotV[c] < 0 { wallBotV[c] = Int32(addVertex(crossPos[c], floor: true, gradient: crossGrad[c])) }
        return UInt32(wallBotV[c])
    }

    enum Target { case face, floor, wall }
    func tri(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ target: Target) {
        let pa: P2 = out.vertices[Int(a)].uv
        let pb: P2 = out.vertices[Int(b)].uv
        let pc: P2 = out.vertices[Int(c)].uv
        let area: Float = (pb.x - pa.x) * (pc.y - pa.y) - (pb.y - pa.y) * (pc.x - pa.x)
        var t0: UInt32 = a
        var t1: UInt32 = b
        var t2: UInt32 = c
        if target == .wall {
            // Wall triangles are vertical (zero area in the plane): keep the given order.
        } else if area < 0 {
            t1 = c
            t2 = b
        }
        t0 = a
        switch target {
        case .face: out.face.append(contentsOf: [t0, t1, t2])
        case .floor: out.floor.append(contentsOf: [t0, t1, t2])
        case .wall: out.wall.append(contentsOf: [t0, t1, t2])
        }
    }
    func fan(_ poly: [UInt32], _ target: Target) {
        if poly.count < 3 { return }
        var k: Int = 1
        while k + 1 < poly.count {
            tri(poly[0], poly[k], poly[k + 1], target)
            k += 1
        }
    }
    func wallQuad(_ ca: Int, _ cb: Int) {
        let a0: UInt32 = wallTop(ca)
        let b0: UInt32 = wallTop(cb)
        let b1: UInt32 = wallBot(cb)
        let a1: UInt32 = wallBot(ca)
        tri(a0, b0, b1, .wall)
        tri(a0, b1, a1, .wall)
    }

    func run() -> CutGridMesh {
        buildCrossings()
        var j: Int = 0
        while j < ny - 1 {
            var i: Int = 0
            while i < nx - 1 {
                processCell(i, j)
                i += 1
            }
            j += 1
        }
        return out
    }

    func processCell(_ i: Int, _ j: Int) {
        let ci: [Int] = [i, i + 1, i + 1, i]
        let cj: [Int] = [j, j, j + 1, j + 1]
        var ins: [Bool] = [false, false, false, false]
        var count: Int = 0
        var k: Int = 0
        while k < 4 {
            ins[k] = dist[gi(ci[k], cj[k])] < 0
            if ins[k] { count += 1 }
            k += 1
        }
        if count == 0 {
            fan([faceVertex(ci[0], cj[0]), faceVertex(ci[1], cj[1]), faceVertex(ci[2], cj[2]), faceVertex(ci[3], cj[3])], .face)
            return
        }
        if count == 4 {
            fan([floorVertex(ci[0], cj[0]), floorVertex(ci[1], cj[1]), floorVertex(ci[2], cj[2]), floorVertex(ci[3], cj[3])], .floor)
            return
        }
        // Edge k joins corner k and corner k + 1.
        let cx: [Int] = [Int(crossH[gi(i, j)]), Int(crossV[gi(i + 1, j)]), Int(crossH[gi(i, j + 1)]), Int(crossV[gi(i, j)])]
        let saddle: Bool = (count == 2) && (ins[0] == ins[2])
        if !saddle {
            var outPoly: [UInt32] = []
            var inPoly: [UInt32] = []
            var wallA: Int = -1
            var wallB: Int = -1
            k = 0
            while k < 4 {
                if ins[k] { inPoly.append(floorVertex(ci[k], cj[k])) } else { outPoly.append(faceVertex(ci[k], cj[k])) }
                if ins[k] != ins[(k + 1) % 4] {
                    outPoly.append(crossFace(cx[k]))
                    inPoly.append(crossFloor(cx[k]))
                    if wallA < 0 { wallA = cx[k] } else { wallB = cx[k] }
                }
                k += 1
            }
            fan(outPoly, .face)
            fan(inPoly, .floor)
            if wallA >= 0 && wallB >= 0 { wallQuad(wallA, wallB) }
            return
        }
        let centre = P2((xs[i] + xs[i + 1]) * 0.5, (ys[j] + ys[j + 1]) * 0.5)
        let connected: Bool = sdf(centre.x, centre.y) < 0
        if connected {
            var inPoly: [UInt32] = []
            k = 0
            while k < 4 {
                if ins[k] { inPoly.append(floorVertex(ci[k], cj[k])) }
                inPoly.append(crossFloor(cx[k]))
                k += 1
            }
            fan(inPoly, .floor)
            k = 0
            while k < 4 {
                if !ins[k] {
                    let prev: Int = cx[(k + 3) % 4]
                    let next: Int = cx[k]
                    fan([crossFace(prev), faceVertex(ci[k], cj[k]), crossFace(next)], .face)
                    wallQuad(prev, next)
                }
                k += 1
            }
        } else {
            var outPoly: [UInt32] = []
            k = 0
            while k < 4 {
                if !ins[k] { outPoly.append(faceVertex(ci[k], cj[k])) }
                outPoly.append(crossFace(cx[k]))
                k += 1
            }
            fan(outPoly, .face)
            k = 0
            while k < 4 {
                if ins[k] {
                    let prev: Int = cx[(k + 3) % 4]
                    let next: Int = cx[k]
                    fan([crossFloor(prev), floorVertex(ci[k], cj[k]), crossFloor(next)], .floor)
                    wallQuad(prev, next)
                }
                k += 1
            }
        }
    }
}

// MARK: - Grid helpers

public enum CutGrid {
    /// Evenly spaced coordinates from `lo` to `hi` with at most `step` between neighbours (both ends included).
    public static func uniform(_ lo: Float, _ hi: Float, step: Float) -> [Float] {
        let n: Int = max(1, Int(((hi - lo) / step).rounded(.up)))
        var out: [Float] = []
        out.reserveCapacity(n + 1)
        var i: Int = 0
        while i <= n {
            let t: Float = Float(i) / Float(n)
            out.append(lo + (hi - lo) * t)
            i += 1
        }
        return out
    }
    /// Concatenates coordinate runs (each ascending), dropping duplicated joints.
    public static func join(_ runs: [[Float]]) -> [Float] {
        var out: [Float] = []
        for r in runs {
            for v in r {
                if let last = out.last, abs(last - v) < 1e-7 { continue }
                out.append(v)
            }
        }
        return out
    }
}
