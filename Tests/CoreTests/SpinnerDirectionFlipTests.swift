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

// Direction lock and the two-sided (flip) tilt.
final class SpinnerDirectionFlipTests: XCTestCase {
    private let g = SpinnerTuning.impulseGain

    // MARK: direction lock

    func testOpposingImpulseStopsAtExactlyZeroWithoutReversing() {
        var p = SpinnerPhysics(angle: 0, velocity: 3)
        p.applyImpulse(-100, now: 1)
        XCTAssertEqual(p.velocity, 0)
        var q = SpinnerPhysics(angle: 0, velocity: -3)
        q.applyImpulse(100, now: 1)
        XCTAssertEqual(q.velocity, 0)
    }

    func testPartialOpposingImpulseBrakesOnly() {
        var p = SpinnerPhysics(angle: 0, velocity: 30)
        p.applyImpulse(-2, now: 1)
        XCTAssertEqual(p.velocity, 30 - 2 * g, accuracy: 1e-9)
        XCTAssertGreaterThan(p.velocity, 0)
    }

    func testOpposingImpulsesIgnoredDuringLockout() {
        var p = SpinnerPhysics(angle: 0, velocity: 3)
        p.applyImpulse(-100, now: 1.0)          // stops
        p.applyImpulse(-5, now: 1.05)           // ignored
        p.applyImpulse(-5, now: 1.30)           // ignored (each input restarts the quiet period)
        p.applyImpulse(-5, now: 1.60)           // 0.30 s after the last input: still locked
        XCTAssertEqual(p.velocity, 0)
    }

    func testSameDirectionStartsAfterQuietLockout() {
        var p = SpinnerPhysics(angle: 0, velocity: 3)
        p.applyImpulse(-100, now: 1.0)
        p.applyImpulse(-5, now: 1.0 + SpinnerTuning.restartLockoutSeconds + 0.01)
        XCTAssertEqual(p.velocity, -5 * g, accuracy: 1e-9)
    }

    func testOriginalDirectionDuringLockoutRestartsImmediately() {
        var p = SpinnerPhysics(angle: 0, velocity: 3)
        p.applyImpulse(-100, now: 1.0)
        p.applyImpulse(2, now: 1.1)
        XCTAssertEqual(p.velocity, 2 * g, accuracy: 1e-9)
        // Lockout is gone: the opposing direction now only brakes.
        p.applyImpulse(-1, now: 1.12)
        XCTAssertEqual(p.velocity, 2 * g - g, accuracy: 1e-9)
    }

    func testFromNaturalRestEitherDirectionStartsAtOnce() {
        var p = SpinnerPhysics()
        p.applyImpulse(1, now: 5)
        XCTAssertEqual(p.velocity, g, accuracy: 1e-9)
        var q = SpinnerPhysics()
        q.applyImpulse(-1, now: 5)
        XCTAssertEqual(q.velocity, -g, accuracy: 1e-9)
        // Friction brought a spinner to rest: the other way starts at once, no lockout.
        var r = SpinnerPhysics(angle: 0, velocity: 0.03)
        r.applyImpulse(-1, now: 5)
        XCTAssertEqual(r.velocity, 0.03 - g, accuracy: 1e-9)
        var f = SpinnerPhysics(angle: 0, velocity: 2)
        for _ in 0..<(120 * 60) { f.step(dt: 1.0 / 60) }
        XCTAssertEqual(f.velocity, 0)
        f.applyImpulse(-1, now: 5)
        XCTAssertEqual(f.velocity, -g, accuracy: 1e-9)
    }

    func testSameDirectionImpulsesAddAndRespectMaxSpeed() {
        var p = SpinnerPhysics(angle: 0, velocity: 2)
        p.applyImpulse(1, now: 1)
        XCTAssertEqual(p.velocity, 2 + g, accuracy: 1e-9)
        p.applyImpulse(10_000, now: 1.1)
        XCTAssertEqual(p.velocity, SpinnerTuning.maxSpeed)
        var q = SpinnerPhysics(angle: 0, velocity: -2)
        q.applyImpulse(-10_000, now: 1)
        XCTAssertEqual(q.velocity, -SpinnerTuning.maxSpeed)
    }

    func testLockoutConstant() {
        XCTAssertEqual(SpinnerTuning.restartLockoutSeconds, 0.35)
    }

    func testVisualizerSuppliesClockToLock() {
        let viz = SpinnerVisualizer()
        viz.advance(dt: 1.0 / 60, impulse: 1, now: 10)
        XCTAssertGreaterThan(viz.physics.velocity, 0)
        viz.advance(dt: 1.0 / 60, impulse: -1000, now: 10.02)   // brakes to zero
        XCTAssertEqual(viz.physics.velocity, 0)
        viz.advance(dt: 1.0 / 60, impulse: -1, now: 10.05)      // locked out
        XCTAssertEqual(viz.physics.velocity, 0)
    }

    // MARK: flip tilt






    func testFacingAndScrollSignForNegativeUnwrappedTilt() {
        let d = Double.pi / 180
        // -25 = 335 front; -90 = 270 (back for scroll, front for isBackFacing); -118 = 242 back; -180 back; -270 = 90
        XCTAssertFalse(SpinnerTilt.isBackFacing(radians: -25 * d)); XCTAssertFalse(SpinnerTilt.scrollIsBack(radians: -25 * d))
        XCTAssertFalse(SpinnerTilt.isBackFacing(radians: -90 * d)); XCTAssertTrue(SpinnerTilt.scrollIsBack(radians: -90 * d))
        XCTAssertTrue(SpinnerTilt.isBackFacing(radians: -118 * d)); XCTAssertTrue(SpinnerTilt.scrollIsBack(radians: -118 * d))
        XCTAssertTrue(SpinnerTilt.isBackFacing(radians: -180 * d)); XCTAssertTrue(SpinnerTilt.scrollIsBack(radians: -180 * d))
        XCTAssertFalse(SpinnerTilt.isBackFacing(radians: -270 * d)); XCTAssertFalse(SpinnerTilt.scrollIsBack(radians: -270 * d))
    }

    func testUniformTiltIsNormalizedToOneTurn() {
        let viz = SpinnerVisualizer()
        viz.debugFreeze(angle: 0, velocity: 0, tilt: 2 * Double.pi + 0.5)
        XCTAssertEqual(viz.makeUniforms(offsetX: 0, offsetY: 0).tilt, 0.5, accuracy: 1e-5)
    }

    func testScrollImpulseNegatedWhenBackFacing() {
        let front = SpinnerVisualizer()
        front.advance(dt: 1.0 / 60, impulse: 1, now: 1)
        XCTAssertGreaterThan(front.physics.velocity, 0)
        let back = SpinnerVisualizer()
        back.debugFreeze(angle: 0, velocity: 0, tilt: Double.pi)
        XCTAssertTrue(back.isBackFacing)
        back.advance(dt: 1.0 / 60, impulse: 1, now: 1)
        XCTAssertLessThan(back.physics.velocity, 0)
    }

    // Side-view presets and scroll sign at exactly 90 / 270.
    func testScrollSignUsesMostRecentSideAtEdgeOn() {
        let d = Double.pi / 180
        XCTAssertFalse(SpinnerTilt.scrollIsBack(radians: 90 * d))     // arrived from the front
        XCTAssertTrue(SpinnerTilt.scrollIsBack(radians: 270 * d))     // arrived from the back
        XCTAssertFalse(SpinnerTilt.scrollIsBack(radians: 89.9 * d))
        XCTAssertTrue(SpinnerTilt.scrollIsBack(radians: 90.1 * d))
        XCTAssertTrue(SpinnerTilt.scrollIsBack(radians: 269.9 * d))
        XCTAssertFalse(SpinnerTilt.scrollIsBack(radians: 270.1 * d))
        XCTAssertFalse(SpinnerTilt.scrollIsBack(radians: 0))
        XCTAssertTrue(SpinnerTilt.scrollIsBack(radians: 180 * d))
        for deg in [90.0, 270.0] {
            let viz = SpinnerVisualizer()
            viz.debugFreeze(angle: 0, velocity: 0, tilt: deg * d)
            // Resting exactly at the pose: the sign does not change between impulses.
            var signs: [Bool] = []
            for i in 0..<5 {
                let v0 = viz.physics.velocity
                viz.advance(dt: 1.0 / 60, impulse: 1, now: 100 + Double(i) * 0.5)
                signs.append(viz.physics.velocity > v0)
            }
            XCTAssertEqual(Set(signs).count, 1, "tilt \(deg)")
            XCTAssertEqual(signs[0], deg == 270 ? false : true)
        }
    }




}
