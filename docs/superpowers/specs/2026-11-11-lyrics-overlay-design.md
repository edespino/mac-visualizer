# Lyrics Overlay (Group 1 of the lyrics-translate merge) — Design

**Date:** 2026-11-11
**Source:** User request — bring `spotify-translate-lyrics` (a personal React + Node web app) into mac-visualizer, showing the lyrics in the visualizer window. Based on a read of both repos: mac-visualizer `main` @ `e8c3bd1`, spotify-translate-lyrics `main` @ `8828745`.

Items tagged **[decided]** came from the user. Items tagged **[call]** were chosen while writing this document and were not explicitly agreed; the user reviews them here.

## Intent

The web app shows time-synced Spanish lyrics next to a line-aligned English translation, scrolling and highlighting like Spotify's lyrics view. The user wants that inside the visualizer window, drawn over the visualization, so one window does both jobs. The visualizer must do this entirely on its own: the web app and its Node server are not running. **[decided]**

The full merge covers every web-app feature **[decided]**, split into five groups built in order **[decided]**:

1. **Lyrics overlay** (this document)
2. Corrections: edit a line, per-line reset, retranslate all, translated title
3. Wrong lyrics: mark, reset, report to LRCLIB
4. Replay a line (seek playback)
5. Language learning: word gloss, vocabulary list, recall mode

Each later group gets its own design. Group 1 must not paint them into a corner (see "Leaving room for later groups").

## Goals

- With lyrics turned on and a song with timed lyrics playing, pairs of Spanish and English lines scroll over the visualizer in time with the music.
- The text is readable over any visualizer style, via a configurable drop shadow.
- Size, colors, shadow, block width, and fade are adjustable in Settings.
- Works with no other process running. Lyrics from LRCLIB, translation from Gemini, both called directly by the app.
- A song is translated once; later plays read from disk.

## Non-goals (group 1)

- Any mouse or keyboard interaction with the lyric text. The overlay ignores the mouse, exactly like the existing `TrackOverlay`.
- Editing, retranslate, title translation display, mark-wrong, replay, gloss, vocabulary, recall (groups 2 to 5).
- Importing the web app's existing `data/translations/` cache or its manual edits.
- Spotify web API login. Nothing in group 1 needs it.
- Languages other than Spanish to English. The translation prompt is carried over as written.
- Changing any visualizer style, shader, or the Metal pipeline.

## Anti-goals

- Spanish text shown in the English column as if it were a translation. A failed translation shows nothing in that column.
- Lyrics text or the Gemini key ending up in the repo or in `settings.json`.
- Any change to what the window looks like when lyrics are off (the default).
- Blocking the render loop or the now-playing poll on a network call.

## What the user sees

### Layout **[decided]**

Side by side, the web app's layout:

```
+--------------------------------------------------+
|                                                  |
|        earlier Spanish | earlier English  (faded)|
|                                                  |
|   CURRENT SPANISH LINE | current English line    |  <- mid-window
|                                                  |
|           next Spanish | next English     (faded)|
|                                                  |
+--------------------------------------------------+
```

- Two columns of equal width. Spanish right-aligned, English left-aligned, meeting at a center gutter.
- The whole two-column block is centered horizontally in the window. Its total width is a setting.
- The active pair sits at mid-window height **[decided]** (the web app uses 32% from the top; the user asked for the middle).
- The active pair is highlighted. All other pairs are faded by a configurable amount **[decided]**.
- Lines already sung get a "past" treatment: dimmer than upcoming (default), brighter than upcoming, or same as upcoming. Carried over from the web app **[call]**.
- Long lines wrap inside their column. A pair's row is as tall as its taller cell, so pairs never drift out of alignment.
- English uses the same size and colors as Spanish, as the web app does **[call]**.

### Motion

- When the active line changes, the block scrolls up smoothly so the new active pair lands at mid-window **[decided: scrolls up as the web app does]**.
- A large jump (seek, or more than a few lines at once) snaps without animation **[call, copied from the web app]**.
- Before the first timestamp, the first pair sits at the anchor with no highlight **[call]**.
- While paused, the text holds still, for as long as the player stays running and paused.

**Pause handling [call].** Today `NowPlayingService.poll()` publishes `track = nil` whenever the active player is not playing, so a pause hides the track card, clears `AudioFrame.trackId`, and makes resume look like a track change. That existing behavior stays exactly as it is (the track card and `trackId` are not touched). The lyrics path gets its own paused-aware playback state (track identity, position, playing flag) that survives a pause, so pausing freezes the lyrics and resuming does not refetch anything.

### States

| Situation | What shows |
|---|---|
| Lyrics setting off (default) | Nothing. Window identical to today. |
| Nothing playing | Nothing. |
| Timed lyrics, Spanish, translation cached | Both columns. |
| Timed lyrics, Spanish, translation in progress | Spanish immediately; English column empty until the translation arrives, then fills in. **[call]** |
| Timed lyrics, translation failed or no Gemini key | Spanish only, in its normal right-aligned column. **[call]** |
| Timed lyrics, already English | One centered column, no Gemini call. **[decided: as the web app]** |
| Lyrics without timestamps, instrumental, none found, LRCLIB error | Nothing. **[call]** |

The web app's loading skeleton bars, "Synced/Unsynced" badge, and empty-state screens are not reproduced in the window in group 1 **[call]**. Instead the Lyrics section in Settings shows one status line for the current track (for example: "Synced lyrics, translated", "Translating...", "No synced lyrics found", "Translation failed: <reason>", "No Gemini key set"). This keeps the visualizer window clean while still making failures diagnosable.

### Tweaks (Settings) **[decided: size, shadow attributes, colors, width, fade are configurable]**

A new Lyrics section in the Settings window. Exact control types, ranges, and defaults below are **[call]**; the set of things that can be adjusted is the requirement.

| Setting | Default | Notes |
|---|---|---|
| Show lyrics | off | Master switch. |
| Text size | 28 pt | Applies to both columns. |
| Block width | 80% of window width | Total width of the two-column block. |
| Active line color | `#4ade80` (the web app's default green) | Free color picker rather than the web app's five presets. |
| Other lines color | white | Upcoming and past lines. |
| Other lines opacity | 0.45 | The "fade" amount. |
| Past lines | Dim | Dim / Bright / Neutral, relative to upcoming lines. |
| Fade by distance | 4 lines each side | Added after first live use **[decided]**: non-active lines get more transparent the farther they are from the active line, reaching invisible one line past this count. 0 turns it off. |
| Shadow on | on | |
| Shadow color | black | |
| Shadow opacity | 0.8 | |
| Shadow blur radius | 4 pt | |
| Shadow offset X, Y | 0, 2 pt | |
| Gemini API key | empty | Secure field. Stored in an owner-only file, never in `settings.json`. |
| Gemini model | `gemini-flash-lite-latest` | The web app's default. |
| Status | (read-only) | One line for the current track, as described above. |

Lyrics settings are one set for the whole app, not per visualizer style **[call]**. They persist in `settings.json` with the project's tolerant-Codable pattern, so existing settings files load unchanged.

## How it works

### Where each piece lives **[call]**

Follows the project's existing split:

- `Sources/Core/` — pure logic with XCTest coverage: LRC parsing, active-line search, position interpolation, English detection, the translation contract (line-count validation, retry, chunk fallback, rate-limit wait) written against a provider protocol, cache entry types, lyrics settings.
- `Sources/Services/` — anything that touches the outside: LRCLIB client, Gemini provider, key file access, cache file I/O, and the additions to `PlayerReader` / `NowPlayingService`.
- `Sources/App/` — the overlay view (a sibling of `TrackOverlay` in `ContentView`'s `ZStack`, hit testing off) and the Settings section.

The overlay is SwiftUI on top of the Metal view, not drawn in Metal **[call]**. This is the same mechanism `TrackOverlay` already uses, gives real text layout and shadow for free, and leaves the render pipeline untouched. Consequence: in the window-opacity and per-pixel-alpha transparency modes, the window's overall opacity also fades the lyric text, as it already does for the track card.

### Playback position and duration

`NowPlayingService` currently publishes title, artist, album, and artwork from a 1.5 s ScriptingBridge poll. Group 1 adds:

- **Duration** of the current track (needed for the LRCLIB lookup).
- **Player position** and **playing/paused** on every poll.

Both players expose these in their scripting dictionaries (verified with `sdef` on this machine): `player position` (seconds, real) on the application object for Spotify and Music; `duration` on the track. **Units need care:** Music documents track duration as seconds (real). Spotify's dictionary says seconds (integer), but Spotify is widely reported to return milliseconds here. The builder must confirm the actual value with the existing `--nowplaying-probe` before relying on it.

Between polls, position is interpolated with a monotonic clock, re-anchoring only when a poll disagrees by more than 1.5 s (a seek) or play/pause flips. This is a port of the web app's `PositionTracker` (`src/sync.ts`); its `nudge` / settle-window behavior exists for locally initiated seeks and can be ported now or deferred to group 4. Active line is a binary search for the last line whose timestamp is at or before the position (`findActiveLine`).

All ScriptingBridge reads keep going through the existing exception-safe helpers in `PlayerReader`.

### Lyrics

Port of `src/lyrics.ts` and `src/lrc.ts`:

- `GET https://lrclib.net/api/get` with `track_name`, `artist_name`, `album_name`, `duration` (whole seconds). No authentication.
- 404 means none. `instrumental: true` means instrumental. `syncedLyrics` parsed as LRC gives timed lines. `plainLyrics` only means unsynced. Keep the `id` from the response on the result (group 3 needs it).
- LRC parser behavior to preserve: minutes above 9, 1 to 3 digit fractions, several timestamps on one line (emitted once per timestamp), malformed lines skipped, empty-text lines kept, output sorted by time.
- Fetch once per track change, only when the lyrics setting is on. Bounded timeouts, as the artwork fetch does.
- Send a generic client name and app version as the User-Agent (for example `MacVisualizer/<version>`), with no personal details **[call]**.

### English detection

Port of `src/detect.ts`: a stopword and accent-mark heuristic over the full lyric text, biased so that only confidently English text skips translation. Word lists and thresholds carry over unchanged.

### Translation

Port of `server/translator.ts`, minus the gloss parts:

- One request per song. Prompt names the song and artist, sends every line as a JSON array, requires the same number of lines back, JSON output forced. The song title rides as the first line; group 1 stores the translated title but does not display it.
- Contract: N lines in, N lines out. Try the full batch twice, then chunks of 20, each strictly validated. Any chunk failure fails the whole translation; nothing partial is saved.
- Rate limit (429): wait for the delay Gemini suggests, else 15 s then 30 s; at most 2 retries; cap 60 s.
- A missing-model error surfaces as a readable status message naming the model setting.
- The web app uses Google's `@google/genai` Node library. The Swift app calls the Gemini REST `generateContent` endpoint directly over HTTPS with the key in a request header. **The builder must take the exact endpoint, header name, and request/response shape from Google's current Gemini API documentation, not from memory.**
- Translation runs only when: lyrics setting on, timed lyrics found, not English, key present, and no cache entry.

### Cache **[call]**

- One JSON file per track under the app's existing Application Support folder (next to `settings.json`), in a `lyrics/` subfolder. This is outside the repo by construction.
- Entry shape mirrors the web app's `TranslationEntry`: title, artist, optional translated title, optional LRCLIB id, and per line `timeMs`, `es`, `en`, plus optional `editedEs` / `editedEn` (unused until group 2, present so the format does not change later).
- File name: a hash of the normalized title, artist, album, and whole-second duration. The web app keys by Spotify track ID, but the visualizer also supports Music, which has no such ID.
- Writes are write-to-temp-then-rename.
- English songs and failed translations write nothing.
- Cached entries hold the timed Spanish lines too, so a cached song needs no LRCLIB call. **[call]**

### Gemini key **[decided]**

Stored in its own file in the app's Application Support folder (next to `settings.json`, outside the repo), with owner-only permissions (0600). Entered and cleared in the Settings Lyrics section. Never written to `settings.json`, logs, or the status line.

The Keychain was considered and rejected for now: the app is ad-hoc signed (`CODE_SIGN_IDENTITY: "-"`), so the Keychain is expected to raise a password prompt after every rebuild. If the app later gets a real signing identity, moving the key to the Keychain is a small follow-up.

## Leaving room for later groups

- Keep LRCLIB id and translated title in the cache entry now.
- Keep `editedEs` / `editedEn` in the entry type now.
- The overlay view should render each pair as its own row view fed by a per-line model, so groups 2 to 5 can attach click, hover, and edit behavior to rows without restructuring. Hit testing stays off in group 1.
- Seeking (group 4) is expected to work by setting `player position` through ScriptingBridge; nothing in group 1 depends on it.

## Follow-up: closing the lyrics-availability gaps (2026-11-16)

Two songs where Spotify showed lyrics but the app found none drove this
addition: one where LRCLIB only had a different-length recording (outside
the 3 s tolerance), and one LRCLIB had no data for at all. Both are
opt-outable; LRCLIB stays primary.

- **Approximate matches.** When no LRCLIB recording is within the 3 s
  duration tolerance, accept the closest synced recording within a 30 s
  ceiling (`looseToleranceMs`; a bigger length gap is a different recording,
  not a different master, and is rejected) instead of showing nothing.
  Marked approximate
  through `LyricsResult.synced`, surfaced on `LyricsModel.approximateMatch`,
  flagged in the Settings status line, and persisted in the cache entry
  (`approximate`). Setting `acceptApproximateMatches`, default on. An
  out-of-tolerance synced match is preferred over an exact unsynced one,
  since only synced lyrics scroll.
- **Lyric timing offset.** `timingOffsetMs` shifts the interpolated position
  before the active-line search (positive pulls lines earlier). App-wide,
  default 0. Nudges a drifted approximate match or systematic
  player-position latency.
- **Local `.lrc` folder.** `localLyricsFolder` names a folder that overrides
  both the cache and LRCLIB: the model consults `localOverride` before its
  cache read, so a local file replaces even an already-cached (stale or
  wrong) entry, and a cached translation is reused only when its source lines
  match (an edited file re-translates). `LocalLyricsMatcher` (Core, tested)
  matches a file by "Artist - Title", "Title - Artist" or "Title" (accent-
  and punctuation-insensitive); `LocalLyricsReader` decodes it
  (`LyricsTextDecoder`: UTF-8, then Windows-1252, then Latin-1, so a
  non-UTF-8 file is not silently skipped) and parses it (synced or plain).
  Lets the user fill a song LRCLIB lacks entirely, or override a wrong entry,
  with their own file. Empty disables it.

Per-fetch configuration (folder, approximate policy) travels into the fetch
via `LyricsFetchOptions`; the model re-fetches the current track when either
changes.

**Explicitly not done:** the Spotify internal color-lyrics endpoint. Reaching
it means exchanging a logged-in cookie for a token past a TOTP check Spotify
added to block third-party clients and rotates to keep blocking them. Using
it circumvents that access control, breaks Spotify's terms for the account
whose cookie is used, and stops working on every rotation. Rejected as a
foundation; the local-folder path closes the same gap with the user's own
data.

## Testing and validation

- **Unit tests (XCTest, Core):** LRC parser, active-line search, position tracker, English detection, translation contract against a fake provider (count mismatch, retry, chunk fallback, rate-limit wait with an injectable sleep, hard failure writes nothing), cache entry round trip, lyrics settings round trip plus legacy JSON without the new fields. The web app's Vitest files (`src/lrc.test.ts`, `src/sync.test.ts`, `src/detect.test.ts`, `server/translator.test.ts`, `server/validate.test.ts`) are the source of cases to port.
- **No network in tests.** LRCLIB and Gemini are never called from the test suite.
- **Visual validation is part of done** (project rule). The offscreen render probe captures the Metal output only, not the SwiftUI layer, so the overlay is confirmed by the user in the live window: Spanish song, English song, a song with no synced lyrics, a seek, a pause, and each tweak moved.
- `make build` and `make test` pass.

## Project conventions that apply

- Apache 2.0 header on every new Swift file.
- Tolerant Codable for new settings; no existing JSON key changes.
- Attribution: the lyrics logic is ported from the user's own Apache 2.0 project, so no third-party entry is required for the code **[call]**. Whether to name LRCLIB and Gemini as external services in `NOTICE` or the README is left to the user.
- Version bump follows the repo's existing practice of a separate bump commit.

## Left to the builder

- How the overlay gets a per-frame position (for example a SwiftUI timeline versus a published active index) and how the scroll animation is implemented.
- Whether lyrics settings are flat fields on `VisualizerSettings` or one nested tolerant-Codable struct.
- Internal type and file names, and how the lyrics pipeline object is owned alongside `NowPlayingService` and `RenderModel`.
- Exact slider ranges and Settings layout.
- Threshold for "large jump snaps instead of animating".
- How empty-text lines (instrumental gaps inside a synced song) are drawn; check `LyricsView.tsx` in the web app for its placeholder treatment.
