# Changelog

All notable changes to this project are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Each released version also has a matching `vX.Y.Z` git tag.

## [0.2.0] - 2026-11-21

### Added
- **Engraved hub finish** for the Spinner (third finish, after Lit and Raised): unlit, the hub marks are cut into the polished hub as channels with a dark matte floor and light walls, no glow. Choose it in Settings > Spinner > Look > Hub finish or cycle with `c`; it switches instantly in RealityKit. In the classic shader renderer it is a simpler dark channel with a wall shadow, and in black zirconium and titanium the polished face is dim, so the cut reads mainly through its edges.
- **Spinner keys**: `Option+t` / `Option+Shift+t` yaw right / left (the same as `y` / `Shift+y`), and `Option+0` flips the disc about the vertical axis (see Changed for `0`). The cheat sheet (`?`) lists them with lowercase key names.
- **Acknowledgements window** (MacVisualizer > Acknowledgements…, or right-click the visualization > Acknowledgements…): Credits (`NOTICE`), Third-Party Licenses (`THIRD_PARTY_NOTICES.md`) and License (`LICENSE`) rendered from the bundled files, under a header with the icon, version, copyright, licence and repository link. The About panel now carries credits (description, licence, repository, and a pointer to Acknowledgements). New probe `MacVisualizer --acknowledgements-probe <outdir>` renders each section in light and dark to PNGs.
- `NOTICE` and the README now name the Spotify public track page (used for the lyrics length correction) among the network services, and both have a Trademarks section (the product names used are trademarks of their owners; the project is independent of them).

### Changed
- **Track card click**: clicking the card now brings Spotify or Apple Music forward and also restores the player's window if it is minimized or closed (0.1.0 only brought a running player to the front). A double-click on the card no longer toggles full screen; double-click elsewhere in the window still does.
- **Spinner rotation keys repeat while held**: `t`, `Shift+t`, `y`, `Shift+y`, `Option+t` and `Option+Shift+t` keep stepping by the rotation step while held; the other Spinner keys still act once per press.
- **`0` now resets or flips**: it still eases the disc back to the front by the shortest way, but pressed again while the disc is face-on it flips to the other side, tumbling about the horizontal axis (as if `t` were pressed until the other face shows); each further press flips again. `Option+0` does the same with the flip about the vertical axis. The two chain in any order, and any pose that is not face-on resets first. The Settings "Reset orientation" button only resets. In the classic shader renderer, which ignores yaw, `Option+0` changes only the side the scroll wheel pushes for.
- **`c` cycles three hub finishes** (lit, raised, engraved) instead of two.
- **Spinner Option-drag locks the window**: while the Spinner is active and Option is held (and through a whole drag, even if Option is released mid-drag), the window cannot be moved by dragging its background, so an Option-drag rotates the disc instead of moving the window. The lock is released when the window or the app loses focus.
- **RealityKit hub marks are real geometry** for all three finishes (a cut channel with a floor and walls for Lit and Engraved, a mark standing proud for Raised, meshed from the same stroke lists the classic shader draws), replacing the generated hub textures. The classic shader still paints its marks. The 2048-pixel hub texture sets are no longer generated.
- Key names in the README, the cheat sheet and the Visualizer menu titles are lowercase (`h`/`l`, `j`/`k`, `r`, `f`, `m`, `c`, `b`, `u`, `g`); the keys themselves are unchanged.

### Removed
- `MacVisualizer --rk-hub-check` (it compared the hub texture generator with its reference; the generator is gone).

## [0.1.0] - 2026-11-21

First public release.

### Visualizations
- **25 visualizer styles**: Bars, Radial, Mirrored, Oscilloscope, Particles, Fountain, Fireworks, Ribbon Wave, Wireframe, Plasma, Bumpscope, Joy Plot, Heightfield, Voronoi, Lava Lamp, Beat Counter, Polartone, Octave Meatballs, Star Nest, Outrun the Rain, XY Scope, Iris, Tricentric, Musical Spectrum and Spinner. Several have multiple render modes (for example Voronoi cells / blobs / soft cells, Lava Lamp shader / marching squares, Heightfield wireframe / solid).
- **Spinner**: a machined-metal two-sided disc you spin with the scroll wheel, with friction, a direction lock, a choice of metals (steel, brass, copper, black zirconium, anodized titanium), two hub finishes (lit and raised, switched instantly with `c`), a fixed interlocked mark on the front hub and sign-off mark on the back hub, and speed-dependent spin blur. It stays visible while it is spinning, can be driven by the music (sustain / kick), and makes a bearing hum that follows its speed. Needs macOS 15 and is hidden on older systems (the deployment target stays macOS 14.4).
  - **Settings, saved**: every choice is a persisted per-style setting (`StyleProfile.spinner`) with a Controls panel in Settings (sections Motion, Look, Shadow, Sound & Music, Renderer), a reset arrow per control, undo, and save-as-my-defaults. Motion: friction (x0.2 to x5), push strength (x0.25 to x4), top speed (20 to 120 rad/s), direction lock, rotation step (5, 10, 15, 30 or 45 degrees). Look: metal, hub finish, glow brightness (0 to 200%), room light (30 to 160%), size (40 to 150%), spin blur (0 to 150%). Shadow: darkness (0 to 85%), spread (x0.3 to x3), distance (0 to x2.5). Sound & Music: hum on/off, hum volume (0 to 150%), music mode, sustain (0 to 100%), kick (0 to 6 rad/s). Renderer: RealityKit or the classic shader. The keys `m`, `c`, `b`, `u` and `g` write the same settings. Only orientation, spin angle and speed are not saved. Every option takes effect immediately in both renderers.
  - **Hum rule**: the hum is only heard when no music is playing. Any music activity (a player reporting a track playing, captured audio above the idle level, or Demo Mode) silences it with a fade of about 0.8 s, and it returns, fading in over about 3 s, only after 6 seconds of continuous silence, so the gap between songs or a quiet passage never lets it back. It is also silent for the first 6 seconds after launch.
  - **Renderers**: RealityKit is the default on macOS 15+ (a lit physically based puck with a difference-based soft shadow, rendered into a square region centred on the puck so the cost follows the puck's size, not the window's, and moving the puck never reallocates). The classic fragment-shader renderer is shown as a stand-in while RealityKit loads (setup starts when the Spinner becomes the active style, including at launch, and takes about 3 seconds in a Debug build), is the fallback below macOS 15, and is selectable with `g`.
  - **Orientation**: pitch about the screen's horizontal axis and yaw about its vertical axis, yaw applied after pitch, eased over about 0.35 s. `t` / `Shift+t` pitch forward / back and `y` / `Shift+y` yaw right / left by the rotation step, `0` resets by the shortest way, and Option+left-drag rotates freely (a drag below a 4-point threshold is still a click; when the app-wide mouse modifier is also Option, the click action fires on release only if the press never became a drag). The scroll wheel pushes the same way on screen on either face. The hub buttons turn about the disc's own axis so each mark always reads upright and unmirrored, at every pose.
  - **Other bare keys while it is active**: `m` metal, `c` hub finish, `b` music mode (off / sustain / kick / both), `u` hum on/off, `g` renderer. The cheat sheet (`?`) lists them.
  - **Known limitations**: Anodized Titanium's colour-shifting film exists only in the classic shader (RealityKit draws plain titanium grey); the shader renderer shows pitch only and ignores yaw; with Shadow distance at 0 RealityKit leaves a thin dark edge around the disc.
- Real-time audio analysis (vDSP FFT), adaptive beat detection and stereo-aware visualizers with an L/R split.
- 14 color palettes with HDR-boosted variants, palette cycling with crossfade, bloom on a full rgba16Float pipeline, trail persistence, vignette and film grain, a kaleidoscope post-process, a global output dimmer and an FFT window selector.
- Demo mode for when no music is playing. With no music the visualization and lyrics ease out over 2 seconds and ease back in when audio returns; rendering drops to 10 fps while idle.
- Per-visualization frame rate (Use global / 30 / 60 / 120).

### Lyrics overlay
- Time-synced lyrics drawn over the visualizer with a line-aligned English translation (original left, translation right); songs already in English show as a single centered column, including English songs with a short passage in another language. Lyrics come from [LRCLIB](https://lrclib.net); translation uses Google's Gemini API (one call per song, cached). Translation assumes Spanish.
- The song title and performer open the lyrics as the first line; a song with no lyrics shows just the title and performer, which then drift away, and the visualization recenters.
- Appearance controls: text size, block width, active-line position, active and other-line colors, other-line opacity, past-line treatment, distance fade and a configurable drop shadow.
- **Beat bounce**: the active line's drop shadow pulses to the beat (Off / Lift / Glow / Both, with a strength), driven by a dedicated bass-energy onset follower.
- **Local `.lrc` folder** used before LRCLIB, approximate matches (closest recording within about 30 s, flagged as approximate) and a lyric timing offset.
- Correct length for Spotify with Crossfade on, and mis-timed LRCLIB records are skipped for a correctly timed one. English lyrics are cached too.
- Smooth motion: the translation eases in, songs crossfade, and the lyrics fade out promptly on pause or stop.
- `MacVisualizer --lyrics-probe` prints what LRCLIB returns for the current track (counts and classifications only, never lyric text or the API key). The Gemini API key is stored in an owner-only file outside `settings.json`; lyric text and the key are never logged.

### Track overlay
- A now-playing card with album art, title and performer. Hover enlarges it (crisp, clamped to the window) and holds it at full; click brings Spotify or Apple Music to the front. It blooms on a song change, re-blooms when the song restarts, and stays on screen while a track is playing, independent of the lyrics. The lyrics keep clear of it when it is in a top corner.

### Audio capture
- Captures Spotify and Apple Music at once through a Core Audio process tap, clocked to the default output device, so switching players needs no re-setup.
- Starting, rebuilding and stopping capture run off the main thread, so the window opens at once even when the audio service is slow; repeated rebuild requests are merged.
- Recovers on its own: follows the default output device (a Bluetooth speaker reconnecting or waking, or switching outputs, rebuilds the tap), a stall watchdog rebuilds a capture that has gone silent (with backoff while nothing is playing), and a failed rebuild is retried every 5 s. Stall rebuilds are not started while no track is playing, and the watchdog waits for an in-flight rebuild to finish. Capture start, stop and any Core Audio call over 50 ms are logged (category `audio-capture`).

### Settings and input
- Settings is a sidebar with a Global section (app-wide) and a per-visualization section headed by the active style; controls with no effect on the active style are disabled with a tooltip. Each style's settings are remembered per style (with an apply-to-all toggle), including its position offset.
- Reset to default for every setting (a small button beside any modified control; Option-click for factory), saved "my defaults", whole-style and whole-app resets, and settings undo / redo (⌘Z / ⌘⇧Z).
- Bare-key controls: `H`/`L` previous/next visualization, `J`/`K` next/previous palette, `R` random, `,`/`.` previous/next song, `Space` play/pause, `F` full screen, `?` cheat sheet (`Esc` closes it). They also work in the Settings window.
- Mouse controls with a modifier held (Shift by default; Off / Shift / Option / Command): click = previous visualization, right-click = next, middle-click = random, scroll = palette. A right-click menu offers Settings, Lyrics and Layout settings, visualization, palette and player controls.
- Player transport for Spotify or Apple Music from the keyboard and menus. Menu shortcuts: ⌘B borderless, ⌘⇧B window border, ⌘T always on top, ⌃⌘C click-through, ⌘L lyrics, ⌥⌘D demo mode, ⌃⌘F full screen. In Settings, ⌘1–⌘9 / ⌘0 jump to a category and ⌘F focuses the filter.

### Window
- Per-pixel-alpha window transparency (default) or uniform opacity, click-through mode, borderless mode and always on top.
- Window border mode (Off / Auto / Always): in Auto a click reveals a thin resize outline and its drop shadow, which fade when idle. Position offset and Center below lyrics for centered styles. The window reopens at its saved position and size, on the same monitor.
- The saved window frame is applied and laid out immediately at launch, and the border fade animates only the border stroke, which avoids an AppKit layout loop when the window is resized while an animation runs. Window identity and frame restore are logged (category `window`).
