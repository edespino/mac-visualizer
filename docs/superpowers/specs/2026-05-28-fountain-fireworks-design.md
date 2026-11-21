# Fountain + Fireworks Particle Styles — Design

- **Date:** 2026-05-28
- **Status:** Approved design (pre-implementation)
- **Audience:** Personal use, single developer
- **Target OS:** macOS 14.4+ (unchanged)

## 1. Goal

Add two new music-reactive particle visualizers to the existing 5-style set:

- **`fountain`** — a per-band "spectrum fountain": each frequency band is a column along the bottom; the band's level drives the spawn rate and launch velocity of particles in its column. Gravity pulls them down; the spectrum becomes a continuous spray you can read across the width.
- **`fireworks`** — bursts of particles at random positions on detected **bass beats** (rising-edge threshold with a refractory period). Punchy, clearly tied to drops; quiet → calm, beats → bursts.

After this change, `VisualizerStyle.allCases` is 7: bars, radial, mirrored, oscilloscope, particles, **fountain**, **fireworks**.

## 2. Background / current state

- `Visualizer` protocol (Core): `func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex]`. Existing stateful conformer: `ParticleVisualizer` (bass-reactive starfield).
- `VisualizerStyle` (Codable, CaseIterable) drives switching: `.makeVisualizer()`, `.next/.previous`, `.displayName`, `.allCases`. The menu (⌘ Visualizer), keyboard cycling (⌘]/⌘[), and the Settings picker all iterate `allCases`, so adding cases auto-extends switching.
- The renderer (`MetalView.Coordinator`) caches the visualizer instance and rebuilds it only when `settings.visualizerStyle` changes, so stateful visualizers (like these) keep their particle pool alive across frames.
- The Plan 7 bloom applies to anything drawn through the pipeline — so glowing fountains and glowing fireworks come for free.

## 3. Non-goals

- No changes to the rendering pipeline, `MetalView`, settings UI, or any other style.
- No new settings (existing palette/glow/etc. already cover what these need).
- No alternative behaviors for these styles (e.g., centered-burst fireworks, single-jet fountain) — picked one behavior each.
- No tunable per-style parameters in Settings yet (constants live in the visualizer; tune live, surface later if needed).

## 4. Decisions (locked)

| Area | Decision |
| --- | --- |
| Fountain audio mapping | Per-band columns: band index → x position; band level → spawn rate + launch velocity |
| Fountain colors | Per-particle color from `palette.sample(at: i / (N−1))` where `i` is the band/column index |
| Fountain physics | Gravity-bound (initial up-velocity, constant downward acceleration); horizontal jitter at spawn; particles fade with age + despawn off-screen |
| Fireworks trigger | Rising-edge bass beat detection (bass crosses threshold AND previous bass was below `threshold − margin`), with a refractory period so sustained bass doesn't strobe |
| Fireworks burst | Random position within a central region; one random palette color per burst; ~60 particles spawned in all directions; gentle gravity + drag |
| Pool capping | Fixed maximum particle count per visualizer (e.g. ~600); when full, new spawns overwrite the oldest |
| Determinism | Seeded `SeededRNG` (xorshift64) used for all randomness, so output is reproducible given identical inputs |
| Switching | `.fountain` and `.fireworks` appended to `VisualizerStyle` after `.particles`; menu/keyboard/picker auto-include via `allCases` |

## 5. Architecture

### 5.1 Core (pure, unit-tested)

- **`SpectrumFountainVisualizer`** — `public final class`, conforms `Visualizer`. Owns a fixed-size particle pool (`maxParticles ≈ 600`) and a seeded `SeededRNG`. Tracks `lastTimestamp` to derive `dt` from `AudioFrame.timestamp`. Each `makeVertices`:
  - Advance live particles (`position += velocity·dt`; `velocity.y -= gravity·dt`; light horizontal drag); age each; deactivate when `age > lifetime` or off-screen.
  - Spawn new particles per band: for each band `i` with level `L_i > spawnFloor`, spawn `floor(L_i · spawnRate · dt)` particles into the inactive slots at `x = mapX(i, N)` (aspect-corrected), `y = −1`, with `v_y = baseUp + L_i · launchScale`, small horizontal jitter from RNG, `colorPos = i / max(N−1, 1)`.
  - Emit each active particle as a small aspect-corrected quad (6 verts), colored `palette.sample(colorPos) × brightnessByAge`.
  - Emitted vertex count = `activeCount × 6`, capped by `maxParticles · 6`.

- **`FireworksVisualizer`** — `public final class`, conforms `Visualizer`. Same pool/RNG/dt pattern. Each `makeVertices`:
  - Advance live particles (gravity, drag, age, fade); deactivate expired.
  - Compute `bass = avg of low ~15% of bands`. Detect a rising-edge beat: `bass > beatThreshold && lastBass ≤ beatThreshold − beatHysteresis && now − lastBeatTime ≥ refractoryPeriod`. Track `lastBass`, `lastBeatTime`.
  - On a beat: pick a random center within `[-0.6, 0.6] × [-0.4, 0.4]`; pick `burstColorPos = rng.nextUnit()`; spawn ~60 particles into the pool — each with that center position, velocity `(cos θ, sin θ) · (baseSpeed + rng·spreadSpeed)` for `θ` evenly distributed (+ small RNG jitter), shared `colorPos`.
  - Emit each active particle as a small aspect-corrected quad, colored `palette.sample(colorPos) × brightnessByAge`.

Each lives in its own file (one responsibility per file), mirroring `ParticleVisualizer`. A private `SeededRNG` lives inside each file (acceptable duplication — three small structs of the same shape isn't worth a shared Core file with broader visibility; YAGNI).

### 5.2 `VisualizerStyle` (modify)

- Add cases after `.particles`: `case bars, radial, mirrored, oscilloscope, particles, fountain, fireworks`.
- `displayName`: "Fountain", "Fireworks".
- `makeVisualizer()`: return `SpectrumFountainVisualizer()` / `FireworksVisualizer()`.
- `next`/`previous` use `allCases` and need no change.

### 5.3 No other code changes

- `MetalView` already caches the active visualizer by style — state persists.
- Visualizer menu, ⌘]/⌘[, and the Settings picker iterate `allCases` — both new styles appear automatically.
- The bloom pipeline applies to any rendered geometry — both styles glow when Glow is on.
- The render probe already takes `--render-probe <path> <style> [glow]` and picks visualizers via `VisualizerStyle(rawValue:).makeVisualizer()` — both new styles probe-renderable with no probe change.

## 6. Particle pool model (shared shape, each file's own)

Each visualizer owns its own `Particle` struct + pool array of fixed size. A particle has:
`position: SIMD2<Float>`, `velocity: SIMD2<Float>`, `size: Float`, `age: Float`, `lifetime: Float`, `colorPos: Float`, `active: Bool`. Spawn = find the first inactive slot (or, when full, overwrite the oldest active). Emit only `active` slots. `brightness(forAge)` fades linearly from 1 → 0 over `lifetime`. Aspect correction applied at emission so dots are square on screen (the same `sx = 1/aspect` if `aspect ≥ 1`, else `sy = aspect` pattern used elsewhere).

## 7. Testing strategy

**Unit-tested per visualizer:**
- Vertex count is `activeCount × 6`, bounded by `maxParticles × 6`.
- After a fixed call sequence, all emitted vertex positions are within clip space (margin ±1.25).
- Deterministic: two fresh instances with the same seed fed identical frames produce identical vertex output.
- **Bass response (each style's defining behavior):**
  - **Fountain**: after several loud-band frames, active particle count (proxied by total vertex count / 6) is greater than after the same number of silent frames.
  - **Fireworks**: simulating a rising-edge beat (one frame with bass below threshold, then one with bass above) yields more active particles than continuous silence (proves the trigger fires and spawns).

**`VisualizerStyleTests` updated** for the 7-case `allCases`, the new wrap targets for `.next`/`.previous`, plus a small factory assertion for each new style (`is SpectrumFountainVisualizer` / `is FireworksVisualizer`).

**Verified by running:**
- `--render-probe /tmp/p.png fountain` and `... fireworks` produce particle snapshots (single-frame initial layouts — static, dim before bass for fireworks, and a thin first row for fountain since `dt = 0` on the first call means no growth from gravity). With `glow` they show subtle halos.
- Live: switching to each style (⌘], menu, or picker) shows the expected behavior — a spectrum fountain spraying upward in colored columns; bursts on bass beats at varied positions. User-confirmed.

## 8. Risks & mitigations

- **Pool capping behavior:** when the pool fills under sustained loud bass (fountain) or rapid beats (fireworks), overwriting-the-oldest can cause a particle to "teleport" to a new spawn position. *Mitigation:* particles already despawn by age/off-screen, so steady-state never fills the pool under reasonable settings; the cap is the safety net.
- **First-call `dt = 0`:** like `ParticleVisualizer`, the first `makeVertices` advances nothing. For fountain this means the first frame's static probe shows only one row of just-spawned particles. Acceptable; live (after a few frames) the spray develops.
- **Beat-detector strobing:** continuous bass slightly above threshold could retrigger every frame without hysteresis. *Mitigation:* `beatHysteresis` (e.g. 0.1) + `refractoryPeriod` (e.g. 0.15 s).
- **Per-frame array allocation for vertex output:** matches every other visualizer; not a regression.
- **Two small RNG copies (one per file):** duplication of ~10 lines, kept private to each file. *Mitigation:* if it bothers a future change, promote a shared internal `SeededRNG` then; YAGNI for now.

## 9. Out of scope / future
- Surfacing per-style tunables in Settings (gravity, spawn rate, burst size, threshold). Constants are tuned live; surface later if needed.
- Beat detection at the analyzer level (so all styles share one beat signal). Each beat-reactive visualizer currently computes its own bass.
- Replacing the existing `.particles` with a generalized "particle engine" — keep as separate classes; clearer and isolated.
