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

/// Maximum Voronoi seed capacity baked into the shader uniform / Swift POD.
/// The active count (`VoronoiUniforms.activeCount`) is driven by the
/// `voronoiSeedCount` user setting and may be smaller; the array is always
/// allocated to capacity so the Swift↔Metal layout is fixed-size. The capacity
/// was raised from the original hardcoded 75 to 128 so the seed-count slider can
/// grow past the default without changing the layout; the default `activeCount`
/// is 75, which loops over exactly the first 75 slots — byte-identical to the
/// prior fixed-75 shader.
public let kVoronoiSeedCapacity = 128

/// Voronoi blobs shader parameters bound at fragment buffer index 2.
///
/// Plain POD whose field order/types MUST match the `VoronoiUniforms` struct
/// declared in `Shaders.metal`. The `seedsAndBands` capacity-128 `float4` array
/// is stored as a fixed tuple (a Swift `[SIMD4<Float>]` does NOT survive
/// `setFragmentBytes`); `withUnsafeMutableBytes` populates it. The scalar tail
/// trails the array and the lone `Int32` (`activeCount`) is last so the struct
/// has no internal padding and the Swift/Metal layouts match (stride 2064).
///
/// Lives in Core (not the renderer) so the pure builder is unit-testable; the
/// renderer becomes a thin caller. `K` (edge sharpness) and `beatBoost` were
/// previously hardcoded shader/builder literals (12.0 and the `0.3 *
/// beatIntensity` coefficient) and are now driven by user settings; their
/// defaults reproduce the original look exactly.
public struct VoronoiUniforms {
    // xy = seed position in NDC, z = band level, w = unused. Capacity 128; only
    // the first `activeCount` entries are populated, the rest stay zero.
    public var seedsAndBands: (
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>
    ) = (
        .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
        .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
        .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
        .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
        .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
        .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
        .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
        .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
        .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
        .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
        .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
        .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
        .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
        .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
        .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
        .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero
    )
    public var K: Float = 12.0           // edge sharpness; higher = sharper cells
    public var beatBoost: Float = 0      // 0..1 added brightness on a beat frame
    public var fadeBrightness: Float = 1 // 0..1 fade-to-black multiplier (1 = full, 0 = black)
    public var activeCount: Int32 = 75   // shader loop bound (Int32 last → no padding)
}

/// Pure mapping from the static blobs seed set + live fade + settings to the
/// shader uniform. The renderer supplies `seeds` (its own static seed set — the
/// blobs path keeps its existing seed source, distinct from the live
/// `VoronoiVisualizer.seeds` used by cells/softCells) and `fadeBrightness`
/// (`VoronoiVisualizer.currentFadeBrightness()`), so cycle/perTrack fades dim
/// the blobs too. Band assignment per seed reproduces the prior renderer code
/// verbatim, including the stereo split (x<0 → bandsLeft, x>=0 → bandsRight).
///
/// Clamps protect the GPU from persisted/hand-edited values:
///   - `K` feeds `exp(-K*dEdge)`; a non-positive K blows the falloff up, so it is
///     floored to a small positive epsilon (1e-4).
///   - `activeCount` is the shader loop bound and the shader indexes
///     `seedsAndBands[nearestIdx]`, so it is clamped to `1...capacity` and bounded
///     by the supplied seed count.
/// Every default value passes its clamp unchanged, so the look is unaltered
/// until a slider moves.
public func makeVoronoiUniforms(seeds: [SIMD2<Float>],
                                fadeBrightness: Float,
                                frame: AudioFrame,
                                settings: VisualizerSettings) -> VoronoiUniforms {
    var u = VoronoiUniforms()
    u.K = max(1e-4, Float(settings.voronoiEdgeSharpness))
    u.beatBoost = frame.beat ? Float(settings.voronoiShaderBeatBoost) * max(0, min(1, frame.beatIntensity)) : 0
    u.fadeBrightness = fadeBrightness

    let available = min(kVoronoiSeedCapacity, seeds.count)
    // Empty seeds → activeCount 0 is the intended safe degenerate (a 0-length
    // shader loop); it is NOT a clamp bug. Looping with no seeds would index
    // uninitialized data. Non-empty seeds always clamp activeCount to 1...capacity.
    guard available > 0 else { u.activeCount = 0; return u }
    let count = max(1, min(available, settings.voronoiSeedCount))

    var arr = [SIMD4<Float>](repeating: .zero, count: kVoronoiSeedCapacity)
    for i in 0..<count {
        let s = seeds[i]
        let level: Float
        if settings.useStereoImage {
            let leftHalf = s.x < 0
            let source = leftHalf ? frame.bandsLeft : frame.bandsRight
            let bi = i % max(source.count, 1)
            level = source.isEmpty ? 0 : source[bi]
        } else {
            let bi = i % max(frame.bands.count, 1)
            level = frame.bands.isEmpty ? 0 : frame.bands[bi]
        }
        arr[i] = SIMD4<Float>(s.x, s.y, level, 0)
    }
    withUnsafeMutableBytes(of: &u.seedsAndBands) { dest in
        arr.withUnsafeBytes { src in
            dest.copyMemory(from: src)
        }
    }
    u.activeCount = Int32(count)
    return u
}
