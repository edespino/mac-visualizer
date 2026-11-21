# Wireframe Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose the Wireframe visualizer's hardcoded constants as user-tunable settings (6 scalars + mesh-resolution), defaults preserving the current look exactly.

**Architecture:** Wireframe is a CPU vertex-emit style (`WireframeVisualizer.makeVertices`), not a Metal shader — so settings flow directly into `makeVertices`, the Polartone pattern. No `MetalRenderer`/`Shaders.metal`/buffer-uniform changes. New fields are flat top-level `VisualizerSettings` fields (Polartone/Star Nest precedent), surfaced in the active-aware `controls(for:)` Settings section, and covered by per-style Reset.

**Tech Stack:** Swift 5.10, XCTest, XcodeGen + Makefile (`USER=eespino LOGNAME=eespino make build` / `make test`).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-06-28-wireframe-controls-design.md`.
- All work in worktree `.worktrees/wireframe-controls`, branch `polly/wireframe-controls`. Do NOT push, do NOT open a PR; commit to the branch only.
- Every new `VisualizerSettings` field defaults to the exact current literal so default output is byte-identical to today.
- Codable for new fields MUST be tolerant: `decodeIfPresent(...) ?? default` (a persisted/legacy JSON missing the key → default; a present value wins).
- Locate patterns by name, not line number (line numbers below are explore-time references on `main` @ `92f7c57` and may drift). Mirror the existing `polartone*` / `starNest*` flat-field treatment EXACTLY in every method they appear (declaration, init param, `defaults`, CodingKeys, decode, encode, Equatable if hand-written, `resetCurrentStyle()`).
- No fabrication: if a referenced symbol/pattern differs from this plan, mirror the real code and note the deviation in the result.
- Gates before "done": `USER=eespino LOGNAME=eespino make build` (BUILD SUCCEEDED) and `USER=eespino LOGNAME=eespino make test` (0 failures); report the test count.
- Commit after each task with `Co-authored-by: omnigent <noreply@omnigent.ai>` trailer (use `git -c user.name="omnigent" -c user.email="noreply@omnigent.ai"`).

The fields (verbatim from the spec):

| Field | Type | Default | Range | Replaces literal |
|---|---|---|---|---|
| `wireframeBaseRadius` | Double | 0.50 | 0.2–1.0 | `baseRadius` |
| `wireframeDisplaceScale` | Double | 0.20 | 0.0–0.6 | `displaceScale` |
| `wireframeLineThickness` | Double | 0.003 | 0.001–0.02 | `edgeHalfThickness` (half-thickness) |
| `wireframeRotationSpeed` | Double | 0.5 | −2.0…2.0 | `rotationSpeed` |
| `wireframeTiltX` | Double | 0.3 | −π…π | `tiltX` |
| `wireframeLineOpacity` | Double | 1.0 | 0.0–1.0 | hardcoded alpha `1` |
| `wireframeSubdivisions` | Int | 2 | 0–4 (clamped) | `icosphere(subdivisions: 2)` |

---

### Task 1: Settings fields + Codable + Reset

**Files:**
- Modify: `Sources/Core/VisualizerSettings.swift` (declarations; `defaults`; CodingKeys; decode w/ tolerance + subdivisions clamp; encode; `resetCurrentStyle()`; Equatable if hand-written)
- Test: `Tests/CoreTests/VisualizerSettingsTests.swift`

**Interfaces:**
- Produces: 7 stored properties on `VisualizerSettings` named exactly as the table above, readable as `settings.wireframe*`. `wireframeSubdivisions` is an `Int` clamped to `0...4` on decode.

- [ ] **Step 1: Write failing tests.** In `VisualizerSettingsTests.swift` add:

```swift
func testWireframeDefaultsMatchLiterals() {
    let d = VisualizerSettings.defaults
    XCTAssertEqual(d.wireframeBaseRadius, 0.50, accuracy: 1e-9)
    XCTAssertEqual(d.wireframeDisplaceScale, 0.20, accuracy: 1e-9)
    XCTAssertEqual(d.wireframeLineThickness, 0.003, accuracy: 1e-9)
    XCTAssertEqual(d.wireframeRotationSpeed, 0.5, accuracy: 1e-9)
    XCTAssertEqual(d.wireframeTiltX, 0.3, accuracy: 1e-9)
    XCTAssertEqual(d.wireframeLineOpacity, 1.0, accuracy: 1e-9)
    XCTAssertEqual(d.wireframeSubdivisions, 2)
}

func testWireframeFieldsRoundTrip() throws {
    var s = VisualizerSettings.defaults
    s.wireframeBaseRadius = 0.7
    s.wireframeDisplaceScale = 0.4
    s.wireframeLineThickness = 0.01
    s.wireframeRotationSpeed = -1.0
    s.wireframeTiltX = 0.9
    s.wireframeLineOpacity = 0.5
    s.wireframeSubdivisions = 3
    let data = try JSONEncoder().encode(s)
    let back = try JSONDecoder().decode(VisualizerSettings.self, from: data)
    XCTAssertEqual(back, s)
}

func testWireframeTolerantDecodeUsesDefaultsWhenMissing() throws {
    // Legacy JSON without wireframe keys decodes to defaults (mirror existing
    // tolerant-decode test fixture in this file).
    let json = "{ \"gain\": 1.0 }".data(using: .utf8)!
    let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
    XCTAssertEqual(decoded.wireframeBaseRadius, 0.50, accuracy: 1e-9)
    XCTAssertEqual(decoded.wireframeSubdivisions, 2)
}

func testWireframeSubdivisionsClampOnDecode() throws {
    // Out-of-range persisted values clamp to 0...4 (mirror Star Nest density clamp test).
    let high = "{ \"wireframeSubdivisions\": 99 }".data(using: .utf8)!
    XCTAssertEqual(try JSONDecoder().decode(VisualizerSettings.self, from: high).wireframeSubdivisions, 4)
    let low = "{ \"wireframeSubdivisions\": -5 }".data(using: .utf8)!
    XCTAssertEqual(try JSONDecoder().decode(VisualizerSettings.self, from: low).wireframeSubdivisions, 0)
}
```

- [ ] **Step 2: Run, verify FAIL.** `USER=eespino LOGNAME=eespino make test` → fails (members don't exist). If it fails to *compile*, that counts as RED; proceed.

- [ ] **Step 3: Implement.** Add the 7 fields mirroring the `polartone*` fields' treatment in EACH location. Concretely:
  - Stored property declarations (with the `starNest*`/`polartone*` group).
  - `init` parameters with the table defaults.
  - Entries in `VisualizerSettings.defaults`.
  - `CodingKeys` cases.
  - In `init(from:)`: `wireframeBaseRadius = try c.decodeIfPresent(Double.self, forKey: .wireframeBaseRadius) ?? Self.defaults.wireframeBaseRadius` (and same shape for each). For subdivisions, decode then clamp:
    ```swift
    let rawSubdiv = try c.decodeIfPresent(Int.self, forKey: .wireframeSubdivisions) ?? Self.defaults.wireframeSubdivisions
    wireframeSubdivisions = min(max(rawSubdiv, 0), 4)
    ```
  - In `encode(to:)`: encode all 7.
  - If `Equatable` is hand-written (not synthesized), add all 7 to `==`. (If synthesized, nothing to do — verify which.)

- [ ] **Step 4: Run, verify PASS.** `USER=eespino LOGNAME=eespino make test` → the 4 new tests pass.

- [ ] **Step 5: Reset coverage — failing test.** Add:

```swift
func testResetCurrentStyleResetsWireframeFields() {
    var s = VisualizerSettings.defaults
    s.visualizerStyle = .wireframe
    s.wireframeBaseRadius = 0.9
    s.wireframeSubdivisions = 4
    s.wireframeLineOpacity = 0.2
    s.resetCurrentStyle()
    XCTAssertEqual(s.wireframeBaseRadius, 0.50, accuracy: 1e-9)
    XCTAssertEqual(s.wireframeSubdivisions, 2)
    XCTAssertEqual(s.wireframeLineOpacity, 1.0, accuracy: 1e-9)
}
```

- [ ] **Step 6: Run, verify FAIL** (no `.wireframe` branch yet).

- [ ] **Step 7: Implement reset.** In `resetCurrentStyle()` add a `case .wireframe:` (mirroring the existing `.polartone` / `.starNest` branches) that resets all 7 fields to `Self.defaults.*`. Do NOT touch shared fields or other styles.

- [ ] **Step 8: Run, verify PASS.** Full `make test` green.

- [ ] **Step 9: Commit.**
```bash
git add Sources/Core/VisualizerSettings.swift Tests/CoreTests/VisualizerSettingsTests.swift
git -c user.name="omnigent" -c user.email="noreply@omnigent.ai" commit -m "Add Wireframe settings fields, tolerant Codable, and reset coverage

Co-authored-by: omnigent <noreply@omnigent.ai>"
```

---

### Task 2: WireframeVisualizer reads the settings

**Files:**
- Modify: `Sources/Core/WireframeVisualizer.swift`
- Test: `Tests/CoreTests/WireframeVisualizerTests.swift`

**Interfaces:**
- Consumes: the 7 `settings.wireframe*` fields from Task 1.
- Produces: `makeVertices(frame:settings:aspect:)` whose geometry is driven by those fields; at default settings, output is identical to today.

- [ ] **Step 1: Default-parity failing test (the critical regression guard).** Before changing the visualizer, capture today's behavior. Add a test that builds the vertex array at `VisualizerSettings.defaults` for a fixed synthetic frame and asserts a stable property of the output (e.g. exact vertex count = edges×6, and the first/last vertex positions within `1e-6`). Because the substitution must be value-preserving, this test is written to pass BOTH before and after — run it on the unchanged code first to record the golden values, then keep it as the guard. Example:

```swift
func testWireframeDefaultOutputUnchanged() {
    let v = WireframeVisualizer()
    let frame = AudioFrame.silent(bandCount: VisualizerSettings.defaults.barCount) // mirror existing test fixture
    let out = v.makeVertices(frame: frame, settings: .defaults, aspect: 1.5)
    XCTAssertEqual(out.count, 480 * 6) // subdivisions 2 → 480 edges (see WireframeMeshTests)
    // pin a couple of deterministic coordinates captured from current output:
    // (fill from the recorded golden run in Step 2)
}
```
(Use the existing `WireframeVisualizerTests` fixture/helpers for frame construction; match how the current count/clip-space tests build their input.)

- [ ] **Step 2: Record golden values.** Run the parity test against the UNCHANGED visualizer; read the actual emitted count and a couple of coordinate values from the failure/log; fill them into the assertions so the test passes on current code. Commit nothing yet.

- [ ] **Step 3: Per-field behavior failing tests.** Add:

```swift
func testWireframeSubdivisionsChangeEdgeCount() {
    let v = WireframeVisualizer()
    let frame = AudioFrame.silent(bandCount: VisualizerSettings.defaults.barCount)
    var s0 = VisualizerSettings.defaults; s0.wireframeSubdivisions = 1
    var s3 = VisualizerSettings.defaults; s3.wireframeSubdivisions = 3
    let c0 = v.makeVertices(frame: frame, settings: s0, aspect: 1.5).count
    let c3 = v.makeVertices(frame: frame, settings: s3, aspect: 1.5).count
    XCTAssertGreaterThan(c3, c0)
}

func testWireframeLineOpacityFlowsToAlpha() {
    let v = WireframeVisualizer()
    let frame = AudioFrame.silent(bandCount: VisualizerSettings.defaults.barCount)
    var s = VisualizerSettings.defaults; s.wireframeLineOpacity = 0.3
    let out = v.makeVertices(frame: frame, settings: s, aspect: 1.5)
    // every emitted vertex color alpha ≈ 0.3 (match the BarVertex/color field name in this codebase)
    XCTAssertTrue(out.allSatisfy { abs($0.color.w - 0.3) < 1e-5 })
}

func testWireframeSubdivisionsClampedAtUseSite() {
    let v = WireframeVisualizer()
    let frame = AudioFrame.silent(bandCount: VisualizerSettings.defaults.barCount)
    var s = VisualizerSettings.defaults; s.wireframeSubdivisions = 4
    // does not crash / produces a bounded, non-empty mesh
    XCTAssertFalse(v.makeVertices(frame: frame, settings: s, aspect: 1.5).isEmpty)
}
```
(Adjust `$0.color.w` to the actual vertex color accessor — find the existing color/alpha field name in the vertex struct and the existing Wireframe color test, and mirror it. Do NOT guess the accessor; read it.)

- [ ] **Step 4: Run, verify the per-field tests FAIL** (visualizer still uses literals; subdivisions/opacity not wired).

- [ ] **Step 5: Implement.** In `makeVertices`, replace each local constant with the setting:
  - `baseRadius` → `settings.wireframeBaseRadius`
  - `displaceScale` → `settings.wireframeDisplaceScale`
  - `edgeHalfThickness` → `settings.wireframeLineThickness`
  - `rotationSpeed` → `settings.wireframeRotationSpeed`
  - `tiltX` → `settings.wireframeTiltX`
  - per-vertex color alpha `1` → `Float(settings.wireframeLineOpacity)`
  - `WireframeMesh.icosphere(subdivisions: 2)` → `WireframeMesh.icosphere(subdivisions: min(max(settings.wireframeSubdivisions, 0), 4))`

  **Mesh build:** the icosphere is currently built once (a stored constant). Since the level is now settings-driven, change `WireframeVisualizer` to a class (if it is a struct) OR cache keyed on the resolved subdivision level, rebuilding only when the level changes — whichever fits the existing structure with the least churn. Build per-call is acceptable for correctness if a level-keyed cache is awkward, but avoid rebuilding a level-4 mesh every frame where a one-line cache (store last level + mesh) is natural. If converting struct→class: verify nothing relies on value-copy semantics of `WireframeVisualizer` (grep usages in `Sources/` and the factory in `VisualizerStyle.swift`), and that `makeVertices` stays correct under reuse. Note the chosen approach in the result.

  Leave unchanged: the `dt` clamp (0.1), azimuth band-mapping, orthographic projection, aspect correction, degenerate-segment threshold.

- [ ] **Step 6: Run, verify ALL PASS** — the per-field tests pass AND the default-parity test still passes (proves value-preserving substitution).

- [ ] **Step 7: Commit.**
```bash
git add Sources/Core/WireframeVisualizer.swift Tests/CoreTests/WireframeVisualizerTests.swift
git -c user.name="omnigent" -c user.email="noreply@omnigent.ai" commit -m "Drive Wireframe geometry from settings (defaults preserve current look)

Co-authored-by: omnigent <noreply@omnigent.ai>"
```

---

### Task 3: Settings UI controls

**Files:**
- Modify: `Sources/App/SettingsView.swift`

**Interfaces:**
- Consumes: the 7 `settings.wireframe*` fields; the existing active-aware `controls(for:)` switch and the `polartoneControls` / `starNestControls` view precedent.

- [ ] **Step 1: Implement the UI.** Add `case .wireframe:` to `controls(for:)` returning a new `wireframeControls` view. Bind directly to `$model.settings.wireframe*` (top-level binding, NOT `bind(_:)` — match how `polartoneControls`/`starNestControls` bind their top-level fields). Layout, mirroring the existing per-style control sections:
  - Sliders: Base Radius (0.2–1.0), Audio Displacement (0.0–0.6), Line Thickness (0.001–0.02), Rotation Speed (−2…2), X Tilt (−π…π), Line Opacity (0.0–1.0).
  - A `Text("Detail (performance)")` subheading, then a control for `wireframeSubdivisions` over 0…4 (a `Stepper` or integer `Slider` — mirror any existing integer control such as Star Nest's density / `polartonePointCount`), with a short caption that higher levels cost more CPU per frame (level 4 ≈ 16× edges).

  This view has no business logic to unit-test; correctness is the binding wiring + that it compiles. Add a `#Preview`/DEBUG preview only if the file's other per-style sections have them (match the file's convention).

- [ ] **Step 2: Build.** `USER=eespino LOGNAME=eespino make build` → BUILD SUCCEEDED. `USER=eespino LOGNAME=eespino make test` → still 0 failures.

- [ ] **Step 3: Commit.**
```bash
git add Sources/App/SettingsView.swift
git -c user.name="omnigent" -c user.email="noreply@omnigent.ai" commit -m "Add Wireframe controls to active-aware Settings section

Co-authored-by: omnigent <noreply@omnigent.ai>"
```

---

## Final gate (before reporting done)

- [ ] `USER=eespino LOGNAME=eespino make build` → BUILD SUCCEEDED.
- [ ] `USER=eespino LOGNAME=eespino make test` → 0 failures; report the count (expect ~+11 over the pre-task baseline).
- [ ] Confirm only these files changed: `Sources/Core/VisualizerSettings.swift`, `Sources/Core/WireframeVisualizer.swift`, `Sources/App/SettingsView.swift`, and the two test files (+ the spec/plan docs already committed). No `MetalRenderer`/`Shaders.metal`/other-style changes.
- [ ] Report: files changed, commit SHAs, the mesh-build approach chosen (struct→class vs cache), and any deviation from this plan.
