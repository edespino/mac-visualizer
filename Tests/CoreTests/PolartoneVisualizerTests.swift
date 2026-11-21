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

final class PolartoneVisualizerTests: XCTestCase {
    private func frame(_ waveform: [Float], timestamp: CFTimeInterval = 0) -> AudioFrame {
        AudioFrame(bands: [], bandPeaks: [], waveform: waveform, rms: 0, peak: 0, timestamp: timestamp)
    }

    private func settings(_ mutate: (inout VisualizerSettings) -> Void) -> VisualizerSettings {
        var s = VisualizerSettings.defaults
        mutate(&s)
        return s
    }

    func testSixVerticesPerClosedWaveformSegment() {
        // Segment count is driven by polartonePointCount; set it to match the
        // 4-sample waveform (identity resample) so this stays a "6 verts/segment" check.
        let vertices = PolartoneVisualizer().makeVertices(frame: frame([0, 0.5, 0, -0.5]),
                                                          settings: settings { $0.polartonePointCount = 4 },
                                                          aspect: 1)
        XCTAssertEqual(vertices.count, 4 * 6)
    }

    func testEmptyWaveformEmitsBaseRing() {
        // The old fixed 128-sample fallback is now folded into polartonePointCount (default 256).
        let vertices = PolartoneVisualizer().makeVertices(frame: frame([]),
                                                          settings: .defaults,
                                                          aspect: 1)
        XCTAssertEqual(vertices.count, 256 * 6)
    }

    func testSilentWaveformIsCleanRing() {
        let vertices = PolartoneVisualizer().makeVertices(frame: frame([Float](repeating: 0, count: 64)),
                                                          settings: .defaults,
                                                          aspect: 1)
        let radii = segmentStartCenters(vertices).map { simd_length($0) }
        let minRadius = radii.min()!
        let maxRadius = radii.max()!
        XCTAssertEqual(minRadius, maxRadius, accuracy: 0.002)
        XCTAssertEqual((minRadius + maxRadius) / 2, 0.46, accuracy: 0.002)
    }

    func testWaveformChangesPolarRadius() {
        let vertices = PolartoneVisualizer().makeVertices(frame: frame([1, 0, -1, 0]),
                                                          settings: settings { $0.polartonePointCount = 4 },
                                                          aspect: 1)
        let centers = segmentStartCenters(vertices)
        XCTAssertGreaterThan(simd_length(centers[0]), simd_length(centers[2]))
    }

    // MARK: - New scalar controls (defaults preserve the prior look)

    func testDefaultPointCountResamplesToTwoFiftySix() {
        // Any-length waveform is resampled to the default point count (256).
        let vertices = PolartoneVisualizer().makeVertices(frame: frame([Float](repeating: 0, count: 100)),
                                                          settings: .defaults,
                                                          aspect: 1)
        XCTAssertEqual(vertices.count, 256 * 6)
    }

    func testPointCountControlsSegmentCount() {
        let vertices = PolartoneVisualizer().makeVertices(frame: frame([Float](repeating: 0, count: 256)),
                                                          settings: settings { $0.polartonePointCount = 64 },
                                                          aspect: 1)
        XCTAssertEqual(vertices.count, 64 * 6)
    }

    func testPointCountClampsBelowThree() {
        // Defensive clamp: a degenerate point count still yields a valid ring (>= 3 segments).
        let vertices = PolartoneVisualizer().makeVertices(frame: frame([Float](repeating: 0, count: 8)),
                                                          settings: settings { $0.polartonePointCount = 0 },
                                                          aspect: 1)
        XCTAssertEqual(vertices.count, 3 * 6)
    }

    func testDefaultLineHalfThicknessMatchesPriorLiteral() {
        // The cross-segment width = 2 × halfThickness. Default 0.006 × oscilloscopeThickness 1.0 → 0.012.
        let vertices = PolartoneVisualizer().makeVertices(frame: frame([Float](repeating: 0.3, count: 256)),
                                                          settings: .defaults,
                                                          aspect: 1)
        XCTAssertEqual(crossThickness(vertices, segment: 0), 0.012, accuracy: 1e-5)
    }

    func testLineHalfThicknessControlScalesWidth() {
        let vertices = PolartoneVisualizer().makeVertices(frame: frame([Float](repeating: 0.3, count: 256)),
                                                          settings: settings { $0.polartoneLineHalfThickness = 0.012 },
                                                          aspect: 1)
        XCTAssertEqual(crossThickness(vertices, segment: 0), 0.024, accuracy: 1e-5)
    }

    func testLineHalfThicknessStillRespectsOscilloscopeMultiplier() {
        // Reconciliation: effective width = polartoneLineHalfThickness × oscilloscopeThickness.
        let vertices = PolartoneVisualizer().makeVertices(
            frame: frame([Float](repeating: 0.3, count: 256)),
            settings: settings { $0.oscilloscopeThickness = 2.0 },   // 0.006 × 2.0 = 0.012 half → 0.024 cross
            aspect: 1)
        XCTAssertEqual(crossThickness(vertices, segment: 0), 0.024, accuracy: 1e-5)
    }

    func testDefaultRotationIsStaticAcrossTimestamps() {
        // rotationSpeed 0 + phaseOffset 0 → ring identical regardless of frame.timestamp.
        let wave = (0..<256).map { sinf(Float($0) / 256 * 2 * .pi * 3) }
        let v0 = PolartoneVisualizer().makeVertices(frame: frame(wave, timestamp: 0), settings: .defaults, aspect: 1)
        let v5 = PolartoneVisualizer().makeVertices(frame: frame(wave, timestamp: 5), settings: .defaults, aspect: 1)
        XCTAssertEqual(v0.count, v5.count)
        for (a, b) in zip(v0, v5) {
            XCTAssertEqual(a.position.x, b.position.x, accuracy: 1e-6)
            XCTAssertEqual(a.position.y, b.position.y, accuracy: 1e-6)
        }
    }

    func testRotationSpeedRotatesRing() {
        let wave = (0..<256).map { sinf(Float($0) / 256 * 2 * .pi * 3) }
        let s = settings { $0.polartoneRotationSpeed = 1 }
        let v0 = PolartoneVisualizer().makeVertices(frame: frame(wave, timestamp: 0), settings: s, aspect: 1)
        let v1 = PolartoneVisualizer().makeVertices(frame: frame(wave, timestamp: 1), settings: s, aspect: 1)
        let moved = zip(v0, v1).contains { abs($0.position.x - $1.position.x) > 1e-3 }
        XCTAssertTrue(moved, "non-zero rotation speed should rotate the ring over time")
    }

    func testPhaseOffsetRotatesStartAngle() {
        // A quarter-turn phase offset rotates the whole ring; the first segment center moves.
        let wave = [Float](repeating: 0.5, count: 256)
        let base = segmentStartCenters(PolartoneVisualizer().makeVertices(frame: frame(wave), settings: .defaults, aspect: 1))
        let rotated = segmentStartCenters(PolartoneVisualizer().makeVertices(
            frame: frame(wave), settings: settings { $0.polartonePhaseOffset = .pi / 2 }, aspect: 1))
        XCTAssertGreaterThan(simd_distance(base[0], rotated[0]), 0.1)
    }

    func testWaveformClampSaturatesRadius() {
        // Default clamp 1 lets a full-scale sample push radius to baseRadius + amplitude.
        let wave: [Float] = [1] + [Float](repeating: 0, count: 255)
        let full = segmentStartCenters(PolartoneVisualizer().makeVertices(frame: frame(wave), settings: .defaults, aspect: 1))
        // clamp 0.5 caps the deflection to half.
        let clamped = segmentStartCenters(PolartoneVisualizer().makeVertices(
            frame: frame(wave), settings: settings { $0.polartoneWaveformClamp = 0.5 }, aspect: 1))
        XCTAssertGreaterThan(simd_length(full[0]), simd_length(clamped[0]))
        XCTAssertEqual(simd_length(full[0]), 0.46 + 1.0 * 0.22, accuracy: 1e-4)
        XCTAssertEqual(simd_length(clamped[0]), 0.46 + 0.5 * 0.22, accuracy: 1e-4)
    }

    func testColorFloorAffectsSilentRingColor() {
        // A silent ring samples the palette at max(0, colorFloor). Lowering the floor changes the color.
        let wave = [Float](repeating: 0, count: 256)
        let dflt = PolartoneVisualizer().makeVertices(frame: frame(wave), settings: .defaults, aspect: 1)
        let lowFloor = PolartoneVisualizer().makeVertices(
            frame: frame(wave), settings: settings { $0.polartoneColorFloor = 0 }, aspect: 1)
        let changed = zip(dflt, lowFloor).contains {
            abs($0.color.x - $1.color.x) > 1e-4 || abs($0.color.y - $1.color.y) > 1e-4 || abs($0.color.z - $1.color.z) > 1e-4
        }
        XCTAssertTrue(changed, "color floor should change the sampled palette color of a silent ring")
    }

    func testDownsampleReachesLateSourceSamples() {
        // Downsample case (waveform longer than the configured point count): a
        // monotonically rising ramp must surface in LATE segments, proving the
        // nearest-neighbour stride in sample(at:) reaches waveform.count - 1 and
        // does not collapse onto an early sample. If the resample clamp ever
        // regressed from `waveform.count - 1` to `count - 1`, every segment past
        // index `count - 1` would pin to an early low value and this fails.
        let length = 1024
        let pointCount = 64
        let ramp = (0..<length).map { Float($0) / Float(length - 1) }   // 0 … 1, rising
        let vertices = PolartoneVisualizer().makeVertices(
            frame: frame(ramp),
            settings: settings { $0.polartonePointCount = pointCount },
            aspect: 1)
        let centers = segmentStartCenters(vertices)
        XCTAssertEqual(centers.count, pointCount)

        let firstRadius = simd_length(centers.first!)   // samples ramp[0] = 0 → baseRadius 0.46
        let lastRadius = simd_length(centers.last!)      // must sample a late, high ramp value
        XCTAssertGreaterThan(lastRadius, firstRadius + 0.1)
        // Correct stride reaches ramp[~1008] ≈ 0.985 → radius ≈ 0.46 + 0.985 × 0.22 ≈ 0.677.
        // A clamp-to-(count - 1) regression would cap the last segment near 0.474.
        XCTAssertGreaterThan(lastRadius, 0.6)
    }

    func testAspectCorrectionKeepsCircleCircularInWideViewport() {
        let vertices = PolartoneVisualizer().makeVertices(frame: frame([Float](repeating: 0, count: 64)),
                                                          settings: .defaults,
                                                          aspect: 2)
        let centers = segmentStartCenters(vertices)
        let maxX = centers.map { abs($0.x) }.max()!
        let maxY = centers.map { abs($0.y) }.max()!
        XCTAssertEqual(maxX, maxY / 2, accuracy: 0.01)
    }

    func testAllVerticesStayInClipSpace() {
        let waveform = (0..<256).map { sinf(Float($0) / 256 * 2 * .pi * 3) }
        for aspect: Float in [0.5, 1, 2] {
            let vertices = PolartoneVisualizer().makeVertices(frame: frame(waveform),
                                                              settings: .defaults,
                                                              aspect: aspect)
            for vertex in vertices {
                XCTAssertLessThanOrEqual(abs(vertex.position.x), 1.0001, "x out at aspect \(aspect)")
                XCTAssertLessThanOrEqual(abs(vertex.position.y), 1.0001, "y out at aspect \(aspect)")
            }
        }
    }

    // MARK: - Ring-mode regression guard (survives the struct → class conversion)

    func testRingModeOutputUnchangedAfterClassConversion() {
        // Deterministic sine waveform + default settings (.ring). Pins concrete,
        // analytically-known invariants so the struct → class refactor cannot
        // silently change the default look. The broader ring suite above
        // (radius / thickness / rotation / phase / clamp / aspect) is the rest
        // of the oracle and must also stay green through the conversion.
        let wave = (0..<256).map { sinf(Float($0) / 256 * 2 * .pi * 3) }
        let viz = PolartoneVisualizer()
        let verts = viz.makeVertices(frame: frame(wave), settings: .defaults, aspect: 1)

        XCTAssertEqual(verts.count, 256 * 6)

        // Two instances must agree exactly (determinism is preserved by the refactor).
        let verts2 = PolartoneVisualizer().makeVertices(frame: frame(wave), settings: .defaults, aspect: 1)
        XCTAssertEqual(verts.count, verts2.count)
        for (a, b) in zip(verts, verts2) {
            XCTAssertEqual(a.position.x, b.position.x, accuracy: 1e-7)
            XCTAssertEqual(a.position.y, b.position.y, accuracy: 1e-7)
            XCTAssertEqual(a.color.x, b.color.x, accuracy: 1e-7)
        }

        // A silent ring with the same settings sits exactly at baseRadius 0.46;
        // index 0 → angle 0 → (0.46, 0), index 64 → angle π/2 → (0, 0.46).
        let silent = segmentStartCenters(
            viz.makeVertices(frame: frame([Float](repeating: 0, count: 256)), settings: .defaults, aspect: 1))
        XCTAssertEqual(silent[0].x, 0.46, accuracy: 1e-5)
        XCTAssertEqual(silent[0].y, 0, accuracy: 1e-5)
        XCTAssertEqual(silent[64].x, 0, accuracy: 1e-5)
        XCTAssertEqual(silent[64].y, 0.46, accuracy: 1e-5)
    }

    func testStyleMetadataAndFactory() {
        XCTAssertTrue(VisualizerStyle.polartone.makeVisualizer() is PolartoneVisualizer)
        XCTAssertEqual(VisualizerStyle.polartone.displayName, "Polartone")
        XCTAssertFalse(VisualizerStyle.polartone.usesRoundParticles)
        XCTAssertNil(VisualizerStyle.polartone.customShader(settings: .defaults))
        XCTAssertEqual(VisualizerStyle.beatCounter.next, .polartone)
        XCTAssertEqual(VisualizerStyle.polartone.next, .octaveMeatballs)
        XCTAssertEqual(VisualizerStyle.polartone.previous, .beatCounter)
    }

    // MARK: - Spiral render mode (breathing spiral state machine)

    private func spiralSettings(inner: Float = 0.05, revs: Float = 8,
                                start: PolartoneStartDirection = .inward) -> VisualizerSettings {
        var s = VisualizerSettings.defaults
        s.polartoneRenderMode = .spiral
        s.polartoneRadius = 0.9              // outer bound
        s.polartoneInnerThreshold = inner
        s.polartoneDriftRevolutions = revs
        s.polartoneStartDirection = start
        s.polartoneRotationSpeed = 1.0
        return s
    }

    /// Drives N frames at a fixed dt by advancing the frame timestamp; silent waveform.
    @discardableResult
    private func drive(_ viz: PolartoneVisualizer, _ settings: VisualizerSettings,
                       frames: Int, dt: Double) -> [[BarVertex]] {
        var out: [[BarVertex]] = []
        var t = 0.0
        for _ in 0..<frames {
            out.append(viz.makeVertices(frame: frame([Float](repeating: 0, count: 256), timestamp: t),
                                        settings: settings, aspect: 1))
            t += dt
        }
        return out
    }

    func testSpiralTrailColoringIsFrameStable() {
        // A point's color is fixed by the deflection at the frame it was appended;
        // it must NOT recolor as the base radius drifts on later frames. Drive a
        // constant, strongly-deflecting waveform through a slow inward sweep and
        // assert point 0's emitted color is identical early vs. after the base has
        // drifted. (Under the old live-radius coloring, point 0 shimmered.)
        let viz = PolartoneVisualizer()
        var s = spiralSettings(revs: 8)            // slow enough that point 0 is never trimmed/reversed
        s.polartoneAmplitude = 0.5
        let wave = [Float](repeating: 0.8, count: 256)   // deflection 0.4, well above the color floor

        _ = viz.makeVertices(frame: frame(wave, timestamp: 0), settings: s, aspect: 1)
        let early = viz.makeVertices(frame: frame(wave, timestamp: 1.0 / 60.0), settings: s, aspect: 1)

        var t = 2.0 / 60.0
        for _ in 0..<150 {   // let the base radius drift substantially
            _ = viz.makeVertices(frame: frame(wave, timestamp: t), settings: s, aspect: 1)
            t += 1.0 / 60.0
        }
        let later = viz.makeVertices(frame: frame(wave, timestamp: t), settings: s, aspect: 1)

        // vertex 0 of the emitted polyline carries point 0's color.
        XCTAssertEqual(early[0].color.x, later[0].color.x, accuracy: 1e-6)
        XCTAssertEqual(early[0].color.y, later[0].color.y, accuracy: 1e-6)
        XCTAssertEqual(early[0].color.z, later[0].color.z, accuracy: 1e-6)
    }

    func testSpiralRadiusMonotonicWithinInwardSweep() {
        let viz = PolartoneVisualizer()
        let s = spiralSettings(revs: 50)   // slow enough to stay in one inward sweep
        drive(viz, s, frames: 30, dt: 1.0 / 60.0)
        XCTAssertLessThan(viz.debugSpiralRadius, 0.9)            // moved inward from the outer bound
        XCTAssertEqual(viz.debugSpiralDirection, .inward)       // not yet reversed
    }

    func testSpiralWipesAndReversesAtInnerThreshold() {
        let viz = PolartoneVisualizer()
        let s = spiralSettings(revs: 1)    // fast: reach the inner threshold quickly
        var reversed = false
        var t = 0.0
        for _ in 0..<2000 {
            _ = viz.makeVertices(frame: frame([Float](repeating: 0, count: 256), timestamp: t),
                                 settings: s, aspect: 1)
            if viz.debugSpiralDirection == .outward { reversed = true; break }
            t += 1.0 / 60.0
        }
        XCTAssertTrue(reversed, "spiral should reverse to outward after collapsing inward")
    }

    func testSpiralBufferNeverExceedsCap() {
        // revs 40 keeps a single inward sweep going (no reversal for ~15k frames),
        // so 4100 frames fill the 4000-point cap and then exercise the ring-buffer
        // overwrite branch (frames 4001–4100). Frame outputs are inspected inline
        // (not retained) to avoid holding thousands of vertex arrays in memory.
        let viz = PolartoneVisualizer()
        let s = spiralSettings(revs: 40)
        var maxEmitted = 0
        var t = 0.0
        for _ in 0..<4100 {
            let verts = viz.makeVertices(frame: frame([Float](repeating: 0, count: 256), timestamp: t),
                                         settings: s, aspect: 1)
            maxEmitted = max(maxEmitted, verts.count)
            // The stored buffer never exceeds the cap...
            XCTAssertLessThanOrEqual(viz.debugSpiralPointCount, 4000)
            t += 1.0 / 60.0
        }
        // ...and the cap is actually reached (the overwrite branch was exercised).
        XCTAssertEqual(viz.debugSpiralPointCount, 4000)
        // The emitted (visible) polyline also respects the cap: at most
        // (cap - 1) segments × 6 vertices.
        XCTAssertLessThanOrEqual(maxEmitted, (4000 - 1) * 6)
    }

    func testRingBufferWrapOrderingIsOldestToNewest() {
        // White-box: drive the real ring buffer PAST capacity with strictly
        // increasing, distinguishable values, then assert the logical order
        // (oldest→newest, exactly what emission iterates) survives the wrap with no
        // stale or duplicated slots.
        let viz = PolartoneVisualizer()
        let cap = 4000
        let n = cap + 5                       // append past capacity → force wrap
        let values = (0..<n).map { Float($0) } // strictly increasing
        let result = viz.debugRingBufferLogicalValues(appending: values)

        XCTAssertEqual(result.count, cap)              // holds exactly the last `cap`
        XCTAssertGreaterThan(result.head, 0)           // wrap occurred (head advanced)
        XCTAssertEqual(result.ordered.first, Float(n - cap))  // oldest surviving = values[n-cap]
        XCTAssertEqual(result.ordered.last, Float(n - 1))     // newest = values[n-1]
        for i in 1..<result.ordered.count {
            // strictly increasing → correct oldest→newest order, no stale/dup slots
            XCTAssertGreaterThan(result.ordered[i], result.ordered[i - 1])
        }
    }

    func testSpiralWaveformPhaseFreeRunsWhenBufferFull() {
        // A ramp waveform maps each sample index to a distinct value. Once the ring
        // buffer is full, the per-point sample index must keep advancing (a free-
        // running phase) rather than sticking — so successive newest points still
        // read DIFFERENT waveform positions. With the old spiralCount-based index,
        // spiralCount caps at maxSpiralPoints and the index froze (constant value).
        let viz = PolartoneVisualizer()
        let s = spiralSettings(revs: 40)   // no reversal: buffer fills and stays full
        let ramp = (0..<256).map { Float($0) / 255.0 }
        var t = 0.0
        for _ in 0..<4001 {                 // fill the buffer to capacity
            _ = viz.makeVertices(frame: frame(ramp, timestamp: t), settings: s, aspect: 1)
            t += 1.0 / 60.0
        }
        XCTAssertEqual(viz.debugSpiralPointCount, 4000)   // full
        let v1 = viz.debugSpiralLastValue
        _ = viz.makeVertices(frame: frame(ramp, timestamp: t), settings: s, aspect: 1)
        let v2 = viz.debugSpiralLastValue
        // Index advanced → the newest point read a different ramp position.
        XCTAssertGreaterThan(abs(v2 - v1), 1e-4)
    }

    func testSpiralDtClampPreventsJump() {
        let viz = PolartoneVisualizer()
        let s = spiralSettings()
        _ = viz.makeVertices(frame: frame([Float](repeating: 0, count: 256), timestamp: 0),
                             settings: s, aspect: 1)
        _ = viz.makeVertices(frame: frame([Float](repeating: 0, count: 256), timestamp: 10_000),  // huge gap
                             settings: s, aspect: 1)
        XCTAssertGreaterThanOrEqual(viz.debugSpiralRadius, 0.0)
        XCTAssertLessThanOrEqual(viz.debugSpiralRadius, 0.9)               // no unbounded jump
    }

    private func spiralFrame(_ t: Double) -> AudioFrame {
        frame([Float](repeating: 0, count: 256), timestamp: t)
    }

    func testSpiralReseedsWhenStartDirectionChangesMidSweep() {
        let viz = PolartoneVisualizer()
        var s = spiralSettings(start: .inward)   // outer 0.9, inner 0.05
        drive(viz, s, frames: 30, dt: 1.0 / 60.0)
        XCTAssertEqual(viz.debugSpiralDirection, .inward)
        XCTAssertLessThan(viz.debugSpiralRadius, 0.9)   // drifted inward from the outer bound

        // Flip start direction live → re-seed outward at the inner bound.
        s.polartoneStartDirection = .outward
        _ = viz.makeVertices(frame: spiralFrame(31.0 / 60.0), settings: s, aspect: 1)
        XCTAssertEqual(viz.debugSpiralDirection, .outward)
        XCTAssertEqual(viz.debugSpiralRadius, 0.05, accuracy: 1e-4)   // reset to the inner bound
    }

    func testSpiralReseedsAfterRingRoundTrip() {
        let viz = PolartoneVisualizer()
        var s = spiralSettings(start: .inward)
        drive(viz, s, frames: 30, dt: 1.0 / 60.0)
        XCTAssertLessThan(viz.debugSpiralRadius, 0.9)

        // Switch to ring for a frame, then back to spiral: a fresh sweep must
        // re-seed at the outer bound rather than resuming mid-drift.
        s.polartoneRenderMode = .ring
        _ = viz.makeVertices(frame: spiralFrame(31.0 / 60.0), settings: s, aspect: 1)
        s.polartoneRenderMode = .spiral
        _ = viz.makeVertices(frame: spiralFrame(32.0 / 60.0), settings: s, aspect: 1)
        XCTAssertEqual(viz.debugSpiralDirection, .inward)
        XCTAssertEqual(viz.debugSpiralRadius, 0.9, accuracy: 1e-4)   // re-seeded at the outer bound
        XCTAssertEqual(viz.debugSpiralPointCount, 1)                 // buffer wiped, one fresh point
    }

    func testSpiralDoesNotReseedOnLiveScalarChanges() {
        let viz = PolartoneVisualizer()
        var s = spiralSettings(revs: 50, start: .inward)
        drive(viz, s, frames: 30, dt: 1.0 / 60.0)
        let countBefore = viz.debugSpiralPointCount
        XCTAssertLessThan(viz.debugSpiralRadius, 0.9)

        // Inner-threshold / drift / outer-radius are read live each frame and must
        // NOT trigger a re-seed: the sweep keeps accumulating in place.
        s.polartoneInnerThreshold = 0.2
        s.polartoneDriftRevolutions = 12
        s.polartoneRadius = 0.8
        _ = viz.makeVertices(frame: spiralFrame(31.0 / 60.0), settings: s, aspect: 1)
        XCTAssertEqual(viz.debugSpiralDirection, .inward)              // unchanged
        XCTAssertLessThan(viz.debugSpiralRadius, 0.9)                  // still drifting, not snapped to a bound
        XCTAssertEqual(viz.debugSpiralPointCount, countBefore + 1)    // accumulated, not wiped
    }

    func testRotationSpeedZeroStillAdvancesSpiral() {
        // Ring honors rotationSpeed 0 = static; spiral falls back to a small
        // internal angular speed so it still forms rather than degenerating.
        let viz = PolartoneVisualizer()
        var s = spiralSettings()
        s.polartoneRotationSpeed = 0
        drive(viz, s, frames: 60, dt: 1.0 / 60.0)
        XCTAssertLessThan(viz.debugSpiralRadius, 0.9)   // still drifted inward
    }

    /// Distance across a segment's start edge (vertex 0 = p0a, vertex 2 = p0b),
    /// which equals 2 × the line half-thickness for that segment.
    private func crossThickness(_ vertices: [BarVertex], segment: Int) -> Float {
        let offset = segment * 6
        let a = vertices[offset].position
        let b = vertices[offset + 2].position
        return simd_length(SIMD2<Float>(a.x - b.x, a.y - b.y))
    }

    private func segmentStartCenters(_ vertices: [BarVertex]) -> [SIMD2<Float>] {
        stride(from: 0, to: vertices.count, by: 6).map { offset in
            let a = vertices[offset].position
            let b = vertices[offset + 2].position
            return SIMD2<Float>((a.x + b.x) / 2, (a.y + b.y) / 2)
        }
    }
}
