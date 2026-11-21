# Lyrics Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show time-synced Spanish lyrics with a line-aligned English translation as a side-by-side scrolling overlay in the visualizer window, working with no other process running.

**Architecture:** All lyric logic (LRC parsing, position interpolation, English detection, translation contract, cache, key file, and the `LyricsModel` that orchestrates them) lives in `MacVisualizerCore` behind small protocols so it is unit-tested with fakes. `Sources/Services` supplies the two network implementations (LRCLIB, Gemini) and extends the ScriptingBridge poll with position and duration. `Sources/App` adds a non-interactive SwiftUI overlay next to `TrackOverlay` and a Lyrics section in Settings.

**Tech Stack:** Swift 5.10, SwiftUI, Combine, Foundation `URLSession`, CryptoKit (SHA-256 for cache file names), ScriptingBridge, XCTest. No new third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-11-11-lyrics-overlay-design.md`. Read it before starting any task.

**Source being ported:** a personal web app, `spotify-translate-lyrics` (read-only reference). Never read or print its `.env`. Never copy anything from its `data/` folder.

## Global Constraints

- Build and test only through `make build` and `make test`. Never invoke `xcodebuild` directly.
- Every new `.swift` file in `Sources/` and `Tests/` starts with the 16-line Apache 2.0 header from `CLAUDE.md`, then a blank line, then imports.
- Deployment target stays macOS 14.4. No API newer than that.
- New settings use tolerant Codable (`decodeIfPresent ?? default`). No existing JSON key changes. A `settings.json` written before this work must load unchanged.
- With lyrics off (the default) the window must look and behave exactly as it does today. `TrackOverlay`, `AudioFrame.trackId`, and `NowPlayingService.track` / `.artwork` behavior are not changed.
- The overlay never accepts mouse or keyboard input (`allowsHitTesting(false)`).
- Lyrics text and the Gemini key never go in the repo, in `settings.json`, or in logs. Log with `privacy: .private` for anything derived from lyrics; never log the key at all.
- Spanish text is never placed in the English column. A failed translation leaves that column empty.
- No network calls from the test suite.
- No network or file I/O on the main thread or on the `visualizer.nowplaying` poll queue.
- Git: never run `git config`; commits are attributed to the user with no AI attribution lines. Work on branch `dev`.
- User-facing strings and comments use ASCII punctuation.

## Review Focus

Conditions the spec implies but does not spell out, most likely first. Each has a test in the task named.

1. **Skipping tracks quickly:** a lyrics or translation result that arrives for a track that is no longer current must be discarded, never shown over the new song. (Task 7)
2. **Tracks with no usable identity:** missing title or artist, or zero/unknown duration (ads, podcasts, radio streams) must make no LRCLIB request and show nothing. (Task 7)
3. **Corrupt or half-written cache file:** treated as a cache miss and overwritten on the next successful translation; never a crash, never shown. (Task 5)
4. **Lyrics on, turned on mid-song:** enabling the setting while a song is already playing loads that song without waiting for a track change; disabling clears the display and cancels in-flight work. (Task 7)
5. **Pasted key with stray whitespace or a trailing newline:** stored trimmed; an empty or whitespace-only value removes the key file. (Task 5)

---

## File Structure

**Create in `Sources/Core/`** (all `public`, unit-tested):

| File | Responsibility |
|---|---|
| `LyricsSettings.swift` | `LyricsSettings` struct, `LyricsPastMode`, `LyricRowPhase`, per-phase opacity. |
| `LyricsTypes.swift` | `LyricLine`, `LyricsResult`, `LyricsTrack`, `PlaybackSnapshot`. |
| `LRCParser.swift` | `LRCParser.parse`, `findActiveLine`. |
| `PlaybackPositionTracker.swift` | Position interpolation between polls. |
| `EnglishLyricsDetector.swift` | Stopword heuristic. |
| `LyricsTranslator.swift` | `TranslationProvider` protocol, prompt, response validation, retry/chunk/rate-limit contract. |
| `GeminiAPI.swift` | Pure request building and response parsing for Gemini REST. |
| `LyricsCache.swift` | `TranslationEntry`, `LyricsCacheKey`, `LyricsCacheStore`, `GeminiKeyStore`. |
| `LyricsModel.swift` | `LyricsFetching` protocol, `LyricsDisplay`, `LyricsStatus`, `LyricsModel` (ObservableObject orchestrator). |

**Create in `Sources/Services/`:** `LRCLIBClient.swift`, `GeminiProvider.swift`.

**Create in `Sources/App/`:** `LyricsOverlay.swift`, `LyricsSettingsSection.swift`.

**Modify:** `Sources/Core/VisualizerSettings.swift` (one nested field), `Sources/Services/PlayerReader.swift`, `Sources/Services/NowPlayingService.swift`, `Sources/Services/NowPlayingProbe.swift`, `Sources/App/MacVisualizerApp.swift`, `Sources/App/SettingsView.swift`, `CLAUDE.md`, `README.md`, `project.yml` (version).

**Tests in `Tests/CoreTests/`:** one `<TypeName>Tests.swift` per Core file above.

Deviation from the spec, on purpose: the spec lists cache and key file I/O under `Sources/Services`. They go in Core instead because only Core has a test target, and `VisualizerSettings` already does file I/O there.

---

### Task 1: Lyrics settings

**Files:**
- Create: `Sources/Core/LyricsSettings.swift`
- Modify: `Sources/Core/VisualizerSettings.swift` (struct field, `init`, `defaults`, `CodingKeys`, `init(from:)`, `encode(to:)`; follow how `paletteCycleEnabled` is threaded through, lines ~425, 723, 1020, 1670, 1911, 2224, 2582, 2884)
- Test: `Tests/CoreTests/LyricsSettingsTests.swift`

**Interfaces:**
- Consumes: existing `RGBAColor` (`Sources/Core/VisualizerSettings.swift:18`).
- Produces:

```swift
public enum LyricsPastMode: String, Codable, CaseIterable { case dim, bright, neutral }
public enum LyricRowPhase { case past, active, upcoming }

public struct LyricsSettings: Codable, Equatable {
    public var enabled: Bool                // false
    public var textSize: Float              // 28 (points)
    public var blockWidthFraction: Float    // 0.8 (of window width)
    public var activeColor: RGBAColor       // #4ade80 -> r 0.290, g 0.871, b 0.502, a 1
    public var otherColor: RGBAColor        // white
    public var otherOpacity: Float          // 0.45
    public var pastMode: LyricsPastMode     // .dim
    public var shadowEnabled: Bool          // true
    public var shadowColor: RGBAColor       // black
    public var shadowOpacity: Float         // 0.8
    public var shadowRadius: Float          // 4
    public var shadowOffsetX: Float         // 0
    public var shadowOffsetY: Float         // 2
    public var geminiModel: String          // "gemini-flash-lite-latest"
    public static let defaults: LyricsSettings
    public func opacity(for phase: LyricRowPhase) -> Float
}
// On VisualizerSettings:
public var lyrics: LyricsSettings   // JSON key "lyrics"
```

`opacity(for:)`: `.active` is 1; `.upcoming` is `otherOpacity`; `.past` is `otherOpacity` times 0.7 (dim), 1.45 (bright), or 1.0 (neutral), clamped to 0...1. The factors come from the web app's gray levels (`#666` and `#d0d0d0` against `#8f8f8f`).

`LyricsSettings.init(from:)` is tolerant per field. `geminiModel` decoding an empty string falls back to the default.

- [ ] **Step 1: Write failing tests** in `LyricsSettingsTests.swift`:
  - `testDefaults`: every default above, exactly.
  - `testOpacityPerPhase`: with `otherOpacity = 0.45`: active 1.0; upcoming 0.45; past dim 0.315; past bright 0.6525; past neutral 0.45 (accuracy 0.0001). With `otherOpacity = 0.9` and `.bright`: 1.0 (clamped).
  - `testRoundTrip`: change every field, encode, decode, equal.
  - `testPartialJSONFillsDefaults`: decode `{"enabled":true}` gives `enabled == true` and all other fields default.
  - `testEmptyModelFallsBack`: decode `{"geminiModel":""}` gives the default model.
  - `testVisualizerSettingsLegacyJSONWithoutLyrics`: encode `VisualizerSettings.defaults`, strip the `"lyrics"` key from the JSON object, decode, `lyrics == .defaults`.
  - `testVisualizerSettingsRoundTripsLyrics`: set `settings.lyrics.enabled = true`, `textSize = 40`, round trip, equal.
- [ ] **Step 2:** `make test`. Expected: build failure, `LyricsSettings` undefined.
- [ ] **Step 3:** Implement `LyricsSettings.swift` and thread `lyrics` through `VisualizerSettings`.
- [ ] **Step 4:** `make test`. Expected: all pass, including every pre-existing test.
- [ ] **Step 5:** Commit: `Add lyrics settings`.

---

### Task 2: Lyric types, LRC parser, active-line search

**Files:**
- Create: `Sources/Core/LyricsTypes.swift`, `Sources/Core/LRCParser.swift`
- Test: `Tests/CoreTests/LRCParserTests.swift`
- Reference: web app `src/lrc.ts`, `src/lrc.test.ts`, `src/sync.ts` (`findActiveLine`), `src/sync.test.ts`

**Interfaces:**
- Produces:

```swift
public struct LyricLine: Codable, Equatable { public var timeMs: Int; public var text: String }

public enum LyricsResult: Equatable {
    case synced(lines: [LyricLine], lrclibId: Int?)
    case plain(lines: [String], lrclibId: Int?)
    case instrumental
    case none
}

public struct LyricsTrack: Equatable {
    public var title: String; public var artist: String; public var album: String
    public var durationMs: Int
    public var isLookupable: Bool   // title and artist non-blank and durationMs > 0
}

public struct PlaybackSnapshot: Equatable {
    public var track: LyricsTrack
    public var positionMs: Int
    public var isPlaying: Bool
    public var sampledAtMs: Double   // monotonic clock, ms
}

public enum LRCParser { public static func parse(_ lrc: String) -> [LyricLine] }
public func findActiveLine(_ lines: [LyricLine], positionMs: Int) -> Int   // -1 before the first line
```

Parser rules (from `src/lrc.ts`): timestamp pattern `[m+:ss]`, `[m+:ss.f]`, `[m+:ss:f]` with a 1 to 3 digit fraction (1 digit is tenths, 2 is hundredths, 3 is ms); timestamps must be contiguous at the start of the line after leading whitespace; seconds of 60 or more invalidates the line; a line with several timestamps is emitted once per timestamp; text is trimmed; empty text is kept; lines with no valid timestamp are skipped; output sorted by time, stable.

- [ ] **Step 1: Write failing tests.** Port every case in `src/lrc.test.ts` (9 cases) and the `findActiveLine` cases in `src/sync.test.ts`, keeping their inputs and expected values. Add:
  - `testIsLookupable`: blank title false; blank artist false; `durationMs == 0` false; all present true.
  - `testFindActiveLineEmptyLines`: empty array gives -1.
- [ ] **Step 2:** `make test`. Expected: build failure.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `make test`. Expected: pass.
- [ ] **Step 5:** Commit: `Add LRC parser and active-line search`.

---

### Task 3: Playback position tracker

**Files:**
- Create: `Sources/Core/PlaybackPositionTracker.swift`
- Test: `Tests/CoreTests/PlaybackPositionTrackerTests.swift`
- Reference: web app `src/sync.ts` (`PositionTracker`), `src/sync.test.ts`

**Interfaces:**
- Produces:

```swift
public struct PlaybackPositionTracker {
    public static let snapThresholdMs: Double = 1500
    public init()
    public mutating func update(polledPositionMs: Double, isPlaying: Bool, nowMs: Double)
    public func position(atMs nowMs: Double) -> Double
    public mutating func reset()
}
```

Port `update`, `positionAt`, and `reset` only. `nudge` and the settle window are for locally initiated seeks and belong to group 4; do not port them.

- [ ] **Step 1: Write failing tests.** Port the `PositionTracker` cases from `src/sync.test.ts` that do not involve `nudge`, same numbers.
- [ ] **Step 2:** `make test`. Expected: build failure.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `make test`. Expected: pass.
- [ ] **Step 5:** Commit: `Add playback position tracker`.

---

### Task 4: English detection and translation contract

**Files:**
- Create: `Sources/Core/EnglishLyricsDetector.swift`, `Sources/Core/LyricsTranslator.swift`, `Sources/Core/GeminiAPI.swift`
- Test: `Tests/CoreTests/EnglishLyricsDetectorTests.swift`, `Tests/CoreTests/LyricsTranslatorTests.swift`, `Tests/CoreTests/GeminiAPITests.swift`
- Reference: web app `src/detect.ts`, `src/detect.test.ts`, `server/translator.ts`, `server/translator.test.ts`, `server/validate.ts`, `server/validate.test.ts`

**Interfaces:**
- Produces:

```swift
public enum EnglishLyricsDetector { public static func isEnglish(_ text: String) -> Bool }

public struct TranslationMeta: Equatable {
    public var title: String; public var artist: String; public var titleFirst: Bool
}

public enum TranslationProviderError: Error, Equatable {
    case rateLimited(retryAfterMs: Int?)
    case modelUnavailable(model: String)
    case other(String)
}

public protocol TranslationProvider {
    /// Returns the model's raw text output for one prompt.
    func generate(prompt: String) async throws -> String
}

public struct TranslationFailed: Error, Equatable { public var message: String }

public enum LyricsTranslator {
    public static let chunkSize = 20
    public static let maxRateLimitRetries = 2
    public static let defaultRetryDelayMs = 15_000
    public static let maxRetryDelayMs = 60_000
    public static func buildPrompt(lines: [String], meta: TranslationMeta) -> String
    public static func parseResponse(_ raw: String, expected: Int) throws -> [String]
    public static func translateWithTitle(
        provider: TranslationProvider, lines: [String], meta: TranslationMeta,
        sleep: (Int) async -> Void          // milliseconds; injectable for tests
    ) async throws -> (titleEn: String, en: [String])
}

public enum GeminiAPI {
    public static func makeRequest(apiKey: String, model: String, prompt: String) throws -> URLRequest
    public static func parse(data: Data, statusCode: Int, model: String) throws -> String  // throws TranslationProviderError
    public static func retryDelayMs(fromErrorBody body: String) -> Int?
}
```

Rules to preserve:
- Detector: word lists, the "other language" disqualifiers, and thresholds (`enRate >= 0.15`, at least 5 distinct English words, `esRate <= 0.02`, Spanish marks at most `tokens / 200`, fewer than 10 tokens is not English) copied exactly from `src/detect.ts`.
- `buildPrompt`: the exact prompt lines from `buildPrompt` in `server/translator.ts`, including the title-first sentence only when `titleFirst` is true.
- `parseResponse`: accepts raw JSON or JSON inside a markdown code fence; must be an array of strings of exactly `expected` length; anything else throws.
- `translateWithTitle`: empty `lines` returns `("", [])` with no provider call. Batch is `[title] + lines`. Full batch attempted twice; then chunks of 20 with the title riding in the first chunk (only that chunk's prompt has `titleFirst`); a chunk that fails throws `TranslationFailed` naming the 1-based line range. A wrong count or a non-rate-limit provider error is a soft failure for that attempt. `.rateLimited` waits `retryAfterMs` if present (capped at 60 000), else `15_000 * (attempt + 1)`, and throws `TranslationFailed` after 2 retries. `.modelUnavailable` throws `TranslationFailed` immediately with a message naming the model.
- `GeminiAPI`: **before writing its tests, read Google's current Gemini API reference for `generateContent`** and take the endpoint URL, key header name, request body shape, and response text path from it. The values believed correct, to be confirmed there and not assumed: `POST https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent`, header `x-goog-api-key`, body `{"contents":[{"parts":[{"text":<prompt>}]}],"generationConfig":{"responseMimeType":"application/json"}}`, output at `candidates[0].content.parts[0].text`. If the documentation differs, the documentation wins; note the difference in the commit message.
- `GeminiAPI.parse`: status 429 throws `.rateLimited` with the delay from `retryDelayMs`; status 404 whose body mentions the model as not found or unavailable throws `.modelUnavailable`; any other non-2xx throws `.other`; 2xx with no text throws `.other`.
- `retryDelayMs`: matches `"retryDelay": "7s"` and `retry in 7.5s` forms, returns ms capped at 60 000, else nil (port `parseRetryDelayMs`).

- [ ] **Step 1: Write failing tests.** Port all 21 cases of `src/detect.test.ts`; the translation cases of `server/translator.test.ts` and `server/validate.test.ts` (skip every gloss case), using a scripted fake `TranslationProvider` that returns queued results and records prompts, and a fake `sleep` that records requested delays. Add:
  - `testEmptyLinesMakesNoProviderCall`.
  - `testTranslatedOutputNeverEqualsInputOnFailure`: provider always returns the wrong count; call throws; nothing returned.
  - `GeminiAPITests`: request URL, method, header, and body JSON match the documented shape; `parse` extracts text from a documented-shape success body; 429 with a `retryDelay` body gives `.rateLimited(retryAfterMs: 7000)`; 404 model-not-found gives `.modelUnavailable`; 500 gives `.other`. The API key must not appear in the URL.
- [ ] **Step 2:** `make test`. Expected: build failure.
- [ ] **Step 3:** Implement the three files.
- [ ] **Step 4:** `make test`. Expected: pass.
- [ ] **Step 5:** Commit: `Add English detection and the translation contract`.

---

### Task 5: Cache and key file

**Files:**
- Create: `Sources/Core/LyricsCache.swift`
- Test: `Tests/CoreTests/LyricsCacheTests.swift`

**Interfaces:**
- Consumes: `LyricLine`, `LyricsTrack` (Task 2).
- Produces:

```swift
public struct TranslationLine: Codable, Equatable {
    public var timeMs: Int
    public var es: String
    public var en: String
    public var editedEs: String?   // unused until group 2
    public var editedEn: String?   // unused until group 2
}

public struct TranslationEntry: Codable, Equatable {
    public var title: String
    public var artist: String
    public var titleEn: String?
    public var lrclibId: Int?
    public var lines: [TranslationLine]
}

public enum LyricsCacheKey {
    /// Lowercase hex SHA-256 of normalized title, artist, album and whole-second
    /// duration joined by U+001F. Normalization: lowercased, trimmed, inner
    /// whitespace runs collapsed to one space.
    public static func make(for track: LyricsTrack) -> String
}

public struct LyricsCacheStore {
    public init(directory: URL)
    public static func defaultDirectory() -> URL   // <App Support>/MacVisualizer/lyrics
    public func read(_ track: LyricsTrack) -> TranslationEntry?   // nil on missing OR undecodable
    public func write(_ entry: TranslationEntry, for track: LyricsTrack) throws  // temp file then rename
}

public struct GeminiKeyStore {
    public init(fileURL: URL)
    public static func defaultFileURL() -> URL     // <App Support>/MacVisualizer/gemini-key
    public func read() -> String?                  // nil when missing or blank
    public func write(_ key: String) throws        // trims; blank removes the file; POSIX 0600
}
```

Derive both default locations from `VisualizerSettings.defaultFileURL().deletingLastPathComponent()` so they always sit next to `settings.json`.

- [ ] **Step 1: Write failing tests** (each uses a fresh temp directory removed in `tearDown`):
  - `testKeyIsStableAndNormalized`: `"  Hola   Mundo "` / `"ARTIST"` / `"Album"` / 201_400 ms equals `"hola mundo"` / `"artist"` / `"album"` / 201_900 ms (same whole second 201); 64 hex characters.
  - `testKeyDiffersByDurationSecond`: 201_000 vs 202_000 differ.
  - `testReadMissingIsNil`.
  - `testWriteThenReadRoundTrips`, including `editedEs` / `editedEn` nil and non-nil.
  - `testCorruptFileReadsAsNil`: write garbage bytes at the entry's path; `read` returns nil and does not throw. *(Review Focus 3)*
  - `testWriteOverwritesCorruptFile`: after the above, `write` succeeds and `read` returns the entry.
  - `testWriteLeavesNoTempFiles`: directory holds exactly one file after a write.
  - `testKeyStoreRoundTrip`: `write("abc")` then `read() == "abc"`.
  - `testKeyStoreTrimsWhitespace`: `write("  abc\n")` then `read() == "abc"`. *(Review Focus 5)*
  - `testKeyStoreBlankRemovesFile`: after a write, `write("  \n")` leaves no file and `read() == nil`. *(Review Focus 5)*
  - `testKeyStoreFileIsOwnerOnly`: POSIX permissions of the file equal `0o600`.
- [ ] **Step 2:** `make test`. Expected: build failure.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `make test`. Expected: pass.
- [ ] **Step 5:** Commit: `Add lyrics cache and Gemini key file`.

---

### Task 6: Playback position and duration from the players

**Files:**
- Modify: `Sources/Services/PlayerReader.swift`, `Sources/Services/NowPlayingService.swift`, `Sources/Services/NowPlayingProbe.swift`
- Create: add `PlaybackUnits` to `Sources/Core/LyricsTypes.swift`
- Test: `Tests/CoreTests/PlaybackUnitsTests.swift`

**Interfaces:**
- Consumes: `LyricsTrack`, `PlaybackSnapshot` (Task 2).
- Produces:

```swift
// Core
public enum PlaybackUnits {
    /// Converts a player's raw `duration` value to milliseconds.
    public static func durationMs(raw: Double, bundleID: String) -> Int
    /// Converts a player's raw `player position` (seconds) to milliseconds.
    public static func positionMs(rawSeconds: Double) -> Int
}

// Services
extension PlayerReader {
    static func rawDuration(_ bundleID: String) -> Double?        // currentTrack.duration
    static func rawPlayerPosition(_ bundleID: String) -> Double?  // application playerPosition
}

// NowPlayingService
@Published private(set) var playback: PlaybackSnapshot?
```

`playback` is published on every poll whenever the active player is running and has a readable track, **whether playing or paused**; nil otherwise. `sampledAtMs` is `ProcessInfo.processInfo.systemUptime * 1000` taken on the poll queue right after the position read. The existing `track` / `artwork` publishing and its `lastKey` logic are left exactly as they are.

- [ ] **Step 1: Extend the probe.** Make `--nowplaying-probe` also print, per running player, the raw `duration` and raw `playerPosition` values with their Swift runtime types. Use the existing exception-safe `safeValue` path.
- [ ] **Step 2: Measure the units (manual, needs the user).** `make build`, then ask the user to play a track of known length in Spotify and run `DerivedData/Build/Products/Debug/MacVisualizer.app/Contents/MacOS/MacVisualizer --nowplaying-probe`; repeat with Music if available. Record the raw numbers in the commit message. This decides whether Spotify's `duration` is seconds or milliseconds; the scripting dictionary says seconds, reports say milliseconds. Do not proceed on an assumption.
- [ ] **Step 3: Write failing tests** in `PlaybackUnitsTests.swift` using the measured facts: Music raw `duration` is seconds (`245.3` gives `245_300`); Spotify per the measurement; `positionMs(rawSeconds: 12.5) == 12_500`; negative or NaN raw values give 0.
- [ ] **Step 4:** `make test`. Expected: build failure.
- [ ] **Step 5:** Implement `PlaybackUnits`, the two `PlayerReader` readers, and `playback` publishing.
- [ ] **Step 6:** `make test`. Expected: pass. Run the probe again; duration and position print sensible values while playing and while paused.
- [ ] **Step 7:** Commit: `Read playback position and duration from Spotify and Music`.

---

### Task 7: Lyrics model

**Files:**
- Create: `Sources/Core/LyricsModel.swift`
- Test: `Tests/CoreTests/LyricsModelTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1 to 5; `PlaybackSnapshot` (Task 2).
- Produces:

```swift
public protocol LyricsFetching {
    func fetch(track: LyricsTrack) async throws -> LyricsResult
}

public struct LyricRow: Equatable, Identifiable {
    public var id: Int            // line index
    public var timeMs: Int
    public var original: String   // "" for an instrumental gap
    public var translation: String?   // nil = not available (yet); never the original text
}

public struct LyricsDisplay: Equatable {
    public var rows: [LyricRow]
    public var singleColumn: Bool     // true for English songs
}

public enum LyricsStatus: Equatable {
    case off, nothingPlaying, loading, noSyncedLyrics, instrumental
    case lyricsError
    case englishNoTranslation
    case translating
    case translated
    case noKey
    case translationFailed(String)
    public var message: String
}

@MainActor
public final class LyricsModel: ObservableObject {
    @Published public private(set) var display: LyricsDisplay?
    @Published public private(set) var status: LyricsStatus
    public init(fetcher: LyricsFetching,
                makeProvider: @escaping (_ apiKey: String, _ model: String) -> TranslationProvider,
                cache: LyricsCacheStore,
                keyStore: GeminiKeyStore,
                sleep: @escaping (Int) async -> Void)
    /// Call on every poll and whenever lyrics settings change.
    public func update(playback: PlaybackSnapshot?, settings: LyricsSettings)
    /// Call after the key file changes so a track stuck on .noKey retries.
    public func keyDidChange()
    public func activeIndex(atMs nowMs: Double) -> Int   // -1 when none
    /// Awaits the in-flight load, for tests.
    public func waitForIdle() async
}
```

Behavior:
- `update` feeds `PlaybackPositionTracker` on every call and starts a load only when the track (compared by `LyricsCacheKey`) changes, or when `enabled` flips to true.
- Load order: not `isLookupable` gives `display = nil`, status `.nothingPlaying`, no fetch. Cache hit gives rows from the entry (`editedEs ?? es`, `editedEn ?? en`), status `.translated`, no network. Otherwise set `display = nil`, status `.loading`, and fetch: error gives `.lyricsError`; `.none` and `.plain` give `.noSyncedLyrics`; `.instrumental` gives `.instrumental`; all with `display = nil`. `.synced`: publish rows immediately with `translation = nil`. If `EnglishLyricsDetector.isEnglish` on the joined text: `singleColumn = true`, `.englishNoTranslation`, stop. If no key: `.noKey`, stop. Else `.translating`, call `LyricsTranslator.translateWithTitle`; on success fill translations, write the cache entry (with `titleEn`, `lrclibId`), `.translated`; on failure rows stay Spanish-only, `.translationFailed(message)`, nothing written.
- Every await point re-checks that the load's track is still the current track and that lyrics are still enabled; if not, the result is dropped. A new load cancels the previous `Task`.
- `enabled == false`: `display = nil`, `.off`, in-flight work cancelled, no network.
- `playback == nil`: `display = nil`, `.nothingPlaying`, tracker reset.
- File and network work run off the main actor; only publishing happens on it.
- `LyricsStatus.message` strings: off "Lyrics off"; nothingPlaying "Nothing playing"; loading "Loading lyrics..."; noSyncedLyrics "No synced lyrics found"; instrumental "Instrumental"; lyricsError "Lyrics service error"; englishNoTranslation "Synced lyrics (English, no translation)"; translating "Translating..."; translated "Synced lyrics, translated"; noKey "No Gemini key set"; translationFailed(m) "Translation failed: " + m.

- [ ] **Step 1: Write failing tests** with a fake `LyricsFetching` (scripted results, call counter, optional suspension via a continuation the test resumes), the scripted fake provider from Task 4, temp-directory cache and key store, and a no-op sleep. `@MainActor` test class.
  - `testDisabledMakesNoFetch`.
  - `testSpanishSongShowsOriginalThenTranslation`: after fetch, rows have `translation == nil` and status `.translating`; after provider resolves, translations filled and `.translated`; cache now has the entry.
  - `testCachedSongMakesNoNetworkCall`: pre-write an entry; fetcher and provider call counts stay 0.
  - `testEnglishSongIsSingleColumnAndUntranslated`: provider call count 0; nothing cached.
  - `testNoKeyShowsSpanishOnly`: status `.noKey`; rows present; provider never built.
  - `testKeyDidChangeRetriesTranslation`.
  - `testTranslationFailureLeavesTranslationNil`: every `row.translation == nil`, status `.translationFailed`, cache empty. No row's translation equals its original.
  - `testPlainInstrumentalNoneAndErrorShowNothing`: four sub-cases, `display == nil` with the matching status.
  - `testStaleFetchResultIsDropped`: start track A with a suspended fetch, switch to track B (resolves immediately), then resume A's fetch; `display` rows are B's. *(Review Focus 1)*
  - `testStaleTranslationIsDroppedAndNotShown`: same shape with a suspended provider.
  - `testUnlookupableTrackMakesNoFetch`: blank artist, and `durationMs == 0`; fetch count 0, `display == nil`. *(Review Focus 2)*
  - `testEnablingMidSongLoadsCurrentTrack`: update with `enabled: false`, then the same playback with `enabled: true`; fetch count 1. *(Review Focus 4)*
  - `testDisablingClearsDisplayAndDropsInFlight`. *(Review Focus 4)*
  - `testPauseAndResumeDoesNotRefetch`: same track, `isPlaying` false then true; fetch count stays 1; `activeIndex` holds still while paused.
  - `testActiveIndexFollowsPosition`: lines at 1000/5000/9000 ms; playing snapshot at position 0 sampled at t; index is -1 at t+500, 0 at t+1200, 1 at t+5200.
  - `testSeekReanchors`: a later snapshot 20 s ahead moves the index accordingly.
  - `testEmptyLinesStayEmptyInBothColumns`: a synced line with empty text has `original == ""` and, once translated, `translation == ""`.
- [ ] **Step 2:** `make test`. Expected: build failure.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `make test`. Expected: pass.
- [ ] **Step 5:** Commit: `Add the lyrics model`.

---

### Task 8: Network services

**Files:**
- Create: `Sources/Services/LRCLIBClient.swift`, `Sources/Services/GeminiProvider.swift`
- Reference: web app `src/lyrics.ts`

**Interfaces:**
- Consumes: `LyricsFetching`, `LyricsResult`, `LRCParser` (Tasks 2, 7); `TranslationProvider`, `TranslationProviderError`, `GeminiAPI` (Task 4).
- Produces:

```swift
struct LRCLIBClient: LyricsFetching { init() }
struct GeminiProvider: TranslationProvider { init(apiKey: String, model: String) }
```

Rules:
- `LRCLIBClient`: `GET https://lrclib.net/api/get` with query `track_name`, `artist_name`, `album_name`, `duration` (whole seconds, rounded). 404 gives `.none`; other non-2xx throws. `instrumental == true` gives `.instrumental`; non-empty `syncedLyrics` that parses to at least one line gives `.synced` with the response `id`; else non-empty `plainLyrics` gives `.plain` (lines trimmed; blank lines dropped only at the very start and end); else `.none`. `User-Agent: MacVisualizer/<CFBundleShortVersionString>` and nothing else identifying.
- `GeminiProvider.generate`: `GeminiAPI.makeRequest`, send, `GeminiAPI.parse`. Transport errors map to `.other`.
- Both use an ephemeral `URLSession` with `timeoutIntervalForRequest` 15 and `timeoutIntervalForResource` 60 (a full-song translation can take a while), `waitsForConnectivity = false`, modeled on `PlayerReader.artworkSession`.

These two files have no unit tests (the Services target has no test target; all parsing logic they call is tested in Core). They are exercised in Task 10.

- [ ] **Step 1:** Implement both files.
- [ ] **Step 2:** `make build`. Expected: succeeds with no new warnings.
- [ ] **Step 3:** `make test`. Expected: pass.
- [ ] **Step 4:** Commit: `Add LRCLIB and Gemini clients`.

---

### Task 9: Settings section

**Files:**
- Create: `Sources/App/LyricsSettingsSection.swift`
- Modify: `Sources/App/SettingsView.swift` (insert the section after `Section("Track Overlay")`, around line 190), `Sources/App/MacVisualizerApp.swift` (create and pass the model)

**Interfaces:**
- Consumes: `LyricsSettings` (Task 1), `GeminiKeyStore` (Task 5), `LyricsModel` (Task 7), `LRCLIBClient`, `GeminiProvider` (Task 8).
- Produces: `struct LyricsSettingsSection: View` taking a `Binding<LyricsSettings>`, the `LyricsModel`, and the `GeminiKeyStore`. `MacVisualizerMain` owns `@StateObject private var lyrics: LyricsModel`, built with `LRCLIBClient()`, `{ GeminiProvider(apiKey: $0, model: $1) }`, `LyricsCacheStore(directory: LyricsCacheStore.defaultDirectory())`, `GeminiKeyStore(fileURL: GeminiKeyStore.defaultFileURL())`, and a `Task.sleep`-based sleep; passed to both `ContentView` and `SettingsView`.

Controls, in order, in `Section("Lyrics")`:

| Control | Binds | Range |
|---|---|---|
| Toggle "Show lyrics" | `enabled` | |
| Slider "Text size" | `textSize` | 12...72, step 1 |
| Slider "Block width" | `blockWidthFraction` | 0.3...1.0 |
| ColorPicker "Active line" | `activeColor` | opacity off |
| ColorPicker "Other lines" | `otherColor` | opacity off |
| Slider "Other lines opacity" | `otherOpacity` | 0.1...1.0 |
| Picker "Past lines" | `pastMode` | Dim / Bright / Neutral |
| Toggle "Drop shadow" | `shadowEnabled` | |
| ColorPicker "Shadow color" | `shadowColor` | opacity off |
| Slider "Shadow opacity" | `shadowOpacity` | 0...1 |
| Slider "Shadow blur" | `shadowRadius` | 0...20 |
| Slider "Shadow offset X" | `shadowOffsetX` | -10...10 |
| Slider "Shadow offset Y" | `shadowOffsetY` | -10...10 |
| SecureField "Gemini API key" + Save / Clear buttons | key file | |
| TextField "Gemini model" | `geminiModel` | |
| Text (secondary style) | `lyrics.status.message` | read-only |

The shadow controls below the toggle are disabled when `shadowEnabled` is false. The key field never displays the stored key: it starts empty with placeholder text "Key saved" or "Not set" depending on `keyStore.read() != nil`. Save writes the field through `keyStore.write`, clears the field, and calls `lyrics.keyDidChange()`. Clear writes an empty string and calls `keyDidChange()`. Match the existing sections' label and slider style; check how `SettingsView.bind(_:)` is written before deciding whether nested key paths (`\.lyrics.textSize`) work with it or a `Binding<LyricsSettings>` is simpler.

Add an `RGBAColor` to and from SwiftUI `Color` conversion as a private extension in this file if one does not already exist in `Sources/App` (search first).

- [ ] **Step 1:** Implement the section and the app wiring. `ContentView` gains the `lyrics` parameter but does not use it yet.
- [ ] **Step 2:** `make build`, then `make test`. Expected: both pass.
- [ ] **Step 3:** Commit: `Add the Lyrics settings section`.

---

### Task 10: Overlay view

**Files:**
- Create: `Sources/App/LyricsOverlay.swift`
- Modify: `Sources/App/MacVisualizerApp.swift` (`ContentView`)

**Interfaces:**
- Consumes: `LyricsModel`, `LyricsDisplay`, `LyricRow` (Task 7); `LyricsSettings`, `LyricRowPhase` (Task 1); `NowPlayingService.playback` (Task 6).
- Produces: `struct LyricsOverlay: View` with `@ObservedObject var lyrics: LyricsModel` and `let settings: LyricsSettings`; a private `LyricPairRow` view per row.

Wiring in `ContentView`: `LyricsOverlay` goes in the `ZStack` between `MetalView` and `TrackOverlay`. Call `lyrics.update(playback: nowPlaying.playback, settings: model.settings.lyrics)` from `.onChange(of: nowPlaying.playback)`, from `.onChange(of: model.settings.lyrics)`, and once in `.onAppear`.

View rules:
- Renders nothing unless `settings.enabled` and `lyrics.display != nil`.
- A `TimelineView(.periodic(from: .now, by: 0.1))` reads `lyrics.activeIndex(atMs: ProcessInfo.processInfo.systemUptime * 1000)`; the index is held in `@State` and only assigned when it changes.
- Rows live in a vertical `ScrollView` with scrolling disabled and indicators hidden, inside a `ScrollViewReader`. Top and bottom padding equal half the view height so the first and last rows can reach the middle. On index change, `proxy.scrollTo(index, anchor: .center)`; animated with `.easeInOut(duration: 0.35)` when the index moved by 1 to 3 rows, unanimated otherwise (larger jump, track change, or first appearance). When the index is -1, scroll to row 0 with anchor `.center`, unanimated.
- Block width is `settings.blockWidthFraction` times the available width, centered.
- Dual mode row: two equal-width cells with a 24 pt gutter; original `.trailing` aligned with `multilineTextAlignment(.trailing)`, translation `.leading`. Single-column mode: one centered cell. Rows are top-aligned so a wrapped cell does not shift its partner.
- Text: system font, bold, size `settings.textSize`, wraps (no line limit). Empty `original` renders as a music note character in the original cell; empty or nil `translation` renders as an empty cell of the same width.
- Color: active row uses `activeColor`; other rows use `otherColor`. Opacity from `settings.opacity(for:)` with phase past (`index < active`), active, or upcoming (`index > active`, and every row when active is -1). Color and opacity changes animate over 0.2 s. Never change font weight or size per phase.
- Shadow, when enabled: `.shadow(color: shadowColor at shadowOpacity, radius: shadowRadius, x: shadowOffsetX, y: shadowOffsetY)` on the text.
- Whole overlay: `.allowsHitTesting(false)`, `.accessibilityHidden(true)`.
- Each row is its own view fed by one `LyricRow` (groups 2 to 5 will attach interaction there).

- [ ] **Step 1:** Implement the overlay and wiring.
- [ ] **Step 2:** `make build`, then `make test`. Expected: both pass.
- [ ] **Step 3: Launch check (manual, needs the user).** `make run`. With lyrics off, the window is unchanged. Ask the user to enter a Gemini key in Settings, turn on Show lyrics, and play a Spanish song with synced lyrics in Spotify. Expected: Spanish column appears, English fills in, the active pair sits mid-window and scrolls up in time. If nothing shows, read the Status line in Settings and Console logs for the app before changing code.
- [ ] **Step 4:** Commit: `Add the lyrics overlay`.

---

### Task 11: Visual validation, docs, version

**Files:**
- Modify: `CLAUDE.md`, `README.md`, `project.yml` (`MARKETING_VERSION`)

- [ ] **Step 1: Visual validation with the user** (invoke the `verify-visualizer-changes` skill; the render probe does not capture the SwiftUI layer, so this is live-window only). Checklist, each confirmed by the user:
  1. Lyrics off: window identical to before.
  2. Spanish song: both columns, aligned pairs, active pair mid-window, smooth upward scroll.
  3. Same song replayed: appears with no "Translating..." status (cache hit).
  4. English song: single centered column, status "Synced lyrics (English, no translation)".
  5. Song without synced lyrics: nothing in the window; status says so.
  6. Seek in the player: highlight snaps to the right line within about two seconds.
  7. Pause: text holds still; resume continues; track card behaves as before.
  8. Skip several tracks quickly: the lyrics shown always belong to the current song.
  9. Each tweak moves what it says: size, width, both colors, other-lines opacity, past mode, each shadow control.
  10. Legibility over at least three visualizer styles including a bright one.
  11. Window-opacity and per-pixel-alpha transparency modes: lyrics visible, fading with the window as the track card does.
  12. Narrow window (640 wide): long lines wrap, pairs stay aligned.
  13. Clear the key: Spanish only, status "No Gemini key set"; Save a key: translation appears without changing track.
  Fix anything that fails before continuing; re-run `make test` after any fix.
- [ ] **Step 2: Docs.** `CLAUDE.md`: add the lyrics files to Architecture and Key types, and a short "Lyrics overlay" section covering the Core/Services/App split, the paused-aware `playback` snapshot versus the unchanged `track`, the cache and key file locations, and the measured Spotify duration unit. `README.md`: a Lyrics section with setup (Gemini key from https://aistudio.google.com, entered in Settings), what is sent where (title, artist, album, duration to LRCLIB; lyric text to Gemini), and where cached lyrics and the key are stored. Do not add `NOTICE` or `THIRD_PARTY_NOTICES.md` entries unless the user asks; the ported code is the user's own.
- [ ] **Step 3: Version.** Ask the user which version number to use, then set `MARKETING_VERSION` in `project.yml` in its own commit, matching the repo's "Bump version to X for ..." commit style.
- [ ] **Step 4:** `make clean && make build && make test`. Expected: pass.
- [ ] **Step 5:** Commit docs: `Document the lyrics overlay`.
