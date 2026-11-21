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
/// Full-screen volumetric fractal starfield shader. This Swift class is a
/// stub — it exists only to satisfy `VisualizerStyle.makeVisualizer()`. The
/// actual rendering happens in `star_nest_fs` inside `Shaders.metal`,
/// dispatched by `MetalRenderer.encodeShaderFill(...)` when
/// `style.customShader(settings:) == .starNest`.
public final class StarNestVisualizer: Visualizer {
    public init() {}

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings,
                             palette: ColorPalette, aspect: Float) -> [BarVertex] {
        return []
    }
}
