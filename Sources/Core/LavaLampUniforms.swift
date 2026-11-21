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

/// Maximum metaball point capacity baked into the shader uniform / Swift POD.
/// The active count (`LavaLampUniforms.pointCount`) is driven by the
/// `lavaLampBlobCount` user setting and may be smaller; the array is always
/// allocated to capacity so the Swift↔Metal layout is fixed-size.
public let kLavaLampPointCapacity = 24

/// Lava-Lamp shader parameters bound at fragment buffer index 2.
///
/// Plain POD whose field order/types MUST match the `LavaLampUniforms` struct
/// declared in `Shaders.metal`. The `pointsAndAmps` capacity-24 `float4` array
/// is stored as a fixed tuple (a Swift `[SIMD4<Float>]` does NOT survive
/// `setFragmentBytes`); `withUnsafeMutableBytes` populates it. The scalar tail
/// trails the array and the lone `Int32` (`pointCount`) is last so the struct
/// has no internal padding and the Swift/Metal layouts match (stride 432).
///
/// `thresholds`/`tolerance` are retained verbatim from the original struct.
/// They are computed but unused by both render paths today (the marching-squares
/// emitter and `lavalamp_fs` ignore them); they are kept exactly as-is rather
/// than activated, which would be a behaviour change.
public struct LavaLampUniforms {
    // xy = position NDC, z = amplitude, w = unused. Capacity 24; only the first
    // `pointCount` entries are populated, the rest stay zero.
    public var pointsAndAmps: (
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>
    ) = (
        .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
        .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
        .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero
    )
    public var thresholds: (Float, Float, Float, Float) = (0, 0, 0, 0)  // retained, unused (see note)
    public var tolerance: Float = 0.05                                   // retained, unused (see note)
    public var beatBoost: Float = 0
    public var densityFalloff: Float = 8.0
    public var brightnessResponse: Float = 0.8
    public var paletteDensityScale: Float = 0.4
    public var pointCount: Int32 = 0
}

/// Pure mapping from a `LavaLampVisualizer`'s live point state + settings to the
/// shader uniform. Packs up to `kLavaLampPointCapacity` moving points (position
/// + audio amplitude) and the shared field/color scalars.
///
/// Clamps protect the GPU from persisted/hand-edited values:
///   - `densityFalloff` multiplies inside `exp(-r2 * K)`; a non-positive K would
///     invert the Gaussian, so it is floored to a small positive epsilon (1e-4).
///     This MUST match the identical floor applied in `LavaLampVisualizer`'s CPU
///     density so both render modes stay in lock-step.
///   - `pointCount` is the shader loop bound; it is the live point count clamped
///     to `0...kLavaLampPointCapacity`.
/// Every default value passes its clamp unchanged, so the look is unaltered
/// until a slider moves.
public func makeLavaLampUniforms(visualizer: LavaLampVisualizer?,
                                 frame: AudioFrame,
                                 settings: VisualizerSettings) -> LavaLampUniforms {
    var u = LavaLampUniforms()
    u.densityFalloff = max(1e-4, Float(settings.lavaLampDensityFalloff))
    u.brightnessResponse = Float(settings.lavaLampBrightnessResponse)
    u.paletteDensityScale = Float(settings.lavaLampPaletteDensityScale)
    u.beatBoost = frame.beat ? Float(settings.lavaLampShaderBeatBoost) * max(0, min(1, frame.beatIntensity)) : 0

    guard let viz = visualizer else { return u }
    let amps = viz.currentAmplitudes(frame: frame, settings: settings)
    let count = min(kLavaLampPointCapacity, viz.points.count)
    var pa = [SIMD4<Float>](repeating: .zero, count: kLavaLampPointCapacity)
    for i in 0..<count {
        let p = viz.points[i]
        pa[i] = SIMD4<Float>(p.position.x, p.position.y, amps[i], 0)
    }
    withUnsafeMutableBytes(of: &u.pointsAndAmps) { dest in
        pa.withUnsafeBytes { src in
            dest.copyMemory(from: src)
        }
    }
    u.pointCount = Int32(count)

    // Retain the original threshold/tolerance values verbatim (unused by both
    // render paths today; kept rather than activated to avoid a look change).
    let thr = viz.currentThresholds()
    u.thresholds = (
        thr.indices.contains(0) ? thr[0] : 0,
        thr.indices.contains(1) ? thr[1] : 0,
        thr.indices.contains(2) ? thr[2] : 0,
        thr.indices.contains(3) ? thr[3] : 0
    )
    u.tolerance = 0.15
    return u
}
