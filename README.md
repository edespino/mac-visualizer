# mac-visualizer

[![CI](https://github.com/edespino/mac-visualizer/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/edespino/mac-visualizer/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
![platform: macOS 14.4+](https://img.shields.io/badge/platform-macOS%2014.4%2B-lightgrey)

A Mac desktop audio visualizer that reacts to the audio of Spotify and Apple Music, captured through a Core Audio process tap.

## Visualizer styles

25 styles across vertex-emit and shader-driven rendering: bars, radial, mirrored, oscilloscope, particles, fountain, fireworks, ribbon wave, wireframe icosphere, plasma, bumpscope, joy plot, heightfield grid, voronoi cells/blobs/softCells, lava lamp shader/marching-squares, beat counter, polartone, octave meatballs, star nest, outrun the rain, XY scope, iris, tricentric, musical spectrum, spinner.

**Spinner** (macOS 15 or later; the style is hidden on older systems): a machined-metal two-sided disc you spin with the scroll wheel. It keeps spinning with friction, stays visible while in use, and makes a soft bearing hum **that is only heard when no music is playing**. It is drawn by RealityKit, with the classic shader renderer shown for a moment while RealityKit loads (loading starts when the Spinner becomes the active style, including at launch; setup takes about 3 seconds in a Debug build). Every choice below is a saved setting (Settings, with the Spinner active: Controls, then the Motion, Look, Shadow, Sound & Music and Renderer sections); each has a reset arrow and an undo step, and the keys write the same settings. Only the orientation (pitch and yaw), spin angle and speed are not saved.

Keys, while it is active (`?` lists them):

| Input | Action |
|---|---|
| Scroll wheel | Spin the disc (the wheel pushes the same way on screen on either face) |
| `T` / `Shift+T` | Pitch forward / back, by the Rotation step setting (15 degrees by default) |
| `Y` / `Shift+Y` | Yaw right / left, by the Rotation step setting |
| `0` | Reset the orientation (the shortest way); also the "Reset orientation" button in Settings |
| `Option` + drag | Rotate the disc freely (horizontal = yaw, vertical = pitch) |
| `M` | Metal: steel, brass, copper, black zirconium, anodized titanium |
| `C` | Hub finish: lit or raised (switches instantly) |
| `B` | Music mode: off, sustain, kick, sustain + kick |
| `U` | Bearing hum on / off |
| `G` | Switch between the RealityKit renderer and the classic shader renderer |

Settings (default, range). Physics settings apply in both renderers; the Look and Shadow settings work in both renderers too.

| Section | Setting | Default | Range | What it does |
|---|---|---|---|---|
| Motion | Friction | x1.00 | x0.2 to x5 | Multiplies both friction terms; lower coasts longer |
| Motion | Push strength | x1.00 | x0.25 to x4 | Multiplies how hard each scroll notch pushes |
| Motion | Top speed | 60 rad/s | 20 to 120 | Speed limit |
| Motion | Direction lock | on | on / off | On: an opposing push only brakes and cannot restart the disc the other way until a moment of quiet; off: it passes through zero and reverses |
| Motion | Rotation step | 15 degrees | 5, 10, 15, 30, 45 | Size of one `T` / `Y` key step |
| Look | Metal | Steel | 5 metals | The disc's material (`M`) |
| Look | Hub finish | Lit | Lit, Raised | Marks cut in as glowing channels, or standing proud (`C`) |
| Look | Glow brightness | 100% | 0 to 200% | Rods, motion arcs and lit hub marks; 0 turns the emission off |
| Look | Room light | 100% | 30 to 160% | Lighting of the metal (not the glowing parts) |
| Look | Size | 100% | 40 to 150% | Scales the disc |
| Look | Spin blur | 100% | 0 to 150% | Scales the smear of a fast spin; 0 is sharp at any speed |
| Shadow | Darkness | 48% | 0 to 85% | Drop-shadow opacity; 0 hides it |
| Shadow | Spread | x1.00 | x0.3 to x3 | Softness of the shadow's edge |
| Shadow | Distance | x1.00 | 0 to x2.5 | Offset of the shadow from the disc; 0 puts it directly behind |
| Sound & Music | Bearing hum | on | on / off | The hum that follows the spin speed (`U`) |
| Sound & Music | Hum volume | 100% | 0 to 150% | Scales the hum's loudness |
| Sound & Music | Music mode | Off | Off, Sustain, Kick, Sustain + Kick | How the music acts on the spin (`B`) |
| Sound & Music | Sustain | 85% | 0 to 100% | Friction that loud music removes (Sustain modes) |
| Sound & Music | Kick | 2.0 rad/s | 0 to 6 | Speed added by a full-strength bass beat (Kick modes) |
| Renderer | Renderer | RealityKit | RealityKit, Shader | RealityKit needs macOS 15; the classic shader stands in while it loads (`G`) |

**The hum rule.** The hum is only heard when no music is playing. Any music activity silences it (fading out over about 0.8 s): a player reporting a track playing, captured player audio above the idle level, or Demo Mode. It returns, fading in over about 3 s, only after 6 seconds of continuous silence, so the gap or crossfade between songs, a quiet passage and a track's fade-out never let it back in. It also stays silent for the first 6 seconds after launch.

**Hub marks.** The interlocked mark is on the front hub and the sign-off mark on the back hub; each hub turns about the disc's own axis so its mark always reads upright and unmirrored, whichever way you tilt or turn the disc. Known limitations: Anodized Titanium's colour-shifting film exists only in the classic shader renderer (RealityKit draws plain titanium grey); the classic renderer shows pitch only and ignores yaw; with Shadow distance at 0 RealityKit leaves a thin dark edge around the disc. If the app-wide mouse modifier is Option, an Option-click that never moves is still "previous visualization"; once it moves it rotates the disc.

## Features

- Real-time audio analysis via vDSP FFT + adaptive beat detection
- Stereo-aware visualizers with L/R channel split
- 14 color palettes (classic, phosphor, synthwave, inferno, aurora, ember, ice, mono, viridis, plasma, spectrum, pastel, forest, oceanic) with HDR-boosted variants, and optional palette auto-cycle with crossfade
- Settings organized as a sidebar — app-wide settings vs. the active visualization's own, with each style's controls remembered per style (apply-to-all toggle). Controls that have no effect on the current style are greyed out with a tooltip explaining why
- Keyboard shortcuts for common actions and in-window Settings navigation (see below)
- Track overlay (album art, title and performer via ScriptingBridge): blooms on each song change and settles; hover enlarges it and holds it at full; click brings the player to the front. It stays on screen while a track is playing, alongside the lyrics (corner and opacity under Settings > Track Overlay)
- Window transparency (per-pixel alpha by default, or uniform opacity) + click-through mode
- Window border: an outline around the whole window, in normal or borderless mode
- Demo mode for when no music is playing
- Lyrics overlay: time-synced lyrics with a line-aligned English translation, scrolling over the visualizer, opening with the song title and performer as the first line. Smooth throughout — the translation eases in when it arrives, songs crossfade into each other, and the lyrics fade out promptly when playback stops. On by default
- Idle fade: with no music, the visualization and the lyrics ease out over 2 seconds and ease back in when audio returns. Demo mode stays up
- Audio capture that recovers on output changes: switching output device, or a Bluetooth speaker reconnecting or waking, rebuilds the tap automatically instead of leaving the visualizer faded out
- Position offset and Center below lyrics, for centered styles and Octave Meatballs
- Settings undo and redo (Command-Z, Command-Shift-Z), a reset button on every modified control (Option-click for the factory value), saved "my defaults", and whole-style and whole-app resets

## Keyboard shortcuts

Bare keys, active when the visualizer window or the Settings window is focused (not while typing in a Settings text field). Press **?** to show a cheat sheet over the visualizer; **Esc** closes it.

| Key | Action |
|---|---|
| H / L | Previous / next visualization |
| J / K | Next / previous palette |
| R | Random visualization |
| , / . | Previous / next song in the active player (Spotify or Music) |
| Space | Play / pause the active player |
| F | Toggle full screen |
| ? | Show / hide the shortcut cheat sheet |

The Spinner adds its own keys while it is the active visualization (see above).

Mouse, in the visualizer window, with the **mouse control modifier** held (Shift by default; Off, Shift, Option or Command in Settings > Window): click = previous visualization, right-click = next, middle-click = random, scroll = change palette (scroll down = next). Without a modifier: right-click opens a menu (Settings, Lyrics Settings, Layout Settings, visualization / palette / song controls, lyrics, window border, full screen) and double-click toggles full screen.

Menu-bar shortcuts:

| Shortcut | Action |
|---|---|
| ⌘B | Toggle borderless window |
| ⌘⇧B | Toggle window border |
| ⌘T | Toggle always on top |
| ⌃⌘C | Toggle click-through |
| ⌘L | Toggle lyrics |
| ⌘Z / ⌘⇧Z | Undo / redo a settings change |
| ⌥⌘D | Toggle demo mode |
| ⌃⌘F | Toggle full screen |

In the **Settings** window: **⌘1–⌘9 / ⌘0** jump to a category, **⌘F** focuses the filter.

## Lyrics overlay

Shows the current song's time-synced lyrics over the visualizer: the original line on the left, its English translation on the right, the active pair highlighted at mid-window and scrolling up in time with the music. Songs already in English show as a single centered column. On by default.

The song title (in italics) and performer open above the lyrics as the first line and scroll off when the words begin; a song with no lyrics at all shows just the title, which then drifts away. Movement is smooth throughout: the translation column eases in once it is ready, one song crossfades into the next, and the lyrics fade out when you pause and back in when you resume.

With no music playing, the lyrics and the visualization ease out together over 2 seconds and ease back in over 2 seconds when audio returns. The track title and art stay. Demo mode does not fade.

Centered styles, and Octave Meatballs, can sit in the clear space under the lyric block (Center below lyrics, on by default for that behavior). Octave Meatballs moves its field, background included, and leaves the uncovered window clear. Bars and Musical Spectrum stay anchored to the bottom edge and do not move.

Setup:

1. Get a Gemini API key at https://aistudio.google.com (the free tier is enough).
2. Open Settings, find the Lyrics section, paste the key, and click Save.
3. Play a song in Spotify or Apple Music. Lyrics are on by default. Turn off "Show lyrics" to hide them.

The Lyrics section also has the tweaks (text size, block width, active line position, active and other-line colors, fade, fade by distance from the active line, past-line treatment, drop shadow color, opacity, blur and offset, beat bounce and bounce strength, Gemini model) and a status line that says what happened for the current track, for example "No synced lyrics found" or "Translating...".

The active line's drop shadow can also **bounce to the beat** — pick Lift (the shadow lifts), Glow (the blur swells), or Both, with a strength, or Off. It follows the song's bass/kick and adapts to quiet and loud tracks alike, firing reliably where a fixed threshold would not. Only the shadow moves; the text never shifts. It needs the drop shadow on and reacts to live audio (not Demo Mode).

When a song is not found, three controls help:

- **Local lyrics folder:** point it at a folder of `.lrc` files and a file named for the song (for example `Artist - Title.lrc`) is used before LRCLIB. This fills a song LRCLIB does not have, or overrides a wrong entry, using your own file. The file is read from your Mac; nothing extra is sent anywhere.
- **Use approximate matches** (on by default): when LRCLIB has no recording of the exact length, the closest one (a different edit of the song) is shown instead of nothing. Its timing may drift, so the status line flags it as an approximate match. Turning it off hides approximate lyrics already saved for a song, not just new ones.
- **Lyric timing:** shifts the lyrics against playback (positive pulls them earlier) to nudge a drifted approximate match, or any latency, into sync.

What is sent where:

- LRCLIB (https://lrclib.net) receives the track's title, artist, album, and duration to look up lyrics. If the exact lookup finds nothing, a second search by title and artist picks the entry closest in length (within 3 seconds, or within about 30 seconds when approximate matches are on; a recording whose length differs more than that is treated as a different song and skipped). No account is needed.
- Google's Gemini API receives the lyric lines and the song title and artist, once per song, to translate them. Songs detected as English are never sent.

What is stored, all under `~/Library/Application Support/MacVisualizer/`:

- `lyrics/` holds one JSON file per translated song, so a song is only translated once. These files are derived from copyrighted lyrics; do not publish them.
- `gemini-key` holds the API key, readable only by your user account. It is never written to `settings.json`.

Songs with time-synced lyrics on LRCLIB (or in your local folder) are shown. Translation assumes Spanish lyrics; a song detected as English — including an English song with a short part in another language, such as a French refrain — is shown as-is in a single centered column rather than translated.

`MacVisualizer --lyrics-probe` (run the binary inside the built app, `MacVisualizer.app/Contents/MacOS/MacVisualizer`) prints what LRCLIB returns for the track now playing, without printing any lyric text.

## Build and run

```
make build      # generates the Xcode project with XcodeGen, then builds a Debug app
make run        # builds, then opens DerivedData/Build/Products/Debug/MacVisualizer.app
make test       # runs the full XCTest suite (over 1,200 tests)
make clean      # removes the generated project and DerivedData
```

Requires macOS 14.4+, Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for example `brew install xcodegen`). The Spinner visualization needs macOS 15+. CI runs `make build` then `make test` on GitHub's macos-15 runner with the latest stable Xcode. Debug builds are signed ad hoc ("Sign to Run Locally"), so no developer account is needed.

## First launch and permissions

- **Audio capture.** The app listens to Spotify and Apple Music (both at once, whichever is playing) through a Core Audio process tap. macOS asks for permission to capture audio the first time capture starts; allow it, or the window stays faded out. If it was denied, re-enable it for Mac Visualizer in System Settings > Privacy & Security.
- **Track information.** The track overlay and lyrics read the current track from Spotify or Apple Music; macOS asks for permission to control those apps (Automation). Without it the visualizer still works but there is no track card, lyrics or song controls.
- **Other audio sources.** Only Spotify and Apple Music are captured (the target list is fixed in this release). With no music playing the visualization and lyrics fade out after a moment; turn on Demo mode (⌥⌘D) to see the styles without music.
- **Settings.** Open Settings with ⌘, (or the right-click menu). They are saved to `~/Library/Application Support/MacVisualizer/settings.json`, together with the lyrics cache and the Gemini key described above. The sidebar has a Global section (Styles & Presets, Palette Cycle, Post-FX, Analysis, Track Overlay, Lyrics, Layout, Window) and a section for the active visualization (Controls, Appearance, Glow, Bands).
- **Window.** Window modes are under Settings > Window and the Window Chrome menu: transparency (per-pixel alpha, uniform opacity or opaque), borderless, click-through, always on top, and the window border (off, auto or always).

Other command-line probes (run the same binary): `--render-probe <out.png> [style] [renderMode] [glow]` writes an offscreen PNG of a style (Spinner tokens, comma-separated as the render mode: `a<angle>`, `v<velocity>`, `m<metal index>`, `h<finish index>`, `p<pitchDeg>`, `y<yawDeg>`, `z<zoom>`, `t`, `g1`, `w<pixels>`, and the settings overrides `S<size>`, `G<glow>`, `L<room light>`, `B<spin blur>`, `D<shadow darkness>`, `P<shadow spread>`, `X<shadow distance>`, `K<backdrop gray>`), `--rk-hub-check` (compares the hub texture generator with its reference), `--audio-probe`, `--nowplaying-probe` and `--list-audio-processes`.

## License

Apache License, Version 2.0. See [LICENSE](LICENSE) for the full text, [NOTICE](NOTICE) for attribution credits, and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the full license texts of ported third-party shaders.

`Copyright 2026 Ed Espino`
