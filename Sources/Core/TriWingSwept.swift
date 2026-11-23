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

// Profile maths of the Tri-wing's spinning look (pure, no RealityKit types): how the solid part hands over to the swept
// volume as it spins up, how opaque the swept wing zone is at each radius, how tall it is, and the light rings and the
// side band of light that the edge lights sweep into. The renderer turns these into meshes and textures.

public enum TriWingSwept {

    // MARK: Ramp

    /// Weights of the layers at blur amount `t` (0 at rest, 1 fully spun up).
    public struct Ramp {
        /// Solid part and its tubes: stays opaque until the swept core is mostly in, then fades out.
        public let solid: Float
        /// Face overlay inside the full-coverage radius (the body there is a full circle, so it can come in early).
        public let core: Float
        /// Swept wing zone beyond the full-coverage radius (translucent faces and shells), the light rings and the side
        /// band: comes in late, as a cube of `t`, so nothing shows outside the solid part's own outline while it is slow.
        public let zone: Float
    }

    public static func ramp(_ t: Float) -> Ramp {
        let x: Float = min(max(t, 0), 1)
        let solid: Float = x < 0.7 ? 1 : (1 - x) / 0.3
        return Ramp(solid: solid, core: x, zone: x * x * x)
    }

    // MARK: Wing zone opacity

    static func smooth(_ lo: Float, _ hi: Float, _ x: Float) -> Float {
        let t: Float = min(max((x - lo) / (hi - lo), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Opacity of the swept wing zone where the body covers `coverage` of the circle. Physically it follows the coverage;
    /// it is lifted (exponent below 1) so the faint outer zone still reads on a dark backdrop, and fades in smoothly
    /// from 1.5% to 6% coverage so the zone has no hard circular edge at the tip.
    public static func zoneOpacity(coverage: Float) -> Float {
        let c: Float = min(max(coverage, 0), 1)
        let lifted: Float = Float(pow(Double(c), 0.72))
        return lifted * smooth(0.012, 0.06, c)
    }

    // MARK: Light rings

    /// Peak opacity of the swept light rings.
    public static let ringPeakOpacity: Float = 0.85
    /// Opacity of a ring at a radius where lit tubes cover `share` of the circle.
    public static func ringOpacity(share: Float) -> Float {
        ringPeakOpacity * (1 - Float(exp(Double(-max(share, 0) * 70))))
    }

    /// Saturation lift about the Rec. 601 luma (negative channels clamp to 0).
    public static func liftSaturation(_ c: SIMD3<Float>, _ k: Float) -> SIMD3<Float> {
        let grey: Float = c.x * 0.30 + c.y * 0.59 + c.z * 0.11
        return SIMD3<Float>(max(grey + (c.x - grey) * k, 0), max(grey + (c.y - grey) * k, 0), max(grey + (c.z - grey) * k, 0))
    }

    // MARK: Side band

    /// The edge-light windows swept round the waist: the share of the circle at `waistRadius` they cover, the half height of
    /// the lit band (the window's), and the average colours of the upper half (the front face's windows) and lower half
    /// (the back face's), with the saturation lifted so the average of the three wing colours does not read as grey.
    public struct SideBand {
        public let share: Float
        public let halfHeight: Float
        public let upper: SIMD3<Float>
        public let lower: SIMD3<Float>
    }

    /// `wingColours` are the three wings' light colours (the renderer's `twLightColor`).
    public static func sideBand(waistRadius: Float, wingColours: [SIMD3<Float>] = TriWingSwept.defaultWingColours) -> SideBand {
        let windows: [TriWingWall.Window] = TriWingWall.windows()
        var length: Float = 0
        var front = SIMD3<Float>(0, 0, 0)
        var back = SIMD3<Float>(0, 0, 0)
        for w in windows {
            let l: Float = 2 * w.halfLength
            length += l
            front += wingColours[w.wing % wingColours.count] * l
            // The back face is the front half turned half a turn about the vertical axis: it carries the same windows, and
            // the wing that sits at a given place on the front is the one that the turn brings round to its mirror place.
            back += wingColours[(TriWing.wingCount - w.wing) % TriWing.wingCount % wingColours.count] * l
        }
        let circumference: Float = 2 * Float.pi * waistRadius
        let share: Float = min(length / circumference, 1)
        let upper: SIMD3<Float> = liftSaturation(front / max(length, 1e-6) * 1.0, 1.9)
        let lower: SIMD3<Float> = liftSaturation(back / max(length, 1e-6) * 1.0, 1.9)
        let norm: (SIMD3<Float>) -> SIMD3<Float> = { (c: SIMD3<Float>) -> SIMD3<Float> in
            let m: Float = max(c.x, max(c.y, c.z))
            return m > 1e-6 ? c / m : c
        }
        return SideBand(share: share, halfHeight: TriWingWall.windowHalfHeight, upper: norm(upper), lower: norm(lower))
    }

    /// Upper (front faces') and lower (back faces') side-band colours for any three wing colours: the same result as
    /// `sideBand(waistRadius:wingColours:)`'s `upper` and `lower`, with the window weights computed once (cheap enough to
    /// call every frame while a palette crossfades).
    public static func sideBandColours(wingColours: [SIMD3<Float>]) -> (upper: SIMD3<Float>, lower: SIMD3<Float>) {
        let w = sideBandWeights
        var front = SIMD3<Float>(0, 0, 0)
        var back = SIMD3<Float>(0, 0, 0)
        for k in 0..<3 {
            front += wingColours[k % wingColours.count] * w.front[k]
            back += wingColours[k % wingColours.count] * w.back[k]
        }
        let norm: (SIMD3<Float>) -> SIMD3<Float> = { (c: SIMD3<Float>) -> SIMD3<Float> in
            let m: Float = max(c.x, max(c.y, c.z))
            return m > 1e-6 ? c / m : c
        }
        return (norm(liftSaturation(front, 1.9)), norm(liftSaturation(back, 1.9)))
    }

    /// Share of the windows' total length carried by each wing, for the front (upper) and back (lower) faces.
    private static let sideBandWeights: (front: [Float], back: [Float]) = {
        var length: Float = 0
        var front: [Float] = [0, 0, 0]
        var back: [Float] = [0, 0, 0]
        for w in TriWingWall.windows() {
            let l: Float = 2 * w.halfLength
            length += l
            front[w.wing % 3] += l
            back[(TriWing.wingCount - w.wing) % TriWing.wingCount % 3] += l
        }
        let total: Float = max(length, 1e-6)
        return (front.map { (v: Float) -> Float in v / total }, back.map { (v: Float) -> Float in v / total })
    }()

    public static let defaultWingColours: [SIMD3<Float>] = [SIMD3<Float>(0.25, 1.0, 0.45), SIMD3<Float>(0.30, 0.75, 1.0), SIMD3<Float>(1.0, 0.50, 0.12)]
}

extension TriWingSmear {

    /// Smoothed share of the circle covered by lit tubes at each radius, as opacity and colour of the swept light rings.
    public struct GlowRing {
        public var opacity: [Float]
        public var colour: [SIMD3<Float>]
    }

    /// Light rings: the tube share and colours blurred a few bins (soft edges), the colour normalised to its brightest
    /// channel and its saturation lifted, the opacity from `TriWingSwept.ringOpacity`.
    public func glowRing() -> GlowRing {
        let n: Int = radii
        let sigma: Float = 2.2
        let half: Int = 7
        var weights: [Float] = []
        var total: Float = 0
        for k in -half...half {
            let w: Float = Float(exp(Double(-Float(k * k) / (2 * sigma * sigma))))
            weights.append(w)
            total += w
        }
        var share = [Float](repeating: 0, count: n)
        var col = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: n)
        var i: Int = 0
        while i < n {
            var s: Float = 0
            var c = SIMD3<Float>(0, 0, 0)
            var k: Int = -half
            while k <= half {
                let j: Int = min(max(i + k, 0), n - 1)
                let w: Float = weights[k + half] / total
                s += glow[j] * w
                c += glowColor[j] * w
                k += 1
            }
            share[i] = s
            col[i] = c
            i += 1
        }
        var opacity = [Float](repeating: 0, count: n)
        var colour = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: n)
        i = 0
        while i < n {
            opacity[i] = TriWingSwept.ringOpacity(share: share[i])
            if share[i] > 1e-6 {
                let avg: SIMD3<Float> = col[i] / share[i]
                let m: Float = max(avg.x, max(avg.y, avg.z))
                let lifted: SIMD3<Float> = TriWingSwept.liftSaturation(m > 1e-6 ? avg / m : avg, 1.25)
                let m2: Float = max(lifted.x, max(lifted.y, lifted.z))
                colour[i] = m2 > 1e-6 ? lifted / m2 : lifted
            }
            i += 1
        }
        return GlowRing(opacity: opacity, colour: colour)
    }

    /// The swept light rings split by wing: per wing, the ring opacity (`glowRing().opacity`) multiplied by that wing's
    /// share of the lit tubes at the radius, so the three arrays add up to the ring opacity. Each is a neutral mask that a
    /// material tints with the wing's colour, which lets the ring's colours change without rebuilding any texture.
    public func glowRingWings() -> [[Float]] {
        let n: Int = radii
        let sigma: Float = 2.2
        let half: Int = 7
        var weights: [Float] = []
        var total: Float = 0
        for k in -half...half {
            let w: Float = Float(exp(Double(-Float(k * k) / (2 * sigma * sigma))))
            weights.append(w)
            total += w
        }
        let opacity: [Float] = glowRing().opacity
        var out: [[Float]] = [[Float](repeating: 0, count: n), [Float](repeating: 0, count: n), [Float](repeating: 0, count: n)]
        var i: Int = 0
        while i < n {
            var acc = SIMD3<Float>(0, 0, 0)
            var k: Int = -half
            while k <= half {
                let j: Int = min(max(i + k, 0), n - 1)
                if j < glowWing.count { acc += glowWing[j] * (weights[k + half] / total) }
                k += 1
            }
            let sum: Float = acc.x + acc.y + acc.z
            if sum > 1e-9 {
                out[0][i] = opacity[i] * acc.x / sum
                out[1][i] = opacity[i] * acc.y / sum
                out[2][i] = opacity[i] * acc.z / sum
            }
            i += 1
        }
        return out
    }

    /// Half height of the swept body at radius `r`: the body plate's (less the seat inset of the opaque core) plus the lift
    /// of the plates and bosses where they cover the circle, smoothed over about 0.11 R so the swept silhouette has no
    /// steps. Never below the plate, never above the tallest feature.
    public func sweptHalfHeight(at r: Float) -> Float {
        let base: Float = TriWing.halfThickness - 0.003
        let centre: Int = min(max(Int(r * Float(radii)), 0), radii - 1)
        let span: Int = max(Int(0.055 * Float(radii)), 1)
        var sum: Float = 0
        var count: Float = 0
        var i: Int = max(centre - span, 0)
        let last: Int = min(centre + span, radii - 1)
        while i <= last {
            let cov: Float = max(coverage[i], 1e-4)
            let padShare: Float = (classes[i][TriWingSmear.pad] + classes[i][TriWingSmear.boss] + classes[i][TriWingSmear.gold]
                                   + classes[i][TriWingSmear.jewel] + classes[i][TriWingSmear.screw] + classes[i][TriWingSmear.steel]) / cov
            // Below full coverage the share of the plate is not the share of the circle; weight by coverage.
            sum += min(max(padShare, 0), 1) * min(cov, 1)
            count += 1
            i += 1
        }
        let lift: Float = (TriWing.padHeight + TriWing.bossHeight) * (count > 0 ? sum / count : 0)
        return base + min(lift, TriWing.padHeight + TriWing.bossHeight + 0.003)
    }
}
