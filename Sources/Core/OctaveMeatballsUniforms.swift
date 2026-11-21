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

/// Octave-Meatballs-specific shader parameters bound at fragment buffer index 2.
///
/// Plain POD whose field order and types MUST match the `OctaveMeatballsUniforms`
/// struct declared in `Shaders.metal` (29 × `float`, then 1 × `int`). The 29
/// scalars are `Float`; the lone `octaves` density loop-count is `Int32`, already
/// clamped to a safe `1...32` range by `makeOctaveMeatballsUniforms`. The int is
/// last so the struct has no internal padding and Swift/Metal layouts match.
///
/// Lives in Core (not the renderer) so the pure builder is unit-testable; the
/// renderer mirrors the existing Star Nest / Outrun the Rain buffer-2 pattern.
/// Each field is a prior hardcoded shader literal; `*Base`-style fields are
/// resting values and the rest are audio-response coefficients. The shader keeps
/// its `base + audio * coefficient` structure intact — only the numeric literals
/// became fields — so default values reproduce the original look byte-for-byte.
public struct OctaveMeatballsUniforms: Equatable {
    // Pattern & Scale
    public var scale: Float
    public var ballDivisor: Float
    // Background color
    public var backgroundR: Float
    public var backgroundG: Float
    public var backgroundB: Float
    // Shimmer & Drift
    public var octavePhase: Float
    public var shimmerOctaveScale: Float
    public var shimmerTimeScale: Float
    public var lifeTimeScale: Float
    public var pulseEdge0: Float
    public var pulseEdge1: Float
    public var lifeOctaveScale: Float
    public var lifeDenomBase: Float
    public var lifeDenomRadius: Float
    public var lifeDenomScale: Float
    // Metaball field
    public var distanceFloor: Float
    public var ballStrength: Float
    public var ballBase: Float
    // Red glow color
    public var redGlowR: Float
    public var redGlowG: Float
    public var redGlowB: Float
    // Palette
    public var paletteFieldGain: Float
    public var paletteGain: Float
    // Audio response coefficients
    public var bandPhase: Float
    public var bandBrightness: Float
    public var energyBrightness: Float
    public var paletteEnergy: Float
    /// Clip-space shift applied to the field, same axes as geometry position
    /// offset (x right, y up). Zero leaves the original fullscreen picture.
    /// A non-zero value moves the field and leaves the uncovered window clear,
    /// so the background does not stay painted edge to edge.
    public var offsetX: Float
    public var offsetY: Float
    // Density (structural loop bound, Int32 last to keep layout padding-free)
    public var octaves: Int32
}

/// Pure mapping from settings to the Octave Meatballs shader uniform. Most
/// scalars map straight through (Double → Float). The clamps protect the GPU
/// from persisted/hand-edited values that would produce divide-by-zero or
/// undefined behaviour:
///   - `octaves` is the loop bound and divides `float(octaves)`; clamp to 1...32.
///   - `pulseEdge1` feeds `smoothstep(pulseEdge0, pulseEdge1, ...)`, undefined
///     for equal/inverted edges; raise it to at least `pulseEdge0 + 0.01`.
///   - `scale`, `ballDivisor`, `lifeDenomBase`, `lifeDenomScale`, `distanceFloor`
///     are divisors/denominators floored to a small positive epsilon (1e-4).
///   - `lifeDenomRadius` scales `l` inside that same drift denominator; a
///     negative value could cancel `lifeDenomBase` to zero, so it is floored
///     to 0 (with `l >= 0` the denominator then stays strictly positive).
/// Every default value passes its clamp unchanged, so the look is unaltered
/// until a slider moves.
public func makeOctaveMeatballsUniforms(_ settings: VisualizerSettings,
                                        offsetX: Float = 0,
                                        offsetY: Float = 0) -> OctaveMeatballsUniforms {
    let epsilon: Float = 1e-4
    let edge0 = Float(settings.octaveMeatballsPulseEdge0)
    let edge1 = max(Float(settings.octaveMeatballsPulseEdge1), edge0 + 0.01)
    return OctaveMeatballsUniforms(
        scale: max(epsilon, Float(settings.octaveMeatballsScale)),
        ballDivisor: max(epsilon, Float(settings.octaveMeatballsBallDivisor)),
        backgroundR: Float(settings.octaveMeatballsBackgroundR),
        backgroundG: Float(settings.octaveMeatballsBackgroundG),
        backgroundB: Float(settings.octaveMeatballsBackgroundB),
        octavePhase: Float(settings.octaveMeatballsOctavePhase),
        shimmerOctaveScale: Float(settings.octaveMeatballsShimmerOctaveScale),
        shimmerTimeScale: Float(settings.octaveMeatballsShimmerTimeScale),
        lifeTimeScale: Float(settings.octaveMeatballsLifeTimeScale),
        pulseEdge0: edge0,
        pulseEdge1: edge1,
        lifeOctaveScale: Float(settings.octaveMeatballsLifeOctaveScale),
        lifeDenomBase: max(epsilon, Float(settings.octaveMeatballsLifeDenomBase)),
        lifeDenomRadius: max(0.0, Float(settings.octaveMeatballsLifeDenomRadius)),
        lifeDenomScale: max(epsilon, Float(settings.octaveMeatballsLifeDenomScale)),
        distanceFloor: max(epsilon, Float(settings.octaveMeatballsDistanceFloor)),
        ballStrength: Float(settings.octaveMeatballsBallStrength),
        ballBase: Float(settings.octaveMeatballsBallBase),
        redGlowR: Float(settings.octaveMeatballsRedGlowR),
        redGlowG: Float(settings.octaveMeatballsRedGlowG),
        redGlowB: Float(settings.octaveMeatballsRedGlowB),
        paletteFieldGain: Float(settings.octaveMeatballsPaletteFieldGain),
        paletteGain: Float(settings.octaveMeatballsPaletteGain),
        bandPhase: Float(settings.octaveMeatballsBandPhase),
        bandBrightness: Float(settings.octaveMeatballsBandBrightness),
        energyBrightness: Float(settings.octaveMeatballsEnergyBrightness),
        paletteEnergy: Float(settings.octaveMeatballsPaletteEnergy),
        offsetX: offsetX,
        offsetY: offsetY,
        octaves: Int32(min(32, max(1, settings.octaveMeatballsOctaves)))
    )
}
