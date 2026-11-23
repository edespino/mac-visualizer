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
// CPU-only geometry of the Tri-wing spinner. No RealityKit, safe off the main thread. The layout lives in
// `TriWing` (Core); this file turns it into meshes: plates and chamfers from polygons (`PolygonTriangulator`), round
// parts from lathes, and the engraved ring and logo patch from `RectCutMesher`.
//
// Every face is built once in "front layout" (z up, wing 0 toward +y) and the back face is the same mesh turned half a
// turn about y (x -> -x, z -> -z), so text and marks read correctly on whichever face is toward the viewer.
import Foundation
import simd
import MacVisualizerCore

enum TWKind: Hashable {
    case bodyTop, bodyChamfer, bodyWall, wellWall, collar
    /// The waist band round the side wall: its polished shoulder, its turned floor, the grip flutes round the tips, the polished
    /// frame of an edge-light window and its lens (one kind per wing so each carries its light colour).
    case waistBevel, waistFloor, waistFlute, windowFrame, windowLens(Int)
    case padTop, padChamfer, padWall
    case bossTop, bossChamfer, bossWall
    case countersink, countersinkFloor
    case gold, goldWall, goldDark, spring
    case jewelBlue, screwBlue, screwSlot
    case ringTop, ringChamfer, ringWall, engraveFloor, engraveWall, letterFloor, letterWall, notchChamfer, notchWall, notchFloor, notchFloorShade, flute
    case raceSteel, innerRace, cage, ballSteel
    case tubeCore(Int), tubeShell(Int)
    /// A wing's slot walls and floor (one kind per wing so each carries its own light colour; the lit material gives the wall
    /// a glow that fades up from the tube, the unlit one is plain dark metal), the bright line on the slot lip, and the soft
    /// tint on the side of the pad that faces the slot.
    case slotWall(Int), slotFloor(Int), slotLip(Int), padTint(Int)
    case hubTurned, hubChamfer, hubWall, crystal, crystalRim, glint(Int)
    /// Spin-blur parts: the face overlay inside the full-coverage radius, the translucent wing-zone face beyond it, the swept
    /// light rings, the swept side band of light (0 upper half, 1 lower half) and the thin shells of the wing zone.
    case smearBody(Int), smearZone(Int), smearGlow, sideBand(Int)
    /// The swept light ring of one wing, a neutral opacity mask tinted by the wing's palette colour (used instead of `smearGlow` when the lights follow the palette).
    case smearGlowWing(Int)
    /// The swept core's wall (turned, anisotropic: a vertical streak highlight that stays with the light).
    case coreWall
    case sweptShell(Int)
}

/// Which entity group a part belongs to: `spin` turns with the body, `tube` is the edge-light glass tubes (always
/// shown; lit or unlit by the setting), `glow` is the light they throw into their slots (only while lit), `hub` is static (the plain hubs, the inner
/// races and the crystal), `smear` is the spin-blur overlay, `sweptCore` the opaque solid of revolution that replaces the body
/// at speed, `zone` the translucent wing zone (face overlay and thin shells) and `sweptGlow` the swept light rings (outside the body's own outline between the wings, so they come in late) and `sweptBand` the side band of light on the core's waist.
enum TWGroup { case spin, tube, glow, hub, smear, sweptCore, zone, sweptGlow, sweptBand }

func twGroup(_ k: TWKind) -> TWGroup {
    switch k {
    case .tubeCore, .tubeShell, .windowLens: return .tube
    case .slotLip, .padTint: return .glow
    case .innerRace, .hubTurned, .hubChamfer, .hubWall, .crystal, .crystalRim, .glint: return .hub
    case .smearBody: return .smear
    case .smearZone, .sweptShell: return .zone
    case .smearGlow, .smearGlowWing: return .sweptGlow
    case .sideBand: return .sweptBand
    default: return .spin
    }
}

struct TWPart { var mb: MB; var kind: TWKind; var name: String; var group: TWGroup }

struct TWGeometryCPU {
    var parts: [TWPart] = []
    var smear: TriWingSmear? = nil
    var shellOpacities: [Float] = []
    var images: TWImages? = nil
    var smearImages: TWSmearImages? = nil
    var timings: [(String, Double)] = []
    var triangles: Int { var n: Int = 0; for p in parts { n += p.mb.triCount }; return n }
}

// ---- small transform helpers ----
func twRotZ(_ a: Float) -> (m: simd_float4x4, n: simd_float3x3) {
    let c: Float = cos(a)
    let s: Float = sin(a)
    let m = simd_float4x4(columns: (SIMD4<Float>(c, s, 0, 0), SIMD4<Float>(-s, c, 0, 0), SIMD4<Float>(0, 0, 1, 0), SIMD4<Float>(0, 0, 0, 1)))
    let n = simd_float3x3(columns: (SIMD3<Float>(c, s, 0), SIMD3<Float>(-s, c, 0), SIMD3<Float>(0, 0, 1)))
    return (m, n)
}
func twTranslate(_ t: V3) -> simd_float4x4 {
    simd_float4x4(columns: (SIMD4<Float>(1, 0, 0, 0), SIMD4<Float>(0, 1, 0, 0), SIMD4<Float>(0, 0, 1, 0), SIMD4<Float>(t.x, t.y, t.z, 1)))
}
/// Half a turn about y: front layout to back layout.
func twFlipY() -> (m: simd_float4x4, n: simd_float3x3) {
    let m = simd_float4x4(columns: (SIMD4<Float>(-1, 0, 0, 0), SIMD4<Float>(0, 1, 0, 0), SIMD4<Float>(0, 0, -1, 0), SIMD4<Float>(0, 0, 0, 1)))
    let n = simd_float3x3(columns: (SIMD3<Float>(-1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 0, -1)))
    return (m, n)
}

/// Meshes collected per material kind.
struct TWAccumulator {
    var meshes: [TWKind: MB] = [:]
    var order: [TWKind] = []
    mutating func add(_ mb: MB, _ kind: TWKind, transform m: simd_float4x4 = matrix_identity_float4x4,
                      normalMatrix nm: simd_float3x3 = matrix_identity_float3x3) {
        if mb.idx.isEmpty { return }
        if meshes[kind] == nil { meshes[kind] = MB(); order.append(kind) }
        meshes[kind]!.append(mb, transform: m, normalMatrix: nm)
    }
    mutating func merge(_ other: TWAccumulator, transform m: simd_float4x4, normalMatrix nm: simd_float3x3) {
        for k in other.order { if let mb = other.meshes[k] { add(mb, k, transform: m, normalMatrix: nm) } }
    }
}

// ---- polygon plate emitters (front layout) ----
let twUp = V3(0, 0, 1)

/// Planar uv over the [-1, 1] square (the same mapping as the disc's brushed face texture).
@inline(__always) func twPlanarUV(_ p: P2) -> V2 { V2(p.x * 0.5 + 0.5, p.y * 0.5 + 0.5) }

/// A flat triangulated polygon at height z facing up.
func twFlat(_ t: PolygonTriangulation, z: Float, textured: Bool) -> MB {
    var m = MB()
    var map: [UInt32] = []
    map.reserveCapacity(t.vertices.count)
    for p in t.vertices {
        let uv: V2 = textured ? twPlanarUV(p) : V2(0, 0)
        map.append(m.v(V3(p.x, p.y, z), twUp, uv, tan: V3(1, 0, 0)))
    }
    var k: Int = 0
    while k + 2 < t.indices.count {
        m.tri(map[Int(t.indices[k])], map[Int(t.indices[k + 1])], map[Int(t.indices[k + 2])])
        k += 3
    }
    return m
}

/// Vertical wall around a counter-clockwise loop between two heights; `inward` makes the normals face the loop's inside.
func twWall(_ loop: [P2], zTop: Float, zBottom: Float, inward: Bool) -> MB {
    var m = MB()
    let normals: [P2] = polygonOutwardNormals(loop)
    let sign: Float = inward ? -1 : 1
    var top: [UInt32] = []
    var bot: [UInt32] = []
    for (i, p) in loop.enumerated() {
        let n = V3(normals[i].x * sign, normals[i].y * sign, 0)
        let tangent = V3(-n.y, n.x, 0)
        top.append(m.v(V3(p.x, p.y, zTop), n, V2(0, 0), tan: tangent))
        bot.append(m.v(V3(p.x, p.y, zBottom), n, V2(0, 1), tan: tangent))
    }
    let count: Int = loop.count
    var i: Int = 0
    while i < count {
        let j: Int = (i + 1) % count
        m.quad(top[i], top[j], bot[j], bot[i])
        i += 1
    }
    return m
}

/// Bevel between an outer loop at `zLow` and the index-aligned inner loop at `zHigh`, facing outward and up.
func twBevel(outer: [P2], inner: [P2], zLow: Float, zHigh: Float) -> MB {
    var m = MB()
    let normals: [P2] = polygonOutwardNormals(outer)
    var lo: [UInt32] = []
    var hi: [UInt32] = []
    for i in 0..<outer.count {
        let d: P2 = outer[i] - inner[i]
        let dr: Float = max((d.x * d.x + d.y * d.y).squareRoot(), 1e-6)
        let dz: Float = zHigh - zLow
        let raw = V3(normals[i].x * dz, normals[i].y * dz, dr)
        let n: V3 = simd_normalize(raw)
        let tangent = V3(-normals[i].y, normals[i].x, 0)
        lo.append(m.v(V3(outer[i].x, outer[i].y, zLow), n, V2(0, 0), tan: tangent))
        hi.append(m.v(V3(inner[i].x, inner[i].y, zHigh), n, V2(0, 1), tan: tangent))
    }
    let count: Int = outer.count
    var i: Int = 0
    while i < count {
        let j: Int = (i + 1) % count
        m.quad(lo[i], lo[j], hi[j], hi[i])
        i += 1
    }
    return m
}

/// Lathe of a polyline in (r, z) whose surface lies to the LEFT of the travel direction. Crease points are written twice.
func twLathe(_ pts: [(Float, Float)], seg: Int) -> MB {
    let prof: [ProfilePt] = flank(pts, sign: -1)
    return lathe(prof, seg: seg)
}

/// Partial lathe around +Z from angle `from` to `to` (radians, counter-clockwise from +x), profile as for `twLathe`.
func twLatheArc(_ pts: [(Float, Float)], from: Float, to: Float, seg: Int) -> MB {
    let prof: [ProfilePt] = flank(pts, sign: -1)
    var m = MB()
    var rows: [[UInt32]] = []
    for pp in prof {
        var row: [UInt32] = []
        var j: Int = 0
        while j <= seg {
            let f: Float = Float(j) / Float(seg)
            let span: Float = to - from
            let th: Float = from + span * f
            let c: Float = cos(th)
            let s: Float = sin(th)
            let nor: V3 = simd_normalize(V3(pp.nr * c, pp.nr * s, pp.nz))
            row.append(m.v(V3(pp.r * c, pp.r * s, pp.z), nor, V2(f, pp.v), tan: V3(-s, c, 0)))
            j += 1
        }
        rows.append(row)
    }
    var i: Int = 0
    while i < prof.count - 1 {
        var j: Int = 0
        while j < seg { m.quad(rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]); j += 1 }
        i += 1
    }
    return m
}

/// Sphere of radius r centred on the origin.
func twSphere(radius: Float, seg: Int, rows: Int) -> MB {
    var prof: [ProfilePt] = []
    var i: Int = 0
    while i <= rows {
        let t: Float = Float(i) / Float(rows)
        let phi: Float = t * Float.pi
        let s: Float = sin(phi)
        let c: Float = cos(phi)
        prof.append(ProfilePt(r: radius * s, z: -radius * c, nr: s, nz: -c, v: t))
        i += 1
    }
    return lathe(prof, seg: seg)
}

/// One vertex of a glow overlay: position and the light intensity (0...1) it carries. The intensity is written into the
/// texture coordinate (u), where a linear ramp texture turns it into opacity, so one small texture serves every overlay.
struct TWGlowPt { var p: V3; var intensity: Float }

/// A band round a closed loop, between consecutive rings of glow vertices (all rings the same length, index aligned).
/// A quad whose four corners are all nearly dark is dropped.
func twGlowBand(_ rings: [[TWGlowPt]]) -> MB {
    var m = MB()
    var ids: [[UInt32]] = []
    for ring in rings {
        var row: [UInt32] = []
        for g in ring {
            row.append(m.v(g.p, twUp, V2(min(max(g.intensity, 0), 1), 0.5), tan: V3(1, 0, 0)))
        }
        ids.append(row)
    }
    var i: Int = 0
    while i + 1 < rings.count {
        let count: Int = rings[i].count
        var j: Int = 0
        while j < count {
            let k: Int = (j + 1) % count
            let a: Float = rings[i][j].intensity
            let b: Float = rings[i][k].intensity
            let c: Float = rings[i + 1][k].intensity
            let d: Float = rings[i + 1][j].intensity
            let peak: Float = max(max(a, b), max(c, d))
            if peak > 0.01 { m.quad(ids[i][j], ids[i][k], ids[i + 1][k], ids[i + 1][j]) }
            j += 1
        }
        i += 1
    }
    return m
}

/// Light on the inside of a slot: a wall just inside the real one, from the floor (`zBottom`) to the lip (`zTop`), whose
/// intensity at fractional height h (0 floor ... 1 lip) is `intensity(h)`.
func twGlowWall(_ loop: [P2], zTop: Float, zBottom: Float, rows: Int, intensity: (Float) -> Float) -> MB {
    var rings: [[TWGlowPt]] = []
    var r: Int = 0
    while r <= rows {
        let h: Float = Float(r) / Float(rows)
        let z: Float = zBottom + (zTop - zBottom) * h
        let level: Float = intensity(h)
        var ring: [TWGlowPt] = []
        for q in loop { ring.append(TWGlowPt(p: V3(q.x, q.y, z), intensity: level)) }
        rings.append(ring)
        r += 1
    }
    return twGlowBand(rings)
}

/// Distance from `q` to the nearest point of any of the polylines in `paths`.
func twDistanceToPaths(_ q: P2, _ paths: [[P2]]) -> Float {
    var best: Float = 1e9
    for path in paths {
        var i: Int = 0
        while i + 1 < path.count {
            let a: P2 = path[i]
            let b: P2 = path[i + 1]
            let abx: Float = b.x - a.x
            let aby: Float = b.y - a.y
            let len2: Float = max(abx * abx + aby * aby, 1e-12)
            let t: Float = min(max(((q.x - a.x) * abx + (q.y - a.y) * aby) / len2, 0), 1)
            let dx: Float = a.x + abx * t - q.x
            let dy: Float = a.y + aby * t - q.y
            let d: Float = (dx * dx + dy * dy).squareRoot()
            if d < best { best = d }
            i += 1
        }
    }
    return best
}

/// A flat ribbon (rectangular section: `halfWidth` across in the plane, `halfThick` high) swept along a 3D centre line.
func twRibbon(_ path: [V3], halfWidth: Float, halfThick: Float) -> MB {
    var m = MB()
    let n: Int = path.count
    var topIdx: [(UInt32, UInt32)] = []
    var leftIdx: [(UInt32, UInt32)] = []
    var rightIdx: [(UInt32, UInt32)] = []
    var firstDir = V3(1, 0, 0)
    var lastDir = V3(1, 0, 0)
    var firstNormal2 = V3(0, 1, 0)
    var lastNormal2 = V3(0, 1, 0)
    var i: Int = 0
    while i < n {
        let a: V3 = path[max(i - 1, 0)]
        let b: V3 = path[min(i + 1, n - 1)]
        let dx: Float = b.x - a.x
        let dy: Float = b.y - a.y
        let dz: Float = b.z - a.z
        let ds: Float = max((dx * dx + dy * dy).squareRoot(), 1e-9)
        let tx: Float = dx / ds
        let ty: Float = dy / ds
        let slope: Float = dz / ds
        let nx: Float = -ty
        let ny: Float = tx
        let p: V3 = path[i]
        let up: V3 = simd_normalize(V3(-tx * slope, -ty * slope, 1))
        let tan3 = V3(tx, ty, 0)
        let tl = V3(p.x + nx * halfWidth, p.y + ny * halfWidth, p.z + halfThick)
        let tr = V3(p.x - nx * halfWidth, p.y - ny * halfWidth, p.z + halfThick)
        let bl = V3(tl.x, tl.y, p.z - halfThick)
        let br = V3(tr.x, tr.y, p.z - halfThick)
        topIdx.append((m.v(tl, up, V2(0, 0), tan: tan3), m.v(tr, up, V2(1, 0), tan: tan3)))
        let nl = V3(nx, ny, 0)
        let nr = V3(-nx, -ny, 0)
        leftIdx.append((m.v(tl, nl, V2(0, 0), tan: tan3), m.v(bl, nl, V2(0, 1), tan: tan3)))
        rightIdx.append((m.v(tr, nr, V2(0, 0), tan: tan3), m.v(br, nr, V2(0, 1), tan: tan3)))
        if i == 0 { firstDir = V3(-tx, -ty, 0); firstNormal2 = V3(nx, ny, 0) }
        if i == n - 1 { lastDir = V3(tx, ty, 0); lastNormal2 = V3(nx, ny, 0) }
        i += 1
    }
    i = 0
    while i + 1 < n {
        m.quad(topIdx[i].0, topIdx[i + 1].0, topIdx[i + 1].1, topIdx[i].1)
        m.quad(leftIdx[i].0, leftIdx[i + 1].0, leftIdx[i + 1].1, leftIdx[i].1)
        m.quad(rightIdx[i].0, rightIdx[i + 1].0, rightIdx[i + 1].1, rightIdx[i].1)
        i += 1
    }
    // End caps.
    func cap(_ idx: Int, _ dir: V3, _ side: V3) {
        let p: V3 = path[idx]
        let w: V3 = side * halfWidth
        let t: Float = halfThick
        let a = m.v(V3(p.x + w.x, p.y + w.y, p.z + t), dir, V2(0, 0), tan: side)
        let b = m.v(V3(p.x - w.x, p.y - w.y, p.z + t), dir, V2(1, 0), tan: side)
        let c = m.v(V3(p.x - w.x, p.y - w.y, p.z - t), dir, V2(1, 1), tan: side)
        let d = m.v(V3(p.x + w.x, p.y + w.y, p.z - t), dir, V2(0, 1), tan: side)
        m.quad(a, b, c, d)
    }
    cap(0, firstDir, firstNormal2)
    cap(n - 1, lastDir, lastNormal2)
    return m
}

/// A flat strip with a bevelled top edge, swept along a 3D centre line: even width, flat polished top, small bevels, plain
/// side walls. `lateralSlope[i]` is the rise per unit sideways at sample i, so the strip can roll to lie on a domed surface.
/// The cross-section is built from the horizontal sideways direction tilted by that slope, and the top faces along the
/// local up. Both ends are closed with flat caps.
func twBevelStrip(_ path: [V3], lateralSlope: [Float], halfWidth: Float, halfThick: Float, bevel: Float) -> MB {
    var m = MB()
    let n: Int = path.count
    if n < 2 { return m }
    // Cross-section corners (sideways, up): bottom left, bottom right, right shoulder, right top, left top, left shoulder.
    let w: Float = halfWidth
    let t: Float = halfThick
    let b: Float = bevel
    let corners: [(Float, Float)] = [(-w, -t), (w, -t), (w, t - b), (w - b, t), (-w + b, t), (-w, t - b)]
    var frames: [(l: V3, u: V3, tan: V3)] = []
    var i: Int = 0
    while i < n {
        let a: V3 = path[max(i - 1, 0)]
        let c: V3 = path[min(i + 1, n - 1)]
        let tan: V3 = simd_normalize(c - a)
        let flat: Float = max((tan.x * tan.x + tan.y * tan.y).squareRoot(), 1e-6)
        let tx: Float = tan.x / flat
        let ty: Float = tan.y / flat
        let side: V3 = simd_normalize(V3(-ty, tx, lateralSlope[i]))
        var up: V3 = simd_cross(tan, side)
        up = simd_normalize(up)
        frames.append((side, up, tan))
        i += 1
    }
    func corner(_ k: Int, _ f: Int) -> V3 {
        let fr = frames[f]
        let c = corners[k]
        return path[f] + fr.l * c.0 + fr.u * c.1
    }
    // Faces: each edge of the cross-section between two corners, flat-shaded with its own normal.
    func faceNormal(_ face: Int, _ f: Int) -> V3 {
        let fr = frames[f]
        switch face {
        case 0: return fr.u                                     // top
        case 1: return simd_normalize(fr.l + fr.u)              // right bevel
        case 2: return simd_normalize(fr.u - fr.l)              // left bevel
        case 3: return fr.l                                     // right side
        default: return -fr.l                                   // left side
        }
    }
    // face -> (corner a, corner b) with a to b running left to right (top) or bottom to top (sides).
    let faces: [(Int, Int)] = [(4, 3), (3, 2), (5, 4), (2, 1), (0, 5)]
    var f: Int = 0
    while f + 1 < n {
        for (face, pair) in faces.enumerated() {
            let n0: V3 = faceNormal(face, f)
            let n1: V3 = faceNormal(face, f + 1)
            let a0 = m.v(corner(pair.0, f), n0, V2(0, 0), tan: frames[f].tan)
            let b0 = m.v(corner(pair.1, f), n0, V2(1, 0), tan: frames[f].tan)
            let a1 = m.v(corner(pair.0, f + 1), n1, V2(0, 1), tan: frames[f + 1].tan)
            let b1 = m.v(corner(pair.1, f + 1), n1, V2(1, 1), tan: frames[f + 1].tan)
            m.quad(a0, b0, b1, a1)
        }
        f += 1
    }
    // End caps.
    func cap(_ idx: Int, _ dir: V3) {
        var ids: [UInt32] = []
        for k in 0..<corners.count { ids.append(m.v(corner(k, idx), dir, V2(0, 0), tan: frames[idx].l)) }
        var k: Int = 1
        while k + 1 < ids.count { m.tri(ids[0], ids[k], ids[k + 1]); k += 1 }
    }
    cap(0, -frames[0].tan)
    cap(n - 1, frames[n - 1].tan)
    return m
}
