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

/// Classic spectrum bars: each band is a bottom-anchored bar with a vertical
/// palette gradient, plus an optional peak-hold cap.
///
/// When `settings.useStereoImage == true`: split the screen in half. The left
/// half displays `bandsLeft` (low-freq toward the edge), the right half
/// displays `bandsRight` (low-freq toward the edge). High frequencies meet at
/// the center.
public struct SpectrumBarsVisualizer: Visualizer {
    public init() {}

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings,
                             palette: ColorPalette, aspect: Float) -> [BarVertex] {
        let count = frame.bands.count
        guard count > 0 else { return [] }

        if settings.useStereoImage {
            return emitStereo(frame: frame, settings: settings, palette: palette)
        }
        return emitMono(frame: frame, settings: settings, palette: palette)
    }

    private func emitMono(frame: AudioFrame, settings: VisualizerSettings, palette: ColorPalette) -> [BarVertex] {
        let count = frame.bands.count
        let layout = BarLayout(barCount: count, gapFraction: settings.barGap)
        var verts: [BarVertex] = []
        verts.reserveCapacity(count * (settings.peakHoldEnabled ? 12 : 6))
        for i in 0..<count {
            let level = min(max(frame.bands[i], 0), 1)
            let (xs, xe) = layout.barXRange(i)
            let x0 = xs * 2 - 1, x1 = xe * 2 - 1
            let yTop = -1 + 2 * level
            let cBottom = rgba(palette.sample(at: 0))
            let cTop = rgba(palette.sample(at: level))
            appendQuad(&verts, x0: x0, x1: x1, yLow: -1, yHigh: yTop, colorLow: cBottom, colorHigh: cTop)
            if settings.peakHoldEnabled {
                let peak = min(max(i < frame.bandPeaks.count ? frame.bandPeaks[i] : 0, 0), 1)
                let capCenter = -1 + 2 * peak
                let capHalf: Float = 0.01
                let capLow = min(max(capCenter - capHalf, -1), 1)
                let capHigh = min(max(capCenter + capHalf, -1), 1)
                let capColor = rgba(palette.sample(at: peak))
                appendQuad(&verts, x0: x0, x1: x1, yLow: capLow, yHigh: capHigh, colorLow: capColor, colorHigh: capColor)
            }
        }
        return verts
    }

    private func emitStereo(frame: AudioFrame, settings: VisualizerSettings, palette: ColorPalette) -> [BarVertex] {
        let count = frame.bands.count
        // Each half hosts `count` bars across half the screen width.
        let layout = BarLayout(barCount: count, gapFraction: settings.barGap)
        var verts: [BarVertex] = []
        verts.reserveCapacity(count * (settings.peakHoldEnabled ? 24 : 12))

        // Left half: bandsLeft[0] (bass) at far-left edge, bandsLeft[count-1] (treble) near center.
        // i=0 → leftmost x-position → leftIdx=0 (bass). i=count-1 → near-center → leftIdx=count-1 (treble).
        for i in 0..<count {
            let leftIdx = i
            let level = min(max(frame.bandsLeft[leftIdx], 0), 1)
            let (xs, xe) = layout.barXRange(i)
            // Compress [0,1] to [-1, 0].
            let x0 = xs - 1
            let x1 = xe - 1
            let yTop = -1 + 2 * level
            let cBottom = rgba(palette.sample(at: 0))
            let cTop = rgba(palette.sample(at: level))
            appendQuad(&verts, x0: x0, x1: x1, yLow: -1, yHigh: yTop, colorLow: cBottom, colorHigh: cTop)
            if settings.peakHoldEnabled {
                let peak = min(max(leftIdx < frame.bandPeaks.count ? frame.bandPeaks[leftIdx] : 0, 0), 1)
                let capCenter = -1 + 2 * peak
                let capHalf: Float = 0.01
                let capLow = min(max(capCenter - capHalf, -1), 1)
                let capHigh = min(max(capCenter + capHalf, -1), 1)
                let capColor = rgba(palette.sample(at: peak))
                appendQuad(&verts, x0: x0, x1: x1, yLow: capLow, yHigh: capHigh, colorLow: capColor, colorHigh: capColor)
            }
        }
        // Right half: bandsRight[count-1] (bass) at far-right edge, bandsRight[0] (treble) near center.
        // i=0 → near-center x-position → rightIdx=count-1 (bass at far right when i=count-1).
        for i in 0..<count {
            let rightIdx = count - 1 - i
            let level = min(max(frame.bandsRight[rightIdx], 0), 1)
            let (xs, xe) = layout.barXRange(i)
            // Compress [0,1] to [0, 1] (NDC right half).
            let x0 = xs
            let x1 = xe
            let yTop = -1 + 2 * level
            let cBottom = rgba(palette.sample(at: 0))
            let cTop = rgba(palette.sample(at: level))
            appendQuad(&verts, x0: x0, x1: x1, yLow: -1, yHigh: yTop, colorLow: cBottom, colorHigh: cTop)
            if settings.peakHoldEnabled {
                let peak = min(max(rightIdx < frame.bandPeaks.count ? frame.bandPeaks[rightIdx] : 0, 0), 1)
                let capCenter = -1 + 2 * peak
                let capHalf: Float = 0.01
                let capLow = min(max(capCenter - capHalf, -1), 1)
                let capHigh = min(max(capCenter + capHalf, -1), 1)
                let capColor = rgba(palette.sample(at: peak))
                appendQuad(&verts, x0: x0, x1: x1, yLow: capLow, yHigh: capHigh, colorLow: capColor, colorHigh: capColor)
            }
        }
        return verts
    }

    private func rgba(_ c: RGBAColor) -> SIMD4<Float> { SIMD4<Float>(c.r, c.g, c.b, c.a) }

    private func appendQuad(_ verts: inout [BarVertex],
                            x0: Float, x1: Float, yLow: Float, yHigh: Float,
                            colorLow: SIMD4<Float>, colorHigh: SIMD4<Float>) {
        let bl = BarVertex(position: SIMD4<Float>(x0, yLow, 0, 1), color: colorLow)
        let br = BarVertex(position: SIMD4<Float>(x1, yLow, 0, 1), color: colorLow)
        let tl = BarVertex(position: SIMD4<Float>(x0, yHigh, 0, 1), color: colorHigh)
        let tr = BarVertex(position: SIMD4<Float>(x1, yHigh, 0, 1), color: colorHigh)
        verts.append(contentsOf: [bl, br, tl, br, tr, tl])
    }
}