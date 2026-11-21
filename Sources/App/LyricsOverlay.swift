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
import Combine
import MacVisualizerCore

extension LyricsModel {
    /// The model wired to the real services: LRCLIB, Gemini, and the
    /// on-disk cache and key file next to settings.json.
    static func live() -> LyricsModel {
        LyricsModel(
            fetcher: CompositeLyricsFetcher(local: LocalLyricsReader(), remote: LRCLIBClient()),
            makeProvider: { GeminiProvider(apiKey: $0, model: $1) },
            cache: LyricsCacheStore(directory: LyricsCacheStore.defaultDirectory()),
            keyStore: GeminiKeyStore(fileURL: GeminiKeyStore.defaultFileURL()),
            sleep: { ms in try? await Task.sleep(nanoseconds: UInt64(max(ms, 0)) * 1_000_000) }
        )
    }
}

/// Connects the three independent pieces the lyrics need: the player poll
/// (`NowPlayingService.playback`), the lyrics settings (`RenderModel`), and
/// the `LyricsModel`. Lives outside the view tree so a poll never
/// re-evaluates a view, and so the service only does its extra player
/// reads while lyrics are turned on.
@MainActor
final class LyricsCoordinator {
    private var cancellables: Set<AnyCancellable> = []
    private var latestPlayback: PlaybackSnapshot?
    private var latestSettings: LyricsSettings

    init(model: RenderModel, nowPlaying: NowPlayingService, lyrics: LyricsModel) {
        latestSettings = model.settings.lyrics
        nowPlaying.setLyricsEnabled(latestSettings.enabled)
        lyrics.update(playback: nil, settings: latestSettings)

        nowPlaying.playback
            .sink { [weak self, weak lyrics] playback in
                guard let self, let lyrics else { return }
                self.latestPlayback = playback
                lyrics.update(playback: playback, settings: self.latestSettings)
            }
            .store(in: &cancellables)

        // `model.lyricsShowing` (which the renderer uses to center the visualization
        // below the text) is driven by the LyricsOverlay view via onTextVisibleChange
        // instead of from `display != nil` here, so a no-lyrics header that has
        // scrolled off correctly reads as "no text showing" and recenters the viz.

        model.$settings
            .map(\.lyrics)
            .removeDuplicates()
            .sink { [weak self, weak lyrics, weak nowPlaying] settings in
                guard let self, let lyrics else { return }
                let wasEnabled = self.latestSettings.enabled
                self.latestSettings = settings
                if settings.enabled != wasEnabled {
                    if !settings.enabled { self.latestPlayback = nil }
                    nowPlaying?.setLyricsEnabled(settings.enabled)
                }
                lyrics.update(playback: self.latestPlayback, settings: settings)
            }
            .store(in: &cancellables)
    }
}

/// A non-interactive overlay that scrolls time-synced lyric pairs over the
/// visualizer: original right-aligned, translation left-aligned, meeting at
/// a center gutter, with the active pair held at mid-window.
struct LyricsOverlay: View {
    @ObservedObject var lyrics: LyricsModel
    let settings: LyricsSettings
    /// Beats from the dedicated `LyricBeatFollower` (via `RenderModel`), used to
    /// snap the active line's shadow. Only the shadow reacts; text never moves.
    let lyricPulse: AnyPublisher<Float, Never>
    /// Bottom edge of the track overlay card (points, in the window's coordinate
    /// space), or 0 when the overlay is absent or not in a top corner. The top
    /// fade's clear zone extends down to here, so a past line fades out before it
    /// would collide with the overlay rather than scrolling under it.
    var topInset: CGFloat = 0
    /// Reports whether lyric TEXT is effectively on screen — real lyrics, or a
    /// no-lyrics header that has not yet scrolled off. The renderer centers the
    /// visualization when this is false (`model.lyricsShowing`), so a no-lyrics
    /// song recenters the visualization once its title has scrolled off.
    var onTextVisibleChange: (Bool) -> Void = { _ in }
    /// Bumped by `NowPlayingService` when the same song restarts. Folded into the
    /// header-only dwell task so a restart re-shows the title/performer (a no-lyrics
    /// song's header reappears, then scrolls off again), matching the track overlay.
    var replayNonce: Int = 0

    @State private var activeIndex = -1
    /// Current beat boost — snaps up on a beat, eases back to 0. Drives the
    /// active line's shadow bounce only.
    @State private var beatBoost: CGFloat = 0
    /// For a song with no lyrics, the standalone title drifts up and fades after a
    /// dwell (like a lyric scrolling off); once it has, the overlay reports text as
    /// no longer showing so the visualization recenters. Reset per song by
    /// `.task(id: songKey)`.
    @State private var headerOnlyDismissed = false
    private static let headerOnlyDwellSeconds: Double = 5
    /// Polls the model's interpolated position; the index only changes
    /// (and the view only updates) when the active line does. Static so a
    /// parent re-evaluation never rebuilds (and so restarts) the timer.
    private static let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    /// Scroll id for the song header, which sits before the first lyric
    /// (conceptually line -1). Int.min so it never collides with a row id.
    private static let headerID = Int.min

    var body: some View {
        // A container hosts the appearance transition: the lyrics block fades
        // in the first time a song's lyrics appear (display nil -> present) and
        // out when they go away, instead of popping. Per-song content updates (a
        // translation arriving, a new active line) keep `lyricsShowing` true, so
        // only appearance/disappearance animates, never a content change.
        ZStack {
        if settings.enabled, let display = lyrics.display {
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: CGFloat(settings.textSize) * 0.6) {
                            // The song announces itself as the active "lyric"
                            // before the first line (activeIndex < 0), then
                            // scrolls up and off as a past line (position -1)
                            // once the real lyrics begin.
                            LyricHeaderRow(title: display.title, artist: display.artist,
                                           phase: activeIndex < 0 ? .active : .past,
                                           distance: abs(-1 - activeIndex),
                                           settings: settings)
                                .id(Self.headerID)
                                // A no-lyrics title drifts up and fades out after its
                                // dwell, rather than staying put.
                                .opacity(headerOnlyDismissed ? 0 : 1)
                                .offset(y: headerOnlyDismissed ? -CGFloat(settings.textSize) * 1.5 : 0)
                            ForEach(display.rows) { row in
                                LyricPairRow(row: row,
                                             singleColumn: display.singleColumn,
                                             phase: phase(of: row.id),
                                             // Before the first line (-1) this counts
                                             // from just above row 0, so the opening
                                             // lines are already fading in.
                                             distance: abs(row.id - activeIndex),
                                             settings: settings,
                                             beatBoost: beatBoost)
                                    .id(row.id)
                            }
                        }
                        .frame(width: max(geo.size.width * CGFloat(settings.blockWidthFraction), 1))
                        .frame(maxWidth: .infinity)
                        // Padding above and below the rows lets the first and
                        // last lines travel all the way to the active-line
                        // anchor. It is split to match the anchor, so a higher
                        // anchor still lets row 0 reach it.
                        .padding(.top, geo.size.height * anchorY)
                        .padding(.bottom, geo.size.height * (1 - anchorY))
                    }
                    .scrollDisabled(true)
                    .onAppear { recenter(proxy) }
                    .onChange(of: activeIndex) { old, new in
                        let step = abs(new - old)
                        if (1...4).contains(step) {
                            // The active line stays at the anchor; a slow, gentle
                            // ease glides the block up between lines, so the move
                            // reads as a smooth scroll rather than a quick hop.
                            // Includes the header (position -1) easing off as the
                            // first lyric (0) takes the anchor.
                            withAnimation(.easeInOut(duration: 0.8)) {
                                proxy.scrollTo(scrollTarget(new), anchor: activeAnchor)
                            }
                        } else {
                            // Seek, track change, or first appearance: snap.
                            proxy.scrollTo(scrollTarget(new), anchor: activeAnchor)
                        }
                    }
                    // New track, a translation arriving (row heights change),
                    // a resize, or a size/width/position tweak: re-center without motion.
                    .onChange(of: display) { _, _ in recenter(proxy) }
                    .onChange(of: geo.size) { _, _ in recenter(proxy) }
                    .onChange(of: settings.textSize) { _, _ in recenter(proxy) }
                    .onChange(of: settings.blockWidthFraction) { _, _ in recenter(proxy) }
                    .onChange(of: settings.activeLinePosition) { _, _ in recenter(proxy) }
                    // Position-based top fade, independent of the per-line
                    // distance/opacity settings: a fixed vertical mask that is
                    // transparent at the very top and ramps to fully opaque by
                    // the active-line anchor, so a past line fades out as it
                    // scrolls up and is fully gone at the top edge. Opaque below
                    // the anchor, so upcoming lines keep their own fade.
                    .mask(
                        LinearGradient(
                            stops: topFadeStops(height: geo.size.height),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    )
                }
            }
            .onReceive(Self.ticker) { _ in refreshActiveIndex() }
            // A song with no lyrics shows its title, then after a dwell scrolls it
            // off (drifts up and fades). With lyrics the header scrolls off naturally
            // when the first line begins, so skip it there. Keyed on replayNonce too,
            // so restarting the song re-shows the title/performer, then it dwells and
            // scrolls off again.
            .task(id: "\(songKey)|\(replayNonce)") {
                headerOnlyDismissed = false
                guard display.rows.isEmpty else { return }
                try? await Task.sleep(nanoseconds: UInt64(Self.headerOnlyDwellSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.9)) { headerOnlyDismissed = true }
            }
            // Snap the boost up on each beat, then ease it back. The snap must
            // land in its own render pass; if the decay runs in the same
            // synchronous block SwiftUI coalesces both writes and only the final
            // (0) value renders, so nothing animates. Commit the snap now, defer
            // the decay to the next runloop tick. The 0.28 s decay eases back
            // within the follower's ~0.30 s refractory, so the shadow never pins.
            .onReceive(lyricPulse) { intensity in
                beatBoost = 0.55 + 0.45 * CGFloat(max(0, min(1, intensity)))
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.28)) { beatBoost = 0 }
                }
            }
            .onAppear { refreshActiveIndex() }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            // Per-song identity: a different song is a different view, so when
            // one song replaces another — even a fast cache-hit switch that
            // would otherwise swap rows in place — SwiftUI crossfades them (old
            // fades out while new fades in, overlapping and blended) rather than
            // cutting or flickering. Stable across a translation arriving or the
            // active line moving, so those never trigger a block crossfade.
            .id(songKey)
            // Fades in on appearance and out on removal (an abrupt track change
            // clears `display`, so the outgoing lyrics ease out rather than pop).
            .transition(.opacity)
        }
        }
        .animation(.easeInOut(duration: 0.6), value: lyricsShowing)
        // A song change crossfades the outgoing and incoming lyrics.
        .animation(.easeInOut(duration: 0.6), value: songKey)
        // Tell the renderer whether lyric text is effectively on screen, so the
        // visualization recenters once a no-lyrics title has scrolled off.
        .onChange(of: textVisible) { _, now in onTextVisibleChange(now) }
        .onAppear { onTextVisibleChange(textVisible) }
    }

    /// True while a song's lyrics are on screen. Drives the block's fade in/out;
    /// toggles only on appearance/disappearance, never on a content update.
    private var lyricsShowing: Bool { settings.enabled && lyrics.display != nil }

    /// Whether lyric TEXT is effectively on screen: real lyrics, or a no-lyrics
    /// header that has not yet scrolled off. The visualization centers when this is
    /// false, so a no-lyrics song recenters it once the title has scrolled away.
    private var textVisible: Bool {
        guard settings.enabled, let display = lyrics.display else { return false }
        if display.rows.isEmpty && headerOnlyDismissed { return false }
        return true
    }

    /// A per-song identity, stable across a translation arriving or the active
    /// line moving (both leave the source lines unchanged), changing only when
    /// the song itself changes. Drives the cross-song crossfade.
    private var songKey: String {
        guard let display = lyrics.display else { return "" }
        let first = display.rows.first?.original ?? ""
        let last = display.rows.last?.original ?? ""
        // Includes title/artist so distinct no-lyrics songs (empty rows) still
        // crossfade, and stays stable across a translation arriving.
        return "\(display.title)|\(display.artist)|\(display.rows.count)|\(first)|\(last)"
    }

    /// Vertical fraction (0 = top, 0.5 = center) where the active line is held.
    private var anchorY: CGFloat { CGFloat(min(max(settings.activeLinePosition, 0), 1)) }
    private var activeAnchor: UnitPoint { UnitPoint(x: 0.5, y: anchorY) }

    /// Stops for the position-based top fade. Fully clear from the top down to
    /// the track overlay's bottom edge (`topInset`), then ramps to opaque by the
    /// active-line anchor, so a past line scrolling up fades out and is gone
    /// before it reaches the overlay. With no top overlay (`topInset` 0) this is
    /// the original clear-at-top → opaque-by-anchor fade.
    private func topFadeStops(height: CGFloat) -> [Gradient.Stop] {
        let clearEnd = height > 0 ? min(max(topInset / height, 0), anchorY) : 0
        let opaqueAt = max(anchorY, clearEnd + 0.0001)
        return [
            Gradient.Stop(color: .clear, location: 0),
            Gradient.Stop(color: .clear, location: clearEnd),
            Gradient.Stop(color: .black, location: opaqueAt),
            Gradient.Stop(color: .black, location: 1)
        ]
    }

    private func refreshActiveIndex() {
        let index = lyrics.activeIndex(atMs: ProcessInfo.processInfo.systemUptime * 1000)
        if index != activeIndex { activeIndex = index }
    }

    /// Re-anchors after the pending layout pass, so new row heights count.
    private func recenter(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            let index = lyrics.activeIndex(atMs: ProcessInfo.processInfo.systemUptime * 1000)
            proxy.scrollTo(scrollTarget(index), anchor: activeAnchor)
        }
    }

    /// The scroll id to anchor for an active index: the song header while still
    /// in the intro (index < 0), otherwise the active lyric row.
    private func scrollTarget(_ index: Int) -> Int { index < 0 ? Self.headerID : index }

    private func phase(of index: Int) -> LyricRowPhase {
        if activeIndex < 0 || index > activeIndex { return .upcoming }
        return index == activeIndex ? .active : .past
    }
}

/// One lyric pair. Its own view so later features (click, hover, edit)
/// can attach to a row without restructuring the overlay.
private struct LyricPairRow: View {
    let row: LyricRow
    let singleColumn: Bool
    let phase: LyricRowPhase
    /// Lines away from the active line; drives the distance fade.
    let distance: Int
    let settings: LyricsSettings
    /// Beat-driven shadow boost (0 when idle); applied to the active line only.
    let beatBoost: CGFloat

    private var opacity: Double {
        Double(settings.opacity(for: phase, distance: distance))
    }

    /// Whether this row has a non-empty translation to show. Drives the
    /// translation column's fade-in when the async translation arrives.
    private var hasTranslation: Bool {
        !(row.translation ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    // Beat-driven shadow bounce, active line only, scaled by pulse * strength.
    // Only the shadow (blur / Y-offset / opacity) moves — never the text.
    private var bounceActive: Bool { phase == .active && settings.beatBounceMode != .off }
    private var liftOn: Bool { bounceActive && (settings.beatBounceMode == .lift || settings.beatBounceMode == .both) }
    private var glowOn: Bool { bounceActive && (settings.beatBounceMode == .glow || settings.beatBounceMode == .both) }
    private var beatAmount: CGFloat { beatBoost * CGFloat(settings.beatBounceStrength) }
    private var shadowRadiusNow: CGFloat {
        CGFloat(settings.shadowRadius) + (glowOn ? beatAmount * 14 : 0)
    }
    private var shadowOffsetYNow: CGFloat {
        CGFloat(settings.shadowOffsetY) + (liftOn ? beatAmount * 10 : 0)
    }
    private var shadowOpacityNow: Double {
        min(1, Double(settings.shadowOpacity) + (bounceActive ? Double(beatAmount) * 0.35 : 0))
    }

    var body: some View {
        Group {
            if singleColumn {
                cell(originalText, alignment: .center, textAlignment: .center)
            } else {
                // Top-aligned so a wrapped cell never shifts its partner.
                HStack(alignment: .top, spacing: 24) {
                    cell(originalText, alignment: .trailing, textAlignment: .trailing)
                    // The translation arrives asynchronously (one Gemini call per
                    // song), so the second column swaps from empty to populated
                    // mid-scroll. Fade it in rather than pop. A translation
                    // present from the first render (cache hit) starts at full
                    // opacity, so only the async arrival animates.
                    cell(row.translation ?? "", alignment: .leading, textAlignment: .leading)
                        .opacity(hasTranslation ? 1 : 0)
                        .animation(.easeInOut(duration: 0.6), value: hasTranslation)
                }
            }
        }
        .opacity(opacity)
        // Matches the scroll duration, so a line fades in or out as it
        // travels toward or away from the middle.
        .animation(.easeInOut(duration: 0.45), value: opacity)
        .animation(.easeInOut(duration: 0.2), value: phase)
    }

    /// An instrumental gap shows a music note, as the web app does.
    private var originalText: String {
        row.original.trimmingCharacters(in: .whitespaces).isEmpty ? "\u{266A}" : row.original
    }

    private func cell(_ text: String, alignment: Alignment, textAlignment: TextAlignment) -> some View {
        Text(text)
            // Color only, never weight or size: a heavier active line would
            // change glyph widths and jitter the column alignment.
            .font(.system(size: CGFloat(settings.textSize), weight: .bold))
            .foregroundStyle(Color(phase == .active ? settings.activeColor : settings.otherColor))
            .multilineTextAlignment(textAlignment)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: alignment)
            .shadow(color: settings.shadowEnabled
                        ? Color(settings.shadowColor).opacity(shadowOpacityNow)
                        : .clear,
                    radius: shadowRadiusNow,
                    x: CGFloat(settings.shadowOffsetX),
                    y: shadowOffsetYNow)
    }
}

/// The song's title and performer, shown as the active "lyric" before the first
/// line and scrolling off as a past line once the lyrics begin. Styled to match
/// the lyric lines (same color / shadow / distance-opacity rules) so it reads as
/// part of the scroll, with the performer a smaller, dimmer second line.
private struct LyricHeaderRow: View {
    let title: String
    let artist: String
    let phase: LyricRowPhase
    /// Lines away from the active line; drives the distance fade, same as a row.
    let distance: Int
    let settings: LyricsSettings

    private var opacity: Double { Double(settings.opacity(for: phase, distance: distance)) }

    var body: some View {
        VStack(spacing: CGFloat(settings.textSize) * 0.15) {
            Text(title)
                // Distinct from the lyric lines by size + weight + italics (a
                // work title) + full opacity, not hue: the "other lines" color
                // at full strength, a little larger and bold. A legible light
                // title rather than the dark shadow color, which is invisible
                // on the dark visualizer.
                .font(.system(size: CGFloat(settings.textSize) * 1.15, weight: .bold).italic())
                .foregroundStyle(Color(settings.otherColor))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !artist.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(artist)
                    .font(.system(size: CGFloat(settings.textSize) * 0.7, weight: .semibold))
                    .foregroundStyle(Color(settings.otherColor).opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        // The lyric lines' own drop shadow, for legibility on any background.
        .shadow(color: settings.shadowEnabled
                    ? Color(settings.shadowColor).opacity(Double(settings.shadowOpacity))
                    : .clear,
                radius: CGFloat(settings.shadowRadius),
                x: CGFloat(settings.shadowOffsetX),
                y: CGFloat(settings.shadowOffsetY))
        .opacity(opacity)
        .animation(.easeInOut(duration: 0.45), value: opacity)
        .animation(.easeInOut(duration: 0.2), value: phase)
    }
}
