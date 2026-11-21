---
name: verify-visualizer-changes
description: Use after any code change that affects rendered output — new styles, tuning constants, render-mode changes, post-process effects, shader edits, settings that visualizers consume. Not optional; treat as part of "done." Tests verify code correctness, not feature correctness — only eyes can confirm whether the output looks right.
---

# Verifying Visualizer Changes

## When this skill applies

Any change that affects pixels rendered to the screen:
- New visualizer style or render mode
- Modified tuning constants (decay rates, scale factors, thresholds, angles)
- Shader edits (`Sources/Rendering/Shaders.metal`)
- Post-process additions (composite_fs, bloom, trails, vignette, kaleidoscope)
- Settings that visualizers consume (palettes, stereo image toggle, render-mode pickers)
- Beat / stereo / track-ID plumbing changes that downstream visualizers might react to

If the change is purely refactor (rename, extract helper, comment, test-only), this skill does not apply.

## Why this exists

Tests verify code correctness; they do not verify feature correctness. A Voronoi cells test with uniform-amplitude bands passes regardless of whether bass appears at the edges or the center of the screen. A beat-detector test with synthetic kicks passes whether the detector responds reasonably on real music or not. A heightfield projection test passes even when the rendered grid is clipped off-screen.

**The post-cluster-A learning** (documented in user auto-memory as `feedback_visual_validation_required.md`): A cluster shipped with bugs that hours of subagent review missed — a stereo-bars layout was inverted, a heightfield's Z projection was structurally broken, render-mode dispatch was wrong for default lavaLamp. A five-second visual look would have caught each one immediately. We don't make that mistake again.

## The workflow

Apply both steps. They catch different classes of bugs.

### Step 1: Offscreen render probe (deterministic, no GUI)

The probe path `Sources/Rendering/RenderProbe.swift` produces PNG snapshots without a window. Driving it programmatically is the right way to:
- Catch shader compilation errors before manual testing
- Spot structural issues (style emits zero vertices, scene is uniformly black, dispatch misroutes)
- Generate baseline images for visual diff against future changes
- Verify each render-mode of a multi-mode visualizer produces visibly distinct output

For each style × render mode combination affected by the change, generate one PNG with the built app binary: `MacVisualizer.app/Contents/MacOS/MacVisualizer --render-probe <out.png> <style> [renderMode] [glow]` (`<style>` is the `VisualizerStyle` raw value, for example `siri` for Ribbon Wave; the frame is a fixed synthetic AudioFrame, 800x400 by default). The Spinner takes comma-separated tokens as its render mode (`a<angle>`, `v<velocity>`, `m<metal>`, `h<finish>` (0 lit, 1 raised, 2 engraved), `p<pitchDeg>`, `y<yawDeg>`, `z<zoom>`, `t`, `g1` for RealityKit, `w<pixels>`; see CLAUDE.md "Spinner"). No snapshot directory is tracked in the repo: write the PNGs to a scratch location. Attach the PNGs to any final-review subagent for visual inspection.

Caveat: `screencapture` is permission-blocked in this environment for live windows. The offscreen probe is the only automated visual artifact we can produce.

### Step 2: Ask the user to launch the live app

After tests + probe pass, ask the user to:
1. Run the build: `! open DerivedData/Build/Products/Debug/MacVisualizer.app` (the `!` prefix runs it in the session) or via Finder.
2. Play real music (Spotify or Apple Music — both supported).
3. Walk every affected style / render mode / setting combination.
4. Report anything visibly wrong.

Provide an explicit checklist of what to verify. Be specific:
- "Switch to Voronoi → Cells mode → confirm sharp polygon edges with audio-modulated brightness"
- "Toggle Use stereo image ON → confirm left half responds to left channel"
- "Hit a percussive track → confirm beat triggers visible effect in Fireworks/Particles/Fountain"

The user has eyes you don't. They will spot:
- Layouts inverted (bass at wrong screen edge, Y-axis flipped, aspect-ratio borders)
- Tuning values that "work" mathematically but look broken on real music
- Render-mode pickers that produce identical-looking output (mode does nothing)
- Visual artifacts (stairstepped edges, dark gaps, clipping off-screen)
- Aesthetic mismatches with existing styles (new style looks out of place)

## What "done" means

A behavior-changing change is done when:
1. `make test` passes
2. Code-review subagent approves spec compliance + code quality
3. Offscreen probe PNGs look right (final-review subagent inspects them)
4. User has launched the live app, walked the affected paths, reported "looks good" or specific issues addressed

Skip any of those four and you risk shipping a regression that adds hours of post-merge fix-forward work.

## Anti-patterns to avoid

- **"Tests pass so we're done"** — see "Why this exists" above
- **"The diff is small, no need to verify visually"** — small changes to shaders or tuning constants are exactly the changes most likely to break the output silently
- **"User can test after merge"** — they won't, and the bug will compound with the next cluster
- **"Render probe alone is enough"** — the probe runs synthetic frames; real music exposes tuning issues the probe can't
- **"User said 'looks good' for one style, that covers all"** — verify every style affected, individually

## Integration with the superpowers workflow

This skill is the visual-validation half of `superpowers:subagent-driven-development`'s final-task pattern. The plan's final task should include:

1. `make clean && make build && make test` — clean baseline
2. Final code-review subagent over the full branch diff
3. **Invoke this skill** — render probe + user walk
4. Only after Step 3 passes: hand off to `superpowers:finishing-a-development-branch`

Future plans for cluster work in this repo should incorporate this skill explicitly in the final-task description, not as an "optional smoke check."
