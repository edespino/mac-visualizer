# Mac Music Visualizer — Plan 1: Foundation & Core DSP

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a buildable native macOS Xcode project and a fully unit-tested, pure-Swift audio-analysis core that turns PCM samples into normalized spectrum-band data.

**Architecture:** A reproducible XcodeGen project with three targets — a `MacVisualizerCore` framework (pure Swift, no UIKit/AppKit/Metal), a minimal `MacVisualizer` SwiftUI app (an empty black window, proving end-to-end build), and a `MacVisualizerCoreTests` logic-test bundle. The DSP pipeline (Hann window → vDSP FFT → log-spaced band mapping → gain/smoothing/peak-hold) lives entirely in Core and is deterministic, so it is verified by XCTest with synthetic signals.

**Tech Stack:** Swift 5.9, XcodeGen, SwiftUI (app shell only), Accelerate/`vDSP`, XCTest.

**Scope boundary:** This plan ships NO audio capture, NO rendering, NO metadata. Those are Plans 2–4. The app target here is a placeholder window that proves the project generates and builds.

---

## File Structure

```
mac-visualizer/
  project.yml                                   # XcodeGen definition (create)
  Makefile                                      # generate/build/test/run/clean (create)
  .gitignore                                    # ignore build artifacts (create)
  Sources/
    App/
      MacVisualizerApp.swift                    # @main SwiftUI app, empty window (create)
    Core/
      AudioFrame.swift                          # value type: bands/rms/peak/timestamp (create)
      VisualizerSettings.swift                  # Codable config + JSON persistence (create)
      ColorPalette.swift                        # named palettes + gradient sampling (create)
      HannWindow.swift                          # windowing helper (create)
      FFTProcessor.swift                        # vDSP real FFT → magnitudes (create)
      BandMapper.swift                          # log-spaced bin→band mapping (create)
      BandPostProcessor.swift                   # dB/normalize/gain/smoothing/peak-hold (create)
      SpectrumAnalyzer.swift                    # orchestrates the full pipeline (create)
  Tests/
    CoreTests/
      AudioFrameTests.swift                     # (create)
      VisualizerSettingsTests.swift             # (create)
      ColorPaletteTests.swift                   # (create)
      HannWindowTests.swift                     # (create)
      FFTProcessorTests.swift                   # (create)
      BandMapperTests.swift                     # (create)
      BandPostProcessorTests.swift              # (create)
      SpectrumAnalyzerTests.swift               # (create)
      SignalGenerators.swift                    # shared sine/silence test helpers (create)
```

**Responsibility per file:** each Core file is one stage of the pipeline with a small, pure interface. `SpectrumAnalyzer` is the only orchestrator; everything else is a leaf it composes. Tests mirror source files 1:1, plus one shared helper for synthetic signals.

---

## Task 0: Verify tooling is available

**Files:** none.

- [ ] **Step 1: Confirm Xcode command-line build works**

Run: `xcodebuild -version`
Expected: prints `Xcode 16.x` (or any installed version) and a build number. If it errors with "xcode-select", the engineer must install Xcode and run `sudo xcode-select -s /Applications/Xcode.app`. STOP and resolve before continuing.

- [ ] **Step 2: Confirm XcodeGen is installed**

Run: `which xcodegen && xcodegen --version`
Expected: a path and a version (e.g. `2.x`). If not found, install it: `brew install xcodegen` (requires Homebrew). Ask the user before running any install command.

---

## Task 1: Project scaffolding (generate + build empty app + run empty tests)

**Files:**
- Create: `project.yml`
- Create: `Makefile`
- Create: `.gitignore`
- Create: `Sources/App/MacVisualizerApp.swift`
- Create: `Tests/CoreTests/.gitkeep` (placeholder so the source dir exists for XcodeGen)
- Create: `Sources/Core/.gitkeep` (placeholder so the source dir exists for XcodeGen)

- [ ] **Step 1: Write `project.yml`**

```yaml
name: MacVisualizer
options:
  bundleIdPrefix: com.example
  deploymentTarget:
    macOS: "14.4"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "5.9"
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
  configs:
    debug:
      ENABLE_TESTABILITY: YES
targets:
  MacVisualizerCore:
    type: framework
    platform: macOS
    sources:
      - Sources/Core
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.MacVisualizerCore
  MacVisualizer:
    type: application
    platform: macOS
    sources:
      - Sources/App
    dependencies:
      - target: MacVisualizerCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.MacVisualizer
    info:
      path: Sources/App/Info.plist
      properties:
        CFBundleDisplayName: Mac Visualizer
        LSMinimumSystemVersion: "14.4"
        NSHighResolutionCapable: true
  MacVisualizerCoreTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests/CoreTests
    dependencies:
      - target: MacVisualizerCore
schemes:
  MacVisualizer:
    build:
      targets:
        MacVisualizer: all
        MacVisualizerCoreTests: [test]
    run:
      config: debug
    test:
      config: debug
      targets:
        - MacVisualizerCoreTests
```

- [ ] **Step 2: Write `Makefile`**

```makefile
DERIVED := DerivedData
PROJECT := MacVisualizer.xcodeproj
SCHEME  := MacVisualizer
DEST    := platform=macOS

.PHONY: generate build test run clean

generate:
	xcodegen generate

build: generate
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DEST)' -derivedDataPath $(DERIVED)

test: generate
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' -derivedDataPath $(DERIVED)

run: build
	open $(DERIVED)/Build/Products/Debug/MacVisualizer.app

clean:
	rm -rf $(PROJECT) $(DERIVED)
```

- [ ] **Step 3: Write `.gitignore`**

```gitignore
# XcodeGen output (regenerated from project.yml)
MacVisualizer.xcodeproj/
# Build output
DerivedData/
build/
# macOS
.DS_Store
# Xcode user state
xcuserdata/
*.xcuserstate
```

- [ ] **Step 4: Write `Sources/App/MacVisualizerApp.swift`**

```swift
import SwiftUI

@main
struct MacVisualizerApp: App {
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

- [ ] **Step 5: Create placeholder files so XcodeGen source dirs exist**

Create empty files `Sources/Core/.gitkeep` and `Tests/CoreTests/.gitkeep`.

- [ ] **Step 6: Generate and build**

Run: `make build`
Expected: `xcodegen generate` prints "Created project at MacVisualizer.xcodeproj", then `xcodebuild` ends with `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Run the (empty) test bundle**

Run: `make test`
Expected: `** TEST SUCCEEDED **` (zero tests run is acceptable at this point; the bundle must compile and the action must succeed).

- [ ] **Step 8: Commit**

```bash
git add project.yml Makefile .gitignore Sources/App/MacVisualizerApp.swift Sources/Core/.gitkeep Tests/CoreTests/.gitkeep
git commit -m "Scaffold XcodeGen project with Core framework, app shell, and test bundle"
```

---

## Task 2: `AudioFrame` value type

**Files:**
- Create: `Sources/Core/AudioFrame.swift`
- Test: `Tests/CoreTests/AudioFrameTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/CoreTests/AudioFrameTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class AudioFrameTests: XCTestCase {
    func testSilentHasZeroEnergyAndNoBands() {
        let frame = AudioFrame.silent
        XCTAssertEqual(frame.rms, 0)
        XCTAssertEqual(frame.peak, 0)
        XCTAssertTrue(frame.bands.isEmpty)
        XCTAssertEqual(frame.timestamp, 0)
    }

    func testInitStoresValues() {
        let frame = AudioFrame(bands: [0.1, 0.2, 0.3], rms: 0.4, peak: 0.9, timestamp: 12.5)
        XCTAssertEqual(frame.bands, [0.1, 0.2, 0.3])
        XCTAssertEqual(frame.rms, 0.4)
        XCTAssertEqual(frame.peak, 0.9)
        XCTAssertEqual(frame.timestamp, 12.5)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MacVisualizer.xcodeproj -scheme MacVisualizer -destination 'platform=macOS' -derivedDataPath DerivedData`
Expected: FAIL — compile error, `cannot find 'AudioFrame' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/Core/AudioFrame.swift`:

```swift
import QuartzCore

public struct AudioFrame: Equatable {
    public var bands: [Float]
    public var rms: Float
    public var peak: Float
    public var timestamp: CFTimeInterval

    public init(bands: [Float], rms: Float, peak: Float, timestamp: CFTimeInterval) {
        self.bands = bands
        self.rms = rms
        self.peak = peak
        self.timestamp = timestamp
    }

    public static let silent = AudioFrame(bands: [], rms: 0, peak: 0, timestamp: 0)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test`
Expected: `** TEST SUCCEEDED **`, both `AudioFrameTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/AudioFrame.swift Tests/CoreTests/AudioFrameTests.swift
git commit -m "Add AudioFrame value type"
```

---

## Task 3: `VisualizerSettings` (Codable + JSON persistence)

**Files:**
- Create: `Sources/Core/VisualizerSettings.swift`
- Test: `Tests/CoreTests/VisualizerSettingsTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/CoreTests/VisualizerSettingsTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class VisualizerSettingsTests: XCTestCase {
    func testDefaultsAreSensible() {
        let s = VisualizerSettings.defaults
        XCTAssertEqual(s.barCount, 48)
        XCTAssertEqual(s.targetFPS, 60)
        XCTAssertGreaterThan(s.gain, 0)
        XCTAssertTrue((0...1).contains(s.smoothing))
        XCTAssertTrue(s.peakHoldEnabled)
        XCTAssertEqual(s.paletteName, "classic")
    }

    func testJSONRoundTrips() throws {
        var s = VisualizerSettings.defaults
        s.gain = 2.5
        s.barCount = 64
        s.paletteName = "custom"
        s.customStops = [RGBAColor(r: 1, g: 0, b: 0, a: 1),
                         RGBAColor(r: 0, g: 0, b: 1, a: 1)]
        s.overlayEnabled = false

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)

        XCTAssertEqual(decoded, s)
    }

    func testLoadReturnsDefaultsWhenFileMissing() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).json")
        let loaded = VisualizerSettings.load(from: url)
        XCTAssertEqual(loaded, VisualizerSettings.defaults)
    }

    func testSaveThenLoadRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        var s = VisualizerSettings.defaults
        s.gain = 3.0
        try s.save(to: url)

        let loaded = VisualizerSettings.load(from: url)
        XCTAssertEqual(loaded, s)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `cannot find 'VisualizerSettings' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/Core/VisualizerSettings.swift`:

```swift
import Foundation

public struct RGBAColor: Codable, Equatable {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float
    public init(r: Float, g: Float, b: Float, a: Float) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
}

public enum OverlayCorner: String, Codable, Equatable, CaseIterable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
}

public enum BackgroundStyle: String, Codable, Equatable, CaseIterable {
    case solid, gradient
}

public struct VisualizerSettings: Codable, Equatable {
    // Palette
    public var paletteName: String
    public var customStops: [RGBAColor]

    // Sensitivity / smoothing
    public var gain: Float
    public var barCount: Int
    public var smoothing: Float
    public var peakHoldEnabled: Bool

    // Overlay
    public var overlayEnabled: Bool
    public var overlayPosition: OverlayCorner
    public var overlayOpacity: Float

    // Window / display
    public var alwaysOnTop: Bool
    public var fullscreenDisplayID: UInt32?
    public var targetFPS: Int
    public var backgroundStyle: BackgroundStyle

    public static let defaults = VisualizerSettings(
        paletteName: "classic",
        customStops: [],
        gain: 1.0,
        barCount: 48,
        smoothing: 0.6,
        peakHoldEnabled: true,
        overlayEnabled: true,
        overlayPosition: .bottomLeading,
        overlayOpacity: 0.85,
        alwaysOnTop: false,
        fullscreenDisplayID: nil,
        targetFPS: 60,
        backgroundStyle: .solid
    )
}

extension VisualizerSettings {
    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("MacVisualizer", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    public static func load(from url: URL) -> VisualizerSettings {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(VisualizerSettings.self, from: data)
        else { return .defaults }
        return decoded
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test`
Expected: `** TEST SUCCEEDED **`, all four `VisualizerSettingsTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/VisualizerSettings.swift Tests/CoreTests/VisualizerSettingsTests.swift
git commit -m "Add VisualizerSettings with JSON persistence"
```

---

## Task 4: `ColorPalette` (presets + gradient sampling)

**Files:**
- Create: `Sources/Core/ColorPalette.swift`
- Test: `Tests/CoreTests/ColorPaletteTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/CoreTests/ColorPaletteTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class ColorPaletteTests: XCTestCase {
    func testClassicPresetExists() {
        let palette = ColorPalette.preset(named: "classic")
        XCTAssertNotNil(palette)
        XCTAssertGreaterThanOrEqual(palette!.stops.count, 2)
    }

    func testUnknownPresetReturnsNil() {
        XCTAssertNil(ColorPalette.preset(named: "no-such-palette"))
    }

    func testSampleAtStopsReturnsStopColors() {
        let palette = ColorPalette(stops: [
            RGBAColor(r: 0, g: 0, b: 0, a: 1),
            RGBAColor(r: 1, g: 1, b: 1, a: 1)
        ])
        let low = palette.sample(at: 0)
        let high = palette.sample(at: 1)
        XCTAssertEqual(low.r, 0, accuracy: 0.0001)
        XCTAssertEqual(high.r, 1, accuracy: 0.0001)
    }

    func testSampleInterpolatesMidpoint() {
        let palette = ColorPalette(stops: [
            RGBAColor(r: 0, g: 0, b: 0, a: 1),
            RGBAColor(r: 1, g: 1, b: 1, a: 1)
        ])
        let mid = palette.sample(at: 0.5)
        XCTAssertEqual(mid.r, 0.5, accuracy: 0.0001)
        XCTAssertEqual(mid.g, 0.5, accuracy: 0.0001)
        XCTAssertEqual(mid.b, 0.5, accuracy: 0.0001)
    }

    func testSampleClampsOutOfRange() {
        let palette = ColorPalette(stops: [
            RGBAColor(r: 0.2, g: 0, b: 0, a: 1),
            RGBAColor(r: 0.8, g: 0, b: 0, a: 1)
        ])
        XCTAssertEqual(palette.sample(at: -5).r, 0.2, accuracy: 0.0001)
        XCTAssertEqual(palette.sample(at: 5).r, 0.8, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `cannot find 'ColorPalette' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/Core/ColorPalette.swift`:

```swift
import Foundation

public struct ColorPalette: Equatable {
    public let stops: [RGBAColor]

    public init(stops: [RGBAColor]) {
        precondition(stops.count >= 2, "A palette needs at least two stops")
        self.stops = stops
    }

    /// Sample the gradient at position `t` in 0...1 (clamped). Stops are evenly spaced.
    public func sample(at t: Float) -> RGBAColor {
        let clamped = min(max(t, 0), 1)
        let segments = Float(stops.count - 1)
        let scaled = clamped * segments
        let lowerIndex = Int(scaled.rounded(.down))
        if lowerIndex >= stops.count - 1 { return stops[stops.count - 1] }
        let upperIndex = lowerIndex + 1
        let localT = scaled - Float(lowerIndex)
        return lerp(stops[lowerIndex], stops[upperIndex], localT)
    }

    private func lerp(_ a: RGBAColor, _ b: RGBAColor, _ t: Float) -> RGBAColor {
        RGBAColor(
            r: a.r + (b.r - a.r) * t,
            g: a.g + (b.g - a.g) * t,
            b: a.b + (b.b - a.b) * t,
            a: a.a + (b.a - a.a) * t
        )
    }
}

extension ColorPalette {
    public static let presets: [String: ColorPalette] = [
        "classic": ColorPalette(stops: [
            RGBAColor(r: 0.0, g: 0.8, b: 0.2, a: 1), // green
            RGBAColor(r: 0.9, g: 0.9, b: 0.0, a: 1), // yellow
            RGBAColor(r: 0.9, g: 0.1, b: 0.1, a: 1)  // red
        ]),
        "phosphor": ColorPalette(stops: [
            RGBAColor(r: 0.0, g: 0.15, b: 0.0, a: 1),
            RGBAColor(r: 0.2, g: 1.0, b: 0.3, a: 1)
        ]),
        "synthwave": ColorPalette(stops: [
            RGBAColor(r: 0.15, g: 0.0, b: 0.4, a: 1),
            RGBAColor(r: 0.9, g: 0.1, b: 0.6, a: 1),
            RGBAColor(r: 0.1, g: 0.9, b: 1.0, a: 1)
        ])
    ]

    public static func preset(named name: String) -> ColorPalette? {
        presets[name]
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test`
Expected: `** TEST SUCCEEDED **`, all `ColorPaletteTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/ColorPalette.swift Tests/CoreTests/ColorPaletteTests.swift
git commit -m "Add ColorPalette with presets and gradient sampling"
```

---

## Task 5: Shared signal generators + Hann window

**Files:**
- Create: `Tests/CoreTests/SignalGenerators.swift`
- Create: `Sources/Core/HannWindow.swift`
- Test: `Tests/CoreTests/HannWindowTests.swift`

- [ ] **Step 1: Write the shared test helper**

`Tests/CoreTests/SignalGenerators.swift`:

```swift
import Foundation

enum SignalGenerators {
    /// A pure sine wave of `frequency` Hz at `sampleRate`, `count` samples, amplitude 1.
    static func sine(frequency: Float, sampleRate: Float, count: Int) -> [Float] {
        (0..<count).map { i in
            sinf(2 * .pi * frequency * Float(i) / sampleRate)
        }
    }

    static func silence(count: Int) -> [Float] {
        [Float](repeating: 0, count: count)
    }

    /// Index of the maximum value in `values`.
    static func argmax(_ values: [Float]) -> Int {
        var best = 0
        var bestVal = -Float.greatestFiniteMagnitude
        for (i, v) in values.enumerated() where v > bestVal {
            bestVal = v; best = i
        }
        return best
    }
}
```

- [ ] **Step 2: Write the failing Hann window test**

`Tests/CoreTests/HannWindowTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class HannWindowTests: XCTestCase {
    func testLength() {
        XCTAssertEqual(makeHannWindow(2048).count, 2048)
    }

    func testEndpointsNearZeroCenterNearOne() {
        let w = makeHannWindow(1024)
        XCTAssertEqual(w.first!, 0, accuracy: 0.001)
        XCTAssertEqual(w.last!, 0, accuracy: 0.01)
        XCTAssertEqual(w[w.count / 2], 1, accuracy: 0.001)
    }

    func testApproximatelySymmetric() {
        // vDSP's window convention makes endpoints differ by up to one sample's
        // worth; a generous tolerance keeps this robust across conventions.
        let w = makeHannWindow(256)
        for i in 0..<(w.count / 2) {
            XCTAssertEqual(w[i], w[w.count - 1 - i], accuracy: 0.02)
        }
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `cannot find 'makeHannWindow' in scope`.

- [ ] **Step 4: Write minimal implementation**

`Sources/Core/HannWindow.swift`:

```swift
import Accelerate

/// Builds a denormalized Hann window (endpoints ~0, center ~1).
func makeHannWindow(_ count: Int) -> [Float] {
    var window = [Float](repeating: 0, count: count)
    vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_DENORM))
    return window
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `make test`
Expected: `** TEST SUCCEEDED **`, all `HannWindowTests` pass.

- [ ] **Step 6: Commit**

```bash
git add Tests/CoreTests/SignalGenerators.swift Sources/Core/HannWindow.swift Tests/CoreTests/HannWindowTests.swift
git commit -m "Add Hann window helper and synthetic signal generators"
```

---

## Task 6: `FFTProcessor` (vDSP real FFT → magnitude spectrum)

**Files:**
- Create: `Sources/Core/FFTProcessor.swift`
- Test: `Tests/CoreTests/FFTProcessorTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/CoreTests/FFTProcessorTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class FFTProcessorTests: XCTestCase {
    func testMagnitudeLengthIsHalfTheInput() {
        let fft = FFTProcessor(size: 2048)
        let input = SignalGenerators.silence(count: 2048)
        XCTAssertEqual(fft.magnitudes(of: input).count, 1024)
    }

    func testSineWavePeaksInExpectedBin() {
        let size = 2048
        let sampleRate: Float = 48000
        let frequency: Float = 1000
        let fft = FFTProcessor(size: size)
        let window = makeHannWindow(size)

        let raw = SignalGenerators.sine(frequency: frequency, sampleRate: sampleRate, count: size)
        let windowed = zip(raw, window).map(*)

        let mags = fft.magnitudes(of: windowed)
        let peakBin = SignalGenerators.argmax(mags)

        let expectedBin = Int((frequency * Float(size) / sampleRate).rounded())
        XCTAssertEqual(peakBin, expectedBin, accuracy: 1)
    }

    func testSilenceProducesNearZeroMagnitudes() {
        let fft = FFTProcessor(size: 1024)
        let mags = fft.magnitudes(of: SignalGenerators.silence(count: 1024))
        XCTAssertLessThan(mags.max() ?? 0, 1e-5)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `cannot find 'FFTProcessor' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/Core/FFTProcessor.swift`:

```swift
import Accelerate

/// Computes the magnitude spectrum of a real, already-windowed signal using vDSP.
/// Not thread-safe; use one instance per analysis queue.
final class FFTProcessor {
    private let n: Int
    private let halfN: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var realp: [Float]
    private var imagp: [Float]

    init(size: Int) {
        precondition(size > 0 && (size & (size - 1)) == 0, "FFT size must be a power of two")
        self.n = size
        self.halfN = size / 2
        self.log2n = vDSP_Length(log2(Float(size)))
        self.setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        self.realp = [Float](repeating: 0, count: halfN)
        self.imagp = [Float](repeating: 0, count: halfN)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// Returns `size/2` magnitudes for a real input of length `size`.
    func magnitudes(of input: [Float]) -> [Float] {
        precondition(input.count == n, "Input length must equal FFT size")
        var output = [Float](repeating: 0, count: halfN)

        realp.withUnsafeMutableBufferPointer { rp in
            imagp.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)

                input.withUnsafeBufferPointer { inPtr in
                    inPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { typed in
                        vDSP_ctoz(typed, 2, &split, 1, vDSP_Length(halfN))
                    }
                }

                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &output, 1, vDSP_Length(halfN))
            }
        }

        // Normalize by FFT size so magnitudes are independent of `size`.
        // Write to a separate buffer to avoid overlapping access on `output`.
        var scaled = [Float](repeating: 0, count: halfN)
        var scale: Float = 1.0 / Float(n)
        vDSP_vsmul(output, 1, &scale, &scaled, 1, vDSP_Length(halfN))
        return scaled
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test`
Expected: `** TEST SUCCEEDED **`. In particular `testSineWavePeaksInExpectedBin` confirms a 1 kHz tone peaks at bin ~43.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/FFTProcessor.swift Tests/CoreTests/FFTProcessorTests.swift
git commit -m "Add vDSP FFT magnitude processor"
```

---

## Task 7: `BandMapper` (log-spaced bin → band reduction)

**Files:**
- Create: `Sources/Core/BandMapper.swift`
- Test: `Tests/CoreTests/BandMapperTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/CoreTests/BandMapperTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class BandMapperTests: XCTestCase {
    func testProducesRequestedBandCount() {
        let mapper = BandMapper(bandCount: 24, fftSize: 2048, sampleRate: 48000)
        let mags = [Float](repeating: 0, count: 1024)
        XCTAssertEqual(mapper.bands(from: mags).count, 24)
    }

    func testEdgesAreMonotonicallyIncreasing() {
        let mapper = BandMapper(bandCount: 32, fftSize: 2048, sampleRate: 48000)
        for i in 1..<mapper.edges.count {
            XCTAssertGreaterThanOrEqual(mapper.edges[i], mapper.edges[i - 1])
        }
    }

    func testSpikeLightsUpExactlyOneBand() {
        let bandCount = 24
        let mapper = BandMapper(bandCount: bandCount, fftSize: 2048, sampleRate: 48000)

        var mags = [Float](repeating: 0, count: 1024)
        let spikeBin = 100
        mags[spikeBin] = 1.0

        let bands = mapper.bands(from: mags)

        // Find which band's [lo, hi) range contains the spike bin.
        var expectedBand = -1
        for i in 0..<(mapper.edges.count - 1) where spikeBin >= mapper.edges[i] && spikeBin < mapper.edges[i + 1] {
            expectedBand = i
        }
        XCTAssertGreaterThanOrEqual(expectedBand, 0, "spike bin should fall within mapped range")

        XCTAssertEqual(bands[expectedBand], 1.0, accuracy: 0.0001)
        for (i, v) in bands.enumerated() where i != expectedBand {
            XCTAssertEqual(v, 0, accuracy: 0.0001)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `cannot find 'BandMapper' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/Core/BandMapper.swift`:

```swift
import Foundation

/// Reduces a linear magnitude spectrum into log-frequency-spaced bands.
/// Each band's value is the max magnitude across its bin range.
struct BandMapper {
    /// `bandCount + 1` bin indices delimiting each band's [lo, hi) range.
    let edges: [Int]

    init(bandCount: Int, fftSize: Int, sampleRate: Float, minHz: Float = 30, maxHz: Float = 16000) {
        precondition(bandCount > 0)
        let nyquistBins = fftSize / 2
        let minBin = max(1, Int(minHz * Float(fftSize) / sampleRate))
        let maxBin = min(nyquistBins, Int(maxHz * Float(fftSize) / sampleRate))
        let safeMaxBin = max(maxBin, minBin + bandCount)

        let logMin = log(Float(minBin))
        let logMax = log(Float(safeMaxBin))

        var computed = [Int]()
        computed.reserveCapacity(bandCount + 1)
        for i in 0...bandCount {
            let t = Float(i) / Float(bandCount)
            let bin = Int(exp(logMin + (logMax - logMin) * t).rounded())
            computed.append(min(max(bin, minBin), safeMaxBin))
        }
        // Guarantee strictly non-decreasing, with each band at least one bin wide.
        for i in 1..<computed.count where computed[i] <= computed[i - 1] {
            computed[i] = computed[i - 1] + 1
        }
        self.edges = computed
    }

    func bands(from magnitudes: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: edges.count - 1)
        for i in 0..<out.count {
            let lo = edges[i]
            let hi = max(edges[i + 1], lo + 1)
            var peak: Float = 0
            var b = lo
            while b < hi && b < magnitudes.count {
                peak = max(peak, magnitudes[b])
                b += 1
            }
            out[i] = peak
        }
        return out
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test`
Expected: `** TEST SUCCEEDED **`, all `BandMapperTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/BandMapper.swift Tests/CoreTests/BandMapperTests.swift
git commit -m "Add log-spaced band mapper"
```

---

## Task 8: `BandPostProcessor` (dB normalize, gain, smoothing, peak-hold)

**Files:**
- Create: `Sources/Core/BandPostProcessor.swift`
- Test: `Tests/CoreTests/BandPostProcessorTests.swift`

Design note: `process` runs, in order, per band: magnitude → dB → normalize to 0…1 against a noise floor → multiply by `gain` (clamped to 0…1) → exponential smoothing → peak-hold. `gain` acts linearly on the normalized value below saturation, satisfying the "gain scales output" requirement.

- [ ] **Step 1: Write the failing test**

`Tests/CoreTests/BandPostProcessorTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class BandPostProcessorTests: XCTestCase {
    func testSilenceProducesZeroBands() {
        let p = BandPostProcessor(bandCount: 4, gain: 1, smoothing: 0, peakDecay: 0.9)
        let result = p.process([0, 0, 0, 0])
        for v in result.bands { XCTAssertEqual(v, 0, accuracy: 1e-4) }
    }

    func testOutputIsClampedToUnitRange() {
        let p = BandPostProcessor(bandCount: 2, gain: 100, smoothing: 0, peakDecay: 0.9)
        let result = p.process([10, 10])
        for v in result.bands {
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThanOrEqual(v, 1)
        }
    }

    func testHigherGainGivesHigherOrEqualOutput() {
        let low = BandPostProcessor(bandCount: 1, gain: 1, smoothing: 0, peakDecay: 0.9)
        let high = BandPostProcessor(bandCount: 1, gain: 2, smoothing: 0, peakDecay: 0.9)
        let input: [Float] = [0.01]
        let lowOut = low.process(input).bands[0]
        let highOut = high.process(input).bands[0]
        XCTAssertGreaterThan(highOut, lowOut)
    }

    func testSmoothingConvergesTowardSteadyInput() {
        let p = BandPostProcessor(bandCount: 1, gain: 1, smoothing: 0.5, peakDecay: 0.9)
        let input: [Float] = [1.0]
        var last: Float = 0
        for _ in 0..<50 { last = p.process(input).bands[0] }
        let target = p.process(input).bands[0] // already converged
        XCTAssertEqual(last, target, accuracy: 0.01)
        XCTAssertGreaterThan(last, 0.5) // moved well off zero toward steady value
    }

    func testPeakIsAtLeastCurrentBand() {
        let p = BandPostProcessor(bandCount: 1, gain: 1, smoothing: 0, peakDecay: 0.5)
        let result = p.process([1.0])
        XCTAssertGreaterThanOrEqual(result.peaks[0], result.bands[0] - 1e-4)
    }

    func testPeakDecaysWhenInputDrops() {
        let p = BandPostProcessor(bandCount: 1, gain: 1, smoothing: 0, peakDecay: 0.5)
        _ = p.process([1.0])               // establish a high peak
        let afterDrop = p.process([0.0])   // input gone
        let afterMore = p.process([0.0])
        XCTAssertLessThan(afterMore.peaks[0], afterDrop.peaks[0])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `cannot find 'BandPostProcessor' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/Core/BandPostProcessor.swift`:

```swift
import Foundation

/// Stateful per-band post-processing: dB-normalize, gain, exponential smoothing, peak-hold.
/// One instance per analyzer; call `process` once per audio frame.
final class BandPostProcessor {
    var gain: Float
    /// 0 = no smoothing (use current), →1 = very smooth (mostly previous).
    var smoothing: Float
    /// Per-frame multiplicative decay applied to held peaks.
    var peakDecay: Float

    private let floorDb: Float = -80
    private let refDb: Float = 0
    private var smoothed: [Float]
    private var peaks: [Float]

    init(bandCount: Int, gain: Float, smoothing: Float, peakDecay: Float = 0.95) {
        self.gain = gain
        self.smoothing = smoothing
        self.peakDecay = peakDecay
        self.smoothed = [Float](repeating: 0, count: bandCount)
        self.peaks = [Float](repeating: 0, count: bandCount)
    }

    func process(_ rawMagnitudes: [Float]) -> (bands: [Float], peaks: [Float]) {
        let count = min(rawMagnitudes.count, smoothed.count)
        var bands = [Float](repeating: 0, count: count)

        for i in 0..<count {
            // magnitude -> dB
            let db = 20 * log10(max(rawMagnitudes[i], 1e-9))
            // normalize to 0...1 against the noise floor
            let normalized = min(max((db - floorDb) / (refDb - floorDb), 0), 1)
            // gain (linear below saturation), clamped
            let gained = min(max(normalized * gain, 0), 1)
            // exponential smoothing
            smoothed[i] = smoothing * smoothed[i] + (1 - smoothing) * gained
            // peak-hold
            peaks[i] = max(peaks[i] * peakDecay, smoothed[i])
            bands[i] = smoothed[i]
        }

        return (bands, Array(peaks[0..<count]))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test`
Expected: `** TEST SUCCEEDED **`, all `BandPostProcessorTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/BandPostProcessor.swift Tests/CoreTests/BandPostProcessorTests.swift
git commit -m "Add band post-processor (dB normalize, gain, smoothing, peak-hold)"
```

---

## Task 9: `SpectrumAnalyzer` (orchestrate the full pipeline)

**Files:**
- Create: `Sources/Core/SpectrumAnalyzer.swift`
- Test: `Tests/CoreTests/SpectrumAnalyzerTests.swift`

Design note: `SpectrumAnalyzer` owns an FFT size and a sample-accumulation ring. Callers push arbitrary-length PCM via `append(_:)`; whenever a full window is available it computes one `AudioFrame` and returns the most recent one (or `nil` if not enough samples yet). `rms`/`peak` are computed from the raw window. It is the single public entry point the app and services will use in later plans.

- [ ] **Step 1: Write the failing test**

`Tests/CoreTests/SpectrumAnalyzerTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class SpectrumAnalyzerTests: XCTestCase {
    private func makeAnalyzer(bands: Int = 24) -> SpectrumAnalyzer {
        var settings = VisualizerSettings.defaults
        settings.barCount = bands
        settings.gain = 1
        settings.smoothing = 0   // deterministic: output = current frame
        return SpectrumAnalyzer(fftSize: 2048, sampleRate: 48000, settings: settings)
    }

    func testReturnsNilUntilEnoughSamples() {
        let analyzer = makeAnalyzer()
        let half = SignalGenerators.silence(count: 1024)
        XCTAssertNil(analyzer.append(half))
    }

    func testEmitsFrameWithRequestedBandCount() {
        let analyzer = makeAnalyzer(bands: 24)
        let frame = analyzer.append(SignalGenerators.silence(count: 2048))
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame!.bands.count, 24)
    }

    func testSilenceYieldsZeroEnergy() {
        let analyzer = makeAnalyzer()
        let frame = analyzer.append(SignalGenerators.silence(count: 2048))!
        XCTAssertEqual(frame.rms, 0, accuracy: 1e-4)
        XCTAssertEqual(frame.peak, 0, accuracy: 1e-4)
        XCTAssertEqual(frame.bands.max() ?? 0, 0, accuracy: 1e-3)
    }

    func testToneEnergyConcentratesInExpectedBand() {
        let analyzer = makeAnalyzer(bands: 24)
        let tone = SignalGenerators.sine(frequency: 1000, sampleRate: 48000, count: 2048)
        let frame = analyzer.append(tone)!

        let loudest = SignalGenerators.argmax(frame.bands)
        // 1 kHz must not land in the lowest band (sub-bass) nor the very top band.
        XCTAssertGreaterThan(loudest, 0)
        XCTAssertLessThan(loudest, frame.bands.count - 1)
        XCTAssertGreaterThan(frame.bands[loudest], 0.1)
        XCTAssertGreaterThan(frame.rms, 0)
    }

    func testAccumulatesAcrossMultipleAppends() {
        let analyzer = makeAnalyzer()
        XCTAssertNil(analyzer.append(SignalGenerators.silence(count: 1024)))
        let frame = analyzer.append(SignalGenerators.silence(count: 1024))
        XCTAssertNotNil(frame)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `cannot find 'SpectrumAnalyzer' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/Core/SpectrumAnalyzer.swift`:

```swift
import Accelerate
import QuartzCore

/// Turns streamed mono PCM into `AudioFrame`s via the full DSP pipeline.
/// Not thread-safe; confine to a single analysis queue.
public final class SpectrumAnalyzer {
    private let fftSize: Int
    private let sampleRate: Float
    private let window: [Float]
    private let fft: FFTProcessor
    private let mapper: BandMapper
    private let post: BandPostProcessor

    private var ring: [Float] = []

    public init(fftSize: Int = 2048, sampleRate: Float = 48000, settings: VisualizerSettings) {
        self.fftSize = fftSize
        self.sampleRate = sampleRate
        self.window = makeHannWindow(fftSize)
        self.fft = FFTProcessor(size: fftSize)
        self.mapper = BandMapper(bandCount: settings.barCount, fftSize: fftSize, sampleRate: sampleRate)
        self.post = BandPostProcessor(
            bandCount: settings.barCount,
            gain: settings.gain,
            smoothing: settings.smoothing,
            peakDecay: settings.peakHoldEnabled ? 0.95 : 0.0
        )
        self.ring.reserveCapacity(fftSize * 2)
    }

    /// Live-tune the parameters that can change without reallocating buffers.
    public func update(gain: Float, smoothing: Float, peakHoldEnabled: Bool) {
        post.gain = gain
        post.smoothing = smoothing
        post.peakDecay = peakHoldEnabled ? 0.95 : 0.0
    }

    /// Append PCM samples. Returns a new `AudioFrame` once a full window is available, else nil.
    @discardableResult
    public func append(_ samples: [Float]) -> AudioFrame? {
        ring.append(contentsOf: samples)
        guard ring.count >= fftSize else { return nil }

        // Take the most recent full window; drop everything older.
        let frameSamples = Array(ring.suffix(fftSize))
        ring.removeAll(keepingCapacity: true)

        var rms: Float = 0
        vDSP_rmsqv(frameSamples, 1, &rms, vDSP_Length(fftSize))

        var peak: Float = 0
        var minV: Float = 0
        var maxV: Float = 0
        vDSP_minv(frameSamples, 1, &minV, vDSP_Length(fftSize))
        vDSP_maxv(frameSamples, 1, &maxV, vDSP_Length(fftSize))
        peak = max(abs(minV), abs(maxV))

        let windowed = zip(frameSamples, window).map(*)
        let mags = fft.magnitudes(of: windowed)
        let rawBands = mapper.bands(from: mags)
        let processed = post.process(rawBands)

        return AudioFrame(
            bands: processed.bands,
            rms: rms,
            peak: peak,
            timestamp: CACurrentMediaTime()
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test`
Expected: `** TEST SUCCEEDED **`, all `SpectrumAnalyzerTests` pass. This is the milestone: the full DSP pipeline turns a synthetic tone into correctly-placed band energy.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/SpectrumAnalyzer.swift Tests/CoreTests/SpectrumAnalyzerTests.swift
git commit -m "Add SpectrumAnalyzer orchestrating the full DSP pipeline"
```

---

## Definition of Done (Plan 1)

- `make build` → `** BUILD SUCCEEDED **` (empty app window target builds).
- `make test` → `** TEST SUCCEEDED **` with all Core tests green.
- Core contains the complete, deterministic analysis pipeline (`AudioFrame`, `VisualizerSettings`, `ColorPalette`, `SpectrumAnalyzer` + helpers), independent of any audio capture, rendering, or metadata code.
- `VisualizerSettings` round-trips to JSON on disk.

## Handoff to Plan 2 (Rendering)

Plan 2 will add `Sources/Rendering` (MetalRenderer, `Visualizer` protocol, `SpectrumBarsVisualizer`, shaders) and a `MetalView` wrapper, update `project.yml` to include the Rendering source dir, and drive the view from synthetic `AudioFrame`s (a sine sweep) so rendering is verified before real audio capture exists in Plan 3.

### Carry-forward findings from the Plan 1 final code review (APPROVED)

These were intentionally deferred from Plan 1 and should be addressed in the noted plan:

- **Per-band peak-hold is computed but dropped (Plan 2).** `BandPostProcessor.process` returns `(bands, peaks)` but `SpectrumAnalyzer.append` discards `processed.peaks`. `AudioFrame` only carries scalar `rms`/`peak` (full-window amplitude), not the per-band held caps the renderer needs for "peak-hold cap quad per band." Before building the renderer, revisit the data contract: add `bandPeaks: [Float]` to `AudioFrame` (and populate it in `SpectrumAnalyzer.append`), or hold peaks renderer-side. Until then, computing peaks each frame is mild dead work.
- **`peakHoldEnabled == false` collapses peaks onto the bars rather than suppressing them (Plan 2).** `SpectrumAnalyzer` maps disabled → `peakDecay = 0`, so `peaks == bands`. Confirm this is the desired "off" behavior when the renderer consumes peaks (likely: draw no cap quad at all when disabled).
- **Ring buffer drains all samples with no overlap/hop (Plan 3).** `SpectrumAnalyzer.append` takes the most-recent `fftSize` samples then clears the ring, so (a) surplus older samples in a large buffer are dropped and (b) at most one frame is produced per `append`. The design spec (4.2, "hop as buffers arrive") implies a hopped/overlapping ring. Replace with a proper hop-based ring (e.g. 50% overlap) when wiring real capture, to avoid sample loss and visual flicker.
- **FFT magnitude omits the conventional `vDSP_fft_zrip` 0.5 scale and bin 0 holds packed DC/Nyquist (informational).** Harmless here: the spectrum is relative and dB-normalized, and `BandMapper` uses `minBin = max(1, …)` so bin 0 is never read. Note it only if absolute amplitude calibration is ever needed.
- **`SpectrumAnalyzer.update(gain:smoothing:peakHoldEnabled:)` is untested.** Add a small test (raising gain changes a subsequent frame's band levels) when live-tuning is wired to the settings UI.
