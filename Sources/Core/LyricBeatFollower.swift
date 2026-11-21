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

/// Adaptive, floor-free onset follower for the lyric shadow bounce. Unlike
/// `BeatDetector` (which gates on an absolute threshold floor of 0.05 of the
/// raw peak and so stays silent at the user's ~0.02 capture level), this
/// follower is fully *relative*: it fires when the instantaneous bass energy
/// rises above its own slow baseline by an adaptive multiple of recent
/// variability. That makes it scale-invariant — it fires the same on a quiet
/// track as a loud one — with no sensitivity control to tune.
///
/// Feed it `AudioFrame.bassEnergy` (a pre-gain mean FFT magnitude over a fixed
/// ~30–150 Hz window) once per frame; it returns a normalized pulse in `0...1`,
/// non-zero only on the frame a beat is detected. A refractory window enforces
/// one pulse per beat (a snap that eases back), never a shimmer on every bass
/// transient. A small absolute epsilon — far below BeatDetector's 0.05 — gates
/// out true silence so a paused or silent track never pulses.
///
/// Stateful; keep one instance alive and confine it to a single queue (the
/// analyzer's dsp queue), like `BeatDetector`.
public struct LyricBeatFollower {
    // Adaptive state.
    private var baseline: Float = 0        // slow EMA of bass energy
    private var variability: Float = 0     // slow EMA of |energy - baseline|
    private var previous: Float = 0        // last frame's energy (rising-edge gate)
    private var framesSeen: Int = 0
    private var lastPulseTime: CFTimeInterval = -.infinity

    // Tuning constants. Relative throughout, so they hold at any capture level.
    private let baselineAlpha: Float = 0.05       // baseline time constant (~0.33 s at 60 fps)
    private let variabilityAlpha: Float = 0.05    // variability tracks at the same rate
    private let sensitivity: Float = 3.0          // rise must clear this many "std devs"
    private let silenceEpsilon: Float = 0.002     // below this absolute level = silence; << 0.05
    private let refractorySeconds: CFTimeInterval = 0.30   // one pulse per beat, not per transient
    private let warmupFrames: Int = 8             // let the baseline settle before firing
    private let fullScaleRiseRatio: Float = 6.0   // a rise 6x the baseline = a full-strength pulse

    public init() {}

    public mutating func reset() {
        baseline = 0
        variability = 0
        previous = 0
        framesSeen = 0
        lastPulseTime = -.infinity
    }

    /// One frame. `bassEnergy` is `AudioFrame.bassEnergy`; `timestamp` is a
    /// monotonic clock (e.g. `CACurrentMediaTime()`). Returns the pulse in
    /// `0...1` (`0` = no onset this frame).
    public mutating func update(bassEnergy current: Float, timestamp: CFTimeInterval) -> Float {
        // Seed the baseline on the first frame so a cold start (baseline 0)
        // never reads the first real sample as a huge onset.
        if framesSeen == 0 {
            baseline = current
            variability = 0
            previous = current
            framesSeen = 1
            return 0
        }
        framesSeen += 1

        let rise = current - baseline
        let threshold = sensitivity * variability
        let refractoryOK = timestamp - lastPulseTime >= refractorySeconds
        let aboveSilence = current > silenceEpsilon
        let rising = current > previous
        let warmedUp = framesSeen > warmupFrames

        var pulse: Float = 0
        if warmedUp && aboveSilence && rising && refractoryOK && rise > threshold {
            lastPulseTime = timestamp
            pulse = min(1, max(0, rise / (max(baseline, silenceEpsilon) * fullScaleRiseRatio)))
        }

        // Advance the adaptive state after the decision, so the deviation is
        // measured against the baseline the decision actually used.
        let deviation = abs(current - baseline)
        baseline += baselineAlpha * (current - baseline)
        variability += variabilityAlpha * (deviation - variability)
        previous = current

        return pulse
    }
}
