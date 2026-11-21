# Palette Crossfade for CPU Vertex-Emit Styles — Design

**Date:** 2026-06-29
**Branch:** `polly/palette-fade-cpu`
**Source:** Follow-up to `2026-06-29-palette-auto-cycle-design.md` (deferred scope)

## Goal

Make the palette auto-cycle crossfade **gradual on every visualizer**, not just shader-driven
ones. Today the crossfade is visible only on shader styles; the 15 CPU vertex-emit styles
(including the default `.bars`) bake their colors from `settings.paletteName` inside
`makeVertices` and therefore **hard-cut** to the new palette at fade completion. A user on a
CPU style sees an abrupt switch instead of a gradual blend.

## Root Cause (confirmed, read-only investigation against `main@e5e2818`)

- `PaletteCycleEngine` ramps `mix` 0→1 over multiple frames (correct; tested).
- `RenderModel.effectivePalette()` blends `from`/`to` palettes by `mix` and is consumed by the
  **shader** path (`encodeShaderFill` rebinds the palette uniform every frame) — shader styles
  crossfade correctly.
- CPU vertex-emit visualizers read `ColorPalette.preset(settings.paletteName)` directly inside
  `makeVertices` (`Sources/Core/Visualizer.swift:20-21` passes only `frame`, `settings`,
  `aspect` — no palette). `MetalView.draw` calls `makeVertices` **before** resolving
  `effectivePalette()`, so CPU styles only change when the committed palette *name* changes at
  fade completion → hard cut.

This is a scope limitation of the original feature, not a fade-math regression.

## Architecture

Thread the engine's resolved (possibly blended) palette into CPU vertex emission, so the same
per-frame blended `ColorPalette` that shader styles already receive also colors CPU geometry.

### Component 1 — Protocol signature (`Sources/Core/Visualizer.swift`)

Extend `makeVertices` to receive the resolved palette:

```swift
func makeVertices(frame: AudioFrame,
                  settings: VisualizerSettings,
                  palette: ColorPalette,
                  aspect: Float) -> [BarVertex]
```

`palette` is the **effective** palette for this frame: during a fade it is the blended palette;
otherwise it is exactly `ColorPalette.preset(settings.paletteName)` (resolved with the same
fallback `effectivePalette()` already uses). Every `Visualizer` conformer updates its signature;
the 15 color-emitting CPU visualizers use `palette` in place of their internal
`ColorPalette.preset(settings.paletteName)` lookup. Visualizers that don't emit color from a
palette accept the parameter and ignore it.

### Component 2 — Call-site ordering (`Sources/Rendering/MetalView.swift`)

Resolve `effectivePalette()` **before** `makeVertices`, and pass it in. Today it's resolved
after (`MetalView.swift:91` makeVertices, then `:94/:97` effectivePalette). Reorder so the one
`effectivePalette()` result feeds both CPU vertex emission and the shader uniform path — single
source of truth per frame, no double resolution.

### Component 3 — CPU visualizer color source (15 files)

Each replaces its `let palette = ColorPalette.preset(settings.paletteName)` (or equivalent)
with the injected `palette` parameter. Files (from investigation):
BeatCounter, Fireworks, Heightfield, JoyPlot, LavaLamp, MirroredBars, Oscilloscope, Particle,
Polartone, RadialSpectrum, RibbonWave, SpectrumBars, SpectrumFountain, Voronoi (CPU cells),
Wireframe.

Note: some visualizers resolve the palette in helper paths (e.g. Polartone `:113` and `:254`,
Voronoi `:269`); all internal palette lookups for that visualizer use the injected palette.

## Value-Preservation Invariant (critical)

When auto-cycle is **off** (or not mid-fade), `effectivePalette()` returns exactly
`ColorPalette.preset(settings.paletteName)`. Therefore every CPU visualizer's output must be
**byte-identical** to today at defaults / feature-off. This is the regression guard: the
substitution changes *where* the palette comes from, never *what* it is when not fading.

## Testing

- **Per-visualizer parity:** for representative CPU visualizers, assert `makeVertices(..., palette:
  ColorPalette.preset(settings.paletteName), ...)` produces a **bit-identical** `[BarVertex]`
  array to the pre-change behavior (golden snapshot on a seeded frame). Covers the
  value-preservation invariant.
- **Blend propagation:** assert that passing a deliberately distinct `palette` actually changes
  the emitted vertex colors (proves CPU styles now honor the injected palette).
- **Existing suite:** all current tests must remain green; visualizer test call sites updated to
  pass the palette argument.
- **Ordering:** a `MetalView`-level check is not unit-testable (Rendering isn't unit-tested), so
  correctness of the reorder is covered by build + the per-visualizer parity tests + manual
  visual verification.

## Risks

- **Wide signature change** (~20 conformers + all visualizer test call sites). Mechanical, but
  the compiler enforces completeness — every conformer must update or it won't build.
- **Hidden palette lookups:** a visualizer that resolves a palette somewhere other than the
  obvious `makeVertices` head (helper methods) must route *all* its lookups through the injected
  palette, or it will partially hard-cut. The parity + blend-propagation tests per visualizer
  guard this.
- **Double-resolution / ordering:** ensure `effectivePalette()` is resolved exactly once per
  frame and before vertex emission; the engine advances on the draw thread, so resolving earlier
  in the same `draw` call is safe (no extra advance).

## Out of Scope

- No change to the engine, the fade math, the 6 new palettes, or the shader path (all correct).
- No new user-facing controls.
