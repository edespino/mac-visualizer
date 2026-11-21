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

/// 12 moving metaball point sources. Each frame, advance positions via 2D
/// value noise drift; amplitude driven by an assigned audio band. Two render
/// modes: shader (fragment shader, default), marchingSquares (CPU iso-line).
///
/// On `frame.beat`: density threshold multiplier `1 - 0.2 * beatIntensity`
/// briefly lowers thresholds (contours expand outward). 200ms half-life.
public final class LavaLampVisualizer: Visualizer {

    public struct PointState {
        public var position: SIMD2<Float>
        public var velocity: SIMD2<Float>
        public let bandIdx: Int
    }

    public private(set) var points: [PointState]
    private var beatBoost: Float = 0
    private var lastTimestamp: CFTimeInterval = -1
    private let baseThresholds: [Float] = [0.3, 0.7, 1.2, 2.0]

    /// Default blob count; matches `VisualizerSettings.defaults.lavaLampBlobCount`
    /// so a freshly constructed visualizer needs no rebuild under default settings.
    private static let defaultPointCount: Int = 12

    public init() {
        self.points = LavaLampVisualizer.makePoints(count: LavaLampVisualizer.defaultPointCount)
    }

    /// Deterministically generate `count` metaball points from the fixed seed.
    /// Reproduces the original 12-point sequence exactly for `count == 12`, so
    /// the default look is unchanged; called again to rebuild when the user
    /// changes `lavaLampBlobCount`.
    static func makePoints(count: Int) -> [PointState] {
        var rng = SeededRNG(seed: 0xFA51BABE)
        var p: [PointState] = []
        p.reserveCapacity(count)
        for i in 0..<count {
            let pos = SIMD2<Float>(rng.nextSigned() * 0.5, rng.nextSigned() * 0.5)
            let vel = SIMD2<Float>(rng.nextSigned() * 0.1, rng.nextSigned() * 0.1)
            p.append(PointState(position: pos, velocity: vel, bandIdx: i))
        }
        return p
    }

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings,
                             palette: ColorPalette, aspect: Float) -> [BarVertex] {
        // dt
        var realDt: Float = 0
        if lastTimestamp >= 0 {
            realDt = Float(min(max(frame.timestamp - lastTimestamp, 0), 0.1))
        }
        lastTimestamp = frame.timestamp

        // Rebuild the points array if the user changed blob count (clamped to
        // 1...capacity). Stateful reset-on-change; positions restart from seed.
        let targetCount = max(1, min(kLavaLampPointCapacity, settings.lavaLampBlobCount))
        if points.count != targetCount {
            points = LavaLampVisualizer.makePoints(count: targetCount)
        }

        // Shared motion tunables (drive both render modes via the single points
        // array). `motionSpeed` scales the noise time; `driftStrength` scales the
        // per-frame velocity; `wrapBounds` (floored >0) is the recenter radius.
        let motionSpeed = settings.lavaLampMotionSpeed
        let driftStrength = Float(settings.lavaLampDriftStrength)
        let wrapBounds = Float(max(1e-4, settings.lavaLampWrapBounds))

        // Advance points via value-noise-driven drift.
        for i in 0..<points.count {
            let nx = LavaLampVisualizer.value2D(
                x: Double(points[i].position.x) + frame.timestamp * motionSpeed,
                y: Double(points[i].position.y),
                seed: UInt64(bitPattern: Int64(i) &* Int64(bitPattern: 0x9E3779B97F4A7C15))
            )
            let ny = LavaLampVisualizer.value2D(
                x: Double(points[i].position.x),
                y: Double(points[i].position.y) + frame.timestamp * motionSpeed,
                seed: UInt64(bitPattern: Int64(i) &* Int64(bitPattern: 0xBF58476D1CE4E5B9))
            )
            let drift = SIMD2<Float>((Float(nx) - 0.5) * driftStrength, (Float(ny) - 0.5) * driftStrength)
            points[i].velocity = drift
            points[i].position += points[i].velocity * realDt
            // Wrap when out of bounds.
            if abs(points[i].position.x) > wrapBounds { points[i].position.x = 0 }
            if abs(points[i].position.y) > wrapBounds { points[i].position.y = 0 }
        }

        // Beat boost decay. Half-life floored >0 (CPU divides by it).
        let beatHalfLife = Float(max(1e-4, settings.lavaLampCpuBeatHalfLife))
        beatBoost *= powf(0.5, realDt / beatHalfLife)
        if frame.beat {
            beatBoost = max(beatBoost, Float(settings.lavaLampCpuBeatBoost) * max(0, min(1, frame.beatIntensity)))
        }

        switch settings.current.lavaLampRenderMode {
        case .shader:
            return []   // shader-driven; Renderer dispatches via .lavaLampShader (Task 12)
        case .marchingSquares:
            return emitMarchingSquares(frame: frame, settings: settings, palette: palette, aspect: aspect)
        }
    }

    /// Current threshold values adjusted by beat boost. Used by Task 12 shader
    /// uniforms and Task 13 marching-squares pass.
    public func currentThresholds() -> [Float] {
        let mul: Float = 1 - beatBoost
        return baseThresholds.map { $0 * mul }
    }

    /// Current per-point amplitudes (bandLevel[bandIdx] for each point).
    /// Returns mono levels when `useStereoImage == false`; L or R per-point
    /// based on point.x when true.
    public func currentAmplitudes(frame: AudioFrame, settings: VisualizerSettings) -> [Float] {
        var amps: [Float] = Array(repeating: 0, count: points.count)
        guard !frame.bands.isEmpty else { return amps }
        for i in 0..<points.count {
            let bi = points[i].bandIdx % frame.bands.count
            if settings.useStereoImage {
                let src = points[i].position.x < 0 ? frame.bandsLeft : frame.bandsRight
                amps[i] = src.isEmpty ? 0 : src[bi]
            } else {
                amps[i] = frame.bands[bi]
            }
        }
        return amps
    }

    private func emitMarchingSquares(frame: AudioFrame, settings: VisualizerSettings,
                                     palette: ColorPalette, aspect: Float) -> [BarVertex] {
        _ = aspect   // cells span full NDC; aspect handled by Metal's NDC→screen mapping
        // Clamp grid >=2 (the 2/(gridSize-1) divide and the cell loops require it).
        let gridSize = max(2, settings.lavaLampGridSize)
        let cellSize: Float = 2.0 / Float(gridSize - 1)
        // Shared field/color tunables (identical literals to the shader path).
        let densityFalloff = Float(max(1e-4, settings.lavaLampDensityFalloff))
        let brightnessResponse = Float(settings.lavaLampBrightnessResponse)
        let paletteDensityScale = Float(settings.lavaLampPaletteDensityScale)
        let amps = currentAmplitudes(frame: frame, settings: settings)
        let beatMul = 1 + beatBoost

        // 1. Pre-compute density at every grid POINT.
        var densityGrid = Array(repeating: Array(repeating: Float(0), count: gridSize), count: gridSize)
        for y in 0..<gridSize {
            let fy = -1 + Float(y) * cellSize
            for x in 0..<gridSize {
                let fx = -1 + Float(x) * cellSize
                var d: Float = 0
                for i in 0..<points.count {
                    let dx = fx - points[i].position.x
                    let dy = fy - points[i].position.y
                    let r2 = dx * dx + dy * dy
                    d += amps[i] * expf(-r2 * densityFalloff)
                }
                densityGrid[y][x] = d
            }
        }

        // 2. Per grid POINT, compute a color from density.
        func colorAt(_ density: Float) -> SIMD4<Float> {
            let brightness: Float = 1 - expf(-density * brightnessResponse)
            let level = min(max(density * paletteDensityScale, 0), 1)
            let baseColor = palette.sample(at: level)
            return SIMD4<Float>(
                baseColor.r * brightness * beatMul,
                baseColor.g * brightness * beatMul,
                baseColor.b * brightness * beatMul,
                1
            )
        }
        var colorGrid = Array(repeating: Array(repeating: SIMD4<Float>.zero, count: gridSize), count: gridSize)
        for y in 0..<gridSize {
            for x in 0..<gridSize {
                colorGrid[y][x] = colorAt(densityGrid[y][x])
            }
        }

        // 3. Emit one quad per cell (gridSize-1 × gridSize-1 cells) with 4 distinct
        //    corner colors. Metal interpolates between corners across the quad.
        var verts: [BarVertex] = []
        verts.reserveCapacity((gridSize - 1) * (gridSize - 1) * 6)
        for y in 0..<(gridSize - 1) {
            let y0 = -1 + Float(y) * cellSize
            let y1 = y0 + cellSize
            for x in 0..<(gridSize - 1) {
                let x0 = -1 + Float(x) * cellSize
                let x1 = x0 + cellSize
                let c00 = colorGrid[y][x]
                let c10 = colorGrid[y][x + 1]
                let c01 = colorGrid[y + 1][x]
                let c11 = colorGrid[y + 1][x + 1]
                // Emit every cell so bilinear color interpolation continues smoothly
                // to the boundary. Skipping cells produced a stairstepped outer edge.
                // Cost: constant ~24k verts per frame, trivial on modern GPUs.

                let p00 = SIMD4<Float>(x0, y0, 0, 1)
                let p10 = SIMD4<Float>(x1, y0, 0, 1)
                let p01 = SIMD4<Float>(x0, y1, 0, 1)
                let p11 = SIMD4<Float>(x1, y1, 0, 1)
                verts.append(contentsOf: [
                    BarVertex(position: p00, color: c00),
                    BarVertex(position: p10, color: c10),
                    BarVertex(position: p01, color: c01),
                    BarVertex(position: p10, color: c10),
                    BarVertex(position: p11, color: c11),
                    BarVertex(position: p01, color: c01)
                ])
            }
        }
        return verts
    }

    // MARK: - 2D value noise (inline; mirrors RibbonWaveVisualizer's value1D extended to 2D)

    static func value2D(x: Double, y: Double, seed: UInt64) -> Double {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let xf = x - Double(xi), yf = y - Double(yi)
        func hash(_ ix: Int, _ iy: Int) -> Double {
            var h = UInt64(bitPattern: Int64(ix &* 374761393 &+ iy &* 668265263)) &+ seed
            h = (h ^ (h >> 13)) &* 1274126177
            return Double(h & 0xFFFFFF) / Double(0xFFFFFF)
        }
        let v00 = hash(xi, yi)
        let v10 = hash(xi + 1, yi)
        let v01 = hash(xi, yi + 1)
        let v11 = hash(xi + 1, yi + 1)
        let u = xf * xf * (3 - 2 * xf)
        let v = yf * yf * (3 - 2 * yf)
        let x0 = v00 + (v10 - v00) * u
        let x1 = v01 + (v11 - v01) * u
        return x0 + (x1 - x0) * v
    }
}