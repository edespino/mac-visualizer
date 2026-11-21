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
/// the wave geometry. Falling back to the field's default keeps the read-site clamps total.
private func finiteOr(_ v: Double, _ fallback: Double) -> Double { v.isFinite ? v : fallback }

/// 8th visualizer style: centered overlapping smooth waves (ribbon-wave style).
/// Each wave is bound to an equal-band group of the spectrum; its
/// amplitude tracks that group's energy (smoothed via EMA), its phase wanders
/// via a small inline 1-D value-noise function so motion feels organic.
/// Stateful — the renderer caches one instance across frames.
public final class RibbonWaveVisualizer: Visualizer {
    private struct Wave {
        var amplitude: Float        // smoothed band-group mean
        let baseFreq1: Float        // sine 1 base frequency in radians per NDC unit
        let baseFreq2: Float        // sine 2 base frequency
        let noiseSeed1: UInt64
        let noiseSeed2: UInt64
    }

    private var waves: [Wave] = []
    private var lastWaveCount: Int = 0
    // Frequency basis the persistent `waves` were built with. When the user moves
    // the base-frequency / spread sliders these change, so the waves are rebuilt
    // (mirroring a wave-count change) — the frequencies live in `Wave`, not in a
    // per-frame read. Sentinel NaN forces the first frame to build.
    private var lastBaseFreq: Float = .nan
    private var lastBaseFreqSpread: Float = .nan
    private var lastTimestamp: CFTimeInterval = -1
    private var phaseTime: Double = 0
    private var rng: SeededRNG

    // Internal robustness, not a visual control: cap the per-frame dt so a long
    // pause (window occluded, app backgrounded) can't apply one giant phase step.
    // Left hardcoded, consistent with the other styles.
    private let deltaTimeCap: CFTimeInterval = 0.1

    public init(seed: UInt64 = 0xC0DE5) {
        self.rng = SeededRNG(seed: seed)
    }

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings,
                             palette: ColorPalette, aspect: Float) -> [BarVertex] {
        // Read user-tunable fields with finiteOr + read-site clamps so persisted/
        // edited JSON can't break the geometry. finiteOr drops a non-finite value
        // back to the field default BEFORE clamping (Swift min/max propagate NaN).
        // The dt cap (deltaTimeCap), stereo epsilon (1e-6), 0.5 centering, 6-vert
        // topology, and the wave-construction slopes stay hardcoded — structure,
        // not controls. Defaults reproduce today's look bit-exact (seeded golden).
        let d = VisualizerSettings.defaults
        let n = max(1, min(6, settings.ribbonWaveCount))
        let sampleCount = max(2, settings.ribbonSampleCount)              // divide guard: i/(count-1)
        let smoothing = Float(min(max(finiteOr(settings.ribbonSmoothing, d.ribbonSmoothing), 0), 1))
        let gainMul = Float(max(0, finiteOr(settings.ribbonGain, d.ribbonGain)))
        let heightCap = Float(max(0, finiteOr(settings.ribbonHeightScale, d.ribbonHeightScale)))
        let motionSpeed = max(0, finiteOr(settings.ribbonMotionSpeed, d.ribbonMotionSpeed))   // Double
        let baseFreqMin = Float(max(finiteOr(settings.ribbonBaseFrequency, d.ribbonBaseFrequency), 1e-6))  // > 0
        let baseFreqSpread = Float(max(0, finiteOr(settings.ribbonFrequencySpread, d.ribbonFrequencySpread)))
        let panScale = Float(min(max(finiteOr(settings.ribbonStereoPanScale, d.ribbonStereoPanScale), 0), 1))
        let phaseSwing = Float(max(0, finiteOr(settings.ribbonPhaseSwing, d.ribbonPhaseSwing)))
        let maxAmplitude = Float(max(finiteOr(settings.ribbonMaxAmplitude, d.ribbonMaxAmplitude), 1e-6))    // > 0
        let alpha = Float(min(max(finiteOr(settings.ribbonAlpha, d.ribbonAlpha), 0), 1))

        // Rebuild the persistent waves when the count OR the frequency basis
        // changes (frequencies are baked into each `Wave`). Default values redraw
        // the exact same RNG sequence, so the build is unchanged at defaults.
        if n != lastWaveCount || baseFreqMin != lastBaseFreq || baseFreqSpread != lastBaseFreqSpread {
            rebuild(n: n, baseFreqMin: baseFreqMin, baseFreqSpread: baseFreqSpread)
        }

        // dt advance for phase noise.
        let dt: CFTimeInterval
        if lastTimestamp < 0 {
            dt = 0
        } else {
            dt = max(0, frame.timestamp - lastTimestamp)
        }
        lastTimestamp = frame.timestamp

        var panOffsetX: Float = 0
        if settings.useStereoImage {
            let lSum = frame.bandsLeft.reduce(0, +)
            let rSum = frame.bandsRight.reduce(0, +)
            let total = max(lSum + rSum, 1e-6)
            // ±15° of tilt translates into ~tan(15°) ≈ 0.27 NDC at the screen edge.
            // We shift the whole wave's horizontal centerline by this amount.
            panOffsetX = panScale * (rSum - lSum) / total   // (rSum - lSum)/total ∈ [-1, 1] ⇒ result ∈ [-panScale, +panScale]
        }

        // Per-wave amplitude EMA from equal-band-group means. Cap target at
        // `maxAmplitude` (default 1.0) so worst-case |y| = maxAmplitude * heightCap
        // (default 0.40) stays inside the clip box at the default settings.
        let bands = frame.bands
        for i in 0..<n {
            let target = min(maxAmplitude, groupMean(bands: bands, group: i, total: n) * gainMul)
            waves[i].amplitude += smoothing * (target - waves[i].amplitude)
        }

        // Advance the phase clock only proportionally to current audio energy:
        // silent music → no phase movement → static waves; loud music → full
        // noise-driven wobble. Prevents the wave from drifting when there's
        // nothing to react to.
        var meanAmp: Float = 0
        for i in 0..<n { meanAmp += waves[i].amplitude }
        meanAmp /= Float(n)
        phaseTime += min(dt, deltaTimeCap) * motionSpeed * Double(meanAmp)

        // Pre-sample y-values per wave for all x-positions. Phase swing is held
        // to ±phaseSwing/2 (default ±π/4, 90° total) so the wave wobbles in place
        // instead of drifting.
        // Each wave gets a vertical baseline offset (`yBase`) and a small
        // amplitude scale-down (`depthScale`) so the stack reads as a slight
        // perspective tilt: lower-index waves sit toward the foreground (lower
        // on screen) and higher-index waves recede upward and shrink slightly.
        let depthFalloff: Float = settings.ribbonDepthFalloff
        let tiltSpacing: Float = settings.ribbonTiltSpacing
        var ysPerWave = [[Float]](repeating: [], count: n)
        var yBasesPerWave = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let depthPos: Float = n == 1 ? 0 : Float(i) / Float(n - 1)
            let depthScale: Float = 1 - depthFalloff * depthPos
            let yBase: Float = n == 1 ? 0 : (Float(i) - Float(n - 1) * 0.5) * tiltSpacing
            yBasesPerWave[i] = yBase
            let phi1 = (Float(value1D(phaseTime, seed: waves[i].noiseSeed1)) - 0.5) * phaseSwing
            let phi2 = (Float(value1D(phaseTime, seed: waves[i].noiseSeed2)) - 0.5) * phaseSwing
            var ys = [Float](repeating: 0, count: sampleCount)
            for j in 0..<sampleCount {
                let x = Float(j) / Float(sampleCount - 1) * 2 - 1
                let s1 = sinf(x * waves[i].baseFreq1 + phi1)
                let s2 = sinf(x * waves[i].baseFreq2 + phi2)
                ys[j] = (s1 + s2) * 0.5 * waves[i].amplitude * heightCap * depthScale
            }
            ysPerWave[i] = ys
        }

        // Emit filled ribbons (two triangles per x-segment between the curve
        // and the wave's `yBase` line).
        var verts: [BarVertex] = []
        verts.reserveCapacity(n * (sampleCount - 1) * 6)
        for i in 0..<n {
            let colorPos: Float = n == 1 ? 0.5 : Float(i) / Float(n - 1)
            let c = palette.sample(at: colorPos)
            let color = SIMD4<Float>(c.r, c.g, c.b, alpha)
            let ys = ysPerWave[i]
            let yBase = yBasesPerWave[i]
            for j in 0..<(sampleCount - 1) {
                let x0 = Float(j) / Float(sampleCount - 1) * 2 - 1
                let x1 = Float(j + 1) / Float(sampleCount - 1) * 2 - 1
                let y0 = ys[j]
                let y1 = ys[j + 1]
                let p00 = SIMD4<Float>(x0 + panOffsetX, yBase, 0, 1)
                let p10 = SIMD4<Float>(x1 + panOffsetX, yBase, 0, 1)
                let p0y = SIMD4<Float>(x0 + panOffsetX, yBase + y0, 0, 1)
                let p1y = SIMD4<Float>(x1 + panOffsetX, yBase + y1, 0, 1)
                verts.append(BarVertex(position: p00, color: color))
                verts.append(BarVertex(position: p10, color: color))
                verts.append(BarVertex(position: p0y, color: color))
                verts.append(BarVertex(position: p10, color: color))
                verts.append(BarVertex(position: p1y, color: color))
                verts.append(BarVertex(position: p0y, color: color))
            }
        }
        return verts
    }

    private func rebuild(n: Int, baseFreqMin: Float, baseFreqSpread: Float) {
        lastWaveCount = n
        lastBaseFreq = baseFreqMin
        lastBaseFreqSpread = baseFreqSpread
        waves = (0..<n).map { i in
            let f1 = baseFreqMin + Float(i) * 1.3 + Float(rng.nextUnit()) * baseFreqSpread * 0.25
            let f2 = baseFreqMin + Float(i) * 1.6 + Float(rng.nextUnit()) * baseFreqSpread * 0.25 + 1.7
            let s1 = rng.nextU64()
            let s2 = rng.nextU64()
            return Wave(amplitude: 0, baseFreq1: f1, baseFreq2: f2,
                        noiseSeed1: s1, noiseSeed2: s2)
        }
    }

    private func groupMean(bands: [Float], group: Int, total: Int) -> Float {
        if bands.isEmpty { return 0 }
        let n = bands.count
        let lo = (group * n) / total
        let hi = ((group + 1) * n) / total
        if hi <= lo { return bands[min(lo, n - 1)] }
        var sum: Float = 0
        for k in lo..<hi { sum += bands[k] }
        return sum / Float(hi - lo)
    }
}

// MARK: - 1-D value noise

/// Smooth deterministic 1-D value noise. Hash integer steps + smoothstep
/// interpolate. Output in [0, 1].
private func value1D(_ x: Double, seed: UInt64) -> Float {
    let xi = floor(x)
    let xf = Float(x - xi)
    let i = UInt64(bitPattern: Int64(xi))
    let a = hashToUnit(i, seed: seed)
    let b = hashToUnit(i &+ 1, seed: seed)
    let u = xf * xf * (3 - 2 * xf)
    return a * (1 - u) + b * u
}

private func hashToUnit(_ x: UInt64, seed: UInt64) -> Float {
    var h = x &+ (seed &* 0x9E3779B97F4A7C15)
    h ^= h >> 33
    h = h &* 0xff51afd7ed558ccd
    h ^= h >> 33
    h = h &* 0xc4ceb9fe1a85ec53
    h ^= h >> 33
    return Float(h >> 40) / Float(1 << 24)
}

// `SeededRNG` lives in Sources/Core/SeededRNG.swift (single module-internal copy
// shared across visualizers + DemoAudioSource).