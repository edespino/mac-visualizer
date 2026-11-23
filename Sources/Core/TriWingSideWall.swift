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
import simd

// Layout of the Tri-wing's side wall (pure data, no RealityKit types): the edge chamfers, a recessed waist band round the
// whole outline, fine vertical grip flutes in the band round each wing tip, and six edge-light windows (one per flank).
//
// The wall is built from `columns()`: the body outline sampled finely and evenly (the three tip arcs at an angular step
// that lines up with the flutes, the flanks at a fixed arc-length step), counter-clockwise, with outward normals. Every
// face builds the half of the wall above the mid plane (z from 0 up to the face); the back face is the same half turned
// half a turn about y, so the two halves meet at z = 0 in the middle of the band.
//
// Heights are in R, measured up from the mid plane. A cross-section of the half wall, from the top:
//   chamfer      from (inset = bodyChamfer, z = halfThickness) down to (0, wallTopZ), 45 degrees
//   plain wall   (0, wallTopZ) down to (0, bandOpenHalfHeight)
//   shoulder     (0, bandOpenHalfHeight) in and down to (recess, bandHalfHeight), 45 degrees, polished
//   band floor   (recess, bandHalfHeight) down to the mid plane (flutes and windows cut into it)

public enum TriWingWall {

    // MARK: Heights

    /// Edge chamfer where the wall meets each face (equal horizontal and vertical extent).
    public static var chamfer: Float { TriWing.bodyChamfer }
    /// Height where the chamfer meets the plain wall.
    public static var wallTopZ: Float { TriWing.halfThickness - TriWing.bodyChamfer }
    /// How far the band floor sits inside the plain wall.
    public static let recess: Float = 0.010
    /// Half height of the band floor, and the height of each polished 45 degree shoulder.
    public static let bandHalfHeight: Float = 0.049
    public static let shoulderHeight: Float = 0.010
    /// Half height of the band's opening in the plain wall (floor plus shoulders).
    public static var bandOpenHalfHeight: Float { bandHalfHeight + shoulderHeight }
    /// Floor height as a share of the straight wall (between the two chamfers).
    public static var bandFraction: Float { 2 * bandHalfHeight / (2 * wallTopZ) }

    // MARK: Columns

    public struct Column {
        public var p: P2
        /// Outward unit normal in the plane.
        public var n: P2
        /// Arc length from the first column, counter-clockwise.
        public var s: Float
        /// The wing whose tip arc this column lies on, or -1 on a flank.
        public var tipWing: Int
        /// Angle from that wing's axis (radians, counter-clockwise positive); 0 on flanks.
        public var tipAngle: Float
    }

    /// Spacing of the flank columns (R). The tip columns follow the flutes (see `tipColumnsPerFlute`).
    public static let columnSpacing: Float = 0.004
    /// Radius of a wing's tip arc and half its angular span (radians), from the outline's definition.
    public static var tipRadius: Float { 34 * TriWing.unit }
    public static var tipHalfSpan: Float { atan2(30 as Float, 16 as Float) }

    public static var perimeter: Float { cache.perimeter }
    public static func columns() -> [Column] { cache.columns }

    private struct Cache {
        var columns: [Column]
        var perimeter: Float
    }
    private static let cache: Cache = buildCache()

    private static func buildCache() -> Cache {
        // Wing 0's block: the tip arc (from its right end over the top to its left end), then the flank to the next tip.
        let centre: P2 = TriWing.tipCentre
        let radius: Float = tipRadius
        let span: Float = tipHalfSpan
        let zone: Float = fluteHalfAngle
        let step: Float = fluteAnglePitch / Float(tipColumnsPerFlute)
        var angles: [Float] = []
        // Right of the zone (outside it), the zone itself, then left of it.
        let outer: Int = max(Int(((span - zone) / step).rounded(.up)), 1)
        var k: Int = 0
        while k < outer {
            angles.append(-span + (span - zone) * Float(k) / Float(outer))
            k += 1
        }
        let inner: Int = fluteCount * tipColumnsPerFlute
        k = 0
        while k <= inner {
            angles.append(-zone + 2 * zone * Float(k) / Float(inner))
            k += 1
        }
        k = 1
        while k <= outer {
            angles.append(zone + (span - zone) * Float(k) / Float(outer))
            k += 1
        }
        var block: [(p: P2, wing: Int, angle: Float)] = []
        for a in angles {
            let th: Float = Float.pi / 2 + a
            block.append((P2(centre.x + radius * cos(th), centre.y + radius * sin(th)), 0, a))
        }
        // Flank: the outline's scooped side from wing 0's left end to the next tip's right end (counter-clockwise order).
        let p0: P2 = TriWing.point(-30, -128)
        let c: P2 = TriWing.point(-60.6, -35)
        let p2: P2 = TriWing.point(-125.85, 38.02)
        let fine: Int = 4000
        var poly: [P2] = []
        var cum: [Float] = [0]
        var i: Int = 0
        while i <= fine {
            let t: Float = Float(i) / Float(fine)
            let u: Float = 1 - t
            let q = P2(u * u * p0.x + 2 * u * t * c.x + t * t * p2.x, u * u * p0.y + 2 * u * t * c.y + t * t * p2.y)
            if let last = poly.last { cum.append(cum[cum.count - 1] + simd_length(q - last)) }
            poly.append(q)
            i += 1
        }
        let length: Float = cum[cum.count - 1]
        let count: Int = Int((length / columnSpacing).rounded())
        var j: Int = 1
        var seg: Int = 0
        while j < count {
            let target: Float = length * Float(j) / Float(count)
            while seg + 1 < cum.count - 1 && cum[seg + 1] < target { seg += 1 }
            let span2: Float = max(cum[seg + 1] - cum[seg], 1e-9)
            let f: Float = (target - cum[seg]) / span2
            block.append((poly[seg] + (poly[seg + 1] - poly[seg]) * f, -1, 0))
            j += 1
        }
        var pts: [P2] = []
        var wings: [Int] = []
        var tipAngles: [Float] = []
        for w in 0..<TriWing.wingCount {
            for b in block {
                pts.append(TriWing.inWing(b.p, w))
                wings.append(b.wing >= 0 ? w : -1)
                tipAngles.append(b.angle)
            }
        }
        let normals: [P2] = polygonOutwardNormals(pts)
        var cols: [Column] = []
        cols.reserveCapacity(pts.count)
        var s: Float = 0
        var n: Int = 0
        while n < pts.count {
            if n > 0 { s += simd_length(pts[n] - pts[n - 1]) }
            cols.append(Column(p: pts[n], n: normals[n], s: s, tipWing: wings[n], tipAngle: tipAngles[n]))
            n += 1
        }
        let total: Float = s + simd_length(pts[0] - pts[pts.count - 1])
        return Cache(columns: cols, perimeter: total)
    }

    /// Position and outward normal at arc length `s` (wrapped into one lap), interpolated between columns.
    public static func sample(at sIn: Float) -> (p: P2, n: P2) {
        let cols: [Column] = cache.columns
        let total: Float = cache.perimeter
        var s: Float = sIn.truncatingRemainder(dividingBy: total)
        if s < 0 { s += total }
        var lo: Int = 0
        var hi: Int = cols.count - 1
        while lo < hi {
            let mid: Int = (lo + hi + 1) / 2
            if cols[mid].s <= s { lo = mid } else { hi = mid - 1 }
        }
        let a: Column = cols[lo]
        let b: Column = cols[(lo + 1) % cols.count]
        let bs: Float = lo + 1 < cols.count ? b.s : total
        let f: Float = (s - a.s) / max(bs - a.s, 1e-9)
        let p: P2 = a.p + (b.p - a.p) * f
        var nn: P2 = a.n + (b.n - a.n) * f
        let l: Float = max(simd_length(nn), 1e-9)
        nn = nn / l
        return (p, nn)
    }

    // MARK: Flutes (grip grooves round each wing tip, in the band floor)

    /// Half angle of the fluted zone about each tip's axis, groove pitch along the outline (target), depth, and the stretch
    /// over which the grooves fade to the plain floor at each end of the zone, in grooves.
    public static let fluteHalfAngle: Float = 50 * Float.pi / 180
    public static let flutePitchTarget: Float = 0.020
    public static let fluteGrooveDepth: Float = 0.0045
    public static let fluteFadePitches: Float = 2.5
    /// Heights: full-depth grooves up to this half height, then a run-out to nothing over `fluteRunOut` (clean, tapered ends).
    public static let fluteHalfHeight: Float = 0.030
    public static let fluteRunOut: Float = 0.010
    public static let tipColumnsPerFlute: Int = 6
    public static var fluteCount: Int { Int((2 * fluteHalfAngle * tipRadius / flutePitchTarget).rounded()) }
    public static var fluteAnglePitch: Float { 2 * fluteHalfAngle / Float(fluteCount) }

    private static func smooth01(_ t: Float) -> Float {
        let x: Float = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }

    /// How far the band floor is cut in (inward, R) at angle `tipAngle` from a tip's axis and height `z`. Smooth round
    /// grooves, zero at the ends of the zone (ridges) and beyond the run-out.
    public static func fluteDepth(tipAngle phi: Float, z: Float) -> Float {
        let a: Float = abs(phi)
        if a >= fluteHalfAngle { return 0 }
        let az: Float = abs(z)
        if az >= fluteHalfHeight + fluteRunOut { return 0 }
        let pa: Float = fluteAnglePitch
        let groove: Float = 0.5 - 0.5 * cos(2 * Float.pi * (phi + fluteHalfAngle) / pa)
        let env: Float = smooth01((fluteHalfAngle - a) / (fluteFadePitches * pa))
        let mask: Float = az <= fluteHalfHeight ? 1 : 1 - smooth01((az - fluteHalfHeight) / fluteRunOut)
        return fluteGrooveDepth * groove * env * mask
    }

    // MARK: Windows (slim edge-light lenses in the band, one per flank)

    public static let windowHalfLength: Float = 0.10
    public static let windowHalfHeight: Float = 0.021
    /// Width of the polished frame round the lens, and how far the lens sits behind the band floor.
    public static let windowFrameWidth: Float = 0.004
    public static let windowPocketDepth: Float = 0.004

    public struct Window {
        /// The wing whose tube this window belongs to and the tube's side (-1 left, +1 right, as `TriWing.flankTubePath`).
        public let wing: Int
        public let side: Int
        /// Index of the centre column and the number of columns either side that the window spans.
        public let centre: Int
        public let halfColumns: Int
        /// Half length along the outline (exactly `halfColumns` column steps) and half height (z) of the opening.
        public let halfLength: Float
        public let halfHeight: Float
    }

    /// The six windows: one beside each flank tube, centred on the outline point nearest the tube's middle.
    public static func windows() -> [Window] {
        let cols: [Column] = cache.columns
        var out: [Window] = []
        for w in 0..<TriWing.wingCount {
            for side in [-1, 1] {
                var path: [P2] = TriWing.flankTubePath(side: Float(side))
                for i in 0..<path.count { path[i] = TriWing.inWing(path[i], w) }
                let mid: P2 = (path[path.count / 2 - 1] + path[path.count / 2]) * 0.5
                var best: Int = 0
                var bestD: Float = 1e9
                for (i, c) in cols.enumerated() where c.tipWing < 0 {
                    let d: Float = simd_length(c.p - mid)
                    if d < bestD { bestD = d; best = i }
                }
                let m: Int = Int((windowHalfLength / columnSpacing).rounded())
                let step: Float = cols[best + 1].s - cols[best].s
                out.append(Window(wing: w, side: side, centre: best, halfColumns: m, halfLength: Float(m) * step, halfHeight: windowHalfHeight))
            }
        }
        return out
    }

    /// Half height of the stadium (a slot with half-round ends) of half length `halfLength` and half height `halfHeight` at
    /// distance `offset` along its length from the centre; 0 at and beyond the ends.
    public static func stadiumHalfHeight(offset: Float, halfLength: Float, halfHeight: Float) -> Float {
        let o: Float = abs(offset)
        let straight: Float = halfLength - halfHeight
        if o <= straight { return halfHeight }
        if o >= halfLength { return 0 }
        let d: Float = o - straight
        return max(halfHeight * halfHeight - d * d, 0).squareRoot()
    }
}
