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

/// Outrun-the-Rain-specific shader parameters bound at fragment buffer index 2.
///
/// Plain POD whose field order and types MUST match the `OutrunRainUniforms`
/// struct declared in `Shaders.metal` (44 × `float`). Every field is a `Float`,
/// so the struct has no internal padding and Swift/Metal layouts match trivially.
///
/// Lives in Core (not the renderer) so the pure builder is unit-testable; the
/// renderer mirrors the existing Star Nest / Voronoi / LavaLamp buffer-2 pattern.
/// Each field is the prior hardcoded shader literal; `*Base` fields are resting
/// values and the rest are audio-response coefficients. The shader keeps its
/// `base + audio * coefficient` structure intact — only the numeric literals
/// became fields — so default values reproduce the original look byte-for-byte.
public struct OutrunRainUniforms: Equatable {
    // Horizon & Backdrop
    public var horizon: Float
    public var horizonGlowScale: Float
    public var horizonGlowBase: Float
    public var horizonBassGlow: Float
    public var lowMidBackdrop: Float
    public var backgroundBrightness: Float
    public var backgroundGlow: Float
    // Rain Motion
    public var leanBase: Float
    public var leanLowMid: Float
    public var fallBase: Float
    public var fallBass: Float
    public var fallEnergy: Float
    public var density: Float
    // Depth Layer 0
    public var layer0ColumnScale: Float
    public var layer0FallScale: Float
    public var layer0Seed: Float
    public var layer0Thickness: Float
    public var layer0Weight: Float
    // Depth Layer 1
    public var layer1ColumnScale: Float
    public var layer1FallScale: Float
    public var layer1Seed: Float
    public var layer1Thickness: Float
    public var layer1Weight: Float
    // Depth Layer 2
    public var layer2ColumnScale: Float
    public var layer2FallScale: Float
    public var layer2Seed: Float
    public var layer2Thickness: Float
    public var layer2Weight: Float
    // Sparkle Layer
    public var sparkleColumnScale: Float
    public var sparkleFallScale: Float
    public var sparkleSeed: Float
    public var sparkleThickness: Float
    public var sparkleBase: Float
    public var sparkleTreble: Float
    // Rain Shape & Color
    public var rainVerticalBase: Float
    public var rainVerticalY: Float
    public var rainColorBase: Float
    public var rainColorTreble: Float
    public var rainColorEnergy: Float
    // Brightness & Reflection
    public var rainBrightnessBase: Float
    public var rainBrightnessEnergy: Float
    public var rainBrightnessTreble: Float
    public var reflectionWidth: Float
    public var reflectionBass: Float
}

/// Pure mapping from settings to the Outrun the Rain shader uniform. Each scalar
/// maps straight through (Double → Float), no transposition. The lone exception
/// is `horizon`: it feeds `smoothstep(0.0, horizon, uv.y)` in the shader, where a
/// value of 0 makes edge0 == edge1 (undefined in Metal), so it is clamped up to a
/// small positive floor — a persisted/hand-edited 0 can never reach the GPU.
public func makeOutrunRainUniforms(_ settings: VisualizerSettings) -> OutrunRainUniforms {
    OutrunRainUniforms(
        horizon: max(0.05, Float(settings.outrunHorizon)),
        horizonGlowScale: Float(settings.outrunHorizonGlowScale),
        horizonGlowBase: Float(settings.outrunHorizonGlowBase),
        horizonBassGlow: Float(settings.outrunHorizonBassGlow),
        lowMidBackdrop: Float(settings.outrunLowMidBackdrop),
        backgroundBrightness: Float(settings.outrunBackgroundBrightness),
        backgroundGlow: Float(settings.outrunBackgroundGlow),
        leanBase: Float(settings.outrunLeanBase),
        leanLowMid: Float(settings.outrunLeanLowMid),
        fallBase: Float(settings.outrunFallBase),
        fallBass: Float(settings.outrunFallBass),
        fallEnergy: Float(settings.outrunFallEnergy),
        density: Float(settings.outrunDensity),
        layer0ColumnScale: Float(settings.outrunLayer0ColumnScale),
        layer0FallScale: Float(settings.outrunLayer0FallScale),
        layer0Seed: Float(settings.outrunLayer0Seed),
        layer0Thickness: Float(settings.outrunLayer0Thickness),
        layer0Weight: Float(settings.outrunLayer0Weight),
        layer1ColumnScale: Float(settings.outrunLayer1ColumnScale),
        layer1FallScale: Float(settings.outrunLayer1FallScale),
        layer1Seed: Float(settings.outrunLayer1Seed),
        layer1Thickness: Float(settings.outrunLayer1Thickness),
        layer1Weight: Float(settings.outrunLayer1Weight),
        layer2ColumnScale: Float(settings.outrunLayer2ColumnScale),
        layer2FallScale: Float(settings.outrunLayer2FallScale),
        layer2Seed: Float(settings.outrunLayer2Seed),
        layer2Thickness: Float(settings.outrunLayer2Thickness),
        layer2Weight: Float(settings.outrunLayer2Weight),
        sparkleColumnScale: Float(settings.outrunSparkleColumnScale),
        sparkleFallScale: Float(settings.outrunSparkleFallScale),
        sparkleSeed: Float(settings.outrunSparkleSeed),
        sparkleThickness: Float(settings.outrunSparkleThickness),
        sparkleBase: Float(settings.outrunSparkleBase),
        sparkleTreble: Float(settings.outrunSparkleTreble),
        rainVerticalBase: Float(settings.outrunRainVerticalBase),
        rainVerticalY: Float(settings.outrunRainVerticalY),
        rainColorBase: Float(settings.outrunRainColorBase),
        rainColorTreble: Float(settings.outrunRainColorTreble),
        rainColorEnergy: Float(settings.outrunRainColorEnergy),
        rainBrightnessBase: Float(settings.outrunRainBrightnessBase),
        rainBrightnessEnergy: Float(settings.outrunRainBrightnessEnergy),
        rainBrightnessTreble: Float(settings.outrunRainBrightnessTreble),
        reflectionWidth: Float(settings.outrunReflectionWidth),
        reflectionBass: Float(settings.outrunReflectionBass)
    )
}
