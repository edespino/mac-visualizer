# Demo Mode — Design

- **Date:** 2026-05-28
- **Status:** Approved design (pre-implementation; lands on a new branch after plan-09 merges)
- **Audience:** Personal use, single developer
- **Target OS:** macOS 14.4+ (unchanged)

## 1. Goal

Let the visualizer run **without any music playing** by feeding the spectrum pipeline procedural, music-like `AudioFrame`s. A View → "Demo Mode" toggle (⌥⌘D) flips between live Core-Audio capture and synthetic frames. Each visualizer style still gets meaningful, varied input (bass kicks for fireworks, mid-band sweeps for bars/radial, occasional sparkle for high bands), so demos and offline development don't require Spotify.

## 2. Background / current state

- `AudioCapture` (the Core Audio process tap) emits an `AudioFrame` per render tick. The frame carries: `bands: [Float]` (normalized 0..1), `peak: Float` (raw vDSP min/max), `rms: Float`, and `timestamp: CFTimeInterval`.
- Every visualizer reads from that single `AudioFrame`. There is no other audio path.
- The renderer (`RenderModel`) holds the capture object and pumps frames to the active visualizer through Metal's display link.
- When Spotify (or any tapped process) emits silence — paused, quit, or no track loaded — every visualizer goes flat (zero bands, zero peak), which is correct but unhelpful for demos.

## 3. Non-goals

- No replacement / extension of the Core Audio process tap.
- No "auto-detect silence and switch to demo" magic — explicit toggle only.
- No per-style demo patterns (one music-like pattern feeds every style; the visualizers respond differently based on their own logic).
- No multiple selectable demo patterns (one pattern, music-like; covers all cases). User picked this in brainstorming.
- No exposing demo-mode tunables in Settings beyond the on/off toggle.

## 4. Decisions (locked)

| Area | Decision |
| --- | --- |
| Demo content | One **music-like** procedural pattern (~120 BPM bass kick, mid-band melodic sweep, occasional high-band sparkle) |
| Trigger | View menu item **"Demo Mode"** + keyboard shortcut **⌥⌘D**, with a checkmark on the menu item when on |
| Persistence | `demoModeEnabled: Bool` as a **top-level** field on `VisualizerSettings` (defaults to `false`); not per-style |
| Source dispatch | When `demoModeEnabled` is true, `RenderModel` ignores the real `AudioCapture` and pumps frames from a `DemoAudioSource` instead |
| Determinism | Seeded RNG so unit tests get repeatable frames; same seed → same frame stream |
| Tap lifecycle | Core Audio tap stays active in the background while demo mode is on (cheap; lets ⌥⌘D toggle back instantly). No teardown / restart cost. |

## 5. Architecture

### 5.1 New: `Sources/Core/DemoAudioSource.swift`

```
public final class DemoAudioSource {
    private let barCount: Int           // matches the analyzer's band count
    private var rng: SeededRNG          // xorshift64, fixed seed
    private var startTime: CFTimeInterval?

    public init(barCount: Int, seed: UInt64 = 0xDEADBEEF) { ... }

    /// Produce one synthetic AudioFrame for the given wall-clock timestamp.
    /// Pure: no state captured outside `rng` and `startTime` (set on first call).
    public func nextFrame(at timestamp: CFTimeInterval) -> AudioFrame {
        // t = seconds since first call (relative time, so demo starts at t=0)
        // Bass kick: every 0.5 s, gaussian pulse on bands 0..(barCount * 0.15)
        // Mid sweep: slow sine sweep across bands [barCount*0.2 .. barCount*0.6] over 4 s cycle
        // High sparkle: every ~1.2 s, random tap on a band > barCount*0.7
        // Sum, clamp 0..1, fill `bands[]`.
        // peak: max of bands.
        // rms: sqrt(mean(bands²))
        // timestamp: passed in
    }

    public func reset() { rng = .init(seed: 0xDEADBEEF); startTime = nil }
}
```

Generation specifics (constants tunable, picked for "looks lively, not chaotic"):
- **Bass kick** — every `kickPeriod = 0.5` s (≈120 BPM), a gaussian envelope `exp(-((t-kickT)/0.06)²)` of amplitude 0.8 distributed across the bottom 15% of bands (so it looks like a thump on bass frequencies). Random ±10% amplitude jitter per kick via `rng.nextUnit()`.
- **Mid-band melodic sweep** — `sweep(t) = 0.4 + 0.4·sin(2π·(t/4))`, applied to bands in `[20%, 60%]` of `barCount`. Adds a gentle moving hump across the mid spectrum that traces a slow sine, so bars/radial/mirrored have something visually flowing.
- **High-band sparkle** — every `1.2 ± 0.4` s (RNG-jittered), pick a single band `i ∈ [70%, 100%]·barCount`, set `bands[i] += 0.6 · exp(-(t-sparkleT)/0.15)`. Particles/fireworks high-end colors get small flicks.
- **Smoothing** — bands aren't smoothed by `DemoAudioSource`; the existing `SpectrumAnalyzer` smoothing applies downstream via `RenderModel.applyLive`.

This is a single pattern. The visualizers handle the variety:
- Bars/radial/mirrored — show the moving sweep + kicks visibly.
- Oscilloscope — kicks and sweep show as a varying amplitude waveform.
- Particles — the bass kicks gate the starfield bursts.
- Fountain — per-band activity drives per-column spawns; the kick spikes the leftmost columns.
- Fireworks — the bass kicks trigger bursts (this is the most important: the beat detector now actually fires reliably in demo mode).

### 5.2 `VisualizerSettings` — add one top-level Bool

```
public var demoModeEnabled: Bool   // default false
```

Add to `CodingKeys`, `init(from:)` (tolerant), `encode(to:)`, `defaults`. Same pattern as the fireworks tunables. No `StyleProfile` change — demo mode is app-level, not per-style.

### 5.3 `RenderModel` integration

`RenderModel` already pumps frames into the active visualizer each render tick (via the display link / metal callback). Currently it reads from `AudioCapture.lastFrame` (or equivalent). Change:

```swift
let frame: AudioFrame
if settings.demoModeEnabled {
    frame = demoSource.nextFrame(at: CACurrentMediaTime())
} else {
    frame = audioCapture.lastFrame()   // existing path
}
visualizer.makeVertices(frame: frame, settings: settings, aspect: aspect)
```

`demoSource` is constructed lazily on first toggle-on and lives for the model's lifetime. Reset its RNG (`demoSource.reset()`) when re-enabling, so the same seed gives the same intro every time.

If `barCount` changes (rare; configurable), recreate `demoSource` with the new band count.

### 5.4 Menu + shortcut in `MacVisualizerApp`

The existing `MacVisualizerMain: App` has a Commands menu (Visualizer cycling, etc.). Add to the View menu:

```swift
.commands {
    CommandGroup(after: .toolbar) {
        Toggle("Demo Mode", isOn: $model.settings.demoModeEnabled)
            .keyboardShortcut("d", modifiers: [.option, .command])
    }
    // ... existing commands ...
}
```

The `Toggle` in a Commands group renders as a menu item with a checkmark — bound to `settings.demoModeEnabled`. Flipping it triggers the existing `@Published` flow → `RenderModel.applyLive` (no special handling needed beyond the source switch in `RenderModel`).

### 5.5 (Optional) Settings UI

Skip a Settings toggle for v1; the menu + shortcut covers it. If the user later wants discoverability, add a single Toggle to the Audio tab (or a new "Demo" tab).

## 6. Testing strategy

**Unit-tested (Core):**
- `DemoAudioSource` with the default seed produces a deterministic frame stream — same `(barCount, seed)` + same `nextFrame(at:)` sequence → byte-identical `bands[]`.
- After a bass-kick beat (caller passes timestamps spanning a `t = 0.5` boundary), the low-band sum is significantly higher than the surrounding silence.
- Mid-band sweep is non-zero across the configured mid range at all sample points.
- High-band sparkles are zero between sparkle events and ≥ 0.5 at the sparkle event time.
- Reset → identical frame stream after the same input sequence.

**Verified by running:**
- Toggle demo on with no music playing → fireworks bursts, bars dance, oscilloscope shows a moving waveform. Toggle off (silence) → all visualizers go flat. Toggle on again → demo resumes from t=0 (seeded reset).
- Render probe with `--render-probe <path> bars demo` (TBD CLI extension if useful; not required for v1) OR just visually with a quick session.

## 7. Risks & mitigations

- **Demo frames clash with smoothing.** If `SpectrumAnalyzer.smoothing` is high, the kick gets blurred. *Mitigation:* the user can drop smoothing per-style; the demo is fine even with smoothing maxed (the sweep still moves).
- **Tap remains active while demo plays.** Doesn't affect anything visible (we just don't read it), and it lets ⌥⌘D return instantly. The tap's CPU cost is minor.
- **Determinism vs liveness.** Same seed = same demo every time. If that becomes boring, expose a seed-per-launch option later. For v1 the deterministic pattern is fine — different visualizers + style switches keep it from feeling repetitive.
- **One pattern is restrictive.** Multiple patterns were explicitly out of scope. If we want sweep / silence / noise as separate demos later, extend `DemoAudioSource` with a pattern enum then.

## 8. Out of scope / future
- Multiple selectable demo patterns (sweep, silence, white noise, recorded-track-loop) via a sub-menu.
- Auto-detect silence and switch to demo without explicit toggle.
- Exporting a demo loop as a screen recording / GIF for sharing.
- A "demo seed" knob (different randomization per launch) — fixed deterministic seed for now.
