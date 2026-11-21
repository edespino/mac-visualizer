# Implementation Plan — Palette Crossfade for CPU Vertex-Emit Styles

**Spec:** `docs/superpowers/specs/2026-06-29-palette-crossfade-cpu-styles-design.md`
**Branch:** `polly/palette-fade-cpu`

Discipline: TDD (RED → GREEN), one task at a time, build + full test suite green before moving
on. Value-preservation is the gate: feature-off / not-fading output must be bit-identical.

## Task 0 — Orientation (no code changes)

Read and record the real APIs so nothing is fabricated:
- `Sources/Core/Visualizer.swift` — exact `makeVertices` signature and every conformer.
- `Sources/App/RenderModel.swift` `effectivePalette()` — confirm that when NOT mid-fade it returns
  exactly `ColorPalette.preset(settings.paletteName)` (the value-preservation anchor). Quote it.
- `Sources/Rendering/MetalView.swift` `draw` — current order of `makeVertices` vs
  `effectivePalette()`; identify where to resolve the palette earlier.
- For each of the 15 CPU visualizers, the exact line(s) where it resolves the palette today
  (head of `makeVertices` and any helper paths — Polartone and Voronoi have more than one).
- `Sources/Core/ColorPalette.swift` — `preset(_:)` / `named(_:)` and `blend(_:_:_:)` signatures.

Record golden values: pick 3 representative CPU visualizers (one simple e.g. SpectrumBars, one
stateful e.g. Particles or Fountain, one multi-path e.g. Polartone) and capture their current
`makeVertices` output on a seeded `AudioFrame` so Task 2 can prove bit-identical parity.

## Task 1 — Extend the protocol + call site (RED → GREEN)

1. **RED:** add a test (or temporarily a compile-checked stub) expressing the new signature:
   `makeVertices(frame:settings:palette:aspect:)`. It will fail to compile until conformers update.
2. **GREEN:**
   - Add `palette: ColorPalette` to `Visualizer.makeVertices` in `Sources/Core/Visualizer.swift`.
   - Update **every** conformer's signature (compiler enforces completeness). Non-color or
     shader-only visualizers accept and ignore the param for now.
   - In `Sources/Rendering/MetalView.swift` `draw`, resolve `effectivePalette()` **once, before**
     `makeVertices`, and pass it in. Ensure it's resolved exactly once per frame (no double
     `advance`). The same value continues to feed the shader uniform path unchanged.
   - Update all visualizer test call sites to pass `palette: ColorPalette.preset(settings.paletteName)`.
3. Build + full suite green. At this point behavior is unchanged (every CPU visualizer still uses
   its internal lookup); this task only plumbs the parameter.

## Task 2 — Route the 15 CPU visualizers through the injected palette (RED → GREEN)

For each of the 15 files, replace the internal `ColorPalette.preset(settings.paletteName)` lookup
(and any helper-path lookups) with the injected `palette` parameter.

1. **RED (per representative visualizer):**
   - **Parity test:** `makeVertices(..., palette: ColorPalette.preset(settings.paletteName), ...)`
     must equal the Task-0 golden snapshot **bit-for-bit** (proves feature-off is byte-identical).
   - **Propagation test:** passing a deliberately distinct palette (e.g. `mono` vs `classic`)
     must change the emitted vertex colors (proves the injected palette is actually used).
   Write these for the 3 representatives first (they fail until the substitution is made), then
   add lighter parity/propagation coverage for the remaining 12.
2. **GREEN:** make the substitution in all 15 files. Route **all** palette lookups in each
   visualizer (including helper methods — Polartone `:113`/`:254`, Voronoi `:269`) through the
   injected palette so no path partially hard-cuts.
3. Build + full suite green; all parity tests bit-identical, all propagation tests pass.

STOP-and-report rule: if any parity test reveals a real (non-bit-identical) diff at feature-off,
do **not** "adjust the test" — that means a substitution wasn't value-preserving; report it.

## Task 3 — Verification sweep

- Confirm no remaining `ColorPalette.preset(settings.paletteName)` / `.named(settings.paletteName)`
  lookups inside any CPU visualizer's emission path (grep the worktree; they should now use the
  injected palette). Document the grep result.
- Confirm the shader path and engine are untouched (no diff in `PaletteCycleEngine.swift`,
  `effectivePalette` blend logic, or `Shaders.metal` palette sampling).
- Build + full test suite green; report final test count.

## Definition of Done

- `make build` + `make test` green.
- Feature-off / not-fading: every CPU visualizer bit-identical to pre-change (parity goldens).
- Mid-fade: CPU visualizers emit the blended palette (propagation tests).
- No change to engine, fade math, palettes, controls, or shader path.
- Spec + plan committed on the branch.
