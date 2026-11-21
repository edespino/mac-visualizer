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
import QuartzCore
import simd

/// Classic XY oscilloscope (goniometer / Lissajous): plots the left channel
/// against the right channel sample-by-sample and connects consecutive points
/// with thin quads, colored by radial amplitude. At the default 45° rotation
/// mono content collapses onto the vertical axis (the pro-audio goniometer
/// convention); at 0° the raw Lissajous convention applies (L on x, R on y).
/// Stereo width therefore reads directly as horizontal spread.
///
/// Original implementation from first principles — plots `frame.waveformLeft`
/// against `frame.waveformRight`; no third-party scope code involved.
///
/// Knobs (top-level settings; defaults reproduce a clean reference scope):
///   - `xyScopeGain` deflection multiplier (clamp >= 0)
///   - `xyScopeSampleCount` trace resolution (clamp >= 2, bounded by analyzer output)
///   - `xyScopeLineHalfThickness` segment half-width in NDC (clamp >= 0)
///   - `xyScopeRotationDegrees` trace rotation (45 = goniometer, 0 = Lissajous)
///   - `xyScopeColorFloor` min palette-sample position (clamp 0...1)
///   - `xyScopeBeatBoost` beat pulse: deflection × (1 + boost×intensity) (clamp >= 0)
///   - `xyScopeBeatHalfLife` beat pulse decay half-life in seconds (clamp > 0)
///   - `xyScopeAlpha` trace opacity (clamp 0...1)
/// Phosphor persistence comes from the per-style `trailPersistence`.
public final class XYScopeVisualizer: Visualizer {
    // Beat pulse decays with wall-clock frame timestamps (realDt), so it is
    // independent of `particleSpeed` per the beat-consumer convention.
    private var beatBoost: Float = 0
    private var lastTimestamp: CFTimeInterval = -1
    private let deltaTimeCap: Float = 0.25

    public init() {}

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings,
                             palette: ColorPalette, aspect: Float) -> [BarVertex] {
        let wl = frame.waveformLeft
        let wr = frame.waveformRight
        let available = min(wl.count, wr.count)
        guard available >= 2 else { return [] }

        // Knobs, clamped at the read site so persisted/hand-edited values
        // can't break geometry.
        let gain = max(0, Float(settings.xyScopeGain))
        let sampleCount = min(available, max(2, settings.xyScopeSampleCount))
        let halfThickness = max(0, Float(settings.xyScopeLineHalfThickness))
        let theta = Float(settings.xyScopeRotationDegrees) * .pi / 180
        let colorFloor = min(1, max(0, Float(settings.xyScopeColorFloor)))
        let boostCoeff = max(0, Float(settings.xyScopeBeatBoost))
        let halfLife = max(1e-4, Float(settings.xyScopeBeatHalfLife))
        let alpha = min(1, max(0, Float(settings.xyScopeAlpha)))
        let safeAspect = max(aspect, 1e-3)

        // Beat pulse: decay by wall-clock dt, then latch a new beat.
        var realDt: Float = 0
        if lastTimestamp >= 0 {
            realDt = Float(min(max(frame.timestamp - lastTimestamp, 0), Double(deltaTimeCap)))
        }
        lastTimestamp = frame.timestamp
        beatBoost *= powf(0.5, realDt / halfLife)
        if frame.beat {
            beatBoost = max(beatBoost, boostCoeff * max(0, min(1, frame.beatIntensity)))
        }
        let deflection = gain * (1 + beatBoost)

        let cosT = cosf(theta), sinT = sinf(theta)

        // Resample both channels at the same stride so pairs stay time-aligned.
        func point(_ i: Int) -> SIMD2<Float> {
            let src = sampleCount == available ? i : (i * (available - 1)) / (sampleCount - 1)
            let px = wl[src] * deflection
            let py = wr[src] * deflection
            // Rotate, aspect-correct x so the scope stays square, clamp to NDC.
            let rx = (px * cosT - py * sinT) / safeAspect
            let ry = px * sinT + py * cosT
            return SIMD2<Float>(min(max(rx, -1), 1), min(max(ry, -1), 1))
        }

        func color(_ p: SIMD2<Float>) -> SIMD4<Float> {
            // Color by radial amplitude (aspect-neutral): louder excursions
            // sample higher palette positions; the floor keeps quiet passages
            // visible.
            let radius = min(1, simd_length(SIMD2<Float>(p.x * safeAspect, p.y)))
            let c = palette.sample(at: max(colorFloor, radius))
            return SIMD4<Float>(c.r, c.g, c.b, alpha)
        }

        var verts: [BarVertex] = []
        verts.reserveCapacity((sampleCount - 1) * 6)
        var p0 = point(0)
        var c0 = color(p0)
        for i in 1..<sampleCount {
            let p1 = point(i)
            let c1 = color(p1)
            defer { p0 = p1; c0 = c1 }

            // Perpendicular offset for arbitrary segment direction; degenerate
            // (zero-length) segments still emit a quad using a vertical offset
            // so a DC-hold trace stays a visible dot/line.
            let d = p1 - p0
            let len = simd_length(d)
            let perp = len > 1e-6
                ? SIMD2<Float>(-d.y / len, d.x / len) * halfThickness
                : SIMD2<Float>(0, halfThickness)

            let bl = BarVertex(position: SIMD4<Float>(p0.x - perp.x, p0.y - perp.y, 0, 1), color: c0)
            let tl = BarVertex(position: SIMD4<Float>(p0.x + perp.x, p0.y + perp.y, 0, 1), color: c0)
            let br = BarVertex(position: SIMD4<Float>(p1.x - perp.x, p1.y - perp.y, 0, 1), color: c1)
            let tr = BarVertex(position: SIMD4<Float>(p1.x + perp.x, p1.y + perp.y, 0, 1), color: c1)
            verts.append(contentsOf: [bl, br, tl, br, tr, tl])
        }
        return verts
    }
}
