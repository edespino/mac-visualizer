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

/// Tricentric: a receding tunnel of concentric triangle outlines, each ring
/// scaled by its frequency band × overall loudness (with a floor so silence
/// stays visible), the whole tunnel rotating at a loudness-driven rate. An
/// independent Swift reimplementation inspired by the "Tricentric" preset
/// from Vissonance by Tariq Soliman
/// (https://github.com/tariqksoliman/Vissonance, MIT License) — see NOTICE.
/// The reimplementation collapses the original's perspective z-stack into a per-ring
/// radius falloff and maps its band-driven HSL color onto the active palette;
/// the loudness-driven camera roll becomes an accumulated rotation advanced by
/// wall-clock frame time (realDt, independent of `particleSpeed`).
///
/// Knobs (top-level settings; clamps live at the read sites):
///   - `tricentricRingCount` rings in the tunnel (32 default, clamp 4...64)
///   - `tricentricBaseRadius` outermost ring radius in NDC (1.1 default, clamp > 0)
///   - `tricentricRadiusFalloff` per-ring shrink factor (0.97 default, clamp 0.5...0.99)
///   - `tricentricScaleFloor` minimum ring scale at silence (0.25 default, clamp 0...1)
///   - `tricentricRotationSpeed` loudness-rotation multiplier, rad/s at full
///     loudness (1.0 default, clamp -6...6; 0 freezes)
///   - `tricentricLineThickness` outline half-width in NDC (0.008 default, clamp >= 0)
///   - `tricentricAlpha` opacity multiplier on the loudness-driven base alpha
///     (1.0 default, clamp 0...1)
public final class TricentricVisualizer: Visualizer {
    private var rotation: Float = 0
    private var lastTimestamp: CFTimeInterval = -1
    private let deltaTimeCap: Float = 0.25

    public init() {}

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings,
                             palette: ColorPalette, aspect: Float) -> [BarVertex] {
        let bands = frame.bands
        guard !bands.isEmpty else { return [] }

        let ringCount = max(4, min(64, settings.tricentricRingCount))
        let baseRadius = max(1e-3, Float(settings.tricentricBaseRadius))
        let falloff = min(0.99, max(0.5, Float(settings.tricentricRadiusFalloff)))
        let scaleFloor = min(1, max(0, Float(settings.tricentricScaleFloor)))
        let rotSpeed = min(6, max(-6, Float(settings.tricentricRotationSpeed)))
        let halfWidth = max(0, Float(settings.tricentricLineThickness))
        let alphaKnob = min(1, max(0, Float(settings.tricentricAlpha)))
        let safeAspect = max(aspect, 1e-3)

        var loudness: Float = 0
        for b in bands { loudness += b }
        loudness = min(1, max(0, loudness / Float(bands.count)))

        // Loudness-driven roll, advanced by wall-clock dt so the speed knob is
        // rad/s at full loudness regardless of frame rate.
        var realDt: Float = 0
        if lastTimestamp >= 0 {
            realDt = Float(min(max(frame.timestamp - lastTimestamp, 0), Double(deltaTimeCap)))
        }
        lastTimestamp = frame.timestamp
        rotation += rotSpeed * loudness * realDt

        // Base alpha follows the original's loudness-driven saturation term
        // (0.6 at silence rising to 1.0), scaled by the knob.
        let baseAlpha = (0.6 + 0.4 * loudness) * alphaKnob

        var verts: [BarVertex] = []
        verts.reserveCapacity(ringCount * 3 * 6)

        var radius = baseRadius
        for ring in 0..<ringCount {
            defer { radius *= falloff }
            let j = min(bands.count - 1, ring * bands.count / ringCount)
            let lv = min(1, max(0, bands[j]))
            // Original per-ring scale: (level × loudness) + floor.
            let r = radius * (lv * loudness + scaleFloor)
            let c = palette.sample(at: lv)
            let color = SIMD4<Float>(c.r, c.g, c.b, baseAlpha)

            // Triangle outline: 3 corners, one thin quad per edge.
            var corners: [SIMD2<Float>] = []
            for k in 0..<3 {
                let a = rotation + Float.pi / 2 + Float(k) * (2 * Float.pi / 3)
                corners.append(SIMD2<Float>(cosf(a) * r, sinf(a) * r))
            }
            for k in 0..<3 {
                let p0 = corners[k]
                let p1 = corners[(k + 1) % 3]
                let d = p1 - p0
                let len = simd_length(d)
                let perp = len > 1e-6
                    ? SIMD2<Float>(-d.y / len, d.x / len) * halfWidth
                    : SIMD2<Float>(0, halfWidth)

                func vertex(_ p: SIMD2<Float>) -> BarVertex {
                    BarVertex(position: SIMD4<Float>(
                        min(max(p.x / safeAspect, -1), 1),
                        min(max(p.y, -1), 1), 0, 1), color: color)
                }
                let bl = vertex(p0 - perp)
                let tl = vertex(p0 + perp)
                let br = vertex(p1 - perp)
                let tr = vertex(p1 + perp)
                verts.append(contentsOf: [bl, br, tl, br, tr, tl])
            }
        }
        return verts
    }
}
