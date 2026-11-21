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
import XCTest
@testable import MacVisualizerCore

final class DemoAudioSourceTests: XCTestCase {
    func testFrameShapeMatchesBarCount() {
        let src = DemoAudioSource(barCount: 32)
        let f = src.nextFrame(at: 0)
        XCTAssertEqual(f.bands.count, 32)
        XCTAssertEqual(f.bandPeaks.count, 32)
        XCTAssertFalse(f.waveform.isEmpty)
        XCTAssertEqual(f.timestamp, 0)
    }

    func testBandsAreInUnitRange() {
        let src = DemoAudioSource(barCount: 48)
        // Sample across 10 seconds to cover kicks, sparkles, sweep peaks.
        for i in 0..<200 {
            let t = Double(i) * 0.05
            let f = src.nextFrame(at: t)
            for b in f.bands {
                XCTAssertGreaterThanOrEqual(b, 0)
                XCTAssertLessThanOrEqual(b, 1, "band out of range at t=\(t)")
            }
            XCTAssertGreaterThanOrEqual(f.peak, 0)
            XCTAssertLessThanOrEqual(f.peak, 1)
        }
    }

    func testDeterministicWithSameSeed() {
        let a = DemoAudioSource(barCount: 32, seed: 0xC0FFEE)
        let b = DemoAudioSource(barCount: 32, seed: 0xC0FFEE)
        // Step both sources through identical times.
        for i in 0..<60 {
            let t = Double(i) * 0.05
            let fa = a.nextFrame(at: t)
            let fb = b.nextFrame(at: t)
            XCTAssertEqual(fa.bands, fb.bands, "diverged at t=\(t)")
        }
    }

    func testResetReproducesFrameStream() {
        var src = DemoAudioSource(barCount: 32, seed: 0xABCD)
        let captured = (0..<30).map { i -> [Float] in
            src.nextFrame(at: Double(i) * 0.05).bands
        }
        src.reset()
        for (i, expected) in captured.enumerated() {
            let f = src.nextFrame(at: Double(i) * 0.05)
            XCTAssertEqual(f.bands, expected, "diverged after reset at step \(i)")
        }
    }

    func testBassKickRaisesLowBandEnergy() {
        // Around t = 0 a bass kick fires (kicks at t = 0, 0.5, 1.0, ...).
        // The low bands at t ≈ 0 should carry significantly more energy than at
        // the midpoint between kicks (t ≈ 0.25).
        let src = DemoAudioSource(barCount: 48)
        let lowCount = max(1, 48 * 15 / 100)
        func lowSum(_ f: AudioFrame) -> Float {
            f.bands.prefix(lowCount).reduce(0, +)
        }
        let onKick = lowSum(src.nextFrame(at: 0))
        let between = lowSum(src.nextFrame(at: 0.25))
        XCTAssertGreaterThan(onKick, between * 1.5,
                             "expected low-band energy at kick (\(onKick)) >> between (\(between))")
    }

    func testMidSweepEnergyIsNonZero() {
        let src = DemoAudioSource(barCount: 48)
        // Mid bands occupy roughly 20%..60% of the spectrum.
        let lo = 48 * 20 / 100
        let hi = 48 * 60 / 100
        // Across a full sweep cycle (4 s) at least one of these samples must
        // show non-trivial mid-band activity.
        var maxMid: Float = 0
        for i in 0..<80 {
            let t = Double(i) * 0.05
            let f = src.nextFrame(at: t)
            let mid = f.bands[lo..<hi].max() ?? 0
            if mid > maxMid { maxMid = mid }
        }
        XCTAssertGreaterThan(maxMid, 0.1,
                             "mid sweep produced suspiciously low max=\(maxMid)")
    }

    func testHighBandSparkleFiresAtScheduledTime() {
        // The first sparkle is scheduled at t = sparklePeriodMean (1.2 s) on
        // the default seed (before any RNG advances). High bands (top 30%)
        // are touched ONLY by sparkles — bass kicks live in the bottom 15%
        // and the mid sweep in the middle 40%. So high-band energy at the
        // sparkle time should be meaningfully larger than just before.
        let src = DemoAudioSource(barCount: 48)
        // Walk through frames up to just before the scheduled sparkle.
        for i in 0..<20 {
            _ = src.nextFrame(at: Double(i) * 0.05)
        }
        let lo = 48 * 70 / 100
        let beforeSparkle = src.nextFrame(at: 1.05)
        let highMaxBefore = beforeSparkle.bands[lo..<48].max() ?? 0
        let atSparkle = src.nextFrame(at: 1.21)
        let highMaxAt = atSparkle.bands[lo..<48].max() ?? 0
        XCTAssertGreaterThan(highMaxAt, 0.3,
                             "sparkle should be visible at firing time (got \(highMaxAt))")
        XCTAssertGreaterThan(highMaxAt, highMaxBefore + 0.2,
                             "sparkle should be substantially brighter than the moment before (before=\(highMaxBefore), at=\(highMaxAt))")
    }
}