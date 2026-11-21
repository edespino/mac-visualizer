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
import QuartzCore

/// Returns `v` if it is finite, otherwise `fallback`. Applied to every user-tunable
/// float BEFORE clamping: Swift's `min`/`max` propagate NaN (`max(.nan, lo) == .nan`),
/// so a persisted/edited non-finite value would otherwise survive the clamp and poison
/// the geometry. Falling back to the field's default keeps the read-site clamps total.
private func finiteOr(_ v: Double, _ fallback: Double) -> Double { v.isFinite ? v : fallback }

/// Joy Division "Unknown Pleasures" style: 4 horizontal smoothed area paths
/// stacked vertically. Each path is sampled at `sampleCount` evenly-spaced
/// x-positions; the y at each sample is a 3-point moving average of band
/// magnitudes mapped to that path.
///
/// When `useStereoImage == false`: rows 0-2 split the spectrum (low/mid/high),
/// row 3 shows the overall mix. When `useStereoImage == true`: row 0 = bandsLeft,
/// rows 1-2 split the mono mix (low half, high half), row 3 = bandsRight.
///
/// On `frame.beat`: line/area thickness multiplier `1 + 0.5 * beatIntensity`,
/// 150ms half-life decay. Stateful — keep one instance alive across frames.
public final class JoyPlotVisualizer: Visualizer {

    // rowCount stays FIXED at 4: the four rows have bespoke per-row audio sources
    // (mono: low/mid/high thirds + full-mix; stereo: bandsLeft / low / high /
    // bandsRight). A variable count would require redesigning that row→source
    // mapping and could not stay byte-identical at the default, so it is left
    // hardcoded. Everything else is user-tunable.
    private let rowCount: Int = 4
    private var beatBoost: Float = 0            // decays to 0; pulsed by frame.beat
    private var lastTimestamp: CFTimeInterval = -1

    // Internal robustness, not a control: cap the per-frame dt so a long pause
    // (window occluded, app backgrounded) can't apply one giant decay step.
    private let deltaTimeCap: CFTimeInterval = 0.1

    public init() {}

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings,
                             palette: ColorPalette, aspect: Float) -> [BarVertex] {
        guard !frame.bands.isEmpty else { return [] }

        // Read user-tunable fields with finiteOr + read-site clamps so persisted/
        // edited JSON can't break the geometry. finiteOr drops a non-finite value
        // back to the field default BEFORE clamping (Swift min/max propagate NaN).
        // The dt cap (deltaTimeCap), 3-point smoothing /3, level 0...1 clamp,
        // beatIntensity clamp, slice-index logic, and 6-vertex topology stay
        // hardcoded — structure, not controls. Defaults reproduce today's look
        // bit-exact (seeded golden: mono + stereo + beat).
        let d = VisualizerSettings.defaults
        let sampleCount = max(2, settings.joyPlotSampleCount)                                       // divide guard: i/(count-1)
        let rowSpacing = Float(max(0, finiteOr(settings.joyPlotRowSpacing, d.joyPlotRowSpacing)))
        let rowHeight = Float(max(0, finiteOr(settings.joyPlotRowHeight, d.joyPlotRowHeight)))
        let baselineShift = Float(finiteOr(settings.joyPlotBaselineOffset, d.joyPlotBaselineOffset))
        let xExtent = Float(max(finiteOr(settings.joyPlotXExtent, d.joyPlotXExtent), 1e-6))         // > 0
        let beatHalfLife = Float(max(finiteOr(settings.joyPlotBeatHalfLife, d.joyPlotBeatHalfLife), 1e-6))  // > 0
        let beatBoostCoeff = Float(max(0, finiteOr(settings.joyPlotBeatBoost, d.joyPlotBeatBoost)))
        let bottomDim = Float(min(max(finiteOr(settings.joyPlotBottomDim, d.joyPlotBottomDim), 0), 1))
        let alpha = Float(min(max(finiteOr(settings.joyPlotAlpha, d.joyPlotAlpha), 0), 1))

        // Decay + pulse beatBoost using wall-clock dt (independent of any speed multiplier).
        var realDt: Float = 0
        if lastTimestamp >= 0 {
            realDt = Float(min(max(frame.timestamp - lastTimestamp, 0), deltaTimeCap))
        }
        lastTimestamp = frame.timestamp
        beatBoost *= powf(0.5, realDt / beatHalfLife)
        if frame.beat {
            beatBoost = max(beatBoost, beatBoostCoeff * max(0, min(1, frame.beatIntensity)))
        }
        let amplitudeScale: Float = 1 + beatBoost

        // Choose band slices per row.
        let rowSlices: [[Float]]
        if settings.useStereoImage {
            let mono = frame.bands
            let mid = mono.count / 2
            rowSlices = [
                frame.bandsLeft,
                Array(mono[0..<mid]),
                Array(mono[mid..<mono.count]),
                frame.bandsRight
            ]
        } else {
            let n = frame.bands.count
            let third = max(1, n / 3)
            rowSlices = [
                Array(frame.bands[0..<third]),
                Array(frame.bands[third..<min(2 * third, n)]),
                Array(frame.bands[min(2 * third, n)..<n]),
                frame.bands
            ]
        }

        // Per-row baseline y positions. Centered around y=0, spaced by rowSpacing,
        // plus the user baseline shift (default 0 → unchanged centering).
        let centeringOffset = (Float(rowCount - 1) * rowSpacing) / 2
        var verts: [BarVertex] = []
        verts.reserveCapacity(rowCount * (sampleCount - 1) * 6)

        // Half-width of the x mapping. Default xExtent 1.0 → xSpan 2.0, which
        // reproduces the prior `frac * 2 - 1` mapping byte-for-byte.
        let xSpan = 2 * xExtent

        for r in 0..<rowCount {
            let baseY = Float(r) * rowSpacing - centeringOffset + baselineShift
            let slice = rowSlices[r]
            guard !slice.isEmpty else { continue }
            // Sample the slice at sampleCount evenly-spaced positions, 3-point smoothing.
            var ys: [Float] = []
            ys.reserveCapacity(sampleCount)
            for i in 0..<sampleCount {
                let frac = Float(i) / Float(sampleCount - 1)
                let idx = Int(frac * Float(slice.count - 1))
                let prev = max(0, idx - 1), next = min(slice.count - 1, idx + 1)
                let smoothed = (slice[prev] + slice[idx] + slice[next]) / 3
                let level = min(max(smoothed, 0), 1)
                ys.append(level * rowHeight * amplitudeScale)
            }
            // Emit triangle quads between (x_i, baseY) and (x_{i+1}, baseY + y_i).
            let colorPos = Float(r) / Float(max(rowCount - 1, 1))
            let c = palette.sample(at: colorPos)
            let topColor = SIMD4<Float>(c.r, c.g, c.b, alpha)
            let bottomColor = SIMD4<Float>(c.r * bottomDim, c.g * bottomDim, c.b * bottomDim, alpha)
            for i in 0..<(sampleCount - 1) {
                let x0 = Float(i) / Float(sampleCount - 1) * xSpan - xExtent
                let x1 = Float(i + 1) / Float(sampleCount - 1) * xSpan - xExtent
                let y0 = ys[i], y1 = ys[i + 1]
                let p00 = SIMD4<Float>(x0, baseY, 0, 1)
                let p10 = SIMD4<Float>(x1, baseY, 0, 1)
                let p0y = SIMD4<Float>(x0, baseY + y0, 0, 1)
                let p1y = SIMD4<Float>(x1, baseY + y1, 0, 1)
                verts.append(contentsOf: [
                    BarVertex(position: p00, color: bottomColor),
                    BarVertex(position: p10, color: bottomColor),
                    BarVertex(position: p0y, color: topColor),
                    BarVertex(position: p10, color: bottomColor),
                    BarVertex(position: p1y, color: topColor),
                    BarVertex(position: p0y, color: topColor)
                ])
            }
        }
        return verts
    }
}