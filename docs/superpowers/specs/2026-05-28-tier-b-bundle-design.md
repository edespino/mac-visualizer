# Tier B Bundle (Plasma + Bumpscope + Kaleidoscope) — Design

- **Date:** 2026-05-28
- **Status:** Approved design (pre-implementation)
- **Audience:** Personal use, single developer
- **Target OS:** macOS 14.4+ (unchanged)

## 1. Goal

Three Tier-B roadmap items bundled into a single branch:

1. **Plasma** — 10th visualizer style. Per-pixel demoscene-classic 2D plasma — `sin(x·f1 + t) + sin(y·f2 + t·1.3) + sin((x+y)·f3 + t·0.7)` mapped to the active palette. Audio modulates `t` advance + an overall energy boost.
2. **Bumpscope** — 11th visualizer style. Per-pixel audio-lit heightfield: each pixel's "height" comes from the frequency band at that pixel's x position; surface normal computed from horizontal neighbors; lit by a fixed light direction.
3. **Kaleidoscope** — post-process applied inside `composite_fs`. N-fold rotational mirror of whatever visualizer is currently active. Configurable 0 (off) / 2–12 folds. Pairs with any of the 11 styles.

Both shader-driven visualizers use new MTLRenderPipelineState objects with custom fragment shaders. Kaleidoscope is a UV transformation inside the existing composite shader.

## 2. Non-goals

- No CPU-grid fallback (decision locked: per-pixel shader, no chunkiness).
- No exposing plasma/bumpscope shader tunables in Settings — both ship with reasonable defaults.
- No interaction with mouse / cursor.
- No new color palettes; the 8 existing palettes feed into the new shaders via uniforms.
- No solid-fill mode for the wireframe (already shipped as wireframe-only).

## 3. Decisions (locked)

| Area | Decision |
| --- | --- |
| Plasma/Bumpscope rendering | **Per-pixel fragment shaders** (no CPU grid). Each visualizer renders a fullscreen triangle through a dedicated MTLRenderPipelineState. |
| Shader inputs | Two uniform buffers: `ShaderInputs { time, energy, bands[16] }` + `PaletteUniform { stops[8], stopCount }`. Both updated per-frame; passed via `setFragmentBytes`. |
| Audio downsampling | Existing `frame.bands` (typically 48 floats) is downsampled to 16 bins by averaging contiguous groups before passing to the shader. `bass` / `mid` / `treble` aggregates not needed — shader can compute them from `bands[16]`. |
| Palette format | Up to 8 stops as `float4`s (RGB + position-in-0..1 in alpha). Most palettes have 3–5; the extra slots are unused (controlled by `stopCount`). |
| Plasma formula | `v = (sin(uv.x·8 + t) + sin(uv.y·6 + t·1.3) + sin((uv.x+uv.y)·5 + t·0.7)) / 3 · 0.5 + 0.5 + energy·0.3`, clamped 0..1; map to palette. |
| Bumpscope formula | Sample heightfield at uv.x → band index → height `h = bands[xi]`. Compute `n = normalize(float3(-(hR - hL) * 0.5, 1, 0))`. Lit by `L = normalize(float3(0.5, 0.7, 0.5))`. Brightness `= max(0, dot(n, L)) · (h · 2 + 0.2)`. Map to palette. |
| Visualizer-style dispatch | New `customShader: ShaderKind?` on `VisualizerStyle`. Renderer routes to shader-fill path when non-nil. |
| Visualizer stub | `PlasmaVisualizer` / `BumpscopeVisualizer` are minimal classes that return `[]` from `makeVertices`. The renderer's shader path uses the frame directly. |
| Bloom / trails / vignette / grain interaction | Shader output fills `sceneTexture` (or `trailTexture` when persistence > 0); existing bloom + composite + post-process apply unchanged. |
| Kaleidoscope placement | UV transformation inside `composite_fs` BEFORE sampling sceneTex / blurTex / trailTex. Applied to the FINAL frame, so it folds whatever visualizer was active. |
| Kaleidoscope range | Setting `kaleidoscopeFolds: Int` (0..12). 0 = off (default), 2..12 = N-fold mirror. Slider on the Tweaks tab. |
| Reset semantics | Reset All Styles resets `kaleidoscopeFolds` to 0 via `.defaults`. Reset This Style doesn't touch it. |

## 4. Architecture

### 4.1 Module-level additions

**`Sources/Core/VisualizerStyle.swift`**:
- Add cases `.plasma`, `.bumpscope` after `.wireframe`. Order: bars, radial, mirrored, oscilloscope, particles, fountain, fireworks, siri, wireframe, plasma, bumpscope.
- New `customShader: ShaderKind?` returns `.plasma`, `.bumpscope`, or `nil`.
- `displayName` adds "Plasma", "Bumpscope".
- `usesRoundParticles` returns `false` for both.
- `makeVisualizer()` returns `PlasmaVisualizer()` / `BumpscopeVisualizer()`.
- Wrap targets: `.bumpscope.next == .bars`, `.bars.previous == .bumpscope`, `.wireframe.next == .plasma`, `.plasma.next == .bumpscope`.

**`Sources/Core/ShaderKind.swift`** (new):

```swift
public enum ShaderKind: String, Codable, CaseIterable {
    case plasma, bumpscope
}
```

**`Sources/Core/PlasmaVisualizer.swift`** (new) — minimal stub:

```swift
public final class PlasmaVisualizer: Visualizer {
    public init() {}
    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        return []   // shader path handles everything; this class exists only to satisfy makeVisualizer()
    }
}
```

**`Sources/Core/BumpscopeVisualizer.swift`** — same shape as `PlasmaVisualizer`.

### 4.2 Renderer additions

**`Sources/Rendering/MetalRenderer.swift`**:
- New private pipeline states: `plasmaPipeline16` (writes to rgba16Float scene/trail texture).
- New uniform struct (Swift mirror):

```swift
private struct ShaderInputs {
    var time: Float = 0
    var energy: Float = 0
    var bands: (Float, Float, Float, Float, Float, Float, Float, Float,
                Float, Float, Float, Float, Float, Float, Float, Float) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

private struct PaletteStopUniform {
    var r: Float = 0
    var g: Float = 0
    var b: Float = 0
    var position: Float = 0
}

private struct PaletteUniform {
    var stops: (PaletteStopUniform, PaletteStopUniform, PaletteStopUniform, PaletteStopUniform,
                PaletteStopUniform, PaletteStopUniform, PaletteStopUniform, PaletteStopUniform) =
        (.init(), .init(), .init(), .init(), .init(), .init(), .init(), .init())
    var stopCount: Int32 = 0
}
```

(Fixed-size tuples used because Metal/Swift struct interop is easiest when the layout is known at compile time.)

- New helper methods:
  - `private func makeShaderInputs(frame: AudioFrame) -> ShaderInputs` — computes time, mean energy, downsamples `frame.bands` to 16 bins.
  - `private func makePaletteUniform(named name: String) -> PaletteUniform` — fills the stops array from the named palette.
  - `private func encodeShaderFill(kind: ShaderKind, frame: AudioFrame, settings: VisualizerSettings, into descriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer)` — draws the fullscreen triangle with the matching pipeline + uniforms.

- Existing `renderBloom` and `renderWithTrails` gain an optional `shaderKind: ShaderKind? = nil` parameter. When set, they substitute the shader-fill call for the existing `encode(...)` geometry step. Both functions also need access to `frame` to build ShaderInputs — pass `frame: AudioFrame` parameter to both.

- `encode()` is **unchanged** for non-shader styles.

### 4.3 New shaders in `Sources/Rendering/Shaders.metal`

**Matching Metal structs** (must match Swift layout):

```metal
struct ShaderInputs {
    float time;
    float energy;
    float bands[16];
};

struct PaletteStopUniform {
    float r, g, b;
    float position;
};

struct PaletteUniform {
    PaletteStopUniform stops[8];
    int stopCount;
};

// Linearly sample the palette at t in [0,1].
static inline float3 samplePalette(constant PaletteUniform &p, float t) {
    t = clamp(t, 0.0, 1.0);
    if (p.stopCount <= 1) return float3(p.stops[0].r, p.stops[0].g, p.stops[0].b);
    // Stops evenly distributed across [0,1] regardless of position alpha (matches Swift ColorPalette.sample).
    float scaled = t * float(p.stopCount - 1);
    int lo = clamp(int(floor(scaled)), 0, p.stopCount - 2);
    int hi = lo + 1;
    float u = scaled - float(lo);
    PaletteStopUniform a = p.stops[lo];
    PaletteStopUniform b = p.stops[hi];
    return float3(a.r + (b.r - a.r) * u,
                  a.g + (b.g - a.g) * u,
                  a.b + (b.b - a.b) * u);
}
```

**`plasma_fs`**:

```metal
fragment float4 plasma_fs(FSQOut in [[stage_in]],
                          constant ShaderInputs &input [[buffer(0)]],
                          constant PaletteUniform &palette [[buffer(1)]]) {
    float2 uv = in.uv * 2.0 - 1.0;     // -1..+1
    float t = input.time;
    float v = sin(uv.x * 8.0 + t)
            + sin(uv.y * 6.0 + t * 1.3)
            + sin((uv.x + uv.y) * 5.0 + t * 0.7);
    v = v / 3.0 * 0.5 + 0.5 + input.energy * 0.3;
    v = clamp(v, 0.0, 1.0);
    float3 col = samplePalette(palette, v);
    return float4(col, 1.0);
}
```

**`bumpscope_fs`**:

```metal
fragment float4 bumpscope_fs(FSQOut in [[stage_in]],
                             constant ShaderInputs &input [[buffer(0)]],
                             constant PaletteUniform &palette [[buffer(1)]]) {
    float u = clamp(in.uv.x, 0.0, 1.0);
    int xi = int(u * 15.0);
    int xL = max(0, xi - 1);
    int xR = min(15, xi + 1);
    float h  = input.bands[xi];
    float hL = input.bands[xL];
    float hR = input.bands[xR];
    float dx = (hR - hL) * 0.5;
    float3 n = normalize(float3(-dx, 1.0, 0.0));
    float3 L = normalize(float3(0.5, 0.7, 0.5));
    float lit = max(0.0, dot(n, L));
    float intensity = lit * (h * 2.0 + 0.2);
    intensity = clamp(intensity, 0.0, 1.0);
    float3 col = samplePalette(palette, intensity);
    return float4(col, 1.0);
}
```

### 4.4 Kaleidoscope inside `composite_fs`

`VisualizerSettings.kaleidoscopeFolds: Int` (default 0, range 0..12). Wired through the standard 7-site pattern.

`CompositeUniforms` (existing struct) gains a `kaleidoscopeFolds: Int32` field. The Swift mirror gets the same field.

In `composite_fs`, BEFORE sampling textures, transform `in.uv`:

```metal
if (u.kaleidoscopeFolds > 0) {
    float2 c = in.uv - 0.5;
    float r = length(c);
    float angle = atan2(c.y, c.x);
    float foldAngle = (2.0 * M_PI_F) / float(u.kaleidoscopeFolds);
    float a = fmod(angle + 2.0 * M_PI_F, foldAngle);
    if (a > foldAngle * 0.5) a = foldAngle - a;
    c = float2(cos(a) * r, sin(a) * r);
    // Re-center, applying a single-fold mirror.
    float2 newUV = c + 0.5;
    // Sampling uses the transformed UV from here on.
    scene = sceneTex.sample(samp, newUV).rgb;
    blur  = blurTex.sample(samp, newUV).rgb;
}
```

Settings UI: new slider on the Tweaks tab in the existing "Post-process" section (under Vignette + Film grain). Range 0..12, integer-stepped. Label "Kaleidoscope" with "Off" / "12-fold" min/max.

### 4.5 Call-site integration

**`Sources/Rendering/MetalView.swift`** — the `draw(in:)` body extends. Compute `shaderKind = style.customShader`. The existing if/elseif/else cascade is extended with the shader case:

```swift
let shaderKind = model.settings.visualizerStyle.customShader
let persistence = model.settings.trailPersistence
if persistence > 0 {
    renderer.renderWithTrails(... shaderKind: shaderKind, frame: frame, ...)
} else if model.settings.glowEnabled {
    renderer.renderBloom(... shaderKind: shaderKind, frame: frame, ...)
} else {
    // For shader visualizers, ALWAYS go through bloom-path (intensity = 0) so
    // we get composite_fs vignette/grain/kaleidoscope. Pure-`encode()` skipped.
    if shaderKind != nil {
        renderer.renderBloom(... intensity: 0, shaderKind: shaderKind, frame: frame, ...)
    } else {
        renderer.encode(vertices: vertices, ...)
    }
}
```

**`RenderProbe.swift`** mirrors the same logic.

### 4.6 Audio sampling pre-pass

`makeShaderInputs(frame:)` downsamples `frame.bands` to 16 bins by averaging contiguous groups:

```swift
private func makeShaderInputs(frame: AudioFrame) -> ShaderInputs {
    var inputs = ShaderInputs()
    inputs.time = Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 1024))
    inputs.energy = frame.rms
    let bandCount = frame.bands.count
    var arr = [Float](repeating: 0, count: 16)
    if bandCount > 0 {
        for i in 0..<16 {
            let lo = (i * bandCount) / 16
            let hi = ((i + 1) * bandCount) / 16
            var sum: Float = 0
            for k in lo..<hi { sum += frame.bands[k] }
            arr[i] = sum / Float(max(hi - lo, 1))
        }
    }
    inputs.bands = (arr[0], arr[1], arr[2], arr[3], arr[4], arr[5], arr[6], arr[7],
                    arr[8], arr[9], arr[10], arr[11], arr[12], arr[13], arr[14], arr[15])
    return inputs
}
```

## 5. Testing strategy

**Unit-tested (Core):**
- `VisualizerStyle.allCases.count == 11`; `.plasma.displayName == "Plasma"`; `.bumpscope.displayName == "Bumpscope"`.
- `.plasma.customShader == .plasma`; `.bumpscope.customShader == .bumpscope`; others return `nil`.
- `.wireframe.next == .plasma`; `.plasma.next == .bumpscope`; `.bumpscope.next == .bars`; `.bars.previous == .bumpscope`.
- `PlasmaVisualizer().makeVertices(...).isEmpty == true`.
- `BumpscopeVisualizer().makeVertices(...).isEmpty == true`.
- `VisualizerSettings.defaults.kaleidoscopeFolds == 0`.
- `kaleidoscopeFolds` round-trips through JSON; defaults to 0 in partial JSON.

**Verified by running:**
- Switch to plasma — full-screen colored plasma effect, modulated by audio.
- Switch to bumpscope — heightfield illuminated as audio energy bumps it.
- Both plasma and bumpscope work with all 8 palettes, glow, trails, vignette, grain (composite_fs applies all post-processes).
- Kaleidoscope slider on Tweaks tab. At 0 = no change. At 6 = sixfold mirror visible. At 12 = denser symmetry.
- Kaleidoscope works on every style (bars, radial, particles, plasma, bumpscope, wireframe, etc.).

## 6. Risks & mitigations

- **Uniform-buffer layout mismatch** — Swift and Metal structs must have identical layout. Fixed-size tuples in Swift give predictable layout; arrays in Metal struct are zero-padded. *Mitigation:* explicit struct mirroring in spec, plus a runtime sanity check via render-probe (any layout mismatch → broken render or kernel panic).
- **palette downsampling artifacts** — Our existing palettes have up to 5 stops; passing 8 with `stopCount` works. *Mitigation:* `samplePalette` reads `stopCount` and only interpolates over the active range.
- **Shader compile failure** — new shaders could fail in Metal compilation. *Mitigation:* `make build` catches it. If the pipeline state is `nil` after init, fall through to a black-screen output via a defensive guard (rather than crashing).
- **Performance of plasma at 4K** — per-pixel sin × 3 + palette sample. ~8 ops/pixel. At 4K = 8M pixels × 60fps × 8 ops = 4 GFLOPS. Apple GPUs handle 1+ TFLOPS easily.
- **Kaleidoscope creates seams at fold boundaries** — slight visual discontinuity where folded segments meet. *Mitigation:* the `fmod` + mirror math is standard; bloom + grain mask most artifacts.

## 7. Out of scope / future
- Per-style tunables for plasma frequencies / bumpscope light angle / kaleidoscope center.
- A "shader playground" — user-loadable Metal fragments. Power-user feature; sandboxing required.
- True 3D bumpscope (perspective + camera).
- Kaleidoscope position offset (currently centered).
- Auto-cycling kaleidoscope folds.
