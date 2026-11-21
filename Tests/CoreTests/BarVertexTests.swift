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
import XCTest
import simd
@testable import MacVisualizerCore

final class BarVertexTests: XCTestCase {
    /// The Swift layout MUST match the Metal `Vertex` struct (two float4s, 32-byte stride).
    /// If this fails, the renderer will read garbled geometry — update Shaders.metal to match.
    func testMemoryLayoutMatchesMetalVertexStruct() {
        XCTAssertEqual(MemoryLayout<BarVertex>.stride, 32)
        XCTAssertEqual(MemoryLayout<BarVertex>.size, 32)
        XCTAssertEqual(MemoryLayout<BarVertex>.alignment, 16)
        // position at offset 0, color at offset 16.
        XCTAssertEqual(MemoryLayout<BarVertex>.offset(of: \.position), 0)
        XCTAssertEqual(MemoryLayout<BarVertex>.offset(of: \.color), 16)
    }
}