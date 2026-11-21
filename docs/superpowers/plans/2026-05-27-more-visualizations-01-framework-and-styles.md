# More Visualizations — Phase 1: Framework + 3 Styles + Switching — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three new visualizer styles (radial spectrum, mirrored bars, oscilloscope) plus live switching (⌘]/⌘[, View menu, Settings picker), all on the existing flat-triangle Metal pipeline.

**Architecture:** New `Visualizer` conformers are pure functions of `(AudioFrame, VisualizerSettings, aspect)` → `[BarVertex]`, unit-tested like the existing bars. A `VisualizerStyle` enum (Codable, CaseIterable) maps a style to its conformer and drives switching via `settings.visualizerStyle`. The oscilloscope needs raw audio, so `AudioFrame` gains a downsampled `waveform`. The renderer picks the active visualizer each frame and passes the drawable aspect ratio.

**Tech Stack:** Swift 5.10, simd, SwiftUI (commands + Settings), Accelerate (existing), Metal (existing pipeline, no shader changes), XCTest.

**Builds on:** the merged app (`Visualizer`/`SpectrumBarsVisualizer`, `AudioFrame`, `VisualizerSettings`, `SpectrumAnalyzer`, `SyntheticFrameSource`, `MetalView`, `RenderProbe`, `SettingsView`). Spec: `docs/superpowers/specs/2026-05-27-more-visualizations-phase1-design.md`.

**Scope boundary — NOT here (Phase 2):** glow/bloom post-processing, the stateful particle field, auto-rotate.

---

## File Structure

```
mac-visualizer/
  Sources/
    Core/
      Visualizer.swift                 # MODIFY: add `aspect: Float` to makeVertices
      SpectrumBarsVisualizer.swift      # MODIFY: accept (ignore) aspect
      AudioFrame.swift                  # MODIFY: add `waveform: [Float]`
      SpectrumAnalyzer.swift            # MODIFY: emit downsampled waveform
      SyntheticFrameSource.swift        # MODIFY: emit synthetic waveform
      RadialSpectrumVisualizer.swift    # CREATE
      MirroredBarsVisualizer.swift      # CREATE
      OscilloscopeVisualizer.swift      # CREATE
      VisualizerStyle.swift             # CREATE: enum + factory + next/previous
      VisualizerSettings.swift          # MODIFY: add visualizerStyle + tolerant init(from:)
    Rendering/
      RenderProbe.swift                 # MODIFY: optional style arg
      MetalView.swift                   # MODIFY: select visualizer by style, pass aspect
    App/
      MacVisualizerApp.swift            # MODIFY: Visualizer menu (cycle + list)
      SettingsView.swift                # MODIFY: Visualization picker
  Tests/
    CoreTests/
      RadialSpectrumVisualizerTests.swift     # CREATE
      MirroredBarsVisualizerTests.swift        # CREATE
      OscilloscopeVisualizerTests.swift        # CREATE
      VisualizerStyleTests.swift               # CREATE
      WaveformTests.swift                       # CREATE (AudioFrame.waveform + analyzer + synthetic)
      VisualizerSettingsTests.swift            # MODIFY: tolerant decode + style round-trip
      AudioFrameTests.swift                    # MODIFY: waveform field
      SpectrumBarsVisualizerTests.swift        # MODIFY: aspect param
```

Each new visualizer is one focused file with a single pure method; the enum is the one place that knows the full set of styles.

---

## Task 1: Extend the `Visualizer` protocol with `aspect`

This is a signature refactor (no behavior change). It must update the protocol, the one existing conformer, both call sites, and the existing bars tests together so the build and the 65 tests stay green.

**Files:**
- Modify: `Sources/Core/Visualizer.swift`
- Modify: `Sources/Core/SpectrumBarsVisualizer.swift`
- Modify: `Sources/Rendering/MetalView.swift`
- Modify: `Sources/Rendering/RenderProbe.swift`
- Modify: `Tests/CoreTests/SpectrumBarsVisualizerTests.swift`

- [ ] **Step 1: Change the protocol** — `Sources/Core/Visualizer.swift`:

```swift
/// A visualizer turns an audio frame + settings into triangle vertices in clip space.
/// `aspect` is viewport width / height (used by styles that must stay proportional,
/// e.g. the radial circle); styles that don't need it ignore it.
/// Pure and GPU-free so it can be unit-tested; the Metal renderer encodes the result.
public protocol Visualizer {
    func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex]
}
```

- [ ] **Step 2: Update `SpectrumBarsVisualizer`** — change its method signature to `func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex]`. Do NOT use `aspect` (bars fill the width). Leave the body unchanged.

- [ ] **Step 3: Update the two call sites.**
  - `Sources/Rendering/MetalView.swift`, in `Coordinator.draw(in:)`, replace `let vertices = visualizer.makeVertices(frame: frame, settings: model.settings)` with:
    ```swift
    let size = view.drawableSize
    let aspect = size.height > 0 ? Float(size.width / size.height) : 1
    let vertices = visualizer.makeVertices(frame: frame, settings: model.settings, aspect: aspect)
    ```
  - `Sources/Rendering/RenderProbe.swift`, where it calls `SpectrumBarsVisualizer().makeVertices(frame: frame, settings: settings)`, replace with:
    ```swift
    let aspect = Float(width) / Float(height)
    let vertices = SpectrumBarsVisualizer().makeVertices(frame: frame, settings: settings, aspect: aspect)
    ```

- [ ] **Step 4: Update `SpectrumBarsVisualizerTests`** — every `viz.makeVertices(frame: ..., settings: ...)` call gains `, aspect: 1`. (Bars ignore aspect, so behavior and assertions are unchanged.)

- [ ] **Step 5: Build + test + probe**

Run: `make test` → expect `** TEST SUCCEEDED **`, still 65 tests (signatures changed, behavior identical).
Run: `make build` then `./DerivedData/Build/Products/Debug/MacVisualizer.app/Contents/MacOS/MacVisualizer --render-probe /tmp/p_t1.png && echo exit=$?`. Read `/tmp/p_t1.png`: unchanged green→red staircase.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Visualizer.swift Sources/Core/SpectrumBarsVisualizer.swift Sources/Rendering/MetalView.swift Sources/Rendering/RenderProbe.swift Tests/CoreTests/SpectrumBarsVisualizerTests.swift
git commit -m "Add aspect parameter to Visualizer.makeVertices"
```

---

## Task 2: Add `waveform` to `AudioFrame` (+ analyzer + synthetic)

**Files:**
- Modify: `Sources/Core/AudioFrame.swift`
- Modify: `Sources/Core/SpectrumAnalyzer.swift`
- Modify: `Sources/Core/SyntheticFrameSource.swift`
- Modify: `Tests/CoreTests/AudioFrameTests.swift`
- Modify: `Tests/CoreTests/SpectrumBarsVisualizerTests.swift` (its `frame(...)` helper builds AudioFrame directly)
- Create: `Tests/CoreTests/WaveformTests.swift`

- [ ] **Step 1: Write/extend the failing tests.**

Replace the body of `AudioFrameTests` so the init/silent tests include `waveform`:

```swift
import XCTest
@testable import MacVisualizerCore

final class AudioFrameTests: XCTestCase {
    func testSilentHasZeroEnergyAndNoBands() {
        let frame = AudioFrame.silent
        XCTAssertEqual(frame.rms, 0)
        XCTAssertEqual(frame.peak, 0)
        XCTAssertTrue(frame.bands.isEmpty)
        XCTAssertTrue(frame.bandPeaks.isEmpty)
        XCTAssertTrue(frame.waveform.isEmpty)
        XCTAssertEqual(frame.timestamp, 0)
    }

    func testInitStoresValues() {
        let frame = AudioFrame(bands: [0.1, 0.2], bandPeaks: [0.15, 0.25],
                               waveform: [0.0, 0.5, -0.5], rms: 0.4, peak: 0.9, timestamp: 12.5)
        XCTAssertEqual(frame.bands, [0.1, 0.2])
        XCTAssertEqual(frame.bandPeaks, [0.15, 0.25])
        XCTAssertEqual(frame.waveform, [0.0, 0.5, -0.5])
        XCTAssertEqual(frame.rms, 0.4)
        XCTAssertEqual(frame.peak, 0.9)
        XCTAssertEqual(frame.timestamp, 12.5)
    }
}
```

Create `Tests/CoreTests/WaveformTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class WaveformTests: XCTestCase {
    func testAnalyzerEmitsWaveformOf256Points() {
        let a = SpectrumAnalyzer(fftSize: 2048, sampleRate: 48000, settings: .defaults)
        let frame = a.append(SignalGenerators.sine(frequency: 440, sampleRate: 48000, count: 2048))!
        XCTAssertEqual(frame.waveform.count, 256)
        XCTAssertGreaterThan(frame.waveform.map { abs($0) }.max() ?? 0, 0) // a tone is non-flat
    }

    func testAnalyzerSilenceWaveformIsFlat() {
        let a = SpectrumAnalyzer(fftSize: 2048, sampleRate: 48000, settings: .defaults)
        let frame = a.append(SignalGenerators.silence(count: 2048))!
        XCTAssertEqual(frame.waveform.count, 256)
        XCTAssertLessThan(frame.waveform.map { abs($0) }.max() ?? 0, 1e-4)
    }

    func testSyntheticWaveformIsNonEmptyAndAnimates() {
        let s = SyntheticFrameSource(bandCount: 24)
        let w0 = s.frame(at: 0).waveform
        let w1 = s.frame(at: 1).waveform
        XCTAssertFalse(w0.isEmpty)
        XCTAssertNotEqual(w0, w1)
    }
}
```

In `SpectrumBarsVisualizerTests`, update its private `frame(bands:peaks:)` helper to pass `waveform: []`:
```swift
    private func frame(bands: [Float], peaks: [Float]) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: peaks, waveform: [], rms: 0, peak: 0, timestamp: 0)
    }
```

- [ ] **Step 2: Run `make test`** — expect FAIL (`AudioFrame` init has no `waveform`; missing argument).

- [ ] **Step 3: Add `waveform` to `AudioFrame`** — replace `Sources/Core/AudioFrame.swift`:

```swift
import QuartzCore

public struct AudioFrame: Equatable {
    public var bands: [Float]
    public var bandPeaks: [Float]
    public var waveform: [Float]
    public var rms: Float
    public var peak: Float
    public var timestamp: CFTimeInterval

    public init(bands: [Float], bandPeaks: [Float], waveform: [Float],
                rms: Float, peak: Float, timestamp: CFTimeInterval) {
        self.bands = bands
        self.bandPeaks = bandPeaks
        self.waveform = waveform
        self.rms = rms
        self.peak = peak
        self.timestamp = timestamp
    }

    public static let silent = AudioFrame(bands: [], bandPeaks: [], waveform: [],
                                          rms: 0, peak: 0, timestamp: 0)
}
```

- [ ] **Step 4: Emit waveform from `SpectrumAnalyzer.append`.** Add a constant near the top of the class: `private let waveformPointCount = 256`. In `append`, after `frameSamples` is computed and before the `return AudioFrame(...)`, build the downsampled waveform:

```swift
        let step = max(1, fftSize / waveformPointCount)
        var wave = [Float]()
        wave.reserveCapacity(waveformPointCount)
        var wi = 0
        while wi < frameSamples.count && wave.count < waveformPointCount {
            wave.append(frameSamples[wi]); wi += step
        }
```

Then change the `return AudioFrame(...)` to include `waveform: wave` (in the correct argument position: `bands:bandPeaks:waveform:rms:peak:timestamp:`).

- [ ] **Step 5: Emit synthetic waveform from `SyntheticFrameSource.frame(at:)`.** Before the final `return AudioFrame(...)`, add:

```swift
        let wavePoints = 256
        var wave = [Float](repeating: 0, count: wavePoints)
        for j in 0..<wavePoints {
            let p = Float(j) / Float(wavePoints)
            wave[j] = 0.6 * sinf(tf * 3 + p * 2 * .pi * 3) * (0.5 + 0.5 * sinf(tf * 1.3))
        }
```

(`tf` is the existing `Float(t)` local in `frame(at:)`.) Then include `waveform: wave` in the returned `AudioFrame(...)`.

- [ ] **Step 6: Run `make test`** — expect `** TEST SUCCEEDED **`; the new `WaveformTests` (3) pass and the updated AudioFrame/bars tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/Core/AudioFrame.swift Sources/Core/SpectrumAnalyzer.swift Sources/Core/SyntheticFrameSource.swift Tests/CoreTests/AudioFrameTests.swift Tests/CoreTests/WaveformTests.swift Tests/CoreTests/SpectrumBarsVisualizerTests.swift
git commit -m "Add downsampled waveform to AudioFrame, analyzer, and synthetic source"
```

---

## Task 3: `RadialSpectrumVisualizer`

**Files:**
- Create: `Sources/Core/RadialSpectrumVisualizer.swift`
- Test: `Tests/CoreTests/RadialSpectrumVisualizerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import simd
@testable import MacVisualizerCore

final class RadialSpectrumVisualizerTests: XCTestCase {
    private func frame(_ bands: [Float]) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: bands, waveform: [], rms: 0, peak: 0, timestamp: 0)
    }
    private func settings(_ n: Int) -> VisualizerSettings {
        var s = VisualizerSettings.defaults; s.barCount = n; return s
    }

    func testSixVerticesPerBand() {
        let v = RadialSpectrumVisualizer().makeVertices(frame: frame([0.2, 0.5, 0.9]),
                                                        settings: settings(3), aspect: 1)
        XCTAssertEqual(v.count, 3 * 6)
    }

    func testAllVerticesInClipSpace() {
        for aspect: Float in [0.5, 1, 2] {
            let v = RadialSpectrumVisualizer().makeVertices(frame: frame([1, 1, 1, 1]),
                                                            settings: settings(4), aspect: aspect)
            for vertex in v {
                XCTAssertLessThanOrEqual(abs(vertex.position.x), 1.0001, "x out at aspect \(aspect)")
                XCTAssertLessThanOrEqual(abs(vertex.position.y), 1.0001, "y out at aspect \(aspect)")
            }
        }
    }

    func testWideAspectStaysRound() {
        // With a wide window (aspect 2), equal-length bars must extend LESS in x than in y.
        let v = RadialSpectrumVisualizer().makeVertices(frame: frame([1, 1, 1, 1, 1, 1, 1, 1]),
                                                        settings: settings(8), aspect: 2)
        let maxX = v.map { abs($0.position.x) }.max()!
        let maxY = v.map { abs($0.position.y) }.max()!
        XCTAssertLessThan(maxX, maxY)
    }

    func testZeroBandsCollapseToInnerRadius() {
        // All-zero levels: every vertex sits on the inner ring (radius r0 = 0.25),
        // so the max radial extent is ~0.25, not the full span.
        let v = RadialSpectrumVisualizer().makeVertices(frame: frame([0, 0, 0, 0]),
                                                        settings: settings(4), aspect: 1)
        let maxR = v.map { sqrt($0.position.x * $0.position.x + $0.position.y * $0.position.y) }.max()!
        XCTAssertEqual(maxR, 0.25, accuracy: 0.02)
    }
}
```

- [ ] **Step 2: Run `make test`** — expect FAIL (`cannot find 'RadialSpectrumVisualizer'`).

- [ ] **Step 3: Implement** — `Sources/Core/RadialSpectrumVisualizer.swift`:

```swift
import simd

/// Spectrum bands arranged radially around a center ring; each band is a bar
/// pointing outward, length = level. Aspect-corrected so the ring stays round.
public struct RadialSpectrumVisualizer: Visualizer {
    public init() {}

    private let innerRadius: Float = 0.25
    private let radialSpan: Float = 0.6

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        let n = frame.bands.count
        guard n > 0 else { return [] }
        let palette = ColorPalette.preset(named: settings.paletteName) ?? ColorPalette.preset(named: "classic")!

        // Scale the longer screen axis down so a circle stays round AND inside clip space.
        var sx: Float = 1, sy: Float = 1
        if aspect >= 1 { sx = 1 / aspect } else { sy = aspect }

        let angularHalf = (Float.pi / Float(n)) * 0.8
        var verts: [BarVertex] = []
        verts.reserveCapacity(n * 6)

        func point(_ r: Float, _ a: Float) -> SIMD4<Float> {
            SIMD4<Float>(r * cosf(a) * sx, r * sinf(a) * sy, 0, 1)
        }

        for i in 0..<n {
            let level = min(max(frame.bands[i], 0), 1)
            let theta = 2 * Float.pi * Float(i) / Float(n) - Float.pi / 2
            let rOuter = innerRadius + level * radialSpan
            let cInner = rgba(palette.sample(at: 0))
            let cOuter = rgba(palette.sample(at: level))
            let a0 = theta - angularHalf
            let a1 = theta + angularHalf
            let il = point(innerRadius, a0), ir = point(innerRadius, a1)
            let ol = point(rOuter, a0), or = point(rOuter, a1)
            verts.append(contentsOf: [
                BarVertex(position: il, color: cInner),
                BarVertex(position: ir, color: cInner),
                BarVertex(position: ol, color: cOuter),
                BarVertex(position: ir, color: cInner),
                BarVertex(position: or, color: cOuter),
                BarVertex(position: ol, color: cOuter),
            ])
        }
        return verts
    }

    private func rgba(_ c: RGBAColor) -> SIMD4<Float> { SIMD4<Float>(c.r, c.g, c.b, c.a) }
}
```

- [ ] **Step 4: Run `make test`** — expect `** TEST SUCCEEDED **`, the 4 radial tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/RadialSpectrumVisualizer.swift Tests/CoreTests/RadialSpectrumVisualizerTests.swift
git commit -m "Add RadialSpectrumVisualizer"
```

---

## Task 4: `MirroredBarsVisualizer`

**Files:**
- Create: `Sources/Core/MirroredBarsVisualizer.swift`
- Test: `Tests/CoreTests/MirroredBarsVisualizerTests.swift`

Geometry: each band is two stacked quads sharing the center line `y = 0` — an upper quad from `y=0` (center color) to `y=+level` (edge color) and a lower quad from `y=0` to `y=−level`. So **12 vertices per band**, symmetric about `y=0`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import simd
@testable import MacVisualizerCore

final class MirroredBarsVisualizerTests: XCTestCase {
    private func frame(_ bands: [Float]) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: bands, waveform: [], rms: 0, peak: 0, timestamp: 0)
    }
    private func settings(_ n: Int) -> VisualizerSettings {
        var s = VisualizerSettings.defaults; s.barCount = n; return s
    }

    func testTwelveVerticesPerBand() {
        let v = MirroredBarsVisualizer().makeVertices(frame: frame([0.3, 0.7]),
                                                      settings: settings(2), aspect: 1)
        XCTAssertEqual(v.count, 2 * 12)
    }

    func testSymmetricAboutCenter() {
        let v = MirroredBarsVisualizer().makeVertices(frame: frame([0.5, 0.9, 0.2]),
                                                      settings: settings(3), aspect: 1)
        // For every vertex (x,y) there must be a matching vertex (x,-y).
        for vertex in v {
            let mirrored = v.contains { other in
                abs(other.position.x - vertex.position.x) < 1e-5 &&
                abs(other.position.y + vertex.position.y) < 1e-5
            }
            XCTAssertTrue(mirrored, "no mirror for (\(vertex.position.x), \(vertex.position.y))")
        }
    }

    func testAllVerticesInClipSpace() {
        let v = MirroredBarsVisualizer().makeVertices(frame: frame([1, 1, 1, 1]),
                                                      settings: settings(4), aspect: 1)
        for vertex in v {
            XCTAssertLessThanOrEqual(abs(vertex.position.x), 1.0001)
            XCTAssertLessThanOrEqual(abs(vertex.position.y), 1.0001)
        }
    }

    func testZeroLevelCollapsesToCenter() {
        let v = MirroredBarsVisualizer().makeVertices(frame: frame([0, 0]),
                                                      settings: settings(2), aspect: 1)
        for vertex in v { XCTAssertEqual(vertex.position.y, 0, accuracy: 1e-5) }
    }
}
```

- [ ] **Step 2: Run `make test`** — expect FAIL (`cannot find 'MirroredBarsVisualizer'`).

- [ ] **Step 3: Implement** — `Sources/Core/MirroredBarsVisualizer.swift`:

```swift
import simd

/// Spectrum bars mirrored about the center line: each band grows up and down
/// symmetrically, colored from center (palette 0) to the tips (palette level).
public struct MirroredBarsVisualizer: Visualizer {
    public init() {}

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        let n = frame.bands.count
        guard n > 0 else { return [] }
        let layout = BarLayout(barCount: n)
        let palette = ColorPalette.preset(named: settings.paletteName) ?? ColorPalette.preset(named: "classic")!

        var verts: [BarVertex] = []
        verts.reserveCapacity(n * 12)

        for i in 0..<n {
            let level = min(max(frame.bands[i], 0), 1)
            let (xs, xe) = layout.barXRange(i)
            let x0 = xs * 2 - 1
            let x1 = xe * 2 - 1
            let cCenter = rgba(palette.sample(at: 0))
            let cEdge = rgba(palette.sample(at: level))
            appendQuad(&verts, x0: x0, x1: x1, yLow: 0, yHigh: level, colorLow: cCenter, colorHigh: cEdge)
            appendQuad(&verts, x0: x0, x1: x1, yLow: 0, yHigh: -level, colorLow: cCenter, colorHigh: cEdge)
        }
        return verts
    }

    private func rgba(_ c: RGBAColor) -> SIMD4<Float> { SIMD4<Float>(c.r, c.g, c.b, c.a) }

    /// Rectangle [x0,x1] × [yLow,yHigh]; `yLow` vertices use colorLow, `yHigh` use colorHigh.
    private func appendQuad(_ verts: inout [BarVertex], x0: Float, x1: Float,
                            yLow: Float, yHigh: Float, colorLow: SIMD4<Float>, colorHigh: SIMD4<Float>) {
        let bl = BarVertex(position: SIMD4<Float>(x0, yLow, 0, 1), color: colorLow)
        let br = BarVertex(position: SIMD4<Float>(x1, yLow, 0, 1), color: colorLow)
        let tl = BarVertex(position: SIMD4<Float>(x0, yHigh, 0, 1), color: colorHigh)
        let tr = BarVertex(position: SIMD4<Float>(x1, yHigh, 0, 1), color: colorHigh)
        verts.append(contentsOf: [bl, br, tl, br, tr, tl])
    }
}
```

- [ ] **Step 4: Run `make test`** — expect `** TEST SUCCEEDED **`, the 4 mirrored tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/MirroredBarsVisualizer.swift Tests/CoreTests/MirroredBarsVisualizerTests.swift
git commit -m "Add MirroredBarsVisualizer"
```

---

## Task 5: `OscilloscopeVisualizer`

**Files:**
- Create: `Sources/Core/OscilloscopeVisualizer.swift`
- Test: `Tests/CoreTests/OscilloscopeVisualizerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import simd
@testable import MacVisualizerCore

final class OscilloscopeVisualizerTests: XCTestCase {
    private func frame(_ wave: [Float]) -> AudioFrame {
        AudioFrame(bands: [], bandPeaks: [], waveform: wave, rms: 0, peak: 0, timestamp: 0)
    }

    func testSixVerticesPerSegment() {
        let v = OscilloscopeVisualizer().makeVertices(frame: frame([0, 0.5, -0.5, 0.2]),
                                                      settings: .defaults, aspect: 1)
        XCTAssertEqual(v.count, (4 - 1) * 6)
    }

    func testEmptyOrSingleSampleYieldsNothing() {
        XCTAssertTrue(OscilloscopeVisualizer().makeVertices(frame: frame([]), settings: .defaults, aspect: 1).isEmpty)
        XCTAssertTrue(OscilloscopeVisualizer().makeVertices(frame: frame([0.5]), settings: .defaults, aspect: 1).isEmpty)
    }

    func testAllVerticesInClipSpace() {
        let wave = (0..<128).map { sinf(Float($0) / 128 * 2 * .pi * 4) } // big swings
        let v = OscilloscopeVisualizer().makeVertices(frame: frame(wave), settings: .defaults, aspect: 1)
        for vertex in v {
            XCTAssertLessThanOrEqual(abs(vertex.position.x), 1.0001)
            XCTAssertLessThanOrEqual(abs(vertex.position.y), 1.0001)
        }
    }

    func testSilentWaveformIsFlatNearZero() {
        let v = OscilloscopeVisualizer().makeVertices(frame: frame([Float](repeating: 0, count: 64)),
                                                      settings: .defaults, aspect: 1)
        for vertex in v { XCTAssertLessThan(abs(vertex.position.y), 0.02) } // within line thickness
    }
}
```

- [ ] **Step 2: Run `make test`** — expect FAIL (`cannot find 'OscilloscopeVisualizer'`).

- [ ] **Step 3: Implement** — `Sources/Core/OscilloscopeVisualizer.swift`:

```swift
import simd

/// Draws the raw waveform as a connected line (one thin quad per segment),
/// colored by amplitude.
public struct OscilloscopeVisualizer: Visualizer {
    public init() {}

    private let yScale: Float = 0.9
    private let halfThickness: Float = 0.008

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        let w = frame.waveform
        guard w.count >= 2 else { return [] }
        let palette = ColorPalette.preset(named: settings.paletteName) ?? ColorPalette.preset(named: "classic")!
        let m = w.count

        func y(_ s: Float) -> Float { min(max(s * yScale, -1), 1) }
        func color(_ yv: Float) -> SIMD4<Float> { rgba(palette.sample(at: min(abs(yv), 1))) }

        var verts: [BarVertex] = []
        verts.reserveCapacity((m - 1) * 6)
        for j in 0..<(m - 1) {
            let x0 = -1 + 2 * Float(j) / Float(m - 1)
            let x1 = -1 + 2 * Float(j + 1) / Float(m - 1)
            let y0 = y(w[j]); let y1 = y(w[j + 1])
            let c0 = color(y0); let c1 = color(y1)
            let bl = BarVertex(position: SIMD4<Float>(x0, y0 - halfThickness, 0, 1), color: c0)
            let tl = BarVertex(position: SIMD4<Float>(x0, y0 + halfThickness, 0, 1), color: c0)
            let br = BarVertex(position: SIMD4<Float>(x1, y1 - halfThickness, 0, 1), color: c1)
            let tr = BarVertex(position: SIMD4<Float>(x1, y1 + halfThickness, 0, 1), color: c1)
            verts.append(contentsOf: [bl, br, tl, br, tr, tl])
        }
        return verts
    }

    private func rgba(_ c: RGBAColor) -> SIMD4<Float> { SIMD4<Float>(c.r, c.g, c.b, c.a) }
}
```

- [ ] **Step 4: Run `make test`** — expect `** TEST SUCCEEDED **`, the 4 oscilloscope tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/OscilloscopeVisualizer.swift Tests/CoreTests/OscilloscopeVisualizerTests.swift
git commit -m "Add OscilloscopeVisualizer"
```

---

## Task 6: `VisualizerStyle` enum + factory

**Files:**
- Create: `Sources/Core/VisualizerStyle.swift`
- Test: `Tests/CoreTests/VisualizerStyleTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MacVisualizerCore

final class VisualizerStyleTests: XCTestCase {
    func testAllCases() {
        XCTAssertEqual(VisualizerStyle.allCases, [.bars, .radial, .mirrored, .oscilloscope])
    }

    func testNextWrapsAround() {
        XCTAssertEqual(VisualizerStyle.bars.next, .radial)
        XCTAssertEqual(VisualizerStyle.oscilloscope.next, .bars)
    }

    func testPreviousWrapsAround() {
        XCTAssertEqual(VisualizerStyle.radial.previous, .bars)
        XCTAssertEqual(VisualizerStyle.bars.previous, .oscilloscope)
    }

    func testDisplayNamesNonEmpty() {
        for s in VisualizerStyle.allCases { XCTAssertFalse(s.displayName.isEmpty) }
    }

    func testFactoryMatchesConcreteVisualizer() {
        // The factory must return the right conformer: compare vertex output to the
        // concrete visualizer for a known frame.
        var settings = VisualizerSettings.defaults; settings.barCount = 4
        let frame = AudioFrame(bands: [0.2, 0.4, 0.6, 0.8], bandPeaks: [0.2, 0.4, 0.6, 0.8],
                               waveform: [0, 0.5, -0.5, 0.3], rms: 0, peak: 0, timestamp: 0)
        XCTAssertEqual(VisualizerStyle.bars.makeVisualizer().makeVertices(frame: frame, settings: settings, aspect: 1),
                       SpectrumBarsVisualizer().makeVertices(frame: frame, settings: settings, aspect: 1))
        XCTAssertEqual(VisualizerStyle.radial.makeVisualizer().makeVertices(frame: frame, settings: settings, aspect: 1),
                       RadialSpectrumVisualizer().makeVertices(frame: frame, settings: settings, aspect: 1))
        XCTAssertEqual(VisualizerStyle.mirrored.makeVisualizer().makeVertices(frame: frame, settings: settings, aspect: 1),
                       MirroredBarsVisualizer().makeVertices(frame: frame, settings: settings, aspect: 1))
        XCTAssertEqual(VisualizerStyle.oscilloscope.makeVisualizer().makeVertices(frame: frame, settings: settings, aspect: 1),
                       OscilloscopeVisualizer().makeVertices(frame: frame, settings: settings, aspect: 1))
    }
}
```

(`BarVertex` is `Equatable`, so the vertex-array comparisons compile.)

- [ ] **Step 2: Run `make test`** — expect FAIL (`cannot find 'VisualizerStyle'`).

- [ ] **Step 3: Implement** — `Sources/Core/VisualizerStyle.swift`:

```swift
/// The selectable visualization styles. Drives switching and the visualizer factory.
public enum VisualizerStyle: String, Codable, CaseIterable {
    case bars, radial, mirrored, oscilloscope

    public var displayName: String {
        switch self {
        case .bars: return "Bars"
        case .radial: return "Radial"
        case .mirrored: return "Mirrored"
        case .oscilloscope: return "Oscilloscope"
        }
    }

    public func makeVisualizer() -> Visualizer {
        switch self {
        case .bars: return SpectrumBarsVisualizer()
        case .radial: return RadialSpectrumVisualizer()
        case .mirrored: return MirroredBarsVisualizer()
        case .oscilloscope: return OscilloscopeVisualizer()
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

- [ ] **Step 4: Run `make test`** — expect `** TEST SUCCEEDED **`, the 5 style tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/VisualizerStyle.swift Tests/CoreTests/VisualizerStyleTests.swift
git commit -m "Add VisualizerStyle enum with factory and cycling"
```

---

## Task 7: `VisualizerSettings.visualizerStyle` + tolerant decoder

**Files:**
- Modify: `Sources/Core/VisualizerSettings.swift`
- Modify: `Tests/CoreTests/VisualizerSettingsTests.swift`

- [ ] **Step 1: Write the failing tests** — add to `VisualizerSettingsTests`:

```swift
    func testDefaultVisualizerStyleIsBars() {
        XCTAssertEqual(VisualizerSettings.defaults.visualizerStyle, .bars)
    }

    func testVisualizerStyleRoundTrips() throws {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .oscilloscope
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.visualizerStyle, .oscilloscope)
        XCTAssertEqual(decoded, s)
    }

    func testPartialJSONDecodesWithDefaults() throws {
        // An old settings file with only some keys must decode, defaulting the rest
        // (including the new visualizerStyle) instead of throwing.
        let json = #"{ "gain": 2.5, "barCount": 64 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.gain, 2.5)
        XCTAssertEqual(decoded.barCount, 64)
        XCTAssertEqual(decoded.visualizerStyle, .bars)        // defaulted
        XCTAssertEqual(decoded.smoothing, VisualizerSettings.defaults.smoothing) // defaulted
        XCTAssertEqual(decoded.paletteName, VisualizerSettings.defaults.paletteName) // defaulted
    }
```

- [ ] **Step 2: Run `make test`** — expect FAIL (`visualizerStyle` doesn't exist; partial JSON throws `keyNotFound`).

- [ ] **Step 3: Add the field and a tolerant decoder.** In `Sources/Core/VisualizerSettings.swift`:

(3a) Add the stored property to the struct (with the other fields), e.g. after `backgroundStyle`:
```swift
    // Visualization
    public var visualizerStyle: VisualizerStyle
```

(3b) Add `visualizerStyle: .bars` to the `defaults` initializer call (in the correct argument position — keep it last, matching the property order).

(3c) Add a tolerant `Codable` implementation in an **extension** (so the memberwise initializer used by `defaults` is preserved):
```swift
extension VisualizerSettings {
    private enum CodingKeys: String, CodingKey {
        case paletteName, customStops, gain, barCount, smoothing, peakHoldEnabled
        case overlayEnabled, overlayPosition, overlayOpacity
        case alwaysOnTop, fullscreenDisplayID, targetFPS, backgroundStyle, visualizerStyle
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VisualizerSettings.defaults
        self.init(
            paletteName: try c.decodeIfPresent(String.self, forKey: .paletteName) ?? d.paletteName,
            customStops: try c.decodeIfPresent([RGBAColor].self, forKey: .customStops) ?? d.customStops,
            gain: try c.decodeIfPresent(Float.self, forKey: .gain) ?? d.gain,
            barCount: try c.decodeIfPresent(Int.self, forKey: .barCount) ?? d.barCount,
            smoothing: try c.decodeIfPresent(Float.self, forKey: .smoothing) ?? d.smoothing,
            peakHoldEnabled: try c.decodeIfPresent(Bool.self, forKey: .peakHoldEnabled) ?? d.peakHoldEnabled,
            overlayEnabled: try c.decodeIfPresent(Bool.self, forKey: .overlayEnabled) ?? d.overlayEnabled,
            overlayPosition: try c.decodeIfPresent(OverlayCorner.self, forKey: .overlayPosition) ?? d.overlayPosition,
            overlayOpacity: try c.decodeIfPresent(Float.self, forKey: .overlayOpacity) ?? d.overlayOpacity,
            alwaysOnTop: try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? d.alwaysOnTop,
            fullscreenDisplayID: try c.decodeIfPresent(UInt32.self, forKey: .fullscreenDisplayID) ?? d.fullscreenDisplayID,
            targetFPS: try c.decodeIfPresent(Int.self, forKey: .targetFPS) ?? d.targetFPS,
            backgroundStyle: try c.decodeIfPresent(BackgroundStyle.self, forKey: .backgroundStyle) ?? d.backgroundStyle,
            visualizerStyle: try c.decodeIfPresent(VisualizerStyle.self, forKey: .visualizerStyle) ?? d.visualizerStyle
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(paletteName, forKey: .paletteName)
        try c.encode(customStops, forKey: .customStops)
        try c.encode(gain, forKey: .gain)
        try c.encode(barCount, forKey: .barCount)
        try c.encode(smoothing, forKey: .smoothing)
        try c.encode(peakHoldEnabled, forKey: .peakHoldEnabled)
        try c.encode(overlayEnabled, forKey: .overlayEnabled)
        try c.encode(overlayPosition, forKey: .overlayPosition)
        try c.encode(overlayOpacity, forKey: .overlayOpacity)
        try c.encode(alwaysOnTop, forKey: .alwaysOnTop)
        try c.encodeIfPresent(fullscreenDisplayID, forKey: .fullscreenDisplayID)
        try c.encode(targetFPS, forKey: .targetFPS)
        try c.encode(backgroundStyle, forKey: .backgroundStyle)
        try c.encode(visualizerStyle, forKey: .visualizerStyle)
    }
}
```

The memberwise `init(...)` argument list must include `visualizerStyle` last; update the `defaults` static to pass `visualizerStyle: .bars`. (The struct must NOT declare an explicit `init` in its main body, so the memberwise init remains synthesized — the custom `init(from:)`/`encode(to:)` live in the extension above.)

- [ ] **Step 4: Run `make test`** — expect `** TEST SUCCEEDED **`; the 3 new settings tests pass, the existing settings round-trip test still passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/VisualizerSettings.swift Tests/CoreTests/VisualizerSettingsTests.swift
git commit -m "Add visualizerStyle setting with backward-compatible decoding"
```

---

## Task 8: Render probe selects a style (headless visual check)

**Files:**
- Modify: `Sources/Rendering/RenderProbe.swift`
- Modify: `Sources/App/MacVisualizerApp.swift`

- [ ] **Step 1: Parse an optional style arg.** In `Sources/App/MacVisualizerApp.swift`, update the `--render-probe` branch in `AppEntry.main()`:
```swift
        if let idx = args.firstIndex(of: "--render-probe"), idx + 1 < args.count {
            let path = args[idx + 1]
            let style = (idx + 2 < args.count ? VisualizerStyle(rawValue: args[idx + 2]) : nil) ?? .bars
            let ok = RenderProbe.run(outputPath: path, style: style)
            exit(ok ? 0 : 1)
        }
```

- [ ] **Step 2: Use the style in `RenderProbe`.** Change `RenderProbe.run` to `static func run(outputPath: String, style: VisualizerStyle = .bars, width: Int = 800, height: Int = 400) -> Bool`. Replace the frame/vertex construction block with one that builds a ramp-bands frame plus a sine waveform, then uses the style's visualizer with the probe aspect:
```swift
        let settings = VisualizerSettings.defaults
        let bandCount = settings.barCount
        let bands = (0..<bandCount).map { Float($0) / Float(max(bandCount - 1, 1)) }
        let peaks = bands.map { min($0 + 0.05, 1) }
        let wave = (0..<256).map { sinf(Float($0) / 256 * 2 * .pi * 4) }
        let frame = AudioFrame(bands: bands, bandPeaks: peaks, waveform: wave,
                               rms: 0, peak: bands.last ?? 0, timestamp: 0)
        let aspect = Float(width) / Float(height)
        let vertices = style.makeVisualizer().makeVertices(frame: frame, settings: settings, aspect: aspect)

        renderer.encode(vertices: vertices,
                        clearColor: MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                        into: pass, commandBuffer: commandBuffer)
```
(Keep the rest of `run` — device/texture setup, blit, `writePNG` — unchanged. Remove any now-unused prior `SpectrumBarsVisualizer()` line so only this block builds the vertices.)

- [ ] **Step 3: Build, then probe each new style and INSPECT the PNGs.**

Run: `make build` → `** BUILD SUCCEEDED **`. Then:
```bash
BIN=./DerivedData/Build/Products/Debug/MacVisualizer.app/Contents/MacOS/MacVisualizer
$BIN --render-probe /tmp/v_bars.png bars
$BIN --render-probe /tmp/v_radial.png radial
$BIN --render-probe /tmp/v_mirror.png mirrored
$BIN --render-probe /tmp/v_scope.png oscilloscope
```
Use the Read tool on each. Expected: `v_bars.png` = the staircase (regression); `v_radial.png` = bars radiating from a center ring in a **round** burst (round, not stretched, on the 800×400 canvas); `v_mirror.png` = bars mirrored above and below a center line; `v_scope.png` = a wiggling waveform line spanning the width. If any is blank/wrong, report what you saw (DONE_WITH_CONCERNS) with the image — don't fudge the probe.

- [ ] **Step 4: Run unit tests** — `make test` → `** TEST SUCCEEDED **` (count unchanged from Task 7).

- [ ] **Step 5: Commit**

```bash
git add Sources/Rendering/RenderProbe.swift Sources/App/MacVisualizerApp.swift
git commit -m "Let the render probe render any visualizer style"
```

---

## Task 9: Renderer selects the active visualizer by style

**Files:**
- Modify: `Sources/Rendering/MetalView.swift`

- [ ] **Step 1: Replace the fixed visualizer with a style-driven, cached one.** In `MetalView.Coordinator`:

(1a) Replace the stored `private let visualizer = SpectrumBarsVisualizer()` with:
```swift
        private var currentStyle: VisualizerStyle
        private var visualizer: Visualizer
```
(1b) In `Coordinator.init(model:)`, after `self.model = model` and creating `renderer`, initialize them from settings:
```swift
            self.currentStyle = model.settings.visualizerStyle
            self.visualizer = model.settings.visualizerStyle.makeVisualizer()
```
(1c) In `draw(in:)`, before computing vertices, rebuild the visualizer if the style changed:
```swift
            let style = model.settings.visualizerStyle
            if style != currentStyle {
                currentStyle = style
                visualizer = style.makeVisualizer()
            }
```
(Then the existing `makeVertices(frame:settings:aspect:)` call uses `visualizer`.) Order the property declarations / init so Swift's definite-initialization is satisfied (set `currentStyle` and `visualizer` in `init` before use).

- [ ] **Step 2: Build + tests + probe**

Run: `make build` → `** BUILD SUCCEEDED **`. `make test` → `** TEST SUCCEEDED **`.
Run the bars probe again (`--render-probe /tmp/v_bars2.png bars`) and confirm the staircase (render path intact).

- [ ] **Step 3: Confirm the app launches**
```bash
make run >/dev/null 2>&1 & sleep 3; pgrep -x MacVisualizer >/dev/null && echo "running ok"; osascript -e 'quit app "MacVisualizer"' 2>/dev/null || pkill -x MacVisualizer || true
```
Expect `running ok` (defaults to bars; switching UI lands in Task 10).

- [ ] **Step 4: Commit**

```bash
git add Sources/Rendering/MetalView.swift
git commit -m "Select the active visualizer from settings.visualizerStyle"
```

---

## Task 10: Switching UI — Visualizer menu + Settings picker

**Files:**
- Modify: `Sources/App/MacVisualizerApp.swift`
- Modify: `Sources/App/SettingsView.swift`

- [ ] **Step 1: Add a Visualizer command menu.** In `MacVisualizerApp.swift`, ensure the imports include `import MacVisualizerCore` (needed for `VisualizerStyle`). Inside the existing `.commands { ... }` on the `Window` scene, add a second command builder after the existing `CommandGroup(after: .windowArrangement) { ... }`:
```swift
            CommandMenu("Visualizer") {
                Button("Next Visualization") {
                    model.settings.visualizerStyle = model.settings.visualizerStyle.next
                }
                .keyboardShortcut("]", modifiers: .command)
                Button("Previous Visualization") {
                    model.settings.visualizerStyle = model.settings.visualizerStyle.previous
                }
                .keyboardShortcut("[", modifiers: .command)
                Divider()
                ForEach(VisualizerStyle.allCases, id: \.self) { style in
                    Button(style.displayName) { model.settings.visualizerStyle = style }
                }
            }
```

- [ ] **Step 2: Add a Visualization picker to Settings.** In `SettingsView.swift`, add a section at the TOP of the `Form` (before "Palette"):
```swift
            Section("Visualization") {
                Picker("Style", selection: $model.settings.visualizerStyle) {
                    ForEach(VisualizerStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
```

- [ ] **Step 3: Build + tests**

Run: `make build` → `** BUILD SUCCEEDED **`. `make test` → `** TEST SUCCEEDED **`.

- [ ] **Step 4: Live verification (requires the user)**

Run `make run` with music playing. Verify:
- **⌘]** cycles forward through Bars → Radial → Mirrored → Oscilloscope → Bars; **⌘[** goes back.
- The **Visualizer** menu lists all four and selecting one switches instantly.
- **⌘,** Settings → **Visualization** picker switches the style and persists across relaunch.
- Each style reacts to the audio (radial pulses round, mirrored is symmetric, oscilloscope traces the waveform).

The agent should build, run the bars/radial/mirrored/oscilloscope probes once more if helpful, confirm launch, and report that live switching confirmation is pending the user. Do NOT claim the live switching works without user confirmation.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/MacVisualizerApp.swift Sources/App/SettingsView.swift
git commit -m "Add visualizer switching: keyboard cycle, Visualizer menu, Settings picker"
```

---

## Definition of Done (Phase 1)

- `make test` → `** TEST SUCCEEDED **` with the ~23 new Core tests green (radial, mirrored, oscilloscope, style, waveform, settings-decode) on top of the prior 65 (~88 tests total).
- `make build` → `** BUILD SUCCEEDED **`.
- `--render-probe <path> radial|mirrored|oscilloscope|bars` each render the expected shape (verified via PNG).
- `make run`: ⌘]/⌘[, the Visualizer menu, and the Settings picker switch among Bars/Radial/Mirrored/Oscilloscope live; each reacts to audio; the choice persists. Confirmed by the user.
- Existing `settings.json` files still load (tolerant decoder).

## Handoff to Phase 2 (Glow/bloom + particles)

Phase 2 adds the bloom post-processing pipeline (offscreen render → bright-pass → gaussian blur → additive composite; new shaders, multi-pass) over all styles, and the stateful `ParticleVisualizer` (reusing the Coordinator's `visualizer` cache slot built in Task 9; it will need per-frame state advanced by `frame.rms`/bass + a time delta, unlike the stateless Phase 1 visualizers). The `aspect` parameter and the `VisualizerStyle` factory/switching are already in place for it.
