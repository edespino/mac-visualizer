//
// Copyright 2026 Ed Espino
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
// implied. See the License for the specific language governing
// permissions and limitations under the License.
//
import ScriptingBridge
import AppKit
import os
import MacVisualizerCore

/// Reads now-playing info from Music/Spotify via ScriptingBridge (dynamic KVC).
/// Every read is gated behind a running check so polling never launches the app.
enum PlayerReader {
    static let musicBundle = "com.apple.Music"
    static let spotifyBundle = "com.spotify.client"

    private static let log = Logger(subsystem: Log.subsystem, category: "now-playing")

    /// 'kPSP' — the "playing" player-state FourCC, identical in both apps' dictionaries.
    static let playingCode: UInt32 = 0x6B505350

    /// Exception-safe dynamic access. ScriptingBridge KVC raises Obj-C
    /// exceptions — uncatchable from Swift — when a player app's scripting
    /// interface drifts or the app quits mid-call. `body` runs under an Obj-C
    /// @try/@catch (MVCatchObjCException); a raised exception logs and yields
    /// nil instead of terminating the process.
    private static func catchingObjCException<T>(_ label: String, _ body: () -> T?) -> T? {
        var result: T?
        if let e = MVCatchObjCException({ result = body() }) {
            log.error("ScriptingBridge \(label, privacy: .public) raised \(e.name.rawValue, privacy: .public): \(e.reason ?? "", privacy: .public)")
            return nil
        }
        return result
    }

    /// KVC read through the exception shim: nil on missing key OR raised exception.
    private static func safeValue(_ object: NSObject, forKey key: String) -> Any? {
        catchingObjCException("value(forKey: \"\(key)\")") { object.value(forKey: key) }
    }

    /// Player transport commands, named by the scripting selector both Spotify and
    /// Music expose (`playpause`, `nextTrack`, `previousTrack`).
    enum Transport: String {
        case playPause = "playpause"
        case nextTrack
        case previousTrack
    }

    /// Sends a transport command to an ALREADY RUNNING player (never launches it),
    /// through the same Obj-C exception shim as the reads.
    static func send(_ command: Transport, to bundleID: String) {
        guard let app = app(bundleID) else { return }
        let selector = Selector(command.rawValue)
        _ = catchingObjCException("transport \(command.rawValue)") { () -> Bool? in
            _ = app.perform(selector)
            return true
        }
    }

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
        let v = safeValue(app, forKey: "playerState")
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
              let track = safeValue(app, forKey: "currentTrack") as? NSObject else { return nil }
        let title = safeValue(track, forKey: "name") as? String
        let artist = safeValue(track, forKey: "artist") as? String
        let album = safeValue(track, forKey: "album") as? String
        if title == nil && artist == nil && album == nil { return nil }
        return TrackInfo(title: title, artist: artist, album: album)
    }

    /// Raw `duration` of the current track exactly as the player reports it,
    /// or nil. Units differ per player; convert with `PlaybackUnits.durationMs`.
    static func rawDuration(_ bundleID: String) -> Double? {
        guard let app = app(bundleID),
              let track = safeValue(app, forKey: "currentTrack") as? NSObject else { return nil }
        return (safeValue(track, forKey: "duration") as? NSNumber)?.doubleValue
    }

    /// Spotify's URI for the current track (`spotify:track:<id>`), or nil.
    static func spotifyTrackURI() -> String? {
        guard let app = app(spotifyBundle),
              let track = safeValue(app, forKey: "currentTrack") as? NSObject else { return nil }
        return safeValue(track, forKey: "id") as? String
    }

    /// Raw `player position` (seconds into the current track), or nil.
    static func rawPlayerPosition(_ bundleID: String) -> Double? {
        guard let app = app(bundleID) else { return nil }
        return (safeValue(app, forKey: "playerPosition") as? NSNumber)?.doubleValue
    }

    /// Runtime type and value of a raw scripting property, for the probe.
    static func describeRaw(_ bundleID: String, trackKey: String?, appKey: String?) -> String {
        guard let app = app(bundleID) else { return "nil (not running)" }
        var object: NSObject? = app
        var key = appKey
        if let trackKey {
            object = safeValue(app, forKey: "currentTrack") as? NSObject
            key = trackKey
        }
        guard let object, let key, let value = safeValue(object, forKey: key) else { return "nil" }
        return "\(value) (\(type(of: value)))"
    }

    /// Shared session with explicit request/resource timeouts so an artwork
    /// fetch can never hang indefinitely (the failure mode of `Data(contentsOf:)`).
    private static let artworkSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5     // per-request stall ceiling
        cfg.timeoutIntervalForResource = 10   // whole-fetch ceiling
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    /// Artwork that is available without any network access — Music's embedded
    /// artwork data. Returns nil for URL-based sources (e.g. Spotify); use
    /// `artworkURL` + `fetchArtwork` to load those off the caller's queue.
    static func localArtwork(_ bundleID: String) -> NSImage? {
        guard bundleID == musicBundle,
              let app = app(bundleID),
              let track = safeValue(app, forKey: "currentTrack") as? NSObject,
              let arts = safeValue(track, forKey: "artworks") as? SBElementArray,
              let first = catchingObjCException("artworks.firstObject", { arts.firstObject }) as? NSObject,
              let blob = safeValue(first, forKey: "data") else { return nil }
        if let img = blob as? NSImage { return img }
        if let d = blob as? Data { return NSImage(data: d) }
        return nil
    }

    /// Remote artwork URL (e.g. Spotify's `artworkUrl`), or nil. Cheap, no I/O.
    static func artworkURL(_ bundleID: String) -> URL? {
        guard bundleID != musicBundle,
              let app = app(bundleID),
              let track = safeValue(app, forKey: "currentTrack") as? NSObject,
              let urlStr = safeValue(track, forKey: "artworkUrl") as? String else { return nil }
        return URL(string: urlStr)
    }

    /// Fetch remote artwork without blocking the caller's thread. The request runs
    /// on `artworkSession`'s background queue with bounded timeouts, so it can never
    /// stall the queue that scheduled it; `completion` receives nil on any failure.
    static func fetchArtwork(from url: URL, completion: @escaping (NSImage?) -> Void) {
        let task = artworkSession.dataTask(with: url) { data, _, _ in
            completion(data.flatMap(NSImage.init(data:)))
        }
        task.resume()
    }

    /// Album artwork as an NSImage, or nil. Synchronous with bounded timeouts —
    /// suitable for one-shot diagnostics. NEVER call from the polling timer queue;
    /// use `localArtwork` + `fetchArtwork` there so polling is never blocked.
    static func artwork(_ bundleID: String) -> NSImage? {
        if let local = localArtwork(bundleID) { return local }
        guard let url = artworkURL(bundleID) else { return nil }
        // dataTask completes on the session's background queue, so waiting on the
        // calling thread cannot deadlock. The timeout bounds the wait regardless.
        let sem = DispatchSemaphore(value: 0)
        var result: NSImage?
        fetchArtwork(from: url) { img in
            result = img
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 10)
        return result
    }
}
