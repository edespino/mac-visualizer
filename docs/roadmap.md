# Mac Visualizer — Feature Roadmap

A forward-looking backlog. Each open entry includes the source, scope, effort, and pointers to the relevant files. Pick one, brainstorm/spec/plan it via the superpowers discipline, ship it, mark it done.

**Status legend:** ⬜ not started · 🟡 in progress / partly done · ✅ done · ❌ rejected, superseded, or deliberately skipped

> **North Star (owner's intent).** The lasting value here is **learning other-language phrases through synced, translated lyrics** — the translation feature exists for this, not just to read along. The destination is **E4**: tap a line to capture a foreign phrase with its gloss and review it later, fed by the music you already play. The **visualizations are the ambient backdrop** — enjoyable "fidget spinners," but not why someone keeps the app open. So weight effort toward **Tier E (especially E4)**; treat the Phosphor-inspired visual features (**Tier F**) as opportunistic polish, and raw scene count as the least valuable axis.

**Critical path to the North Star:** **E3** (player control: transport + seek) → **E6** (any→any translation) → **E4** (phrase learning). E4 has no design yet; its brainstorm/spec is the next real step.

---

## Where we are today (the first release, 0.1.0)

A highlights list, not an inventory — `CHANGELOG.md` is the record.

- ✅ **25 visualizer styles:** Bars, Radial, Mirrored, Oscilloscope, Particles, Fountain, Fireworks, Ribbon Wave, Wireframe, Plasma, Bumpscope, Joy Plot, Heightfield, Voronoi, Lava Lamp, Beat Counter, Polartone, Octave Meatballs, Star Nest, Outrun the Rain, XY Scope, Iris, Tricentric, Musical Spectrum, Spinner — several with multiple render modes
- ✅ **14 palette presets**, HDR-boosted warm palettes on a full rgba16Float pipeline, palette cycling keys (J/K), and **palette auto-cycle** with crossfade (interval + fade duration)
- ✅ Per-style profiles (`StyleProfile`), Demo Mode, bloom, trail persistence, vignette + film grain, kaleidoscope post-process, FFT window selector
- ✅ Beat detection, stereo path, track ID plumbing (`AudioFrame`)
- ✅ Track overlay (album art + song/artist via ScriptingBridge)
- ✅ Lyrics overlay: time-synced lyrics with a line-aligned English translation (LRCLIB + Gemini), local `.lrc` folder, approximate-match, timing-offset, and active-line-position controls — group 1 (display) of the 5-group lyrics plan
- ✅ Lyric beat bounce: the active line's drop shadow pulses to the beat via a dedicated onset follower (`LyricBeatFollower`) on `AudioFrame.bassEnergy`
- ✅ Window border, centering, and idle fade: window outline; position offset and Center below lyrics; idle fade with no music; settings undo/redo
- ✅ Settings sidebar, hotkeys, app-wide migration, control relevance: Global vs per-visualization sidebar; keyboard shortcuts; track overlay / always-on-top / frame rate / position offset moved app-wide; irrelevant controls greyed out; window-position memory; smoother active-line scroll
- ✅ Lyrics song-title header, transitions, audio-capture recovery, non-Spanish English detection: title + performer as the opening scrolling line; fades and cross-song crossfade; capture taps all target players, follows the default output device, and self-heals on route changes / Bluetooth clock stalls; English songs with a foreign section recognized as English
- ✅ Spinner: a machined-metal two-sided disc spun with the scroll wheel; RealityKit renderer by default on macOS 15+ (classic shader renderer as stand-in, fallback and `g` alternative); pitch / yaw orientation with keys and Option-drag; lit and raised hub finishes; five metals (the anodized titanium film is shader-only); music-driven spin and a bearing hum that is silent whenever music is playing; every choice is a saved setting with a Settings panel. Limitations are listed in `CLAUDE.md` ("Spinner") and `CHANGELOG.md`
- ✅ Audio capture lifecycle off the main thread with coalesced requests and a completion-driven, playback-gated watchdog with escalating backoff
- ✅ Track overlay & window border: the track card enlarges on hover (crisp oversampled art, clamped to the window width), holds while hovered, carries a drop shadow, and re-blooms when a song restarts; clicking it activates the player without tripping App Management; window border modes off / auto / always, where auto reveals the outline and shadow on a deliberate click and fades them when idle; a no-lyrics song's title scrolls off and the visualization recenters

---

## Completed backlog items (one line each)

Full write-ups live in the plans under `docs/superpowers/plans/`.

- ✅ **A1. HDR-boosted palettes** (plan-13) — palette stops above 1.0 feed the bloom pass. Idea source: UnityAudioVisualizer's HDR particle gradients.
- ✅ **A2. Wireframe mesh visualizer** (plan-14) — audio-deformed icosphere. Idea source: UnityAudioVisualizer `WireFrame.shader` (Apache 2.0).
- ✅ **A3. FFT window functions** (plan-13) — rectangular / Hann / Hamming / Blackman. Idea source: AudioVisualizerKit `FFT.swift`.
- ✅ **B1. Plasma** (plan-15) — per-pixel sin-interference shader. Ideas only from libvisual's `plazma` (GPLv2; re-implemented from scratch).
- ✅ **B2. Bumpscope** (plan-15) — audio-lit heightfield shader. Ideas only from libvisual's `bumpscope` (GPLv2; re-implemented from scratch).
- ✅ **B3. Kaleidoscope post-process** (plan-15) — N-fold UV mirror inside `composite_fs`.
- ✅ **C2. Vignette / film grain** (plan-13) — inside `composite_fs`.
- ✅ **CC1. Shared `SeededRNG`** (plan-16) — consolidated from 5 duplicates into `Sources/Core/SeededRNG.swift`.
- ✅ **E5. Graceful no-key fallback** — see Tier E.

---

## Tier C — UX polish

### C1. Style auto-cycle 🟡 (palette half shipped)

Palette auto-cycle is done (`paletteCycleEnabled` / interval / fade duration, the "Palette Cycle" Settings category). What remains is the **style** half: a "cycle visualizer every N seconds" toggle for set-and-forget viewing. **F2** (Director) is the audio-reactive mode of this same feature — build them as one selector with two modes (timer, audio-driven).

- **Source:** general visualizer convention (Winamp had this).
- **Where:**
  - `Sources/Core/VisualizerSettings.swift` — `styleCycleEnabled: Bool`, `styleCyclePeriod: Double` (seconds), mirroring the palette-cycle fields.
  - `Sources/App/RenderModel.swift` — a timer that advances the style; reuse `randomizeStyle()` / `VisualizerSettings.randomEnabledStyle` so disabled styles are skipped.
  - `Sources/App/SettingsView.swift` — controls in the "Styles & Presets" category (or next to Palette Cycle).
- **Effort:** Small.
- **Edge case:** pause cycling while the Settings window is open, or leave it to the user to uncheck.

### C3. Screenshot export ⬜

Press ⌘S to save the current frame as PNG. Video capture is **F4**.

- **Where:**
  - `Sources/Rendering/RenderProbe.swift` already has `writePNG` for the probe. Reuse the texture read-back against the resolved scene texture.
  - `Sources/App/MacVisualizerApp.swift` — a File menu "Save Screenshot…" + ⌘S.
- **Effort:** Small (~40 LOC reusing the probe code).
- **Caveat:** the lyrics and track overlays are SwiftUI layers, not in the Metal scene texture; a scene-texture screenshot will not include them. Decide at spec time whether that is acceptable.

### C4. User-configurable capture targets ⬜

The tap captures **every running target player at once**, where the target set is the hardcoded `ProcessLocator.defaultTargets` (Spotify + Apple Music). Let the user add or remove audio-producing apps from that set (a browser, another player).

- **Where:**
  - `Sources/Services/ProcessLocator.swift` — `defaultTargets` becomes a settings-driven list; it already enumerates audio processes.
  - `Sources/Services/AudioCaptureService.swift` — it already rebuilds when the *set* of running targets changes; feed it the configured set.
  - `Sources/Core/TargetProcessSelection.swift` — the pure id-set picker (unit-tested) takes the configured bundle IDs.
  - `Sources/App/SettingsView.swift` — a target list in the "Analysis" category.
- **Effort:** Medium. Track info and lyrics still come only from Spotify / Apple Music (ScriptingBridge), so extra targets get visualization only.

---

## Tier D — heavy / niche (deliberately skipped)

### D1. ShaderToy-style custom Metal shader slot ❌

Let the user plug in a custom fragment shader. Skipped: niche audience, and runtime compilation of user-supplied Metal brings a support and maintenance burden (shader errors, uniform contract, licensing of pasted shaders) out of proportion to its value here.

### D2. Spotify Track Analysis integration ❌

Drive visualizers from the Spotify Web API's audio-analysis data. Skipped: heavy (OAuth, token storage, time-sync), brittle, and Spotify-only.

### D3. Network sync (multiple Macs showing the same visualization) ❌

Skipped: very heavy (networking, time sync, multi-display).

---

## Tier E — lyrics: the North Star tier

The lyrics overlay shipped as group 1 (display) of a 5-group plan; see `docs/superpowers/specs/2026-11-11-lyrics-overlay-design.md`. **This tier holds the North Star**: E4 (phrase learning) is the destination, reached through E3 (player control) and E6 (any→any translation). E5 (graceful no-key fallback) is done; with the translation path still hardcoded Spanish→English, E6 is the single blocker for the North Star beyond Spanish. E1–E2 are smaller supporting follow-ons. Explicitly rejected: the Spotify internal color-lyrics endpoint (TOTP-gated access control; the local `.lrc` folder covers the same gap with the user's own data).

### E1. Line editing ⬜

Let the user correct a wrong translation or original line in place, persisted to the cache's `editedEs`/`editedEn` fields (present in `TranslationLine` in `Sources/Core/LyricsCache.swift`, unused for now).

- **Effort:** Medium — an editable overlay/row interaction plus cache write-back. The overlay is non-interactive today, so this needs a hit-testing decision.
- **Note:** if E6 lands first, these fields are renamed along with `es`/`en`.

### E2. Reject a wrong LRCLIB match ⬜

A control to reject the current (wrong) LRCLIB entry by its `lrclibId` and fall through to the next candidate or the local folder. `lrclibId` is already carried in the cache entry and `LyricsResult.synced`.

- **Effort:** Small-medium.

### E3. Player control — transport + seek 🟡 · first step on the critical path (absorbs F1)

**Status:** transport shipped (play/pause, next, previous via bare keys `Space` `.` `,`, the menu bar and the right-click menu; `PlayerReader.send`). **Seek and tap-a-line-to-seek remain**, as do optional controls on the hovered card.

Control Spotify / Apple Music from inside the app: play/pause/next/previous, plus **seek** to a timestamp. `PlayerReader` reads (`playerPosition`, track fields) and sends the transport verbs (`PlayerReader.send`: play/pause, next, previous); there is no seek verb yet. One piece of plumbing serves two uses: everyday transport controls (Phosphor's dev said media controls "turned out to matter") and re-hearing a tapped lyric line, which E4's review loop is built on.

- **Source:** Phosphor media controls; the lyrics plan's replay group.
- **Where:**
  - `Sources/Services/PlayerReader.swift` / `NowPlayingService.swift` — add play/pause/next/previous and `set player position` over the same ScriptingBridge path used for reads (wrapped in the Obj-C exception shim like the reads).
  - `Sources/App/TrackOverlay.swift` — optional controls on the enlarged (hovered) card.
  - `Sources/App/MacVisualizerApp.swift` — menu items + hotkeys.
  - `Sources/App/LyricsOverlay.swift` — tap-a-line-to-seek (requires the overlay to accept clicks; it is non-interactive today).
- **Effort:** Small for transport; Medium with tap-to-seek on lyric lines.
- **Decisions to lock at spec time:** which controls live on the card vs hotkeys only; whether a seek-to-start should bump `replayNonce` the way a restart does (it will, via the position-drop detection — confirm that is wanted).

### E4. Language-phrase learning ⬜ · the North Star (why translation exists)

**The actual purpose of the lyrics + translation work**: the owner added translation to learn other-language phrases, not just read along. Turn the lyrics into a phrase-learning tool — tap a line to extract learnable chunks (Gemini), save them to a persisted deck carrying the song / line / timestamp, and review with song-clip replay: a spaced-repetition surface fed by the music you already play. Build it language-pair-agnostic so it serves whatever you're learning, not just Spanish.

- **Effort:** Large — new persisted store, a review/SRS surface, Gemini phrase extraction.
- **Depends on:** E3 (seek/replay), E6 (any→any translation).
- **Status of design:** none. **Next action: brainstorm + spec.** It can be designed before E3/E6 are built, and doing so will sharpen what those two must deliver.
- **Decisions to lock at spec time:** what a "phrase" is (whole line vs model-extracted chunk); where review happens (in the visualizer window, a separate window, or export to an existing SRS tool such as Anki); deck storage format and location (user data — outside the repo and `settings.json`, like the lyrics cache); how capture works on a non-interactive overlay; what happens with no Gemini key.

### E5. Graceful no-key fallback → single column ✅

Without a Gemini API key the app now shows the lyrics untranslated — single centered column, the layout English songs already use — for **any** language, instead of a half-empty two-column view. Previously a non-English song with no key committed to two columns and then bailed, leaving a blank translation column. Fixed: `LyricsModel.translate()`'s no-key branch re-emits the synced rows as single-column (`singleColumn: true`, each `LyricRow.translation` nil) and sets `status = .noKey`, keeping `pending` set so a key added later still triggers a retry.

- **Where:** `Sources/Core/LyricsModel.swift` — the no-key branch of `translate()`.
- **Test:** `Tests/CoreTests/LyricsModelTests.swift` — `testNoKeyShowsSpanishOnly` asserts `display?.singleColumn == true`.

### E6. Any-language → any-language translation ⬜ · the blocker for E4 beyond Spanish

Today the pipeline is hardcoded **Spanish → English**: `LyricsTranslator`'s prompt says "Translate these Spanish song lyrics to English" (`LyricsTranslator.swift:73`), `EnglishLyricsDetector` is an English-vs-Spanish heuristic, and the cache fields are literally `es`/`en`. Generalize to an auto-detected (or overridden) source and a user-chosen target language.

- **Where:**
  - `Sources/Core/LyricsTranslator.swift` — parameterize the prompt with source/target language names.
  - `Sources/Core/EnglishLyricsDetector.swift` — replace the English/Spanish test with "is the lyric already in the target language?"
  - `LyricsSettings` (nested at `settings.lyrics`) + `Sources/App/SettingsView.swift` — a target-language picker (and optional source override).
  - `Sources/Core/LyricsCache.swift` — `TranslationLine` `es`/`en` (and `editedEs`/`editedEn`) become source/target-agnostic.
- **Effort:** Large — detection, prompt, settings, and the cache schema.
- **Why it's tractable:** translation is AI-driven (Gemini), which already handles arbitrary language pairs — so this is a prompt + detection + settings generalization, not a new engine per language. Bounded only by lyric availability (LRCLIB / local `.lrc`).
- **Decisions to lock at spec time:**
  - **Detection strategy:** keep a local no-network heuristic per target language (today's detector is tuned for English only and encodes hard-won cases — "Espresso," "Dazz," "Forever," "Psycho Killer"), or let the model report "already in target language" at the cost of one call per uncached song. A hybrid (local fast path for English target, model otherwise) preserves the existing tests.
  - **Cache migration:** existing entries are keyed by song, not by language pair. Decide whether the key gains the target language, how old `es`/`en` JSON keeps loading (CodingKeys raw values, per the project's backward-compat convention), and that a cached Spanish→English entry must not be served when the target changes.
  - **Mixed-language songs:** the "Psycho Killer" path (English song, French refrain) shows a per-song language label is a simplification; decide whether detection is per-song or per-line.

---

## Tier F — Phosphor survey: durable utility over more "fidget spinners"

Phosphor ([getphosphor.com](https://getphosphor.com)) is a near-identical-stack macOS visualizer — Core Audio Process Tap, hand-written Metal shaders per scene, macOS 14.4+ / Apple Silicon — that ships ~150 scenes plus wallpaper mode, video recording, and an Apple-TV companion. Surveying it is useful, but with a bias: **the visualizations themselves are "fidget spinners"** — fun for a minute, no lasting pull, and *more* of them is the least sticky thing we can build. The durable value is the layer Phosphor lacks — lyrics, translation, the now-playing card, and phrase learning (**Tier E**) — plus a few utility features that give a *reason to keep the app open*. Prioritize by staying-power, not eye-candy.

> Licensing: feature ideas aren't copyrightable, so every item below is an independent/clean-room build. The only item with a real copyright hook is **F5** (porting a specific Shadertoy scene), which follows the `NOTICE` / `THIRD_PARTY_NOTICES.md` attribution policy. No NOTICE entry is needed to borrow a generic feature concept.

### F1. Transport controls ❌ (merged into E3)

Same ScriptingBridge control plumbing as lyric seek; tracked as **E3**.

### F2. Director — audio-driven auto-scene selection ⬜

Auto-pick the visualizer from the audio using heuristics (bass / onset / tempo / spectral flatness — "no ML"). Drops → high-energy styles, ambient passages → calm ones. We already compute `frame.beat`, `beatIntensity`, `bassEnergy`, and bands, so the signals exist. This is the audio-driven mode of **C1** (style auto-cycle) — one selector, two modes.

- **Source:** Phosphor "Director" mode.
- **Where:** `Sources/App/RenderModel.swift` — a selector that switches `settings.visualizerStyle` on the heuristics; put the pure decision logic in `Sources/Core` so it is unit-testable.
- **Effort:** Small-medium on top of C1.
- **Fidget-spinner caveat:** this makes the spinners spin themselves — nice for ambient/party, but still eye-candy.

### F3. Wallpaper mode — animate behind desktop icons ⬜ · durable utility (ambient)

A real `NSWindow` at the desktop-icon window level (not a screensaver hack), so the visualizer lives behind your windows as ambient motion rather than something you stare at. The one *visual* feature with staying power, because it changes the mode of use from "watch" to "always on."

- **Source:** Phosphor wallpaper mode.
- **Where:** `Sources/App/MacVisualizerApp.swift` `WindowConfigurator` — it already does transparency / borderless / always-on-top (window level is only `.floating`/`.normal` today); add a desktop-level window level + behind-icons placement and a mode toggle.
- **Effort:** Medium.
- **Decisions to lock at spec time:** how the user gets back out (a behind-icons window receives no clicks — menu bar item or hotkey); interaction with click-through, the auto window border, and per-style `fullscreenDisplayID`; whether lyrics show in wallpaper mode.

### F4. Video / clip recording with audio ⬜ · sharing = reach

Export MP4 / ProRes of the visualization *with* the system audio that drove it. Gives a reason to return (make/share clips) and is how a visualizer spreads. Extends **C3** (screenshot) to video.

- **Source:** Phosphor recording.
- **Where:** `Sources/Rendering/RenderProbe.swift` has texture read-back; add an `AVAssetWriter` path capturing the resolved scene texture + the tapped audio buffer; a record toggle + File menu item.
- **Effort:** Large (frame pacing, dropped frames, A/V sync).
- **Caveats:** same as C3 — the SwiftUI lyrics/track overlays are not in the scene texture. Recording captured third-party music also has redistribution implications for whoever shares the clip; say so in the UI or docs.

### F5. More scenes via curated permissive Shadertoy ports ⬜ · low priority (the fidget-spinner axis)

Phosphor ships ~150 scenes; we have 25. We have the pipeline (`ShaderKind` + the "add a fragment-shader visualizer" flow) and the licensing discipline. **Deliberately low priority**: breadth is the least sticky axis. Add a *few* high-impact looks, don't chase the count.

- **Where:** `Sources/Core/ShaderKind.swift`, `Sources/Rendering/Shaders.metal`, `VisualizerStyle` factory.
- **Effort:** Medium / ongoing.
- **Licensing:** each port — verify the author declared a permissive license (Shadertoy default is CC BY-NC-SA, which is NOT usable) → `THIRD_PARTY_NOTICES.md` + inline credit header. Concept-only inspiration → `NOTICE`.

### F6. Stackable post-FX + full-look presets ⬜

Phosphor stacks 8 post-effects on any scene and saves presets (scene + FX + layering). We have bloom / trails / vignette / grain / kaleidoscope but no arbitrary stacking, scene layering, or named "whole look" presets (the "Styles & Presets" Settings category refers to palette presets only). A preset system (capture everything, recall by name) has more staying value than another individual effect.

- **Where:** `Sources/Rendering` composite pipeline; a presets store adjacent to `StyleProfile`; the "Post-FX" / "Styles & Presets" Settings categories for save/recall.
- **Effort:** Medium.

### Explicitly deprioritized from the survey

- **Apple-TV companion** (Phosphor "Link"): interesting, out of scope.
- **Chasing scene count for its own sake** — the fidget-spinner trap; see F5.

**Suggested Phosphor slice (by staying-power):** **F3** (wallpaper) first — it reuses window code we already have and changes how the app is used day-to-day — then **F4** (recording) when we want reach. Treat **F2/F5/F6** as eye-candy to add opportunistically. Transport controls are on the North Star path as **E3**.

---

## Cross-cutting / infrastructure items

### CC2. Move single-style tunables into per-style profiles ⬜ · overdue — needs a decision

`VisualizerSettings` carries roughly 90 top-level fields that each apply to one style (polartone, star nest, wireframe, outrun rain, particle/bar/oscilloscope knobs). The original deferral trigger ("12+ top-level tunables") passed long ago. `StyleProfile` exists and holds the shared per-style fields; the style-specific knobs never moved. Either do the refactor or record it as a conscious non-goal — the current state is neither.

- **Effort:** Large now — the tolerant decoder, a JSON migration for every moved key (old flat keys must keep loading), the Settings "Controls" panels, and the tests.
- **Argument for leaving it:** it works, the decoder is tolerant, and it does nothing for the North Star.

### CC3. Per-style trail persistence ⬜

`trailPersistence` is one global value on `VisualizerSettings`. Could be per-style (each profile picks its own).

- **Effort:** Small if combined with CC2; standalone ~30 LOC plus the decoder migration.

### CC5. Shared defaults for per-style settings ("use global unless overridden") ⬜ · deferred on purpose

- **Idea (2026-11-20):** a second level between app-wide and per-visualization: one shared value for the settings every style has, which each style follows unless it sets its own. Frame rate already works this way (`targetFPS` + `StyleProfile.frameRateOverride`, "Use global").
- **Scope:** palette, gain, smoothing, glow on/off and intensity, background. NOT style-unique tunables (nothing to inherit), NOT app-wide settings, NOT position offset (tuned per style on purpose).
- **Replaces:** the "Apply edits to all styles" switch, which is a one-off copy rather than a default.
- **Costs:** a value could then come from four places (style override, shared value, saved "my defaults", factory), so each control must show which is in effect; and existing profiles need a migration that decides which per-style values are real overrides.
- **Why deferred:** the per-control reset and saved "my defaults" shipped the same day and are unproven in use. Revisit once they have been lived with; do after CC2, which touches the same fields.

### CC4. Audio source: file playback for testing ⬜

For development: drop a `.wav` on the visualizer to play it through the analyzer. Repeatable visual testing without Spotify. No file source exists today (Demo Mode is procedural).

- **Effort:** Medium — an `AudioCaptureSource` implementation that bypasses the process tap.

---

## How to use this doc

1. Pick an item — by default the next one on the critical path (**E3 → E6 → E4**).
2. Run `superpowers:brainstorming` to lock decisions (each open item lists the ones it knows about).
3. Run `superpowers:writing-plans` to produce the implementation plan.
4. Execute the plan (`superpowers:subagent-driven-development` or `superpowers:executing-plans`).
5. Validate live — overlay and visualizer work is not done until it has been checked in the running app.
6. Run `superpowers:finishing-a-development-branch` to merge.
7. Come back here: collapse the item to one line under "Completed backlog items," and add a line to "Where we are today" once it ships in a release.

**Suggested order:**
- **E4 brainstorm/spec** now (design only) — it defines what E3 and E6 must deliver.
- **E3** (player control) — small, useful on its own, and unblocks E4's replay.
- **E6** (any→any translation) — the large one; lock the detection and cache-migration decisions first.
- **E4** build.
- Opportunistic, when a break from the main line is wanted: **F3** (wallpaper), **C1 + F2** (style auto-cycle / Director), **C3** (screenshot).
