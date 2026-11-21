# Lyric Shadow Beat Bounce Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The active lyric line's drop shadow snaps on each musical beat and eases back, driven by a dedicated adaptive onset follower that fires reliably at the user's ~0.02 capture level, without touching any visualizer's beat behavior.

**Architecture:** A new pre-gain `AudioFrame.bassEnergy` (fixed-Hz FFT window) feeds a new unit-tested `LyricBeatFollower` (Core) that emits a normalized once-per-beat pulse. `RenderModel` runs the follower on its dsp queue and publishes pulses to `LyricsOverlay`, which modulates only the active line's shadow. Mode + strength become real `LyricsSettings` fields.

**Tech Stack:** Swift 5.10, vDSP FFT, Combine, SwiftUI, XCTest. XcodeGen + Makefile (`make build` / `make test`).

**Spec:** `docs/superpowers/specs/2026-11-17-lyric-beat-bounce-design.md`

## Global Constraints

- Every new `.swift` file in `Sources/` and `Tests/` starts with the 16-line Apache 2.0 header, blank line, then imports. (CLAUDE.md)
- Build/test only via `make build` / `make test`. Never invoke `xcodebuild`.
- Only `Sources/Core` is unit-tested. `Sources/App` tasks are verified by `make build` succeeding + `make test` (Core suite) staying green + **live visual validation** (`verify-visualizer-changes` skill) — the SwiftUI overlay is not captured by the render probe.
- Settings use tolerant Codable: every new field decodes via `decodeIfPresent(...) ?? d.<field>`; old `settings.json` must load unchanged.
- Do **not** modify `BeatDetector` or anything the 24 visualizers consume. `AudioFrame.beat`/`beatIntensity` stay as they are.
- `bassEnergy` is computed from a fixed Hz window off the raw FFT magnitudes — independent of `barCount`, band mapping, and per-style gain.
- The follower is fed only from the **real capture path** (`capture.onSamples`); demo/synthetic frames never drive the bounce.
- Lyrics settings are app-wide (`settings.lyrics`), not per-style.
- Commits attributed to the user; no AI attribution.

## Review Focus

- **Paused/silent track must not pulse.** A silent capture (epsilon-level energy) must yield zero pulses — covered by a `LyricBeatFollower` silence test (Task 2).
- **Sustained-loud passage must settle, not strobe.** The adaptive baseline must stop firing on a held-loud input after it adapts — covered by a baseline-adaptation test (Task 2).
- **Fast tempo must not drop beats.** At ~400 ms spacing (150 BPM) each beat must still fire exactly once — covered by a refractory test at that spacing (Task 2).
- **Band settings must not move the trigger.** `bassEnergy` must be unchanged across `barCount` values and when the mapper is in `.notes` mode — covered by an independence test (Task 1).
- **Legacy settings.json.** A JSON missing `beatBounceMode`/`beatBounceStrength` must decode to `both` / `1.0` — covered by a legacy-decode test (Task 3).

---

### Task 1: `bassEnergy` on `AudioFrame` + `SpectrumAnalyzer`

**Files:**
- Modify: `Sources/Core/AudioFrame.swift` (add field + both inits)
- Modify: `Sources/Core/SpectrumAnalyzer.swift:157-204` (compute + pass through)
- Test: `Tests/CoreTests/SpectrumAnalyzerTests.swift`

**Interfaces:**
- Produces: `AudioFrame.bassEnergy: Float` — mean raw-FFT magnitude over ~30–150 Hz, `>= 0`, pre-gain.

- [ ] **Step 1: Write the failing tests**

In `SpectrumAnalyzerTests.swift`, following the existing synthetic-signal helpers in that file:
```swift
func testBassEnergyHigherForLowFrequencyInput() {
    // A ~60 Hz tone yields a larger bassEnergy than a ~4 kHz tone of equal amplitude.
}
func testBassEnergyIndependentOfBandMappingAndBarCount() {
    // Same samples → same bassEnergy whether the analyzer is log-spaced or
    // .notes(...) mapped, and at barCount 16 vs 128 (setBandMapping / reconfigure).
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `make test` (or the Core scheme filtered to `SpectrumAnalyzerTests`)
Expected: FAIL — `bassEnergy` is not a member of `AudioFrame`.

- [ ] **Step 3: Add the field to `AudioFrame`**

Add `public var bassEnergy: Float` after `beatIntensity`. Add `bassEnergy: Float = 0` (defaulted) to **both** inits and assign it, so the existing ~34 construction sites keep compiling and synthesized `Equatable` just gains a field.

- [ ] **Step 4: Compute it in `SpectrumAnalyzer.append`**

After `magsL`/`magsR` are computed (`:161-162`): convert 30 Hz and 150 Hz to bin indices via `fftSize` and the current sample rate (`loBin = max(1, Int(30 * Float(fftSize) / sampleRate))`, `hiBin = Int(150 * Float(fftSize) / sampleRate)`, excluding DC bin 0), take the mean magnitude across `loBin...hiBin` for L and R, average the two. Pass it into the `AudioFrame(...)` init at `:191`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `make test`
Expected: PASS (both new tests; full suite green).

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/AudioFrame.swift Sources/Core/SpectrumAnalyzer.swift Tests/CoreTests/SpectrumAnalyzerTests.swift
git commit -m "Add pre-gain bassEnergy to AudioFrame for the lyric beat follower"
```

---

### Task 2: `LyricBeatFollower` (adaptive, floor-free onset)

**Files:**
- Create: `Sources/Core/LyricBeatFollower.swift`
- Test: `Tests/CoreTests/LyricBeatFollowerTests.swift`

**Interfaces:**
- Consumes: `AudioFrame.bassEnergy` (Task 1).
- Produces: a value type (or final class — builder's call; `BeatDetector` is the reference) with
  `mutating func update(bassEnergy: Float, timestamp: CFTimeInterval) -> Float`,
  returning the pulse in `0...1` (`0` = no onset this frame), plus `reset()`.

- [ ] **Step 1: Write the failing tests**

In `LyricBeatFollowerTests.swift` (license header, `@testable import MacVisualizerCore`), model a frame stream by calling `update` at ~60 fps timestamps:
```swift
func testFiresOnRisingBassAtLowLevel()        // step 0.005→0.03 fires (>0); level a 0.05-floor detector ignores
func testDoesNotFireOnFlatInput()             // constant 0.03 → never fires after warmup
func testDoesNotFireOnSilence()               // constant ~0 (below epsilon) → never fires
func testRefractoryAllowsOnePulsePerBeat()    // pulses 400 ms apart each fire once; a 2nd spike 80 ms later is suppressed
func testIntensityScalesWithRise()            // a bigger jump returns a larger pulse (both clamped ≤1)
func testBaselineAdaptsOnSustainedLoud()      // held-loud input stops firing once the baseline catches up
```

- [ ] **Step 2: Run to verify they fail**

Run: `make test`
Expected: FAIL — `LyricBeatFollower` undefined.

- [ ] **Step 3: Implement `LyricBeatFollower`**

Maintain an EMA baseline of `bassEnergy` and a measure of recent variability; fire when the instantaneous value's rise over the baseline clears an adaptive multiple of that variability **and** energy is increasing, with pulse intensity proportional to the normalized rise (clamped `0...1`). Gate out silence with a small absolute epsilon far below 0.05. Enforce a refractory window (~250–400 ms) so at most one pulse fires per beat. No absolute onset floor. Starting constants are the builder's, tuned so `testFiresOnRisingBassAtLowLevel` passes at ≈0.02–0.03.

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: PASS (all six; full suite green).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/LyricBeatFollower.swift Tests/CoreTests/LyricBeatFollowerTests.swift
git commit -m "Add LyricBeatFollower: adaptive floor-free once-per-beat onset detection"
```

---

### Task 3: `LyricBounceMode` + `LyricsSettings` fields

**Files:**
- Modify: `Sources/Core/LyricsSettings.swift` (enum near `LyricsPastMode:21`; fields, defaults, init, CodingKeys, decode, encode)
- Test: `Tests/CoreTests/LyricsSettingsTests.swift`

**Interfaces:**
- Produces: `LyricsSettings.beatBounceMode: LyricBounceMode`, `LyricsSettings.beatBounceStrength: Float`; `public enum LyricBounceMode: String, Codable, Equatable, CaseIterable { case off, lift, glow, both }`.

- [ ] **Step 1: Write the failing tests**
```swift
func testBeatBounceFieldsRoundTrip()          // encode→decode preserves mode=.lift, strength=2.0
func testLegacyJSONWithoutBeatBounceDefaults() // JSON lacking both keys decodes to .both / 1.0
```

- [ ] **Step 2: Run to verify they fail**

Run: `make test`
Expected: FAIL — members `beatBounceMode` / `beatBounceStrength` undefined.

- [ ] **Step 3: Implement the enum + fields**

Add `LyricBounceMode` beside `LyricsPastMode`. Add the two `public var`s, their `defaults` values (`.both`, `1.0`), init params + assignments, `CodingKeys`, and `decodeIfPresent ?? d.<field>` / `encode` lines — mirroring the existing shadow fields.

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: PASS (both; full suite green).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/LyricsSettings.swift Tests/CoreTests/LyricsSettingsTests.swift
git commit -m "Add beatBounceMode and beatBounceStrength to LyricsSettings"
```

---

### Task 4: Wire the follower into `RenderModel`; rename publisher; remove spike artifacts

**Files:**
- Modify: `Sources/App/RenderModel.swift:33,104-120` (own a `LyricBeatFollower`; feed `bassEnergy` on the dsp queue; publish pulses; remove the `Log.settings.notice` line and the `frame.beat` spike path)
- Modify: `Sources/App/MacVisualizerApp.swift:266` (rename in `ContentView`)

**Interfaces:**
- Consumes: `LyricBeatFollower` (Task 2), `AudioFrame.bassEnergy` (Task 1).
- Produces: `RenderModel.lyricPulse: PassthroughSubject<Float, Never>` (renamed from `beatPulse`).

- [ ] **Step 1: Rename and rewire**

Rename `beatPulse` → `lyricPulse`. In the dsp closure, after `box.store(...)`, call the follower with `frame.bassEnergy` and `CACurrentMediaTime()`; on a non-zero pulse `DispatchQueue.main.async { self?.lyricPulse.send(pulse) }`. Delete the `if frame.beat { … }` spike block and its `Log.settings.notice`. The follower instance is dsp-queue-confined (declared on `RenderModel`, only touched inside the dsp closure). Update the `ContentView` call site to `lyricPulse`.

- [ ] **Step 2: Build and run the Core suite**

Run: `make build && make test`
Expected: BUILD SUCCEEDED; Core suite green (App is not unit-tested — this task's gate is a clean build + unchanged Core suite, per Global Constraints). Defer the on-screen check to Task 5's visual validation, once the UI is bound.

- [ ] **Step 3: Commit**

```bash
git add Sources/App/RenderModel.swift Sources/App/MacVisualizerApp.swift
git commit -m "Drive the lyric bounce from LyricBeatFollower instead of the shared beat detector"
```

---

### Task 5: Overlay + Settings UI rewire; visual validation

**Files:**
- Modify: `Sources/App/LyricsOverlay.swift` (rename param `beatPulse`→`lyricPulse`; replace `@AppStorage("spikeBounce*")` with reads of `settings.beatBounceMode` / `settings.beatBounceStrength`; keep the deferred-decay snap envelope, decay tuned with the follower's refractory so it never pins)
- Modify: `Sources/App/LyricsSettingsSection.swift` (bind the picker + slider to `settings.lyrics`; remove the `@AppStorage` vars; drop the "(spike)" labels; place after the Drop-shadow group and disable when `!settings.shadowEnabled`; add help text noting it needs the shadow on and reacts to live audio, not Demo Mode)

**Interfaces:**
- Consumes: `LyricsSettings.beatBounceMode` / `beatBounceStrength` (Task 3); `RenderModel.lyricPulse` (Task 4).

- [ ] **Step 1: Rewire the overlay to settings**

Replace the two `@AppStorage` properties in `LyricPairRow`/`LyricsOverlay` with values threaded from `settings`. Keep the `bounceActive`/`liftOn`/`glowOn`/`shadow*Now` computed props (active line only). Rename the `beatPulse` publisher param to `lyricPulse`.

- [ ] **Step 2: Rewire the Settings section**

Bind `Picker("Beat bounce", selection: $settings.beatBounceMode)` (Off/Lift/Glow/Both) and `Slider($settings.beatBounceStrength, in: 0.2...3)` to `settings.lyrics`; delete the `@AppStorage` vars; add `.disabled(!settings.shadowEnabled)` and `.help(...)`.

- [ ] **Step 3: Build**

Run: `make build && make test`
Expected: BUILD SUCCEEDED; Core suite green.

- [ ] **Step 4: Visual validation (part of "done")**

Launch via the `run`/verify flow. With lyrics on, drop shadow on, and a song playing, confirm on **both a quiet and a loud track**: the active line's shadow snaps on the beat and eases back (no pinning), the text/columns never jitter, Off/Lift/Glow/Both and the strength slider behave, and a **paused** track produces no pulse. Switching styles (incl. Musical Spectrum) and `barCount` does not change whether it bounces. Per `verify-visualizer-changes`, this manual pass is required before the task is complete.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/LyricsOverlay.swift Sources/App/LyricsSettingsSection.swift
git commit -m "Bind lyric beat bounce to real settings; remove spike @AppStorage hacks"
```
