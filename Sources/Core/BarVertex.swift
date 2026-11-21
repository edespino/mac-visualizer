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

/// One vertex for the bar renderer. Layout MUST match the `Vertex` struct in Shaders.metal:
/// two 16-byte-aligned float4s, total stride 32 bytes. `position.xy` is Metal clip space.
public struct BarVertex: Equatable {
    public var position: SIMD4<Float> // xy used (clip space), zw unused
    public var color: SIMD4<Float>    // rgba, 0...1

    public init(position: SIMD4<Float>, color: SIMD4<Float>) {
        self.position = position
        self.color = color
    }
}