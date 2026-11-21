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
import Foundation

/// Identifies which Metal fragment shader a shader-driven visualizer uses.
/// `VisualizerStyle.customShader(settings:)` returns one of these (or nil for the
/// standard geometry-based visualizers).
public enum ShaderKind: String, Codable, CaseIterable {
    case plasma
    case bumpscope
    case voronoiBlobs
    case lavaLampShader
    case octaveMeatballs
    case starNest
    case outrunRain
    case spinner
}
