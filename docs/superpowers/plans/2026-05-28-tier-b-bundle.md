# Tier B Bundle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship three Tier-B roadmap items on one branch — Plasma (10th visualizer, per-pixel shader), Bumpscope (11th visualizer, audio-lit heightfield shader), and Kaleidoscope (N-fold rotational mirror post-process inside `composite_fs`).

**Architecture:** Two new visualizer styles, both rendered via dedicated fragment shaders (no CPU geometry). The renderer's existing scene-fill stage (which feeds bloom + composite + post-process) substitutes a `encodeShaderFill(...)` call for the geometry pass when `style.customShader` is non-nil. Shader inputs (current time, RMS, 16-bin downsampled bands) + palette stops are passed via `setFragmentBytes` uniform structs. Kaleidoscope is a UV transformation applied INSIDE `composite_fs` before sampling — it folds whatever visualizer is active.

**Tech Stack:** Swift 5.10, Metal (new fragment shaders + pipeline states + uniform structs), XCTest.

**Builds on:** `main` after merging `plan-14-wireframe-mesh`. Spec: `docs/superpowers/specs/2026-05-28-tier-b-bundle-design.md`.

**Scope boundary:** No new color palettes, no CPU-grid fallback, no in-Settings tunables for plasma/bumpscope (default values only), no kaleidoscope-center offset.

---

## File Structure

```
mac-visualizer/
  Sources/
    Core/
      ShaderKind.swift                # CREATE: enum (.plasma, .bumpscope)
      PlasmaVisualizer.swift          # CREATE: minimal stub class returning []
      BumpscopeVisualizer.swift       # CREATE: minimal stub class returning []
      VisualizerStyle.swift           # MODIFY: add .plasma + .bumpscope cases + customShader
      VisualizerSettings.swift        # MODIFY (Task 3): add kaleidoscopeFolds: Int top-level
    Rendering/
      Shaders.metal                   # MODIFY: ShaderInputs/PaletteUniform structs + plasma_fs/bumpscope_fs + kaleidoscope UV transform in composite_fs
      MetalRenderer.swift             # MODIFY: plasma/bumpscope pipelines + encodeShaderFill + uniform builders; renderBloom/renderWithTrails grow shaderKind+frame params; CompositeUniforms adds kaleidoscopeFolds
      MetalView.swift                 # MODIFY: route shader-driven styles through renderBloom (intensity=0 if !glow); pass frame + shaderKind
      RenderProbe.swift               # MODIFY: same routing as MetalView
    App/
      SettingsView.swift              # MODIFY (Task 3): add Kaleidoscope slider to Post-process section
  Tests/
    CoreTests/
      VisualizerStyleTests.swift      # MODIFY: tests for .plasma + .bumpscope (count==11, customShader, displayName, wrap)
      VisualizerSettingsTests.swift   # MODIFY (Task 3): tests for kaleidoscopeFolds
      PlasmaVisualizerTests.swift     # CREATE
      BumpscopeVisualizerTests.swift  # CREATE
```

Test count: 164 → 172 (+5 style + 0 visualizer-rendering + 3 settings).

---

## Task 1: Style enum + stub visualizers + `customShader` dispatch

Add `.plasma` / `.bumpscope` as the 10th and 11th cases of `VisualizerStyle`. Add `ShaderKind` enum + `customShader` dispatcher. Add minimal `PlasmaVisualizer` / `BumpscopeVisualizer` stubs that return `[]` from `makeVertices` (the shader path will handle rendering in Task 2). No rendering yet — this task is buildable green but the new styles produce blank output until Task 2 lands.

**Files:**
- Create: `Sources/Core/ShaderKind.swift`
- Create: `Sources/Core/PlasmaVisualizer.swift`
- Create: `Sources/Core/BumpscopeVisualizer.swift`
- Modify: `Sources/Core/VisualizerStyle.swift`
- Modify: `Tests/CoreTests/VisualizerStyleTests.swift`
- Create: `Tests/CoreTests/PlasmaVisualizerTests.swift`
- Create: `Tests/CoreTests/BumpscopeVisualizerTests.swift`

- [ ] **Step 1: Write the failing tests.**

In `Tests/CoreTests/VisualizerStyleTests.swift`, append three new methods:

```swift
    func testPlasmaAndBumpscopeAreLastTwoCases() {
        XCTAssertEqual(VisualizerStyle.allCases.count, 11)
        let last = VisualizerStyle.allCases.last
        XCTAssertEqual(last, .bumpscope)
        XCTAssertEqual(VisualizerStyle.allCases[VisualizerStyle.allCases.count - 2], .plasma)
    }

    func testShaderKindsForPlasmaAndBumpscope() {
        XCTAssertEqual(VisualizerStyle.plasma.displayName, "Plasma")
        XCTAssertEqual(VisualizerStyle.bumpscope.displayName, "Bumpscope")
        XCTAssertEqual(VisualizerStyle.plasma.customShader, .plasma)
        XCTAssertEqual(VisualizerStyle.bumpscope.customShader, .bumpscope)
        XCTAssertNil(VisualizerStyle.bars.customShader)
        XCTAssertNil(VisualizerStyle.wireframe.customShader)
        XCTAssertFalse(VisualizerStyle.plasma.usesRoundParticles)
        XCTAssertFalse(VisualizerStyle.bumpscope.usesRoundParticles)
        XCTAssertTrue(VisualizerStyle.plasma.makeVisualizer() is PlasmaVisualizer)
        XCTAssertTrue(VisualizerStyle.bumpscope.makeVisualizer() is BumpscopeVisualizer)
    }

    func testPlasmaBumpscopeWrapping() {
        XCTAssertEqual(VisualizerStyle.wireframe.next, .plasma)
        XCTAssertEqual(VisualizerStyle.plasma.next, .bumpscope)
        XCTAssertEqual(VisualizerStyle.bumpscope.next, .bars)
        XCTAssertEqual(VisualizerStyle.bars.previous, .bumpscope)
        XCTAssertEqual(VisualizerStyle.plasma.previous, .wireframe)
        XCTAssertEqual(VisualizerStyle.bumpscope.previous, .plasma)
    }
```

In `Tests/CoreTests/PlasmaVisualizerTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class PlasmaVisualizerTests: XCTestCase {
    func testReturnsNoGeometry() {
        // PlasmaVisualizer is a stub: the shader path handles rendering, so
        // makeVertices() returns an empty array.
        let viz = PlasmaVisualizer()
        let frame = AudioFrame(bands: [0.5, 0.5, 0.5], bandPeaks: [], waveform: [],
                               rms: 0.5, peak: 0.5, timestamp: 0)
        let verts = viz.makeVertices(frame: frame, settings: .defaults, aspect: 1)
        XCTAssertTrue(verts.isEmpty)
    }
}
```

In `Tests/CoreTests/BumpscopeVisualizerTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class BumpscopeVisualizerTests: XCTestCase {
    func testReturnsNoGeometry() {
        let viz = BumpscopeVisualizer()
        let frame = AudioFrame(bands: [0.5, 0.5, 0.5], bandPeaks: [], waveform: [],
                               rms: 0.5, peak: 0.5, timestamp: 0)
        let verts = viz.makeVertices(frame: frame, settings: .defaults, aspect: 1)
        XCTAssertTrue(verts.isEmpty)
    }
}
```

Also UPDATE the existing wrap-target tests in `VisualizerStyleTests.swift` (likely `testAllCases`, `testNextWrapsAround`, `testPreviousWrapsAround`, plus the wireframe-specific `testWireframeCaseExistsAndIsLast` / `testWireframeNextPreviousWrapping`) so they reflect the new wrap targets:
- `allCases.count == 9` → `11`.
- `.wireframe.next == .bars` → `.plasma`.
- `.bars.previous == .wireframe` → `.bumpscope`.
- `last == .wireframe` → `.bumpscope`.

If `testAllCases` enumerates the cases explicitly, append `.plasma, .bumpscope`.

- [ ] **Step 2: Run `make test`** — expect FAIL (cases / classes don't exist).

- [ ] **Step 3: Create `Sources/Core/ShaderKind.swift`:**

```swift
import Foundation

/// Identifies which Metal fragment shader a shader-driven visualizer uses.
/// `VisualizerStyle.customShader` returns one of these (or nil for the
/// standard geometry-based visualizers).
public enum ShaderKind: String, Codable, CaseIterable {
    case plasma
    case bumpscope
}
```

- [ ] **Step 4: Create `Sources/Core/PlasmaVisualizer.swift`:**

```swift
/// 10th visualizer style: full-screen plasma shader. This Swift class is a
/// stub — it exists only to satisfy `VisualizerStyle.makeVisualizer()`. The
/// actual rendering happens in `plasma_fs` inside `Shaders.metal`, dispatched
/// by `MetalRenderer.encodeShaderFill(...)` when `style.customShader == .plasma`.
public final class PlasmaVisualizer: Visualizer {
    public init() {}

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        return []
    }
}
```

- [ ] **Step 5: Create `Sources/Core/BumpscopeVisualizer.swift`** (same shape):

```swift
/// 11th visualizer style: audio-lit heightfield shader. Stub class for the
/// same reason as PlasmaVisualizer; `bumpscope_fs` does the per-pixel work.
public final class BumpscopeVisualizer: Visualizer {
    public init() {}

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        return []
    }
}
```

- [ ] **Step 6: Add `.plasma` + `.bumpscope` + `customShader` to `Sources/Core/VisualizerStyle.swift`.**

Replace the entire enum body:

```swift
public enum VisualizerStyle: String, Codable, CaseIterable {
    case bars, radial, mirrored, oscilloscope, particles, fountain, fireworks, siri, wireframe, plasma, bumpscope

    public var displayName: String {
        switch self {
        case .bars: return "Bars"
        case .radial: return "Radial"
        case .mirrored: return "Mirrored"
        case .oscilloscope: return "Oscilloscope"
        case .particles: return "Particles"
        case .fountain: return "Fountain"
        case .fireworks: return "Fireworks"
        case .siri: return "Siri"
        case .wireframe: return "Wireframe"
        case .plasma: return "Plasma"
        case .bumpscope: return "Bumpscope"
        }
    }

    public var usesRoundParticles: Bool {
        switch self {
        case .particles, .fountain, .fireworks: return true
        case .bars, .radial, .mirrored, .oscilloscope, .siri, .wireframe, .plasma, .bumpscope: return false
        }
    }

    /// For shader-driven visualizers, returns the `ShaderKind` whose fragment
    /// shader should fill the scene. Geometry-based visualizers return nil
    /// and use the normal triangle-pipeline path.
    public var customShader: ShaderKind? {
        switch self {
        case .plasma: return .plasma
        case .bumpscope: return .bumpscope
        case .bars, .radial, .mirrored, .oscilloscope, .particles, .fountain, .fireworks, .siri, .wireframe:
            return nil
        }
    }

    public func makeVisualizer() -> Visualizer {
        switch self {
        case .bars: return SpectrumBarsVisualizer()
        case .radial: return RadialSpectrumVisualizer()
        case .mirrored: return MirroredBarsVisualizer()
        case .oscilloscope: return OscilloscopeVisualizer()
        case .particles: return ParticleVisualizer()
        case .fountain: return SpectrumFountainVisualizer()
        case .fireworks: return FireworksVisualizer()
        case .siri: return SiriWaveVisualizer()
        case .wireframe: return WireframeVisualizer()
        case .plasma: return PlasmaVisualizer()
        case .bumpscope: return BumpscopeVisualizer()
        }
    }

    public var next: VisualizerStyle {
        let all = Self.allCases
        let i = all.firstIndex(of: self)!
        return all[(i + 1) % all.count]
    }

    public var previous: VisualizerStyle {
        let all = Self.allCases
        let i = all.firstIndex(of: self)!
        return all[(i - 1 + all.count) % all.count]
    }
}
```

- [ ] **Step 7: Run `make test`** — expect `** TEST SUCCEEDED **`, **169** tests passing (164 + 5 new). Existing wrap-target tests need updating too; if they still fail, update them as described in Step 1.

- [ ] **Step 8: Run `make build`** — expect `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
git add Sources/Core/ShaderKind.swift \
        Sources/Core/PlasmaVisualizer.swift \
        Sources/Core/BumpscopeVisualizer.swift \
        Sources/Core/VisualizerStyle.swift \
        Tests/CoreTests/VisualizerStyleTests.swift \
        Tests/CoreTests/PlasmaVisualizerTests.swift \
        Tests/CoreTests/BumpscopeVisualizerTests.swift
git commit -m "Add .plasma / .bumpscope styles + ShaderKind dispatch (rendering stubbed in Task 2)"
```

---

## Task 2: Shader infrastructure — uniforms, plasma_fs, bumpscope_fs, pipelines, render integration

This is the biggest task. Adds matching Swift+Metal uniform structs, two new fragment shaders, two new pipeline states, a new `encodeShaderFill` render path, and wires it into `renderBloom` + `renderWithTrails` so shader visualizers go through the same bloom/composite/post-process chain as everyone else. Also extends MetalView + RenderProbe call sites.

No new tests — verified visually in Task 4.

**Files:**
- Modify: `Sources/Rendering/Shaders.metal`
- Modify: `Sources/Rendering/MetalRenderer.swift`
- Modify: `Sources/Rendering/MetalView.swift`
- Modify: `Sources/Rendering/RenderProbe.swift`

### Subtask 2a: Add shader uniforms + helper + shaders to `Shaders.metal`

- [ ] **Step 1: Append to `Sources/Rendering/Shaders.metal`** (after the existing `fade_fs` block):

```metal
// ============================================================================
// Shader-driven visualizers (plasma, bumpscope)
// ============================================================================

struct ShaderInputs {
    float time;
    float energy;
    float bands[16];
};

struct PaletteStopUniform {
    float r;
    float g;
    float b;
    float position;
};

struct PaletteUniform {
    PaletteStopUniform stops[8];
    int stopCount;
};

// Linearly sample the palette at t in [0,1]. Stops are treated as evenly
// distributed across [0,1] regardless of their `position` field (matches the
// Swift ColorPalette.sample semantics).
static inline float3 samplePalette(constant PaletteUniform &p, float t) {
    t = clamp(t, 0.0, 1.0);
    int n = p.stopCount;
    if (n <= 1) {
        return float3(p.stops[0].r, p.stops[0].g, p.stops[0].b);
    }
    float scaled = t * float(n - 1);
    int lo = (int)floor(scaled);
    if (lo < 0) lo = 0;
    if (lo > n - 2) lo = n - 2;
    int hi = lo + 1;
    float u = scaled - float(lo);
    PaletteStopUniform a = p.stops[lo];
    PaletteStopUniform b = p.stops[hi];
    return float3(a.r + (b.r - a.r) * u,
                  a.g + (b.g - a.g) * u,
                  a.b + (b.b - a.b) * u);
}

fragment float4 plasma_fs(FSQOut in [[stage_in]],
                          constant ShaderInputs &input [[buffer(0)]],
                          constant PaletteUniform &palette [[buffer(1)]]) {
    // Plasma over uv in -1..+1 so wave frequencies feel symmetric across screen.
    float2 uv = in.uv * 2.0 - 1.0;
    float t = input.time;
    float v = sin(uv.x * 8.0 + t)
            + sin(uv.y * 6.0 + t * 1.3)
            + sin((uv.x + uv.y) * 5.0 + t * 0.7);
    v = v / 3.0 * 0.5 + 0.5 + input.energy * 0.3;
    v = clamp(v, 0.0, 1.0);
    return float4(samplePalette(palette, v), 1.0);
}

fragment float4 bumpscope_fs(FSQOut in [[stage_in]],
                             constant ShaderInputs &input [[buffer(0)]],
                             constant PaletteUniform &palette [[buffer(1)]]) {
    // Each pixel's "height" comes from the spectrum band at that x position.
    // Surface normal computed from horizontal neighbors. Lit by a fixed
    // direction, then color sampled from the palette by lit intensity.
    float u = clamp(in.uv.x, 0.0, 1.0);
    int xi = (int)(u * 15.0);
    if (xi < 0) xi = 0;
    if (xi > 15) xi = 15;
    int xL = (xi - 1 >= 0) ? xi - 1 : 0;
    int xR = (xi + 1 <= 15) ? xi + 1 : 15;
    float h  = input.bands[xi];
    float hL = input.bands[xL];
    float hR = input.bands[xR];
    float dx = (hR - hL) * 0.5;
    float3 n = normalize(float3(-dx, 1.0, 0.0));
    float3 L = normalize(float3(0.5, 0.7, 0.5));
    float lit = max(0.0, dot(n, L));
    float intensity = clamp(lit * (h * 2.0 + 0.2), 0.0, 1.0);
    return float4(samplePalette(palette, intensity), 1.0);
}
```

### Subtask 2b: Add Swift mirror structs + pipeline state + helpers in `MetalRenderer.swift`

- [ ] **Step 2: Add the Swift uniform mirrors** at the top of `MetalRenderer.swift`, immediately under the existing `private struct CompositeUniforms { ... }`:

```swift
private struct PaletteStopUniform {
    var r: Float = 0
    var g: Float = 0
    var b: Float = 0
    var position: Float = 0
}

private struct PaletteUniform {
    // Fixed 8 slots matches the Metal `PaletteStopUniform stops[8]`.
    var stops: (PaletteStopUniform, PaletteStopUniform, PaletteStopUniform, PaletteStopUniform,
                PaletteStopUniform, PaletteStopUniform, PaletteStopUniform, PaletteStopUniform) =
        (.init(), .init(), .init(), .init(), .init(), .init(), .init(), .init())
    var stopCount: Int32 = 0
}

private struct ShaderInputs {
    var time: Float = 0
    var energy: Float = 0
    // 16 floats; tuple keeps layout deterministic.
    var bands: (Float, Float, Float, Float, Float, Float, Float, Float,
                Float, Float, Float, Float, Float, Float, Float, Float) =
        (0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0)
}
```

- [ ] **Step 3: Add new pipeline-state properties.** In the class field block (under the existing pipelines):

```swift
    private let plasmaPipeline16: MTLRenderPipelineState?
    private let bumpscopePipeline16: MTLRenderPipelineState?
```

- [ ] **Step 4: Build the new pipelines in `init?(...)`.** After the existing `roundPipeline16` setup block (which uses `pixelFormat = .rgba16Float`):

```swift
        // Plasma / Bumpscope pipelines — fullscreen_vs + their own fragment
        // shader, writing into the rgba16Float scene/trail texture.
        let pdesc = MTLRenderPipelineDescriptor()
        pdesc.vertexFunction = library.makeFunction(name: "fullscreen_vs")
        pdesc.fragmentFunction = library.makeFunction(name: "plasma_fs")
        pdesc.colorAttachments[0].pixelFormat = .rgba16Float
        self.plasmaPipeline16 = try? device.makeRenderPipelineState(descriptor: pdesc)

        let bdesc = MTLRenderPipelineDescriptor()
        bdesc.vertexFunction = library.makeFunction(name: "fullscreen_vs")
        bdesc.fragmentFunction = library.makeFunction(name: "bumpscope_fs")
        bdesc.colorAttachments[0].pixelFormat = .rgba16Float
        self.bumpscopePipeline16 = try? device.makeRenderPipelineState(descriptor: bdesc)
```

- [ ] **Step 5: Add three helpers in `MetalRenderer`.** Place them at the end of the class, alongside `makeCompositeUniforms`:

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
                if hi > lo {
                    for k in lo..<hi { sum += frame.bands[k] }
                    arr[i] = sum / Float(hi - lo)
                } else {
                    arr[i] = frame.bands[min(lo, bandCount - 1)]
                }
            }
        }
        inputs.bands = (arr[0],  arr[1],  arr[2],  arr[3],  arr[4],  arr[5],  arr[6],  arr[7],
                        arr[8],  arr[9],  arr[10], arr[11], arr[12], arr[13], arr[14], arr[15])
        return inputs
    }

    private func makePaletteUniform(named name: String) -> PaletteUniform {
        let palette = ColorPalette.preset(named: name)
            ?? ColorPalette.preset(named: "classic")!
        var u = PaletteUniform()
        let n = min(palette.stops.count, 8)
        u.stopCount = Int32(n)
        // Stops are stored in a fixed-size tuple; populate by index.
        var arr = [PaletteStopUniform](repeating: .init(), count: 8)
        for i in 0..<n {
            let c = palette.stops[i]
            // position field unused by Metal sampler; included for layout parity.
            arr[i] = PaletteStopUniform(r: c.r, g: c.g, b: c.b,
                                        position: Float(i) / Float(max(n - 1, 1)))
        }
        u.stops = (arr[0], arr[1], arr[2], arr[3], arr[4], arr[5], arr[6], arr[7])
        return u
    }

    /// Fill the destination pass with a fullscreen-shader visualizer. Used by
    /// `renderBloom` / `renderWithTrails` when `shaderKind` is non-nil.
    private func encodeShaderFill(kind: ShaderKind,
                                  frame: AudioFrame,
                                  settings: VisualizerSettings,
                                  clearColor: MTLClearColor,
                                  into descriptor: MTLRenderPassDescriptor,
                                  commandBuffer: MTLCommandBuffer) {
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = clearColor
        descriptor.colorAttachments[0].storeAction = .store

        let pipeline: MTLRenderPipelineState?
        switch kind {
        case .plasma: pipeline = plasmaPipeline16
        case .bumpscope: pipeline = bumpscopePipeline16
        }
        guard let pipeline,
              let enc = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        enc.setRenderPipelineState(pipeline)
        var inputs = makeShaderInputs(frame: frame)
        var palette = makePaletteUniform(named: settings.paletteName)
        enc.setFragmentBytes(&inputs, length: MemoryLayout<ShaderInputs>.stride, index: 0)
        enc.setFragmentBytes(&palette, length: MemoryLayout<PaletteUniform>.stride, index: 1)
        // fullscreen_vs synthesizes a 3-vertex screen-covering triangle from vid.
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }
```

### Subtask 2c: Integrate the shader path with `renderBloom` and `renderWithTrails`

The existing scene-fill step in both functions calls `encode(vertices:into:...)`. We add an optional `shaderKind` parameter; when non-nil, substitute `encodeShaderFill(...)` and ignore `vertices`.

- [ ] **Step 6: Modify `renderBloom`'s signature.** Find:

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

Replace with (adds `shaderKind` + `frame`):

```swift
    func renderBloom(vertices: [BarVertex],
                     clearColor: MTLClearColor,
                     intensity: Float,
                     settings: VisualizerSettings,
                     frame: AudioFrame,
                     finalPass: MTLRenderPassDescriptor,
                     width: Int,
                     height: Int,
                     commandBuffer: MTLCommandBuffer,
                     roundParticles: Bool = false,
                     shaderKind: ShaderKind? = nil) {
```

Inside `renderBloom`, find the scene-pass call:

```swift
        // Pass 1: geometry -> sceneTexture (encode sets clear/store on the descriptor).
        let scenePass = MTLRenderPassDescriptor()
        scenePass.colorAttachments[0].texture = sceneTexture
        encode(vertices: vertices, clearColor: clearColor, into: scenePass,
               commandBuffer: commandBuffer, roundParticles: roundParticles,
               highPrecision: true)
```

Replace with:

```swift
        // Pass 1: scene fill -> sceneTexture. Geometry path for normal styles;
        // shader path for plasma / bumpscope (writes through encodeShaderFill).
        let scenePass = MTLRenderPassDescriptor()
        scenePass.colorAttachments[0].texture = sceneTexture
        if let shaderKind {
            encodeShaderFill(kind: shaderKind, frame: frame, settings: settings,
                             clearColor: clearColor, into: scenePass,
                             commandBuffer: commandBuffer)
        } else {
            encode(vertices: vertices, clearColor: clearColor, into: scenePass,
                   commandBuffer: commandBuffer, roundParticles: roundParticles,
                   highPrecision: true)
        }
```

- [ ] **Step 7: Modify `renderWithTrails`'s signature.** Find:

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

Replace with:

```swift
    func renderWithTrails(vertices: [BarVertex],
                          clearColor: MTLClearColor,
                          intensity: Float,
                          persistence: Float,
                          glow: Bool,
                          settings: VisualizerSettings,
                          frame: AudioFrame,
                          finalPass: MTLRenderPassDescriptor,
                          width: Int,
                          height: Int,
                          commandBuffer: MTLCommandBuffer,
                          roundParticles: Bool = false,
                          shaderKind: ShaderKind? = nil) {
```

Inside, find the geometry pass (Pass 2) inside `renderWithTrails`:

```swift
        // Pass 2: Geometry — draw vertices into trailTexture on top of the
        // faded prior frames. loadAction = .load to preserve the fade pass.
        if !vertices.isEmpty {
            let geomPass = MTLRenderPassDescriptor()
            geomPass.colorAttachments[0].texture = trailTexture
            geomPass.colorAttachments[0].loadAction = .load
            geomPass.colorAttachments[0].storeAction = .store
            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: geomPass) {
                // Use the 16-bit-output pipelines (trailTexture is rgba16Float).
                enc.setRenderPipelineState((roundParticles ? roundPipeline16 : nil) ?? pipeline16)
                let length = vertices.count * MemoryLayout<BarVertex>.stride
                if vertexBuffer == nil || vertexBufferCapacity < length {
                    vertexBuffer = device.makeBuffer(length: length, options: .storageModeShared)
                    vertexBufferCapacity = length
                }
                if let buffer = vertexBuffer {
                    vertices.withUnsafeBytes { raw in
                        memcpy(buffer.contents(), raw.baseAddress!, length)
                    }
                    enc.setVertexBuffer(buffer, offset: 0, index: 0)
                    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
                }
                enc.endEncoding()
            }
        }
```

Replace the entire block above with:

```swift
        // Pass 2: Scene fill — either draw vertex geometry on top of the
        // faded trail, OR run the shader-driven fragment fragment over the
        // trail. shaderKind path uses loadAction = .load so the trail accumulates.
        if let shaderKind {
            // For shader visualizers in the trail path: replay the shader on
            // top of the faded trail with loadAction = .load so trails of the
            // shader's prior frames remain visible.
            let geomPass = MTLRenderPassDescriptor()
            geomPass.colorAttachments[0].texture = trailTexture
            geomPass.colorAttachments[0].loadAction = .load
            geomPass.colorAttachments[0].storeAction = .store
            let pipeline: MTLRenderPipelineState?
            switch shaderKind {
            case .plasma: pipeline = plasmaPipeline16
            case .bumpscope: pipeline = bumpscopePipeline16
            }
            if let pipeline,
               let enc = commandBuffer.makeRenderCommandEncoder(descriptor: geomPass) {
                enc.setRenderPipelineState(pipeline)
                var inputs = makeShaderInputs(frame: frame)
                var palette = makePaletteUniform(named: settings.paletteName)
                enc.setFragmentBytes(&inputs, length: MemoryLayout<ShaderInputs>.stride, index: 0)
                enc.setFragmentBytes(&palette, length: MemoryLayout<PaletteUniform>.stride, index: 1)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
            }
        } else if !vertices.isEmpty {
            let geomPass = MTLRenderPassDescriptor()
            geomPass.colorAttachments[0].texture = trailTexture
            geomPass.colorAttachments[0].loadAction = .load
            geomPass.colorAttachments[0].storeAction = .store
            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: geomPass) {
                enc.setRenderPipelineState((roundParticles ? roundPipeline16 : nil) ?? pipeline16)
                let length = vertices.count * MemoryLayout<BarVertex>.stride
                if vertexBuffer == nil || vertexBufferCapacity < length {
                    vertexBuffer = device.makeBuffer(length: length, options: .storageModeShared)
                    vertexBufferCapacity = length
                }
                if let buffer = vertexBuffer {
                    vertices.withUnsafeBytes { raw in
                        memcpy(buffer.contents(), raw.baseAddress!, length)
                    }
                    enc.setVertexBuffer(buffer, offset: 0, index: 0)
                    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
                }
                enc.endEncoding()
            }
        }
```

Inside `renderWithTrails`, also find the fallback `renderBloom` call:

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

Replace with (forwards `frame` and `shaderKind`):

```swift
            if glow {
                renderBloom(vertices: vertices, clearColor: clearColor, intensity: intensity,
                            settings: settings, frame: frame,
                            finalPass: finalPass, width: width, height: height,
                            commandBuffer: commandBuffer, roundParticles: roundParticles,
                            shaderKind: shaderKind)
            } else if let shaderKind {
                // Shader visualizer with no glow: still need to route through
                // bloom path (intensity = 0) so composite_fs/vignette/grain apply.
                renderBloom(vertices: vertices, clearColor: clearColor, intensity: 0,
                            settings: settings, frame: frame,
                            finalPass: finalPass, width: width, height: height,
                            commandBuffer: commandBuffer, roundParticles: roundParticles,
                            shaderKind: shaderKind)
            } else {
                encode(vertices: vertices, clearColor: clearColor, into: finalPass,
                       commandBuffer: commandBuffer, roundParticles: roundParticles)
            }
```

### Subtask 2d: Update call sites in `MetalView` + `RenderProbe`

- [ ] **Step 8: Modify `Sources/Rendering/MetalView.swift`.** Find the existing route block (after the shader-style addition, which we're adding now):

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

Replace with (adds `shaderKind` lookup + forwards `frame` to bloom/trails, routes shader-no-glow path through bloom with intensity=0):

```swift
            let round = model.settings.visualizerStyle.usesRoundParticles
            let shaderKind = model.settings.visualizerStyle.customShader
            let persistence = model.settings.trailPersistence
            if persistence > 0 {
                renderer.renderWithTrails(vertices: vertices, clearColor: clear,
                                          intensity: model.settings.glowIntensity,
                                          persistence: persistence,
                                          glow: model.settings.glowEnabled,
                                          settings: model.settings,
                                          frame: frame,
                                          finalPass: descriptor,
                                          width: Int(size.width), height: Int(size.height),
                                          commandBuffer: commandBuffer,
                                          roundParticles: round,
                                          shaderKind: shaderKind)
            } else if model.settings.glowEnabled {
                renderer.renderBloom(vertices: vertices, clearColor: clear,
                                     intensity: model.settings.glowIntensity,
                                     settings: model.settings,
                                     frame: frame,
                                     finalPass: descriptor,
                                     width: Int(size.width), height: Int(size.height),
                                     commandBuffer: commandBuffer,
                                     roundParticles: round,
                                     shaderKind: shaderKind)
            } else if shaderKind != nil {
                // Shader visualizer with no glow: route through bloom path
                // (intensity = 0) so composite_fs/vignette/grain apply.
                renderer.renderBloom(vertices: vertices, clearColor: clear,
                                     intensity: 0,
                                     settings: model.settings,
                                     frame: frame,
                                     finalPass: descriptor,
                                     width: Int(size.width), height: Int(size.height),
                                     commandBuffer: commandBuffer,
                                     roundParticles: round,
                                     shaderKind: shaderKind)
            } else {
                renderer.encode(vertices: vertices, clearColor: clear,
                                into: descriptor, commandBuffer: commandBuffer,
                                roundParticles: round)
            }
```

- [ ] **Step 9: Modify `Sources/Rendering/RenderProbe.swift`.** Find the existing call block:

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
            renderer.encode(vertices: vertices,
                            clearColor: MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                            into: pass, commandBuffer: commandBuffer,
                            roundParticles: round)
        }
```

Replace with:

```swift
        let round = style.usesRoundParticles
        let shaderKind = style.customShader
        let persistence = settings.trailPersistence
        if persistence > 0 {
            renderer.renderWithTrails(vertices: vertices,
                                      clearColor: MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                                      intensity: 0.9,
                                      persistence: persistence,
                                      glow: glow,
                                      settings: settings,
                                      frame: frame,
                                      finalPass: pass,
                                      width: width, height: height,
                                      commandBuffer: commandBuffer,
                                      roundParticles: round,
                                      shaderKind: shaderKind)
        } else if glow {
            renderer.renderBloom(vertices: vertices,
                                 clearColor: MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                                 intensity: 0.9,
                                 settings: settings,
                                 frame: frame,
                                 finalPass: pass,
                                 width: width, height: height,
                                 commandBuffer: commandBuffer,
                                 roundParticles: round,
                                 shaderKind: shaderKind)
        } else if shaderKind != nil {
            renderer.renderBloom(vertices: vertices,
                                 clearColor: MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                                 intensity: 0,
                                 settings: settings,
                                 frame: frame,
                                 finalPass: pass,
                                 width: width, height: height,
                                 commandBuffer: commandBuffer,
                                 roundParticles: round,
                                 shaderKind: shaderKind)
        } else {
            renderer.encode(vertices: vertices,
                            clearColor: MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                            into: pass, commandBuffer: commandBuffer,
                            roundParticles: round)
        }
```

- [ ] **Step 10: Run `make build`** — expect `** BUILD SUCCEEDED **`.

- [ ] **Step 11: Run `make test`** — expect `** TEST SUCCEEDED **`, 169 tests passing (unchanged; no new tests in Task 2).

- [ ] **Step 12: Render-probe smoke test** — confirm shader visualizers render:

```bash
BIN=$(find DerivedData -name MacVisualizer -type f -path '*/MacOS/*' 2>/dev/null | head -1)
"$BIN" --render-probe /tmp/p_plasma.png plasma
"$BIN" --render-probe /tmp/p_bump.png bumpscope
ls -la /tmp/p_plasma.png /tmp/p_bump.png
```

Expect two non-zero PNGs. Plasma probe will be vivid; bumpscope probe at silent input has all `bands = 0` so `h = hL = hR = 0`, `intensity = 0`, palette samples at 0 → dark/empty (this is expected; live verify with non-silent input shows the real effect).

- [ ] **Step 13: Commit**

```bash
git add Sources/Rendering/Shaders.metal \
        Sources/Rendering/MetalRenderer.swift \
        Sources/Rendering/MetalView.swift \
        Sources/Rendering/RenderProbe.swift
git commit -m "Add shader-driven visualizer infrastructure + plasma_fs + bumpscope_fs"
```

---

## Task 3: Kaleidoscope post-process

Add `kaleidoscopeFolds: Int` (default 0, range 0..12) top-level setting. Extend `CompositeUniforms` (Swift + Metal) with an `Int32` field. Apply UV transformation INSIDE `composite_fs` BEFORE sampling textures. Add a slider on the Tweaks tab's Post-process section.

**Files:**
- Modify: `Sources/Core/VisualizerSettings.swift`
- Modify: `Sources/Rendering/Shaders.metal`
- Modify: `Sources/Rendering/MetalRenderer.swift`
- Modify: `Sources/App/SettingsView.swift`
- Modify: `Tests/CoreTests/VisualizerSettingsTests.swift`

### Subtask 3a: Add `kaleidoscopeFolds` to `VisualizerSettings`

- [ ] **Step 1: Write the failing tests.** Append to `VisualizerSettingsTests`:

```swift
    func testKaleidoscopeFoldsDefaultsZero() {
        XCTAssertEqual(VisualizerSettings.defaults.kaleidoscopeFolds, 0)
    }

    func testKaleidoscopeFoldsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.kaleidoscopeFolds = 6
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.kaleidoscopeFolds, 6)
        XCTAssertEqual(decoded, s)
    }

    func testKaleidoscopeFoldsPartialJSONDefaults() throws {
        let json = #"{ "gain": 2.5 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.kaleidoscopeFolds, 0)
    }
```

- [ ] **Step 2: Run `make test`** — expect FAIL (`VisualizerSettings has no member 'kaleidoscopeFolds'`).

- [ ] **Step 3: Add `kaleidoscopeFolds: Int` to `VisualizerSettings`** via the 7-site pattern. Place immediately AFTER `grainAmount`.

  1. Stored property: `public var kaleidoscopeFolds: Int       // 0 = off; 2..12 = N-fold mirror`.
  2. `public init(...)` parameter and body: `kaleidoscopeFolds: Int` + `self.kaleidoscopeFolds = kaleidoscopeFolds`.
  3. `static let defaults`: append `kaleidoscopeFolds: 0`.
  4. `CodingKeys`: `case kaleidoscopeFolds`.
  5. `init(from:)`: `let kf = try c.decodeIfPresent(Int.self, forKey: .kaleidoscopeFolds) ?? d.kaleidoscopeFolds`, pass `kaleidoscopeFolds: kf` at the trailing `self.init(...)`.
  6. `encode(to:)`: `try c.encode(kaleidoscopeFolds, forKey: .kaleidoscopeFolds)`.

- [ ] **Step 4: Run `make test`** — expect `** TEST SUCCEEDED **`, **172** tests passing (169 + 3 new).

### Subtask 3b: Update `composite_fs` shader

- [ ] **Step 5: Modify `Sources/Rendering/Shaders.metal`.** Find the existing `CompositeUniforms` struct:

```metal
struct CompositeUniforms {
    float intensity;
    float vignetteAmount;
    float grainAmount;
    float time;
};
```

Replace with:

```metal
struct CompositeUniforms {
    float intensity;
    float vignetteAmount;
    float grainAmount;
    float time;
    int kaleidoscopeFolds;     // 0 = off; 2..12 = N-fold mirror
};
```

Find the existing `composite_fs` body. Look for the lines that sample sceneTex / blurTex:

```metal
fragment float4 composite_fs(FSQOut in [[stage_in]],
                             texture2d<float> sceneTex [[texture(0)]],
                             texture2d<float> blurTex  [[texture(1)]],
                             sampler samp              [[sampler(0)]],
                             constant CompositeUniforms &u [[buffer(0)]]) {
    float3 scene = sceneTex.sample(samp, in.uv).rgb;
    float3 blur  = blurTex.sample(samp, in.uv).rgb;
    float3 color = scene + blur * u.intensity;
    ...
}
```

Replace the function body (everything between `{` and the matching closing `}`) with:

```metal
fragment float4 composite_fs(FSQOut in [[stage_in]],
                             texture2d<float> sceneTex [[texture(0)]],
                             texture2d<float> blurTex  [[texture(1)]],
                             sampler samp              [[sampler(0)]],
                             constant CompositeUniforms &u [[buffer(0)]]) {
    float2 uv = in.uv;

    // Kaleidoscope: fold the UV across N rotational symmetry segments around
    // the screen center. With folds = 0, the UV passes through unchanged.
    if (u.kaleidoscopeFolds > 0) {
        float2 c = uv - 0.5;
        float r = length(c);
        float angle = atan2(c.y, c.x);
        float foldAngle = (2.0 * M_PI_F) / float(u.kaleidoscopeFolds);
        float a = fmod(angle + 2.0 * M_PI_F, foldAngle);
        if (a > foldAngle * 0.5) a = foldAngle - a;
        uv = float2(cos(a) * r, sin(a) * r) + 0.5;
    }

    float3 scene = sceneTex.sample(samp, uv).rgb;
    float3 blur  = blurTex.sample(samp, uv).rgb;
    float3 color = scene + blur * u.intensity;

    if (u.vignetteAmount > 0.0) {
        float rv = length(in.uv * 2.0 - 1.0);
        float v = 1.0 - u.vignetteAmount * smoothstep(0.55, 1.1, rv);
        color *= v;
    }

    if (u.grainAmount > 0.0) {
        float n = grainHash(in.uv, u.time) - 0.5;
        color += n * u.grainAmount;
    }

    return float4(color, 1.0);
}
```

Note: vignette + grain use `in.uv` (raw, before kaleidoscope) so the vignette stays centered on the actual screen and grain doesn't tile through the folds.

### Subtask 3c: Update Swift `CompositeUniforms` mirror + builder

- [ ] **Step 6: Modify `Sources/Rendering/MetalRenderer.swift`.** Find the Swift `CompositeUniforms` struct (near the top of the file):

```swift
private struct CompositeUniforms {
    var intensity: Float
    var vignetteAmount: Float
    var grainAmount: Float
    var time: Float
}
```

Replace with (adds `kaleidoscopeFolds`):

```swift
private struct CompositeUniforms {
    var intensity: Float
    var vignetteAmount: Float
    var grainAmount: Float
    var time: Float
    var kaleidoscopeFolds: Int32
}
```

Find the `makeCompositeUniforms` helper:

```swift
    private func makeCompositeUniforms(intensity: Float, settings: VisualizerSettings) -> CompositeUniforms {
        let t = Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 1024))
        return CompositeUniforms(
            intensity: intensity,
            vignetteAmount: settings.vignetteAmount,
            grainAmount: settings.grainAmount,
            time: t
        )
    }
```

Replace with:

```swift
    private func makeCompositeUniforms(intensity: Float, settings: VisualizerSettings) -> CompositeUniforms {
        let t = Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 1024))
        return CompositeUniforms(
            intensity: intensity,
            vignetteAmount: settings.vignetteAmount,
            grainAmount: settings.grainAmount,
            time: t,
            kaleidoscopeFolds: Int32(max(0, min(12, settings.kaleidoscopeFolds)))
        )
    }
```

### Subtask 3d: Add the Settings UI slider

- [ ] **Step 7: Modify `Sources/App/SettingsView.swift`.** Find the existing "Post-process" Section inside `tweaksTab`:

```swift
            Section("Post-process") {
                Slider(value: $model.settings.vignetteAmount, in: 0...1) {
                    Text("Vignette")
                } minimumValueLabel: { Text("Off") } maximumValueLabel: { Text("Heavy") }
                Slider(value: $model.settings.grainAmount, in: 0...1) {
                    Text("Film grain")
                } minimumValueLabel: { Text("Off") } maximumValueLabel: { Text("Heavy") }
            }
```

Replace with (adds Kaleidoscope Stepper):

```swift
            Section("Post-process") {
                Slider(value: $model.settings.vignetteAmount, in: 0...1) {
                    Text("Vignette")
                } minimumValueLabel: { Text("Off") } maximumValueLabel: { Text("Heavy") }
                Slider(value: $model.settings.grainAmount, in: 0...1) {
                    Text("Film grain")
                } minimumValueLabel: { Text("Off") } maximumValueLabel: { Text("Heavy") }
                Stepper(model.settings.kaleidoscopeFolds == 0
                        ? "Kaleidoscope: Off"
                        : "Kaleidoscope: \(model.settings.kaleidoscopeFolds)-fold",
                        value: $model.settings.kaleidoscopeFolds, in: 0...12)
            }
```

- [ ] **Step 8: Run `make build`** — expect `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Run `make test`** — expect `** TEST SUCCEEDED **`, 172 tests passing.

- [ ] **Step 10: Launch check**

```bash
osascript -e 'quit app "MacVisualizer"' 2>/dev/null; pkill -x MacVisualizer 2>/dev/null; sleep 1
make run >/dev/null 2>&1 & sleep 3
pgrep -x MacVisualizer >/dev/null && echo "running ok"
osascript -e 'quit app "MacVisualizer"' 2>/dev/null; pkill -x MacVisualizer 2>/dev/null
```

Expect `running ok`. Kill the app at the end.

- [ ] **Step 11: Commit**

```bash
git add Sources/Core/VisualizerSettings.swift \
        Sources/Rendering/Shaders.metal \
        Sources/Rendering/MetalRenderer.swift \
        Sources/App/SettingsView.swift \
        Tests/CoreTests/VisualizerSettingsTests.swift
git commit -m "Kaleidoscope: N-fold UV mirror in composite_fs + Tweaks-tab Stepper (0..12)"
```

---

## Task 4: Live verification (user)

- [ ] **Step 1: Launch the app** — `make run`.

- [ ] **Step 2: Switch to plasma** — ⌘] until Plasma (10th in the list). Toggle Demo Mode (⌥⌘D). Full-screen colored plasma effect modulated by audio. Try changing palettes (Settings → Visualization → Color palette) — plasma colors update live.

- [ ] **Step 3: Switch to bumpscope** — ⌘] to Bumpscope. Heightfield illuminated by the spectrum. Tall bands cast lit ridges. Watch how the heightfield changes with the music. Try with `inferno` / `ember` palettes for hot ridges.

- [ ] **Step 4: Layer post-process on shader styles** — on Plasma:
  - Glow: bump intensity to ~1.0. Bright plasma cells halo.
  - Trails: bump persistence to ~0.7. Plasma should leave fading ghosts.
  - Vignette to ~0.3: corners darken.
  - Grain to ~0.15: film-grain noise overlay.
  All four post-process effects should layer cleanly on top of the shader output.

- [ ] **Step 5: Test kaleidoscope on every style** — Settings → Tweaks → Post-process → Kaleidoscope Stepper.
  - At 0: no change.
  - At 6: sixfold rotational mirror visible regardless of which style is active.
  - At 12: dense kaleidoscope.
  - Cycle ⌘] through styles with kaleidoscope at 6 → every style (bars, radial, particles, plasma, bumpscope, wireframe, etc.) appears symmetrically.

- [ ] **Step 6: Cycle wrap test** — ⌘] from Bumpscope wraps to Bars; ⌘[ from Bars wraps to Bumpscope.

- [ ] **Step 7: Persistence** — set Plasma + kaleidoscope=6 + palette=inferno, ⌘Q, `make run`. App should reopen on Plasma with the same kaleidoscope setting.

(Nothing to commit. If anything looks broken or off, capture the issue.)

---

## Definition of Done

- `make test` → `** TEST SUCCEEDED **`, **172** tests passing (164 + 5 style + 3 settings).
- `make build` → `** BUILD SUCCEEDED **`.
- Render probe with `plasma` and `bumpscope` produces non-zero PNGs.
- `VisualizerStyle.allCases.count == 11`; `.plasma.customShader == .plasma`; `.bumpscope.customShader == .bumpscope`.
- Live: plasma + bumpscope visible, audio-reactive; all 8 palettes work; bloom + trails + vignette + grain layer correctly on shader output; kaleidoscope works on every style with folds 2..12.
- `kaleidoscopeFolds` persists across relaunch via `settings.json`.

## Notes on implementation choices

- **No CPU-grid fallback** — per-pixel shaders unconditionally. Builds the right architecture; no kludge.
- **`customShader: ShaderKind?` on `VisualizerStyle`** — clean dispatch. Default nil for geometry styles; non-nil opts into the shader path.
- **Stub visualizer classes** — `PlasmaVisualizer` / `BumpscopeVisualizer` return `[]` and exist only to satisfy `makeVisualizer()`. The shader path bypasses geometry. Slightly odd but consistent.
- **Shader writes into trail/scene texture** — leverages all existing post-process (bloom, trails, vignette, grain, kaleidoscope). No special-case rendering for shader visualizers downstream of the scene-fill step.
- **Fixed-size tuples for uniform arrays** — Swift / Metal struct interop is most reliable when you control layout precisely. Tuples give predictable 4-byte-aligned packing for `Float` arrays.
- **Kaleidoscope inside `composite_fs`** — runs ONCE per frame as part of the existing composite, costs effectively nothing. Could be a separate pass but inlining is simpler and equally cheap.
- **Vignette + grain use raw `in.uv` (not kaleidoscoped)** — vignette stays centered on the actual screen, grain doesn't tile through folds. Subtle but important.
