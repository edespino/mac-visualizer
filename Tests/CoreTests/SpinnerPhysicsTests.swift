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
import simd
import XCTest
@testable import MacVisualizerCore

final class SpinnerPhysicsTests: XCTestCase {
    private func run(_ p: inout SpinnerPhysics, seconds: Double) -> Int {
        var n = 0
        for _ in 0..<Int(seconds * 60) { n += p.step(dt: 1.0 / 60) }
        return n
    }

    func testImpulseSetsDirectionAndSpeed() {
        var p = SpinnerPhysics()
        p.applyImpulse(1)
        XCTAssertEqual(p.velocity, SpinnerTuning.impulseGain, accuracy: 1e-9)
        var q = SpinnerPhysics()
        q.applyImpulse(-2)
        XCTAssertEqual(q.velocity, -2 * SpinnerTuning.impulseGain, accuracy: 1e-9)
    }

    func testFrictionReachesExactZeroAndNeverReverses() {
        // Detent off: it can legitimately roll the spinner back into a notch.
        let saved = SpinnerTuning.detentStrength
        SpinnerTuning.detentStrength = 0
        defer { SpinnerTuning.detentStrength = saved }
        var p = SpinnerPhysics(angle: 0.1, velocity: 30)
        for _ in 0..<(400 * 60) {
            p.step(dt: 1.0 / 60)
            XCTAssertGreaterThanOrEqual(p.velocity, 0)
        }
        XCTAssertEqual(p.velocity, 0)
        var q = SpinnerPhysics(angle: 0.1, velocity: -30)
        for _ in 0..<(400 * 60) {
            q.step(dt: 1.0 / 60)
            XCTAssertLessThanOrEqual(q.velocity, 0)
        }
        XCTAssertEqual(q.velocity, 0)
    }

    func testDetentSettlesToExactZero() {
        let saved = (SpinnerTuning.detentStrength, SpinnerTuning.detentFadeSpeed, SpinnerTuning.detentDamping)
        SpinnerTuning.detentStrength = 1.5
        SpinnerTuning.detentFadeSpeed = 3
        SpinnerTuning.detentDamping = 1.5
        defer { (SpinnerTuning.detentStrength, SpinnerTuning.detentFadeSpeed, SpinnerTuning.detentDamping) = saved }
        var p = SpinnerPhysics(angle: 0.1, velocity: 3)
        _ = run(&p, seconds: 60)
        XCTAssertEqual(p.velocity, 0)
    }

    func testCoastsMonotonicallyWithoutReversal() {
        var p = SpinnerPhysics(angle: 0, velocity: 10)
        var prevV = p.velocity, prevA = p.angle
        for _ in 0..<(20 * 60) {
            p.step(dt: 1.0 / 60)
            XCTAssertLessThanOrEqual(p.velocity, prevV)
            XCTAssertGreaterThanOrEqual(p.velocity, 0)
            XCTAssertGreaterThanOrEqual(p.angle, prevA)
            prevV = p.velocity; prevA = p.angle
        }
    }

    func testLongCoastFromHighSpeed() {
        var p = SpinnerPhysics(angle: 0, velocity: 40)
        _ = run(&p, seconds: 60)
        XCTAssertGreaterThan(p.velocity, 1.0)
        _ = run(&p, seconds: 120)
        XCTAssertEqual(p.velocity, 0)
    }

    func testSingleClickGivesVisibleTurn() {
        var p = SpinnerPhysics()
        p.applyImpulse(1.0)
        _ = run(&p, seconds: 60)
        XCTAssertEqual(p.velocity, 0)
        XCTAssertGreaterThan(p.angle, 2 * Double.pi)
    }

    func testCycleMetalWraps() {
        var metal: SpinnerMetal = .steel
        var seen: [SpinnerMetal] = []
        for _ in 0..<SpinnerMetal.allCases.count {
            metal = metal.next
            seen.append(metal)
        }
        XCTAssertEqual(seen, [.brass, .copper, .blackZirconium, .anodizedTitanium, .steel])
        XCTAssertEqual(SpinnerMetal.copper.displayName, "Copper")
    }

    func testHubMarkIsFixedWithInterlockOnTheFront() {
        XCTAssertEqual(SpinnerTuning.hubMark, .interlock)
        XCTAssertEqual(SpinnerHubMark.allCases, [.interlock, .signOff])
        XCTAssertEqual(SpinnerHubMark.interlock.displayName, "Interlock")
        XCTAssertEqual(SpinnerHubMark.signOff.displayName, "Sign-off")
    }

    func testSpeedClamp() {
        var p = SpinnerPhysics()
        p.applyImpulse(10_000)
        XCTAssertEqual(p.velocity, SpinnerTuning.maxSpeed)
        // Direction lock: an opposing push only brakes, never reverses.
        p.applyImpulse(-100_000, now: 1)
        XCTAssertEqual(p.velocity, 0)
        var q = SpinnerPhysics()
        q.applyImpulse(-10_000)
        XCTAssertEqual(q.velocity, -SpinnerTuning.maxSpeed)
    }

    func testFrictionMultiplierScalesBothTerms() {
        func coast(_ friction: Double) -> Double {
            var settings = SpinnerSettings()
            settings.friction = friction
            var p = SpinnerPhysics(angle: 0, velocity: 20)
            for _ in 0..<(2 * 60) { p.step(dt: 1.0 / 60, settings: settings) }
            return p.velocity
        }
        XCTAssertGreaterThan(coast(0.2), coast(1.0))
        XCTAssertGreaterThan(coast(1.0), coast(5.0))
        // One step at multiplier m removes m times the default deceleration (Coulomb + viscous).
        var low = SpinnerSettings(); low.friction = 2
        var a = SpinnerPhysics(angle: 0, velocity: 10), b = a
        a.step(dt: 0.01)
        b.step(dt: 0.01, settings: low)
        let removedDefault: Double = 10 - a.velocity
        let removedDoubled: Double = 10 - b.velocity
        let expectedRemoved: Double = 2 * removedDefault
        XCTAssertEqual(removedDoubled, expectedRemoved, accuracy: 1e-4)
    }

    func testPushStrengthScalesImpulse() {
        var s = SpinnerSettings(); s.pushStrength = 2
        var p = SpinnerPhysics()
        p.applyImpulse(1, now: 0, settings: s)
        let expectedVelocity: Double = 2 * SpinnerTuning.impulseGain
        XCTAssertEqual(p.velocity, expectedVelocity, accuracy: 1e-9)
    }

    func testTopSpeedSetting() {
        var s = SpinnerSettings(); s.topSpeed = 30
        var p = SpinnerPhysics()
        p.applyImpulse(10_000, now: 0, settings: s)
        XCTAssertEqual(p.velocity, 30)
        p.applyKick(500, topSpeed: 30)
        XCTAssertEqual(p.velocity, 30)
        var q = SpinnerPhysics(angle: 0, velocity: 100)
        q.step(dt: 0.01, settings: s)
        XCTAssertLessThanOrEqual(q.velocity, 30)
        var fast = SpinnerSettings(); fast.topSpeed = 100
        var r = SpinnerPhysics()
        r.applyImpulse(10_000, now: 0, settings: fast)
        XCTAssertEqual(r.velocity, 100)
    }

    func testDirectionLockOffLetsAnOpposingPushReverse() {
        var free = SpinnerSettings(); free.directionLock = false
        var p = SpinnerPhysics()
        p.applyImpulse(10, now: 0, settings: free)          // +15 rad/s
        p.applyImpulse(-20, now: 0.1, settings: free)       // -30 rad/s of push: passes through zero
        let expectedReversed: Double = 15 - 30
        XCTAssertEqual(p.velocity, expectedReversed, accuracy: 1e-9)
        XCTAssertEqual(p.lockoutDirection, 0)
        // With the lock the same sequence only brakes to rest.
        var q = SpinnerPhysics()
        q.applyImpulse(10, now: 0)
        q.applyImpulse(-20, now: 0.1)
        XCTAssertEqual(q.velocity, 0)
        XCTAssertNotEqual(q.lockoutDirection, 0)
    }

    func testNotchCountingMatchesRevolutions() {
        let saved = SpinnerTuning.detentStrength
        SpinnerTuning.detentStrength = 0
        defer { SpinnerTuning.detentStrength = saved }
        var p = SpinnerPhysics(angle: 0, velocity: 20)
        let startAngle = p.angle
        let n = run(&p, seconds: 2)
        let expected = (p.angle - startAngle) / (2 * Double.pi) * Double(SpinnerTuning.beadCount)
        XCTAssertEqual(Double(n), expected, accuracy: 1.0)
        XCTAssertGreaterThan(n, 0)
    }

    func testVisualizerAdvancesStateAndEmitsNoVertices() {
        let viz = SpinnerVisualizer()
        viz.advance(dt: 1.0 / 60, impulse: 5)
        XCTAssertGreaterThan(viz.physics.velocity, 0)
        let u = viz.makeUniforms(offsetX: 0.1, offsetY: -0.2)
        XCTAssertEqual(u.velocity, Float(viz.physics.velocity))
        XCTAssertEqual(u.metal, Int32(SpinnerSettings().metal.index))
        SpinnerInput.shared.pendingImpulse = 0
        let frame = AudioFrame(bands: [0], bandPeaks: [0], waveform: [0], rms: 0, peak: 0, timestamp: 0)
        XCTAssertTrue(viz.makeVertices(frame: frame, settings: .defaults, aspect: 2).isEmpty)
    }
}
