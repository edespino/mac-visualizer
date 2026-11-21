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
import simd
@testable import MacVisualizerCore

final class SpectrumFountainVisualizerTests: XCTestCase {
    private func frame(bands: [Float], t: TimeInterval) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: bands, waveform: [], rms: 0, peak: 0, timestamp: t)
    }
    private let loud = [Float](repeating: 1.0, count: 24)
    private let quiet = [Float](repeating: 0.0, count: 24)

    /// Settings whose capacity matches a test's init capacity so the visualizer's
    /// settings-driven reconciliation does not reallocate mid-test.
    private func settings(maxParticles: Int) -> VisualizerSettings {
        var s = VisualizerSettings.defaults
        s.fountainMaxParticles = maxParticles
        return s
    }

    func testVertexCountIsMultipleOfSixAndBounded() {
        let viz = SpectrumFountainVisualizer(maxParticles: 100)
        let s = settings(maxParticles: 100)
        var t = 0.0
        for _ in 0..<60 {
            let v = viz.makeVertices(frame: frame(bands: loud, t: t), settings: s, aspect: 1)
            XCTAssertEqual(v.count % 6, 0)
            XCTAssertLessThanOrEqual(v.count, 100 * 6)
            t += 1.0 / 60.0
        }
    }

    func testVerticesStayInClipSpace() {
        let viz = SpectrumFountainVisualizer(maxParticles: 200)
        let s = settings(maxParticles: 200)
        var t = 0.0
        for _ in 0..<120 {
            let v = viz.makeVertices(frame: frame(bands: loud, t: t), settings: s, aspect: 1.6)
            for vert in v {
                XCTAssertLessThanOrEqual(abs(vert.position.x), 1.25)
                XCTAssertLessThanOrEqual(abs(vert.position.y), 1.25)
            }
            t += 1.0 / 60.0
        }
    }

    func testDeterministicForSameSeedAndCalls() {
        let a = SpectrumFountainVisualizer(maxParticles: 64, seed: 42)
        let b = SpectrumFountainVisualizer(maxParticles: 64, seed: 42)
        let s = settings(maxParticles: 64)
        var t = 0.0
        var lastA: [BarVertex] = [], lastB: [BarVertex] = []
        for _ in 0..<30 {
            lastA = a.makeVertices(frame: frame(bands: loud, t: t), settings: s, aspect: 1)
            lastB = b.makeVertices(frame: frame(bands: loud, t: t), settings: s, aspect: 1)
            t += 1.0 / 60.0
        }
        XCTAssertEqual(lastA, lastB)
    }

    func testLoudProducesMoreActiveParticlesThanSilent() {
        func activeAfterRun(bands: [Float]) -> Int {
            let viz = SpectrumFountainVisualizer(maxParticles: 200, seed: 7)
            let s = settings(maxParticles: 200)
            var t = 0.0
            var last: [BarVertex] = []
            for _ in 0..<30 {
                last = viz.makeVertices(frame: frame(bands: bands, t: t), settings: s, aspect: 1)
                t += 1.0 / 60.0
            }
            return last.count / 6
        }
        XCTAssertGreaterThan(activeAfterRun(bands: loud), activeAfterRun(bands: quiet))
    }

    func testBeatBoostsLaunchVelocityImmediately() {
        let bands = [Float](repeating: 0.5, count: 24)
        func make(_ t: TimeInterval, beat: Bool = false, intensity: Float = 0) -> AudioFrame {
            AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                       rms: 0.4, peak: 0.5, timestamp: t,
                       beat: beat, beatIntensity: intensity)
        }
        let baseViz = SpectrumFountainVisualizer(seed: 21)
        let beatViz = SpectrumFountainVisualizer(seed: 21)
        // Warm both visualizers with one non-beat frame so dt > 0 on the next call.
        _ = baseViz.makeVertices(frame: make(0), settings: .defaults, aspect: 1)
        _ = beatViz.makeVertices(frame: make(0), settings: .defaults, aspect: 1)
        // Apply the beat at t = 1/60. Now dt > 0 inside makeVertices, so the spawn
        // loop runs and the beatLaunch multiplier is applied to any spawned particles.
        _ = baseViz.makeVertices(frame: make(1.0/60), settings: .defaults, aspect: 1)
        _ = beatViz.makeVertices(frame: make(1.0/60, beat: true, intensity: 1.0), settings: .defaults, aspect: 1)
        // After 5 frames of decay, the beat-spawned particles should still sit
        // visibly higher (larger maxY) than the non-beat ones.
        var bestBase: Float = -10, bestBeat: Float = -10
        for i in 2...6 {
            let f = make(Double(i) / 60.0)
            let bv = baseViz.makeVertices(frame: f, settings: .defaults, aspect: 1)
            let kv = beatViz.makeVertices(frame: f, settings: .defaults, aspect: 1)
            bestBase = max(bestBase, bv.map(\.position.y).max() ?? -10)
            bestBeat = max(bestBeat, kv.map(\.position.y).max() ?? -10)
        }
        XCTAssertGreaterThan(bestBeat, bestBase)
    }

    // MARK: - Value-preservation golden (bit-exact, captured from base behavior)

    // Flattened [position.x, position.y, color.r, color.g, color.b, color.a] of every
    // emitted vertex (Float little-endian bit patterns, base64), captured from the base
    // SpectrumFountainVisualizer at VisualizerSettings.defaults driving a fixed seeded
    // frame sequence (seed 0xABCDEF12, capacity 600, 24-band ramp, t = k/60, beat at
    // frame 10 with intensity 0.8, aspect 1.5). BEAT = emitted vertices at the beat
    // frame (k=10); FINAL = emitted vertices after the full sequence (k=20). A ramp +
    // accumulated stateful physics + a beat frame make this catch displacement, launch,
    // gravity, drag, lifetime, color, and spawn-RNG regressions, not just count.
    private static let beatGolden = "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r+cBP+EgQD0AAIA/7ivxPtFSab8f+GE/r+cBP+EgQD0AAIA/rvBRP9Moar8f+GE/GSlwPtrtpT0AAIA/uqtUP9Moar8f+GE/GSlwPtrtpT0AAIA/rvBRPz8QZr8f+GE/GSlwPtrtpT0AAIA/uqtUP9Moar8f+GE/GSlwPtrtpT0AAIA/uqtUPz8QZr8f+GE/GSlwPtrtpT0AAIA/rvBRPz8QZr8f+GE/GSlwPtrtpT0AAIA/U6EPP3T1cb82cmM/7ljiPoCLZD0AAIA/X1wSP3T1cb82cmM/7ljiPoCLZD0AAIA/U6EPP+Dcbb82cmM/7ljiPoCLZD0AAIA/X1wSP3T1cb82cmM/7ljiPoCLZD0AAIA/X1wSP+Dcbb82cmM/7ljiPoCLZD0AAIA/U6EPP+Dcbb82cmM/7ljiPoCLZD0AAIA/W2BSP0I6br82cmM/77pxPnwDpz0AAIA/ZxtVP0I6br82cmM/77pxPnwDpz0AAIA/W2BSP64har82cmM/77pxPnwDpz0AAIA/ZxtVP0I6br82cmM/77pxPnwDpz0AAIA/ZxtVP64har82cmM/77pxPnwDpz0AAIA/W2BSP64har82cmM/77pxPnwDpz0AAIA/JLB+P09Nb782cmM/oyzKPaMsyj0AAIA/mLWAP09Nb782cmM/oyzKPaMsyj0AAIA/JLB+P7s0a782cmM/oyzKPaMsyj0AAIA/mLWAP09Nb782cmM/oyzKPaMsyj0AAIA/mLWAP7s0a782cmM/oyzKPaMsyj0AAIA/JLB+P7s0a782cmM/oyzKPaMsyj0AAIA/SMpZPkAQe79P7GQ/zq84PwHysDwAAIA/fLZkPkAQe79P7GQ/zq84PwHysDwAAIA/SMpZPqz3dr9P7GQ/zq84PwHysDwAAIA/fLZkPkAQe79P7GQ/zq84PwHysDwAAIA/fLZkPqz3dr9P7GQ/zq84PwHysDwAAIA/SMpZPqz3dr9P7GQ/zq84PwHysDwAAIA/hzDyPiH7er9P7GQ/Z5oDP9KjQj0AAIA/oab3PiH7er9P7GQ/Z5oDP9KjQj0AAIA/hzDyPo3idr9P7GQ/Z5oDP9KjQj0AAIA/oab3PiH7er9P7GQ/Z5oDP9KjQj0AAIA/oab3Po3idr9P7GQ/Z5oDP9KjQj0AAIA/hzDyPo3idr9P7GQ/Z5oDP9KjQj0AAIA/tiVZPiUGgb9mZmY/1uA5P0AWsjwAAIA/6hFkPiUGgb9mZmY/1uA5P0AWsjwAAIA/tiVZPrbzfb9mZmY/1uA5P0AWsjwAAIA/6hFkPiUGgb9mZmY/1uA5P0AWsjwAAIA/6hFkPrbzfb9mZmY/1uA5P0AWsjwAAIA/tiVZPrbzfb9mZmY/1uA5P0AWsjwAAIA/jyPyPiUGgb9mZmY/wnMEP0rlQz0AAIA/qZn3PiUGgb9mZmY/wnMEP0rlQz0AAIA/jyPyPrbzfb9mZmY/wnMEP0rlQz0AAIA/qZn3PiUGgb9mZmY/wnMEP0rlQz0AAIA/qZn3Prbzfb9mZmY/wnMEP0rlQz0AAIA/jyPyPrbzfb9mZmY/wnMEP0rlQz0AAIA/kFQPPyUGgb9mZmY/d0nlPleDZz0AAIA/nA8SPyUGgb9mZmY/d0nlPleDZz0AAIA/kFQPP7bzfb9mZmY/d0nlPleDZz0AAIA/nA8SPyUGgb9mZmY/d0nlPleDZz0AAIA/nA8SP7bzfb9mZmY/d0nlPleDZz0AAIA/kFQPP7bzfb9mZmY/d0nlPleDZz0AAIA/"
    private static let finalGolden = "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"

    /// Replays the exact base-capture frame sequence and returns the emitted vertices
    /// at the beat frame (k=10) and the final frame (k=20).
    private func goldenRun() -> (beat: [BarVertex], final: [BarVertex]) {
        let viz = SpectrumFountainVisualizer(maxParticles: 600, seed: 0xABCDEF12)
        let bands: [Float] = (0..<24).map { Float($0) / 23.0 }
        var beat: [BarVertex] = [], final: [BarVertex] = []
        for k in 0...20 {
            let t = Double(k) / 60.0
            let isBeat = (k == 10)
            let f = AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                               rms: 0.4, peak: 0.5, timestamp: t,
                               beat: isBeat, beatIntensity: isBeat ? 0.8 : 0)
            let out = viz.makeVertices(frame: f, settings: .defaults, aspect: 1.5)
            if k == 10 { beat = out }
            if k == 20 { final = out }
        }
        return (beat, final)
    }

    private func assertMatchesGolden(_ out: [BarVertex], _ base64: String, _ label: String) {
        let golden = Data(base64Encoded: base64)!.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        XCTAssertEqual(golden.count, out.count * 6, "\(label) vertex count")
        for (i, v) in out.enumerated() {
            let b = i * 6
            XCTAssertEqual(v.position.x.bitPattern, golden[b + 0].bitPattern, "\(label) position.x @ \(i)")
            XCTAssertEqual(v.position.y.bitPattern, golden[b + 1].bitPattern, "\(label) position.y @ \(i)")
            XCTAssertEqual(v.color.x.bitPattern,    golden[b + 2].bitPattern, "\(label) color.r @ \(i)")
            XCTAssertEqual(v.color.y.bitPattern,    golden[b + 3].bitPattern, "\(label) color.g @ \(i)")
            XCTAssertEqual(v.color.z.bitPattern,    golden[b + 4].bitPattern, "\(label) color.b @ \(i)")
            XCTAssertEqual(v.color.w.bitPattern,    golden[b + 5].bitPattern, "\(label) color.a @ \(i)")
        }
    }

    func testDefaultBeatFrameOutputUnchanged() {
        assertMatchesGolden(goldenRun().beat, Self.beatGolden, "beat")
    }

    func testDefaultFinalFrameOutputUnchanged() {
        assertMatchesGolden(goldenRun().final, Self.finalGolden, "final")
    }

    // MARK: - Field-read & clamp helpers

    /// Runs `frames` of identical `bands` through a fresh visualizer (default init
    /// capacity 600) under settings produced by `configure`, returning the last emit.
    private func run(_ configure: (inout VisualizerSettings) -> Void,
                     bands customBands: [Float]? = nil, frames: Int = 40,
                     seed: UInt64 = 9, initCapacity: Int = 600, aspect: Float = 1) -> [BarVertex] {
        var s = VisualizerSettings.defaults
        configure(&s)
        let viz = SpectrumFountainVisualizer(maxParticles: initCapacity, seed: seed)
        let b = customBands ?? loud
        var t = 0.0, last: [BarVertex] = []
        for _ in 0..<frames {
            last = viz.makeVertices(frame: frame(bands: b, t: t), settings: s, aspect: aspect)
            t += 1.0 / 60.0
        }
        return last
    }
    private func maxY(_ v: [BarVertex]) -> Float { v.map(\.position.y).max() ?? -10 }
    private func xSpan(_ v: [BarVertex]) -> Float { (v.map(\.position.x).max() ?? 0) - (v.map(\.position.x).min() ?? 0) }
    private func allFinite(_ v: [BarVertex]) -> Bool {
        v.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite }
    }

    // MARK: - Field-read tests (each tunable actually drives output)

    func testSpawnRateZeroSpawnsNothing() {
        XCTAssertTrue(run({ $0.fountainSpawnRate = 0 }).isEmpty)
    }
    func testSpawnFloorBlocksSpawnsBelowThreshold() {
        // Floor 1.0 with sub-unity bands -> nothing crosses the threshold.
        let v = run({ $0.fountainSpawnFloor = 1.0 }, bands: [Float](repeating: 0.9, count: 24))
        XCTAssertTrue(v.isEmpty)
    }
    func testBaseUpRaisesApex() {
        XCTAssertGreaterThan(maxY(run({ $0.fountainBaseUp = 1.5 })), maxY(run({ $0.fountainBaseUp = 0.1 })))
    }
    func testLaunchScaleRaisesApex() {
        XCTAssertGreaterThan(maxY(run({ $0.fountainLaunchScale = 4 })), maxY(run({ $0.fountainLaunchScale = 0.2 })))
    }
    func testGravityLowersApex() {
        // Stronger gravity pulls particles back down sooner -> lower peak height.
        XCTAssertLessThan(maxY(run({ $0.fountainGravity = 4 })), maxY(run({ $0.fountainGravity = 0.2 })))
    }
    func testBaseSizeScalesQuad() {
        XCTAssertGreaterThan(xSpan(run({ $0.fountainBaseSize = 0.04 })), xSpan(run({ $0.fountainBaseSize = 0.001 })))
    }
    func testHorizontalJitterWidensSpread() {
        let none = run({ $0.fountainHorizontalJitter = 0; $0.fountainBaseSize = 0 })
        let wide = run({ $0.fountainHorizontalJitter = 0.25; $0.fountainBaseSize = 0 })
        XCTAssertGreaterThan(xSpan(wide), xSpan(none))
    }
    func testBaseLifetimeKeepsMoreParticlesAlive() {
        let shortLife = run({ $0.fountainBaseLifetime = 0.2 }, frames: 60).count
        let longLife = run({ $0.fountainBaseLifetime = 8 }, frames: 60).count
        XCTAssertGreaterThan(longLife, shortLife)
    }
    func testBeatLaunchBoostScalesBeatResponse() {
        func beatApex(_ boost: Double) -> Float {
            var s = VisualizerSettings.defaults
            s.fountainBeatLaunchBoost = boost
            let viz = SpectrumFountainVisualizer(maxParticles: 600, seed: 5)
            let bands = [Float](repeating: 0.6, count: 24)
            func mk(_ t: Double, beat: Bool) -> AudioFrame {
                AudioFrame(bands: bands, bandPeaks: bands, waveform: [], rms: 0.4, peak: 0.5,
                           timestamp: t, beat: beat, beatIntensity: beat ? 1.0 : 0)
            }
            _ = viz.makeVertices(frame: mk(0, beat: false), settings: s, aspect: 1)
            _ = viz.makeVertices(frame: mk(1.0/60, beat: true), settings: s, aspect: 1)
            var best: Float = -10
            for i in 2...6 { best = max(best, maxY(viz.makeVertices(frame: mk(Double(i)/60, beat: false), settings: s, aspect: 1))) }
            return best
        }
        XCTAssertGreaterThan(beatApex(2.5), beatApex(0))
    }

    // MARK: - maxParticles stateful reallocation

    func testMaxParticlesDrivesCapacityFromSettings() {
        // init capacity differs from settings; the visualizer reconciles to settings.
        let v = run({ $0.fountainMaxParticles = 60 }, frames: 80, initCapacity: 600)
        XCTAssertLessThanOrEqual(v.count, 60 * 6)
        XCTAssertEqual(v.count % 6, 0)
    }
    func testMaxParticlesReallocCanGrowAndShrinkAcrossFrames() {
        // Same visualizer instance, capacity changed between frames -> no crash, bounded.
        let viz = SpectrumFountainVisualizer(maxParticles: 600, seed: 3)
        var s = VisualizerSettings.defaults
        var t = 0.0
        func step(_ cap: Int, _ n: Int) -> [BarVertex] {
            s.fountainMaxParticles = cap
            var last: [BarVertex] = []
            for _ in 0..<n { last = viz.makeVertices(frame: frame(bands: loud, t: t), settings: s, aspect: 1); t += 1.0/60.0 }
            return last
        }
        let grown = step(800, 40)
        XCTAssertLessThanOrEqual(grown.count, 800 * 6)
        let shrunk = step(40, 40)
        XCTAssertLessThanOrEqual(shrunk.count, 40 * 6)
        XCTAssertTrue(allFinite(shrunk))
    }

    // MARK: - Clamp tests (persisted/edited out-of-range values snap to nearest bound)

    func testMaxParticlesZeroClampsToOneNoCrash() {
        let v = run({ $0.fountainMaxParticles = 0 }, frames: 40)
        XCTAssertLessThanOrEqual(v.count, 6)            // capacity clamped to 1 -> at most one particle
        XCTAssertTrue(allFinite(v))
    }
    func testMaxParticlesNegativeClampsToOne() {
        XCTAssertEqual(run({ $0.fountainMaxParticles = -50 }, frames: 40).count,
                       run({ $0.fountainMaxParticles = 1 }, frames: 40).count)
    }
    func testMaxParticlesCapsAtFourThousand() {
        // High spawn drives alive demand (~3744) between 3000 and 4000, so capacity is
        // observable: 10000 and 4000 both clamp to 4000 (identical); 3000 differs.
        func highSpawn(_ cap: Int) -> [BarVertex] {
            run({ $0.fountainMaxParticles = cap; $0.fountainSpawnRate = 60; $0.fountainSpawnFloor = 0 },
                frames: 200, seed: 5)
        }
        XCTAssertEqual(highSpawn(10000), highSpawn(4000))
        XCTAssertNotEqual(highSpawn(4000), highSpawn(3000))
    }
    func testSpawnRateNegativeClampsToZero() {
        XCTAssertEqual(run({ $0.fountainSpawnRate = -10 }), run({ $0.fountainSpawnRate = 0 }))
    }
    func testSpawnFloorClampsToUnitRange() {
        // Floor < 0 clamps to 0 (everything ≥0 spawns) == floor 0; floor > 1 clamps to 1.
        XCTAssertEqual(run({ $0.fountainSpawnFloor = -5 }), run({ $0.fountainSpawnFloor = 0 }))
        XCTAssertEqual(run({ $0.fountainSpawnFloor = 5 }, bands: [Float](repeating: 0.5, count: 24)),
                       run({ $0.fountainSpawnFloor = 1 }, bands: [Float](repeating: 0.5, count: 24)))
    }
    func testLaunchJitterClampsToUnitRange() {
        XCTAssertEqual(run({ $0.fountainLaunchJitter = 5 }), run({ $0.fountainLaunchJitter = 1 }))
        XCTAssertEqual(run({ $0.fountainLaunchJitter = -5 }), run({ $0.fountainLaunchJitter = 0 }))
    }
    func testGravityNegativeClampsToZero() {
        XCTAssertEqual(run({ $0.fountainGravity = -3 }), run({ $0.fountainGravity = 0 }))
    }
    func testHorizontalDragClampsToUnitRange() {
        // Drag > 1 would amplify x velocity; must clamp to 1. Drag < 0 clamps to 0.
        XCTAssertEqual(run({ $0.fountainHorizontalDrag = 1.5 }), run({ $0.fountainHorizontalDrag = 1 }))
        XCTAssertEqual(run({ $0.fountainHorizontalDrag = -1 }), run({ $0.fountainHorizontalDrag = 0 }))
        XCTAssertTrue(allFinite(run({ $0.fountainHorizontalDrag = 9 })))
    }
    func testBaseLifetimeClampPositiveStaysFinite() {
        let v = run({ $0.fountainBaseLifetime = 0 }, frames: 40)
        XCTAssertTrue(allFinite(v))
    }
    func testBaseSizeNegativeClampsToZero() {
        XCTAssertEqual(xSpan(run({ $0.fountainBaseSize = -1 })), xSpan(run({ $0.fountainBaseSize = 0 })), accuracy: 0)
    }
    func testBeatLaunchBoostNegativeClampsToZero() {
        func beatApex(_ boost: Double) -> Float {
            var s = VisualizerSettings.defaults
            s.fountainBeatLaunchBoost = boost
            let viz = SpectrumFountainVisualizer(maxParticles: 600, seed: 5)
            let bands = [Float](repeating: 0.6, count: 24)
            func mk(_ t: Double, beat: Bool) -> AudioFrame {
                AudioFrame(bands: bands, bandPeaks: bands, waveform: [], rms: 0.4, peak: 0.5,
                           timestamp: t, beat: beat, beatIntensity: beat ? 1.0 : 0)
            }
            _ = viz.makeVertices(frame: mk(0, beat: false), settings: s, aspect: 1)
            _ = viz.makeVertices(frame: mk(1.0/60, beat: true), settings: s, aspect: 1)
            var best: Float = -10
            for i in 2...6 { best = max(best, maxY(viz.makeVertices(frame: mk(Double(i)/60, beat: false), settings: s, aspect: 1))) }
            return best
        }
        // Negative boost clamps to 0 (a beat at intensity 1 then yields a 1× multiplier,
        // same as boost 0); without the clamp a negative boost would shrink launch.
        XCTAssertEqual(beatApex(-5), beatApex(0), accuracy: 1e-6)
    }

    // MARK: - Defaults are not clamped (sanity: default values sit inside their ranges)

    func testDefaultsNotClampedToBounds() {
        XCTAssertNotEqual(run({ $0.fountainGravity = 0 }), run({ _ in }))         // default gravity 1.4 != 0
        XCTAssertNotEqual(run({ $0.fountainSpawnRate = 0 }), run({ _ in }))       // default rate 15 != 0
    }
}