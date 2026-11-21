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
@testable import MacVisualizerCore

final class DelaunayTests: XCTestCase {

    func testTwoTrianglesFromUnitSquare() {
        let pts: [SIMD2<Float>] = [
            SIMD2(-1, -1), SIMD2(1, -1), SIMD2(1, 1), SIMD2(-1, 1)
        ]
        let triangles = Delaunay.triangulate(points: pts)
        XCTAssertEqual(triangles.count, 2, "unit square should triangulate to exactly 2 triangles")
        // Each triangle should reference 3 unique vertex indices in 0..<4
        for t in triangles {
            let indices = [t.a, t.b, t.c]
            XCTAssertEqual(Set(indices).count, 3, "triangle has duplicate vertex")
            for i in indices { XCTAssertTrue(i >= 0 && i < 4) }
        }
    }

    func testAllTrianglesCCWOriented() {
        // Random non-degenerate points
        var rng = SeededRNG(seed: 0xDEAD1234)
        var pts: [SIMD2<Float>] = []
        for _ in 0..<20 { pts.append(SIMD2(rng.nextSigned(), rng.nextSigned())) }
        let triangles = Delaunay.triangulate(points: pts)
        for t in triangles {
            let a = pts[t.a], b = pts[t.b], c = pts[t.c]
            // CCW: (b-a) cross (c-a) > 0
            let cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
            XCTAssertGreaterThan(cross, 0, "triangle \(t) is CW or degenerate")
        }
    }

    func testTriangleCountBounded() {
        // Euler's formula for a triangulated planar point set: T ≤ 2N - 2 - h
        // where h is the convex hull point count. For our purposes, T ≤ 2N - 5 is conservative.
        var rng = SeededRNG(seed: 0xBEEF5678)
        var pts: [SIMD2<Float>] = []
        for _ in 0..<30 { pts.append(SIMD2(rng.nextSigned(), rng.nextSigned())) }
        let triangles = Delaunay.triangulate(points: pts)
        XCTAssertLessThanOrEqual(triangles.count, 2 * 30, "triangle count exceeds 2N bound")
    }

    func testVoronoiCellsCoverInput() {
        // For 4 corner points, each should get a Voronoi cell.
        let pts: [SIMD2<Float>] = [
            SIMD2(-0.5, -0.5), SIMD2(0.5, -0.5), SIMD2(0.5, 0.5), SIMD2(-0.5, 0.5)
        ]
        let cells = Delaunay.voronoiCells(points: pts)
        XCTAssertEqual(cells.count, 4, "expected one cell per input point")
        for cell in cells {
            XCTAssertGreaterThanOrEqual(cell.vertices.count, 3, "cell has fewer than 3 vertices")
        }
    }
}