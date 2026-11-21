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

// Presence (stay visible while spinning) and hum mappings.
final class SpinnerPresenceHumTests: XCTestCase {
    func testSpinningIsHeld() {
        var p = SpinnerPresence()
        p.update(now: 100, speed: 5, impulse: false)
        XCTAssertTrue(p.isHeld(now: 100))
    }

    func testLingersThenReleases() {
        var p = SpinnerPresence()
        p.update(now: 100, speed: 5, impulse: false)
        p.update(now: 101, speed: 0.01, impulse: false)   // below threshold: no refresh
        XCTAssertTrue(p.isHeld(now: 100 + SpinnerTuning.presenceLingerSeconds - 0.1))
        XCTAssertFalse(p.isHeld(now: 100 + SpinnerTuning.presenceLingerSeconds + 0.1))
    }

    func testImpulseWhileStoppedHolds() {
        var p = SpinnerPresence()
        p.update(now: 50, speed: 0, impulse: true)
        XCTAssertTrue(p.isHeld(now: 55))
        XCTAssertFalse(p.isHeld(now: 50 + SpinnerTuning.presenceLingerSeconds + 0.1))
    }

    func testNeverTouchedIsNotHeld() {
        var p = SpinnerPresence()
        p.update(now: 10, speed: 0, impulse: false)
        XCTAssertFalse(p.isHeld(now: 10))
        XCTAssertFalse(p.isHeld(now: 1000))
    }

    func testGainMapping() {
        XCTAssertEqual(SpinnerHum.gain(speed: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(SpinnerHum.gain(speed: SpinnerTuning.maxSpeed), SpinnerTuning.humMaxGain, accuracy: 1e-9)
        XCTAssertEqual(SpinnerHum.gain(speed: -SpinnerTuning.maxSpeed * 3), SpinnerTuning.humMaxGain, accuracy: 1e-9)
        var prev = -1.0
        for i in 0...60 {
            let g = SpinnerHum.gain(speed: Double(i))
            XCTAssertGreaterThanOrEqual(g, prev)
            prev = g
        }
        XCTAssertLessThanOrEqual(SpinnerTuning.humMaxGain, 0.0631)   // about -24 dBFS
    }

    func testGainCurveIsGentleAtLowSpeed() {
        let full = SpinnerTuning.humMaxGain
        XCTAssertEqual(SpinnerTuning.humGainExponent, 1.8, accuracy: 1e-12)
        XCTAssertEqual(SpinnerHum.gain(speed: SpinnerTuning.maxSpeed * 0.25) / full, 0.082, accuracy: 0.01)
        XCTAssertEqual(SpinnerHum.gain(speed: SpinnerTuning.maxSpeed * 0.5) / full, 0.287, accuracy: 0.01)
    }

    func testFrequencyMapping() {
        XCTAssertEqual(SpinnerHum.noiseCenterHz(speed: 0), 300, accuracy: 1e-9)
        XCTAssertEqual(SpinnerHum.noiseCenterHz(speed: SpinnerTuning.maxSpeed), 2200, accuracy: 1e-9)
        XCTAssertEqual(SpinnerHum.fundamentalHz(speed: 60), 180, accuracy: 1e-9)
        XCTAssertEqual(SpinnerHum.fundamentalHz(speed: -60), 180, accuracy: 1e-9)
    }
}

// The hum is a strict gate: any music activity silences it, and it may return only after
// `humQuietSeconds` of continuous silence.
final class SpinnerHumGateTests: XCTestCase {
    private let dt = 1.0 / 60

    private func run(_ g: inout SpinnerHumGate, trackPlaying: Bool = false, _ sample: IdleAudioSample = .noCapture,
                     seconds: Double) {
        let frames: Int = Int((seconds / dt).rounded())
        for _ in 0..<frames { _ = g.update(trackPlaying: trackPlaying, sample: sample, dt: dt) }
    }

    func testConstants() {
        XCTAssertEqual(SpinnerTuning.humQuietSeconds, 6.0)
        XCTAssertEqual(SpinnerTuning.humFadeOutSeconds, 0.8, accuracy: 1e-12)
        XCTAssertEqual(SpinnerTuning.humFadeInSeconds, 3.0, accuracy: 1e-12)
    }

    func testActivityClassification() {
        XCTAssertFalse(SpinnerHumGate.isMusicActivity(trackPlaying: false, sample: .noCapture))
        XCTAssertFalse(SpinnerHumGate.isMusicActivity(trackPlaying: false, sample: .level(0)))
        XCTAssertFalse(SpinnerHumGate.isMusicActivity(trackPlaying: false, sample: .level(IdleFadeTracker.levelEpsilon)))
        XCTAssertTrue(SpinnerHumGate.isMusicActivity(trackPlaying: false, sample: .level(IdleFadeTracker.levelEpsilon * 2)))
        XCTAssertTrue(SpinnerHumGate.isMusicActivity(trackPlaying: true, sample: .noCapture))
        XCTAssertTrue(SpinnerHumGate.isMusicActivity(trackPlaying: false, sample: .demo))
    }

    func testLaunchGraceKeepsHumSilentUntilQuietSecondsPass() {
        var g = SpinnerHumGate()
        XCTAssertEqual(g.gain, 0)
        run(&g, seconds: 5.9)
        XCTAssertEqual(g.gain, 0)
    }

    func testSilenceForSixSecondsThenFadesInOverAboutThree() {
        var g = SpinnerHumGate()
        run(&g, seconds: SpinnerTuning.humQuietSeconds + 0.05)
        XCTAssertLessThan(g.gain, 0.05)
        run(&g, seconds: 1.5)
        XCTAssertEqual(g.gain, 0.5, accuracy: 0.08)
        run(&g, seconds: 1.6)
        XCTAssertEqual(g.gain, 1.0, accuracy: 1e-9)
    }

    func testOneAudioFrameAfterFiveNinePointsRestartsTimer() {
        var g = SpinnerHumGate()
        run(&g, seconds: 5.9)
        _ = g.update(trackPlaying: false, sample: .level(0.2), dt: dt)
        XCTAssertEqual(g.gain, 0)
        XCTAssertEqual(g.quietSeconds, 0, accuracy: 1e-12)
        run(&g, seconds: 5.9)
        XCTAssertEqual(g.gain, 0)
    }

    func testTrackPlayingWithZeroCapturedLevelIsSilent() {
        var g = SpinnerHumGate()
        run(&g, seconds: 10)
        XCTAssertGreaterThan(g.gain, 0.99)
        run(&g, trackPlaying: true, .level(0), seconds: 3)
        XCTAssertEqual(g.gain, 0, accuracy: 1e-12)
        run(&g, trackPlaying: true, .noCapture, seconds: 30)
        XCTAssertEqual(g.gain, 0)
    }

    func testCapturedAudioWithNoTrackReportedIsSilent() {
        var g = SpinnerHumGate()
        run(&g, seconds: 10)
        run(&g, trackPlaying: false, .level(0.3), seconds: 3)
        XCTAssertEqual(g.gain, 0, accuracy: 1e-12)
        run(&g, trackPlaying: false, .level(0.3), seconds: 30)
        XCTAssertEqual(g.gain, 0)
    }

    func testThreeSecondGapBetweenTracksStaysSilent() {
        var g = SpinnerHumGate()
        run(&g, trackPlaying: true, .level(0.3), seconds: 20)
        run(&g, trackPlaying: false, .noCapture, seconds: 3)      // the gap
        XCTAssertEqual(g.gain, 0)
        run(&g, trackPlaying: true, .level(0.3), seconds: 5)
        run(&g, trackPlaying: false, .level(0.001), seconds: 5.5) // fade-out tail, still inside the quiet window
        XCTAssertEqual(g.gain, 0)
    }

    func testActivityDuringFadeInPullsBackSmoothlyToZero() {
        var g = SpinnerHumGate()
        run(&g, seconds: SpinnerTuning.humQuietSeconds + 1.5)
        let mid: Double = g.gain
        XCTAssertGreaterThan(mid, 0.3)
        XCTAssertLessThan(mid, 0.7)
        var prev: Double = g.gain
        let limit: Double = dt / SpinnerTuning.humFadeOutSeconds + 1e-12
        for _ in 0..<Int(1.0 / dt) {
            let v: Double = g.update(trackPlaying: true, sample: .noCapture, dt: dt)
            XCTAssertLessThanOrEqual(prev - v, limit)
            XCTAssertLessThanOrEqual(v, prev)
            prev = v
        }
        XCTAssertEqual(g.gain, 0, accuracy: 1e-12)
    }

    func testFadeOutTakesAboutPointEightSeconds() {
        var g = SpinnerHumGate()
        run(&g, seconds: 12)
        XCTAssertEqual(g.gain, 1, accuracy: 1e-9)
        run(&g, trackPlaying: true, seconds: 0.4)
        XCTAssertEqual(g.gain, 0.5, accuracy: 0.05)
        run(&g, trackPlaying: true, seconds: 0.5)
        XCTAssertEqual(g.gain, 0, accuracy: 1e-9)
    }

    func testDemoModeIsSilent() {
        var g = SpinnerHumGate()
        run(&g, .demo, seconds: 30)
        XCTAssertEqual(g.gain, 0)
    }

    func testNeverStepsMoreThanDtOverShortestFade() {
        var g = SpinnerHumGate()
        var prev: Double = g.gain
        let shortest: Double = min(SpinnerTuning.humFadeOutSeconds, SpinnerTuning.humFadeInSeconds)
        let limit: Double = dt / shortest + 1e-12
        let phases: [(Bool, IdleAudioSample)] = [(false, .noCapture), (true, .level(0.3)), (false, .noCapture),
                                                 (false, .level(0.2)), (false, .demo), (false, .noCapture)]
        for i in 0..<(60 * 120) {
            let phase: (Bool, IdleAudioSample) = phases[(i / 600) % phases.count]
            let v: Double = g.update(trackPlaying: phase.0, sample: phase.1, dt: dt)
            XCTAssertTrue(v.isFinite && v >= 0 && v <= 1)
            XCTAssertLessThanOrEqual(abs(v - prev), limit)
            prev = v
        }
    }

    func testZeroDtChangesNothing() {
        var g = SpinnerHumGate()
        XCTAssertEqual(g.update(trackPlaying: false, sample: .noCapture, dt: 0), 0)
        XCTAssertEqual(g.quietSeconds, 0)
    }
}

// Offline check of the hum signal (the audio engine itself is not unit-tested).
final class SpinnerHumSynthTests: XCTestCase {
    private let sr = 48000.0

    private func renderSeconds(_ secs: Double, speed: Float, duck: Float = 1, enabled: Float = 1,
                               synth: SpinnerHumSynth, rate: Double = 48000) -> [Float] {
        let total = Int(secs * rate)
        var out = [Float](repeating: 0, count: total)
        out.withUnsafeMutableBufferPointer { p in
            var off = 0
            while off < total {
                let n = min(512, total - off)
                synth.render(into: p.baseAddress! + off, frames: n, targetSpeed: speed,
                             targetDuck: duck, targetEnabled: enabled)
                off += n
            }
        }
        return out
    }

    private func jump(_ a: [Float]) -> Float { zip(a, a.dropFirst()).map { abs($1 - $0) }.max() ?? 0 }

    private func windowRMS(_ a: [Float], window: Int) -> [Float] {
        stride(from: 0, to: a.count - window + 1, by: window).map { i in
            sqrt(a[i..<(i + window)].reduce(0) { $0 + $1 * $1 } / Float(window))
        }
    }

    func testFullSpeedPeakBoundedAndFinite() {
        let s = SpinnerHumSynth(sampleRate: sr)
        let out = renderSeconds(5, speed: Float(SpinnerTuning.maxSpeed), synth: s)
        XCTAssertTrue(out.allSatisfy { $0.isFinite })
        let peak = out.map { abs($0) }.max()!
        XCTAssertLessThanOrEqual(peak, Float(SpinnerTuning.humMaxGain) + 1e-6)
        let tail = out.suffix(48000)
        let rms = sqrt(tail.reduce(0) { $0 + $1 * $1 } / Float(tail.count))
        XCTAssertGreaterThan(rms, 0.001)
        print("HUM full speed peak=\(peak) rms=\(rms) finite=\(out.allSatisfy { $0.isFinite })")
    }

    func testFirstStartFadesInOverEnabledFadeSeconds() {
        let s = SpinnerHumSynth(sampleRate: sr)
        let out = renderSeconds(3, speed: 60, synth: s)
        let early = out.prefix(Int(0.05 * sr)).map { abs($0) }.max()!
        let steadyPeak = out.suffix(Int(sr)).map { abs($0) }.max()!
        XCTAssertLessThan(early, steadyPeak * 0.05)
        XCTAssertEqual(s.currentGain, Float(SpinnerTuning.humMaxGain), accuracy: 1e-4)
        let rms = windowRMS(out, window: Int(0.1 * sr))
        // rises over about 1.2 s (the attack smoothing adds to it), never beyond steady
        XCTAssertLessThan(rms[Int(0.4 / 0.1)], rms.last! * 0.9)
        XCTAssertLessThan(abs(jump(Array(out.prefix(Int(1.5 * sr))))), jump(Array(out.suffix(Int(sr)))) * 1.25)
    }

    func testDisableRampsToExactZeroWithoutClick() {
        let s = SpinnerHumSynth(sampleRate: sr)
        _ = renderSeconds(5, speed: 60, synth: s)
        let steady = jump(renderSeconds(0.5, speed: 60, synth: s))
        let out = renderSeconds(2, speed: 60, enabled: 0, synth: s)
        XCTAssertTrue(out.allSatisfy { $0.isFinite })
        XCTAssertLessThanOrEqual(jump(out), steady * 1.25)
        // still audible at the start of the ramp, silent after the fade time
        XCTAssertGreaterThan(out.prefix(Int(0.3 * sr)).map { abs($0) }.max()!, 0.01)
        XCTAssertEqual(out.suffix(Int(0.2 * sr)).map { abs($0) }.max()!, 0, accuracy: 1e-9)
        XCTAssertEqual(s.currentGain, 0, accuracy: 1e-9)
    }

    func testDuckEasesWithoutClick() {
        let s = SpinnerHumSynth(sampleRate: sr)
        _ = renderSeconds(5, speed: 60, synth: s)
        let steady = jump(renderSeconds(0.5, speed: 60, synth: s))
        let out = renderSeconds(2, speed: 60, duck: 0, synth: s)
        XCTAssertLessThanOrEqual(jump(out), steady * 1.25)
        XCTAssertLessThan(out.suffix(4800).map { abs($0) }.max()!, 1e-3)
    }

    func testSpeedStepEnvelopeTimeConstant() {
        let s = SpinnerHumSynth(sampleRate: sr)
        _ = renderSeconds(5, speed: 5, synth: s)
        let before = windowRMS(renderSeconds(0.5, speed: 5, synth: s), window: 480).reduce(0, +) / 25
        let stepped = renderSeconds(3, speed: 20, synth: s)
        let rms = windowRMS(stepped, window: 1920)      // 40 ms windows
        let after = rms.suffix(6).reduce(0, +) / 6
        let threshold = before + 0.632 * (after - before)
        let idx = rms.firstIndex { $0 >= threshold }!
        let t63 = Double(idx) * 0.04 + 0.02
        print("HUM speed step 5->20: before=\(before) after=\(after) t63=\(t63)s")
        XCTAssertGreaterThan(t63, 0.2)
        XCTAssertLessThan(t63, 0.45)
        XCTAssertTrue(stepped.allSatisfy { $0.isFinite })
        _ = renderSeconds(2, speed: 20, synth: s)
        let steady = renderSeconds(0.5, speed: 20, synth: s)
        XCTAssertLessThanOrEqual(jump(stepped), jump(steady) * 1.25)
    }

    /// Time (s) for the synth's gain to cover 63.2% of a step between two speeds, read 10 ms at a time.
    private func gainT63(from: Float, to: Float) -> Double {
        let s = SpinnerHumSynth(sampleRate: sr)
        _ = renderSeconds(6, speed: from, synth: s)
        let g0 = s.currentGain
        let g1 = Float(SpinnerHum.gain(speed: Double(to)))
        for i in 0..<400 {
            _ = renderSeconds(0.01, speed: to, synth: s)
            let frac = (s.currentGain - g0) / (g1 - g0)
            if frac >= 0.632 { return Double(i + 1) * 0.01 }
        }
        return .infinity
    }

    func testGainAttackAndReleaseTimeConstants() {
        let attack = gainT63(from: 5, to: 20)
        let release = gainT63(from: 20, to: 5)
        print("HUM gain t63 attack=\(attack)s release=\(release)s")
        XCTAssertEqual(attack, SpinnerTuning.humAttackSeconds, accuracy: 0.03)
        XCTAssertEqual(release, SpinnerTuning.humReleaseSeconds, accuracy: 0.03)
    }

    func testZeroSpeedIsSilent() {
        let s = SpinnerHumSynth(sampleRate: 44100)
        let out = renderSeconds(1, speed: 0, synth: s, rate: 44100)
        XCTAssertEqual(out.map { abs($0) }.max()!, 0, accuracy: 1e-7)
    }
}
