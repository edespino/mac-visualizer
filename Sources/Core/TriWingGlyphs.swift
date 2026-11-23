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

// An original engraved roman alphabet for the Tri-wing's ring, and the layout that runs a phrase along the ring. Every glyph
// is a union of pieces in a box of cap height 1 (x from 0 at the glyph's left ink edge, y up from the baseline): butt-ended
// bars of varying width (stems, arms, diagonals, small wedge serifs) and elliptical arcs whose width swells at the sides and
// thins at top and bottom. Each piece has a signed-distance function, so the letters are cut as real geometry (see
// `RectCutMesher`). No font files and no third-party glyph data; every shape below is drawn from these pieces.

/// One drawn piece of a glyph.
public enum GlyphPiece {
    /// A straight bar from `a` to `b` with squared (butt) ends; `wa` and `wb` are the half widths at the two ends (a wedge
    /// when they differ).
    case bar(a: P2, b: P2, wa: Float, wb: Float)
    /// An elliptical arc band about (`cx`, `cy`) with radii `rx`, `ry`, over the parametric angles `from`...`to` (degrees,
    /// counter-clockwise, `to - from` at most 360); its half width is `thick` at 0 and 180 degrees and `thin` at 90 and 270.
    /// A 360 degree span is a closed ring; shorter arcs are cut square (radially) at both ends.
    case arc(cx: Float, cy: Float, rx: Float, ry: Float, from: Float, to: Float, thick: Float, thin: Float)

    /// Signed distance to the piece (negative inside). Exact on the long edges; the squared corners use a max of the edge
    /// distances, so they stay sharp.
    public func distance(_ p: P2) -> Float {
        switch self {
        case let .bar(a, b, wa, wb):
            let dx: Float = b.x - a.x
            let dy: Float = b.y - a.y
            let len: Float = max((dx * dx + dy * dy).squareRoot(), 1e-9)
            let ux: Float = dx / len
            let uy: Float = dy / len
            let px: Float = p.x - a.x
            let py: Float = p.y - a.y
            let t: Float = px * ux + py * uy
            let s: Float = -px * uy + py * ux
            let tc: Float = min(max(t, 0), len)
            let hw: Float = wa + (wb - wa) * (tc / len)
            let across: Float = abs(s) - hw
            let ends: Float = max(-t, t - len)
            return max(across, ends)
        case let .arc(cx, cy, rx, ry, from, to, thick, thin):
            let x: Float = (p.x - cx) / rx
            let y: Float = (p.y - cy) / ry
            let rho: Float = (x * x + y * y).squareRoot()
            let gx: Float = x / rx
            let gy: Float = y / ry
            let gradMag: Float = max((gx * gx + gy * gy).squareRoot() / max(rho, 1e-6), 1e-6)
            let curve: Float = (rho - 1) / gradMag
            let phi: Float = atan2(y, x)
            let c: Float = cos(phi)
            let hw: Float = thin + (thick - thin) * c * c
            let across: Float = abs(curve) - hw
            let span: Float = to - from
            if span >= 359.99 { return across }
            let mid: Float = (from + to) * 0.5
            var dphi: Float = phi * 180 / Float.pi - mid
            while dphi > 180 { dphi -= 360 }
            while dphi < -180 { dphi += 360 }
            let over: Float = (abs(dphi) - span * 0.5) * Float.pi / 180
            let sx: Float = rx * sin(phi)
            let sy: Float = ry * cos(phi)
            let local: Float = (sx * sx + sy * sy).squareRoot()
            return max(across, over * local)
        }
    }
}

public enum GlyphShape { case straight, round, diagonal, dot }

public struct EngravedGlyph {
    public var pieces: [GlyphPiece]
    /// Width of the glyph's ink box in cap heights, and the height of its top (1 for capitals and digits).
    public var width: Float
    public var top: Float
    public var left: GlyphShape
    public var right: GlyphShape

    /// Signed distance to the glyph's ink (negative inside), clipped to the ink box so no piece can poke out of it.
    public func distance(_ p: P2) -> Float {
        var best: Float = 1
        for piece in pieces {
            let d: Float = piece.distance(p)
            if d < best { best = d }
        }
        let clip: Float = max(max(-p.y, p.y - top), max(-p.x, p.x - width))
        return max(best, clip)
    }
}

public enum EngravingFont {

    /// Characters the font defines (besides the space).
    public static let supported: String = "ABCDEHIJKLMNOPRSTUVWYZ01o."

    /// Half widths in cap heights: stems (verticals and the sides of round letters), thin strokes (horizontals, the tops
    /// and bottoms of rounds, light diagonals) and heavier diagonals. Stems are 0.16 of the cap height; thin strokes 0.625 of
    /// a stem.
    public static let stemHalfWidth: Float = 0.08
    public static let thinHalfWidth: Float = 0.05
    public static let diagonalHalfWidth: Float = 0.065
    /// Serif wedge: half length either side of its stem and the half thickness at the stem and at the tip.
    private static let serifRoot: Float = 0.040
    private static let serifTip: Float = 0.026
    private static let beakRoot: Float = 0.035
    private static let beakTip: Float = 0.022

    private static let S: Float = stemHalfWidth
    private static let T: Float = thinHalfWidth
    private static let D: Float = diagonalHalfWidth

    private static func bar(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ wa: Float, _ wb: Float) -> GlyphPiece {
        GlyphPiece.bar(a: P2(x0, y0), b: P2(x1, y1), wa: wa, wb: wb)
    }
    private static func stem(_ x: Float, _ y0: Float, _ y1: Float) -> GlyphPiece { bar(x, y0, x, y1, S, S) }
    private static func thin(_ x0: Float, _ y: Float, _ x1: Float) -> GlyphPiece { bar(x0, y, x1, y, T, T) }
    private static func arc(_ cx: Float, _ cy: Float, _ rx: Float, _ ry: Float, _ a0: Float, _ a1: Float) -> GlyphPiece {
        GlyphPiece.arc(cx: cx, cy: cy, rx: rx, ry: ry, from: a0, to: a1, thick: S, thin: T)
    }
    /// Wedge serifs on the stem at `x`: a pair of tapered bars at the foot and/or the head, `half` long either side.
    private static func serifs(_ x: Float, foot: Bool, head: Bool, half: Float = 0.15) -> [GlyphPiece] {
        var out: [GlyphPiece] = []
        var ys: [Float] = []
        if foot { ys.append(0.04) }
        if head { ys.append(0.96) }
        for y in ys {
            out.append(bar(x, y, x - half, y, serifRoot, serifTip))
            out.append(bar(x, y, x + half, y, serifRoot, serifTip))
        }
        return out
    }
    /// A vertical wedge at the end of an arm (a beak), from `y0` toward `y1`.
    private static func beak(_ x: Float, _ y0: Float, _ y1: Float) -> GlyphPiece { bar(x, y0, x, y1, beakRoot, beakTip) }

    private static func make(_ pieces: [GlyphPiece], _ width: Float, _ left: GlyphShape, _ right: GlyphShape, top: Float = 1) -> EngravedGlyph {
        EngravedGlyph(pieces: pieces, width: width, top: top, left: left, right: right)
    }

    public static func glyph(for ch: Character) -> EngravedGlyph? {
        switch ch {
        case "A":
            var p: [GlyphPiece] = [bar(0.43, 1.03, 0.12, -0.03, T, T), bar(0.37, 1.03, 0.68, -0.03, D, D), thin(0.20, 0.30, 0.60)]
            p.append(contentsOf: serifs(0.12, foot: true, head: false, half: 0.12))
            p.append(contentsOf: serifs(0.68, foot: true, head: false, half: 0.12))
            return make(p, 0.80, .diagonal, .diagonal)
        case "B":
            var p: [GlyphPiece] = [stem(0.15, 0, 1), thin(0.15, 0.95, 0.31), thin(0.15, 0.545, 0.31), thin(0.15, 0.05, 0.31)]
            p.append(arc(0.28, 0.7475, 0.25, 0.2025, -90, 90))
            p.append(arc(0.28, 0.2975, 0.29, 0.2475, -90, 90))
            p.append(contentsOf: serifs(0.15, foot: true, head: true))
            return make(p, 0.65, .straight, .round)
        case "C":
            let p: [GlyphPiece] = [arc(0.43, 0.5, 0.35, 0.45, 40, 320), beak(0.70, 0.81, 0.62), beak(0.70, 0.19, 0.38)]
            return make(p, 0.75, .round, .round)
        case "D":
            var p: [GlyphPiece] = [stem(0.15, 0, 1), thin(0.15, 0.95, 0.31), thin(0.15, 0.05, 0.31), arc(0.28, 0.5, 0.42, 0.45, -90, 90)]
            p.append(contentsOf: serifs(0.15, foot: true, head: true))
            return make(p, 0.78, .straight, .round)
        case "E":
            var p: [GlyphPiece] = [stem(0.15, 0, 1), thin(0.15, 0.95, 0.60), thin(0.15, 0.50, 0.48), thin(0.15, 0.05, 0.60),
                                   beak(0.585, 0.99, 0.80), beak(0.585, 0.01, 0.20)]
            p.append(contentsOf: serifs(0.15, foot: true, head: true))
            return make(p, 0.62, .straight, .straight)
        case "H":
            var p: [GlyphPiece] = [stem(0.15, 0, 1), stem(0.67, 0, 1), thin(0.15, 0.50, 0.67)]
            p.append(contentsOf: serifs(0.15, foot: true, head: true))
            p.append(contentsOf: serifs(0.67, foot: true, head: true))
            return make(p, 0.82, .straight, .straight)
        case "I":
            var p: [GlyphPiece] = [stem(0.15, 0, 1)]
            p.append(contentsOf: serifs(0.15, foot: true, head: true))
            return make(p, 0.30, .straight, .straight)
        case "J":
            var p: [GlyphPiece] = [stem(0.58, 0.28, 1), arc(0.33, 0.30, 0.25, 0.25, 180, 360), beak(0.08, 0.28, 0.46)]
            p.append(contentsOf: serifs(0.58, foot: false, head: true))
            return make(p, 0.73, .straight, .straight)
        case "K":
            var p: [GlyphPiece] = [stem(0.15, 0, 1), bar(0.20, 0.38, 0.66, 1.03, T, T), bar(0.34, 0.57, 0.74, -0.03, D, D)]
            p.append(contentsOf: serifs(0.15, foot: true, head: true))
            p.append(contentsOf: serifs(0.64, foot: false, head: true, half: 0.12))
            p.append(contentsOf: serifs(0.72, foot: true, head: false, half: 0.12))
            return make(p, 0.84, .straight, .diagonal)
        case "L":
            var p: [GlyphPiece] = [stem(0.15, 0, 1), thin(0.15, 0.05, 0.55), beak(0.515, 0.01, 0.22)]
            p.append(contentsOf: serifs(0.15, foot: true, head: true))
            return make(p, 0.55, .straight, .straight)
        case "M":
            var p: [GlyphPiece] = [stem(0.15, 0, 1), stem(0.85, 0, 1), bar(0.15, 1.03, 0.50, -0.03, D, D), bar(0.50, -0.03, 0.85, 1.03, T, T)]
            p.append(contentsOf: serifs(0.15, foot: true, head: true))
            p.append(contentsOf: serifs(0.85, foot: true, head: true))
            return make(p, 1.0, .straight, .straight)
        case "N":
            var p: [GlyphPiece] = [stem(0.15, 0, 1), stem(0.75, 0, 1), bar(0.15, 1.03, 0.75, -0.03, D, D)]
            p.append(contentsOf: serifs(0.15, foot: true, head: true))
            p.append(contentsOf: serifs(0.75, foot: true, head: true))
            return make(p, 0.90, .straight, .straight)
        case "O":
            return make([arc(0.43, 0.5, 0.35, 0.45, 0, 360)], 0.86, .round, .round)
        case "P":
            var p: [GlyphPiece] = [stem(0.15, 0, 1), thin(0.15, 0.95, 0.33), thin(0.15, 0.40, 0.33), arc(0.30, 0.675, 0.30, 0.275, -90, 90)]
            p.append(contentsOf: serifs(0.15, foot: true, head: true))
            return make(p, 0.68, .straight, .round)
        case "R":
            var p: [GlyphPiece] = [stem(0.15, 0, 1), thin(0.15, 0.95, 0.33), thin(0.15, 0.52, 0.33), arc(0.30, 0.735, 0.30, 0.215, -90, 90),
                                   bar(0.36, 0.55, 0.70, -0.03, D, D)]
            p.append(contentsOf: serifs(0.15, foot: true, head: true))
            p.append(contentsOf: serifs(0.68, foot: true, head: false, half: 0.10))
            return make(p, 0.78, .straight, .diagonal)
        case "S":
            let p: [GlyphPiece] = [arc(0.34, 0.735, 0.25, 0.215, 25, 300), arc(0.36, 0.285, 0.27, 0.235, -160, 80),
                                   beak(0.57, 0.85, 0.68), beak(0.11, 0.19, 0.34)]
            return make(p, 0.71, .round, .round)
        case "T":
            var p: [GlyphPiece] = [thin(0.0, 0.95, 0.66), beak(0.035, 0.99, 0.80), beak(0.625, 0.99, 0.80), stem(0.33, 0, 0.95)]
            p.append(contentsOf: serifs(0.33, foot: true, head: false))
            return make(p, 0.66, .diagonal, .diagonal)
        case "U":
            var p: [GlyphPiece] = [stem(0.15, 0.38, 1), stem(0.70, 0.38, 1), arc(0.425, 0.40, 0.275, 0.35, 180, 360)]
            p.append(contentsOf: serifs(0.15, foot: false, head: true))
            p.append(contentsOf: serifs(0.70, foot: false, head: true))
            return make(p, 0.85, .straight, .straight)
        case "V":
            var p: [GlyphPiece] = [bar(0.12, 1.03, 0.37, -0.03, D, D), bar(0.68, 1.03, 0.43, -0.03, T, T)]
            p.append(contentsOf: serifs(0.12, foot: false, head: true, half: 0.12))
            p.append(contentsOf: serifs(0.68, foot: false, head: true, half: 0.12))
            return make(p, 0.80, .diagonal, .diagonal)
        case "W":
            var p: [GlyphPiece] = [bar(0.12, 1.03, 0.33, -0.03, D, D), bar(0.33, -0.03, 0.57, 1.03, T, T),
                                   bar(0.57, 1.03, 0.80, -0.03, D, D), bar(0.80, -0.03, 1.02, 1.03, T, T)]
            p.append(contentsOf: serifs(0.12, foot: false, head: true, half: 0.12))
            p.append(contentsOf: serifs(1.02, foot: false, head: true, half: 0.12))
            return make(p, 1.14, .diagonal, .diagonal)
        case "Y":
            var p: [GlyphPiece] = [bar(0.12, 1.03, 0.39, 0.46, D, D), bar(0.66, 1.03, 0.39, 0.46, T, T), stem(0.39, 0, 0.50)]
            p.append(contentsOf: serifs(0.12, foot: false, head: true, half: 0.12))
            p.append(contentsOf: serifs(0.66, foot: false, head: true, half: 0.12))
            p.append(contentsOf: serifs(0.39, foot: true, head: false))
            return make(p, 0.78, .diagonal, .diagonal)
        case "Z":
            let p: [GlyphPiece] = [thin(0.0, 0.95, 0.70), thin(0.0, 0.05, 0.70), beak(0.035, 0.99, 0.80), beak(0.665, 0.01, 0.20),
                                   bar(0.60, 0.93, 0.10, 0.07, D, D)]
            return make(p, 0.70, .straight, .straight)
        case "0":
            return make([arc(0.33, 0.5, 0.25, 0.45, 0, 360)], 0.66, .round, .round)
        case "1":
            var p: [GlyphPiece] = [stem(0.30, 0, 1), bar(0.34, 1.03, 0.04, 0.79, T, T)]
            p.append(contentsOf: serifs(0.30, foot: true, head: false, half: 0.20))
            return make(p, 0.50, .diagonal, .straight)
        case "o":
            return make([GlyphPiece.arc(cx: 0.27, cy: 0.29, rx: 0.20, ry: 0.245, from: 0, to: 360, thick: 0.07, thin: 0.045)],
                        0.54, .round, .round, top: 0.58)
        case ".":
            return make([bar(0.07, 0, 0.07, 0.14, 0.07, 0.07)], 0.14, .dot, .dot, top: 0.14)
        default:
            return nil
        }
    }

    /// Side bearing in cap heights next to a glyph edge of this shape (ink to ink, serifs included), so the optical gap
    /// looks even.
    public static func bearing(_ shape: GlyphShape) -> Float {
        switch shape {
        case .straight: return 0.07
        case .round: return 0.05
        case .diagonal: return 0.02
        case .dot: return 0.10
        }
    }
}

/// Lettering laid out as arcs on the ring's strip: u = position along the circumference at the ring's mid radius (clockwise),
/// v = radial distance from the ring's inner edge. An upper arc reads clockwise with letter tops outward; a lower arc is the
/// same line turned half a turn (it reads counter-clockwise, left to right at 6 o'clock, with letter tops toward the hub).
/// Every arc uses the same cap height and tracking (the fixed space added to each glyph's natural side bearings), so short
/// lines stay compact and are centred on their clock position rather than stretched.
public struct RingTextLayout {
    public struct Item {
        public var character: Character
        public var glyph: EngravedGlyph
        /// Smallest u of the glyph's ink box and its width (along u, whichever way the arc reads).
        public var u: Float
        public var width: Float
        /// The strip position of the glyph's local x = 0, and whether the glyph is on a lower arc (turned half a turn).
        public var originU: Float
        public var lower: Bool
    }
    public var items: [Item] = []
    public var capHeight: Float
    public var baselineV: Float
    /// Fixed space added after every glyph's natural advance (and after each word gap).
    public var tracking: Float

    /// Gap on each side of a space, in cap heights (a space is two of these plus two trackings).
    public static let wordGap: Float = 0.35

    /// Length of `text` from its first glyph's ink edge to its last glyph's ink edge.
    public static func span(of text: String, capHeight: Float, tracking: Float) -> Float {
        var glyphs: [EngravedGlyph?] = []
        for c in text { glyphs.append(c == " " ? nil : EngravingFont.glyph(for: c)) }
        var total: Float = 0
        var i: Int = 0
        while i < glyphs.count {
            total += (glyphs[i]?.width ?? 0) * capHeight
            if i + 1 < glyphs.count { total += gap(glyphs[i], glyphs[i + 1], capHeight: capHeight) + tracking }
            i += 1
        }
        return total
    }

    private static func gap(_ a: EngravedGlyph?, _ b: EngravedGlyph?, capHeight: Float) -> Float {
        if let a = a, let b = b { return (EngravingFont.bearing(a.right) + EngravingFont.bearing(b.left)) * capHeight }
        return wordGap * capHeight
    }

    /// One arc, centred on `centreU`. The cap box spans v = baselineV ... baselineV + capHeight on both arcs.
    public static func layoutArc(text: String, centreU: Float, lower: Bool, capHeight: Float, tracking: Float,
                                 baselineV: Float) -> RingTextLayout {
        var layout = RingTextLayout(capHeight: capHeight, baselineV: baselineV, tracking: tracking)
        var chars: [Character] = []
        for c in text { chars.append(c) }
        var glyphs: [EngravedGlyph?] = []
        for c in chars { glyphs.append(c == " " ? nil : EngravingFont.glyph(for: c)) }
        let total: Float = span(of: text, capHeight: capHeight, tracking: tracking)
        let half: Float = total * 0.5
        var x: Float = 0
        var i: Int = 0
        while i < chars.count {
            let w: Float = (glyphs[i]?.width ?? 0) * capHeight
            if let g = glyphs[i] {
                // Reading offset x along the line; the lower arc is the upper arc turned half a turn.
                let origin: Float = lower ? centreU + half - x : centreU - half + x
                let u0: Float = lower ? origin - w : origin
                layout.items.append(Item(character: chars[i], glyph: g, u: u0, width: w, originU: origin, lower: lower))
            }
            x += w
            if i + 1 < chars.count { x += gap(glyphs[i], glyphs[i + 1], capHeight: capHeight) + tracking }
            i += 1
        }
        return layout
    }

    /// All the arcs of a face with the TriWing lettering constants.
    public static func layoutFace(_ face: TriWing.RingFace) -> RingTextLayout {
        var all = RingTextLayout(capHeight: TriWing.ringTextCapHeight, baselineV: TriWing.ringTextBaselineV,
                                 tracking: TriWing.ringTextTracking)
        for spec in TriWing.ringArcs(face: face) {
            let one: RingTextLayout = layoutArc(text: spec.text, centreU: TriWing.ringArcCentreU(lower: spec.lower), lower: spec.lower,
                                                capHeight: all.capHeight, tracking: all.tracking, baselineV: all.baselineV)
            all.items.append(contentsOf: one.items)
        }
        return all
    }

    /// Signed distance (negative inside the letters) at strip point (u, v), in the strip's units.
    public func distance(u: Float, v: Float) -> Float {
        var best: Float = 1
        let pad: Float = 0.02
        for it in items {
            if u < it.u - pad || u > it.u + it.width + pad { continue }
            if v < baselineV - pad || v > baselineV + capHeight + pad { continue }
            let gx: Float = (it.lower ? it.originU - u : u - it.originU) / capHeight
            let gy: Float = (it.lower ? baselineV + capHeight - v : v - baselineV) / capHeight
            let d: Float = it.glyph.distance(P2(gx, gy)) * capHeight
            if d < best { best = d }
        }
        return best
    }

    /// Smallest and largest u any glyph of the layout reaches.
    public func extent() -> (lo: Float, hi: Float) {
        var lo: Float = Float.greatestFiniteMagnitude
        var hi: Float = -Float.greatestFiniteMagnitude
        for it in items {
            lo = min(lo, it.u)
            hi = max(hi, it.u + it.width)
        }
        return (lo, hi)
    }
}

/// Fits a mark authored in design units (y down or up as given) into a patch: returns capsule strokes centred on the
/// patch centre with the mark's design centre at the origin, scaled so the mark's height (including stroke width) is
/// `targetHeight`, with y flipped when `flipY` (design y down to world y up). Pure, for tests and the patch builder.
public enum MarkFit {
    public static func strokes(_ design: [(a: P2, b: P2, width: Float)], designCentre: P2, designHeight: Float,
                               targetHeight: Float, flipY: Bool) -> [(a: P2, b: P2, hw: Float)] {
        let scale: Float = targetHeight / designHeight
        let sign: Float = flipY ? -1 : 1
        var out: [(a: P2, b: P2, hw: Float)] = []
        for s in design {
            let a = P2((s.a.x - designCentre.x) * scale, sign * (s.a.y - designCentre.y) * scale)
            let b = P2((s.b.x - designCentre.x) * scale, sign * (s.b.y - designCentre.y) * scale)
            out.append((a: a, b: b, hw: s.width * scale * 0.5))
        }
        return out
    }
}
