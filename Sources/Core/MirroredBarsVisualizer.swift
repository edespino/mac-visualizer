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

/// Spectrum bars mirrored about the center line: each band grows up and down
/// symmetrically, colored from center (palette 0) to the tips (palette level).
public struct MirroredBarsVisualizer: Visualizer {
    public init() {}

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings,
                             palette: ColorPalette, aspect: Float) -> [BarVertex] {
        let n = frame.bands.count
        guard n > 0 else { return [] }
        let layout = BarLayout(barCount: n, gapFraction: settings.barGap)

        var verts: [BarVertex] = []
        verts.reserveCapacity(n * 12)

        for i in 0..<n {
            let level = min(max(frame.bands[i], 0), 1)
            let (xs, xe) = layout.barXRange(i)
            let x0 = xs * 2 - 1
            let x1 = xe * 2 - 1
            let cCenter = rgba(palette.sample(at: 0))
            let cEdge = rgba(palette.sample(at: level))
            appendQuad(&verts, x0: x0, x1: x1, yLow: 0, yHigh: level, colorLow: cCenter, colorHigh: cEdge)
            appendQuad(&verts, x0: x0, x1: x1, yLow: 0, yHigh: -level, colorLow: cCenter, colorHigh: cEdge)
        }
        return verts
    }

    private func rgba(_ c: RGBAColor) -> SIMD4<Float> { SIMD4<Float>(c.r, c.g, c.b, c.a) }

    private func appendQuad(_ verts: inout [BarVertex], x0: Float, x1: Float,
                            yLow: Float, yHigh: Float, colorLow: SIMD4<Float>, colorHigh: SIMD4<Float>) {
        let bl = BarVertex(position: SIMD4<Float>(x0, yLow, 0, 1), color: colorLow)
        let br = BarVertex(position: SIMD4<Float>(x1, yLow, 0, 1), color: colorLow)
        let tl = BarVertex(position: SIMD4<Float>(x0, yHigh, 0, 1), color: colorHigh)
        let tr = BarVertex(position: SIMD4<Float>(x1, yHigh, 0, 1), color: colorHigh)
        verts.append(contentsOf: [bl, br, tl, br, tr, tl])
    }
}