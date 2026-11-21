# Per-Style Profiles + Settings Refresh — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Each `VisualizerStyle` keeps its own complete profile of settings; the Settings window becomes a resizable `TabView` with per-style + global Reset; the four Fireworks beat-detector knobs become live sliders (no rebuild).

**Architecture:** Add a `StyleProfile` value type and a `profiles: [VisualizerStyle: StyleProfile]` field on `VisualizerSettings`. Keep the old flat field names as **computed forwarder properties** that read/write the current style's profile — so every existing visualizer, `MetalView`, and `RenderModel` keep compiling unchanged. The tolerant `Codable` decoder migrates old flat-field `settings.json` into the new profiles dict on first launch. The four fireworks tunables move to top-level `Float` fields on `VisualizerSettings` (single shared block, not per-profile). `SettingsView` is rewritten as a `TabView` (resizable) with two Reset buttons + alerts. The `/tune-fireworks` skill and the `/tmp/fireworks.log` diagnostic are deleted.

**Tech Stack:** Swift 5.10, SwiftUI (`TabView`, `Alert`, custom `Binding`s), XCTest.

**Builds on:** the merged app + everything on `plan-09-fountain-fireworks`. Spec: `docs/superpowers/specs/2026-05-28-per-style-profiles-and-settings-refresh-design.md`.

**Scope boundary:** No rendering changes, no new visualizer styles, no shader work, no file-watching `settings.json`.

---

## File Structure

```
mac-visualizer/
  Sources/
    Core/
      StyleProfile.swift            # CREATE: per-style profile value type
      VisualizerSettings.swift      # REFACTOR: stored profiles dict + 4 fireworks fields; old flat fields become computed forwarders; tolerant decoder migrates old JSON
      FireworksVisualizer.swift     # MODIFY: read fireworks tunables from settings; remove the 4 private let constants; remove the /tmp/fireworks.log diagnostic
    App/
      SettingsView.swift            # REFACTOR: TabView (5 tabs), per-style label, two Reset buttons, resizable
  Tests/
    CoreTests/
      VisualizerSettingsTests.swift # MODIFY: tests for the new profile model + migration; existing forwarder-backed tests stay green
      StyleProfileTests.swift       # CREATE
  .claude/
    skills/
      tune-fireworks/               # DELETE: superseded by the new live sliders
```

No changes to any other visualizer file (they keep reading `settings.gain` / `settings.smoothing` / etc. — those continue to work via forwarders to the current profile). No changes to `MetalView`, `RenderModel`, or `RenderProbe`. No new tests are needed for visualizer code.

---

## Task 1: Move fireworks tunables into Settings + remove the diagnostic log

This task is self-contained and unblocks the live-slider experience for fireworks even before the per-style refactor lands.

**Files:**
- Modify: `Sources/Core/VisualizerSettings.swift`
- Modify: `Sources/Core/FireworksVisualizer.swift`
- Modify: `Tests/CoreTests/VisualizerSettingsTests.swift`

- [ ] **Step 1: Write the failing tests** — append these methods to `VisualizerSettingsTests`:

```swift
    func testFireworksTunablesDefaults() {
        let d = VisualizerSettings.defaults
        XCTAssertEqual(d.fireworksMinBass, 0.05, accuracy: 1e-6)
        XCTAssertEqual(d.fireworksMarginFloor, 0.015, accuracy: 1e-6)
        XCTAssertEqual(d.fireworksMarginScale, 0.5, accuracy: 1e-6)
        XCTAssertEqual(d.fireworksBaselineAlpha, 0.05, accuracy: 1e-6)
    }

    func testFireworksTunablesRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.fireworksMinBass = 0.07
        s.fireworksMarginFloor = 0.02
        s.fireworksMarginScale = 0.8
        s.fireworksBaselineAlpha = 0.03
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.fireworksMinBass, 0.07, accuracy: 1e-6)
        XCTAssertEqual(decoded.fireworksMarginFloor, 0.02, accuracy: 1e-6)
        XCTAssertEqual(decoded.fireworksMarginScale, 0.8, accuracy: 1e-6)
        XCTAssertEqual(decoded.fireworksBaselineAlpha, 0.03, accuracy: 1e-6)
        XCTAssertEqual(decoded, s)
    }

    func testFireworksTunablesPartialJSONDefaults() throws {
        let json = #"{ "gain": 2.5 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.gain, 2.5)
        XCTAssertEqual(decoded.fireworksMinBass, 0.05, accuracy: 1e-6)
        XCTAssertEqual(decoded.fireworksMarginFloor, 0.015, accuracy: 1e-6)
        XCTAssertEqual(decoded.fireworksMarginScale, 0.5, accuracy: 1e-6)
        XCTAssertEqual(decoded.fireworksBaselineAlpha, 0.05, accuracy: 1e-6)
    }
```

- [ ] **Step 2: Run `make test`** — expect FAIL (`VisualizerSettings has no member 'fireworksMinBass'` etc.).

- [ ] **Step 3: Add the four fields to `VisualizerSettings`** — in five places (matching the existing tolerant-codec pattern):
  1. As stored properties (after `visualizerStyle`):
     ```swift
         // Fireworks beat-detector tunables (apply only when the active style is .fireworks)
         public var fireworksMinBass: Float
         public var fireworksMarginFloor: Float
         public var fireworksMarginScale: Float
         public var fireworksBaselineAlpha: Float
     ```
  2. In `defaults`, append (as the last four args):
     ```swift
         fireworksMinBass: 0.05,
         fireworksMarginFloor: 0.015,
         fireworksMarginScale: 0.5,
         fireworksBaselineAlpha: 0.05
     ```
  3. In `CodingKeys`, add the four cases.
  4. In `init(from:)`, append four `decodeIfPresent ?? d.X` lines in the `self.init(...)` call.
  5. In `encode(to:)`, append four `try c.encode(...)` lines.

- [ ] **Step 4: Run `make test`** — expect `** TEST SUCCEEDED **`. The 3 new tests pass; existing settings tests still pass.

- [ ] **Step 5: Read `FireworksVisualizer.swift` to see the current state** — confirm it has these `private let` constants:
  - `beatMinBass: Float = 0.05`
  - `beatMarginFloor: Float = 0.015`
  - `beatMarginScale: Float = 0.5`
  - `baselineAlpha: Float = 0.05`
  - And the diagnostic-log stored properties + init code + per-frame write block.

- [ ] **Step 6: Replace the constants with settings-driven reads.** In `FireworksVisualizer.swift`:
  - **Delete** the 4 `private let` constants listed above.
  - **Delete** `private var diagLog: FileHandle?` and `private var diagFrame = 0`.
  - **Delete** the block in `init` that opens `/tmp/fireworks.log` (the `FileManager.default.createFile(...)` + `FileHandle(forWritingAtPath:...)` + header-write).
  - **Delete** the diagnostic-write block in `makeVertices` (the `if diagFrame % 10 == 0 { ... }` block AND the `diagFrame += 1` line).
  - In `makeVertices`, replace this three-line block (which references the deleted `private let` constants):
    ```swift
            let effectiveMargin = max(beatMarginFloor, baseline * beatMarginScale)
            let aboveBaseline = bass > baseline + effectiveMargin
            let rising = aboveBaseline && bass > beatMinBass
    ```
    with this block (settings-sourced locals shadow the deleted constants):
    ```swift
            let beatMinBass = settings.fireworksMinBass
            let beatMarginFloor = settings.fireworksMarginFloor
            let beatMarginScale = settings.fireworksMarginScale
            let baselineAlpha = settings.fireworksBaselineAlpha
            let effectiveMargin = max(beatMarginFloor, baseline * beatMarginScale)
            let aboveBaseline = bass > baseline + effectiveMargin
            let rising = aboveBaseline && bass > beatMinBass
    ```
  - Remove the now-unused `fired` variable. The existing block:
    ```swift
            var fired = false
            if rising && refractoryPassed {
                spawnBurst()
                lastBeatTime = now
                fired = true
            }
    ```
    becomes:
    ```swift
            if rising && refractoryPassed {
                spawnBurst()
                lastBeatTime = now
            }
    ```
    (Only the deleted diagnostic-log block read `fired`.)
  - The existing baseline-update line `baseline += baselineAlpha * (bass - baseline)` now resolves to the local `baselineAlpha` (sourced from settings). No change to that line.
  - If `import Foundation` was added ONLY for the log, remove it. (`QuartzCore` already provides `CFTimeInterval`.)

- [ ] **Step 7: Run `make test`** — expect `** TEST SUCCEEDED **`, 108 (105 prior + 3 new).
  The existing `FireworksVisualizerTests` still pass because they construct frames with `settings: .defaults`, and the defaults match the old constant values exactly.

- [ ] **Step 8: Run `make build`** — `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
git add Sources/Core/VisualizerSettings.swift Sources/Core/FireworksVisualizer.swift Tests/CoreTests/VisualizerSettingsTests.swift
git commit -m "Move fireworks tunables into settings; remove /tmp/fireworks.log diagnostic"
```

---

## Task 2: `StyleProfile` + per-style profiles (with forwarders + migration)

This is the main refactor of the data model. **Strategy:** keep the old flat field NAMES on `VisualizerSettings` as computed forwarder properties that delegate to the current profile. That way every visualizer, `MetalView`, `RenderModel`, and existing test keeps compiling and behaving identically — only the storage shape changes.

**Files:**
- Create: `Sources/Core/StyleProfile.swift`
- Modify: `Sources/Core/VisualizerSettings.swift` (significant refactor)
- Create: `Tests/CoreTests/StyleProfileTests.swift`
- Modify: `Tests/CoreTests/VisualizerSettingsTests.swift`

- [ ] **Step 1: Write the StyleProfile tests** — `Tests/CoreTests/StyleProfileTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class StyleProfileTests: XCTestCase {
    func testDefaultsAreSensible() {
        let d = StyleProfile.defaults
        XCTAssertEqual(d.paletteName, "classic")
        XCTAssertEqual(d.barCount, 48)
        XCTAssertEqual(d.targetFPS, 60)
        XCTAssertTrue(d.glowEnabled)
        XCTAssertTrue(d.peakHoldEnabled)
        XCTAssertTrue(d.overlayEnabled)
        XCTAssertFalse(d.alwaysOnTop)
    }

    func testJSONRoundTrips() throws {
        var p = StyleProfile.defaults
        p.gain = 2.5
        p.paletteName = "phosphor"
        p.overlayEnabled = false
        p.alwaysOnTop = true
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(StyleProfile.self, from: data)
        XCTAssertEqual(decoded, p)
    }
}
```

- [ ] **Step 2: Write the additional VisualizerSettings tests** — append these methods to `VisualizerSettingsTests`:

```swift
    func testProfilesPopulatedForEveryStyle() {
        let d = VisualizerSettings.defaults
        XCTAssertEqual(d.profiles.count, VisualizerStyle.allCases.count)
        for s in VisualizerStyle.allCases {
            XCTAssertEqual(d.profiles[s], StyleProfile.defaults)
        }
    }

    func testCurrentReturnsActiveProfile() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .radial
        var radial = StyleProfile.defaults
        radial.gain = 3.0
        s.profiles[.radial] = radial
        XCTAssertEqual(s.current.gain, 3.0)
    }

    func testMutateCurrentTouchesOnlyOneProfile() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .bars
        s.mutateCurrent { $0.gain = 4.0 }
        XCTAssertEqual(s.profiles[.bars]?.gain, 4.0)
        XCTAssertEqual(s.profiles[.radial]?.gain, StyleProfile.defaults.gain)
    }

    func testForwardersWriteToCurrentProfile() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .oscilloscope
        s.gain = 2.0
        s.paletteName = "synthwave"
        XCTAssertEqual(s.profiles[.oscilloscope]?.gain, 2.0)
        XCTAssertEqual(s.profiles[.oscilloscope]?.paletteName, "synthwave")
        XCTAssertEqual(s.profiles[.bars]?.gain, StyleProfile.defaults.gain)
    }

    func testSwitchingStyleSwitchesWhatCurrentReturns() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .bars
        s.gain = 2.5
        s.visualizerStyle = .particles
        s.gain = 3.5
        s.visualizerStyle = .bars
        XCTAssertEqual(s.current.gain, 2.5)
        s.visualizerStyle = .particles
        XCTAssertEqual(s.current.gain, 3.5)
    }

    func testMigrationFromOldFlatFieldJSON() throws {
        // Old-format JSON: top-level flat fields, no `profiles` key.
        let json = #"""
        { "gain": 2.5, "barCount": 64, "paletteName": "phosphor", "smoothing": 0.4 }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        // Every style's profile should be initialized from the old flat values.
        for s in VisualizerStyle.allCases {
            XCTAssertEqual(decoded.profiles[s]?.gain, 2.5, "gain for \(s)")
            XCTAssertEqual(decoded.profiles[s]?.barCount, 64, "barCount for \(s)")
            XCTAssertEqual(decoded.profiles[s]?.paletteName, "phosphor", "paletteName for \(s)")
            XCTAssertEqual(decoded.profiles[s]?.smoothing, 0.4, accuracy: 1e-6, "smoothing for \(s)")
        }
    }

    func testNewFormatRoundTripWithDistinctProfiles() throws {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .bars
        var bars = StyleProfile.defaults; bars.gain = 1.5; bars.paletteName = "classic"
        var fireworks = StyleProfile.defaults; fireworks.gain = 3.0; fireworks.paletteName = "synthwave"
        s.profiles[.bars] = bars
        s.profiles[.fireworks] = fireworks
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.profiles[.bars]?.gain, 1.5)
        XCTAssertEqual(decoded.profiles[.bars]?.paletteName, "classic")
        XCTAssertEqual(decoded.profiles[.fireworks]?.gain, 3.0)
        XCTAssertEqual(decoded.profiles[.fireworks]?.paletteName, "synthwave")
        XCTAssertEqual(decoded, s)
    }
```

- [ ] **Step 3: Run `make test`** — expect FAIL (`StyleProfile` doesn't exist, `VisualizerSettings has no member 'profiles' / 'current' / 'mutateCurrent'`).

- [ ] **Step 4: Create `Sources/Core/StyleProfile.swift`:**

```swift
import Foundation

/// Per-visualizer-style settings. One `StyleProfile` per `VisualizerStyle` lives in
/// `VisualizerSettings.profiles`. Holds every "what does this look/feel like" knob;
/// fireworks-specific tunables live separately on `VisualizerSettings` since they
/// only apply when fireworks is the active style.
public struct StyleProfile: Codable, Equatable {
    // Palette
    public var paletteName: String
    public var customStops: [RGBAColor]

    // Sensitivity / audio
    public var gain: Float
    public var barCount: Int
    public var smoothing: Float
    public var peakHoldEnabled: Bool

    // Glow
    public var glowEnabled: Bool
    public var glowIntensity: Float

    // Overlay
    public var overlayEnabled: Bool
    public var overlayPosition: OverlayCorner
    public var overlayOpacity: Float

    // Window / display
    public var alwaysOnTop: Bool
    public var fullscreenDisplayID: UInt32?
    public var targetFPS: Int
    public var backgroundStyle: BackgroundStyle

    public init(paletteName: String, customStops: [RGBAColor],
                gain: Float, barCount: Int, smoothing: Float, peakHoldEnabled: Bool,
                glowEnabled: Bool, glowIntensity: Float,
                overlayEnabled: Bool, overlayPosition: OverlayCorner, overlayOpacity: Float,
                alwaysOnTop: Bool, fullscreenDisplayID: UInt32?, targetFPS: Int,
                backgroundStyle: BackgroundStyle) {
        self.paletteName = paletteName
        self.customStops = customStops
        self.gain = gain
        self.barCount = barCount
        self.smoothing = smoothing
        self.peakHoldEnabled = peakHoldEnabled
        self.glowEnabled = glowEnabled
        self.glowIntensity = glowIntensity
        self.overlayEnabled = overlayEnabled
        self.overlayPosition = overlayPosition
        self.overlayOpacity = overlayOpacity
        self.alwaysOnTop = alwaysOnTop
        self.fullscreenDisplayID = fullscreenDisplayID
        self.targetFPS = targetFPS
        self.backgroundStyle = backgroundStyle
    }

    public static let defaults = StyleProfile(
        paletteName: "classic",
        customStops: [],
        gain: 1.0,
        barCount: 48,
        smoothing: 0.6,
        peakHoldEnabled: true,
        glowEnabled: true,
        glowIntensity: 0.6,
        overlayEnabled: true,
        overlayPosition: .bottomLeading,
        overlayOpacity: 0.85,
        alwaysOnTop: false,
        fullscreenDisplayID: nil,
        targetFPS: 60,
        backgroundStyle: .solid
    )
}

extension StyleProfile {
    private enum CodingKeys: String, CodingKey {
        case paletteName, customStops, gain, barCount, smoothing, peakHoldEnabled
        case glowEnabled, glowIntensity
        case overlayEnabled, overlayPosition, overlayOpacity
        case alwaysOnTop, fullscreenDisplayID, targetFPS, backgroundStyle
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StyleProfile.defaults
        self.init(
            paletteName: try c.decodeIfPresent(String.self, forKey: .paletteName) ?? d.paletteName,
            customStops: try c.decodeIfPresent([RGBAColor].self, forKey: .customStops) ?? d.customStops,
            gain: try c.decodeIfPresent(Float.self, forKey: .gain) ?? d.gain,
            barCount: try c.decodeIfPresent(Int.self, forKey: .barCount) ?? d.barCount,
            smoothing: try c.decodeIfPresent(Float.self, forKey: .smoothing) ?? d.smoothing,
            peakHoldEnabled: try c.decodeIfPresent(Bool.self, forKey: .peakHoldEnabled) ?? d.peakHoldEnabled,
            glowEnabled: try c.decodeIfPresent(Bool.self, forKey: .glowEnabled) ?? d.glowEnabled,
            glowIntensity: try c.decodeIfPresent(Float.self, forKey: .glowIntensity) ?? d.glowIntensity,
            overlayEnabled: try c.decodeIfPresent(Bool.self, forKey: .overlayEnabled) ?? d.overlayEnabled,
            overlayPosition: try c.decodeIfPresent(OverlayCorner.self, forKey: .overlayPosition) ?? d.overlayPosition,
            overlayOpacity: try c.decodeIfPresent(Float.self, forKey: .overlayOpacity) ?? d.overlayOpacity,
            alwaysOnTop: try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? d.alwaysOnTop,
            fullscreenDisplayID: try c.decodeIfPresent(UInt32.self, forKey: .fullscreenDisplayID) ?? d.fullscreenDisplayID,
            targetFPS: try c.decodeIfPresent(Int.self, forKey: .targetFPS) ?? d.targetFPS,
            backgroundStyle: try c.decodeIfPresent(BackgroundStyle.self, forKey: .backgroundStyle) ?? d.backgroundStyle
        )
    }
}
```

- [ ] **Step 5: Refactor `Sources/Core/VisualizerSettings.swift` to the profile-backed model.**

Replace the ENTIRE contents of `Sources/Core/VisualizerSettings.swift` with:

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

/// Top-level app settings. Visual + audio knobs live in per-style profiles
/// (`profiles[visualizerStyle]`); fireworks-only beat-detector tunables live as
/// flat fields on this struct (they only apply when the active style is fireworks).
///
/// For ergonomic access, the old flat field NAMES (`gain`, `smoothing`, etc.) are
/// preserved as computed forwarder properties that read/write the CURRENT profile.
/// That keeps every visualizer / view / test compiling unchanged after this refactor.
public struct VisualizerSettings: Equatable {
    public var visualizerStyle: VisualizerStyle
    public var profiles: [VisualizerStyle: StyleProfile]

    // Fireworks beat-detector tunables (apply only when style == .fireworks).
    public var fireworksMinBass: Float
    public var fireworksMarginFloor: Float
    public var fireworksMarginScale: Float
    public var fireworksBaselineAlpha: Float

    public init(visualizerStyle: VisualizerStyle,
                profiles: [VisualizerStyle: StyleProfile],
                fireworksMinBass: Float,
                fireworksMarginFloor: Float,
                fireworksMarginScale: Float,
                fireworksBaselineAlpha: Float) {
        self.visualizerStyle = visualizerStyle
        self.profiles = profiles
        self.fireworksMinBass = fireworksMinBass
        self.fireworksMarginFloor = fireworksMarginFloor
        self.fireworksMarginScale = fireworksMarginScale
        self.fireworksBaselineAlpha = fireworksBaselineAlpha
    }

    /// Returns the profile for the current style (falls back to defaults).
    public var current: StyleProfile {
        profiles[visualizerStyle] ?? .defaults
    }

    /// In-place mutation of the current style's profile.
    public mutating func mutateCurrent(_ body: (inout StyleProfile) -> Void) {
        var p = profiles[visualizerStyle] ?? .defaults
        body(&p)
        profiles[visualizerStyle] = p
    }

    public static let defaults: VisualizerSettings = {
        var profiles: [VisualizerStyle: StyleProfile] = [:]
        for s in VisualizerStyle.allCases { profiles[s] = .defaults }
        return VisualizerSettings(
            visualizerStyle: .bars,
            profiles: profiles,
            fireworksMinBass: 0.05,
            fireworksMarginFloor: 0.015,
            fireworksMarginScale: 0.5,
            fireworksBaselineAlpha: 0.05
        )
    }()
}

// MARK: - Forwarders to the current profile
//
// These let existing code (every visualizer, MetalView, RenderModel, SettingsView)
// keep using `settings.gain` / `settings.paletteName` / etc. unchanged — every read
// hits the current profile, every write mutates only the current profile.

public extension VisualizerSettings {
    var paletteName: String {
        get { current.paletteName }
        set { mutateCurrent { $0.paletteName = newValue } }
    }
    var customStops: [RGBAColor] {
        get { current.customStops }
        set { mutateCurrent { $0.customStops = newValue } }
    }
    var gain: Float {
        get { current.gain }
        set { mutateCurrent { $0.gain = newValue } }
    }
    var barCount: Int {
        get { current.barCount }
        set { mutateCurrent { $0.barCount = newValue } }
    }
    var smoothing: Float {
        get { current.smoothing }
        set { mutateCurrent { $0.smoothing = newValue } }
    }
    var peakHoldEnabled: Bool {
        get { current.peakHoldEnabled }
        set { mutateCurrent { $0.peakHoldEnabled = newValue } }
    }
    var glowEnabled: Bool {
        get { current.glowEnabled }
        set { mutateCurrent { $0.glowEnabled = newValue } }
    }
    var glowIntensity: Float {
        get { current.glowIntensity }
        set { mutateCurrent { $0.glowIntensity = newValue } }
    }
    var overlayEnabled: Bool {
        get { current.overlayEnabled }
        set { mutateCurrent { $0.overlayEnabled = newValue } }
    }
    var overlayPosition: OverlayCorner {
        get { current.overlayPosition }
        set { mutateCurrent { $0.overlayPosition = newValue } }
    }
    var overlayOpacity: Float {
        get { current.overlayOpacity }
        set { mutateCurrent { $0.overlayOpacity = newValue } }
    }
    var alwaysOnTop: Bool {
        get { current.alwaysOnTop }
        set { mutateCurrent { $0.alwaysOnTop = newValue } }
    }
    var fullscreenDisplayID: UInt32? {
        get { current.fullscreenDisplayID }
        set { mutateCurrent { $0.fullscreenDisplayID = newValue } }
    }
    var targetFPS: Int {
        get { current.targetFPS }
        set { mutateCurrent { $0.targetFPS = newValue } }
    }
    var backgroundStyle: BackgroundStyle {
        get { current.backgroundStyle }
        set { mutateCurrent { $0.backgroundStyle = newValue } }
    }
}

// MARK: - Persistence

public extension VisualizerSettings {
    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("MacVisualizer", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    static func load(from url: URL) -> VisualizerSettings {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(VisualizerSettings.self, from: data)
        else { return .defaults }
        return decoded
    }

    func save(to url: URL) throws {
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

// MARK: - Codable (tolerant decoder + migration from old flat-field JSON)

extension VisualizerSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case visualizerStyle, profiles
        case fireworksMinBass, fireworksMarginFloor, fireworksMarginScale, fireworksBaselineAlpha
        // Legacy flat fields (old format) — used for migration only.
        case paletteName, customStops, gain, barCount, smoothing, peakHoldEnabled
        case glowEnabled, glowIntensity
        case overlayEnabled, overlayPosition, overlayOpacity
        case alwaysOnTop, fullscreenDisplayID, targetFPS, backgroundStyle
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VisualizerSettings.defaults

        let style = try c.decodeIfPresent(VisualizerStyle.self, forKey: .visualizerStyle) ?? d.visualizerStyle
        let fmb  = try c.decodeIfPresent(Float.self, forKey: .fireworksMinBass) ?? d.fireworksMinBass
        let fmf  = try c.decodeIfPresent(Float.self, forKey: .fireworksMarginFloor) ?? d.fireworksMarginFloor
        let fms  = try c.decodeIfPresent(Float.self, forKey: .fireworksMarginScale) ?? d.fireworksMarginScale
        let fba  = try c.decodeIfPresent(Float.self, forKey: .fireworksBaselineAlpha) ?? d.fireworksBaselineAlpha

        let profiles: [VisualizerStyle: StyleProfile]
        if let decodedProfiles = try c.decodeIfPresent([VisualizerStyle: StyleProfile].self, forKey: .profiles) {
            // New format: start from defaults so any missing style is populated.
            var merged: [VisualizerStyle: StyleProfile] = [:]
            for s in VisualizerStyle.allCases { merged[s] = .defaults }
            for (k, v) in decodedProfiles { merged[k] = v }
            profiles = merged
        } else {
            // Migration: build one profile per style from the old flat fields.
            let dp = StyleProfile.defaults
            let migrated = StyleProfile(
                paletteName: try c.decodeIfPresent(String.self, forKey: .paletteName) ?? dp.paletteName,
                customStops: try c.decodeIfPresent([RGBAColor].self, forKey: .customStops) ?? dp.customStops,
                gain: try c.decodeIfPresent(Float.self, forKey: .gain) ?? dp.gain,
                barCount: try c.decodeIfPresent(Int.self, forKey: .barCount) ?? dp.barCount,
                smoothing: try c.decodeIfPresent(Float.self, forKey: .smoothing) ?? dp.smoothing,
                peakHoldEnabled: try c.decodeIfPresent(Bool.self, forKey: .peakHoldEnabled) ?? dp.peakHoldEnabled,
                glowEnabled: try c.decodeIfPresent(Bool.self, forKey: .glowEnabled) ?? dp.glowEnabled,
                glowIntensity: try c.decodeIfPresent(Float.self, forKey: .glowIntensity) ?? dp.glowIntensity,
                overlayEnabled: try c.decodeIfPresent(Bool.self, forKey: .overlayEnabled) ?? dp.overlayEnabled,
                overlayPosition: try c.decodeIfPresent(OverlayCorner.self, forKey: .overlayPosition) ?? dp.overlayPosition,
                overlayOpacity: try c.decodeIfPresent(Float.self, forKey: .overlayOpacity) ?? dp.overlayOpacity,
                alwaysOnTop: try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? dp.alwaysOnTop,
                fullscreenDisplayID: try c.decodeIfPresent(UInt32.self, forKey: .fullscreenDisplayID) ?? dp.fullscreenDisplayID,
                targetFPS: try c.decodeIfPresent(Int.self, forKey: .targetFPS) ?? dp.targetFPS,
                backgroundStyle: try c.decodeIfPresent(BackgroundStyle.self, forKey: .backgroundStyle) ?? dp.backgroundStyle
            )
            var fresh: [VisualizerStyle: StyleProfile] = [:]
            for s in VisualizerStyle.allCases { fresh[s] = migrated }
            profiles = fresh
        }

        self.init(
            visualizerStyle: style,
            profiles: profiles,
            fireworksMinBass: fmb,
            fireworksMarginFloor: fmf,
            fireworksMarginScale: fms,
            fireworksBaselineAlpha: fba
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(visualizerStyle, forKey: .visualizerStyle)
        try c.encode(profiles, forKey: .profiles)
        try c.encode(fireworksMinBass, forKey: .fireworksMinBass)
        try c.encode(fireworksMarginFloor, forKey: .fireworksMarginFloor)
        try c.encode(fireworksMarginScale, forKey: .fireworksMarginScale)
        try c.encode(fireworksBaselineAlpha, forKey: .fireworksBaselineAlpha)
        // Legacy fields are NOT encoded — the encoder produces only the new schema.
    }
}
```

(This replaces the previous `VisualizerSettings.swift` entirely. The old struct's bodies for `defaults`, `save`/`load`, and the prior tolerant `init(from:)`/`encode(to:)` are gone; the public API surface is preserved via the forwarders, plus the new `profiles`, `current`, `mutateCurrent`. `RGBAColor`/`OverlayCorner`/`BackgroundStyle` move into this same file so the namespace stays as it was — they were already defined here.)

- [ ] **Step 6: Update existing tests in `VisualizerSettingsTests.swift`.**

The existing `testJSONRoundTrips` and `testSaveThenLoadRoundTrips` set fields on `s` directly (e.g. `s.gain = 2.5`) and compare encoded↔decoded. They still pass because the setters now write through to the current profile and `Equatable` compares the new stored fields. **No changes needed to those tests.**

The existing `testLoadReturnsDefaultsWhenFileMissing` still passes (returns `.defaults`).

The existing `testDefaultsAreSensible` reads `s.barCount`, `s.targetFPS`, `s.gain`, `s.smoothing`, `s.peakHoldEnabled`, `s.paletteName`. These all read via the forwarders from `current` (which is `.defaults` for the default `.bars` style). **No changes needed.**

The existing `testPartialJSONDecodesWithDefaults` decodes `{"gain": 2.5, "barCount": 64}` and asserts the defaulted fields. Under the new migration path, this JSON has no `profiles` key → migration populates every profile with `gain=2.5`, `barCount=64`, and defaults for everything else. The forwarder for `decoded.gain` returns the current profile's `gain` → 2.5. The defaults for `visualizerStyle` etc. still match. **No change needed; this test now also exercises the migration path.**

(`testVisualizerStyleRoundTrips` and similar tests for prior fields likewise still pass.)

- [ ] **Step 7: Run `make test`** — expect `** TEST SUCCEEDED **`. Test count grows from 108 (after Task 1) to **116** (+2 in StyleProfileTests, +6 in the new VisualizerSettingsTests methods).

- [ ] **Step 8: Run `make build`** — `** BUILD SUCCEEDED **`. The forwarders mean every existing consumer (visualizers, MetalView, RenderModel, RenderProbe, SettingsView, every test) compiles unchanged.

- [ ] **Step 9: Render-probe regression** — `./DerivedData/Build/Products/Debug/MacVisualizer.app/Contents/MacOS/MacVisualizer --render-probe /tmp/p_t2.png bars`. Read it: still the green→red staircase.

- [ ] **Step 10: Commit**

```bash
git add Sources/Core/StyleProfile.swift Sources/Core/VisualizerSettings.swift Tests/CoreTests/StyleProfileTests.swift Tests/CoreTests/VisualizerSettingsTests.swift
git commit -m "Add StyleProfile and per-style profiles via tolerant migration + forwarders"
```

---

## Task 3: Settings UI — `TabView`, resizable, two Reset buttons

**Files:**
- Modify: `Sources/App/SettingsView.swift`

- [ ] **Step 1: Read the current `SettingsView.swift`** to confirm its existing sections (Visualization, Palette, Sensitivity, Track Overlay, Window) and the `@ObservedObject var model: RenderModel`.

- [ ] **Step 2: Replace the entire contents** of `Sources/App/SettingsView.swift` with:

```swift
import SwiftUI
import MacVisualizerCore

/// Tabbed, resizable Settings. Most controls edit the CURRENT style's profile
/// (so each visualizer style remembers its own settings). The Fireworks tab
/// edits the shared fireworks beat-detector tunables (top-level on
/// `VisualizerSettings`; they apply only when the active style is fireworks).
struct SettingsView: View {
    @ObservedObject var model: RenderModel

    @State private var confirmResetThisStyle = false
    @State private var confirmResetAllStyles = false

    private let palettes = ["classic", "phosphor", "synthwave"]
    private let fpsOptions = [30, 60, 120]

    var body: some View {
        VStack(spacing: 0) {
            editingHeader

            TabView {
                visualizationTab
                    .tabItem { Label("Visualization", systemImage: "square.grid.2x2") }

                audioTab
                    .tabItem { Label("Audio", systemImage: "waveform") }

                overlayTab
                    .tabItem { Label("Overlay", systemImage: "rectangle.inset.topleft.filled") }

                windowTab
                    .tabItem { Label("Window", systemImage: "macwindow") }

                fireworksTab
                    .tabItem { Label("Fireworks", systemImage: "sparkles") }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Divider()
            resetFooter
        }
        .frame(minWidth: 460, minHeight: 420)
        .alert("Reset \(model.settings.visualizerStyle.displayName) to defaults?",
               isPresented: $confirmResetThisStyle) {
            Button("Reset", role: .destructive) { resetThisStyle() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This restores the \(model.settings.visualizerStyle.displayName) profile to defaults. Other styles are unchanged.")
        }
        .alert("Reset ALL styles to defaults?",
               isPresented: $confirmResetAllStyles) {
            Button("Reset All", role: .destructive) { resetAllStyles() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This restores every visualizer style's profile AND the Fireworks tunables to defaults. This cannot be undone.")
        }
    }

    // MARK: - Header

    private var editingHeader: some View {
        HStack {
            Text("Editing \(model.settings.visualizerStyle.displayName) profile")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Tabs

    private var visualizationTab: some View {
        Form {
            Section("Style") {
                Picker("Active style", selection: $model.settings.visualizerStyle) {
                    ForEach(VisualizerStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            Section("Palette") {
                Picker("Color palette",
                       selection: bind(\.paletteName)) {
                    ForEach(palettes, id: \.self) { Text($0.capitalized).tag($0) }
                }
            }
            Section("Glow") {
                Toggle("Enable glow", isOn: bind(\.glowEnabled))
                Slider(value: bind(\.glowIntensity), in: 0...1.5) {
                    Text("Intensity")
                } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1.5") }
            }
            Section("Spectrum") {
                Toggle("Peak-hold caps", isOn: bind(\.peakHoldEnabled))
            }
        }
        .formStyle(.grouped)
    }

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

    private var overlayTab: some View {
        Form {
            Section("Track Overlay") {
                Toggle("Show overlay", isOn: bind(\.overlayEnabled))
                Picker("Position", selection: bind(\.overlayPosition)) {
                    Text("Top Left").tag(OverlayCorner.topLeading)
                    Text("Top Right").tag(OverlayCorner.topTrailing)
                    Text("Bottom Left").tag(OverlayCorner.bottomLeading)
                    Text("Bottom Right").tag(OverlayCorner.bottomTrailing)
                }
                Slider(value: bind(\.overlayOpacity), in: 0.2...1) {
                    Text("Opacity")
                } minimumValueLabel: { Text("20%") } maximumValueLabel: { Text("100%") }
            }
        }
        .formStyle(.grouped)
    }

    private var windowTab: some View {
        Form {
            Section("Window") {
                Toggle("Always on top", isOn: bind(\.alwaysOnTop))
                Picker("Frame rate", selection: bind(\.targetFPS)) {
                    ForEach(fpsOptions, id: \.self) { Text("\($0) fps").tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var fireworksTab: some View {
        Form {
            Section {
                Text("These knobs apply only when the active style is Fireworks. Drag while music plays to dial in beat detection.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Beat detector") {
                Slider(value: $model.settings.fireworksMinBass, in: 0...0.2) {
                    Text("Min bass")
                } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.2") }
                Slider(value: $model.settings.fireworksMarginFloor, in: 0...0.1) {
                    Text("Margin floor")
                } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.1") }
                Slider(value: $model.settings.fireworksMarginScale, in: 0...2) {
                    Text("Margin × baseline")
                } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("2") }
                Slider(value: $model.settings.fireworksBaselineAlpha, in: 0...0.2) {
                    Text("Baseline smoothing")
                } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.2") }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Footer

    private var resetFooter: some View {
        HStack {
            Spacer()
            Button("Reset This Style") { confirmResetThisStyle = true }
                .keyboardShortcut(.defaultAction)
            Button("Reset All Styles", role: .destructive) { confirmResetAllStyles = true }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Reset actions

    private func resetThisStyle() {
        model.settings.mutateCurrent { $0 = .defaults }
        if model.settings.visualizerStyle == .fireworks {
            model.settings.fireworksMinBass = VisualizerSettings.defaults.fireworksMinBass
            model.settings.fireworksMarginFloor = VisualizerSettings.defaults.fireworksMarginFloor
            model.settings.fireworksMarginScale = VisualizerSettings.defaults.fireworksMarginScale
            model.settings.fireworksBaselineAlpha = VisualizerSettings.defaults.fireworksBaselineAlpha
        }
    }

    private func resetAllStyles() {
        model.settings = .defaults
    }

    // MARK: - Bindings to the current profile

    /// Builds a SwiftUI Binding to a field on the current style's profile.
    /// Reads via `settings.current` (the forwarder), writes via `mutateCurrent`.
    private func bind<T>(_ keyPath: WritableKeyPath<StyleProfile, T>) -> Binding<T> {
        Binding(
            get: { model.settings.current[keyPath: keyPath] },
            set: { newValue in
                model.settings.mutateCurrent { $0[keyPath: keyPath] = newValue }
            }
        )
    }
}
```

(The previous fixed-size `.frame(width:height:)` is replaced by the `VStack`'s `.frame(minWidth:minHeight:)`. The footer is always visible; tabs scroll/size naturally.)

- [ ] **Step 3: Build + tests** — `make build` → `** BUILD SUCCEEDED **`; `make test` → `** TEST SUCCEEDED **`, 116.

- [ ] **Step 4: Probe regression** — `./DerivedData/Build/Products/Debug/MacVisualizer.app/Contents/MacOS/MacVisualizer --render-probe /tmp/p_t3.png radial glow`. Read it: the radial burst with the glow halo (rendering unaffected).

- [ ] **Step 5: Launch check**
```bash
osascript -e 'quit app "MacVisualizer"' 2>/dev/null; pkill -x MacVisualizer 2>/dev/null; sleep 1
make run >/dev/null 2>&1 & sleep 3; pgrep -x MacVisualizer >/dev/null && echo "running ok"; osascript -e 'quit app "MacVisualizer"' 2>/dev/null || pkill -x MacVisualizer || true
```
Expect `running ok`.

- [ ] **Step 6: Commit**

```bash
git add Sources/App/SettingsView.swift
git commit -m "Refactor Settings to resizable TabView with per-style profiles and Reset buttons"
```

---

## Task 4: Retire the `/tune-fireworks` skill

The live sliders supersede the swept tuner. Delete the skill directory.

**Files:**
- Delete: `.claude/skills/tune-fireworks/SKILL.md` (and the directory)

- [ ] **Step 1: Delete the directory**

```bash
git rm -r .claude/skills/tune-fireworks
```

- [ ] **Step 2: Commit**

```bash
git commit -m "Retire /tune-fireworks skill (superseded by live Fireworks sliders in Settings)"
```

---

## Task 5: Live verification (user)

Build + tests + probe done; this last task is user-driven.

- [ ] **Step 1: Launch the app**
```bash
make run
```

- [ ] **Step 2: Verify per-style profiles**
- Press ⌘, to open Settings. Confirm the **"Editing Bars profile"** label appears.
- On the Audio tab, drag Gain to ~3.0. Confirm bars get taller.
- Switch the **Style** picker (Visualization tab) to Radial. The label changes to "Editing Radial profile." Gain shows its own value (default 1.0). Drag Gain to ~0.7. Confirm bars/visuals respond live, but the Bars profile's 3.0 is preserved when you switch back.
- Repeat with Palette: set Bars → phosphor, Radial → synthwave. Switch among styles, confirm each remembers its own palette.

- [ ] **Step 3: Verify Fireworks sliders are live**
- Switch the active style to Fireworks. Open the Fireworks tab. Drag Min bass / Margin floor / Margin × baseline / Baseline smoothing while music plays. Confirm burst rate / sensitivity changes immediately.

- [ ] **Step 4: Verify Reset buttons**
- With current style = Fireworks, tune the sliders to obviously-wrong values. Click **Reset This Style** → confirm in the alert → values snap back to defaults; other styles unchanged.
- Tune several styles' profiles non-default. Click **Reset All Styles** → confirm → every style returns to defaults; Fireworks tunables return to defaults.

- [ ] **Step 5: Verify resizable window**
- Drag the Settings window's bottom-right corner to grow it. It resizes. Drag down to the minimum — content stays usable.

- [ ] **Step 6: Verify persistence (per-style profiles persist across relaunch)**
- Set a distinctive value in each of two styles' profiles.
- Quit the app, relaunch (`make run`). Open Settings. Switch between those styles — each remembers its distinctive value.

(There's nothing to commit in this task. If anything didn't work, capture what you saw before adjusting.)

---

## Definition of Done

- `make test` → `** TEST SUCCEEDED **`, 116 tests passing (3 fireworks-fields + 2 StyleProfile + 6 per-style/migration).
- `make build` → `** BUILD SUCCEEDED **`.
- The render probe still produces correct bars / radial / fireworks PNGs (regression unchanged).
- Each visualizer style remembers its own profile across switches and across relaunch (verified live).
- The Settings window is a resizable `TabView` with five tabs and the "Editing X profile" label; **Reset This Style** and **Reset All Styles** behave per spec (resetting Fireworks's own profile also resets the fireworks tunables when Reset This Style fires on Fireworks).
- The fireworks beat-detector sliders take effect live during playback.
- `/tmp/fireworks.log` diagnostic and the `.claude/skills/tune-fireworks/` directory are removed.

## Notes on implementation choices

- **Forwarder properties** (`var gain: Float { get { current.gain }; set { mutateCurrent { $0.gain = newValue } } }`) keep every existing visualizer / `MetalView` / `RenderModel` / `RenderProbe` / test compiling **unchanged** after the refactor. Each read/write transparently hits the current profile. The spec's design goal ("every visualizer reads from the current profile") is achieved without touching their source.
- **Single fireworks block** (top-level, not per-profile) honors the spec's reasoning: the four knobs only apply when the active style is `.fireworks`, so duplicating them on the other six profiles would just waste bytes and create the puzzle of "which copy wins."
- The reset semantics for Fireworks (Reset This Style also clears the four shared tunables when current = fireworks) match the spec.
