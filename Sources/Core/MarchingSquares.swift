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

/// Iso-line extraction from a sampled 2D density grid. Each cell of the grid
/// produces 0, 1, or 2 line segments based on which of its 4 corners exceed
/// the threshold. Saddle cases (5 and 10) use the "separate" tiebreak —
/// two disjoint segments, not a connected curve through the cell center.
/// This choice produces visually less-confusing iso-contours for the metaball
/// use case (moving points with periodic threshold crossings).
public enum MarchingSquares {

    public struct Segment: Equatable {
        public let a: SIMD2<Float>
        public let b: SIMD2<Float>
    }

    /// Extract iso-line segments from a 2D grid.
    ///
    /// - Parameters:
    ///   - grid: 2D array of density values. `grid[y][x]` accessed as row-major.
    ///   - threshold: density value at which iso-lines are drawn.
    ///   - cellSize: world-space width/height of each grid cell.
    ///   - origin: world-space position of grid[0][0].
    public static func extractIsoLines(grid: [[Float]], threshold: Float, cellSize: Float, origin: SIMD2<Float>) -> [Segment] {
        let rows = grid.count
        guard rows >= 2 else { return [] }
        let cols = grid[0].count
        guard cols >= 2 else { return [] }

        var segments: [Segment] = []
        for y in 0..<(rows - 1) {
            for x in 0..<(cols - 1) {
                let tl = grid[y][x]
                let tr = grid[y][x + 1]
                let br = grid[y + 1][x + 1]
                let bl = grid[y + 1][x]
                // 4-bit case: TL=8, TR=4, BR=2, BL=1
                var caseIdx = 0
                if tl > threshold { caseIdx |= 8 }
                if tr > threshold { caseIdx |= 4 }
                if br > threshold { caseIdx |= 2 }
                if bl > threshold { caseIdx |= 1 }

                // Interpolated edge crossing positions (in world space):
                let cx = origin.x + Float(x) * cellSize
                let cy = origin.y + Float(y) * cellSize
                func lerpEdge(_ va: Float, _ vb: Float, _ ax: Float, _ ay: Float, _ bx: Float, _ by: Float) -> SIMD2<Float> {
                    // Crossing where (1-t)*va + t*vb = threshold; t = (threshold - va) / (vb - va)
                    let denom = vb - va
                    let t: Float = abs(denom) < 1e-6 ? 0.5 : (threshold - va) / denom
                    let tc = max(0, min(1, t))
                    return SIMD2(ax + (bx - ax) * tc, ay + (by - ay) * tc)
                }
                // Edge endpoints in world space:
                let topX0 = cx,                topX1 = cx + cellSize
                let topY  = cy
                let botX0 = cx,                botX1 = cx + cellSize
                let botY  = cy + cellSize
                // Edge crossings (4 possible: top, right, bottom, left)
                let crossTop    = lerpEdge(tl, tr, topX0, topY, topX1, topY)
                let crossRight  = lerpEdge(tr, br, topX1, topY, botX1, botY)
                let crossBottom = lerpEdge(bl, br, botX0, botY, botX1, botY)
                let crossLeft   = lerpEdge(tl, bl, topX0, topY, botX0, botY)

                switch caseIdx {
                case 0, 15: break   // all in or all out
                case 1:    segments.append(Segment(a: crossLeft,   b: crossBottom))   // BL in
                case 14:   segments.append(Segment(a: crossLeft,   b: crossBottom))
                case 2:    segments.append(Segment(a: crossBottom, b: crossRight))    // BR in
                case 13:   segments.append(Segment(a: crossBottom, b: crossRight))
                case 3:    segments.append(Segment(a: crossLeft,   b: crossRight))    // BL+BR in
                case 12:   segments.append(Segment(a: crossLeft,   b: crossRight))
                case 4:    segments.append(Segment(a: crossTop,    b: crossRight))    // TR in
                case 11:   segments.append(Segment(a: crossTop,    b: crossRight))
                case 6:    segments.append(Segment(a: crossTop,    b: crossBottom))   // TR+BR in
                case 9:    segments.append(Segment(a: crossTop,    b: crossBottom))
                case 7:    segments.append(Segment(a: crossLeft,   b: crossTop))      // TR+BR+BL in (TL out)
                case 8:    segments.append(Segment(a: crossLeft,   b: crossTop))      // TL in
                case 5:
                    // Saddle: TR + BL above (caseIdx 5 = 0b0101). "Separate" tiebreak → 2 disjoint segments.
                    segments.append(Segment(a: crossTop, b: crossRight))     // isolates TR
                    segments.append(Segment(a: crossLeft, b: crossBottom))   // isolates BL
                case 10:
                    // Saddle: TL + BR above (caseIdx 10 = 0b1010). "Separate" tiebreak.
                    segments.append(Segment(a: crossLeft, b: crossTop))      // isolates TL
                    segments.append(Segment(a: crossBottom, b: crossRight))  // isolates BR
                default: break
                }
            }
        }
        return segments
    }
}