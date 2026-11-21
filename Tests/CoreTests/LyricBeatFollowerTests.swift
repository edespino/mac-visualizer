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

final class LyricBeatFollowerTests: XCTestCase {
    private let dt = 1.0 / 60.0   // ~60 fps frame stream

    /// Feed a sequence of bassEnergy values at ~60 fps; return the pulse per frame.
    private func run(_ values: [Float], follower: inout LyricBeatFollower) -> [Float] {
        values.enumerated().map { i, v in
            follower.update(bassEnergy: v, timestamp: Double(i) * dt)
        }
    }

    func testFiresOnRisingBassAtLowLevel() {
        // A step from 0.005 to 0.03 — a level a 0.05-floor detector ignores.
        var f = LyricBeatFollower()
        var values = [Float](repeating: 0.005, count: 30)
        values.append(0.03)
        values.append(contentsOf: [Float](repeating: 0.03, count: 5))
        let pulses = run(values, follower: &f)
        XCTAssertGreaterThan(pulses[30], 0, "a rise to 0.03 from 0.005 must fire")
        XCTAssertLessThanOrEqual(pulses[30], 1)
    }

    func testDoesNotFireOnFlatInput() {
        var f = LyricBeatFollower()
        let pulses = run([Float](repeating: 0.03, count: 120), follower: &f)
        XCTAssertEqual(pulses.filter { $0 > 0 }.count, 0, "steady input must never fire")
    }

    func testDoesNotFireOnSilence() {
        // Jittering noise floor, every value below the silence epsilon.
        var f = LyricBeatFollower()
        let floorPattern: [Float] = [0.0, 0.0009, 0.0018]
        let values = (0..<120).map { floorPattern[$0 % floorPattern.count] }
        let pulses = run(values, follower: &f)
        XCTAssertEqual(pulses.filter { $0 > 0 }.count, 0, "sub-epsilon input must never fire")
    }

    func testRefractoryAllowsOnePulsePerBeat() {
        var f = LyricBeatFollower()
        var values = [Float](repeating: 0.01, count: 30)          // warmup / baseline
        values.append(0.05)                                        // 30: spike 1 -> fires
        values.append(contentsOf: [Float](repeating: 0.01, count: 4))   // 31..34
        values.append(0.05)                                        // 35: spike 2 (~83 ms) -> suppressed
        values.append(contentsOf: [Float](repeating: 0.01, count: 18))  // 36..53
        values.append(0.05)                                        // 54: spike 3 (400 ms) -> fires
        values.append(contentsOf: [Float](repeating: 0.01, count: 6))
        let pulses = run(values, follower: &f)
        XCTAssertGreaterThan(pulses[30], 0, "spike 1 fires")
        XCTAssertEqual(pulses[35], 0, "spike 2 inside the refractory window is suppressed")
        XCTAssertGreaterThan(pulses[54], 0, "spike 3 past the refractory window fires")
        XCTAssertEqual(pulses.filter { $0 > 0 }.count, 2, "exactly two beats fire")
    }

    func testIntensityScalesWithRise() {
        var small = LyricBeatFollower()
        var big = LyricBeatFollower()
        let warmup = [Float](repeating: 0.01, count: 15)
        let smallPulse = run(warmup + [0.03], follower: &small).last!
        let bigPulse = run(warmup + [0.06], follower: &big).last!
        XCTAssertGreaterThan(smallPulse, 0)
        XCTAssertGreaterThan(bigPulse, smallPulse, "a bigger rise yields a bigger pulse")
        XCTAssertLessThanOrEqual(bigPulse, 1)
    }

    func testBaselineAdaptsOnSustainedLoud() {
        var f = LyricBeatFollower()
        let jitter: [Float] = [0.004, -0.003, 0.005, -0.002, 0.003, -0.004, 0.002, -0.005]
        var values = [Float](repeating: 0.01, count: 20)          // quiet baseline
        for i in 0..<150 { values.append(0.08 + jitter[i % jitter.count]) }   // sustained loud + jitter
        let pulses = run(values, follower: &f)
        let loud = Array(pulses[20...])
        XCTAssertGreaterThan(loud.prefix(40).filter { $0 > 0 }.count, 0, "fires when the loud passage starts")
        XCTAssertEqual(loud.suffix(40).filter { $0 > 0 }.count, 0, "settles once the baseline catches up")
    }
}
