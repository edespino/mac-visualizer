# Palette Auto-Cycle + New Palettes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in global palette auto-cycle (shuffle deck, configurable interval + crossfade) and six new predefined palettes, with zero visual change when the feature is off.

**Architecture:** A pure, deterministic `PaletteCycleEngine` (Core) owns the deck/countdown/fade and is advanced once per frame on the draw path. A pure palette `blend(a,b,t)` produces a single effective palette at the existing palette-uniform build site, so all 15 styles (CPU + shader) consume one already-blended palette unchanged. Three new global `VisualizerSettings` fields drive it; the new palettes are appended to the existing preset registry.

**Tech Stack:** Swift 5.10, XCTest, macOS/Metal app built via `make` (XcodeGen + xcodebuild). Tests live in `Tests/CoreTests`.

## Global Constraints

- **Build/test:** `USER=eespino LOGNAME=eespino make build` and `USER=eespino LOGNAME=eespino make test` must both pass (the worker shell needs `USER`/`LOGNAME` set for `xcodegen`).
- **Value preservation:** with `paletteCycleEnabled == false` (the default), every existing render path must be **bit-identical** to pre-feature behavior for the same `paletteName`. This is the controlling invariant; if a step can't satisfy it, STOP and report.
- **No fabrication:** the exact `ColorPalette` representation, the preset registry, `orderedPresetNames`, and the palette-uniform build site are NOT guessed — read the real code first (Task 0) and define everything against what is actually there.
- **Additive only:** do not modify or reorder the existing 8 presets (`classic, phosphor, synthwave, inferno, aurora, ember, ice, mono`).
- **Finite-guard:** numeric settings reads use the established `finiteOr(default)`-then-clamp pattern (NaN/inf can't poison timer math).
- **Commit trailer:** every commit ends with `Co-authored-by: omnigent <noreply@omnigent.ai>`.
- **Threading:** the cycle engine is advanced on the main/draw path only — never the audio IO thread.

---

## Task 0: Orientation (no code) — read the real palette internals

**Files:**
- Read: `Sources/Core/ColorPalette.swift` (or wherever `ColorPalette`, the 8 presets, and `orderedPresetNames` live)
- Read: the palette-uniform build site (grep for `PaletteUniform` / where `paletteName` → bound palette per frame)
- Read: `Sources/Core/VisualizerSettings.swift` (`paletteName` forwarding, "apply to all styles" path, manual palette-cycle shortcut)
- Read: the render model draw/update seam (where per-frame `dt`/elapsed time exists)

- [ ] **Step 1: Record the palette representation**

Write down (in the task's working notes / PR description, not a code file): the exact stored shape of a `ColorPalette` (stop array? fixed N colors? component type — `SIMD3<Float>`/`Float` tuple?), the function that resolves a name → palette, the `orderedPresetNames` definition, and the exact build site that turns the active palette into the bound uniform each frame. All later tasks reference these real names/types.

- [ ] **Step 2: Confirm the manual palette-write-to-all-styles path**

Identify the existing code the manual "apply to all styles" / palette-cycle shortcut uses to write a palette name into every `StyleProfile`. Task 5 reuses it verbatim — record its signature.

No commit (read-only orientation).

---

## Task 1: Six new predefined palettes

**Files:**
- Modify: `Sources/Core/ColorPalette.swift` (the real file from Task 0)
- Test: `Tests/CoreTests/ColorPaletteNewPresetsTests.swift` (create)

**Interfaces:**
- Consumes: the real palette literal format + `orderedPresetNames` (Task 0).
- Produces: 6 new resolvable names — `viridis`, `plasma`, `spectrum`, `pastel`, `forest`, `oceanic` — appended to `orderedPresetNames` after `mono`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MacVisualizerCore

final class ColorPaletteNewPresetsTests: XCTestCase {
    private let originalEight = ["classic","phosphor","synthwave","inferno","aurora","ember","ice","mono"]
    private let newSix = ["viridis","plasma","spectrum","pastel","forest","oceanic"]

    func testOriginalEightUnchangedAndFirst() {
        // The original presets must remain the first 8 entries, in order.
        XCTAssertEqual(Array(ColorPalette.orderedPresetNames.prefix(8)), originalEight)
    }

    func testAllFourteenResolve() {
        XCTAssertEqual(ColorPalette.orderedPresetNames.count, 14)
        for name in originalEight + newSix {
            // Use the real resolver discovered in Task 0; replace `ColorPalette.named(_:)`
            // with the actual API if different.
            XCTAssertNotNil(ColorPalette.named(name), "\(name) must resolve")
        }
    }

    func testNewPalettesNonDegenerate() {
        for name in newSix {
            let p = ColorPalette.named(name)!
            // Replace `.colors` with the real stop accessor from Task 0.
            let comps = p.colors
            XCTAssertGreaterThanOrEqual(comps.count, 2, "\(name) needs >=2 stops")
            // not all-identical stops (avoid a flat/degenerate palette)
            XCTAssertFalse(comps.dropFirst().allSatisfy { $0 == comps.first }, "\(name) is degenerate")
        }
    }
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `USER=eespino LOGNAME=eespino make test 2>&1 | grep -A3 NewPresets`
Expected: FAIL (count is 8, new names don't resolve).

- [ ] **Step 3: Define the six palettes in the real format**

In `ColorPalette.swift`, add six presets matching the existing literal format (same stop count/structure the other presets use — discovered in Task 0). Target hues (tune to the existing stop count; values are guidance, not authoritative — match the file's conventions):
- `viridis`: dark indigo `#440154` → blue `#3b528b` → teal `#21918c` → green `#5ec962` → yellow `#fde725`
- `plasma`: indigo `#0d0887` → magenta `#cc4778` → orange `#f89540` → gold `#f0f921`
- `spectrum`: red `#ff0000` → yellow `#ffff00` → green `#00ff00` → cyan `#00ffff` → blue `#0000ff` → violet `#ff00ff`
- `pastel`: rose `#ffb3ba` → peach `#ffdfba` → mint `#baffc9` → periwinkle `#bae1ff`
- `forest`: deep moss `#1b3a1b` → fir `#2e5d34` → leaf `#6aa84f` → bark `#7a5230`
- `oceanic`: navy `#012038` → deep teal `#024d5c` → aqua `#2bc4c9`

Append the six names to `orderedPresetNames` **after** `mono` (do not touch the first 8).

- [ ] **Step 4: Run tests, verify pass**

Run: `USER=eespino LOGNAME=eespino make test 2>&1 | tail -5`
Expected: PASS (14 names, originals first-8 unchanged, new ones non-degenerate).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/ColorPalette.swift Tests/CoreTests/ColorPaletteNewPresetsTests.swift
git commit -m "Add six predefined palettes (viridis, plasma, spectrum, pastel, forest, oceanic)

Co-authored-by: omnigent <noreply@omnigent.ai>"
```

---

## Task 2: Three global cycle settings fields

**Files:**
- Modify: `Sources/Core/VisualizerSettings.swift`
- Test: `Tests/CoreTests/PaletteCycleSettingsTests.swift` (create)

**Interfaces:**
- Produces: `settings.paletteCycleEnabled: Bool` (default `false`), `settings.paletteCycleInterval: Double` (default `60`), `settings.paletteCycleFadeDuration: Double` (default `1.5`) — flat top-level, tolerant Codable, Equatable.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MacVisualizerCore

final class PaletteCycleSettingsTests: XCTestCase {
    func testDefaultsFeatureOff() {
        let d = VisualizerSettings.defaults
        XCTAssertFalse(d.paletteCycleEnabled)
        XCTAssertEqual(d.paletteCycleInterval, 60, accuracy: 0)
        XCTAssertEqual(d.paletteCycleFadeDuration, 1.5, accuracy: 0)
    }

    func testRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.paletteCycleEnabled = true
        s.paletteCycleInterval = 30
        s.paletteCycleFadeDuration = 2.0
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(back, s)
    }

    func testLegacyJSONDecodesToFeatureOff() throws {
        // A settings JSON with none of the new keys must decode to the defaults (feature off).
        let legacy = "{}".data(using: .utf8)!
        let s = try JSONDecoder().decode(VisualizerSettings.self, from: legacy)
        XCTAssertFalse(s.paletteCycleEnabled)
        XCTAssertEqual(s.paletteCycleInterval, 60, accuracy: 0)
        XCTAssertEqual(s.paletteCycleFadeDuration, 1.5, accuracy: 0)
    }
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `USER=eespino LOGNAME=eespino make test 2>&1 | grep -A3 PaletteCycleSettings`
Expected: FAIL (members don't exist).

- [ ] **Step 3: Add the three fields**

In `VisualizerSettings.swift`, mirror the existing flat-field convention EXACTLY (declaration, init parameter with default, value in `VisualizerSettings.defaults`, `CodingKeys`, `decodeIfPresent ?? default`, `encode`, and inclusion in synthesized/explicit `Equatable`):

```swift
public var paletteCycleEnabled: Bool          // default false
public var paletteCycleInterval: Double        // default 60
public var paletteCycleFadeDuration: Double    // default 1.5
```

Decode: `paletteCycleEnabled = try c.decodeIfPresent(Bool.self, forKey: .paletteCycleEnabled) ?? false`, etc. (If the type uses memberwise init + a custom decoder like the other flat fields, follow that same shape.)

- [ ] **Step 4: Run tests, verify pass**

Run: `USER=eespino LOGNAME=eespino make test 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/VisualizerSettings.swift Tests/CoreTests/PaletteCycleSettingsTests.swift
git commit -m "Add global palette-cycle settings (enabled, interval, fade duration)

Co-authored-by: omnigent <noreply@omnigent.ai>"
```

---

## Task 3: Pure palette crossfade blend + value-preservation golden

**Files:**
- Modify: `Sources/Core/ColorPalette.swift`
- Test: `Tests/CoreTests/ColorPaletteBlendTests.swift` (create)

**Interfaces:**
- Produces: `static func blend(_ a: ColorPalette, _ b: ColorPalette, _ t: Double) -> ColorPalette` — component-wise lerp of the real stop representation; `t` clamped to `0...1`; `t==0` ⇒ `a` exactly, `t==1` ⇒ `b` exactly. (Adjust the value type to whatever Task 0 found — same idea.)

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MacVisualizerCore

final class ColorPaletteBlendTests: XCTestCase {
    func testEndpointsExact() {
        let a = ColorPalette.named("classic")!
        let b = ColorPalette.named("inferno")!
        XCTAssertEqual(ColorPalette.blend(a, b, 0).colors, a.colors)
        XCTAssertEqual(ColorPalette.blend(a, b, 1).colors, b.colors)
    }

    func testSelfBlendIsIdentity() {
        let a = ColorPalette.named("aurora")!
        XCTAssertEqual(ColorPalette.blend(a, a, 0.5).colors, a.colors)
    }

    func testMidpointIsComponentwiseMean() {
        let a = ColorPalette.named("ice")!
        let b = ColorPalette.named("ember")!
        let mid = ColorPalette.blend(a, b, 0.5).colors
        for i in mid.indices {
            // Replace `.x/.y/.z` with the real component accessors from Task 0.
            XCTAssertEqual(mid[i].x, (a.colors[i].x + b.colors[i].x) / 2, accuracy: 1e-6)
        }
    }

    func testClampsOutOfRangeT() {
        let a = ColorPalette.named("classic")!
        let b = ColorPalette.named("mono")!
        XCTAssertEqual(ColorPalette.blend(a, b, -5).colors, a.colors)
        XCTAssertEqual(ColorPalette.blend(a, b, 5).colors, b.colors)
    }
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `USER=eespino LOGNAME=eespino make test 2>&1 | grep -A3 ColorPaletteBlend`
Expected: FAIL (`blend` undefined).

- [ ] **Step 3: Implement `blend`**

Add a pure component-wise lerp over the real stop array (all presets share the same stop count by construction, so index-wise lerp is well-defined). Clamp `t` to `0...1`. At `t==0`/`t==1` return the endpoint stops unchanged (use an exact branch so endpoints are bit-exact, not float-rounded):

```swift
public static func blend(_ a: ColorPalette, _ b: ColorPalette, _ t: Double) -> ColorPalette {
    let tt = min(max(t, 0), 1)
    if tt == 0 { return a }
    if tt == 1 { return b }
    let f = Float(tt)
    let mixed = zip(a.colors, b.colors).map { ca, cb in ca + (cb - ca) * f } // adapt to real component type
    return ColorPalette(/* same initializer the presets use */, colors: mixed)
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `USER=eespino LOGNAME=eespino make test 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/ColorPalette.swift Tests/CoreTests/ColorPaletteBlendTests.swift
git commit -m "Add pure palette crossfade blend (component-wise lerp, exact endpoints)

Co-authored-by: omnigent <noreply@omnigent.ai>"
```

---

## Task 4: Deterministic PaletteCycleEngine

**Files:**
- Create: `Sources/Core/PaletteCycleEngine.swift`
- Test: `Tests/CoreTests/PaletteCycleEngineTests.swift` (create)

**Interfaces:**
- Produces:
```swift
public struct PaletteCycleOutput: Equatable {
    public var currentName: String
    public var nextName: String?
    public var mix: Double           // 0..1
    public var committedName: String?
}
public final class PaletteCycleEngine {
    public init()
    public func advance(dt: Double, enabled: Bool, interval: Double, fadeDuration: Double,
                        currentPaletteName: String, availableNames: [String],
                        rng: inout some RandomNumberGenerator) -> PaletteCycleOutput
}
```

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MacVisualizerCore

private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(_ s: UInt64) { state = s }
    mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
}

final class PaletteCycleEngineTests: XCTestCase {
    let names = ["classic","phosphor","synthwave","inferno","aurora","ember","ice","mono",
                 "viridis","plasma","spectrum","pastel","forest","oceanic"]

    func testDisabledIsPassthrough() {
        let e = PaletteCycleEngine(); var rng = SeededRNG(1)
        let o = e.advance(dt: 100, enabled: false, interval: 60, fadeDuration: 1.5,
                          currentPaletteName: "classic", availableNames: names, rng: &rng)
        XCTAssertEqual(o, PaletteCycleOutput(currentName: "classic", nextName: nil, mix: 0, committedName: nil))
    }

    func testNoAdvanceBeforeInterval() {
        let e = PaletteCycleEngine(); var rng = SeededRNG(1)
        var o = e.advance(dt: 0, enabled: true, interval: 60, fadeDuration: 1.5,
                          currentPaletteName: "classic", availableNames: names, rng: &rng)
        for _ in 0..<59 { o = e.advance(dt: 1, enabled: true, interval: 60, fadeDuration: 1.5,
                          currentPaletteName: "classic", availableNames: names, rng: &rng) }
        XCTAssertNil(o.nextName); XCTAssertEqual(o.mix, 0, accuracy: 0)
    }

    func testFadeRampThenCommitOnce() {
        let e = PaletteCycleEngine(); var rng = SeededRNG(1)
        func step(_ dt: Double) -> PaletteCycleOutput {
            e.advance(dt: dt, enabled: true, interval: 10, fadeDuration: 2,
                      currentPaletteName: "classic", availableNames: names, rng: &rng)
        }
        _ = step(0)
        _ = step(10)                 // hit interval → fade begins
        let mid = step(1)            // 1s into a 2s fade
        XCTAssertNotNil(mid.nextName); XCTAssertEqual(mid.mix, 0.5, accuracy: 1e-6)
        XCTAssertNil(mid.committedName)
        let done = step(1)           // fade completes
        XCTAssertEqual(done.mix, 1, accuracy: 0)
        XCTAssertEqual(done.committedName, mid.nextName)
        let after = step(0.001)      // commit fires exactly once
        XCTAssertNil(after.committedName)
        XCTAssertNil(after.nextName)
    }

    func testDeckExhaustsAllBeforeRepeatNoSeam() {
        let e = PaletteCycleEngine(); var rng = SeededRNG(42)
        var committed: [String] = []
        var current = "classic"
        var t = 0.0
        // advance through 2 full decks worth of commits
        while committed.count < names.count * 2 {
            let o = e.advance(dt: 0.5, enabled: true, interval: 1, fadeDuration: 0.5,
                              currentPaletteName: current, availableNames: names, rng: &rng)
            t += 0.5
            if let c = o.committedName { committed.append(c); current = c }
        }
        let firstDeck = Set(committed.prefix(names.count - 1)) // current excluded from its own deck draw
        XCTAssertEqual(firstDeck.count, committed.prefix(names.count - 1).count, "no repeat within a deck")
        // no immediate repeat at any commit boundary
        for i in 1..<committed.count { XCTAssertNotEqual(committed[i], committed[i-1], "no seam repeat") }
    }

    func testManualChangeReanchors() {
        let e = PaletteCycleEngine(); var rng = SeededRNG(7)
        _ = e.advance(dt: 0, enabled: true, interval: 60, fadeDuration: 1.5,
                      currentPaletteName: "classic", availableNames: names, rng: &rng)
        for _ in 0..<50 { _ = e.advance(dt: 1, enabled: true, interval: 60, fadeDuration: 1.5,
                      currentPaletteName: "classic", availableNames: names, rng: &rng) }
        // user picks "ember" at t≈50s → countdown must restart, no immediate fade
        let o = e.advance(dt: 1, enabled: true, interval: 60, fadeDuration: 1.5,
                      currentPaletteName: "ember", availableNames: names, rng: &rng)
        XCTAssertEqual(o.currentName, "ember"); XCTAssertNil(o.nextName); XCTAssertEqual(o.mix, 0, accuracy: 0)
        // and it should NOT fire again at the old schedule (would need another full interval)
        var last = o
        for _ in 0..<58 { last = e.advance(dt: 1, enabled: true, interval: 60, fadeDuration: 1.5,
                      currentPaletteName: "ember", availableNames: names, rng: &rng) }
        XCTAssertNil(last.nextName, "must wait a full interval from the manual pick")
    }

    func testNaNInfSanitized() {
        let e = PaletteCycleEngine(); var rng = SeededRNG(1)
        let o = e.advance(dt: .nan, enabled: true, interval: .infinity, fadeDuration: .nan,
                          currentPaletteName: "classic", availableNames: names, rng: &rng)
        XCTAssertEqual(o.mix, 0, accuracy: 0)   // no crash, no poison
        XCTAssertNil(o.nextName)
    }
}
```

- [ ] **Step 2: Run them, verify they fail**

Run: `USER=eespino LOGNAME=eespino make test 2>&1 | grep -A3 PaletteCycleEngine`
Expected: FAIL (type undefined).

- [ ] **Step 3: Implement the engine**

Create `PaletteCycleEngine.swift`. Internal state: `deck: [String]` (remaining names this deck), `trackedCurrent: String?`, `elapsed: Double` (countdown), `fadeElapsed: Double?` (nil = not fading), `nextName: String?`, `lastCommittedSeam: String?` (last palette of the previous deck, to forbid a seam repeat).

Logic per `advance`:
1. Sanitize: `let dt = finiteOr(dt, 0).clamped(0, 1)` (reuse the project's finite helper; clamp dt to ≤1s to avoid huge jumps); `interval = max(finiteOr(interval, 60), 0.1)`; `fade = max(finiteOr(fadeDuration, 1.5), 0.01)`; `effFade = min(fade, interval)`.
2. If `!enabled`: reset `elapsed=0, fadeElapsed=nil, nextName=nil`, set `trackedCurrent = currentPaletteName`, return passthrough `(currentPaletteName, nil, 0, nil)`.
3. **Manual-change detection:** if `trackedCurrent != nil && trackedCurrent != currentPaletteName`: re-anchor — `trackedCurrent = currentPaletteName; elapsed = 0; fadeElapsed = nil; nextName = nil`; ensure `currentPaletteName` is removed from the current `deck` so it isn't the immediate next draw. Return passthrough this frame.
4. If `trackedCurrent == nil`: initialize `trackedCurrent = currentPaletteName`.
5. **Fading?** if `fadeElapsed != nil`: `fadeElapsed! += dt`; `mix = min(fadeElapsed!/effFade, 1)`. If `mix >= 1`: commit — `let committed = nextName!; trackedCurrent = committed; nextName = nil; fadeElapsed = nil; elapsed = 0`; return `(committed, nil, 1, committed)`. Else return `(trackedCurrent!, nextName, mix, nil)`.
6. **Counting down:** `elapsed += dt`. If `elapsed >= interval`: draw next from deck (refill+reshuffle via injected `rng` when empty, forbidding `lastCommittedSeam` as the first draw and excluding `trackedCurrent`), set `nextName`, `fadeElapsed = 0`, return `(trackedCurrent!, nextName, 0, nil)`. Else return passthrough `(trackedCurrent!, nil, 0, nil)`.

Deck refill: when `deck` empty, set `deck = availableNames.shuffled(using: &rng)`; if `deck.first == lastCommittedSeam` (or `== trackedCurrent`), rotate/reshuffle until the first element differs. On each draw, set `lastCommittedSeam` when the deck empties.

Add a small `finiteOr` if Core doesn't already expose one (the Particles work added the pattern — reuse it).

- [ ] **Step 4: Run tests, verify pass**

Run: `USER=eespino LOGNAME=eespino make test 2>&1 | tail -5`
Expected: PASS (all engine tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/PaletteCycleEngine.swift Tests/CoreTests/PaletteCycleEngineTests.swift
git commit -m "Add deterministic PaletteCycleEngine (shuffle deck, interval, fade)

Co-authored-by: omnigent <noreply@omnigent.ai>"
```

---

## Task 5: Wire engine + blend into the render model; add Settings UI

**Files:**
- Modify: the render model file from Task 0 (per-frame palette resolution + `dt`)
- Modify: the palette-uniform build site from Task 0
- Modify: `Sources/App/SettingsView.swift`
- Test: `Tests/CoreTests/PaletteUniformParityTests.swift` (create) — value-preservation golden

**Interfaces:**
- Consumes: `PaletteCycleEngine`, `PaletteCycleOutput`, `ColorPalette.blend`, the three settings fields, the existing write-to-all-styles path (Task 0 Step 2).

- [ ] **Step 1: Write the failing value-preservation test**

```swift
import XCTest
@testable import MacVisualizerCore

final class PaletteUniformParityTests: XCTestCase {
    // With the feature OFF, the engine output must be a pure passthrough, so the
    // bound palette equals the named palette exactly for all original presets.
    func testFeatureOffPassthroughForOriginalEight() {
        let e = PaletteCycleEngine(); var rng = SystemRandomNumberGenerator()
        for name in ["classic","phosphor","synthwave","inferno","aurora","ember","ice","mono"] {
            let o = e.advance(dt: 0.016, enabled: false, interval: 60, fadeDuration: 1.5,
                              currentPaletteName: name, availableNames: ColorPalette.orderedPresetNames, rng: &rng)
            XCTAssertEqual(o.currentName, name)
            XCTAssertNil(o.nextName)
            XCTAssertEqual(o.mix, 0, accuracy: 0)
            // The build site uses currentName + (nextName,mix); with mix==0 it must bind `name` verbatim.
            let bound = ColorPalette.named(o.currentName)!
            XCTAssertEqual(bound.colors, ColorPalette.named(name)!.colors)
        }
    }
}
```

- [ ] **Step 2: Run it, verify it fails (or compiles-but-guides)**

Run: `USER=eespino LOGNAME=eespino make test 2>&1 | grep -A3 PaletteUniformParity`
Expected: FAIL until the engine is referenced from the model build (or PASS only once wiring compiles). Treat a compile error here as the RED.

- [ ] **Step 3: Hold one `PaletteCycleEngine` on the render model**

Add a stored `private let paletteCycleEngine = PaletteCycleEngine()` to the render model. Do NOT advance it on the audio thread.

- [ ] **Step 4: Advance the engine each frame and build the blended palette**

At the per-frame draw/update seam (where `dt`/elapsed exists), before the palette uniform is built:

```swift
var rng = SystemRandomNumberGenerator()
let cyc = paletteCycleEngine.advance(
    dt: frameDeltaSeconds,
    enabled: settings.paletteCycleEnabled,
    interval: settings.paletteCycleInterval,
    fadeDuration: settings.paletteCycleFadeDuration,
    currentPaletteName: settings.paletteName,
    availableNames: ColorPalette.orderedPresetNames,
    rng: &rng)

let effectivePalette: ColorPalette
if let next = cyc.nextName, cyc.mix > 0 {
    effectivePalette = ColorPalette.blend(ColorPalette.named(cyc.currentName) ?? .fallback,
                                          ColorPalette.named(next) ?? .fallback,
                                          cyc.mix)
} else {
    effectivePalette = ColorPalette.named(cyc.currentName) ?? .fallback
}
// Build the bound PaletteUniform from `effectivePalette` (replace the prior `named(settings.paletteName)`).

if let committed = cyc.committedName {
    // reuse the EXACT write-to-all-styles path from Task 0 Step 2
    applyPaletteToAllStyles(committed)   // <- real method name from Task 0
}
```

Use a stored RNG on the model if you prefer reproducibility; a per-frame `SystemRandomNumberGenerator` is fine since shuffle only happens at deck refill.

- [ ] **Step 5: Run the parity test + full suite, verify pass**

Run: `USER=eespino LOGNAME=eespino make test 2>&1 | tail -5`
Expected: PASS (feature-off path binds the named palette verbatim).

- [ ] **Step 6: Add the Settings UI group**

In `SettingsView.swift`, under the global **Appearance** section, add a **"Palette Cycle"** group:

```swift
Section("Palette Cycle") {
    Toggle("Auto-cycle palettes", isOn: $model.settings.paletteCycleEnabled)
    if model.settings.paletteCycleEnabled {
        HStack { Text("Interval"); Slider(value: $model.settings.paletteCycleInterval, in: 5...600); Text("\(Int(model.settings.paletteCycleInterval))s") }
        HStack { Text("Fade"); Slider(value: $model.settings.paletteCycleFadeDuration, in: 0.1...10); Text(String(format: "%.1fs", model.settings.paletteCycleFadeDuration)) }
    }
}
```

(Match the surrounding section's exact styling/binding idiom — `$model.settings...` vs a local binding — discovered in Task 0.)

- [ ] **Step 7: Build + full test + manual-sanity note**

Run: `USER=eespino LOGNAME=eespino make build && USER=eespino LOGNAME=eespino make test 2>&1 | tail -5`
Expected: BUILD SUCCEEDED, all tests pass.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Wire palette auto-cycle into render model + Settings UI

Co-authored-by: omnigent <noreply@omnigent.ai>"
```

---

## Self-Review (completed)

- **Spec coverage:** Component 1 → Task 1; Component 2 → Task 2; Component 3 → Task 3; Component 4 → Task 4; Component 5 → Task 5; Grounding → Task 0. All covered.
- **Placeholders:** the `ColorPalette.named`/`.colors`/`.x` accessors and the `applyPaletteToAllStyles` name are explicitly flagged as "replace with the real API from Task 0" — these are deliberate no-fabrication anchors (the real names are read, not invented), not placeholders. All test/impl bodies are concrete.
- **Type consistency:** `PaletteCycleOutput` fields (`currentName/nextName/mix/committedName`) and `advance(...)` signature are identical across Tasks 4 and 5; `blend(_:_:_:)` signature consistent across Tasks 3 and 5.
- **Value preservation:** guarded by Task 5 Step 1 (feature-off passthrough) + Task 3 exact endpoints.
