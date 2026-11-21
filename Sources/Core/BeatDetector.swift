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
import QuartzCore

/// Adaptive single-band onset detector. Clean-room Swift reimplementation of
/// the algorithm described in goom2k4's `sound_tester.c` — no source code was
/// copied, only the algorithm concept. See NOTICE for credits.
///
/// Tracks an aged "loudness" envelope; when its per-frame increase exceeds an
/// adaptive limit (auto-tuned every 32 frames toward a target onset rate),
/// emits a beat. The `intensity` returned on a beat is the normalized
/// magnitude of the onset (0…1), zero on non-beat frames.
///
/// Stateful — keep one instance alive across the analyzer's lifetime.
public struct BeatDetector {
    // State
    private var accelvar: Float = 0          // aged loudness envelope
    private var prevAccel: Float = 0         // previous frame's envelope (for delta)
    public private(set) var goomLimit: Float = 0.1    // adaptive onset threshold (readable for diagnostics)
    private var cycleTime: Int = 0           // frames since last retune
    private var totalGoom: Int = 0           // onsets fired in current cycle
    private var lastBeatTimestamp: CFTimeInterval = -.infinity

    // Tuning constants (units adapted to our 0…1 peak amplitude range).
    private let cycleLength: Int = 32
    private let targetGoomsPerWindow: Int = 2   // ≈ 4 onsets per second at 60 fps
    private let goomLimitFloor: Float = 0.05
    private let goomLimitDecay: Float = 0.50
    private let goomLimitGrowth: Float = 1.10
    private let accelDecay: Float = 0.91
    private let refractorySeconds: CFTimeInterval = 0.15

    public init() {}

    public mutating func reset() {
        accelvar = 0
        prevAccel = 0
        goomLimit = 0.1
        cycleTime = 0
        totalGoom = 0
        lastBeatTimestamp = -.infinity
    }

    /// Testing-only: pre-seed the adaptive threshold so tests can verify
    /// auto-tune behavior in either direction.
    internal mutating func setGoomLimitForTesting(_ value: Float) {
        goomLimit = value
    }

    /// One frame of analysis. `peak` should be the raw window peak amplitude
    /// (pre-smoothing), typically `frame.peak` from `SpectrumAnalyzer`.
    /// Returns `(beat: true, intensity: x>0)` on the single frame an onset
    /// fires, else `(beat: false, intensity: 0)`.
    public mutating func update(peak: Float, timestamp: CFTimeInterval) -> (beat: Bool, intensity: Float) {
        accelvar = max(accelvar * accelDecay, peak)
        let delta = accelvar - prevAccel
        let refractoryOK = timestamp - lastBeatTimestamp >= refractorySeconds
        let firing = (delta > goomLimit) && refractoryOK

        var intensity: Float = 0
        if firing {
            totalGoom += 1
            lastBeatTimestamp = timestamp
            intensity = min(1, max(0, delta / max(goomLimit, 0.01)))   // 0.01 guards sub-floor test injection
        }
        prevAccel = accelvar

        cycleTime += 1
        if cycleTime >= cycleLength {
            if totalGoom < targetGoomsPerWindow {
                goomLimit = max(goomLimitFloor, goomLimit * goomLimitDecay)
            } else if totalGoom > targetGoomsPerWindow {
                goomLimit = goomLimit * goomLimitGrowth
            }
            cycleTime = 0
            totalGoom = 0
        }

        return (firing, intensity)
    }
}