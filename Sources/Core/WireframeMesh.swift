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
import simd

/// A subdivided icosphere: unit-sphere vertices + unique edges. Built once;
/// the visualizer rotates / deforms these per frame.
struct WireframeMesh {
    let vertices: [SIMD3<Float>]
    let edges: [(Int, Int)]   // each pair sorted i < j, deduplicated

    /// Build an icosphere by starting from a golden-ratio icosahedron (12 verts,
    /// 20 faces) and subdividing each face into 4 sub-faces `subdivisions` times.
    /// Each subdivision adds a midpoint vertex per edge and renormalizes it to
    /// unit length. Shared edges share their midpoint via a vertex cache.
    static func icosphere(subdivisions: Int) -> WireframeMesh {
        precondition(subdivisions >= 0, "subdivisions must be non-negative")

        // --- Base icosahedron (12 verts, 20 faces) -------------------------
        let phi: Float = (1 + sqrt(5)) / 2
        var verts: [SIMD3<Float>] = [
            SIMD3(-1,  phi, 0), SIMD3( 1,  phi, 0),
            SIMD3(-1, -phi, 0), SIMD3( 1, -phi, 0),
            SIMD3( 0, -1,  phi), SIMD3( 0,  1,  phi),
            SIMD3( 0, -1, -phi), SIMD3( 0,  1, -phi),
            SIMD3( phi, 0, -1), SIMD3( phi, 0,  1),
            SIMD3(-phi, 0, -1), SIMD3(-phi, 0,  1)
        ].map { simd_normalize($0) }

        var faces: [(Int, Int, Int)] = [
            (0,11, 5), ( 0, 5, 1), ( 0, 1, 7), ( 0, 7,10), ( 0,10,11),
            (1, 5, 9), ( 5,11, 4), (11,10, 2), (10, 7, 6), ( 7, 1, 8),
            (3, 9, 4), ( 3, 4, 2), ( 3, 2, 6), ( 3, 6, 8), ( 3, 8, 9),
            (4, 9, 5), ( 2, 4,11), ( 6, 2,10), ( 8, 6, 7), ( 9, 8, 1)
        ]

        // --- Subdivide -----------------------------------------------------
        var midpointCache: [Int64: Int] = [:]

        func midpoint(_ a: Int, _ b: Int) -> Int {
            let key: Int64 = a < b ? Int64(a) << 32 | Int64(b) : Int64(b) << 32 | Int64(a)
            if let cached = midpointCache[key] { return cached }
            let v = simd_normalize((verts[a] + verts[b]) * 0.5)
            verts.append(v)
            let index = verts.count - 1
            midpointCache[key] = index
            return index
        }

        for _ in 0..<subdivisions {
            var newFaces: [(Int, Int, Int)] = []
            newFaces.reserveCapacity(faces.count * 4)
            for (a, b, c) in faces {
                let ab = midpoint(a, b)
                let bc = midpoint(b, c)
                let ca = midpoint(c, a)
                newFaces.append((a, ab, ca))
                newFaces.append((b, bc, ab))
                newFaces.append((c, ca, bc))
                newFaces.append((ab, bc, ca))
            }
            faces = newFaces
        }

        // --- Extract unique edges ------------------------------------------
        var edgeSet = Set<Int64>()
        var edges: [(Int, Int)] = []
        func addEdge(_ a: Int, _ b: Int) {
            let lo = min(a, b), hi = max(a, b)
            let key = Int64(lo) << 32 | Int64(hi)
            if !edgeSet.contains(key) {
                edgeSet.insert(key)
                edges.append((lo, hi))
            }
        }
        for (a, b, c) in faces {
            addEdge(a, b)
            addEdge(b, c)
            addEdge(c, a)
        }

        return WireframeMesh(vertices: verts, edges: edges)
    }
}