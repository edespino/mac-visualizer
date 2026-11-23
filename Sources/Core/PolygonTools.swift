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

// Pure 2D polygon helpers for the Tri-wing spinner: curve sampling, inward offset, point-in-polygon and an ear-clipping
// triangulator with hole bridging. The Tri-wing plates are flat, so triangle quality does not matter; what matters is that
// the triangulation is exact (every vertex of the outline and of every hole is used, areas add up, nothing leaks into a
// hole). No RealityKit types, safe on any thread.

public typealias P2 = SIMD2<Float>

/// Signed area (positive for counter-clockwise).
public func polygonSignedArea(_ p: [P2]) -> Float {
    var sum: Float = 0
    let n: Int = p.count
    var i: Int = 0
    while i < n {
        let a: P2 = p[i]
        let b: P2 = p[(i + 1) % n]
        let cross: Float = a.x * b.y - b.x * a.y
        sum += cross
        i += 1
    }
    return sum * 0.5
}

/// The polygon with counter-clockwise (ccw true) or clockwise orientation.
public func polygonOriented(_ p: [P2], counterClockwise: Bool) -> [P2] {
    let area: Float = polygonSignedArea(p)
    let isCCW: Bool = area >= 0
    if isCCW == counterClockwise { return p }
    return Array(p.reversed())
}

/// Even-odd point-in-polygon test.
public func polygonContains(_ p: [P2], _ q: P2) -> Bool {
    var inside: Bool = false
    let n: Int = p.count
    var j: Int = n - 1
    var i: Int = 0
    while i < n {
        let a: P2 = p[i]
        let b: P2 = p[j]
        let straddles: Bool = (a.y > q.y) != (b.y > q.y)
        if straddles {
            let t: Float = (q.y - a.y) / (b.y - a.y)
            let xAt: Float = a.x + t * (b.x - a.x)
            if q.x < xAt { inside = !inside }
        }
        j = i
        i += 1
    }
    return inside
}

/// Distance from `q` to the closest point of the closed polygon's boundary.
public func polygonBoundaryDistance(_ p: [P2], _ q: P2) -> Float {
    var best: Float = Float.greatestFiniteMagnitude
    let n: Int = p.count
    var i: Int = 0
    while i < n {
        let a: P2 = p[i]
        let b: P2 = p[(i + 1) % n]
        let ab: P2 = b - a
        let l2: Float = ab.x * ab.x + ab.y * ab.y
        var t: Float = 0
        if l2 > 0 {
            let ap: P2 = q - a
            let proj: Float = (ap.x * ab.x + ap.y * ab.y) / l2
            t = min(max(proj, 0), 1)
        }
        let c: P2 = a + ab * t
        let d: P2 = q - c
        let dist: Float = (d.x * d.x + d.y * d.y).squareRoot()
        best = min(best, dist)
        i += 1
    }
    return best
}

/// Per-vertex outward unit normals of a counter-clockwise polygon (average of the two adjacent edge normals).
public func polygonOutwardNormals(_ p: [P2]) -> [P2] {
    let n: Int = p.count
    var out: [P2] = []
    out.reserveCapacity(n)
    var i: Int = 0
    while i < n {
        let prev: P2 = p[(i + n - 1) % n]
        let cur: P2 = p[i]
        let next: P2 = p[(i + 1) % n]
        let e0: P2 = cur - prev
        let e1: P2 = next - cur
        let n0 = P2(e0.y, -e0.x)
        let n1 = P2(e1.y, -e1.x)
        let l0: Float = max((n0.x * n0.x + n0.y * n0.y).squareRoot(), 1e-12)
        let l1: Float = max((n1.x * n1.x + n1.y * n1.y).squareRoot(), 1e-12)
        let sum: P2 = n0 / l0 + n1 / l1
        let ls: Float = (sum.x * sum.x + sum.y * sum.y).squareRoot()
        if ls < 1e-9 {
            out.append(n0 / l0)
        } else {
            out.append(sum / ls)
        }
        i += 1
    }
    return out
}

/// Moves every vertex of a counter-clockwise polygon inward by `distance` along its mitred normal (the mitre is limited
/// so a sharp corner cannot spike). Negative distances grow the polygon.
public func polygonOffsetInward(_ p: [P2], by distance: Float) -> [P2] {
    let n: Int = p.count
    let normals: [P2] = polygonOutwardNormals(p)
    var out: [P2] = []
    out.reserveCapacity(n)
    var i: Int = 0
    while i < n {
        let prev: P2 = p[(i + n - 1) % n]
        let cur: P2 = p[i]
        let next: P2 = p[(i + 1) % n]
        let e0: P2 = cur - prev
        let e1: P2 = next - cur
        let l0: Float = max((e0.x * e0.x + e0.y * e0.y).squareRoot(), 1e-12)
        let l1: Float = max((e1.x * e1.x + e1.y * e1.y).squareRoot(), 1e-12)
        let d0: P2 = e0 / l0
        let d1: P2 = e1 / l1
        let cosTurn: Float = d0.x * d1.x + d0.y * d1.y
        // cos of the half turn angle between the edge normals: the mitre scale is 1 / that.
        let halfCos: Float = ((1 + cosTurn) * 0.5).squareRoot()
        let scale: Float = 1 / max(halfCos, 0.5)
        let shift: P2 = normals[i] * (-distance * scale)
        out.append(cur + shift)
        i += 1
    }
    return out
}

/// Circle polygon, counter-clockwise, starting at angle `start`.
public func circlePolygon(center: P2, radius: Float, segments: Int, start: Float = 0) -> [P2] {
    var out: [P2] = []
    out.reserveCapacity(segments)
    var i: Int = 0
    while i < segments {
        let frac: Float = Float(i) / Float(segments)
        let angle: Float = start + frac * 2 * Float.pi
        out.append(P2(center.x + radius * cos(angle), center.y + radius * sin(angle)))
        i += 1
    }
    return out
}

/// Polygon, in `points` order, rotated about the origin by `angle` radians.
public func polygonRotated(_ p: [P2], by angle: Float) -> [P2] {
    let c: Float = cos(angle)
    let s: Float = sin(angle)
    var out: [P2] = []
    out.reserveCapacity(p.count)
    for q in p {
        let x: Float = c * q.x - s * q.y
        let y: Float = s * q.x + c * q.y
        out.append(P2(x, y))
    }
    return out
}

// MARK: - Path sampling (SVG-style commands, y down in drawing space)

/// Accumulates sampled points of line, quadratic, cubic and circular-arc segments. Coordinates are the caller's.
public struct SampledPath {
    public private(set) var points: [P2] = []
    private var cursor: P2 = P2(0, 0)
    /// Target distance between sampled points.
    public var step: Float

    public init(step: Float = 1.0) { self.step = step }

    private func count(forLength length: Float) -> Int {
        let raw: Int = Int((length / max(step, 1e-6)).rounded(.up))
        return max(2, raw)
    }

    public mutating func move(to p: P2) {
        points.append(p)
        cursor = p
    }
    public mutating func line(to p: P2) {
        let d: P2 = p - cursor
        let len: Float = (d.x * d.x + d.y * d.y).squareRoot()
        let n: Int = count(forLength: len)
        var i: Int = 1
        while i <= n {
            let t: Float = Float(i) / Float(n)
            points.append(cursor + d * t)
            i += 1
        }
        cursor = p
    }
    public mutating func quad(control c: P2, to p: P2) {
        let chord: P2 = p - cursor
        let len: Float = (chord.x * chord.x + chord.y * chord.y).squareRoot()
        let n: Int = count(forLength: len * 1.05)
        let p0: P2 = cursor
        var i: Int = 1
        while i <= n {
            let t: Float = Float(i) / Float(n)
            let u: Float = 1 - t
            let a: P2 = p0 * (u * u)
            let b: P2 = c * (2 * u * t)
            let d: P2 = p * (t * t)
            points.append(a + b + d)
            i += 1
        }
        cursor = p
    }
    public mutating func cubic(control1 c1: P2, control2 c2: P2, to p: P2) {
        let chord: P2 = p - cursor
        let len: Float = (chord.x * chord.x + chord.y * chord.y).squareRoot()
        let n: Int = count(forLength: len * 1.1)
        let p0: P2 = cursor
        var i: Int = 1
        while i <= n {
            let t: Float = Float(i) / Float(n)
            let u: Float = 1 - t
            let w0: Float = u * u * u
            let w1: Float = 3 * u * u * t
            let w2: Float = 3 * u * t * t
            let w3: Float = t * t * t
            let a: P2 = p0 * w0
            let b: P2 = c1 * w1
            let d: P2 = c2 * w2
            let e: P2 = p * w3
            points.append(a + b + d + e)
            i += 1
        }
        cursor = p
    }
    /// Circular arc with the SVG flag semantics (sweep 1 = increasing angle in the caller's axes).
    public mutating func arc(radius rIn: Float, large: Bool, sweep: Bool, to p: P2) {
        let x0: Float = cursor.x
        let y0: Float = cursor.y
        let hx: Float = (x0 - p.x) * 0.5
        let hy: Float = (y0 - p.y) * 0.5
        let d2: Float = hx * hx + hy * hy
        var r: Float = rIn
        if d2 > r * r { r = d2.squareRoot() }
        let r2: Float = r * r
        let sign: Float = (large == sweep) ? -1 : 1
        let ratio: Float = max(0, (r2 - d2) / max(d2, 1e-12))
        let coef: Float = sign * ratio.squareRoot()
        let cxp: Float = coef * hy
        let cyp: Float = -coef * hx
        let cx: Float = cxp + (x0 + p.x) * 0.5
        let cy: Float = cyp + (y0 + p.y) * 0.5
        let t1: Float = atan2((hy - cyp) / r, (hx - cxp) / r)
        let t2: Float = atan2((-hy - cyp) / r, (-hx - cxp) / r)
        var delta: Float = t2 - t1
        if !sweep && delta > 0 { delta -= 2 * Float.pi }
        if sweep && delta < 0 { delta += 2 * Float.pi }
        let arcLength: Float = abs(delta) * r
        let n: Int = count(forLength: arcLength)
        var i: Int = 1
        while i <= n {
            let t: Float = Float(i) / Float(n)
            let a: Float = t1 + delta * t
            points.append(P2(cx + r * cos(a), cy + r * sin(a)))
            i += 1
        }
        points[points.count - 1] = p
        cursor = p
    }
    /// The sampled points with the closing duplicate (last point equal to the first) removed.
    public var closedPoints: [P2] {
        var out: [P2] = points
        if let first = out.first, let last = out.last, out.count > 1 {
            let d: P2 = last - first
            if d.x * d.x + d.y * d.y < 1e-10 { out.removeLast() }
        }
        return out
    }
}

// MARK: - Triangulation

/// Result of triangulating a polygon with holes: `vertices` are the outer ring followed by each hole's ring (in input
/// order, with the orientations normalised: outer counter-clockwise, holes clockwise); `indices` are counter-clockwise triples.
public struct PolygonTriangulation {
    public var vertices: [P2] = []
    public var indices: [UInt32] = []
    public init() {}
}

public enum PolygonTriangulator {

    /// Ear-clipping triangulation with Eberly-style hole bridging. Every input vertex is used.
    public static func triangulate(outer outerIn: [P2], holes holesIn: [[P2]]) -> PolygonTriangulation {
        var result = PolygonTriangulation()
        if outerIn.count < 3 { return result }
        let outer: [P2] = polygonOriented(outerIn, counterClockwise: true)
        var holes: [[P2]] = []
        for h in holesIn where h.count >= 3 { holes.append(polygonOriented(h, counterClockwise: false)) }
        // Vertex store: outer first, then every hole.
        var verts: [P2] = outer
        var ring: [Int] = Array(0..<outer.count)
        var holeRings: [[Int]] = []
        for h in holes {
            let base: Int = verts.count
            verts.append(contentsOf: h)
            holeRings.append(Array(base..<(base + h.count)))
        }
        // Holes sorted by their rightmost vertex, furthest right first.
        var order: [Int] = Array(0..<holeRings.count)
        func maxX(_ k: Int) -> Float {
            var m: Float = -Float.greatestFiniteMagnitude
            for idx in holeRings[k] { m = max(m, verts[idx].x) }
            return m
        }
        order.sort { (a: Int, b: Int) -> Bool in maxX(a) > maxX(b) }
        for k in order {
            bridge(hole: holeRings[k], into: &ring, verts: verts)
        }
        result.vertices = verts
        result.indices = earClip(ring: ring, verts: verts)
        return result
    }

    /// Splices `hole` (clockwise) into the outer `ring` through a bridge from the hole's rightmost vertex.
    private static func bridge(hole: [Int], into ring: inout [Int], verts: [P2]) {
        // Rightmost hole vertex M.
        var mPos: Int = 0
        var mx: Float = -Float.greatestFiniteMagnitude
        for (i, idx) in hole.enumerated() where verts[idx].x > mx { mx = verts[idx].x; mPos = i }
        let m: P2 = verts[hole[mPos]]
        // Nearest ring edge hit by the ray from M toward +x.
        var bestX: Float = Float.greatestFiniteMagnitude
        var bestEdge: Int = -1
        let n: Int = ring.count
        var i: Int = 0
        while i < n {
            let a: P2 = verts[ring[i]]
            let b: P2 = verts[ring[(i + 1) % n]]
            let straddles: Bool = (a.y <= m.y && b.y >= m.y) || (b.y <= m.y && a.y >= m.y)
            if straddles && a.y != b.y {
                let t: Float = (m.y - a.y) / (b.y - a.y)
                let xAt: Float = a.x + t * (b.x - a.x)
                if xAt >= m.x - 1e-7 && xAt < bestX {
                    bestX = xAt
                    bestEdge = i
                }
            }
            i += 1
        }
        if bestEdge < 0 { bestEdge = 0 }
        let ea: Int = bestEdge
        let eb: Int = (bestEdge + 1) % n
        let pa: P2 = verts[ring[ea]]
        let pb: P2 = verts[ring[eb]]
        var candidate: Int = pa.x > pb.x ? ea : eb
        let hit = P2(bestX, m.y)
        // Reflex ring vertices inside the triangle (M, hit, candidate) can hide the candidate: take the one with the smallest angle.
        let pc: P2 = verts[ring[candidate]]
        var bestAngle: Float = Float.greatestFiniteMagnitude
        var j: Int = 0
        while j < n {
            if j != candidate {
                let q: P2 = verts[ring[j]]
                if pointInTriangle(q, m, hit, pc) && isReflex(ring: ring, at: j, verts: verts) {
                    let d: P2 = q - m
                    let dist: Float = (d.x * d.x + d.y * d.y).squareRoot()
                    let ang: Float = abs(atan2(d.y, d.x))
                    let key: Float = ang + dist * 1e-6
                    if key < bestAngle { bestAngle = key; candidate = j }
                }
            }
            j += 1
        }
        // Splice: ring[0...candidate], hole from M around back to M, ring[candidate...]
        var spliced: [Int] = []
        spliced.append(contentsOf: ring[0...candidate])
        var k: Int = 0
        while k < hole.count {
            spliced.append(hole[(mPos + k) % hole.count])
            k += 1
        }
        spliced.append(hole[mPos])
        spliced.append(ring[candidate])
        if candidate + 1 < ring.count { spliced.append(contentsOf: ring[(candidate + 1)...]) }
        ring = spliced
    }

    private static func cross(_ o: P2, _ a: P2, _ b: P2) -> Float {
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }

    private static func pointInTriangle(_ p: P2, _ a: P2, _ b: P2, _ c: P2) -> Bool {
        let d1: Float = cross(p, a, b)
        let d2: Float = cross(p, b, c)
        let d3: Float = cross(p, c, a)
        let hasNeg: Bool = d1 < 0 || d2 < 0 || d3 < 0
        let hasPos: Bool = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNeg && hasPos)
    }

    private static func isReflex(ring: [Int], at i: Int, verts: [P2]) -> Bool {
        let n: Int = ring.count
        let prev: P2 = verts[ring[(i + n - 1) % n]]
        let cur: P2 = verts[ring[i]]
        let next: P2 = verts[ring[(i + 1) % n]]
        return cross(prev, cur, next) < 0
    }

    /// Ear clipping over an index ring (counter-clockwise, may repeat vertices after bridging).
    private static func earClip(ring ringIn: [Int], verts: [P2]) -> [UInt32] {
        var ring: [Int] = ringIn
        var out: [UInt32] = []
        out.reserveCapacity(max(0, (ring.count - 2) * 3))
        var guardCount: Int = ring.count * ring.count + 16
        var start: Int = 0
        while ring.count > 3 && guardCount > 0 {
            guardCount -= 1
            let n: Int = ring.count
            var clipped: Bool = false
            var tried: Int = 0
            while tried < n {
                let i: Int = (start + tried) % n
                let ia: Int = ring[(i + n - 1) % n]
                let ib: Int = ring[i]
                let ic: Int = ring[(i + 1) % n]
                let a: P2 = verts[ia]
                let b: P2 = verts[ib]
                let c: P2 = verts[ic]
                var ear: Bool = cross(a, b, c) > 1e-12
                if ear {
                    var j: Int = 0
                    while j < n {
                        let iq: Int = ring[j]
                        if iq != ia && iq != ib && iq != ic {
                            let q: P2 = verts[iq]
                            let coincident: Bool = (q == a) || (q == b) || (q == c)
                            if !coincident && pointInTriangleInclusive(q, a, b, c) { ear = false; break }
                        }
                        j += 1
                    }
                }
                if ear {
                    out.append(UInt32(ia)); out.append(UInt32(ib)); out.append(UInt32(ic))
                    ring.remove(at: i)
                    start = i % max(ring.count, 1)
                    clipped = true
                    break
                }
                tried += 1
            }
            if !clipped {
                // No ear found (collinear run or a numerically awkward bridge): drop the flattest vertex.
                var flat: Int = 0
                var flatArea: Float = Float.greatestFiniteMagnitude
                var i: Int = 0
                while i < n {
                    let a: P2 = verts[ring[(i + n - 1) % n]]
                    let b: P2 = verts[ring[i]]
                    let c: P2 = verts[ring[(i + 1) % n]]
                    let ar: Float = abs(cross(a, b, c))
                    if ar < flatArea { flatArea = ar; flat = i }
                    i += 1
                }
                let ia: Int = ring[(flat + n - 1) % n]
                let ib: Int = ring[flat]
                let ic: Int = ring[(flat + 1) % n]
                if cross(verts[ia], verts[ib], verts[ic]) > 0 {
                    out.append(UInt32(ia)); out.append(UInt32(ib)); out.append(UInt32(ic))
                }
                ring.remove(at: flat)
                start = flat % max(ring.count, 1)
            }
        }
        if ring.count == 3 {
            let a: P2 = verts[ring[0]]
            let b: P2 = verts[ring[1]]
            let c: P2 = verts[ring[2]]
            if cross(a, b, c) > 1e-12 {
                out.append(UInt32(ring[0])); out.append(UInt32(ring[1])); out.append(UInt32(ring[2]))
            }
        }
        return out
    }

    private static func pointInTriangleInclusive(_ p: P2, _ a: P2, _ b: P2, _ c: P2) -> Bool {
        // Inclusive of the boundary: a vertex lying exactly on an edge of the candidate ear (a reflex corner touching the
        // chord) must block the ear, or the clip would cut across the polygon.
        let eps: Float = 1e-9
        let d1: Float = cross(p, a, b)
        let d2: Float = cross(p, b, c)
        let d3: Float = cross(p, c, a)
        return d1 >= -eps && d2 >= -eps && d3 >= -eps
    }
}
