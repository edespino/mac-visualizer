# Cluster A — Audio Foundations — Design

**Date:** 2026-05-29
**Branch:** `plan-17-cluster-a-audio-foundations`
**Source:** Tier-1 items #1 (shared beat detector) + #3 (stereo-aware analysis) from the 2026-05-28 visuals-repo deep-dive.

## Goal

Add two foundational audio-analysis capabilities that downstream visualizers can opt into:

1. **Shared beat detector** — replace the bespoke threshold-on-bass logic in `FireworksVisualizer` with a self-tuning detector available to every visualizer via `AudioFrame.beat` / `beatIntensity`.
2. **Stereo-aware analysis** — stop downmixing to mono at the FFT boundary; expose per-channel band arrays so visualizers can show the stereo image of the spectrum.

This cluster is the foundation for Tier-1 #6 (crossfade — wants a real onset trigger) and Tier-2 #11 (Perlin drift — wants beat-modulated drift), shipped in later clusters.

## Architecture

Two parallel changes, both inside the `Sources/Core/` audio pipeline:

- **Beat path:** New `BeatDetector` service. `SpectrumAnalyzer` calls `BeatDetector.update(peak:)` once per frame and attaches the result to `AudioFrame`.
- **Stereo path:** Stop calling `downmixToMono(...)` upfront. `SpectrumAnalyzer` runs FFT for L and R channels separately; the mono `bands` field becomes the element-wise mean.

Consumers (visualizers) read the new fields from `AudioFrame` directly. No new protocol surface.

## Component 1 — `BeatDetector`

### File
`Sources/Core/BeatDetector.swift` (new, ~150 LOC including comments + tests fixture data)

### Algorithm — clean-room reimplementation inspired by goom2k4 `sound_tester.c`

State:
- `accelvar: Float` — current aged loudness (acceleration of envelope)
- `prevAccel: Float` — previous frame's aged loudness (for delta detection)
- `goomLimit: Float` — adaptive threshold (starts at 1.0, auto-tunes)
- `goomDetected: Bool` — true on the frame the onset fires
- `cycleTime: Int` — frame counter within the 64-frame tuning window
- `totalGoom: Int` — onsets fired so far in the current window
- `lastBeatTimestamp: CFTimeInterval` — for refractory enforcement

Constants (mirror goom2k4 with units adapted to our 0…1 peak range):
- `cycleLength: Int = 64` — tune window length in frames
- `targetGoomsPerWindow: Int = 4` — ~3 onsets/sec at our 60 fps
- `goomLimitFloor: Float = 0.05` — minimum threshold
- `goomLimitDecay: Float = 0.91` — multiplicative decay each tuning cycle if too few onsets
- `goomLimitGrowth: Float = 1.1` — multiplicative growth each tuning cycle if too many onsets
- `accelDecay: Float = 0.91` — aged loudness decay per frame
- `refractorySeconds: CFTimeInterval = 0.15` — minimum gap between consecutive beats

Per-frame logic (`update(peak: Float, timestamp: CFTimeInterval)`):

```
// 1. Age the loudness envelope.
let target = peak
accelvar = max(accelvar * accelDecay, target)

// 2. Onset = delta exceeds adaptive limit AND outside refractory window.
let delta = accelvar - prevAccel
let refractoryOK = timestamp - lastBeatTimestamp >= refractorySeconds
goomDetected = (delta > goomLimit) && refractoryOK
if goomDetected {
    totalGoom += 1
    lastBeatTimestamp = timestamp
}
prevAccel = accelvar

// 3. Every cycleLength frames, retune goomLimit.
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
```

### Output API

```swift
public final class BeatDetector {
    public init()
    public func reset()
    public mutating func update(peak: Float, timestamp: CFTimeInterval) -> (beat: Bool, intensity: Float)
}
```

`intensity` returned as `min(1, max(0, delta / max(goomLimit, 0.01)))` when `goomDetected == true`, else `0`. Per-frame onset magnitude in 0…1 (one-shot, not a continuous reading).

### Tests

`Tests/CoreTests/BeatDetectorTests.swift` (new):
- **Silence:** 200 frames of `peak == 0` → 0 beats fired
- **Steady tone:** 200 frames of constant `peak == 0.7` → 0 beats fired (no onsets, only steady level)
- **Synthetic 120 BPM kicks:** sine-decay envelope every 0.5s for 4 seconds → beats fire on each kick within ±1 frame
- **Auto-tune up:** start with `goomLimit = 5.0` (too high) and feed real kicks; assert it decays below 1.0 within 4 windows
- **Auto-tune down:** feed continuous noise; assert it grows to suppress all detections after 4 windows
- **Refractory:** two onsets 0.05s apart → only first fires

## Component 2 — `AudioFrame` schema extension

### File
`Sources/Core/AudioFrame.swift` (modify)

### New fields

```swift
public struct AudioFrame: Sendable {
    public let bands: [Float]
    public let bandsLeft: [Float]         // NEW — same length as `bands`
    public let bandsRight: [Float]        // NEW — same length as `bands`
    public let bandPeaks: [Float]
    public let waveform: [Float]
    public let rms: Float
    public let peak: Float
    public let beat: Bool                 // NEW
    public let beatIntensity: Float       // NEW — 0…1
    public let timestamp: CFTimeInterval
}
```

### Invariants
- `bands.count == bandsLeft.count == bandsRight.count`
- `bands[i] == (bandsLeft[i] + bandsRight[i]) / 2` for all i (preserves existing visualizer behavior bit-for-bit on mono sources where `bandsLeft == bandsRight`)
- On frames where no onset fires: `beat == false` AND `beatIntensity == 0`. `beatIntensity` is only non-zero on the single frame an onset fires; it is NOT a continuous "current energy" reading. Consumers wanting decay must implement it themselves.

### Mono fallback
For sources that don't produce stereo (legacy code paths, synthetic test frames, `DemoAudioSource`), `bandsLeft = bandsRight = bands`. The mean invariant holds trivially.

### Default initializer

Add convenience initializer that takes only mono `bands` and synthesizes `bandsLeft = bandsRight = bands` so existing test code continues to compile without modification:

```swift
public init(bands: [Float], bandPeaks: [Float], waveform: [Float],
            rms: Float, peak: Float, timestamp: CFTimeInterval,
            beat: Bool = false, beatIntensity: Float = 0)
```

This forwards to a full initializer that takes `bandsLeft` + `bandsRight` explicitly for the production path.

### Tests

`Tests/CoreTests/AudioFrameTests.swift` (extend existing):
- Mean invariant holds for arbitrary L/R inputs
- Convenience initializer produces `left == right == bands`
- Default values for `beat` / `beatIntensity` are `false` / `0`

## Component 3 — `SpectrumAnalyzer` stereo path

### File
`Sources/Core/SpectrumAnalyzer.swift` (modify)

### Current behavior (single-channel)
Takes interleaved PCM, downmixes via `downmixToMono(...)` in `AudioDownmix.swift`, runs vDSP FFT, produces `bands`.

### New behavior (dual-channel)
Deinterleave to L and R buffers. Run FFT separately on each. Produce `bandsLeft` and `bandsRight`. Compute `bands = (bandsLeft + bandsRight) / 2`. Pass `peak` (the max of L/R peaks) to `BeatDetector`.

### Performance
Doubles the FFT cost. Our current FFT is on 1024-sample windows at 60 fps — well within budget. No need to optimize.

### Mono input handling
If the input PCM only has one channel (mono file), treat L == R. Cheaper path: skip the second FFT, just copy.

### Tests

`Tests/CoreTests/SpectrumAnalyzerStereoTests.swift` (new):
- Mono PCM input → `bandsLeft == bandsRight == bands` (bit-equality)
- Hard-left PCM (silence on R) → `bandsRight` all near zero, `bandsLeft` non-zero, `bands` half of L
- Hard-right PCM → mirror of above
- Stereo PCM with known per-channel content → correct band assignment per channel

### Golden-value regression
`Tests/CoreTests/SpectrumAnalyzerTests.swift` (existing):
- Feed the existing golden synthetic mono inputs
- Assert `bands` output is bit-identical to pre-change values (because mean of two equal arrays equals each array)

## Component 4 — Beat consumers

### `FireworksVisualizer`

**Remove:** `baseline`, `lastBeatTime`, `refractoryPeriod`, `burstHalfX`/`burstHalfY` stay, all the `computeBass` / `effectiveMargin` logic.

**Add:** `if frame.beat { spawnBurst(intensity: frame.beatIntensity) }`

**Adjust** `spawnBurst` to scale `burstParticles`, `baseSpeed`, and per-particle lifetime by `0.7 + 0.6 * intensity` — gives quieter onsets smaller bursts and louder onsets bigger bursts.

### `ParticleVisualizer`

**Add:** on `frame.beat`, multiply the next frame's particle radius and outward velocity by `1 + 0.5 * beatIntensity`. Decay the boost over ~150 ms via a simple `Float` field that decays each frame.

### `SpectrumFountainVisualizer`

**Add:** on `frame.beat`, multiply `launchScale` by `1 + 0.4 * beatIntensity` for that frame's spawn. No persistent state; the visual effect is a per-beat surge.

### Settings cleanup

Remove from `VisualizerSettings.swift`:
- `fireworksMinBass: Float`
- `fireworksMarginFloor: Float`
- `fireworksMarginScale: Float`
- `fireworksBaselineAlpha: Float`

These were tunables specific to the old hand-rolled detector. The tolerant Codable decoder already ignores unknown fields, so existing user `UserDefaults` snapshots decode cleanly.

Remove the corresponding sliders from `SettingsView.swift` (the Fireworks row in the Audio tab — currently four sliders).

### Tests
`Tests/CoreTests/FireworksVisualizerTests.swift` (modify existing):
- Update existing tests that injected synthetic `bandPeaks` to instead inject `AudioFrame(beat: true, beatIntensity: 0.8, …)` and assert a burst spawned
- Add: `beat: false` produces no burst regardless of bass content
- Add: `beatIntensity: 0.1` (quiet onset) produces fewer particles than `beatIntensity: 0.9`

## Component 5 — Stereo consumers

### Settings — global stereo toggle

Add to `VisualizerSettings.swift`:
```swift
public var useStereoImage: Bool = false   // default off — opt-in
```

Add to `SettingsView.swift` Tweaks tab: single toggle "Use stereo image" with subtitle "Bars / Radial / Siri respond to L–R balance".

### `BarsVisualizer` stereo mode

When `useStereoImage == false`: current behavior (one band per bar across full width).

When `useStereoImage == true`:
- Left half of screen displays `bandsLeft[0..<count]` bars rising from bottom
- Right half displays `bandsRight[0..<count]` bars rising from bottom (mirrored — high-freq toward center, low toward edge, OR low toward center — pick at spec time below)

**Mirror direction:** low-freq toward the edges, high-freq toward the center. Visually echoes traditional stereo VU meters. (If wrong at first sight in implementation, a one-line index reversal flips it.)

### `RadialSpectrumVisualizer` pan offset

When `useStereoImage == false`: current behavior (centered).

When `useStereoImage == true`: shift center X by `0.15 * normalize(R−L, R+L)` where `normalize` is `(R−L) / max(R+L, 0.001)`. Clamp to ±0.15 normalized screen units. Pan only — no Y offset, no scale change.

Compute L/R aggregate from `frame.bandsLeft.reduce(0, +)` and `frame.bandsRight.reduce(0, +)`. Plain sum, not RMS.

### `SiriWaveVisualizer` stereo tilt

When `useStereoImage == false`: current behavior (uniform tilt from settings).

When `useStereoImage == true`: add a horizontal tilt component proportional to L/R balance. Add `±15°` of pan tilt on top of the existing front-back tilt. Compute from `bandsLeft.reduce(0, +)` / `bandsRight.reduce(0, +)` sums (same as radial).

### Tests
- **BarsVisualizer:** `useStereoImage = true` + hard-left PCM → right-half bars are near zero, left-half bars are non-zero
- **RadialVisualizer:** `useStereoImage = true` + balanced input → center stays centered (offset == 0). Hard-left input → center.x shifts negative.
- **SiriWaveVisualizer:** similar pan test

## Settings codec

`VisualizerSettings.swift` already uses tolerant Codable (decodeIfPresent + defaults). The four removed fireworks fields decode-skip on existing user snapshots; the new `useStereoImage` field defaults to `false` on legacy snapshots. No migration code needed beyond field deletion.

## Risks and trade-offs

1. **Beat detector tuning may need iteration.** goom2k4's constants were chosen for its specific peak-amplitude range; ours is 0…1 from vDSP. Ship with the constants above and tune visually. The tests use canned 120-BPM kicks which should be unambiguous.

2. **Fireworks visual character may shift.** The bespoke detector fires more aggressively (no auto-tune ceiling); goom2k4 will fire less on dense music. Mitigation: ship as a feature change, expect to retune burstParticles count and lifetime if too sparse.

3. **Stereo bars layout is novel.** Two acceptable layouts (high-to-center vs high-to-edge). Locked the recommended one above; if it looks wrong, a single line edit flips it.

4. **Doubled FFT cost.** ~1% extra CPU at 60 fps. Not a concern at our window sizes.

5. **Default off for `useStereoImage`.** Avoids surprising users on update. The setting needs to be discoverable — Tweaks tab placement should be prominent.

## Non-goals

- Beat detector knobs in UI (no `targetRate` slider, etc.). The whole point is self-tuning.
- Beat consumers in plasma, bumpscope, wireframe, oscilloscope, mirrored. They can adopt `frame.beat` in later clusters when there's a clear use case.
- Stereo consumers in fountain, fireworks, particles, oscilloscope. Same reason.
- Crossfade on style switch (Tier-1 #6) — separate cluster E.
- Perlin drift (Tier-2 #11) — separate cluster E.

## Estimated scope

~550 LOC:
- `BeatDetector.swift`: ~80 source + ~70 test = 150
- `AudioFrame.swift`: +30
- `SpectrumAnalyzer.swift` + `AudioDownmix.swift`: ~100 (stereo plumbing) + ~50 test
- 3 beat consumers (Fireworks, Particle, Fountain): ~30 each = 90
- 3 stereo consumers (Bars, Radial, Siri): ~50 each = 150
- Settings + codec: ~25
- Tests beyond what's listed per-component: ~60

## Out of scope (future clusters)

- Cluster B: feedback-warp + reflected floor + RMS hue rotate
- Cluster C: barycentric wireframe + multi-band siri (note: multi-band siri builds on stereo path, but the band-per-wave mapping is independent)
- Cluster D: joy plot + heightfield + voronoi + (maybe) lava lamp
- Cluster E: crossfade + Perlin drift
