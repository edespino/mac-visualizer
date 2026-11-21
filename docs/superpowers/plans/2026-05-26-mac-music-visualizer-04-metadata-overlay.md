# Mac Music Visualizer — Plan 4: Track Metadata Overlay

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a small overlay on the visualizer with the currently-playing track (title, artist, album, album artwork) read from Apple Music / Spotify.

**Architecture:** The pure, testable pieces (the `TrackInfo` value type and the "which player is active" selection logic) live in `MacVisualizerCore`. The untestable ScriptingBridge integration (`PlayerReader`, `NowPlayingService`) lives in the app target and is verified by a headless `--nowplaying-probe` CLI mode plus a live run. The overlay is a SwiftUI view layered over the existing `MetalView`, honoring the overlay settings already in `VisualizerSettings` (enabled / corner / opacity).

**Tech Stack:** Swift 5.10, ScriptingBridge (dynamic KVC, no generated headers), AppKit (`NSRunningApplication`, `NSImage`), SwiftUI, XCTest.

**Builds on Plans 1–3 (merged):** the visualizer window (`MetalView`/`ContentView`/`MacVisualizerMain`), `RenderModel`, and `VisualizerSettings` (which already has `overlayEnabled`, `overlayPosition: OverlayCorner`, `overlayOpacity`).

**Verified API basis (researched, cited):** Read now-playing via **ScriptingBridge dynamic access**, NOT the private MediaRemote framework (Apple locked MediaRemote down for unentitled apps in macOS 15.4). Confirmed from the on-disk scripting dictionaries: bundle ids `com.apple.Music` / `com.spotify.client`; KVC keys `currentTrack`, `playerState`, `name`/`artist`/`album`; Music artwork via the `artworks` element's `data` (a picture → `NSImage`); Spotify artwork via `artworkUrl` (an HTTP URL string — the old embedded `artwork` is deprecated and "will never be set"). Permission: the **Automation** TCC prompt fires per-target on the first Apple Event; declared by the **`NSAppleEventsUsageDescription`** Info.plist key. **No entitlement** is required for this non-sandboxed build with Hardened Runtime OFF (a distributed/notarized build would later need `com.apple.security.automation.apple-events`). To avoid launching the apps just to poll, gate every read behind `NSRunningApplication`. Uncertain (handle defensively, confirm via the probe): the exact Swift type ScriptingBridge returns for `playerState` (FourCC `UInt32` vs `NSNumber`) and for Music's artwork `data` (`Data` vs `NSImage`).

**Scope boundary — NOT in this plan:** the Settings UI and the sample-rate/barCount analyzer reconfigure (those are Plan 5). The overlay reads the overlay-related settings from the on-disk `VisualizerSettings` (defaults until Plan 5 lets the user edit them live).

---

## File Structure

```
mac-visualizer/
  project.yml                                   # MODIFY: add NSAppleEventsUsageDescription
  Sources/
    Core/
      TrackInfo.swift                           # CREATE: pure value type + active-player selection
    App/
      MacVisualizerApp.swift                    # MODIFY: --nowplaying-probe CLI; host NowPlayingService; ZStack overlay
      TrackOverlay.swift                        # CREATE: SwiftUI overlay view
    Services/
      PlayerReader.swift                        # CREATE: ScriptingBridge reads (running/state/track/artwork)
      NowPlayingService.swift                   # CREATE: ObservableObject polling loop -> @Published track/artwork
      NowPlayingProbe.swift                     # CREATE: CLI verification
  Tests/
    CoreTests/
      TrackInfoTests.swift                      # CREATE
      ActivePlayerSelectionTests.swift          # CREATE
```

**Decomposition rationale:** `TrackInfo` + `selectActivePlayer` are pure and unit-tested. `PlayerReader`/`NowPlayingService`/`NowPlayingProbe` are the ScriptingBridge layer, isolated in `Sources/Services` and verified by the probe + live run. `TrackOverlay` is a pure SwiftUI view that takes already-resolved data.

---

## Task 1: `TrackInfo` + active-player selection (pure, testable)

**Files:**
- Create: `Sources/Core/TrackInfo.swift`
- Test: `Tests/CoreTests/TrackInfoTests.swift`
- Test: `Tests/CoreTests/ActivePlayerSelectionTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/CoreTests/TrackInfoTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class TrackInfoTests: XCTestCase {
    func testIsEmptyWhenAllNilOrBlank() {
        XCTAssertTrue(TrackInfo(title: nil, artist: nil, album: nil).isEmpty)
        XCTAssertTrue(TrackInfo(title: "", artist: "", album: "").isEmpty)
    }

    func testNotEmptyWhenTitlePresent() {
        XCTAssertFalse(TrackInfo(title: "Song", artist: nil, album: nil).isEmpty)
    }

    func testEquatable() {
        XCTAssertEqual(TrackInfo(title: "A", artist: "B", album: "C"),
                       TrackInfo(title: "A", artist: "B", album: "C"))
        XCTAssertNotEqual(TrackInfo(title: "A", artist: "B", album: "C"),
                          TrackInfo(title: "A", artist: "B", album: "D"))
    }
}
```

`Tests/CoreTests/ActivePlayerSelectionTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class ActivePlayerSelectionTests: XCTestCase {
    private let order = ["com.spotify.client", "com.apple.Music"]

    func testPrefersAPlayingPlayer() {
        let snaps = [
            PlayerSnapshot(bundleID: "com.spotify.client", isRunning: true, isPlaying: false),
            PlayerSnapshot(bundleID: "com.apple.Music", isRunning: true, isPlaying: true),
        ]
        XCTAssertEqual(selectActivePlayer(snaps, preferenceOrder: order), "com.apple.Music")
    }

    func testPreferenceOrderBreaksTieAmongPlaying() {
        let snaps = [
            PlayerSnapshot(bundleID: "com.spotify.client", isRunning: true, isPlaying: true),
            PlayerSnapshot(bundleID: "com.apple.Music", isRunning: true, isPlaying: true),
        ]
        XCTAssertEqual(selectActivePlayer(snaps, preferenceOrder: order), "com.spotify.client")
    }

    func testFallsBackToRunningWhenNonePlaying() {
        let snaps = [
            PlayerSnapshot(bundleID: "com.apple.Music", isRunning: true, isPlaying: false),
        ]
        XCTAssertEqual(selectActivePlayer(snaps, preferenceOrder: order), "com.apple.Music")
    }

    func testNilWhenNoneRunning() {
        let snaps = [
            PlayerSnapshot(bundleID: "com.spotify.client", isRunning: false, isPlaying: false),
            PlayerSnapshot(bundleID: "com.apple.Music", isRunning: false, isPlaying: false),
        ]
        XCTAssertNil(selectActivePlayer(snaps, preferenceOrder: order))
    }

    func testIgnoresUnknownBundles() {
        let snaps = [PlayerSnapshot(bundleID: "com.other.app", isRunning: true, isPlaying: true)]
        XCTAssertNil(selectActivePlayer(snaps, preferenceOrder: order))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — `cannot find 'TrackInfo' / 'PlayerSnapshot' / 'selectActivePlayer' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/Core/TrackInfo.swift`:

```swift
import Foundation

/// Currently-playing track metadata (artwork is resolved separately as an image).
public struct TrackInfo: Equatable {
    public var title: String?
    public var artist: String?
    public var album: String?

    public init(title: String?, artist: String?, album: String?) {
        self.title = title
        self.artist = artist
        self.album = album
    }

    public var isEmpty: Bool {
        (title?.isEmpty ?? true) && (artist?.isEmpty ?? true) && (album?.isEmpty ?? true)
    }
}

/// A snapshot of one media player's run/play status (no ScriptingBridge here — pure).
public struct PlayerSnapshot: Equatable {
    public let bundleID: String
    public let isRunning: Bool
    public let isPlaying: Bool

    public init(bundleID: String, isRunning: Bool, isPlaying: Bool) {
        self.bundleID = bundleID
        self.isRunning = isRunning
        self.isPlaying = isPlaying
    }
}

/// Choose the active player: a running+playing one (first in `preferenceOrder`),
/// else the first running one (preference order), else nil. Unknown bundles are ignored.
public func selectActivePlayer(_ snapshots: [PlayerSnapshot], preferenceOrder: [String]) -> String? {
    for id in preferenceOrder {
        if let s = snapshots.first(where: { $0.bundleID == id }), s.isRunning, s.isPlaying { return id }
    }
    for id in preferenceOrder {
        if let s = snapshots.first(where: { $0.bundleID == id }), s.isRunning { return id }
    }
    return nil
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: `** TEST SUCCEEDED **`, the 3 `TrackInfoTests` + 5 `ActivePlayerSelectionTests` pass (total 62).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/TrackInfo.swift Tests/CoreTests/TrackInfoTests.swift Tests/CoreTests/ActivePlayerSelectionTests.swift
git commit -m "Add TrackInfo and pure active-player selection"
```

---

## Task 2: `PlayerReader` + `NowPlayingService` + `--nowplaying-probe` + permission key

**Files:**
- Modify: `project.yml`
- Create: `Sources/Services/PlayerReader.swift`
- Create: `Sources/Services/NowPlayingService.swift`
- Create: `Sources/Services/NowPlayingProbe.swift`
- Modify: `Sources/App/MacVisualizerApp.swift` (add `--nowplaying-probe`)

This is the ScriptingBridge integration — no unit tests. Verified by the probe (with a player running + Automation granted) and the live run in Task 3.

- [ ] **Step 1: Add the Automation usage string in `project.yml`**

In the `MacVisualizer` target's `info.properties`, add (alongside the existing keys, including `NSAudioCaptureUsageDescription`):

```yaml
        NSAppleEventsUsageDescription: "Mac Visualizer reads the current track from Apple Music or Spotify to show it on screen."
```

(One key for the whole app; the per-target "control" prompt appears on first access. No entitlement needed — this build has Hardened Runtime off. The key MUST be present before the first Apple Event or macOS terminates the app.)

- [ ] **Step 2: Write `Sources/Services/PlayerReader.swift`**

```swift
import ScriptingBridge
import AppKit
import MacVisualizerCore

/// Reads now-playing info from Music/Spotify via ScriptingBridge (dynamic KVC).
/// Every read is gated behind a running check so polling never launches the app.
enum PlayerReader {
    static let musicBundle = "com.apple.Music"
    static let spotifyBundle = "com.spotify.client"

    /// 'kPSP' — the "playing" player-state FourCC, identical in both apps' dictionaries.
    static let playingCode: UInt32 = 0x6B505350

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// An SBApplication handle ONLY if the app is already running (never launches it).
    private static func app(_ bundleID: String) -> SBApplication? {
        guard isRunning(bundleID) else { return nil }
        return SBApplication(bundleIdentifier: bundleID)
    }

    /// Raw player-state value (FourCC), or nil. Exposed so the probe can show what SB returns.
    static func playerStateRaw(_ bundleID: String) -> UInt32? {
        guard let app = app(bundleID) else { return nil }
        let v = app.value(forKey: "playerState")
        if let n = v as? NSNumber { return n.uint32Value }
        if let u = v as? UInt32 { return u }
        return nil
    }

    static func isPlaying(_ bundleID: String) -> Bool {
        playerStateRaw(bundleID) == playingCode
    }

    static func snapshot(_ bundleID: String) -> PlayerSnapshot {
        PlayerSnapshot(bundleID: bundleID, isRunning: isRunning(bundleID), isPlaying: isPlaying(bundleID))
    }

    /// Current track metadata, or nil if not running / nothing readable.
    static func track(_ bundleID: String) -> TrackInfo? {
        guard let app = app(bundleID),
              let track = app.value(forKey: "currentTrack") as? NSObject else { return nil }
        let title = track.value(forKey: "name") as? String
        let artist = track.value(forKey: "artist") as? String
        let album = track.value(forKey: "album") as? String
        if title == nil && artist == nil && album == nil { return nil }
        return TrackInfo(title: title, artist: artist, album: album)
    }

    /// Album artwork as an NSImage, or nil. Synchronous (call off the main thread).
    static func artwork(_ bundleID: String) -> NSImage? {
        guard let app = app(bundleID),
              let track = app.value(forKey: "currentTrack") as? NSObject else { return nil }
        if bundleID == musicBundle {
            // Music: data of artwork 1 of current track -> picture (Data or NSImage via SB).
            guard let arts = track.value(forKey: "artworks") as? SBElementArray,
                  let first = arts.firstObject as? NSObject,
                  let blob = first.value(forKey: "data") else { return nil }
            if let img = blob as? NSImage { return img }
            if let d = blob as? Data { return NSImage(data: d) }
            return nil
        } else {
            // Spotify: artwork url -> fetch.
            guard let urlStr = track.value(forKey: "artworkUrl") as? String,
                  let url = URL(string: urlStr),
                  let d = try? Data(contentsOf: url) else { return nil }
            return NSImage(data: d)
        }
    }
}
```

- [ ] **Step 3: Write `Sources/Services/NowPlayingService.swift`**

```swift
import SwiftUI
import AppKit
import MacVisualizerCore

/// Polls Music/Spotify for the current track and publishes it to the UI.
/// Reads happen on a background queue; @Published updates are marshalled to main.
final class NowPlayingService: ObservableObject {
    @Published private(set) var track: TrackInfo?
    @Published private(set) var artwork: NSImage?

    private let order = [PlayerReader.spotifyBundle, PlayerReader.musicBundle]
    private let queue = DispatchQueue(label: "visualizer.nowplaying")
    private var timer: DispatchSourceTimer?
    private var lastKey: String?

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.5, repeating: 1.5)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func poll() { // on `queue`
        let snaps = order.map { PlayerReader.snapshot($0) }
        guard let active = selectActivePlayer(snaps, preferenceOrder: order),
              snaps.first(where: { $0.bundleID == active })?.isPlaying == true,
              let info = PlayerReader.track(active) else {
            publish(nil, nil)
            lastKey = nil
            return
        }
        let key = "\(active)|\(info.title ?? "")|\(info.artist ?? "")|\(info.album ?? "")"
        if key == lastKey { return } // track unchanged; avoid refetching artwork
        lastKey = key
        let art = PlayerReader.artwork(active)
        publish(info, art)
    }

    private func publish(_ track: TrackInfo?, _ artwork: NSImage?) {
        DispatchQueue.main.async {
            self.track = track
            self.artwork = artwork
        }
    }

    deinit { stop() }
}
```

- [ ] **Step 4: Write `Sources/Services/NowPlayingProbe.swift`**

```swift
import Foundation
import MacVisualizerCore

/// CLI verification: print each player's run/play state (raw FourCC) and, for the active
/// playing one, its track. First run triggers the Automation permission prompt per app.
enum NowPlayingProbe {
    static func run() {
        let order = [PlayerReader.spotifyBundle, PlayerReader.musicBundle]
        for id in order {
            let running = PlayerReader.isRunning(id)
            let raw = PlayerReader.playerStateRaw(id)
            let rawStr = raw.map { String(format: "0x%08X", $0) } ?? "nil"
            print("\(id): running=\(running) playerStateRaw=\(rawStr) isPlaying=\(PlayerReader.isPlaying(id))")
        }
        let snaps = order.map { PlayerReader.snapshot($0) }
        if let active = selectActivePlayer(snaps, preferenceOrder: order) {
            print("active: \(active)")
            if let t = PlayerReader.track(active) {
                print("  title:  \(t.title ?? "?")")
                print("  artist: \(t.artist ?? "?")")
                print("  album:  \(t.album ?? "?")")
                print("  artwork: \(PlayerReader.artwork(active) != nil ? "present" : "none")")
            } else {
                print("  (no readable track)")
            }
        } else {
            print("active: none")
        }
    }
}
```

- [ ] **Step 5: Add the `--nowplaying-probe` CLI branch**

In `Sources/App/MacVisualizerApp.swift`, in `AppEntry.main()`, add this branch after the `--audio-probe` branch and before `--render-probe`:

```swift
        if args.contains("--nowplaying-probe") {
            NowPlayingProbe.run()
            exit(0)
        }
```

- [ ] **Step 6: Build and run the probe (with a player running)**

Run: `make build` → expect `** BUILD SUCCEEDED **`.

With Spotify or Apple Music open and PLAYING a track, run:
```bash
./DerivedData/Build/Products/Debug/MacVisualizer.app/Contents/MacOS/MacVisualizer --nowplaying-probe
```
On first run, macOS shows "MacVisualizer wants to control Spotify/Music" — grant it (re-run after granting). Expected: a line per app with `running=true` for the playing app, a non-nil `playerStateRaw`, and `isPlaying=true`; then the active player's title/artist/album and `artwork: present`.

IMPORTANT verification-honesty note: report the VERBATIM output. The key uncertainty is whether `isPlaying` correctly decodes — if `playerStateRaw` prints a non-nil value (e.g. `0x6B505350`) but `isPlaying=false` while music is audibly playing, the FourCC constant or the SB return type is different than assumed: report the actual `playerStateRaw` value (DONE_WITH_CONCERNS) so the `playingCode`/decoding can be corrected. Do NOT fake `isPlaying=true`. If you (the agent) cannot grant the Automation prompt or have nothing playing, build successfully, run the probe once, and report the verbatim output (likely `running=...`, `playerStateRaw=nil` or denied) with status DONE_WITH_CONCERNS noting live confirmation is pending the user.

- [ ] **Step 7: Run unit tests**

Run: `make test` → expect `** TEST SUCCEEDED **`, total 62.

- [ ] **Step 8: Commit**

```bash
git add project.yml Sources/Services/PlayerReader.swift Sources/Services/NowPlayingService.swift Sources/Services/NowPlayingProbe.swift Sources/App/MacVisualizerApp.swift
git commit -m "Add ScriptingBridge now-playing reader, polling service, and --nowplaying-probe"
```

---

## Task 3: `TrackOverlay` view + wire into the window

**Files:**
- Create: `Sources/App/TrackOverlay.swift`
- Modify: `Sources/App/MacVisualizerApp.swift` (host `NowPlayingService`, layer the overlay)

- [ ] **Step 1: Write `Sources/App/TrackOverlay.swift`**

```swift
import SwiftUI
import AppKit
import MacVisualizerCore

/// A non-interactive overlay showing the current track + artwork in a chosen corner.
struct TrackOverlay: View {
    let track: TrackInfo?
    let artwork: NSImage?
    let settings: VisualizerSettings

    var body: some View {
        if settings.overlayEnabled, let track, !track.isEmpty {
            card(track)
                .opacity(Double(settings.overlayOpacity))
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(settings.overlayPosition))
                .allowsHitTesting(false)
        }
    }

    private func card(_ track: TrackInfo) -> some View {
        HStack(spacing: 10) {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title ?? "")
                    .font(.headline)
                    .lineLimit(1)
                let secondary = [track.artist, track.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
                if !secondary.isEmpty {
                    Text(secondary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(.white)
    }

    private func alignment(_ corner: OverlayCorner) -> Alignment {
        switch corner {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }
}
```

- [ ] **Step 2: Host `NowPlayingService` and layer the overlay**

In `Sources/App/MacVisualizerApp.swift`, replace the `MacVisualizerMain` struct and the `ContentView` struct with:

```swift
struct MacVisualizerMain: App {
    @StateObject private var model = RenderModel()
    @StateObject private var nowPlaying = NowPlayingService()

    var body: some Scene {
        Window("Mac Visualizer", id: "main") {
            ContentView(model: model, nowPlaying: nowPlaying)
                .background(WindowConfigurator(alwaysOnTop: model.settings.alwaysOnTop))
                .onAppear { nowPlaying.start() }
        }
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Toggle Full Screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: RenderModel
    @ObservedObject var nowPlaying: NowPlayingService

    var body: some View {
        ZStack {
            MetalView(model: model)
                .ignoresSafeArea()
            TrackOverlay(track: nowPlaying.track, artwork: nowPlaying.artwork, settings: model.settings)
        }
        .frame(minWidth: 640, minHeight: 360)
    }
}
```

(Leave `@main enum AppEntry`, the probe branches, and `WindowConfigurator` unchanged.)

- [ ] **Step 3: Build**

Run: `make build` → expect `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Render-probe regression (no audio/automation needed)**

```bash
./DerivedData/Build/Products/Debug/MacVisualizer.app/Contents/MacOS/MacVisualizer --render-probe /tmp/probe_p4.png && echo "exit=$?"
```
Read `/tmp/probe_p4.png`: still the green→red staircase (the probe path renders bars only, no overlay/now-playing — must be unchanged).

- [ ] **Step 5: Run unit tests**

Run: `make test` → expect `** TEST SUCCEEDED **`, total 62.

- [ ] **Step 6: Live verification (requires the user)**

Run `make run` with Apple Music/Spotify playing. On first launch, grant the "control Music/Spotify" Automation prompt(s). Expected: the visualizer shows a track overlay (artwork + title + artist/album) in the bottom-leading corner (the default `overlayPosition`), at ~0.85 opacity, updating when the track changes, and hiding when playback stops. The bars continue reacting to audio underneath.

The agent should: build, run the render-probe regression (Step 4), and confirm the app launches without crashing; then report that live overlay confirmation is pending the user. Do NOT claim the overlay shows the correct track without user confirmation.

- [ ] **Step 7: Commit**

```bash
git add Sources/App/TrackOverlay.swift Sources/App/MacVisualizerApp.swift
git commit -m "Add track metadata overlay layered over the visualizer"
```

---

## Definition of Done (Plan 4)

- `make test` → `** TEST SUCCEEDED **`, 62 Core tests (TrackInfo + active-player selection added).
- `make build` → `** BUILD SUCCEEDED **`.
- `MacVisualizer --nowplaying-probe` prints the active player's track (artwork present) with music playing + Automation granted — confirmed by the user; `playerStateRaw`/`isPlaying` decode validated against real output.
- `make run` shows the track overlay over the live visualizer; it updates on track change and hides when stopped — confirmed by the user.
- `--render-probe` still renders the bar staircase (overlay change didn't regress rendering).

## Handoff to Plan 5 (Settings UI + analyzer reconfigure)

Plan 5 adds the SwiftUI Settings window bound to `VisualizerSettings`, applying changes live: palette switch, `gain`/`smoothing`/`peakHoldEnabled` via `SpectrumAnalyzer.update(...)`, `barCount` and the **captured sample rate** via a new `SpectrumAnalyzer` reconfigure path (the Plan 3 carry-forward — `RenderModel` currently discards the delivered rate and pins 48000), overlay options (enabled/corner/opacity — already consumed by `TrackOverlay` here), and window/display (`alwaysOnTop`, `targetFPS`, background). Persist on change via `VisualizerSettings.save(to:)`. Also pool the per-draw `MTLBuffer` in `MetalRenderer.encode`. When `barCount` changes, the `SyntheticFrameSource`, analyzer `BandMapper`, and `BandPostProcessor` must all be rebuilt consistently.

## Notes on verification honesty (ScriptingBridge)

The now-playing path can't be unit-tested (depends on the apps + Automation permission). Confidence comes from: (1) `TrackInfo`/`selectActivePlayer` are unit-tested; (2) `--nowplaying-probe` proves the ScriptingBridge reads work and validates the `playerState` decode against real output; (3) the user confirms the overlay shows the correct track + artwork live. Do not claim it works from build success alone.
