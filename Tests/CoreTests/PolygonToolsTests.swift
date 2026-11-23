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

final class PolygonToolsTests: XCTestCase {

    private func triArea(_ v: [P2], _ i: [UInt32], _ k: Int) -> Float {
        let a = v[Int(i[k])], b = v[Int(i[k + 1])], c = v[Int(i[k + 2])]
        return ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)) * 0.5
    }

    private func totalArea(_ t: PolygonTriangulation) -> Float {
        var s: Float = 0
        var k = 0
        while k < t.indices.count { s += triArea(t.vertices, t.indices, k); k += 3 }
        return s
    }

    func testSquareTriangulation() {
        let sq: [P2] = [P2(0, 0), P2(1, 0), P2(1, 1), P2(0, 1)]
        let t = PolygonTriangulator.triangulate(outer: sq, holes: [])
        XCTAssertEqual(t.indices.count, 6)
        XCTAssertEqual(totalArea(t), 1, accuracy: 1e-5)
    }

    func testClockwiseInputIsNormalised() {
        let sq: [P2] = [P2(0, 1), P2(1, 1), P2(1, 0), P2(0, 0)]
        let t = PolygonTriangulator.triangulate(outer: sq, holes: [])
        XCTAssertEqual(totalArea(t), 1, accuracy: 1e-5)
    }

    func testConcavePolygonAreaAndWinding() {
        let l: [P2] = [P2(0, 0), P2(2, 0), P2(2, 1), P2(1, 1), P2(1, 2), P2(0, 2)]
        let t = PolygonTriangulator.triangulate(outer: l, holes: [])
        XCTAssertEqual(totalArea(t), 3, accuracy: 1e-5)
        var k = 0
        while k < t.indices.count { XCTAssertGreaterThan(triArea(t.vertices, t.indices, k), 0); k += 3 }
    }

    func testHolesRemoveTheirArea() {
        let outer = circlePolygon(center: P2(0, 0), radius: 1, segments: 64)
        let h1 = circlePolygon(center: P2(0.4, 0.1), radius: 0.15, segments: 24)
        let h2 = circlePolygon(center: P2(-0.45, -0.2), radius: 0.2, segments: 24)
        let h3 = circlePolygon(center: P2(0.0, -0.6), radius: 0.1, segments: 16)
        let t = PolygonTriangulator.triangulate(outer: outer, holes: [h1, h2, h3])
        let expected: Float = polygonSignedArea(outer) - abs(polygonSignedArea(h1)) - abs(polygonSignedArea(h2)) - abs(polygonSignedArea(h3))
        XCTAssertEqual(totalArea(t), expected, accuracy: 1e-4)
        // No triangle centroid lies inside a hole.
        var k = 0
        while k < t.indices.count {
            let a = t.vertices[Int(t.indices[k])], b = t.vertices[Int(t.indices[k + 1])], c = t.vertices[Int(t.indices[k + 2])]
            let g: P2 = (a + b + c) / 3
            XCTAssertFalse(polygonContains(h1, g)); XCTAssertFalse(polygonContains(h2, g)); XCTAssertFalse(polygonContains(h3, g))
            XCTAssertGreaterThan(triArea(t.vertices, t.indices, k), 0)
            k += 3
        }
    }

    func testEveryInputVertexIsUsed() {
        let outer = circlePolygon(center: P2(0, 0), radius: 1, segments: 40)
        let hole = circlePolygon(center: P2(0.1, 0), radius: 0.3, segments: 20)
        let t = PolygonTriangulator.triangulate(outer: outer, holes: [hole])
        var used = Set<UInt32>()
        for i in t.indices { used.insert(i) }
        XCTAssertEqual(used.count, outer.count + hole.count)
    }

    func testWingPadWithScrewHolesTriangulatesExactly() {
        let pad = TriWing.padOutline()
        var holes: [[P2]] = []
        for c in TriWing.screwCentres { holes.append(circlePolygon(center: c, radius: TriWing.countersinkScrewRadius, segments: 24)) }
        holes.append(circlePolygon(center: TriWing.bossCenter, radius: TriWing.bossRadius, segments: 48))
        let t = PolygonTriangulator.triangulate(outer: pad, holes: holes)
        var expected: Float = polygonSignedArea(pad)
        for h in holes { expected -= abs(polygonSignedArea(h)) }
        XCTAssertEqual(totalArea(t), expected, accuracy: 2e-4)
    }

    func testBodyFaceWithCentreWellAndTubeSlotsTriangulatesExactly() {
        let body = polygonOffsetInward(TriWing.bodyOutline(), by: TriWing.bodyChamfer)
        var holes: [[P2]] = [circlePolygon(center: P2(0, 0), radius: TriWing.wellRadius, segments: 96)]
        holes.append(circlePolygon(center: P2(0.3, 0.3), radius: 0.05, segments: 12))
        let t = PolygonTriangulator.triangulate(outer: body, holes: holes)
        var expected: Float = polygonSignedArea(body)
        for h in holes { expected -= abs(polygonSignedArea(h)) }
        XCTAssertEqual(totalArea(t), expected, accuracy: 5e-4)
    }

    func testOffsetInwardShrinksAndStaysInside() {
        let body = TriWing.bodyOutline()
        let inset = polygonOffsetInward(body, by: 0.016)
        XCTAssertLessThan(polygonSignedArea(inset), polygonSignedArea(body))
        for q in inset {
            XCTAssertTrue(polygonContains(body, q))
            XCTAssertEqual(polygonBoundaryDistance(body, q), 0.016, accuracy: 0.006)
        }
    }

    func testSampledArcMatchesSvgSemantics() {
        // Half circle from (-1,0) to (1,0), sweep=1 in y-down axes goes through (0,-1).
        var path = SampledPath(step: 0.05)
        path.move(to: P2(-1, 0))
        path.arc(radius: 1, large: false, sweep: true, to: P2(1, 0))
        var minY: Float = 0
        for q in path.points { minY = min(minY, q.y) }
        XCTAssertEqual(minY, -1, accuracy: 0.01)
        for q in path.points { XCTAssertEqual(simd_length(q), 1, accuracy: 1e-3) }
    }
}

final class TriWingFaceTriangulationTests: XCTestCase {
    func testBodyTopFaceWithWellAndAllSixTubeSlotsKeepsItsFullArea() {
        let inset = polygonOffsetInward(TriWing.bodyOutline(), by: TriWing.bodyChamfer)
        var holes: [[P2]] = [circlePolygon(center: P2(0, 0), radius: TriWing.wellRadius, segments: 120)]
        for k in 0..<3 {
            for side: Float in [-1, 1] {
                holes.append(polygonRotated(TriWing.flankSlotOutline(side: side), by: TriWing.wingAngle(k)))
            }
        }
        let t = PolygonTriangulator.triangulate(outer: inset, holes: holes)
        var area: Float = 0
        var k = 0
        while k < t.indices.count {
            let a = t.vertices[Int(t.indices[k])], b = t.vertices[Int(t.indices[k + 1])], c = t.vertices[Int(t.indices[k + 2])]
            area += ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)) * 0.5
            k += 3
        }
        var expected: Float = polygonSignedArea(inset)
        for h in holes { expected -= abs(polygonSignedArea(h)) }
        XCTAssertEqual(area, expected, accuracy: 1e-3)
        // Coverage: every sample point of the face is covered by exactly one triangle, none inside a hole.
        var wrong = 0
        var gy: Float = -1
        while gy <= 1 {
            var gx: Float = -1
            while gx <= 1 {
                let q = P2(gx, gy)
                var inHole = false
                for h in holes where polygonContains(h, q) { inHole = true }
                let want: Int = (polygonContains(inset, q) && !inHole) ? 1 : 0
                var got = 0
                var k = 0
                while k < t.indices.count {
                    let a = t.vertices[Int(t.indices[k])], b = t.vertices[Int(t.indices[k + 1])], c = t.vertices[Int(t.indices[k + 2])]
                    let d1 = (q.x - b.x) * (a.y - b.y) - (a.x - b.x) * (q.y - b.y)
                    let d2 = (q.x - c.x) * (b.y - c.y) - (b.x - c.x) * (q.y - c.y)
                    let d3 = (q.x - a.x) * (c.y - a.y) - (c.x - a.x) * (q.y - a.y)
                    let neg = d1 < 0 || d2 < 0 || d3 < 0
                    let pos = d1 > 0 || d2 > 0 || d3 > 0
                    if !(neg && pos) { got += 1 }
                    k += 3
                }
                if got != want { wrong += 1 }
                gx += 0.01
            }
            gy += 0.01
        }
        XCTAssertEqual(wrong, 0)
    }
}
