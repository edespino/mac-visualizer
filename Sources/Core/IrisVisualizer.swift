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

/// Iris: a ring of thin radial petals whose tips extend with their frequency
/// band, mirrored left/right so the figure stays symmetric, with a whole-frame
/// color driven by loudness and a brightness gradient from dim base to bright
/// tip. An independent Swift reimplementation inspired by the "Iris" preset
/// from Vissonance by Tariq Soliman
/// (https://github.com/tariqksoliman/Vissonance, MIT License) — see NOTICE.
/// The reimplementation maps the original's loudness-swept HSL hue onto the active palette
/// and its depth-fade fragment shader onto the per-vertex base→tip gradient.
///
/// Knobs (top-level settings; clamps live at the read sites):
///   - `irisPetalCount` petals in the ring (128 default, clamp 8...256, forced even)
///   - `irisInnerRadius` ring hole radius in NDC (0.22 default, clamp 0...1)
///   - `irisBaseLength` resting petal length (0.18 default, clamp >= 0)
///   - `irisLengthScale` band level → extra length (0.55 default, clamp >= 0)
///   - `irisPetalWidth` petal half-width in NDC (0.012 default, clamp >= 0)
///   - `irisLoudnessSwell` loudness → whole-ring swell (0.25 default, clamp >= 0)
///   - `irisInnerDim` base brightness fraction of the tip (0.35 default, clamp 0...1)
///   - `irisAlpha` petal opacity (1.0 default, clamp 0...1)
/// Stereo: with `useStereoImage`, x<0 petals read bandsLeft, x>=0 bandsRight.
public struct IrisVisualizer: Visualizer {
    public init() {}

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings,
                             palette: ColorPalette, aspect: Float) -> [BarVertex] {
        let bands = frame.bands
        guard !bands.isEmpty else { return [] }

        let petalCount = max(8, min(256, settings.irisPetalCount)) & ~1  // even
        let innerRadius = min(1, max(0, Float(settings.irisInnerRadius)))
        let baseLength = max(0, Float(settings.irisBaseLength))
        let lengthScale = max(0, Float(settings.irisLengthScale))
        let halfWidth = max(0, Float(settings.irisPetalWidth))
        let swell = max(0, Float(settings.irisLoudnessSwell))
        let innerDim = min(1, max(0, Float(settings.irisInnerDim)))
        let alpha = min(1, max(0, Float(settings.irisAlpha)))
        let safeAspect = max(aspect, 1e-3)

        // Whole-frame loudness: drives the shared petal color (the original
        // sweeps an HSL hue; the port sweeps the active palette) and the ring
        // swell.
        var loudness: Float = 0
        for b in bands { loudness += b }
        loudness = min(1, max(0, loudness / Float(bands.count)))
        let base = palette.sample(at: loudness)
        let tipColor = SIMD4<Float>(base.r, base.g, base.b, alpha)
        let dimColor = SIMD4<Float>(base.r * innerDim, base.g * innerDim, base.b * innerDim, alpha)

        func level(forPair i: Int, leftHalf: Bool) -> Float {
            let source: [Float]
            if settings.useStereoImage {
                source = leftHalf ? frame.bandsLeft : frame.bandsRight
            } else {
                source = bands
            }
            guard !source.isEmpty else { return 0 }
            let j = min(source.count - 1, i * source.count / max(1, petalCount / 2))
            return min(1, max(0, source[j]))
        }

        let angleStep = 2 * Float.pi / Float(petalCount)
        var verts: [BarVertex] = []
        verts.reserveCapacity(petalCount * 6)

        // Petal pairs at ±angle from the +y axis, mirroring the original's
        // paired rotation.z placement so left and right stay symmetric.
        for i in 0..<(petalCount / 2) {
            let a = Float(i) * angleStep + angleStep / 2
            for sign: Float in [1, -1] {
                let leftHalf = sign < 0
                let lv = level(forPair: i, leftHalf: leftHalf)
                let length = baseLength + lv * lengthScale + loudness * swell
                let dir = SIMD2<Float>(sinf(a) * sign, cosf(a))
                // The mirrored twin's perpendicular flips with the petal so
                // vertex k of the -angle petal is the exact x-mirror of vertex
                // k of the +angle petal (pinned by the symmetry test).
                let perp = SIMD2<Float>(-dir.y, dir.x) * halfWidth * sign
                let inner = dir * innerRadius
                let outer = dir * min(innerRadius + length, 1.4)

                func vertex(_ p: SIMD2<Float>, _ c: SIMD4<Float>) -> BarVertex {
                    BarVertex(position: SIMD4<Float>(
                        min(max(p.x / safeAspect, -1), 1),
                        min(max(p.y, -1), 1), 0, 1), color: c)
                }
                let bl = vertex(inner - perp, dimColor)
                let tl = vertex(inner + perp, dimColor)
                let br = vertex(outer - perp, tipColor)
                let tr = vertex(outer + perp, tipColor)
                verts.append(contentsOf: [bl, br, tl, br, tr, tl])
            }
        }
        return verts
    }
}
