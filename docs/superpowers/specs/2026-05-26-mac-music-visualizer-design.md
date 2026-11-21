# Mac Music Visualizer — Design

- **Date:** 2026-05-26
- **Status:** Approved design (pre-implementation)
- **Audience:** Personal use, single developer
- **Target OS:** macOS 14.4+ (uses Core Audio process-tap API)

## 1. Goal

A native macOS app that renders a real-time, dynamic music visualizer reacting to
audio played by **Spotify** or **Apple Music**. The starter visual is a classic
retro **spectrum-bars** display. The app is configurable (palette, sensitivity,
overlay, window/display) and runs in a resizable main window that can go fullscreen.

### Non-goals (v1)

- No other audio sources beyond Spotify/Music (the tap is scoped to those processes).
- No App Store distribution, sandboxing, or notarization (personal use).
- No support for macOS < 14.4.
- Only one visualizer style ships (spectrum bars); the architecture allows more later.

## 2. Decisions (locked)

| Area | Decision |
| --- | --- |
| Language / UI | Swift + SwiftUI |
| Rendering | Metal (`MTKView`) |
| Audio source | Hybrid: real audio (FFT) **and** track metadata |
| Audio capture | Core Audio **process tap** (`CATapDescription` + aggregate device), scoped to Spotify/Music PIDs |
| Metadata | ScriptingBridge / Apple Events to `Music.app` and `Spotify.app` |
| FFT/DSP | Accelerate `vDSP` |
| Starter visual | Classic spectrum bars (log-spaced bands, gradient, peak-hold) |
| Config | Palette, sensitivity/smoothing, metadata overlay, window/display |
| Project tooling | XcodeGen (`project.yml` → `.xcodeproj`) |
| Sandbox | Non-sandboxed |

## 3. Architecture

Each unit has one responsibility and communicates through value types.

### 3.1 Core (pure Swift, unit-tested)

- **`AudioFrame`** — value type that is the contract between analysis and rendering.
  - `bands: [Float]` — N normalized band levels in `0...1`.
  - `rms: Float`, `peak: Float` — overall energy (useful for bass-driven effects).
  - `timestamp: CFTimeInterval`.
- **`SpectrumAnalyzer`** — converts mono PCM `[Float]` into an `AudioFrame`. Pure and
  deterministic given the same input + settings. (Pipeline in §4.2.)
- **`VisualizerSettings`** — `Codable`, the single source of configuration truth.
  Persisted as JSON. (Schema in §6.)
- **`ColorPalette`** — named palette → ordered gradient stops; includes presets and a
  custom-colors option.

### 3.2 Services (integration layers; verified by running)

- **`ProcessLocator`** — finds running Spotify/Music by bundle id
  (`com.spotify.client`, `com.apple.Music`), returns audio object IDs / PIDs to scope
  the tap. Publishes "which players are running."
- **`AudioCaptureService`** — owns the Core Audio process tap and the private aggregate
  device; installs the IO callback that delivers float PCM to the analyzer. Publishes a
  `CaptureState`: `.running`, `.noAudio` (no target process / silence), `.permissionDenied`.
- **`NowPlayingService`** — ScriptingBridge to `Music.app` / `Spotify.app`; reads
  `current track` and artwork; determines which app is actively playing; publishes
  `TrackInfo`.

### 3.3 Rendering

- **`MetalRenderer`** — `MTKView` delegate. Owns `MTLDevice`, command queue, and render
  pipeline state. Each frame reads the latest `AudioFrame` and asks the active visualizer
  to encode draw commands.
- **`Visualizer` protocol** — `func render(frame: AudioFrame, settings: VisualizerSettings,
  encoder: MTLRenderCommandEncoder, viewport: CGSize)`. Pluggable.
- **`SpectrumBarsVisualizer`** — first conformer: instanced bar quads + peak-hold cap quads,
  vertical color from the palette gradient. (Detail in §4.3.)

### 3.4 App / UI (SwiftUI)

- **`AppCoordinator`** (`ObservableObject`) — wires services → analyzer → renderer; owns
  the `VisualizerSettings` instance; exposes capture state and `TrackInfo` to views.
- **`MainWindow`** — hosts a full-bleed `MetalView` (`NSViewRepresentable` over `MTKView`)
  with the optional `TrackOverlay` layered on top; supports native fullscreen.
- **`SettingsWindow`** — SwiftUI `Form` bound to `VisualizerSettings`.
- **`TrackOverlay`** — shows title/artist/artwork; position + opacity from settings.
- **Menu commands** — toggle fullscreen (⌘F), open Settings (⌘,), pick audio source.

## 4. Data Flow & Pipelines

### 4.1 End-to-end flow

```
Spotify / Music plays
        │  (Core Audio process tap, scoped to those PIDs)
        ▼
AudioCaptureService ──float PCM──▶ SpectrumAnalyzer ──AudioFrame──▶ MetalRenderer
        │                                                              │
        │                                                       SpectrumBarsVisualizer
        ▼                                                              ▼
ProcessLocator                                                   MainWindow (MTKView)

NowPlayingService ──TrackInfo──▶ TrackOverlay (layered over MTKView)
VisualizerSettings ──▶ feeds analyzer params AND render params (live)
```

### 4.2 DSP pipeline (`SpectrumAnalyzer`)

1. Downmix incoming PCM to mono.
2. Accumulate into a 2048-sample ring buffer (hop as buffers arrive).
3. Apply a **Hann window** to the 2048-sample frame.
4. Real **FFT** via `vDSP` → complex spectrum → magnitude = `sqrt(re² + im²)`.
5. Convert to dB, clamp to a noise floor (e.g. −80 dB), normalize to `0...1`.
6. Map the ~1024 usable bins to `barCount` **log-spaced** bands (perceptual balance of
   bass/mid/treble); each band = max (or mean) of its bin range.
7. Apply `gain`, then **exponential smoothing** (`smoothing` = decay factor per frame),
   then **peak-hold** caps that decay slowly.
8. Emit `AudioFrame { bands, rms, peak, timestamp }`.

### 4.3 Render pipeline (`SpectrumBarsVisualizer`)

- `MTKView` draws at display refresh, capped by the `fps` setting.
- Each draw reads the most recent `AudioFrame`; uploads `bands` into an `MTLBuffer`.
- Draws one **instanced quad per band**: x = band index, height = level, vertical color
  sampled from the palette gradient.
- Draws a thin **peak-hold cap** quad per band at the held level.
- Background: solid color or vertical gradient per `BackgroundStyle`.

### 4.4 Threading

- Audio IO callback runs on a real-time Core Audio thread — it must not block or allocate.
  It copies PCM into a lock-free ring and signals the DSP queue.
- DSP runs on a dedicated serial queue, producing `AudioFrame`s.
- The newest `AudioFrame` is published to the renderer via a **single-slot atomic swap**
  (render always reads the latest frame; the audio thread never waits on the renderer).

## 5. Metadata (`NowPlayingService`)

- Uses **ScriptingBridge** (public Apple Events), not the private `MediaRemote` framework
  (which Apple restricted around macOS 15.4).
- Determines the active player by querying `player state` of each running app.
- Reads `current track`: name, artist, album.
- Artwork: `Music.app` exposes `artwork`/raw data; `Spotify.app` exposes `artwork url`
  (fetched over HTTP and cached by track id).
- Refresh: light timer (~1 s) plus immediate refresh on detected track change.
- Requires the **Automation** TCC consent prompt for each controlled app.

## 6. Configuration Schema (`VisualizerSettings`)

Persisted as JSON at `~/Library/Application Support/MacVisualizer/settings.json`. Live-applied.

```
VisualizerSettings {
  // Palette
  paletteName: String            // preset id, or "custom"
  customStops: [RGBAColor]        // used when paletteName == "custom"

  // Sensitivity / smoothing
  gain: Float                     // input multiplier
  barCount: Int                   // number of log-spaced bands
  smoothing: Float                // 0..1 exponential decay
  peakHoldEnabled: Bool

  // Overlay
  overlayEnabled: Bool
  overlayPosition: Corner         // topLeading / topTrailing / bottomLeading / bottomTrailing
  overlayOpacity: Float           // 0..1

  // Window / display
  alwaysOnTop: Bool
  fullscreenDisplayID: UInt32?    // chosen monitor (nil = current)
  targetFPS: Int                  // render cap (e.g. 60 / 120)
  backgroundStyle: BackgroundStyle // solid | gradient
}
```

## 7. UI / Windows

- **Main window:** full-bleed `MetalView`; `TrackOverlay` layered on top when enabled;
  native fullscreen via ⌘F / menu / double-click; optional always-on-top window level on
  the chosen monitor.
- **Settings window:** SwiftUI `Form` with four sections matching §6 — Palette,
  Sensitivity, Overlay, Window/Display. Opens with ⌘,. Changes apply live.
- **Menu bar:** App menu (Settings), View menu (Toggle Fullscreen), Audio menu (choose
  source: Spotify / Music / auto).

## 8. Project Structure & Build

```
mac-visualizer/
  project.yml                 # XcodeGen project definition (committed)
  Makefile                    # `make generate`, `make build`, `make run`, `make test`
  Sources/
    App/                      # SwiftUI app, windows, coordinator, overlay, settings UI
    Core/                     # AudioFrame, SpectrumAnalyzer, VisualizerSettings, ColorPalette
    Services/                 # ProcessLocator, AudioCaptureService, NowPlayingService
    Rendering/                # MetalRenderer, Visualizer, SpectrumBarsVisualizer, shaders
  Tests/
    CoreTests/                # unit tests for the pure Core layer
  Resources/
    Info.plist
    *.entitlements
  docs/superpowers/specs/
```

- **Targets:** `MacVisualizer` (app) and `CoreTests` (XCTest).
- **Build:** `xcodegen generate` then `xcodebuild` (wrapped by the Makefile).

## 9. Testing Strategy

- **Unit-tested (pure Core):**
  - A synthetic **1 kHz sine** at 48 kHz must peak in the expected log-spaced band.
  - Gain scales output linearly; smoothing converges toward target; peak-hold decays
    monotonically; a silent buffer yields ~zero bands.
  - `VisualizerSettings` JSON round-trips; palette gradient sampling is correct at stops.
- **Verified by running the app (no automated test):**
  - Core Audio tap actually captures Spotify/Music audio.
  - ScriptingBridge returns live track info and artwork.
  - The spectrum visibly and smoothly reacts to music in window and fullscreen.
  - Note: the visual reaction is validated by running the app, not by automated tests.

## 10. Permissions & Entitlements

- `NSAppleEventsUsageDescription` — to read now-playing from Music/Spotify (Automation TCC).
- Audio-capture consent for the process tap (TCC); include the microphone-usage string the
  tap APIs require.
- Non-sandboxed; no notarization (personal use).
- First-run UX: if capture state is `.permissionDenied`, the UI explains how to grant access
  in System Settings → Privacy.

## 11. Risks & Mitigations

- **Core Audio process-tap API is newer and fiddly** (aggregate-device lifecycle, IO
  callback correctness). *Mitigation:* isolate all of it in `AudioCaptureService` behind a
  simple `CaptureState` + PCM-callback interface; if it proves flaky, a ScreenCaptureKit
  audio backend can be swapped behind the same interface without touching DSP/render.
- **ScriptingBridge requires Automation consent** and apps must be running. *Mitigation:*
  degrade gracefully — overlay simply hides when no track info is available; visuals still
  run from the audio tap.
- **Real-time audio thread constraints** (no locks/allocations). *Mitigation:* lock-free
  ring + single-slot atomic frame handoff; DSP off the IO thread.
