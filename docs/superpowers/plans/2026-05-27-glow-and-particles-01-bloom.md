# Glow/Bloom Implementation Plan (Phase 2, Plan 1 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a toggleable neon glow/bloom post-process (with intensity control) applied to whichever visualizer is active.

**Architecture:** Blur-and-add bloom in three passes within one command buffer: render the visualizer geometry to an offscreen `sceneTexture`; blur it with `MPSImageGaussianBlur` into `blurTexture`; composite `scene + blur × intensity` to the destination via a fullscreen-triangle pass. When the Glow toggle is off, the existing single-pass-to-drawable path is used (zero overhead). The `RenderProbe` exercises the same bloom path for headless PNG verification.

**Tech Stack:** Metal, MetalKit, MetalPerformanceShaders (`MPSImageGaussianBlur`), SwiftUI, XCTest.

**Builds on:** the merged app. Spec: `docs/superpowers/specs/2026-05-27-glow-and-particles-design.md`. Verified Metal approach: MPS Gaussian blur out-of-place (separate destination texture); offscreen textures `bgra8Unorm`, usage `[.renderTarget, .shaderRead, .shaderWrite]`, storage `.private`; final composite into the destination pass descriptor; keep everything non-sRGB to avoid gamma mismatch; composite blending disabled; `framebufferOnly` default (true) is fine (we write the drawable, never sample it).

**Scope boundary — NOT here:** the particle field (Plan 8, separate).

---

## File Structure

```
mac-visualizer/
  Sources/
    Core/
      VisualizerSettings.swift      # MODIFY: add glowEnabled + glowIntensity (+ tolerant codec)
    Rendering/
      Shaders.metal                 # MODIFY: add fullscreen_vs + composite_fs
      MetalRenderer.swift           # MODIFY: composite pipeline, sampler, offscreen textures, MPS blur, renderBloom()
      RenderProbe.swift             # MODIFY: optional glow arg -> exercise renderBloom
      MetalView.swift               # MODIFY: use bloom path when glowEnabled; resize textures
    App/
      MacVisualizerApp.swift        # MODIFY: --render-probe glow arg parsing
      SettingsView.swift            # MODIFY: Glow section (toggle + intensity slider)
  Tests/
    CoreTests/
      VisualizerSettingsTests.swift # MODIFY: glow fields round-trip + partial-decode default
```

---

## Task 1: Add `glowEnabled` + `glowIntensity` settings

**Files:**
- Modify: `Sources/Core/VisualizerSettings.swift`
- Modify: `Tests/CoreTests/VisualizerSettingsTests.swift`

The struct has a tolerant hand-written `Codable` in an extension (CodingKeys + `init(from:)` + `encode(to:)`) and a synthesized memberwise init used by `defaults`. Both new fields must be added in all four places: the stored properties, `defaults`, the `CodingKeys`, `init(from:)`, and `encode(to:)`.

- [ ] **Step 1: Write the failing tests** — append to `VisualizerSettingsTests`:

```swift
    func testGlowDefaults() {
        XCTAssertTrue(VisualizerSettings.defaults.glowEnabled)
        XCTAssertEqual(VisualizerSettings.defaults.glowIntensity, 0.6, accuracy: 1e-6)
    }

    func testGlowRoundTrips() throws {
        var s = VisualizerSettings.defaults
        s.glowEnabled = false
        s.glowIntensity = 1.2
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.glowEnabled, false)
        XCTAssertEqual(decoded.glowIntensity, 1.2, accuracy: 1e-6)
        XCTAssertEqual(decoded, s)
    }

    func testPartialJSONDefaultsGlow() throws {
        let json = #"{ "gain": 2.0 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.gain, 2.0)
        XCTAssertTrue(decoded.glowEnabled)                 // defaulted
        XCTAssertEqual(decoded.glowIntensity, 0.6, accuracy: 1e-6) // defaulted
    }
```

- [ ] **Step 2: Run `make test`** — expect FAIL (`glowEnabled`/`glowIntensity` don't exist).

- [ ] **Step 3: Add the fields.** In `Sources/Core/VisualizerSettings.swift`:
  - Add as the LAST two stored properties (after `visualizerStyle`):
    ```swift
        // Glow / bloom
        public var glowEnabled: Bool
        public var glowIntensity: Float
    ```
  - In `static let defaults = VisualizerSettings(...)`, append `glowEnabled: true, glowIntensity: 0.6` as the last two arguments (matching property order).
  - In the extension's `CodingKeys`, add `case glowEnabled, glowIntensity` to the list.
  - In `init(from:)`, add as the last two arguments of the `self.init(...)` call:
    ```swift
            glowEnabled: try c.decodeIfPresent(Bool.self, forKey: .glowEnabled) ?? d.glowEnabled,
            glowIntensity: try c.decodeIfPresent(Float.self, forKey: .glowIntensity) ?? d.glowIntensity
    ```
  - In `encode(to:)`, add:
    ```swift
        try c.encode(glowEnabled, forKey: .glowEnabled)
        try c.encode(glowIntensity, forKey: .glowIntensity)
    ```

- [ ] **Step 4: Run `make test`** — expect `** TEST SUCCEEDED **`; the 3 new tests pass, existing settings tests still pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/VisualizerSettings.swift Tests/CoreTests/VisualizerSettingsTests.swift
git commit -m "Add glowEnabled and glowIntensity settings"
```

---

## Task 2: Bloom shaders + `MetalRenderer.renderBloom` (build only)

**Files:**
- Modify: `Sources/Rendering/Shaders.metal`
- Modify: `Sources/Rendering/MetalRenderer.swift`

No runtime output yet (nothing calls `renderBloom` until Task 3's probe). Verified here by the build; Task 3 PNG-verifies the actual glow.

- [ ] **Step 1: Add the bloom shaders** to `Sources/Rendering/Shaders.metal` (after the existing `vs_main`/`fs_main`):

```metal
// ---- Bloom post-processing ----
struct FSQOut {
    float4 position [[position]];
    float2 uv;
};

// Fullscreen triangle from vertex_id (no vertex buffer).
vertex FSQOut fullscreen_vs(uint vid [[vertex_id]]) {
    FSQOut out;
    float2 uv = float2(float((vid << 1) & 2), float(vid & 2)); // (0,0),(2,0),(0,2)
    out.uv = uv;
    out.position = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    return out;
}

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

- [ ] **Step 2: Extend `MetalRenderer`** (`Sources/Rendering/MetalRenderer.swift`):

(2a) Add imports at top: `import MetalPerformanceShaders` (in addition to the existing `import Metal`, `import MetalKit`, etc.).

(2b) Add stored properties (near the existing ones):
```swift
    private let compositePipeline: MTLRenderPipelineState?
    private let linearSampler: MTLSamplerState?
    private var sceneTexture: MTLTexture?
    private var blurTexture: MTLTexture?
    private var bloomWidth = 0
    private var bloomHeight = 0
    private let blurSigma: Float = 8
```

(2c) In `init?`, AFTER the existing geometry pipeline is built (it already has `library`, `device`, and `pixelFormat`), build the composite pipeline and sampler. Add before the final assignments:
```swift
        // Composite pipeline (fullscreen) for bloom.
        let cdesc = MTLRenderPipelineDescriptor()
        cdesc.vertexFunction = library.makeFunction(name: "fullscreen_vs")
        cdesc.fragmentFunction = library.makeFunction(name: "composite_fs")
        cdesc.colorAttachments[0].pixelFormat = pixelFormat
        self.compositePipeline = try? device.makeRenderPipelineState(descriptor: cdesc)

        let sdesc = MTLSamplerDescriptor()
        sdesc.minFilter = .linear
        sdesc.magFilter = .linear
        sdesc.sAddressMode = .clampToEdge
        sdesc.tAddressMode = .clampToEdge
        self.linearSampler = device.makeSamplerState(descriptor: sdesc)
```
(Assign `compositePipeline`/`linearSampler` as `let` stored properties — set them exactly once in `init`. Ensure they're initialized on every `init` path; if `library`/functions are already unwrapped earlier in `init`, reuse them. If a function lookup fails, `compositePipeline` becomes nil and bloom silently no-ops — acceptable.)

(2d) Add the offscreen-texture allocator:
```swift
    private func ensureBloomTextures(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        if width == bloomWidth, height == bloomHeight, sceneTexture != nil { return }
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead, .shaderWrite]
        d.storageMode = .private
        sceneTexture = device.makeTexture(descriptor: d)
        blurTexture = device.makeTexture(descriptor: d)
        bloomWidth = width
        bloomHeight = height
    }
```

(2e) Add `renderBloom` — orchestrates the three passes. It reuses the existing `encode(vertices:clearColor:into:commandBuffer:)` for the geometry pass into `sceneTexture`:
```swift
    /// Bloom path: geometry -> sceneTexture, MPS blur -> blurTexture, composite -> finalPass.
    /// `finalPass` is the destination (the drawable's pass for live, an offscreen pass for the probe).
    /// Caller presents/commits the command buffer.
    func renderBloom(vertices: [BarVertex],
                     clearColor: MTLClearColor,
                     intensity: Float,
                     finalPass: MTLRenderPassDescriptor,
                     width: Int,
                     height: Int,
                     commandBuffer: MTLCommandBuffer) {
        ensureBloomTextures(width: width, height: height)
        guard let sceneTexture, let blurTexture,
              let compositePipeline, let linearSampler else {
            // Bloom unavailable: fall back to a plain pass into finalPass.
            encode(vertices: vertices, clearColor: clearColor, into: finalPass, commandBuffer: commandBuffer)
            return
        }

        // Pass 1: geometry -> sceneTexture
        let scenePass = MTLRenderPassDescriptor()
        scenePass.colorAttachments[0].texture = sceneTexture
        encode(vertices: vertices, clearColor: clearColor, into: scenePass, commandBuffer: commandBuffer)

        // Pass 2: MPS Gaussian blur sceneTexture -> blurTexture
        let blur = MPSImageGaussianBlur(device: device, sigma: blurSigma)
        blur.edgeMode = .clamp
        blur.encode(commandBuffer: commandBuffer, sourceTexture: sceneTexture, destinationTexture: blurTexture)

        // Pass 3: composite (scene + blur*intensity) -> finalPass
        finalPass.colorAttachments[0].loadAction = .clear
        finalPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        finalPass.colorAttachments[0].storeAction = .store
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: finalPass) else { return }
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
Note: the existing `encode(...)` sets its own loadAction/clear/store on the descriptor it's given, so the geometry pass into `sceneTexture` clears + stores correctly.

- [ ] **Step 3: Build** — `make build` → `** BUILD SUCCEEDED **`. (The Metal toolchain compiles the new shaders; `MetalPerformanceShaders` links.) If `MPSImageGaussianBlur` or `.encode(commandBuffer:sourceTexture:destinationTexture:)` doesn't resolve on this SDK, report the EXACT error (BLOCKED) — do not substitute a guessed API.

- [ ] **Step 4: Run `make test`** — `** TEST SUCCEEDED **` (unchanged count; no new tests — bloom is GPU code).

- [ ] **Step 5: Commit**

```bash
git add Sources/Rendering/Shaders.metal Sources/Rendering/MetalRenderer.swift
git commit -m "Add bloom shaders and MetalRenderer.renderBloom (MPS blur + composite)"
```

---

## Task 3: Probe exercises bloom — PNG-verify the glow

**Files:**
- Modify: `Sources/Rendering/RenderProbe.swift`
- Modify: `Sources/App/MacVisualizerApp.swift`

- [ ] **Step 1: Add an optional `glow` arg to the probe.** In `MacVisualizerApp.swift`, update the `--render-probe` branch:
```swift
        if let idx = args.firstIndex(of: "--render-probe"), idx + 1 < args.count {
            let path = args[idx + 1]
            let style = (idx + 2 < args.count ? VisualizerStyle(rawValue: args[idx + 2]) : nil) ?? .bars
            let glow = args.contains("glow")
            let ok = RenderProbe.run(outputPath: path, style: style, glow: glow)
            exit(ok ? 0 : 1)
        }
```

- [ ] **Step 2: Apply bloom in `RenderProbe`.** Change `run` to `static func run(outputPath: String, style: VisualizerStyle = .bars, glow: Bool = false, width: Int = 800, height: Int = 400) -> Bool`. The probe currently builds `vertices` and calls `renderer.encode(vertices:clearColor:into:commandBuffer:)` with `pass` targeting its readback `texture`. Replace that single encode call with a branch:
```swift
        if glow {
            renderer.renderBloom(vertices: vertices,
                                 clearColor: MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                                 intensity: 0.9,
                                 finalPass: pass,
                                 width: width, height: height,
                                 commandBuffer: commandBuffer)
        } else {
            renderer.encode(vertices: vertices,
                            clearColor: MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                            into: pass, commandBuffer: commandBuffer)
        }
```
(`pass` is the probe's existing `MTLRenderPassDescriptor` whose `colorAttachments[0].texture` is the `.managed` readback `texture`. `renderBloom` writes the composite into it as its final pass. Keep the existing blit-synchronize + `writePNG` afterward unchanged.)

- [ ] **Step 3: Build, render with and without glow, INSPECT.**
Run: `make build` → `** BUILD SUCCEEDED **`. Then:
```bash
BIN=./DerivedData/Build/Products/Debug/MacVisualizer.app/Contents/MacOS/MacVisualizer
$BIN --render-probe /tmp/g_off.png radial && echo off=$?
$BIN --render-probe /tmp/g_on.png radial glow && echo on=$?
```
Read BOTH PNGs. Expected: `g_off.png` = the crisp radial burst (sharp bars). `g_on.png` = the SAME radial burst but with a soft luminous **halo/glow** around the bars (bright cores, blurred bleed into the dark background). The glow version should look noticeably softer/brighter around shapes while the original shapes remain visible. If `g_on.png` is identical to `g_off.png` (no glow), all-black, washed-out/blown-out, or vertically flipped vs `g_off.png`, report exactly what you saw (DONE_WITH_CONCERNS) with both images.
  - If FLIPPED (glow image upside-down relative to off): the fix is to flip the sampled v coordinate in `composite_fs` (sample at `float2(in.uv.x, 1.0 - in.uv.y)`); note this in your report and apply it.
  - If BLOWN OUT (mostly white): lower the probe `intensity` is NOT the fix — report it; it likely indicates a double-add or wrong blend.

- [ ] **Step 4: Run `make test`** — `** TEST SUCCEEDED **` (unchanged count).

- [ ] **Step 5: Commit**

```bash
git add Sources/Rendering/RenderProbe.swift Sources/App/MacVisualizerApp.swift
git commit -m "Render probe can apply bloom for headless glow verification"
```

---

## Task 4: Live bloom path in `MetalView`

**Files:**
- Modify: `Sources/Rendering/MetalView.swift`

- [ ] **Step 1: Use the bloom path when glow is enabled.** In `Coordinator.draw(in:)`, after computing `frame`, `vertices`, and `aspect`/`size`, replace the existing single encode+present+commit with:
```swift
            let w = Int(size.width), h = Int(size.height)
            let clear = renderer.clearColor(for: model.settings)
            if model.settings.glowEnabled, let finalPass = view.currentRenderPassDescriptor {
                renderer.renderBloom(vertices: vertices, clearColor: clear,
                                     intensity: model.settings.glowIntensity,
                                     finalPass: finalPass, width: w, height: h,
                                     commandBuffer: commandBuffer)
                commandBuffer.present(drawable)
                commandBuffer.commit()
            } else if let descriptor = view.currentRenderPassDescriptor {
                renderer.encode(vertices: vertices, clearColor: clear,
                                into: descriptor, commandBuffer: commandBuffer)
                commandBuffer.present(drawable)
                commandBuffer.commit()
            }
```
(Adapt to the exact local names already in `draw` — there is already a `drawable`, a `commandBuffer` from `renderer.makeCommandBuffer()`, and a `size`/`aspect`. Remove the old single-path present/commit so it isn't done twice. `renderBloom` recreates its offscreen textures when `w`/`h` change, so no separate resize wiring is needed; `mtkView(_:drawableSizeWillChange:)` may remain a no-op.)

- [ ] **Step 2: Build + test** — `make build` → `** BUILD SUCCEEDED **`; `make test` → `** TEST SUCCEEDED **`.

- [ ] **Step 3: Probe regression** — `--render-probe /tmp/g_bars.png bars` still shows the staircase (non-glow path intact).

- [ ] **Step 4: Launch check**
```bash
make run >/dev/null 2>&1 & sleep 3; pgrep -x MacVisualizer >/dev/null && echo "running ok"; osascript -e 'quit app "MacVisualizer"' 2>/dev/null || pkill -x MacVisualizer || true
```
Expect `running ok` (glow defaults on, so the live window now renders through the bloom path without crashing).

- [ ] **Step 5: Commit**

```bash
git add Sources/Rendering/MetalView.swift
git commit -m "Use bloom path in MetalView when glow is enabled"
```

---

## Task 5: Glow controls in Settings

**Files:**
- Modify: `Sources/App/SettingsView.swift`

- [ ] **Step 1: Add a Glow section.** In `SettingsView`'s `Form`, add (e.g. right after the "Visualization" section):
```swift
            Section("Glow") {
                Toggle("Enable glow", isOn: $model.settings.glowEnabled)
                Slider(value: $model.settings.glowIntensity, in: 0...1.5) {
                    Text("Intensity")
                } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1.5") }
            }
```

- [ ] **Step 2: Build + test** — `make build` → `** BUILD SUCCEEDED **`; `make test` → `** TEST SUCCEEDED **`.

- [ ] **Step 3: Live verification (requires the user)** — `make run` with music playing. Open ⌘, → Glow: toggle off → bars are crisp; toggle on → bars/shapes gain a soft neon halo; drag Intensity → glow strength changes live. Switch styles (⌘]) and confirm the glow applies to each (radial, oscilloscope especially pop). Quit & relaunch → glow settings persisted.
  - Agent: build, run the `radial glow` probe (Task 3) once more if helpful, confirm launch; report that live glow confirmation is pending the user.

- [ ] **Step 4: Commit**

```bash
git add Sources/App/SettingsView.swift
git commit -m "Add Glow controls (toggle + intensity) to Settings"
```

---

## Definition of Done (Plan 7 — Bloom)

- `make test` → `** TEST SUCCEEDED **` (3 new settings tests; ~91 total).
- `make build` → `** BUILD SUCCEEDED **`.
- `--render-probe /tmp/x.png radial glow` produces a visibly glowing radial burst (soft halo) vs the crisp non-glow version; bars probe (no glow) unchanged.
- `make run`: the Glow toggle + intensity slider change the on-screen look live across all styles; glow defaults on; settings persist. Confirmed by the user.

## Handoff to Plan 8 (Particle field)

Plan 8 adds the stateful `ParticleVisualizer` (bass-reactive starfield) and the `.particles` `VisualizerStyle` case. It renders into the same pipeline, so the bloom built here makes the stars glow automatically. The renderer's cached-visualizer slot keeps the particle state alive across frames.

## Notes on verification

Bloom is GPU/visual and can't be unit-tested; correctness comes from (1) the settings fields' unit tests, (2) the `--render-probe ... glow` PNG showing a real halo (inspected), and (3) the user confirming the live toggle/intensity across styles. The MPS blur API (`MPSImageGaussianBlur(device:sigma:)`, `.encode(commandBuffer:sourceTexture:destinationTexture:)`) and the texture-usage flags were research-verified but flagged as on-device-confirm; if a symbol fails to compile, the implementer reports BLOCKED rather than guessing.
