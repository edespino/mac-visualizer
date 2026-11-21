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
import MacVisualizerCore

/// A non-interactive overlay showing the current track + artwork in a chosen corner.
///
/// It runs its own opacity lifecycle, independent of the lyrics layer, so the two
/// never fight even where they overlap: on a new track it **blooms** from zero up
/// to full opacity, holds a moment, then **settles** down to the configured overlay
/// opacity. On a song switch the current card fades out and the next blooms in at
/// full, then settles — all gradual. `displayedTrack`/`displayedArtwork` hold the
/// shown content across the fade so the card never pops to the new song.
struct TrackOverlay: View {
    let track: TrackInfo?
    let artwork: NSImage?
    let settings: VisualizerSettings
    /// Bundle id of the player the current track is from (Spotify / Music), or
    /// nil when unknown. A tap on the card brings that app to the foreground.
    var sourceBundleID: String? = nil
    /// Bumped by `NowPlayingService` when the same song restarts from the start.
    /// Folded into the fade `.task` id so a restart re-runs `runFade` (re-bloom)
    /// even though the track identity is unchanged.
    var replayNonce: Int = 0

    /// The track/artwork currently drawn — held across fades so the content swaps
    /// only while the card is invisible, never mid-view.
    @State private var displayedTrack: TrackInfo?
    @State private var displayedArtwork: NSImage?
    /// Animated opacity: 0 → 1 (bloom) → `overlayOpacity` (settle).
    @State private var level: Double = 0
    /// True once the bloom has settled, so a live opacity-slider change is honored.
    @State private var settled = false
    /// True only during the destructive dip + content swap of a song switch (and
    /// the pause/clear fade). Hover opacity is blocked then so a hover can't fight
    /// the swap — but hover IS honored during bloom/hold/settle, so catching a card
    /// mid-settle still raises it to full instead of leaving it grown-but-dimmed.
    @State private var transitioning = false
    /// The latest cover + the track it belongs to, in a reference type (see
    /// ArtworkStash) so the running `runFade` task reads it LIVE while it waits
    /// for a new song's cover. A `@State` value or `let` input is a stale snapshot
    /// inside the escaping task; a class instance is shared storage.
    @State private var stash = ArtworkStash()
    /// True while the pointer is over the card. While hovering, the settle target
    /// is full opacity (hover-to-reveal); on exit it eases back to the configured
    /// opacity. Opacity is always driven by `level`, so a song switch still fades
    /// even while hovering.
    @State private var hovering = false
    /// Hover progress: 0 at rest, 1 while hovered. Animated on its own symmetric
    /// timing, independent of `level`, so the grow responds immediately (even before
    /// the bloom has settled) and grows/shrinks at the same speed. The displayed
    /// scale is `1 + hoverProgress * (effectiveScale - 1)`.
    @State private var hoverProgress: Double = 0
    /// The card's base (unscaled) width, measured so the hover grow can be clamped
    /// to keep the enlarged card inside the window.
    @State private var cardWidth: CGFloat = 0
    /// How much the card grows on hover, to read the art/title/performer — capped so
    /// the grown card never spills past the opposite window edge. Tunable.
    private let hoverScale: Double = 2.5

    /// Identity of the track to show, or "" when there is nothing to show (no
    /// track, paused/stopped, or the overlay disabled). Drives the fade `.task`.
    private func key(_ t: TrackInfo?) -> String {
        guard settings.overlayEnabled, let t, !t.isEmpty else { return "" }
        return "\(t.title ?? "")|\(t.artist ?? "")|\(t.album ?? "")"
    }

    var body: some View {
      GeometryReader { geo in
        // Cap the hover grow so the enlarged card stays inside the window. The card
        // is pinned `gutter` from its corner and grows toward the far edge, so its
        // far edge sits at gutter + cardWidth·scale and must stay within
        // (containerWidth − gutter): scale ≤ (containerWidth − 2·gutter) / cardWidth.
        let gutter: CGFloat = 20
        let maxScale: Double = cardWidth > 0
            ? max(1.0, Double((geo.size.width - 2 * gutter) / cardWidth))
            : hoverScale
        let effScale = min(hoverScale, maxScale)
        let shownScale = 1 + hoverProgress * (effScale - 1)
        ZStack {
            if let shown = displayedTrack, !shown.isEmpty {
                // Crisp hover-grow: `scaleEffect` enlarges whatever was rasterized at
                // the view's own size, so scaling a rest-size card UP blurs its text
                // and edges. Instead the VISIBLE card is built at the fully grown
                // size (every metric and font × hoverScale) and scaled DOWN to rest,
                // so it is never upscaled. An invisible rest-size copy owns layout
                // and measurement (scaleEffect does not affect layout), and the big
                // card rides on it as a corner-aligned overlay.
                let os = CGFloat(hoverScale)
                card(shown, artwork: displayedArtwork, metric: 1)
                    .hidden()
                    // Report the card's bottom edge (lyrics upper limit) and its base
                    // width (to clamp the hover grow). Measured at rest size.
                    .background(
                        GeometryReader { g in
                            Color.clear
                                .preference(
                                    key: TrackOverlayBottomKey.self,
                                    value: g.frame(in: .named(TrackOverlayBottomKey.space)).maxY)
                                .preference(key: TrackOverlayWidthKey.self, value: g.size.width)
                        }
                    )
                    .overlay(alignment: alignment(settings.overlayPosition)) {
                        card(shown, artwork: displayedArtwork, metric: os)
                            // Match the rest card's (possibly truncated) width.
                            .frame(maxWidth: cardWidth > 0 ? cardWidth * os : nil)
                            .fixedSize()
                            // Grow from the overlay's own corner so the enlarged card
                            // expands into the window; `shownScale` is clamped to the
                            // window width. At rest this is 1/os (a downscale).
                            .scaleEffect(shownScale / os,
                                         anchor: scaleAnchor(settings.overlayPosition))
                            .opacity(level)
                            // Drop shadow to lift the card off the visualization,
                            // prominent like the window's drop shadow. Applied after
                            // `.opacity` with its strength tied to `level`, so it dims
                            // (and vanishes) exactly in step with the card.
                            .shadow(color: .black.opacity(0.7 * level), radius: 16, x: 0, y: 6)
                            // Hover-to-reveal: the fade itself is driven by
                            // onChange(of: hovering) below, so a song switch still
                            // animates while the pointer rests on the card.
                            .onHover { inside in hovering = inside }
                            // Click the card to bring the source player (Spotify /
                            // Music) to the foreground. Hover and tap need hit
                            // testing, so the card captures the pointer over its
                            // corner; the surrounding frame stays empty and lets
                            // events through to the visualization behind.
                            .onTapGesture { activateSourceApp() }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: alignment(settings.overlayPosition))
            }
        }
        // Re-run whenever the track to show changes (new song, pause/stop, or the
        // overlay being toggled). `.task(id:)` cancels the in-flight fade on a
        // fast switch, so rapid song changes don't stack animations.
        // Keyed on the track AND the replay nonce, so a song switch OR a restart of
        // the same song (nonce bump) re-runs the fade and re-blooms the card.
        .task(id: "\(key(track))|\(replayNonce)") { await runFade() }
        // Spotify artwork arrives asynchronously, after the track; keep the shown
        // art current once it belongs to the track on screen.
        .onChange(of: artwork) { newArtwork in
            stash.image = newArtwork
            stash.key = key(track)
            // Only ever push a REAL cover onto the visible card, and only when that
            // card already shows the current song. NEVER push nil: on a switch the
            // model clears `artwork` in the same update that changes `track`, and
            // SwiftUI can run this closure while `track` still reads as the OLD
            // (displayed) song — so a nil push here strips the art off the old card
            // mid-fade and it goes text-only. Clearing/replacing art on a song
            // change is the runFade swap's job, not this handler's.
            if newArtwork != nil && key(displayedTrack) == key(track) { displayedArtwork = newArtwork }
        }
        // Honor a live overlay-opacity change once settled — but not while hovering
        // (the card is held at full then).
        .onChange(of: settings.overlayOpacity) { newOpacity in
            if settled && !hovering { withAnimation(.easeInOut(duration: 0.3)) { level = Double(newOpacity) } }
        }
        // Hover-to-reveal: once settled, ease to full while hovered and back to the
        // configured opacity on exit (same settle fade). During a transition (not
        // settled) the switch animation owns `level`, so hover waits for it.
        .onChange(of: hovering) { nowHovering in
            // Size: always responsive (even during bloom/settle — it never fights
            // runFade, which only drives `level`), symmetric grow-in / shrink-out.
            // The actual scale (clamped to the window width) is derived in `body`.
            withAnimation(.easeInOut(duration: 0.65)) {
                hoverProgress = nowHovering ? 1 : 0
            }
            // Opacity: allowed whenever a card is shown and not mid-switch — so a
            // hover during the settle fade redirects it to full instead of leaving
            // it dimmed. Blocked only during the dip/swap (transitioning).
            guard displayedTrack != nil, !transitioning else { return }
            withAnimation(.easeInOut(duration: nowHovering ? 0.6 : 2.5)) {
                level = nowHovering ? 1.0 : Double(settings.overlayOpacity)
            }
        }
        .onPreferenceChange(TrackOverlayWidthKey.self) { cardWidth = $0 }
      }
    }

    /// On a new song: dip the old card out at once (so it never lingers) while
    /// waiting, bounded, for the new cover; once the dip is done and the cover is
    /// ready, swap at the invisible trough, bloom the new card to full, and settle
    /// to the configured opacity. On pause/stop/disable: fade out and clear. Guarded
    /// so a cancelled run (a faster switch arrived) writes nothing further.
    @MainActor
    private func runFade() async {
        let newKey = key(track)
        settled = false

        // Pause / stop / overlay off: fade the current card out and clear.
        guard !newKey.isEmpty else {
            transitioning = true   // fading out / clearing; hover must not resurrect it
            if displayedTrack != nil {
                withAnimation(.easeOut(duration: 0.35)) { level = 0 }
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { return }
            }
            displayedTrack = nil
            displayedArtwork = nil
            return
        }

        // Re-reveal path: the SAME song is already on screen (a restart / replay —
        // the task re-fired on a replay-nonce bump, not a track change). Don't dip
        // and don't swap content; just bring the existing card back to full, hold,
        // and settle. It simply returns to view, with no new-song transition.
        if let shown = displayedTrack, key(shown) == newKey {
            transitioning = false   // same card, just re-raise — hover allowed throughout
            await bloomHoldSettle()
            return
        }

        // Dip the old card out IMMEDIATELY so it never lingers on a switch, and let
        // the cover wait below overlap that dip. Without this the old card sat at
        // full opacity for the whole cover wait (up to ~1 s) before fading — the
        // "previous card shown after the song already changed" symptom, during which
        // its low-contrast art blended into the background and it read as text-only.
        transitioning = true   // dip + swap: block hover so it can't fight the switch
        let dipStart = Date()
        let hadCard = displayedTrack != nil
        if hadCard {
            withAnimation(.easeOut(duration: 0.3)) { level = 0 }
        }

        // Wait (bounded) for the new cover WHILE the old card dips. Music's embedded
        // art is already in `artwork` (no wait); Spotify's is fetched (~0.1–0.3 s)
        // and lands in the live stash, read here via a reference type so the value
        // is current, not a snapshot. Bounded, so a track with genuinely no art
        // still appears. Because the wait overlaps the dip, the new card still
        // blooms complete — never title-only-then-pop — with no stuck old card.
        if artwork == nil {
            let deadline = Date().addingTimeInterval(1.0)
            while !(stash.key == newKey && stash.image != nil) && Date() < deadline {
                try? await Task.sleep(nanoseconds: 40_000_000)
                if Task.isCancelled { return }
            }
        }
        let newArtwork = (stash.key == newKey && stash.image != nil) ? stash.image : artwork

        // Make sure the dip has fully finished before swapping, so the old content
        // is never under the new at the trough (the wait may have been shorter than
        // the dip). Then swap at the invisible trough and bloom the new card in.
        if hadCard {
            let remaining = 0.3 - Date().timeIntervalSince(dipStart)
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                if Task.isCancelled { return }
            }
        }
        displayedTrack = track
        displayedArtwork = newArtwork
        transitioning = false   // swapped; bloom/hold/settle — hover allowed again
        await bloomHoldSettle()
    }

    /// Bloom to full, hold, then settle to the configured opacity (or stay full
    /// while hovered). Shared by a fresh switch and a same-song re-reveal.
    @MainActor
    private func bloomHoldSettle() async {
        withAnimation(.easeOut(duration: 0.5)) { level = 1.0 }
        try? await Task.sleep(nanoseconds: 4_500_000_000)   // 0.5 bloom + 4.0 s hold at full
        if Task.isCancelled { return }
        withAnimation(.easeInOut(duration: 2.5)) { level = hovering ? 1.0 : Double(settings.overlayOpacity) }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        if Task.isCancelled { return }
        settled = true
    }

    /// Brings the source player (Spotify / Music) to the foreground. No-op when
    /// the source is unknown or the app is not installed.
    ///
    /// Activates the already-running player process directly, which never touches
    /// the app bundle. The old `NSWorkspace.open(appURL)` tripped macOS App
    /// Management ("MacVisualizer was prevented from modifying apps") — that
    /// deprecated file-open call, handed an `.app` URL, is treated as opening the
    /// bundle rather than launching the app. Launch is only a fallback for the rare
    /// case where the player isn't running, via the proper app-launch API.
    private func activateSourceApp() {
        guard let bundleID = sourceBundleID else { return }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            running.activate()
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
    }

    /// The card, with every metric and font multiplied by `metric`. `metric: 1` is
    /// the rest-size card (used invisibly for layout); `metric: hoverScale` is the
    /// visible one, built at the fully grown size and scaled down by the caller.
    private func card(_ track: TrackInfo, artwork: NSImage?, metric m: CGFloat) -> some View {
        HStack(spacing: 10 * m) {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 48 * m, height: 48 * m)
                    .clipShape(RoundedRectangle(cornerRadius: 4 * m))
            }
            VStack(alignment: .leading, spacing: 2 * m) {
                Text(track.title ?? "")
                    .font(scaledFont(.headline, m))
                    .lineLimit(1)
                let performer = track.artist ?? ""
                if !performer.isEmpty {
                    Text(performer)
                        .font(scaledFont(.subheadline, m))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(10 * m)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8 * m))
        .foregroundStyle(.white)
    }

    /// The system text style's font at `m` times its point size (same face/weight),
    /// so the grown card's text is real large type, not a magnified small raster.
    private func scaledFont(_ style: NSFont.TextStyle, _ m: CGFloat) -> Font {
        let base = NSFont.preferredFont(forTextStyle: style)
        return Font(NSFont(descriptor: base.fontDescriptor, size: base.pointSize * m) ?? base)
    }

    private func alignment(_ corner: OverlayCorner) -> Alignment {
        switch corner {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }

    /// The scale anchor matching the overlay's corner, so a hover-grow expands the
    /// card away from its pinned corner (into the window) instead of off-screen.
    private func scaleAnchor(_ corner: OverlayCorner) -> UnitPoint {
        switch corner {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }
}

/// The bottom edge (Y, in the ContentView coordinate space named `space`) of the
/// track overlay card, published up so the lyrics layer can treat it as its upper
/// limit and fade lyrics out before they reach it. `max` so a stale or empty
/// contribution can never pull the reported edge up.
struct TrackOverlayBottomKey: PreferenceKey {
    static let space = "contentOverlaySpace"
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The track overlay card's base (unscaled) width, used to clamp the hover grow so
/// the enlarged card never spills past the opposite window edge.
struct TrackOverlayWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Holds the latest cover and the track it belongs to. A reference type on
/// purpose: the `runFade` task captures the view struct by value, so a `@State`
/// value or a `let` input reads as a frozen snapshot inside it — but a class
/// instance is shared storage, so the wait loop sees the cover the instant the
/// `onChange(of: artwork)` handler writes it.
private final class ArtworkStash {
    var image: NSImage?
    var key: String = ""
}
