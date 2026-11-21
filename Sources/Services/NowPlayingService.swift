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
import SwiftUI
import AppKit
import Combine
import MacVisualizerCore

/// Polls Music/Spotify for the current track and publishes it to the UI.
/// Reads happen on a background queue; @Published updates are marshalled to main.
final class NowPlayingService: ObservableObject {
    @Published private(set) var track: TrackInfo?
    @Published private(set) var artwork: NSImage?
    /// Bundle id of the player the current `track` is from (Spotify / Music), or
    /// nil when nothing is playing. Lets the UI bring the source app forward.
    @Published private(set) var activeBundleID: String?
    /// Bumped when the current song **restarts from the beginning** (replay,
    /// repeat-one loop, or a seek back to the start) while its track identity is
    /// unchanged. The track overlay keys its fade on this, so a restart re-blooms
    /// the card as if a new song began. Only changes while a track is playing.
    @Published private(set) var replayNonce: Int = 0
    /// The active player's track, position and play state, sent on every
    /// poll WHILE LYRICS ARE ENABLED (see `setLyricsEnabled`). Unlike
    /// `track`, the snapshot stays populated while the player is PAUSED, so
    /// the lyrics overlay can freeze instead of treating a pause as "no
    /// track". Nil when no player is running or no track is readable.
    ///
    /// Deliberately a subject, not `@Published`: the snapshot differs on
    /// every poll (position), and publishing it would re-evaluate every
    /// view observing this service every 1.5 s. Delivered on main.
    let playback = PassthroughSubject<PlaybackSnapshot?, Never>()
    /// Queue-confined. When false (the default) polling does exactly what it
    /// did before lyrics existed: no position/duration reads at all.
    private var lyricsEnabled = false

    private let order = [PlayerReader.spotifyBundle, PlayerReader.musicBundle]
    private let queue = DispatchQueue(label: "visualizer.nowplaying")
    private var timer: DispatchSourceTimer?
    private var lastKey: String?
    /// True track lengths (Spotify trims its reported duration under Crossfade). On `queue`.
    private var lengths = TrackLengthMemory()
    private var lengthRequested: Set<String> = []
    /// Last observed play position (seconds) for the current track, to detect a
    /// restart (position jumping back to the start). Reset when the track changes.
    private var lastPosition: Double = 0

    func start() {
        guard timer == nil else { return }   // already running; don't leak a second timer
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.5, repeating: 1.5)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    /// Turns the per-poll playback snapshot on or off. Enabling polls at
    /// once so lyrics do not wait up to a full interval; disabling sends a
    /// final nil.
    func setLyricsEnabled(_ enabled: Bool) {
        queue.async { [weak self] in
            guard let self, self.lyricsEnabled != enabled else { return }
            self.lyricsEnabled = enabled
            if enabled {
                self.poll()
            } else {
                DispatchQueue.main.async { self.playback.send(nil) }
            }
        }
    }

    // MARK: - Transport

    /// Play/pause, next and previous track on the active player (the one polling
    /// treats as active: a playing player first, else the first running one).
    /// Does nothing when no target player is running; never launches one.
    func togglePlayPause() { transport(.playPause) }
    func nextTrack() { transport(.nextTrack) }
    func previousTrack() { transport(.previousTrack) }

    private func transport(_ command: PlayerReader.Transport) {
        queue.async { [weak self] in
            guard let self else { return }
            let snaps = self.order.map { PlayerReader.snapshot($0) }
            guard let id = selectActivePlayer(snaps, preferenceOrder: self.order) else { return }
            PlayerReader.send(command, to: id)
            // Refresh sooner than the next 1.5 s tick so the overlay follows.
            self.queue.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.poll() }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func poll() { // on `queue`
        let snaps = order.map { PlayerReader.snapshot($0) }
        let activeID = selectActivePlayer(snaps, preferenceOrder: order)
        let isPlaying = activeID.flatMap { id in snaps.first(where: { $0.bundleID == id }) }?.isPlaying == true
        // The track is read once and shared by both paths. With lyrics off it
        // is read only while playing, exactly as before.
        let activeInfo: TrackInfo? = activeID.flatMap { (isPlaying || lyricsEnabled) ? PlayerReader.track($0) : nil }
        if lyricsEnabled {
            let snapshot = activeID.flatMap { id in
                activeInfo.map { readPlayback(id, info: $0, isPlaying: isPlaying) }
            }
            DispatchQueue.main.async { self.playback.send(snapshot) }
        }
        guard let active = activeID, isPlaying, let info = activeInfo else {
            publish(nil, nil)
            lastKey = nil
            lastPosition = 0
            return
        }
        let key = "\(active)|\(info.title ?? "")|\(info.artist ?? "")|\(info.album ?? "")"
        let position = PlayerReader.rawPlayerPosition(active) ?? 0   // seconds, both players
        if key == lastKey {
            // Same track: a jump back to the start (replay / repeat-one / restart)
            // re-triggers the overlay so it blooms again like a fresh song. Fires
            // once — after it does, lastPosition is near 0, so it won't refire until
            // the song plays past `restartFromSeconds` and returns to the start.
            let restartResetSeconds = 2.0
            let restartFromSeconds = 3.0
            if position < restartResetSeconds && lastPosition >= restartFromSeconds {
                DispatchQueue.main.async { self.replayNonce &+= 1 }
            }
            lastPosition = position
            return // track unchanged; avoid refetching artwork
        }
        lastKey = key
        lastPosition = position

        // Embedded artwork (Music) is available locally with no I/O — publish it now.
        if let local = PlayerReader.localArtwork(active) {
            publish(info, local, bundleID: active)
            return
        }

        // URL-based artwork (Spotify) must be fetched. Publish the track immediately
        // with no artwork, then fetch OFF this timer queue so a slow/hung URL can
        // never stall polling. The artwork lands later via deliverArtwork.
        publish(info, nil, bundleID: active)
        if let url = PlayerReader.artworkURL(active) {
            PlayerReader.fetchArtwork(from: url) { [weak self] img in
                self?.deliverArtwork(forKey: key, img)
            }
        }
    }

    /// Applies a late-arriving artwork fetch, but only if the track that requested it
    /// is still current. Re-enters `queue` to read `lastKey` safely (the fetch
    /// completion runs on URLSession's background queue).
    private func deliverArtwork(forKey key: String, _ image: NSImage?) {
        guard let image else { return }
        queue.async { [weak self] in
            guard let self, self.lastKey == key else { return } // track changed mid-fetch
            DispatchQueue.main.async { self.artwork = image }
        }
    }

    /// Reads position and duration for the active player's track. On `queue`.
    private func readPlayback(_ active: String, info: TrackInfo, isPlaying: Bool) -> PlaybackSnapshot {
        let rawPosition = PlayerReader.rawPlayerPosition(active) ?? 0
        let sampledAtMs = ProcessInfo.processInfo.systemUptime * 1000
        let rawDuration = PlayerReader.rawDuration(active) ?? 0
        let track = LyricsTrack(
            title: info.title ?? "",
            artist: info.artist ?? "",
            album: info.album ?? "",
            durationMs: trueLengthMs(active, reportedMs: PlaybackUnits.durationMs(raw: rawDuration, bundleID: active))
        )
        return PlaybackSnapshot(
            track: track,
            positionMs: PlaybackUnits.positionMs(rawSeconds: rawPosition),
            isPlaying: isPlaying,
            sampledAtMs: sampledAtMs
        )
    }

    /// The track's true length for lyric matching. Spotify reports a SHORTENED
    /// duration while it crossfades a song into the next (see `TrackLengthMemory`),
    /// so the longest length seen wins, corrected by the length on the track's
    /// public page, fetched once per track per session. On `queue`.
    private func trueLengthMs(_ active: String, reportedMs: Int) -> Int {
        guard active == PlayerReader.spotifyBundle, reportedMs > 0,
              let uri = PlayerReader.spotifyTrackURI(),
              let id = SpotifyTrackPage.trackID(fromURI: uri) else { return reportedMs }
        if lengthRequested.insert(id).inserted {
            if lengthRequested.count > 2000 { lengthRequested = [id] }
            Task.detached { [weak self] in
                guard let seconds = await SpotifyTrackLengthFetcher.durationSeconds(trackID: id) else { return }
                self?.queue.async { self?.lengths.setPublished(id: id, seconds: seconds) }
            }
        }
        return lengths.resolve(id: id, reportedMs: reportedMs)
    }

    private func publish(_ track: TrackInfo?, _ artwork: NSImage?, bundleID: String? = nil) {
        DispatchQueue.main.async {
            self.track = track
            self.artwork = artwork
            self.activeBundleID = bundleID
        }
    }

    deinit { stop() }

    // MARK: - Track key

    /// Returns a stable string identifier for a track suitable for stamping into
    /// AudioFrame.trackId. Returns nil when no track is playing.
    static func trackKey(for track: TrackInfo?) -> String? {
        guard let t = track, !t.isEmpty else { return nil }
        return "\(t.title ?? "")|\(t.artist ?? "")|\(t.album ?? "")"
    }
}