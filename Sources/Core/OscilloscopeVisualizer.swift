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

/// Draws the raw waveform as a connected line (one thin quad per segment),
/// colored by amplitude.
public struct OscilloscopeVisualizer: Visualizer {
    public init() {}

    private let yScale: Float = 0.9
    private let halfThickness: Float = 0.008

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings,
                             palette: ColorPalette, aspect: Float) -> [BarVertex] {
        let w = frame.waveform
        guard w.count >= 2 else { return [] }
        let m = w.count
        let halfThickness = self.halfThickness * settings.oscilloscopeThickness

        func y(_ s: Float) -> Float { min(max(s * yScale, -1), 1) }
        func color(_ yv: Float) -> SIMD4<Float> { rgba(palette.sample(at: min(abs(yv), 1))) }

        var verts: [BarVertex] = []
        verts.reserveCapacity((m - 1) * 6)
        for j in 0..<(m - 1) {
            let x0 = -1 + 2 * Float(j) / Float(m - 1)
            let x1 = -1 + 2 * Float(j + 1) / Float(m - 1)
            let y0 = y(w[j]); let y1 = y(w[j + 1])
            let c0 = color(y0); let c1 = color(y1)
            let bl = BarVertex(position: SIMD4<Float>(x0, y0 - halfThickness, 0, 1), color: c0)
            let tl = BarVertex(position: SIMD4<Float>(x0, y0 + halfThickness, 0, 1), color: c0)
            let br = BarVertex(position: SIMD4<Float>(x1, y1 - halfThickness, 0, 1), color: c1)
            let tr = BarVertex(position: SIMD4<Float>(x1, y1 + halfThickness, 0, 1), color: c1)
            verts.append(contentsOf: [bl, br, tl, br, tr, tl])
        }
        return verts
    }

    private func rgba(_ c: RGBAColor) -> SIMD4<Float> { SIMD4<Float>(c.r, c.g, c.b, c.a) }
}