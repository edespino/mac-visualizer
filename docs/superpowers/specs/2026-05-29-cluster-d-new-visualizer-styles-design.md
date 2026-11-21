# Cluster D — Four New Visualizer Styles — Design

**Date:** 2026-05-29
**Branch:** `plan-18-cluster-d-new-visualizer-styles`
**Source:** Items #8 (joy plot), #9 (heightfield), #10 (voronoi), #13 (lava lamp) from the 2026-05-28 visuals-repo deep-dive.

## Goal

Add four new visualizer styles, each with multiple render-mode variants, beat consumption via `frame.beat`/`beatIntensity`, and stereo awareness via `frame.bandsLeft`/`bandsRight` (Cluster A foundations). The catalog grows from 11 to 15 styles.

The four styles aim at visual territory the existing catalog doesn't cover:
- **Joy plot** — Joy Division "Unknown Pleasures" stacked smoothed area paths
- **Heightfield grid** — 3D-tilted 16×16 vertex mesh, audio-displaced
- **Voronoi cells** — stained-glass / blob / soft-cells geometric variants
- **Lava lamp** — organic moving density contours

## Architecture

Four new visualizer files, each conforming to the existing `Visualizer` protocol or the `ShaderKind`-dispatched fragment-shader pattern (precedent: plasma, bumpscope). Two new pure-function utility files (Delaunay triangulation, marching squares). Three new fragment shaders in `Shaders.metal`. Four new `VisualizerStyle` enum cases. Three new render-mode enums on `StyleProfile`. No changes to the existing post-process pipeline (bloom, trails, vignette, grain, kaleidoscope all wrap the new outputs uniformly).

Each render-mode switcher is isolated within its visualizer — flipping a mode swaps the implementation path inside the visualizer's `makeVertices(...)` or `customShader` dispatch, with no cross-style coupling.

## Component 1 — JoyPlotVisualizer

### File
`Sources/Core/JoyPlotVisualizer.swift` (new, ~135 LOC including comments + state)

### Algorithm

Four horizontal smoothed area paths stacked vertically. Each path is a closed polygon: the top edge traces the smoothed band values; the bottom edge sits at the row's `yBase`. Smoothing is a 3-point moving average over band values.

Per-row band mapping when `useStereoImage == false`:
- Row 0 (bottom): bands[0..count/3]                 — low freq
- Row 1: bands[count/3..2*count/3]                  — mid freq
- Row 2: bands[2*count/3..count]                    — high freq
- Row 3 (top): all bands averaged (mid-mix)         — overview

Per-row band mapping when `useStereoImage == true`:
- Row 0 (bottom): bandsLeft (full spectrum)
- Row 1: bands[0..count/2]                          — mono low half
- Row 2: bands[count/2..count]                      — mono high half
- Row 3 (top): bandsRight (full spectrum)

This keeps all four rows visually distinct: the outer rows show channel separation, the inner two show frequency separation across the mono mix.

Each row is sampled at 64 horizontal points, evenly spaced. Path emission as triangle quads between adjacent samples and the row's `yBase`.

On `frame.beat`: line/area thickness multiplier `1 + 0.5 * beatIntensity`, decays with 150ms half-life (re-use the `realDt`-based pattern from ParticleVisualizer).

### Tunables (private constants)
- `rowCount: Int = 4`
- `sampleCount: Int = 64`
- `rowSpacing: Float = 0.4` — vertical NDC between row baselines
- `rowHeight: Float = 0.15` — max amplitude in NDC

### Tests
- Vertex bounds within `[-1.25, +1.25]`
- Vertex count is multiple of 6 (triangle quads)
- Determinism (same input → same output; no per-instance state beyond beatBoost)
- `frame.beat == true` produces wider quads than `frame.beat == false` (similar shape to particle boost test)
- `useStereoImage == true` + hard-left input: bottom row (bandsLeft) shows visible amplitude; top row (bandsRight) is flat

## Component 2 — HeightfieldVisualizer

### File
`Sources/Core/HeightfieldVisualizer.swift` (new, ~365 LOC for both render modes)

### Algorithm

A `gridSize × gridSize` (default 16×16) grid of vertices in 3D. Each vertex has:
- `(x, y)` from grid coordinates in NDC, perspective-transformed
- `z` from a band magnitude lookup

Band-to-grid mapping by column index. The 16×16 grid has 16 columns; bands are sampled at column positions via `bands[col * bands.count / gridSize]`.

Camera setup: fixed orthographic-ish projection with a 25° X-axis tilt (rotateX matrix). Z displacement is scaled by `0.25 * level` in NDC units (max ~0.25 unit displacement at level=1).

When `useStereoImage == true`:
- Left 8 columns driven by `bandsLeft`
- Right 8 columns driven by `bandsRight`

When `useStereoImage == false`: all columns from `bands`.

On `frame.beat`: Z amplitude multiplier `1 + 0.4 * beatIntensity`, decays with 200ms half-life.

### Render modes

`HeightfieldRenderMode { case wireframe, solid }`. Defaults to `.wireframe`.

**`.wireframe`**: emits horizontal lines (one per row) and vertical lines (one per column) as `[BarVertex]` line-primitive pairs. Reuses the line-primitive draw path established by `WireframeVisualizer`. Vertex color: palette sample at `level`.

**`.solid`**: emits `(gridSize-1)² × 2 = 450` filled triangles. Each triangle gets vertex normals computed from cross-product of adjacent edges; flat-shaded with a fixed light direction `(0.5, 0.7, 0.5)` (normalized). Vertex color: palette sample at `level` × `max(0.3, dot(normal, lightDir))`.

### Tunables (private constants)
- `gridSize: Int = 16`
- `tiltAngle: Float = .pi / 7.5` — ≈ 24° X-axis tilt
- `zScale: Float = 0.25` — band level → Z displacement
- `lightDir: SIMD3<Float> = normalize(SIMD3(0.5, 0.7, 0.5))`

### Tests
- Per render mode: vertex bounds, determinism
- `.wireframe`: vertex count is `gridSize * 2 * (gridSize-1) * 2` (rows + cols, line pairs)
- `.solid`: vertex count is `(gridSize-1)^2 * 6` (triangles)
- Beat consumer: max Z extent on beat frame > non-beat frame
- Stereo split: hard-left input makes left half taller than right half

## Component 3 — VoronoiVisualizer

### File
`Sources/Core/VoronoiVisualizer.swift` (new, ~225 LOC for visualizer; Delaunay utility in separate file ~80 LOC)
`Sources/Core/Delaunay.swift` (new, ~80 LOC, Bowyer-Watson algorithm)

### Algorithm

75 seed points generated deterministically at startup via `SeededRNG(seed: 0xCE110155)`. Each seed point lives in NDC `[-1, +1]^2`.

Per-cell band assignment: cell index → band index via `bandIdx = i % bands.count`. (Simple round-robin; alternatives like angular mapping not worth the extra LOC.)

Per-cell color and opacity: palette sample at `level` × cell-specific tint variation (small `±10%` jitter from the SeededRNG, so the cluster looks "alive" not uniform).

When `useStereoImage == true`: cells with center `x < 0` driven by `bandsLeft[bandIdx]`, `x ≥ 0` by `bandsRight[bandIdx]`.

On `frame.beat`: all-cell brightness multiplier `1 + 0.3 * beatIntensity`, 100ms half-life.

### Render modes

`VoronoiRenderMode { case cells, blobs, softCells }`. Defaults to `.cells`.

**`.cells`** (vertex-emit): precomputed Delaunay triangulation at init, converted to proper Voronoi dual. For each seed point, collect all Delaunay triangles containing it; the circumcenters of those triangles in angular order around the seed form the Voronoi cell polygon. Each cell rendered as a triangle fan from its center. Sharp stained-glass look — each cell is a polygonal region of pixels closer to its seed than any other.

(Computing the Voronoi dual from Delaunay: ~50 LOC of post-processing on top of the Delaunay output. The dual computation is well-known and deterministic given the input triangulation.)

**`.blobs`** (fragment shader): `voronoi_fs` in `Shaders.metal`. Per-pixel, compute distance to all 75 seed points; smooth-min via `exp(-dist*K)` weighted sum produces soft radial blobs (no hard edges). Each seed contributes its band-driven color. K controls edge softness; default K=12.

**`.softCells`** (hybrid): emit `.cells` triangles into an offscreen MTLTexture, then a 2-pass separable Gaussian blur (radius=4px) writes into the scene texture. Two-stage rendering, requires a temp texture and two extra shader passes.

### Tunables (private constants)
- `seedCount: Int = 75`
- `seedRng: SeededRNG = SeededRNG(seed: 0xCE110155)`
- `blobK: Float = 12.0` — fragment-shader sharpness

### Tests
- Delaunay (separate test file `DelaunayTests.swift`):
  - Triangulation of 4 corner points of a square produces 2 triangles
  - All output triangles are CCW-oriented
  - For 20 random non-degenerate points: triangle count ≤ 2N-5 (Euler's formula)
  - No vertex appears in more than (N+2) triangles
- VoronoiVisualizer per render mode: vertex bounds (where applicable), determinism (same seed → same triangulation)
- Beat consumer: cell brightness on beat frame > non-beat
- Stereo split: hard-left input makes left-half cells brighter

## Component 4 — LavaLampVisualizer

### File
`Sources/Core/LavaLampVisualizer.swift` (new, ~270 LOC for visualizer)
`Sources/Core/MarchingSquares.swift` (new, ~120 LOC, iso-line extraction)

### Algorithm

12 moving point sources (metaballs). Each point has:
- `position: SIMD2<Float>` in NDC
- `velocity: SIMD2<Float>` from inline 2D value-noise (small private function `value2D(x: Double, y: Double, seed: UInt64) -> Float` in the same file — implementation mirrors `SiriWaveVisualizer`'s `value1D` but with a hash of two coordinates)
- `bandIdx: Int` — which band drives its amplitude

Per-frame: advance positions; if a point exits `[-1.2, +1.2]^2`, respawn near center. Density field at pixel `(x, y)` = `Σ amplitude_i / max(distance_i, 0.01)^2`.

Iso-lines at thresholds `[0.5, 1.0, 1.5, 2.0]` (four nested contours).

When `useStereoImage == true`: points with `position.x < 0` driven by `bandsLeft[bandIdx]`, `x ≥ 0` by `bandsRight[bandIdx]`.

On `frame.beat`: density threshold multiplier `1 - 0.2 * beatIntensity` (briefly lowers thresholds, expanding contours), 200ms half-life.

### Render modes

`LavaLampRenderMode { case shader, marchingSquares }`. Defaults to `.shader`.

**`.shader`** (fragment shader): `lavalamp_fs` in `Shaders.metal`. Per-pixel, evaluate density. For each threshold T_k, contribute color if `|density - T_k| < tolerance` (tolerance ≈ 0.05). Smooth fast iso-lines.

**`.marchingSquares`** (CPU): sample density on a 64×64 grid. For each cell, look up the 4-bit corner pattern in the marching-squares table; emit the appropriate line segment(s). Render segments as line-primitive `BarVertex` pairs. Sharper, ~4,000 segments per threshold per frame.

### Tunables (private constants)
- `pointCount: Int = 12`
- `thresholds: [Float] = [0.5, 1.0, 1.5, 2.0]`
- `mscGridSize: Int = 64` — marching squares sampling resolution

### Tests
- MarchingSquares (separate test file `MarchingSquaresTests.swift`):
  - Density field of a single point at origin with radius r produces a circular contour at threshold T (vertex positions lie within tolerance of expected radius)
  - Empty field (all zeros) produces zero segments
  - Saddle-point disambiguation: known 4-bit case 5 (diagonal corners) produces 2 separate segments (not connected through the middle)
- LavaLampVisualizer per render mode: vertex bounds (where applicable), determinism on fixed seed
- Beat consumer: total visible contour area on beat frame > non-beat
- Stereo split: hard-left input visibly differentiates left vs right half densities

## Component 5 — Settings and StyleProfile additions

### File
`Sources/Core/StyleProfile.swift` (modify)

Add three Codable enums + three `StyleProfile` fields:

```swift
public enum VoronoiRenderMode: String, Codable, Equatable, CaseIterable { case cells, blobs, softCells }
public enum HeightfieldRenderMode: String, Codable, Equatable, CaseIterable { case wireframe, solid }
public enum LavaLampRenderMode: String, Codable, Equatable, CaseIterable { case shader, marchingSquares }

extension StyleProfile {
    var voronoiRenderMode: VoronoiRenderMode { ... }    // default .cells
    var heightfieldRenderMode: HeightfieldRenderMode { ... }   // default .wireframe
    var lavaLampRenderMode: LavaLampRenderMode { ... }   // default .shader
}
```

These three fields use the tolerant-decoder pattern (decodeIfPresent + default). Existing user `StyleProfile` snapshots ignore unknown keys; new fields default cleanly.

### File
`Sources/App/SettingsView.swift` (modify)

In the "Style Settings" tab (currently shows per-style sliders for the active style), add a render-mode `Picker` that appears only when the active style is voronoi / heightfield / lava lamp. Three Pickers, each visible conditionally — keeps the UI uncluttered for other styles.

## Component 6 — Visualizer protocol + factory wiring

### File
`Sources/Core/VisualizerStyle.swift` (modify)

Add four cases: `.joyPlot, .heightfield, .voronoi, .lavaLamp`. Update `displayName`, `allCases` already auto-includes. Catalog grows from 11 to 15.

### File
`Sources/Rendering/MetalRenderer.swift` (modify)

Add three new `ShaderKind` cases: `.voronoiBlobs, .lavaLampShader, .heightfieldSolid`. The renderer's `customShader` dispatch routes each to its fragment shader pipeline.

For vertex-emitting modes (`.joyPlot`, `.heightfield(.wireframe)`, `.voronoi(.cells)`, `.lavaLamp(.marchingSquares)`), the standard `makeVertices(...)` → triangle/line draw call applies.

For hybrid `.voronoi(.softCells)`: routes through a new two-pass path (vertex-emit to temp texture, then blur into scene). Add a private helper in `MetalRenderer` to manage the temp texture.

## Component 7 — Shaders

### File
`Sources/Rendering/Shaders.metal` (modify)

Add three fragment shaders:

```metal
fragment float4 voronoi_fs(/* uniforms: 75 seed points + 75 colors + K */, ...);
fragment float4 lavalamp_fs(/* uniforms: 12 point positions + amplitudes + 4 thresholds + tolerance */, ...);
fragment float4 heightfield_solid_fs(/* uniforms: light direction */, ...);
```

Each shader uses a uniform buffer for its parameters (avoid hardcoded array sizes — use a max constant and a count).

## Visual validation (REQUIRED)

Final task before merge: visual validation, not optional, applying the cluster-A learning.

1. **Offscreen render probe** — `RenderProbe` produces PNG snapshots for each of the 4 styles × each render mode = 9 PNGs total. Snapshots use a fixed synthetic frame with stereo bands and a beat-active state, so the output is deterministic. Attach PNGs to the final-review subagent.

2. **Live app walk** — user launches the built app with real music, walks each new style, toggles `useStereoImage` on/off, cycles render modes via the Picker. Reports anything off.

Cluster is not "done" until both pass.

## Risks and tradeoffs

1. **Cluster size.** ~1,800 LOC total — the largest cluster to date. Mitigation: pure-function utilities (`Delaunay`, `MarchingSquares`) are independent and testable; render modes are isolated within each visualizer; foundation tests catch algorithm bugs before integration.

2. **Aesthetic match.** Voronoi and lava lamp have distinctly different vibes from existing styles. Risk that the new styles feel out of place with HDR bloom / trails. Visual validation step will surface this; tuning constants are exposed for quick iteration.

3. **Delaunay correctness edge cases.** Bowyer-Watson super-triangle removal can leave artifacts; degenerate (collinear) input causes infinite loops. Mitigation: deterministic seed produces well-distributed points (no collinearity); test suite covers known geometries.

4. **Marching squares ambiguity.** Case 5 (`0101`) and Case 10 (`1010`) — both diagonal-corner cases — have two valid disambiguations: "joined" (one connected curve through the cell center) or "separate" (two disjoint segments). We pick the "separate" tiebreak (not connected through middle); document the choice in `MarchingSquares.swift`. Visually noticeable only at fine grid resolutions or extreme thresholds.

5. **Voronoi `.softCells` hybrid mode** is the most novel rendering path. Requires temp MTLTexture allocation + 2-pass blur. If it produces edge artifacts or perf issues, dropping to two voronoi modes is a one-task removal.

6. **Heightfield `.solid` fixed light** may look static. Auto-rotating light is a follow-up if it feels lifeless.

## Non-goals

- No new audio analysis (Cluster A already shipped beat + stereo)
- No new post-process effects (Cluster B's territory — feedback warp, reflected floor, RMS hue rotation)
- No MilkDrop / projectM integration (separate decision)
- No auto-cycle through render modes (manual Picker only)

## Estimated scope

- ~1,250 LOC implementation across 4 visualizers + 2 utilities + 3 shaders
- ~400 LOC tests (~30-40 new tests)
- ~150 LOC settings/codec/UI
- **~1,800 LOC total**
- 16-20 implementation tasks following TDD pattern

## Out of scope (future clusters)

- Cluster B — Feedback-warp post-process + Reflected floor + RMS hue rotate
- Cluster C — Barycentric wireframe + Multi-band siri (note: multi-band siri builds on stereo path, independent of this cluster)
- Cluster E — Crossfade + Perlin drift
- MilkDrop integration — separate decision tree (projectM embed vs butterchurn port vs technique mining)
