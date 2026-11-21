# Mac Music Visualizer — Plan 5: Settings UI + Live Reconfigure

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A SwiftUI Settings window that makes `VisualizerSettings` editable live (palette, sensitivity, overlay, window/display), persisting changes; plus the deferred analyzer reconfigure (sample rate + bar count) and `MTLBuffer` pooling carry-forwards.

**Architecture:** Add a `reconfigure(sampleRate:barCount:)` to the pure `SpectrumAnalyzer` (rebuild its `BandMapper`/`BandPostProcessor`; unit-tested). `RenderModel` observes its `@Published settings` (Combine): applies gain/smoothing/peak-hold and bar-count changes to the analyzer on the DSP queue, uses the capture-delivered sample rate (the Plan 3 carry-forward), and persists settings (debounced). A SwiftUI `Settings` scene (⌘,) binds a `Form` to `model.settings`. `MetalRenderer` reuses a pooled vertex buffer instead of allocating per draw.

**Tech Stack:** Swift 5.10, SwiftUI (`Settings` scene, `Form`, bindings), Combine, Metal, Accelerate (existing), XCTest.

**Builds on Plans 1–4 (merged):** `VisualizerSettings` (all fields + `save`/`load`), `SpectrumAnalyzer` (`append`, `update(gain:smoothing:peakHoldEnabled:)`), `SyntheticFrameSource`, `RenderModel` (capture → analyzer → box, synthetic fallback), `MetalRenderer.encode`, `MacVisualizerMain`/`ContentView`.

**Resolves carry-forwards:** Plan 3 — `RenderModel` currently pins the analyzer to 48000 and discards the capture-delivered rate; this plan reconfigures the analyzer to the delivered rate and on bar-count change. Plan 2 — `MetalRenderer.encode` allocates a new `MTLBuffer` every draw; this plan pools it.

**Scope boundary — intentionally NOT included (documented as remaining):** custom palette color editing (preset picker only), the background-gradient render (the `backgroundStyle` setting stays effectively solid; no UI control for it here), and per-monitor fullscreen selection (`fullscreenDisplayID`). These are noted in the Definition of Done as the final remaining polish.

---

## File Structure

```
mac-visualizer/
  Sources/
    Core/
      SpectrumAnalyzer.swift     # MODIFY: make rate/mapper/post mutable; add reconfigure(sampleRate:barCount:)
    Rendering/
      MetalRenderer.swift        # MODIFY: pool the vertex MTLBuffer (grow-only)
    App/
      RenderModel.swift          # MODIFY: Combine-observe settings -> apply live + persist; use delivered sample rate
      SettingsView.swift         # CREATE: SwiftUI Form bound to settings
      MacVisualizerApp.swift     # MODIFY: add a Settings scene (⌘,)
  Tests/
    CoreTests/
      SpectrumAnalyzerReconfigureTests.swift   # CREATE
```

**Decomposition rationale:** the reconfigure logic is pure and unit-tested in Core. Live application + persistence is in `RenderModel`. The `Form` is a pure SwiftUI view bound to the settings. The buffer pool is an isolated rendering change verified by the render probe.

---

## Task 1: `SpectrumAnalyzer.reconfigure(sampleRate:barCount:)` (Core, TDD)

**Files:**
- Modify: `Sources/Core/SpectrumAnalyzer.swift`
- Test: `Tests/CoreTests/SpectrumAnalyzerReconfigureTests.swift`

Background: the analyzer currently stores `sampleRate`, `mapper`, `post` as `let`, fixed at init. To support changing the captured sample rate and the bar count at runtime, make them `var` (plus track `barCount`) and add a `reconfigure` that rebuilds the `BandMapper` (depends on barCount + fftSize + sampleRate) and `BandPostProcessor` (depends on barCount), preserving the current gain/smoothing/peakDecay. The Hann `window` and `FFTProcessor` depend only on `fftSize` (unchanged) — do NOT rebuild them.

- [ ] **Step 1: Write the failing test**

`Tests/CoreTests/SpectrumAnalyzerReconfigureTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class SpectrumAnalyzerReconfigureTests: XCTestCase {
    private func analyzer(bands: Int = 24, sr: Float = 48000) -> SpectrumAnalyzer {
        var s = VisualizerSettings.defaults
        s.barCount = bands
        s.gain = 1
        s.smoothing = 0
        return SpectrumAnalyzer(fftSize: 2048, sampleRate: sr, settings: s)
    }

    func testReconfigureBarCountChangesEmittedBandCount() {
        let a = analyzer(bands: 24)
        XCTAssertEqual(a.append(SignalGenerators.silence(count: 2048))!.bands.count, 24)
        a.reconfigure(barCount: 48)
        XCTAssertEqual(a.append(SignalGenerators.silence(count: 2048))!.bands.count, 48)
    }

    func testReconfigureSampleRateShiftsToneBand() {
        // The signal is a fixed 1 kHz tone sampled at 48 kHz (FFT bin ~43, fixed).
        // Telling the mapper the rate is higher labels that bin as a higher frequency,
        // so the tone lands in a HIGHER band index.
        let a = analyzer(bands: 32, sr: 48000)
        let tone = SignalGenerators.sine(frequency: 1000, sampleRate: 48000, count: 2048)
        let bandAt48k = SignalGenerators.argmax(a.append(tone)!.bands)

        a.reconfigure(sampleRate: 96000)
        let bandAt96k = SignalGenerators.argmax(a.append(tone)!.bands)

        XCTAssertGreaterThan(bandAt96k, bandAt48k)
    }

    func testReconfigureAfterUpdateWorks() {
        // Reconfiguring after update() must not crash or zero things out, and must
        // honor the new bar count while still producing output.
        let a = analyzer(bands: 8)
        a.update(gain: 3, smoothing: 0.5, peakHoldEnabled: true)
        a.reconfigure(barCount: 16)
        let frame = a.append(SignalGenerators.sine(frequency: 2000, sampleRate: 48000, count: 2048))!
        XCTAssertEqual(frame.bands.count, 16)
        XCTAssertGreaterThan(frame.bands.max() ?? 0, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `value of type 'SpectrumAnalyzer' has no member 'reconfigure'`.

- [ ] **Step 3: Modify `SpectrumAnalyzer`**

In `Sources/Core/SpectrumAnalyzer.swift`:

(3a) Change the stored-property declarations. Find:

```swift
    private let fftSize: Int
    private let sampleRate: Float
    private let window: [Float]
    private let fft: FFTProcessor
    private let mapper: BandMapper
    private let post: BandPostProcessor
```

Replace with:

```swift
    private let fftSize: Int
    private var sampleRate: Float
    private var barCount: Int
    private let window: [Float]
    private let fft: FFTProcessor
    private var mapper: BandMapper
    private var post: BandPostProcessor
```

(3b) In `init`, set `barCount`. Find the line that creates the mapper in init (it uses `settings.barCount`); just before it, add:

```swift
        self.barCount = settings.barCount
```

(Keep the existing `self.mapper = BandMapper(bandCount: settings.barCount, ...)` and `self.post = BandPostProcessor(bandCount: settings.barCount, ...)` lines as they are.)

(3c) Add the `reconfigure` method (place it right after the existing `update(gain:smoothing:peakHoldEnabled:)` method):

```swift
    /// Rebuild the band mapper / post-processor for a new sample rate and/or bar count.
    /// Preserves the current gain/smoothing/peak-hold. The FFT and window are unaffected
    /// (they depend only on fftSize). Call on the same queue as `append`.
    public func reconfigure(sampleRate newRate: Float? = nil, barCount newBarCount: Int? = nil) {
        if let r = newRate { sampleRate = r }
        if let b = newBarCount { barCount = b }
        mapper = BandMapper(bandCount: barCount, fftSize: fftSize, sampleRate: sampleRate)
        post = BandPostProcessor(bandCount: barCount,
                                 gain: post.gain,
                                 smoothing: post.smoothing,
                                 peakDecay: post.peakDecay)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test`
Expected: `** TEST SUCCEEDED **`, the 3 new tests pass and all existing tests still pass (total 65).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/SpectrumAnalyzer.swift Tests/CoreTests/SpectrumAnalyzerReconfigureTests.swift
git commit -m "Add SpectrumAnalyzer.reconfigure for live sample-rate and bar-count changes"
```

---

## Task 2: Pool the vertex `MTLBuffer` in `MetalRenderer` (Plan 2 carry-forward)

**Files:**
- Modify: `Sources/Rendering/MetalRenderer.swift`

Replace the per-draw `device.makeBuffer(bytes:...)` with a reusable, grow-only buffer that is reallocated only when a larger one is needed, then filled with `memcpy` each draw.

- [ ] **Step 1: Add a pooled buffer property and use it in `encode`**

In `Sources/Rendering/MetalRenderer.swift`:

(1a) Add a stored property to the class (near the other stored properties):

```swift
    private var vertexBuffer: MTLBuffer?
    private var vertexBufferCapacity = 0
```

(1b) In `encode(...)`, replace this block:

```swift
        if !vertices.isEmpty {
            let length = vertices.count * MemoryLayout<BarVertex>.stride
            // Use a buffer (not setVertexBytes, which caps at 4 KB): at 48 bars with
            // caps the vertex data is ~18 KB.
            let buffer = vertices.withUnsafeBytes { raw in
                device.makeBuffer(bytes: raw.baseAddress!, length: length, options: .storageModeShared)
            }
            if let buffer {
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
            }
        }
        encoder.endEncoding()
```

with:

```swift
        if !vertices.isEmpty {
            let length = vertices.count * MemoryLayout<BarVertex>.stride
            // Grow-only pooled buffer: reallocate only when a larger one is needed,
            // then memcpy each frame (avoids a per-draw allocation in the render loop).
            if vertexBuffer == nil || vertexBufferCapacity < length {
                vertexBuffer = device.makeBuffer(length: length, options: .storageModeShared)
                vertexBufferCapacity = length
            }
            if let buffer = vertexBuffer {
                vertices.withUnsafeBytes { raw in
                    memcpy(buffer.contents(), raw.baseAddress!, length)
                }
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
            }
        }
        encoder.endEncoding()
```

- [ ] **Step 2: Build**

Run: `make build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Render-probe regression**

```bash
./DerivedData/Build/Products/Debug/MacVisualizer.app/Contents/MacOS/MacVisualizer --render-probe /tmp/probe_p5.png && echo "exit=$?"
```
Read `/tmp/probe_p5.png`: must STILL show the left→right green→red staircase with caps (the pooled buffer must produce identical output). If it's blank or garbled, the memcpy/length is wrong — report it (DONE_WITH_CONCERNS) rather than reverting silently.

- [ ] **Step 4: Run unit tests**

Run: `make test`
Expected: `** TEST SUCCEEDED **`, total 65.

- [ ] **Step 5: Commit**

```bash
git add Sources/Rendering/MetalRenderer.swift
git commit -m "Pool the vertex MTLBuffer instead of allocating per draw"
```

Note: `MetalRenderer` instances are confined to one consumer each (one for the live `MTKView`, a separate one created in the render probe), so the single pooled buffer has a single writer — no synchronization needed.

---

## Task 3: `RenderModel` — apply settings live, use delivered sample rate, persist

**Files:**
- Modify: `Sources/App/RenderModel.swift`

`RenderModel` observes its own `@Published settings` via Combine: immediately applies gain/smoothing/peak-hold and bar-count to the analyzer on the DSP queue, and persists (debounced). The capture callback reconfigures the analyzer when the delivered sample rate differs from the analyzer's current rate (the Plan 3 carry-forward). The synthetic fallback frame is built from the current `settings.barCount` so it matches live bar-count changes.

- [ ] **Step 1: Rewrite `Sources/App/RenderModel.swift`**

Replace the ENTIRE contents with:

```swift
import SwiftUI
import QuartzCore
import Combine
import MacVisualizerCore

/// Drives rendering from real captured audio (synthetic fallback) and applies live
/// settings changes to the analyzer, persisting them.
final class RenderModel: ObservableObject {
    @Published var settings: VisualizerSettings
    @Published private(set) var captureState: CaptureState = .stopped

    private let analyzer: SpectrumAnalyzer
    private let box = LatestFrameBox()
    private let capture: AudioCaptureSource
    private let dsp = DispatchQueue(label: "visualizer.dsp")
    private var cancellables = Set<AnyCancellable>()

    // DSP-queue-confined state.
    private var currentBarCount: Int
    private var currentSampleRate: Float

    init(capture: AudioCaptureSource = AudioCaptureService()) {
        let loaded = VisualizerSettings.load(from: VisualizerSettings.defaultFileURL())
        self.settings = loaded
        self.analyzer = SpectrumAnalyzer(fftSize: 2048, sampleRate: 48000, settings: loaded)
        self.capture = capture
        self.currentBarCount = loaded.barCount
        self.currentSampleRate = 48000

        capture.onSamples = { [weak self] samples, rate in
            guard let self else { return }
            self.dsp.async {
                if Float(rate) > 0, abs(Float(rate) - self.currentSampleRate) > 1 {
                    self.currentSampleRate = Float(rate)
                    self.analyzer.reconfigure(sampleRate: Float(rate))
                }
                if let frame = self.analyzer.append(samples) {
                    self.box.store(frame, at: CACurrentMediaTime())
                }
            }
        }
        capture.start()
        captureState = capture.state

        // Apply settings changes live (immediate) and persist (debounced).
        $settings
            .dropFirst()
            .sink { [weak self] s in self?.applyLive(s) }
            .store(in: &cancellables)

        $settings
            .dropFirst()
            .debounce(for: .seconds(0.4), scheduler: DispatchQueue.global(qos: .utility))
            .sink { s in try? s.save(to: VisualizerSettings.defaultFileURL()) }
            .store(in: &cancellables)
    }

    private func applyLive(_ s: VisualizerSettings) {
        dsp.async {
            self.analyzer.update(gain: s.gain, smoothing: s.smoothing, peakHoldEnabled: s.peakHoldEnabled)
            if s.barCount != self.currentBarCount {
                self.currentBarCount = s.barCount
                self.analyzer.reconfigure(barCount: s.barCount)
            }
        }
    }

    /// The frame to render right now: real audio if flowing recently, else synthetic
    /// (built from the current bar count so it tracks live settings changes).
    func currentFrame() -> AudioFrame {
        let now = CACurrentMediaTime()
        if capture.state == .running, let frame = box.recent(now: now, maxAge: 0.5) {
            return frame
        }
        return SyntheticFrameSource(bandCount: settings.barCount).frame(at: now)
    }

    deinit { capture.stop() }
}
```

- [ ] **Step 2: Build**

Run: `make build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run unit tests**

Run: `make test`
Expected: `** TEST SUCCEEDED **`, total 65.

- [ ] **Step 4: Render-probe regression**

```bash
./DerivedData/Build/Products/Debug/MacVisualizer.app/Contents/MacOS/MacVisualizer --render-probe /tmp/probe_p5b.png && echo "exit=$?"
```
Read it: still the staircase (the probe doesn't use RenderModel, but confirms nothing broke the build/render path).

- [ ] **Step 5: Confirm the app launches without crashing**

```bash
make run >/dev/null 2>&1 & sleep 3; pgrep -x MacVisualizer >/dev/null && echo "running ok"; osascript -e 'quit app "MacVisualizer"' 2>/dev/null || pkill -x MacVisualizer || true
```
Expect `running ok`.

- [ ] **Step 6: Commit**

```bash
git add Sources/App/RenderModel.swift
git commit -m "Apply settings live, use delivered sample rate, persist settings"
```

---

## Task 4: `SettingsView` + Settings scene (⌘,)

**Files:**
- Create: `Sources/App/SettingsView.swift`
- Modify: `Sources/App/MacVisualizerApp.swift` (add a `Settings` scene)

- [ ] **Step 1: Create `Sources/App/SettingsView.swift`**

```swift
import SwiftUI
import MacVisualizerCore

/// The preferences Form, bound to the live `VisualizerSettings` on RenderModel.
struct SettingsView: View {
    @ObservedObject var model: RenderModel

    private let palettes = ["classic", "phosphor", "synthwave"]
    private let fpsOptions = [30, 60, 120]

    var body: some View {
        Form {
            Section("Palette") {
                Picker("Color palette", selection: $model.settings.paletteName) {
                    ForEach(palettes, id: \.self) { Text($0.capitalized).tag($0) }
                }
            }

            Section("Sensitivity") {
                Slider(value: $model.settings.gain, in: 0.5...4) {
                    Text("Gain")
                } minimumValueLabel: { Text("0.5") } maximumValueLabel: { Text("4") }
                Stepper("Bars: \(model.settings.barCount)",
                        value: $model.settings.barCount, in: 16...96, step: 4)
                Slider(value: $model.settings.smoothing, in: 0...0.95) {
                    Text("Smoothing")
                } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.95") }
                Toggle("Peak-hold caps", isOn: $model.settings.peakHoldEnabled)
            }

            Section("Track Overlay") {
                Toggle("Show overlay", isOn: $model.settings.overlayEnabled)
                Picker("Position", selection: $model.settings.overlayPosition) {
                    Text("Top Left").tag(OverlayCorner.topLeading)
                    Text("Top Right").tag(OverlayCorner.topTrailing)
                    Text("Bottom Left").tag(OverlayCorner.bottomLeading)
                    Text("Bottom Right").tag(OverlayCorner.bottomTrailing)
                }
                Slider(value: $model.settings.overlayOpacity, in: 0.2...1) {
                    Text("Opacity")
                } minimumValueLabel: { Text("20%") } maximumValueLabel: { Text("100%") }
            }

            Section("Window") {
                Toggle("Always on top", isOn: $model.settings.alwaysOnTop)
                Picker("Frame rate", selection: $model.settings.targetFPS) {
                    ForEach(fpsOptions, id: \.self) { Text("\($0) fps").tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 460)
    }
}
```

- [ ] **Step 2: Add a `Settings` scene in `Sources/App/MacVisualizerApp.swift`**

In `MacVisualizerMain`, add a `Settings` scene after the `Window { ... }.commands { ... }` block. The model is already a `@StateObject` on `MacVisualizerMain`; pass the same instance. Change the `body` so it returns both scenes:

```swift
    var body: some Scene {
        Window("Mac Visualizer", id: "main") {
            ContentView(model: model, nowPlaying: nowPlaying)
                .background(WindowConfigurator(alwaysOnTop: model.settings.alwaysOnTop))
                .onAppear { nowPlaying.start() }
        }
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Toggle Full Screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }
```

(Leave `@main enum AppEntry`, `ContentView`, and `WindowConfigurator` unchanged. The `Settings` scene provides the standard ⌘, Preferences window automatically.)

- [ ] **Step 3: Build**

Run: `make build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run unit tests**

Run: `make test`
Expected: `** TEST SUCCEEDED **`, total 65.

- [ ] **Step 5: Live verification (requires the user)**

Run `make run`, then press **⌘,** to open Settings. Verify, with the visualizer visible (ideally with music playing):
- **Gain** slider — bars get taller/shorter as you drag.
- **Bars** stepper — the number of bars changes live.
- **Smoothing** — higher = bars move more sluggishly.
- **Peak-hold caps** toggle — the cap ticks appear/disappear.
- **Palette** — colors change (classic green→red, phosphor green, synthwave neon).
- **Overlay** show/position/opacity — the track card toggles, moves corner, fades.
- **Always on top** — window floats above others.
- Quit and relaunch — settings persisted (the values you set are retained).

The agent should: build, run the render-probe regression, confirm the app launches; then report that live settings confirmation is pending the user. Do NOT claim the live controls work without user confirmation.

- [ ] **Step 6: Commit**

```bash
git add Sources/App/SettingsView.swift Sources/App/MacVisualizerApp.swift
git commit -m "Add Settings window (palette, sensitivity, overlay, window) bound live"
```

---

## Definition of Done (Plan 5)

- `make test` → `** TEST SUCCEEDED **`, 65 Core tests (analyzer reconfigure added).
- `make build` → `** BUILD SUCCEEDED **`; `--render-probe` still shows the staircase (buffer pool + RenderModel changes didn't regress rendering).
- ⌘, opens a Settings window; changing palette, gain, bar count, smoothing, peak-hold, overlay (enable/position/opacity), always-on-top, and frame rate all take effect live; settings persist across relaunch — confirmed by the user.
- Carry-forwards resolved: analyzer reconfigures to the capture-delivered sample rate and to live bar-count changes; `MetalRenderer` pools its vertex buffer.

**Remaining (final polish, not blocking the milestone):** custom palette color editing (currently presets only), the background-gradient render + its control (`backgroundStyle` stays solid), and per-monitor fullscreen selection (`fullscreenDisplayID`). With those aside, every requirement from the original brainstorm — a configurable, fullscreen-capable Mac visualizer reacting to Spotify/Apple Music with a retro spectrum-bars look and a now-playing overlay — is delivered.

## Notes on verification

The reconfigure logic is unit-tested (bar-count and sample-rate effects on band placement). The buffer pool is verified by the render probe (identical output). The live Settings controls are verified by the user (drag a slider, watch the bars), since SwiftUI control behavior and live audio response can't be asserted headlessly. Do not claim the live controls work from build success alone.
