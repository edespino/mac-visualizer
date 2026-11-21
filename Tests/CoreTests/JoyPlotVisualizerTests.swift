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

final class JoyPlotVisualizerTests: XCTestCase {

    private func mono(bands: [Float], beat: Bool = false, intensity: Float = 0, t: TimeInterval = 0) -> AudioFrame {
        AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                   rms: 0, peak: 0, timestamp: t,
                   beat: beat, beatIntensity: intensity)
    }

    private func stereo(L: [Float], R: [Float], beat: Bool = false, intensity: Float = 0, t: TimeInterval = 0) -> AudioFrame {
        let bands = zip(L, R).map { ($0 + $1) / 2 }
        return AudioFrame(bands: bands, bandsLeft: L, bandsRight: R,
                          bandPeaks: bands, waveform: [],
                          rms: 0, peak: 0, timestamp: t,
                          beat: beat, beatIntensity: intensity)
    }

    func testVertexBoundsInClipSpace() {
        let viz = JoyPlotVisualizer()
        let bands: [Float] = (0..<24).map { _ in 0.5 }
        let verts = viz.makeVertices(frame: mono(bands: bands), settings: .defaults, aspect: 1.6)
        for v in verts {
            XCTAssertLessThanOrEqual(abs(v.position.x), 1.25)
            XCTAssertLessThanOrEqual(abs(v.position.y), 1.25)
        }
    }

    func testVertexCountIsMultipleOfSix() {
        let viz = JoyPlotVisualizer()
        let bands: [Float] = (0..<24).map { Float($0) / 24 }
        let verts = viz.makeVertices(frame: mono(bands: bands), settings: .defaults, aspect: 1)
        XCTAssertEqual(verts.count % 6, 0)
    }

    func testEmptyBandsProducesNoVertices() {
        let viz = JoyPlotVisualizer()
        let verts = viz.makeVertices(frame: mono(bands: []), settings: .defaults, aspect: 1)
        XCTAssertEqual(verts.count, 0)
    }

    func testBeatBoostMakesPathWiderForOneFrame() {
        let bands: [Float] = (0..<24).map { _ in 0.6 }
        let baseViz = JoyPlotVisualizer()
        let beatViz = JoyPlotVisualizer()
        _ = baseViz.makeVertices(frame: mono(bands: bands, t: 0), settings: .defaults, aspect: 1)
        _ = beatViz.makeVertices(frame: mono(bands: bands, beat: true, intensity: 1.0, t: 0), settings: .defaults, aspect: 1)
        // Next frame — beat boost should still be in effect (150ms decay).
        let baseVerts = baseViz.makeVertices(frame: mono(bands: bands, t: 1.0/60), settings: .defaults, aspect: 1)
        let beatVerts = beatViz.makeVertices(frame: mono(bands: bands, t: 1.0/60), settings: .defaults, aspect: 1)
        // Path quad heights are wider on the beat-boosted visualizer.
        let baseSpan = (baseVerts.map(\.position.y).max() ?? 0) - (baseVerts.map(\.position.y).min() ?? 0)
        let beatSpan = (beatVerts.map(\.position.y).max() ?? 0) - (beatVerts.map(\.position.y).min() ?? 0)
        XCTAssertGreaterThan(beatSpan, baseSpan)
    }

    // MARK: - Seeded bit-exact golden

    /// Drives a fixed multi-frame sequence (fixed timestamps, fixed bands, a
    /// beat frame) for BOTH the mono and the stereo (distinct L/R) paths and
    /// folds every emitted vertex float's bit pattern into an FNV-1a-64 hash.
    /// JoyPlot has no RNG; its only state is `beatBoost` + `lastTimestamp`.
    /// Captured against base behavior; the refactor that reads tunables from
    /// settings must keep this byte-identical at default settings.
    private func goldenHash() -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        func fold(_ f: Float) {
            var bp = f.bitPattern
            for _ in 0..<4 {
                hash ^= UInt64(bp & 0xFF)
                hash = hash &* 0x100000001b3
                bp >>= 8
            }
        }
        func foldVerts(_ verts: [BarVertex]) {
            for v in verts {
                fold(v.position.x); fold(v.position.y); fold(v.position.z); fold(v.position.w)
                fold(v.color.x); fold(v.color.y); fold(v.color.z); fold(v.color.w)
            }
        }
        // Mono run: 8 frames, fixed timestamps, beat on frame 4.
        var sMono = VisualizerSettings.defaults
        sMono.visualizerStyle = .joyPlot
        let monoViz = JoyPlotVisualizer()
        for i in 0..<8 {
            let lo = Float(i % 3) * 0.3 + 0.2
            let hi = Float((i + 1) % 4) * 0.2 + 0.1
            let bands = (0..<32).map { j in j < 16 ? lo : hi }
            let f = AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                               rms: 0, peak: 0, timestamp: TimeInterval(i) * 0.016,
                               beat: i == 4, beatIntensity: i == 4 ? 0.8 : 0)
            foldVerts(monoViz.makeVertices(frame: f, settings: sMono, aspect: 1.3))
        }
        // Stereo run: fresh instance, distinct L/R so the bandsLeft/bandsRight
        // rows differ, beat on frame 4.
        var sStereo = VisualizerSettings.defaults
        sStereo.visualizerStyle = .joyPlot
        sStereo.useStereoImage = true
        let stereoViz = JoyPlotVisualizer()
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
            foldVerts(stereoViz.makeVertices(frame: f, settings: sStereo, aspect: 1.3))
        }
        return hash
    }

    func testSeededGoldenBitExact() {
        // Captured against base behavior before exposing tunables. Defaults must
        // reproduce the prior look byte-identically (mono + stereo + beat).
        XCTAssertEqual(goldenHash(), 13245971659361103656)
    }

    // MARK: - Comprehensive control behavior + guards

    /// Single mono frame with default-ish bands, with `configure` applied to settings.
    private func oneJoyFrame(_ configure: (inout VisualizerSettings) -> Void) -> [BarVertex] {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .joyPlot
        configure(&s)
        let viz = JoyPlotVisualizer()
        let bands = (0..<24).map { Float($0 % 6 + 1) / 6 }
        return viz.makeVertices(frame: mono(bands: bands), settings: s, aspect: 1.2)
    }

    /// Drives a fixed 6-frame mono sequence (beat on frame 3) with `configure`
    /// applied; returns every emitted vertex across all frames. Used for the
    /// finite-guard equality tests (a non-finite field must reproduce defaults).
    private func driveJoySequence(_ configure: (inout VisualizerSettings) -> Void) -> [BarVertex] {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .joyPlot
        configure(&s)
        let viz = JoyPlotVisualizer()
        var all: [BarVertex] = []
        for i in 0..<6 {
            let frameScale: Float = (Float(i % 3) + 1) / 3
            let bands: [Float] = (0..<24).map { j in
                let base: Float = Float(j % 6 + 1) / 6
                return base * frameScale
            }
            let f = AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                               rms: 0, peak: 0, timestamp: TimeInterval(i) * 0.02,
                               beat: i == 3, beatIntensity: 0.9)
            all.append(contentsOf: viz.makeVertices(frame: f, settings: s, aspect: 1.2))
        }
        return all
    }

    private func vertsBitEqual(_ a: [BarVertex], _ b: [BarVertex]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) {
            if x.position.x.bitPattern != y.position.x.bitPattern { return false }
            if x.position.y.bitPattern != y.position.y.bitPattern { return false }
            if x.position.z.bitPattern != y.position.z.bitPattern { return false }
            if x.position.w.bitPattern != y.position.w.bitPattern { return false }
            if x.color.x.bitPattern != y.color.x.bitPattern { return false }
            if x.color.y.bitPattern != y.color.y.bitPattern { return false }
            if x.color.z.bitPattern != y.color.z.bitPattern { return false }
            if x.color.w.bitPattern != y.color.w.bitPattern { return false }
        }
        return true
    }

    private func allFinite(_ verts: [BarVertex]) -> Bool {
        for v in verts {
            if !(v.position.x.isFinite && v.position.y.isFinite && v.position.z.isFinite && v.position.w.isFinite) { return false }
            if !(v.color.x.isFinite && v.color.y.isFinite && v.color.z.isFinite && v.color.w.isFinite) { return false }
        }
        return true
    }

    private func ySpan(_ verts: [BarVertex]) -> Float {
        (verts.map(\.position.y).max() ?? 0) - (verts.map(\.position.y).min() ?? 0)
    }

    func testSampleCountChangesVertexCount() {
        let verts = oneJoyFrame { $0.joyPlotSampleCount = 32 }
        XCTAssertEqual(verts.count, 4 * (32 - 1) * 6)
    }

    func testSampleCountClampedToMinimumTwo() {
        let verts = oneJoyFrame { $0.joyPlotSampleCount = 0 }   // divide guard
        XCTAssertEqual(verts.count, 4 * (2 - 1) * 6)
        XCTAssertTrue(allFinite(verts))
    }

    func testRowHeightIncreasesAmplitude() {
        let lo = ySpan(oneJoyFrame { $0.joyPlotRowHeight = 0.05 })
        let hi = ySpan(oneJoyFrame { $0.joyPlotRowHeight = 0.5 })
        XCTAssertGreaterThan(hi, lo)
    }

    func testRowSpacingIncreasesSpread() {
        let lo = ySpan(oneJoyFrame { $0.joyPlotRowSpacing = 0.1 })
        let hi = ySpan(oneJoyFrame { $0.joyPlotRowSpacing = 0.9 })
        XCTAssertGreaterThan(hi, lo)
    }

    func testBaselineOffsetShiftsAllRows() {
        let base = oneJoyFrame { _ in }
        let shifted = oneJoyFrame { $0.joyPlotBaselineOffset = 0.3 }
        let baseMean = base.map(\.position.y).reduce(0, +) / Float(base.count)
        let shiftedMean = shifted.map(\.position.y).reduce(0, +) / Float(shifted.count)
        XCTAssertEqual(shiftedMean - baseMean, 0.3, accuracy: 1e-5)
    }

    func testXExtentControlsHorizontalSpan() {
        let def = oneJoyFrame { _ in }.map { abs($0.position.x) }.max() ?? 0
        let wide = oneJoyFrame { $0.joyPlotXExtent = 2.0 }.map { abs($0.position.x) }.max() ?? 0
        XCTAssertEqual(def, 1.0, accuracy: 1e-5)
        XCTAssertEqual(wide, 2.0, accuracy: 1e-5)
    }

    func testAlphaSetsOpacity() {
        let verts = oneJoyFrame { $0.joyPlotAlpha = 0.5 }
        for v in verts { XCTAssertEqual(v.color.w, 0.5, accuracy: 1e-6) }
    }

    func testBottomDimScalesBottomColor() {
        let dim = oneJoyFrame { $0.joyPlotBottomDim = 0.0 }.map(\.color.x).reduce(0, +)
        let bright = oneJoyFrame { $0.joyPlotBottomDim = 0.8 }.map(\.color.x).reduce(0, +)
        XCTAssertGreaterThan(bright, dim, "higher bottom dim brightens the bottom-edge vertices")
    }

    func testBeatBoostScalesBeatResponse() {
        func spanAfterBeat(boost: Double) -> Float {
            var s = VisualizerSettings.defaults
            s.visualizerStyle = .joyPlot
            s.joyPlotBeatBoost = boost
            let viz = JoyPlotVisualizer()
            let bands = [Float](repeating: 0.6, count: 24)
            _ = viz.makeVertices(frame: mono(bands: bands, t: 0), settings: s, aspect: 1)
            let verts = viz.makeVertices(frame: mono(bands: bands, beat: true, intensity: 1.0, t: 0.016), settings: s, aspect: 1)
            return ySpan(verts)
        }
        XCTAssertGreaterThan(spanAfterBeat(boost: 2.5), spanAfterBeat(boost: 0.1))
    }

    func testNonFiniteFieldsFallBackToDefaults() {
        let base = driveJoySequence { _ in }
        let mutators: [(String, (inout VisualizerSettings) -> Void)] = [
            ("rowSpacing.nan",  { $0.joyPlotRowSpacing = .nan }),
            ("rowSpacing.inf",  { $0.joyPlotRowSpacing = .infinity }),
            ("rowHeight.nan",   { $0.joyPlotRowHeight = .nan }),
            ("baselineOffset.nan", { $0.joyPlotBaselineOffset = .nan }),
            ("baselineOffset.inf", { $0.joyPlotBaselineOffset = -.infinity }),
            ("xExtent.nan",     { $0.joyPlotXExtent = .nan }),
            ("beatHalfLife.nan",{ $0.joyPlotBeatHalfLife = .nan }),
            ("beatBoost.nan",   { $0.joyPlotBeatBoost = .nan }),
            ("bottomDim.nan",   { $0.joyPlotBottomDim = .nan }),
            ("alpha.nan",       { $0.joyPlotAlpha = .nan }),
            ("alpha.inf",       { $0.joyPlotAlpha = .infinity }),
        ]
        for (name, mut) in mutators {
            let out = driveJoySequence(mut)
            XCTAssertTrue(allFinite(out), "\(name) produced non-finite output")
            XCTAssertTrue(vertsBitEqual(out, base), "\(name) did not fall back to default behavior bit-exact")
        }
    }

    func testOutOfRangeFieldsClampWithoutNaN() {
        // Negative / zero values that the read-site clamps must tame.
        let out = driveJoySequence {
            $0.joyPlotRowSpacing = -5
            $0.joyPlotRowHeight = -2
            $0.joyPlotXExtent = -1
            $0.joyPlotBeatHalfLife = 0
            $0.joyPlotBeatBoost = -3
            $0.joyPlotBottomDim = 5
            $0.joyPlotAlpha = 9
            $0.joyPlotSampleCount = -10
        }
        XCTAssertTrue(allFinite(out))
        XCTAssertFalse(out.isEmpty)
        for v in out { XCTAssertEqual(v.color.w, 1.0, accuracy: 1e-6) }   // alpha clamped to 1
    }

    func testStereoModeUsesLandR() {
        var s = VisualizerSettings.defaults
        s.useStereoImage = true
        let L: [Float] = [Float](repeating: 0.9, count: 24)
        let R: [Float] = [Float](repeating: 0.0, count: 24)
        let viz = JoyPlotVisualizer()
        let verts = viz.makeVertices(frame: stereo(L: L, R: R), settings: s, aspect: 1)
        // Row 0 (bottom, bandsLeft) should reach much higher than row 3 (top, bandsRight).
        // Row 0 vertices have lower y values than rows 1-3. Find lowest 1/4 of vertices.
        let allY = verts.map(\.position.y).sorted()
        let bottomQuartile = Array(allY.prefix(allY.count / 4))
        let topQuartile = Array(allY.suffix(allY.count / 4))
        let bottomSpan = (bottomQuartile.max() ?? 0) - (bottomQuartile.min() ?? 0)
        let topSpan = (topQuartile.max() ?? 0) - (topQuartile.min() ?? 0)
        XCTAssertGreaterThan(bottomSpan, topSpan, "hard-L input should make bottom (bandsLeft) row taller than top (bandsRight) row")
    }
}