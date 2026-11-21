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

final class HubCutMeshTests: XCTestCase {
    typealias V2 = SIMD2<Float>
    typealias V3 = SIMD3<Float>

    let params = HubCutParams(rimRadius: 0.33, domeTop: 0.18, domeDrop: 0.008, cell: 0.0033, rings: 6)

    /// A mark shaped like the real ones: a bracket of straight strokes (two pieces, touching strokes that overlap at
    /// joints) plus a ring-with-bar built from many short segments (a round "e"-like piece).
    func sampleStrokes(mirrorX: Bool = false) -> [HubCutStroke] {
        let xs: Float = mirrorX ? -1 : 1
        var out: [HubCutStroke] = []
        func add(_ ax: Float, _ ay: Float, _ bx: Float, _ by: Float, _ hw: Float, _ piece: Int) {
            out.append(HubCutStroke(a: V2(xs * ax, ay), b: V2(xs * bx, by), hw: hw, piece: piece))
        }
        add(-0.12, -0.12, -0.12, 0.12, 0.012, 0)
        add(-0.12, 0.12, -0.02, 0.12, 0.012, 0)
        add(-0.12, 0.0, -0.04, 0.0, 0.012, 0)
        let c = V2(0.08, 0.0)
        let radius: Float = 0.06
        var prev: V2 = c + V2(radius, 0)
        for s in 1...64 {
            let a: Float = 2 * Float.pi * Float(s) / 64
            let q: V2 = c + V2(radius * cos(a), radius * sin(a))
            out.append(HubCutStroke(a: V2(xs * prev.x, prev.y), b: V2(xs * q.x, q.y), hw: 0.010, piece: 1))
            prev = q
        }
        add(0.02, 0.0, 0.14, 0.0, 0.010, 1)
        return out
    }

    func bruteDistance(_ strokes: [HubCutStroke], _ p: V2) -> Float {
        var best: Float = 1e9
        for s in strokes {
            let ab: V2 = s.b - s.a
            let l2: Float = simd_dot(ab, ab)
            var t: Float = 0
            if l2 > 0 { t = max(0, min(1, simd_dot(p - s.a, ab) / l2)) }
            let q: V2 = s.a + ab * t
            best = min(best, simd_length(p - q) - s.hw)
        }
        return best
    }

    struct EdgeKey: Hashable { var a: [Float]; var b: [Float] }
    func key(_ p: V3) -> [Float] { [p.x, p.y, p.z] }

    /// Undirected edge counts with vertices welded by exact position.
    func edgeCounts(_ m: HubCutMesh) -> [EdgeKey: Int] {
        var all: [[UInt32]] = [m.face]
        all.append(contentsOf: m.floors)
        all.append(contentsOf: m.walls)
        var counts: [EdgeKey: Int] = [:]
        for list in all {
            var t = 0
            while t + 2 < list.count {
                let v: [V3] = [m.positions[Int(list[t])], m.positions[Int(list[t + 1])], m.positions[Int(list[t + 2])]]
                for e in 0..<3 {
                    let ka: [Float] = key(v[e])
                    let kb: [Float] = key(v[(e + 1) % 3])
                    let lo: [Float]
                    let hi: [Float]
                    if ka.lexicographicallyPrecedes(kb) { lo = ka; hi = kb } else { lo = kb; hi = ka }
                    counts[EdgeKey(a: lo, b: hi), default: 0] += 1
                }
                t += 3
            }
        }
        return counts
    }

    func triangles(_ m: HubCutMesh, _ list: [UInt32]) -> [(V3, V3, V3)] {
        var out: [(V3, V3, V3)] = []
        var t = 0
        while t + 2 < list.count {
            out.append((m.positions[Int(list[t])], m.positions[Int(list[t + 1])], m.positions[Int(list[t + 2])]))
            t += 3
        }
        return out
    }
    func xyArea(_ tris: [(V3, V3, V3)]) -> Double {
        var a: Double = 0
        for t in tris {
            let ux: Double = Double(t.1.x - t.0.x), uy: Double = Double(t.1.y - t.0.y)
            let vx: Double = Double(t.2.x - t.0.x), vy: Double = Double(t.2.y - t.0.y)
            a += abs(ux * vy - uy * vx) / 2
        }
        return a
    }

    func build(_ strokes: [HubCutStroke], dz: Float = -0.0115, mirror: Bool = false) -> (HubCutField, HubCutMesh) {
        let field = HubCutField(strokes: strokes, params: params)
        return (field, field.mesh(insideDz: dz, mirrorZ: mirror))
    }

    func testEveryEdgeIsSharedByTwoTrianglesExceptTheRim() {
        for dz: Float in [-0.0115, 0.008] {
            let (_, m) = build(sampleStrokes(), dz: dz)
            let counts = edgeCounts(m)
            var rimEdges = 0
            for (k, n) in counts {
                XCTAssertLessThanOrEqual(n, 2, "edge shared by more than two triangles")
                if n == 1 {
                    rimEdges += 1
                    // A single-sided edge must lie on the rim circle at the dome rim height.
                    let ra = (k.a[0] * k.a[0] + k.a[1] * k.a[1]).squareRoot()
                    let rb = (k.b[0] * k.b[0] + k.b[1] * k.b[1]).squareRoot()
                    XCTAssertEqual(ra, 0.33, accuracy: 1e-5)
                    XCTAssertEqual(rb, 0.33, accuracy: 1e-5)
                }
            }
            XCTAssertEqual(rimEdges, m.rim.count, "open edges are exactly the rim polygon")
            XCTAssertGreaterThan(m.rim.count, 100)
        }
    }

    func testFacePlusFloorTileTheRimPolygon() {
        let (_, m) = build(sampleStrokes())
        var floorArea: Double = 0
        for f in m.floors { floorArea += xyArea(triangles(m, f)) }
        let faceArea: Double = xyArea(triangles(m, m.face))
        var poly: Double = 0
        for k in 0..<m.rim.count {
            let a: V2 = m.rim[k]
            let b: V2 = m.rim[(k + 1) % m.rim.count]
            poly += Double(a.x * b.y - a.y * b.x) / 2
        }
        XCTAssertEqual(faceArea + floorArea, abs(poly), accuracy: abs(poly) * 1e-5)
    }

    func testFloorAreaMatchesTheMarkArea() {
        let strokes = sampleStrokes()
        let (_, m) = build(strokes)
        var floorArea: Double = 0
        for f in m.floors { floorArea += xyArea(triangles(m, f)) }
        // Reference: dense point sampling of the true distance field.
        var inside = 0
        let step: Float = 0.001
        var y: Float = -0.2
        while y < 0.2 {
            var x: Float = -0.2
            while x < 0.2 {
                if bruteDistance(strokes, V2(x, y)) < 0 { inside += 1 }
                x += step
            }
            y += step
        }
        let reference: Double = Double(inside) * Double(step * step)
        XCTAssertEqual(floorArea, reference, accuracy: reference * 0.02)
    }

    func testPieceFloorsSplitTheMark() {
        let strokes = sampleStrokes()
        let (_, m) = build(strokes)
        XCTAssertEqual(m.floors.count, 2)
        XCTAssertGreaterThan(xyArea(triangles(m, m.floors[0])), 0.002)
        XCTAssertGreaterThan(xyArea(triangles(m, m.floors[1])), 0.002)
        XCTAssertFalse(m.walls[0].isEmpty)
        XCTAssertFalse(m.walls[1].isEmpty)
    }

    func testOutlineVerticesLieOnTheTrueOutline() {
        let strokes = sampleStrokes()
        let (_, m) = build(strokes)
        var checked = 0
        for list in m.walls {
            for idx in list {
                let p: V3 = m.positions[Int(idx)]
                let d: Float = bruteDistance(strokes, V2(p.x, p.y))
                XCTAssertEqual(d, 0, accuracy: 0.02 * params.cell)
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 1000)
    }

    func testNoDegenerateTriangles() {
        for dz: Float in [-0.0115, 0.008] {
            let (_, m) = build(sampleStrokes(), dz: dz)
            var lists: [[UInt32]] = [m.face]
            lists.append(contentsOf: m.floors)
            lists.append(contentsOf: m.walls)
            var smallest: Float = 1
            for list in lists {
                for t in triangles(m, list) {
                    let area: Float = simd_length(simd_cross(t.1 - t.0, t.2 - t.0)) / 2
                    smallest = min(smallest, area)
                    XCTAssertGreaterThan(area, 1e-12)
                }
            }
            XCTAssertGreaterThan(smallest, 1e-12)
        }
    }

    func testWindingFollowsVertexNormals() {
        for mirror in [false, true] {
            let (_, m) = build(sampleStrokes(), mirror: mirror)
            var lists: [[UInt32]] = [m.face]
            lists.append(contentsOf: m.floors)
            lists.append(contentsOf: m.walls)
            for list in lists {
                var t = 0
                while t + 2 < list.count {
                    let a = m.positions[Int(list[t])], b = m.positions[Int(list[t + 1])], c = m.positions[Int(list[t + 2])]
                    let g: V3 = simd_cross(b - a, c - a)
                    let n: V3 = m.normals[Int(list[t])] + m.normals[Int(list[t + 1])] + m.normals[Int(list[t + 2])]
                    XCTAssertGreaterThanOrEqual(simd_dot(g, n), 0)
                    t += 3
                }
            }
        }
    }

    func testCutDepthAndWallHeight() {
        let (_, m) = build(sampleStrokes(), dz: -0.0115)
        let dome: (Float, Float) -> Float = { (x: Float, y: Float) -> Float in
            let r: Float = (x * x + y * y).squareRoot()
            let ratio: Float = r / 0.33
            return 0.18 - 0.008 * ratio * ratio
        }
        for f in m.floors {
            for idx in f {
                let p: V3 = m.positions[Int(idx)]
                XCTAssertEqual(p.z, dome(p.x, p.y) - 0.0115, accuracy: 1e-6)
            }
        }
        for w in m.walls {
            for idx in w {
                let p: V3 = m.positions[Int(idx)]
                let top: Float = dome(p.x, p.y)
                let atTop: Bool = abs(p.z - top) < 1e-6
                let atFloor: Bool = abs(p.z - (top - 0.0115)) < 1e-6
                XCTAssertTrue(atTop || atFloor)
                XCTAssertEqual(m.normals[Int(idx)].z, 0, accuracy: 1e-6)
            }
        }
    }

    func testCutWallNormalsFaceTheChannelAndRaisedWallNormalsFaceOut() {
        let strokes = sampleStrokes()
        for (dz, expectInward) in [(Float(-0.0115), true), (Float(0.008), false)] {
            let (_, m) = build(strokes, dz: dz)
            var checked = 0
            for w in m.walls {
                for idx in w {
                    let p: V3 = m.positions[Int(idx)]
                    let n: V3 = m.normals[Int(idx)]
                    // Step along the normal by a little: it enters the mark when the wall faces the channel.
                    let q = V2(p.x + n.x * 0.002, p.y + n.y * 0.002)
                    let d: Float = bruteDistance(strokes, q)
                    if expectInward { XCTAssertLessThan(d, 0.0005) } else { XCTAssertGreaterThan(d, -0.0005) }
                    checked += 1
                }
            }
            XCTAssertGreaterThan(checked, 1000)
        }
    }

    func testRaisedTopSitsAboveTheFace() {
        let (_, m) = build(sampleStrokes(), dz: 0.008)
        for f in m.floors {
            for idx in f {
                let p: V3 = m.positions[Int(idx)]
                let r: Float = (p.x * p.x + p.y * p.y).squareRoot()
                let ratio: Float = r / 0.33
                XCTAssertEqual(p.z, 0.18 - 0.008 * ratio * ratio + 0.008, accuracy: 1e-6)
            }
        }
    }

    func testMirroredMarkBuildsTheMirroredMesh() {
        let (_, a) = build(sampleStrokes())
        let (_, b) = build(sampleStrokes(mirrorX: true))
        func areas(_ m: HubCutMesh) -> [Double] { m.floors.map { xyArea(triangles(m, $0)) } }
        let aa = areas(a), bb = areas(b)
        for k in 0..<aa.count { XCTAssertEqual(aa[k], bb[k], accuracy: aa[k] * 0.01) }
        // Bounding boxes of the floors are mirrored.
        func box(_ m: HubCutMesh) -> (Float, Float) {
            var lo: Float = 9, hi: Float = -9
            for f in m.floors { for i in f { lo = min(lo, m.positions[Int(i)].x); hi = max(hi, m.positions[Int(i)].x) } }
            return (lo, hi)
        }
        let ba = box(a), bb2 = box(b)
        XCTAssertEqual(ba.0, -bb2.1, accuracy: 0.004)
        XCTAssertEqual(ba.1, -bb2.0, accuracy: 0.004)
    }

    func testBackHubIsMirroredInZ() {
        let (_, front) = build(sampleStrokes(), mirror: false)
        let (_, back) = build(sampleStrokes(), mirror: true)
        XCTAssertEqual(front.positions.count, back.positions.count)
        for k in 0..<front.positions.count {
            XCTAssertEqual(front.positions[k].x, back.positions[k].x)
            XCTAssertEqual(front.positions[k].z, -back.positions[k].z)
            XCTAssertEqual(front.normals[k].z, -back.normals[k].z, accuracy: 1e-6)
        }
        XCTAssertEqual(front.rimZ, -back.rimZ)
    }

    func testRimVerticesAreOnTheRimCircle() {
        let (field, m) = build(sampleStrokes())
        XCTAssertLessThan(field.cornerRadius, 0.33)
        for p in m.rim { XCTAssertEqual(simd_length(p), 0.33, accuracy: 1e-6) }
    }

    func testTriangleCountAndBuildTimeAreModest() {
        let t0 = DispatchTime.now().uptimeNanoseconds
        let (_, m) = build(sampleStrokes())
        let ms: Double = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        XCTAssertLessThan(m.triangleCount, 60_000)
        XCTAssertLessThan(ms, 1500, "Debug build; the app's target is well under 100 ms per hub")
    }

    func testEmptyMarkStillBuildsAPlainFace() {
        let (_, m) = build([])
        XCTAssertTrue(m.floors[0].isEmpty)
        XCTAssertFalse(m.face.isEmpty)
        let counts = edgeCounts(m)
        for (_, n) in counts { XCTAssertLessThanOrEqual(n, 2) }
    }
}
