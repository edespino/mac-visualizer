# Polartone Spiral Mode — Design

**Date:** 2026-06-28
**Branch:** `polly/polartone-spiral`
**Source:** User request — a slowly-rotating line that winds inward with an "ever so slightly decreasing radius", collapses at an inner threshold, clears the screen, spirals back outward toward where it started, clears again at the outer bound, and reverses — looping, with the bounds and speed controllable. Builds on the upstream-fidelity findings for `mattdesl/polartone` (persistent trail + time-rotated `startAngle` + `radius = 1 - dur` inward drift) captured in the prior investigation.

## Goal

Add a second render mode to the existing Polartone visualizer: a continuous, time-driven **breathing spiral**. The accumulated line winds between an outer and inner radius bound at a steady, controllable rate; at each bound the screen hard-wipes and the radial direction reverses. The current static waveform ring is preserved unchanged as the default mode.

This is a behavioral addition to one existing style, not a new style and not a replacement. It reuses the per-style render-mode pattern already established for Voronoi (`cells`/`blobs`) and LavaLamp.

## Architecture

Three coordinated changes, all additive:

- **Render-mode enum** on the per-style profile, selecting `ring` (today) vs `spiral` (new). Default `ring`, so nothing changes until the user opts in.
- **`PolartoneVisualizer` becomes stateful** (`struct → class`) to hold cross-frame spiral state (angle, radius, direction, accumulated points). No `Visualizer` protocol change is required — a class mutates its own stored properties inside the non-`mutating` protocol method.
- **Settings + UI**: new spiral-only scalar fields, surfaced in the active-aware "Polartone Controls" section, shown only when the mode is `spiral`.

No renderer/Metal changes: Polartone is a CPU vertex-emit visualizer (`makeVertices(...) -> [BarVertex]`), so the spiral is pure CPU geometry. The "hard wipe" is simply emitting an empty/reset polyline on the turnaround frame.

## Component 1 — Render-mode enum

### Files
- `Sources/Core/VisualizerSettings.swift` (StyleProfile + Codable)

### Design
Add `PolartoneRenderMode: String, Codable, CaseIterable { case ring, spiral }` and a `polartoneRenderMode` field on `StyleProfile`, mirroring `voronoiRenderMode` / `lavaLampRenderMode` exactly:
- default `.ring`;
- tolerant decode: `decodeIfPresent(PolartoneRenderMode.self, forKey: .polartoneRenderMode) ?? .ring`;
- present in the flat-JSON → profiles migration path (additive; legacy JSON lacking the key resolves to `.ring`);
- covered by the existing settings round-trip / migration / Equatable tests.

## Component 2 — Stateful PolartoneVisualizer

### Files
- `Sources/Core/PolartoneVisualizer.swift` (struct → class)

### Lifecycle justification
The live visualizer instance is created once when the style is selected and reused for every frame, and recreated only when the visualizer style changes (`Sources/Rendering/MetalView.swift:61,67,79-84`). Converting to a `class` therefore gives per-frame state that:
- persists across frames within a Polartone session, and
- resets naturally when the user switches away from and back to Polartone (a fresh instance is constructed).

`makeVertices` runs single-threaded on the draw path, so the mutable state needs no locking.

### State (spiral mode only)
- `angle: Float` — current sweep angle (radians), advanced over time.
- `radius: Float` — current base radius, drifting between bounds.
- `direction: Direction` — `.inward` or `.outward`.
- `points: [SIMD2<Float>]` — accumulated polyline for the current sweep (cleared on wipe).
- `lastTimestamp: Double?` — for computing `dt` from the frame timestamp.
- A `maxPoints` capacity cap (safety bound on the buffer).

`ring` mode keeps the existing stateless code path and ignores all spiral state.

### Per-frame logic (`spiral` mode)
On each `makeVertices(frame:settings:size:)`:
1. **dt**: `dt = clamp(frame.timestamp - lastTimestamp, 0, dtMax)`; update `lastTimestamp`. Clamp guards against pauses / first-frame jumps.
2. **angle**: `angle += rotationSpeed * dt` (reusing `polartoneRotationSpeed` as angular speed; if the user leaves it 0, fall back to a small nonzero default sweep so the spiral still advances — see Open Decisions).
3. **radius drift**: derive a per-frame radial step from **revolutions-per-sweep** (`polartoneDriftRevolutions`) and the angular speed, so the radius crosses `outerBound → innerThreshold` in approximately that many turns. Apply toward the active `direction`.
4. **append point**: convert `(angle, radius + waveformDeflection)` to a 2D point. The waveform deflection reuses `polartoneAmplitude` (and existing thickness/color-floor handling), so the line still wobbles to the music.
5. **bound check / hard wipe**: if `direction == .inward && radius <= innerThreshold`, or `direction == .outward && radius >= outerBound`: clear `points`, flip `direction`, snap `radius` to the just-reached bound. The cleared frame emits no line (hardwipe in one frame).
6. **emit**: build `[BarVertex]` from `points` as a polyline (same vertex/thickness construction the ring path already uses).

### Bounds and reused parameters
- **outer bound** = `polartoneRadius` (already shipped).
- **inner threshold** = `polartoneInnerThreshold` (new).
- **angular speed** = `polartoneRotationSpeed` (already shipped).
- line thickness, waveform amplitude, color floor — reused as-is.

### Value-semantics risk
`struct → class` changes Polartone from value to reference semantics. The implementer MUST verify (grep + build) that nothing copies the visualizer expecting value semantics (the prior explore indicated the instance is only stored and called, never copied) — verified, not assumed.

## Component 3 — Settings fields + UI

### Files
- `Sources/Core/VisualizerSettings.swift` (new scalar fields)
- `Sources/App/SettingsView.swift` (mode picker + conditional spiral controls)

### New fields (spiral-only)
| Field | Default | Range | Meaning |
|---|---|---|---|
| `polartoneInnerThreshold` | 0.05 | 0.0–0.4 | radius at which it wipes and reverses inward→outward |
| `polartoneDriftRevolutions` | 8 | 1–40 | turns to cross outer→inner (the "relatively slow" rate) |
| `polartoneStartDirection` | `.inward` | enum | which way the first sweep goes |

All additive scalars/enums with tolerant `decodeIfPresent ?? default`; legacy JSON is unaffected. Defaults are chosen so enabling spiral mode produces a calm, slow spiral consistent with the user's described reference.

### UI
In the active-aware "Polartone Controls" section of the restructured Settings:
- add the **mode picker** (`ring` / `spiral`);
- show the three spiral-only controls **only when** `polartoneRenderMode == .spiral` (conditional rendering within the section — the restructured Settings already gates controls per active style; this extends it per active mode).

## Testing

The stateful class is unit-testable headless (no GPU), the highest-value coverage in this change:

- **Ring-mode regression** — for the same synthetic frame, `spiral` disabled produces vertex output byte-identical to the current shipped Polartone (proves the refactor preserves the default).
- **Radius monotonic within a sweep** — driving N synthetic frames in one direction, `radius` moves monotonically toward the active bound.
- **Wipe + reverse at bounds** — when `radius` reaches the inner threshold (resp. outer bound), the points buffer is emptied that frame and `direction` flips; the next frame begins re-accumulating from the bound.
- **Buffer capacity** — `points` never exceeds `maxPoints`.
- **State reset on re-init** — a freshly constructed instance starts from `startDirection` at the outer bound with an empty buffer (models the style-switch reset).
- **Codable** — round-trip + tolerant-decode + Equatable for the new enum and scalars; legacy flat JSON resolves `polartoneRenderMode` to `.ring`.
- **dt clamp** — a large or negative timestamp delta does not produce an unbounded radius/angle jump.

## Open Decisions (resolved)

- **rotationSpeed == 0 in spiral mode**: spiral needs angular advance to form. If the user has `polartoneRotationSpeed == 0`, spiral mode uses a small internal default angular speed so the spiral still advances rather than degenerating to a radial line. (Ring mode keeps honoring 0 = static.)
- **Track-duration drift**: upstream ties inward drift to elapsed/track-duration (`radius = 1 - dur`). This app's `AudioFrame` has no reliable track duration, so the drift is modeled as a steady time-driven rate (`polartoneDriftRevolutions`) rather than fabricating a duration. This matches the user's "relatively slow, controllable" intent.

## Out of Scope (deferred)

- Upstream's 3D tilted-perspective camera projection (`[0, 3.5, 0]`) — this remains a flat 2D top-down spiral.
- Upstream's low-alpha overdraw / trail history beyond the current sweep — the hard-wipe-per-sweep model is intentionally simpler.
- The structural trail/`capacity`/open-arc/`alpha` options previously deferred for the ring mode.

## Workflow

Single feature branch `polly/polartone-spiral`. Implemented by a coding sub-agent (`claude_code`) following TDD, cross-reviewed by a different vendor (`codex`), then merged to `main`. Per the repo's standing policy, the merge triggers: clean rebuild (`rm -rf DerivedData`) → `make build` → `make test` → install to `/Applications/MacVisualizer.app` → verify installed dylib UUID matches the freshly-built one. Live, audio-on confirmation of the spiral motion is the user's manual step (the motion can't be GPU-verified headless).
