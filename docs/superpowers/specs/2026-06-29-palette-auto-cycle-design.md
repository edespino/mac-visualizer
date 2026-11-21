# Palette Auto-Cycle + New Palettes — Design

**Date:** 2026-06-29
**Branch:** `polly/palette-cycle`
**Source:** User request — a new **global** feature: when enabled, the active color palette automatically changes after a configurable interval (default 60s), crossfading between palettes. Plus: add appropriate new predefined palettes. Based on a read-only explore of the palette system on `main` @ `38d6ea0`.

## Goal

Two related additions, both global (not per-style):

1. **Palette auto-cycle** — an opt-in global feature (off by default). When on, every *interval* seconds (default 60) the app advances to the next palette in a **shuffle deck** (all palettes used once before any repeat; no same-palette seam between decks) and **crossfades** to it over a configurable *fade duration* (default ~1.5s). The new palette is written to **every** style's profile (global color identity). A manual palette change re-anchors the countdown and continues the deck.

2. **Six new predefined palettes** — `viridis`, `plasma`, `spectrum`, `pastel`, `forest`, `oceanic` — expanding the deck from 8 to 14, each visually distinct from the existing set.

Both default to a no-op visual: auto-cycle is off by default, and the new palettes only appear if selected or cycled to. Nothing changes about any existing style's default look.

## Grounding (verify before implementing — no fabrication)

The implementer MUST read these before writing code; this spec deliberately does not invent line numbers for the palette internals:

- `Sources/Core/ColorPalette.swift` (or wherever `ColorPalette` + `orderedPresetNames` + the 8 presets live) — the **exact representation** of a palette (color-stop array? fixed N colors? interpolation function?) and the **format** each preset is defined in. The 6 new palettes must be defined in that same format. The blend implementation depends on this representation.
- The **palette uniform build site** — where the active palette is converted into the `PaletteUniform` (or equivalent) that is bound for CPU/shader color lookup each frame. This is the single injection point for the crossfade blend (see Component 3).
- `VisualizerSettings` / `StyleProfile` — `paletteName` storage (per-`StyleProfile`, forwarded via `settings.paletteName` to the active style), the session-only **"Apply to all styles"** toggle, and the existing **manual palette-cycle** shortcut path (the auto-cycle reuses this write path).
- The **per-frame draw/update seam** on the render model (where elapsed wall-clock time is already available and where a non-realtime-thread timer tick belongs). The auto-cycle advance and the fade progress are computed here, NOT on the audio IO thread.

## Architecture

Five components, all additive:

- **Component 1 — Six new palettes.** Define `viridis`, `plasma`, `spectrum`, `pastel`, `forest`, `oceanic` in the existing `ColorPalette` format; append them to `orderedPresetNames` after the current 8 (so existing indices/order are unchanged). No existing palette is modified.
- **Component 2 — Settings fields.** Three new global flat top-level fields on `VisualizerSettings`: `paletteCycleEnabled` (Bool, default `false`), `paletteCycleInterval` (Double seconds, default `60`), `paletteCycleFadeDuration` (Double seconds, default `1.5`). Tolerant Codable + Equatable, mirroring the established flat-field precedent. These are global (not per-`StyleProfile`).
- **Component 3 — Crossfade blend.** A pure function that blends two palettes into one effective palette by a mix factor `t ∈ [0,1]`, applied **once per frame on the CPU side** at the palette-uniform build site. Downstream consumers (all 15 styles, CPU + shader) receive a single already-blended palette and are **unchanged**. When not mid-fade, the blend is a passthrough of the current palette (bit-identical to today).
- **Component 4 — Cycle engine.** A small, testable, deterministic state machine (`PaletteCycleEngine`) in Core that owns the shuffle deck, the interval countdown, the current/next palette names, and the fade progress. It is driven by `(dt, settings, currentPaletteName)` each frame and emits the effective palette pair + mix factor. Pure logic, no timers/threads — fully unit-testable.
- **Component 5 — Wiring + UI.** The render model advances the engine each frame using already-available elapsed time, applies its output (the blended palette + any committed palette-name change written to all styles), and the Settings UI gains a **"Palette Cycle"** group under the global **Appearance** section: the toggle, interval slider, and fade-duration slider.

No change to the `Visualizer` protocol, to individual visualizers, to `Shaders.metal`, or to buffer indices. The crossfade is invisible to every render path because it happens before the palette is handed to them.

## Component 1 — Six new palettes

### Files
- `Sources/Core/ColorPalette.swift` (the actual file per Grounding)
- tests under `Tests/CoreTests/`

### Design
Add six presets in the existing palette format and append their names to `orderedPresetNames` (after `mono`, preserving existing order). Each must be visually distinct from the current 8 (`classic, phosphor, synthwave, inferno, aurora, ember, ice, mono`).

Target character per palette (the implementer defines the actual stops in the existing format to match these intents — do not copy values blindly; tune to the existing stop count/structure):

| Name | Character / target hues | Distinct from |
|---|---|---|
| `viridis` | perceptually-uniform: dark indigo → blue → teal → green → yellow (matplotlib viridis). Colorblind-friendly. | nothing currently perceptually-uniform |
| `plasma` | indigo → magenta → orange → gold (matplotlib plasma). | different curve from synthwave/inferno |
| `spectrum` | full rainbow hue sweep (red→orange→yellow→green→blue→violet). | nothing spans the full hue wheel |
| `pastel` | soft low-saturation multi-hue (rose, peach, mint, periwinkle). | only desaturated palette; all others saturated |
| `forest` | muted greens + earthy browns + moss. | only natural/earthy palette |
| `oceanic` | deep navy → teal → aqua (deeper/greener than `ice`). | greener & deeper than `ice` |

**Requirement:** these are additive only. A test must assert the existing 8 presets and `orderedPresetNames`' first 8 entries are unchanged (no reordering, no value drift), and that all 14 names resolve to a valid palette. The `ColorPalette.fallback` behavior (non-optional fallback established earlier) must still hold for any unknown name.

## Component 2 — Settings fields

### Files
- `Sources/Core/VisualizerSettings.swift`

### Design
Three new **global** flat fields (not per-`StyleProfile`, since the feature is app-wide):

| Field | Type | Default | UI range | Meaning |
|---|---|---|---|---|
| `paletteCycleEnabled` | Bool | `false` | toggle | master on/off |
| `paletteCycleInterval` | Double | `60` | 5–600 s | seconds between palette advances |
| `paletteCycleFadeDuration` | Double | `1.5` | 0.1–10 s | crossfade length |

- Tolerant Codable (`decodeIfPresent ?? default`), CodingKeys, encode, Equatable — mirroring the established flat-field convention so legacy `settings.json` (without these keys) decodes to the defaults (feature off).
- `paletteCycleInterval` and `paletteCycleFadeDuration` are clamped to positive, finite values on read (a fade duration ≥ interval is allowed but the engine treats fade as `min(fadeDuration, interval)` to avoid a fade that never completes before the next tick). Use the `finiteOr(default)`-then-clamp pattern established in the Particles/Ribbon work so NaN/inf can't poison the timer math.

## Component 3 — Crossfade blend

### Files
- `Sources/Core/ColorPalette.swift` (blend function lives with the palette type)
- the palette-uniform build site (per Grounding)
- tests under `Tests/CoreTests/`

### Design
Add a pure blend: given palette A, palette B, and `t ∈ [0,1]`, return an effective palette whose every color component is `lerp(A, B, t)` (component-wise on the existing stop representation; A and B share the same stop count by construction since all presets use the same format). `t = 0` returns A exactly; `t = 1` returns B exactly.

At the palette-uniform build site, build the bound palette from the engine's `(currentName, nextName, mix)`:
- when `mix == 0` (not fading): use `currentName`'s palette directly — **bit-identical to today** (regression-guarded).
- when `0 < mix < 1`: bind `blend(current, next, mix)`.
- when `mix` reaches 1: the engine commits `next` as the new current (see Component 4); subsequent frames are passthrough again.

**Value-preservation requirement:** with auto-cycle disabled (default), this path must produce a palette uniform **bit-identical** to the pre-feature build for the same `paletteName`. A test pins this (build the uniform for each of the 8 original palettes with the feature off and assert byte/bit-exact equality against a golden captured from the unblended path).

## Component 4 — Cycle engine (deterministic, testable)

### Files
- `Sources/Core/PaletteCycleEngine.swift` (new)
- `Tests/CoreTests/PaletteCycleEngineTests.swift` (new)

### Design
A struct/class with **no timers and no threads** — advanced explicitly by the caller each frame:

```
struct PaletteCycleOutput {
    var currentName: String      // palette to show (or fade from)
    var nextName: String?        // palette to fade to (nil when not fading)
    var mix: Double              // 0 = show current, 1 = fully next
    var committedName: String?   // non-nil on the frame a fade completes → write to all styles
}

final class PaletteCycleEngine {
    // deck: shuffled order of orderedPresetNames, exhausted before reshuffle;
    // first draw of a new deck != last palette of the previous deck (no seam repeat).
    func advance(dt: Double,
                 enabled: Bool,
                 interval: Double,
                 fadeDuration: Double,
                 currentPaletteName: String,
                 availableNames: [String],
                 rng: inout some RandomNumberGenerator) -> PaletteCycleOutput
}
```

Behavior:
- **Disabled:** countdown/fade reset; output is `current = currentPaletteName, next = nil, mix = 0, committed = nil`. Pure passthrough.
- **Enabled, counting down:** accumulate `dt` (clamped/finite) toward `interval`. While counting, output passthrough of the current palette.
- **Interval reached:** pick the next palette from the shuffle deck (excluding the current name from the immediate next draw), begin a fade; each subsequent frame advances `mix = elapsedFade / effectiveFade` where `effectiveFade = min(fadeDuration, interval)`.
- **Fade complete (`mix ≥ 1`):** clamp `mix = 1`, set `committedName = nextName`, reset to counting-down with the new current = next, `next = nil`.
- **Manual change detection:** if `currentPaletteName` (the externally-set palette) differs from the engine's tracked current AND no fade is in progress, treat it as a manual pick — re-anchor: reset the countdown, set tracked current to the new name, and exclude it from the immediate next deck draw. (If a fade IS in progress when a manual change arrives, the manual pick wins: cancel the fade, snap to the manual palette, re-anchor countdown.)

**Determinism:** the RNG is injected (`inout RandomNumberGenerator`) so the shuffle is reproducible in tests. Seeded tests assert: interval timing (no advance before `interval`, advance at/after it), fade ramps 0→1 over `effectiveFade`, `committedName` fires exactly once per cycle at completion, the deck exhausts all 14 names before repeating, no same-name seam between decks, manual-change re-anchors the countdown and continues the deck, and disabled is a pure passthrough.

## Component 5 — Wiring + UI

### Files
- the render model (per Grounding — where palette is resolved per frame and where `dt`/elapsed is available)
- `Sources/App/SettingsView.swift`

### Design
**Render model:** each frame (on the main/draw path, NOT the audio IO thread), call `engine.advance(...)` with the frame `dt`, the three settings, and the current `settings.paletteName`. Then:
- build the bound palette from the engine output via the Component-3 blend;
- when `output.committedName != nil`, write that palette name to **all** styles' profiles (reuse the existing "apply to all styles" palette-write path used by the manual cycle shortcut), so switching styles mid-session shows the cycled palette and persistence reflects it.

The fade itself (mix between commits) does NOT rewrite `paletteName` every frame — only the **committed** name is persisted; intermediate blends are render-only. This keeps the debounced settings-save from thrashing.

**UI:** in the active-aware `SettingsView`, add a global **"Palette Cycle"** group under the **Appearance** section (with palette/gain), containing:
- `Toggle("Auto-cycle palettes", isOn: $settings.paletteCycleEnabled)`
- interval slider (5–600 s) — shown/enabled only when the toggle is on
- fade-duration slider (0.1–10 s) — shown/enabled only when the toggle is on

The new palettes need no special UI — they appear automatically in the existing palette picker (which is populated from `orderedPresetNames`).

## Testing

Headless-testable seams (no GPU, no timers, no audio thread):

1. **New palettes:** all 14 names resolve; the original 8 presets + first-8 ordering are byte/bit-unchanged; each new palette is non-degenerate (distinct stops, valid components).
2. **Blend:** `t=0` ⇒ A exactly, `t=1` ⇒ B exactly, `t=0.5` ⇒ component-wise midpoint; blend of a palette with itself is identity.
3. **Value-preservation:** with auto-cycle off, the palette-uniform build for each original palette is bit-identical to the pre-feature path (golden).
4. **Engine:** the full deterministic behavior matrix above (seeded RNG): timing, fade ramp, single commit per cycle, deck exhaustion, no seam repeat, manual re-anchor, fade-interrupt-by-manual, disabled passthrough, NaN/inf interval/fade sanitized.
5. **Codable:** round-trip + tolerant decode (legacy JSON ⇒ feature off) + Equatable for the 3 new fields.

## Risks / non-goals

- **Risk — value preservation:** the feature must be invisible when off. The bit-identical palette-uniform golden (test 3) is the guard; the implementer STOPS and reports if it can't be made to pass (it would mean the blend path isn't a true passthrough at `mix=0`).
- **Risk — per-frame cost:** blending happens once per frame on the CPU (lerp a small stop array), only while fading; when not fading it's a passthrough. Negligible, but the blend must not allocate per-frame in the hot path (reuse a buffer or value type).
- **Non-goal — per-style cycle scope:** cycle always writes all styles (decided). Not exposing a per-style cycle mode.
- **Non-goal — fade curve control:** linear `mix` ramp only; no easing-curve control this pass.
- **Non-goal — new palette authoring UI:** the 6 are predefined; no user-defined palette editor.
- **Non-goal — reset coverage:** these are global fields, not per-style; `resetCurrentStyle()` is NOT involved. "Reset All Styles" (`.defaults`) already resets all `VisualizerSettings` fields, so the new globals reset there for free — a test confirms `.defaults` has the feature off.
