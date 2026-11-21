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

/// Spectrum bands arranged radially around a center ring; each band is a bar
/// pointing outward, length = level. Aspect-corrected so the ring stays round.
public struct RadialSpectrumVisualizer: Visualizer {
    public init() {}

    private let innerRadius: Float = 0.25
    private let radialSpan: Float = 0.6

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings,
                             palette: ColorPalette, aspect: Float) -> [BarVertex] {
        let n = frame.bands.count
        guard n > 0 else { return [] }

        // Scale the longer screen axis down so a circle stays round AND inside clip space.
        var sx: Float = 1, sy: Float = 1
        if aspect >= 1 { sx = 1 / aspect } else { sy = aspect }

        var centerOffsetX: Float = 0
        if settings.useStereoImage {
            let lSum = frame.bandsLeft.reduce(0, +)
            let rSum = frame.bandsRight.reduce(0, +)
            let total = max(lSum + rSum, 1e-6)
            centerOffsetX = 0.15 * (rSum - lSum) / total   // (rSum - lSum)/total ∈ [-1, 1] ⇒ result ∈ [-0.15, +0.15]
        }

        let angularHalf = (Float.pi / Float(n)) * 0.8
        var verts: [BarVertex] = []
        verts.reserveCapacity(n * 6)

        func point(_ r: Float, _ a: Float) -> SIMD4<Float> {
            SIMD4<Float>(r * cosf(a) * sx + centerOffsetX, r * sinf(a) * sy, 0, 1)
        }

        for i in 0..<n {
            let level = min(max(frame.bands[i], 0), 1)
            let theta = 2 * Float.pi * Float(i) / Float(n) - Float.pi / 2
            let rOuter = innerRadius + level * radialSpan
            let cInner = rgba(palette.sample(at: 0))
            let cOuter = rgba(palette.sample(at: level))
            let a0 = theta - angularHalf
            let a1 = theta + angularHalf
            let il = point(innerRadius, a0), ir = point(innerRadius, a1)
            let ol = point(rOuter, a0), or_ = point(rOuter, a1)
            verts.append(contentsOf: [
                BarVertex(position: il, color: cInner),
                BarVertex(position: ir, color: cInner),
                BarVertex(position: ol, color: cOuter),
                BarVertex(position: ir, color: cInner),
                BarVertex(position: or_, color: cOuter),
                BarVertex(position: ol, color: cOuter),
            ])
        }
        return verts
    }

    private func rgba(_ c: RGBAColor) -> SIMD4<Float> { SIMD4<Float>(c.r, c.g, c.b, c.a) }
}