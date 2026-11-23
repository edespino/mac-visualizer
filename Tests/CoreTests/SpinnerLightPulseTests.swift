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

final class SpinnerLightPulseTests: XCTestCase {

    private func settings(on: Bool = true, rest: Double = 0.5, peak: Double = 1.0) -> SpinnerSettings {
        var s = SpinnerSettings()
        s.beatLights = on
        s.restingGlow = rest
        s.beatGlow = peak
        return s
    }

    /// Runs `seconds` of frames at 60 Hz with no beats; returns the last level.
    private func run(_ p: inout SpinnerLightPulse, seconds: Double, playing: Bool, _ s: SpinnerSettings) -> Float {
        var level: Float = 0
        let dt: Double = 1.0 / 60.0
        var t: Double = 0
        while t < seconds {
            level = p.update(dt: dt, beatStrength: 0, trackPlaying: playing, settings: s)
            t += dt
        }
        return level
    }

    func testOffIsAlwaysOne() {
        var p = SpinnerLightPulse()
        let s = settings(on: false)
        XCTAssertEqual(p.update(dt: 0.016, beatStrength: 1, trackPlaying: true, settings: s), 1, accuracy: 1e-6)
        XCTAssertEqual(p.update(dt: 0.016, beatStrength: 0, trackPlaying: false, settings: s), 1, accuracy: 1e-6)
        XCTAssertEqual(run(&p, seconds: 3, playing: true, s), 1, accuracy: 1e-6)
    }

    func testRestsAtRestingGlowWhilePlayingWithoutBeats() {
        var p = SpinnerLightPulse()
        let s = settings(rest: 0.4)
        XCTAssertEqual(run(&p, seconds: 5, playing: true, s), 0.4, accuracy: 1e-5)
    }

    func testBeatJumpsImmediatelyToRestPlusSpan() {
        var p = SpinnerLightPulse()
        let s = settings(rest: 0.4, peak: 1.0)
        _ = run(&p, seconds: 1, playing: true, s)
        let level = p.update(dt: 1.0 / 60.0, beatStrength: 1, trackPlaying: true, settings: s)
        XCTAssertGreaterThan(level, 0.95)
        XCTAssertLessThanOrEqual(level, 1.0)
    }

    func testSoftBeatStillReachesFortyPercentOfTheWay() {
        var p = SpinnerLightPulse()
        let s = settings(rest: 0.2, peak: 1.0)
        _ = run(&p, seconds: 1, playing: true, s)
        let level = p.update(dt: 0, beatStrength: 0.05, trackPlaying: true, settings: s)
        XCTAssertEqual(level, 0.2 + 0.8 * 0.4, accuracy: 1e-5)
    }

    func testBeatStrengthScalesAboveTheFloor() {
        var p = SpinnerLightPulse()
        let s = settings(rest: 0.2, peak: 1.0)
        _ = run(&p, seconds: 1, playing: true, s)
        let level = p.update(dt: 0, beatStrength: 0.7, trackPlaying: true, settings: s)
        XCTAssertEqual(level, 0.2 + 0.8 * 0.7, accuracy: 1e-5)
    }

    func testDecaysBackToRestWithinQuarterSecond() {
        var p = SpinnerLightPulse()
        let s = settings(rest: 0.3, peak: 1.0)
        _ = run(&p, seconds: 1, playing: true, s)
        _ = p.update(dt: 0, beatStrength: 1, trackPlaying: true, settings: s)
        var level: Float = 0
        var t: Double = 0
        var previous: Float = 2
        while t < 0.2501 {
            level = p.update(dt: 1.0 / 60.0, beatStrength: 0, trackPlaying: true, settings: s)
            XCTAssertLessThanOrEqual(level, previous + 1e-6, "the fall is monotonic")
            previous = level
            t += 1.0 / 60.0
        }
        XCTAssertEqual(level, 0.3, accuracy: 0.01)
    }

    func testPeakNeverBelowRest() {
        var p = SpinnerLightPulse()
        let s = settings(rest: 0.8, peak: 0.2)
        _ = run(&p, seconds: 1, playing: true, s)
        let level = p.update(dt: 0, beatStrength: 1, trackPlaying: true, settings: s)
        XCTAssertEqual(level, 0.8, accuracy: 1e-5)
    }

    func testEqualLevelsMeanNoPulse() {
        var p = SpinnerLightPulse()
        let s = settings(rest: 0.6, peak: 0.6)
        _ = run(&p, seconds: 1, playing: true, s)
        let level = p.update(dt: 0, beatStrength: 1, trackPlaying: true, settings: s)
        XCTAssertEqual(level, 0.6, accuracy: 1e-6)
    }

    func testRepeatedBeatsNeverExceedPeak() {
        var p = SpinnerLightPulse()
        let s = settings(rest: 0.3, peak: 0.9)
        _ = run(&p, seconds: 1, playing: true, s)
        for _ in 0..<30 {
            let level = p.update(dt: 1.0 / 120.0, beatStrength: 1, trackPlaying: true, settings: s)
            XCTAssertLessThanOrEqual(level, 0.9 + 1e-6)
        }
    }

    func testWeakerBeatDuringDecayDoesNotLowerTheLevel() {
        var p = SpinnerLightPulse()
        let s = settings(rest: 0.2, peak: 1.0)
        _ = run(&p, seconds: 1, playing: true, s)
        let strong = p.update(dt: 0, beatStrength: 1, trackPlaying: true, settings: s)
        let after = p.update(dt: 0, beatStrength: 0.1, trackPlaying: true, settings: s)
        XCTAssertEqual(after, strong, accuracy: 1e-6)
    }

    func testNoMusicForTwoSecondsEasesUpToOne() {
        var p = SpinnerLightPulse()
        let s = settings(rest: 0.3)
        _ = run(&p, seconds: 1, playing: true, s)
        // Within the 2 s delay the level stays at rest.
        XCTAssertEqual(run(&p, seconds: 1.8, playing: false, s), 0.3, accuracy: 1e-5)
        // About one more second finishes the ease.
        XCTAssertEqual(run(&p, seconds: 1.3, playing: false, s), 1.0, accuracy: 1e-4)
    }

    func testIdleEaseIsGradualNotAStep() {
        var p = SpinnerLightPulse()
        let s = settings(rest: 0.3)
        _ = run(&p, seconds: 1, playing: true, s)
        _ = run(&p, seconds: 2.5, playing: false, s)
        let level = p.update(dt: 1.0 / 60.0, beatStrength: 0, trackPlaying: false, settings: s)
        XCTAssertGreaterThan(level, 0.3)
        XCTAssertLessThan(level, 0.95)
    }

    func testResumeEasesBackToRest() {
        var p = SpinnerLightPulse()
        let s = settings(rest: 0.3)
        _ = run(&p, seconds: 1, playing: true, s)
        _ = run(&p, seconds: 4, playing: false, s)
        XCTAssertEqual(p.update(dt: 0, beatStrength: 0, trackPlaying: true, settings: s), 1.0, accuracy: 1e-3)
        XCTAssertEqual(run(&p, seconds: 1.5, playing: true, s), 0.3, accuracy: 1e-4)
    }

    func testBeatsAreIgnoredWhileNothingPlays() {
        var p = SpinnerLightPulse()
        let s = settings(rest: 0.3)
        _ = run(&p, seconds: 3, playing: false, s)
        let level = p.update(dt: 1.0 / 60.0, beatStrength: 1, trackPlaying: false, settings: s)
        XCTAssertEqual(level, 1.0, accuracy: 1e-4)
    }

    func testClampsAndNaNSafety() {
        var p = SpinnerLightPulse()
        let s = settings(rest: 0.5, peak: 1.0)
        let a = p.update(dt: Double.nan, beatStrength: Float.nan, trackPlaying: true, settings: s)
        XCTAssertFalse(a.isNaN)
        XCTAssertGreaterThanOrEqual(a, 0)
        XCTAssertLessThanOrEqual(a, 1)
        let b = p.update(dt: -5, beatStrength: 99, trackPlaying: true, settings: s)
        XCTAssertGreaterThanOrEqual(b, 0)
        XCTAssertLessThanOrEqual(b, 1)
        let c = p.update(dt: 1e9, beatStrength: -3, trackPlaying: true, settings: s)
        XCTAssertGreaterThanOrEqual(c, 0)
        XCTAssertLessThanOrEqual(c, 1)
    }

    func testTurningOffResetsToOne() {
        var p = SpinnerLightPulse()
        _ = p.update(dt: 0, beatStrength: 1, trackPlaying: true, settings: settings(rest: 0.2))
        XCTAssertEqual(p.update(dt: 0.016, beatStrength: 0, trackPlaying: true, settings: settings(on: false)), 1, accuracy: 1e-6)
        // Back on: no leftover pulse.
        let level = p.update(dt: 0.016, beatStrength: 0, trackPlaying: true, settings: settings(rest: 0.2))
        XCTAssertEqual(level, 0.2, accuracy: 1e-5)
    }
}

final class SpinnerLightInboxTests: XCTestCase {
    func testKeepsTheStrongestPulseSinceLastDrain() {
        let inbox = SpinnerLightInbox()
        inbox.post(0.3, at: 10)
        inbox.post(0.9, at: 10.01)
        inbox.post(0.5, at: 10.02)
        XCTAssertEqual(inbox.drain(now: 10.03), 0.9, accuracy: 1e-6)
        XCTAssertEqual(inbox.drain(now: 10.04), 0, accuracy: 1e-6)
    }

    func testStalePulsesAreDropped() {
        let inbox = SpinnerLightInbox()
        inbox.post(1, at: 10)
        XCTAssertEqual(inbox.drain(now: 20), 0, accuracy: 1e-6)
    }

    func testRejectsNaNAndClampsRange() {
        let inbox = SpinnerLightInbox()
        inbox.post(Float.nan, at: 1)
        XCTAssertEqual(inbox.drain(now: 1.01), 0, accuracy: 1e-6)
        inbox.post(7, at: 1)
        XCTAssertEqual(inbox.drain(now: 1.01), 1, accuracy: 1e-6)
    }

    func testConcurrentPostsAreSafe() {
        let inbox = SpinnerLightInbox()
        DispatchQueue.concurrentPerform(iterations: 200) { (i: Int) -> Void in
            inbox.post(Float(i % 100) / 100, at: 5)
        }
        XCTAssertEqual(inbox.drain(now: 5.01), 0.99, accuracy: 1e-6)
    }
}
