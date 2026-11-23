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

final class TriWingCrystalTests: XCTestCase {
    func testGlancingIsZeroFaceOnAndGrowsWithTiltOnEitherFace() {
        XCTAssertEqual(TriWingCrystal.glancing(pitch: 0, yaw: 0), 0, accuracy: 1e-6)
        XCTAssertEqual(TriWingCrystal.glancing(pitch: Float.pi, yaw: 0), 0, accuracy: 1e-5)   // back face toward the viewer
        XCTAssertEqual(TriWingCrystal.glancing(pitch: 0, yaw: Float.pi), 0, accuracy: 1e-5)
        var prev: Float = 0
        for deg in stride(from: 0, through: 80, by: 10) {
            let g = TriWingCrystal.glancing(pitch: Float(deg) * Float.pi / 180, yaw: 0)
            XCTAssertGreaterThanOrEqual(g, prev)
            prev = g
        }
        XCTAssertEqual(TriWingCrystal.glancing(pitch: Float.pi / 2, yaw: 0), 1, accuracy: 1e-5)
    }

    func testSheenIsZeroFaceOnGrowsWithTiltAndStaysThin() {
        XCTAssertEqual(TriWingCrystal.sheenOpacity(pitch: 0, yaw: 0), 0, accuracy: 1e-6)
        XCTAssertEqual(TriWingCrystal.sheenOpacity(pitch: Float.pi, yaw: 0), 0, accuracy: 1e-5)
        var prev: Float = 0
        for deg in stride(from: 0, through: 89, by: 5) {
            let v = TriWingCrystal.sheenOpacity(pitch: Float(deg) * Float.pi / 180, yaw: 0)
            XCTAssertGreaterThanOrEqual(v, prev)
            prev = v
        }
        // Thin at moderate tilt, still under the shadow pass's silhouette threshold (0.30) edge-on.
        XCTAssertLessThan(TriWingCrystal.sheenOpacity(pitch: 35 * Float.pi / 180, yaw: 0), 0.04)
        XCTAssertLessThan(TriWingCrystal.sheenOpacity(pitch: 60 * Float.pi / 180, yaw: 0), 0.10)
        XCTAssertLessThan(TriWingCrystal.sheenOpacity(pitch: Float.pi / 2, yaw: 0), 0.30)
    }

    func testMirrorPoseMatchesKeyLightHalfVector() {
        let h = TriWingCrystal.mirrorNormal
        let len = (h.x * h.x + h.y * h.y + h.z * h.z).squareRoot()
        XCTAssertEqual(len, 1, accuracy: 1e-5)
        // The half vector between the key light and the view axis (+z).
        let l = TriWingCrystal.keyLight
        let hx = l.x, hy = l.y, hz = l.z + 1
        let hl = (hx * hx + hy * hy + hz * hz).squareRoot()
        XCTAssertEqual(h.x, hx / hl, accuracy: 1e-5)
        XCTAssertEqual(h.y, hy / hl, accuracy: 1e-5)
        XCTAssertEqual(h.z, hz / hl, accuracy: 1e-5)
        for face in 0...1 {
            let pose = TriWingCrystal.mirrorPose(face: face)
            XCTAssertEqual(TriWingCrystal.ghostStrength(pitch: pose.pitch, yaw: pose.yaw, face: face), 1, accuracy: 1e-4)
        }
    }

    func testGhostIsZeroFaceOnAndFarAwayAndPeaksAtTheMirrorPose() {
        XCTAssertEqual(TriWingCrystal.ghostStrength(pitch: 0, yaw: 0, face: 0), 0, accuracy: 1e-6)
        XCTAssertEqual(TriWingCrystal.ghostStrength(pitch: Float.pi, yaw: 0, face: 1), 0, accuracy: 1e-6)
        XCTAssertEqual(TriWingCrystal.ghostStrength(pitch: 1.3, yaw: 0.9, face: 0), 0, accuracy: 1e-6)
        let pose = TriWingCrystal.mirrorPose(face: 0)
        let peak = TriWingCrystal.ghostStrength(pitch: pose.pitch, yaw: pose.yaw, face: 0)
        let near = TriWingCrystal.ghostStrength(pitch: pose.pitch + 0.1, yaw: pose.yaw, face: 0)
        let farther = TriWingCrystal.ghostStrength(pitch: pose.pitch + 0.2, yaw: pose.yaw, face: 0)
        XCTAssertGreaterThan(peak, near)
        XCTAssertGreaterThan(near, farther)
        XCTAssertGreaterThan(farther, 0)
        // The back face reflects at a different pose; the front's peak pose gives the back face nothing.
        XCTAssertEqual(TriWingCrystal.ghostStrength(pitch: pose.pitch, yaw: pose.yaw, face: 1), 0, accuracy: 1e-6)
    }

    func testGhostStrengthIsContinuousAndBounded() {
        let pose = TriWingCrystal.mirrorPose(face: 0)
        var prev = TriWingCrystal.ghostStrength(pitch: pose.pitch - 0.6, yaw: pose.yaw, face: 0)
        for k in 1...240 {
            let p = pose.pitch - 0.6 + Float(k) * 0.005
            let v = TriWingCrystal.ghostStrength(pitch: p, yaw: pose.yaw, face: 0)
            XCTAssertLessThanOrEqual(v, 1.0001)
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThan(abs(v - prev), 0.08)
            prev = v
        }
    }

    func testGhostOffsetIsZeroAtThePeakAndMovesWithTiltOnBothFaces() {
        for face in 0...1 {
            let pose = TriWingCrystal.mirrorPose(face: face)
            let o = TriWingCrystal.ghostOffset(pitch: pose.pitch, yaw: pose.yaw, face: face)
            XCTAssertEqual(o.x, 0, accuracy: 1e-4)
            XCTAssertEqual(o.y, 0, accuracy: 1e-4)
        }
        // Screen-space image position: tilting the normal toward +y moves the image toward -y (on the front face).
        let pose = TriWingCrystal.mirrorPose(face: 0)
        let a = TriWingCrystal.ghostOffset(pitch: pose.pitch + 0.1, yaw: pose.yaw, face: 0)
        let b = TriWingCrystal.ghostOffset(pitch: pose.pitch - 0.1, yaw: pose.yaw, face: 0)
        XCTAssertLessThan(a.y, 0)
        XCTAssertGreaterThan(b.y, 0)
        // Within +-0.4 crystal diameters wherever the ghost is visible.
        for p in stride(from: -1.2 as Float, through: 1.2, by: 0.05) {
            for y in stride(from: -1.2 as Float, through: 1.2, by: 0.05) {
                if TriWingCrystal.ghostStrength(pitch: p, yaw: y, face: 0) > 0.01 {
                    let o = TriWingCrystal.ghostOffset(pitch: p, yaw: y, face: 0)
                    XCTAssertLessThan(abs(o.x), 0.4)
                    XCTAssertLessThan(abs(o.y), 0.4)
                }
            }
        }
    }
}
