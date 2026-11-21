# Wireframe Mesh Visualizer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 9th visualizer style — a slowly-rotating wireframe icosphere whose vertices are pushed outward along their normals proportional to per-vertex audio band energy. Each edge rendered as a thin oriented quad via the existing sharp triangle pipeline.

**Architecture:** Two-file split: `WireframeMesh.swift` is a pure utility that builds the icosphere geometry (vertices + unique edges) once via golden-ratio formulas + subdivision; `WireframeVisualizer.swift` is the stateful per-frame logic (rotation accumulator + per-vertex projection + edge-quad emission). Spatial-angle band mapping per vertex via `atan2(vx, vz)`. No new shader, no Settings UI changes, no renderer changes.

**Tech Stack:** Swift 5.10, simd, QuartzCore, XCTest. Reuses existing `pipeline` / `pipeline16` for rendering.

**Builds on:** `main` after merging `plan-13-polish-bundle`. Spec: `docs/superpowers/specs/2026-05-28-wireframe-mesh-design.md`.

**Scope boundary:** No new shader, no new render pipeline, no Settings UI changes, no mouse interaction, no solid-fill mode.

---

## File Structure

```
mac-visualizer/
  Sources/
    Core/
      WireframeMesh.swift            # CREATE: icosphere geometry (vertices + unique edges)
      WireframeVisualizer.swift      # CREATE: stateful per-frame rotation, deformation, projection, edge-quad emission
      VisualizerStyle.swift          # MODIFY: add .wireframe case + factory + displayName + usesRoundParticles
  Tests/
    CoreTests/
      WireframeMeshTests.swift       # CREATE
      WireframeVisualizerTests.swift # CREATE
      VisualizerStyleTests.swift     # MODIFY: tests for .wireframe (count, displayName, factory, wrap)
```

Test count: 152 → 164 (+5 mesh + 4 visualizer + 3 style).

---

## Task 1: `WireframeMesh` — icosphere geometry generator

Pure-utility struct that builds a unit-sphere icosphere with `n` subdivisions and returns its vertices + unique edges. No audio, no rendering — just geometry.

**Files:**
- Create: `Sources/Core/WireframeMesh.swift`
- Create: `Tests/CoreTests/WireframeMeshTests.swift`

- [ ] **Step 1: Write the failing tests** — `Tests/CoreTests/WireframeMeshTests.swift`:

```swift
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
```

- [ ] **Step 2: Run `make test`** — expect FAIL (`WireframeMesh` doesn't exist).

- [ ] **Step 3: Create `Sources/Core/WireframeMesh.swift`:**

```swift
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
```

- [ ] **Step 4: Run `make test`** — expect `** TEST SUCCEEDED **`, **157** tests passing (152 + 5 new).
  - If `testSubdivision2Counts` reports 481 or 479 edges, the dedup or sort is off. Inspect the `addEdge` logic.
  - If `testAllVerticesAreUnitLength` reports length ≠ 1, the `midpoint` normalization is wrong. Verify it calls `simd_normalize` after averaging.

- [ ] **Step 5: Run `make build`** — expect `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/WireframeMesh.swift Tests/CoreTests/WireframeMeshTests.swift
git commit -m "Add WireframeMesh: golden-ratio icosphere with edge dedup"
```

---

## Task 2: `WireframeVisualizer` — per-frame rotation + deformation + edge-quad emission

Conform to `Visualizer`. Take the precomputed `WireframeMesh`, advance a rotation accumulator per frame, deform each vertex along its normal by the audio band mapped to its azimuth, project orthographically to 2D NDC, and emit each edge as a thin oriented quad.

**Files:**
- Create: `Sources/Core/WireframeVisualizer.swift`
- Create: `Tests/CoreTests/WireframeVisualizerTests.swift`

- [ ] **Step 1: Write the failing tests** — `Tests/CoreTests/WireframeVisualizerTests.swift`:

```swift
import XCTest
import simd
@testable import MacVisualizerCore

final class WireframeVisualizerTests: XCTestCase {

    private func frame(bands: [Float], t: TimeInterval = 0) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: bands.map { min($0 + 0.05, 1) },
                   waveform: [], rms: 0, peak: bands.max() ?? 0,
                   timestamp: t)
    }

    func testVertexCountMatchesEdgeCount() {
        // Subdivision-2 icosphere has 480 edges → 480 * 6 = 2880 vertices.
        let viz = WireframeVisualizer()
        let settings = VisualizerSettings.defaults
        let f = frame(bands: [Float](repeating: 0.5, count: 48))
        let verts = viz.makeVertices(frame: f, settings: settings, aspect: 1)
        XCTAssertEqual(verts.count, 480 * 6)
    }

    func testVerticesAreInClipSpace() {
        // Drive a few frames so rotation advances; check all output positions
        // stay within the expanded clip-space box (margin 0.2 for thick lines +
        // max displacement at full bands).
        let viz = WireframeVisualizer()
        let settings = VisualizerSettings.defaults
        let bands = [Float](repeating: 1.0, count: 48)
        for i in 0..<10 {
            _ = viz.makeVertices(frame: frame(bands: bands, t: TimeInterval(i) * 0.017),
                                 settings: settings, aspect: 1)
        }
        let verts = viz.makeVertices(frame: frame(bands: bands, t: 0.5),
                                     settings: settings, aspect: 1)
        for v in verts {
            XCTAssertGreaterThanOrEqual(v.position.x, -1.2)
            XCTAssertLessThanOrEqual(v.position.x, 1.2)
            XCTAssertGreaterThanOrEqual(v.position.y, -1.2)
            XCTAssertLessThanOrEqual(v.position.y, 1.2)
        }
    }

    func testRotationAdvancesBetweenFrames() {
        // After several frames with non-zero dt, vertex positions should differ
        // from the first-frame output (rotation has progressed).
        let viz = WireframeVisualizer()
        let settings = VisualizerSettings.defaults
        let bands = [Float](repeating: 0.5, count: 48)
        let f0 = viz.makeVertices(frame: frame(bands: bands, t: 0), settings: settings, aspect: 1)
        // Advance several frames at 60 fps.
        for i in 1..<60 {
            _ = viz.makeVertices(frame: frame(bands: bands, t: TimeInterval(i) * 0.017),
                                 settings: settings, aspect: 1)
        }
        let fLater = viz.makeVertices(frame: frame(bands: bands, t: 60 * 0.017),
                                      settings: settings, aspect: 1)
        // At least some output positions should differ.
        var diffCount = 0
        for (a, b) in zip(f0, fLater) {
            if abs(a.position.x - b.position.x) > 0.01 || abs(a.position.y - b.position.y) > 0.01 {
                diffCount += 1
            }
        }
        XCTAssertGreaterThan(diffCount, 100,
                             "rotation should have changed many vertex positions (got \(diffCount) differ)")
    }

    func testDeterministicSequences() {
        // Two fresh visualizers fed identical inputs produce identical output.
        let a = WireframeVisualizer()
        let b = WireframeVisualizer()
        let settings = VisualizerSettings.defaults
        let bands = [Float](repeating: 0.5, count: 48)
        for i in 0..<30 {
            let f = frame(bands: bands, t: TimeInterval(i) * 0.017)
            let va = a.makeVertices(frame: f, settings: settings, aspect: 1)
            let vb = b.makeVertices(frame: f, settings: settings, aspect: 1)
            XCTAssertEqual(va.count, vb.count)
            for (xa, xb) in zip(va, vb) {
                XCTAssertEqual(xa.position.x, xb.position.x, accuracy: 1e-5)
                XCTAssertEqual(xa.position.y, xb.position.y, accuracy: 1e-5)
            }
        }
    }
}
```

- [ ] **Step 2: Run `make test`** — expect FAIL (`WireframeVisualizer` doesn't exist).

- [ ] **Step 3: Create `Sources/Core/WireframeVisualizer.swift`:**

```swift
import simd
import QuartzCore

/// 9th visualizer style: subdivided icosphere wireframe with audio-deformed
/// vertices. Rotates slowly on the Y axis with a constant X tilt; each vertex
/// pushes outward along its normal by the audio band mapped to its azimuth.
/// Stateful — the renderer caches one instance across frames.
public final class WireframeVisualizer: Visualizer {

    // Precomputed mesh (built once at init).
    private let baseVertices: [SIMD3<Float>]
    private let edges: [(Int, Int)]

    // Animation state.
    private var rotationY: Float = 0
    private var lastTimestamp: CFTimeInterval = -1

    // Tunables — fixed in v1; expose in Settings later if needed.
    private let baseRadius: Float = 0.50
    private let displaceScale: Float = 0.20
    private let edgeHalfThickness: Float = 0.003
    private let rotationSpeed: Float = 0.5      // rad/s on Y axis
    private let tiltX: Float = 0.3              // constant X tilt (rad)

    public init() {
        let mesh = WireframeMesh.icosphere(subdivisions: 2)
        self.baseVertices = mesh.vertices
        self.edges = mesh.edges
    }

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        // --- Advance rotation ---------------------------------------------
        let dt: Float
        if lastTimestamp < 0 {
            dt = 0
        } else {
            dt = Float(min(max(frame.timestamp - lastTimestamp, 0), 0.1))
        }
        lastTimestamp = frame.timestamp
        rotationY += dt * rotationSpeed

        // --- Resolve palette + aspect correction --------------------------
        let palette = ColorPalette.preset(named: settings.paletteName)
            ?? ColorPalette.preset(named: "classic")!
        var sx: Float = 1, sy: Float = 1
        if aspect >= 1 { sx = 1 / aspect } else { sy = aspect }

        // --- Per-vertex: deform, rotate, project, sample color -----------
        let bandCount = max(frame.bands.count, 1)
        let cosX = cos(tiltX), sinX = sin(tiltX)
        let cosY = cos(rotationY), sinY = sin(rotationY)

        struct ProjectedVertex {
            var screen: SIMD2<Float>
            var color: SIMD4<Float>
        }
        var projected = [ProjectedVertex](repeating: ProjectedVertex(screen: .zero, color: .zero),
                                          count: baseVertices.count)
        for i in 0..<baseVertices.count {
            let v = baseVertices[i]
            // Map azimuth angle in XZ-plane → band index. Use BASE vertex (not
            // rotated) so each vertex always reads the same band — the band
            // physically rotates with the mesh as the user sees the geometry
            // turn.
            let azimuth = atan2(v.x, v.z)              // ∈ [-π, π]
            let t = (azimuth + .pi) / (2 * .pi)        // 0..1
            let bandIndex = min(bandCount - 1, max(0, Int(t * Float(bandCount))))
            let energy = frame.bands[bandIndex]
            // Push outward along the vertex's own normal (== position on unit sphere).
            let displaced = v * (baseRadius + energy * displaceScale)

            // Apply tilt-X, then rotate-Y.
            let v1 = SIMD3<Float>(displaced.x,
                                  displaced.y * cosX - displaced.z * sinX,
                                  displaced.y * sinX + displaced.z * cosX)
            let v2 = SIMD3<Float>( v1.x * cosY + v1.z * sinY,
                                   v1.y,
                                  -v1.x * sinY + v1.z * cosY)

            // Orthographic projection: drop z, apply aspect correction.
            let screen = SIMD2<Float>(v2.x * sx, v2.y * sy)

            // Color: palette sampled by energy.
            let c = palette.sample(at: energy)
            projected[i] = ProjectedVertex(screen: screen,
                                           color: SIMD4<Float>(c.r, c.g, c.b, 1))
        }

        // --- Emit edge-quads -----------------------------------------------
        var verts: [BarVertex] = []
        verts.reserveCapacity(edges.count * 6)
        for (a, b) in edges {
            let pa = projected[a].screen
            let pb = projected[b].screen
            let ca = projected[a].color
            let cb = projected[b].color

            // Perpendicular offset for the thin quad. Aspect-correct so the
            // line looks uniformly thick on screen.
            let dir = pb - pa
            let len = simd_length(dir)
            let perp: SIMD2<Float>
            if len > 1e-6 {
                let n = dir / len
                perp = SIMD2<Float>(-n.y, n.x) * edgeHalfThickness
            } else {
                perp = SIMD2<Float>(0, edgeHalfThickness)
            }
            let perpCorrected = SIMD2<Float>(perp.x * sx, perp.y * sy)

            let p00 = pa - perpCorrected
            let p01 = pa + perpCorrected
            let p10 = pb - perpCorrected
            let p11 = pb + perpCorrected

            // Two triangles: (p00, p10, p01) and (p10, p11, p01).
            // Colors interpolate from a→b across the quad.
            verts.append(BarVertex(position: SIMD4(p00.x, p00.y, 0, 1), color: ca))
            verts.append(BarVertex(position: SIMD4(p10.x, p10.y, 0, 1), color: cb))
            verts.append(BarVertex(position: SIMD4(p01.x, p01.y, 0, 1), color: ca))
            verts.append(BarVertex(position: SIMD4(p10.x, p10.y, 0, 1), color: cb))
            verts.append(BarVertex(position: SIMD4(p11.x, p11.y, 0, 1), color: cb))
            verts.append(BarVertex(position: SIMD4(p01.x, p01.y, 0, 1), color: ca))
        }
        return verts
    }
}
```

- [ ] **Step 4: Run `make test`** — expect `** TEST SUCCEEDED **`, **161** tests passing (157 + 4 new).

  Common failure modes:
  - `testVerticesAreInClipSpace` reports |y| > 1.2 → check `baseRadius + displaceScale` ≤ 1.0 (currently 0.7, so max projected |y| ≈ 0.7; well inside ±1.2).
  - `testRotationAdvancesBetweenFrames` reports too few diffs → check that `rotationY += dt * rotationSpeed` actually persists between calls.

- [ ] **Step 5: Run `make build`** — expect `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/WireframeVisualizer.swift Tests/CoreTests/WireframeVisualizerTests.swift
git commit -m "Add WireframeVisualizer: rotating icosphere with spatial-angle band mapping"
```

---

## Task 3: Wire `.wireframe` into `VisualizerStyle`

Add the new case to the style enum + factory + tests.

**Files:**
- Modify: `Sources/Core/VisualizerStyle.swift`
- Modify: `Tests/CoreTests/VisualizerStyleTests.swift`

- [ ] **Step 1: Write the failing tests** — append to `VisualizerStyleTests`:

```swift
    func testWireframeCaseExistsAndIsLast() {
        XCTAssertEqual(VisualizerStyle.allCases.count, 9)
        XCTAssertEqual(VisualizerStyle.allCases.last, .wireframe)
    }

    func testWireframeDisplayNameAndFactory() {
        XCTAssertEqual(VisualizerStyle.wireframe.displayName, "Wireframe")
        XCTAssertTrue(VisualizerStyle.wireframe.makeVisualizer() is WireframeVisualizer)
        XCTAssertFalse(VisualizerStyle.wireframe.usesRoundParticles)
    }

    func testWireframeNextPreviousWrapping() {
        XCTAssertEqual(VisualizerStyle.siri.next, .wireframe)
        XCTAssertEqual(VisualizerStyle.wireframe.next, .bars)
        XCTAssertEqual(VisualizerStyle.bars.previous, .wireframe)
        XCTAssertEqual(VisualizerStyle.wireframe.previous, .siri)
    }
```

If existing tests (`testAllCases`, `testNextWrapsAround`, `testPreviousWrapsAround`) hardcode the wrap target as `.siri` or check `allCases.count == 8`, update them:
- `XCTAssertEqual(VisualizerStyle.allCases.count, 8)` → `9`
- `XCTAssertEqual(VisualizerStyle.siri.next, .bars)` → `.wireframe`
- `XCTAssertEqual(VisualizerStyle.bars.previous, .siri)` → `.wireframe`

- [ ] **Step 2: Run `make test`** — expect FAIL (case doesn't exist, count mismatch).

- [ ] **Step 3: Add `.wireframe` to `VisualizerStyle`** in `Sources/Core/VisualizerStyle.swift`. Replace the enum body:

```swift
public enum VisualizerStyle: String, Codable, CaseIterable {
    case bars, radial, mirrored, oscilloscope, particles, fountain, fireworks, siri, wireframe

    public var displayName: String {
        switch self {
        case .bars: return "Bars"
        case .radial: return "Radial"
        case .mirrored: return "Mirrored"
        case .oscilloscope: return "Oscilloscope"
        case .particles: return "Particles"
        case .fountain: return "Fountain"
        case .fireworks: return "Fireworks"
        case .siri: return "Siri"
        case .wireframe: return "Wireframe"
        }
    }

    public var usesRoundParticles: Bool {
        switch self {
        case .particles, .fountain, .fireworks: return true
        case .bars, .radial, .mirrored, .oscilloscope, .siri, .wireframe: return false
        }
    }

    public func makeVisualizer() -> Visualizer {
        switch self {
        case .bars: return SpectrumBarsVisualizer()
        case .radial: return RadialSpectrumVisualizer()
        case .mirrored: return MirroredBarsVisualizer()
        case .oscilloscope: return OscilloscopeVisualizer()
        case .particles: return ParticleVisualizer()
        case .fountain: return SpectrumFountainVisualizer()
        case .fireworks: return FireworksVisualizer()
        case .siri: return SiriWaveVisualizer()
        case .wireframe: return WireframeVisualizer()
        }
    }

    public var next: VisualizerStyle {
        let all = Self.allCases
        let i = all.firstIndex(of: self)!
        return all[(i + 1) % all.count]
    }

    public var previous: VisualizerStyle {
        let all = Self.allCases
        let i = all.firstIndex(of: self)!
        return all[(i - 1 + all.count) % all.count]
    }
}
```

- [ ] **Step 4: Run `make test`** — expect `** TEST SUCCEEDED **`, **164** tests passing (161 + 3 new).

- [ ] **Step 5: Run `make build`** — expect `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Render-probe regression** — confirm wireframe renders without error:

```bash
BIN=$(find DerivedData -name MacVisualizer -type f -path '*/MacOS/*' 2>/dev/null | head -1)
"$BIN" --render-probe /tmp/p_wire.png wireframe
ls -la /tmp/p_wire.png
```

Expect a non-zero PNG. (Visible mesh edges in initial orientation — first-frame `dt=0` means no rotation accumulator advance; mesh is at default position with no displacement since bands are silent in the probe.)

- [ ] **Step 7: Commit**

```bash
git add Sources/Core/VisualizerStyle.swift Tests/CoreTests/VisualizerStyleTests.swift
git commit -m "Add .wireframe to VisualizerStyle (factory wires up WireframeVisualizer)"
```

---

## Task 4: Live verification (user)

- [ ] **Step 1: Launch the app**

```bash
make run
```

- [ ] **Step 2: Switch to wireframe**
- Cycle with ⌘] until you reach Wireframe (last in the list), or pick from the Visualizer menu.
- Confirm a wireframe icosphere appears, slowly rotating. With music playing or Demo Mode (⌥⌘D), vertices push outward proportional to the audio energy at each azimuth.

- [ ] **Step 3: Verify palette interaction**
- Cycle palettes (Settings → Visualization → Color palette). Edge colors change per-vertex by current band energy.
- Try `inferno` / `aurora` (HDR palettes): bright bands at high energy should produce visible bloom halos along edges.

- [ ] **Step 4: Verify rendering integrations**
- Toggle glow off / on. Wireframe edges visible without glow; significantly brighter with glow.
- Bump trail persistence to ~0.7. As the mesh rotates, trailing copies of edges fade. With HDR palette + trails: hot streaks.
- Bump vignette to ~0.4. Mesh corners darken; center unaffected.

- [ ] **Step 5: Verify cycling**
- ⌘] / ⌘[ to cycle through all 9 styles. Wireframe should appear at the end after Siri; ⌘] from Wireframe wraps back to Bars.
- ⌥] / ⌥[ to cycle palettes while on Wireframe — edge colors update live.

- [ ] **Step 6: Verify persistence**
- Switch to wireframe. ⌘Q. `make run`. App should reopen on the Wireframe visualizer.

(Nothing to commit. If something doesn't render, capture the issue.)

---

## Definition of Done

- `make test` → `** TEST SUCCEEDED **`, **164** tests passing (152 + 5 mesh + 4 visualizer + 3 style).
- `make build` → `** BUILD SUCCEEDED **`.
- Render probe with `wireframe` produces a non-zero PNG.
- `VisualizerStyle.allCases.count == 9` with `.wireframe` last; `.wireframe.makeVisualizer() is WireframeVisualizer`; `.wireframe.usesRoundParticles == false`.
- Live: wireframe icosphere visible, rotating, audio-deformed. Glow + trails + vignette + grain all layer correctly.

## Notes on implementation choices

- **No new renderer code** — every wireframe edge becomes a 6-vertex thin quad emitted through the existing sharp triangle pipeline. Reuses bloom, HDR, trails, vignette, grain for free.
- **Mesh built once at `init`** — the precomputed `vertices` and `edges` arrays are reused every frame; only the per-vertex deformation + projection runs per frame.
- **Spatial-angle band mapping** uses the BASE (un-rotated) vertex position so each physical vertex always reads the same band. As the mesh rotates, the user visually sees bands "rotating" with the geometry — bass section travels around the screen over time. Better than rotating the band assignment (which would make the visualization disconnect from spatial layout).
- **Orthographic projection** (no perspective FOV) — keeps the visualizer "flat enough" that all edges are roughly the same on-screen thickness; perspective foreshortening at this small scale wouldn't add much.
- **No depth testing / occlusion** — back edges show through front edges. That's the desired wireframe look (X-ray sphere); not a bug.
- **No new Settings UI** for v1. Rotation speed, subdivision count, displacement strength are fixed. If user wants control, the Settings UI is straightforward to add as a follow-up.
