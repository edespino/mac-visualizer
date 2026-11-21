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
@testable import MacVisualizerCore

final class MarchingSquaresTests: XCTestCase {

    func testEmptyFieldProducesNoSegments() {
        let grid = Array(repeating: Array(repeating: Float(0), count: 16), count: 16)
        let segments = MarchingSquares.extractIsoLines(grid: grid, threshold: 0.5, cellSize: 0.1, origin: SIMD2(-1, -1))
        XCTAssertEqual(segments.count, 0)
    }

    func testCircleFieldProducesClosedContour() {
        // A circular density field centered at origin with value = 1 - r
        // At threshold 0.5 the iso-line is the circle r = 0.5.
        let gridSize = 64
        let cellSize: Float = 2.0 / Float(gridSize - 1)
        var grid = Array(repeating: Array(repeating: Float(0), count: gridSize), count: gridSize)
        for y in 0..<gridSize {
            for x in 0..<gridSize {
                let fx = -1 + Float(x) * cellSize
                let fy = -1 + Float(y) * cellSize
                let r = sqrtf(fx * fx + fy * fy)
                grid[y][x] = max(0, 1 - r)
            }
        }
        let segments = MarchingSquares.extractIsoLines(grid: grid, threshold: 0.5, cellSize: cellSize, origin: SIMD2(-1, -1))
        XCTAssertGreaterThan(segments.count, 20, "expected many segments for a closed circle")
        // Each segment endpoint should lie close to r = 0.5
        for seg in segments {
            for p in [seg.a, seg.b] {
                let r = sqrtf(p.x * p.x + p.y * p.y)
                XCTAssertEqual(r, 0.5, accuracy: 0.05, "segment endpoint should be near r=0.5; got r=\(r)")
            }
        }
    }

    func testSaddleCase10ProducesSeparateSegments() {
        // caseIdx=10: TL + BR above threshold. "Separate" tiebreak → 2 disjoint segments.
        let grid: [[Float]] = [
            [1.0, 0.0],   // TL above, TR below
            [0.0, 1.0]    // BL below, BR above
        ]
        let segments = MarchingSquares.extractIsoLines(grid: grid, threshold: 0.5, cellSize: 1.0, origin: SIMD2(0, 0))
        XCTAssertEqual(segments.count, 2, "case 10 should produce 2 disjoint segments")
    }

    func testSaddleCase5ProducesSeparateSegments() {
        // caseIdx=5: TR + BL above threshold. "Separate" tiebreak → 2 disjoint segments.
        let grid: [[Float]] = [
            [0.0, 1.0],   // TL below, TR above
            [1.0, 0.0]    // BL above, BR below
        ]
        let segments = MarchingSquares.extractIsoLines(grid: grid, threshold: 0.5, cellSize: 1.0, origin: SIMD2(0, 0))
        XCTAssertEqual(segments.count, 2, "case 5 should produce 2 disjoint segments")
    }
}