# More Visualizations — Phase 2: Glow/Bloom + Particle Field — Design

- **Date:** 2026-05-27
- **Status:** Approved design (pre-implementation)
- **Audience:** Personal use, single developer
- **Target OS:** macOS 14.4+ (unchanged)

## 1. Goal

Two enhancements that make the visualizer dramatically more compelling:

1. **Glow/bloom** — a neon post-processing pass applied to whatever visualizer is
   active (bars, radial, mirrored, oscilloscope, particles), with an on/off toggle and
   an intensity slider.
2. **Bass-reactive starfield** — a new `particles` visualizer style: a field of drifting
   particles that pulse brighter/larger and surge outward on bass beats.

Implemented as **two plans**: Plan 7 (bloom) lands first and benefits all styles; Plan 8
(particles) builds on the now-glowing pipeline.

## 2. Background / current state

- `MetalView.Coordinator.draw` renders the active visualizer's `[BarVertex]` in a **single
  pass** straight to the `MTKView` drawable via `MetalRenderer.encode(vertices:clearColor:into:commandBuffer:)`.
- `Shaders.metal` has one pipeline: `vs_main` (passthrough vertex-colored triangles) + `fs_main` (flat color).
- `Visualizer` protocol: `func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex]`. Conformers so far are stateless structs. The Coordinator **caches** the visualizer instance and rebuilds it only when `settings.visualizerStyle` changes (Phase 1, Task 9) — so a stateful conformer's state persists across frames.
- `VisualizerStyle` (Codable, CaseIterable): `bars, radial, mirrored, oscilloscope`. `makeVisualizer()` factory; `next`/`previous`; drives the menu/keyboard/Settings switching.
- `AudioFrame` carries `bands`, `bandPeaks`, `waveform`, `rms`, `peak`, `timestamp`.
- `VisualizerSettings` is Codable with a **tolerant decoder** (decode-if-present + defaults), so adding fields never breaks existing `settings.json`. `SettingsView` is a SwiftUI `Form`. `RenderProbe` renders a chosen style offscreen to a PNG (`--render-probe <path> [style]`).
- `MetalRenderer` already pools a vertex buffer; one renderer instance per consumer (live view, probe).

## 3. Non-goals

- No bright-pass/threshold bloom step (our content is bright-on-black; blur-and-add suffices).
- No additional particle behaviors beyond the bass-reactive starfield (one new style).
- No HDR/tone-mapping; bloom composites in the existing sRGB bgra8 pipeline.
- No auto-rotate (unchanged from Phase 1).

## 4. Decisions (locked)

| Area | Decision |
| --- | --- |
| Bloom method | Blur-and-add (no threshold): scene → blur (separable Gaussian, reduced res) → composite `scene + blur × intensity` |
| Bloom control | `glowEnabled` toggle (default on) + `glowIntensity` slider |
| Glow off | Keep the current single-pass-to-drawable path (no offscreen overhead) |
| Particles | New `particles` `VisualizerStyle`; a stateful **class** `ParticleVisualizer` conforming to `Visualizer` |
| Particle behavior | Bass-reactive starfield: drift + bass-triggered brightness/size pulse and outward surge |
| Particle state | Persists via the Coordinator's cached-visualizer slot; deterministic seed for testability |
| Plans | Plan 7 = bloom; Plan 8 = particles |

## 5. Architecture — Plan 7: Bloom

### 5.1 Shaders (`Shaders.metal`, additions)
- A **fullscreen** vertex shader (`fsq_vertex`) that emits a full-screen triangle with UVs (no vertex buffer; uses `vertex_id`).
- **`blur_fragment`** — separable Gaussian: samples the input texture along a direction uniform (horizontal or vertical) with a small fixed kernel (e.g. 9 taps), reading a `texelSize`/`direction` from a small uniforms buffer.
- **`composite_fragment`** — samples the scene texture and the blurred texture, returns `scene + blur × intensity` (intensity from a uniforms buffer).
- The existing `vs_main`/`fs_main` (geometry) are unchanged.

### 5.2 `MetalRenderer` (bloom path)
- Builds three additional pipeline states: blur and composite (plus the existing geometry pipeline). The geometry pipeline must be able to render into an offscreen texture (same `bgra8Unorm` format).
- Owns offscreen textures sized to the drawable: `sceneTexture` (full res, render target + shader read) and two reduced-res (½ or ¼) ping-pong textures `blurA`/`blurB`. A `resize(width:height:)` recreates them when the drawable size changes (compare cached size).
- New method, roughly: `renderBloom(vertices:clearColor:intensity:drawable:drawableSize:commandBuffer:)`:
  1. Geometry pass: clear + draw `vertices` into `sceneTexture`.
  2. Horizontal blur pass: fullscreen draw sampling `sceneTexture` → `blurA` (at reduced res).
  3. Vertical blur pass: fullscreen draw sampling `blurA` → `blurB`.
  4. Composite pass: fullscreen draw sampling `sceneTexture` + `blurB` (× intensity) → the drawable.
- The existing `encode(...)` single-pass path stays for when glow is off.

### 5.3 `MetalView` / `RenderModel` / Settings
- `MetalView.Coordinator.draw`: if `model.settings.glowEnabled`, call the bloom path with `model.settings.glowIntensity`; else the current single-pass path. Texture (re)allocation keyed on `view.drawableSize`.
- `VisualizerSettings` gains `glowEnabled: Bool` (default `true`) and `glowIntensity: Float` (default `0.6`), both added to the tolerant decoder/encoder + memberwise init/defaults.
- `SettingsView` gains a "Glow" section: a toggle and an intensity `Slider` (e.g. 0…1.5).
- `RenderProbe`: render with bloom applied (so the PNG shows the glow). Simplest: the probe always applies bloom at a fixed intensity (e.g. 0.8) after drawing the style, writing the composited result to its offscreen output. This verifies the full bloom pipeline headlessly.

### 5.4 Testing (Plan 7)
- Bloom is GPU/visual → verified by the probe PNG (a visibly glowing version of a style: bright cores with soft halos) and live confirmation; the toggle/intensity wiring is build- + live-verified.
- `VisualizerSettings`: a test that `glowEnabled`/`glowIntensity` round-trip and that a JSON missing them decodes to the defaults (extends the existing tolerant-decoder test).

## 6. Architecture — Plan 8: Particle field

### 6.1 `ParticleVisualizer` (Core, stateful class)
- `public final class ParticleVisualizer: Visualizer`. Holds a fixed-size `[Particle]` where `Particle = { position: SIMD2<Float>, velocity: SIMD2<Float>, size: Float, brightness: Float, colorPos: Float }`. `colorPos` (0…1) is assigned deterministically at init (e.g. from the particle index) and selects the particle's palette color.
- Initialized deterministically (a seeded PRNG or a fixed pseudo-random layout) so output is reproducible for tests.
- `makeVertices(frame:settings:aspect:)`:
  1. Compute `dt` from `frame.timestamp` minus the stored previous timestamp (clamped to a sane range; first call `dt = 0`).
  2. Compute **bass** = average of the lowest ~15% of `frame.bands` (fallback to `rms` if bands empty).
  3. Advance each particle: `position += velocity × dt`; apply gentle drift; decay `brightness`/`size` toward a baseline. When `bass` exceeds a threshold, add an outward velocity impulse (away from center) and bump `brightness`/`size` proportionally to bass.
  4. Wrap or respawn particles that leave the visible region (deterministic respawn).
  5. Emit each particle as a small **aspect-corrected** quad (so dots are round-ish, not stretched), 6 vertices, colored `palette.sample(at: particle.colorPos) × particle.brightness`.
- Particle count is fixed (e.g. 200), so vertex count is bounded (`count × 6`).

### 6.2 `VisualizerStyle` + switching
- Add `case particles`; `makeVisualizer()` returns `ParticleVisualizer()`; `displayName` = "Particles". `allCases` becomes 5; `next`/`previous`, the Visualizer menu, and the Settings picker include it automatically.
- The Coordinator's cached-visualizer slot keeps the single `ParticleVisualizer` instance alive across frames, so its state persists (a fresh instance is created only when switching to `.particles`).

### 6.3 Testing (Plan 8)
- Deterministic unit tests on `ParticleVisualizer`: vertex count == `particleCount × 6`; all vertices within clip space (with a small margin); after several `makeVertices` calls fed a **bass-heavy** frame, total brightness/size (e.g. sum of vertex alpha or quad area) is **greater** than the same number of calls fed a **silent** frame (bass response); deterministic — two instances given identical call sequences produce identical output.
- `VisualizerStyleTests` updated for the 5th case (allCases, next/previous wrap including `.particles`).
- Live: switching to Particles shows a glowing star field that pulses/surges on bass.

## 7. Data flow

```
AudioFrame{bands, rms, waveform, timestamp}
        │
settings.visualizerStyle → Visualizer.makeVertices(frame, settings, aspect)   [bars/radial/.../particles]
        │  [BarVertex]
        ▼
MetalView.draw:
   glowEnabled ? MetalRenderer.renderBloom(vertices, intensity, → drawable)
               : MetalRenderer.encode(vertices, → drawable)   [existing single pass]
```

## 8. Risks & mitigations

- **Multi-pass Metal restructuring is the riskiest part** (offscreen textures, fullscreen passes, sampling, pipeline states). *Mitigation:* research the exact Metal patterns before writing Plan 7 code; keep the single-pass path intact for glow-off; verify via the probe PNG before live.
- **Texture lifecycle on resize / fullscreen** (drawable size changes). *Mitigation:* recreate offscreen textures when the cached size differs; guard zero sizes.
- **Particle protocol statefulness** (the only stateful `Visualizer`). *Mitigation:* the Coordinator already caches the instance; deterministic seeding keeps it testable; `dt` derived from `frame.timestamp` (not wall-clock inside the pure-ish method).
- **Factory equality test with a stateful visualizer.** *Mitigation:* keep `ParticleVisualizer` deterministic so a fresh instance's first call is reproducible; test particle behavior separately from the strict factory-equality check if needed.
- **Performance** (bloom multi-pass at 60–120 fps). *Mitigation:* blur at reduced resolution; the pooled buffers/textures are reused; glow-off path has zero extra cost.

## 9. Out of scope / future
- Threshold/bright-pass bloom, multiple blur levels (mip bloom), HDR.
- Additional particle behaviors (fountain, fireworks) — the architecture (a stateful `Visualizer` + a `VisualizerStyle` case) makes adding more later straightforward.
- Custom palette colors, background gradient, per-monitor fullscreen (pre-existing deferrals).
