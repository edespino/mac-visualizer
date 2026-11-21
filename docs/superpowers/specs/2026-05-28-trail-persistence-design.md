# Trail Persistence — Design

- **Date:** 2026-05-28
- **Status:** Approved design (pre-implementation)
- **Audience:** Personal use, single developer
- **Target OS:** macOS 14.4+ (unchanged)

## 1. Goal

Add an optional "trail persistence" rendering effect that keeps previous frames visible on screen as a fading ghost. When the slider is at 0 (default), behavior is identical to today (each frame clears the framebuffer). As the slider increases toward 1, old frames linger longer — moving particles leave fading streaks, bars show afterimages, the siri wave traces its history, the oscilloscope draws a fading trace.

Single global slider on the existing **Tweaks** Settings tab; trails fade toward the existing soft off-black background color (no accumulation artifacts, no per-style configuration).

## 2. Background / current state

- `MetalRenderer.encode(...)` and `MetalRenderer.renderBloom(...)` are the two render entry points. Both clear the framebuffer each frame (`loadAction = .clear`) and emit the entire visualizer's geometry fresh.
- The bloom pipeline (Plan 7) already maintains a persistent `sceneTexture` and `blurTexture` matching the drawable size; both are recreated when the size changes (`ensureBloomTextures`). The pattern is established for "manage a private texture between frames."
- The renderer's `clearColor(for:)` returns the soft off-black `(0.04, 0.04, 0.06)` introduced in the palettes branch.
- There is currently no concept of frame-to-frame state in the GPU pipeline — every frame is independent.

## 3. Non-goals

- No per-style persistence values (one global slider).
- No selective per-element fade (e.g., "trails only for particles") — applies uniformly to whatever the active visualizer drew.
- No motion-direction-aware blur (just temporal averaging).
- No persistent state mid-resize (the trail texture is cleared on resize; a brief visual flash is acceptable, identical to how the bloom textures recreate).
- No interaction with Demo Mode beyond the natural behavior.

## 4. Decisions (locked)

| Area | Decision |
| --- | --- |
| Control | **Single global slider** `trailPersistence: Float` (0..0.97), top-level on `VisualizerSettings`, default **0** (= off). |
| Fade target | **Soft off-black BG** `(0.04, 0.04, 0.06)` (matches `clearColor`). Trails attenuate toward the BG so they take on its tint as they die. |
| Per-frame math | Two-pass: `trailTex = trailTex * persistence + bg * (1 - persistence)`, then render geometry on top of the faded trail. |
| Range cap | Max value **0.97** (NOT 1.0) so trails always eventually fully fade — a slider at exactly 1.0 would create permanent burn-in. |
| Bloom interaction | Bloom blurs the **trail texture** (not the per-frame scene). Trails get their own glow halo. |
| UI placement | Add a new slider on the existing **Tweaks** tab, in a new "Trails" section. |
| Reset | Reset This Style and Reset All Styles both restore `trailPersistence` to 0 (since it's a top-level value, "Reset All" picks it up automatically). |
| Probe | The render probe is single-frame; trail persistence has no effect on probe output (no previous frame to blend with). Probe PNGs remain comparable to non-trail builds. |
| Resize handling | The trail texture is recreated whenever the drawable size changes (mirrors `ensureBloomTextures`). New texture starts cleared to BG. |

## 5. Architecture

### 5.1 New top-level setting

`VisualizerSettings.trailPersistence: Float` — wired through the existing six places (stored property, init param + body, defaults, CodingKeys, tolerant `init(from:)`, `encode(to:)`). Same pattern as the existing tweak fields.

### 5.2 `MetalRenderer` — persistent trail texture

Add a new private texture alongside `sceneTexture` / `blurTexture`:

```
private var trailTexture: MTLTexture?
```

`ensureBloomTextures(width:height:)` extends to also (re)create `trailTexture` and clear it to the BG color on first allocation. (Cleared via a one-shot render pass that does `loadAction = .clear` to the BG color.)

### 5.3 New render path: `renderWithTrails(...)`

A new method (parallel to `renderBloom(...)`) takes `trailPersistence`, the existing `vertices` + `clearColor` + `intensity`, and the final pass descriptor.

Frame sequence:

1. **Fade pass**: render to `trailTexture` with `loadAction = .load`. Draw a fullscreen quad whose fragment shader outputs `bg * (1 - persistence)`. Use blend equation `dst = dst * persistence + src` so the destination math becomes `trailTexture * persistence + bg * (1 - persistence)`. After this pass, the trail texture is faded toward the BG.

2. **Geometry pass**: render `vertices` to `trailTexture` with `loadAction = .load`, using the existing visualizer pipeline (sharp or round). The new geometry draws on top of the faded trail. After this pass, `trailTexture` contains: faded prior frames + this frame's geometry.

3. **Bloom**: MPS blur `trailTexture` → `blurTexture`. (Unchanged sigma=8.)

4. **Composite**: composite (`trailTexture` + `blurTexture` * intensity) into `finalPass` (the drawable). Existing `compositePipeline` fragment.

When `trailPersistence == 0`, the fade pass clears the trail texture to pure BG each frame (`dst * 0 + bg * 1 = bg`) and step 2 just draws geometry over pure BG — equivalent to today's behavior with a small extra pass overhead.

### 5.4 New fragment shader: `fade_fs`

In `Shaders.metal`:

```
fragment float4 fade_fs(FSQOut in [[stage_in]],
                        constant float4 &fadeRGB [[buffer(0)]]) {
    return fadeRGB;  // output bg * (1 - persistence) — the blend equation handles the rest
}
```

The blend mode is set on the fade pipeline state:
- `rgbBlendOperation = .add`
- `sourceRGBBlendFactor = .one`
- `destinationRGBBlendFactor = persistence` (passed in via the fragment uniform — actually use a fixed `.blendColor` factor with `setBlendColor(...)`).

Implementation detail: Metal supports per-draw blend color via `setBlendColor(_:_:_:_:)`. We set the alpha channel of the blend color to `persistence` and use `destinationRGBBlendFactor = .blendAlpha` so the blend equation evaluates per-frame from the slider value.

### 5.5 `MetalView` / `RenderProbe` — call site

`MetalView.Coordinator.draw(in:)` chooses between `renderBloom` (when glow on) and `encode` (no glow). Add a third path: if `settings.trailPersistence > 0`, use `renderWithTrails` (which handles glow internally). When `trailPersistence == 0` and glow is on → existing `renderBloom`; when both 0 → existing `encode`.

Probe is unaffected — `trailPersistence > 0` on a single-frame render is a no-op visually (the trail texture starts cleared; one frame writes geometry on top of a freshly-cleared texture, identical to the non-trail path).

### 5.6 Settings UI

Add to `tweaksTab` in `SettingsView.swift`, after the existing sections, a new section:

```
Section("Trails") {
    Slider(value: $model.settings.trailPersistence, in: 0...0.97) {
        Text("Persistence")
    } minimumValueLabel: { Text("Off") } maximumValueLabel: { Text("Long") }
}
```

## 6. Testing strategy

**Unit-tested (Core):**
- `VisualizerSettings.defaults.trailPersistence == 0`.
- `trailPersistence` round-trips through JSON.
- `trailPersistence` defaults to 0 in partial-JSON decoding.
- Range clamping NOT enforced at the model layer — the UI Slider provides the 0...0.97 range. Decoded values outside this range pass through (acceptable for a personal app).

**Verified by running:**
- With slider at 0: app behaves identically to today (no visible difference, render probe unchanged).
- With slider at ~0.85: moving siri waves leave a fading swell; bars show afterimages; particles + fireworks have visible streaks.
- With slider at 0.95: long persistent trails; clearly noticeable lag, looks intentional.
- Switching styles with trails on: brief crossfade between styles' content as the trail texture absorbs the new visualizer's frames.
- Window resize: trails clear on resize, no crash, geometry re-stabilizes within a couple of frames.

## 7. Risks & mitigations

- **Texture cost** — one extra full-drawable-size texture (~8 MB at 2560×1440 BGRA8). Same magnitude as `sceneTexture` / `blurTexture`. Acceptable.
- **Bloom + trails together** — strong trails + strong bloom may saturate to white. *Mitigation:* both are user-tunable; the user can dial whichever down. Not a code bug.
- **Burn-in on slider at 1.0** — the cap at 0.97 means the BG term `(1 - 0.97) = 0.03` always nudges the trail toward BG, preventing permanent residue. Verified by the fade equation math.
- **Slider at 0 still does the fade pass** — minor overhead. *Mitigation:* skip the trail path entirely when `trailPersistence == 0` (use existing `renderBloom` or `encode`). One-line check in MetalView/Probe.
- **Resize flash** — clearing the trail texture on resize causes one black frame's worth of "no trails." Acceptable; mirrors bloom texture recreation behavior.

## 8. Out of scope / future
- Per-style trail values (each profile picks its own).
- Motion-direction-aware trails (would require frame-difference analysis).
- Tail color tinting (e.g., trails take on a complementary color rather than BG).
- Persistence preserved across resize (would need texture content migration).
- Frame skip / temporal downsampling for animated GIF capture.
