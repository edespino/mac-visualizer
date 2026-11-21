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

final class WireframeMeshTests: XCTestCase {
    func testBaseIcosahedronCounts() {
        // Subdivision 0 = base icosahedron: 12 vertices, 30 edges (Euler: V-E+F=2 → E=V+F-2=12+20-2=30).
        let m = WireframeMesh.icosphere(subdivisions: 0)
        XCTAssertEqual(m.vertices.count, 12)
        XCTAssertEqual(m.edges.count, 30)
    }

    func testSubdivision1Counts() {
        // After 1 subdivision: 42 vertices (12 + 30 midpoints), 120 edges.
        let m = WireframeMesh.icosphere(subdivisions: 1)
        XCTAssertEqual(m.vertices.count, 42)
        XCTAssertEqual(m.edges.count, 120)
    }

    func testSubdivision2Counts() {
        // After 2 subdivisions: 162 vertices (42 + 120 midpoints), 480 edges.
        let m = WireframeMesh.icosphere(subdivisions: 2)
        XCTAssertEqual(m.vertices.count, 162)
        XCTAssertEqual(m.edges.count, 480)
    }

    func testAllVerticesAreUnitLength() {
        let m = WireframeMesh.icosphere(subdivisions: 2)
        for (i, v) in m.vertices.enumerated() {
            let len = simd_length(v)
            XCTAssertEqual(len, 1, accuracy: 1e-4, "vertex \(i) not unit length (got \(len))")
        }
    }

    func testEdgesAreSortedAndUnique() {
        let m = WireframeMesh.icosphere(subdivisions: 2)
        var seen = Set<String>()
        for (i, j) in m.edges {
            XCTAssertLessThan(i, j, "edge (\(i), \(j)) is not sorted i < j")
            let key = "\(i)-\(j)"
            XCTAssertFalse(seen.contains(key), "duplicate edge \(key)")
            seen.insert(key)
        }
    }
}