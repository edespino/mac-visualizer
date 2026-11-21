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

final class FireworksVisualizerTests: XCTestCase {
    private func frame(beat: Bool, intensity: Float = 0.7, t: TimeInterval) -> AudioFrame {
        AudioFrame(bands: [Float](repeating: 0, count: 24),
                   bandPeaks: [Float](repeating: 0, count: 24),
                   waveform: [], rms: 0, peak: 0, timestamp: t,
                   beat: beat, beatIntensity: intensity)
    }

    /// Settings whose capacity matches a test's init capacity so the visualizer's
    /// settings-driven reconciliation does not reallocate mid-test.
    private func settings(maxParticles: Int) -> VisualizerSettings {
        var s = VisualizerSettings.defaults
        s.fireworksMaxParticles = maxParticles
        return s
    }

    func testVertexCountIsMultipleOfSixAndBounded() {
        let viz = FireworksVisualizer(maxParticles: 200)
        let s = settings(maxParticles: 200)
        var t = 0.0
        for i in 0..<60 {
            let f = frame(beat: i % 10 == 0, t: t)
            let v = viz.makeVertices(frame: f, settings: s, aspect: 1)
            XCTAssertEqual(v.count % 6, 0)
            XCTAssertLessThanOrEqual(v.count, 200 * 6)
            t += 1.0 / 60.0
        }
    }

    func testVerticesStayInClipSpace() {
        let viz = FireworksVisualizer(maxParticles: 200)
        var t = 0.0
        for i in 0..<120 {
            let v = viz.makeVertices(frame: frame(beat: i % 12 == 0, t: t),
                                     settings: .defaults, aspect: 1.6)
            for vert in v {
                XCTAssertLessThanOrEqual(abs(vert.position.x), 1.25)
                XCTAssertLessThanOrEqual(abs(vert.position.y), 1.25)
            }
            t += 1.0 / 60.0
        }
    }

    func testDeterministicForSameSeedAndCalls() {
        let a = FireworksVisualizer(maxParticles: 100, seed: 42)
        let b = FireworksVisualizer(maxParticles: 100, seed: 42)
        var t = 0.0
        var lastA: [BarVertex] = [], lastB: [BarVertex] = []
        for i in 0..<30 {
            let f = frame(beat: i % 8 == 0, t: t)
            lastA = a.makeVertices(frame: f, settings: .defaults, aspect: 1)
            lastB = b.makeVertices(frame: f, settings: .defaults, aspect: 1)
            t += 1.0 / 60.0
        }
        XCTAssertEqual(lastA, lastB)
    }

    func testBeatProducesParticlesAndSilenceDoesNot() {
        let beatViz = FireworksVisualizer(maxParticles: 200, seed: 7)
        _ = beatViz.makeVertices(frame: frame(beat: false, t: 0), settings: .defaults, aspect: 1)
        _ = beatViz.makeVertices(frame: frame(beat: true, intensity: 0.9, t: 1.0/60), settings: .defaults, aspect: 1)
        let beatLast = beatViz.makeVertices(frame: frame(beat: false, t: 5.0/60), settings: .defaults, aspect: 1)

        let silentViz = FireworksVisualizer(maxParticles: 200, seed: 7)
        _ = silentViz.makeVertices(frame: frame(beat: false, t: 0), settings: .defaults, aspect: 1)
        _ = silentViz.makeVertices(frame: frame(beat: false, t: 1.0/60), settings: .defaults, aspect: 1)
        let silentLast = silentViz.makeVertices(frame: frame(beat: false, t: 5.0/60), settings: .defaults, aspect: 1)

        XCTAssertGreaterThan(beatLast.count, 0)
        XCTAssertEqual(silentLast.count, 0)
    }

    func testIntensityScalesBurstSize() {
        let small = FireworksVisualizer(maxParticles: 200, seed: 7)
        let big   = FireworksVisualizer(maxParticles: 200, seed: 7)
        // Same seed, same call sequence — only difference is intensity.
        _ = small.makeVertices(frame: frame(beat: true, intensity: 0.1, t: 0), settings: .defaults, aspect: 1)
        _ = big.makeVertices  (frame: frame(beat: true, intensity: 1.0, t: 0), settings: .defaults, aspect: 1)
        let sV = small.makeVertices(frame: frame(beat: false, t: 1.0/60), settings: .defaults, aspect: 1)
        let bV = big.makeVertices  (frame: frame(beat: false, t: 1.0/60), settings: .defaults, aspect: 1)
        XCTAssertLessThan(sV.count, bV.count, "lower intensity should produce fewer live particles")
    }

    // MARK: - Value-preservation golden (bit-exact, captured from base behavior)

    // Flattened [position.x, position.y, color.r, color.g, color.b, color.a] of every
    // emitted vertex (Float little-endian bit patterns, base64), captured from the BASE
    // FireworksVisualizer at VisualizerSettings.defaults driving a fixed seeded frame
    // sequence (seed 0xABCDEF12, capacity 600, zero bands, t = k/60, beat at frame 2 with
    // intensity 0.8, aspect 1.5). BURST = emitted vertices at the beat frame (k=2, all 70
    // particles freshly spawned at the burst center); FINAL = emitted vertices after the
    // full sequence (k=20, particles displaced by velocity + gravity + drag). A beat frame
    // plus accumulated stateful physics makes FINAL catch displacement, radial speed,
    // gravity, drag, lifetime, color, angle, and spawn-RNG regressions, not just count.
    private static let burstGolden = "lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PviHR571mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/exjKviHR571mZmY/c6T8PlooUD0AAIA/exjKvoUMx71mZmY/c6T8PlooUD0AAIA/lY7PvoUMx71mZmY/c6T8PlooUD0AAIA/"
    private static let finalGolden = "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"

    /// Replays the exact base-capture frame sequence and returns the emitted vertices
    /// at the burst frame (k=2) and the final frame (k=20).
    private func goldenRun() -> (burst: [BarVertex], final: [BarVertex]) {
        let viz = FireworksVisualizer(maxParticles: 600, seed: 0xABCDEF12)
        let bands = [Float](repeating: 0, count: 24)
        var burst: [BarVertex] = [], final: [BarVertex] = []
        for k in 0...20 {
            let t = Double(k) / 60.0
            let isBeat = (k == 2)
            let f = AudioFrame(bands: bands, bandPeaks: bands, waveform: [],
                               rms: 0, peak: 0, timestamp: t,
                               beat: isBeat, beatIntensity: isBeat ? 0.8 : 0)
            let out = viz.makeVertices(frame: f, settings: .defaults, aspect: 1.5)
            if k == 2 { burst = out }
            if k == 20 { final = out }
        }
        return (burst, final)
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

    func testDefaultBurstFrameOutputUnchanged() {
        assertMatchesGolden(goldenRun().burst, Self.burstGolden, "burst")
    }

    func testDefaultFinalFrameOutputUnchanged() {
        assertMatchesGolden(goldenRun().final, Self.finalGolden, "final")
    }

    // MARK: - Field-read & clamp helpers

    /// Warms the visualizer (so dt > 0), fires ONE beat at intensity, then evolves
    /// `frames` non-beat frames, returning the final emit. Output exists only because
    /// of the beat (Fireworks has no band/rms drive).
    private func burstRun(_ configure: (inout VisualizerSettings) -> Void,
                          intensity: Float = 0.9, frames: Int = 30,
                          seed: UInt64 = 7, initCapacity: Int = 600, aspect: Float = 1) -> [BarVertex] {
        var s = VisualizerSettings.defaults
        configure(&s)
        let viz = FireworksVisualizer(maxParticles: initCapacity, seed: seed)
        var t = 0.0
        _ = viz.makeVertices(frame: frame(beat: false, t: t), settings: s, aspect: aspect); t += 1.0/60.0
        _ = viz.makeVertices(frame: frame(beat: true, intensity: intensity, t: t), settings: s, aspect: aspect); t += 1.0/60.0
        var last: [BarVertex] = []
        for _ in 0..<frames {
            last = viz.makeVertices(frame: frame(beat: false, t: t), settings: s, aspect: aspect); t += 1.0/60.0
        }
        return last
    }

    /// Returns the emit AT the beat frame (freshly spawned particles, no displacement yet).
    private func burstFrame(_ configure: (inout VisualizerSettings) -> Void,
                            intensity: Float = 0.9, seed: UInt64 = 7, initCapacity: Int = 600) -> [BarVertex] {
        var s = VisualizerSettings.defaults
        configure(&s)
        let viz = FireworksVisualizer(maxParticles: initCapacity, seed: seed)
        _ = viz.makeVertices(frame: frame(beat: false, t: 0), settings: s, aspect: 1)
        return viz.makeVertices(frame: frame(beat: true, intensity: intensity, t: 1.0/60.0), settings: s, aspect: 1)
    }

    /// Fires `beats` consecutive beats (warming first) with huge lifetime so nothing
    /// dies, returning the final emit — used to fill the ring buffer to capacity.
    private func fillRun(_ configure: (inout VisualizerSettings) -> Void,
                         beats: Int = 6, seed: UInt64 = 7, initCapacity: Int = 600) -> [BarVertex] {
        var s = VisualizerSettings.defaults
        configure(&s)
        let viz = FireworksVisualizer(maxParticles: initCapacity, seed: seed)
        var t = 0.0, last: [BarVertex] = []
        _ = viz.makeVertices(frame: frame(beat: false, t: t), settings: s, aspect: 1); t += 1.0/60.0
        for _ in 0..<beats {
            last = viz.makeVertices(frame: frame(beat: true, intensity: 1.0, t: t), settings: s, aspect: 1); t += 1.0/60.0
        }
        return last
    }

    private func count(_ v: [BarVertex]) -> Int { v.count / 6 }
    private func maxY(_ v: [BarVertex]) -> Float { v.map(\.position.y).max() ?? -10 }
    private func xSpan(_ v: [BarVertex]) -> Float { (v.map(\.position.x).max() ?? 0) - (v.map(\.position.x).min() ?? 0) }
    private func ySpan(_ v: [BarVertex]) -> Float { (v.map(\.position.y).max() ?? 0) - (v.map(\.position.y).min() ?? 0) }
    private func maxRadius(_ v: [BarVertex]) -> Float { v.map { hypotf($0.position.x, $0.position.y) }.max() ?? 0 }
    private func allFinite(_ v: [BarVertex]) -> Bool { v.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite } }

    // MARK: - Field-read tests (each tunable actually drives output)

    func testBurstParticlesMaxScalesCount() {
        XCTAssertGreaterThan(count(burstFrame({ $0.fireworksBurstParticlesMax = 200 })),
                             count(burstFrame({ $0.fireworksBurstParticlesMax = 20 })))
    }
    func testBurstParticlesMinFloorRaisesCount() {
        // burstParticlesMax = 1 with scale < 1 -> Int(max*scale) = 0, so the floor governs.
        XCTAssertGreaterThan(count(burstFrame({ $0.fireworksBurstParticlesMax = 1; $0.fireworksBurstParticlesMin = 30 }, intensity: 0)),
                             count(burstFrame({ $0.fireworksBurstParticlesMax = 1; $0.fireworksBurstParticlesMin = 0 }, intensity: 0)))
    }
    func testBurstScaleBaseScalesCount() {
        XCTAssertGreaterThan(count(burstFrame({ $0.fireworksBurstScaleBase = 2.0 })),
                             count(burstFrame({ $0.fireworksBurstScaleBase = 0.2 })))
    }
    func testBurstScaleIntensityScalesCount() {
        // Same intensity, larger coeff -> larger scale -> more particles.
        XCTAssertGreaterThan(count(burstFrame({ $0.fireworksBurstScaleIntensity = 3.0 }, intensity: 1.0)),
                             count(burstFrame({ $0.fireworksBurstScaleIntensity = 0.0 }, intensity: 1.0)))
    }
    func testBaseSpeedWidensSpread() {
        XCTAssertGreaterThan(maxRadius(burstRun({ $0.fireworksBaseSpeed = 2.0 }, frames: 8)),
                             maxRadius(burstRun({ $0.fireworksBaseSpeed = 0.1 }, frames: 8)))
    }
    func testSpreadSpeedWidensExtent() {
        // spread 0 -> uniform radial speed ring; spread > 0 lets some go faster/farther.
        XCTAssertGreaterThan(maxRadius(burstRun({ $0.fireworksSpreadSpeed = 1.5 }, frames: 8)),
                             maxRadius(burstRun({ $0.fireworksSpreadSpeed = 0.0 }, frames: 8)))
    }
    func testGravityLowersApex() {
        XCTAssertLessThan(maxY(burstRun({ $0.fireworksGravity = 4.0 }, frames: 12)),
                          maxY(burstRun({ $0.fireworksGravity = 0.0 }, frames: 12)))
    }
    func testDragWidensSpreadWhenNearOne() {
        // Drag closer to 1 damps velocity less -> particles travel farther.
        XCTAssertGreaterThan(maxRadius(burstRun({ $0.fireworksDrag = 1.0 }, frames: 12)),
                             maxRadius(burstRun({ $0.fireworksDrag = 0.85 }, frames: 12)))
    }
    func testBaseLifetimeKeepsMoreParticlesAlive() {
        XCTAssertGreaterThan(count(burstRun({ $0.fireworksBaseLifetime = 5.0 }, frames: 40)),
                             count(burstRun({ $0.fireworksBaseLifetime = 0.3 }, frames: 40)))
    }
    func testLifetimeJitterChangesOutput() {
        XCTAssertNotEqual(burstRun({ $0.fireworksLifetimeJitter = 0.9 }, frames: 20),
                          burstRun({ $0.fireworksLifetimeJitter = 0.0 }, frames: 20))
    }
    func testMinLifetimeKeepsShortLivedParticlesAlive() {
        // Tiny baseLifetime -> computed lifetime is small; a large floor keeps them alive.
        XCTAssertGreaterThan(count(burstRun({ $0.fireworksBaseLifetime = 0.2; $0.fireworksMinLifetime = 3.0 }, frames: 30)),
                             count(burstRun({ $0.fireworksBaseLifetime = 0.2; $0.fireworksMinLifetime = 0.05 }, frames: 30)))
    }
    func testBaseSizeScalesQuad() {
        XCTAssertGreaterThan(xSpan(burstFrame({ $0.fireworksBaseSize = 0.04 })),
                             xSpan(burstFrame({ $0.fireworksBaseSize = 0.001 })))
    }
    func testBurstHalfXSpreadsCentersHorizontally() {
        // Collapse particles onto their centers (no speed, no size) and fire several
        // bursts; the x-extent of the sampled centers scales with burstHalfX.
        func cfg(_ hx: Double) -> (inout VisualizerSettings) -> Void {
            { $0.fireworksBaseSpeed = 0; $0.fireworksSpreadSpeed = 0; $0.fireworksBaseSize = 0
              $0.fireworksBurstHalfX = hx; $0.fireworksBurstHalfY = 0 }
        }
        XCTAssertGreaterThan(xSpan(fillRun(cfg(1.0), beats: 8)), xSpan(fillRun(cfg(0.05), beats: 8)))
    }
    func testBurstHalfYSpreadsCentersVertically() {
        func cfg(_ hy: Double) -> (inout VisualizerSettings) -> Void {
            { $0.fireworksBaseSpeed = 0; $0.fireworksSpreadSpeed = 0; $0.fireworksBaseSize = 0
              $0.fireworksBurstHalfX = 0; $0.fireworksBurstHalfY = hy; $0.fireworksGravity = 0 }
        }
        XCTAssertGreaterThan(ySpan(fillRun(cfg(1.0), beats: 8)), ySpan(fillRun(cfg(0.05), beats: 8)))
    }
    func testAngleJitterChangesOutput() {
        XCTAssertNotEqual(burstRun({ $0.fireworksAngleJitter = 0.5 }, frames: 8),
                          burstRun({ $0.fireworksAngleJitter = 0.0 }, frames: 8))
    }

    // MARK: - maxParticles stateful reallocation

    func testMaxParticlesDrivesCapacityFromSettings() {
        // init capacity differs from settings; the visualizer reconciles to settings.
        let v = burstRun({ $0.fireworksMaxParticles = 40; $0.fireworksBurstParticlesMax = 200; $0.fireworksBaseLifetime = 5 },
                         frames: 4, initCapacity: 600)
        XCTAssertLessThanOrEqual(v.count, 40 * 6)
        XCTAssertEqual(v.count % 6, 0)
    }
    func testMaxParticlesReallocCanGrowAndShrinkAcrossFrames() {
        let viz = FireworksVisualizer(maxParticles: 600, seed: 3)
        var s = VisualizerSettings.defaults
        s.fireworksBaseLifetime = 100; s.fireworksBurstParticlesMax = 400
        s.fireworksBurstScaleBase = 2; s.fireworksBurstScaleIntensity = 3
        var t = 0.0
        func step(_ cap: Int, beats: Int) -> [BarVertex] {
            s.fireworksMaxParticles = cap
            var last: [BarVertex] = []
            for _ in 0..<beats {
                last = viz.makeVertices(frame: frame(beat: true, intensity: 1.0, t: t), settings: s, aspect: 1); t += 1.0/60.0
            }
            return last
        }
        let grown = step(800, beats: 6)
        XCTAssertLessThanOrEqual(grown.count, 800 * 6)
        let shrunk = step(40, beats: 6)
        XCTAssertLessThanOrEqual(shrunk.count, 40 * 6)
        XCTAssertTrue(allFinite(shrunk))
    }

    // MARK: - Clamp tests (persisted/edited out-of-range values snap to nearest bound)

    func testMaxParticlesZeroClampsToOneNoCrash() {
        let v = burstRun({ $0.fireworksMaxParticles = 0; $0.fireworksBaseLifetime = 5 }, frames: 4)
        XCTAssertLessThanOrEqual(v.count, 6)        // capacity clamped to 1 -> at most one particle
        XCTAssertTrue(allFinite(v))
    }
    func testMaxParticlesNegativeClampsToOne() {
        XCTAssertEqual(count(burstRun({ $0.fireworksMaxParticles = -50; $0.fireworksBaseLifetime = 5 }, frames: 4)),
                       count(burstRun({ $0.fireworksMaxParticles = 1; $0.fireworksBaseLifetime = 5 }, frames: 4)))
    }
    func testMaxParticlesCapsAtFourThousand() {
        // Fill the ring far past 4000 with huge bursts + infinite lifetime: 10000 and 4000
        // both clamp to 4000 alive (identical); 3000 differs.
        func fill(_ cap: Int) -> Int {
            count(fillRun({ $0.fireworksMaxParticles = cap; $0.fireworksBaseLifetime = 1000
                            $0.fireworksBurstParticlesMax = 400; $0.fireworksBurstScaleBase = 2
                            $0.fireworksBurstScaleIntensity = 3 }, beats: 6, seed: 5))
        }
        XCTAssertEqual(fill(10000), fill(4000))
        XCTAssertNotEqual(fill(4000), fill(3000))
    }
    func testBurstParticlesMaxCapsAtFourHundred() {
        // 10000 and 400 both clamp to 400 base count (identical burst); 300 differs.
        XCTAssertEqual(count(burstFrame({ $0.fireworksBurstParticlesMax = 10000 })),
                       count(burstFrame({ $0.fireworksBurstParticlesMax = 400 })))
        XCTAssertNotEqual(count(burstFrame({ $0.fireworksBurstParticlesMax = 400 })),
                          count(burstFrame({ $0.fireworksBurstParticlesMax = 300 })))
    }
    func testPathologicalScaleDoesNotTrapAndStaysBounded() {
        // A persisted/edited huge scale field narrows to Float.infinity, and
        // Int(Float.infinity) / Int(Float.nan) TRAP in Swift. The per-burst count must
        // saturate the float product before Int(...) so a garbage scale can't crash and
        // the burst stays bounded by the ring capacity.
        let cap = 600
        // Huge finite burstScaleBase -> Float(+inf) -> scale = +inf.
        let big = burstFrame({ $0.fireworksBurstScaleBase = 1e308 }, intensity: 1.0, initCapacity: cap)
        XCTAssertLessThanOrEqual(big.count, cap * 6)
        XCTAssertTrue(allFinite(big))
        // Huge finite burstScaleIntensity -> Float(+inf) at intensity 1 -> scale = +inf.
        let bigI = burstFrame({ $0.fireworksBurstScaleIntensity = 1e308 }, intensity: 1.0, initCapacity: cap)
        XCTAssertLessThanOrEqual(bigI.count, cap * 6)
        XCTAssertTrue(allFinite(bigI))
        // +inf base plus -inf*intensity yields a NaN scale; must also be crash-free/bounded.
        let nan = burstFrame({ $0.fireworksBurstScaleBase = 1e308; $0.fireworksBurstScaleIntensity = -1e308 },
                             intensity: 1.0, initCapacity: cap)
        XCTAssertLessThanOrEqual(nan.count, cap * 6)
        XCTAssertTrue(allFinite(nan))
    }
    func testBurstParticlesMaxClampsToOneWhenZeroOrNegative() {
        // max <= 0 clamps to 1; with the default min floor (8) the burst still emits >= 8.
        let v = burstFrame({ $0.fireworksBurstParticlesMax = 0 }, intensity: 0)
        XCTAssertTrue(allFinite(v))
        XCTAssertEqual(count(burstFrame({ $0.fireworksBurstParticlesMax = -10 }, intensity: 0)),
                       count(burstFrame({ $0.fireworksBurstParticlesMax = 1 }, intensity: 0)))
    }
    func testBurstParticlesMinClampedToBurstMax() {
        // min above max must clamp down to max, so count cannot exceed Int(max*scale)'s
        // companion; min = 1000 with max = 10 yields the same count as min = 10.
        XCTAssertEqual(count(burstFrame({ $0.fireworksBurstParticlesMax = 10; $0.fireworksBurstParticlesMin = 1000 }, intensity: 0)),
                       count(burstFrame({ $0.fireworksBurstParticlesMax = 10; $0.fireworksBurstParticlesMin = 10 }, intensity: 0)))
    }
    func testBurstParticlesMinNegativeClampsToZero() {
        XCTAssertEqual(count(burstFrame({ $0.fireworksBurstParticlesMax = 1; $0.fireworksBurstParticlesMin = -50 }, intensity: 0)),
                       count(burstFrame({ $0.fireworksBurstParticlesMax = 1; $0.fireworksBurstParticlesMin = 0 }, intensity: 0)))
    }
    func testGravityNegativeClampsToZero() {
        XCTAssertEqual(burstRun({ $0.fireworksGravity = -3 }, frames: 12),
                       burstRun({ $0.fireworksGravity = 0 }, frames: 12))
    }
    func testDragClampsToUnitRange() {
        XCTAssertEqual(burstRun({ $0.fireworksDrag = 1.5 }, frames: 12),
                       burstRun({ $0.fireworksDrag = 1.0 }, frames: 12))
        XCTAssertEqual(burstRun({ $0.fireworksDrag = -1 }, frames: 12),
                       burstRun({ $0.fireworksDrag = 0 }, frames: 12))
        XCTAssertTrue(allFinite(burstRun({ $0.fireworksDrag = 9 }, frames: 12)))
    }
    func testBaseLifetimeClampPositiveStaysFinite() {
        XCTAssertTrue(allFinite(burstRun({ $0.fireworksBaseLifetime = 0 }, frames: 12)))
        XCTAssertTrue(allFinite(burstRun({ $0.fireworksBaseLifetime = -5 }, frames: 12)))
    }
    func testMinLifetimeClampPositiveStaysFinite() {
        XCTAssertTrue(allFinite(burstRun({ $0.fireworksMinLifetime = 0 }, frames: 12)))
        XCTAssertTrue(allFinite(burstRun({ $0.fireworksMinLifetime = -5 }, frames: 12)))
    }
    func testBaseSizeNegativeClampsToZero() {
        XCTAssertEqual(xSpan(burstFrame({ $0.fireworksBaseSize = -1 })),
                       xSpan(burstFrame({ $0.fireworksBaseSize = 0 })), accuracy: 0)
    }

    // MARK: - Defaults are not clamped (sanity: default values sit inside their ranges)

    func testDefaultsNotClampedToBounds() {
        XCTAssertNotEqual(burstRun({ $0.fireworksGravity = 0 }, frames: 12), burstRun({ _ in }, frames: 12)) // default gravity 0.5 != 0
        XCTAssertNotEqual(burstFrame({ $0.fireworksBurstParticlesMax = 1 }), burstFrame({ _ in }))           // default max 60 != 1
    }
}

