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

final class BeatCounterVisualizerTests: XCTestCase {
    private func frame(beat: Bool, intensity: Float = 0.8, t: TimeInterval) -> AudioFrame {
        AudioFrame(bands: [Float](repeating: 0, count: 24),
                   bandPeaks: [Float](repeating: 0, count: 24),
                   waveform: [], rms: 0, peak: 0, timestamp: t,
                   beat: beat, beatIntensity: intensity)
    }

    /// Average brightness of the quad (all six vertices share one color).
    private func luma(_ v: [BarVertex]) -> Float {
        guard let c = v.first?.color else { return 0 }
        return (c.x + c.y + c.z) / 3
    }

    func testEmitsFullScreenQuad() {
        let viz = BeatCounterVisualizer()
        let v = viz.makeVertices(frame: frame(beat: false, t: 0), settings: .defaults, aspect: 1)
        XCTAssertEqual(v.count, 6)
        // The two triangles must span the full clip-space square.
        let xs = v.map { $0.position.x }, ys = v.map { $0.position.y }
        XCTAssertEqual(xs.min(), -1); XCTAssertEqual(xs.max(), 1)
        XCTAssertEqual(ys.min(), -1); XCTAssertEqual(ys.max(), 1)
        for vert in v {
            XCTAssertLessThanOrEqual(abs(vert.position.x), 1)
            XCTAssertLessThanOrEqual(abs(vert.position.y), 1)
        }
    }

    func testColorComponentsStayInRange() {
        let viz = BeatCounterVisualizer()
        var t = 0.0
        for i in 0..<120 {
            let v = viz.makeVertices(frame: frame(beat: i % 7 == 0, intensity: 1.0, t: t),
                                     settings: .defaults, aspect: 1)
            for vert in v {
                XCTAssertGreaterThanOrEqual(vert.color.x, 0)
                XCTAssertGreaterThanOrEqual(vert.color.y, 0)
                XCTAssertGreaterThanOrEqual(vert.color.z, 0)
                XCTAssertEqual(vert.color.w, 1)
            }
            t += 1.0 / 60.0
        }
    }

    func testBeatBrightensAndDecaysOverWallClock() {
        let viz = BeatCounterVisualizer()
        _ = viz.makeVertices(frame: frame(beat: false, t: 0), settings: .defaults, aspect: 1)
        let onBeat = viz.makeVertices(frame: frame(beat: true, intensity: 1.0, t: 1.0/60),
                                      settings: .defaults, aspect: 1)
        // A few hundred ms later with no beat, brightness must have dropped.
        let later = viz.makeVertices(frame: frame(beat: false, t: 0.5),
                                     settings: .defaults, aspect: 1)
        XCTAssertGreaterThan(luma(onBeat), luma(later))
        XCTAssertGreaterThan(luma(onBeat), 0.1)
    }

    func testDecayIsFrameRateIndependent() {
        // Same wall-clock elapsed time stepped at two different frame rates (both
        // well under the 0.1s per-frame clamp) must reach the same final flash.
        func run(stepsPerSecond: Int) -> Float {
            let viz = BeatCounterVisualizer()
            _ = viz.makeVertices(frame: frame(beat: true, intensity: 1.0, t: 0), settings: .defaults, aspect: 1)
            let dt = 1.0 / Double(stepsPerSecond)
            var t = 0.0, last: [BarVertex] = []
            let total = stepsPerSecond * 3 / 10   // ~0.3s of frames
            for _ in 0..<total { t += dt; last = viz.makeVertices(frame: frame(beat: false, t: t), settings: .defaults, aspect: 1) }
            return luma(last)
        }
        XCTAssertEqual(run(stepsPerSecond: 30), run(stepsPerSecond: 120), accuracy: 2e-3)
    }

    func testIdleSettlesToDimBackground() {
        let viz = BeatCounterVisualizer()
        _ = viz.makeVertices(frame: frame(beat: true, intensity: 1.0, t: 0), settings: .defaults, aspect: 1)
        // A couple of seconds of beat-free frames at 60fps settles near black.
        var t = 0.0, idle: [BarVertex] = []
        for _ in 0..<120 { t += 1.0 / 60.0; idle = viz.makeVertices(frame: frame(beat: false, t: t), settings: .defaults, aspect: 1) }
        XCTAssertLessThan(luma(idle), 0.05)
    }

    func testSuccessiveBeatsAdvancePaletteColor() {
        let viz = BeatCounterVisualizer()
        // First beat color.
        let c1 = viz.makeVertices(frame: frame(beat: true, intensity: 1.0, t: 0),
                                  settings: .defaults, aspect: 1).first!.color
        // Second beat fires the next palette color, sampled while flash is full.
        let c2 = viz.makeVertices(frame: frame(beat: true, intensity: 1.0, t: 1.0/60),
                                  settings: .defaults, aspect: 1).first!.color
        XCTAssertNotEqual(SIMD3(c1.x, c1.y, c1.z), SIMD3(c2.x, c2.y, c2.z),
                          "consecutive beats should flash different palette colors")
    }

    func testSilenceDoesNotBrighten() {
        let viz = BeatCounterVisualizer()
        var t = 0.0
        var last: [BarVertex] = []
        for _ in 0..<60 {
            last = viz.makeVertices(frame: frame(beat: false, t: t), settings: .defaults, aspect: 1)
            t += 1.0 / 60.0
        }
        XCTAssertLessThan(luma(last), 0.05)
    }

    func testFactoryAndStyleMetadata() {
        XCTAssertTrue(VisualizerStyle.beatCounter.makeVisualizer() is BeatCounterVisualizer)
        XCTAssertEqual(VisualizerStyle.beatCounter.displayName, "Beat Counter")
        XCTAssertFalse(VisualizerStyle.beatCounter.usesRoundParticles)
        XCTAssertNil(VisualizerStyle.beatCounter.customShader(settings: .defaults))
        XCTAssertEqual(VisualizerStyle.lavaLamp.next, .beatCounter)
        XCTAssertEqual(VisualizerStyle.beatCounter.next, .polartone)
        XCTAssertEqual(VisualizerStyle.beatCounter.previous, .lavaLamp)
    }
}
