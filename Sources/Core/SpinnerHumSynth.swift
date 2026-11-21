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

// Procedural bearing hum, rendered sample by sample. Pure DSP with no
// allocation or locks in `render`, so the audio engine can call it on the render thread.

public final class SpinnerHumSynth {
    private let sampleRate: Float
    private var speed: Float = 0        // smoothed |speed| (drives pitch), rad/s
    private var level: Float = 0        // smoothed speed gain (linear)
    private var duckSmoothed: Float = 0 // short smoothing of the gate input (avoids stepping)
    private var volumeSmoothed: Float = 1 // short smoothing of the volume input
    private var fadePos: Float = 0      // 0...1 enabled-fade position; starts at 0 so first start fades in
    private var rng: UInt32 = 0x9E3779B9
    private var low: Float = 0
    private var band: Float = 0
    private var phase1: Float = 0
    private var phase2: Float = 0
    private var wobblePhase: Float = 0
    private let attackCoef: Float
    private let releaseCoef: Float
    private let duckCoef: Float         // about 30 ms
    private let fadeStep: Float         // fadePos change per sample (linear ramp over humEnabledFadeSeconds)
    private var gainOut: Float = 0

    public init(sampleRate: Double) {
        let sr: Float = Float(max(sampleRate, 8000))
        self.sampleRate = sr
        let attackSamples: Float = Float(SpinnerTuning.humAttackSeconds) * sr
        let releaseSamples: Float = Float(SpinnerTuning.humReleaseSeconds) * sr
        let duckSamples: Float = 0.03 * sr
        let fadeSeconds: Float = Float(max(SpinnerTuning.humEnabledFadeSeconds, 0.01))
        attackCoef = 1 - exp(-1 / attackSamples)
        releaseCoef = 1 - exp(-1 / releaseSamples)
        duckCoef = 1 - exp(-1 / duckSamples)
        fadeStep = 1 / (fadeSeconds * sr)
    }

    /// Current overall output gain (speed gain * duck * enabled fade, linear). Read by the player
    /// to know when the output has been at zero long enough to stop the engine.
    public var currentGain: Float { gainOut }

    /// Writes `frames` mono samples. `targetSpeed` is signed rad/s; `targetDuck` is the 0...1 gate gain
    /// (`SpinnerHumGate`: 0 whenever there is music activity); `targetEnabled` is 0 or 1 and eases over
    /// `humEnabledFadeSeconds`; `targetVolume` multiplies the peak gain (`SpinnerSettings.humVolume`).
    public func render(into out: UnsafeMutablePointer<Float>, frames: Int, targetSpeed: Float,
                       targetDuck: Float, targetEnabled: Float, targetVolume: Float = 1) {
        let maxSpeed = Float(max(SpinnerTuning.maxSpeed, 1e-6))
        let maxGain = Float(SpinnerTuning.humMaxGain)
        let target = min(abs(targetSpeed), maxSpeed * 4)
        let targetLevel = Float(SpinnerHum.gain(speed: Double(target)))
        let duckT = min(max(targetDuck, 0), 1)
        let volumeT: Float = min(max(targetVolume, 0), 2)
        let twoPi = 2 * Float.pi
        for i in 0..<frames {
            let speedCoef: Float = (target > speed) ? attackCoef : releaseCoef
            speed += (target - speed) * speedCoef
            let levelCoef: Float = (targetLevel > level) ? attackCoef : releaseCoef
            level += (targetLevel - level) * levelCoef
            duckSmoothed += (duckT - duckSmoothed) * duckCoef
            volumeSmoothed += (volumeT - volumeSmoothed) * duckCoef
            if targetEnabled > 0.5 { fadePos = min(fadePos + fadeStep, 1) } else { fadePos = max(fadePos - fadeStep, 0) }
            let fadeShape: Float = 3 - 2 * fadePos
            let fade: Float = fadePos * fadePos * fadeShape
            let n: Float = min(speed / maxSpeed, 1)
            let fc: Float = 300 + 1900 * n
            let f0: Float = 3 * speed
            wobblePhase += twoPi * 0.3 / sampleRate
            if wobblePhase > twoPi { wobblePhase -= twoPi }
            let wob: Float = 1 + 0.002 * sin(wobblePhase)   // about 3 cents
            phase1 += twoPi * f0 * wob / sampleRate
            phase2 += twoPi * f0 * 2.7 * wob / sampleRate
            if phase1 > twoPi { phase1 -= twoPi }
            if phase2 > twoPi { phase2 -= twoPi }
            // white noise -> state-variable band-pass (Q about 3)
            rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5
            let white: Float = Float(Int32(bitPattern: rng)) / Float(Int32.max)
            let nyquistLimit: Float = sampleRate * 0.25
            let fcLimited: Float = min(fc, nyquistLimit)
            let f: Float = 2 * sin(Float.pi * fcLimited / sampleRate)
            low += f * band
            let high: Float = white - low - band / 3
            band += f * high
            let toneA: Float = 0.15 * sin(phase1)
            let toneB: Float = 0.08 * sin(phase2)
            let mix: Float = 0.9 * band + toneA + toneB
            let g: Float = min(level, maxGain) * volumeSmoothed * duckSmoothed * fade
            gainOut = g
            // tanh bounds the output to +-1 before the gain, so the peak never exceeds the gain
            out[i] = tanh(mix) * g
        }
    }
}
