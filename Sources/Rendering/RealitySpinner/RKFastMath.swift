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

import Foundation

// Non-generic scalar helpers for the CPU texture generators. In a Debug build the standard library's generic
// functions (min, max, abs, UInt8(clamping:), iteration over a Range) are not specialised, even inside functions marked
// @_optimize(speed), and dominated the per-pixel cost of RealityKit's setup. These concrete Float / Int versions
// compile to straight-line code at every optimisation level and give the same results.

@inline(__always) func rkMin(_ a: Float, _ b: Float) -> Float { return a < b ? a : b }
@inline(__always) func rkMax(_ a: Float, _ b: Float) -> Float { return a > b ? a : b }
@inline(__always) func rkAbs(_ a: Float) -> Float { return a < 0 ? -a : a }
@inline(__always) func rkClamp01(_ x: Float) -> Float { return x < 0 ? 0 : (x > 1 ? 1 : x) }
@inline(__always) func rkMinInt(_ a: Int, _ b: Int) -> Int { return a < b ? a : b }

/// Equivalent of `UInt8(clamping: Int(v))` for a finite Float: truncates toward zero and limits to 0...255.
@inline(__always) func rkClampByte(_ v: Float) -> UInt8 {
    if v <= 0 { return 0 }
    if v >= 255 { return 255 }
    return UInt8(v)
}
