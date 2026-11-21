# Wireframe Controls — Design

**Date:** 2026-06-28
**Branch:** `polly/wireframe-controls`
**Source:** User request — the Wireframe visualizer hardcodes every tunable; bring them over as user controls, the same way Polartone and Star Nest were enhanced. Based on a read-only explore of `main` @ `92f7c57`: Wireframe is a **CPU vertex-emit** style (`WireframeVisualizer`), not a Metal shader, so it needs **no** shader-uniform/buffer plumbing — settings flow directly into `makeVertices`, exactly like Polartone.

## Goal

Expose the Wireframe visualizer's hardcoded constants as user-tunable settings: 6 scalars (base radius, audio displacement, line thickness, rotation speed, X tilt, line opacity) plus a structural mesh-resolution control (subdivisions). Each control's default equals the current literal, so the look is byte-identical until a control is moved. Audio reactivity is preserved (it is driven by the displacement scale).

## Architecture

All changes are additive and confined to the CPU path:

- **Settings**: 7 new flat top-level fields on `VisualizerSettings` (Polartone/Star Nest precedent), tolerant Codable + migration + Equatable.
- **Visualizer**: `WireframeVisualizer.makeVertices` replaces each hardcoded literal with the matching setting; the hardcoded line alpha `1` becomes `wireframeLineOpacity`; `wireframeSubdivisions` feeds `WireframeMesh.icosphere(subdivisions:)`, clamped to 0–4 at the use site.
- **UI**: the active-aware `controls(for:)` switch gains a `wireframeControls` case — 6 scalar sliders plus a "Detail (performance)" subgroup for the subdivisions stepper/slider.
- **Reset**: `resetCurrentStyle()` gains a `.wireframe` branch resetting these new top-level fields (Wireframe currently exposes no exclusive top-level fields, so it is not yet in that switch).

No change to `MetalRenderer`, `Shaders.metal`, `ShaderInputs`, buffer indices, or the `Visualizer` protocol.

## Component 1 — Settings fields

### Files
- `Sources/Core/VisualizerSettings.swift`

### Design
Add 7 fields, each `Codable`, each defaulting to the current literal so default output is unchanged. Mirror the `polartone*` / `starNest*` flat-field precedent exactly (declaration, init param, default in `VisualizerSettings.defaults`, CodingKeys, `decodeIfPresent ?? default`, encode, Equatable).

| Field | Type | Default | Slider range | Source literal |
|---|---|---|---|---|
| `wireframeBaseRadius` | Double | 0.50 | 0.2–1.0 | `baseRadius` (`WireframeVisualizer.swift:34`) |
| `wireframeDisplaceScale` | Double | 0.20 | 0.0–0.6 | `displaceScale` (`:35`) |
| `wireframeLineThickness` | Double | 0.003 | 0.001–0.02 | `edgeHalfThickness` (`:36`) |
| `wireframeRotationSpeed` | Double | 0.5 | −2.0…2.0 | `rotationSpeed` (`:37`) |
| `wireframeTiltX` | Double | 0.3 | −π…π | `tiltX` (`:38`) |
| `wireframeLineOpacity` | Double | 1.0 | 0.0–1.0 | hardcoded alpha `1` (`:97`) |
| `wireframeSubdivisions` | Int | 2 | 0–4 (clamped) | `subdivisions: 2` (`:41`) |

The field-name semantics preserve the existing literal exactly: `wireframeLineThickness` stores the **half-thickness** value (default `0.003`), matching `edgeHalfThickness`, so parity holds with no arithmetic change.

`wireframeSubdivisions` is clamped to `0...4` on decode (mirroring the Star Nest density decode-clamp), so a corrupt/hand-edited `settings.json` can never push it out of range.

## Component 2 — Visualizer reads the settings

### Files
- `Sources/Core/WireframeVisualizer.swift`

### Design
Replace each local hardcoded constant with the corresponding `settings.wireframe*` value:
- `baseRadius` → `settings.wireframeBaseRadius`
- `displaceScale` → `settings.wireframeDisplaceScale`
- `edgeHalfThickness` → `settings.wireframeLineThickness`
- `rotationSpeed` → `settings.wireframeRotationSpeed`
- `tiltX` → `settings.wireframeTiltX`
- per-vertex color alpha `1` → `Float(settings.wireframeLineOpacity)`
- `WireframeMesh.icosphere(subdivisions: 2)` → `WireframeMesh.icosphere(subdivisions: min(max(settings.wireframeSubdivisions, 0), 4))`

The `dt` clamp (`0.1`), azimuth band-mapping, orthographic projection, aspect correction, and degenerate-segment threshold are left unchanged (not in scope; not user-meaningful tunables).

**Mesh-resolution note:** `makeVertices` currently precomputes the icosphere once. With subdivisions now settings-driven, the mesh must be (re)built for the active subdivision level. The implementer chooses the minimal correct approach (rebuild when the level changes, or build per-call) consistent with the existing structure; `makeVertices` is documented pure/GPU-free, so correctness over micro-optimization — but avoid rebuilding a level-4 mesh every frame if a cheap cache keyed on the level is natural.

## Component 3 — Settings UI

### Files
- `Sources/App/SettingsView.swift`

### Design
Add a `case .wireframe:` to `controls(for:)` returning a new `wireframeControls` view, bound directly to `$model.settings.wireframe*` (top-level field binding, not `bind(_:)`). Layout:
- A group of 6 scalar sliders (base radius, displacement, line thickness, rotation speed, X tilt, line opacity), each with its range above.
- A **"Detail (performance)"** subheading containing the subdivisions control (stepper or slider over 0–4), with a brief note that higher levels cost more CPU per frame (level 4 ≈ 16× today's edge count).

## Component 4 — Reset coverage

### Files
- `Sources/Core/VisualizerSettings.swift` (`resetCurrentStyle()`)

### Design
Add a `.wireframe` branch to `resetCurrentStyle()` that resets the 7 new fields to their defaults when Wireframe is the active style — matching the Polartone/Star Nest reset handling added in the per-style-reset fix. Do not touch shared fields or other styles.

## Testing

All headless (no GPU), through the documented pure `makeVertices` seam and the settings layer:

- **Default parity:** `makeVertices` output at `VisualizerSettings.defaults` is identical to today's output (the critical regression guard — proves the literal→setting substitution is value-preserving, not just syntactic).
- **Per-field behavior:**
  - higher `wireframeSubdivisions` → strictly more emitted vertices/edges; level 0 → base icosahedron count; clamp holds for out-of-range input.
  - `wireframeBaseRadius` scales geometry magnitude; `wireframeDisplaceScale` changes audio-driven displacement; `wireframeLineThickness` changes emitted quad width; `wireframeLineOpacity` flows to vertex color alpha; `wireframeRotationSpeed`/`wireframeTiltX` change orientation deterministically.
- **Codable:** round-trip of all 7 fields; tolerant decode (legacy JSON missing the keys → defaults); explicit persisted values survive decode (new defaults do not override them); `wireframeSubdivisions` decode-clamp to 0–4; Equatable includes the new fields.
- **Reset:** with Wireframe active, mutate the 7 fields then `resetCurrentStyle()` restores defaults; other styles' fields untouched.

## Risks

- **Value-preserving substitution (primary):** at default field values, `makeVertices` output must equal today's exactly — pinned by the default-parity test, verified not assumed.
- **Per-frame mesh rebuild cost:** settings-driven subdivisionsmeans the mesh can no longer be a fixed one-time constant; the implementer must avoid rebuilding a dense mesh every frame where a level-keyed cache is straightforward, while keeping `makeVertices` correct when the level changes at runtime.
