# Mac Music Visualizer — Plan 2: Metal Rendering (Spectrum Bars)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the classic spectrum-bars visualizer with Metal in the app window, driven (for now) by a synthetic animated frame source, with a resizable, fullscreen-capable window.

**Architecture:** Keep all rendering *logic* (bar geometry, vertex generation, the synthetic frame source) as pure Swift in the `MacVisualizerCore` framework so it is unit-tested with no GPU. Only the actual Metal device/pipeline/shaders and the `MTKView`/SwiftUI glue live in the app target. The GPU path is verified two ways: an offscreen **render probe** (`MacVisualizer --render-probe <path>`) that renders a known frame to a PNG for visual inspection (deterministic, needs no screen-recording permission), and running the live app.

**Tech Stack:** Swift 5.10, Metal, MetalKit (`MTKView`), SwiftUI (`NSViewRepresentable`), simd, Accelerate (already used by Core), XCTest, ImageIO/CoreGraphics (PNG writeback).

**Builds on Plan 1** (merged to `main`): `AudioFrame`, `VisualizerSettings`, `ColorPalette`/`RGBAColor`, `SpectrumAnalyzer`. This plan also resolves three Plan 1 carry-forward findings: add `bandPeaks` to `AudioFrame`; populate it in `SpectrumAnalyzer`; render peak caps only when `peakHoldEnabled`.

**Scope boundary — NOT in this plan:** real audio capture (Plan 3), track metadata overlay and the settings UI (Plan 4). Settings are read from disk via `VisualizerSettings.load(...)` (returns `.defaults` when absent) and are not yet editable in-app.

---

## File Structure

```
mac-visualizer/
  project.yml                                   # MODIFY: add Sources/Rendering to the app target sources
  Sources/
    Core/
      AudioFrame.swift                          # MODIFY: add `bandPeaks: [Float]`
      SpectrumAnalyzer.swift                    # MODIFY: populate bandPeaks
      BarLayout.swift                           # CREATE: pure per-bar horizontal geometry
      SyntheticFrameSource.swift                # CREATE: deterministic animated AudioFrames
      BarVertex.swift                           # CREATE: public vertex struct (matches Metal layout)
      Visualizer.swift                          # CREATE: Visualizer protocol
      SpectrumBarsVisualizer.swift              # CREATE: pure makeVertices (bars + caps)
    App/
      MacVisualizerApp.swift                    # MODIFY: @main entry routes to render-probe or UI; host MetalView; fullscreen
      RenderModel.swift                         # CREATE: ObservableObject holding settings + synthetic source
    Rendering/                                  # CREATE dir (app target)
      Shaders.metal                             # CREATE: passthrough vertex + flat fragment
      MetalRenderer.swift                       # CREATE: device/pipeline; render([BarVertex]) to a drawable or texture
      MetalView.swift                           # CREATE: NSViewRepresentable wrapping MTKView + render loop
      RenderProbe.swift                         # CREATE: offscreen render of a known frame to a PNG
  Tests/
    CoreTests/
      AudioFrameTests.swift                     # MODIFY: bandPeaks
      SpectrumAnalyzerTests.swift               # MODIFY: assert bandPeaks emitted
      BarLayoutTests.swift                      # CREATE
      SyntheticFrameSourceTests.swift           # CREATE
      SpectrumBarsVisualizerTests.swift         # CREATE
```

**Decomposition rationale:** `BarLayout`, `SyntheticFrameSource`, `BarVertex`, and `SpectrumBarsVisualizer.makeVertices` are pure (no Metal) and live in Core, so the bulk of rendering correctness is unit-tested. `MetalRenderer`/`Shaders.metal`/`MetalView`/`RenderProbe` are the irreducible GPU/UI layer, verified by the probe PNG and by running the app.

---

## Task 1: Add per-band peaks to `AudioFrame` and populate them in `SpectrumAnalyzer`

**Files:**
- Modify: `Sources/Core/AudioFrame.swift`
- Modify: `Sources/Core/SpectrumAnalyzer.swift`
- Modify: `Tests/CoreTests/AudioFrameTests.swift`
- Modify: `Tests/CoreTests/SpectrumAnalyzerTests.swift`

- [ ] **Step 1: Update the AudioFrame tests to expect `bandPeaks`**

Replace the entire contents of `Tests/CoreTests/AudioFrameTests.swift` with:

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
        XCTAssertEqual(frame.timestamp, 0)
    }

    func testInitStoresValues() {
        let frame = AudioFrame(bands: [0.1, 0.2, 0.3],
                               bandPeaks: [0.15, 0.25, 0.35],
                               rms: 0.4, peak: 0.9, timestamp: 12.5)
        XCTAssertEqual(frame.bands, [0.1, 0.2, 0.3])
        XCTAssertEqual(frame.bandPeaks, [0.15, 0.25, 0.35])
        XCTAssertEqual(frame.rms, 0.4)
        XCTAssertEqual(frame.peak, 0.9)
        XCTAssertEqual(frame.timestamp, 12.5)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail to compile**

Run: `make test`
Expected: FAIL — `incorrect argument label in call (have 'bands:rms:peak:timestamp:', expected ...)` / `value of type 'AudioFrame' has no member 'bandPeaks'`.

- [ ] **Step 3: Add `bandPeaks` to `AudioFrame`**

Replace the entire contents of `Sources/Core/AudioFrame.swift` with:

```swift
import QuartzCore

public struct AudioFrame: Equatable {
    public var bands: [Float]
    public var bandPeaks: [Float]
    public var rms: Float
    public var peak: Float
    public var timestamp: CFTimeInterval

    public init(bands: [Float], bandPeaks: [Float], rms: Float, peak: Float, timestamp: CFTimeInterval) {
        self.bands = bands
        self.bandPeaks = bandPeaks
        self.rms = rms
        self.peak = peak
        self.timestamp = timestamp
    }

    public static let silent = AudioFrame(bands: [], bandPeaks: [], rms: 0, peak: 0, timestamp: 0)
}
```

- [ ] **Step 4: Populate `bandPeaks` in `SpectrumAnalyzer.append`**

In `Sources/Core/SpectrumAnalyzer.swift`, find the return statement at the end of `append(_:)`:

```swift
        return AudioFrame(
            bands: processed.bands,
            rms: rms,
            peak: peak,
            timestamp: CACurrentMediaTime()
        )
```

Replace it with:

```swift
        return AudioFrame(
            bands: processed.bands,
            bandPeaks: processed.peaks,
            rms: rms,
            peak: peak,
            timestamp: CACurrentMediaTime()
        )
```

(`processed` is the tuple returned by `post.process(rawBands)`, whose `.peaks` is the per-band peak-hold array.)

- [ ] **Step 5: Strengthen the SpectrumAnalyzer tests to assert `bandPeaks`**

In `Tests/CoreTests/SpectrumAnalyzerTests.swift`, replace the `testEmitsFrameWithRequestedBandCount` and `testSilenceYieldsZeroEnergy` functions with:

```swift
    func testEmitsFrameWithRequestedBandCount() {
        let analyzer = makeAnalyzer(bands: 24)
        let frame = analyzer.append(SignalGenerators.silence(count: 2048))
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame!.bands.count, 24)
        XCTAssertEqual(frame!.bandPeaks.count, 24)
    }

    func testSilenceYieldsZeroEnergy() {
        let analyzer = makeAnalyzer()
        let frame = analyzer.append(SignalGenerators.silence(count: 2048))!
        XCTAssertEqual(frame.rms, 0, accuracy: 1e-4)
        XCTAssertEqual(frame.peak, 0, accuracy: 1e-4)
        XCTAssertEqual(frame.bands.max() ?? 0, 0, accuracy: 1e-3)
        XCTAssertEqual(frame.bandPeaks.max() ?? 0, 0, accuracy: 1e-3)
    }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `make test`
Expected: `** TEST SUCCEEDED **`, all tests pass (total 31; counts unchanged, two tests strengthened).

- [ ] **Step 7: Commit**

```bash
git add Sources/Core/AudioFrame.swift Sources/Core/SpectrumAnalyzer.swift Tests/CoreTests/AudioFrameTests.swift Tests/CoreTests/SpectrumAnalyzerTests.swift
git commit -m "Add per-band peaks to AudioFrame and emit them from SpectrumAnalyzer"
```

---

## Task 2: `BarLayout` (pure horizontal bar geometry)

**Files:**
- Create: `Sources/Core/BarLayout.swift`
- Test: `Tests/CoreTests/BarLayoutTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/CoreTests/BarLayoutTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class BarLayoutTests: XCTestCase {
    func testBarsPartitionFullWidthWhenNoGap() {
        let layout = BarLayout(barCount: 4, gapFraction: 0)
        XCTAssertEqual(layout.barXRange(0).start, 0, accuracy: 1e-6)
        XCTAssertEqual(layout.barXRange(3).end, 1, accuracy: 1e-6)
        // adjacent bars touch when there is no gap
        XCTAssertEqual(layout.barXRange(0).end, layout.barXRange(1).start, accuracy: 1e-6)
    }

    func testGapReducesBarWidth() {
        let layout = BarLayout(barCount: 4, gapFraction: 0.5)
        let width = layout.barXRange(0).end - layout.barXRange(0).start
        // slot width is 0.25; with gapFraction 0.5 the bar fills half the slot
        XCTAssertEqual(width, 0.25 * 0.5, accuracy: 1e-6)
    }

    func testBarsAreCenteredInTheirSlot() {
        let layout = BarLayout(barCount: 4, gapFraction: 0.2)
        let r = layout.barXRange(0)
        XCTAssertEqual((r.start + r.end) / 2, 0.125, accuracy: 1e-6) // center of slot [0,0.25]
    }

    func testBarsDoNotOverlap() {
        let layout = BarLayout(barCount: 16, gapFraction: 0.2)
        for i in 0..<15 {
            XCTAssertLessThanOrEqual(layout.barXRange(i).end, layout.barXRange(i + 1).start + 1e-6)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `cannot find 'BarLayout' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/Core/BarLayout.swift`:

```swift
import Foundation

/// Pure horizontal layout: maps a bar index to its normalized [0,1] x-extent.
/// Bars are evenly spaced; `gapFraction` is the portion of each slot left as a gap.
public struct BarLayout: Equatable {
    public let barCount: Int
    public let gapFraction: Float

    public init(barCount: Int, gapFraction: Float = 0.2) {
        precondition(barCount > 0, "barCount must be positive")
        precondition(gapFraction >= 0 && gapFraction < 1, "gapFraction must be in [0,1)")
        self.barCount = barCount
        self.gapFraction = gapFraction
    }

    /// Normalized [0,1] horizontal extent of the bar at `index`, centered in its slot.
    public func barXRange(_ index: Int) -> (start: Float, end: Float) {
        let slot = 1 / Float(barCount)
        let gap = slot * gapFraction
        let start = Float(index) * slot + gap / 2
        let end = Float(index + 1) * slot - gap / 2
        return (start, end)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test`
Expected: `** TEST SUCCEEDED **`, all four `BarLayoutTests` pass (total 35).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/BarLayout.swift Tests/CoreTests/BarLayoutTests.swift
git commit -m "Add BarLayout pure bar geometry"
```

---

## Task 3: `SyntheticFrameSource` (deterministic animated frames)

**Files:**
- Create: `Sources/Core/SyntheticFrameSource.swift`
- Test: `Tests/CoreTests/SyntheticFrameSourceTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/CoreTests/SyntheticFrameSourceTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class SyntheticFrameSourceTests: XCTestCase {
    func testProducesRequestedBandCounts() {
        let source = SyntheticFrameSource(bandCount: 32)
        let frame = source.frame(at: 0)
        XCTAssertEqual(frame.bands.count, 32)
        XCTAssertEqual(frame.bandPeaks.count, 32)
    }

    func testAllValuesAreInUnitRange() {
        let source = SyntheticFrameSource(bandCount: 48)
        for t in stride(from: 0.0, through: 3.0, by: 0.25) {
            let frame = source.frame(at: t)
            for v in frame.bands { XCTAssertTrue((0...1).contains(v), "band \(v) out of range at t=\(t)") }
            for v in frame.bandPeaks { XCTAssertTrue((0...1).contains(v)) }
        }
    }

    func testAnimatesOverTime() {
        let source = SyntheticFrameSource(bandCount: 16)
        let a = source.frame(at: 0).bands
        let b = source.frame(at: 1).bands
        XCTAssertNotEqual(a, b, "frames should differ as time advances")
    }

    func testPeaksAtLeastBands() {
        let source = SyntheticFrameSource(bandCount: 16)
        let frame = source.frame(at: 0.5)
        for i in 0..<frame.bands.count {
            XCTAssertGreaterThanOrEqual(frame.bandPeaks[i], frame.bands[i] - 1e-6)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `cannot find 'SyntheticFrameSource' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/Core/SyntheticFrameSource.swift`:

```swift
import Foundation

/// Generates deterministic, animated `AudioFrame`s so the renderer has lively
/// input before real audio capture exists. `frame(at:)` is a pure function of time.
public struct SyntheticFrameSource {
    public let bandCount: Int

    public init(bandCount: Int) {
        precondition(bandCount > 0, "bandCount must be positive")
        self.bandCount = bandCount
    }

    public func frame(at t: TimeInterval) -> AudioFrame {
        let tf = Float(t)
        let twoPi: Float = 2 * .pi
        var bands = [Float](repeating: 0, count: bandCount)

        // A sweeping Gaussian bump plus a per-band oscillation, clamped to [0,1].
        let sweepCenter = (sinf(tf * 0.7) * 0.5 + 0.5) * Float(max(bandCount - 1, 1))
        let sigma: Float = 2

        for i in 0..<bandCount {
            let phase = Float(i) / Float(bandCount) * twoPi
            let oscillation = 0.5 + 0.5 * sinf(tf * 2.0 + phase)
            let dist = Float(i) - sweepCenter
            let bump = expf(-(dist * dist) / (2 * sigma * sigma))
            let level = 0.12 + 0.45 * oscillation + 0.5 * bump
            bands[i] = min(max(level, 0), 1)
        }

        let peak = bands.max() ?? 0
        let sumSquares = bands.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = (bands.isEmpty ? 0 : sqrtf(sumSquares / Float(bandCount)))
        let bandPeaks = bands.map { min($0 + 0.05, 1) }

        return AudioFrame(bands: bands, bandPeaks: bandPeaks, rms: rms, peak: peak, timestamp: t)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test`
Expected: `** TEST SUCCEEDED **`, all four `SyntheticFrameSourceTests` pass (total 39).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/SyntheticFrameSource.swift Tests/CoreTests/SyntheticFrameSourceTests.swift
git commit -m "Add SyntheticFrameSource for driving rendering before capture"
```

---

## Task 4: `BarVertex`, `Visualizer` protocol, and `SpectrumBarsVisualizer.makeVertices`

**Files:**
- Create: `Sources/Core/BarVertex.swift`
- Create: `Sources/Core/Visualizer.swift`
- Create: `Sources/Core/SpectrumBarsVisualizer.swift`
- Test: `Tests/CoreTests/SpectrumBarsVisualizerTests.swift`

Design: `makeVertices` is pure — it turns an `AudioFrame` + `VisualizerSettings` into a flat list of triangle vertices in Metal clip space (x,y ∈ [-1,1]). Each bar is two triangles (6 vertices) growing up from the bottom (y=-1); vertical color comes from the palette gradient (bottom = `palette.sample(0)`, top = `palette.sample(level)`). When `peakHoldEnabled`, each bar adds a thin cap quad (6 vertices) at its `bandPeaks` height.

- [ ] **Step 1: Write the failing test**

`Tests/CoreTests/SpectrumBarsVisualizerTests.swift`:

```swift
import XCTest
import simd
@testable import MacVisualizerCore

final class SpectrumBarsVisualizerTests: XCTestCase {
    private func settings(bands: Int, peakHold: Bool, palette: String = "classic") -> VisualizerSettings {
        var s = VisualizerSettings.defaults
        s.barCount = bands
        s.peakHoldEnabled = peakHold
        s.paletteName = palette
        return s
    }

    private func frame(bands: [Float], peaks: [Float]) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: peaks, rms: 0, peak: 0, timestamp: 0)
    }

    func testSixVerticesPerBarWithoutPeakHold() {
        let viz = SpectrumBarsVisualizer()
        let f = frame(bands: [0.2, 0.5, 0.9], peaks: [0.3, 0.6, 1.0])
        let verts = viz.makeVertices(frame: f, settings: settings(bands: 3, peakHold: false))
        XCTAssertEqual(verts.count, 3 * 6)
    }

    func testTwelveVerticesPerBarWithPeakHold() {
        let viz = SpectrumBarsVisualizer()
        let f = frame(bands: [0.2, 0.5, 0.9], peaks: [0.3, 0.6, 1.0])
        let verts = viz.makeVertices(frame: f, settings: settings(bands: 3, peakHold: true))
        XCTAssertEqual(verts.count, 3 * 12) // 6 for the bar + 6 for the cap
    }

    func testAllVerticesAreInsideClipSpace() {
        let viz = SpectrumBarsVisualizer()
        let f = frame(bands: [0, 0.5, 1.0], peaks: [0.1, 0.6, 1.0])
        let verts = viz.makeVertices(frame: f, settings: settings(bands: 3, peakHold: true))
        for v in verts {
            XCTAssertTrue((-1...1).contains(v.position.x), "x \(v.position.x) out of clip space")
            XCTAssertTrue((-1...1).contains(v.position.y), "y \(v.position.y) out of clip space")
        }
    }

    func testTallerBarReachesHigher() {
        let viz = SpectrumBarsVisualizer()
        let f = frame(bands: [0.2, 0.8], peaks: [0.2, 0.8])
        let verts = viz.makeVertices(frame: f, settings: settings(bands: 2, peakHold: false))
        // bar 0 = vertices 0..5, bar 1 = vertices 6..11
        let bar0Top = verts[0..<6].map { $0.position.y }.max()!
        let bar1Top = verts[6..<12].map { $0.position.y }.max()!
        XCTAssertGreaterThan(bar1Top, bar0Top)
    }

    func testZeroLevelBarHasZeroHeight() {
        let viz = SpectrumBarsVisualizer()
        let f = frame(bands: [0.0], peaks: [0.0])
        let verts = viz.makeVertices(frame: f, settings: settings(bands: 1, peakHold: false))
        let ys = verts.map { $0.position.y }
        for y in ys { XCTAssertEqual(y, -1, accuracy: 1e-5) } // top == bottom == -1
    }

    func testBottomVertexUsesPaletteBottomColor() {
        let viz = SpectrumBarsVisualizer()
        let f = frame(bands: [1.0], peaks: [1.0])
        let verts = viz.makeVertices(frame: f, settings: settings(bands: 1, peakHold: false, palette: "phosphor"))
        let bottomColor = ColorPalette.preset(named: "phosphor")!.sample(at: 0)
        // A bottom vertex sits at y == -1.
        let bottom = verts.first { abs($0.position.y - (-1)) < 1e-5 }!
        XCTAssertEqual(bottom.color.x, bottomColor.r, accuracy: 1e-4)
        XCTAssertEqual(bottom.color.y, bottomColor.g, accuracy: 1e-4)
        XCTAssertEqual(bottom.color.z, bottomColor.b, accuracy: 1e-4)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `cannot find 'SpectrumBarsVisualizer' in scope` (and `BarVertex`).

- [ ] **Step 3: Write `BarVertex`**

`Sources/Core/BarVertex.swift`:

```swift
import simd

/// One vertex for the bar renderer. Layout MUST match the `Vertex` struct in Shaders.metal:
/// two 16-byte-aligned float4s, total stride 32 bytes. `position.xy` is Metal clip space.
public struct BarVertex: Equatable {
    public var position: SIMD4<Float> // xy used (clip space), zw unused
    public var color: SIMD4<Float>    // rgba, 0...1

    public init(position: SIMD4<Float>, color: SIMD4<Float>) {
        self.position = position
        self.color = color
    }
}
```

- [ ] **Step 4: Write the `Visualizer` protocol**

`Sources/Core/Visualizer.swift`:

```swift
/// A visualizer turns an audio frame + settings into triangle vertices in clip space.
/// Pure and GPU-free so it can be unit-tested; the Metal renderer encodes the result.
public protocol Visualizer {
    func makeVertices(frame: AudioFrame, settings: VisualizerSettings) -> [BarVertex]
}
```

- [ ] **Step 5: Write `SpectrumBarsVisualizer`**

`Sources/Core/SpectrumBarsVisualizer.swift`:

```swift
import simd

/// Classic spectrum bars: each band is a bottom-anchored bar with a vertical
/// palette gradient, plus an optional peak-hold cap.
public struct SpectrumBarsVisualizer: Visualizer {
    public init() {}

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings) -> [BarVertex] {
        let count = frame.bands.count
        guard count > 0 else { return [] }

        let layout = BarLayout(barCount: count)
        let palette = ColorPalette.preset(named: settings.paletteName)
            ?? ColorPalette.preset(named: "classic")!

        var verts: [BarVertex] = []
        verts.reserveCapacity(count * (settings.peakHoldEnabled ? 12 : 6))

        for i in 0..<count {
            let level = min(max(frame.bands[i], 0), 1)
            let (xs, xe) = layout.barXRange(i)
            let x0 = xs * 2 - 1               // [0,1] -> clip [-1,1]
            let x1 = xe * 2 - 1
            let yBottom: Float = -1
            let yTop = -1 + 2 * level

            let cBottom = rgba(palette.sample(at: 0))
            let cTop = rgba(palette.sample(at: level))

            appendQuad(&verts, x0: x0, x1: x1, yLow: yBottom, yHigh: yTop,
                       colorLow: cBottom, colorHigh: cTop)

            if settings.peakHoldEnabled {
                let peak = min(max(i < frame.bandPeaks.count ? frame.bandPeaks[i] : 0, 0), 1)
                let capCenter = -1 + 2 * peak
                let capHalf: Float = 0.01 // ~1% of clip height
                let capLow = min(max(capCenter - capHalf, -1), 1)
                let capHigh = min(max(capCenter + capHalf, -1), 1)
                let capColor = rgba(palette.sample(at: peak))
                appendQuad(&verts, x0: x0, x1: x1, yLow: capLow, yHigh: capHigh,
                           colorLow: capColor, colorHigh: capColor)
            }
        }
        return verts
    }

    private func rgba(_ c: RGBAColor) -> SIMD4<Float> { SIMD4<Float>(c.r, c.g, c.b, c.a) }

    /// Two triangles forming the axis-aligned rectangle [x0,x1] × [yLow,yHigh].
    /// Bottom vertices use `colorLow`, top vertices use `colorHigh`.
    private func appendQuad(_ verts: inout [BarVertex],
                            x0: Float, x1: Float, yLow: Float, yHigh: Float,
                            colorLow: SIMD4<Float>, colorHigh: SIMD4<Float>) {
        let bl = BarVertex(position: SIMD4<Float>(x0, yLow, 0, 1), color: colorLow)
        let br = BarVertex(position: SIMD4<Float>(x1, yLow, 0, 1), color: colorLow)
        let tl = BarVertex(position: SIMD4<Float>(x0, yHigh, 0, 1), color: colorHigh)
        let tr = BarVertex(position: SIMD4<Float>(x1, yHigh, 0, 1), color: colorHigh)
        verts.append(contentsOf: [bl, br, tl, br, tr, tl])
    }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `make test`
Expected: `** TEST SUCCEEDED **`, all seven `SpectrumBarsVisualizerTests` pass (total 46).

- [ ] **Step 7: Commit**

```bash
git add Sources/Core/BarVertex.swift Sources/Core/Visualizer.swift Sources/Core/SpectrumBarsVisualizer.swift Tests/CoreTests/SpectrumBarsVisualizerTests.swift
git commit -m "Add Visualizer protocol and pure spectrum-bars vertex generation"
```

---

## Task 5: Metal shaders, pipeline, and a clear-only render probe

**Files:**
- Modify: `project.yml`
- Create: `Sources/Rendering/Shaders.metal`
- Create: `Sources/Rendering/MetalRenderer.swift`
- Create: `Sources/Rendering/RenderProbe.swift`
- Modify: `Sources/App/MacVisualizerApp.swift`

This task builds the Metal pipeline and proves it works by rendering a **solid background color** to an offscreen PNG (no bars yet). Bars come in Task 6.

- [ ] **Step 1: Add `Sources/Rendering` to the app target in `project.yml`**

In `project.yml`, change the `MacVisualizer` app target's `sources` from:

```yaml
    sources:
      - Sources/App
```

to:

```yaml
    sources:
      - Sources/App
      - Sources/Rendering
```

- [ ] **Step 2: Write the Metal shaders**

`Sources/Rendering/Shaders.metal`:

```metal
#include <metal_stdlib>
using namespace metal;

// Must match BarVertex in Swift: two float4s, stride 32 bytes.
struct Vertex {
    float4 position; // xy = clip space
    float4 color;    // rgba
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

vertex VertexOut vs_main(const device Vertex *verts [[buffer(0)]],
                         uint vid [[vertex_id]]) {
    VertexOut out;
    out.position = float4(verts[vid].position.xy, 0.0, 1.0);
    out.color = verts[vid].color;
    return out;
}

fragment float4 fs_main(VertexOut in [[stage_in]]) {
    return in.color;
}
```

- [ ] **Step 3: Write `MetalRenderer`**

`Sources/Rendering/MetalRenderer.swift`:

```swift
import Metal
import MetalKit
import simd
import MacVisualizerCore

/// Owns the Metal device, command queue, and render pipeline. Encodes a list of
/// `BarVertex` triangles into a render pass. Used both by the live `MTKView` and
/// the offscreen render probe.
final class MetalRenderer {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    init?(pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vfn = library.makeFunction(name: "vs_main"),
              let ffn = library.makeFunction(name: "fs_main")
        else { return nil }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = pixelFormat

        guard let state = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }

        self.device = device
        self.commandQueue = queue
        self.pipeline = state
    }

    /// Background clear color. Plan 2 renders a solid black background regardless of
    /// `backgroundStyle` (the gradient option is a later visual-polish item; there is
    /// no settings UI to change it from `.solid` until Plan 4).
    func clearColor(for settings: VisualizerSettings) -> MTLClearColor {
        MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    }

    /// Encode one frame: clear to `clearColor`, then draw `vertices` as triangles.
    /// `descriptor` must have its color attachment texture and load/store actions set
    /// by the caller (drawable for live view, offscreen texture for the probe).
    func encode(vertices: [BarVertex],
                clearColor: MTLClearColor,
                into descriptor: MTLRenderPassDescriptor,
                commandBuffer: MTLCommandBuffer) {
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = clearColor
        descriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.setRenderPipelineState(pipeline)

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
    }

    func makeCommandBuffer() -> MTLCommandBuffer? { commandQueue.makeCommandBuffer() }
}
```

- [ ] **Step 4: Write `RenderProbe` (clear-only for now)**

`Sources/Rendering/RenderProbe.swift`:

```swift
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import simd
import MacVisualizerCore

/// Renders a single frame offscreen to a PNG for deterministic visual verification.
/// Invoked via `MacVisualizer --render-probe <path>`.
enum RenderProbe {
    static func run(outputPath: String, width: Int = 800, height: Int = 400) -> Bool {
        guard let renderer = MetalRenderer(pixelFormat: .bgra8Unorm) else {
            FileHandle.standardError.write(Data("RenderProbe: no Metal device\n".utf8))
            return false
        }

        let settings = VisualizerSettings.defaults

        // Offscreen render target.
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .managed
        guard let texture = renderer.device.makeTexture(descriptor: texDesc),
              let commandBuffer = renderer.makeCommandBuffer() else { return false }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture

        // Task 5: clear only, no bars yet.
        renderer.encode(vertices: [],
                        clearColor: MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                        into: pass, commandBuffer: commandBuffer)

        // Blit to make managed texture contents readable on CPU.
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.synchronize(resource: texture)
            blit.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return writePNG(texture: texture, width: width, height: height, to: outputPath)
    }

    private static func writePNG(texture: MTLTexture, width: Int, height: Int, to path: String) -> Bool {
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        texture.getBytes(&data, bytesPerRow: bytesPerRow,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        // bgra8Unorm bytes -> CGImage via premultipliedFirst + little-endian (ARGB in memory order = BGRA).
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: &data, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                  space: colorSpace, bitmapInfo: bitmapInfo),
              let image = ctx.makeImage() else { return false }

        let url = URL(fileURLWithPath: path)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }
}
```

- [ ] **Step 5: Route `@main` to the probe or the UI**

Replace the entire contents of `Sources/App/MacVisualizerApp.swift` with:

```swift
import SwiftUI

@main
enum AppEntry {
    static func main() {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--render-probe"), idx + 1 < args.count {
            let ok = RenderProbe.run(outputPath: args[idx + 1])
            exit(ok ? 0 : 1)
        }
        MacVisualizerMain.main()
    }
}

struct MacVisualizerMain: App {
    var body: some Scene {
        Window("Mac Visualizer", id: "main") {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        Color.black
            .ignoresSafeArea()
            .frame(minWidth: 640, minHeight: 360)
    }
}
```

- [ ] **Step 6: Build, then run the probe and inspect the PNG**

Run: `make build`
Expected: `** BUILD SUCCEEDED **`.

Run the probe:
```bash
./DerivedData/Build/Products/Debug/MacVisualizer.app/Contents/MacOS/MacVisualizer --render-probe /tmp/probe5.png && echo "exit=$?"
```
Expected: exit 0 and `/tmp/probe5.png` created.

Verify the image: use the Read tool on `/tmp/probe5.png`. Expected: an 800×400 image filled with a uniform dark blue-grey (the clear color ~RGB 13,13,20). Confirm it is a solid, non-black, uniform color (proves the pipeline clears and writes correctly). If the file is missing, all-black, or `make build` fails on the Metal compile, report the exact error (BLOCKED) — do not weaken the probe.

- [ ] **Step 7: Confirm tests still pass**

Run: `make test`
Expected: `** TEST SUCCEEDED **` (still 46 Core tests; the app/render code is not unit-tested).

- [ ] **Step 8: Commit**

```bash
git add project.yml Sources/Rendering/Shaders.metal Sources/Rendering/MetalRenderer.swift Sources/Rendering/RenderProbe.swift Sources/App/MacVisualizerApp.swift
git commit -m "Add Metal pipeline and clear-only offscreen render probe"
```

---

## Task 6: Render bars in the probe

**Files:**
- Modify: `Sources/Rendering/RenderProbe.swift`

Now draw real bars in the probe using a known **ramp** frame (band levels increasing left→right), producing a predictable staircase image.

- [ ] **Step 1: Replace the clear-only encode with a ramp frame**

In `Sources/Rendering/RenderProbe.swift`, replace this block:

```swift
        // Task 5: clear only, no bars yet.
        renderer.encode(vertices: [],
                        clearColor: MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                        into: pass, commandBuffer: commandBuffer)
```

with:

```swift
        // A ramp frame: band levels increase left -> right, so the PNG shows a staircase.
        let bandCount = settings.barCount
        let bands = (0..<bandCount).map { Float($0) / Float(max(bandCount - 1, 1)) }
        let peaks = bands.map { min($0 + 0.05, 1) }
        let frame = AudioFrame(bands: bands, bandPeaks: peaks, rms: 0, peak: bands.last ?? 0, timestamp: 0)
        let vertices = SpectrumBarsVisualizer().makeVertices(frame: frame, settings: settings)

        renderer.encode(vertices: vertices,
                        clearColor: MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                        into: pass, commandBuffer: commandBuffer)
```

- [ ] **Step 2: Build and run the probe**

Run: `make build`
Expected: `** BUILD SUCCEEDED **`.

```bash
./DerivedData/Build/Products/Debug/MacVisualizer.app/Contents/MacOS/MacVisualizer --render-probe /tmp/probe6.png && echo "exit=$?"
```
Expected: exit 0, `/tmp/probe6.png` created.

- [ ] **Step 3: Inspect the PNG**

Use the Read tool on `/tmp/probe6.png`. Expected: on the dark blue-grey background, a row of vertical bars whose heights increase from left (very short) to right (full height), colored with the "classic" palette gradient (green near the bottom shifting toward red at the top of the tall bars), each tall bar topped by a thin peak-hold cap. Confirm: (a) bars are visible, (b) they form a left→right increasing staircase, (c) the tallest (rightmost) bar nearly fills the height. If the image is blank/all-background or the staircase is absent or inverted, report what you observe (DONE_WITH_CONCERNS) with the image — do not alter the test frame to mask it.

- [ ] **Step 4: Commit**

```bash
git add Sources/Rendering/RenderProbe.swift
git commit -m "Render spectrum bars in the offscreen probe (ramp frame)"
```

---

## Task 7: Live `MTKView` driven by the synthetic frame source

**Files:**
- Create: `Sources/App/RenderModel.swift`
- Create: `Sources/Rendering/MetalView.swift`
- Modify: `Sources/App/MacVisualizerApp.swift` (wire `MetalView` into `ContentView`)

- [ ] **Step 1: Write `RenderModel`**

`Sources/App/RenderModel.swift`:

```swift
import SwiftUI
import QuartzCore
import MacVisualizerCore

/// Holds the live settings and the frame source that drives rendering.
/// For Plan 2 the source is synthetic; Plan 3 swaps in the real analyzer.
final class RenderModel: ObservableObject {
    @Published var settings: VisualizerSettings
    let source: SyntheticFrameSource

    init() {
        let loaded = VisualizerSettings.load(from: VisualizerSettings.defaultFileURL())
        self.settings = loaded
        self.source = SyntheticFrameSource(bandCount: loaded.barCount)
    }

    /// The frame to render right now.
    func currentFrame() -> AudioFrame {
        source.frame(at: CACurrentMediaTime())
    }
}
```

- [ ] **Step 2: Write `MetalView`**

`Sources/Rendering/MetalView.swift`:

```swift
import SwiftUI
import MetalKit
import MacVisualizerCore

/// SwiftUI wrapper around an `MTKView` that continuously renders frames from the model.
struct MetalView: NSViewRepresentable {
    @ObservedObject var model: RenderModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        guard let coordinator = context.coordinator.renderer else { return view }
        view.device = coordinator.device
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = max(30, model.settings.targetFPS)
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        view.preferredFramesPerSecond = max(30, model.settings.targetFPS)
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        let model: RenderModel
        let renderer: MetalRenderer?
        private let visualizer = SpectrumBarsVisualizer()

        init(model: RenderModel) {
            self.model = model
            self.renderer = MetalRenderer(pixelFormat: .bgra8Unorm)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let renderer,
                  let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let commandBuffer = renderer.makeCommandBuffer()
            else { return }

            let frame = model.currentFrame()
            let vertices = visualizer.makeVertices(frame: frame, settings: model.settings)
            renderer.encode(vertices: vertices,
                            clearColor: renderer.clearColor(for: model.settings),
                            into: descriptor, commandBuffer: commandBuffer)
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
```

- [ ] **Step 3: Wire `MetalView` into `ContentView`**

In `Sources/App/MacVisualizerApp.swift`, replace the `MacVisualizerMain` struct and `ContentView` struct with:

```swift
struct MacVisualizerMain: App {
    @StateObject private var model = RenderModel()

    var body: some Scene {
        Window("Mac Visualizer", id: "main") {
            ContentView(model: model)
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: RenderModel

    var body: some View {
        MetalView(model: model)
            .ignoresSafeArea()
            .frame(minWidth: 640, minHeight: 360)
    }
}
```

(Leave the `AppEntry` enum unchanged — it still routes `--render-probe` before the UI starts.)

- [ ] **Step 4: Build**

Run: `make build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run the app and verify animated bars**

Launch:
```bash
make run
```
The app window opens. Wait ~2 seconds, then capture it for inspection:
```bash
screencapture -x -o /tmp/live7.png
```
Use the Read tool on `/tmp/live7.png`. Expected: the visualizer window shows a field of spectrum bars with the classic green→red palette, a moving Gaussian "bump" sweeping across the bands, and thin peak caps. (If `screencapture` produces a black or permission-blocked image, instead confirm by asking the user to look at the window; do NOT claim success from an unverifiable capture.) Confirm bars are visible and animating (two captures a second apart should differ).

Quit the app (Cmd-Q) when done.

- [ ] **Step 6: Confirm tests still pass**

Run: `make test`
Expected: `** TEST SUCCEEDED **` (46 Core tests).

- [ ] **Step 7: Commit**

```bash
git add Sources/App/RenderModel.swift Sources/Rendering/MetalView.swift Sources/App/MacVisualizerApp.swift
git commit -m "Render live animated spectrum bars in an MTKView"
```

---

## Task 8: Fullscreen toggle and always-on-top

**Files:**
- Modify: `Sources/App/MacVisualizerApp.swift`

Add a View menu with **Toggle Full Screen** (⌘F via the standard AppKit action) and honor the `alwaysOnTop` setting on the window.

- [ ] **Step 1: Add the fullscreen menu command and window-level handling**

In `Sources/App/MacVisualizerApp.swift`, first ensure the imports at the very top of the file are exactly:

```swift
import SwiftUI
import AppKit
import MacVisualizerCore
```

(`AppKit` is needed for `NSApp`, `NSWindow.toggleFullScreen`, `NSView`, and `NSWindow.Level`; `MacVisualizerCore` is needed to read `model.settings.alwaysOnTop`, whose type `VisualizerSettings` lives in that module.)

Then update the `MacVisualizerMain` scene to add `.commands` and a window accessor. Replace the `MacVisualizerMain` struct with:

```swift
struct MacVisualizerMain: App {
    @StateObject private var model = RenderModel()

    var body: some Scene {
        Window("Mac Visualizer", id: "main") {
            ContentView(model: model)
                .background(WindowConfigurator(alwaysOnTop: model.settings.alwaysOnTop))
        }
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Toggle Full Screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
            }
        }
    }
}

/// Applies window-level chrome (always-on-top) once the window exists.
private struct WindowConfigurator: NSViewRepresentable {
    let alwaysOnTop: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [alwaysOnTop] in
            view.window?.level = alwaysOnTop ? .floating : .normal
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.level = alwaysOnTop ? .floating : .normal
    }
}
```

Note: macOS already provides a default ⌘-Control-F "Enter Full Screen" menu item; this explicit command guarantees a discoverable toggle bound to the same standard shortcut. The native green-button and `View > Enter Full Screen` continue to work as well.

- [ ] **Step 2: Build**

Run: `make build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run and verify fullscreen**

Run: `make run`. With the window focused, press ⌃⌘F (or use the menu item). Expected: the window enters macOS fullscreen and the bars fill the screen; pressing again exits. Confirm the bars still render and animate in fullscreen. (This step is verified by running; if you cannot interactively verify, ask the user to confirm.) Quit when done.

- [ ] **Step 4: Confirm tests still pass and the probe still works**

Run: `make test`
Expected: `** TEST SUCCEEDED **`.

Run:
```bash
make build && ./DerivedData/Build/Products/Debug/MacVisualizer.app/Contents/MacOS/MacVisualizer --render-probe /tmp/probe8.png && echo "exit=$?"
```
Expected: exit 0, PNG still shows the staircase bars (regression check that menu/window changes didn't break the probe path).

- [ ] **Step 5: Commit**

```bash
git add Sources/App/MacVisualizerApp.swift
git commit -m "Add fullscreen toggle command and always-on-top window handling"
```

---

## Definition of Done (Plan 2)

- `make test` → `** TEST SUCCEEDED **` with 46 Core tests green (pure rendering logic fully unit-tested).
- `make build` → `** BUILD SUCCEEDED **`.
- `MacVisualizer --render-probe /tmp/p.png` writes a PNG showing the classic spectrum bars (ramp staircase), confirming the Metal pipeline + shaders + `SpectrumBarsVisualizer` draw correctly.
- `make run` shows a resizable window of live, animated spectrum bars (synthetic source), with palette gradient and peak caps, and ⌃⌘F toggles fullscreen.
- Plan 1 carry-forward resolved: `AudioFrame.bandPeaks` exists and is emitted by `SpectrumAnalyzer`; peak caps render only when `peakHoldEnabled`.

## Handoff to Plan 3 (Audio Capture)

Plan 3 replaces `RenderModel`'s `SyntheticFrameSource` with a real pipeline: a Core Audio process tap (scoped to Spotify/Music PIDs) feeding `SpectrumAnalyzer`, delivering live `AudioFrame`s to the same `MetalView`. The renderer, visualizer, and vertex path built here stay unchanged — only the frame *source* changes. Also revisit the deferred ring-buffer overlap/hop finding from Plan 1 when wiring real capture, and confirm the `targetFPS`/`drawableSizeWillChange` handling under sustained real-time load.
