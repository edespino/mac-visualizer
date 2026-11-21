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

/// Plasma-specific shader parameters bound at fragment buffer index 2.
///
/// Plain POD whose field order and types MUST match the `PlasmaUniforms` struct
/// declared in `Shaders.metal` (15 × `float`). Every field is a `Float`, so the
/// struct has no internal padding and the Swift/Metal layouts match trivially
/// (stride 60). Each field is the prior hardcoded `plasma_fs` literal; the
/// shader keeps its `+ t * scale` time-phase and `+ energy * coeff` brightness
/// structure intact — only the numeric literals became fields — so default
/// values reproduce the original look byte-for-byte.
///
/// Lives in Core (not the renderer) so the pure builder is unit-testable; the
/// renderer mirrors the existing Star Nest / Outrun the Rain buffer-2 pattern.
public struct PlasmaUniforms: Equatable {
    // Pattern
    public var coordinateScale: Float
    public var coordinateOffset: Float
    public var xFrequency: Float
    public var yFrequency: Float
    public var diagonalFrequency: Float
    // Animation
    public var xTimeScale: Float
    public var yTimeScale: Float
    public var diagonalTimeScale: Float
    // Color
    public var waveDivisor: Float
    public var contrast: Float
    public var brightnessBias: Float
    public var energyResponse: Float
    public var clampMin: Float
    public var clampMax: Float
    public var alpha: Float
}

/// Pure mapping from settings to the Plasma shader uniform. Most scalars map
/// straight through (Double → Float). The exceptions enforce shader safety:
/// `coordinateScale` scales/recentres the UV (a 0 collapses the pattern) so it
/// is floored to a small positive epsilon; `waveDivisor` is the `v / divisor`
/// normaliser so it is floored to 0.1 to forbid divide-by-zero; `clampMax` is
/// raised to `clampMin` when a persisted value would invert the shader's
/// `clamp(v, min, max)`; and `alpha` is clamped to the valid 0...1 opacity range.
public func makePlasmaUniforms(_ settings: VisualizerSettings) -> PlasmaUniforms {
    let clampMin = Float(settings.plasmaClampMin)
    let clampMax = max(clampMin, Float(settings.plasmaClampMax))
    return PlasmaUniforms(
        coordinateScale: max(1e-3, Float(settings.plasmaCoordinateScale)),
        coordinateOffset: Float(settings.plasmaCoordinateOffset),
        xFrequency: Float(settings.plasmaXFrequency),
        yFrequency: Float(settings.plasmaYFrequency),
        diagonalFrequency: Float(settings.plasmaDiagonalFrequency),
        xTimeScale: Float(settings.plasmaXTimeScale),
        yTimeScale: Float(settings.plasmaYTimeScale),
        diagonalTimeScale: Float(settings.plasmaDiagonalTimeScale),
        waveDivisor: max(0.1, Float(settings.plasmaWaveDivisor)),
        contrast: Float(settings.plasmaContrast),
        brightnessBias: Float(settings.plasmaBrightnessBias),
        energyResponse: Float(settings.plasmaEnergyResponse),
        clampMin: clampMin,
        clampMax: clampMax,
        alpha: min(1.0, max(0.0, Float(settings.plasmaAlpha)))
    )
}
