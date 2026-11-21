# Wireframe Mesh Visualizer — Design

- **Date:** 2026-05-28
- **Status:** Approved design (pre-implementation)
- **Audience:** Personal use, single developer
- **Target OS:** macOS 14.4+ (unchanged)

## 1. Goal

Add a 9th visualizer style — **`wireframe`** — that draws a slowly-rotating subdivided icosphere whose vertices are pushed outward along their normals proportional to per-vertex audio band energy. Each edge of the mesh is rendered as a thin glowing line. Color comes from the active palette, sampled by per-vertex energy. Gives the visualizer catalog its first true 3D feel.

After this change, `VisualizerStyle.allCases` is 9: bars, radial, mirrored, oscilloscope, particles, fountain, fireworks, siri, **wireframe**.

## 2. Background / current state

- `Visualizer` protocol: `func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex]`. Every existing visualizer emits filled triangles via the sharp or round-particle pipelines.
- `VisualizerStyle` (`String`, `Codable`, `CaseIterable`) drives menu/⌘]/⌘[/picker switching. Adding a case auto-extends the menus.
- The Metal renderer has only one geometry-primitive type: triangles. There's no `.line` draw path. We need either: (a) add a line-primitive draw path, or (b) emit each wireframe edge as a thin oriented quad (6 vertices), reusing the existing triangle pipeline.
- The existing sharp pipeline (`pipeline` / `pipeline16`) handles arbitrary triangle vertex streams.
- Bloom + HDR palettes work for anything the pipeline draws; wireframe edges get the same glow halo as any other visualizer.

## 3. Non-goals

- No tunable rotation speed / subdivision count / displacement strength in Settings for v1. Ship with defaults; add sliders later if needed.
- No new render pipeline / shader — reuse existing sharp pipelines via thin-quad emission per edge.
- No interaction with mouse/touch — the mesh rotates autonomously.
- No solid-fill mode — wireframe-only.
- No texture mapping, no per-edge thickness variation.
- No `wireframe`-specific tunables on a new Settings tab. (Particle size / speed / etc. from the Tweaks tab don't apply.)

## 4. Decisions (locked)

| Area | Decision |
| --- | --- |
| Mesh shape | **Subdivided icosphere** — base icosahedron (12 vertices, 20 triangles) subdivided 2× → 162 vertices, 320 triangles, 480 unique edges |
| Edge rendering | **Thin oriented quads** (6 verts/edge via existing sharp pipeline). ~2880 verts/frame. No new render path. |
| Camera | **Slow auto-rotation** on Y axis at ~0.5 rad/s plus slight constant X tilt (~0.3 rad) for visual depth |
| Projection | **Orthographic** (no perspective foreshortening). Mesh scale ~0.7 NDC so it fits comfortably with aspect correction. |
| Audio mapping | **Spatial-angle band-of-N**: each vertex's azimuth `atan2(vx, vz) ∈ [-π, π]` maps to band index `floor((azimuth + π) / (2π) · N)`. Vertex displacement = `band[index] · displaceScale` along the vertex's normal (which equals its position on the unit sphere). |
| Color | **Per-vertex palette sample** by `vertex.energy` (which is `band[index]` for that vertex). Bright bands → top of palette, dim bands → bottom. |
| Default displacement | `displaceScale = 0.20` (vertex max push = 20% NDC; combined with base radius 0.5 NDC = max outer radius 0.7 NDC, fits screen). |
| Default edge thickness | `0.003` NDC half-width. With bloom on, lines glow nicely. |
| Aspect correction | Standard pattern (used by other visualizers): if `aspect ≥ 1`, scale x; else scale y. Applied to both the projected vertex coordinates AND the thin-quad's perpendicular thickness. |
| Settings | **No new settings fields**. The 9th style just appears in the picker. |

## 5. Architecture

### 5.1 New: `Sources/Core/WireframeVisualizer.swift`

```
public final class WireframeVisualizer: Visualizer {
    // Pre-computed mesh data (built once at init).
    private let baseVertices: [SIMD3<Float>]  // 162 unit-sphere positions
    private let edges: [(Int, Int)]            // 480 (i, j) index pairs into baseVertices

    // Animation state.
    private var rotationY: Float = 0           // accumulator advanced by dt
    private var lastTimestamp: CFTimeInterval = -1

    // Tunables (private; not exposed in Settings v1).
    private let subdivisionLevel = 2           // 0 = base icosahedron, 2 = ~120 edges
    private let baseRadius: Float = 0.50
    private let displaceScale: Float = 0.20
    private let edgeHalfThickness: Float = 0.003
    private let rotationSpeed: Float = 0.5     // rad/s on Y axis
    private let tiltX: Float = 0.3             // constant X tilt (rad)

    public init() {
        let mesh = WireframeMesh.icosphere(subdivisions: 2)
        self.baseVertices = mesh.vertices
        self.edges = mesh.edges
    }

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        // 1. Advance rotation.
        // 2. Build (3D) deformed positions: position = baseVertex * (baseRadius + bandEnergy * displaceScale).
        // 3. Rotate by tilt-X then rotateY; project ortho to (x, y).
        // 4. For each edge: emit a thin oriented quad in 2D NDC, colored by per-vertex palette sample.
    }
}
```

### 5.2 New: `Sources/Core/WireframeMesh.swift`

```
struct WireframeMesh {
    let vertices: [SIMD3<Float>]
    let edges: [(Int, Int)]   // unique edges; each pair sorted ascending

    /// Subdivide icosphere `subdivisions` times. Returns normalized unit-sphere vertices.
    static func icosphere(subdivisions: Int) -> WireframeMesh
}
```

Algorithm:
1. Build base icosahedron: 12 vertices on the unit sphere using the golden-ratio formula. 20 triangular faces.
2. For each subdivision level: for each face, split into 4 sub-faces by inserting midpoints on each edge; renormalize new vertices to unit length (so they land on the sphere). Use a vertex-cache keyed by sorted index pair so shared edges share midpoint vertices.
3. After subdivisions, extract unique edges from the face list: for each face `(a, b, c)`, add edges `(a,b), (b,c), (a,c)`, with each sorted ascending and deduplicated.

At subdivision 2: 162 vertices, 320 faces, **480 unique edges** (Euler: V - E + F = 2 → E = V + F - 2 = 162 + 320 - 2 = 480).

### 5.3 Edge-as-quad geometry

For each edge `(i, j)` with projected 2D vertices `p_i = (xi, yi)` and `p_j = (xj, yj)`:

```
direction = normalize(p_j - p_i)
perpendicular = (-direction.y, direction.x) * edgeHalfThickness
// Apply aspect correction to perp so the line looks uniformly thick.
let perpCorrected = SIMD2(perpendicular.x * sx, perpendicular.y * sy)

// 4 corner positions:
let p00 = p_i - perpCorrected
let p01 = p_i + perpCorrected
let p10 = p_j - perpCorrected
let p11 = p_j + perpCorrected

// 6 vertices: two triangles forming the thin quad.
emit triangle (p00, p10, p01)
emit triangle (p10, p11, p01)

// Colors: each end vertex's energy → palette sample.
let colorI = palette.sample(at: energy_i)
let colorJ = palette.sample(at: energy_j)
// All 6 vertices use one of these two colors; linear interpolation is implicit
// across the quad via Metal's vertex-to-fragment color interpolation.
```

Total vertex count per frame: `480 edges × 6 verts = 2880`. Comfortably under the existing renderer's grow-only vertex buffer.

### 5.4 Camera math

```
// Per-frame rotation update.
rotationY += dt * rotationSpeed

// Build rotation: first tilt around X, then rotate around Y. (Order matters.)
func rotate(_ v: SIMD3<Float>) -> SIMD3<Float> {
    // Rotate X by tiltX.
    let cosX = cos(tiltX), sinX = sin(tiltX)
    let v1 = SIMD3<Float>(
        v.x,
        v.y * cosX - v.z * sinX,
        v.y * sinX + v.z * cosX
    )
    // Rotate Y by rotationY.
    let cosY = cos(rotationY), sinY = sin(rotationY)
    return SIMD3<Float>(
        v1.x * cosY + v1.z * sinY,
        v1.y,
        -v1.x * sinY + v1.z * cosY
    )
}

// Project to 2D (orthographic): drop z.
func project(_ v3: SIMD3<Float>) -> SIMD2<Float> {
    return SIMD2(v3.x, v3.y)
}
```

Apply aspect correction at projection: `projected.x *= sx; projected.y *= sy` (or equivalent), same pattern as oscilloscope.

### 5.5 `VisualizerStyle` (modify)

- Add `case wireframe` after `.siri`. String raw value `"wireframe"`.
- `displayName`: `"Wireframe"`.
- `makeVisualizer()`: `return WireframeVisualizer()`.
- `usesRoundParticles`: `false` (sharp pipeline).
- `next`/`previous` continue to work via `allCases`.

### 5.6 No other code changes

- `MetalView`, `RenderModel`, `RenderProbe`, `SettingsView`, shaders — all unaffected.
- The bloom + HDR pipeline + trails + vignette/grain post-process all work on the wireframe output for free (it's just another set of triangles flowing through the same pipelines).

## 6. Testing strategy

**Unit-tested:**
- `WireframeMesh.icosphere(subdivisions: 0)` has 12 vertices, 30 edges (icosahedron).
- `WireframeMesh.icosphere(subdivisions: 1)` has 42 vertices, 120 edges.
- `WireframeMesh.icosphere(subdivisions: 2)` has 162 vertices, 480 edges.
- All vertices are unit length (within float epsilon).
- All edges are sorted (`i < j`) and unique (no duplicates in the array).
- `WireframeVisualizer.makeVertices(...)` returns `480 * 6 = 2880` vertices for the default subdivision-2 mesh.
- `WireframeVisualizer.makeVertices(...)` produces vertices within clip space (`|x|, |y| ≤ 1.2` with a 0.2 margin for thick lines + max displacement).
- Determinism: two `WireframeVisualizer` instances given identical inputs produce identical output (no RNG in this visualizer).
- `VisualizerStyle.allCases.count == 9`; `.wireframe.makeVisualizer() is WireframeVisualizer`; `.wireframe.displayName == "Wireframe"`; `.wireframe.usesRoundParticles == false`.
- `.siri.next == .wireframe`; `.wireframe.next == .bars`; `.bars.previous == .wireframe`.

**Verified by running:**
- `--render-probe /tmp/p_wire.png wireframe` produces a non-zero PNG with visible mesh edges (since first frame has `dt=0`, the mesh shows undeformed but the rotation accumulator is 0, so it's a known orientation).
- Live: switch to wireframe (⌘] / menu / picker). Mesh visible, rotating slowly, deforming on bass. Combined with bloom: edges glow. Combined with HDR palette + trails: hot trails as the mesh moves.

## 7. Risks & mitigations

- **Aspect correction subtle** — projected 2D quad needs perpendicular thickness scaled differently per axis to stay visually thin. *Mitigation:* mirror the existing oscilloscope pattern (`sx = 1/aspect` if `aspect ≥ 1`, else `sy = aspect`); apply to both the projected vertex AND the perpendicular offset.
- **Z-fighting / overdraw** — both front-facing and back-facing edges render at the same depth (we're not doing depth testing). All 480 edges draw every frame; back edges show through. *Mitigation:* this is actually the desired wireframe look (no occlusion). Not a problem.
- **Vertex count limit** — 2880 verts/frame; renderer's grow-only vertex buffer handles this without per-frame allocation. Comfortable budget.
- **First-frame `dt = 0`** — mesh appears in initial orientation with no rotation drift; subsequent frames advance. Matches what other dt-driven visualizers do.
- **No depth in 2D projection** — edges in the back of the sphere overlay edges in the front. Could feel busy. *Mitigation:* the slight X tilt + slow rotation breaks up symmetry visually; combined with palette color gradient across band index, the rotating sphere reads clearly.
- **Subdivision 2 might be too dense / sparse** — *Mitigation:* easy to tune `subdivisionLevel` constant if needed during live verify. Subdivision 1 = 120 edges (sparser); subdivision 3 = 1920 edges (4× denser).

## 8. Out of scope / future
- Solid-fill mode (showing triangles, not just edges).
- Per-style tunables in Settings (rotation speed, mesh density, displacement strength).
- Different mesh types (grid heightmap, cylinder, torus).
- Real perspective projection (with FOV / camera-distance controls).
- Per-vertex normal lighting (would require depth-aware shading).
- Mouse interaction (drag-to-rotate).
- Sub-mesh particle emission from vertices on beat.
