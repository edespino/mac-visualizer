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

/// Delaunay triangulation + Voronoi-dual computation, both deterministic
/// given the input point order. Implementation: Bowyer–Watson incremental
/// algorithm. Intended for small N (≤ ~200 points); not optimized for huge
/// point clouds.
public enum Delaunay {

    public struct Triangle: Equatable {
        public let a: Int    // index into input points array
        public let b: Int
        public let c: Int
    }

    public struct VoronoiCell {
        public let seedIndex: Int          // which input point this cell belongs to
        public let vertices: [SIMD2<Float>]  // polygon vertices in CCW order
    }

    /// Triangulate the input point set. Returns CCW-oriented triangles
    /// referencing original input indices. Skips degenerate (collinear) input.
    public static func triangulate(points: [SIMD2<Float>]) -> [Triangle] {
        guard points.count >= 3 else { return [] }
        let N = points.count
        let (allTriangles, _) = bowyerWatson(points: points)
        return allTriangles.filter { $0.a < N && $0.b < N && $0.c < N }
    }

    /// Compute Voronoi cells (polygonal regions) for the input point set.
    /// For each input point, finds Delaunay triangles containing it and
    /// connects their circumcenters in angular order. Includes super-triangle
    /// adjacencies so convex-hull cells receive boundary circumcenters and
    /// always have ≥3 polygon vertices (for N ≥ 4 non-degenerate inputs).
    public static func voronoiCells(points: [SIMD2<Float>]) -> [VoronoiCell] {
        guard points.count >= 3 else { return [] }
        let N = points.count
        // Retain super-triangle triangles so boundary cells get circumcenters
        // from those triangles, giving every convex-hull cell ≥3 vertices.
        let (allTriangles, allPoints) = bowyerWatson(points: points)
        var cells: [VoronoiCell] = []
        for i in 0..<N {
            var circumcenters: [SIMD2<Float>] = []
            for t in allTriangles where t.a == i || t.b == i || t.c == i {
                let cc = circumcenter(allPoints[t.a], allPoints[t.b], allPoints[t.c])
                circumcenters.append(cc)
            }
            // Sort circumcenters CCW around the seed point.
            let seed = points[i]
            circumcenters.sort { lhs, rhs in
                atan2(lhs.y - seed.y, lhs.x - seed.x) < atan2(rhs.y - seed.y, rhs.x - seed.x)
            }
            cells.append(VoronoiCell(seedIndex: i, vertices: circumcenters))
        }
        return cells
    }

    // MARK: - Core Bowyer-Watson implementation

    /// Runs the full Bowyer–Watson algorithm and returns:
    /// - all triangles (including those referencing super-triangle vertices N, N+1, N+2)
    /// - the extended point array (input points + 3 super-triangle vertices)
    private static func bowyerWatson(points: [SIMD2<Float>]) -> ([Triangle], [SIMD2<Float>]) {
        let N = points.count

        // 1. Build a super-triangle that contains all input points.
        let bounds = pointBounds(points)
        let dx = bounds.maxX - bounds.minX, dy = bounds.maxY - bounds.minY
        let deltaMax = max(dx, dy) * 10
        let midX = (bounds.minX + bounds.maxX) / 2
        let midY = (bounds.minY + bounds.maxY) / 2
        // Super-triangle must be CCW so circumcircleContains (which assumes CCW) works.
        // stA bottom-left, stB bottom-right, stC top-center → CCW order.
        let stA = SIMD2<Float>(midX - 20 * deltaMax, midY - deltaMax)
        let stB = SIMD2<Float>(midX + 20 * deltaMax, midY - deltaMax)
        let stC = SIMD2<Float>(midX,                 midY + 20 * deltaMax)
        // Super-triangle vertices live at indices N, N+1, N+2 in the extended array.
        let allPoints = points + [stA, stB, stC]
        var triangles: [Triangle] = [Triangle(a: N, b: N + 1, c: N + 2)]

        // 2. Add each point one at a time.
        for i in 0..<N {
            let p = allPoints[i]
            var badEdges: [(Int, Int)] = []
            var newTriangles: [Triangle] = []
            for t in triangles {
                if circumcircleContains(p,
                                        a: allPoints[t.a], b: allPoints[t.b], c: allPoints[t.c]) {
                    badEdges.append((t.a, t.b))
                    badEdges.append((t.b, t.c))
                    badEdges.append((t.c, t.a))
                } else {
                    newTriangles.append(t)
                }
            }
            // Edges that appear exactly once form the hole boundary.
            let boundaryEdges = uniqueEdges(badEdges)
            // Triangulate the hole by connecting each boundary edge to p.
            for edge in boundaryEdges {
                let tri = ccwTriangle(allPoints, a: edge.0, b: edge.1, c: i)
                newTriangles.append(tri)
            }
            triangles = newTriangles
        }

        return (triangles, allPoints)
    }

    // MARK: - Internal geometry helpers

    private static func pointBounds(_ pts: [SIMD2<Float>]) -> (minX: Float, minY: Float, maxX: Float, maxY: Float) {
        var minX = Float.infinity, minY = Float.infinity
        var maxX = -Float.infinity, maxY = -Float.infinity
        for p in pts {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return (minX, minY, maxX, maxY)
    }

    private static func circumcircleContains(_ p: SIMD2<Float>, a: SIMD2<Float>, b: SIMD2<Float>, c: SIMD2<Float>) -> Bool {
        let ax = a.x - p.x, ay = a.y - p.y
        let bx = b.x - p.x, by = b.y - p.y
        let cx = c.x - p.x, cy = c.y - p.y
        let det =
            (ax * ax + ay * ay) * (bx * cy - cx * by)
          - (bx * bx + by * by) * (ax * cy - cx * ay)
          + (cx * cx + cy * cy) * (ax * by - bx * ay)
        // For CCW (a,b,c), p is inside circumcircle iff det > 0.
        return det > 0
    }

    private static func circumcenter(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> SIMD2<Float> {
        let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        if abs(d) < 1e-10 {
            // Degenerate (collinear) — return centroid as fallback.
            return SIMD2((a.x + b.x + c.x) / 3, (a.y + b.y + c.y) / 3)
        }
        let aSq = a.x * a.x + a.y * a.y
        let bSq = b.x * b.x + b.y * b.y
        let cSq = c.x * c.x + c.y * c.y
        let ux = (aSq * (b.y - c.y) + bSq * (c.y - a.y) + cSq * (a.y - b.y)) / d
        let uy = (aSq * (c.x - b.x) + bSq * (a.x - c.x) + cSq * (b.x - a.x)) / d
        return SIMD2(ux, uy)
    }

    private static func uniqueEdges(_ edges: [(Int, Int)]) -> [(Int, Int)] {
        // An edge appears twice iff two bad triangles shared it; it appears once iff it's on the hole boundary.
        var counts: [String: Int] = [:]
        var canonical: [String: (Int, Int)] = [:]
        for e in edges {
            let key = e.0 < e.1 ? "\(e.0)_\(e.1)" : "\(e.1)_\(e.0)"
            counts[key, default: 0] += 1
            if canonical[key] == nil { canonical[key] = e }
        }
        return counts.compactMap { (k, v) in v == 1 ? canonical[k] : nil }
    }

    private static func ccwTriangle(_ pts: [SIMD2<Float>], a: Int, b: Int, c: Int) -> Triangle {
        let pa = pts[a], pb = pts[b], pc = pts[c]
        let cross = (pb.x - pa.x) * (pc.y - pa.y) - (pb.y - pa.y) * (pc.x - pa.x)
        if cross < 0 {
            return Triangle(a: a, b: c, c: b)   // swap to CCW
        }
        return Triangle(a: a, b: b, c: c)
    }
}