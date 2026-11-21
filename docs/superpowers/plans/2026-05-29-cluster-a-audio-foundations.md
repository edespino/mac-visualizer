# Cluster A — Audio Foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a shared goom2k4-style beat detector and a stereo-aware analysis path to `AudioFrame`/`SpectrumAnalyzer`, then wire three beat consumers (Fireworks, Particles, Fountain) and three stereo consumers (Bars, Radial, Siri).

**Architecture:** Two parallel additions inside `Sources/Core/` audio pipeline. (1) A new `BeatDetector` struct that `SpectrumAnalyzer` calls each frame; its `(beat, intensity)` output is attached to `AudioFrame`. (2) `AudioCaptureService` stops downmixing upfront and instead extracts L+R; `SpectrumAnalyzer` runs FFT per channel and exposes `bandsLeft`/`bandsRight`. Visualizers opt in via a new `useStereoImage` setting.

**Tech Stack:** Swift 5.10, XCTest, vDSP/Accelerate FFT, AppKit/SwiftUI settings UI, XcodeGen + Makefile build (`make build`, `make test`).

**Branch:** `plan-17-cluster-a-audio-foundations` (already created and the spec is committed).

---

## File Structure (what each file owns)

- `Sources/Core/BeatDetector.swift` (NEW) — goom2k4 state machine. Inputs: `peak`, `timestamp`. Outputs: `(beat: Bool, intensity: Float)`.
- `Sources/Core/AudioFrame.swift` (MODIFY) — add `bandsLeft`, `bandsRight`, `beat`, `beatIntensity`. Keep existing mono-only convenience init.
- `Sources/Core/AudioDownmix.swift` (MODIFY) — add `extractStereo(...)` alongside existing `downmixToMono(...)`.
- `Sources/Core/SpectrumAnalyzer.swift` (MODIFY) — new dual-channel `append(left:right:)` overload + per-frame `BeatDetector.update`.
- `Sources/Services/AudioCaptureService.swift` (MODIFY) — call `extractStereo`; handler now receives `(left, right, rate)`.
- `Sources/Core/FireworksVisualizer.swift` (MODIFY) — delete bespoke detector logic; trigger on `frame.beat`.
- `Sources/Core/ParticleVisualizer.swift` (MODIFY) — add transient size/velocity boost on `frame.beat`.
- `Sources/Core/SpectrumFountainVisualizer.swift` (MODIFY) — boost launch velocity on `frame.beat`.
- `Sources/Core/VisualizerSettings.swift` (MODIFY) — remove `fireworksMinBass`/`fireworksMarginFloor`/`fireworksMarginScale`/`fireworksBaselineAlpha`; add `useStereoImage: Bool`.
- `Sources/Core/SpectrumBarsVisualizer.swift` (MODIFY) — stereo split when `useStereoImage == true`.
- `Sources/Core/RadialSpectrumVisualizer.swift` (MODIFY) — center pan offset based on L/R balance.
- `Sources/Core/SiriWaveVisualizer.swift` (MODIFY) — pan tilt component based on L/R balance.
- `Sources/App/SettingsView.swift` (MODIFY) — remove four fireworks sliders; add "Use stereo image" toggle on Tweaks tab.
- `Tests/CoreTests/BeatDetectorTests.swift` (NEW) — silence, steady tone, kicks, auto-tune up, auto-tune down, refractory.
- `Tests/CoreTests/AudioFrameTests.swift` (EXTEND) — mean invariant, default values, convenience init.
- `Tests/CoreTests/SpectrumAnalyzerStereoTests.swift` (NEW) — mono regression, hard-left, hard-right, balanced.
- `Tests/CoreTests/AudioDownmixTests.swift` (EXTEND) — `extractStereo` for mono/2ch/4ch inputs.
- `Tests/CoreTests/FireworksVisualizerTests.swift` (MODIFY) — assertions switch from `bands` content to `frame.beat`.
- `Tests/CoreTests/ParticleVisualizerTests.swift`, `SpectrumFountainVisualizerTests.swift`, `SpectrumBarsVisualizerTests.swift`, `RadialSpectrumVisualizerTests.swift`, `SiriWaveVisualizerTests.swift` (MODIFY or EXTEND) — assert new behaviors.

---

## Conventions used in this plan

- All `make build` runs must end with `** BUILD SUCCEEDED **`.
- All `make test` runs must end with `** TEST SUCCEEDED **` and an `Executed N tests, with 0 failures` line.
- Commits use the existing repo style (imperative subject line, optional body explaining "why").
- The tolerant Codable decoder in `VisualizerSettings.swift` means removing a field is safe: old saved JSON decodes cleanly.

---

## Phase 1 — Beat detector (Tasks 1–6)

### Task 1: Extend AudioFrame with `beat` / `beatIntensity` (no breakage)

**Files:**
- Modify: `Sources/Core/AudioFrame.swift`
- Test: `Tests/CoreTests/AudioFrameTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/CoreTests/AudioFrameTests.swift`:

```swift
func testBeatFieldsDefaultToFalseZero() {
    let f = AudioFrame(bands: [0.1, 0.2], bandPeaks: [0.1, 0.2], waveform: [],
                       rms: 0, peak: 0, timestamp: 0)
    XCTAssertEqual(f.beat, false)
    XCTAssertEqual(f.beatIntensity, 0)
}

func testBeatFieldsAcceptExplicitValues() {
    let f = AudioFrame(bands: [], bandPeaks: [], waveform: [],
                       rms: 0, peak: 0, timestamp: 0,
                       beat: true, beatIntensity: 0.7)
    XCTAssertEqual(f.beat, true)
    XCTAssertEqual(f.beatIntensity, 0.7, accuracy: 1e-6)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: build failure with "extra argument 'beat'" or similar.

- [ ] **Step 3: Add the fields and the extended initializer**

Replace the entire `Sources/Core/AudioFrame.swift`:

```swift
import QuartzCore

public struct AudioFrame: Equatable {
    public var bands: [Float]
    public var bandPeaks: [Float]
    public var waveform: [Float]
    public var rms: Float
    public var peak: Float
    public var timestamp: CFTimeInterval
    public var beat: Bool
    public var beatIntensity: Float

    public init(bands: [Float], bandPeaks: [Float], waveform: [Float],
                rms: Float, peak: Float, timestamp: CFTimeInterval,
                beat: Bool = false, beatIntensity: Float = 0) {
        self.bands = bands
        self.bandPeaks = bandPeaks
        self.waveform = waveform
        self.rms = rms
        self.peak = peak
        self.timestamp = timestamp
        self.beat = beat
        self.beatIntensity = beatIntensity
    }

    public static let silent = AudioFrame(bands: [], bandPeaks: [], waveform: [],
                                          rms: 0, peak: 0, timestamp: 0)
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 174 tests (172 + 2 new) passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/AudioFrame.swift Tests/CoreTests/AudioFrameTests.swift
git commit -m "AudioFrame: add beat / beatIntensity fields (default false/0)"
```

---

### Task 2: New `BeatDetector` struct + tests

**Files:**
- Create: `Sources/Core/BeatDetector.swift`
- Create: `Tests/CoreTests/BeatDetectorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CoreTests/BeatDetectorTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class BeatDetectorTests: XCTestCase {

    func testSilenceProducesNoBeats() {
        var d = BeatDetector()
        var beats = 0
        for i in 0..<200 {
            let r = d.update(peak: 0, timestamp: Double(i) / 60.0)
            if r.beat { beats += 1 }
        }
        XCTAssertEqual(beats, 0)
    }

    func testSteadyToneProducesNoBeats() {
        // No onsets in a perfectly steady signal — the aged baseline catches up.
        var d = BeatDetector()
        var beats = 0
        // Warm up the baseline first.
        for i in 0..<60 { _ = d.update(peak: 0.7, timestamp: Double(i) / 60.0) }
        for i in 60..<260 {
            if d.update(peak: 0.7, timestamp: Double(i) / 60.0).beat { beats += 1 }
        }
        XCTAssertLessThanOrEqual(beats, 1, "expected 0–1 beats on a steady tone, got \(beats)")
    }

    func testKickPulsesProduceBeats() {
        // 120 BPM = 0.5s per kick. Gaussian envelope of width 0.06s around each
        // kick instant. 4 seconds = 8 kicks. Expect at least 6 detected onsets
        // (allowing 2-onset slop for the auto-tune warm-up).
        var d = BeatDetector()
        var beats = 0
        let frames = 4 * 60   // 4 seconds at 60 fps
        for i in 0..<frames {
            let t = Double(i) / 60.0
            let kickPhase = t.truncatingRemainder(dividingBy: 0.5)
            let dt = min(kickPhase, 0.5 - kickPhase)
            let env = Float(exp(-dt * dt / (2 * 0.06 * 0.06)))
            if d.update(peak: env, timestamp: t).beat { beats += 1 }
        }
        XCTAssertGreaterThanOrEqual(beats, 6, "expected ≥6 kicks detected, got \(beats)")
    }

    func testRefractoryPreventsBackToBackBeats() {
        var d = BeatDetector()
        // Two strong onsets 50 ms apart — refractory is 150 ms, so only the
        // first should fire.
        _ = d.update(peak: 0, timestamp: 0.0)
        let a = d.update(peak: 1.0, timestamp: 0.01)
        let b = d.update(peak: 1.0, timestamp: 0.06)
        XCTAssertTrue(a.beat)
        XCTAssertFalse(b.beat)
    }

    func testIntensityZeroWhenNoBeat() {
        var d = BeatDetector()
        for i in 0..<10 {
            let r = d.update(peak: 0, timestamp: Double(i) / 60.0)
            XCTAssertFalse(r.beat)
            XCTAssertEqual(r.intensity, 0, accuracy: 1e-6)
        }
    }

    func testResetClearsState() {
        var d = BeatDetector()
        for i in 0..<60 { _ = d.update(peak: 1, timestamp: Double(i) / 60.0) }
        d.reset()
        // After reset, a single strong onset should fire (no stale baseline above the new peak).
        _ = d.update(peak: 0, timestamp: 0)
        let r = d.update(peak: 1, timestamp: 1.0 / 60)
        XCTAssertTrue(r.beat)
    }

    func testGoomLimitDecaysWhenTooFewOnsets() {
        // Start with a high limit and feed kicks. The limit should decay every
        // cycleLength=64 frames if fewer than targetGoomsPerWindow=4 fired.
        var d = BeatDetector()
        d.setGoomLimitForTesting(5.0)
        // 4 cycle windows = 256 frames with 120 BPM kicks (8 kicks total — but
        // they won't fire at limit=5 initially, so totalGoom stays under target
        // and the limit decays each cycle).
        for i in 0..<256 {
            let t = Double(i) / 60.0
            let kickPhase = t.truncatingRemainder(dividingBy: 0.5)
            let dt = min(kickPhase, 0.5 - kickPhase)
            let env = Float(exp(-dt * dt / (2 * 0.06 * 0.06)))
            _ = d.update(peak: env, timestamp: t)
        }
        XCTAssertLessThan(d.goomLimit, 1.0, "expected goomLimit to decay; got \(d.goomLimit)")
    }

    func testGoomLimitGrowsWhenTooManyOnsets() {
        // Feed a continuously rising-then-falling noise signal that produces
        // many onsets — the limit should grow to suppress them.
        var d = BeatDetector()
        let initial = d.goomLimit
        for i in 0..<256 {
            let t = Double(i) / 60.0
            // Sawtooth pattern with frequent sharp jumps.
            let peak = Float(((i % 4) == 0) ? 1.0 : 0.0)
            _ = d.update(peak: peak, timestamp: t)
        }
        XCTAssertGreaterThan(d.goomLimit, initial, "expected goomLimit to grow; got \(d.goomLimit) (initial \(initial))")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: build failure — `BeatDetector` not defined.

- [ ] **Step 3: Implement `BeatDetector`**

Create `Sources/Core/BeatDetector.swift`:

```swift
import QuartzCore

/// Adaptive single-band onset detector ported from goom2k4's `sound_tester.c`.
/// Tracks an aged "loudness" envelope; when its per-frame increase exceeds an
/// adaptive limit (auto-tuned every 64 frames toward a target onset rate),
/// emits a beat. The `intensity` returned on a beat is the normalized
/// magnitude of the onset (0…1), zero on non-beat frames.
///
/// Stateful — keep one instance alive across the analyzer's lifetime.
public struct BeatDetector {
    // State
    private var accelvar: Float = 0          // aged loudness envelope
    private var prevAccel: Float = 0         // previous frame's envelope (for delta)
    public private(set) var goomLimit: Float = 1.0   // adaptive onset threshold (readable for diagnostics)
    private var cycleTime: Int = 0           // frames since last retune
    private var totalGoom: Int = 0           // onsets fired in current cycle
    private var lastBeatTimestamp: CFTimeInterval = -.infinity

    // Tuning constants (units adapted to our 0…1 peak amplitude range).
    private let cycleLength: Int = 64
    private let targetGoomsPerWindow: Int = 4   // ≈ 4 onsets per second at 60 fps
    private let goomLimitFloor: Float = 0.05
    private let goomLimitDecay: Float = 0.91
    private let goomLimitGrowth: Float = 1.10
    private let accelDecay: Float = 0.91
    private let refractorySeconds: CFTimeInterval = 0.15

    public init() {}

    public mutating func reset() {
        accelvar = 0
        prevAccel = 0
        goomLimit = 1.0
        cycleTime = 0
        totalGoom = 0
        lastBeatTimestamp = -.infinity
    }

    /// Testing-only: pre-seed the adaptive threshold so tests can verify
    /// auto-tune behavior in either direction.
    internal mutating func setGoomLimitForTesting(_ value: Float) {
        goomLimit = value
    }

    /// One frame of analysis. `peak` should be the raw window peak amplitude
    /// (pre-smoothing), typically `frame.peak` from `SpectrumAnalyzer`.
    /// Returns `(beat: true, intensity: x>0)` on the single frame an onset
    /// fires, else `(beat: false, intensity: 0)`.
    public mutating func update(peak: Float, timestamp: CFTimeInterval) -> (beat: Bool, intensity: Float) {
        accelvar = max(accelvar * accelDecay, peak)
        let delta = accelvar - prevAccel
        let refractoryOK = timestamp - lastBeatTimestamp >= refractorySeconds
        let firing = (delta > goomLimit) && refractoryOK

        var intensity: Float = 0
        if firing {
            totalGoom += 1
            lastBeatTimestamp = timestamp
            intensity = min(1, max(0, delta / max(goomLimit, 0.01)))
        }
        prevAccel = accelvar

        cycleTime += 1
        if cycleTime >= cycleLength {
            if totalGoom < targetGoomsPerWindow {
                goomLimit = max(goomLimitFloor, goomLimit * goomLimitDecay)
            } else if totalGoom > targetGoomsPerWindow {
                goomLimit = goomLimit * goomLimitGrowth
            }
            cycleTime = 0
            totalGoom = 0
        }

        return (firing, intensity)
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 182 tests (174 + 8 new) passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/BeatDetector.swift Tests/CoreTests/BeatDetectorTests.swift
git commit -m "Add BeatDetector: goom2k4-port self-tuning onset detector"
```

---

### Task 3: `SpectrumAnalyzer` wires BeatDetector

**Files:**
- Modify: `Sources/Core/SpectrumAnalyzer.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/CoreTests/SpectrumAnalyzerTests.swift` (existing file):

```swift
func testAnalyzerAttachesBeatInfoToFrame() {
    let s = VisualizerSettings.defaults
    let analyzer = SpectrumAnalyzer(fftSize: 1024, sampleRate: 48000, settings: s)
    // First buffer of silence to fill the FFT window.
    let silent = [Float](repeating: 0, count: 1024)
    _ = analyzer.append(silent)
    // Now a loud impulse: ramp to 1 in one window. Expect at least one beat
    // attached to a returned frame over 30 windows.
    var beats = 0
    for w in 0..<30 {
        let pcm: [Float] = (w == 3) ? (0..<1024).map { _ in 1.0 } : silent
        if let frame = analyzer.append(pcm) {
            if frame.beat { beats += 1 }
        }
    }
    XCTAssertGreaterThan(beats, 0, "expected analyzer to attach at least one beat across 30 windows")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: test fails with `expected analyzer to attach at least one beat` (the frame.beat is always false).

- [ ] **Step 3: Add `BeatDetector` to the analyzer**

In `Sources/Core/SpectrumAnalyzer.swift`, add a private field next to `private var post: BandPostProcessor`:

```swift
    private var beatDetector = BeatDetector()
```

Add a reset hook inside `reconfigure(...)` after the `post = ...` reassignment:

```swift
        beatDetector.reset()
```

In the `append(_:)` method, replace the final `return AudioFrame(...)` block:

```swift
        let beatResult = beatDetector.update(peak: peak, timestamp: CACurrentMediaTime())
        return AudioFrame(
            bands: processed.bands,
            bandPeaks: processed.peaks,
            waveform: wave,
            rms: rms,
            peak: peak,
            timestamp: CACurrentMediaTime(),
            beat: beatResult.beat,
            beatIntensity: beatResult.intensity
        )
```

Note: the `timestamp:` is sampled twice (once for the detector, once for the frame) — both `CACurrentMediaTime()` calls happen back-to-back so the values are equal to nanosecond precision. The duplicated reads are intentional and acceptable.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 183 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/SpectrumAnalyzer.swift Tests/CoreTests/SpectrumAnalyzerTests.swift
git commit -m "SpectrumAnalyzer: attach beat/beatIntensity from BeatDetector"
```

---

### Task 4: FireworksVisualizer migrates to `frame.beat`

**Files:**
- Modify: `Sources/Core/FireworksVisualizer.swift`
- Modify: `Tests/CoreTests/FireworksVisualizerTests.swift`

- [ ] **Step 1: Rewrite the test**

Replace `Tests/CoreTests/FireworksVisualizerTests.swift` entirely:

```swift
import XCTest
import simd
@testable import MacVisualizerCore

final class FireworksVisualizerTests: XCTestCase {
    private func frame(beat: Bool, intensity: Float = 0.7, t: TimeInterval) -> AudioFrame {
        AudioFrame(bands: [Float](repeating: 0, count: 24),
                   bandPeaks: [Float](repeating: 0, count: 24),
                   waveform: [], rms: 0, peak: 0, timestamp: t,
                   beat: beat, beatIntensity: intensity)
    }

    func testVertexCountIsMultipleOfSixAndBounded() {
        let viz = FireworksVisualizer(maxParticles: 200)
        var t = 0.0
        for i in 0..<60 {
            let f = frame(beat: i % 10 == 0, t: t)
            let v = viz.makeVertices(frame: f, settings: .defaults, aspect: 1)
            XCTAssertEqual(v.count % 6, 0)
            XCTAssertLessThanOrEqual(v.count, 200 * 6)
            t += 1.0 / 60.0
        }
    }

    func testVerticesStayInClipSpace() {
        let viz = FireworksVisualizer(maxParticles: 200)
        var t = 0.0
        for i in 0..<120 {
            let v = viz.makeVertices(frame: frame(beat: i % 12 == 0, t: t),
                                     settings: .defaults, aspect: 1.6)
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
            let f = frame(beat: i % 8 == 0, t: t)
            lastA = a.makeVertices(frame: f, settings: .defaults, aspect: 1)
            lastB = b.makeVertices(frame: f, settings: .defaults, aspect: 1)
            t += 1.0 / 60.0
        }
        XCTAssertEqual(lastA, lastB)
    }

    func testBeatProducesParticlesAndSilenceDoesNot() {
        let beatViz = FireworksVisualizer(maxParticles: 200, seed: 7)
        _ = beatViz.makeVertices(frame: frame(beat: false, t: 0), settings: .defaults, aspect: 1)
        _ = beatViz.makeVertices(frame: frame(beat: true, intensity: 0.9, t: 1.0/60), settings: .defaults, aspect: 1)
        let beatLast = beatViz.makeVertices(frame: frame(beat: false, t: 5.0/60), settings: .defaults, aspect: 1)

        let silentViz = FireworksVisualizer(maxParticles: 200, seed: 7)
        _ = silentViz.makeVertices(frame: frame(beat: false, t: 0), settings: .defaults, aspect: 1)
        _ = silentViz.makeVertices(frame: frame(beat: false, t: 1.0/60), settings: .defaults, aspect: 1)
        let silentLast = silentViz.makeVertices(frame: frame(beat: false, t: 5.0/60), settings: .defaults, aspect: 1)

        XCTAssertGreaterThan(beatLast.count, 0)
        XCTAssertEqual(silentLast.count, 0)
    }

    func testIntensityScalesBurstSize() {
        let small = FireworksVisualizer(maxParticles: 200, seed: 7)
        let big   = FireworksVisualizer(maxParticles: 200, seed: 7)
        // Same seed, same call sequence — only difference is intensity.
        _ = small.makeVertices(frame: frame(beat: true, intensity: 0.1, t: 0), settings: .defaults, aspect: 1)
        _ = big.makeVertices  (frame: frame(beat: true, intensity: 1.0, t: 0), settings: .defaults, aspect: 1)
        let sV = small.makeVertices(frame: frame(beat: false, t: 1.0/60), settings: .defaults, aspect: 1)
        let bV = big.makeVertices  (frame: frame(beat: false, t: 1.0/60), settings: .defaults, aspect: 1)
        XCTAssertLessThan(sV.count, bV.count, "lower intensity should produce fewer live particles")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: build failure — `FireworksVisualizer` still references `settings.fireworksMinBass` etc., and `computeBass(frame)`.

- [ ] **Step 3: Migrate FireworksVisualizer**

Replace the entire `Sources/Core/FireworksVisualizer.swift` with:

```swift
import simd
import QuartzCore

/// Particle bursts triggered by `frame.beat == true`. Burst size scales with
/// `frame.beatIntensity` (0…1). Stateful — keep one instance alive across
/// frames (the renderer caches it).
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

    private let burstParticlesMax: Int = 60
    private let baseSpeed: Float = 0.5
    private let spreadSpeed: Float = 0.2
    private let gravity: Float = 0.5
    private let drag: Float = 0.97
    private let baseLifetime: Float = 1.5
    private let lifetimeJitter: Float = 0.3
    private let baseSize: Float = 0.008
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
            dt = Float(min(max(frame.timestamp - lastTimestamp, 0), 0.1)) * settings.particleSpeed
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

        if frame.beat {
            spawnBurst(intensity: frame.beatIntensity)
        }

        // Emit live particles.
        var verts: [BarVertex] = []
        verts.reserveCapacity(particles.count * 6)
        let hx = baseSize * sx * settings.particleSize, hy = baseSize * sy * settings.particleSize
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

    private func spawnBurst(intensity: Float) {
        let scale = 0.7 + 0.6 * max(0, min(1, intensity))   // 0.7…1.3
        let burstCount = max(8, Int(Float(burstParticlesMax) * scale))
        let cx = rng.nextSigned() * burstHalfX
        let cy = rng.nextSigned() * burstHalfY
        let colorPos = rng.nextUnit()
        for k in 0..<burstCount {
            let theta = (Float(k) / Float(burstCount)) * 2 * .pi + rng.nextSigned() * 0.05
            let speed = (baseSpeed + rng.nextUnit() * spreadSpeed) * scale
            let lifetime = (baseLifetime + rng.nextSigned() * lifetimeJitter) * scale
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
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **`. Test count is 183 + 1 new (`testIntensityScalesBurstSize`) = 184.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/FireworksVisualizer.swift Tests/CoreTests/FireworksVisualizerTests.swift
git commit -m "Fireworks: trigger on frame.beat, scale burst by beatIntensity"
```

---

### Task 5: ParticleVisualizer adds beat-driven boost

**Files:**
- Modify: `Sources/Core/ParticleVisualizer.swift`
- Modify (extend): `Tests/CoreTests/ParticleVisualizerTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/CoreTests/ParticleVisualizerTests.swift`:

```swift
func testBeatBoostMakesParticlesLargerForOneFrame() {
    let bands = [Float](repeating: 0.5, count: 24)
    let baseFrame = AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                               rms: 0.4, peak: 0.5, timestamp: 0)
    let beatFrame = AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                               rms: 0.4, peak: 0.5, timestamp: 0,
                               beat: true, beatIntensity: 1.0)
    let baseViz = ParticleVisualizer(particleCount: 100, seed: 17)
    let boostViz = ParticleVisualizer(particleCount: 100, seed: 17)
    // Warm both visualizers with one non-beat frame to align state.
    _ = baseViz.makeVertices(frame: baseFrame, settings: .defaults, aspect: 1)
    _ = boostViz.makeVertices(frame: beatFrame, settings: .defaults, aspect: 1)

    // Same next-frame input — the boosted one should still render visibly larger
    // quads because the boost decays gradually.
    let t1 = AudioFrame(bands: bands, bandPeaks: bands, waveform: [], rms: 0.4, peak: 0.5, timestamp: 1.0/60)
    let baseVerts = baseViz.makeVertices(frame: t1, settings: .defaults, aspect: 1)
    let boostVerts = boostViz.makeVertices(frame: t1, settings: .defaults, aspect: 1)
    // Same vertex count (same particle count), but the x-extents on the boosted
    // visualizer should be wider on average.
    func avgWidth(_ verts: [BarVertex]) -> Float {
        guard !verts.isEmpty else { return 0 }
        var total: Float = 0; var n = 0
        for i in stride(from: 0, to: verts.count - 5, by: 6) {
            let xs = [verts[i].position.x, verts[i+1].position.x, verts[i+2].position.x]
            let xmin = xs.min() ?? 0; let xmax = xs.max() ?? 0
            total += (xmax - xmin); n += 1
        }
        return n > 0 ? total / Float(n) : 0
    }
    XCTAssertGreaterThan(avgWidth(boostVerts), avgWidth(baseVerts))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: test fails — boosted and base produce identical widths because no beat handling exists.

- [ ] **Step 3: Add beat-driven boost**

In `Sources/Core/ParticleVisualizer.swift`, line 19 (after `private var lastTimestamp: CFTimeInterval = -1`), add:

```swift
    private var beatBoost: Float = 0   // decays toward 0 each frame; pulsed by frame.beat
```

After line 43 (`lastTimestamp = frame.timestamp`), insert the beat pulse block:

```swift

        // Beat-driven size pulse: decay current boost, then pulse on this frame.
        beatBoost *= powf(0.5, dt / 0.15)   // half-life 150ms
        if frame.beat {
            beatBoost = max(beatBoost, 0.5 * max(0, min(1, frame.beatIntensity)))
        }
        let sizeBoost: Float = 1 + beatBoost
```

Then replace line 81 (`let hx = p.size * sx * settings.particleSize, hy = p.size * sy * settings.particleSize`) with:

```swift
            let hx = p.size * sx * settings.particleSize * sizeBoost
            let hy = p.size * sy * settings.particleSize * sizeBoost
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 185 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/ParticleVisualizer.swift Tests/CoreTests/ParticleVisualizerTests.swift
git commit -m "ParticleVisualizer: pulse particle size on frame.beat (150ms decay)"
```

---

### Task 6: SpectrumFountainVisualizer beat-driven launch boost

**Files:**
- Modify: `Sources/Core/SpectrumFountainVisualizer.swift`
- Modify (extend): `Tests/CoreTests/SpectrumFountainVisualizerTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/CoreTests/SpectrumFountainVisualizerTests.swift`:

```swift
func testBeatBoostsLaunchVelocityImmediately() {
    let bands = [Float](repeating: 0.5, count: 24)
    let baseF = AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                           rms: 0.4, peak: 0.5, timestamp: 0)
    let beatF = AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                           rms: 0.4, peak: 0.5, timestamp: 0,
                           beat: true, beatIntensity: 1.0)
    let baseViz = SpectrumFountainVisualizer(seed: 21)
    let beatViz = SpectrumFountainVisualizer(seed: 21)
    _ = baseViz.makeVertices(frame: baseF, settings: .defaults, aspect: 1)
    _ = beatViz.makeVertices(frame: beatF, settings: .defaults, aspect: 1)
    // After ~5 frames of decay, the beat-spawned particles should still sit
    // visibly higher (larger maxY) than the non-beat ones.
    var bestBase: Float = -10, bestBeat: Float = -10
    for i in 1...5 {
        let t = Double(i) / 60.0
        let f = AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                           rms: 0.4, peak: 0.5, timestamp: t)
        let bv = baseViz.makeVertices(frame: f, settings: .defaults, aspect: 1)
        let kv = beatViz.makeVertices(frame: f, settings: .defaults, aspect: 1)
        bestBase = max(bestBase, bv.map(\.position.y).max() ?? -10)
        bestBeat = max(bestBeat, kv.map(\.position.y).max() ?? -10)
    }
    XCTAssertGreaterThan(bestBeat, bestBase)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: test fails because no beat handling exists.

- [ ] **Step 3: Add launch-velocity boost**

In `Sources/Core/SpectrumFountainVisualizer.swift`, after line 51 (`if aspect >= 1 { sx = 1 / aspect } else { sy = aspect }`) and before the "Advance all particles" loop, insert:

```swift

        let beatLaunch: Float = frame.beat ? (1 + 0.6 * max(0, min(1, frame.beatIntensity))) : 1
```

Then replace line 77 (`let vy = vyBase * (1 + rng.nextSigned() * launchJitter)`) with:

```swift
                    let vy = vyBase * (1 + rng.nextSigned() * launchJitter) * beatLaunch
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 186 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/SpectrumFountainVisualizer.swift Tests/CoreTests/SpectrumFountainVisualizerTests.swift
git commit -m "SpectrumFountain: boost launch velocity on frame.beat"
```

---

## Phase 2 — Stereo plumbing (Tasks 7–10)

### Task 7: Extend AudioFrame with `bandsLeft` / `bandsRight`

**Files:**
- Modify: `Sources/Core/AudioFrame.swift`
- Modify (extend): `Tests/CoreTests/AudioFrameTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/CoreTests/AudioFrameTests.swift`:

```swift
func testBandsLeftRightDefaultToBands() {
    let bands: [Float] = [0.1, 0.2, 0.3]
    let f = AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                       rms: 0, peak: 0, timestamp: 0)
    XCTAssertEqual(f.bandsLeft, bands)
    XCTAssertEqual(f.bandsRight, bands)
}

func testBandsLeftRightExplicit() {
    let L: [Float] = [1.0, 0.0]
    let R: [Float] = [0.0, 1.0]
    let f = AudioFrame(bands: [0.5, 0.5], bandsLeft: L, bandsRight: R,
                       bandPeaks: [0.5, 0.5], waveform: [],
                       rms: 0, peak: 0, timestamp: 0)
    XCTAssertEqual(f.bandsLeft, L)
    XCTAssertEqual(f.bandsRight, R)
    // Mean invariant.
    for i in 0..<2 {
        XCTAssertEqual(f.bands[i], (L[i] + R[i]) / 2, accuracy: 1e-6)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: build failure on the second test — `bandsLeft:` is not an init parameter.

- [ ] **Step 3: Add the fields and the dual-init**

Replace `Sources/Core/AudioFrame.swift` with:

```swift
import QuartzCore

public struct AudioFrame: Equatable {
    public var bands: [Float]
    public var bandsLeft: [Float]
    public var bandsRight: [Float]
    public var bandPeaks: [Float]
    public var waveform: [Float]
    public var rms: Float
    public var peak: Float
    public var timestamp: CFTimeInterval
    public var beat: Bool
    public var beatIntensity: Float

    /// Mono-source convenience init: `bandsLeft = bandsRight = bands`.
    public init(bands: [Float], bandPeaks: [Float], waveform: [Float],
                rms: Float, peak: Float, timestamp: CFTimeInterval,
                beat: Bool = false, beatIntensity: Float = 0) {
        self.bands = bands
        self.bandsLeft = bands
        self.bandsRight = bands
        self.bandPeaks = bandPeaks
        self.waveform = waveform
        self.rms = rms
        self.peak = peak
        self.timestamp = timestamp
        self.beat = beat
        self.beatIntensity = beatIntensity
    }

    /// Stereo init. `bands` is provided explicitly (caller is responsible for
    /// honoring the mean invariant `bands[i] == (bandsLeft[i] + bandsRight[i]) / 2`).
    public init(bands: [Float], bandsLeft: [Float], bandsRight: [Float],
                bandPeaks: [Float], waveform: [Float],
                rms: Float, peak: Float, timestamp: CFTimeInterval,
                beat: Bool = false, beatIntensity: Float = 0) {
        self.bands = bands
        self.bandsLeft = bandsLeft
        self.bandsRight = bandsRight
        self.bandPeaks = bandPeaks
        self.waveform = waveform
        self.rms = rms
        self.peak = peak
        self.timestamp = timestamp
        self.beat = beat
        self.beatIntensity = beatIntensity
    }

    public static let silent = AudioFrame(bands: [], bandPeaks: [], waveform: [],
                                          rms: 0, peak: 0, timestamp: 0)
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 188 tests (186 + 2 new) passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/AudioFrame.swift Tests/CoreTests/AudioFrameTests.swift
git commit -m "AudioFrame: add bandsLeft / bandsRight (defaults to bands on mono init)"
```

---

### Task 8: `AudioDownmix.extractStereo`

**Files:**
- Modify: `Sources/Core/AudioDownmix.swift`
- Modify (extend): `Tests/CoreTests/AudioDownmixTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/CoreTests/AudioDownmixTests.swift`:

```swift
func testExtractStereoMonoDuplicates() {
    let input: [Float] = [0.1, 0.2, 0.3]
    let (L, R) = extractStereo(interleaved: input, channelCount: 1)
    XCTAssertEqual(L, input)
    XCTAssertEqual(R, input)
}

func testExtractStereoTwoChannelDeinterleaves() {
    // L=0.1, R=-0.1, L=0.2, R=-0.2
    let input: [Float] = [0.1, -0.1, 0.2, -0.2]
    let (L, R) = extractStereo(interleaved: input, channelCount: 2)
    XCTAssertEqual(L, [0.1, 0.2])
    XCTAssertEqual(R, [-0.1, -0.2])
}

func testExtractStereoSixChannelTakesFirstTwo() {
    // 5.1 layout: L, R, C, LFE, Ls, Rs
    let input: [Float] = [0.1, -0.1, 0, 0, 0, 0,
                          0.2, -0.2, 0, 0, 0, 0]
    let (L, R) = extractStereo(interleaved: input, channelCount: 6)
    XCTAssertEqual(L, [0.1, 0.2])
    XCTAssertEqual(R, [-0.1, -0.2])
}

func testExtractStereoEmpty() {
    let (L, R) = extractStereo(interleaved: [], channelCount: 2)
    XCTAssertTrue(L.isEmpty)
    XCTAssertTrue(R.isEmpty)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: build failure — `extractStereo` is not defined.

- [ ] **Step 3: Add the function**

Append to `Sources/Core/AudioDownmix.swift`:

```swift

/// Extract L and R channels from an interleaved buffer. For `channelCount == 1`,
/// returns `(samples, samples)` (mono → duplicate). For 2+ channels, returns
/// channels 0 and 1 (5.1 layouts conventionally place L on ch 0 and R on ch 1).
/// A trailing partial frame is ignored.
public func extractStereo(interleaved: [Float], channelCount: Int) -> (left: [Float], right: [Float]) {
    precondition(channelCount >= 1, "channelCount must be >= 1")
    if channelCount == 1 {
        return (interleaved, interleaved)
    }
    let frames = interleaved.count / channelCount
    guard frames > 0 else { return ([], []) }
    var left = [Float](repeating: 0, count: frames)
    var right = [Float](repeating: 0, count: frames)
    for f in 0..<frames {
        let base = f * channelCount
        left[f] = interleaved[base]
        right[f] = interleaved[base + 1]
    }
    return (left, right)
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 192 tests (188 + 4 new) passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/AudioDownmix.swift Tests/CoreTests/AudioDownmixTests.swift
git commit -m "AudioDownmix: add extractStereo(interleaved:channelCount:)"
```

---

### Task 9: SpectrumAnalyzer dual-channel append

**Files:**
- Modify: `Sources/Core/SpectrumAnalyzer.swift`
- Create: `Tests/CoreTests/SpectrumAnalyzerStereoTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CoreTests/SpectrumAnalyzerStereoTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class SpectrumAnalyzerStereoTests: XCTestCase {

    private func sineBuffer(freq: Float, sampleRate: Float, samples: Int, amplitude: Float = 1.0) -> [Float] {
        var out = [Float](repeating: 0, count: samples)
        for i in 0..<samples {
            out[i] = amplitude * sinf(2 * .pi * freq * Float(i) / sampleRate)
        }
        return out
    }

    func testMonoAppendMatchesPreviousBehavior() {
        // Feeding identical L and R should yield bandsLeft == bandsRight == bands.
        let s = VisualizerSettings.defaults
        let analyzer = SpectrumAnalyzer(fftSize: 1024, sampleRate: 48000, settings: s)
        let pcm = sineBuffer(freq: 440, sampleRate: 48000, samples: 1024)
        guard let frame = analyzer.append(left: pcm, right: pcm) else {
            return XCTFail("expected a frame on full window")
        }
        XCTAssertEqual(frame.bandsLeft, frame.bandsRight)
        XCTAssertEqual(frame.bandsLeft, frame.bands)
    }

    func testHardLeftMeansRightIsSilent() {
        let s = VisualizerSettings.defaults
        let analyzer = SpectrumAnalyzer(fftSize: 1024, sampleRate: 48000, settings: s)
        let pcm = sineBuffer(freq: 440, sampleRate: 48000, samples: 1024)
        let silence = [Float](repeating: 0, count: 1024)
        guard let frame = analyzer.append(left: pcm, right: silence) else {
            return XCTFail("expected a frame")
        }
        let leftSum = frame.bandsLeft.reduce(0, +)
        let rightSum = frame.bandsRight.reduce(0, +)
        XCTAssertGreaterThan(leftSum, 0)
        XCTAssertEqual(rightSum, 0, accuracy: 1e-3)
        // Mean invariant.
        for i in 0..<frame.bands.count {
            XCTAssertEqual(frame.bands[i], (frame.bandsLeft[i] + frame.bandsRight[i]) / 2, accuracy: 1e-6)
        }
    }

    func testHardRightMeansLeftIsSilent() {
        let s = VisualizerSettings.defaults
        let analyzer = SpectrumAnalyzer(fftSize: 1024, sampleRate: 48000, settings: s)
        let pcm = sineBuffer(freq: 440, sampleRate: 48000, samples: 1024)
        let silence = [Float](repeating: 0, count: 1024)
        guard let frame = analyzer.append(left: silence, right: pcm) else {
            return XCTFail("expected a frame")
        }
        let leftSum = frame.bandsLeft.reduce(0, +)
        let rightSum = frame.bandsRight.reduce(0, +)
        XCTAssertEqual(leftSum, 0, accuracy: 1e-3)
        XCTAssertGreaterThan(rightSum, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: build failure — `analyzer.append(left:right:)` doesn't exist.

- [ ] **Step 3: Add the dual-channel path**

In `Sources/Core/SpectrumAnalyzer.swift`, the analyzer currently has a single ring buffer. Replace with two rings (one per channel) and add the new `append(left:right:)` method. The current `append(_:)` becomes a forwarder.

Replace the whole file:

```swift
import Accelerate
import QuartzCore

/// Turns streamed PCM into `AudioFrame`s via the full DSP pipeline. Supports
/// per-channel (L+R) analysis: `bandsLeft` / `bandsRight` on the output frame.
/// Single-channel callers can use the legacy `append(_:)` overload, which
/// internally feeds the same buffer to both channels.
/// Not thread-safe; confine to a single analysis queue.
public final class SpectrumAnalyzer {
    private let fftSize: Int
    private let waveformPointCount = 256
    private var sampleRate: Float
    private var barCount: Int
    private var window: [Float]
    private var windowKind: FFTWindow
    private let fftL: FFTProcessor
    private let fftR: FFTProcessor
    private var mapper: BandMapper
    private var postL: BandPostProcessor
    private var postR: BandPostProcessor
    private var beatDetector = BeatDetector()

    private var ringL: [Float] = []
    private var ringR: [Float] = []

    public init(fftSize: Int = 2048, sampleRate: Float = 48000, settings: VisualizerSettings) {
        self.fftSize = fftSize
        self.sampleRate = sampleRate
        self.barCount = settings.barCount
        self.windowKind = settings.fftWindow
        self.window = makeWindow(settings.fftWindow, count: fftSize)
        self.fftL = FFTProcessor(size: fftSize)
        self.fftR = FFTProcessor(size: fftSize)
        self.mapper = BandMapper(bandCount: settings.barCount, fftSize: fftSize, sampleRate: sampleRate)
        self.postL = BandPostProcessor(bandCount: settings.barCount,
                                        gain: settings.gain,
                                        smoothing: settings.smoothing,
                                        peakDecay: settings.peakHoldEnabled ? 0.95 : 0.0)
        self.postR = BandPostProcessor(bandCount: settings.barCount,
                                        gain: settings.gain,
                                        smoothing: settings.smoothing,
                                        peakDecay: settings.peakHoldEnabled ? 0.95 : 0.0)
        self.ringL.reserveCapacity(fftSize * 2)
        self.ringR.reserveCapacity(fftSize * 2)
    }

    public func update(gain: Float, smoothing: Float, peakHoldEnabled: Bool) {
        postL.gain = gain; postR.gain = gain
        postL.smoothing = smoothing; postR.smoothing = smoothing
        let decay: Float = peakHoldEnabled ? 0.95 : 0.0
        postL.peakDecay = decay; postR.peakDecay = decay
    }

    public func setWindow(_ kind: FFTWindow) {
        guard kind != windowKind else { return }
        windowKind = kind
        window = makeWindow(kind, count: fftSize)
    }

    public func reconfigure(sampleRate newRate: Float? = nil, barCount newBarCount: Int? = nil) {
        if let r = newRate { sampleRate = r }
        if let b = newBarCount { barCount = b }
        mapper = BandMapper(bandCount: barCount, fftSize: fftSize, sampleRate: sampleRate)
        postL = BandPostProcessor(bandCount: barCount, gain: postL.gain, smoothing: postL.smoothing, peakDecay: postL.peakDecay)
        postR = BandPostProcessor(bandCount: barCount, gain: postR.gain, smoothing: postR.smoothing, peakDecay: postR.peakDecay)
        beatDetector.reset()
    }

    /// Mono convenience: feed the same buffer to both channels. Returns
    /// `bandsLeft == bandsRight == bands` on the frame.
    @discardableResult
    public func append(_ samples: [Float]) -> AudioFrame? {
        return append(left: samples, right: samples)
    }

    /// Dual-channel append. Returns a frame when both rings have a full window.
    @discardableResult
    public func append(left: [Float], right: [Float]) -> AudioFrame? {
        ringL.append(contentsOf: left)
        ringR.append(contentsOf: right)
        if ringL.count > fftSize { ringL.removeFirst(ringL.count - fftSize) }
        if ringR.count > fftSize { ringR.removeFirst(ringR.count - fftSize) }
        guard ringL.count == fftSize && ringR.count == fftSize else { return nil }

        let l = ringL, r = ringR

        var rmsL: Float = 0, rmsR: Float = 0
        vDSP_rmsqv(l, 1, &rmsL, vDSP_Length(fftSize))
        vDSP_rmsqv(r, 1, &rmsR, vDSP_Length(fftSize))
        let rms = (rmsL + rmsR) / 2

        var minL: Float = 0, maxL: Float = 0, minR: Float = 0, maxR: Float = 0
        vDSP_minv(l, 1, &minL, vDSP_Length(fftSize))
        vDSP_maxv(l, 1, &maxL, vDSP_Length(fftSize))
        vDSP_minv(r, 1, &minR, vDSP_Length(fftSize))
        vDSP_maxv(r, 1, &maxR, vDSP_Length(fftSize))
        let peak = max(abs(minL), abs(maxL), abs(minR), abs(maxR))

        let wL = zip(l, window).map(*)
        let wR = zip(r, window).map(*)
        let magsL = fftL.magnitudes(of: wL)
        let magsR = fftR.magnitudes(of: wR)
        let rawL = mapper.bands(from: magsL)
        let rawR = mapper.bands(from: magsR)
        let procL = postL.process(rawL)
        let procR = postR.process(rawR)

        var bands = [Float](repeating: 0, count: procL.bands.count)
        var peaks = [Float](repeating: 0, count: procL.peaks.count)
        for i in 0..<bands.count {
            bands[i] = (procL.bands[i] + procR.bands[i]) / 2
            peaks[i] = max(procL.peaks[i], procR.peaks[i])
        }

        // Waveform from L channel (visually equivalent; cheaper than averaging).
        let step = max(1, fftSize / waveformPointCount)
        var wave = [Float]()
        wave.reserveCapacity(waveformPointCount)
        var wi = 0
        while wi < l.count && wave.count < waveformPointCount {
            wave.append(l[wi]); wi += step
        }

        let now = CACurrentMediaTime()
        let beatResult = beatDetector.update(peak: peak, timestamp: now)

        return AudioFrame(
            bands: bands,
            bandsLeft: procL.bands,
            bandsRight: procR.bands,
            bandPeaks: peaks,
            waveform: wave,
            rms: rms,
            peak: peak,
            timestamp: now,
            beat: beatResult.beat,
            beatIntensity: beatResult.intensity
        )
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **`. Test count adds 3 from the new file = 195.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/SpectrumAnalyzer.swift Tests/CoreTests/SpectrumAnalyzerStereoTests.swift
git commit -m "SpectrumAnalyzer: dual-channel append(left:right:) with stereo bands"
```

---

### Task 10: AudioCaptureSource passes L + R

**Files:**
- Modify: `Sources/Core/AudioCaptureSource.swift`
- Modify: `Sources/Services/AudioCaptureService.swift`
- Modify: `Sources/Services/AudioProbe.swift`
- Modify: `Sources/App/RenderModel.swift`

- [ ] **Step 1: Update the protocol signature**

In `Sources/Core/AudioCaptureSource.swift`, replace line 16:

```swift
    var onSamples: (([Float], Double) -> Void)? { get set }
```

with:

```swift
    /// Called on a background queue with L and R sample buffers and the sample rate.
    /// Mono sources should pass the same buffer for both L and R.
    var onSamples: (([Float], [Float], Double) -> Void)? { get set }
```

- [ ] **Step 2: Update the service**

In `Sources/Services/AudioCaptureService.swift`, replace line 11:

```swift
    var onSamples: (([Float], Double) -> Void)?
```

with:

```swift
    var onSamples: (([Float], [Float], Double) -> Void)?
```

In the interleaved branch (lines 76–86 region), replace:

```swift
                let mono = downmixToMono(interleaved: interleaved, channelCount: ch)
                if !mono.isEmpty { handler?(mono, rate) }
```

with:

```swift
                let (left, right) = extractStereo(interleaved: interleaved, channelCount: ch)
                if !left.isEmpty { handler?(left, right, rate) }
```

In the non-interleaved branch (lines 87–106 region), replace the existing averaging loop:

```swift
                var mono = [Float](repeating: 0, count: frames)
                let inv = 1 / Float(channelPtrs.count)
                for f in 0..<frames {
                    var s: Float = 0
                    for ch in channelPtrs { s += ch[f] }
                    mono[f] = s * inv
                }
                handler?(mono, rate)
```

with:

```swift
                var left = [Float](repeating: 0, count: frames)
                var right = [Float](repeating: 0, count: frames)
                let lhs = channelPtrs[0]
                let rhs = channelPtrs.count >= 2 ? channelPtrs[1] : channelPtrs[0]
                for f in 0..<frames {
                    left[f] = lhs[f]
                    right[f] = rhs[f]
                }
                handler?(left, right, rate)
```

- [ ] **Step 3: Update the audio probe**

In `Sources/Services/AudioProbe.swift`, line 12, replace:

```swift
        service.onSamples = { samples, _ in
```

with:

```swift
        service.onSamples = { left, _, _ in
            let samples = left   // probe only needs one channel
```

(Add a closing `}` if needed — preserve the surrounding closure shape. The probe just records that audio is flowing.)

- [ ] **Step 4: Update RenderModel**

In `Sources/App/RenderModel.swift`, replace lines 39–50:

```swift
        capture.onSamples = { [weak self] samples, rate in
            guard let self else { return }
            self.dsp.async {
                if Float(rate) > 0, abs(Float(rate) - self.currentSampleRate) > 1 {
                    self.currentSampleRate = Float(rate)
                    self.analyzer.reconfigure(sampleRate: Float(rate))
                }
                if let frame = self.analyzer.append(samples) {
                    self.box.store(frame, at: CACurrentMediaTime())
                }
            }
        }
```

with:

```swift
        capture.onSamples = { [weak self] left, right, rate in
            guard let self else { return }
            self.dsp.async {
                if Float(rate) > 0, abs(Float(rate) - self.currentSampleRate) > 1 {
                    self.currentSampleRate = Float(rate)
                    self.analyzer.reconfigure(sampleRate: Float(rate))
                }
                if let frame = self.analyzer.append(left: left, right: right) {
                    self.box.store(frame, at: CACurrentMediaTime())
                }
            }
        }
```

- [ ] **Step 5: Build + test**

Run: `make build 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`.

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 195 tests still passing.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/AudioCaptureSource.swift Sources/Services/AudioCaptureService.swift Sources/Services/AudioProbe.swift Sources/App/RenderModel.swift
git commit -m "AudioCaptureSource: pass L/R channels instead of mono downmix"
```

---

## Phase 3 — Stereo consumers + settings (Tasks 11–15)

### Task 11: VisualizerSettings — remove fireworks fields, add useStereoImage

**Files:**
- Modify: `Sources/Core/VisualizerSettings.swift`
- Modify (extend): `Tests/CoreTests/VisualizerSettingsTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/CoreTests/VisualizerSettingsTests.swift`:

```swift
func testUseStereoImageDefaultsFalse() {
    XCTAssertEqual(VisualizerSettings.defaults.useStereoImage, false)
}

func testUseStereoImageRoundtrip() throws {
    var s = VisualizerSettings.defaults
    s.useStereoImage = true
    let data = try JSONEncoder().encode(s)
    let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
    XCTAssertTrue(decoded.useStereoImage)
}

func testLegacyJSONWithFireworksFieldsDecodesSafely() throws {
    let legacy = """
    {
      "visualizerStyle": "bars",
      "fireworksMinBass": 0.5,
      "fireworksMarginFloor": 0.1,
      "fireworksMarginScale": 0.5,
      "fireworksBaselineAlpha": 0.05,
      "demoModeEnabled": false,
      "siriWaveCount": 3,
      "particleSize": 1.0,
      "particleSpeed": 1.0,
      "barGap": 0.15,
      "oscilloscopeThickness": 1.0,
      "siriTiltSpacing": 0.18,
      "siriDepthFalloff": 0.25,
      "trailPersistence": 0,
      "fftWindow": "hann",
      "vignetteAmount": 0,
      "grainAmount": 0,
      "kaleidoscopeFolds": 0
    }
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: legacy)
    XCTAssertEqual(decoded.visualizerStyle, .bars)
    XCTAssertFalse(decoded.useStereoImage)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: build failure — `useStereoImage` not defined.

- [ ] **Step 3: Update the settings struct**

In `Sources/Core/VisualizerSettings.swift`:

1. Remove these four properties (lines 33–36):
   ```swift
   public var fireworksMinBass: Float
   public var fireworksMarginFloor: Float
   public var fireworksMarginScale: Float
   public var fireworksBaselineAlpha: Float
   ```

2. Add `public var useStereoImage: Bool` next to `trailPersistence` (or wherever the other Tweaks flags live).

3. In the `init(...)`:
   - Remove the four `fireworks*: Float` parameters.
   - Add `useStereoImage: Bool` parameter.
   - Remove the four `self.fireworks* = ...` assignments.
   - Add `self.useStereoImage = useStereoImage`.

4. In `static let defaults`:
   - Remove the four `fireworks*: 0.X,` argument lines.
   - Add `useStereoImage: false,` as a new argument.

5. In the `CodingKeys` enum:
   - Remove `case fireworksMinBass, fireworksMarginFloor, fireworksMarginScale, fireworksBaselineAlpha`.
   - Add `case useStereoImage`.

6. In `init(from decoder:)`:
   - Remove the four `let fmb = ... let fba = ...` lines.
   - Add `let usi = try c.decodeIfPresent(Bool.self, forKey: .useStereoImage) ?? d.useStereoImage`.
   - In the `self.init(...)` call: remove the four `fireworks*` arguments, add `useStereoImage: usi`.

7. In `encode(to:)`:
   - Remove the four `try c.encode(fireworks*, forKey: ...)` lines.
   - Add `try c.encode(useStereoImage, forKey: .useStereoImage)`.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 198 tests passing (195 + 3 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/VisualizerSettings.swift Tests/CoreTests/VisualizerSettingsTests.swift
git commit -m "Settings: remove fireworks beat tunables, add useStereoImage"
```

---

### Task 12: SpectrumBarsVisualizer stereo split

**Files:**
- Modify: `Sources/Core/SpectrumBarsVisualizer.swift`
- Modify (extend): `Tests/CoreTests/SpectrumBarsVisualizerTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/CoreTests/SpectrumBarsVisualizerTests.swift`:

```swift
func testStereoModeSplitsLeftRight() {
    var s = VisualizerSettings.defaults
    s.useStereoImage = true
    let L: [Float] = [Float](repeating: 0.8, count: 24)
    let R: [Float] = [Float](repeating: 0.0, count: 24)
    let bands: [Float] = (0..<24).map { _ in 0.4 }   // (L+R)/2
    let frame = AudioFrame(bands: bands, bandsLeft: L, bandsRight: R,
                           bandPeaks: bands, waveform: [],
                           rms: 0.3, peak: 0.8, timestamp: 0)
    let viz = SpectrumBarsVisualizer()
    let verts = viz.makeVertices(frame: frame, settings: s, aspect: 1)
    // With hard-left input, left-half bars should reach much higher than right-half.
    let leftMaxY = verts.filter { $0.position.x < 0 }.map(\.position.y).max() ?? -10
    let rightMaxY = verts.filter { $0.position.x >= 0 }.map(\.position.y).max() ?? -10
    XCTAssertGreaterThan(leftMaxY, rightMaxY + 0.1, "hard-left should drive only the left half")
}

func testStereoModeOffMatchesPriorBehavior() {
    var s = VisualizerSettings.defaults
    s.useStereoImage = false
    let bands: [Float] = (0..<24).map { Float($0) / 24 }
    let frame = AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                           rms: 0, peak: 0, timestamp: 0)
    let viz = SpectrumBarsVisualizer()
    let verts = viz.makeVertices(frame: frame, settings: s, aspect: 1)
    XCTAssertEqual(verts.count, 24 * 6)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: `testStereoModeSplitsLeftRight` fails — bars currently ignore `useStereoImage`.

- [ ] **Step 3: Implement stereo split in the visualizer**

Replace `Sources/Core/SpectrumBarsVisualizer.swift` with:

```swift
import simd

/// Classic spectrum bars: each band is a bottom-anchored bar with a vertical
/// palette gradient, plus an optional peak-hold cap.
///
/// When `settings.useStereoImage == true`: split the screen in half. The left
/// half displays `bandsLeft` (low-freq toward the edge), the right half
/// displays `bandsRight` (low-freq toward the edge). High frequencies meet at
/// the center.
public struct SpectrumBarsVisualizer: Visualizer {
    public init() {}

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        let count = frame.bands.count
        guard count > 0 else { return [] }
        let palette = ColorPalette.preset(named: settings.paletteName) ?? ColorPalette.preset(named: "classic")!

        if settings.useStereoImage {
            return emitStereo(frame: frame, settings: settings, palette: palette)
        }
        return emitMono(frame: frame, settings: settings, palette: palette)
    }

    private func emitMono(frame: AudioFrame, settings: VisualizerSettings, palette: ColorPalette) -> [BarVertex] {
        let count = frame.bands.count
        let layout = BarLayout(barCount: count, gapFraction: settings.barGap)
        var verts: [BarVertex] = []
        verts.reserveCapacity(count * (settings.peakHoldEnabled ? 12 : 6))
        for i in 0..<count {
            let level = min(max(frame.bands[i], 0), 1)
            let (xs, xe) = layout.barXRange(i)
            let x0 = xs * 2 - 1, x1 = xe * 2 - 1
            let yTop = -1 + 2 * level
            let cBottom = rgba(palette.sample(at: 0))
            let cTop = rgba(palette.sample(at: level))
            appendQuad(&verts, x0: x0, x1: x1, yLow: -1, yHigh: yTop, colorLow: cBottom, colorHigh: cTop)
            if settings.peakHoldEnabled {
                let peak = min(max(i < frame.bandPeaks.count ? frame.bandPeaks[i] : 0, 0), 1)
                let cap = -1 + 2 * peak
                let capColor = rgba(palette.sample(at: peak))
                appendQuad(&verts, x0: x0, x1: x1, yLow: cap - 0.01, yHigh: cap + 0.01, colorLow: capColor, colorHigh: capColor)
            }
        }
        return verts
    }

    private func emitStereo(frame: AudioFrame, settings: VisualizerSettings, palette: ColorPalette) -> [BarVertex] {
        let count = frame.bands.count
        // Each half hosts `count` bars across half the screen width.
        let layout = BarLayout(barCount: count, gapFraction: settings.barGap)
        var verts: [BarVertex] = []
        verts.reserveCapacity(count * 12)

        // Left half: bands[count-1] at far-left (low-freq edge), bands[0] near center (high-freq).
        // We iterate i = 0..<count placing index (count-1-i) on the left.
        for i in 0..<count {
            let leftIdx = count - 1 - i
            let level = min(max(frame.bandsLeft[leftIdx], 0), 1)
            let (xs, xe) = layout.barXRange(i)
            // Compress [0,1] to [-1, 0].
            let x0 = (xs - 1)   // xs * 1 - 1 == xs - 1; but we want [0..1] → [-1..0], so x0 = xs*1 - 1.
            let x1 = (xe - 1)
            let yTop = -1 + 2 * level
            let cBottom = rgba(palette.sample(at: 0))
            let cTop = rgba(palette.sample(at: level))
            appendQuad(&verts, x0: x0, x1: x1, yLow: -1, yHigh: yTop, colorLow: cBottom, colorHigh: cTop)
        }
        // Right half: bands[0] near center, bands[count-1] far right.
        for i in 0..<count {
            let level = min(max(frame.bandsRight[i], 0), 1)
            let (xs, xe) = layout.barXRange(i)
            // Compress [0,1] to [0, 1] (NDC right half).
            let x0 = xs
            let x1 = xe
            let yTop = -1 + 2 * level
            let cBottom = rgba(palette.sample(at: 0))
            let cTop = rgba(palette.sample(at: level))
            appendQuad(&verts, x0: x0, x1: x1, yLow: -1, yHigh: yTop, colorLow: cBottom, colorHigh: cTop)
        }
        return verts
    }

    private func rgba(_ c: RGBAColor) -> SIMD4<Float> { SIMD4<Float>(c.r, c.g, c.b, c.a) }

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

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 200 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/SpectrumBarsVisualizer.swift Tests/CoreTests/SpectrumBarsVisualizerTests.swift
git commit -m "SpectrumBars: split L/R when useStereoImage is on (low→edge)"
```

---

### Task 13: RadialSpectrumVisualizer pan offset

**Files:**
- Modify: `Sources/Core/RadialSpectrumVisualizer.swift`
- Modify (extend): `Tests/CoreTests/RadialSpectrumVisualizerTests.swift`

- [ ] **Step 1: Inspect current center math**

Open `Sources/Core/RadialSpectrumVisualizer.swift` and find where the visualizer establishes its center — typically `SIMD2<Float>(0, 0)` or `cx, cy` locals near the top of `makeVertices`.

- [ ] **Step 2: Write the failing test**

Append to `Tests/CoreTests/RadialSpectrumVisualizerTests.swift`:

```swift
func testStereoPanOffCentersAtZero() {
    var s = VisualizerSettings.defaults
    s.useStereoImage = false
    let bands = [Float](repeating: 0.5, count: 32)
    let f = AudioFrame(bands: bands, bandsLeft: bands, bandsRight: bands,
                       bandPeaks: bands, waveform: [], rms: 0, peak: 0, timestamp: 0)
    let viz = RadialSpectrumVisualizer()
    let verts = viz.makeVertices(frame: f, settings: s, aspect: 1)
    // Center of mass of the X positions should be near 0.
    let mean = verts.map(\.position.x).reduce(0, +) / Float(verts.count)
    XCTAssertEqual(mean, 0, accuracy: 0.05)
}

func testStereoPanHardLeftShiftsCenterNegative() {
    var s = VisualizerSettings.defaults
    s.useStereoImage = true
    let L = [Float](repeating: 0.8, count: 32)
    let R = [Float](repeating: 0.0, count: 32)
    let bands = zip(L, R).map { ($0 + $1) / 2 }
    let f = AudioFrame(bands: bands, bandsLeft: L, bandsRight: R,
                       bandPeaks: bands, waveform: [], rms: 0, peak: 0, timestamp: 0)
    let viz = RadialSpectrumVisualizer()
    let verts = viz.makeVertices(frame: f, settings: s, aspect: 1)
    let mean = verts.map(\.position.x).reduce(0, +) / Float(verts.count)
    XCTAssertLessThan(mean, -0.02)
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: `testStereoPanHardLeftShiftsCenterNegative` fails — radial currently ignores `useStereoImage`.

- [ ] **Step 4: Implement the pan offset**

In `Sources/Core/RadialSpectrumVisualizer.swift`, after line 18 (`if aspect >= 1 { sx = 1 / aspect } else { sy = aspect }`) and before line 20 (`let angularHalf = ...`), insert:

```swift

        var centerOffsetX: Float = 0
        if settings.useStereoImage {
            let lSum = frame.bandsLeft.reduce(0, +)
            let rSum = frame.bandsRight.reduce(0, +)
            let total = max(lSum + rSum, 1e-6)
            centerOffsetX = 0.15 * (rSum - lSum) / total
            centerOffsetX = max(-0.15, min(0.15, centerOffsetX))
        }
```

Then replace the `point(_:_:)` helper (lines 24–26):

```swift
        func point(_ r: Float, _ a: Float) -> SIMD4<Float> {
            SIMD4<Float>(r * cosf(a) * sx, r * sinf(a) * sy, 0, 1)
        }
```

with:

```swift
        func point(_ r: Float, _ a: Float) -> SIMD4<Float> {
            SIMD4<Float>(r * cosf(a) * sx + centerOffsetX, r * sinf(a) * sy, 0, 1)
        }
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 202 tests passing (200 + 2 new).

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/RadialSpectrumVisualizer.swift Tests/CoreTests/RadialSpectrumVisualizerTests.swift
git commit -m "RadialSpectrum: pan center by ±0.15 with stereo balance when enabled"
```

---

### Task 14: SiriWaveVisualizer stereo tilt

**Files:**
- Modify: `Sources/Core/SiriWaveVisualizer.swift`
- Modify (extend): `Tests/CoreTests/SiriWaveVisualizerTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/CoreTests/SiriWaveVisualizerTests.swift`:

```swift
func testStereoTiltShiftsHorizontalCenter() {
    var s = VisualizerSettings.defaults
    s.useStereoImage = true
    let L = [Float](repeating: 0.9, count: 32)
    let R = [Float](repeating: 0.1, count: 32)
    let bands = zip(L, R).map { ($0 + $1) / 2 }
    let f = AudioFrame(bands: bands, bandsLeft: L, bandsRight: R,
                       bandPeaks: bands, waveform: [], rms: 0, peak: 0, timestamp: 0)
    let viz = SiriWaveVisualizer(seed: 31)
    _ = viz.makeVertices(frame: f, settings: s, aspect: 1)
    let verts = viz.makeVertices(frame: f, settings: s, aspect: 1)
    XCTAssertGreaterThan(verts.count, 0)
    // Left-dominant input should pull the left edge of vertex X-range
    // further negative than a balanced input would.
    let minX = verts.map(\.position.x).min() ?? 0
    let maxX = verts.map(\.position.x).max() ?? 0
    let center = (minX + maxX) / 2
    // With pan tilt active, the center of the wave extent shifts away from 0.
    XCTAssertLessThan(center, -0.001, "expected left-pan shift, got center=\(center)")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: test fails — siri ignores `useStereoImage`.

- [ ] **Step 3: Add pan-tilt component**

In `Sources/Core/SiriWaveVisualizer.swift`, after line 49 (`lastTimestamp = frame.timestamp`) and before line 51 (the comment about per-wave EMA), insert:

```swift

        var panOffsetX: Float = 0
        if settings.useStereoImage {
            let lSum = frame.bandsLeft.reduce(0, +)
            let rSum = frame.bandsRight.reduce(0, +)
            let total = max(lSum + rSum, 1e-6)
            // ±15° of tilt translates into ~tan(15°) ≈ 0.27 NDC at the screen edge.
            // We shift the whole wave's horizontal centerline by this amount.
            panOffsetX = 0.27 * (rSum - lSum) / total
            panOffsetX = max(-0.27, min(0.27, panOffsetX))
        }
```

Then in the per-segment emission loop (lines 110–125), replace lines 115–118:

```swift
                let p00 = SIMD4<Float>(x0, yBase, 0, 1)
                let p10 = SIMD4<Float>(x1, yBase, 0, 1)
                let p0y = SIMD4<Float>(x0, yBase + y0, 0, 1)
                let p1y = SIMD4<Float>(x1, yBase + y1, 0, 1)
```

with:

```swift
                let p00 = SIMD4<Float>(x0 + panOffsetX, yBase, 0, 1)
                let p10 = SIMD4<Float>(x1 + panOffsetX, yBase, 0, 1)
                let p0y = SIMD4<Float>(x0 + panOffsetX, yBase + y0, 0, 1)
                let p1y = SIMD4<Float>(x1 + panOffsetX, yBase + y1, 0, 1)
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 203 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/SiriWaveVisualizer.swift Tests/CoreTests/SiriWaveVisualizerTests.swift
git commit -m "SiriWave: pan-tilt the wave horizontally with L/R balance"
```

---

### Task 15: SettingsView UI — remove fireworks sliders, add stereo toggle

**Files:**
- Modify: `Sources/App/SettingsView.swift`

- [ ] **Step 1: Locate and remove the fireworks sliders**

Run:

```bash
grep -n "fireworksMinBass\|fireworksMargin\|fireworksBaselineAlpha" Sources/App/SettingsView.swift
```

Each hit is a slider row referencing the now-removed setting. Delete those rows. Typical pattern:

```swift
Slider(value: Binding(get: { settings.fireworksMinBass }, set: { settings.fireworksMinBass = $0 }), in: 0...0.5)
    .frame(width: 180)
Text("Min bass")
```

Remove the full row each time, including any surrounding `HStack { ... }` if it wraps only those sliders. Delete any "Fireworks beat" section header that becomes empty as a result.

- [ ] **Step 2: Add the stereo toggle to the Tweaks tab**

Find the Tweaks tab content (look for `siriTiltSpacing`, `vignetteAmount`, etc., grouped under a "Tweaks" Picker/`TabView` tag). Add at the bottom of that section:

```swift
Toggle("Use stereo image", isOn: Binding(
    get: { settings.useStereoImage },
    set: { settings.useStereoImage = $0 }
))
.help("Bars, Radial, and Siri respond to L–R balance when enabled.")
```

- [ ] **Step 3: Build the app**

Run: `make build 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the tests**

Run: `make test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **` with 203 tests still passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/SettingsView.swift
git commit -m "SettingsView: remove fireworks beat sliders, add Use stereo image toggle"
```

---

## Final integration

### Task 16: Full-suite verification + summary

**Files:**
- (none — verification only)

- [ ] **Step 1: Run a clean build**

Run: `make clean 2>&1 | tail -3 && make build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Run the full test suite**

Run: `make test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -3`
Expected: `Executed 203 tests, with 0 failures` (or close — small variations OK if tests were merged/renamed).

- [ ] **Step 3: Manual smoke check (optional, ask user to run)**

The user runs the app, plays music, and verifies:
- Fireworks fire on actual beats (not just on every loud burst)
- Particles pulse larger on beats
- Fountain spikes higher on beats
- Toggling "Use stereo image" on the Tweaks tab visibly changes Bars (split L/R), Radial (center shifts), and Siri (wave pans). Toggling off restores prior behavior.

- [ ] **Step 4: Verify branch state**

Run:

```bash
git log --oneline plan-17-cluster-a-audio-foundations ^main | head -20
```

Expected: ~15 commits — one per task plus the spec commit at the start.

---

## Out of scope (deferred to later clusters)

- Cluster B — Feedback-warp post-process + Reflected floor + RMS hue rotate.
- Cluster C — Barycentric-edge wireframe + Multi-band siri.
- Cluster D — Joy-Division plot + Heightfield grid + Voronoi cells (+ maybe Lava lamp).
- Cluster E — Visualizer crossfade + Perlin organic drift.
