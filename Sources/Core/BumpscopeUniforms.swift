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

/// Bumpscope-specific shader parameters bound at fragment buffer index 2.
///
/// Plain POD whose field order and types MUST match the `BumpscopeUniforms`
/// struct declared in `Shaders.metal` (14 × `float` interleaved with 1 × `int`).
/// Every field is 4 bytes with 4-byte alignment (both `Float` and `Int32`), so
/// the struct is tightly packed with no internal or trailing padding and the
/// Swift/Metal layouts match trivially (stride 60). Each field is the prior
/// hardcoded `bumpscope_fs` literal; the shader keeps its band-slope / Lambert
/// lighting / `h*gain + bias` structure intact — only the numeric literals
/// became fields — so default values reproduce the original look byte-for-byte.
///
/// Lives in Core (not the renderer) so the pure builder is unit-testable; the
/// renderer mirrors the existing Plasma / Star Nest buffer-2 binding pattern.
public struct BumpscopeUniforms: Equatable {
    // UV sampling
    public var uvClampMin: Float
    public var uvClampMax: Float
    public var neighborRadius: Int32
    // Bump slope & surface
    public var slopeScale: Float
    public var surfaceNormalY: Float
    public var surfaceNormalZ: Float
    // Lighting
    public var lightX: Float
    public var lightY: Float
    public var lightZ: Float
    public var diffuseFloor: Float
    // Color & audio
    public var bandGain: Float
    public var intensityBias: Float
    public var intensityClampMin: Float
    public var intensityClampMax: Float
    public var alpha: Float
}

/// Pure mapping from settings to the Bumpscope shader uniform. Most scalars map
/// straight through (Double → Float). The exceptions enforce shader safety:
/// `uvClampMax` and `intensityClampMax` are raised to their matching min so a
/// persisted value can never invert the shader's `clamp(v, min, max)`;
/// `diffuseFloor` and `alpha` are clamped to the valid 0...1 range; and
/// `neighborRadius` is clamped to 0...15 so `bands[xi ± radius]` (a fixed
/// 16-element array) can never leave the band index domain. The shader still
/// re-clamps `xi ± radius` to 0...15, so the two guards together keep indexing
/// in bounds. Normalize-of-zero hazards from the exposed surface-normal and
/// light vectors are guarded in the shader, not here (defaults are nonzero).
public func makeBumpscopeUniforms(_ settings: VisualizerSettings) -> BumpscopeUniforms {
    let uvMin = Float(settings.bumpscopeUvClampMin)
    let uvMax = max(uvMin, Float(settings.bumpscopeUvClampMax))
    let intMin = Float(settings.bumpscopeIntensityClampMin)
    let intMax = max(intMin, Float(settings.bumpscopeIntensityClampMax))
    return BumpscopeUniforms(
        uvClampMin: uvMin,
        uvClampMax: uvMax,
        neighborRadius: Int32(min(15, max(0, settings.bumpscopeNeighborRadius))),
        slopeScale: Float(settings.bumpscopeSlopeScale),
        surfaceNormalY: Float(settings.bumpscopeSurfaceNormalY),
        surfaceNormalZ: Float(settings.bumpscopeSurfaceNormalZ),
        lightX: Float(settings.bumpscopeLightX),
        lightY: Float(settings.bumpscopeLightY),
        lightZ: Float(settings.bumpscopeLightZ),
        diffuseFloor: min(1.0, max(0.0, Float(settings.bumpscopeDiffuseFloor))),
        bandGain: Float(settings.bumpscopeBandGain),
        intensityBias: Float(settings.bumpscopeIntensityBias),
        intensityClampMin: intMin,
        intensityClampMax: intMax,
        alpha: min(1.0, max(0.0, Float(settings.bumpscopeAlpha)))
    )
}
