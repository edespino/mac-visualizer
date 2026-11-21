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
import QuartzCore

/// Procedural music-like audio source for "Demo Mode" — feeds the visualizer
/// when no music is playing. Pure function of timestamp (modulo the seeded RNG
/// for sparkle jitter). Generates a bass kick on a ~120 BPM grid, a slow
/// mid-band melodic sweep, and occasional high-band sparkles. Deterministic
/// given a fixed seed.
public final class DemoAudioSource {
    private let barCount: Int
    private let seed: UInt64
    private var rng: SeededRNG
    private var startTime: CFTimeInterval?

    // Tunables (private; tweak via code if "looks lively, not chaotic" needs adjusting).
    private let kickPeriod: Double = 0.5          // 120 BPM
    private let kickSigma: Double = 0.06          // gaussian half-width in seconds
    private let kickAmplitude: Float = 0.85
    private let lowFraction: Double = 0.15        // kick affects bottom 15% of bands

    private let sweepCycle: Double = 4.0          // seconds per full sweep cycle
    private let sweepMidLow: Double = 0.20        // bands [20%..60%] form the mid region
    private let sweepMidHigh: Double = 0.60

    private let sparklePeriodMean: Double = 1.2   // seconds between sparkles (mean)
    private let sparklePeriodJitter: Double = 0.4 // ± seconds of randomness
    private let sparkleDecay: Double = 0.15
    private let sparkleAmplitude: Float = 0.6
    private let sparkleLowFraction: Double = 0.70 // sparkles land in top 30% of bands

    // Sparkle scheduler state — "next" tracks the upcoming event; "last" tracks
    // the most recent fired event so the decay envelope is applied against it.
    private var nextSparkleTime: Double = -1     // < 0 means "init on first frame"
    private var nextSparkleBand: Int = -1
    private var lastSparkleTime: Double = -1000  // far past → exp(...) ≈ 0 → no sparkle at t=0
    private var lastSparkleBand: Int = -1

    // Per-kick amplitude jitter — chosen once when a new kick fires, held until
    // the next kick. -1 sentinel means "init on first kick".
    private var lastKickIndex: Int = -1
    private var currentKickAmpScale: Float = 1.0

    public init(barCount: Int, seed: UInt64 = 0xDEADBEEF) {
        precondition(barCount > 0, "barCount must be positive")
        self.barCount = barCount
        self.seed = seed
        self.rng = SeededRNG(seed: seed)
    }

    /// Produce one synthetic `AudioFrame` for the given (wall-clock) timestamp.
    /// The internal "demo clock" starts at zero on the first call so callers can
    /// pass in `CACurrentMediaTime()` without coordinating absolute t=0.
    public func nextFrame(at timestamp: CFTimeInterval) -> AudioFrame {
        if startTime == nil { startTime = timestamp }
        let t = max(0, timestamp - (startTime ?? timestamp))

        // Schedule first sparkle into the future on the first frame.
        if nextSparkleTime < 0 {
            nextSparkleTime = sparklePeriodMean
            nextSparkleBand = pickSparkleBand()
        }
        // Advance the sparkle scheduler past any events that already happened,
        // recording each one as the "last" so the decay applies to it.
        while t >= nextSparkleTime {
            lastSparkleTime = nextSparkleTime
            lastSparkleBand = nextSparkleBand
            nextSparkleTime += sparklePeriodMean
                + (Double(rng.nextSigned()) * sparklePeriodJitter)
            nextSparkleBand = pickSparkleBand()
        }

        var bands = [Float](repeating: 0, count: barCount)

        // Per-kick amplitude jitter: ±10% chosen at each new kick instant.
        let kickIndex = Int(floor(t / kickPeriod))
        if kickIndex != lastKickIndex {
            lastKickIndex = kickIndex
            currentKickAmpScale = 1.0 + rng.nextSigned() * 0.1
        }

        // -- Bass kick: gaussian pulse on bands [0 ..< lowCount] every kickPeriod.
        let lowCount = max(1, Int(Double(barCount) * lowFraction))
        let kickPhase = t.truncatingRemainder(dividingBy: kickPeriod)
        let dt = min(kickPhase, kickPeriod - kickPhase)
        let kickEnv = expf(-Float(dt * dt / (2 * kickSigma * kickSigma)))
        for i in 0..<lowCount {
            // Slight per-band falloff inside the bass region.
            let falloff = 1.0 - 0.4 * Float(i) / Float(max(lowCount - 1, 1))
            bands[i] += kickAmplitude * currentKickAmpScale * kickEnv * falloff
        }

        // -- Mid-band sweep: 0.4 + 0.4 * sin(2π t/cycle) across bands [lo..<hi].
        let mLo = Int(Double(barCount) * sweepMidLow)
        let mHi = max(mLo + 1, Int(Double(barCount) * sweepMidHigh))
        let sweepLevel = Float(0.4 + 0.4 * sin(2.0 * .pi * t / sweepCycle))
        for i in mLo..<min(mHi, barCount) {
            // Soft shape across the mid range (cosine-window-ish).
            let u = Float(i - mLo) / Float(max(mHi - mLo - 1, 1))
            let shape = sinf(.pi * u)
            bands[i] += sweepLevel * shape
        }

        // -- High-band sparkle: exponential decay against the most recently
        // fired event. Before any event has fired, `lastSparkleTime` is far in
        // the past so the envelope evaluates to ~0 (no sparkle at startup).
        if lastSparkleBand >= 0, lastSparkleBand < barCount {
            let sparkleAge = max(0, t - lastSparkleTime)
            let sparkleEnv = expf(-Float(sparkleAge / sparkleDecay))
            bands[lastSparkleBand] += sparkleAmplitude * sparkleEnv
        }

        // Clamp 0..1.
        for i in 0..<bands.count { bands[i] = min(max(bands[i], 0), 1) }

        // Derived: peak, rms, bandPeaks (≈ bands + small headroom), waveform (256-sample
        // sine modulated by current bass energy, so the oscilloscope shows life).
        let peak = bands.max() ?? 0
        let sumSquares = bands.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = bands.isEmpty ? 0 : sqrtf(sumSquares / Float(barCount))
        let bandPeaks = bands.map { min($0 + 0.05, 1) }

        let waveLen = 256
        var wave = [Float](repeating: 0, count: waveLen)
        let waveAmp = 0.3 + 0.7 * kickEnv
        for j in 0..<waveLen {
            let p = Float(j) / Float(waveLen)
            wave[j] = waveAmp * sinf(Float(t) * 3 + p * 2 * .pi * 4)
        }

        return AudioFrame(bands: bands, bandPeaks: bandPeaks, waveform: wave,
                          rms: rms, peak: peak, timestamp: timestamp)
    }

    /// Reset state so the next `nextFrame(at:)` call starts a fresh demo at t=0.
    public func reset() {
        rng = SeededRNG(seed: seed)
        startTime = nil
        nextSparkleTime = -1
        nextSparkleBand = -1
        lastSparkleTime = -1000
        lastSparkleBand = -1
        lastKickIndex = -1
        currentKickAmpScale = 1.0
    }

    private func pickSparkleBand() -> Int {
        let lo = Int(Double(barCount) * sparkleLowFraction)
        let hi = max(lo + 1, barCount)
        let span = Float(hi - lo)
        let pick = Int(rng.nextUnit() * span)
        return min(hi - 1, lo + pick)
    }
}

// `SeededRNG` lives in Sources/Core/SeededRNG.swift (single module-internal copy
// shared across visualizers + DemoAudioSource).