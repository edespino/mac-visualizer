# Polish Bundle (HDR palettes + FFT windows + vignette/grain) — Design

- **Date:** 2026-05-28
- **Status:** Approved design (pre-implementation)
- **Scope:** Three independent polish items shipped together as a small low-risk branch. Each is incremental; none touches the core pipeline architecture.

## 1. Goal

Three small improvements bundled into one branch:

1. **HDR-boosted warm palettes** — push the brightest stops on `inferno`, `ember`, and `aurora` above RGB 1.0 so the existing bloom pass produces a true highlight blowout on bright peaks. More dynamic-range feel without changing the rest of the pipeline.

2. **FFT window function selector** — replace the implicit rectangular window in `SpectrumAnalyzer` with selectable Hann (default), Hamming, Blackman, or Rectangular. Cleaner spectrum (less leakage between bins), exposed as a Picker on the Audio Settings tab.

3. **Vignette + film-grain post-process** — two new tunable sliders on the Tweaks tab: a corner-darkening vignette (0..1) and a per-frame noise overlay (0..1). Both default to 0 (off). Applied inside the existing composite shader so they layer over every visualizer.

## 2. Non-goals

- No new visualizer styles (that's Tier A2, separate branch).
- No new color palettes (HDR upgrade is in-place on the existing 3 warm palettes; the other 5 are untouched).
- No new tab in Settings — fold the new controls into existing tabs.
- No interaction with bloom intensity or trail persistence beyond the natural visual stacking.

## 3. Decisions (locked)

| Area | Decision |
| --- | --- |
| HDR scope | **Upgrade in place** on `inferno`, `ember`, `aurora`. Top stops pushed to RGB values >1 (typical ~2.5–4× the original). The other 5 palettes (classic, phosphor, synthwave, ice, mono) stay at 0..1. |
| Window default | **Hann** (cleanest spectrum, most common in audio analysis). Other options: Rectangular, Hamming, Blackman. |
| Window placement | Picker on the existing **Audio** tab, above the existing Gain slider. |
| Vignette + grain default | **Both 0 (off)** by default. Conservative — no visual change for users until they opt in. |
| Vignette/grain placement | Two sliders in a new **"Post-process"** section on the existing **Tweaks** tab, below the existing Trails section. |
| Grain animation | Animated (per-frame deterministic noise) so it looks like film grain, not a static texture. Same RNG seed every frame, but offset by `frame.timestamp` → noise pattern shifts. |
| Reset semantics | "Reset This Style" doesn't touch any of these (all top-level on `VisualizerSettings`, like the existing tweaks). "Reset All Styles" picks them up via `settings = .defaults`. |

## 4. Architecture

### 4.1 HDR-boosted palette stops

`Sources/Core/ColorPalette.swift` — modify the three target palette presets:

```
"inferno": ColorPalette(stops: [
    RGBAColor(r: 0.05, g: 0.0, b: 0.05, a: 1),
    RGBAColor(r: 0.6,  g: 0.0, b: 0.0,  a: 1),
    RGBAColor(r: 1.0,  g: 0.4, b: 0.0,  a: 1),
    RGBAColor(r: 1.8,  g: 1.4, b: 0.3,  a: 1),    // was 1.0/0.85/0.2
    RGBAColor(r: 3.0,  g: 2.5, b: 1.5,  a: 1)     // was 1.0/1.0/0.92 — full HDR top
]),
"aurora": ColorPalette(stops: [
    RGBAColor(r: 0.02, g: 0.05, b: 0.12, a: 1),
    RGBAColor(r: 0.0,  g: 0.55, b: 0.55, a: 1),
    RGBAColor(r: 0.15, g: 0.95, b: 0.6,  a: 1),
    RGBAColor(r: 0.65, g: 0.5,  b: 1.4,  a: 1),    // boosted from 0.45/0.35/0.95
    RGBAColor(r: 1.7,  g: 1.1,  b: 2.4,  a: 1)     // boosted from 0.85/0.55/1.0
]),
"ember": ColorPalette(stops: [
    RGBAColor(r: 0.02, g: 0.0,  b: 0.0,  a: 1),
    RGBAColor(r: 0.62, g: 0.27, b: 0.20, a: 1),
    RGBAColor(r: 1.0,  g: 0.49, b: 0.38, a: 1),
    RGBAColor(r: 1.7,  g: 1.4,  b: 0.9,  a: 1),    // boosted from 1.0/0.83/0.55
    RGBAColor(r: 2.5,  g: 2.2,  b: 1.5,  a: 1)     // boosted from 1.0/0.93/0.78
])
```

Drawable is `bgra8Unorm` (clamps to 0..1 on final write), so over-1 RGB values get **clamped at output**, but they flow through the bloom + composite math at full magnitude. The Gaussian blur (MPSImageGaussianBlur) on the scene texture receives the over-1 brightness; the composite (`scene + blur * intensity`) sees full additive contribution; only the final write to the drawable clamps. Bright peaks (top of the palette) end up with a more substantial halo than dim peaks of the same on-screen pixel value.

**Concern check:** the trail texture is now `rgba16Float` (Plan 12) so HDR values flow through trails too — bright trails get hot bloom. Good interaction.

The 8-bit-output sceneTexture in the bloom path clamps at write, so HDR values get truncated before blur in that path. To get full HDR benefit, the bloom path would need to switch sceneTexture to rgba16Float too — but that's a larger refactor. **Accept truncation in the bloom path for v1**; trail path gets full HDR. (Spec note for future cleanup: CC item in roadmap.)

### 4.2 FFT window function selector

`Sources/Core/SpectrumAnalyzer.swift` — currently applies an implicit rectangular window. Add a window buffer that gets multiplied into the time-domain samples before the FFT:

```
public enum FFTWindow: String, Codable, CaseIterable {
    case rectangular, hann, hamming, blackman

    public var displayName: String {
        switch self {
        case .rectangular: return "Rectangular"
        case .hann: return "Hann"
        case .hamming: return "Hamming"
        case .blackman: return "Blackman"
        }
    }
}
```

In `SpectrumAnalyzer`:
- Add `private var window: [Float]` matching `fftSize`.
- Add `private var currentWindowKind: FFTWindow = .hann`.
- Compute window coefficients on init and on change.
- In the time→frequency step, multiply input by `window` element-wise before vDSP FFT.
- Add `func setWindow(_ kind: FFTWindow)` that recomputes the buffer.

Window math:
- **Rectangular:** `w[i] = 1.0`
- **Hann:** `w[i] = 0.5 * (1 - cos(2π·i / (N-1)))`
- **Hamming:** `w[i] = 0.54 - 0.46 * cos(2π·i / (N-1))`
- **Blackman:** `w[i] = 0.42 - 0.5 * cos(2π·i / (N-1)) + 0.08 * cos(4π·i / (N-1))`

`VisualizerSettings`:
- Add `fftWindow: FFTWindow` top-level (default `.hann`).
- Tolerant codec (decodeIfPresent + default fallback).

`RenderModel.applyLive(_:)`:
- Add `self.analyzer.setWindow(s.fftWindow)` (DSP-queue-confined like the existing `analyzer.update`).

`SettingsView.swift`:
- Add a Picker to the Audio tab above the Gain slider:
  ```
  Picker("FFT window", selection: $model.settings.fftWindow) {
      ForEach(FFTWindow.allCases, id: \.self) { Text($0.displayName).tag($0) }
  }
  ```

### 4.3 Vignette + film grain post-process

Modify `composite_fs` in `Sources/Rendering/Shaders.metal` to apply vignette + grain after the scene+blur composite. Both effects layer on top before the drawable write.

Math:
- **Vignette:** `vignetteFactor = 1 - vignetteAmount * smoothstep(0.55, 1.1, length(uv*2 - 1))`. Multiplies output RGB. At uv center (0.5, 0.5), `length = 0`, factor = 1 (no darkening). At corners (uv ≈ (0,0) or (1,1)), `length ≈ √2 ≈ 1.41`, factor → 1 - vignetteAmount. With amount=1, corners are pure black.
- **Grain:** `noise = (hash(uv, time) - 0.5) * grainAmount`. Add to RGB. Time-varied so the noise shifts per frame.

Pass uniforms via setFragmentBytes:
```
struct CompositeUniforms {
    float intensity;        // bloom intensity (existing)
    float vignetteAmount;   // 0..1
    float grainAmount;      // 0..1
    float time;             // CACurrentMediaTime() mod 1024 for stable precision
};
```

`composite_fs` updated to read all 4. The fragment hash function `hash(uv, time) -> float` uses the existing murmur-style constants from the round-particle shader. ~20 lines added to the shader file.

`VisualizerSettings`:
- Add `vignetteAmount: Float` (default 0).
- Add `grainAmount: Float` (default 0).
- Tolerant codec.

`MetalRenderer`:
- In every place where `compositePipeline` is encoded, replace the single-float `setFragmentBytes(&i, ...)` with a `CompositeUniforms` struct write.
- Three composite sites: `renderBloom`, `renderWithTrails`'s glow branch, `renderWithTrails`'s no-glow branch.

`SettingsView.swift`:
- Add a new Section "Post-process" on the Tweaks tab, below the existing Trails section, with two sliders for vignette (0..1) and grain (0..1).

### 4.4 Test plan

Unit tests:
- `VisualizerSettings.defaults` has `fftWindow == .hann`, `vignetteAmount == 0`, `grainAmount == 0`.
- All three round-trip through JSON.
- All three default from partial JSON.
- `FFTWindow.allCases` has 4 entries; each `displayName` is non-empty.

No automated tests for HDR palette stops (the values are just numerical constants). No automated tests for the shader changes (visual).

Verified by running:
- Switch palette to inferno + max bloom on fireworks during a loud track. The brightest particles should produce a clearly bigger halo than before — hot spots.
- Switch FFT window from Rectangular to Hann. Bars should look slightly cleaner / smoother at transition between adjacent bands. Subtle but visible on sustained tones.
- Drag vignette to 0.5. Corners darken; center unchanged.
- Drag grain to 0.3. Film-grain noise appears, animated per frame.

## 5. Risks & mitigations

- **HDR clamping in bloom path** — sceneTexture is bgra8Unorm, so over-1 colors clamp at scene-write time, before the blur. Bloom halo from HDR values is therefore truncated in the glow-on path. Trail path is unaffected (rgba16Float). *Mitigation:* document; future work can switch sceneTexture to rgba16Float for full HDR through bloom (cross-cutting roadmap item).
- **FFT window switch could glitch** — switching the window mid-stream changes the buffer that's multiplied into samples. If done on the wrong queue, could race with the FFT loop. *Mitigation:* `setWindow` is called from the DSP queue via `applyLive`, same as existing analyzer updates.
- **Grain may look bad with trails on** — animated noise + persistence could create a "speckled stained-glass" look. *Mitigation:* grain is applied AFTER the trail composite (in `composite_fs`), so it doesn't accumulate. Each frame's grain is fresh.
- **HDR may oversaturate with high bloom intensity** — glow intensity 1.5 × HDR-3.0 stops → blow out the entire screen. *Mitigation:* the user has both sliders; can dial whichever down. Not a code bug.
- **Vignette darkening may interact with trails fade target** — trail fades to BG, then vignette darkens the corners further. Visually consistent (corners just go darker than BG); acceptable.

## 6. Out of scope / future
- HDR support in the bloom path's sceneTexture (currently bgra8Unorm; would need rgba16Float).
- Window-function per-style (currently global; could be per-style).
- Grain spatial frequency control (currently fixed per-pixel; could add a "grain size" slider).
- Vignette color tinting (currently darkens to black; could darken to a tinted color).
- Chromatic aberration / scanlines / other CRT/film looks.
