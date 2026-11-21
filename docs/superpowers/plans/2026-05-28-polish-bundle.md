# Polish Bundle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three independent polish items shipped on one branch: HDR-boosted warm palettes (inferno/ember/aurora), FFT window selector (rectangular/hann/hamming/blackman), and vignette + animated film-grain post-process applied in `composite_fs`.

**Architecture:** All three changes are additive layered improvements that ride on existing infrastructure. HDR palettes are pure constant tweaks in `ColorPalette.swift`. Window selection extends the existing `makeHannWindow` factory pattern into a 4-way switch, with the active kind plumbed through `VisualizerSettings` → `RenderModel.applyLive` → `SpectrumAnalyzer.setWindow`. Vignette + grain extend the existing `composite_fs` fragment shader with new uniforms, fed from a new `CompositeUniforms` struct written via `setFragmentBytes` at the three existing composite sites.

**Tech Stack:** Swift, Accelerate (vDSP window functions), Metal (composite_fs shader updates), XCTest.

**Builds on:** `main` after merging `plan-12-trail-persistence`. Spec: `docs/superpowers/specs/2026-05-28-polish-bundle-design.md`.

**Scope boundary:** No new visualizer styles, no new palettes, no new Settings tabs, no rendering pipeline restructuring. Three localized changes bundled because each is too small to merit its own branch.

---

## File Structure

```
mac-visualizer/
  Sources/
    Core/
      ColorPalette.swift              # MODIFY: HDR-boost inferno / ember / aurora stops
      VisualizerSettings.swift        # MODIFY: add fftWindow / vignetteAmount / grainAmount fields
      HannWindow.swift                # MODIFY (or RENAME): add hamming/blackman/rectangular factories
      SpectrumAnalyzer.swift          # MODIFY: take FFTWindow kind; setWindow() entry point
    App/
      RenderModel.swift               # MODIFY: forward settings.fftWindow into analyzer
      SettingsView.swift              # MODIFY: FFT window Picker on Audio tab + Post-process sliders on Tweaks tab
    Rendering/
      MetalRenderer.swift             # MODIFY: replace 3 single-float composite uniform writes with CompositeUniforms struct
      Shaders.metal                   # MODIFY: composite_fs reads CompositeUniforms; applies vignette + grain
  Tests/
    CoreTests/
      ColorPaletteTests.swift         # MODIFY: test inferno HDR top
      VisualizerSettingsTests.swift   # MODIFY: tests for fftWindow / vignetteAmount / grainAmount
      SpectrumAnalyzerTests.swift     # MODIFY (if exists): no new tests strictly required; window is plumbing
```

Test count: 144 → ~152 (+1 HDR + ~4 FFT + ~3 post-process).

---

## Task 1: HDR-boost warm palette stops

Push the brightest stops on `inferno`, `ember`, and `aurora` above RGB 1.0 so the existing bloom pass produces a true highlight blowout. Other palettes untouched.

**Files:**
- Modify: `Sources/Core/ColorPalette.swift`
- Modify: `Tests/CoreTests/ColorPaletteTests.swift`

- [ ] **Step 1: Write the failing test.** Append to `ColorPaletteTests`:

```swift
    func testWarmPalettesHaveHDRTopStop() {
        // The HDR-upgraded warm palettes have at least one component > 1
        // at the top stop (used by the bloom pass to produce highlight blowout).
        for name in ["inferno", "ember", "aurora"] {
            let p = ColorPalette.preset(named: name)!
            let top = p.stops.last!
            let maxComponent = max(top.r, max(top.g, top.b))
            XCTAssertGreaterThan(maxComponent, 1.0,
                                 "\(name) top stop should have an HDR component > 1.0, got max=\(maxComponent)")
        }
    }
```

- [ ] **Step 2: Run `make test`** — expect FAIL (`inferno top stop` max ≈ 1.0).

- [ ] **Step 3: Update the three palette stop tables in `Sources/Core/ColorPalette.swift`.** Find the existing definitions and replace:

```swift
        "inferno": ColorPalette(stops: [
            RGBAColor(r: 0.05, g: 0.0, b: 0.05, a: 1),
            RGBAColor(r: 0.6,  g: 0.0, b: 0.0,  a: 1),
            RGBAColor(r: 1.0,  g: 0.4, b: 0.0,  a: 1),
            RGBAColor(r: 1.8,  g: 1.4, b: 0.3,  a: 1),
            RGBAColor(r: 3.0,  g: 2.5, b: 1.5,  a: 1)
        ]),
        "aurora": ColorPalette(stops: [
            RGBAColor(r: 0.02, g: 0.05, b: 0.12, a: 1),
            RGBAColor(r: 0.0,  g: 0.55, b: 0.55, a: 1),
            RGBAColor(r: 0.15, g: 0.95, b: 0.6,  a: 1),
            RGBAColor(r: 0.65, g: 0.5,  b: 1.4,  a: 1),
            RGBAColor(r: 1.7,  g: 1.1,  b: 2.4,  a: 1)
        ]),
        "ember": ColorPalette(stops: [
            RGBAColor(r: 0.02, g: 0.0,  b: 0.0,  a: 1),
            RGBAColor(r: 0.62, g: 0.27, b: 0.20, a: 1),
            RGBAColor(r: 1.0,  g: 0.49, b: 0.38, a: 1),
            RGBAColor(r: 1.7,  g: 1.4,  b: 0.9,  a: 1),
            RGBAColor(r: 2.5,  g: 2.2,  b: 1.5,  a: 1)
        ]),
```

(Leave `classic`, `phosphor`, `synthwave`, `ice`, `mono` exactly as they were.)

- [ ] **Step 4: Run `make test`** — expect `** TEST SUCCEEDED **`, 145 tests passing (144 + 1).

- [ ] **Step 5: Run `make build`** — expect `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/ColorPalette.swift Tests/CoreTests/ColorPaletteTests.swift
git commit -m "Palettes: HDR-boost inferno / ember / aurora top stops for bloom blowout"
```

---

## Task 2: FFT window selector

Make the windowing function configurable (`rectangular | hann | hamming | blackman`). Default stays Hann (current behavior). Plumb the selection through `VisualizerSettings` → `RenderModel.applyLive` → `SpectrumAnalyzer.setWindow`. Add a Picker on the Audio Settings tab.

**Files:**
- Modify: `Sources/Core/HannWindow.swift` (renamed conceptually — add other factories alongside the existing one; keep file name for git friendliness)
- Modify: `Sources/Core/SpectrumAnalyzer.swift`
- Modify: `Sources/Core/VisualizerSettings.swift`
- Modify: `Sources/App/RenderModel.swift`
- Modify: `Sources/App/SettingsView.swift`
- Modify: `Tests/CoreTests/VisualizerSettingsTests.swift`

### Subtask 2a: Add the FFTWindow enum + factories

- [ ] **Step 1: Read `Sources/Core/HannWindow.swift`** to confirm current shape (one function: `makeHannWindow(_ count: Int) -> [Float]` using `vDSP_hann_window`).

- [ ] **Step 2: Replace the file contents** of `Sources/Core/HannWindow.swift` with:

```swift
import Accelerate

/// FFT analysis-window choices. Higher-quality windows (Hann/Hamming/Blackman)
/// reduce spectral leakage between adjacent frequency bins at the cost of
/// slight resolution loss. Rectangular is "no window" — the default for many
/// quick-and-dirty FFTs and what you get if you skip the multiplication.
public enum FFTWindow: String, Codable, CaseIterable {
    case rectangular, hann, hamming, blackman

    public var displayName: String {
        switch self {
        case .rectangular: return "Rectangular"
        case .hann:        return "Hann"
        case .hamming:     return "Hamming"
        case .blackman:    return "Blackman"
        }
    }
}

/// Build a window of the given length. The result is multiplied element-wise
/// into the time-domain samples before the FFT.
func makeWindow(_ kind: FFTWindow, count: Int) -> [Float] {
    var w = [Float](repeating: 0, count: count)
    switch kind {
    case .rectangular:
        for i in 0..<count { w[i] = 1 }
    case .hann:
        vDSP_hann_window(&w, vDSP_Length(count), Int32(vDSP_HANN_DENORM))
    case .hamming:
        vDSP_hamm_window(&w, vDSP_Length(count), 0)
    case .blackman:
        vDSP_blkman_window(&w, vDSP_Length(count), 0)
    }
    return w
}

/// Convenience for existing callers — preserved for backwards compat.
func makeHannWindow(_ count: Int) -> [Float] {
    return makeWindow(.hann, count: count)
}
```

- [ ] **Step 3: Run `make build`** — expect `** BUILD SUCCEEDED **` (no consumers changed yet; the new helpers are unused but compile).

### Subtask 2b: Wire FFTWindow into SpectrumAnalyzer

- [ ] **Step 4: Modify `Sources/Core/SpectrumAnalyzer.swift`.** Change the `window` field from `let` to `var`, take the initial window kind from settings, and add `setWindow(_:)`.

Find:
```swift
    private let window: [Float]
```
Replace with:
```swift
    private var window: [Float]
    private var windowKind: FFTWindow
```

Find:
```swift
    public init(fftSize: Int = 2048, sampleRate: Float = 48000, settings: VisualizerSettings) {
        self.fftSize = fftSize
        self.sampleRate = sampleRate
        self.barCount = settings.barCount
        self.window = makeHannWindow(fftSize)
        self.fft = FFTProcessor(size: fftSize)
```
Replace with:
```swift
    public init(fftSize: Int = 2048, sampleRate: Float = 48000, settings: VisualizerSettings) {
        self.fftSize = fftSize
        self.sampleRate = sampleRate
        self.barCount = settings.barCount
        self.windowKind = settings.fftWindow
        self.window = makeWindow(settings.fftWindow, count: fftSize)
        self.fft = FFTProcessor(size: fftSize)
```

After the existing `update(gain:smoothing:peakHoldEnabled:)` method, add:
```swift
    /// Live-tune the window function. Recomputes the window coefficients in
    /// place; the next `append(...)` picks them up. Call on the same queue as
    /// `append`.
    public func setWindow(_ kind: FFTWindow) {
        guard kind != windowKind else { return }
        windowKind = kind
        window = makeWindow(kind, count: fftSize)
    }
```

(No other changes; the time→frequency multiplication at `let windowed = zip(frameSamples, window).map(*)` already uses the `window` variable.)

### Subtask 2c: Add `fftWindow` to `VisualizerSettings`

- [ ] **Step 5: Write the failing tests.** Append to `VisualizerSettingsTests`:

```swift
    func testFFTWindowDefaultsToHann() {
        XCTAssertEqual(VisualizerSettings.defaults.fftWindow, .hann)
    }

    func testFFTWindowAllCasesPresent() {
        XCTAssertEqual(FFTWindow.allCases.count, 4)
        XCTAssertTrue(FFTWindow.allCases.contains(.rectangular))
        XCTAssertTrue(FFTWindow.allCases.contains(.hann))
        XCTAssertTrue(FFTWindow.allCases.contains(.hamming))
        XCTAssertTrue(FFTWindow.allCases.contains(.blackman))
    }

    func testFFTWindowRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.fftWindow = .blackman
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.fftWindow, .blackman)
        XCTAssertEqual(decoded, s)
    }

    func testFFTWindowPartialJSONDefaults() throws {
        let json = #"{ "gain": 2.5 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.fftWindow, .hann)
    }
```

- [ ] **Step 6: Run `make test`** — expect FAIL (`VisualizerSettings has no member 'fftWindow'`).

- [ ] **Step 7: Add `fftWindow` to `VisualizerSettings`** via the established 7-site pattern (`siriDepthFalloff` / `trailPersistence` are the most recent examples).

  1. **Stored property** (immediately after `trailPersistence`):
     ```swift
         public var fftWindow: FFTWindow         // Hann (default), Rectangular, Hamming, or Blackman
     ```
  2. **Memberwise `public init` parameter list** — add `fftWindow: FFTWindow` parameter (after `trailPersistence: Float`).
  3. **Memberwise `public init` body** — add `self.fftWindow = fftWindow` assignment.
  4. **`static let defaults`** — append `fftWindow: .hann` as the last argument.
  5. **`CodingKeys`** — add `case fftWindow`.
  6. **`init(from:)`** — add `let fw = try c.decodeIfPresent(FFTWindow.self, forKey: .fftWindow) ?? d.fftWindow` and pass `fftWindow: fw` to the trailing `self.init(...)`.
  7. **`encode(to:)`** — add `try c.encode(fftWindow, forKey: .fftWindow)`.

- [ ] **Step 8: Run `make test`** — expect `** TEST SUCCEEDED **`, 149 tests passing (145 from Task 1 + 4 new).

### Subtask 2d: Forward settings.fftWindow into the analyzer

- [ ] **Step 9: Modify `Sources/App/RenderModel.swift`.** In `applyLive(_ s:)`, add the window update inside the `dsp.async` block alongside the existing `analyzer.update(...)`:

Find:
```swift
        dsp.async {
            self.analyzer.update(gain: s.gain, smoothing: s.smoothing, peakHoldEnabled: s.peakHoldEnabled)
            if s.barCount != self.currentBarCount {
                self.currentBarCount = s.barCount
                self.analyzer.reconfigure(barCount: s.barCount)
            }
        }
```
Replace with:
```swift
        dsp.async {
            self.analyzer.update(gain: s.gain, smoothing: s.smoothing, peakHoldEnabled: s.peakHoldEnabled)
            self.analyzer.setWindow(s.fftWindow)
            if s.barCount != self.currentBarCount {
                self.currentBarCount = s.barCount
                self.analyzer.reconfigure(barCount: s.barCount)
            }
        }
```

### Subtask 2e: Add the Picker to the Audio tab

- [ ] **Step 10: Modify `Sources/App/SettingsView.swift`.** Find the existing `audioTab`:

```swift
    private var audioTab: some View {
        Form {
            Section("Sensitivity") {
                Slider(value: bind(\.gain), in: 0.5...4) {
                    Text("Gain")
                } minimumValueLabel: { Text("0.5") } maximumValueLabel: { Text("4") }
                Stepper("Bars: \(model.settings.barCount)",
                        value: bind(\.barCount), in: 16...96, step: 4)
                Slider(value: bind(\.smoothing), in: 0...0.95) {
                    Text("Smoothing")
                } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.95") }
            }
        }
        .formStyle(.grouped)
    }
```

Replace with (adds a new "FFT" section above "Sensitivity"):

```swift
    private var audioTab: some View {
        Form {
            Section("FFT") {
                Picker("Window", selection: $model.settings.fftWindow) {
                    ForEach(FFTWindow.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            Section("Sensitivity") {
                Slider(value: bind(\.gain), in: 0.5...4) {
                    Text("Gain")
                } minimumValueLabel: { Text("0.5") } maximumValueLabel: { Text("4") }
                Stepper("Bars: \(model.settings.barCount)",
                        value: bind(\.barCount), in: 16...96, step: 4)
                Slider(value: bind(\.smoothing), in: 0...0.95) {
                    Text("Smoothing")
                } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.95") }
            }
        }
        .formStyle(.grouped)
    }
```

- [ ] **Step 11: Run `make build` + `make test`** — expect `** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`, 149 tests.

- [ ] **Step 12: Commit**

```bash
git add Sources/Core/HannWindow.swift \
        Sources/Core/SpectrumAnalyzer.swift \
        Sources/Core/VisualizerSettings.swift \
        Sources/App/RenderModel.swift \
        Sources/App/SettingsView.swift \
        Tests/CoreTests/VisualizerSettingsTests.swift
git commit -m "Add FFT window selector (rectangular/hann/hamming/blackman, default hann)"
```

---

## Task 3: Vignette + film-grain post-process

Add two new top-level settings (`vignetteAmount`, `grainAmount`, both default 0). Extend `composite_fs` in `Shaders.metal` to read a `CompositeUniforms` struct (replacing the existing single-Float `intensity` uniform) and apply the vignette + grain. Update the three composite-encode sites in `MetalRenderer` to write the new uniform struct. Add two sliders to the Tweaks tab.

**Files:**
- Modify: `Sources/Core/VisualizerSettings.swift`
- Modify: `Sources/Rendering/Shaders.metal`
- Modify: `Sources/Rendering/MetalRenderer.swift`
- Modify: `Sources/App/SettingsView.swift`
- Modify: `Tests/CoreTests/VisualizerSettingsTests.swift`

### Subtask 3a: Add settings fields

- [ ] **Step 1: Write the failing tests.** Append to `VisualizerSettingsTests`:

```swift
    func testVignetteAndGrainDefaultsOff() {
        XCTAssertEqual(VisualizerSettings.defaults.vignetteAmount, 0, accuracy: 1e-6)
        XCTAssertEqual(VisualizerSettings.defaults.grainAmount, 0, accuracy: 1e-6)
    }

    func testVignetteAndGrainRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.vignetteAmount = 0.4
        s.grainAmount = 0.2
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.vignetteAmount, 0.4, accuracy: 1e-6)
        XCTAssertEqual(decoded.grainAmount, 0.2, accuracy: 1e-6)
        XCTAssertEqual(decoded, s)
    }

    func testVignetteAndGrainPartialJSONDefaults() throws {
        let json = #"{ "gain": 2.5 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.vignetteAmount, 0, accuracy: 1e-6)
        XCTAssertEqual(decoded.grainAmount, 0, accuracy: 1e-6)
    }
```

- [ ] **Step 2: Run `make test`** — expect FAIL.

- [ ] **Step 3: Add `vignetteAmount` and `grainAmount` to `VisualizerSettings`** via the 7-site pattern (immediately after `fftWindow` from Task 2). Both default to 0.

  Wiring details:
  1. **Stored properties:**
     ```swift
         public var vignetteAmount: Float        // 0..1 corner darkening; 0 = off
         public var grainAmount: Float           // 0..1 film-grain noise overlay; 0 = off
     ```
  2. **`public init` parameters and body** — add both fields.
  3. **`static let defaults`** — `vignetteAmount: 0`, `grainAmount: 0` as the last two arguments.
  4. **`CodingKeys`** — `case vignetteAmount, grainAmount`.
  5. **`init(from:)`** — `let va = try c.decodeIfPresent(Float.self, forKey: .vignetteAmount) ?? d.vignetteAmount` (and `ga` similarly); pass both at the end of `self.init(...)`.
  6. **`encode(to:)`** — encode both.

- [ ] **Step 4: Run `make test`** — expect `** TEST SUCCEEDED **`, 152 tests passing (149 + 3 new).

### Subtask 3b: Update `composite_fs` shader

- [ ] **Step 5: Modify `Sources/Rendering/Shaders.metal`.** Find the existing `composite_fs`:

```metal
fragment float4 composite_fs(FSQOut in [[stage_in]],
                             texture2d<float> sceneTex [[texture(0)]],
                             texture2d<float> blurTex  [[texture(1)]],
                             sampler samp              [[sampler(0)]],
                             constant float &intensity [[buffer(0)]]) {
    float3 scene = sceneTex.sample(samp, in.uv).rgb;
    float3 blur  = blurTex.sample(samp, in.uv).rgb;
    return float4(scene + blur * intensity, 1.0);
}
```

Replace with:

```metal
struct CompositeUniforms {
    float intensity;
    float vignetteAmount;
    float grainAmount;
    float time;
};

// 32-bit hash for per-pixel grain noise. Murmur3 finalizer constants.
static inline float grainHash(float2 uv, float t) {
    uint x = (uint)(uv.x * 1920.0) ^ (uint)(uv.y * 16807.0) ^ (uint)(t * 9301.0);
    x ^= x >> 16;
    x *= 0x85ebca6bu;
    x ^= x >> 13;
    x *= 0xc2b2ae35u;
    x ^= x >> 16;
    return float(x & 0xFFFFFF) / float(0xFFFFFF);
}

fragment float4 composite_fs(FSQOut in [[stage_in]],
                             texture2d<float> sceneTex [[texture(0)]],
                             texture2d<float> blurTex  [[texture(1)]],
                             sampler samp              [[sampler(0)]],
                             constant CompositeUniforms &u [[buffer(0)]]) {
    float3 scene = sceneTex.sample(samp, in.uv).rgb;
    float3 blur  = blurTex.sample(samp, in.uv).rgb;
    float3 color = scene + blur * u.intensity;

    // Vignette: smoothstep on distance from screen center. uv is 0..1; we want
    // (-1..+1) per axis so length = 0 at center, sqrt(2) at corners.
    if (u.vignetteAmount > 0.0) {
        float r = length(in.uv * 2.0 - 1.0);
        float v = 1.0 - u.vignetteAmount * smoothstep(0.55, 1.1, r);
        color *= v;
    }

    // Film grain: per-pixel noise centered at 0, scaled by grainAmount.
    if (u.grainAmount > 0.0) {
        float n = grainHash(in.uv, u.time) - 0.5;
        color += n * u.grainAmount;
    }

    return float4(color, 1.0);
}
```

### Subtask 3c: Update the three composite-encode sites in MetalRenderer

The Swift side needs to write a `CompositeUniforms` struct instead of a bare `Float intensity` at every call to `composite_fs`. There are three sites: `renderBloom`, `renderWithTrails`'s glow branch, `renderWithTrails`'s no-glow branch.

- [ ] **Step 6: Add a Swift mirror of `CompositeUniforms`** at the top of `Sources/Rendering/MetalRenderer.swift` (immediately under `import` lines). This matches the Metal struct layout:

```swift
private struct CompositeUniforms {
    var intensity: Float
    var vignetteAmount: Float
    var grainAmount: Float
    var time: Float
}
```

- [ ] **Step 7: Update `renderBloom`'s composite step.** Find:

```swift
        enc.setRenderPipelineState(compositePipeline)
        enc.setFragmentTexture(sceneTexture, index: 0)
        enc.setFragmentTexture(blurTexture, index: 1)
        enc.setFragmentSamplerState(linearSampler, index: 0)
        var i = intensity
        enc.setFragmentBytes(&i, length: MemoryLayout<Float>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }
```

Replace with (NOTE: only the `var i = intensity` + `setFragmentBytes` lines change; the surrounding context is identical):

```swift
        enc.setRenderPipelineState(compositePipeline)
        enc.setFragmentTexture(sceneTexture, index: 0)
        enc.setFragmentTexture(blurTexture, index: 1)
        enc.setFragmentSamplerState(linearSampler, index: 0)
        var u = makeCompositeUniforms(intensity: intensity, settings: settings)
        enc.setFragmentBytes(&u, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }
```

This requires `renderBloom` to accept a `settings: VisualizerSettings` parameter (currently it doesn't). Add it.

Update the `renderBloom` signature. Find:
```swift
    func renderBloom(vertices: [BarVertex],
                     clearColor: MTLClearColor,
                     intensity: Float,
                     finalPass: MTLRenderPassDescriptor,
                     width: Int,
                     height: Int,
                     commandBuffer: MTLCommandBuffer,
                     roundParticles: Bool = false) {
```
Replace with:
```swift
    func renderBloom(vertices: [BarVertex],
                     clearColor: MTLClearColor,
                     intensity: Float,
                     settings: VisualizerSettings,
                     finalPass: MTLRenderPassDescriptor,
                     width: Int,
                     height: Int,
                     commandBuffer: MTLCommandBuffer,
                     roundParticles: Bool = false) {
```

(And update both `renderBloom` callers in `MetalView` and `RenderProbe` — see step 9.)

- [ ] **Step 8: Update `renderWithTrails`'s two composite-encode branches** (glow path + no-glow path). Same change: replace the `var i = ...` + 4-byte `setFragmentBytes` with a `CompositeUniforms` write.

Find the glow branch:
```swift
            enc.setRenderPipelineState(compositePipeline)
            enc.setFragmentTexture(trailTexture, index: 0)
            enc.setFragmentTexture(blurTexture, index: 1)
            enc.setFragmentSamplerState(linearSampler, index: 0)
            var i = intensity
            enc.setFragmentBytes(&i, length: MemoryLayout<Float>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        } else {
```

Replace with:
```swift
            enc.setRenderPipelineState(compositePipeline)
            enc.setFragmentTexture(trailTexture, index: 0)
            enc.setFragmentTexture(blurTexture, index: 1)
            enc.setFragmentSamplerState(linearSampler, index: 0)
            var u = makeCompositeUniforms(intensity: intensity, settings: settings)
            enc.setFragmentBytes(&u, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        } else {
```

Find the no-glow branch (just after):
```swift
            enc.setRenderPipelineState(compositePipeline)
            enc.setFragmentTexture(trailTexture, index: 0)
            enc.setFragmentTexture(blurTexture, index: 1)
            enc.setFragmentSamplerState(linearSampler, index: 0)
            var zero: Float = 0
            enc.setFragmentBytes(&zero, length: MemoryLayout<Float>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }
```

Replace with:
```swift
            enc.setRenderPipelineState(compositePipeline)
            enc.setFragmentTexture(trailTexture, index: 0)
            enc.setFragmentTexture(blurTexture, index: 1)
            enc.setFragmentSamplerState(linearSampler, index: 0)
            // intensity = 0 so the blur term doesn't contribute; vignette/grain
            // still apply for visual consistency with the glow path.
            var u = makeCompositeUniforms(intensity: 0, settings: settings)
            enc.setFragmentBytes(&u, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }
```

`renderWithTrails` already takes `settings`? Let me check — it takes `persistence: Float` but not the full settings struct. **Add `settings: VisualizerSettings` to the signature** (after `persistence`):

Find:
```swift
    func renderWithTrails(vertices: [BarVertex],
                          clearColor: MTLClearColor,
                          intensity: Float,
                          persistence: Float,
                          glow: Bool,
                          finalPass: MTLRenderPassDescriptor,
                          width: Int,
                          height: Int,
                          commandBuffer: MTLCommandBuffer,
                          roundParticles: Bool = false) {
```
Replace with:
```swift
    func renderWithTrails(vertices: [BarVertex],
                          clearColor: MTLClearColor,
                          intensity: Float,
                          persistence: Float,
                          glow: Bool,
                          settings: VisualizerSettings,
                          finalPass: MTLRenderPassDescriptor,
                          width: Int,
                          height: Int,
                          commandBuffer: MTLCommandBuffer,
                          roundParticles: Bool = false) {
```

And update its internal fallback path so the renderBloom/encode forwarding works. Find:
```swift
            if glow {
                renderBloom(vertices: vertices, clearColor: clearColor, intensity: intensity,
                            finalPass: finalPass, width: width, height: height,
                            commandBuffer: commandBuffer, roundParticles: roundParticles)
            } else {
                encode(vertices: vertices, clearColor: clearColor, into: finalPass,
                       commandBuffer: commandBuffer, roundParticles: roundParticles)
            }
```
Replace with:
```swift
            if glow {
                renderBloom(vertices: vertices, clearColor: clearColor, intensity: intensity,
                            settings: settings,
                            finalPass: finalPass, width: width, height: height,
                            commandBuffer: commandBuffer, roundParticles: roundParticles)
            } else {
                encode(vertices: vertices, clearColor: clearColor, into: finalPass,
                       commandBuffer: commandBuffer, roundParticles: roundParticles)
            }
```

- [ ] **Step 9: Add the `makeCompositeUniforms` helper** at the end of the `MetalRenderer` class (before the closing brace):

```swift
    private func makeCompositeUniforms(intensity: Float, settings: VisualizerSettings) -> CompositeUniforms {
        // Use CACurrentMediaTime() modulo something so the float doesn't lose
        // precision over long sessions. 1024 seconds (~17 minutes) is plenty
        // for the grain hash to stay random.
        let t = Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 1024))
        return CompositeUniforms(
            intensity: intensity,
            vignetteAmount: settings.vignetteAmount,
            grainAmount: settings.grainAmount,
            time: t
        )
    }
```

(Add `import QuartzCore` at the top of `MetalRenderer.swift` if not already present — `CACurrentMediaTime()` lives there.)

### Subtask 3d: Update callers to pass `settings`

- [ ] **Step 10: Modify `Sources/Rendering/MetalView.swift`.** Both `renderBloom` and `renderWithTrails` call sites need `settings: model.settings`.

Find the existing block in `draw(in:)`:
```swift
            let round = model.settings.visualizerStyle.usesRoundParticles
            let persistence = model.settings.trailPersistence
            if persistence > 0 {
                renderer.renderWithTrails(vertices: vertices, clearColor: clear,
                                          intensity: model.settings.glowIntensity,
                                          persistence: persistence,
                                          glow: model.settings.glowEnabled,
                                          finalPass: descriptor,
                                          width: Int(size.width), height: Int(size.height),
                                          commandBuffer: commandBuffer,
                                          roundParticles: round)
            } else if model.settings.glowEnabled {
                renderer.renderBloom(vertices: vertices, clearColor: clear,
                                     intensity: model.settings.glowIntensity,
                                     finalPass: descriptor,
                                     width: Int(size.width), height: Int(size.height),
                                     commandBuffer: commandBuffer,
                                     roundParticles: round)
            } else {
                renderer.encode(vertices: vertices, clearColor: clear,
                                into: descriptor, commandBuffer: commandBuffer,
                                roundParticles: round)
            }
```

Replace with (adds `settings:` to the trail and bloom calls):
```swift
            let round = model.settings.visualizerStyle.usesRoundParticles
            let persistence = model.settings.trailPersistence
            if persistence > 0 {
                renderer.renderWithTrails(vertices: vertices, clearColor: clear,
                                          intensity: model.settings.glowIntensity,
                                          persistence: persistence,
                                          glow: model.settings.glowEnabled,
                                          settings: model.settings,
                                          finalPass: descriptor,
                                          width: Int(size.width), height: Int(size.height),
                                          commandBuffer: commandBuffer,
                                          roundParticles: round)
            } else if model.settings.glowEnabled {
                renderer.renderBloom(vertices: vertices, clearColor: clear,
                                     intensity: model.settings.glowIntensity,
                                     settings: model.settings,
                                     finalPass: descriptor,
                                     width: Int(size.width), height: Int(size.height),
                                     commandBuffer: commandBuffer,
                                     roundParticles: round)
            } else {
                renderer.encode(vertices: vertices, clearColor: clear,
                                into: descriptor, commandBuffer: commandBuffer,
                                roundParticles: round)
            }
```

- [ ] **Step 11: Modify `Sources/Rendering/RenderProbe.swift`.** Same change — add `settings:` to the two non-encode calls.

Find:
```swift
        let round = style.usesRoundParticles
        let persistence = settings.trailPersistence
        if persistence > 0 {
            renderer.renderWithTrails(vertices: vertices,
                                      clearColor: MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                                      intensity: 0.9,
                                      persistence: persistence,
                                      glow: glow,
                                      finalPass: pass,
                                      width: width, height: height,
                                      commandBuffer: commandBuffer,
                                      roundParticles: round)
        } else if glow {
            renderer.renderBloom(vertices: vertices,
                                 clearColor: MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                                 intensity: 0.9,
                                 finalPass: pass,
                                 width: width, height: height,
                                 commandBuffer: commandBuffer,
                                 roundParticles: round)
        } else {
```

Replace with:
```swift
        let round = style.usesRoundParticles
        let persistence = settings.trailPersistence
        if persistence > 0 {
            renderer.renderWithTrails(vertices: vertices,
                                      clearColor: MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                                      intensity: 0.9,
                                      persistence: persistence,
                                      glow: glow,
                                      settings: settings,
                                      finalPass: pass,
                                      width: width, height: height,
                                      commandBuffer: commandBuffer,
                                      roundParticles: round)
        } else if glow {
            renderer.renderBloom(vertices: vertices,
                                 clearColor: MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                                 intensity: 0.9,
                                 settings: settings,
                                 finalPass: pass,
                                 width: width, height: height,
                                 commandBuffer: commandBuffer,
                                 roundParticles: round)
        } else {
```

### Subtask 3e: Add the sliders to the Tweaks tab

- [ ] **Step 12: Modify `Sources/App/SettingsView.swift`.** Find the existing `tweaksTab` "Trails" section. Append a new "Post-process" section after it.

Find:
```swift
            Section("Trails") {
                Slider(value: $model.settings.trailPersistence, in: 0...0.97) {
                    Text("Persistence")
                } minimumValueLabel: { Text("Off") } maximumValueLabel: { Text("Long") }
            }
        }
        .formStyle(.grouped)
    }
```

Replace with:
```swift
            Section("Trails") {
                Slider(value: $model.settings.trailPersistence, in: 0...0.97) {
                    Text("Persistence")
                } minimumValueLabel: { Text("Off") } maximumValueLabel: { Text("Long") }
            }
            Section("Post-process") {
                Slider(value: $model.settings.vignetteAmount, in: 0...1) {
                    Text("Vignette")
                } minimumValueLabel: { Text("Off") } maximumValueLabel: { Text("Heavy") }
                Slider(value: $model.settings.grainAmount, in: 0...1) {
                    Text("Film grain")
                } minimumValueLabel: { Text("Off") } maximumValueLabel: { Text("Heavy") }
            }
        }
        .formStyle(.grouped)
    }
```

- [ ] **Step 13: Run `make build`** — expect `** BUILD SUCCEEDED **`.

- [ ] **Step 14: Run `make test`** — expect `** TEST SUCCEEDED **`, 152 tests passing.

- [ ] **Step 15: Render-probe regression** — confirm the composite pipeline still works end-to-end:

```bash
BIN=$(find DerivedData -name MacVisualizer -type f -path '*/MacOS/*' 2>/dev/null | head -1)
"$BIN" --render-probe /tmp/p_post.png radial glow
ls -la /tmp/p_post.png
```

Expect a non-zero PNG. (Defaults have vignette/grain = 0, so the probe output is visually unchanged from before.)

- [ ] **Step 16: Commit**

```bash
git add Sources/Core/VisualizerSettings.swift \
        Sources/Rendering/Shaders.metal \
        Sources/Rendering/MetalRenderer.swift \
        Sources/Rendering/MetalView.swift \
        Sources/Rendering/RenderProbe.swift \
        Sources/App/SettingsView.swift \
        Tests/CoreTests/VisualizerSettingsTests.swift
git commit -m "Add vignette + animated film-grain post-process via composite_fs uniforms"
```

---

## Task 4: Live verification (user)

- [ ] **Step 1: Launch the app**
```bash
make run
```

- [ ] **Step 2: Verify HDR palettes**
- Switch palette to **inferno** (Settings → Visualization → Color palette).
- Switch to **fireworks** style, toggle Demo Mode (⌥⌘D), bump glow intensity to ~1.0.
- Compared to before: bright peaks of bursts should have noticeably bigger / brighter halos.
- Repeat with **ember** and **aurora** — same effect on different colors.
- Switch to **classic** / **phosphor** / **synthwave** — unchanged (no HDR).

- [ ] **Step 3: Verify FFT window selector**
- Settings → Audio tab → FFT → Window picker should show: Rectangular, Hann, Hamming, Blackman. Default selected: **Hann**.
- With sustained tones (e.g., a long synth note via demo mode) and **bars** style, switch through the windows. Differences are subtle but visible — Rectangular should look "noisier" at the edges of active bands; Hann/Hamming/Blackman should look cleaner / smoother.

- [ ] **Step 4: Verify vignette + grain**
- Settings → Tweaks → Post-process section. Both sliders start at Off.
- Drag **Vignette** to ~0.4. Corners darken; center unchanged. Cinematic.
- Drag **Film grain** to ~0.2. Per-pixel animated noise overlay appears.
- Both = 0 → identical to before this branch.
- Combined with palette/style changes: post-process layers on top of all visualizers.

- [ ] **Step 5: Verify persistence**
- Set FFT window to Blackman, vignette to 0.3, grain to 0.1. ⌘Q. `make run`. Open Settings → confirm all three values persisted.

(Nothing to commit. If anything didn't work, capture the issue.)

---

## Definition of Done

- `make test` → `** TEST SUCCEEDED **`, **152** tests passing (144 + 8 new).
- `make build` → `** BUILD SUCCEEDED **`.
- inferno / ember / aurora palettes show clearly brighter bloom halos on hot peaks vs. classic/synthwave at the same scene.
- Audio tab has a 4-option FFT window picker; default Hann.
- Tweaks tab has a new "Post-process" section with Vignette + Film grain sliders (both 0..1, default 0).
- The composite_fs shader applies vignette + grain inside its fragment; the changes layer over every visualizer + every blend path.
- All three settings persist across relaunch via `settings.json`.

## Notes on implementation choices

- **HDR clamping caveat** — `sceneTexture` is still `bgra8Unorm`, so HDR values get clamped at write to that texture before the bloom blur. Bloom from HDR-overshoot is partial (clamped to 1 at scene write). The trail path uses rgba16Float (from Plan 12) so trails get full HDR. Spec §5 flags this; future cross-cutting cleanup can move sceneTexture to rgba16Float too.
- **`CompositeUniforms` struct mirror** — Swift struct is `@frozen`-style layout: 4 floats, 16 bytes, natural alignment matches the Metal struct.
- **Grain uses a per-pixel-per-frame deterministic hash** of `(uv, time)`, NOT a stored noise texture. Cheaper, animates naturally as `time` advances.
- **Why apply vignette + grain even when persistence > 0 and !glow** — visual consistency. The no-glow trail branch uses intensity = 0 to skip the blur term but still passes vignette/grain through. If a user enables grain and disables glow, they still expect grain.
- **`renderBloom` and `renderWithTrails` both grow a `settings: VisualizerSettings` parameter.** This is the simplest way to pass the new post-process values into the composite shader without smuggling them through a singleton or recomputing in the renderer.
