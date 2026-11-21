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

import Foundation

/// Drop a non-finite value (NaN / ±inf) to a safe fallback so it can't poison
/// the timer arithmetic. Mirrors the file-private `finiteOr` pattern used by the
/// visualizer read sites (e.g. JoyPlotVisualizer).
private func finiteOr(_ v: Double, _ fallback: Double) -> Double { v.isFinite ? v : fallback }

/// One frame of cycle-engine output: which palette to show, an optional palette
/// to crossfade toward, the fade mix factor, and a one-shot `committedName` that
/// is non-nil only on the single frame a fade completes (the caller writes that
/// name to every style's profile).
public struct PaletteCycleOutput: Equatable {
    public var currentName: String
    public var nextName: String?
    public var mix: Double           // 0 = show current, 1 = fully next
    public var committedName: String?

    public init(currentName: String, nextName: String?, mix: Double, committedName: String?) {
        self.currentName = currentName
        self.nextName = nextName
        self.mix = mix
        self.committedName = committedName
    }
}

/// Pure, deterministic palette auto-cycle state machine. Owns a shuffle deck,
/// an interval countdown, and the crossfade progress. It has **no timers and no
/// threads** — the caller advances it once per frame on the main/draw path with
/// the frame `dt`. The RNG is injected so the shuffle is reproducible in tests.
///
/// Value preservation: when `enabled == false` the output is a pure passthrough
/// of `currentPaletteName` (mix 0, no next), so a disabled cycle is a true no-op.
public final class PaletteCycleEngine {
    /// Remaining names to draw in the current deck (shuffled order).
    private var deck: [String] = []
    /// The palette the engine believes is currently shown. `nil` until the first
    /// `advance`. Drives manual-change detection (when the external palette name
    /// diverges from this) and the no-self-fade / no-seam-repeat draw rule.
    private var trackedCurrent: String?
    /// Countdown accumulator toward the interval (seconds).
    private var elapsed: Double = 0
    /// Fade accumulator (seconds) while crossfading; `nil` when not fading.
    private var fadeElapsed: Double?
    /// The palette being faded toward; `nil` when not fading.
    private var nextName: String?

    public init() {}

    public func advance(dt: Double,
                        enabled: Bool,
                        interval: Double,
                        fadeDuration: Double,
                        currentPaletteName: String,
                        availableNames: [String],
                        rng: inout some RandomNumberGenerator) -> PaletteCycleOutput {
        // Sanitize timing inputs. dt is only floored at 0 (and de-NaN'd): the
        // caller may legitimately pass a large dt (e.g. a 10s test step), so no
        // upper clamp — an upper clamp would make the fade-timing contract
        // untestable. interval/fade are kept positive and finite.
        let safeDt = max(finiteOr(dt, 0), 0)
        let safeInterval = max(finiteOr(interval, 60), 0.1)
        let safeFade = max(finiteOr(fadeDuration, 1.5), 0.01)
        let effFade = min(safeFade, safeInterval)

        // Disabled → reset countdown/fade and pass the current palette through.
        if !enabled {
            elapsed = 0
            fadeElapsed = nil
            nextName = nil
            trackedCurrent = currentPaletteName
            return PaletteCycleOutput(currentName: currentPaletteName, nextName: nil, mix: 0, committedName: nil)
        }

        // First frame after enable: anchor to the current palette.
        if trackedCurrent == nil {
            trackedCurrent = currentPaletteName
        }

        // Manual-change detection: the externally-set palette diverged from our
        // anchor. The manual pick wins even mid-fade — cancel the fade, snap to
        // it, restart the countdown, and drop it from the deck so it isn't the
        // immediate next draw.
        if let tc = trackedCurrent, tc != currentPaletteName {
            trackedCurrent = currentPaletteName
            elapsed = 0
            fadeElapsed = nil
            nextName = nil
            deck.removeAll { $0 == currentPaletteName }
            return PaletteCycleOutput(currentName: currentPaletteName, nextName: nil, mix: 0, committedName: nil)
        }

        // Mid-fade: advance the crossfade. Commit exactly once when it completes.
        if fadeElapsed != nil {
            fadeElapsed! += safeDt
            let mix = min(fadeElapsed! / effFade, 1)
            if mix >= 1 {
                let committed = nextName ?? currentPaletteName
                trackedCurrent = committed
                nextName = nil
                fadeElapsed = nil
                elapsed = 0
                return PaletteCycleOutput(currentName: committed, nextName: nil, mix: 1, committedName: committed)
            }
            return PaletteCycleOutput(currentName: trackedCurrent ?? currentPaletteName,
                                      nextName: nextName, mix: mix, committedName: nil)
        }

        // Counting down toward the next advance.
        elapsed += safeDt
        if elapsed >= safeInterval {
            let anchor = trackedCurrent ?? currentPaletteName
            // Never self-fade: when no available palette differs from the
            // current one (empty list, a single name, or all names == current),
            // do NOT start a fade. Reset the countdown and pass through until an
            // alternative becomes available. This is the authoritative guard;
            // `drawNext` keeps its own defensive check.
            guard availableNames.contains(where: { $0 != anchor }) else {
                elapsed = 0
                return PaletteCycleOutput(currentName: anchor, nextName: nil, mix: 0, committedName: nil)
            }
            let picked = drawNext(availableNames: availableNames, rng: &rng)
            nextName = picked
            // Carry the interval overshoot into the fade so timing is
            // frame-rate-independent: a late frame doesn't restart the fade at 0.
            let carried = max(0, elapsed - safeInterval)
            let mix = min(carried / effFade, 1)
            if mix >= 1 {
                // A single dt skipped the entire interval + fade — commit at once.
                trackedCurrent = picked
                nextName = nil
                fadeElapsed = nil
                elapsed = 0
                return PaletteCycleOutput(currentName: picked, nextName: nil, mix: 1, committedName: picked)
            }
            fadeElapsed = carried
            return PaletteCycleOutput(currentName: anchor, nextName: picked, mix: mix, committedName: nil)
        }
        return PaletteCycleOutput(currentName: trackedCurrent ?? currentPaletteName,
                                  nextName: nil, mix: 0, committedName: nil)
    }

    /// Draw the next palette from the shuffle deck. Refills + reshuffles (via the
    /// injected RNG) when empty, and never returns the current palette — which
    /// both avoids a pointless self-fade and forbids a same-name seam between
    /// decks (the previous deck's last commit == `trackedCurrent` at refill).
    private func drawNext(availableNames: [String], rng: inout some RandomNumberGenerator) -> String {
        let hasAlternative = availableNames.contains { $0 != trackedCurrent }
        if deck.isEmpty { deck = availableNames.shuffled(using: &rng) }
        if hasAlternative {
            var guardCount = 0
            let cap = availableNames.count * 2 + 4
            while let first = deck.first, first == trackedCurrent, guardCount < cap {
                deck.removeFirst()
                if deck.isEmpty { deck = availableNames.shuffled(using: &rng) }
                guardCount += 1
            }
        }
        guard let picked = deck.first else { return trackedCurrent ?? (availableNames.first ?? "") }
        deck.removeFirst()
        return picked
    }
}
