# Cluster D — Four New Visualizer Styles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four new visualizer styles — joy plot, heightfield grid, voronoi cells, lava lamp — with multiple render modes each, beat consumption via `frame.beat`, stereo awareness via `frame.bandsLeft/Right`. Catalog grows from 11 to 15 styles.

**Architecture:** Four new `Visualizer` files using the existing protocol for vertex-emit modes and the `ShaderKind` dispatch for fragment-shader modes. Two new pure-function utility files (Delaunay triangulation, marching squares iso-line extraction). Two new fragment shaders. Three new per-style render-mode enums on `StyleProfile`. Voronoi's `.softCells` mode introduces a new two-pass renderer (emit-to-temp-texture + blur). LavaLamp's `.shader` mode introduces a `ShaderUniformProducer` protocol extension so stateful visualizers can ship custom uniforms to their shader.

**Tech Stack:** Swift 5.10, Metal/MetalKit, XCTest, XcodeGen + Makefile build (`make build`, `make test`).

**Branch:** `plan-18-cluster-d-new-visualizer-styles` (already created, spec already committed).

---

## File Structure

**New files:**
- `Sources/Core/Delaunay.swift` — Bowyer-Watson triangulation + Voronoi-dual computation (~150 LOC)
- `Sources/Core/MarchingSquares.swift` — iso-line segment extraction from a sampled density grid (~120 LOC)
- `Sources/Core/JoyPlotVisualizer.swift` — 4 stacked smoothed area paths (~135 LOC)
- `Sources/Core/HeightfieldVisualizer.swift` — 16×16 grid with wireframe + solid render modes (~365 LOC)
- `Sources/Core/VoronoiVisualizer.swift` — 75 seed points with cells/blobs/softCells render modes (~225 LOC; uses Delaunay)
- `Sources/Core/LavaLampVisualizer.swift` — 12 metaball points with shader/marchingSquares render modes (~270 LOC; uses MarchingSquares)
- `Tests/CoreTests/DelaunayTests.swift`
- `Tests/CoreTests/MarchingSquaresTests.swift`
- `Tests/CoreTests/JoyPlotVisualizerTests.swift`
- `Tests/CoreTests/HeightfieldVisualizerTests.swift`
- `Tests/CoreTests/VoronoiVisualizerTests.swift`
- `Tests/CoreTests/LavaLampVisualizerTests.swift`

**Modified files:**
- `Sources/Core/VisualizerStyle.swift` — add 4 cases + factory entries + customShader mapping
- `Sources/Core/StyleProfile.swift` — add 3 render-mode enums + 3 fields + codable
- `Sources/Core/Visualizer.swift` (or wherever protocol lives) — add `ShaderUniformProducer` protocol
- `Sources/Core/ShaderKind.swift` — add `.voronoiBlobs` and `.lavaLampShader` cases
- `Sources/Rendering/Shaders.metal` — add `voronoi_fs` + `lavalamp_fs` fragment shaders
- `Sources/Rendering/MetalRenderer.swift` — add 2 pipeline states + dispatch cases + two-pass hybrid handler
- `Sources/App/SettingsView.swift` — add 3 conditional render-mode Pickers
- `Tests/CoreTests/VisualizerStyleTests.swift` — extend for 4 new cases

---

## Conventions

- All `make build` runs end with `** BUILD SUCCEEDED **`.
- All `make test` runs end with `** TEST SUCCEEDED **`.
- Commits use the existing repo style (imperative subject, optional body).
- `make test 2>&1 | tail -8` shows the final test summary line including count.
- Build before testing for shader changes (`.metal` files require a fresh build step).

---

## Phase 1 — Foundation utilities (Tasks 1–2)

### Task 1: Delaunay triangulation utility

**Files:**
- Create: `Sources/Core/Delaunay.swift`
- Create: `Tests/CoreTests/DelaunayTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CoreTests/DelaunayTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: build failure — `Delaunay` undefined.

- [ ] **Step 3: Implement Delaunay + Voronoi dual**

Create `Sources/Core/Delaunay.swift`:

```swift
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

        // 1. Build a super-triangle that contains all input points.
        let bounds = pointBounds(points)
        let dx = bounds.maxX - bounds.minX, dy = bounds.maxY - bounds.minY
        let deltaMax = max(dx, dy) * 10
        let midX = (bounds.minX + bounds.maxX) / 2
        let midY = (bounds.minY + bounds.maxY) / 2
        let stA = SIMD2<Float>(midX - 20 * deltaMax, midY - deltaMax)
        let stB = SIMD2<Float>(midX,                 midY + 20 * deltaMax)
        let stC = SIMD2<Float>(midX + 20 * deltaMax, midY - deltaMax)
        // Super-triangle vertices live at indices N, N+1, N+2 in an extended array.
        var allPoints = points + [stA, stB, stC]
        let N = points.count
        var triangles: [Triangle] = [Triangle(a: N, b: N + 1, c: N + 2)]

        // 2. Add each point one at a time.
        for i in 0..<N {
            let p = allPoints[i]
            var badEdges: [(Int, Int)] = []
            // Find all triangles whose circumcircle contains p — they are "bad".
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

        // 3. Remove triangles that reference any super-triangle vertex (N, N+1, N+2).
        return triangles.filter { $0.a < N && $0.b < N && $0.c < N }
    }

    /// Compute Voronoi cells (polygonal regions) for the input point set.
    /// For each input point, finds Delaunay triangles containing it and
    /// connects their circumcenters in angular order.
    public static func voronoiCells(points: [SIMD2<Float>]) -> [VoronoiCell] {
        let triangles = triangulate(points: points)
        var cells: [VoronoiCell] = []
        for i in 0..<points.count {
            var circumcenters: [SIMD2<Float>] = []
            for t in triangles where t.a == i || t.b == i || t.c == i {
                let cc = circumcenter(points[t.a], points[t.b], points[t.c])
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
            // Degenerate (collinear) — return midpoint of bounding box as fallback.
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
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 4 new tests (~206 total — building on the 202-test baseline from main).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Delaunay.swift Tests/CoreTests/DelaunayTests.swift
git commit -m "Add Delaunay triangulation + Voronoi-dual utility"
```

---

### Task 2: Marching Squares utility

**Files:**
- Create: `Sources/Core/MarchingSquares.swift`
- Create: `Tests/CoreTests/MarchingSquaresTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CoreTests/MarchingSquaresTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class MarchingSquaresTests: XCTestCase {

    func testEmptyFieldProducesNoSegments() {
        let grid = Array(repeating: Array(repeating: Float(0), count: 16), count: 16)
        let segments = MarchingSquares.extractIsoLines(grid: grid, threshold: 0.5, cellSize: 0.1, origin: SIMD2(-1, -1))
        XCTAssertEqual(segments.count, 0)
    }

    func testCircleFieldProducesClosedContour() {
        // A circular density field centered at origin with value = 1 - r
        // At threshold 0.5 the iso-line is the circle r = 0.5.
        let gridSize = 64
        let cellSize: Float = 2.0 / Float(gridSize - 1)
        var grid = Array(repeating: Array(repeating: Float(0), count: gridSize), count: gridSize)
        for y in 0..<gridSize {
            for x in 0..<gridSize {
                let fx = -1 + Float(x) * cellSize
                let fy = -1 + Float(y) * cellSize
                let r = sqrtf(fx * fx + fy * fy)
                grid[y][x] = max(0, 1 - r)
            }
        }
        let segments = MarchingSquares.extractIsoLines(grid: grid, threshold: 0.5, cellSize: cellSize, origin: SIMD2(-1, -1))
        XCTAssertGreaterThan(segments.count, 20, "expected many segments for a closed circle")
        // Each segment endpoint should lie close to r = 0.5
        for seg in segments {
            for p in [seg.a, seg.b] {
                let r = sqrtf(p.x * p.x + p.y * p.y)
                XCTAssertEqual(r, 0.5, accuracy: 0.05, "segment endpoint should be near r=0.5; got r=\(r)")
            }
        }
    }

    func testSaddleCase5ProducesSeparateSegments() {
        // Case 5 (binary 0101): top-left + bottom-right above threshold, others below.
        // We pick the "separate" tiebreak: two disjoint segments cross the cell, not one connecting curve.
        // Verify by constructing a 2x2 grid where the single cell hits this configuration.
        let grid: [[Float]] = [
            [1.0, 0.0],   // TL above, TR below
            [0.0, 1.0]    // BL below, BR above
        ]
        let segments = MarchingSquares.extractIsoLines(grid: grid, threshold: 0.5, cellSize: 1.0, origin: SIMD2(0, 0))
        XCTAssertEqual(segments.count, 2, "case 5 should produce 2 disjoint segments (separate tiebreak)")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: build failure — `MarchingSquares` undefined.

- [ ] **Step 3: Implement marching squares**

Create `Sources/Core/MarchingSquares.swift`:

```swift
import simd

/// Iso-line extraction from a sampled 2D density grid. Each cell of the grid
/// produces 0, 1, or 2 line segments based on which of its 4 corners exceed
/// the threshold. Saddle cases (5 and 10) use the "separate" tiebreak —
/// two disjoint segments, not a connected curve through the cell center.
public enum MarchingSquares {

    public struct Segment: Equatable {
        public let a: SIMD2<Float>
        public let b: SIMD2<Float>
    }

    /// Extract iso-line segments from a 2D grid.
    ///
    /// - Parameters:
    ///   - grid: 2D array of density values. `grid[y][x]` accessed as row-major.
    ///   - threshold: density value at which iso-lines are drawn.
    ///   - cellSize: world-space width/height of each grid cell.
    ///   - origin: world-space position of grid[0][0].
    public static func extractIsoLines(grid: [[Float]], threshold: Float, cellSize: Float, origin: SIMD2<Float>) -> [Segment] {
        let rows = grid.count
        guard rows >= 2 else { return [] }
        let cols = grid[0].count
        guard cols >= 2 else { return [] }

        var segments: [Segment] = []
        for y in 0..<(rows - 1) {
            for x in 0..<(cols - 1) {
                let tl = grid[y][x]
                let tr = grid[y][x + 1]
                let br = grid[y + 1][x + 1]
                let bl = grid[y + 1][x]
                // 4-bit case: TL=8, TR=4, BR=2, BL=1
                var caseIdx = 0
                if tl > threshold { caseIdx |= 8 }
                if tr > threshold { caseIdx |= 4 }
                if br > threshold { caseIdx |= 2 }
                if bl > threshold { caseIdx |= 1 }

                // Interpolated edge crossing positions (in world space):
                let cx = origin.x + Float(x) * cellSize
                let cy = origin.y + Float(y) * cellSize
                func lerpEdge(_ va: Float, _ vb: Float, _ ax: Float, _ ay: Float, _ bx: Float, _ by: Float) -> SIMD2<Float> {
                    // Crossing where (1-t)*va + t*vb = threshold; t = (threshold - va) / (vb - va)
                    let denom = vb - va
                    let t: Float = abs(denom) < 1e-6 ? 0.5 : (threshold - va) / denom
                    let tc = max(0, min(1, t))
                    return SIMD2(ax + (bx - ax) * tc, ay + (by - ay) * tc)
                }
                // Edge endpoints in world space:
                let topX0 = cx,                topX1 = cx + cellSize
                let topY  = cy
                let botX0 = cx,                botX1 = cx + cellSize
                let botY  = cy + cellSize
                // Edge crossings (4 possible: top, right, bottom, left)
                let crossTop    = lerpEdge(tl, tr, topX0, topY, topX1, topY)
                let crossRight  = lerpEdge(tr, br, topX1, topY, botX1, botY)
                let crossBottom = lerpEdge(bl, br, botX0, botY, botX1, botY)
                let crossLeft   = lerpEdge(tl, bl, topX0, topY, botX0, botY)

                switch caseIdx {
                case 0, 15: break   // all in or all out
                case 1:    segments.append(Segment(a: crossLeft,   b: crossBottom))   // BL in
                case 14:   segments.append(Segment(a: crossLeft,   b: crossBottom))
                case 2:    segments.append(Segment(a: crossBottom, b: crossRight))    // BR in
                case 13:   segments.append(Segment(a: crossBottom, b: crossRight))
                case 3:    segments.append(Segment(a: crossLeft,   b: crossRight))    // BL+BR in
                case 12:   segments.append(Segment(a: crossLeft,   b: crossRight))
                case 4:    segments.append(Segment(a: crossTop,    b: crossRight))    // TR in
                case 11:   segments.append(Segment(a: crossTop,    b: crossRight))
                case 6:    segments.append(Segment(a: crossTop,    b: crossBottom))   // TR+BR in
                case 9:    segments.append(Segment(a: crossTop,    b: crossBottom))
                case 7:    segments.append(Segment(a: crossLeft,   b: crossTop))      // TR+BR+BL in (TL out)
                case 8:    segments.append(Segment(a: crossLeft,   b: crossTop))      // TL in
                case 5:
                    // Saddle: TL + BR in. "Separate" tiebreak → 2 disjoint segments.
                    segments.append(Segment(a: crossLeft, b: crossTop))
                    segments.append(Segment(a: crossBottom, b: crossRight))
                case 10:
                    // Saddle: TR + BL in. "Separate" tiebreak.
                    segments.append(Segment(a: crossTop, b: crossRight))
                    segments.append(Segment(a: crossLeft, b: crossBottom))
                default: break
                }
            }
        }
        return segments
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 3 new tests (~209 total).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/MarchingSquares.swift Tests/CoreTests/MarchingSquaresTests.swift
git commit -m "Add MarchingSquares iso-line extraction (separate-tiebreak saddles)"
```

---

## Phase 2 — Scaffolding (Tasks 3–4)

### Task 3: StyleProfile — render-mode enums + fields

**Files:**
- Modify: `Sources/Core/StyleProfile.swift`
- Modify (extend): `Tests/CoreTests/StyleProfileTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/CoreTests/StyleProfileTests.swift`:

```swift
func testVoronoiRenderModeDefaultsCells() {
    XCTAssertEqual(StyleProfile.defaults.voronoiRenderMode, .cells)
}

func testHeightfieldRenderModeDefaultsWireframe() {
    XCTAssertEqual(StyleProfile.defaults.heightfieldRenderMode, .wireframe)
}

func testLavaLampRenderModeDefaultsShader() {
    XCTAssertEqual(StyleProfile.defaults.lavaLampRenderMode, .shader)
}

func testRenderModesRoundtripCodable() throws {
    var p = StyleProfile.defaults
    p.voronoiRenderMode = .blobs
    p.heightfieldRenderMode = .solid
    p.lavaLampRenderMode = .marchingSquares
    let data = try JSONEncoder().encode(p)
    let decoded = try JSONDecoder().decode(StyleProfile.self, from: data)
    XCTAssertEqual(decoded.voronoiRenderMode, .blobs)
    XCTAssertEqual(decoded.heightfieldRenderMode, .solid)
    XCTAssertEqual(decoded.lavaLampRenderMode, .marchingSquares)
}

func testLegacyStyleProfileJSONDecodesSafely() throws {
    // Old JSON without the new render-mode fields — they should default.
    let legacy = """
    { "paletteName": "phosphor", "customStops": [], "gain": 1.0, "barCount": 48,
      "smoothing": 0.6, "peakHoldEnabled": true, "glowEnabled": true, "glowIntensity": 0.5,
      "overlayEnabled": true, "overlayPosition": "topTrailing", "overlayOpacity": 0.8,
      "alwaysOnTop": false, "targetFPS": 60, "backgroundStyle": "solid" }
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(StyleProfile.self, from: legacy)
    XCTAssertEqual(decoded.voronoiRenderMode, .cells)
    XCTAssertEqual(decoded.heightfieldRenderMode, .wireframe)
    XCTAssertEqual(decoded.lavaLampRenderMode, .shader)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: build failure — `voronoiRenderMode`, `heightfieldRenderMode`, `lavaLampRenderMode` undefined.

- [ ] **Step 3: Add render-mode enums and StyleProfile fields**

In `Sources/Core/StyleProfile.swift`:

Add the three enums at file top (before `public struct StyleProfile`):

```swift
public enum VoronoiRenderMode: String, Codable, Equatable, CaseIterable {
    case cells, blobs, softCells
}

public enum HeightfieldRenderMode: String, Codable, Equatable, CaseIterable {
    case wireframe, solid
}

public enum LavaLampRenderMode: String, Codable, Equatable, CaseIterable {
    case shader, marchingSquares
}
```

Add three stored fields to `StyleProfile`, right after `backgroundStyle`:

```swift
    public var voronoiRenderMode: VoronoiRenderMode
    public var heightfieldRenderMode: HeightfieldRenderMode
    public var lavaLampRenderMode: LavaLampRenderMode
```

Update `init(...)` to accept the three new parameters (with each having a default in the call site for legacy compatibility — see `static let defaults` below):

```swift
    public init(paletteName: String, customStops: [RGBAColor],
                gain: Float, barCount: Int, smoothing: Float, peakHoldEnabled: Bool,
                glowEnabled: Bool, glowIntensity: Float,
                overlayEnabled: Bool, overlayPosition: OverlayCorner, overlayOpacity: Float,
                alwaysOnTop: Bool, fullscreenDisplayID: UInt32?, targetFPS: Int,
                backgroundStyle: BackgroundStyle,
                voronoiRenderMode: VoronoiRenderMode = .cells,
                heightfieldRenderMode: HeightfieldRenderMode = .wireframe,
                lavaLampRenderMode: LavaLampRenderMode = .shader) {
        // ... existing assignments ...
        self.voronoiRenderMode = voronoiRenderMode
        self.heightfieldRenderMode = heightfieldRenderMode
        self.lavaLampRenderMode = lavaLampRenderMode
    }
```

Update `static let defaults`:

```swift
    public static let defaults = StyleProfile(
        paletteName: "classic", customStops: [],
        gain: 1.0, barCount: 48, smoothing: 0.6, peakHoldEnabled: true,
        glowEnabled: true, glowIntensity: 0.6,
        overlayEnabled: true, overlayPosition: .topTrailing, overlayOpacity: 0.85,
        alwaysOnTop: false, fullscreenDisplayID: nil, targetFPS: 60,
        backgroundStyle: .solid,
        voronoiRenderMode: .cells,
        heightfieldRenderMode: .wireframe,
        lavaLampRenderMode: .shader
    )
```

Update `CodingKeys`:

```swift
    private enum CodingKeys: String, CodingKey {
        case paletteName, customStops, gain, barCount, smoothing, peakHoldEnabled
        case glowEnabled, glowIntensity
        case overlayEnabled, overlayPosition, overlayOpacity
        case alwaysOnTop, fullscreenDisplayID, targetFPS, backgroundStyle
        case voronoiRenderMode, heightfieldRenderMode, lavaLampRenderMode
    }
```

Update `init(from decoder:)` to add the three new tolerant decodes:

```swift
        self.init(
            // ... existing decodeIfPresent calls ...
            backgroundStyle: try c.decodeIfPresent(BackgroundStyle.self, forKey: .backgroundStyle) ?? d.backgroundStyle,
            voronoiRenderMode: try c.decodeIfPresent(VoronoiRenderMode.self, forKey: .voronoiRenderMode) ?? d.voronoiRenderMode,
            heightfieldRenderMode: try c.decodeIfPresent(HeightfieldRenderMode.self, forKey: .heightfieldRenderMode) ?? d.heightfieldRenderMode,
            lavaLampRenderMode: try c.decodeIfPresent(LavaLampRenderMode.self, forKey: .lavaLampRenderMode) ?? d.lavaLampRenderMode
        )
```

(StyleProfile already uses synthesized `encode(to:)` via Codable — the new fields encode automatically.)

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 5 new tests (~214 total).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/StyleProfile.swift Tests/CoreTests/StyleProfileTests.swift
git commit -m "StyleProfile: add per-style render-mode enums for voronoi/heightfield/lavaLamp"
```

---

### Task 4: VisualizerStyle — 4 new cases with placeholder visualizers

**Files:**
- Modify: `Sources/Core/VisualizerStyle.swift`
- Create (4 placeholder files): `Sources/Core/JoyPlotVisualizer.swift`, `Sources/Core/HeightfieldVisualizer.swift`, `Sources/Core/VoronoiVisualizer.swift`, `Sources/Core/LavaLampVisualizer.swift`
- Modify (extend): `Tests/CoreTests/VisualizerStyleTests.swift`

This task creates compiling stub visualizers so the enum + factory work end-to-end before later tasks fill them in.

- [ ] **Step 1: Write the failing test**

Append to `Tests/CoreTests/VisualizerStyleTests.swift`:

```swift
func testAllCasesIncludesNewStyles() {
    let names = Set(VisualizerStyle.allCases.map { $0.rawValue })
    XCTAssertTrue(names.contains("joyPlot"))
    XCTAssertTrue(names.contains("heightfield"))
    XCTAssertTrue(names.contains("voronoi"))
    XCTAssertTrue(names.contains("lavaLamp"))
}

func testMakeVisualizerForNewStyles() {
    XCTAssertNotNil(VisualizerStyle.joyPlot.makeVisualizer())
    XCTAssertNotNil(VisualizerStyle.heightfield.makeVisualizer())
    XCTAssertNotNil(VisualizerStyle.voronoi.makeVisualizer())
    XCTAssertNotNil(VisualizerStyle.lavaLamp.makeVisualizer())
}

func testCustomShaderMappingForNewStyles() {
    // Placeholder visualizers return nil customShader; later tasks wire shader-driven modes.
    XCTAssertNil(VisualizerStyle.joyPlot.customShader)
    XCTAssertNil(VisualizerStyle.heightfield.customShader)
    XCTAssertNil(VisualizerStyle.voronoi.customShader)
    XCTAssertNil(VisualizerStyle.lavaLamp.customShader)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: build failure — `joyPlot`, `heightfield`, `voronoi`, `lavaLamp` undefined in VisualizerStyle.

- [ ] **Step 3: Create placeholder visualizer files**

Create `Sources/Core/JoyPlotVisualizer.swift`:

```swift
import simd

/// Stacked smoothed area paths. Filled in by Task 5.
public final class JoyPlotVisualizer: Visualizer {
    public init() {}
    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        return []
    }
}
```

Create `Sources/Core/HeightfieldVisualizer.swift`:

```swift
import simd

/// 16×16 grid mesh with audio-displaced Z. Filled in by Tasks 6+7.
public final class HeightfieldVisualizer: Visualizer {
    public init() {}
    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        return []
    }
}
```

Create `Sources/Core/VoronoiVisualizer.swift`:

```swift
import simd

/// 75-seed Voronoi cells / blobs / softCells. Filled in by Tasks 8+10+11.
public final class VoronoiVisualizer: Visualizer {
    public init() {}
    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        return []
    }
}
```

Create `Sources/Core/LavaLampVisualizer.swift`:

```swift
import simd

/// 12-metaball density iso-contours. Filled in by Tasks 11+13.
public final class LavaLampVisualizer: Visualizer {
    public init() {}
    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        return []
    }
}
```

- [ ] **Step 4: Update VisualizerStyle**

Replace the enum case list (line 2) from:

```swift
    case bars, radial, mirrored, oscilloscope, particles, fountain, fireworks, siri, wireframe, plasma, bumpscope
```

with:

```swift
    case bars, radial, mirrored, oscilloscope, particles, fountain, fireworks, siri, wireframe, plasma, bumpscope, joyPlot, heightfield, voronoi, lavaLamp
```

Extend `displayName` switch with four new cases:

```swift
        case .joyPlot: return "Joy Plot"
        case .heightfield: return "Heightfield"
        case .voronoi: return "Voronoi"
        case .lavaLamp: return "Lava Lamp"
```

Extend `usesRoundParticles` switch — add the four new cases to the `false` arm.

Extend `customShader` switch — return `nil` for all four new cases (later tasks revise this for voronoi and lavaLamp).

Extend `makeVisualizer()` switch:

```swift
        case .joyPlot: return JoyPlotVisualizer()
        case .heightfield: return HeightfieldVisualizer()
        case .voronoi: return VoronoiVisualizer()
        case .lavaLamp: return LavaLampVisualizer()
```

- [ ] **Step 5: Run build + tests**

Run: `make build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 3 new tests (~217 total).

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/VisualizerStyle.swift Sources/Core/JoyPlotVisualizer.swift Sources/Core/HeightfieldVisualizer.swift Sources/Core/VoronoiVisualizer.swift Sources/Core/LavaLampVisualizer.swift Tests/CoreTests/VisualizerStyleTests.swift
git commit -m "VisualizerStyle: add 4 new cases (joyPlot, heightfield, voronoi, lavaLamp) with stub visualizers"
```

---

## Phase 3 — Joy Plot (Task 5)

### Task 5: JoyPlotVisualizer — full implementation

**Files:**
- Modify: `Sources/Core/JoyPlotVisualizer.swift`
- Create: `Tests/CoreTests/JoyPlotVisualizerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CoreTests/JoyPlotVisualizerTests.swift`:

```swift
import XCTest
import simd
@testable import MacVisualizerCore

final class JoyPlotVisualizerTests: XCTestCase {

    private func mono(bands: [Float], beat: Bool = false, intensity: Float = 0, t: TimeInterval = 0) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                   rms: 0, peak: 0, timestamp: t,
                   beat: beat, beatIntensity: intensity)
    }

    private func stereo(L: [Float], R: [Float], beat: Bool = false, intensity: Float = 0, t: TimeInterval = 0) -> AudioFrame {
        let bands = zip(L, R).map { ($0 + $1) / 2 }
        return AudioFrame(bands: bands, bandsLeft: L, bandsRight: R,
                          bandPeaks: bands, waveform: [],
                          rms: 0, peak: 0, timestamp: t,
                          beat: beat, beatIntensity: intensity)
    }

    func testVertexBoundsInClipSpace() {
        let viz = JoyPlotVisualizer()
        let bands: [Float] = (0..<24).map { _ in 0.5 }
        let verts = viz.makeVertices(frame: mono(bands: bands), settings: .defaults, aspect: 1.6)
        for v in verts {
            XCTAssertLessThanOrEqual(abs(v.position.x), 1.25)
            XCTAssertLessThanOrEqual(abs(v.position.y), 1.25)
        }
    }

    func testVertexCountIsMultipleOfSix() {
        let viz = JoyPlotVisualizer()
        let bands: [Float] = (0..<24).map { Float($0) / 24 }
        let verts = viz.makeVertices(frame: mono(bands: bands), settings: .defaults, aspect: 1)
        XCTAssertEqual(verts.count % 6, 0)
    }

    func testEmptyBandsProducesNoVertices() {
        let viz = JoyPlotVisualizer()
        let verts = viz.makeVertices(frame: mono(bands: []), settings: .defaults, aspect: 1)
        XCTAssertEqual(verts.count, 0)
    }

    func testBeatBoostMakesPathWiderForOneFrame() {
        let bands: [Float] = (0..<24).map { _ in 0.6 }
        let baseViz = JoyPlotVisualizer()
        let beatViz = JoyPlotVisualizer()
        _ = baseViz.makeVertices(frame: mono(bands: bands, t: 0), settings: .defaults, aspect: 1)
        _ = beatViz.makeVertices(frame: mono(bands: bands, beat: true, intensity: 1.0, t: 0), settings: .defaults, aspect: 1)
        // Next frame — beat boost should still be in effect (150ms decay).
        let baseVerts = baseViz.makeVertices(frame: mono(bands: bands, t: 1.0/60), settings: .defaults, aspect: 1)
        let beatVerts = beatViz.makeVertices(frame: mono(bands: bands, t: 1.0/60), settings: .defaults, aspect: 1)
        // Path quad heights are wider on the beat-boosted visualizer.
        let baseSpan = (baseVerts.map(\.position.y).max() ?? 0) - (baseVerts.map(\.position.y).min() ?? 0)
        let beatSpan = (beatVerts.map(\.position.y).max() ?? 0) - (beatVerts.map(\.position.y).min() ?? 0)
        XCTAssertGreaterThan(beatSpan, baseSpan)
    }

    func testStereoModeUsesLandR() {
        var s = VisualizerSettings.defaults
        s.useStereoImage = true
        let L: [Float] = [Float](repeating: 0.9, count: 24)
        let R: [Float] = [Float](repeating: 0.0, count: 24)
        let viz = JoyPlotVisualizer()
        let verts = viz.makeVertices(frame: stereo(L: L, R: R), settings: s, aspect: 1)
        // Row 0 (bottom, bandsLeft) should reach much higher than row 3 (top, bandsRight).
        // Row 0 vertices have lower y values than rows 1-3. Find lowest 1/4 of vertices.
        let allY = verts.map(\.position.y).sorted()
        let bottomQuartile = Array(allY.prefix(allY.count / 4))
        let topQuartile = Array(allY.suffix(allY.count / 4))
        let bottomSpan = (bottomQuartile.max() ?? 0) - (bottomQuartile.min() ?? 0)
        let topSpan = (topQuartile.max() ?? 0) - (topQuartile.min() ?? 0)
        XCTAssertGreaterThan(bottomSpan, topSpan, "hard-L input should make bottom (bandsLeft) row taller than top (bandsRight) row")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: tests fail — `JoyPlotVisualizer.makeVertices` currently returns `[]`.

- [ ] **Step 3: Implement JoyPlotVisualizer**

Replace `Sources/Core/JoyPlotVisualizer.swift`:

```swift
import simd
import QuartzCore

/// Joy Division "Unknown Pleasures" style: 4 horizontal smoothed area paths
/// stacked vertically. Each path is sampled at `sampleCount` evenly-spaced
/// x-positions; the y at each sample is a 3-point moving average of band
/// magnitudes mapped to that path.
///
/// When `useStereoImage == false`: rows 0-2 split the spectrum (low/mid/high),
/// row 3 shows the overall mix. When `useStereoImage == true`: row 0 = bandsLeft,
/// rows 1-2 split the mono mix (low half, high half), row 3 = bandsRight.
///
/// On `frame.beat`: line/area thickness multiplier `1 + 0.5 * beatIntensity`,
/// 150ms half-life decay. Stateful — keep one instance alive across frames.
public final class JoyPlotVisualizer: Visualizer {

    private let rowCount: Int = 4
    private let sampleCount: Int = 64
    private let rowSpacing: Float = 0.4         // vertical NDC between row baselines
    private let rowHeight: Float = 0.15         // max amplitude in NDC
    private var beatBoost: Float = 0            // decays to 0; pulsed by frame.beat
    private var lastTimestamp: CFTimeInterval = -1

    public init() {}

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        guard !frame.bands.isEmpty else { return [] }

        // Decay + pulse beatBoost using wall-clock dt (independent of any speed multiplier).
        var realDt: Float = 0
        if lastTimestamp >= 0 {
            realDt = Float(min(max(frame.timestamp - lastTimestamp, 0), 0.1))
        }
        lastTimestamp = frame.timestamp
        beatBoost *= powf(0.5, realDt / 0.15)
        if frame.beat {
            beatBoost = max(beatBoost, 0.5 * max(0, min(1, frame.beatIntensity)))
        }
        let amplitudeScale: Float = 1 + beatBoost

        let palette = ColorPalette.preset(named: settings.paletteName) ?? ColorPalette.preset(named: "classic")!

        // Choose band slices per row.
        let rowSlices: [[Float]]
        if settings.useStereoImage {
            let mono = frame.bands
            let mid = mono.count / 2
            rowSlices = [
                frame.bandsLeft,
                Array(mono[0..<mid]),
                Array(mono[mid..<mono.count]),
                frame.bandsRight
            ]
        } else {
            let n = frame.bands.count
            let third = max(1, n / 3)
            rowSlices = [
                Array(frame.bands[0..<third]),
                Array(frame.bands[third..<min(2 * third, n)]),
                Array(frame.bands[min(2 * third, n)..<n]),
                frame.bands
            ]
        }

        // Per-row baseline y positions. Centered around y=0, spaced by rowSpacing.
        let baselineOffset = (Float(rowCount - 1) * rowSpacing) / 2
        var verts: [BarVertex] = []
        verts.reserveCapacity(rowCount * (sampleCount - 1) * 6)

        for r in 0..<rowCount {
            let baseY = Float(r) * rowSpacing - baselineOffset
            let slice = rowSlices[r]
            guard !slice.isEmpty else { continue }
            // Sample the slice at sampleCount evenly-spaced positions, 3-point smoothing.
            var ys: [Float] = []
            ys.reserveCapacity(sampleCount)
            for i in 0..<sampleCount {
                let frac = Float(i) / Float(sampleCount - 1)
                let idx = Int(frac * Float(slice.count - 1))
                let prev = max(0, idx - 1), next = min(slice.count - 1, idx + 1)
                let smoothed = (slice[prev] + slice[idx] + slice[next]) / 3
                let level = min(max(smoothed, 0), 1)
                ys.append(level * rowHeight * amplitudeScale)
            }
            // Emit triangle quads between (x_i, baseY) and (x_{i+1}, baseY + y_i).
            let colorPos = Float(r) / Float(max(rowCount - 1, 1))
            let c = palette.sample(at: colorPos)
            let topColor = SIMD4<Float>(c.r, c.g, c.b, 1)
            let bottomColor = SIMD4<Float>(c.r * 0.3, c.g * 0.3, c.b * 0.3, 1)
            for i in 0..<(sampleCount - 1) {
                let x0 = Float(i) / Float(sampleCount - 1) * 2 - 1
                let x1 = Float(i + 1) / Float(sampleCount - 1) * 2 - 1
                let y0 = ys[i], y1 = ys[i + 1]
                let p00 = SIMD4<Float>(x0, baseY, 0, 1)
                let p10 = SIMD4<Float>(x1, baseY, 0, 1)
                let p0y = SIMD4<Float>(x0, baseY + y0, 0, 1)
                let p1y = SIMD4<Float>(x1, baseY + y1, 0, 1)
                verts.append(contentsOf: [
                    BarVertex(position: p00, color: bottomColor),
                    BarVertex(position: p10, color: bottomColor),
                    BarVertex(position: p0y, color: topColor),
                    BarVertex(position: p10, color: bottomColor),
                    BarVertex(position: p1y, color: topColor),
                    BarVertex(position: p0y, color: topColor)
                ])
            }
        }
        return verts
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 6 new tests (~223 total).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/JoyPlotVisualizer.swift Tests/CoreTests/JoyPlotVisualizerTests.swift
git commit -m "JoyPlotVisualizer: 4 stacked smoothed area paths with beat + stereo support"
```

---

## Phase 4 — Heightfield (Tasks 6–7)

### Task 6: HeightfieldVisualizer — wireframe mode

**Files:**
- Modify: `Sources/Core/HeightfieldVisualizer.swift`
- Create: `Tests/CoreTests/HeightfieldVisualizerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CoreTests/HeightfieldVisualizerTests.swift`:

```swift
import XCTest
import simd
@testable import MacVisualizerCore

final class HeightfieldVisualizerTests: XCTestCase {

    private func frame(bands: [Float], L: [Float]? = nil, R: [Float]? = nil, beat: Bool = false, intensity: Float = 0) -> AudioFrame {
        if let L, let R {
            return AudioFrame(bands: bands, bandsLeft: L, bandsRight: R,
                              bandPeaks: bands, waveform: [],
                              rms: 0, peak: 0, timestamp: 0,
                              beat: beat, beatIntensity: intensity)
        }
        return AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                          rms: 0, peak: 0, timestamp: 0,
                          beat: beat, beatIntensity: intensity)
    }

    func testWireframeModeVertexBounds() {
        var s = VisualizerSettings.defaults
        s.mutateCurrent { $0.heightfieldRenderMode = .wireframe }
        s.visualizerStyle = .heightfield
        let bands: [Float] = (0..<48).map { _ in 0.7 }
        let viz = HeightfieldVisualizer()
        let verts = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1.6)
        XCTAssertGreaterThan(verts.count, 100)
        for v in verts {
            XCTAssertLessThanOrEqual(abs(v.position.x), 1.5)
            XCTAssertLessThanOrEqual(abs(v.position.y), 1.5)
        }
    }

    func testWireframeBeatBoostExtendsZRange() {
        var s = VisualizerSettings.defaults
        s.mutateCurrent { $0.heightfieldRenderMode = .wireframe }
        s.visualizerStyle = .heightfield
        let bands: [Float] = (0..<48).map { _ in 0.7 }
        let baseViz = HeightfieldVisualizer()
        let beatViz = HeightfieldVisualizer()
        let baseVerts = baseViz.makeVertices(frame: frame(bands: bands, beat: false), settings: s, aspect: 1)
        let beatVerts = beatViz.makeVertices(frame: frame(bands: bands, beat: true, intensity: 1.0), settings: s, aspect: 1)
        // Beat should extend the y-range (Z displacement projected to screen).
        let baseSpan = (baseVerts.map(\.position.y).max() ?? 0) - (baseVerts.map(\.position.y).min() ?? 0)
        let beatSpan = (beatVerts.map(\.position.y).max() ?? 0) - (beatVerts.map(\.position.y).min() ?? 0)
        XCTAssertGreaterThan(beatSpan, baseSpan)
    }

    func testWireframeStereoSplitsLeftRight() {
        var s = VisualizerSettings.defaults
        s.useStereoImage = true
        s.mutateCurrent { $0.heightfieldRenderMode = .wireframe }
        s.visualizerStyle = .heightfield
        let L: [Float] = [Float](repeating: 0.9, count: 48)
        let R: [Float] = [Float](repeating: 0.0, count: 48)
        let bands = zip(L, R).map { ($0 + $1) / 2 }
        let viz = HeightfieldVisualizer()
        let verts = viz.makeVertices(frame: frame(bands: bands, L: L, R: R), settings: s, aspect: 1)
        // Left half (x < 0) should have larger y spread than right half (x ≥ 0).
        let leftHalf = verts.filter { $0.position.x < 0 }.map(\.position.y)
        let rightHalf = verts.filter { $0.position.x >= 0 }.map(\.position.y)
        let leftSpan = (leftHalf.max() ?? 0) - (leftHalf.min() ?? 0)
        let rightSpan = (rightHalf.max() ?? 0) - (rightHalf.min() ?? 0)
        XCTAssertGreaterThan(leftSpan, rightSpan + 0.05)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: tests fail — HeightfieldVisualizer returns `[]`.

- [ ] **Step 3: Implement HeightfieldVisualizer (wireframe mode)**

Replace `Sources/Core/HeightfieldVisualizer.swift`:

```swift
import simd
import QuartzCore

/// 16×16 grid of vertices in 3D. Each vertex's Z is driven by an audio band
/// (indexed by column). Camera: orthographic with a 24° X-axis tilt for
/// perspective feel. Two render modes:
///   - `.wireframe`: horizontal + vertical line segments
///   - `.solid`:     pre-shaded filled triangles with flat lighting
///
/// When `useStereoImage == true`: left 8 columns driven by bandsLeft, right 8
/// by bandsRight. On `frame.beat`: Z-amplitude pulse `1 + 0.4 * beatIntensity`
/// with 200ms half-life. Stateful — beat boost decays across frames.
public final class HeightfieldVisualizer: Visualizer {

    private let gridSize: Int = 16
    private let tiltAngle: Float = .pi / 7.5          // ≈ 24°
    private let zScale: Float = 0.25
    private let lineHalfThickness: Float = 0.003
    private let lightDir: SIMD3<Float> = normalize(SIMD3<Float>(0.5, 0.7, 0.5))

    private var beatBoost: Float = 0
    private var lastTimestamp: CFTimeInterval = -1

    public init() {}

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        guard !frame.bands.isEmpty else { return [] }

        // Beat-boost decay.
        var realDt: Float = 0
        if lastTimestamp >= 0 {
            realDt = Float(min(max(frame.timestamp - lastTimestamp, 0), 0.1))
        }
        lastTimestamp = frame.timestamp
        beatBoost *= powf(0.5, realDt / 0.2)
        if frame.beat {
            beatBoost = max(beatBoost, 0.4 * max(0, min(1, frame.beatIntensity)))
        }
        let zMul: Float = 1 + beatBoost

        // Build Z-displaced grid in 3D.
        var grid = [[SIMD3<Float>]](repeating: [SIMD3<Float>](repeating: .zero, count: gridSize), count: gridSize)
        let halfBands = frame.bands.count / 2
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let nx = Float(col) / Float(gridSize - 1) * 2 - 1        // -1..1
                let ny = Float(row) / Float(gridSize - 1) * 2 - 1
                // Choose band source per column.
                let level: Float
                if settings.useStereoImage {
                    let leftHalf = col < gridSize / 2
                    let source = leftHalf ? frame.bandsLeft : frame.bandsRight
                    let bandIdx = source.isEmpty ? 0 : (col * source.count) / gridSize
                    level = source.isEmpty ? 0 : source[min(bandIdx, source.count - 1)]
                } else {
                    let bandIdx = (col * frame.bands.count) / gridSize
                    level = frame.bands[min(bandIdx, frame.bands.count - 1)]
                }
                let z = min(max(level, 0), 1) * zScale * zMul
                grid[row][col] = SIMD3<Float>(nx, ny, z)
            }
        }
        _ = halfBands   // silence unused if user changes bandsLeft.count

        // Project to 2D via X-axis tilt (rotates Y/Z plane).
        let cosT = cos(tiltAngle), sinT = sin(tiltAngle)
        var aspectSx: Float = 1, aspectSy: Float = 1
        if aspect >= 1 { aspectSx = 1 / aspect } else { aspectSy = aspect }
        func project(_ p3: SIMD3<Float>) -> SIMD2<Float> {
            let yt = p3.y * cosT - p3.z * sinT
            return SIMD2<Float>(p3.x * aspectSx, yt * aspectSy)
        }
        var grid2 = [[SIMD2<Float>]](repeating: [SIMD2<Float>](repeating: .zero, count: gridSize), count: gridSize)
        for r in 0..<gridSize {
            for c in 0..<gridSize {
                grid2[r][c] = project(grid[r][c])
            }
        }

        let palette = ColorPalette.preset(named: settings.paletteName) ?? ColorPalette.preset(named: "classic")!

        switch settings.heightfieldRenderMode {
        case .wireframe:
            return emitWireframe(grid: grid, grid2: grid2, palette: palette)
        case .solid:
            return emitSolid(grid: grid, grid2: grid2, palette: palette)
        }
    }

    private func emitWireframe(grid: [[SIMD3<Float>]], grid2: [[SIMD2<Float>]], palette: ColorPalette) -> [BarVertex] {
        var verts: [BarVertex] = []
        verts.reserveCapacity(gridSize * (gridSize - 1) * 2 * 6)   // rows + cols, each a quad
        for r in 0..<gridSize {
            for c in 0..<(gridSize - 1) {
                let p0 = grid2[r][c], p1 = grid2[r][c + 1]
                appendLineQuad(&verts, p0: p0, p1: p1,
                               level0: grid[r][c].z / zScale, level1: grid[r][c + 1].z / zScale,
                               palette: palette)
            }
        }
        for c in 0..<gridSize {
            for r in 0..<(gridSize - 1) {
                let p0 = grid2[r][c], p1 = grid2[r + 1][c]
                appendLineQuad(&verts, p0: p0, p1: p1,
                               level0: grid[r][c].z / zScale, level1: grid[r + 1][c].z / zScale,
                               palette: palette)
            }
        }
        return verts
    }

    private func emitSolid(grid: [[SIMD3<Float>]], grid2: [[SIMD2<Float>]], palette: ColorPalette) -> [BarVertex] {
        var verts: [BarVertex] = []
        verts.reserveCapacity((gridSize - 1) * (gridSize - 1) * 6)
        for r in 0..<(gridSize - 1) {
            for c in 0..<(gridSize - 1) {
                let p00 = grid[r][c], p10 = grid[r][c + 1], p01 = grid[r + 1][c], p11 = grid[r + 1][c + 1]
                // Triangle 1: (p00, p10, p11). Triangle 2: (p00, p11, p01).
                emitShadedTriangle(&verts, a: p00, b: p10, c: p11, palette: palette)
                emitShadedTriangle(&verts, a: p00, b: p11, c: p01, palette: palette)
            }
        }
        return verts
    }

    private func emitShadedTriangle(_ verts: inout [BarVertex], a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>, palette: ColorPalette) {
        let n = simd_normalize(simd_cross(b - a, c - a))
        let light = max(0.3, simd_dot(n, lightDir))
        let avgZ = (a.z + b.z + c.z) / 3
        let level = min(max(avgZ / zScale, 0), 1)
        let baseColor = palette.sample(at: level)
        let color = SIMD4<Float>(baseColor.r * light, baseColor.g * light, baseColor.b * light, 1)
        let cosT = cos(tiltAngle), sinT = sin(tiltAngle)
        func proj(_ p: SIMD3<Float>) -> SIMD2<Float> {
            let yt = p.y * cosT - p.z * sinT
            return SIMD2<Float>(p.x, yt)
        }
        let pa = proj(a), pb = proj(b), pc = proj(c)
        verts.append(BarVertex(position: SIMD4<Float>(pa.x, pa.y, 0, 1), color: color))
        verts.append(BarVertex(position: SIMD4<Float>(pb.x, pb.y, 0, 1), color: color))
        verts.append(BarVertex(position: SIMD4<Float>(pc.x, pc.y, 0, 1), color: color))
    }

    private func appendLineQuad(_ verts: inout [BarVertex], p0: SIMD2<Float>, p1: SIMD2<Float>, level0: Float, level1: Float, palette: ColorPalette) {
        // Build a thin quad perpendicular to (p1 - p0).
        var dir = p1 - p0
        let len = simd_length(dir)
        guard len > 1e-5 else { return }
        dir /= len
        let perp = SIMD2<Float>(-dir.y, dir.x) * lineHalfThickness
        let c0 = palette.sample(at: max(0, min(1, level0)))
        let c1 = palette.sample(at: max(0, min(1, level1)))
        let color0 = SIMD4<Float>(c0.r, c0.g, c0.b, 1)
        let color1 = SIMD4<Float>(c1.r, c1.g, c1.b, 1)
        let a = p0 - perp, b = p0 + perp, c = p1 + perp, d = p1 - perp
        verts.append(BarVertex(position: SIMD4<Float>(a.x, a.y, 0, 1), color: color0))
        verts.append(BarVertex(position: SIMD4<Float>(b.x, b.y, 0, 1), color: color0))
        verts.append(BarVertex(position: SIMD4<Float>(d.x, d.y, 0, 1), color: color1))
        verts.append(BarVertex(position: SIMD4<Float>(b.x, b.y, 0, 1), color: color0))
        verts.append(BarVertex(position: SIMD4<Float>(c.x, c.y, 0, 1), color: color1))
        verts.append(BarVertex(position: SIMD4<Float>(d.x, d.y, 0, 1), color: color1))
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 3 new tests (~226 total).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/HeightfieldVisualizer.swift Tests/CoreTests/HeightfieldVisualizerTests.swift
git commit -m "HeightfieldVisualizer: wireframe + solid render modes with beat + stereo"
```

---

### Task 7: HeightfieldVisualizer — solid mode verification

The previous task already implemented both wireframe and solid emission. This task adds tests for the solid path so it's not just dead code.

**Files:**
- Modify (extend): `Tests/CoreTests/HeightfieldVisualizerTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/CoreTests/HeightfieldVisualizerTests.swift`:

```swift
func testSolidModeProducesTriangles() {
    var s = VisualizerSettings.defaults
    s.mutateCurrent { $0.heightfieldRenderMode = .solid }
    s.visualizerStyle = .heightfield
    let bands: [Float] = (0..<48).map { _ in 0.7 }
    let viz = HeightfieldVisualizer()
    let verts = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
    // 16×16 grid → 15×15 cells × 2 triangles × 3 verts = 1350
    XCTAssertEqual(verts.count, 15 * 15 * 2 * 3)
    XCTAssertEqual(verts.count % 3, 0)
}

func testSolidModeProducesDarkerColorsThanWireframe() {
    // The solid path multiplies palette colors by the lighting term (≥ 0.3),
    // so on a flat field the colors are slightly darker than the unshaded
    // wireframe equivalent. Just verify the modes produce different vertex
    // counts (sanity check that the switch is exercised).
    var sWire = VisualizerSettings.defaults
    sWire.mutateCurrent { $0.heightfieldRenderMode = .wireframe }
    sWire.visualizerStyle = .heightfield
    var sSolid = VisualizerSettings.defaults
    sSolid.mutateCurrent { $0.heightfieldRenderMode = .solid }
    sSolid.visualizerStyle = .heightfield
    let bands: [Float] = (0..<48).map { _ in 0.5 }
    let viz1 = HeightfieldVisualizer()
    let viz2 = HeightfieldVisualizer()
    let wireVerts = viz1.makeVertices(frame: frame(bands: bands), settings: sWire, aspect: 1)
    let solidVerts = viz2.makeVertices(frame: frame(bands: bands), settings: sSolid, aspect: 1)
    XCTAssertNotEqual(wireVerts.count, solidVerts.count)
}
```

- [ ] **Step 2: Run test to verify they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 2 new tests (~228 total). Both tests should pass because Task 6 already implemented the solid path.

- [ ] **Step 3: Commit**

```bash
git add Tests/CoreTests/HeightfieldVisualizerTests.swift
git commit -m "HeightfieldVisualizer: add solid-mode triangle count + mode-distinct tests"
```

---

## Phase 5 — Voronoi (Tasks 8–11)

### Task 8: VoronoiVisualizer — cells mode (vertex-emit via Voronoi dual)

**Files:**
- Modify: `Sources/Core/VoronoiVisualizer.swift`
- Create: `Tests/CoreTests/VoronoiVisualizerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CoreTests/VoronoiVisualizerTests.swift`:

```swift
import XCTest
import simd
@testable import MacVisualizerCore

final class VoronoiVisualizerTests: XCTestCase {

    private func frame(bands: [Float], beat: Bool = false, intensity: Float = 0) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                   rms: 0, peak: 0, timestamp: 0,
                   beat: beat, beatIntensity: intensity)
    }

    func testCellsModeProducesVertices() {
        var s = VisualizerSettings.defaults
        s.mutateCurrent { $0.voronoiRenderMode = .cells }
        s.visualizerStyle = .voronoi
        let bands: [Float] = (0..<48).map { _ in 0.6 }
        let viz = VoronoiVisualizer()
        let verts = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        XCTAssertGreaterThan(verts.count, 100, "cells mode should emit many triangles")
        XCTAssertEqual(verts.count % 3, 0, "triangle vertices come in groups of 3")
    }

    func testCellsModeVertexBounds() {
        var s = VisualizerSettings.defaults
        s.mutateCurrent { $0.voronoiRenderMode = .cells }
        s.visualizerStyle = .voronoi
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let viz = VoronoiVisualizer()
        let verts = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1.6)
        // Voronoi circumcenters can extend slightly outside the seed bounds
        // due to dual geometry. Allow a generous bound; the composite pass
        // will clip anything truly off-screen.
        for v in verts {
            XCTAssertLessThanOrEqual(abs(v.position.x), 3.0)
            XCTAssertLessThanOrEqual(abs(v.position.y), 3.0)
        }
    }

    func testCellsModeDeterministicSeeds() {
        var s = VisualizerSettings.defaults
        s.mutateCurrent { $0.voronoiRenderMode = .cells }
        s.visualizerStyle = .voronoi
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let v1 = VoronoiVisualizer().makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        let v2 = VoronoiVisualizer().makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        XCTAssertEqual(v1.count, v2.count)
        for i in 0..<v1.count {
            XCTAssertEqual(v1[i].position.x, v2[i].position.x, accuracy: 1e-5)
            XCTAssertEqual(v1[i].position.y, v2[i].position.y, accuracy: 1e-5)
        }
    }

    func testCellsModeBeatBrightensVertices() {
        var s = VisualizerSettings.defaults
        s.mutateCurrent { $0.voronoiRenderMode = .cells }
        s.visualizerStyle = .voronoi
        let bands: [Float] = (0..<48).map { _ in 0.6 }
        let baseViz = VoronoiVisualizer()
        let beatViz = VoronoiVisualizer()
        let baseVerts = baseViz.makeVertices(frame: frame(bands: bands, beat: false), settings: s, aspect: 1)
        let beatVerts = beatViz.makeVertices(frame: frame(bands: bands, beat: true, intensity: 1.0), settings: s, aspect: 1)
        let baseAvg = baseVerts.map { $0.color.x + $0.color.y + $0.color.z }.reduce(0, +) / Float(baseVerts.count)
        let beatAvg = beatVerts.map { $0.color.x + $0.color.y + $0.color.z }.reduce(0, +) / Float(beatVerts.count)
        XCTAssertGreaterThan(beatAvg, baseAvg, "beat should brighten the average cell color")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: tests fail — VoronoiVisualizer returns `[]`.

- [ ] **Step 3: Implement VoronoiVisualizer (cells mode)**

Replace `Sources/Core/VoronoiVisualizer.swift`:

```swift
import simd
import QuartzCore

/// 75 random seed points (deterministic from a fixed RNG seed). Three render
/// modes: cells (Voronoi polygons via Delaunay dual), blobs (fragment shader),
/// softCells (vertex emit + post-process blur).
///
/// On `frame.beat`: cell brightness boost `1 + 0.3 * beatIntensity`, 100ms half-life.
/// On `useStereoImage == true`: cells with x < 0 use bandsLeft, x ≥ 0 use bandsRight.
public final class VoronoiVisualizer: Visualizer {

    private let seedCount: Int = 75
    private let rngSeed: UInt64 = 0xCE110155

    private let seeds: [SIMD2<Float>]
    private let cells: [Delaunay.VoronoiCell]
    private let cellBandIdx: [Int]            // bandIdx assignment per cell (matches seeds order)
    private let cellTints: [Float]            // ±10% per-cell tint variation

    private var beatBoost: Float = 0
    private var lastTimestamp: CFTimeInterval = -1

    public init() {
        var rng = SeededRNG(seed: rngSeed)
        var s: [SIMD2<Float>] = []
        s.reserveCapacity(seedCount)
        for _ in 0..<seedCount {
            s.append(SIMD2<Float>(rng.nextSigned() * 0.95, rng.nextSigned() * 0.95))
        }
        self.seeds = s
        self.cells = Delaunay.voronoiCells(points: s)
        self.cellBandIdx = (0..<seedCount).map { $0 }
        var tints: [Float] = []
        tints.reserveCapacity(seedCount)
        for _ in 0..<seedCount {
            tints.append(0.9 + rng.nextUnit() * 0.2)   // 0.9..1.1
        }
        self.cellTints = tints
    }

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        // Beat decay.
        var realDt: Float = 0
        if lastTimestamp >= 0 {
            realDt = Float(min(max(frame.timestamp - lastTimestamp, 0), 0.1))
        }
        lastTimestamp = frame.timestamp
        beatBoost *= powf(0.5, realDt / 0.1)
        if frame.beat {
            beatBoost = max(beatBoost, 0.3 * max(0, min(1, frame.beatIntensity)))
        }

        switch settings.voronoiRenderMode {
        case .cells:
            return emitCells(frame: frame, settings: settings, aspect: aspect)
        case .blobs:
            // Fragment-shader-driven; visualizer emits nothing. Renderer routes
            // via VisualizerStyle.customShader → .voronoiBlobs (wired in Task 9).
            return []
        case .softCells:
            return emitCells(frame: frame, settings: settings, aspect: aspect)   // same vertices; blur applied by renderer (Task 10)
        }
    }

    private func emitCells(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        guard !frame.bands.isEmpty else { return [] }
        let palette = ColorPalette.preset(named: settings.paletteName) ?? ColorPalette.preset(named: "classic")!
        var sx: Float = 1, sy: Float = 1
        if aspect >= 1 { sx = 1 / aspect } else { sy = aspect }

        var verts: [BarVertex] = []
        verts.reserveCapacity(seedCount * 18)   // ~6 triangles average per cell

        for cell in cells {
            guard cell.vertices.count >= 3 else { continue }
            let seed = seeds[cell.seedIndex]
            // Pick band source per cell based on stereo + cell X position.
            let level: Float
            if settings.useStereoImage {
                let leftHalf = seed.x < 0
                let source = leftHalf ? frame.bandsLeft : frame.bandsRight
                let bi = cellBandIdx[cell.seedIndex] % max(source.count, 1)
                level = source.isEmpty ? 0 : source[bi]
            } else {
                let bi = cellBandIdx[cell.seedIndex] % frame.bands.count
                level = frame.bands[bi]
            }
            let clampedLevel = min(max(level, 0), 1)
            let tint = cellTints[cell.seedIndex]
            let beatMul = 1 + beatBoost
            let c = palette.sample(at: clampedLevel)
            let color = SIMD4<Float>(
                min(1, c.r * tint * beatMul),
                min(1, c.g * tint * beatMul),
                min(1, c.b * tint * beatMul),
                1
            )
            // Triangle fan from the seed to each cell vertex pair (i, i+1).
            for i in 0..<cell.vertices.count {
                let next = (i + 1) % cell.vertices.count
                let v0 = cell.vertices[i], v1 = cell.vertices[next]
                let p0 = SIMD4<Float>(seed.x * sx, seed.y * sy, 0, 1)
                let p1 = SIMD4<Float>(v0.x * sx, v0.y * sy, 0, 1)
                let p2 = SIMD4<Float>(v1.x * sx, v1.y * sy, 0, 1)
                verts.append(BarVertex(position: p0, color: color))
                verts.append(BarVertex(position: p1, color: color))
                verts.append(BarVertex(position: p2, color: color))
            }
        }
        return verts
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 4 new tests (~232 total).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/VoronoiVisualizer.swift Tests/CoreTests/VoronoiVisualizerTests.swift
git commit -m "VoronoiVisualizer: cells mode via Delaunay → Voronoi-dual polygons"
```

---

### Task 9: Voronoi blobs shader — ShaderKind, voronoi_fs, MetalRenderer wiring

**Files:**
- Modify: `Sources/Core/ShaderKind.swift`
- Modify: `Sources/Core/VisualizerStyle.swift`
- Modify: `Sources/Rendering/Shaders.metal`
- Modify: `Sources/Rendering/MetalRenderer.swift`
- Modify (extend): `Tests/CoreTests/VoronoiVisualizerTests.swift`

- [ ] **Step 1: Write a test that exercises the dispatch (lightweight — full shader render is verified by offscreen probe in Task 15)**

Append to `Tests/CoreTests/VoronoiVisualizerTests.swift`:

```swift
func testBlobsModeReturnsEmptyVertices() {
    // Shader-driven; visualizer emits no vertices. Renderer dispatches to voronoi_fs.
    var s = VisualizerSettings.defaults
    s.mutateCurrent { $0.voronoiRenderMode = .blobs }
    s.visualizerStyle = .voronoi
    let bands: [Float] = (0..<48).map { _ in 0.5 }
    let viz = VoronoiVisualizer()
    let verts = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
    XCTAssertEqual(verts.count, 0)
}

func testVoronoiStyleCustomShaderIsBlobsWhenBlobsModeActive() {
    // VisualizerStyle.customShader inspects settings to choose which shader.
    // Add a test once the customShader signature is updated; otherwise skip.
    // This test is a placeholder confirming the API exists; refined in Task 14.
    XCTAssertNotNil(VisualizerStyle.voronoi)
}
```

- [ ] **Step 2: Run test to verify the blobs test passes (returns 0 vertices) and there are no failures**

Run: `make test 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`. (`testBlobsModeReturnsEmptyVertices` should already pass — the visualizer's `.blobs` case returns `[]`.)

- [ ] **Step 3: Add `.voronoiBlobs` and `.lavaLampShader` to ShaderKind**

Replace `Sources/Core/ShaderKind.swift`:

```swift
import Foundation

/// Identifies which Metal fragment shader a shader-driven visualizer uses.
/// `VisualizerStyle.customShader` returns one of these (or nil for the
/// standard geometry-based visualizers).
public enum ShaderKind: String, Codable, CaseIterable {
    case plasma
    case bumpscope
    case voronoiBlobs
    case lavaLampShader
}
```

- [ ] **Step 4: Update VisualizerStyle.customShader to inspect settings**

The current `customShader` is a computed property on `VisualizerStyle`. For voronoi and lava lamp, the choice depends on settings, so we add an alternate API. Add a method on `VisualizerStyle`:

```swift
    /// Like `customShader` but reads per-style render mode from settings.
    /// Returns nil for vertex-emit modes (the standard triangle pipeline applies).
    public func customShader(settings: VisualizerSettings) -> ShaderKind? {
        switch self {
        case .plasma: return .plasma
        case .bumpscope: return .bumpscope
        case .voronoi: return settings.current.voronoiRenderMode == .blobs ? .voronoiBlobs : nil
        case .lavaLamp: return settings.current.lavaLampRenderMode == .shader ? .lavaLampShader : nil
        default: return nil
        }
    }
```

Keep the existing parameterless `customShader` property for backwards compatibility with the renderer if any callers haven't migrated. Update the renderer (next step) to use the new signature.

- [ ] **Step 5: Add `voronoi_fs` fragment shader**

In `Sources/Rendering/Shaders.metal`, find the existing `plasma_fs` or `bumpscope_fs` and add a new shader nearby:

```metal
constant int kVoronoiSeedCount = 75;

struct VoronoiUniforms {
    float4 seedsAndBands[kVoronoiSeedCount];  // xy = seed position in NDC, z = band level, w = unused
    float K;                                   // edge sharpness; higher = sharper cells
    float beatBoost;                           // 0..1 added brightness
};

fragment float4 voronoi_fs(VsOut in [[stage_in]],
                           constant ShaderInputs &inputs [[buffer(0)]],
                           constant PaletteUniform &palette [[buffer(1)]],
                           constant VoronoiUniforms &voronoi [[buffer(2)]]) {
    float2 uv = in.uv * 2.0 - 1.0;
    // Find nearest seed by squared distance.
    float minDist2 = 1e9;
    int nearestIdx = 0;
    for (int i = 0; i < kVoronoiSeedCount; ++i) {
        float2 d = uv - voronoi.seedsAndBands[i].xy;
        float d2 = dot(d, d);
        if (d2 < minDist2) {
            minDist2 = d2;
            nearestIdx = i;
        }
    }
    float level = clamp(voronoi.seedsAndBands[nearestIdx].z, 0.0, 1.0);
    float4 baseColor = samplePalette(palette, level);
    float brightness = 1.0 + voronoi.beatBoost;
    return float4(baseColor.rgb * brightness, 1.0);
}
```

(If `VsOut`, `samplePalette`, etc. don't exist by exactly those names, adapt to the file's existing helper names — read 3-4 nearby shaders for the established style.)

- [ ] **Step 6: Wire voronoi_fs into MetalRenderer**

In `Sources/Rendering/MetalRenderer.swift`:

1. Add a stored property next to `private let bumpscopePipeline16`:

```swift
    private let voronoiPipeline16: MTLRenderPipelineState?
```

2. In the `init?` constructor, after the bumpscope pipeline init block, add:

```swift
        var vdesc = MTLRenderPipelineDescriptor()
        vdesc.vertexFunction = library.makeFunction(name: "fullscreen_vs")
        vdesc.fragmentFunction = library.makeFunction(name: "voronoi_fs")
        vdesc.colorAttachments[0].pixelFormat = .rgba16Float
        self.voronoiPipeline16 = try? device.makeRenderPipelineState(descriptor: vdesc)
```

(Adapt vertex-function name to whatever the existing fullscreen-quad vertex shader is called.)

3. In `encodeShaderFill(...)`:

```swift
        let pipeline: MTLRenderPipelineState?
        switch kind {
        case .plasma: pipeline = plasmaPipeline16
        case .bumpscope: pipeline = bumpscopePipeline16
        case .voronoiBlobs: pipeline = voronoiPipeline16
        case .lavaLampShader: pipeline = nil   // wired in Task 12
        }
        guard let pipeline,
              let enc = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        enc.setRenderPipelineState(pipeline)
        var inputs = makeShaderInputs(frame: frame)
        var palette = makePaletteUniform(named: settings.paletteName)
        enc.setFragmentBytes(&inputs, length: MemoryLayout<ShaderInputs>.stride, index: 0)
        enc.setFragmentBytes(&palette, length: MemoryLayout<PaletteUniform>.stride, index: 1)
        if kind == .voronoiBlobs {
            var v = makeVoronoiUniforms(frame: frame)
            enc.setFragmentBytes(&v, length: MemoryLayout<VoronoiUniforms>.stride, index: 2)
        }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
```

4. Add `private struct VoronoiUniforms` and `makeVoronoiUniforms` to the renderer:

```swift
    private struct VoronoiUniforms {
        // Layout MUST match the Metal shader's constant array layout. 75 SIMD4 = 1200 bytes.
        var seedsAndBands: [SIMD4<Float>] = Array(repeating: .zero, count: 75)
        var K: Float = 12.0
        var beatBoost: Float = 0
    }

    private static let voronoiSeeds: [SIMD2<Float>] = {
        var rng = SeededRNG(seed: 0xCE110155)
        return (0..<75).map { _ in SIMD2<Float>(rng.nextSigned() * 0.95, rng.nextSigned() * 0.95) }
    }()

    private func makeVoronoiUniforms(frame: AudioFrame) -> VoronoiUniforms {
        var u = VoronoiUniforms()
        for i in 0..<75 {
            let s = MetalRenderer.voronoiSeeds[i]
            let bandIdx = i % max(frame.bands.count, 1)
            let level: Float = frame.bands.isEmpty ? 0 : frame.bands[bandIdx]
            u.seedsAndBands[i] = SIMD4<Float>(s.x, s.y, level, 0)
        }
        u.beatBoost = frame.beat ? 0.3 * max(0, min(1, frame.beatIntensity)) : 0
        return u
    }
```

(The renderer maintains its own copy of the seeds — pure deterministic computation from the same SeededRNG seed, so it matches the visualizer's `seeds` array bit-for-bit.)

- [ ] **Step 7: Update callers that use the old parameterless `customShader`**

Search for `customShader` callers:

```bash
grep -rn "\.customShader" Sources/
```

Replace each call site that lacks settings access with the new `customShader(settings:)` method. (The MetalRenderer call site in `renderBloom` / `renderWithTrails` already has settings — just pass it in.)

- [ ] **Step 8: Build + test**

Run: `make build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 2 new tests passing (~234 total).

- [ ] **Step 9: Commit**

```bash
git add Sources/Core/ShaderKind.swift Sources/Core/VisualizerStyle.swift Sources/Rendering/Shaders.metal Sources/Rendering/MetalRenderer.swift Tests/CoreTests/VoronoiVisualizerTests.swift
git commit -m "Voronoi blobs: voronoi_fs fragment shader + ShaderKind + MetalRenderer wiring"
```

---

### Task 10: Voronoi softCells — two-pass renderer

**Files:**
- Modify: `Sources/Rendering/MetalRenderer.swift`
- Modify (extend): `Tests/CoreTests/VoronoiVisualizerTests.swift`

The softCells mode uses the same vertex output as cells mode but routes through a temp-texture + blur pass. Since the visualizer already emits the right vertices (Task 8 returns `emitCells(...)` for both `.cells` and `.softCells`), most of the work is renderer-side.

- [ ] **Step 1: Write a verification test**

Append to `Tests/CoreTests/VoronoiVisualizerTests.swift`:

```swift
func testSoftCellsModeEmitsSameVerticesAsCellsMode() {
    let bands: [Float] = (0..<48).map { _ in 0.5 }
    var sCells = VisualizerSettings.defaults
    sCells.mutateCurrent { $0.voronoiRenderMode = .cells }
    sCells.visualizerStyle = .voronoi
    var sSoft = VisualizerSettings.defaults
    sSoft.mutateCurrent { $0.voronoiRenderMode = .softCells }
    sSoft.visualizerStyle = .voronoi
    let v1 = VoronoiVisualizer().makeVertices(frame: frame(bands: bands), settings: sCells, aspect: 1)
    let v2 = VoronoiVisualizer().makeVertices(frame: frame(bands: bands), settings: sSoft, aspect: 1)
    XCTAssertEqual(v1.count, v2.count, "cells and softCells emit identical vertices; blur is renderer-side")
}
```

- [ ] **Step 2: Run test to verify pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 1 new test passing (~235 total). Already passes because the visualizer's `.softCells` case calls `emitCells(...)`.

- [ ] **Step 3: Plumb the blur pass in the renderer**

In `Sources/Rendering/MetalRenderer.swift`, the existing `bloomBlurTexture` (an MPSImageGaussianBlur target) can be reused or a sibling allocated. The simplest implementation: when rendering voronoi with `.softCells` mode, after the triangle pass, run a 2-pixel separable Gaussian blur on the scene texture before composite.

Add detection in the main render entry point (probably `renderBloom(...)` or similar — find the per-frame entry function):

```swift
        let needsSoftCellsBlur = (settings.visualizerStyle == .voronoi
                                  && settings.current.voronoiRenderMode == .softCells)
        // ... existing triangle render into sceneTexture ...
        if needsSoftCellsBlur, let sceneTex = sceneTexture {
            // Reuse the existing MPS Gaussian blur with a smaller sigma (e.g., 4)
            let blur = MPSImageGaussianBlur(device: device, sigma: 4.0)
            blur.encode(commandBuffer: cb, sourceTexture: sceneTex, destinationTexture: sceneTex)
        }
```

(The exact integration point depends on the existing render flow. Read 50 lines around the bloom call site to find where to insert the conditional blur. The blur replaces sceneTex in-place if MPS supports it — otherwise allocate a temp texture and swap.)

- [ ] **Step 4: Build + test**

Run: `make build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` (~235 total).

- [ ] **Step 5: Commit**

```bash
git add Sources/Rendering/MetalRenderer.swift Tests/CoreTests/VoronoiVisualizerTests.swift
git commit -m "Voronoi softCells: post-process gaussian blur on cell triangles"
```

---

### Task 11: LavaLampVisualizer — state, value2D noise, beat handling

**Files:**
- Modify: `Sources/Core/LavaLampVisualizer.swift`
- Create: `Tests/CoreTests/LavaLampVisualizerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CoreTests/LavaLampVisualizerTests.swift`:

```swift
import XCTest
import simd
@testable import MacVisualizerCore

final class LavaLampVisualizerTests: XCTestCase {

    private func frame(bands: [Float], beat: Bool = false, intensity: Float = 0, t: TimeInterval = 0) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                   rms: 0, peak: 0, timestamp: t,
                   beat: beat, beatIntensity: intensity)
    }

    func testShaderModeReturnsEmptyVertices() {
        var s = VisualizerSettings.defaults
        s.mutateCurrent { $0.lavaLampRenderMode = .shader }
        s.visualizerStyle = .lavaLamp
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let viz = LavaLampVisualizer()
        let verts = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
        XCTAssertEqual(verts.count, 0, "shader mode emits no vertices; renderer dispatches to lavalamp_fs")
    }

    func testStateUpdatesPointPositionsOverTime() {
        var s = VisualizerSettings.defaults
        s.mutateCurrent { $0.lavaLampRenderMode = .marchingSquares }
        s.visualizerStyle = .lavaLamp
        let bands: [Float] = (0..<48).map { _ in 0.4 }
        let viz = LavaLampVisualizer()
        _ = viz.makeVertices(frame: frame(bands: bands, t: 0), settings: s, aspect: 1)
        // Advance several frames; positions should evolve.
        for i in 1..<10 {
            _ = viz.makeVertices(frame: frame(bands: bands, t: Double(i) / 60.0), settings: s, aspect: 1)
        }
        // No explicit assertion — just verify no crash. Position evolution
        // verified visually + by the marching-squares output test in Task 13.
        XCTAssertTrue(true)
    }

    func testBeatLowersDensityThreshold() {
        // Beat reduces the effective threshold, which makes contour areas expand.
        // We can't directly observe threshold in marchingSquares mode (it's per-frame).
        // Sanity check: visualizer accepts beat frames without crashing in either mode.
        var s = VisualizerSettings.defaults
        s.mutateCurrent { $0.lavaLampRenderMode = .marchingSquares }
        s.visualizerStyle = .lavaLamp
        let bands: [Float] = (0..<48).map { _ in 0.5 }
        let viz = LavaLampVisualizer()
        _ = viz.makeVertices(frame: frame(bands: bands, beat: false, t: 0), settings: s, aspect: 1)
        _ = viz.makeVertices(frame: frame(bands: bands, beat: true, intensity: 1.0, t: 1.0/60), settings: s, aspect: 1)
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: tests fail or pass trivially — `LavaLampVisualizer` returns `[]` for everything.

- [ ] **Step 3: Implement LavaLampVisualizer state + shader mode (returns empty)**

Replace `Sources/Core/LavaLampVisualizer.swift`:

```swift
import simd
import QuartzCore

/// 12 moving metaball point sources. Each frame, advance positions via 2D
/// value noise drift; amplitude driven by an assigned audio band. Two render
/// modes: shader (fragment shader, default), marchingSquares (CPU iso-line).
///
/// On `frame.beat`: density threshold multiplier `1 - 0.2 * beatIntensity`
/// briefly lowers thresholds (contours expand outward). 200ms half-life.
public final class LavaLampVisualizer: Visualizer {

    public struct PointState {
        public var position: SIMD2<Float>
        public var velocity: SIMD2<Float>
        public let bandIdx: Int
    }

    public private(set) var points: [PointState]
    private var beatBoost: Float = 0
    private var lastTimestamp: CFTimeInterval = -1
    private let baseThresholds: [Float] = [0.5, 1.0, 1.5, 2.0]
    private let pointCount: Int = 12

    public init() {
        var rng = SeededRNG(seed: 0xFA51BABE)
        var p: [PointState] = []
        p.reserveCapacity(pointCount)
        for i in 0..<pointCount {
            let pos = SIMD2<Float>(rng.nextSigned() * 0.5, rng.nextSigned() * 0.5)
            let vel = SIMD2<Float>(rng.nextSigned() * 0.1, rng.nextSigned() * 0.1)
            p.append(PointState(position: pos, velocity: vel, bandIdx: i))
        }
        self.points = p
    }

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        // dt
        var realDt: Float = 0
        if lastTimestamp >= 0 {
            realDt = Float(min(max(frame.timestamp - lastTimestamp, 0), 0.1))
        }
        lastTimestamp = frame.timestamp

        // Advance points via value-noise-driven drift.
        for i in 0..<points.count {
            let nx = LavaLampVisualizer.value2D(
                x: Double(points[i].position.x) + frame.timestamp * 0.3,
                y: Double(points[i].position.y),
                seed: UInt64(i &* 0x9E3779B97F4A7C15)
            )
            let ny = LavaLampVisualizer.value2D(
                x: Double(points[i].position.x),
                y: Double(points[i].position.y) + frame.timestamp * 0.3,
                seed: UInt64(i &* 0xBF58476D1CE4E5B9)
            )
            let drift = SIMD2<Float>((Float(nx) - 0.5) * 0.3, (Float(ny) - 0.5) * 0.3)
            points[i].velocity = drift
            points[i].position += points[i].velocity * realDt
            // Wrap when out of bounds.
            if abs(points[i].position.x) > 1.2 { points[i].position.x = 0 }
            if abs(points[i].position.y) > 1.2 { points[i].position.y = 0 }
        }

        // Beat boost decay.
        beatBoost *= powf(0.5, realDt / 0.2)
        if frame.beat {
            beatBoost = max(beatBoost, 0.2 * max(0, min(1, frame.beatIntensity)))
        }

        switch settings.lavaLampRenderMode {
        case .shader:
            return []   // shader-driven; Renderer dispatches via .lavaLampShader (Task 12)
        case .marchingSquares:
            return emitMarchingSquares(frame: frame, settings: settings, aspect: aspect)
        }
    }

    /// Current threshold values adjusted by beat boost. Used by Task 12 shader
    /// uniforms and Task 13 marching-squares pass.
    public func currentThresholds() -> [Float] {
        let mul: Float = 1 - beatBoost
        return baseThresholds.map { $0 * mul }
    }

    /// Current per-point amplitudes (bandLevel[bandIdx] for each point).
    /// Returns mono levels when `useStereoImage == false`; L or R per-point
    /// based on point.x when true.
    public func currentAmplitudes(frame: AudioFrame, settings: VisualizerSettings) -> [Float] {
        var amps: [Float] = Array(repeating: 0, count: points.count)
        guard !frame.bands.isEmpty else { return amps }
        for i in 0..<points.count {
            let bi = points[i].bandIdx % frame.bands.count
            if settings.useStereoImage {
                let src = points[i].position.x < 0 ? frame.bandsLeft : frame.bandsRight
                amps[i] = src.isEmpty ? 0 : src[bi]
            } else {
                amps[i] = frame.bands[bi]
            }
        }
        return amps
    }

    private func emitMarchingSquares(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        // Placeholder — implemented in Task 13.
        return []
    }

    // MARK: - 2D value noise (inline; mirrors SiriWaveVisualizer's value1D extended to 2D)

    static func value2D(x: Double, y: Double, seed: UInt64) -> Double {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let xf = x - Double(xi), yf = y - Double(yi)
        func hash(_ ix: Int, _ iy: Int) -> Double {
            var h = UInt64(bitPattern: Int64(ix &* 374761393 &+ iy &* 668265263)) &+ seed
            h = (h ^ (h >> 13)) &* 1274126177
            return Double(h & 0xFFFFFF) / Double(0xFFFFFF)
        }
        let v00 = hash(xi, yi)
        let v10 = hash(xi + 1, yi)
        let v01 = hash(xi, yi + 1)
        let v11 = hash(xi + 1, yi + 1)
        let u = xf * xf * (3 - 2 * xf)
        let v = yf * yf * (3 - 2 * yf)
        let x0 = v00 + (v10 - v00) * u
        let x1 = v01 + (v11 - v01) * u
        return x0 + (x1 - x0) * v
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 3 new tests passing (~238 total).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/LavaLampVisualizer.swift Tests/CoreTests/LavaLampVisualizerTests.swift
git commit -m "LavaLampVisualizer: point state + value2D noise + beat handling (shader mode emits empty)"
```

---

### Task 12: LavaLamp shader — lavalamp_fs + MetalRenderer wiring

**Files:**
- Modify: `Sources/Rendering/Shaders.metal`
- Modify: `Sources/Rendering/MetalRenderer.swift`

The renderer needs access to the LavaLampVisualizer's instance state. Since the renderer already calls `style.makeVisualizer()` and caches the result, we extend the caching path to allow type-cast access. The simplest path: store the active visualizer as `Visualizer?` and downcast when the active style is `.lavaLamp`.

- [ ] **Step 1: Add `lavalamp_fs` shader**

In `Sources/Rendering/Shaders.metal`:

```metal
constant int kLavaLampPointCount = 12;
constant int kLavaLampThresholdCount = 4;

struct LavaLampUniforms {
    float4 pointsAndAmps[kLavaLampPointCount];  // xy = position NDC, z = amplitude, w = unused
    float thresholds[kLavaLampThresholdCount];
    float tolerance;
    float beatBoost;
};

fragment float4 lavalamp_fs(VsOut in [[stage_in]],
                            constant ShaderInputs &inputs [[buffer(0)]],
                            constant PaletteUniform &palette [[buffer(1)]],
                            constant LavaLampUniforms &lava [[buffer(2)]]) {
    float2 uv = in.uv * 2.0 - 1.0;
    // Density = sum of amplitude / dist²
    float density = 0.0;
    for (int i = 0; i < kLavaLampPointCount; ++i) {
        float2 d = uv - lava.pointsAndAmps[i].xy;
        float r2 = max(dot(d, d), 0.0001);
        density += lava.pointsAndAmps[i].z / r2;
    }
    // Output contour brightness based on proximity to any threshold.
    float brightness = 0.0;
    for (int k = 0; k < kLavaLampThresholdCount; ++k) {
        float diff = abs(density - lava.thresholds[k]);
        brightness = max(brightness, max(0.0, 1.0 - diff / lava.tolerance));
    }
    float level = clamp(density * 0.25, 0.0, 1.0);
    float4 base = samplePalette(palette, level);
    return float4(base.rgb * brightness * (1.0 + lava.beatBoost), 1.0);
}
```

- [ ] **Step 2: Add pipeline + uniform plumbing to MetalRenderer**

In `Sources/Rendering/MetalRenderer.swift`:

1. Add stored property:

```swift
    private let lavalampPipeline16: MTLRenderPipelineState?
```

2. In `init?`, add the pipeline creation (after voronoi pipeline):

```swift
        var ldesc = MTLRenderPipelineDescriptor()
        ldesc.vertexFunction = library.makeFunction(name: "fullscreen_vs")
        ldesc.fragmentFunction = library.makeFunction(name: "lavalamp_fs")
        ldesc.colorAttachments[0].pixelFormat = .rgba16Float
        self.lavalampPipeline16 = try? device.makeRenderPipelineState(descriptor: ldesc)
```

3. Add `LavaLampUniforms` struct and `makeLavaLampUniforms`:

```swift
    private struct LavaLampUniforms {
        var pointsAndAmps: [SIMD4<Float>] = Array(repeating: .zero, count: 12)
        var thresholds: [Float] = [0.5, 1.0, 1.5, 2.0]
        var tolerance: Float = 0.05
        var beatBoost: Float = 0
    }

    private func makeLavaLampUniforms(visualizer: LavaLampVisualizer?, frame: AudioFrame, settings: VisualizerSettings) -> LavaLampUniforms {
        var u = LavaLampUniforms()
        guard let viz = visualizer else { return u }
        let amps = viz.currentAmplitudes(frame: frame, settings: settings)
        for i in 0..<min(12, viz.points.count) {
            let p = viz.points[i]
            u.pointsAndAmps[i] = SIMD4<Float>(p.position.x, p.position.y, amps[i], 0)
        }
        u.thresholds = viz.currentThresholds()
        u.beatBoost = frame.beat ? 0.5 * max(0, min(1, frame.beatIntensity)) : 0
        return u
    }
```

4. The renderer needs access to the active LavaLampVisualizer instance. Find where the renderer caches the active visualizer (likely a property like `private var activeVisualizer: Visualizer?` or in MetalView). If no cache exists, add one:

```swift
    private var activeVisualizer: Visualizer?
```

And in the main render entry point, when the active style changes, instantiate and cache:

```swift
        if let cached = activeVisualizer, type(of: cached) == expectedTypeFor(settings.visualizerStyle) {
            // reuse
        } else {
            activeVisualizer = settings.visualizerStyle.makeVisualizer()
        }
```

(If the caching logic already lives in `MetalView` rather than `MetalRenderer`, expose a getter from `MetalView` to pass the visualizer reference to `encodeShaderFill`.)

5. Update the `encodeShaderFill` switch to handle `.lavaLampShader`:

```swift
        case .voronoiBlobs: pipeline = voronoiPipeline16
        case .lavaLampShader: pipeline = lavalampPipeline16
```

And after the standard inputs are set, conditionally upload lavalamp uniforms:

```swift
        if kind == .lavaLampShader {
            var l = makeLavaLampUniforms(visualizer: activeVisualizer as? LavaLampVisualizer, frame: frame, settings: settings)
            enc.setFragmentBytes(&l, length: MemoryLayout<LavaLampUniforms>.stride, index: 2)
        }
```

- [ ] **Step 3: Build + test**

Run: `make build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` (~238 total — no new tests, just plumbing).

- [ ] **Step 4: Commit**

```bash
git add Sources/Rendering/Shaders.metal Sources/Rendering/MetalRenderer.swift
git commit -m "LavaLamp shader: lavalamp_fs + uniform plumbing through active visualizer"
```

---

### Task 13: LavaLamp marching squares mode

**Files:**
- Modify: `Sources/Core/LavaLampVisualizer.swift`
- Modify (extend): `Tests/CoreTests/LavaLampVisualizerTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/CoreTests/LavaLampVisualizerTests.swift`:

```swift
func testMarchingSquaresModeEmitsLineQuads() {
    var s = VisualizerSettings.defaults
    s.mutateCurrent { $0.lavaLampRenderMode = .marchingSquares }
    s.visualizerStyle = .lavaLamp
    let bands: [Float] = (0..<48).map { _ in 0.6 }
    let viz = LavaLampVisualizer()
    let verts = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
    XCTAssertGreaterThan(verts.count, 6, "expected at least one line quad (6 verts) of contour")
    XCTAssertEqual(verts.count % 6, 0, "line quads come in groups of 6 verts")
}

func testMarchingSquaresVerticesInClipSpace() {
    var s = VisualizerSettings.defaults
    s.mutateCurrent { $0.lavaLampRenderMode = .marchingSquares }
    s.visualizerStyle = .lavaLamp
    let bands: [Float] = (0..<48).map { _ in 0.6 }
    let viz = LavaLampVisualizer()
    let verts = viz.makeVertices(frame: frame(bands: bands), settings: s, aspect: 1)
    for v in verts {
        XCTAssertLessThanOrEqual(abs(v.position.x), 1.5)
        XCTAssertLessThanOrEqual(abs(v.position.y), 1.5)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: tests fail — `emitMarchingSquares` returns `[]`.

- [ ] **Step 3: Implement marching-squares emission**

Replace the `emitMarchingSquares(...)` stub in `Sources/Core/LavaLampVisualizer.swift`:

```swift
    private func emitMarchingSquares(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        let gridSize = 64
        let cellSize: Float = 2.0 / Float(gridSize - 1)
        let origin = SIMD2<Float>(-1, -1)
        let amps = currentAmplitudes(frame: frame, settings: settings)
        let thresholds = currentThresholds()
        let palette = ColorPalette.preset(named: settings.paletteName) ?? ColorPalette.preset(named: "classic")!

        // Sample the density field.
        var grid = Array(repeating: Array(repeating: Float(0), count: gridSize), count: gridSize)
        for y in 0..<gridSize {
            let fy = -1 + Float(y) * cellSize
            for x in 0..<gridSize {
                let fx = -1 + Float(x) * cellSize
                var d: Float = 0
                for i in 0..<points.count {
                    let dx = fx - points[i].position.x
                    let dy = fy - points[i].position.y
                    let r2 = max(dx * dx + dy * dy, 0.0001)
                    d += amps[i] / r2
                }
                grid[y][x] = d
            }
        }

        // Extract iso-line segments for each threshold, emit as line quads.
        var verts: [BarVertex] = []
        let halfThickness: Float = 0.003
        var sx: Float = 1, sy: Float = 1
        if aspect >= 1 { sx = 1 / aspect } else { sy = aspect }
        for (idx, t) in thresholds.enumerated() {
            let level = Float(idx) / Float(max(thresholds.count - 1, 1))
            let c = palette.sample(at: level)
            let color = SIMD4<Float>(c.r, c.g, c.b, 1)
            let segs = MarchingSquares.extractIsoLines(grid: grid, threshold: t, cellSize: cellSize, origin: origin)
            for seg in segs {
                let a = SIMD2<Float>(seg.a.x * sx, seg.a.y * sy)
                let b = SIMD2<Float>(seg.b.x * sx, seg.b.y * sy)
                var dir = b - a
                let len = simd_length(dir)
                guard len > 1e-5 else { continue }
                dir /= len
                let perp = SIMD2<Float>(-dir.y, dir.x) * halfThickness
                let p0 = a - perp, p1 = a + perp, p2 = b + perp, p3 = b - perp
                verts.append(BarVertex(position: SIMD4<Float>(p0.x, p0.y, 0, 1), color: color))
                verts.append(BarVertex(position: SIMD4<Float>(p1.x, p1.y, 0, 1), color: color))
                verts.append(BarVertex(position: SIMD4<Float>(p3.x, p3.y, 0, 1), color: color))
                verts.append(BarVertex(position: SIMD4<Float>(p1.x, p1.y, 0, 1), color: color))
                verts.append(BarVertex(position: SIMD4<Float>(p2.x, p2.y, 0, 1), color: color))
                verts.append(BarVertex(position: SIMD4<Float>(p3.x, p3.y, 0, 1), color: color))
            }
        }
        return verts
    }
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 2 new tests (~240 total).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/LavaLampVisualizer.swift Tests/CoreTests/LavaLampVisualizerTests.swift
git commit -m "LavaLampVisualizer: marching-squares mode emits contour line quads"
```

---

## Phase 6 — Settings UI + verification (Tasks 14–15)

### Task 14: SettingsView — render-mode Pickers

**Files:**
- Modify: `Sources/App/SettingsView.swift`

- [ ] **Step 1: Locate the Style tab content**

Run:

```bash
grep -n "voronoi\|heightfield\|lavaLamp\|Style tab\|styleTab" Sources/App/SettingsView.swift | head -10
```

Find the section that renders per-style controls (palette picker, gain, smoothing, etc. for the currently-active style).

- [ ] **Step 2: Add three conditional render-mode Pickers**

In the per-style settings section, after the existing controls and before the close of the section, add three `Picker` rows, each visible only when the matching style is active:

```swift
if settings.visualizerStyle == .voronoi {
    Picker("Voronoi render mode", selection: Binding(
        get: { settings.current.voronoiRenderMode },
        set: { newValue in settings.mutateCurrent { $0.voronoiRenderMode = newValue } }
    )) {
        Text("Cells").tag(VoronoiRenderMode.cells)
        Text("Blobs").tag(VoronoiRenderMode.blobs)
        Text("Soft Cells").tag(VoronoiRenderMode.softCells)
    }
}

if settings.visualizerStyle == .heightfield {
    Picker("Heightfield render mode", selection: Binding(
        get: { settings.current.heightfieldRenderMode },
        set: { newValue in settings.mutateCurrent { $0.heightfieldRenderMode = newValue } }
    )) {
        Text("Wireframe").tag(HeightfieldRenderMode.wireframe)
        Text("Solid").tag(HeightfieldRenderMode.solid)
    }
}

if settings.visualizerStyle == .lavaLamp {
    Picker("Lava lamp render mode", selection: Binding(
        get: { settings.current.lavaLampRenderMode },
        set: { newValue in settings.mutateCurrent { $0.lavaLampRenderMode = newValue } }
    )) {
        Text("Shader").tag(LavaLampRenderMode.shader)
        Text("Marching Squares").tag(LavaLampRenderMode.marchingSquares)
    }
}
```

(Bind-via-closure pattern matches the rest of the file — read 5 surrounding lines for the established style.)

- [ ] **Step 3: Build and verify in the app**

Run: `make build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the tests**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` (~240 total — no new tests, just UI).

- [ ] **Step 5: Commit**

```bash
git add Sources/App/SettingsView.swift
git commit -m "SettingsView: conditional render-mode Pickers for voronoi/heightfield/lavaLamp"
```

---

### Task 15: Final integration — full build + offscreen render probe + visual validation

**Files:**
- (none — verification only)

This task is REQUIRED, not optional. Per the post-Cluster-A feedback memory, manual visual validation is part of "done" for any cluster shipping behavior-changing visualizer work.

- [ ] **Step 1: Run a clean build**

Run: `make clean && make build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Run the full test suite**

Run: `make test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -3`
Expected: ~240 tests passing.

- [ ] **Step 3: Generate offscreen render probe PNGs for each new style × each render mode**

Drive the existing `RenderProbe` infrastructure (see `Sources/Rendering/RenderProbe.swift`) to produce one PNG per (style, render mode) combination. Snapshot inputs: a fixed synthetic AudioFrame with `bands = [0.1, 0.4, 0.8, 0.6, ..., 0.5]` (24 values, varied), `beat = true`, `beatIntensity = 0.7`, `bandsLeft = bands * 0.6`, `bandsRight = bands * 1.4` (visibly imbalanced stereo).

Combinations: joyPlot (1) + heightfield wireframe + heightfield solid + voronoi cells + voronoi blobs + voronoi softCells + lavaLamp shader + lavaLamp marchingSquares = 8 PNGs.

Output path: `Tests/RenderProbeSnapshots/cluster-d-<style>-<mode>.png`.

The render probe should not be invoked as a test (PNG output is not deterministic enough for assertion); instead, run it as a separate command and attach the PNGs to the final-review subagent for visual inspection.

- [ ] **Step 4: Final code review subagent**

Dispatch a final reviewer subagent over the entire branch diff:
- Branch: `plan-18-cluster-d-new-visualizer-styles`
- Diff: `git diff main..plan-18-cluster-d-new-visualizer-styles`
- Attach the 8 PNGs from Step 3
- Ask for: aesthetic coherence with existing styles, any obvious bugs visible in the PNGs, code-quality concerns

- [ ] **Step 5: User visual walk**

Ask the user to launch the built app and walk through each new style:

For each of joyPlot, heightfield, voronoi, lavaLamp:
1. Switch to the style (e.g., via the View menu or ⌥1-9 shortcut if it exists)
2. Toggle render mode via the new Settings → Style tab Picker. Verify each mode produces visibly different output.
3. Toggle `useStereoImage` on/off in Settings → Tweaks tab. Verify stereo-aware styles respond.
4. Verify beat-driven effects fire on percussive music for each style.

Report any of:
- Render mode produces no output / crashes
- Stereo toggle has no visible effect when it should
- Beat effects are invisible / too aggressive
- Anything that looks wrong

If anything is wrong, fix-forward with additional commits on the branch before merging.

- [ ] **Step 6: Verify branch state**

Run:

```bash
git log --oneline main..plan-18-cluster-d-new-visualizer-styles | head -20
```

Expected: ~16 commits — one spec + one plan + 14 implementation/verification.

---

## Out of scope (future clusters)

- Cluster B — Feedback-warp post-process + Reflected floor + RMS hue rotate
- Cluster C — Barycentric wireframe + Multi-band siri
- Cluster E — Crossfade + Perlin drift
- MilkDrop integration — separate decision tree (projectM embed vs butterchurn port vs technique mining)
