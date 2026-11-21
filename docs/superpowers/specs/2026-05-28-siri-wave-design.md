# Siri-Wave Visualizer Style — Design

- **Date:** 2026-05-28
- **Status:** Approved design (pre-implementation)
- **Audience:** Personal use, single developer
- **Target OS:** macOS 14.4+ (unchanged)

## 1. Goal

Add an 8th visualizer style — **`siri`** — that draws a stack of centered overlapping smooth waves (Siri-assistant inspired). Each wave is bound to a contiguous group of frequency bands; its amplitude tracks that group's energy, its phase wanders via 1-D noise so motion feels organic. The on-screen layout is a centered horizontal ribbon (waves all centered at y=0, ±~40% height), drawn as filled colored shapes with the existing bloom providing the glow.

After this change, `VisualizerStyle.allCases` is 8: bars, radial, mirrored, oscilloscope, particles, fountain, fireworks, **siri**.

## 2. Background / current state

- `Visualizer` protocol: `func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex]`. Existing stateful conformers (`ParticleVisualizer`, `SpectrumFountainVisualizer`, `FireworksVisualizer`) follow the same pattern: a `final class` carrying a seeded RNG and `lastTimestamp` for derived `dt`.
- `VisualizerStyle` (`String`, `Codable`, `CaseIterable`) drives the menu, ⌘]/⌘[, and the Settings picker. Adding a case auto-extends those.
- `usesRoundParticles: Bool` on `VisualizerStyle` selects the soft-circle fragment shader for particle styles. The siri style uses sharp filled triangles, so this is `false`.
- The bloom pipeline applies to any rendered geometry — siri waves will glow.
- `VisualizerSettings` already has a precedent for **single-style tunables that live top-level** (the four `fireworks*` Float fields). The siri wave count uses the same pattern.

## 3. Non-goals

- No alpha-blending or additive-blending pipeline changes (the existing bloom is sufficient for visual cohesion; if the overlap looks muddy in practice it's a follow-up, not part of this work).
- No per-wave audio routing UI (the spectrum split is automatic by group).
- No full-screen layout option (centered-ribbon only; `1–6 wave count` is the only configurable knob).
- No fancy noise library — a small inline 1-D value-noise function (linear interpolation between RNG samples) is enough for "phases drift smoothly."
- No new palettes; existing classic/phosphor/synthwave are reused.

## 4. Decisions (locked)

| Area | Decision |
| --- | --- |
| Layout | **Centered ribbon** — all waves centered at y=0 in NDC, capped at ±~0.4 height |
| Wave count | **Configurable 1–6** via a new `siriWaveCount: Int` top-level setting (default 3) |
| Audio mapping | Bands are split into N **equal contiguous groups**; each wave's amplitude = mean of its group's smoothed band levels |
| Per-wave smoothing | Lightweight per-wave EMA inside the visualizer (`smoothing ≈ 0.7`) so the amplitude follows but doesn't twitch |
| Wave shape | Two-sine sum: `y(x) = (sin(x·f1 + φ1) + sin(x·f2 + φ2)) / 2 · amp · heightCap` — `f1`/`f2` per wave (offset so waves don't perfectly align); `φ1`/`φ2` are 1-D noise-modulated |
| Phase noise | Per-wave, per-sine; advances at a slow rate (`noiseSpeed ≈ 0.4 rad/s`), via a tiny inline value-noise function. Deterministic given a seeded RNG so tests can pin behavior. |
| Render | **Filled ribbon** between the curve and y=0, sampled at `S = 256` x-points across `[-1, +1]`. 256 segments × 6 verts/segment = 1536 verts per wave. With 6 waves max, vertex budget = 9216 — well within tolerances |
| Colors | Each wave i takes its color from `palette.sample(at: i / max(N-1, 1))`. So 3 waves with the classic palette = bottom→top sweep through the palette gradient. |
| Setting placement | `siriWaveCount: Int` as a **top-level** flat field on `VisualizerSettings` (same pattern as `fireworksMinBass`); not duplicated into every `StyleProfile` |
| Settings UI | New **"Siri" tab** in the tabbed Settings, containing the wave-count stepper |
| `usesRoundParticles` | **false** for `.siri` (sharp filled triangles, no circular mask) |
| Determinism | Seeded `SeededRNG` (xorshift64, duplicated from `FireworksVisualizer.swift`); reset on construction so live-mode and tests are reproducible |

## 5. Architecture

### 5.1 New file: `Sources/Core/SiriWaveVisualizer.swift`

```
public final class SiriWaveVisualizer: Visualizer {
    private struct Wave {
        var amplitude: Float        // smoothed band-group mean (per wave)
        let baseFreq1: Float        // sine 1 base frequency in radians per NDC unit
        let baseFreq2: Float        // sine 2 base frequency
        let noiseSeed1: UInt64      // distinct seeds per sine per wave
        let noiseSeed2: UInt64
    }

    private var waves: [Wave] = []
    private var lastWaveCount: Int = 0       // recompute waves[] when N changes
    private var lastTimestamp: CFTimeInterval = 0
    private var phaseTime: Double = 0        // accumulator advanced by dt
    private var rng: SeededRNG

    public init(seed: UInt64 = 0xC0DE) { self.rng = SeededRNG(seed: seed) }

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        let n = clamp(settings.siriWaveCount, lo: 1, hi: 6)
        if n != lastWaveCount { rebuild(n: n) }   // assign per-wave freqs + seeds

        // dt-based phase advance (advance even when amplitude is 0, so motion never stops).
        let dt = max(0, frame.timestamp - lastTimestamp)
        lastTimestamp = frame.timestamp
        phaseTime += min(dt, 0.1) * noiseSpeed   // clamp dt so long pauses don't jump

        // Per-wave band-group amplitude (smoothed EMA).
        for i in 0..<n {
            let target = groupMean(bands: frame.bands, group: i, total: n) * gainMul
            waves[i].amplitude += smoothing * (target - waves[i].amplitude)
        }

        // Sample each wave at S points, emit triangle-strip-equivalent quads.
        var verts: [BarVertex] = []
        verts.reserveCapacity(n * (S - 1) * 6)
        let palette = Palette.named(settings.paletteName, customStops: settings.customStops)
        for i in 0..<n {
            let colorPos = n == 1 ? 0.5 : Float(i) / Float(n - 1)
            let c = palette.sample(at: colorPos)
            let color = SIMD4<Float>(c.r, c.g, c.b, 1)
            // ... sample y_j = waveValue(at: x_j, wave: i, t: phaseTime) ...
            // ... emit two triangles per (j, j+1) segment between (x, 0) and (x, y).
        }
        return verts
    }

    // Tunables
    private let S = 256
    private let smoothing: Float = 0.7
    private let gainMul: Float = 1.2
    private let heightCap: Float = 0.40
    private let noiseSpeed: Double = 0.4
}

private func waveValue(at x: Float, wave: SiriWaveVisualizer.Wave, t: Double) -> Float
private func value1D(_ x: Double, seed: UInt64) -> Float  // inline value-noise
private struct SeededRNG  // xorshift64, duplicated
```

### 5.2 1-D noise helper (inline)

A 32-bit-deterministic value-noise function: hash `(floor(x), seed)` to a unit float, linearly interpolate between hashes at `x` and `x+1`. Output is smooth, deterministic for any seed, and cheap. ~25 lines.

```
private func value1D(_ x: Double, seed: UInt64) -> Float {
    let xi = floor(x)
    let xf = Float(x - xi)
    let i = UInt64(bitPattern: Int64(xi))
    let a = hashToUnit(i,     seed: seed)
    let b = hashToUnit(i &+ 1, seed: seed)
    // Smoothstep for cosine-ish interpolation.
    let u = xf * xf * (3 - 2 * xf)
    return a * (1 - u) + b * u
}
```

The noise drives the phase modulation: `φ_k = value1D(t, seed_k) * 2π`. Combined with the slow `phaseTime` advance, each wave wanders organically.

### 5.3 `VisualizerStyle` (modify)

- Add `case siri` after `.fireworks`. `String` raw value `"siri"`.
- `displayName`: `"Siri"`.
- `makeVisualizer()`: `return SiriWaveVisualizer()`.
- `usesRoundParticles` for `.siri`: `false`.
- `next` / `previous` continue to work via `allCases`.

### 5.4 `VisualizerSettings` (modify)

Add a top-level Int field with tolerant codec — same pattern as the `fireworks*` Float fields.

```
public var siriWaveCount: Int    // 1...6, default 3
```

Five wiring sites: stored property, init parameter, `defaults` entry, `CodingKeys` case, `init(from:)` decode (with `?? d.siriWaveCount` default), `encode(to:)` line.

### 5.5 `SettingsView` (modify)

Add a new tab `Siri` to the `TabView` (after Fireworks). Contents:

```
Form {
    Section {
        Text("These knobs apply only when the active style is Siri. Drag during music to dial in wave count and motion.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
    Section("Waves") {
        Stepper("Wave count: \(model.settings.siriWaveCount)",
                value: $model.settings.siriWaveCount,
                in: 1...6)
    }
}
.formStyle(.grouped)
```

Tab item: `Label("Siri", systemImage: "waveform.path")`.

The tab is always visible (consistent with the Fireworks tab pattern), with a footer note explaining the scope.

### 5.6 Reset semantics

The existing "Reset This Style" button on Settings:
- When current style is `.siri`, also resets `settings.siriWaveCount` to `VisualizerSettings.defaults.siriWaveCount = 3` (mirroring how Reset This Style on Fireworks also resets the fireworks tunables).

"Reset All Styles" already does `settings = .defaults`, which restores `siriWaveCount` automatically.

## 6. Testing strategy

**Unit-tested (Core):**
- `VisualizerStyle.allCases.count == 8`.
- `.siri.displayName == "Siri"`, `.siri.makeVisualizer() is SiriWaveVisualizer`, `.siri.usesRoundParticles == false`.
- `.fireworks.next == .siri`; `.siri.next == .bars`; `.bars.previous == .siri`.
- `VisualizerSettings.defaults.siriWaveCount == 3`.
- `siriWaveCount` round-trips through JSON.
- `siriWaveCount` is defaulted from a partial JSON missing the key.
- `SiriWaveVisualizer` with the same seed + identical frames produces identical vertex output.
- After a single `makeVertices` call, the emitted vertex count equals `n * (S - 1) * 6` where `n = settings.siriWaveCount` and `S = 256`.
- Vertex positions are all within the clip-space box `[-1.2, +1.2]` (margin to allow for amplitude overshoot — heightCap=0.4 so worst case ~0.4 magnitude).
- Higher band energy in a given group produces taller waves: feed a frame with `bands[loGroup] = 1.0` for the low group and zeros elsewhere; after several frames (smoothing converges), the maximum |y| in the rendered low-group vertices > the maximum |y| in mid/high-group vertices.

**Verified by running:**
- `--render-probe /tmp/p_siri.png siri` produces a valid PNG with centered colored waves visible.
- Live: switching to `.siri` via menu/⌘]/picker shows three (or N) flowing waves on music.
- Reset This Style on `.siri` returns wave count to 3.
- Reset All Styles restores siri among the other styles.

## 7. Risks & mitigations

- **Visual muddiness** — overlapping filled ribbons can become "mush" when amplitudes are high and waves cross. *Mitigation:* the per-wave color gradient and bloom should keep them readable; if not, add additive-blend pipeline in a follow-up.
- **Vertex count** — 6 waves × 255 segments × 6 verts = 9180 verts per frame. The renderer's grow-only vertex buffer (Plan 5) handles this without per-frame allocation. Within Metal's tolerances.
- **Per-call settings access** — `settings.siriWaveCount` changes can race with `makeVertices` if Settings UI mutates mid-frame. The renderer reads from `model.settings` on the main thread (same as bars / etc.), so no actual race. Recreating `waves[]` only when the count changes is a cheap branch.
- **Noise function smoothness** — value-noise with linear interp can have hash artifacts. *Mitigation:* the `smoothstep` curve on the fractional part softens the corners; if it still looks jaggy, swap for cubic Hermite interp (5-line change).
- **Centered-ribbon constraint feels limiting** — for the worst-case "all waves silent except one big spike" frame, only one ribbon shows. Acceptable; the user can switch to bars/oscilloscope for different layouts.

## 8. Out of scope / future
- Additive / alpha-blended pipeline state for siri (improves overlap if needed).
- Full-screen vs centered layout option (already brainstormed, deliberately kept as centered-only for v1).
- Per-wave color customization (uses palette gradient automatically).
- Sub-bass-through-brilliance 6-band split (VisuAc's specific EQ split) — current design uses equal contiguous groups for simplicity + configurability.
- Mouse / drag interaction for live wave manipulation (could be a fun "demo mode" extension).
