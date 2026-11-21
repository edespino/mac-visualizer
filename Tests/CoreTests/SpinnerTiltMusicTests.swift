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

// Spinner uniform layout, hub finish cycling, and the music-as-force drive (orientation is covered in SpinnerOrientationTests).
final class SpinnerTiltMusicTests: XCTestCase {
    // MARK: tilt

    func testUniformsAre68Bytes() {
        XCTAssertEqual(MemoryLayout<SpinnerUniforms>.stride, 68)
        XCTAssertEqual(MemoryLayout<SpinnerUniforms>.size, 68)
    }

    func testUniformsCarrySettings() {
        var s = SpinnerSettings()
        s.roomLight = 0.5; s.glowBrightness = 1.5; s.spinBlur = 0.25
        s.shadowDarkness = 0.7; s.shadowSpread = 2; s.shadowDistance = 0.4
        s.size = 0.8; s.metal = .brass; s.hubFinish = .raised
        let u = SpinnerVisualizer().makeUniforms(offsetX: 0, offsetY: 0, settings: s)
        XCTAssertEqual(u.roomLight, 0.5)
        XCTAssertEqual(u.glowBrightness, 1.5)
        XCTAssertEqual(u.spinBlur, 0.25)
        XCTAssertEqual(u.shadowDarkness, 0.7)
        XCTAssertEqual(u.shadowSpread, 2)
        XCTAssertEqual(u.shadowDistance, 0.4)
        XCTAssertEqual(u.zoom, 0.8, accuracy: 1e-6)
        XCTAssertEqual(u.metal, 1)
        XCTAssertEqual(u.hubFinish, 1)
        let d = SpinnerVisualizer().makeUniforms(offsetX: 0, offsetY: 0)
        XCTAssertEqual(d.zoom, 1)
        XCTAssertEqual(d.shadowDarkness, 0.48)
        XCTAssertEqual(d.roomLight, 1)
    }

    func testVisualizerReadsMotionFromSettings() {
        var s = SpinnerSettings(); s.pushStrength = 3; s.topSpeed = 40
        let viz = SpinnerVisualizer()
        viz.advance(dt: 0, impulse: 1, spinner: s)
        let expectedPush: Double = 3 * SpinnerTuning.impulseGain
        XCTAssertEqual(viz.physics.velocity, expectedPush, accuracy: 1e-9)
        viz.advance(dt: 0, impulse: 10_000, spinner: s)
        XCTAssertEqual(viz.physics.velocity, 40)
    }

    func testRotationStepFollowsSettings() {
        let viz = SpinnerVisualizer()
        var req = SpinnerOrientationRequests()
        req.pitchSteps = 2
        viz.apply(req, stepDegrees: 30)
        let sixtyDegrees: Double = 60 * Double.pi / 180
        XCTAssertEqual(viz.orientation.pitchTarget, sixtyDegrees, accuracy: 1e-12)
        let viz2 = SpinnerVisualizer()
        viz2.apply(req)
        let thirtyDegrees: Double = 30 * Double.pi / 180
        XCTAssertEqual(viz2.orientation.pitchTarget, thirtyDegrees, accuracy: 1e-12)
    }

    func testHubFinishCycleWraps() {
        XCTAssertEqual(SpinnerHubFinish.lit.next, .raised)
        XCTAssertEqual(SpinnerHubFinish.raised.next, .engraved)
        XCTAssertEqual(SpinnerHubFinish.engraved.next, .lit)
        XCTAssertEqual(SpinnerHubFinish.engraved.displayName, "Engraved")
        XCTAssertEqual(SpinnerHubFinish.lit.displayName, "Lit")
        XCTAssertEqual(SpinnerHubFinish.raised.displayName, "Raised")
        var s = SpinnerSettings(); s.hubFinish = .raised
        let u = SpinnerVisualizer().makeUniforms(offsetX: 0, offsetY: 0, settings: s)
        XCTAssertEqual(u.hubFinish, 1)
    }

    // MARK: music

    private func runSteady(_ d: inout SpinnerMusicDrive, rms: Float, seconds: Double) {
        for _ in 0..<Int(seconds * 60) {
            _ = d.update(rms: rms, bassEnergy: 0, dt: 1.0 / 60, velocity: 0, mode: .both)
        }
    }

    func testEnumWrapAndNames() {
        var mode: SpinnerMusicMode = .off
        var seen: [SpinnerMusicMode] = []
        for _ in 0..<SpinnerMusicMode.allCases.count {
            mode = mode.next
            seen.append(mode)
        }
        XCTAssertEqual(seen, [.sustain, .kick, .both, .off])
        XCTAssertEqual(SpinnerMusicMode.off.displayName, "Off")
        XCTAssertEqual(SpinnerMusicMode.both.displayName, "Sustain + Kick")
    }

    func testDefaultsAreOffAndConstants() {
        XCTAssertEqual(SpinnerSettings().musicMode, .off)
        XCTAssertEqual(SpinnerSettings().musicSustain, 0.85)
        XCTAssertEqual(SpinnerSettings().musicKick, 2.0)
        XCTAssertEqual(SpinnerTuning.musicLevelAttack, 0.08)
        XCTAssertEqual(SpinnerTuning.musicLevelRelease, 0.6)
    }

    func testLevelIsAmplitudeInvariant() {
        var quiet = SpinnerMusicDrive(), loud = SpinnerMusicDrive()
        runSteady(&quiet, rms: 0.02, seconds: 4)
        runSteady(&loud, rms: 0.5, seconds: 4)
        XCTAssertGreaterThan(quiet.level, 0.9)
        XCTAssertGreaterThan(loud.level, 0.9)
        XCTAssertEqual(quiet.level, loud.level, accuracy: 0.05)
    }

    func testLevelDecaysInSilence() {
        var d = SpinnerMusicDrive()
        runSteady(&d, rms: 0.02, seconds: 4)
        let before = d.level
        runSteady(&d, rms: 0, seconds: 4)
        XCTAssertLessThan(d.level, 0.05)
        XCTAssertLessThan(d.level, before)
    }

    func testSustainScaleBoundsAndOffMode() {
        XCTAssertEqual(SpinnerMusicDrive.sustainScale(level: 0), 1, accuracy: 1e-12)
        XCTAssertEqual(SpinnerMusicDrive.sustainScale(level: 1), 1 - 0.85, accuracy: 1e-12)
        XCTAssertEqual(SpinnerMusicDrive.sustainScale(level: 1, strength: 1), 0.05, accuracy: 1e-12)
        XCTAssertEqual(SpinnerMusicDrive.sustainScale(level: 1, strength: 0.5), 0.5, accuracy: 1e-12)

        var d = SpinnerMusicDrive()
        var out = SpinnerMusicDrive.Output(frictionScale: 0, impulse: 0, pulse: 0)
        for _ in 0..<240 { out = d.update(rms: 0.3, bassEnergy: 0.02, dt: 1.0 / 60, velocity: 5, mode: .off) }
        XCTAssertEqual(out.frictionScale, 1)
        XCTAssertEqual(out.impulse, 0)
        // Sustain-only produces no impulse; kick-only keeps friction at 1.
        out = d.update(rms: 0.3, bassEnergy: 0.02, dt: 1.0 / 60, velocity: 5, mode: .sustain)
        XCTAssertLessThan(out.frictionScale, 1)
        XCTAssertEqual(out.impulse, 0)
        out = d.update(rms: 0.3, bassEnergy: 0.02, dt: 1.0 / 60, velocity: 5, mode: .kick)
        XCTAssertEqual(out.frictionScale, 1)
    }

    func testSustainLengthensCoastAndNeverAddsSpeed() {
        func coast(scale: Double) -> (v: Double, maxGain: Double) {
            var p = SpinnerPhysics(angle: 0, velocity: 10)
            var maxGain = 0.0
            for _ in 0..<(5 * 60) {
                let before = p.velocity
                p.step(dt: 1.0 / 60, frictionScale: scale)
                maxGain = max(maxGain, p.velocity - before)
            }
            return (p.velocity, maxGain)
        }
        let quiet = coast(scale: SpinnerMusicDrive.sustainScale(level: 0))
        let loud = coast(scale: SpinnerMusicDrive.sustainScale(level: 1))
        XCTAssertGreaterThan(loud.v, quiet.v + 0.1)
        XCTAssertLessThanOrEqual(loud.maxGain, 0)
        XCTAssertLessThanOrEqual(quiet.maxGain, 0)
        // Default scale leaves existing behavior unchanged.
        var a = SpinnerPhysics(angle: 0, velocity: 10), b = a
        a.step(dt: 0.5); b.step(dt: 0.5, frictionScale: 1)
        XCTAssertEqual(a, b)
    }

    func testKickImpulseDirection() {
        let g = SpinnerSettings.defaultMusicKick
        XCTAssertEqual(SpinnerMusicDrive.kickImpulse(pulse: 0.5, velocity: 3), g * 0.5, accuracy: 1e-12)
        XCTAssertEqual(SpinnerMusicDrive.kickImpulse(pulse: 0.5, velocity: -3), -g * 0.5, accuracy: 1e-12)
        XCTAssertEqual(SpinnerMusicDrive.kickImpulse(pulse: 1, velocity: 0), g, accuracy: 1e-12)
        XCTAssertEqual(SpinnerMusicDrive.kickImpulse(pulse: 1, velocity: -0.04), g, accuracy: 1e-12)
        XCTAssertEqual(SpinnerMusicDrive.kickImpulse(pulse: 0, velocity: 3), 0)
    }

    func testKickFiresFromBassOnsetThroughFollower() {
        var d = SpinnerMusicDrive()
        var fired: SpinnerMusicDrive.Output?
        for i in 0..<60 {
            let bass: Float = i < 30 ? 0.01 : (i == 30 ? 0.06 : 0.01)
            let out = d.update(rms: 0.02, bassEnergy: bass, dt: 1.0 / 60, velocity: -4, mode: .kick)
            if out.pulse > 0 { fired = out }
        }
        let f = try! XCTUnwrap(fired)
        XCTAssertEqual(f.impulse, -SpinnerSettings.defaultMusicKick * Double(f.pulse), accuracy: 1e-9)
        XCTAssertLessThan(f.impulse, 0)
    }

    func testVisualizerKickRespectsTopSpeed() {
        var settings = SpinnerSettings()
        settings.musicMode = .kick
        let viz = SpinnerVisualizer()
        viz.advance(dt: 1.0 / 60, impulse: 10_000, spinner: settings)   // pins at the top speed
        for i in 0..<60 {
            viz.advance(dt: 1.0 / 60, impulse: 0, rms: 0.02, bassEnergy: i == 30 ? 0.06 : 0.01, spinner: settings)
            XCTAssertLessThanOrEqual(viz.physics.velocity, settings.topSpeed)
        }
    }

    func testKickGainAndSustainComeFromSettings() {
        var settings = SpinnerSettings()
        settings.musicMode = .kick
        settings.musicKick = 6
        var fired: Double = 0
        let viz = SpinnerVisualizer()
        for i in 0..<60 {
            let before: Double = viz.physics.velocity
            viz.advance(dt: 1.0 / 60, impulse: 0, rms: 0.02, bassEnergy: i == 30 ? 0.06 : 0.01, spinner: settings)
            if viz.physics.velocity - before > fired { fired = viz.physics.velocity - before }
        }
        XCTAssertGreaterThan(fired, SpinnerSettings.defaultMusicKick)
    }

    // Renderer choice defaults to RealityKit, toggles, and falls back to the shader when unavailable.
    func testRendererChoiceDefaultToggleAndAvailability() {
        XCTAssertEqual(SpinnerSettings().renderer, .realityKit)
        XCTAssertEqual(SpinnerRendererChoice.allCases, [.shader, .realityKit])
        XCTAssertEqual(SpinnerRendererChoice.shader.next, .realityKit)
        XCTAssertEqual(SpinnerRendererChoice.realityKit.next, .shader)
        XCTAssertEqual(SpinnerRendererChoice.realityKit.effective(realityKitAvailable: true), .realityKit)
        XCTAssertEqual(SpinnerRendererChoice.realityKit.effective(realityKitAvailable: false), .shader)
        XCTAssertEqual(SpinnerRendererChoice.shader.effective(realityKitAvailable: true), .shader)
    }
}
