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

// Music-as-force for the spinner. Pure; fed once per frame.

public struct SpinnerMusicDrive {
    public struct Output: Equatable {
        public var frictionScale: Double
        public var impulse: Double
        public var pulse: Float
        public init(frictionScale: Double, impulse: Double, pulse: Float) {
            self.frictionScale = frictionScale
            self.impulse = impulse
            self.pulse = pulse
        }
    }

    /// Self-normalized 0...1 loudness.
    public private(set) var level: Double = 0
    private var runningPeak: Double = 1e-4
    private var follower = LyricBeatFollower()
    private var clock: Double = 0

    /// Half-life (s) of the running rms peak.
    static let peakHalfLife: Double = 8
    static let peakFloor: Double = 1e-4
    static let restSpeed: Double = 0.05

    public init() {}

    /// Friction multiplier at a given level; never below 0.05.
    public static func sustainScale(level: Double, strength: Double = SpinnerSettings.defaultMusicSustain) -> Double {
        let removed: Double = strength * level
        return max(0.05, 1 - removed)
    }

    /// Angular impulse for a beat pulse: along the current spin, positive when at rest.
    public static func kickImpulse(pulse: Float, velocity: Double,
                                   gain: Double = SpinnerSettings.defaultMusicKick) -> Double {
        let mag: Double = gain * Double(pulse)
        return velocity < -restSpeed ? -mag : mag
    }

    public mutating func update(rms: Float, bassEnergy: Float, dt: Double,
                                velocity: Double, mode: SpinnerMusicMode,
                                sustain: Double = SpinnerSettings.defaultMusicSustain,
                                kick: Double = SpinnerSettings.defaultMusicKick) -> Output {
        let dt = max(dt, 0)
        clock += dt
        let r: Double = max(Double(rms), 0)
        let decay: Double = pow(0.5, dt / Self.peakHalfLife)
        let decayed: Double = max(runningPeak * decay, Self.peakFloor)
        runningPeak = max(r, decayed)
        let target: Double = min(1, r / runningPeak)
        let tau: Double = (target > level) ? SpinnerTuning.musicLevelAttack : SpinnerTuning.musicLevelRelease
        let blend: Double = 1 - exp(-dt / max(tau, 1e-6))
        level += (target - level) * blend
        // The follower always runs so it is warm when kick is switched on.
        let pulse = follower.update(bassEnergy: bassEnergy, timestamp: clock)
        var out = Output(frictionScale: 1, impulse: 0, pulse: 0)
        if mode == .sustain || mode == .both { out.frictionScale = Self.sustainScale(level: level, strength: sustain) }
        if (mode == .kick || mode == .both) && pulse > 0 {
            out.pulse = pulse
            out.impulse = Self.kickImpulse(pulse: pulse, velocity: velocity, gain: kick)
        }
        return out
    }
}
