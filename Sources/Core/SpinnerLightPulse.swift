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

/// Hand-over of beat pulses from the analysis queue to the render path: keeps the strongest pulse posted since the last
/// drain, and drops a pulse older than `maxAge` (so a beat from before the Spinner was on screen never fires late).
/// Thread-safe (a lock; the dsp queue posts, the draw loop drains).
public final class SpinnerLightInbox {
    public static let shared = SpinnerLightInbox()
    /// Pulses older than this many seconds are discarded on drain.
    public static let maxAge: TimeInterval = 0.2

    private let lock = NSLock()
    private var strength: Float = 0
    private var postedAt: TimeInterval = 0

    public init() {}

    /// Records a beat of `strength` (0...1; NaN ignored) at `time` (a monotonic clock shared with `drain`).
    public func post(_ value: Float, at time: TimeInterval) {
        if value.isNaN { return }
        let clamped: Float = min(max(value, 0), 1)
        lock.lock()
        if clamped > strength || time - postedAt > Self.maxAge {
            strength = clamped
            postedAt = time
        }
        lock.unlock()
    }

    /// The strongest pulse since the last drain (0 when none or stale); clears it.
    public func drain(now: TimeInterval) -> Float {
        lock.lock()
        let value: Float = strength
        let age: TimeInterval = now - postedAt
        strength = 0
        lock.unlock()
        if age > Self.maxAge { return 0 }
        return value
    }
}

/// The Tri-wing's light level L (0...1): a multiplier on every edge-light emissive (filament, glass, slot glow, lip line,
/// pad tint, smeared glow rings), on top of Glow brightness. Pure; driven once per frame with wall-clock `dt`.
///
/// - `beatLights` off: L = 1.
/// - On: L rests at `restingGlow`; a beat of strength s lifts it at once to rest + (peak - rest) * max(0.4, s), where
///   peak = max(beatGlow, rest), and it falls back over `decaySeconds`. A weaker beat never lowers a level still decaying.
/// - No track playing for `idleDelaySeconds`: L eases up to 1 over `easeSeconds`; playback resuming eases it back to rest.
public struct SpinnerLightPulse {
    public static let decaySeconds: Double = 0.25
    public static let softBeatFloor: Float = 0.4
    public static let idleDelaySeconds: Double = 2.0
    public static let easeSeconds: Double = 1.0

    /// Start fraction of the current pulse (0...1 of the rest-to-peak span) and its age.
    private var amplitude: Float = 0
    private var age: Double = 0
    private var idleTimer: Double = 0
    /// 0 = music mode (rest + pulse), 1 = idle (level 1).
    private var idleBlend: Double = 0
    public private(set) var level: Float = 1

    public init() {}

    private var pulseFraction: Float {
        if amplitude <= 0 { return 0 }
        let remaining: Double = 1 - age / Self.decaySeconds
        if remaining <= 0 { return 0 }
        let shaped: Double = remaining * remaining
        return amplitude * Float(shaped)
    }

    @discardableResult
    public mutating func update(dt rawDt: Double, beatStrength rawBeat: Float, trackPlaying: Bool,
                                settings: SpinnerSettings) -> Float {
        if !settings.beatLights {
            amplitude = 0
            age = 0
            idleTimer = 0
            idleBlend = 0
            level = 1
            return 1
        }
        let dt: Double = (rawDt.isNaN || rawDt < 0) ? 0 : min(rawDt, 1)
        let rest: Float = min(max(Float(settings.restingGlow), 0), 1)
        let beatPeak: Float = min(max(Float(settings.beatGlow), 0), 1)
        let peak: Float = max(beatPeak, rest)
        let span: Float = peak - rest

        // Age the running pulse first, then apply a new beat (so a beat reaches its full height this frame).
        age += dt
        if trackPlaying {
            idleTimer = 0
            idleBlend = max(0, idleBlend - dt / Self.easeSeconds)
            let beat: Float = rawBeat.isNaN ? 0 : min(max(rawBeat, 0), 1)
            if beat > 0 {
                let target: Float = max(Self.softBeatFloor, beat)
                if target >= pulseFraction {
                    amplitude = target
                    age = 0
                }
            }
        } else {
            amplitude = 0
            idleTimer += dt
            if idleTimer >= Self.idleDelaySeconds {
                idleBlend = min(1, idleBlend + dt / Self.easeSeconds)
            }
        }
        let music: Float = rest + span * pulseFraction
        let blend: Float = Float(idleBlend)
        let value: Float = music + (1 - music) * blend
        level = min(max(value, 0), 1)
        return level
    }
}
