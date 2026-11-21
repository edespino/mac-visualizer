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

final class RibbonWaveVisualizerTests: XCTestCase {

    private func frame(bands: [Float], t: TimeInterval = 0) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: bands.map { min($0 + 0.05, 1) },
                   waveform: [], rms: 0, peak: bands.max() ?? 0,
                   timestamp: t)
    }

    func testVertexCountMatchesExpectedFormula() {
        let n = 3
        let sampleCount = 256
        var settings = VisualizerSettings.defaults
        settings.ribbonWaveCount = n
        let viz = RibbonWaveVisualizer()
        let bands = [Float](repeating: 0.5, count: 48)
        let verts = viz.makeVertices(frame: frame(bands: bands), settings: settings, aspect: 1)
        XCTAssertEqual(verts.count, n * (sampleCount - 1) * 6)
    }

    func testVerticesAreInClipSpace() {
        var settings = VisualizerSettings.defaults
        settings.ribbonWaveCount = 6
        let viz = RibbonWaveVisualizer()
        let bands = [Float](repeating: 1.0, count: 48)
        // Drive the EMA for a few frames so amplitudes converge to ~1.
        for i in 0..<30 {
            _ = viz.makeVertices(frame: frame(bands: bands, t: TimeInterval(i) * 0.017),
                                 settings: settings, aspect: 1)
        }
        let verts = viz.makeVertices(frame: frame(bands: bands, t: 0.5),
                                     settings: settings, aspect: 1)
        for v in verts {
            XCTAssertGreaterThanOrEqual(v.position.x, -1.2)
            XCTAssertLessThanOrEqual(v.position.x, 1.2)
            XCTAssertGreaterThanOrEqual(v.position.y, -1.2)
            XCTAssertLessThanOrEqual(v.position.y, 1.2)
        }
    }

    func testDeterministicWithSameSeed() {
        let a = RibbonWaveVisualizer(seed: 0xABCD)
        let b = RibbonWaveVisualizer(seed: 0xABCD)
        var settings = VisualizerSettings.defaults
        settings.ribbonWaveCount = 4
        let bands = [Float](repeating: 0.5, count: 48)
        // Drive both with identical frame sequences.
        var lastA: [BarVertex] = []
        var lastB: [BarVertex] = []
        for i in 0..<20 {
            let f = frame(bands: bands, t: TimeInterval(i) * 0.05)
            lastA = a.makeVertices(frame: f, settings: settings, aspect: 1)
            lastB = b.makeVertices(frame: f, settings: settings, aspect: 1)
        }
        XCTAssertEqual(lastA.count, lastB.count)
        for (va, vb) in zip(lastA, lastB) {
            XCTAssertEqual(va.position.x, vb.position.x, accuracy: 1e-5)
            XCTAssertEqual(va.position.y, vb.position.y, accuracy: 1e-5)
            XCTAssertEqual(va.color.x, vb.color.x, accuracy: 1e-5)
        }
    }

    func testLoudGroupProducesTallerWaves() {
        var settings = VisualizerSettings.defaults
        settings.ribbonWaveCount = 3
        let viz = RibbonWaveVisualizer()
        // 48 bands, split into 3 groups → [0..16), [16..32), [32..48).
        // Make the low group loud, others silent.
        var bands = [Float](repeating: 0, count: 48)
        for i in 0..<16 { bands[i] = 1.0 }
        // Drive the EMA to converge.
        for i in 0..<40 {
            _ = viz.makeVertices(frame: frame(bands: bands, t: TimeInterval(i) * 0.017),
                                 settings: settings, aspect: 1)
        }
        let verts = viz.makeVertices(frame: frame(bands: bands, t: 1.0),
                                     settings: settings, aspect: 1)
        // Vertex stream is laid out wave-by-wave; each wave contributes
        // (sampleCount - 1) * 6 vertices. The first 1530 verts are wave 0 (low group).
        let sampleCount = 256
        let perWave = (sampleCount - 1) * 6
        let lowMax = verts.prefix(perWave).map { abs($0.position.y) }.max() ?? 0
        let highMax = verts.suffix(perWave).map { abs($0.position.y) }.max() ?? 0
        XCTAssertGreaterThan(lowMax, 0.05, "low-group wave should have visible amplitude")
        XCTAssertGreaterThan(lowMax, highMax * 2.0,
                             "loud low group should produce taller wave than silent high group (low=\(lowMax), high=\(highMax))")
    }

    // MARK: - Seeded bit-exact golden

    /// Drives a fixed multi-frame sequence (fixed seed, fixed timestamps, fixed
    /// stereo bands so the pan path runs, a beat frame) and folds every emitted
    /// vertex float's bit pattern into an FNV-1a-64 hash. Captured against base
    /// behavior; the refactor that reads tunables from settings must keep this
    /// byte-identical at default settings.
    private func goldenHash() -> UInt64 {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .ribbonWave
        s.ribbonWaveCount = 3
        s.useStereoImage = true
        let viz = RibbonWaveVisualizer(seed: 0xC0DE5)
        // Distinct L/R so panOffsetX != 0; vary per frame so EMA + phase move.
        var hash: UInt64 = 0xcbf29ce484222325
        func fold(_ f: Float) {
            var bp = f.bitPattern
            for _ in 0..<4 {
                hash ^= UInt64(bp & 0xFF)
                hash = hash &* 0x100000001b3
                bp >>= 8
            }
        }
        for i in 0..<8 {
            let lo = Float(i % 3) * 0.3 + 0.2
            let hi = Float((i + 1) % 4) * 0.2 + 0.1
            let L = (0..<32).map { j in j < 16 ? lo : hi * 0.5 }
            let R = (0..<32).map { j in j < 16 ? hi : lo * 0.5 }
            let bands = zip(L, R).map { ($0 + $1) / 2 }
            let f = AudioFrame(bands: bands, bandsLeft: L, bandsRight: R,
                               bandPeaks: bands, waveform: [], rms: 0, peak: 0,
                               timestamp: TimeInterval(i) * 0.016,
                               beat: i == 4, beatIntensity: i == 4 ? 0.8 : 0)
            let verts = viz.makeVertices(frame: f, settings: s, aspect: 1.3)
            for v in verts {
                fold(v.position.x); fold(v.position.y); fold(v.position.z); fold(v.position.w)
                fold(v.color.x); fold(v.color.y); fold(v.color.z); fold(v.color.w)
            }
        }
        return hash
    }

    func testSeededGoldenBitExact() {
        // Captured against base behavior before exposing tunables. Defaults must
        // reproduce the prior look byte-identically.
        XCTAssertEqual(goldenHash(), 7667281805000989450)
    }

    // MARK: - Comprehensive control behavior + guards

    /// Drives `frames` mono frames of loud bands so amplitudes converge, then
    /// returns the LAST frame's vertices.
    private func drive(_ settings: VisualizerSettings, seed: UInt64 = 0x5EED,
                       frames: Int = 30, level: Float = 1.0) -> [BarVertex] {
        let viz = RibbonWaveVisualizer(seed: seed)
        let bands = [Float](repeating: level, count: 48)
        var last: [BarVertex] = []
        for i in 0..<frames {
            last = viz.makeVertices(frame: frame(bands: bands, t: TimeInterval(i) * 0.017),
                                    settings: settings, aspect: 1)
        }
        return last
    }

    /// For a single-wave ribbon (n == 1, yBase == 0, no pan), pull the curve's
    /// y0 per segment (vertex index 2 of each 6-vertex block) so the wave shape
    /// can be inspected directly.
    private func wave0Curve(_ verts: [BarVertex]) -> [Float] {
        var ys: [Float] = []
        var j = 2
        while j < verts.count { ys.append(verts[j].position.y); j += 6 }
        return ys
    }

    private func signChanges(_ ys: [Float]) -> Int {
        var count = 0
        var prev: Float = 0
        for y in ys where abs(y) > 1e-6 {
            if prev != 0 && (y < 0) != (prev < 0) { count += 1 }
            prev = y
        }
        return count
    }

    func testSampleCountChangesVertexCount() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .ribbonWave
        s.ribbonWaveCount = 2
        s.ribbonSampleCount = 128
        let verts = drive(s, frames: 1)
        XCTAssertEqual(verts.count, 2 * (128 - 1) * 6)
    }

    func testSampleCountClampedToMinimumTwo() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .ribbonWave
        s.ribbonWaveCount = 1
        s.ribbonSampleCount = 0   // would divide by zero / be empty without the clamp
        let verts = drive(s, frames: 1)
        XCTAssertEqual(verts.count, 1 * (2 - 1) * 6)
        for v in verts {
            XCTAssertTrue(v.position.x.isFinite && v.position.y.isFinite)
        }
    }

    func testHigherBaseFrequencyIncreasesOscillation() {
        var lo = VisualizerSettings.defaults
        lo.visualizerStyle = .ribbonWave
        lo.ribbonWaveCount = 1
        lo.ribbonBaseFrequency = 2.0
        var hi = lo
        hi.ribbonBaseFrequency = 16.0
        let loChanges = signChanges(wave0Curve(drive(lo)))
        let hiChanges = signChanges(wave0Curve(drive(hi)))
        XCTAssertGreaterThan(hiChanges, loChanges,
                             "higher base frequency should oscillate more (lo=\(loChanges), hi=\(hiChanges))")
    }

    func testFrequencySpreadChangesWaveConstruction() {
        var a = VisualizerSettings.defaults
        a.visualizerStyle = .ribbonWave
        a.ribbonWaveCount = 3
        a.ribbonFrequencySpread = 0.0
        var b = a
        b.ribbonFrequencySpread = 12.0
        let va = drive(a, frames: 1)
        let vb = drive(b, frames: 1)
        // Same seed + same count, but a different frequency basis must rebuild
        // the waves and therefore change geometry.
        let differs = zip(va, vb).contains { abs($0.position.y - $1.position.y) > 1e-4 }
        XCTAssertTrue(differs, "frequency spread should feed wave rebuild")
    }

    func testFrequencyChangeMidStreamRebuildsWaves() {
        // A single stateful instance: changing base frequency between frames must
        // rebuild the persistent waves (mirroring a wave-count change), so the
        // emitted oscillation count tracks the new frequency.
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .ribbonWave
        s.ribbonWaveCount = 1
        s.ribbonBaseFrequency = 2.0
        let viz = RibbonWaveVisualizer(seed: 0x1234)
        let bands = [Float](repeating: 1.0, count: 48)
        for i in 0..<30 {
            _ = viz.makeVertices(frame: frame(bands: bands, t: TimeInterval(i) * 0.017), settings: s, aspect: 1)
        }
        let lowFreqCurve = wave0Curve(viz.makeVertices(frame: frame(bands: bands, t: 0.6), settings: s, aspect: 1))
        s.ribbonBaseFrequency = 16.0
        var highFreqVerts: [BarVertex] = []
        for i in 30..<60 {
            highFreqVerts = viz.makeVertices(frame: frame(bands: bands, t: TimeInterval(i) * 0.017), settings: s, aspect: 1)
        }
        XCTAssertGreaterThan(signChanges(wave0Curve(highFreqVerts)), signChanges(lowFreqCurve),
                             "raising base frequency mid-stream should rebuild to a higher-frequency wave")
    }

    func testHeightScaleScalesAmplitude() {
        var lo = VisualizerSettings.defaults
        lo.visualizerStyle = .ribbonWave
        lo.ribbonWaveCount = 1
        lo.ribbonHeightScale = 0.2
        var hi = lo
        hi.ribbonHeightScale = 0.6
        let loMax = drive(lo).map { abs($0.position.y) }.max() ?? 0
        let hiMax = drive(hi).map { abs($0.position.y) }.max() ?? 0
        XCTAssertGreaterThan(hiMax, loMax * 2.0,
                             "tripling height scale should roughly triple amplitude (lo=\(loMax), hi=\(hiMax))")
    }

    func testMaxAmplitudeCapsAmplitude() {
        var low = VisualizerSettings.defaults
        low.visualizerStyle = .ribbonWave
        low.ribbonWaveCount = 1
        low.ribbonGain = 5.0          // saturate the target
        low.ribbonMaxAmplitude = 0.5
        var high = low
        high.ribbonMaxAmplitude = 1.0
        let lowMax = drive(low).map { abs($0.position.y) }.max() ?? 0
        let highMax = drive(high).map { abs($0.position.y) }.max() ?? 0
        XCTAssertGreaterThan(highMax, lowMax * 1.5,
                             "a lower amplitude cap should clamp wave height (low=\(lowMax), high=\(highMax))")
    }

    func testAlphaSetsVertexOpacity() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .ribbonWave
        s.ribbonWaveCount = 2
        s.ribbonAlpha = 0.35
        let verts = drive(s, frames: 1)
        for v in verts {
            XCTAssertEqual(v.color.w, 0.35, accuracy: 1e-6)
        }
    }

    func testStereoPanScaleZeroDisablesPan() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .ribbonWave
        s.useStereoImage = true
        s.ribbonStereoPanScale = 0
        let L = [Float](repeating: 0.9, count: 32)
        let R = [Float](repeating: 0.1, count: 32)
        let bands = zip(L, R).map { ($0 + $1) / 2 }
        let f = AudioFrame(bands: bands, bandsLeft: L, bandsRight: R,
                           bandPeaks: bands, waveform: [], rms: 0, peak: 0, timestamp: 0)
        let viz = RibbonWaveVisualizer(seed: 31)
        _ = viz.makeVertices(frame: f, settings: s, aspect: 1)
        let verts = viz.makeVertices(frame: f, settings: s, aspect: 1)
        let minX = verts.map(\.position.x).min() ?? 0
        let maxX = verts.map(\.position.x).max() ?? 0
        XCTAssertEqual((minX + maxX) / 2, 0, accuracy: 1e-5, "zero pan scale should keep the wave centered")
    }

    // MARK: - Finite + clamp guards

    /// Mutators that drive a single field to an out-of-range or non-finite value.
    private func ribbonFieldMutators() -> [(String, (inout VisualizerSettings, Double) -> Void)] {
        [
            ("ribbonSmoothing", { s, v in s.ribbonSmoothing = v }),
            ("ribbonGain", { s, v in s.ribbonGain = v }),
            ("ribbonHeightScale", { s, v in s.ribbonHeightScale = v }),
            ("ribbonMotionSpeed", { s, v in s.ribbonMotionSpeed = v }),
            ("ribbonBaseFrequency", { s, v in s.ribbonBaseFrequency = v }),
            ("ribbonFrequencySpread", { s, v in s.ribbonFrequencySpread = v }),
            ("ribbonStereoPanScale", { s, v in s.ribbonStereoPanScale = v }),
            ("ribbonPhaseSwing", { s, v in s.ribbonPhaseSwing = v }),
            ("ribbonMaxAmplitude", { s, v in s.ribbonMaxAmplitude = v }),
            ("ribbonAlpha", { s, v in s.ribbonAlpha = v }),
        ]
    }

    private func assertAllFinite(_ verts: [BarVertex], _ label: String) {
        for v in verts {
            XCTAssertTrue(v.position.x.isFinite && v.position.y.isFinite &&
                          v.position.z.isFinite && v.position.w.isFinite &&
                          v.color.x.isFinite && v.color.y.isFinite &&
                          v.color.z.isFinite && v.color.w.isFinite,
                          "non-finite vertex from \(label)")
        }
    }

    func testNonFiniteFieldFallsBackToDefaultGeometry() {
        // For each Double field, setting it to NaN or ±inf must fall back to the
        // field default (finiteOr) BEFORE clamping, so a single poisoned field
        // reproduces the all-default geometry bit-for-bit and emits no NaN.
        let base = { () -> VisualizerSettings in
            var s = VisualizerSettings.defaults; s.visualizerStyle = .ribbonWave; s.ribbonWaveCount = 3; return s
        }
        let reference = drive(base(), seed: 0xBEEF)
        for (name, mutate) in ribbonFieldMutators() {
            for bad in [Double.nan, .infinity, -.infinity] {
                var s = base()
                mutate(&s, bad)
                let verts = drive(s, seed: 0xBEEF)
                assertAllFinite(verts, "\(name)=\(bad)")
                XCTAssertEqual(verts.count, reference.count, "\(name)=\(bad) changed vertex count")
                for (a, b) in zip(verts, reference) {
                    XCTAssertEqual(a.position.y.bitPattern, b.position.y.bitPattern,
                                   "\(name)=\(bad) did not fall back to default geometry")
                }
            }
        }
    }

    func testExtremeOutOfRangeFieldsStayFinite() {
        let base = { () -> VisualizerSettings in
            var s = VisualizerSettings.defaults; s.visualizerStyle = .ribbonWave; s.ribbonWaveCount = 3; return s
        }
        for (name, mutate) in ribbonFieldMutators() {
            for bad in [1e9, -1e9] {
                var s = base()
                mutate(&s, bad)
                assertAllFinite(drive(s, seed: 0xBEEF), "\(name)=\(bad)")
            }
        }
        // sampleCount is an Int: exercise tiny, negative, and huge values.
        for sc in [-100, 0, 1, 4096] {
            var s = base()
            s.ribbonSampleCount = sc
            let verts = drive(s, seed: 0xBEEF, frames: 1)
            assertAllFinite(verts, "ribbonSampleCount=\(sc)")
            XCTAssertGreaterThan(verts.count, 0, "ribbonSampleCount=\(sc) produced no geometry")
        }
    }

    func testStereoTiltShiftsHorizontalCenter() {
        var s = VisualizerSettings.defaults
        s.useStereoImage = true
        let L = [Float](repeating: 0.9, count: 32)
        let R = [Float](repeating: 0.1, count: 32)
        let bands = zip(L, R).map { ($0 + $1) / 2 }
        let f = AudioFrame(bands: bands, bandsLeft: L, bandsRight: R,
                           bandPeaks: bands, waveform: [], rms: 0, peak: 0, timestamp: 0)
        let viz = RibbonWaveVisualizer(seed: 31)
        _ = viz.makeVertices(frame: f, settings: s, aspect: 1)
        let verts = viz.makeVertices(frame: f, settings: s, aspect: 1)
        XCTAssertGreaterThan(verts.count, 0)
        // Left-dominant input should pull the left edge of vertex X-range
        // further negative than a balanced input would.
        let minX = verts.map(\.position.x).min() ?? 0
        let maxX = verts.map(\.position.x).max() ?? 0
        let center = (minX + maxX) / 2
        // With pan tilt active, the center of the wave extent shifts away from 0.
        XCTAssertLessThan(center, -0.001, "expected left-pan shift, got center=\(center)")
    }
}