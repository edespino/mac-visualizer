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
/// A visualizer turns an audio frame + settings into triangle vertices in clip space.
/// `aspect` is viewport width / height (used by styles that must stay proportional,
/// e.g. the radial circle); styles that don't need it ignore it.
///
/// `palette` is the EFFECTIVE palette resolved for this frame by the renderer. When
/// the palette auto-cycle is mid-fade it is the blended palette; otherwise it is
/// exactly `ColorPalette.preset(named: settings.paletteName) ?? .fallback`. Color-
/// emitting CPU visualizers must color their geometry from this parameter (never a
/// fresh `ColorPalette.preset(...)` lookup) so the crossfade is gradual on every
/// style; visualizers that don't draw from a palette accept and ignore it.
///
/// Pure and GPU-free so it can be unit-tested; the Metal renderer encodes the result.
public protocol Visualizer {
    func makeVertices(frame: AudioFrame, settings: VisualizerSettings,
                      palette: ColorPalette, aspect: Float) -> [BarVertex]
}

public extension Visualizer {
    /// Value-preserving convenience overload: resolves the palette with the same
    /// fallback `effectivePalette()` uses when NOT mid-fade, then forwards to the
    /// palette-aware requirement. This is the single source of the feature-off
    /// anchor — callers that don't participate in the crossfade (the offscreen
    /// render probe, the test suite) get byte-identical output to the pre-crossfade
    /// behavior without threading a palette. The live draw path passes the
    /// effective (possibly blended) palette explicitly instead.
    func makeVertices(frame: AudioFrame, settings: VisualizerSettings, aspect: Float) -> [BarVertex] {
        makeVertices(frame: frame, settings: settings,
                     palette: ColorPalette.preset(named: settings.paletteName) ?? .fallback,
                     aspect: aspect)
    }
}