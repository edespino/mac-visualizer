# Bass-Reactive Starfield Implementation Plan (Phase 2, Plan 2 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new `particles` visualizer style — a bass-reactive starfield of drifting particles that pulse brighter/larger and surge outward on bass beats.

**Architecture:** A stateful `ParticleVisualizer` class conforming to the existing `Visualizer` protocol. It holds a deterministic (seeded) particle array, advances it each `makeVertices` call using a timestamp-derived `dt` and the bass energy from `AudioFrame.bands`, and emits each particle as a small aspect-corrected quad — so it rides the existing flat-triangle pipeline and the Plan 7 bloom makes the stars glow. The renderer's cached-visualizer slot keeps the instance (and its state) alive across frames. It is a fifth `VisualizerStyle` case, so the existing menu/keyboard/Settings switching includes it automatically.

**Tech Stack:** Swift 5.10, simd, XCTest. No new shaders, no rendering changes, no settings changes.

**Builds on:** the merged app, incl. Plan 7 bloom. Spec: `docs/superpowers/specs/2026-05-27-glow-and-particles-design.md` (§6).

**Scope boundary:** This completes Phase 2. No further particle behaviors (fountain/fireworks) — the architecture makes adding them later easy.

---

## File Structure

```
mac-visualizer/
  Sources/Core/
    ParticleVisualizer.swift     # CREATE: stateful starfield visualizer (+ a private seeded RNG)
    VisualizerStyle.swift        # MODIFY: add `.particles` case (factory + displayName)
  Tests/CoreTests/
    ParticleVisualizerTests.swift # CREATE
    VisualizerStyleTests.swift    # MODIFY: 5th case in allCases / next / previous + particles factory
```

No rendering/UI files change: `MetalView` already selects the visualizer by style and caches the instance (so particle state persists); the Visualizer menu, ⌘]/⌘[ cycling, and the Settings picker all iterate `VisualizerStyle.allCases`, so `.particles` appears automatically; bloom already applies to any rendered geometry.

---

## Task 1: `ParticleVisualizer` (stateful, deterministic)

**Files:**
- Create: `Sources/Core/ParticleVisualizer.swift`
- Test: `Tests/CoreTests/ParticleVisualizerTests.swift`

- [ ] **Step 1: Write the failing tests** — `Tests/CoreTests/ParticleVisualizerTests.swift`:

```swift
import XCTest
import simd
@testable import MacVisualizerCore

final class ParticleVisualizerTests: XCTestCase {
    private func frame(bands: [Float], t: TimeInterval) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: bands, waveform: [], rms: 0, peak: 0, timestamp: t)
    }
    private let loud = [Float](repeating: 1.0, count: 24)
    private let quiet = [Float](repeating: 0.0, count: 24)

    func testVertexCountIsSixPerParticle() {
        let v = ParticleVisualizer(count: 50).makeVertices(frame: frame(bands: quiet, t: 0),
                                                            settings: .defaults, aspect: 1)
        XCTAssertEqual(v.count, 50 * 6)
    }

    func testVerticesStayInClipSpace() {
        let viz = ParticleVisualizer(count: 200)
        var t = 0.0
        for _ in 0..<120 { // 2 seconds of loud bass surging particles outward
            let v = viz.makeVertices(frame: frame(bands: loud, t: t), settings: .defaults, aspect: 1.6)
            for vert in v {
                XCTAssertLessThanOrEqual(abs(vert.position.x), 1.25)
                XCTAssertLessThanOrEqual(abs(vert.position.y), 1.25)
            }
            t += 1.0 / 60.0
        }
    }

    func testDeterministicForSameSeedAndCalls() {
        let a = ParticleVisualizer(count: 64, seed: 12345)
        let b = ParticleVisualizer(count: 64, seed: 12345)
        var t = 0.0
        var lastA: [BarVertex] = [], lastB: [BarVertex] = []
        for _ in 0..<30 {
            lastA = a.makeVertices(frame: frame(bands: loud, t: t), settings: .defaults, aspect: 1)
            lastB = b.makeVertices(frame: frame(bands: loud, t: t), settings: .defaults, aspect: 1)
            t += 1.0 / 60.0
        }
        XCTAssertEqual(lastA, lastB)
    }

    func testBassRaisesTotalBrightnessVsSilence() {
        func totalBrightness(bands: [Float]) -> Float {
            let viz = ParticleVisualizer(count: 100, seed: 7)
            var t = 0.0
            var sum: Float = 0
            for _ in 0..<20 {
                let v = viz.makeVertices(frame: frame(bands: bands, t: t), settings: .defaults, aspect: 1)
                sum = v.reduce(0) { $0 + $1.color.x + $1.color.y + $1.color.z } // last frame's total
                t += 1.0 / 60.0
            }
            return sum
        }
        XCTAssertGreaterThan(totalBrightness(bands: loud), totalBrightness(bands: quiet))
    }
}
```

- [ ] **Step 2: Run `make test`** — expect FAIL (`cannot find 'ParticleVisualizer'`).

- [ ] **Step 3: Implement** — `Sources/Core/ParticleVisualizer.swift`:

```swift
import simd
import QuartzCore

/// Deterministic seeded PRNG (xorshift64) for reproducible particle layouts.
private struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func nextUnit() -> Float { // [0,1)
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Float(state >> 40) / Float(1 << 24)
    }
    mutating func nextSigned() -> Float { nextUnit() * 2 - 1 } // [-1,1)
}

/// A bass-reactive starfield: particles drift, decay toward a baseline, and on bass
/// beats pulse brighter/larger and surge outward; off-screen particles respawn near
/// center. Stateful — keep one instance alive across frames (the renderer caches it).
public final class ParticleVisualizer: Visualizer {
    private struct Particle {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var size: Float
        var brightness: Float
        var colorPos: Float
    }

    private let count: Int
    private var particles: [Particle]
    private var rng: SeededRNG
    private var lastTimestamp: CFTimeInterval = -1

    private let baseSize: Float = 0.012
    private let baseBrightness: Float = 0.45
    private let bassThreshold: Float = 0.5

    public init(count: Int = 200, seed: UInt64 = 0xC0FFEE) {
        self.count = count
        var r = SeededRNG(seed: seed)
        self.particles = (0..<count).map { i in
            Particle(position: SIMD2(r.nextSigned(), r.nextSigned()),
                     velocity: SIMD2(r.nextSigned() * 0.05, r.nextSigned() * 0.05),
                     size: 0.012,
                     brightness: 0.45 + 0.3 * r.nextUnit(),
                     colorPos: Float(i) / Float(max(count - 1, 1)))
        }
        self.rng = r
    }

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        var dt: Float = 0
        if lastTimestamp >= 0 {
            dt = Float(min(max(frame.timestamp - lastTimestamp, 0), 0.1))
        }
        lastTimestamp = frame.timestamp

        let bass = computeBass(frame)
        let palette = ColorPalette.preset(named: settings.paletteName) ?? ColorPalette.preset(named: "classic")!

        // Aspect-correct so dots are square on screen and stay inside clip space.
        var sx: Float = 1, sy: Float = 1
        if aspect >= 1 { sx = 1 / aspect } else { sy = aspect }

        var verts: [BarVertex] = []
        verts.reserveCapacity(count * 6)

        for i in 0..<count {
            var p = particles[i]
            p.position += p.velocity * dt
            p.velocity *= 0.985
            let lerp = min(dt * 3, 1)
            p.brightness += (baseBrightness - p.brightness) * lerp
            p.size += (baseSize - p.size) * lerp

            if bass > bassThreshold {
                let len = simd_length(p.position)
                let dir = len > 0.0001 ? p.position / len : SIMD2<Float>(0, 1)
                p.velocity += dir * (bass * 0.25)
                p.brightness = min(1, p.brightness + bass * 0.5)
                p.size = min(baseSize * 3, p.size + bass * baseSize * 1.5)
            }

            // Respawn before emitting, so emitted positions stay bounded.
            if abs(p.position.x) > 1.15 || abs(p.position.y) > 1.15 {
                p.position = SIMD2(rng.nextSigned() * 0.15, rng.nextSigned() * 0.15)
                p.velocity = SIMD2(rng.nextSigned() * 0.05, rng.nextSigned() * 0.05)
                p.brightness = baseBrightness
                p.size = baseSize
            }

            particles[i] = p

            let c = palette.sample(at: p.colorPos)
            let color = SIMD4<Float>(c.r * p.brightness, c.g * p.brightness, c.b * p.brightness, 1)
            let hx = p.size * sx, hy = p.size * sy
            let x0 = p.position.x - hx, x1 = p.position.x + hx
            let y0 = p.position.y - hy, y1 = p.position.y + hy
            let bl = BarVertex(position: SIMD4(x0, y0, 0, 1), color: color)
            let br = BarVertex(position: SIMD4(x1, y0, 0, 1), color: color)
            let tl = BarVertex(position: SIMD4(x0, y1, 0, 1), color: color)
            let tr = BarVertex(position: SIMD4(x1, y1, 0, 1), color: color)
            verts.append(contentsOf: [bl, br, tl, br, tr, tl])
        }
        return verts
    }

    private func computeBass(_ frame: AudioFrame) -> Float {
        guard !frame.bands.isEmpty else { return frame.rms }
        let n = max(1, frame.bands.count * 15 / 100)
        var sum: Float = 0
        for i in 0..<n { sum += frame.bands[i] }
        return sum / Float(n)
    }
}
```

- [ ] **Step 4: Run `make test`** — expect `** TEST SUCCEEDED **`, the 4 `ParticleVisualizerTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/ParticleVisualizer.swift Tests/CoreTests/ParticleVisualizerTests.swift
git commit -m "Add ParticleVisualizer bass-reactive starfield"
```

---

## Task 2: Add `.particles` to `VisualizerStyle`

**Files:**
- Modify: `Sources/Core/VisualizerStyle.swift`
- Modify: `Tests/CoreTests/VisualizerStyleTests.swift`

- [ ] **Step 1: Update the tests.** In `Tests/CoreTests/VisualizerStyleTests.swift`:
  - Replace `testAllCases` body with:
    ```swift
        XCTAssertEqual(VisualizerStyle.allCases, [.bars, .radial, .mirrored, .oscilloscope, .particles])
    ```
  - Replace `testNextWrapsAround` body with:
    ```swift
        XCTAssertEqual(VisualizerStyle.bars.next, .radial)
        XCTAssertEqual(VisualizerStyle.oscilloscope.next, .particles)
        XCTAssertEqual(VisualizerStyle.particles.next, .bars)
    ```
  - Replace `testPreviousWrapsAround` body with:
    ```swift
        XCTAssertEqual(VisualizerStyle.radial.previous, .bars)
        XCTAssertEqual(VisualizerStyle.bars.previous, .particles)
        XCTAssertEqual(VisualizerStyle.particles.previous, .oscilloscope)
    ```
  - Add a new test:
    ```swift
    func testParticlesFactory() {
        XCTAssertTrue(VisualizerStyle.particles.makeVisualizer() is ParticleVisualizer)
        XCTAssertFalse(VisualizerStyle.particles.displayName.isEmpty)
    }
    ```
  (Leave `testDisplayNamesNonEmpty` and `testFactoryMatchesConcreteVisualizer` — which checks the 4 stateless styles — unchanged.)

- [ ] **Step 2: Run `make test`** — expect FAIL (`.particles` doesn't exist; allCases mismatch).

- [ ] **Step 3: Add the case.** In `Sources/Core/VisualizerStyle.swift`:
  - Add `particles` to the case list: `case bars, radial, mirrored, oscilloscope, particles`.
  - In `displayName`, add `case .particles: return "Particles"`.
  - In `makeVisualizer()`, add `case .particles: return ParticleVisualizer()`.
  (`next`/`previous` use `allCases` and need no change; `CaseIterable` includes `.particles` in declaration order, so it lands last — matching the test.)

- [ ] **Step 4: Run `make test`** — expect `** TEST SUCCEEDED **`. Updated `VisualizerStyleTests` + new `testParticlesFactory` pass; the unchanged 4-style factory test still passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/VisualizerStyle.swift Tests/CoreTests/VisualizerStyleTests.swift
git commit -m "Add particles to VisualizerStyle"
```

---

## Task 3: Verify particles render (probe + live)

**Files:** none (verification only). The Visualizer menu, ⌘]/⌘[ cycling, and the Settings picker already include `.particles` because they iterate `VisualizerStyle.allCases`; the renderer already selects and caches it; bloom already applies.

- [ ] **Step 1: Build** — `make build` → `** BUILD SUCCEEDED **`. `make test` → `** TEST SUCCEEDED **`.

- [ ] **Step 2: Probe-render particles (a static first-frame snapshot), with and without glow, and INSPECT.**
```bash
BIN=./DerivedData/Build/Products/Debug/MacVisualizer.app/Contents/MacOS/MacVisualizer
$BIN --render-probe /tmp/particles.png particles && echo plain=$?
$BIN --render-probe /tmp/particles_glow.png particles glow && echo glow=$?
```
Use the Read tool on both. Expected: `particles.png` = a scatter of small colored dots spread across the dark canvas (the seeded initial layout; the probe renders one frame so it's a static snapshot, no motion). `particles_glow.png` = the same dots but each softly glowing (bloom halos). Confirm dots are present and roughly fill the frame (not all clustered in one spot, not empty). If empty/all-black or all dots in one corner, report it (DONE_WITH_CONCERNS) with the image.
(Note: the probe shows a single frame, so motion/bass-reactivity is NOT visible here — that's the live check.)

- [ ] **Step 3: Live verification (requires the user)** — `make run` with music playing. Press ⌘] to cycle to **Particles** (or pick it in the Visualizer menu / Settings). Expected: a field of glowing particles that **drift**, and on **bass beats** pulse brighter/larger and surge outward (then settle/respawn) — a starfield breathing to the music. Glow (on by default) makes them luminous. Confirm it reacts to bass and the motion looks good; tune is acceptable to adjust later.
  - The agent should build, run both probes (Step 2), confirm launch (`make run` then check `pgrep -x MacVisualizer`), and report that live bass-reactivity confirmation is pending the user. Do NOT claim the live motion/bass-reactivity works from the static probe alone.

- [ ] **Step 4: Commit** (only if Step 2/build produced any incidental change; otherwise nothing to commit — this is a verification task). If there is nothing to commit, state that and skip. If a tuning tweak was needed and applied to `ParticleVisualizer.swift`, commit it:
```bash
git add -A
git commit -m "Verify particles render; tune starfield motion"
```

---

## Definition of Done (Plan 8 — Particles)

- `make test` → `** TEST SUCCEEDED **` with the new `ParticleVisualizerTests` (4) + updated `VisualizerStyleTests` green (~96 total).
- `make build` → `** BUILD SUCCEEDED **`.
- `--render-probe /tmp/p.png particles` (and `... particles glow`) shows a scattered (glowing) starfield.
- `make run`: a "Particles" style is selectable via ⌘]/⌘[, the Visualizer menu, and the Settings picker; it shows a glowing starfield that drifts and reacts to bass. Confirmed by the user.

## Phase 2 complete

With this, Phase 2 (glow/bloom + particle field) is done. The visualizer now offers five styles (bars, radial, mirrored, oscilloscope, particles), all with optional neon bloom. Possible future polish (all independent, none required): more particle behaviors (fountain/fireworks) as new styles; caching the per-frame `MPSImageGaussianBlur`; reduced-resolution blur for perf; the long-standing deferrals (custom palette colors, background gradient, per-monitor fullscreen).

## Notes on verification

The particle *logic* is deterministic and unit-tested (vertex count, clip bounds under sustained surging, reproducibility for a fixed seed, and bass-raises-brightness). The static probe PNG confirms particles render (and glow); the live motion + bass reactivity is confirmed by the user (it cannot be asserted from a single frame). Motion constants (drag, surge impulse, thresholds) are tuned for a reasonable default and may be adjusted live.
