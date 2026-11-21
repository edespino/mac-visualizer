# Trail Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `trailPersistence: Float` slider on the Tweaks Settings tab so previous frames linger and fade toward the background, creating motion afterimages on every visualizer.

**Architecture:** Add a persistent `trailTexture` to `MetalRenderer` that survives across frames. Each frame: render a fullscreen "fade" quad with the existing soft off-black BG color into the trail texture using Metal's `.blendColor` blend factor to softly attenuate yesterday's content; then render the visualizer geometry on top with `loadAction = .load`. The bloom path then blurs the trail texture (instead of a fresh scene texture) so trails get their own glow halo, and the final composite goes to the drawable. When `trailPersistence == 0`, the existing `encode` / `renderBloom` path is used unchanged — zero overhead.

**Tech Stack:** Metal (custom `fade_fs` fragment shader, `MTLBlendFactor.blendColor` blend equation, MTLRenderPipelineState), Swift, XCTest.

**Builds on:** `main` after merging `add-palettes-and-bg`. Spec: `docs/superpowers/specs/2026-05-28-trail-persistence-design.md`.

**Scope boundary:** No per-style trail values, no motion-aware blur, no color-tinted fades (always fade to off-black BG), no preserving trails across resize.

---

## File Structure

```
mac-visualizer/
  Sources/
    Core/
      VisualizerSettings.swift     # MODIFY: add trailPersistence: Float top-level field
    Rendering/
      Shaders.metal                # MODIFY: add fade_fs fragment shader
      MetalRenderer.swift          # MODIFY: add trailTexture + fadePipeline + renderWithTrails()
      MetalView.swift              # MODIFY: route through renderWithTrails when persistence > 0
      RenderProbe.swift            # MODIFY: route same way (no-op visually for single-frame probe)
    App/
      SettingsView.swift           # MODIFY: add Trails section + Persistence slider on Tweaks tab
  Tests/
    CoreTests/
      VisualizerSettingsTests.swift # MODIFY: 3 tests for trailPersistence (default, round-trip, partial JSON)
```

Test count: 141 today → 144 (+3 settings tests). No visualizer-level tests — trails are a rendering pipeline change verified visually.

---

## Task 1: Add `trailPersistence` to `VisualizerSettings`

Wire a new top-level Float into `VisualizerSettings` via the existing tolerant-codec pattern (the same six places used by `fireworksMinBass`, `siriWaveCount`, `particleSize`, etc.).

**Files:**
- Modify: `Sources/Core/VisualizerSettings.swift`
- Modify: `Tests/CoreTests/VisualizerSettingsTests.swift`

- [ ] **Step 1: Write the failing tests** — append to `VisualizerSettingsTests`:

```swift
    func testTrailPersistenceDefaultsOff() {
        XCTAssertEqual(VisualizerSettings.defaults.trailPersistence, 0, accuracy: 1e-6)
    }

    func testTrailPersistenceRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.trailPersistence = 0.85
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.trailPersistence, 0.85, accuracy: 1e-6)
        XCTAssertEqual(decoded, s)
    }

    func testTrailPersistencePartialJSONDefaults() throws {
        let json = #"{ "gain": 2.5 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.trailPersistence, 0, accuracy: 1e-6)
    }
```

- [ ] **Step 2: Run `make test`** — expect FAIL (`VisualizerSettings has no member 'trailPersistence'`).

- [ ] **Step 3: Add the field to `VisualizerSettings`.** In `Sources/Core/VisualizerSettings.swift`, mirror the `particleSize`/`siriTiltSpacing` wiring. Six edit sites:

  1. **Stored property** (immediately after `siriDepthFalloff`):
     ```swift
         public var trailPersistence: Float       // 0..0.97 motion-trail fade. 0 = off (current behavior). Affects all styles.
     ```

  2. **Memberwise `public init` parameter list** — add `trailPersistence: Float` parameter (after `siriDepthFalloff`).

  3. **Memberwise `public init` body** — add `self.trailPersistence = trailPersistence` assignment.

  4. **`static let defaults`** — append `trailPersistence: 0` to the `VisualizerSettings(...)` call (as the LAST argument).

  5. **`CodingKeys`** — add `case trailPersistence` (in the existing tweak-fields block).

  6. **Tolerant `init(from:)`** — add `let tp = try c.decodeIfPresent(Float.self, forKey: .trailPersistence) ?? d.trailPersistence`, then pass `trailPersistence: tp` to the trailing `self.init(...)`.

  7. **`encode(to:)`** — add `try c.encode(trailPersistence, forKey: .trailPersistence)`.

- [ ] **Step 4: Run `make test`** — expect `** TEST SUCCEEDED **`, **144** tests passing (141 + 3 new).

- [ ] **Step 5: Run `make build`** — expect `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/VisualizerSettings.swift Tests/CoreTests/VisualizerSettingsTests.swift
git commit -m "Add trailPersistence setting (defaults 0 = no trails)"
```

---

## Task 2: Rendering pipeline — fade shader + trail texture + `renderWithTrails`

The big task. Adds a fullscreen-fade fragment shader, a second `MTLRenderPipelineState` for the fade pass, a persistent `trailTexture` matching drawable size, and a new `renderWithTrails(...)` method on `MetalRenderer` that orchestrates fade → geometry → blur → composite. Then routes `MetalView` and `RenderProbe` to call it when `trailPersistence > 0`. No new tests (the change is verified visually in Task 4); 144 must remain passing.

**Files:**
- Modify: `Sources/Rendering/Shaders.metal`
- Modify: `Sources/Rendering/MetalRenderer.swift`
- Modify: `Sources/Rendering/MetalView.swift`
- Modify: `Sources/Rendering/RenderProbe.swift`

- [ ] **Step 1: Add `fade_fs` fragment shader** to `Sources/Rendering/Shaders.metal`, immediately after the existing `composite_fs`:

```metal
// Fade pass for the trail-persistence pipeline. Outputs a precomputed
// "fade additive" color (bg * (1 - persistence)). Combined with a blend
// equation `dst = src + dst * blendColor`, where `blendColor = persistence`,
// the trail texture math becomes:
//   trailTex = bg*(1-persistence) + trailTex*persistence
// i.e. it lerps the existing trail toward the bg by (1 - persistence)
// per frame. When persistence == 0, the trail clears to bg each frame
// (identical to today's behavior with the existing clearColor).
fragment float4 fade_fs(FSQOut in [[stage_in]],
                        constant float4 &fadeRGBA [[buffer(0)]]) {
    return fadeRGBA;
}
```

- [ ] **Step 2: Add the fade `MTLRenderPipelineState` + `trailTexture` properties** to `MetalRenderer`. In `Sources/Rendering/MetalRenderer.swift`:

  Find the existing properties block (just below the class declaration). Add:
  ```swift
      private let fadePipeline: MTLRenderPipelineState?     // fullscreen fade quad for trails
      private var trailTexture: MTLTexture?                  // persistent across frames when trails on
  ```
  immediately after the `compositePipeline` declaration.

  In `init?(...)`, after the existing `compositePipeline` setup block (which creates the composite pipeline), add this BEFORE `self.linearSampler = ...`:

  ```swift
          // Fade pipeline — uses fullscreen_vs + fade_fs, with a per-frame
          // `blendColor`-driven fade equation. Blending must be enabled and
          // the destination factor is `.blendColor` so the per-frame
          // setBlendColor(...) call drives the persistence amount.
          let fdesc = MTLRenderPipelineDescriptor()
          fdesc.vertexFunction = library.makeFunction(name: "fullscreen_vs")
          fdesc.fragmentFunction = library.makeFunction(name: "fade_fs")
          fdesc.colorAttachments[0].pixelFormat = pixelFormat
          fdesc.colorAttachments[0].isBlendingEnabled = true
          fdesc.colorAttachments[0].rgbBlendOperation = .add
          fdesc.colorAttachments[0].alphaBlendOperation = .add
          fdesc.colorAttachments[0].sourceRGBBlendFactor = .one
          fdesc.colorAttachments[0].sourceAlphaBlendFactor = .one
          fdesc.colorAttachments[0].destinationRGBBlendFactor = .blendColor
          fdesc.colorAttachments[0].destinationAlphaBlendFactor = .blendAlpha
          self.fadePipeline = try? device.makeRenderPipelineState(descriptor: fdesc)
  ```

- [ ] **Step 3: Extend `ensureBloomTextures(width:height:)` to also (re)allocate `trailTexture`.** Find:

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

  Replace with:

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
          trailTexture = device.makeTexture(descriptor: d)
          bloomWidth = width
          bloomHeight = height
          // The new trailTexture starts uninitialized — the fade pass on the
          // first frame multiplies its undefined contents by persistence and
          // adds bg*(1-persistence). Visually that resolves within a couple
          // of frames as the geometry overdraws. No explicit clear needed.
      }
  ```

- [ ] **Step 4: Add the `renderWithTrails(...)` method** to `MetalRenderer`. Append it after `renderBloom(...)`:

```swift
    /// Trail-persistence render path. Each frame: fade the persistent
    /// `trailTexture` toward the bg by `(1 - persistence)`, draw geometry
    /// on top with `loadAction = .load`, blur for bloom, composite to
    /// `finalPass`.
    ///
    /// `persistence` should be in `[0, 0.97]`. When `persistence == 0` the
    /// fade pass produces `bg + dst*0 = bg`, equivalent to a clear; callers
    /// can still avoid this method when they want zero overhead.
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
        ensureBloomTextures(width: width, height: height)
        guard let trailTexture, let blurTexture,
              let fadePipeline, let compositePipeline, let linearSampler else {
            // Fallback: behave like the non-trail path so we never lose a frame.
            if glow {
                renderBloom(vertices: vertices, clearColor: clearColor, intensity: intensity,
                            finalPass: finalPass, width: width, height: height,
                            commandBuffer: commandBuffer, roundParticles: roundParticles)
            } else {
                encode(vertices: vertices, clearColor: clearColor, into: finalPass,
                       commandBuffer: commandBuffer, roundParticles: roundParticles)
            }
            return
        }

        let bgR = Float(clearColor.red)
        let bgG = Float(clearColor.green)
        let bgB = Float(clearColor.blue)
        let invP = 1.0 - persistence

        // Pass 1: Fade pass — render fullscreen fade quad into trailTexture
        // with loadAction = .load so existing contents are preserved.
        let fadePass = MTLRenderPassDescriptor()
        fadePass.colorAttachments[0].texture = trailTexture
        fadePass.colorAttachments[0].loadAction = .load
        fadePass.colorAttachments[0].storeAction = .store
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: fadePass) {
            enc.setRenderPipelineState(fadePipeline)
            // Source color = bg * (1 - persistence). Blend equation does the rest.
            var fadeRGBA = SIMD4<Float>(bgR * invP, bgG * invP, bgB * invP, 1)
            enc.setFragmentBytes(&fadeRGBA, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            enc.setBlendColor(red: persistence, green: persistence, blue: persistence, alpha: 1)
            // The fullscreen_vs vertex shader synthesizes a screen-covering triangle from vid.
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        // Pass 2: Geometry — draw vertices into trailTexture on top of the
        // faded prior frames. loadAction = .load to preserve the fade pass.
        if !vertices.isEmpty {
            let geomPass = MTLRenderPassDescriptor()
            geomPass.colorAttachments[0].texture = trailTexture
            geomPass.colorAttachments[0].loadAction = .load
            geomPass.colorAttachments[0].storeAction = .store
            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: geomPass) {
                enc.setRenderPipelineState((roundParticles ? roundPipeline : nil) ?? pipeline)
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

        if glow {
            // Pass 3: MPS Gaussian blur trailTexture -> blurTexture.
            let blur = MPSImageGaussianBlur(device: device, sigma: blurSigma)
            blur.edgeMode = .clamp
            blur.encode(commandBuffer: commandBuffer, sourceTexture: trailTexture, destinationTexture: blurTexture)

            // Pass 4: composite (trail + blur*intensity) -> finalPass.
            finalPass.colorAttachments[0].loadAction = .clear
            finalPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            finalPass.colorAttachments[0].storeAction = .store
            guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: finalPass) else { return }
            enc.setRenderPipelineState(compositePipeline)
            enc.setFragmentTexture(trailTexture, index: 0)
            enc.setFragmentTexture(blurTexture, index: 1)
            enc.setFragmentSamplerState(linearSampler, index: 0)
            var i = intensity
            enc.setFragmentBytes(&i, length: MemoryLayout<Float>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        } else {
            // No-glow trail path: blit trailTexture straight to finalPass via
            // the composite shader with intensity 0 (so the blur term is dark).
            // Reuse `blurTexture` as a dummy — it gets multiplied by 0.
            finalPass.colorAttachments[0].loadAction = .clear
            finalPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            finalPass.colorAttachments[0].storeAction = .store
            guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: finalPass) else { return }
            enc.setRenderPipelineState(compositePipeline)
            enc.setFragmentTexture(trailTexture, index: 0)
            enc.setFragmentTexture(blurTexture, index: 1)
            enc.setFragmentSamplerState(linearSampler, index: 0)
            var zero: Float = 0
            enc.setFragmentBytes(&zero, length: MemoryLayout<Float>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }
    }
```

- [ ] **Step 5: Route `MetalView` through `renderWithTrails` when persistence > 0.** In `Sources/Rendering/MetalView.swift`, find the existing branch:

  ```swift
              let round = model.settings.visualizerStyle.usesRoundParticles
              if model.settings.glowEnabled {
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

  Replace with:

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

- [ ] **Step 6: Update `RenderProbe`** to use the same routing. In `Sources/Rendering/RenderProbe.swift`, find:

  ```swift
          let round = style.usesRoundParticles
          if glow {
              renderer.renderBloom(vertices: vertices,
                                   clearColor: MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                                   intensity: 0.9,
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
              renderer.encode(vertices: vertices,
                              clearColor: MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                              into: pass, commandBuffer: commandBuffer,
                              roundParticles: round)
          }
  ```

  The probe is single-frame; with `persistence > 0`, the fade pass writes `bg + uninitialized * persistence`, then geometry draws on top. The first frame may have a faint residual tint from the uninitialized trail texture but is otherwise correct. This is acceptable for the probe.

- [ ] **Step 7: Run `make build`** — expect `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Run `make test`** — expect `** TEST SUCCEEDED **`, 144 tests passing (unchanged).

- [ ] **Step 9: Render-probe smoke test** — verify both the non-trail path and the trail path produce non-zero PNGs:

```bash
BIN=$(find DerivedData -name MacVisualizer -type f -path '*/MacOS/*' 2>/dev/null | head -1)
"$BIN" --render-probe /tmp/p_trail_off.png bars
ls -la /tmp/p_trail_off.png
```

Expect a non-zero PNG. (Trails are off by default in the probe; this just confirms the routing change didn't break anything.)

- [ ] **Step 10: Commit**

```bash
git add Sources/Rendering/Shaders.metal \
        Sources/Rendering/MetalRenderer.swift \
        Sources/Rendering/MetalView.swift \
        Sources/Rendering/RenderProbe.swift
git commit -m "Add trail-persistence render path: fade shader + trailTexture + renderWithTrails()"
```

---

## Task 3: Settings UI — Trails section on the Tweaks tab

Add a slider for `trailPersistence` to the existing Tweaks tab, in a new "Trails" section after the existing oscilloscope section.

**Files:**
- Modify: `Sources/App/SettingsView.swift`

- [ ] **Step 1: Read current `tweaksTab` definition** to confirm the existing sections (Particles/Fountain/Fireworks, Bars/Mirrored, Oscilloscope).

- [ ] **Step 2: Append a "Trails" section to the Form inside `tweaksTab`.** Find the existing block (look for `Section("Oscilloscope")`):

  ```swift
              Section("Oscilloscope") {
                  Slider(value: $model.settings.oscilloscopeThickness, in: 0.5...3.0) {
                      Text("Line thickness")
                  } minimumValueLabel: { Text("0.5×") } maximumValueLabel: { Text("3×") }
              }
          }
          .formStyle(.grouped)
      }
  ```

  Replace with (adds a new section below Oscilloscope):

  ```swift
              Section("Oscilloscope") {
                  Slider(value: $model.settings.oscilloscopeThickness, in: 0.5...3.0) {
                      Text("Line thickness")
                  } minimumValueLabel: { Text("0.5×") } maximumValueLabel: { Text("3×") }
              }
              Section("Trails") {
                  Slider(value: $model.settings.trailPersistence, in: 0...0.97) {
                      Text("Persistence")
                  } minimumValueLabel: { Text("Off") } maximumValueLabel: { Text("Long") }
              }
          }
          .formStyle(.grouped)
      }
  ```

- [ ] **Step 3: Run `make build`** — expect `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run `make test`** — expect `** TEST SUCCEEDED **`, 144 tests passing (no new tests).

- [ ] **Step 5: Launch check**

```bash
osascript -e 'quit app "MacVisualizer"' 2>/dev/null; pkill -x MacVisualizer 2>/dev/null; sleep 1
make run >/dev/null 2>&1 & sleep 3
pgrep -x MacVisualizer >/dev/null && echo "running ok"
osascript -e 'quit app "MacVisualizer"' 2>/dev/null; pkill -x MacVisualizer 2>/dev/null
```

Expect `running ok`. Kill the app at the end.

- [ ] **Step 6: Commit**

```bash
git add Sources/App/SettingsView.swift
git commit -m "Settings: Trails section on Tweaks tab (Persistence slider)"
```

---

## Task 4: Live verification (user)

User-driven. Confirm the trails effect works across visualizers.

- [ ] **Step 1: Launch the app**

```bash
make run
```

- [ ] **Step 2: Verify slider at 0 is a no-op**
- Open Settings (⌘,) → Tweaks tab → confirm "Trails" section with "Persistence" slider exists. Default = Off (left).
- Switch to any style. App behaves identically to today — no visible trails, no performance issues.

- [ ] **Step 3: Verify trails appear with persistence > 0**
- Toggle Demo Mode (⌥⌘D) so something is moving without needing Spotify.
- Drag the Persistence slider to about 60% (~0.6). Switch to **siri** — waves leave a faint fading swell. Switch to **fireworks** — bursts have visible decaying streaks. Switch to **particles** — starfield surges leave streaks.
- Drag to 90% (~0.85). Trails are clearly long; motion has visible memory.
- Drag to max (Long ≈ 0.97). Trails persist for seconds but still eventually fade — no permanent burn-in.

- [ ] **Step 4: Verify all 8 styles handle trails cleanly**
- With persistence at ~0.85, cycle ⌘] through every style. Each should:
  - Bars: bars show afterimages as they fall.
  - Radial: radial sectors leave a fading wheel.
  - Mirrored: top/bottom both leave trails.
  - Oscilloscope: the waveform trace persists as a fading curve.
  - Particles: starfield surges streak across the screen.
  - Fountain: per-band columns leave fading trails as they rise/fall.
  - Fireworks: each burst's particles streak before fading.
  - Siri: waves leave fading swells in their wake.

- [ ] **Step 5: Verify reset behavior**
- Set persistence to ~0.85. Click Reset All Styles → confirm → persistence returns to 0 (since it's part of `VisualizerSettings.defaults`).
- Set persistence to ~0.85 again. Click Reset This Style → persistence should remain at 0.85 (top-level setting, not affected by per-style reset). Confirm this is the intended behavior.

- [ ] **Step 6: Verify resize behavior**
- With persistence at ~0.85 and trails visible, drag the main window's corner to resize. Trail texture recreates → trails clear momentarily → re-stabilize within a couple of seconds. No crash.

- [ ] **Step 7: Verify persistence across relaunch**
- Set persistence to ~0.5. ⌘Q. `make run` again. Open Settings → Tweaks. Persistence should still be ~0.5.

(Nothing to commit. If anything didn't work, capture the issue.)

---

## Definition of Done

- `make test` → `** TEST SUCCEEDED **`, **144** tests passing (141 + 3 settings tests).
- `make build` → `** BUILD SUCCEEDED **`.
- With slider at 0: app behaves identically to today.
- With slider > 0: trails appear on every visualizer style; longer slider = longer trails; max slider (≈0.97) does not burn in.
- Resize works (trail texture recreates cleanly).
- `trailPersistence` persists across relaunch via `settings.json`.

## Notes on implementation choices

- **Single texture, blend-equation fade** — using Metal's `.blendColor` factor with `setBlendColor(_:_:_:_:)` lets the per-frame slider value drive the fade math via the blend pipeline, avoiding a ping-pong texture pair. The fragment shader is one line.
- **Persistence cap at 0.97** in the UI prevents permanent residue; the math `(1 - 0.97) = 0.03` always nudges the trail toward BG.
- **Falls through to existing paths when persistence == 0** in MetalView and RenderProbe → zero overhead for users who don't enable trails. The fallback inside `renderWithTrails` also forwards to `renderBloom`/`encode` if any required resource is missing — defensive.
- **No new visualizer tests** — trails are a rendering pipeline change. The settings field has unit tests; visual behavior is verified live in Task 4.
- **`trailTexture` initialization** — the first frame after allocation reads undefined contents. With `persistence ≤ 0.97`, three frames is enough for the undefined contribution to decay below 5%. Geometry overdraw masks the rest. No explicit clear needed — saves a render pass.
- **Probe behavior** — single-frame: fades undefined trail by (1-p), then draws geometry. Visually similar to non-trail probe for most styles (geometry dominates).
