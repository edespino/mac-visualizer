# Lyric Shadow Beat Bounce — Design

**Date:** 2026-11-17
**Source:** User request — make the active lyric line's drop shadow pulse to the beat. Prototyped first as a throwaway spike on `spike/beat-shadow-bounce` (off `29cf157`). This document productionizes what the spike taught.

Items tagged **[decided]** came from the user. Items tagged **[call]** were chosen while writing this document and were not explicitly agreed; the user reviews them here.

## Intent

When lyrics are on and a song is playing, the **active (highlighted) lyric line's drop shadow** pulses in time with the music — a snap on each beat that eases back. Only the shadow moves; the text never shifts. **[decided]**

## Why — what the spike taught

The spike drove the bounce off the existing `AudioFrame.beat` / `BeatDetector`, the same onset detector the visualizers use. That detector has a hard adaptive-threshold **floor of 0.05** (`BeatDetector.goomLimitFloor`), and it reads the **raw, pre-gain sample peak** (`SpectrumAnalyzer.swift:157,189`). The user's captured audio sits around **0.02 rms** (Core Audio process tap captures the app's output before the system mixer, so system volume can't raise it). Result: the bounce fired only on unusually loud tracks and stayed dead on most songs. The effect itself read well when it fired (confirmed live). So the spike's verdict: **keep the effect, replace the trigger** with one that fires reliably at the user's capture level without changing the 24 visualizers' beat behavior. **[decided: dedicated sensitive trigger]**

## Goals

- The active line's shadow bounces on the beat across **quiet and loud** tracks alike, at the user's ~0.02 capture level.
- The trigger is **self-adapting** — no sensitivity knob. **[decided]**
- The bounce follows the **bass/kick** energy (low frequencies), so it reads as "to the beat." **[decided]**
- Three looks remain, chosen in Settings: **Off / Lift / Glow / Both**, default **Both**. **[decided variants; [call] default Both]**
- A **strength** slider controls the visual magnitude (taste), independent of the trigger. **[call]**
- Zero change to any visualizer's beat response, shaders, or the Metal pipeline.

## Non-goals

- Changing `BeatDetector` or anything the 24 visualizers consume.
- A sensitivity/eagerness control (auto-adapt instead). **[decided]**
- Bouncing in **Demo Mode** — demo frames bypass the capture path, so the bounce is silent there. Acceptable; real music is the use case.
- Moving, resizing, or re-weighting the text. Only the shadow (radius / offset / opacity) is modulated.
- Bouncing non-active lines. Only the single active line reacts.

## Anti-goals

- Any column jitter or text-layout shift on a beat (the overlay's existing no-jitter constraint).
- Firing on **silence or a paused track** (the follower must not pulse on noise when there is no music).
- Coupling the bounce to a visualizer's per-style **gain** (it must work the same whatever style/gain is active).

## The trigger — `LyricBeatFollower` (new, `Sources/Core`) **[call on mechanism]**

A small, pure-Swift, unit-tested onset follower. Per audio frame it takes one scalar — a **bass energy** value — and returns a normalized pulse in `0...1`, non-zero only on a detected onset.

### Bass energy source **[call] — resolved via builder-check**

Add `bassEnergy: Float` to `AudioFrame`, computed in `SpectrumAnalyzer.append(...)` from the **raw FFT magnitudes** (`magsL`/`magsR`, already computed in `append`, before the band mapper) — the mean magnitude over a **fixed frequency window (~30–150 Hz [call])**, with the Hz bounds converted to FFT bin indices from `fftSize` and `sampleRate`.

Deliberately taken **off the FFT, not the mapper's bands.** The shared `BandMapper` layout is not a stable frequency axis: it switches to a note mapping for Musical Spectrum (`.notes(...)`, lowest band can sit near ~500 Hz at `musicalStartOctave = 5`) and its log-spaced bands cover a different Hz span at different `barCount`s. So "lowest K bands" would couple the bass trigger to per-style band settings — breaking the goal (follows the kick/bass) and the anti-goal (works the same whatever style is active). A fixed Hz window off the FFT is independent of `barCount`, band mapping, **and** per-style gain (the FFT magnitudes are pre-post-gain). Additive; changes no existing field.

### Follower algorithm (adaptive, floor-free) **[call]**

- Keep a slow **baseline** of recent bass energy (an exponential moving average) and a measure of recent **variability**.
- Each frame, compute the **relative rise** of the instant bass energy above the baseline. Emit a pulse when the rise clears an adaptive multiple of recent variability **and** energy is increasing — intensity scales with the size of the rise, clamped to `0...1`.
- Because the test is **relative to the recent baseline**, it fires on quiet audio (0.02) exactly as on loud audio; there is no absolute 0.05-style floor.
- A tiny **absolute epsilon** (far below 0.05, e.g. near the capture noise level) gates out true silence so a paused/silent track never pulses (anti-goal).
- A **refractory** window (~250–400 ms **[call]**) enforces **one pulse per beat, not per bass transient** **[decided: snap-and-release, not shimmer]** — long enough that each kick gives a distinct snap that eases back before the next, so the shadow never sits pinned-lifted through a dense low-end passage.
- All state is confined to the dsp queue (fed from `capture.onSamples`), like the analyzer; only the final pulse crosses to the main thread.

## Wiring

- **`RenderModel`**: replace the spike's `if frame.beat { … beatPulse.send(beatIntensity) }` (and the temporary `Log.settings.notice` beat line) with: feed every captured frame's `bassEnergy` to a `LyricBeatFollower` on the dsp queue; when it returns a non-zero pulse, `DispatchQueue.main.async { self.lyricPulse.send(intensity) }`. The publisher stays a `PassthroughSubject<Float, Never>` exposed to the overlay (rename `beatPulse` → `lyricPulse` for clarity). The follower is **not** fed in Demo Mode / synthetic paths — only the real capture callback (matching the non-goal).
- **`ContentView` / `LyricsOverlay`**: unchanged wiring shape — the overlay keeps the snap-and-decay `beatBoost` envelope and the deferred-decay render-pass fix from the spike. It reads mode + strength from **settings**, not `@AppStorage`. The decay duration is tuned **together with** the follower's refractory so each snap eases back within the per-beat gap (no pinning) — the spike's 0.28 s was set against the old sparse trigger and is a starting point, not fixed. **[call]**

## Settings (real, persisted, app-wide) **[call]**

Lyrics settings are app-wide (`settings.lyrics`), so these join `LyricsSettings`:

- `beatBounceMode: LyricBounceMode` — new Core enum `off / lift / glow / both`, with stable raw values for JSON. Default `both`.
- `beatBounceStrength: Float` — default `1.0`, range `0.2…3`.

Both via tolerant Codable (`decodeIfPresent ?? default`, `CodingKeys`, `encode`), so old `settings.json` loads cleanly. The spike's `@AppStorage("spikeBounce*")` keys are **removed** from `LyricsOverlay` and `LyricsSettingsSection`.

## UI (`LyricsSettingsSection`)

Keep the spike's controls but bind them to `settings.lyrics` and drop "(spike)":

- Picker **"Beat bounce"** — Off / Lift / Glow / Both.
- Slider **"Bounce strength"** — Subtle…Strong.

Placed after the Drop-shadow group and **disabled when Drop shadow is off** (the bounce modulates the shadow — **[call]**), with help text noting it needs the shadow on and reacts to live audio (not Demo Mode).

## The three looks (unchanged from the spike)

On the active line only, scaled by `pulse * strength`:

- **Lift** — shadow Y-offset grows, so the line appears to pop off the page.
- **Glow** — shadow blur radius swells.
- **Both** — lift + glow + a small shadow-opacity deepening.

Text font, size, weight, color, and position are untouched (no-jitter anti-goal).

## Tests (Core — the unit-tested boundary)

- **`LyricBeatFollowerTests`**: fires on a rising bass pulse at a **low absolute level** (≈0.02) where a 0.05-floor detector would not; does **not** fire on flat/steady input; does **not** fire on silence (epsilon gate); refractory prevents a double-fire inside the window; intensity scales with the rise; the baseline adapts so a sustained-loud passage settles rather than pulsing every frame.
- **`AudioFrame` / `SpectrumAnalyzer`**: bass-heavy synthetic input yields a higher `bassEnergy` than treble-heavy input; because it comes from the fixed-Hz FFT window, `bassEnergy` is independent of the post-gain setting, the `barCount`, **and** the active band mapping (unchanged when the mapper is in Musical-Spectrum note mode).
- **`LyricsSettings`**: round-trips `beatBounceMode` + `beatBounceStrength`; legacy JSON without the fields decodes to the defaults (`both`, `1.0`).

## Visual validation (part of "done")

The overlay is SwiftUI and is **not** captured by the render probe. Validate in the live window on **both a quiet and a loud track**: the active line's shadow bounces on the beat in each, no text jitter, and a paused track produces no pulse. (See the `verify-visualizer-changes` skill.)

## Attribution

Original work; no third-party code or shader is involved. No `NOTICE` / `THIRD_PARTY_NOTICES` change.

## Left to the builder

- The exact **bass Hz window** (≈30–150 Hz starting point), the EMA time constants, the variability multiple, the refractory length, and the silence epsilon — tuned to fire cleanly at ≈0.02 capture without false pulses. Starting points above; final values are the builder's, validated live.
- Whether `LyricBeatFollower` is a `struct` with `mutating func update` or a `final class` — builder's call, consistent with Core style (`BeatDetector` is the reference).
- Enum/field placement and CodingKey raw strings, following the existing `LyricsSettings` patterns.
