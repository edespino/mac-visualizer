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

final class SpinnerOrientationTests: XCTestCase {
    private let deg = Double.pi / 180

    private func settle(_ o: inout SpinnerOrientation, seconds: Double = 4) {
        let frames = Int(seconds * 60)
        for _ in 0..<frames { o.ease(dt: 1.0 / 60, timeConstant: SpinnerTuning.tiltTimeConstant) }
    }

    // MARK: uniform steps

    func testStepIsOneUniformTuningConstant() {
        let step: Double = Double(SpinnerSettings().rotationStepDegrees)
        XCTAssertEqual(step, 15)
        XCTAssertEqual(360 / step, 24)
        // The 24 stops include exact face-on (0), edge-on (90, 270) and back (180) poses.
        var stops: [Double] = []
        for i in 0..<24 { stops.append(Double(i) * 15) }
        XCTAssertTrue(stops.contains(0))
        XCTAssertTrue(stops.contains(90))
        XCTAssertTrue(stops.contains(180))
        XCTAssertTrue(stops.contains(270))
    }

    func testPitchStepsBothWaysLandOnTheRightTargets() {
        var o = SpinnerOrientation()
        let step = 15 * deg
        o.step(pitch: 1, stepRadians: step)
        o.step(pitch: 1, stepRadians: step)
        XCTAssertEqual(o.pitchTarget, 30 * deg, accuracy: 1e-12)
        XCTAssertEqual(o.yawTarget, 0)
        o.step(pitch: -1, stepRadians: step)
        XCTAssertEqual(o.pitchTarget, 15 * deg, accuracy: 1e-12)
        o.step(pitch: -1, stepRadians: step)
        o.step(pitch: -1, stepRadians: step)
        XCTAssertEqual(o.pitchTarget, -15 * deg, accuracy: 1e-12)   // unwrapped: goes negative, never jumps
        settle(&o)
        XCTAssertEqual(o.pitch, -15 * deg, accuracy: 1e-3)
    }

    func testYawStepsBothWaysLandOnTheRightTargets() {
        var o = SpinnerOrientation()
        let step = 15 * deg
        for _ in 0..<3 { o.step(yaw: 1, stepRadians: step) }
        XCTAssertEqual(o.yawTarget, 45 * deg, accuracy: 1e-12)
        XCTAssertEqual(o.pitchTarget, 0)
        for _ in 0..<5 { o.step(yaw: -1, stepRadians: step) }
        XCTAssertEqual(o.yawTarget, -30 * deg, accuracy: 1e-12)
        settle(&o)
        XCTAssertEqual(o.yaw, -30 * deg, accuracy: 1e-3)
    }

    func testMixedStepsAreIndependentPerAxis() {
        var o = SpinnerOrientation()
        let step = 15 * deg
        o.step(pitch: 1, stepRadians: step)
        o.step(yaw: -1, stepRadians: step)
        o.step(pitch: 1, stepRadians: step)
        o.step(yaw: 1, stepRadians: step)
        o.step(yaw: 1, stepRadians: step)
        XCTAssertEqual(o.pitchTarget, 30 * deg, accuracy: 1e-12)
        XCTAssertEqual(o.yawTarget, 15 * deg, accuracy: 1e-12)
    }

    func testFullTurnOf24ForwardStepsLandsOnOneTurn() {
        var o = SpinnerOrientation()
        let step = 15 * deg
        var last = o.pitch
        for _ in 0..<24 {
            o.step(pitch: 1, stepRadians: step)
            for _ in 0..<(60 * 3) {
                o.ease(dt: 1.0 / 60, timeConstant: SpinnerTuning.tiltTimeConstant)
                XCTAssertGreaterThanOrEqual(o.pitch, last - 1e-12)   // never moves the wrong way
                last = o.pitch
            }
        }
        let turn: Double = 2 * Double.pi
        XCTAssertEqual(o.pitch, turn, accuracy: 1e-3)
        let wrappedDistance: Double = min(o.normalizedPitch, turn - o.normalizedPitch)
        XCTAssertEqual(wrappedDistance, 0, accuracy: 1e-3)
    }

    // MARK: facing

    func testFacesViewerFrontForCombinations() {
        func front(_ p: Double, _ y: Double) -> Bool {
            var o = SpinnerOrientation()
            o.set(pitch: p * deg, yaw: y * deg)
            return o.facesViewerFront
        }
        XCTAssertTrue(front(0, 0))
        XCTAssertFalse(front(180, 0))
        XCTAssertFalse(front(0, 180))
        XCTAssertTrue(front(180, 180))
        XCTAssertTrue(front(45, 45))
        XCTAssertFalse(front(135, 0))
        XCTAssertFalse(front(0, 120))
        XCTAssertTrue(front(60, -45))
        XCTAssertFalse(front(135, 45))
    }

    func testEdgeOnKeepsTheLastFaceShown() {
        // Eased from the front through yaw 90 (edge-on): stays front until the face clearly turns.
        var o = SpinnerOrientation()
        o.set(pitch: 0, yaw: 80 * deg)
        XCTAssertTrue(o.facesViewerFront)
        o.nudge(pitchBy: 0, yawBy: 10 * deg)             // exactly 90: edge-on (cos is ~6e-17)
        XCTAssertTrue(o.facesViewerFront)
        o.nudge(pitchBy: 0, yawBy: 10 * deg)             // 100: back
        XCTAssertFalse(o.facesViewerFront)
        o.nudge(pitchBy: 0, yawBy: -10 * deg)            // back at exactly 90: still back, arrived from the back
        XCTAssertFalse(o.facesViewerFront)
        o.nudge(pitchBy: 0, yawBy: -10 * deg)            // 80: front again
        XCTAssertTrue(o.facesViewerFront)
    }

    func testNormalZFormula() {
        XCTAssertEqual(SpinnerOrientation.frontNormalZ(pitch: 0, yaw: 0), 1, accuracy: 1e-12)
        XCTAssertEqual(SpinnerOrientation.frontNormalZ(pitch: 60 * deg, yaw: 60 * deg), 0.25, accuracy: 1e-12)
    }

    // MARK: easing, nudge, reset

    func testEasingReachesTargetWithoutOvershootOnBothAxes() {
        var o = SpinnerOrientation()
        o.step(pitch: 1, stepRadians: 90 * deg)
        o.step(yaw: -1, stepRadians: 60 * deg)
        var lastPitch = o.pitch
        var lastYaw = o.yaw
        for _ in 0..<(60 * 4) {
            o.ease(dt: 1.0 / 60, timeConstant: SpinnerTuning.tiltTimeConstant)
            XCTAssertLessThanOrEqual(o.pitch, o.pitchTarget + 1e-12)
            XCTAssertGreaterThanOrEqual(o.pitch, lastPitch)
            XCTAssertGreaterThanOrEqual(o.yaw, o.yawTarget - 1e-12)
            XCTAssertLessThanOrEqual(o.yaw, lastYaw)
            lastPitch = o.pitch
            lastYaw = o.yaw
        }
        let pitchTolerance: Double = 0.01 * 90 * deg
        let yawTolerance: Double = 0.01 * 60 * deg
        XCTAssertEqual(o.pitch, 90 * deg, accuracy: pitchTolerance)
        XCTAssertEqual(o.yaw, -60 * deg, accuracy: yawTolerance)
    }

    func testNudgeMovesCurrentAndTargetTogetherWithNoLag() {
        var o = SpinnerOrientation()
        o.nudge(pitchBy: 10 * deg, yawBy: -20 * deg)
        XCTAssertEqual(o.pitch, 10 * deg, accuracy: 1e-12)
        XCTAssertEqual(o.yaw, -20 * deg, accuracy: 1e-12)
        XCTAssertEqual(o.pitchTarget, o.pitch)
        XCTAssertEqual(o.yawTarget, o.yaw)
        o.ease(dt: 1.0 / 60, timeConstant: SpinnerTuning.tiltTimeConstant)
        XCTAssertEqual(o.pitch, 10 * deg, accuracy: 1e-12)          // nothing left to ease: stays where it was released
    }

    func testResetReturnsToZeroByTheShortestWay() {
        var o = SpinnerOrientation()
        o.nudge(pitchBy: 350 * deg, yawBy: -100 * deg)
        o.reset()
        XCTAssertEqual(o.pitchTarget, 360 * deg, accuracy: 1e-9)     // 350 -> 360 (10 degrees), not back through 350
        XCTAssertEqual(o.yawTarget, 0, accuracy: 1e-9)               // -100 -> 0 (100 degrees), not -360
        var lastPitch = o.pitch
        for _ in 0..<(60 * 5) {
            o.ease(dt: 1.0 / 60, timeConstant: SpinnerTuning.tiltTimeConstant)
            XCTAssertGreaterThanOrEqual(o.pitch, lastPitch)
            lastPitch = o.pitch
        }
        let turn: Double = 2 * Double.pi
        let distanceToTurn: Double = abs(o.normalizedPitch - turn)
        XCTAssertTrue(o.normalizedPitch == 0 || distanceToTurn < 1e-3)
        XCTAssertEqual(o.yaw, 0, accuracy: 1e-3)
        XCTAssertTrue(o.facesViewerFront)
    }

    // MARK: visualizer integration

    func testRequestsStepEveryAxisAndReset() {
        let viz = SpinnerVisualizer()
        var r = SpinnerOrientationRequests()
        r.pitchSteps = 2
        r.yawSteps = -3
        viz.apply(r)
        XCTAssertEqual(viz.orientation.pitchTarget, 30 * deg, accuracy: 1e-12)
        XCTAssertEqual(viz.orientation.yawTarget, -45 * deg, accuracy: 1e-12)
        var reset = SpinnerOrientationRequests()
        reset.reset = true
        viz.apply(reset)
        XCTAssertEqual(viz.orientation.pitchTarget, 0, accuracy: 1e-12)
        XCTAssertEqual(viz.orientation.yawTarget, 0, accuracy: 1e-12)
        XCTAssertTrue(SpinnerOrientationRequests().isEmpty)
        XCTAssertFalse(r.isEmpty)
    }

    func testScrollDirectionFollowsFaceForYawToo() {
        let front = SpinnerVisualizer()
        front.advance(dt: 1.0 / 60, impulse: 1, now: 1)
        XCTAssertGreaterThan(front.physics.velocity, 0)
        let yawedBack = SpinnerVisualizer()
        yawedBack.debugFreeze(angle: 0, velocity: 0, tilt: 0, yaw: Double.pi)
        yawedBack.advance(dt: 1.0 / 60, impulse: 1, now: 1)
        XCTAssertLessThan(yawedBack.physics.velocity, 0)
        let bothBack = SpinnerVisualizer()
        bothBack.debugFreeze(angle: 0, velocity: 0, tilt: Double.pi, yaw: Double.pi)   // front again
        bothBack.advance(dt: 1.0 / 60, impulse: 1, now: 1)
        XCTAssertGreaterThan(bothBack.physics.velocity, 0)
    }

    func testInputDrainsOrientationRequestsOnce() {
        let input = SpinnerInput.shared
        _ = input.drainOrientation()
        input.pendingOrientation.pitchSteps += 1
        input.pendingOrientation.pitchSteps += 1
        input.pendingOrientation.dragYawRadians += 0.1
        let drained = input.drainOrientation()
        XCTAssertEqual(drained.pitchSteps, 2)
        XCTAssertEqual(drained.dragYawRadians, 0.1, accuracy: 1e-12)
        XCTAssertTrue(input.drainOrientation().isEmpty)
    }

    func testDragConstantAndUniformsCarryNormalizedPitch() {
        XCTAssertEqual(SpinnerTuning.dragDegreesPerPoint, 0.5)
        let viz = SpinnerVisualizer()
        viz.debugFreeze(angle: 0, velocity: 0, tilt: 2 * Double.pi + 0.5, yaw: 3)
        XCTAssertEqual(viz.makeUniforms(offsetX: 0, offsetY: 0).tilt, 0.5, accuracy: 1e-5)   // yaw is not sent to the shader
    }
}

final class SpinnerDragGestureTests: XCTestCase {
    func testMovementBelowThresholdIsHeldBackAndIsNotRotation() {
        var g = SpinnerDragGesture()
        let r = g.move(deltaX: 1, deltaY: 1, degreesPerPoint: 0.5)
        XCTAssertEqual(r.pitch, 0)
        XCTAssertEqual(r.yaw, 0)
        XCTAssertFalse(g.rotating)
    }

    func testCrossingThresholdReleasesHeldMovementOnce() {
        var g = SpinnerDragGesture()
        _ = g.move(deltaX: 3, deltaY: 0, degreesPerPoint: 0.5)
        let r = g.move(deltaX: 3, deltaY: 0, degreesPerPoint: 0.5)       // total 6 points
        XCTAssertTrue(g.rotating)
        let expectedYaw: Double = -6 * 0.5 * Double.pi / 180
        XCTAssertEqual(r.yaw, expectedYaw, accuracy: 1e-12)
        XCTAssertEqual(r.pitch, 0, accuracy: 1e-12)
        let next = g.move(deltaX: 2, deltaY: 0, degreesPerPoint: 0.5)   // applied directly afterwards
        let expectedNext: Double = -1 * Double.pi / 180
        XCTAssertEqual(next.yaw, expectedNext, accuracy: 1e-12)
    }

    func testHalfADegreePerPointAndAxes() {
        var g = SpinnerDragGesture()
        let r = g.move(deltaX: 0, deltaY: 20, degreesPerPoint: SpinnerTuning.dragDegreesPerPoint)
        let expectedPitch: Double = -10 * Double.pi / 180
        XCTAssertEqual(r.pitch, expectedPitch, accuracy: 1e-12)  // down: top edge toward the viewer
        XCTAssertEqual(r.yaw, 0, accuracy: 1e-12)
    }

    func testQueuedStepsMoveTargetByNTimesStep() {
        var o = SpinnerOrientation()
        let step: Double = 15 * Double.pi / 180
        for _ in 0..<40 { o.step(pitch: 1, stepRadians: step) }
        XCTAssertEqual(o.pitchTarget, 40 * step, accuracy: 1e-9)
        o.ease(dt: 0.5, timeConstant: 0.35)
        XCTAssertLessThan(o.pitch, o.pitchTarget)
        XCTAssertGreaterThan(o.pitch, 0)
        for _ in 0..<600 { o.ease(dt: 1.0 / 60.0, timeConstant: 0.35) }
        XCTAssertEqual(o.pitch, 40 * step, accuracy: 1e-6)
    }

    func testResetOrFlipFromTiltedResets() {
        var o = SpinnerOrientation()
        o.set(pitch: 0.7, yaw: 0)
        o.resetOrFlip()
        XCTAssertEqual(o.pitchTarget, 0, accuracy: 1e-9)
    }

    func testResetOrFlipFromFrontFlipsToBackAndBack() {
        var o = SpinnerOrientation()
        o.resetOrFlip()
        XCTAssertEqual(o.pitchTarget, Double.pi, accuracy: 1e-9)
        o.resetOrFlip()
        XCTAssertEqual(o.pitchTarget, 2 * Double.pi, accuracy: 1e-9)
        XCTAssertEqual(o.yawTarget, 0, accuracy: 1e-9)
    }

    func testResetOrFlipMidResetAnimationFlips() {
        var o = SpinnerOrientation()
        o.set(pitch: 0.7, yaw: 0)
        o.resetOrFlip()                       // target -> 0, current still 0.7
        o.ease(dt: 0.05, timeConstant: 0.35)
        o.resetOrFlip()                       // target is face-on: flips
        XCTAssertEqual(o.pitchTarget, Double.pi, accuracy: 1e-9)
    }

    func testResetOrFlipWithYawResetsInsteadOfFlipping() {
        var o = SpinnerOrientation()
        o.set(pitch: 0, yaw: 0.5)
        o.resetOrFlip()
        XCTAssertEqual(o.pitchTarget, 0, accuracy: 1e-9)
        XCTAssertEqual(o.yawTarget, 0, accuracy: 1e-9)
    }

    func testResetOrFlipRequestIsNotEmpty() {
        var r = SpinnerOrientationRequests()
        XCTAssertTrue(r.isEmpty)
        r.resetOrFlip = true
        XCTAssertFalse(r.isEmpty)
    }

    func testResetOrFlipYawFromFrontFlipsYawAndChains() {
        var o = SpinnerOrientation()
        o.resetOrFlipYaw()
        XCTAssertEqual(o.yawTarget, Double.pi, accuracy: 1e-9)
        XCTAssertEqual(o.pitchTarget, 0, accuracy: 1e-9)
        o.resetOrFlipYaw()
        XCTAssertEqual(o.yawTarget, 2 * Double.pi, accuracy: 1e-9)
    }

    func testMixedFlipChainKeepsFlipping() {
        var o = SpinnerOrientation()
        o.resetOrFlip()
        o.resetOrFlipYaw()
        XCTAssertEqual(o.pitchTarget, Double.pi, accuracy: 1e-9)
        XCTAssertEqual(o.yawTarget, Double.pi, accuracy: 1e-9)
        o.resetOrFlip()
        XCTAssertEqual(o.pitchTarget, 2 * Double.pi, accuracy: 1e-9)
        o.resetOrFlipYaw()
        XCTAssertEqual(o.yawTarget, 2 * Double.pi, accuracy: 1e-9)
    }

    func testResetOrFlipYawFromTiltedResets() {
        var o = SpinnerOrientation()
        o.set(pitch: 0.7, yaw: 0.3)
        o.resetOrFlipYaw()
        XCTAssertEqual(o.pitchTarget, 0, accuracy: 1e-9)
        XCTAssertEqual(o.yawTarget, 0, accuracy: 1e-9)
    }

    func testResetOrFlipYawRequestIsNotEmpty() {
        var r = SpinnerOrientationRequests()
        r.resetOrFlipYaw = true
        XCTAssertFalse(r.isEmpty)
    }
}
