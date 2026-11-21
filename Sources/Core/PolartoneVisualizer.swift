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
import simd

// Polar-waveform technique adapted from Matt DesLauriers' Polartone (MIT): https://github.com/mattdesl/Polartone

/// Draws the waveform in polar coordinates as a circular oscilloscope.
///
/// A `final class` (not a struct) so the spiral render mode can hold cross-frame
/// state (angle, radius, direction, accumulated points). The live instance is
/// created once per Polartone session and reused every frame (see
/// `MetalView`/`RenderProbe`), so reference semantics are correct here — no use
/// site copies the visualizer expecting independent value copies.
public final class PolartoneVisualizer: Visualizer {
    public init() {}

    // MARK: - Spiral state (spiral mode only; ring mode ignores all of this)

    enum SweepDirection: Equatable { case inward, outward }

    /// One accumulated trail point. `value` is the palette-sample input snapshotted
    /// at the frame the point was appended, so the trail's color is frame-stable and
    /// does NOT shimmer as the base radius drifts on later frames.
    private struct SpiralPoint {
        var pos: SIMD2<Float>
        var value: Float
    }

    private var spiralAngle: Float = 0
    private var spiralRadius: Float = 0
    private var spiralDirection: SweepDirection = .inward
    private var lastTimestamp: Double? = nil
    private var spiralInitialized = false
    private var lastStartDirection: PolartoneStartDirection? = nil
    private let maxSpiralPoints = 4000
    private let minAngularSpeed: Float = 0.6   // rad/s fallback when rotationSpeed == 0
    private let dtMax: Double = 0.1             // clamp for pauses / first frame

    // Fixed-capacity ring buffer for the accumulated trail. Append and trim are
    // O(1) (no per-frame O(n) removeFirst on the draw thread). The cap is reachable
    // in normal use (a default sweep runs > maxSpiralPoints frames), so the oldest
    // point is overwritten in place once full; emission walks logical order.
    private lazy var spiralStorage: [SpiralPoint] =
        [SpiralPoint](repeating: SpiralPoint(pos: .zero, value: 0), count: maxSpiralPoints)
    private var spiralHead = 0     // index of the oldest valid point
    private var spiralCount = 0    // number of valid points (≤ maxSpiralPoints)
    // Monotonic, free-running waveform-sample phase. Increments once per appended
    // point and resets per sweep. Unlike spiralCount (which caps once the buffer is
    // full), this keeps the per-point sample position rotating through the waveform
    // for the whole sweep regardless of buffer fullness.
    private var spiralSamplePhase = 0

    private func spiralReset() {
        spiralHead = 0
        spiralCount = 0
        spiralSamplePhase = 0
    }

    private func spiralAppend(_ p: SpiralPoint) {
        if spiralCount < maxSpiralPoints {
            spiralStorage[(spiralHead + spiralCount) % maxSpiralPoints] = p
            spiralCount += 1
        } else {
            spiralStorage[spiralHead] = p          // overwrite oldest in place
            spiralHead = (spiralHead + 1) % maxSpiralPoints
        }
    }

    private func spiralPoint(at i: Int) -> SpiralPoint {
        spiralStorage[(spiralHead + i) % maxSpiralPoints]
    }

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings,
                             palette: ColorPalette, aspect: Float) -> [BarVertex] {
        switch settings.polartoneRenderMode {
        case .ring:
            // Leaving spiral mode forces the next spiral entry to re-seed a fresh
            // sweep (so a ring → spiral round-trip never resumes mid-drift).
            spiralInitialized = false
            return makeRingVertices(frame: frame, settings: settings, palette: palette, aspect: aspect)
        case .spiral:
            return makeSpiralVertices(frame: frame, settings: settings, palette: palette, aspect: aspect)
        }
    }

    // MARK: - Ring (default, unchanged)

    private func makeRingVertices(frame: AudioFrame, settings: VisualizerSettings,
                                  palette: ColorPalette, aspect: Float) -> [BarVertex] {
        let waveform = frame.waveform

        // Resample the waveform locally to the configured point count. The default
        // (256) equals the live analyzer's waveform length (SpectrumAnalyzer
        // .waveformPointCount), so the common path takes the `waveform.count == count`
        // fast branch in `sample(at:)` — an exact identity resample, leaving the
        // default render byte-identical with the pre-control behavior. The point
        // count also replaces the old `fallbackSampleCount`: an empty/short waveform
        // now emits a clean base ring of `count` segments (sample → 0).
        let count = min(max(settings.polartonePointCount, 3), 8192)
        guard count >= 3 else { return [] }

        // Reconciled line width: the per-style base half-thickness (default 0.006,
        // the old hardcoded literal) times the shared `oscilloscopeThickness`
        // multiplier (default 1.0). 0.006 × 1.0 == the previous constant.
        let lineHalfThickness = max(settings.polartoneLineHalfThickness, 0) * max(settings.oscilloscopeThickness, 0)
        let baseRadius = max(settings.polartoneRadius, 0)
        let amplitude = max(settings.polartoneAmplitude, 0)
        let clamp = max(settings.polartoneWaveformClamp, 0.0001)
        let colorFloor = min(max(settings.polartoneColorFloor, 0), 1)
        // Rotate the ring over time (upstream Polartone used startAngle = time).
        // Default rotationSpeed 0 and phaseOffset 0 keep the ring static at angle 0.
        let startAngle = settings.polartonePhaseOffset
            + settings.polartoneRotationSpeed * Float(frame.timestamp)

        // Scale the longer screen axis down so the polar waveform stays circular.
        var sx: Float = 1
        var sy: Float = 1
        if aspect >= 1 {
            sx = 1 / max(aspect, 0.0001)
        } else {
            sy = max(aspect, 0.0001)
        }

        func sample(at index: Int) -> Float {
            guard !waveform.isEmpty else { return 0 }
            if waveform.count == count { return waveform[index] }
            // Nearest-neighbour resample onto the configured point count.
            let pos = Int((Float(index) / Float(count)) * Float(waveform.count))
            return waveform[min(pos, waveform.count - 1)]
        }

        func point(index: Int) -> SIMD2<Float> {
            let value = min(max(sample(at: index), -clamp), clamp)
            let radius = baseRadius + value * amplitude
            let angle = startAngle + (Float(index) / Float(count)) * 2 * Float.pi
            return SIMD2<Float>(radius * cosf(angle) * sx, radius * sinf(angle) * sy)
        }

        func color(index: Int) -> SIMD4<Float> {
            let value = min(abs(sample(at: index)), clamp)
            let c = palette.sample(at: max(value, colorFloor))
            return SIMD4<Float>(c.r, c.g, c.b, c.a)
        }

        var verts: [BarVertex] = []
        verts.reserveCapacity(count * 6)

        for index in 0..<count {
            let next = (index + 1) % count
            appendSegment(&verts,
                          from: point(index: index),
                          to: point(index: next),
                          color0: color(index: index),
                          color1: color(index: next),
                          halfThickness: lineHalfThickness)
        }

        return verts
    }

    // MARK: - Spiral (time-driven breathing spiral)

    private func makeSpiralVertices(frame: AudioFrame, settings: VisualizerSettings,
                                    palette: ColorPalette, aspect: Float) -> [BarVertex] {
        let outerBound = max(settings.polartoneRadius, 0)
        let inner = min(max(settings.polartoneInnerThreshold, 0), outerBound)

        // Seed a fresh sweep on first entry / after a fresh instance / after a ring
        // round-trip (spiralInitialized == false), OR when the start direction
        // changed since the last seed (live re-seed). Inner-threshold / drift /
        // outer-radius are read live each frame and intentionally do NOT re-seed.
        if !spiralInitialized || settings.polartoneStartDirection != lastStartDirection {
            spiralDirection = (settings.polartoneStartDirection == .inward) ? .inward : .outward
            spiralRadius = (spiralDirection == .inward) ? outerBound : inner
            spiralAngle = 0
            spiralReset()
            spiralInitialized = true
            lastStartDirection = settings.polartoneStartDirection
            lastTimestamp = nil
        }

        // dt from the frame timestamp, clamped to guard against pauses / first frame.
        let dt: Double
        if let last = lastTimestamp {
            dt = min(max(frame.timestamp - last, 0), dtMax)
        } else {
            dt = 0
        }
        lastTimestamp = frame.timestamp

        // Angular advance. rotationSpeed 0 keeps the ring static, but the spiral
        // needs a sweep to form, so fall back to a small internal angular speed.
        let angSpeed = (settings.polartoneRotationSpeed != 0) ? abs(settings.polartoneRotationSpeed) : minAngularSpeed
        spiralAngle += angSpeed * Float(dt)

        // Radial drift: cross outerBound → inner over `driftRevolutions` turns.
        let span = max(outerBound - inner, 1e-4)
        let revs = max(settings.polartoneDriftRevolutions, 0.1)
        let radialPerRadian = span / (revs * 2 * .pi)   // distance per radian of sweep
        let radialStep = radialPerRadian * angSpeed * Float(dt)
        spiralRadius += (spiralDirection == .inward) ? -radialStep : radialStep

        // Bound check → HARD WIPE + reverse direction.
        if spiralDirection == .inward && spiralRadius <= inner {
            spiralRadius = inner
            spiralDirection = .outward
            spiralReset()   // wipe in one frame
        } else if spiralDirection == .outward && spiralRadius >= outerBound {
            spiralRadius = outerBound
            spiralDirection = .inward
            spiralReset()
        }

        // Append the new point. The waveform deflects the radius (reusing amplitude
        // + clamp), so the line still wobbles to the music. Points are stored in the
        // unit plane (no aspect) so an aspect change never corrupts accumulated history.
        let waveform = frame.waveform
        let clamp = max(settings.polartoneWaveformClamp, 0.0001)
        let amplitude = max(settings.polartoneAmplitude, 0)
        let sampleValue: Float = waveform.isEmpty
            ? 0
            : min(max(waveform[spiralSamplePhase % waveform.count], -clamp), clamp)
        let deflection = sampleValue * amplitude
        let r = max(spiralRadius + deflection, 0)
        // Snapshot the palette-sample value at append time (frame-stable color).
        let pointValue = min(abs(deflection) / clamp, 1)
        spiralAppend(SpiralPoint(pos: SIMD2<Float>(r * cosf(spiralAngle), r * sinf(spiralAngle)),
                                 value: pointValue))
        spiralSamplePhase += 1   // free-running; does not cap with the buffer

        // A wiped frame (≤ 1 point) emits no line — the hard wipe in one frame.
        guard spiralCount >= 2 else { return [] }

        // Aspect correction so the spiral stays circular (same approach as the ring).
        var sx: Float = 1
        var sy: Float = 1
        if aspect >= 1 {
            sx = 1 / max(aspect, 0.0001)
        } else {
            sy = max(aspect, 0.0001)
        }

        let colorFloor = min(max(settings.polartoneColorFloor, 0), 1)
        let lineHalfThickness = max(settings.polartoneLineHalfThickness, 0) * max(settings.oscilloscopeThickness, 0)

        func scaled(_ p: SIMD2<Float>) -> SIMD2<Float> { SIMD2<Float>(p.x * sx, p.y * sy) }
        func color(_ value: Float) -> SIMD4<Float> {
            // Palette brightness from the value snapshotted at append time, floored.
            let c = palette.sample(at: max(value, colorFloor))
            return SIMD4<Float>(c.r, c.g, c.b, c.a)
        }

        var verts: [BarVertex] = []
        verts.reserveCapacity(spiralCount * 6)
        for i in 0..<(spiralCount - 1) {
            let p0 = spiralPoint(at: i)
            let p1 = spiralPoint(at: i + 1)
            appendSegment(&verts,
                          from: scaled(p0.pos),
                          to: scaled(p1.pos),
                          color0: color(p0.value),
                          color1: color(p1.value),
                          halfThickness: lineHalfThickness)
        }
        return verts
    }

    private func appendSegment(_ verts: inout [BarVertex],
                               from p0: SIMD2<Float>,
                               to p1: SIMD2<Float>,
                               color0: SIMD4<Float>,
                               color1: SIMD4<Float>,
                               halfThickness: Float) {
        let delta = p1 - p0
        let length = simd_length(delta)
        guard length > 0.000001 else { return }

        let normal = SIMD2<Float>(-delta.y, delta.x) / length * halfThickness
        let p0a = p0 + normal
        let p0b = p0 - normal
        let p1a = p1 + normal
        let p1b = p1 - normal

        verts.append(contentsOf: [
            vertex(p0a, color0),
            vertex(p1a, color1),
            vertex(p0b, color0),
            vertex(p1a, color1),
            vertex(p1b, color1),
            vertex(p0b, color0),
        ])
    }

    private func vertex(_ p: SIMD2<Float>, _ c: SIMD4<Float>) -> BarVertex {
        BarVertex(position: SIMD4<Float>(p.x, p.y, 0, 1), color: c)
    }
}

#if DEBUG
extension PolartoneVisualizer {
    /// Test-only introspection of spiral state (not used by production rendering).
    var debugSpiralRadius: Float { spiralRadius }
    var debugSpiralPointCount: Int { spiralCount }
    var debugSpiralDirection: SweepDirection { spiralDirection }
    /// Stored color value of the newest appended trail point.
    var debugSpiralLastValue: Float { spiralCount > 0 ? spiralPoint(at: spiralCount - 1).value : 0 }

    /// Drives the real ring buffer (reset, then append × N) with synthetic points
    /// and returns their stored `value`s in logical oldest→newest order — the same
    /// order emission walks via `spiralPoint(at:)`. White-box hook for the wrap-
    /// ordering test; not used by production rendering.
    func debugRingBufferLogicalValues(appending values: [Float]) -> (ordered: [Float], head: Int, count: Int) {
        spiralReset()
        for v in values {
            spiralAppend(SpiralPoint(pos: SIMD2<Float>(v, 0), value: v))
        }
        let ordered = (0..<spiralCount).map { spiralPoint(at: $0).value }
        return (ordered, spiralHead, spiralCount)
    }
}
#endif
