# Polartone Spiral Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a time-driven "breathing spiral" render mode to the existing Polartone visualizer that winds between an outer and inner radius bound, hard-wiping and reversing direction at each bound, while preserving today's static ring as the default.

**Architecture:** Add a per-style `PolartoneRenderMode` (`ring`|`spiral`) enum on `StyleProfile` (mirroring `voronoiRenderMode`/`lavaLampRenderMode`); convert `PolartoneVisualizer` from `struct` to `class` so it can hold cross-frame spiral state (angle, radius, direction, accumulated points); add spiral-only scalar settings and surface them in the active-aware Settings UI when the mode is spiral. Polartone is a CPU vertex-emit visualizer, so there are no Metal/shader changes.

**Tech Stack:** Swift 5.10, XcodeGen + Makefile, XCTest. Build/test via `make`. `Sources/Core` is glob-included, so new Core files need NO `project.yml` edit.

## Global Constraints

- Build: `USER=eespino LOGNAME=eespino make build` must end `** BUILD SUCCEEDED **`.
- Test: `USER=eespino LOGNAME=eespino make test` must end `** TEST SUCCEEDED **` with 0 failures. Current baseline on `main`: **324 tests**.
- `Sources/Core` must carry no Metal/AppKit imports (layering rule); `PolartoneVisualizer` stays Core-only.
- Every new settings field uses tolerant Codable: `decodeIfPresent(...) ?? <default>`; legacy flat JSON must still decode (resolving new keys to defaults).
- Default `polartoneRenderMode` is `.ring`; with defaults unchanged, Polartone output must be byte-identical to the current shipped behavior.
- New source files carry the existing 16-line Apache-2.0 header used across the repo's Swift files.
- Frequent commits: one commit per task minimum, each with a clear message.

---

### Task 1: Settings model — render-mode enum + spiral scalar fields

**Files:**
- Modify: `Sources/Core/VisualizerSettings.swift` (add enum, `StyleProfile` fields, CodingKeys, init defaults, decode/encode, Equatable if hand-written)
- Test: `Tests/CoreTests/VisualizerSettingsTests.swift` (existing settings test file — add cases)

**Interfaces:**
- Produces:
  - `enum PolartoneRenderMode: String, Codable, CaseIterable { case ring, spiral }`
  - `enum PolartoneStartDirection: String, Codable, CaseIterable { case inward, outward }`
  - On `StyleProfile`: `var polartoneRenderMode: PolartoneRenderMode` (default `.ring`), `var polartoneInnerThreshold: Float` (default `0.05`), `var polartoneDriftRevolutions: Float` (default `8`), `var polartoneStartDirection: PolartoneStartDirection` (default `.inward`).

> Mirror the EXISTING `voronoiRenderMode` / `lavaLampRenderMode` enum + the recently-added `polartoneRadius`/`polartoneAmplitude` scalar fields for every touch point: property declaration, init parameter + default, CodingKeys entry, `decodeIfPresent ?? default` in `init(from:)`, `encode` in `encode(to:)`, and the flat-JSON→profiles migration path. Locate those patterns in the file (do not rely on line numbers; the file changed in the settings-restructure merge).

- [ ] **Step 1: Write the failing tests**

Add to `Tests/CoreTests/VisualizerSettingsTests.swift`:

```swift
func testPolartoneRenderModeDefaultsToRing() {
    let profile = StyleProfile()            // or the project's default-profile constructor
    XCTAssertEqual(profile.polartoneRenderMode, .ring)
}

func testPolartoneSpiralFieldDefaults() {
    let p = StyleProfile()
    XCTAssertEqual(p.polartoneInnerThreshold, 0.05, accuracy: 1e-6)
    XCTAssertEqual(p.polartoneDriftRevolutions, 8, accuracy: 1e-6)
    XCTAssertEqual(p.polartoneStartDirection, .inward)
}

func testPolartoneSpiralFieldsRoundTrip() throws {
    var p = StyleProfile()
    p.polartoneRenderMode = .spiral
    p.polartoneInnerThreshold = 0.12
    p.polartoneDriftRevolutions = 14
    p.polartoneStartDirection = .outward
    let data = try JSONEncoder().encode(p)
    let decoded = try JSONDecoder().decode(StyleProfile.self, from: data)
    XCTAssertEqual(decoded, p)
}

func testPolartoneRenderModeTolerantDecodeFromLegacyJSON() throws {
    // A profile JSON object with NONE of the new keys must decode to defaults.
    let legacy = "{}".data(using: .utf8)!     // replace with the project's minimal valid StyleProfile JSON if {} is insufficient
    let decoded = try JSONDecoder().decode(StyleProfile.self, from: legacy)
    XCTAssertEqual(decoded.polartoneRenderMode, .ring)
    XCTAssertEqual(decoded.polartoneStartDirection, .inward)
}
```

If `StyleProfile()` is not the real default constructor, use the same constructor the existing `polartoneRadius` tests use.

- [ ] **Step 2: Run tests, verify they fail**

Run: `USER=eespino LOGNAME=eespino make test`
Expected: FAIL — `value of type 'StyleProfile' has no member 'polartoneRenderMode'` (compile error) or assertion failures.

- [ ] **Step 3: Add the enums + fields + Codable wiring**

Add the two enums at file scope (near the existing render-mode enums):

```swift
public enum PolartoneRenderMode: String, Codable, CaseIterable {
    case ring
    case spiral
}

public enum PolartoneStartDirection: String, Codable, CaseIterable {
    case inward
    case outward
}
```

On `StyleProfile`, add the four stored properties with defaults, then wire each through CodingKeys, `init(from:)` (`decodeIfPresent ?? default`), `encode(to:)`, the memberwise/default init, and the migration path — exactly as `polartoneRadius` is wired. Keep `Equatable` correct (if synthesized, nothing to do; if hand-written, add the four fields).

- [ ] **Step 4: Run tests, verify they pass**

Run: `USER=eespino LOGNAME=eespino make test`
Expected: PASS — baseline + 4 new tests (328 total).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/VisualizerSettings.swift Tests/CoreTests/VisualizerSettingsTests.swift
git commit -m "Add Polartone render-mode + spiral settings fields"
```

---

### Task 2: Convert PolartoneVisualizer struct → class (ring-mode preserved, no behavior change)

**Files:**
- Modify: `Sources/Core/PolartoneVisualizer.swift` (`struct` → `final class`)
- Test: `Tests/CoreTests/PolartoneVisualizerTests.swift` (existing; add a regression test)

**Interfaces:**
- Consumes: `VisualizerSettings` / `StyleProfile` fields from Task 1.
- Produces: `final class PolartoneVisualizer` conforming to the same `Visualizer` protocol with the same `makeVertices(...)` signature. Ring-mode output identical to the prior struct.

> This task does NOT add spiral behavior. It is the safe refactor + regression guard so spiral work in Task 3 can't silently change the default look.

- [ ] **Step 1: Write the ring-mode regression test**

Capture current output as the oracle. Add to `Tests/CoreTests/PolartoneVisualizerTests.swift`:

```swift
func testRingModeOutputUnchangedAfterClassConversion() {
    // Deterministic synthetic frame (reuse the helper the existing Polartone tests use).
    let frame = AudioFrame.fixture(/* same params existing tests use */)
    var settings = VisualizerSettings()
    settings.profile(for: .polartone).polartoneRenderMode = .ring   // default; explicit for intent

    let viz = PolartoneVisualizer()
    let verts = viz.makeVertices(frame: frame, settings: settings, size: CGSize(width: 800, height: 600))

    XCTAssertFalse(verts.isEmpty)
    // Pin a few invariants that the struct produced (counts + first/last positions),
    // matching whatever the existing Polartone tests already assert for the ring.
    XCTAssertEqual(verts.count, /* the count the existing ring test expects */)
}
```

Use the exact frame fixture + settings accessor the current Polartone tests use (grep `PolartoneVisualizerTests` for the helper). If an existing ring test already asserts vertex output, this step is "keep that test green through the conversion" — note that and reuse it as the oracle.

- [ ] **Step 2: Run test, verify it passes against the current struct**

Run: `USER=eespino LOGNAME=eespino make test`
Expected: PASS (establishes the oracle before refactor).

- [ ] **Step 3: Convert struct → final class**

- Change `struct PolartoneVisualizer` to `final class PolartoneVisualizer`.
- Add an explicit `public init()` (and any init the struct had implicitly).
- Keep `makeVertices(...)` non-`mutating` (protocol requirement) — a class method needs no `mutating`.
- Grep the codebase for every use site: `grep -rn "PolartoneVisualizer" Sources Tests`. Verify NONE rely on value-semantics copying (e.g. `var v = PolartoneVisualizer(); let w = v` expecting independent copies). Document the grep result in the commit message. The live use site (`Sources/Rendering/MetalView.swift`) stores one instance and calls it — reference semantics are fine there.

- [ ] **Step 4: Run tests, verify still green**

Run: `USER=eespino LOGNAME=eespino make test`
Expected: PASS — same count as end of Task 1 (regression test confirms ring output unchanged).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/PolartoneVisualizer.swift Tests/CoreTests/PolartoneVisualizerTests.swift
git commit -m "Convert PolartoneVisualizer to class (ring output unchanged); document no value-semantics use sites"
```

---

### Task 3: Spiral motion state machine + per-frame logic

**Files:**
- Modify: `Sources/Core/PolartoneVisualizer.swift` (add spiral state + spiral branch in `makeVertices`)
- Test: `Tests/CoreTests/PolartoneVisualizerTests.swift` (add spiral tests)

**Interfaces:**
- Consumes: Task 1 fields (`polartoneRenderMode`, `polartoneRadius`, `polartoneInnerThreshold`, `polartoneDriftRevolutions`, `polartoneStartDirection`, `polartoneRotationSpeed`, `polartoneAmplitude`), Task 2 class.
- Produces: spiral state on the class and a `spiral` branch in `makeVertices`.

**State to add to the class:**

```swift
private enum SweepDirection { case inward, outward }
private var spiralAngle: Float = 0
private var spiralRadius: Float = 0
private var spiralDirection: SweepDirection = .inward
private var spiralPoints: [SIMD2<Float>] = []
private var lastTimestamp: Double? = nil
private var spiralInitialized = false
private let maxSpiralPoints = 4000
private let minAngularSpeed: Float = 0.6   // rad/s fallback when rotationSpeed == 0
private let dtMax: Double = 0.1             // clamp for pauses / first frame
```

**Per-frame algorithm (spiral branch of `makeVertices`):**

```swift
// outerBound = profile.polartoneRadius ; inner = profile.polartoneInnerThreshold
// On first spiral frame (or after reset): initialize from start direction.
if !spiralInitialized {
    spiralDirection = (profile.polartoneStartDirection == .inward) ? .inward : .outward
    spiralRadius = (spiralDirection == .inward) ? outerBound : inner
    spiralAngle = 0
    spiralPoints.removeAll(keepingCapacity: true)
    spiralInitialized = true
    lastTimestamp = nil
}

// dt from frame timestamp, clamped.
let dt: Double
if let last = lastTimestamp { dt = min(max(frame.timestamp - last, 0), dtMax) } else { dt = 0 }
lastTimestamp = frame.timestamp

// Angular advance (fallback when user left rotationSpeed at 0).
let angSpeed = (profile.polartoneRotationSpeed != 0) ? abs(profile.polartoneRotationSpeed) : minAngularSpeed
spiralAngle += angSpeed * Float(dt)

// Radial drift: cross outerBound->inner over `driftRevolutions` turns.
let span = max(outerBound - inner, 1e-4)
let revs = max(profile.polartoneDriftRevolutions, 0.1)
let radialPerRadian = span / (revs * 2 * .pi)          // distance per radian of sweep
let radialStep = radialPerRadian * angSpeed * Float(dt)
spiralRadius += (spiralDirection == .inward) ? -radialStep : radialStep

// Bound check -> HARD WIPE + reverse.
if spiralDirection == .inward && spiralRadius <= inner {
    spiralRadius = inner
    spiralDirection = .outward
    spiralPoints.removeAll(keepingCapacity: true)        // wipe in one frame
} else if spiralDirection == .outward && spiralRadius >= outerBound {
    spiralRadius = outerBound
    spiralDirection = .inward
    spiralPoints.removeAll(keepingCapacity: true)
}

// Append the new point (waveform deflects radius, reusing amplitude).
let deflection = waveformSample(frame) * profile.polartoneAmplitude   // same sampling the ring uses
let r = spiralRadius + deflection
let pt = SIMD2<Float>(r * cos(spiralAngle), r * sin(spiralAngle))
spiralPoints.append(pt)
if spiralPoints.count > maxSpiralPoints { spiralPoints.removeFirst(spiralPoints.count - maxSpiralPoints) }

// Emit polyline vertices from spiralPoints using the SAME thickness/color construction the ring path uses.
return buildPolylineVertices(spiralPoints, profile: profile, size: size)
```

Reuse the ring path's existing waveform sampling, color-floor, and vertex/thickness construction helpers; factor them out if needed so both modes share them (DRY). The `makeVertices` body becomes `switch profile.polartoneRenderMode { case .ring: <existing>; case .spiral: <above> }`.

- [ ] **Step 1: Write the failing spiral tests**

```swift
private func spiralSettings(inner: Float = 0.05, revs: Float = 8,
                            start: PolartoneStartDirection = .inward) -> VisualizerSettings {
    var s = VisualizerSettings()
    let p = s.profile(for: .polartone)              // use the project's accessor
    p.polartoneRenderMode = .spiral
    p.polartoneRadius = 0.9
    p.polartoneInnerThreshold = inner
    p.polartoneDriftRevolutions = revs
    p.polartoneStartDirection = start
    p.polartoneRotationSpeed = 1.0
    return s
}

// Drives N frames at fixed dt by advancing timestamp.
private func drive(_ viz: PolartoneVisualizer, _ settings: VisualizerSettings,
                   frames: Int, dt: Double) -> [[BarVertex]] {
    var out: [[BarVertex]] = []
    var t = 0.0
    for _ in 0..<frames {
        let f = AudioFrame.fixture(timestamp: t)     // silent/flat waveform fixture
        out.append(viz.makeVertices(frame: f, settings: settings, size: CGSize(width: 800, height: 600)))
        t += dt
    }
    return out
}

func testSpiralRadiusMonotonicWithinInwardSweep() {
    let viz = PolartoneVisualizer()
    let s = spiralSettings(revs: 50)   // slow enough to stay in one sweep
    _ = drive(viz, s, frames: 30, dt: 1.0/60.0)
    XCTAssertTrue(viz.debugSpiralRadius < 0.9)          // moved inward from outer bound
    XCTAssertEqual(viz.debugSpiralDirection, .inward)   // not yet reversed
}

func testSpiralWipesAndReversesAtInnerThreshold() {
    let viz = PolartoneVisualizer()
    let s = spiralSettings(revs: 1)    // fast: reach inner quickly
    var reversed = false
    var t = 0.0
    for _ in 0..<2000 {
        _ = viz.makeVertices(frame: AudioFrame.fixture(timestamp: t),
                             settings: s, size: CGSize(width: 800, height: 600))
        if viz.debugSpiralDirection == .outward { reversed = true; break }
        t += 1.0/60.0
    }
    XCTAssertTrue(reversed, "spiral should reverse to outward after collapsing inward")
}

func testSpiralBufferNeverExceedsCap() {
    let viz = PolartoneVisualizer()
    let s = spiralSettings(revs: 40)
    _ = drive(viz, s, frames: 6000, dt: 1.0/60.0)
    XCTAssertLessThanOrEqual(viz.debugSpiralPointCount, 4000)
}

func testSpiralDtClampPreventsJump() {
    let viz = PolartoneVisualizer()
    let s = spiralSettings()
    _ = viz.makeVertices(frame: AudioFrame.fixture(timestamp: 0),
                         settings: s, size: CGSize(width: 800, height: 600))
    _ = viz.makeVertices(frame: AudioFrame.fixture(timestamp: 10_000),  // huge gap
                         settings: s, size: CGSize(width: 800, height: 600))
    XCTAssertGreaterThanOrEqual(viz.debugSpiralRadius, 0.0)
    XCTAssertLessThanOrEqual(viz.debugSpiralRadius, 0.9)               // no unbounded jump
}
```

Add minimal `internal` debug accessors on the class for testability (gated, not used by production rendering):

```swift
#if DEBUG
extension PolartoneVisualizer {
    var debugSpiralRadius: Float { spiralRadius }
    var debugSpiralPointCount: Int { spiralPoints.count }
    var debugSpiralDirection: SweepDirection { spiralDirection }
}
#endif
```

(Make `SweepDirection` and the inner threshold comparison testable; if exposing the enum is awkward, expose `debugSpiralIsInward: Bool` instead and adjust the asserts.)

- [ ] **Step 2: Run tests, verify they fail**

Run: `USER=eespino LOGNAME=eespino make test`
Expected: FAIL — missing `debugSpiral*` members / spiral branch not implemented.

- [ ] **Step 3: Implement the spiral branch + state**

Add the state properties and the `switch` on `polartoneRenderMode` with the algorithm above. Keep the `.ring` branch exactly as Task 2 left it.

- [ ] **Step 4: Run tests, verify they pass**

Run: `USER=eespino LOGNAME=eespino make test`
Expected: PASS — Task 1 regression (ring unchanged) still green + 4 spiral tests green.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/PolartoneVisualizer.swift Tests/CoreTests/PolartoneVisualizerTests.swift
git commit -m "Implement Polartone spiral breathing mode (state machine + tests)"
```

---

### Task 4: Settings UI — mode picker + conditional spiral controls

**Files:**
- Modify: `Sources/App/SettingsView.swift` (Polartone controls section)

**Interfaces:**
- Consumes: Task 1 fields, bound via the existing `$model.settings...` profile bindings.

> No new unit test (SwiftUI view). Verification is build + a `#Preview`. Mirror how the existing Polartone sliders (radius/amplitude/etc.) and the Voronoi/LavaLamp render-mode pickers are presented in the restructured active-aware Settings section.

- [ ] **Step 1: Add the mode picker + conditional controls**

In the active-aware "Polartone Controls" section, add a `Picker` bound to `polartoneRenderMode` over `PolartoneRenderMode.allCases`, and render the three spiral controls only when the mode is `.spiral`:

```swift
Picker("Mode", selection: bindingForPolartoneRenderMode) {
    Text("Ring").tag(PolartoneRenderMode.ring)
    Text("Spiral").tag(PolartoneRenderMode.spiral)
}
if activeProfile.polartoneRenderMode == .spiral {
    Slider(value: bindingForInnerThreshold, in: 0.0...0.4) { Text("Inner threshold") }
    Slider(value: bindingForDriftRevolutions, in: 1...40) { Text("Drift (revolutions/sweep)") }
    Picker("Start direction", selection: bindingForStartDirection) {
        Text("Inward").tag(PolartoneStartDirection.inward)
        Text("Outward").tag(PolartoneStartDirection.outward)
    }
}
```

Use the exact binding style already in the file for the existing Polartone scalar sliders (same label/format/`.onChange` conventions). Add/extend a `#Preview` that shows the section with mode = spiral so the conditional block is exercised at build time.

- [ ] **Step 2: Build**

Run: `USER=eespino LOGNAME=eespino make build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run full test suite**

Run: `USER=eespino LOGNAME=eespino make test`
Expected: `** TEST SUCCEEDED **`, 0 failures (settings + spiral tests from Tasks 1 & 3 all green).

- [ ] **Step 4: Commit**

```bash
git add Sources/App/SettingsView.swift
git commit -m "Add Polartone spiral mode picker + conditional controls to Settings"
```

---

## Self-Review

**1. Spec coverage:**
- Render-mode enum + tolerant Codable + migration → Task 1. ✓
- Stateful struct→class + lifecycle/value-semantics check → Task 2. ✓
- Motion model (angle advance, time-driven radial drift, waveform deflection, hard wipe + reverse at both bounds, capacity cap, dt clamp, rotationSpeed-0 fallback) → Task 3. ✓
- New settings fields (innerThreshold, driftRevolutions, startDirection) → Task 1 (model) + Task 4 (UI). ✓
- Settings UI mode picker + conditional spiral controls → Task 4. ✓
- Testing: ring regression (Task 2), radius monotonic / wipe+reverse / buffer cap / dt clamp (Task 3), Codable round-trip + legacy decode (Task 1). ✓
- Out-of-scope items (3D camera, cross-sweep trail, structural arc/alpha) → not in any task, as intended. ✓

**2. Placeholder scan:** Code blocks are concrete. The few "use the project's existing helper / accessor / fixture" notes are deliberate adaptation points to existing code the implementer can see (frame fixture, profile accessor, vertex builder) — not vague requirements; each names exactly what to reuse.

**3. Type consistency:** `PolartoneRenderMode`/`PolartoneStartDirection` (Task 1) used verbatim in Tasks 3–4. `spiralRadius`/`spiralDirection`/`spiralPoints` and `SweepDirection` defined in Task 3 match the `debugSpiral*` accessors and the tests. Field names (`polartoneInnerThreshold`, `polartoneDriftRevolutions`, `polartoneStartDirection`, reused `polartoneRadius`/`polartoneRotationSpeed`/`polartoneAmplitude`) consistent across tasks and with the spec table.
