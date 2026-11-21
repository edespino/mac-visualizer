# Per-Style Profiles + Settings Refresh — Design

- **Date:** 2026-05-28
- **Status:** Approved design (pre-implementation)
- **Audience:** Personal use, single developer
- **Target OS:** macOS 14.4+ (unchanged)

## 1. Goal

Three related improvements to the Settings experience:

1. **Per-style profiles.** Each `VisualizerStyle` keeps its own complete copy of visual + audio settings (palette, gain, smoothing, bar count, peak-hold caps, glow, overlay, window, background). Switching styles loads that style's profile; the on-screen visualizer + the Settings UI both reflect it.
2. **Settings UI refresh.** Replace the single fixed-size `Form` with a `TabView` (Visualization · Audio · Overlay · Window · Fireworks). The Settings window becomes **resizable**.
3. **Reset to defaults.** Two confirming buttons: **Reset This Style** (just the current profile) and **Reset All Styles** (every profile, plus the fireworks tunables).

Also: make the four Fireworks beat-detector knobs **adjustable from Settings** as live sliders (no more rebuild-to-tune), delete the temporary `/tmp/fireworks.log` diagnostic from `FireworksVisualizer`, and retire the `/tune-fireworks` skill (the sliders make it redundant).

## 2. Background / current state

- `VisualizerSettings` (Core, Codable, Equatable, tolerant decoder) currently holds 15 flat fields used by every visualizer. The struct grew by accretion through prior plans and is now ~120 lines.
- `SettingsView` is a single fixed-size SwiftUI `Form` (`.frame(width: 380, height: 460)` — non-resizable) with five sections (Visualization, Palette, Sensitivity, Track Overlay, Window).
- `FireworksVisualizer` (Core, stateful class) has four hardcoded `private let` constants — `beatMinBass`, `beatMarginFloor`, `beatMarginScale`, `baselineAlpha` — plus a `/tmp/fireworks.log` writer added during the recent tuning iterations.
- `RenderModel` already observes `@Published settings` and applies changes live; the renderer caches the active visualizer instance by style.
- A `/tune-fireworks` project-scoped skill exists for swept tuning of fireworks constants by editing Swift source. Once the constants are in `VisualizerSettings` and exposed in the UI, the skill is redundant.

## 3. Non-goals

- No new visualizer styles, no rendering pipeline changes, no shaders.
- No live re-reading of `settings.json` from disk by the app (the UI is already live-bound; the slider drag IS the dynamic-tuning path).
- No sidebar-style settings layout (TabView is the chosen pattern).
- No per-tab reset buttons (the user picked a single global pair — "Reset This Style" + "Reset All Styles").

## 4. Decisions (locked)

| Area | Decision |
| --- | --- |
| Per-style scope | **Full profile** per style: every "what does this look/feel like" field, including overlay + window |
| Fireworks tunables | **Single shared block** on `VisualizerSettings` (not per-profile) — they only apply when fireworks is active |
| Settings layout | **`TabView`** with 5 tabs: Visualization · Audio · Overlay · Window · Fireworks |
| Window | **Resizable** (replace fixed `.frame` with min sizes) |
| Reset | Two buttons: **"Reset This Style"** (primary) and **"Reset All Styles"** (secondary), each with `Alert` confirmation. "Reset All Styles" also resets the fireworks tunables block |
| Migration | Tolerant decoder reads old flat-field `settings.json` and replicates the values across every style's new profile |
| Auto-tuner skill | Retired (delete `.claude/skills/tune-fireworks/`) |
| Diagnostic log | Removed (`/tmp/fireworks.log` writer deleted from `FireworksVisualizer`) |

## 5. Architecture

### 5.1 Core data model

```
public struct StyleProfile: Codable, Equatable {
    public var paletteName: String
    public var customStops: [RGBAColor]
    public var gain: Float
    public var barCount: Int
    public var smoothing: Float
    public var peakHoldEnabled: Bool
    public var glowEnabled: Bool
    public var glowIntensity: Float
    public var overlayEnabled: Bool
    public var overlayPosition: OverlayCorner
    public var overlayOpacity: Float
    public var alwaysOnTop: Bool
    public var fullscreenDisplayID: UInt32?
    public var targetFPS: Int
    public var backgroundStyle: BackgroundStyle

    public static let defaults: StyleProfile = .init( /* current per-field defaults */ )
}

public struct VisualizerSettings: Codable, Equatable {
    public var visualizerStyle: VisualizerStyle
    public var profiles: [VisualizerStyle: StyleProfile]
    // Fireworks-only tunables (single block; only relevant when style == .fireworks).
    public var fireworksMinBass: Float          // default 0.05
    public var fireworksMarginFloor: Float      // default 0.015
    public var fireworksMarginScale: Float      // default 0.5
    public var fireworksBaselineAlpha: Float    // default 0.05

    public var current: StyleProfile { profiles[visualizerStyle] ?? .defaults }

    public static let defaults: VisualizerSettings = /* every style mapped to StyleProfile.defaults */
}
```

`current` is computed (read-only). Mutating writes go through a separate helper (see §5.3).

### 5.2 Migration in the tolerant decoder

`VisualizerSettings.init(from:)` already pulls every field with `decodeIfPresent ?? default`. Extend it so that **if the old flat fields are present and `profiles` is absent**, every entry in the new `profiles` dictionary is constructed from those old flat fields (so the user's prior tuning becomes the starting state for every style). If `profiles` is present, use it; the flat fields are ignored (legacy keys decoded but discarded).

This keeps the user's settings.json viable across the change with no manual migration.

### 5.3 Mutating the current profile (Swift + SwiftUI binding)

Add a helper on `VisualizerSettings`:

```
public mutating func mutateCurrent(_ body: (inout StyleProfile) -> Void) {
    var p = profiles[visualizerStyle] ?? .defaults
    body(&p)
    profiles[visualizerStyle] = p
}
```

For SwiftUI bindings, use a small computed `Binding<T>` helper inside `SettingsView`:

```
private func bind<T>(_ keyPath: WritableKeyPath<StyleProfile, T>) -> Binding<T> {
    Binding(
        get: { model.settings.current[keyPath: keyPath] },
        set: { newValue in model.settings.mutateCurrent { $0[keyPath: keyPath] = newValue } }
    )
}
```

Now `Slider(value: bind(\.gain), in: 0.5...4)` works and triggers the existing `@Published settings` change → renderer + persistence.

### 5.4 Reading sites in the visualizers

Every visualizer that currently reads `settings.X` is updated to read `settings.current.X`. The fireworks visualizer additionally reads the four fireworks-specific knobs from the top-level `settings.fireworks*` fields (not from the profile).

Sites: `SpectrumBarsVisualizer`, `RadialSpectrumVisualizer`, `MirroredBarsVisualizer`, `OscilloscopeVisualizer`, `ParticleVisualizer`, `SpectrumFountainVisualizer`, `FireworksVisualizer`, `MetalView`, `RenderModel`, plus tests that construct `VisualizerSettings` directly.

### 5.5 `FireworksVisualizer` constant removal + diagnostic removal

- Delete the four `private let` constants. Read from `settings.fireworksMinBass` / `…MarginFloor` / `…MarginScale` / `…BaselineAlpha` inside `makeVertices`.
- Delete the `diagLog`/`diagFrame` properties, the log-truncate code in `init`, and the per-frame diagnostic-write block. Remove `import Foundation` if it was added only for that.

### 5.6 Settings UI (`SettingsView`)

`TabView` with five tabs. The same `bind(_:)` helper feeds all per-profile controls; the Fireworks tab uses direct `$model.settings.fireworksX` bindings for the shared tunables.

- **Visualization** — Style picker (drives `model.settings.visualizerStyle`, which also flips which profile the other controls edit); Palette picker; Glow toggle + intensity; Peak-hold caps toggle.
- **Audio** — Gain slider, Bar count stepper, Smoothing slider.
- **Overlay** — Show overlay toggle, Position (4-corner picker), Opacity slider.
- **Window** — Always on top toggle, Frame rate picker (30/60/120), Background style picker (solid/gradient — gradient still falls back to solid in the renderer, noted as pre-existing deferral).
- **Fireworks** — Four sliders for the shared tunables. A header note: "These apply only when the Fireworks visualizer is active."

Common header on every tab (above the section title): a small text label `"Editing \(visualizerStyle.displayName) profile"`. Helps disambiguate which profile is being edited when switching styles.

Footer (across the bottom of every tab): two buttons — **Reset This Style** (primary; resets the current profile to `StyleProfile.defaults`, AND when the current style is `.fireworks` also resets the four shared `fireworks*` tunables to their defaults — so resetting "Fireworks" returns *every* fireworks-affecting knob to factory) and **Reset All Styles** (secondary; resets every profile and the fireworks tunables block to defaults). Both pop an `Alert` first.

Window size: replace `.frame(width: 380, height: 460)` with `.frame(minWidth: 460, minHeight: 420)` and leave `maxWidth/maxHeight` unset so the user can resize.

### 5.7 Auto-tuner skill removal

Delete `.claude/skills/tune-fireworks/` entirely. Commit message notes the rationale (sliders replace it; can be re-added later if batch sweeps become necessary).

## 6. Data flow (unchanged externally)

```
SettingsView slider → bind(\.X).setter → model.settings.mutateCurrent { $0.X = … }
                                       → @Published triggers Combine sinks → renderer + debounced persist
Renderer reads settings.current.X (per profile) or settings.fireworksX (shared)
```

## 7. Testing strategy

**Unit-tested (Core):**
- `StyleProfile.defaults` round-trips through JSON.
- `VisualizerSettings.defaults` has one profile entry per `VisualizerStyle.allCases`, all set to `StyleProfile.defaults`.
- `current` returns the profile for the active style; mutating via `mutateCurrent` updates only that profile.
- `mutateCurrent` then changing `visualizerStyle` and reading `current` reflects the OTHER style's profile (independence).
- **Migration**: a partial JSON containing only the old flat fields (e.g. `{"gain": 2.5, "barCount": 64, "smoothing": 0.4, "paletteName": "phosphor"}`) decodes into a `VisualizerSettings` whose every `profiles[style]` has those values, and `visualizerStyle` defaults to `.bars` (or whatever default applies).
- A modern JSON with `profiles` round-trips losslessly.
- Existing tolerant-decode test (missing-field defaulting) still passes for the four `fireworks*` fields.

**Verified by running:**
- App launch on a fresh install → defaults populated for all 7 styles → switching styles shows independent profiles.
- Slider drags update the active profile only; switching styles + back shows the change persisted to the original profile.
- Reset This Style restores defaults for the current style only.
- Reset All Styles restores defaults for everything (including fireworks tunables).
- Fireworks sliders take effect live during music playback.
- Probe regression (`--render-probe bars` etc.) still produces expected PNGs.

## 8. Risks & mitigations

- **Wide-blast-radius refactor** — almost every visualizer file changes one line each. *Mitigation:* the compiler will flag every missed call site; tests verify behavior. The change is mechanical.
- **Binding helper bugs** — a wrong `WritableKeyPath` could silently fail to persist. *Mitigation:* the bound controls drive observable on-screen behavior, surfacing any wiring bug immediately during the live verify.
- **Settings.json format change** — old files must still decode. *Mitigation:* the tolerant decoder migration step (§5.2); a unit test asserts the migration path explicitly.
- **TabView size variance** — different tabs may want different sizes. *Mitigation:* a generous `minWidth/minHeight` plus user resize; no fixed sizes.

## 9. Out of scope / future
- File-watching `settings.json` for external edits to apply live without focusing Settings (would re-enable an external auto-tuner).
- Per-style separate **fireworks** tunable copies (rare use case; current design keeps one shared block — simpler).
- Migration tooling for renamed enum cases (none planned).
- More sophisticated auto-tuning (binary search, multi-constant joint optimization) — defer until a need shows up.
