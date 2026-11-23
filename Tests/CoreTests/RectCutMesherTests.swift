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

final class RectCutMesherTests: XCTestCase {

    /// Signed distance to a capsule (negative inside).
    private func capsule(_ a: P2, _ b: P2, _ hw: Float) -> (Float, Float) -> Float {
        return { (x: Float, y: Float) -> Float in
            let p = P2(x, y)
            let ab = b - a
            let l2: Float = ab.x * ab.x + ab.y * ab.y
            var t: Float = 0
            if l2 > 0 { t = min(max(simd_dot(p - a, ab) / l2, 0), 1) }
            return simd_length(p - (a + ab * t)) - hw
        }
    }

    private func area(_ m: CutGridMesh, _ idx: [UInt32]) -> Float {
        var s: Float = 0
        var k = 0
        while k < idx.count {
            let a = m.vertices[Int(idx[k])].uv, b = m.vertices[Int(idx[k + 1])].uv, c = m.vertices[Int(idx[k + 2])].uv
            s += ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)) * 0.5
            k += 3
        }
        return s
    }

    private func buildSample() -> (CutGridMesh, [Float], [Float]) {
        let xs: [Float] = CutGrid.join([CutGrid.uniform(-0.1, -0.06, step: 0.04), CutGrid.uniform(-0.06, 0.06, step: 0.004), CutGrid.uniform(0.06, 0.1, step: 0.04)])
        let ys: [Float] = CutGrid.uniform(-0.05, 0.05, step: 0.004)
        let f1 = capsule(P2(-0.04, -0.01), P2(0.03, 0.015), 0.008)
        let f2 = capsule(P2(-0.03, 0.035), P2(0.03, 0.035), 0.006)
        let m = RectCutMesher.mesh(xs: xs, ys: ys, activeColumns: nil) { (x: Float, y: Float) -> Float in min(f1(x, y), f2(x, y)) }
        return (m, xs, ys)
    }

    func testFaceAndFloorAreasFillTheRectangle() {
        let (m, xs, ys) = buildSample()
        let rect: Float = (xs.last! - xs.first!) * (ys.last! - ys.first!)
        let total: Float = area(m, m.face) + area(m, m.floor)
        XCTAssertEqual(total, rect, accuracy: rect * 1e-4)
        XCTAssertGreaterThan(area(m, m.floor), 0)
        XCTAssertGreaterThan(area(m, m.face), 0)
        XCTAssertGreaterThan(m.wall.count, 0)
    }

    func testFloorAreaMatchesTheAnalyticCutRegion() {
        let (m, _, _) = buildSample()
        // Two capsules (they do not overlap): length * 2hw + pi hw^2 each.
        let l1: Float = simd_length(P2(0.07, 0.025))
        let l2: Float = 0.06
        let expected: Float = l1 * 0.016 + Float.pi * 0.008 * 0.008 + l2 * 0.012 + Float.pi * 0.006 * 0.006
        XCTAssertEqual(area(m, m.floor), expected, accuracy: expected * 0.03)
    }

    func testMeshIsWatertightEveryInteriorEdgeIsSharedByTwoTriangles() {
        let (m, xs, ys) = buildSample()
        struct Key: Hashable { var a: [Int32]; var b: [Int32] }
        func q(_ v: CutVertex) -> [Int32] {
            let u: Int32 = Int32((v.uv.x * 1e5).rounded())
            let w: Int32 = Int32((v.uv.y * 1e5).rounded())
            return [u, w, v.onFloor ? 1 : 0]
        }
        var counts: [Key: Int] = [:]
        let all: [[UInt32]] = [m.face, m.floor, m.wall]
        for idx in all {
            var k = 0
            while k < idx.count {
                let t: [UInt32] = [idx[k], idx[k + 1], idx[k + 2]]
                for e in 0..<3 {
                    let pa = q(m.vertices[Int(t[e])]), pb = q(m.vertices[Int(t[(e + 1) % 3])])
                    let key: Key = pa.lexicographicallyPrecedes(pb) ? Key(a: pa, b: pb) : Key(a: pb, b: pa)
                    counts[key, default: 0] += 1
                }
                k += 3
            }
        }
        let x0: Int32 = Int32((xs.first! * 1e5).rounded()), x1: Int32 = Int32((xs.last! * 1e5).rounded())
        let y0: Int32 = Int32((ys.first! * 1e5).rounded()), y1: Int32 = Int32((ys.last! * 1e5).rounded())
        var bad = 0
        for (key, n) in counts {
            let onBoundary: Bool = (key.a[0] == x0 && key.b[0] == x0) || (key.a[0] == x1 && key.b[0] == x1)
                || (key.a[1] == y0 && key.b[1] == y0) || (key.a[1] == y1 && key.b[1] == y1)
            // A wall's two vertical edges are shared with the neighbouring wall quad; its top edge with the face, its bottom with the floor.
            if onBoundary { if n != 1 { bad += 1 } } else if n != 2 { bad += 1 }
        }
        XCTAssertEqual(bad, 0)
    }

    func testWallVerticesCarryUnitOutwardGradient() {
        let (m, _, _) = buildSample()
        var walls = 0
        for v in m.vertices where simd_length(v.gradient) > 0 {
            walls += 1
            XCTAssertEqual(simd_length(v.gradient), 1, accuracy: 1e-3)
        }
        XCTAssertGreaterThan(walls, 10)
    }

    func testInactiveColumnsAreNeverSampled() {
        let xs: [Float] = [0, 1, 2, 3]
        let ys: [Float] = [0, 1]
        var calls = 0
        let active: [Bool] = [false, true, false]
        _ = RectCutMesher.mesh(xs: xs, ys: ys, activeColumns: active) { (x: Float, y: Float) -> Float in
            calls += 1
            return 1
        }
        // Columns 1 and 2 (vertices at x = 1 and 2) are touched by the active cell column; 2 vertices * 2 rows.
        XCTAssertEqual(calls, 4)
    }
}
