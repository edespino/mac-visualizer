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

final class BeatDetectorTests: XCTestCase {

    func testSilenceProducesNoBeats() {
        var d = BeatDetector()
        var beats = 0
        for i in 0..<200 {
            let r = d.update(peak: 0, timestamp: Double(i) / 60.0)
            if r.beat { beats += 1 }
        }
        XCTAssertEqual(beats, 0)
    }

    func testSteadyToneProducesNoBeats() {
        // No onsets in a perfectly steady signal — the aged baseline catches up.
        var d = BeatDetector()
        var beats = 0
        // Warm up the baseline first.
        for i in 0..<60 { _ = d.update(peak: 0.7, timestamp: Double(i) / 60.0) }
        for i in 60..<260 {
            if d.update(peak: 0.7, timestamp: Double(i) / 60.0).beat { beats += 1 }
        }
        XCTAssertLessThanOrEqual(beats, 1, "expected 0–1 beats on a steady tone, got \(beats)")
    }

    func testKickPulsesProduceBeats() {
        // 120 BPM = 0.5s per kick. Gaussian envelope of width 0.06s around each
        // kick instant. 4 seconds = 8 kicks. Expect at least 6 detected onsets
        // (allowing 2-onset slop for the auto-tune warm-up).
        var d = BeatDetector()
        var beats = 0
        let frames = 4 * 60   // 4 seconds at 60 fps
        for i in 0..<frames {
            let t = Double(i) / 60.0
            let kickPhase = t.truncatingRemainder(dividingBy: 0.5)
            let dt = min(kickPhase, 0.5 - kickPhase)
            let env = Float(exp(-dt * dt / (2 * 0.06 * 0.06)))
            if d.update(peak: env, timestamp: t).beat { beats += 1 }
        }
        XCTAssertGreaterThanOrEqual(beats, 6, "expected ≥6 kicks detected, got \(beats)")
    }

    func testRefractoryPreventsBackToBackBeats() {
        var d = BeatDetector()
        // Two strong onsets 50 ms apart — refractory is 150 ms, so only the
        // first should fire.
        _ = d.update(peak: 0, timestamp: 0.0)
        let a = d.update(peak: 1.0, timestamp: 0.01)
        let b = d.update(peak: 1.0, timestamp: 0.06)
        XCTAssertTrue(a.beat)
        XCTAssertFalse(b.beat)
    }

    func testIntensityZeroWhenNoBeat() {
        var d = BeatDetector()
        for i in 0..<10 {
            let r = d.update(peak: 0, timestamp: Double(i) / 60.0)
            XCTAssertFalse(r.beat)
            XCTAssertEqual(r.intensity, 0, accuracy: 1e-6)
        }
    }

    func testResetClearsState() {
        var d = BeatDetector()
        for i in 0..<60 { _ = d.update(peak: 1, timestamp: Double(i) / 60.0) }
        d.reset()
        // After reset, a single strong onset should fire (no stale baseline above the new peak).
        _ = d.update(peak: 0, timestamp: 0)
        let r = d.update(peak: 1, timestamp: 1.0 / 60)
        XCTAssertTrue(r.beat)
    }

    func testGoomLimitDecaysWhenTooFewOnsets() {
        // Start with a high limit and feed kicks. The limit should decay every
        // cycleLength=32 frames if fewer than targetGoomsPerWindow=2 fired.
        var d = BeatDetector()
        d.setGoomLimitForTesting(5.0)
        // 8 cycle windows = 256 frames with 120 BPM kicks (8 kicks total — but
        // they won't fire at limit=5 initially, so totalGoom stays under target
        // and the limit decays each cycle).
        for i in 0..<256 {
            let t = Double(i) / 60.0
            let kickPhase = t.truncatingRemainder(dividingBy: 0.5)
            let dt = min(kickPhase, 0.5 - kickPhase)
            let env = Float(exp(-dt * dt / (2 * 0.06 * 0.06)))
            _ = d.update(peak: env, timestamp: t)
        }
        XCTAssertLessThan(d.goomLimit, 1.0, "expected goomLimit to decay; got \(d.goomLimit)")
    }

    func testGoomLimitGrowsWhenTooManyOnsets() {
        // Feed a continuously rising-then-falling noise signal that produces
        // many onsets — the limit should grow to suppress them.
        var d = BeatDetector()
        let initial = d.goomLimit
        for i in 0..<256 {
            let t = Double(i) / 60.0
            // Sawtooth pattern with frequent sharp jumps.
            let peak = Float(((i % 4) == 0) ? 1.0 : 0.0)
            _ = d.update(peak: peak, timestamp: t)
        }
        XCTAssertGreaterThan(d.goomLimit, initial, "expected goomLimit to grow; got \(d.goomLimit) (initial \(initial))")
    }
}