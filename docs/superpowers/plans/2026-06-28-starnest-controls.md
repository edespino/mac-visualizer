# Star Nest Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose Star Nest's 9 hardcoded shader scalars + 2 density loop-counts as user-tunable settings, surfaced in the active-aware Settings UI, with audio reactivity preserved and defaults reproducing the current look exactly.

**Architecture:** Add 11 flat fields to `VisualizerSettings`; add a Star-Nest-specific uniform at fragment buffer index 2 (mirroring the existing Voronoi/LavaLamp uniform pattern) built by a pure `makeStarNestUniforms(settings:)`; in `Shaders.metal` replace each hardcoded `base` literal with the matching uniform field while leaving the `+ audio·k` modulation intact; add the sliders to the Star Nest controls section.

**Tech Stack:** Swift 5.10, Metal (MSL), XCTest, XcodeGen + Makefile. macOS 14.4+.

## Global Constraints

- Every new settings field defaults to the current shader literal so default output is byte-identical to today.
- Density caps are NOT raised: clamp `volsteps`→`1...26`, `iterations`→`1...16` (the existing loop maxima).
- Audio reactivity model: slider sets the resting `base`; the existing `+ audio·k` modulation stays untouched.
- Mirror existing patterns exactly: `polartone*` fields for settings/Codable; Voronoi/LavaLamp uniform for the buffer-2 shader-params path. Locate patterns by name in the current tree, not by line number.
- Apache-2.0 headers preserved on any touched/new file; commits carry `Co-authored-by: omnigent <noreply@omnigent.ai>`.
- Gates: `USER=eespino LOGNAME=eespino make build` and `make test` must pass before a taskis done.

---

### Task 1: Settings fields

**Files:**
- Modify: `Sources/Core/VisualizerSettings.swift`
- Test: `Tests/CoreTests/VisualizerSettingsTests.swift` (or the existing settings test file)

**Interfaces:**
- Produces: 11 stored properties on `VisualizerSettings` — `starNestZoom: Double` (0.78), `starNestSpeed: Double` (0.18), `starNestFormuparam: Double` (0.53), `starNestTile: Double` (0.85), `starNestStepsize: Double` (0.105), `starNestBrightness: Double` (0.00095), `starNestDarkmatter: Double` (0.34), `starNestDistfading: Double` (0.73), `starNestSaturation: Double` (0.82), `starNestVolsteps: Int` (18), `starNestIterations: Int` (13). All `Codable`, tolerant-decoded, in `==`.

- [ ] **Step 1: Write the failing tests**

Add to the settings test file, mirroring the existing `polartone*` field tests:

```swift
func testStarNestDefaults() {
    let s = VisualizerSettings()
    XCTAssertEqual(s.starNestZoom, 0.78, accuracy: 1e-9)
    XCTAssertEqual(s.starNestSpeed, 0.18, accuracy: 1e-9)
    XCTAssertEqual(s.starNestFormuparam, 0.53, accuracy: 1e-9)
    XCTAssertEqual(s.starNestTile, 0.85, accuracy: 1e-9)
    XCTAssertEqual(s.starNestStepsize, 0.105, accuracy: 1e-9)
    XCTAssertEqual(s.starNestBrightness, 0.00095, accuracy: 1e-9)
    XCTAssertEqual(s.starNestDarkmatter, 0.34, accuracy: 1e-9)
    XCTAssertEqual(s.starNestDistfading, 0.73, accuracy: 1e-9)
    XCTAssertEqual(s.starNestSaturation, 0.82, accuracy: 1e-9)
    XCTAssertEqual(s.starNestVolsteps, 18)
    XCTAssertEqual(s.starNestIterations, 13)
}

func testStarNestCodableRoundTrip() throws {
    var s = VisualizerSettings()
    s.starNestZoom = 1.5
    s.starNestVolsteps = 22
    s.starNestIterations = 9
    let data = try JSONEncoder().encode(s)
    let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
    XCTAssertEqual(decoded, s)
}

func testStarNestTolerantDecodeMissingKeys() throws {
    // Legacy JSON lacking the new keys decodes to defaults.
    let json = "{}".data(using: .utf8)!
    let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
    XCTAssertEqual(decoded.starNestZoom, 0.78, accuracy: 1e-9)
    XCTAssertEqual(decoded.starNestVolsteps, 18)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `USER=eespino LOGNAME=eespino make test`
Expected: FAIL — `value of type 'VisualizerSettings' has no member 'starNestZoom'`.

- [ ] **Step 3: Add the fields**

In `VisualizerSettings.swift`, replicate the exact `polartone*` field treatment for all 11 fields: stored property with default, `CodingKeys` entry, `decodeIfPresent(...) ?? default` in `init(from:)`, `encode(...)` in `encode(to:)`, and inclusion in any hand-written `==` / `Equatable`. Use `Double` for the 9 scalars, `Int` for `starNestVolsteps`/`starNestIterations`. If the flat-JSON→profiles migration path enumerates fields, add these there too (additive; absent keys → defaults).

- [ ] **Step 4: Run to verify pass**

Run: `USER=eespino LOGNAME=eespino make test`
Expected: PASS (the 3 new tests + all prior tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/VisualizerSettings.swift Tests/CoreTests/VisualizerSettingsTests.swift
git commit -m "Add Star Nest control settings fields

Co-authored-by: omnigent <noreply@omnigent.ai>"
```

---

### Task 2: Shader-uniform plumbing + shader substitution

**Files:**
- Modify: `Sources/Rendering/MetalRenderer.swift` (add `StarNestUniforms` Swift struct + `makeStarNestUniforms(settings:)`; bind at buffer 2 in `encodeShaderFill` for `.starNest`)
- Modify: `Sources/Rendering/Shaders.metal` (add matching `StarNestUniforms` Metal struct; Star Nest fragment reads it)
- Test: `Tests/RenderingTests/...` or `Tests/CoreTests/...` wherever the uniform builder can be reached (the builder must be at least `internal`/testable)

**Interfaces:**
- Consumes: the 11 `VisualizerSettings` fields from Task 1.
- Produces: `makeStarNestUniforms(_ settings: VisualizerSettings) -> StarNestUniforms`, a pure function. `StarNestUniforms` holds the 9 scalars as `Float` and the 2 counts as `Int32`, clamped (`volsteps` 1...26, `iterations` 1...16), memory-layout-matched to the Metal struct.

- [ ] **Step 1: Write the failing tests**

```swift
func testStarNestUniformsDefaultParity() {
    let u = makeStarNestUniforms(VisualizerSettings())
    XCTAssertEqual(u.zoom, 0.78, accuracy: 1e-6)
    XCTAssertEqual(u.speed, 0.18, accuracy: 1e-6)
    XCTAssertEqual(u.formuparam, 0.53, accuracy: 1e-6)
    XCTAssertEqual(u.tile, 0.85, accuracy: 1e-6)
    XCTAssertEqual(u.stepsize, 0.105, accuracy: 1e-6)
    XCTAssertEqual(u.brightness, 0.00095, accuracy: 1e-6)
    XCTAssertEqual(u.darkmatter, 0.34, accuracy: 1e-6)
    XCTAssertEqual(u.distfading, 0.73, accuracy: 1e-6)
    XCTAssertEqual(u.saturation, 0.82, accuracy: 1e-6)
    XCTAssertEqual(u.volsteps, 18)
    XCTAssertEqual(u.iterations, 13)
}

func testStarNestUniformsDensityClamp() {
    var s = VisualizerSettings()
    s.starNestVolsteps = 999; s.starNestIterations = 999
    let hi = makeStarNestUniforms(s)
    XCTAssertEqual(hi.volsteps, 26)
    XCTAssertEqual(hi.iterations, 16)
    s.starNestVolsteps = -5; s.starNestIterations = 0
    let lo = makeStarNestUniforms(s)
    XCTAssertEqual(lo.volsteps, 1)
    XCTAssertEqual(lo.iterations, 1)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `USER=eespino LOGNAME=eespino make test`
Expected: FAIL — `makeStarNestUniforms` / `StarNestUniforms` undefined.

- [ ] **Step 3: Add the Swift uniform + builder**

In `MetalRenderer.swift`, locate the Voronoi or LavaLamp uniform struct + its `makeXUniforms(settings:)` builder and mirror it:

```swift
struct StarNestUniforms {
    var zoom: Float
    var speed: Float
    var formuparam: Float
    var tile: Float
    var stepsize: Float
    var brightness: Float
    var darkmatter: Float
    var distfading: Float
    var saturation: Float
    var volsteps: Int32
    var iterations: Int32
}

func makeStarNestUniforms(_ settings: VisualizerSettings) -> StarNestUniforms {
    StarNestUniforms(
        zoom: Float(settings.starNestZoom),
        speed: Float(settings.starNestSpeed),
        formuparam: Float(settings.starNestFormuparam),
        tile: Float(settings.starNestTile),
        stepsize: Float(settings.starNestStepsize),
        brightness: Float(settings.starNestBrightness),
        darkmatter: Float(settings.starNestDarkmatter),
        distfading: Float(settings.starNestDistfading),
        saturation: Float(settings.starNestSaturation),
        volsteps: Int32(min(26, max(1, settings.starNestVolsteps))),
        iterations: Int32(min(16, max(1, settings.starNestIterations)))
    )
}
```

(Match the access level of the existing Voronoi/LavaLamp builder so the test target can call it.)

- [ ] **Step 4: Run to verify the builder tests pass**

Run: `USER=eespino LOGNAME=eespino make test`
Expected: PASS for the two new tests.

- [ ] **Step 5: Add the matching Metal struct + bind at buffer 2**

In `Shaders.metal`, declare a `struct StarNestUniforms` with identical field order/types (`float` ×9, `int` ×2). Change the Star Nest fragment signature to take `constant StarNestUniforms &u [[buffer(2)]]`. In `MetalRenderer.encodeShaderFill`, in the `case .starNest` (or the kind switch), build `var u = makeStarNestUniforms(settings)` and `encoder.setFragmentBytes(&u, length: MemoryLayout<StarNestUniforms>.stride, index: 2)` — mirroring how Voronoi/LavaLamp set their buffer-2 bytes.

- [ ] **Step 6: Substitute literals in the shader (value-preserving)**

In the Star Nest fragment in `Shaders.metal`, replace each hardcoded base literal with the matching `u.<field>`, leaving the existing `+ audio·k` modulation terms untouched:
- `zoom` base → `u.zoom`; `time/speed` factor base → `u.speed`; `formuparam` → `u.formuparam`; `tile` → `u.tile`; `stepsize` → `u.stepsize`; `brightness` → `u.brightness`; `darkmatter` → `u.darkmatter`; `distfading` → `u.distfading`; `saturation` → `u.saturation`.
- Loop bounds: `for r in 0..<volsteps` → use `u.volsteps`; inner `iterations` loop → `u.iterations` (MSL needs a bounded loop; keep the existing literal cap as the loop's compile-time upper bound and `break` when the index reaches `u.volsteps`/`u.iterations`, OR loop directly to `u.volsteps`/`u.iterations` if the existing code already does a runtime-bounded loop — preserve whatever bounding construct is already there).

VERIFY value-preservation: with defaults, `u.<field>` equals the literal it replaced, so the compiled output is unchanged. Cross-check each replaced literal against the default in Task 1.

- [ ] **Step 7: Run gates**

Run: `USER=eespino LOGNAME=eespino make build && USER=eespino LOGNAME=eespino make test`
Expected: BUILD SUCCEEDED; all tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/Rendering/MetalRenderer.swift Sources/Rendering/Shaders.metal Tests
git commit -m "Add Star Nest shader-params uniform at buffer 2

Co-authored-by: omnigent <noreply@omnigent.ai>"
```

---

### Task 3: Settings UI controls

**Files:**
- Modify: `Sources/App/SettingsView.swift`

**Interfaces:**
- Consumes: the 11 `VisualizerSettings` fields (Task 1).

- [ ] **Step 1: Add the sliders**

In the active-aware controls switch, locate the Star Nest case (or add one to the same switch Polartone/Oscilloscope use). Add 9 scalar `Slider`s bound to `$model.settings.starNest*` with labels and ranges:
- Zoom 0.3...2.0, Speed 0.0...1.0, Formuparam 0.4...0.7, Tile 0.5...1.2, Stepsize 0.02...0.3, Brightness 0.0002...0.003, Darkmatter 0.0...1.0, Distfading 0.4...1.0, Saturation 0.0...1.0.

Then a quiet subheading `Text("Density (performance)")` followed by two integer sliders:
- Volsteps `1...26` (step 1), Iterations `1...16` (step 1), each bound to the `Int` field via a `Double`/`Int` bridge consistent with how any existing `Int` slider in this file is done (or `Stepper`s if the file uses those for ints).

Mirror the exact label/Slider styling already used for the `polartone*` controls in this file.

- [ ] **Step 2: Run gates**

Run: `USER=eespino LOGNAME=eespino make build && USER=eespino LOGNAME=eespino make test`
Expected: BUILD SUCCEEDED; all tests pass.

- [ ] **Step 3: Commit**

```bash
git add Sources/App/SettingsView.swift
git commit -m "Add Star Nest controls to Settings UI

Co-authored-by: omnigent <noreply@omnigent.ai>"
```

---

## Self-Review

- **Spec coverage:** Settings fields (Task 1), uniform plumbing + shader substitution + reactivity reconciliation (Task 2), UI incl. density subgroup (Task 3), all testing items (parity, clamp, Codable, migration) covered in Tasks 1–2. ✓
- **Placeholder scan:** none — all code/commands concrete; the only deliberate deferral is "match the existing bounding construct" in the shader loop, which is correct because the exact loop shape must be read from the current `Shaders.metal` rather than guessed. ✓
- **Type consistency:** `makeStarNestUniforms` / `StarNestUniforms` field names identical across Tasks 1–3; `Int` fields clamped to `Int32` in the builder; default values identical between Task 1 and the Task 2 parity test. ✓
