# Fountain + Fireworks Particle Styles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two new music-reactive `VisualizerStyle` cases — a per-band **spectrum fountain** and a **bass-beat fireworks** burst visualizer.

**Architecture:** Each new style is its own stateful `Visualizer` conformer (`SpectrumFountainVisualizer`, `FireworksVisualizer`) following the `ParticleVisualizer` pattern — a fixed-size ring-buffer particle pool advanced by `dt` derived from `AudioFrame.timestamp`, with a seeded `SeededRNG` for deterministic tests. Both ride the existing flat-triangle pipeline and the Plan 7 bloom. Adding `.fountain` and `.fireworks` to `VisualizerStyle.allCases` makes the menu, ⌘]/⌘[, and Settings picker include them automatically — no rendering/UI/Settings code changes.

**Tech Stack:** Swift 5.10, simd, XCTest. No new shaders or pipeline changes.

**Builds on:** the merged app, incl. Phase 2 (bloom + particles). Spec: `docs/superpowers/specs/2026-05-28-fountain-fireworks-design.md`.

---

## File Structure

```
mac-visualizer/
  Sources/Core/
    SpectrumFountainVisualizer.swift   # CREATE: per-band spawn + gravity (stateful)
    FireworksVisualizer.swift          # CREATE: rising-edge bass beat → random burst (stateful)
    VisualizerStyle.swift              # MODIFY: add .fountain + .fireworks cases
  Sources/Rendering/
    RenderProbe.swift                  # MODIFY: 3-call warm-up for fountain/fireworks so PNGs show real state
  Tests/CoreTests/
    SpectrumFountainVisualizerTests.swift # CREATE
    FireworksVisualizerTests.swift        # CREATE
    VisualizerStyleTests.swift            # MODIFY: 7-case allCases / next / prev + factory assertions
```

No `MetalView`, `SettingsView`, or `MacVisualizerApp` changes needed — the existing switching iterates `allCases`, the renderer caches the visualizer (stateful instances persist), and bloom applies automatically.

Each new visualizer keeps its own private `SeededRNG` struct in its own file (~10 lines of duplication; YAGNI vs. extracting a shared internal type).

---

## Task 1: `SpectrumFountainVisualizer`

**Files:**
- Create: `Sources/Core/SpectrumFountainVisualizer.swift`
- Test: `Tests/CoreTests/SpectrumFountainVisualizerTests.swift`

Per-band columns spawn upward-moving particles at `y = −1`; gravity pulls them down; they fade and die over `lifetime`. Particle positions are stored in clip space; aspect correction is applied only to the emitted quad half-extents (matches `ParticleVisualizer`).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import simd
@testable import MacVisualizerCore

final class SpectrumFountainVisualizerTests: XCTestCase {
    private func frame(bands: [Float], t: TimeInterval) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: bands, waveform: [], rms: 0, peak: 0, timestamp: t)
    }
    private let loud = [Float](repeating: 1.0, count: 24)
    private let quiet = [Float](repeating: 0.0, count: 24)

    func testVertexCountIsMultipleOfSixAndBounded() {
        let viz = SpectrumFountainVisualizer(maxParticles: 100)
        var t = 0.0
        for _ in 0..<60 {
            let v = viz.makeVertices(frame: frame(bands: loud, t: t), settings: .defaults, aspect: 1)
            XCTAssertEqual(v.count % 6, 0)
            XCTAssertLessThanOrEqual(v.count, 100 * 6)
            t += 1.0 / 60.0
        }
    }

    func testVerticesStayInClipSpace() {
        let viz = SpectrumFountainVisualizer(maxParticles: 200)
        var t = 0.0
        for _ in 0..<120 {
            let v = viz.makeVertices(frame: frame(bands: loud, t: t), settings: .defaults, aspect: 1.6)
            for vert in v {
                XCTAssertLessThanOrEqual(abs(vert.position.x), 1.25)
                XCTAssertLessThanOrEqual(abs(vert.position.y), 1.25)
            }
            t += 1.0 / 60.0
        }
    }

    func testDeterministicForSameSeedAndCalls() {
        let a = SpectrumFountainVisualizer(maxParticles: 64, seed: 42)
        let b = SpectrumFountainVisualizer(maxParticles: 64, seed: 42)
        var t = 0.0
        var lastA: [BarVertex] = [], lastB: [BarVertex] = []
        for _ in 0..<30 {
            lastA = a.makeVertices(frame: frame(bands: loud, t: t), settings: .defaults, aspect: 1)
            lastB = b.makeVertices(frame: frame(bands: loud, t: t), settings: .defaults, aspect: 1)
            t += 1.0 / 60.0
        }
        XCTAssertEqual(lastA, lastB)
    }

    func testLoudProducesMoreActiveParticlesThanSilent() {
        func activeAfterRun(bands: [Float]) -> Int {
            let viz = SpectrumFountainVisualizer(maxParticles: 200, seed: 7)
            var t = 0.0
            var last: [BarVertex] = []
            for _ in 0..<30 {
                last = viz.makeVertices(frame: frame(bands: bands, t: t), settings: .defaults, aspect: 1)
                t += 1.0 / 60.0
            }
            return last.count / 6
        }
        XCTAssertGreaterThan(activeAfterRun(bands: loud), activeAfterRun(bands: quiet))
    }
}
```

- [ ] **Step 2: Run `make test`** — expect FAIL (`cannot find 'SpectrumFountainVisualizer' in scope`).

- [ ] **Step 3: Write `Sources/Core/SpectrumFountainVisualizer.swift`**:

```swift
import simd
import QuartzCore

private struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func nextUnit() -> Float {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Float(state >> 40) / Float(1 << 24)
    }
    mutating func nextSigned() -> Float { nextUnit() * 2 - 1 }
}

/// A per-band fountain: each frequency band is a column along the bottom; the band's
/// level drives the spawn rate and launch velocity of particles in that column.
/// Gravity pulls particles back down; they fade and die over `lifetime`.
/// Stateful — keep one instance alive across frames (the renderer caches it).
public final class SpectrumFountainVisualizer: Visualizer {
    private struct Particle {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var age: Float
        var lifetime: Float
        var colorPos: Float
    }

    private let maxParticles: Int
    private var particles: [Particle]
    private var nextIndex: Int = 0
    private var rng: SeededRNG
    private var lastTimestamp: CFTimeInterval = -1

    private let spawnRate: Float = 15        // particles/sec/(unit level)/band
    private let spawnFloor: Float = 0.15
    private let baseUp: Float = 0.55
    private let launchScale: Float = 0.9
    private let gravity: Float = 1.4
    private let horizontalJitter: Float = 0.04
    private let horizontalDrag: Float = 0.99
    private let baseLifetime: Float = 2.0
    private let baseSize: Float = 0.008

    public init(maxParticles: Int = 600, seed: UInt64 = 0xFEEDFACE) {
        self.maxParticles = maxParticles
        // All particles start dead (age > lifetime).
        self.particles = Array(repeating: Particle(position: .zero, velocity: .zero,
                                                    age: 999, lifetime: 1, colorPos: 0),
                               count: maxParticles)
        self.rng = SeededRNG(seed: seed)
    }

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        var dt: Float = 0
        if lastTimestamp >= 0 {
            dt = Float(min(max(frame.timestamp - lastTimestamp, 0), 0.1))
        }
        lastTimestamp = frame.timestamp

        let palette = ColorPalette.preset(named: settings.paletteName) ?? ColorPalette.preset(named: "classic")!
        var sx: Float = 1, sy: Float = 1
        if aspect >= 1 { sx = 1 / aspect } else { sy = aspect }

        // Advance all particles.
        for i in 0..<particles.count {
            var p = particles[i]
            if p.age <= p.lifetime {
                p.position += p.velocity * dt
                p.velocity.y -= gravity * dt
                p.velocity.x *= horizontalDrag
                p.age += dt
                particles[i] = p
            }
        }

        // Spawn from each band probabilistically. P(spawn) = L * spawnRate * dt (clamped).
        let n = frame.bands.count
        if n > 0 && dt > 0 {
            for i in 0..<n {
                let L = frame.bands[i]
                guard L >= spawnFloor else { continue }
                let p = min(L * spawnRate * dt, 1)
                if rng.nextUnit() < p {
                    let x = -1 + 2 * Float(i) / Float(max(n - 1, 1))
                    let vy = baseUp + L * launchScale
                    let vx = rng.nextSigned() * horizontalJitter
                    particles[nextIndex] = Particle(
                        position: SIMD2(x, -1),
                        velocity: SIMD2(vx, vy),
                        age: 0,
                        lifetime: baseLifetime,
                        colorPos: Float(i) / Float(max(n - 1, 1))
                    )
                    nextIndex = (nextIndex + 1) % particles.count
                }
            }
        }

        // Emit live particles as small aspect-corrected quads.
        var verts: [BarVertex] = []
        verts.reserveCapacity(particles.count * 6)
        let hx = baseSize * sx, hy = baseSize * sy
        for p in particles {
            guard p.age <= p.lifetime else { continue }
            let life = max(p.lifetime, 1e-6)
            let brightness = max(0, 1 - p.age / life)
            let c = palette.sample(at: p.colorPos)
            let color = SIMD4<Float>(c.r * brightness, c.g * brightness, c.b * brightness, 1)
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
}
```

- [ ] **Step 4: Run `make test`** — expect `** TEST SUCCEEDED **`, 4 new fountain tests pass (total 100).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/SpectrumFountainVisualizer.swift Tests/CoreTests/SpectrumFountainVisualizerTests.swift
git commit -m "Add SpectrumFountainVisualizer (per-band fountain with gravity)"
```

---

## Task 2: `FireworksVisualizer`

**Files:**
- Create: `Sources/Core/FireworksVisualizer.swift`
- Test: `Tests/CoreTests/FireworksVisualizerTests.swift`

Rising-edge bass beat → one burst at a random central position; particles spread in all directions with drag + gentle gravity; fade with age.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import simd
@testable import MacVisualizerCore

final class FireworksVisualizerTests: XCTestCase {
    private func frame(bands: [Float], t: TimeInterval) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: bands, waveform: [], rms: 0, peak: 0, timestamp: t)
    }
    private let loud = [Float](repeating: 1.0, count: 24)
    private let quiet = [Float](repeating: 0.0, count: 24)

    func testVertexCountIsMultipleOfSixAndBounded() {
        let viz = FireworksVisualizer(maxParticles: 200)
        var t = 0.0
        for _ in 0..<60 {
            let v = viz.makeVertices(frame: frame(bands: loud, t: t), settings: .defaults, aspect: 1)
            XCTAssertEqual(v.count % 6, 0)
            XCTAssertLessThanOrEqual(v.count, 200 * 6)
            t += 1.0 / 60.0
        }
    }

    func testVerticesStayInClipSpace() {
        let viz = FireworksVisualizer(maxParticles: 200)
        var t = 0.0
        for _ in 0..<120 {
            // Alternate loud/quiet every 8 frames to keep triggering rising-edge beats.
            let bands = ((Int(t * 60) / 8) % 2 == 0) ? loud : quiet
            let v = viz.makeVertices(frame: frame(bands: bands, t: t), settings: .defaults, aspect: 1.6)
            for vert in v {
                XCTAssertLessThanOrEqual(abs(vert.position.x), 1.25)
                XCTAssertLessThanOrEqual(abs(vert.position.y), 1.25)
            }
            t += 1.0 / 60.0
        }
    }

    func testDeterministicForSameSeedAndCalls() {
        let a = FireworksVisualizer(maxParticles: 100, seed: 42)
        let b = FireworksVisualizer(maxParticles: 100, seed: 42)
        var t = 0.0
        var lastA: [BarVertex] = [], lastB: [BarVertex] = []
        for i in 0..<30 {
            let bands: [Float] = (i / 8) % 2 == 0 ? loud : quiet
            lastA = a.makeVertices(frame: frame(bands: bands, t: t), settings: .defaults, aspect: 1)
            lastB = b.makeVertices(frame: frame(bands: bands, t: t), settings: .defaults, aspect: 1)
            t += 1.0 / 60.0
        }
        XCTAssertEqual(lastA, lastB)
    }

    func testBeatProducesParticlesAndSilenceDoesNot() {
        // Loud run with a rising edge on frame 1 -> beat fires -> burst spawns.
        let beatViz = FireworksVisualizer(maxParticles: 200, seed: 7)
        _ = beatViz.makeVertices(frame: frame(bands: quiet, t: 0), settings: .defaults, aspect: 1)
        _ = beatViz.makeVertices(frame: frame(bands: loud, t: 1.0/60),  settings: .defaults, aspect: 1)
        let beatLast = beatViz.makeVertices(frame: frame(bands: quiet, t: 5.0/60), settings: .defaults, aspect: 1)

        // Silent run.
        let silentViz = FireworksVisualizer(maxParticles: 200, seed: 7)
        _ = silentViz.makeVertices(frame: frame(bands: quiet, t: 0), settings: .defaults, aspect: 1)
        _ = silentViz.makeVertices(frame: frame(bands: quiet, t: 1.0/60), settings: .defaults, aspect: 1)
        let silentLast = silentViz.makeVertices(frame: frame(bands: quiet, t: 5.0/60), settings: .defaults, aspect: 1)

        XCTAssertGreaterThan(beatLast.count, 0)
        XCTAssertEqual(silentLast.count, 0)
    }
}
```

- [ ] **Step 2: Run `make test`** — expect FAIL (`cannot find 'FireworksVisualizer' in scope`).

- [ ] **Step 3: Write `Sources/Core/FireworksVisualizer.swift`**:

```swift
import simd
import QuartzCore

private struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func nextUnit() -> Float {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Float(state >> 40) / Float(1 << 24)
    }
    mutating func nextSigned() -> Float { nextUnit() * 2 - 1 }
}

/// Particle bursts triggered by rising-edge bass beats at random central positions.
/// Stateful — keep one instance alive across frames (the renderer caches it).
public final class FireworksVisualizer: Visualizer {
    private struct Particle {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var age: Float
        var lifetime: Float
        var colorPos: Float
    }

    private let maxParticles: Int
    private var particles: [Particle]
    private var nextIndex: Int = 0
    private var rng: SeededRNG
    private var lastTimestamp: CFTimeInterval = -1
    private var lastBass: Float = 0
    private var lastBeatTime: CFTimeInterval = -1

    private let burstParticles: Int = 60
    private let baseSpeed: Float = 0.5
    private let spreadSpeed: Float = 0.2
    private let gravity: Float = 0.5
    private let drag: Float = 0.97
    private let baseLifetime: Float = 1.5
    private let lifetimeJitter: Float = 0.3
    private let baseSize: Float = 0.008
    private let beatThreshold: Float = 0.5
    private let beatHysteresis: Float = 0.15
    private let refractoryPeriod: CFTimeInterval = 0.15
    private let burstHalfX: Float = 0.6
    private let burstHalfY: Float = 0.4

    public init(maxParticles: Int = 600, seed: UInt64 = 0xBEEFC0DE) {
        self.maxParticles = maxParticles
        self.particles = Array(repeating: Particle(position: .zero, velocity: .zero,
                                                    age: 999, lifetime: 1, colorPos: 0),
                               count: maxParticles)
        self.rng = SeededRNG(seed: seed)
    }

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        var dt: Float = 0
        if lastTimestamp >= 0 {
            dt = Float(min(max(frame.timestamp - lastTimestamp, 0), 0.1))
        }
        lastTimestamp = frame.timestamp

        let palette = ColorPalette.preset(named: settings.paletteName) ?? ColorPalette.preset(named: "classic")!
        var sx: Float = 1, sy: Float = 1
        if aspect >= 1 { sx = 1 / aspect } else { sy = aspect }

        // Advance all particles.
        for i in 0..<particles.count {
            var p = particles[i]
            if p.age <= p.lifetime {
                p.position += p.velocity * dt
                p.velocity *= drag
                p.velocity.y -= gravity * dt
                p.age += dt
                particles[i] = p
            }
        }

        // Beat detection (rising edge over hysteresis + refractory).
        let bass = computeBass(frame)
        let now = frame.timestamp
        let crossedRising = bass > beatThreshold && lastBass <= beatThreshold - beatHysteresis
        let refractoryPassed = lastBeatTime < 0 || now - lastBeatTime >= refractoryPeriod
        if crossedRising && refractoryPassed {
            spawnBurst()
            lastBeatTime = now
        }
        lastBass = bass

        // Emit live particles.
        var verts: [BarVertex] = []
        verts.reserveCapacity(particles.count * 6)
        let hx = baseSize * sx, hy = baseSize * sy
        for p in particles {
            guard p.age <= p.lifetime else { continue }
            let life = max(p.lifetime, 1e-6)
            let brightness = max(0, 1 - p.age / life)
            let c = palette.sample(at: p.colorPos)
            let color = SIMD4<Float>(c.r * brightness, c.g * brightness, c.b * brightness, 1)
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

    private func spawnBurst() {
        let cx = rng.nextSigned() * burstHalfX
        let cy = rng.nextSigned() * burstHalfY
        let colorPos = rng.nextUnit()
        for k in 0..<burstParticles {
            // Evenly distributed angles with small RNG jitter.
            let theta = (Float(k) / Float(burstParticles)) * 2 * .pi + rng.nextSigned() * 0.05
            let speed = baseSpeed + rng.nextUnit() * spreadSpeed
            let lifetime = baseLifetime + rng.nextSigned() * lifetimeJitter
            particles[nextIndex] = Particle(
                position: SIMD2(cx, cy),
                velocity: SIMD2(cosf(theta) * speed, sinf(theta) * speed),
                age: 0,
                lifetime: max(0.3, lifetime),
                colorPos: colorPos
            )
            nextIndex = (nextIndex + 1) % particles.count
        }
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

- [ ] **Step 4: Run `make test`** — expect `** TEST SUCCEEDED **`, 4 new fireworks tests pass (total 104).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/FireworksVisualizer.swift Tests/CoreTests/FireworksVisualizerTests.swift
git commit -m "Add FireworksVisualizer (rising-edge bass beat triggers bursts)"
```

---

## Task 3: Add `.fountain` and `.fireworks` to `VisualizerStyle`

**Files:**
- Modify: `Sources/Core/VisualizerStyle.swift`
- Modify: `Tests/CoreTests/VisualizerStyleTests.swift`

- [ ] **Step 1: Update the tests** in `Tests/CoreTests/VisualizerStyleTests.swift`:
  - Replace `testAllCases` body:
    ```swift
        XCTAssertEqual(VisualizerStyle.allCases,
                       [.bars, .radial, .mirrored, .oscilloscope, .particles, .fountain, .fireworks])
    ```
  - Replace `testNextWrapsAround` body:
    ```swift
        XCTAssertEqual(VisualizerStyle.bars.next, .radial)
        XCTAssertEqual(VisualizerStyle.particles.next, .fountain)
        XCTAssertEqual(VisualizerStyle.fountain.next, .fireworks)
        XCTAssertEqual(VisualizerStyle.fireworks.next, .bars)
    ```
  - Replace `testPreviousWrapsAround` body:
    ```swift
        XCTAssertEqual(VisualizerStyle.radial.previous, .bars)
        XCTAssertEqual(VisualizerStyle.fountain.previous, .particles)
        XCTAssertEqual(VisualizerStyle.fireworks.previous, .fountain)
        XCTAssertEqual(VisualizerStyle.bars.previous, .fireworks)
    ```
  - Add a new test method:
    ```swift
        func testFountainAndFireworksFactories() {
            XCTAssertTrue(VisualizerStyle.fountain.makeVisualizer() is SpectrumFountainVisualizer)
            XCTAssertTrue(VisualizerStyle.fireworks.makeVisualizer() is FireworksVisualizer)
            XCTAssertFalse(VisualizerStyle.fountain.displayName.isEmpty)
            XCTAssertFalse(VisualizerStyle.fireworks.displayName.isEmpty)
        }
    ```
  - Leave `testDisplayNamesNonEmpty`, `testParticlesFactory`, and `testFactoryMatchesConcreteVisualizer` unchanged.

- [ ] **Step 2: Run `make test`** — expect FAIL (`.fountain`/`.fireworks` don't exist).

- [ ] **Step 3: In `Sources/Core/VisualizerStyle.swift`**:
  - Extend the case list to: `case bars, radial, mirrored, oscilloscope, particles, fountain, fireworks`.
  - In `displayName`, add: `case .fountain: return "Fountain"` and `case .fireworks: return "Fireworks"`.
  - In `makeVisualizer()`, add: `case .fountain: return SpectrumFountainVisualizer()` and `case .fireworks: return FireworksVisualizer()`.
  - `next`/`previous` use `allCases` and need no change.

- [ ] **Step 4: Run `make test`** — expect `** TEST SUCCEEDED **` (total 105 — 1 new factory test).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/VisualizerStyle.swift Tests/CoreTests/VisualizerStyleTests.swift
git commit -m "Add fountain and fireworks to VisualizerStyle"
```

---

## Task 4: Probe warm-up for stateful motion + verify

**Files:**
- Modify: `Sources/Rendering/RenderProbe.swift`

The probe currently calls `makeVertices` once. For motion-dependent visualizers (fountain needs `dt>0` to spawn; fireworks needs a rising-edge beat) a single frame produces an empty image. Add a small 3-call warm-up gated to those two styles, so their PNGs show real state. Leave all other styles' probe behavior unchanged.

- [ ] **Step 1: Modify `Sources/Rendering/RenderProbe.swift`.** READ the file first. Today it builds the local `frame` (ramp bands + sine waveform) and then computes vertices in one line:

```swift
        let vertices = style.makeVisualizer().makeVertices(frame: frame, settings: settings, aspect: aspect)
```

Replace that single line with the block below. Keep the surrounding texture/clear/encode/blit/writePNG code unchanged; `bandCount`, `wave`, `settings`, `aspect`, and `frame` are already locals in scope.

```swift
        let visualizer = style.makeVisualizer()
        let vertices: [BarVertex]
        if style == .fountain || style == .fireworks {
            // Warm-up: prime the visualizer with quiet -> loud -> quiet across ~0.5 s so
            // fountain spawns and a fireworks rising-edge beat triggers a burst that has
            // time to expand before we snapshot.
            let rampBands = (0..<bandCount).map { Float($0) / Float(max(bandCount - 1, 1)) }
            let loudBands = [Float](repeating: 1.0, count: bandCount)
            let f0 = AudioFrame(bands: rampBands, bandPeaks: rampBands, waveform: wave,
                                rms: 0, peak: rampBands.last ?? 0, timestamp: 0)
            let f1 = AudioFrame(bands: loudBands, bandPeaks: loudBands, waveform: wave,
                                rms: 1, peak: 1, timestamp: 1.0 / 60.0)
            let f2 = AudioFrame(bands: rampBands, bandPeaks: rampBands, waveform: wave,
                                rms: 0, peak: rampBands.last ?? 0, timestamp: 30.0 / 60.0)
            _ = visualizer.makeVertices(frame: f0, settings: settings, aspect: aspect)
            _ = visualizer.makeVertices(frame: f1, settings: settings, aspect: aspect)
            vertices = visualizer.makeVertices(frame: f2, settings: settings, aspect: aspect)
        } else {
            vertices = visualizer.makeVertices(frame: frame, settings: settings, aspect: aspect)
        }
```

- [ ] **Step 2: Build + tests + probe each new style (no glow then with glow)**

```bash
make build
BIN=./DerivedData/Build/Products/Debug/MacVisualizer.app/Contents/MacOS/MacVisualizer
$BIN --render-probe /tmp/v_fountain.png fountain && echo fountain=$?
$BIN --render-probe /tmp/v_fountain_glow.png fountain glow && echo fountain_glow=$?
$BIN --render-probe /tmp/v_fireworks.png fireworks && echo fireworks=$?
$BIN --render-probe /tmp/v_fireworks_glow.png fireworks glow && echo fireworks_glow=$?
make test
```
Expect `** BUILD SUCCEEDED **`, the four probes exit 0, and `make test` is `** TEST SUCCEEDED **` (105).

USE THE READ TOOL on each PNG. Expected:
- `v_fountain.png`: multiple small colored dots scattered above the bottom row, predominantly on the RIGHT side of the canvas (because the ramp's high bands are on the right; loud frame at t=1/60 sprayed every column once; particles have ~½ s of gravity acting on them in the snapshot).
- `v_fountain_glow.png`: same dots but each softly glowing.
- `v_fireworks.png`: a roughly circular ring/cloud of small colored dots radiating from a single random central position (the burst spawned at the loud frame, expanded for ~½ s).
- `v_fireworks_glow.png`: same ring/cloud with glow halos.

If a PNG is unexpectedly empty / all-black / clustered in a single pixel, report it (DONE_WITH_CONCERNS) with the actual image — don't fudge.

- [ ] **Step 3: Confirm `git status` does NOT show stray new files** (only the modified `RenderProbe.swift`). Don't commit the PNGs.

- [ ] **Step 4: Commit**

```bash
git add Sources/Rendering/RenderProbe.swift
git commit -m "Warm up motion-dependent visualizers in the render probe"
```

- [ ] **Step 5: Live verification (requires the user)** — `make run` with music playing. Press ⌘] to cycle to **Fountain** then **Fireworks** (or pick from the Visualizer menu / Settings). Expected:
  - Fountain: per-band columns spray particles up that fall back; bass on the left, treble on the right; the spectrum becomes a flowing fountain.
  - Fireworks: relatively quiet during low-energy passages; bass hits trigger bursts at random positions on the canvas, then fade.
  - Both glow when Glow is on.

Agent reports DONE if Steps 1–4 succeeded; live confirmation is pending the user.

---

## Definition of Done

- `make test` → `** TEST SUCCEEDED **` with the new tests green (4 fountain + 4 fireworks + 1 factory; ~105 total).
- `make build` → `** BUILD SUCCEEDED **`.
- The four probe PNGs render the expected fountain spray + fireworks burst (with and without glow).
- `make run`: `.fountain` and `.fireworks` are selectable via ⌘]/⌘[, the Visualizer menu, and Settings; each reacts to the music as described. Confirmed by the user.

## Notes

- Constants (spawnRate, gravity, baseSpeed, beatThreshold, lifetimes, sizes) are reasonable defaults; if the live look needs tuning, edit the constants and rerun.
- Each visualizer keeps its own private `SeededRNG` to avoid cross-file coupling (~10 lines duplicated).
- The render-probe warm-up is gated to the two new styles, so existing probe outputs (bars/radial/mirrored/oscilloscope/particles) are byte-for-byte unchanged.
