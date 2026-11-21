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

/// Star-Nest-specific shader parameters bound at fragment buffer index 2.
///
/// Plain POD whose field order and types MUST match the `StarNestUniforms`
/// struct declared in `Shaders.metal` (9 × `float`, then 2 × `int`). The 9
/// scalars are `Float`; the 2 density loop-counts are `Int32`, already clamped
/// to the shader's compile-time loop maxima by `makeStarNestUniforms`.
///
/// Lives in Core (not the renderer) so the pure builder is unit-testable; the
/// renderer mirrors the existing Voronoi/LavaLamp buffer-2 binding pattern.
public struct StarNestUniforms: Equatable {
    public var zoom: Float
    public var speed: Float
    public var formuparam: Float
    public var tile: Float
    public var stepsize: Float
    public var brightness: Float
    public var darkmatter: Float
    public var distfading: Float
    public var saturation: Float
    public var volsteps: Int32
    public var iterations: Int32
}

/// Pure mapping from settings to the Star Nest shader uniform. Each scalar maps
/// straight through; `volsteps`/`iterations` clamp to the existing loop caps
/// (`1...26` / `1...16`) so worst-case GPU cost is never raised.
public func makeStarNestUniforms(_ settings: VisualizerSettings) -> StarNestUniforms {
    StarNestUniforms(
        zoom: Float(settings.starNestZoom),
        speed: Float(settings.starNestSpeed),
        formuparam: Float(settings.starNestFormuparam),
        tile: Float(settings.starNestTile),
        stepsize: Float(settings.starNestStepsize),
        brightness: Float(settings.starNestBrightness),
        darkmatter: Float(settings.starNestDarkmatter),
        distfading: Float(settings.starNestDistfading),
        saturation: Float(settings.starNestSaturation),
        volsteps: Int32(min(26, max(1, settings.starNestVolsteps))),
        iterations: Int32(min(16, max(1, settings.starNestIterations)))
    )
}
