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

import XCTest
@testable import MacVisualizerCore

final class SpinnerHubRollTests: XCTestCase {
    private let deg = Double.pi / 180

    /// Angle in degrees between two directions' headings, wrapped to [-180, 180].
    private func wrapped(_ a: Double, _ b: Double) -> Double {
        var d = (a - b) / deg
        while d > 180 { d -= 360 }
        while d < -180 { d += 360 }
        return d
    }

    /// Angle (degrees) of the on-screen mark-up direction from screen-up (0 = upright).
    private func tilt(pitch: Double, yaw: Double, roll: Double) -> Double {
        let up = SpinnerHubRoll.screenUp(pitch: pitch, yaw: yaw, roll: roll)
        return atan2(up.x, up.y) / deg
    }

    private func det(_ pitch: Double, _ yaw: Double) -> Double {
        SpinnerOrientation.frontNormalZ(pitch: pitch, yaw: yaw)
    }

    func testFaceOnFrontRollIsZero() {
        let r = SpinnerHubRoll.rolls(pitch: 0, yaw: 0, previous: nil)
        XCTAssertEqual(r.front, 0, accuracy: 1e-12)
        XCTAssertEqual(tilt(pitch: 0, yaw: 0, roll: r.front), 0, accuracy: 1e-9)
    }

    func testBackMarkUprightWhenTurnedOverAboutHorizontalAxis() {
        let r = SpinnerHubRoll.rolls(pitch: Double.pi, yaw: 0, previous: nil)
        XCTAssertEqual(tilt(pitch: Double.pi, yaw: 0, roll: r.back), 0, accuracy: 1e-6)
        let up = SpinnerHubRoll.screenUp(pitch: Double.pi, yaw: 0, roll: r.back)
        XCTAssertGreaterThan(up.y, 0.99)
    }

    func testBackMarkUprightWhenTurnedOverAboutVerticalAxis() {
        let r = SpinnerHubRoll.rolls(pitch: 0, yaw: Double.pi, previous: nil)
        XCTAssertEqual(tilt(pitch: 0, yaw: Double.pi, roll: r.back), 0, accuracy: 1e-6)
        XCTAssertEqual(r.back, 0, accuracy: 1e-9)   // already upright: the back texture is authored for this view
    }

    func testFrontMarkUprightAtPitchAndYawBothTurned() {
        let r = SpinnerHubRoll.rolls(pitch: Double.pi, yaw: Double.pi, previous: nil)
        XCTAssertEqual(tilt(pitch: Double.pi, yaw: Double.pi, roll: r.front), 0, accuracy: 1e-6)
    }

    func testTiltedPoseIsUprightWithinSmallAngle() {
        let pitchA: Double = 45 * deg
        let yawA: Double = 60 * deg
        let r = SpinnerHubRoll.rolls(pitch: pitchA, yaw: yawA, previous: nil)
        XCTAssertEqual(tilt(pitch: pitchA, yaw: yawA, roll: r.front), 0, accuracy: 0.5)
        let pitchB: Double = 225 * deg
        let yawB: Double = -45 * deg
        let r2 = SpinnerHubRoll.rolls(pitch: pitchB, yaw: yawB, previous: nil)
        XCTAssertEqual(tilt(pitch: pitchB, yaw: yawB, roll: r2.back), 0, accuracy: 0.5)
    }

    func testEveryVisibleOrientationIsUpright() {
        var worst: Double = 0
        for p in stride(from: 0.0, to: 360.0, by: 15.0) {
            for y in stride(from: 0.0, to: 360.0, by: 15.0) {
                let pr: Double = p * deg
                let yw: Double = y * deg
                if abs(det(pr, yw)) < 0.05 { continue }
                let r = SpinnerHubRoll.rolls(pitch: pr, yaw: yw, previous: nil)
                let visible: Double = det(pr, yw) > 0 ? r.front : r.back
                worst = max(worst, abs(tilt(pitch: pr, yaw: yw, roll: visible)))
            }
        }
        XCTAssertLessThan(worst, 0.5)
    }

    func testExactlyEdgeOnKeepsPreviousRoll() {
        let kept = SpinnerHubRoll.rolls(pitch: Double.pi / 2, yaw: 0, previous: (front: 0.7, back: -1.2))
        XCTAssertEqual(kept.front, 0.7)
        XCTAssertEqual(kept.back, -1.2)
        let kept2 = SpinnerHubRoll.rolls(pitch: 0, yaw: -Double.pi / 2, previous: (front: 0.3, back: 0.3))
        XCTAssertEqual(kept2.front, 0.3)
        let fresh = SpinnerHubRoll.rolls(pitch: Double.pi / 2, yaw: 0, previous: nil)
        XCTAssertTrue(fresh.front.isFinite && fresh.back.isFinite)
    }

    /// Roll changes continuously while a face is visible; a jump may happen only where the face is edge-on.
    private func assertContinuous(_ pitchOf: (Double) -> Double, _ yawOf: (Double) -> Double, label: String) {
        var prevRoll: Double?
        var prevDet: Double = 0
        var havePrev = false
        var previousPair: (front: Double, back: Double)?
        for step in 0...720 {
            let t: Double = Double(step) * 0.5
            let pr: Double = pitchOf(t) * deg
            let yw: Double = yawOf(t) * deg
            let r = SpinnerHubRoll.rolls(pitch: pr, yaw: yw, previous: previousPair)
            previousPair = r
            let d: Double = det(pr, yw)
            let roll: Double = r.front
            if let prev = prevRoll, havePrev {
                let jump: Double = abs(wrapped(roll, prev))
                let crossed: Bool = (d > 0) != (prevDet > 0)
                let nearEdge: Bool = min(abs(d), abs(prevDet)) < 0.03
                if jump > 12 {
                    XCTAssertTrue(crossed || nearEdge, "\(label): roll jumped \(jump) deg at t=\(t), det \(d)")
                }
            }
            prevRoll = roll
            prevDet = d
            havePrev = true
        }
    }

    func testRollIsContinuousOverPitchSweeps() {
        for yawFixed in [0.0, 20.0, 45.0, 75.0, 135.0, 200.0, 300.0] {
            assertContinuous({ (t: Double) -> Double in t }, { (_: Double) -> Double in yawFixed }, label: "pitch sweep, yaw \(yawFixed)")
        }
    }

    func testRollIsContinuousOverYawSweeps() {
        for pitchFixed in [0.0, 20.0, 45.0, 75.0, 135.0, 200.0, 300.0] {
            assertContinuous({ (_: Double) -> Double in pitchFixed }, { (t: Double) -> Double in t }, label: "yaw sweep, pitch \(pitchFixed)")
        }
    }

    func testOrientationPublishesHubRollAsItEases() {
        var o = SpinnerOrientation()
        XCTAssertEqual(o.hubRoll, 0, accuracy: 1e-12)
        o.set(pitch: Double.pi, yaw: 0)
        XCTAssertEqual(abs(wrapped(o.hubRoll, Double.pi)), 0, accuracy: 1e-6)
        o.set(pitch: 0, yaw: 0)
        XCTAssertEqual(o.hubRoll, 0, accuracy: 1e-9)
    }
}
