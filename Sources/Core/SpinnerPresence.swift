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

// Keeps the scene visible while the spinner is in use, and the pure
// mappings for the bearing hum.

/// Tracks when the spinner was last in use. Pure; the caller supplies `now`.
public struct SpinnerPresence {
    public private(set) var lastActive: TimeInterval?
    public init() {}

    /// Call once per frame with the current speed and whether a scroll impulse arrived.
    public mutating func update(now: TimeInterval, speed: Double, impulse: Bool) {
        if impulse || abs(speed) > SpinnerTuning.presenceSpeedThreshold { lastActive = now }
    }

    /// True while spinning, and for `presenceLingerSeconds` after it last was (or an impulse arrived).
    public func isHeld(now: TimeInterval) -> Bool {
        guard let last = lastActive else { return false }
        return now - last < SpinnerTuning.presenceLingerSeconds
    }
}

/// Pure decisions and mappings for the bearing hum (the audio engine lives in Services).
public enum SpinnerHum {
    private static func norm(_ speed: Double) -> Double {
        min(abs(speed) / max(SpinnerTuning.maxSpeed, 1e-6), 1)
    }

    /// Linear output gain: 0 at rest, `humMaxGain * norm^humGainExponent` (gentle at low speed), `humMaxGain` at `maxSpeed`.
    public static func gain(speed: Double) -> Double {
        SpinnerTuning.humMaxGain * pow(norm(speed), SpinnerTuning.humGainExponent)
    }

    /// Band-pass center for the bearing rush: 300 Hz at rest to 2.2 kHz at `maxSpeed`.
    public static func noiseCenterHz(speed: Double) -> Double {
        let span: Double = 2200 - 300
        let n: Double = norm(speed)
        return 300 + span * n
    }

    /// Fundamental of the two sine partials: 3 Hz per rad/s.
    public static func fundamentalHz(speed: Double) -> Double { 3 * abs(speed) }
}

/// Continuous duck factor (1 = hum at full, 0 = fully ducked) that crossfades the hum with the music.
/// Pure; fed once per frame. Uses the same running-peak self-normalization as `SpinnerMusicDrive`.
/// Strict gate for the bearing hum: the hum is heard only when there is no music activity at all.
///
/// "Music activity" is any of: a player reports a track playing, captured player audio above
/// `IdleFadeTracker.levelEpsilon`, or demo mode. The hum is permitted only after activity has been absent
/// CONTINUOUSLY for `SpinnerTuning.humQuietSeconds`, so the gap or crossfade between songs, a quiet passage and a
/// track's fade-out never let it back in. Any activity resets that timer. The output is a smooth 0...1 gain: it
/// falls to exactly 0 over `humFadeOutSeconds` while activity is present (never partial values during music), and
/// rises over `humFadeInSeconds` once permitted. A new gate counts as "activity just seen" (the timer starts at 0),
/// so the hum cannot blurt out before the first now-playing poll and capture start have reported.
public struct SpinnerHumGate {
    /// Current gain, 0...1.
    public private(set) var gain: Double = 0
    /// Seconds of continuous silence so far (0 at launch and whenever activity is seen).
    public private(set) var quietSeconds: Double = 0

    public init() {}

    /// True when a track is reported playing, the capture carries audio above the idle epsilon, or demo mode is on.
    public static func isMusicActivity(trackPlaying: Bool, sample: IdleAudioSample) -> Bool {
        if trackPlaying { return true }
        switch sample {
        case .demo:
            return true
        case .noCapture:
            return false
        case .level(let l):
            return l > IdleFadeTracker.levelEpsilon
        }
    }

    /// Advances by `dt` seconds with this frame's inputs and returns the gain.
    @discardableResult
    public mutating func update(trackPlaying: Bool, sample: IdleAudioSample, dt: Double) -> Double {
        let step: Double = min(max(dt, 0), 0.25)
        let active: Bool = Self.isMusicActivity(trackPlaying: trackPlaying, sample: sample)
        if active {
            quietSeconds = 0
        } else {
            quietSeconds += step
        }
        let permitted: Bool = !active && quietSeconds >= SpinnerTuning.humQuietSeconds
        if permitted {
            let rise: Double = step / max(SpinnerTuning.humFadeInSeconds, 1e-6)
            gain = min(gain + rise, 1)
        } else {
            let fall: Double = step / max(SpinnerTuning.humFadeOutSeconds, 1e-6)
            gain = max(gain - fall, 0)
        }
        return gain
    }
}
