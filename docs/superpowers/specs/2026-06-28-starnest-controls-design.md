# Star Nest Controls — Design

**Date:** 2026-06-28
**Branch:** `polly/starnest-controls`
**Source:** User request — the Star Nest port hardcodes every tunable the original `#define`s exposed; bring them over as user controls. Builds on the prior explore of the current shader-uniform plumbing (`main` @ `8db88b3`): buffer 2 is free for a Star-Nest-specific uniform; Voronoi/LavaLamp already establish the per-style uniform pattern to mirror.

## Goal

Expose Star Nest's hardcoded shader constants as user-tunable settings: 9 visual scalars (zoom, speed, formuparam, tile, stepsize, brightness, darkmatter, distfading, saturation) plus 2 density loop-counts (volsteps, iterations). Each slider sets the **resting value**; the existing audio modulation (`base + audio·k`) continues on top, so Star Nest stays audio-reactive. Defaults equal the current literals, so the look is byte-identical until a control is moved.

This requires a one-time foundational piece — a settings→shader-uniform path for Star Nest — that establishes the pattern Octave Meatballs and Outrun the Rain will reuse later.

## Architecture

Three coordinated changes, all additive:

- **Shader-uniform plumbing**: a `StarNestUniforms` struct (private in `MetalRenderer`) + a matching Metal struct, built by `makeStarNestUniforms(settings:)`, bound at **buffer index 2** in `encodeShaderFill` only when `kind == .starNest`. Mirrors the existing Voronoi/LavaLamp uniform pattern exactly. No change to `ShaderInputs` (buffer 0) or `PaletteUniform` (buffer 1).
- **Settings**: 11 new flat top-level fields on `VisualizerSettings` (Polartone precedent), tolerant Codable + migration.
- **Shader**: each hardcoded `base` literal in the Star Nest fragment function is replaced by the matching `uniforms.<field>`; the existing `+ audio·k` modulation is left untouched. `volsteps`/`iterations` replace the literal loop bounds, clamped to the existing caps.
- **UI**: the active-aware "Star Nest Controls" section gains the 9 scalar sliders plus a "Density (performance)" subgroup for the 2 loop-count sliders.

## Component 1 — Settings fields

### Files
- `Sources/Core/VisualizerSettings.swift`

### Design
Add 11 fields, each `Codable`, each defaulting to the current shader literal so default output is unchanged. Mirror the `polartone*` flat-field precedent exactly (declaration, init param, default, CodingKeys, `decodeIfPresent ?? default`, encode).

| Field | Type | Default | Slider range |
|---|---|---|---|
| `starNestZoom` | Double | 0.78 | 0.3–2.0 |
| `starNestSpeed` | Double | 0.18 | 0.0–1.0 |
| `starNestFormuparam` | Double | 0.53 | 0.4–0.7 |
| `starNestTile` | Double | 0.85 | 0.5–1.2 |
| `starNestStepsize` | Double | 0.105 | 0.02–0.3 |
| `starNestBrightness` | Double | 0.00095 | 0.0002–0.003 |
| `starNestDarkmatter` | Double | 0.34 | 0.0–1.0 |
| `starNestDistfading` | Double | 0.73 | 0.4–1.0 |
| `starNestSaturation` | Double | 0.82 | 0.0–1.0 |
| `starNestVolsteps` | Int | 18 | 1–26 (cap) |
| `starNestIterations` | Int | 13 | 1–16 (cap) |

The density caps (26, 16) are the existing literal loop maxima in `Shaders.metal`; they are NOT raised (user choice A) so worst-case GPU cost is unchanged. Covered by the existing settings round-trip / tolerant-decode / Equatable / flat-JSON-migration tests.

## Component 2 — Shader-uniform plumbing

### Files
- `Sources/Rendering/MetalRenderer.swift` (`StarNestUniforms` struct + `makeStarNestUniforms(settings:)` + bind at buffer 2 in `encodeShaderFill`)
- `Sources/Rendering/Shaders.metal` (matching `StarNestUniforms` struct; Star Nest fragment reads it)

### Design
Mirror the Voronoi/LavaLamp pattern precisely:
- Define a private Swift struct `StarNestUniforms` with the 9 scalars (as `Float`) and 2 counts (as `Int32`), memory-layout-matched to a Metal `struct StarNestUniforms` declared in `Shaders.metal`.
- `makeStarNestUniforms(settings:)` is a pure function mapping each `VisualizerSettings` field to its uniform slot, clamping `volsteps`→1...26 and `iterations`→1...16.
- In `encodeShaderFill`, when `kind == .starNest`, build the uniform and `setFragmentBytes(...)` at buffer index **2** (the slot Voronoi/LavaLamp use for their kinds; free for Star Nest).
- In `Shaders.metal`, the Star Nest fragment function takes the new uniform at `[[buffer(2)]]` and replaces each hardcoded base literal with `u.<field>`; loop bounds use `u.volsteps` / `u.iterations`.

### Reactivity reconciliation (the one real risk)
Each Star Nest scalar is currently `base + audio·k`. The substitution replaces only `base` with `u.<field>` and leaves `+ audio·k` intact. The implementer MUST verify that at default field values the *total* expression reproduces today's behavior exactly (defaults equal the prior literals), so the swap is value-preserving, not merely syntactic.

## Component 3 — Settings UI

### Files
- `Sources/App/SettingsView.swift`

### Design
In the active-aware Polartone-precedent controls switch, the Star Nest case gains:
- 9 scalar `Slider`s with labels and the ranges above;
- a quiet "Density (performance)" subheading grouping the 2 integer sliders (`volsteps` 1–26, `iterations` 1–16), conveying they affect GPU cost.

Defaults render identically to today; only slider movement changes output.

## Testing

Headless, no GPU required:
- **`makeStarNestUniforms(settings:)` mapping** — each field maps to the correct uniform slot.
- **Default parity** — with default settings, every uniform field equals the prior hardcoded literal (the guard that proves the look is unchanged).
- **Density clamps** — `volsteps`/`iterations` clamp to 1...26 / 1...16 (below, within, above).
- **Codable** — round-trip, tolerant decode (missing keys → defaults), Equatable across the 11 fields.
- **Migration** — legacy flat JSON without the new keys decodes to defaults.

The actual shader output cannot be unit-verified (needs the GPU/real audio); final confirmation is a manual run.

## Out of scope
- Raising the density loop caps (user chose to clamp to existing 26/16).
- Per-param "audio amount" sliders (user chose base-only; audio reactivity stays at its current fixed coefficients).
- Octave Meatballs / Outrun the Rain controls — they reuse this uniform pattern in later tasks.
