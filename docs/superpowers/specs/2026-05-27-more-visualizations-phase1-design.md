# More Visualizations — Phase 1: Framework + 3 Styles + Switching — Design

- **Date:** 2026-05-27
- **Status:** Approved design (pre-implementation)
- **Audience:** Personal use, single developer
- **Target OS:** macOS 14.4+ (unchanged)

## 1. Goal

Add multiple selectable visualization styles to the existing spectrum-bars visualizer,
with live switching. Phase 1 adds three new styles that fit the existing flat-triangle
Metal pipeline (no shader changes) plus the switching machinery. Phase 2 (a separate
spec) adds glow/bloom post-processing and a stateful particle field.

After Phase 1 the user can switch — via keyboard, the View menu, or Settings — between:
**Bars** (existing), **Radial spectrum**, **Mirrored bars**, and **Oscilloscope**.

## 2. Background / current state

- `Visualizer` protocol (Core): `func makeVertices(frame: AudioFrame, settings: VisualizerSettings) -> [BarVertex]` — pure, GPU-free, unit-tested. One conformer today: `SpectrumBarsVisualizer`.
- The Metal pipeline draws a flat vertex-colored **triangle list** (`Shaders.metal`); anything expressible as colored triangles in clip space (x,y ∈ [-1,1]) renders with no shader change.
- `AudioFrame` (Core) carries `bands`, `bandPeaks`, `rms`, `peak`, `timestamp` — **no raw waveform**.
- `MetalView.Coordinator` holds a single `SpectrumBarsVisualizer` and calls `makeVertices` each draw; `RenderModel.settings` (`@Published`) is read live by the renderer/overlay; `SettingsView` edits it.
- `VisualizerSettings` is `Codable` with the compiler-synthesized decoder (so adding a field breaks decoding of existing `settings.json`).

## 3. Non-goals (Phase 1)

- Glow/bloom / any post-processing or new shaders (Phase 2).
- The particle field (stateful visualizer) (Phase 2).
- Auto-rotate timer (the user chose keyboard + Settings + View menu only).
- Custom palette colors, background gradient, per-monitor fullscreen (pre-existing deferrals, unchanged).

## 4. Decisions (locked)

| Area | Decision |
| --- | --- |
| New styles | Radial spectrum, Mirrored bars, Oscilloscope |
| Switching | ⌘] / ⌘[ cycle, View-menu list, Settings picker |
| Pipeline | Existing flat-triangle shader, unchanged |
| Protocol | Extend `makeVertices` with an `aspect: Float` parameter |
| Waveform | Add `waveform: [Float]` to `AudioFrame`; analyzer downsamples its window; synthetic source generates one |
| Settings compat | `VisualizerSettings` gets a tolerant `init(from:)` (decode-if-present + defaults) so adding fields never breaks old saved settings |
| Style selection | `VisualizerStyle` enum (`Codable`, `CaseIterable`) with a `makeVisualizer()` factory and `next`/`previous` |

## 5. Architecture

### 5.1 Core (pure, unit-tested)

- **`VisualizerStyle`** — `public enum VisualizerStyle: String, Codable, CaseIterable { case bars, radial, mirrored, oscilloscope }`. Adds:
  - `var displayName: String` (e.g. "Bars", "Radial", "Mirrored", "Oscilloscope").
  - `func makeVisualizer() -> Visualizer` — factory returning the conformer for the case.
  - `var next: VisualizerStyle` / `var previous: VisualizerStyle` — wrap-around cycling over `allCases`.
- **`Visualizer` protocol** — changed to:
  `func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex]`
  where `aspect = viewportWidth / viewportHeight`. Conformers that don't need it ignore it.
- **`SpectrumBarsVisualizer`** — signature updated to accept (and ignore) `aspect`. Behavior unchanged.
- **`RadialSpectrumVisualizer`**, **`MirroredBarsVisualizer`**, **`OscilloscopeVisualizer`** — new conformers (geometry in §6).
- **`AudioFrame`** — gains `public var waveform: [Float]` (downsampled time-domain samples, roughly −1…1). Initializer + `.silent` updated; all construction sites updated.
- **`VisualizerSettings`** — gains `public var visualizerStyle: VisualizerStyle` (default `.bars`) and a hand-written `init(from decoder:)` that `decodeIfPresent`s every field, falling back to the `defaults` value, so older `settings.json` (missing any field) decodes successfully.
- **`SpectrumAnalyzer.append`** — also populate `waveform` by downsampling the current analysis window (2048 samples) to a fixed `waveformPointCount` (256) via striding.
- **`SyntheticFrameSource.frame(at:)`** — also produce a synthetic `waveform` (e.g. a couple of summed sines over the 256 points) so the oscilloscope animates without real audio.

### 5.2 Rendering (app target; verified by probe + run)

- **`MetalView.Coordinator`** — holds the current `VisualizerStyle` + its `Visualizer`; rebuilds the visualizer only when `settings.visualizerStyle` changes. Each draw computes `aspect` from `view.drawableSize` and calls `makeVertices(frame:settings:aspect:)`. (All Phase 1 visualizers are stateless structs, so rebuilding on change is trivial; Phase 2's stateful particle visualizer will reuse this same cache slot.)
- **`RenderProbe`** — gains an optional style argument: `MacVisualizer --render-probe <path> [bars|radial|mirrored|oscilloscope]` (default `bars`), so each style can be rendered offscreen to a PNG for headless visual verification. It passes `aspect = width/height` and, for the oscilloscope, a ramp/synthetic frame with a non-flat `waveform`.

### 5.3 App / UI

- **`RenderModel`** — no structural change beyond `AudioFrame.waveform` flowing through (analyzer already produces it). `currentFrame()`’s synthetic fallback now carries a waveform.
- **Switching commands** (`MacVisualizerApp.swift`):
  - A `CommandMenu("Visualizer")` listing each `VisualizerStyle.allCases` as a button that sets `model.settings.visualizerStyle` (a checkmark/state marks the current one), plus "Next Visualization" (⌘]) and "Previous Visualization" (⌘[) that set `.next`/`.previous`.
- **`SettingsView`** — add a "Visualization" `Section` with a `Picker` bound to `$model.settings.visualizerStyle` over `VisualizerStyle.allCases` (using `displayName`).

## 6. Visualizer geometry (each → `[BarVertex]` triangles in clip space)

All operate on clip space x,y ∈ [−1,1]; `BarVertex` is `{ position: SIMD4<Float> (xy used), color: SIMD4<Float> }`.

### 6.1 RadialSpectrumVisualizer
- For `N = frame.bands.count` bands, band `i` sits at angle `θ = 2π·i/N` (starting at top, going clockwise).
- Each band is a radial bar from inner radius `r0` (e.g. 0.25) outward to `r0 + level·rSpan` (e.g. `rSpan = 0.6`), drawn as a quad of small angular width (two triangles).
- **Aspect correction:** every vertex's x is divided by `aspect` (so a circle stays round on a non-square window).
- Color: radial gradient — inner vertices `palette.sample(at: 0)`, outer vertices `palette.sample(at: level)` (mirrors the bars' bottom→top gradient).
- Invariants for tests: vertex count `== N·6`; all vertices within [−1,1]; with `aspect>1`, the max |x| extent is smaller than the max |y| extent for equal-length bars (roundness); zero-level bars collapse to `r0`.

### 6.2 MirroredBarsVisualizer
- Like bars, but each bar is centered on `y = 0` and spans `y ∈ [−level, +level]` (symmetric top/bottom). One quad per bar (6 vertices).
- x layout reuses `BarLayout` (same as bars). Color by distance from center (palette).
- Invariants: vertex count `== N·6`; geometry symmetric about `y = 0` (for each top vertex there is a mirrored bottom vertex); zero-level bars collapse to the center line.

### 6.3 OscilloscopeVisualizer
- Input: `frame.waveform` (M points). Maps point `j` to `x = −1 + 2·j/(M−1)`, `y = clamp(sample·yScale, −1, 1)` (e.g. `yScale = 0.9`).
- Renders the polyline as `M−1` thin quads (each segment a rectangle of fixed thickness, perpendicular offset), 6 vertices per segment.
- Color: `palette.sample(at: |y|)` per vertex.
- Invariants: vertex count `== (M−1)·6` (M ≥ 2); all vertices within [−1,1]; a silent (all-zero) waveform yields a flat horizontal line at `y ≈ 0`.

## 7. Data flow (unchanged except waveform + style selection)

```
capture/synthetic → SpectrumAnalyzer.append → AudioFrame{bands, bandPeaks, waveform, ...}
                                                      │
settings.visualizerStyle ── selects ──▶ Visualizer.makeVertices(frame, settings, aspect)
                                                      │
                                               MetalRenderer.encode → bars/radial/mirrored/oscilloscope
```

## 8. Testing strategy

- **Unit-tested (pure Core):**
  - `VisualizerStyle`: `next`/`previous` wrap-around; `makeVisualizer()` returns a conformer for each case; `displayName` non-empty.
  - `RadialSpectrumVisualizer` / `MirroredBarsVisualizer` / `OscilloscopeVisualizer`: the geometry invariants in §6.
  - `AudioFrame.waveform` round-trips through the initializer; `SpectrumAnalyzer.append` emits a `waveform` of length 256; `SyntheticFrameSource` produces a non-empty waveform that animates.
  - `VisualizerSettings`: a JSON missing `visualizerStyle` (and missing other newer fields) decodes to the defaults for those fields (tolerant decoder), while present fields are preserved.
  - `SpectrumBarsVisualizer`: existing tests updated for the new `aspect:` parameter (behavior unchanged).
- **Verified by running / probe:**
  - `--render-probe <path> radial|mirrored|oscilloscope` writes a PNG showing the expected shape (round radial burst; symmetric mirrored bars; a wiggling line) — inspected via the Read tool.
  - Live: ⌘]/⌘[ and the View-menu/Settings picker switch the visualizer instantly while audio plays; each style reacts to music.

## 9. Risks & mitigations

- **Protocol change ripples** (`makeVertices` gains `aspect`): touches `SpectrumBarsVisualizer`, its tests, `MetalView`, `RenderProbe`. *Mitigation:* mechanical; the compiler flags every call site.
- **`AudioFrame` initializer change** (adds `waveform`): touches `.silent`, the analyzer, the synthetic source, and tests that build frames directly. *Mitigation:* compiler flags all sites; the set is small and known.
- **Settings backward-compat:** adding `visualizerStyle` would reset saved settings without the tolerant decoder. *Mitigation:* the hand-written `init(from:)` with `decodeIfPresent` defaults (tested) — also future-proofs further settings additions.
- **Radial roundness on resize:** wrong aspect handling makes the circle an ellipse. *Mitigation:* aspect passed per-draw from `drawableSize`; unit test asserts the x-extent shrinks relative to y when `aspect>1`.

## 10. Handoff to Phase 2

Phase 2 (separate spec) adds: a bloom/glow post-processing pipeline (offscreen render target → bright-pass → gaussian blur → additive composite; new shaders, multi-pass) applied to all styles, and a stateful `ParticleVisualizer` (particles persisting/moving frame-to-frame, reusing the Coordinator's visualizer cache slot). The `aspect` parameter added here is also what the particle field needs to stay proportional.
