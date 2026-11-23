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

// Layout of the Tri-wing spinner (pure data, no RealityKit types). Everything is authored for one wing pointing up
// (+y) on a face seen from the front; the other two wings are copies rotated by 120 and 240 degrees, and the back face is
// the same layout mirrored in x (so lettering and marks read correctly when that face is toward the viewer).
//
// The design coordinates (`d` values below) come from a 2D drawing with y pointing down and the centre at the origin; the
// wing tip reaches 146 drawing units, which `unit` maps to 1 R (the disc's outer radius). Heights are in R.

public enum TriWing {

    /// One drawing unit in R: the wing tip (146 units) lands at R = 1, the same on-screen size as the disc.
    public static let unit: Float = 1.0 / 146.0

    /// Drawing point (y down) to R coordinates (y up).
    public static func point(_ x: Float, _ yDown: Float) -> P2 {
        P2(x * unit, -yDown * unit)
    }
    public static func length(_ drawing: Float) -> Float { drawing * unit }

    // MARK: Heights (R)

    /// Half thickness of the body plate (the top face is at +halfThickness, the back face at -halfThickness).
    public static let halfThickness: Float = 0.14
    /// Chamfer around the body edge.
    public static let bodyChamfer: Float = 0.018
    /// Height of a wing pad above the body face, and its edge chamfer.
    public static let padHeight: Float = 0.026
    public static let padChamfer: Float = 0.009
    /// Height of the round boss above the pad, and its edge chamfer.
    public static let bossHeight: Float = 0.026
    public static let bossChamfer: Float = 0.009

    // MARK: Wings

    public static let wingCount: Int = 3
    public static func wingAngle(_ k: Int) -> Float { Float(k) * 2 * Float.pi / 3 }

    /// Body outline (counter-clockwise, wing 0 up, scooped sides), sampled about every `step` R.
    public static func bodyOutline(step: Float = 0.012) -> [P2] {
        var path = SampledPath(step: step / unit)
        path.move(to: P2(-30, -128))
        path.arc(radius: 34, large: false, sweep: true, to: P2(30, -128))
        path.quad(control: P2(60.6, -35), to: P2(125.85, 38.02))
        path.arc(radius: 34, large: false, sweep: true, to: P2(95.85, 89.98))
        path.quad(control: P2(0, 70), to: P2(-95.85, 89.98))
        path.arc(radius: 34, large: false, sweep: true, to: P2(-125.85, 38.02))
        path.quad(control: P2(-60.6, -35), to: P2(-30, -128))
        return polygonOriented(mapToR(path.closedPoints), counterClockwise: true)
    }

    /// Outline of one wing pad (wing 0, counter-clockwise).
    public static func padOutline(step: Float = 0.008) -> [P2] {
        var path = SampledPath(step: step / unit)
        path.move(to: P2(-22, -80))
        path.cubic(control1: P2(-30, -96), control2: P2(-29, -112), to: P2(-24, -126))
        path.arc(radius: 27.8, large: false, sweep: true, to: P2(24, -126))
        path.cubic(control1: P2(29, -112), control2: P2(30, -96), to: P2(22, -80))
        path.quad(control: P2(0, -86), to: P2(-22, -80))
        return polygonOriented(mapToR(path.closedPoints), counterClockwise: true)
    }

    private static func mapToR(_ pts: [P2]) -> [P2] {
        var out: [P2] = []
        out.reserveCapacity(pts.count)
        for q in pts { out.append(point(q.x, q.y)) }
        return out
    }

    // MARK: Wing features (wing 0)

    /// Centre of the round boss and of the jewel setting on it.
    public static let bossCenter: P2 = point(0, -113)
    public static let bossRadius: Float = 13.5 * unit

    /// Shock-spring jewel setting radii and heights (relative to the boss top).
    public static let countersinkTopRadius: Float = 11.6 * unit
    public static let countersinkFloorRadius: Float = 10.7 * unit
    public static let countersinkDepth: Float = 0.014
    public static let blockRadius: Float = 10.0 * unit
    public static let blockDrop: Float = 0.006          // block top below the boss top
    public static let seatRadius: Float = 7.7 * unit
    public static let seatDepth: Float = 0.006
    public static let capRadius: Float = 6.3 * unit
    public static let capRise: Float = 0.004            // cap jewel top above the block top

    // MARK: Cap jewel and spring clip
    //
    // The jewel is a polished domed cabochon: a spherical cap rising `jewelDomeHeight` above its rim, which sits
    // `jewelRimRise` above the gold block's top, inside a thin polished bezel. The spring clip is a flat even-width
    // strip: a stem seated in the hinge notch forks into two arms that bear on the stone's shoulder and end in two hooked
    // feet seated in the tip-side notches. Everything is mirror symmetric about the boss's radial (y) axis.

    public static let jewelDomeHeight: Float = 0.012
    public static let jewelRimRise: Float = 0.0025
    /// Radial width of the polished bezel around the stone and the height its lip stands above the stone's rim.
    public static let jewelBezelWidth: Float = 0.0036
    public static let jewelBezelLip: Float = 0.0008
    /// Radius of the sphere the dome is cut from.
    public static var jewelSphereRadius: Float {
        let a: Float = capRadius
        let h: Float = jewelDomeHeight
        return (a * a + h * h) / (2 * h)
    }
    /// Height of the dome above its rim at radius `r` (0 at and beyond the rim).
    public static func jewelDomeRise(at r: Float) -> Float {
        if r >= capRadius { return 0 }
        let rs: Float = jewelSphereRadius
        let under: Float = max(rs * rs - r * r, 0)
        return under.squareRoot() - (rs - jewelDomeHeight)
    }
    /// Height above the gold block's top of whatever the spring lies on at radius `r`: the stone, then its bezel, then the block.
    public static func jewelSurfaceRise(at r: Float) -> Float {
        if r <= capRadius { return jewelRimRise + jewelDomeRise(at: r) }
        let into: Float = r - capRadius
        if into >= jewelBezelWidth { return 0 }
        let top: Float = jewelRimRise + jewelBezelLip
        let flat: Float = 0.0012
        if into <= flat { return top }
        let t: Float = (into - flat) / (jewelBezelWidth - flat)
        return top * (1 - t)
    }

    public static let springHalfWidth: Float = 0.8 * unit
    /// Radius of the arms' centreline: on the stone's shoulder, inside its rim.
    public static let springShoulderRadius: Float = 5.4 * unit

    /// Even resampling of a polyline at `step` spacing (the last point is kept exactly).
    private static func resample(_ pts: [P2], step: Float) -> [P2] {
        var out: [P2] = [pts[0]]
        var carried: Float = 0
        var i: Int = 1
        while i < pts.count {
            var a: P2 = pts[i - 1]
            let b: P2 = pts[i]
            var seg: Float = simd_length(b - a)
            while carried + seg >= step && seg > 1e-9 {
                let need: Float = step - carried
                let t: Float = need / seg
                a = a + (b - a) * t
                out.append(a)
                seg = simd_length(b - a)
                carried = 0
            }
            carried += seg
            i += 1
        }
        out.append(pts[pts.count - 1])
        if out.count > 2 && simd_length(out[out.count - 1] - out[out.count - 2]) < step * 0.3 { out.remove(at: out.count - 2) }
        return out
    }

    /// The U-shaped arc of the spring (centreline, R, boss-local, y up): left foot in its notch, round the stone's shoulder
    /// to the fork at the hinge side, and back out to the right foot. Mirror symmetric; first and last points are the feet.
    public static func springArc() -> [P2] {
        // Left half in drawing units (y down): foot, a bend out of the notch, then the shoulder circle down to the fork.
        var half: [P2] = []
        half.append(P2(-6.2, -9.4))
        half.append(P2(-6.2, -8.0))
        let c0 = P2(-6.2, -8.0), c1 = P2(-6.2, -6.0), c2 = P2(-3.86, -4.27), c3 = P2(-4.79, -2.5)
        var k: Int = 1
        while k <= 24 {
            let t: Float = Float(k) / 24
            let m: Float = 1 - t
            let bx: Float = m * m * m * c0.x + 3 * m * m * t * c1.x + 3 * m * t * t * c2.x + t * t * t * c3.x
            let by: Float = m * m * m * c0.y + 3 * m * m * t * c1.y + 3 * m * t * t * c2.y + t * t * t * c3.y
            half.append(P2(bx, by))
            k += 1
        }
        let r: Float = 5.4
        let a0: Float = atan2(-2.5, -4.79)                 // about 207.6 degrees, written as -152.4
        let start: Float = a0 < 0 ? a0 + 2 * Float.pi : a0
        let end: Float = Float.pi / 2
        var j: Int = 1
        while j <= 40 {
            let t: Float = Float(j) / 40
            let ang: Float = start + (end - start) * t
            half.append(P2(r * cos(ang), r * sin(ang)))
            j += 1
        }
        var left: [P2] = []
        for q in half { left.append(point(q.x, q.y)) }
        var even: [P2] = resample(left, step: 0.5 * unit)
        even[even.count - 1] = point(0, 5.4)                  // the fork, exactly on the axis
        var full: [P2] = even
        var i: Int = even.count - 2
        while i >= 0 {
            full.append(P2(-even[i].x, even[i].y))
            i -= 1
        }
        return full
    }

    /// The stem: from the fork (on the axis, at the shoulder radius) toward the hinge notch at the part's centre side.
    public static func springStem() -> [P2] {
        let top: P2 = point(0, 5.2)
        let end: P2 = point(0, 9.0)
        return resample([top, end], step: 0.5 * unit)
    }

    /// Screw positions on a wing pad (design units: two at the base corners, one beyond the boss), and slot angles
    /// (radians, counter-clockwise in R space).
    public static let screwCentres: [P2] = [point(-19.5, -90), point(19.5, -90), point(0, -133.4)]
    public static let screwSlotAngles: [Float] = [-25 * Float.pi / 180, 50 * Float.pi / 180, -80 * Float.pi / 180]
    public static let screwHeadRadius: Float = 4.0 * 0.8 * unit
    public static let countersinkScrewRadius: Float = 5.6 * 0.8 * unit
    /// Screw head top below the pad surface.
    public static let screwDrop: Float = 0.006
    public static let screwCountersinkDepth: Float = 0.012
    public static let screwSlotHalfWidth: Float = 0.65 * 0.8 * unit
    public static let screwSlotDepth: Float = 0.004

    /// Edge-light tip centre (the body's tip arc is centred here).
    public static let tipCentre: P2 = point(0, -112)

    // MARK: Edge-light flank tubes
    //
    // Each wing carries two glass tubes, one in a machined slot along each outer flank, between the pad and the body edge
    // (the tip itself has no room for a tube as thick as the disc's rods). Each wing has its own colour.

    /// Tube radii (the disc rod's core and glass shell), slot half width, and depth below the face.
    public static let tubeCoreRadius: Float = 0.0115
    public static let tubeShellRadius: Float = 0.0185
    public static let tubeSlotHalfWidth: Float = 0.0185 + 0.0025
    public static let tubeSlotDepth: Float = 1.5 * (2 * 0.0185 + 0.0040)
    /// The hot filament inside the glass shell; the polished collar (a short cylindrical sleeve with a flat end cap and a
    /// small chamfer) that closes each tube end, its sleeve length along the tube, the chamfer, and how far its end cap
    /// reaches beyond the tube tip; and the width of the thin bright line along the slot's upper lip.
    public static let tubeFilamentRadius: Float = 0.0068
    public static let tubeCollarRadius: Float = 0.0197
    public static let tubeCollarLength: Float = 0.012
    public static let tubeCollarChamfer: Float = 0.0035
    public static let tubeCollarCapReach: Float = 0.0195
    public static let slotLipWidth: Float = 0.0026
    /// Distance of the tube centre line inside the body edge (design units), and the stretch of the flank it follows
    /// (parameter of the flank curve, from the tip end).
    public static let flankInset: Float = 7.4
    public static let flankWindow: (start: Float, end: Float) = (0.17, 0.35)

    /// Centre line of the flank tube of wing 0 on one side (`side` +1 right, -1 left), from the tip end toward the
    /// centre. In R coordinates.
    public static func flankTubePath(side: Float, samples: Int = 14) -> [P2] {
        let w = flankWindow
        let p0 = P2(30, -128), c = P2(60.6, -35), p2 = P2(125.85, 38.02)
        var out: [P2] = []
        var i: Int = 0
        while i < samples {
            let t: Float = w.start + (w.end - w.start) * Float(i) / Float(samples - 1)
            let u: Float = 1 - t
            let bx: Float = u * u * p0.x + 2 * u * t * c.x + t * t * p2.x
            let by: Float = u * u * p0.y + 2 * u * t * c.y + t * t * p2.y
            let tx: Float = 2 * u * (c.x - p0.x) + 2 * t * (p2.x - c.x)
            let ty: Float = 2 * u * (c.y - p0.y) + 2 * t * (p2.y - c.y)
            let l: Float = (tx * tx + ty * ty).squareRoot()
            // Outward normal of the right flank (y down): rotate the tangent toward +x / -y.
            let nx: Float = ty / l
            let ny: Float = -tx / l
            let qx: Float = bx - nx * flankInset
            let qy: Float = by - ny * flankInset
            out.append(point(side * qx, qy))
            i += 1
        }
        return out
    }

    /// Capsule outline (a stadium along a polyline) of half width `halfWidth`, with half-round ends.
    public static func pathCapsule(_ path: [P2], halfWidth: Float, capSteps: Int = 8) -> [P2] {
        var left: [P2] = []
        var right: [P2] = []
        let n: Int = path.count
        var i: Int = 0
        while i < n {
            let a: P2 = path[max(i - 1, 0)]
            let b: P2 = path[min(i + 1, n - 1)]
            let dx: Float = b.x - a.x
            let dy: Float = b.y - a.y
            let l: Float = max((dx * dx + dy * dy).squareRoot(), 1e-9)
            let nx: Float = -dy / l
            let ny: Float = dx / l
            left.append(P2(path[i].x + nx * halfWidth, path[i].y + ny * halfWidth))
            right.append(P2(path[i].x - nx * halfWidth, path[i].y - ny * halfWidth))
            i += 1
        }
        var out: [P2] = left
        // End cap: from the left side round to the right side about the last point.
        let last: P2 = path[n - 1]
        let before: P2 = path[n - 2]
        let endAngle: Float = atan2(last.y - before.y, last.x - before.x)
        var k: Int = 1
        while k < capSteps {
            let a: Float = endAngle + Float.pi / 2 - Float.pi * Float(k) / Float(capSteps)
            out.append(P2(last.x + halfWidth * cos(a), last.y + halfWidth * sin(a)))
            k += 1
        }
        out.append(contentsOf: right.reversed())
        let first: P2 = path[0]
        let after: P2 = path[1]
        let startAngle: Float = atan2(first.y - after.y, first.x - after.x)
        k = 1
        while k < capSteps {
            let a: Float = startAngle + Float.pi / 2 - Float.pi * Float(k) / Float(capSteps)
            out.append(P2(first.x + halfWidth * cos(a), first.y + halfWidth * sin(a)))
            k += 1
        }
        return out
    }

    /// Slot outline of the flank tube of wing 0 (see `flankTubePath`).
    public static func flankSlotOutline(side: Float) -> [P2] {
        pathCapsule(flankTubePath(side: side), halfWidth: tubeSlotHalfWidth)
    }

    /// Logo patch on wing 0: gold plate between the two base screws.
    public static let patchCentre: P2 = point(0, -92)
    public static let patchSize: P2 = P2(27 * unit, 11.6 * unit)
    public static let patchCorner: Float = 2.6 * unit
    public static let patchHeight: Float = 0.012
    public static let markDepth: Float = 0.006

    // MARK: Centre

    public static let wellRadius: Float = 56 * unit
    public static let ringInner: Float = 57 * unit
    public static let ringOuter: Float = 73 * unit
    public static let ringHeight: Float = 0.022
    public static let ringCutDepth: Float = 0.012
    public static let outerRaceInner: Float = 49.0 * unit
    public static let outerRaceOuter: Float = 56.0 * unit
    public static let cageInner: Float = 44.2 * unit
    public static let cageOuter: Float = 47.8 * unit
    public static let ballRingRadius: Float = 46 * unit
    public static let ballRadius: Float = 4.6 * unit
    public static let ballCount: Int = 12
    public static let innerRaceInner: Float = 35.5 * unit
    public static let innerRaceOuter: Float = 43.0 * unit
    public static let hubRadius: Float = 35.5 * unit
    /// Pocket radius round each ball in the cage (0.25 unit of clearance), and half thickness of the cage bars (about the
    /// mid plane). The bar is 3.6 units wide (centred on the ball ring), leaving 1.2 units of open through-slit each side.
    /// Its top edge, pockets included, has a small bevel (`cageBevelDrop` in z, `cageBevelInset` in plan) that catches a
    /// highlight line and makes each pocket read as a machined seat.
    public static let cagePocketRadius: Float = 4.85 * unit
    public static let cageHalfThickness: Float = 0.016
    public static let cageBevelDrop: Float = 0.004
    public static let cageBevelInset: Float = 0.0027
    /// The bearing is a through part: races, cage and balls are built as a half in each face's layout and meet at the mid
    /// plane (z = 0), where the balls' centres lie. Each race face toward the balls has a circular-arc raceway (radius
    /// `racewayRadius`, centred on the ball centre) that ends at the race land, a small bevel, a straight wall and a rounded
    /// shoulder up to the race top; the hub rim (dished down by `hubDishDrop`) stands above the inner race.
    public static let ballCentreZ: Float = 0
    public static let raceTopZ: Float = 0.055
    public static let raceShoulder: Float = 0.014
    public static let racewayRadius: Float = 4.8 * unit
    public static let raceEdgeBreak: Float = 0.0025

    /// The gap-facing side of a race as (offset into the race material from the land radius, height) samples from the
    /// raceway bottom (z = 0, on the ball's equator) up to the race top. The same list serves both races: the outer race
    /// adds the offset to its inner edge, the inner race subtracts it from its outer edge (the lands are symmetric about
    /// the ball ring). The arc keeps smooth normals; the bevel and shoulder catch light.
    public static func raceGapFace() -> [(Float, Float)] {
        var out: [(Float, Float)] = []
        let pr: Float = racewayRadius
        let land: Float = outerRaceInner - ballRingRadius
        let brk: Float = raceEdgeBreak
        // The arc runs from the bottom (theta 0, offset pr - land) to where its offset falls to the bevel width.
        let cosEnd: Float = (land + brk) / pr
        let thEnd: Float = acos(min(max(cosEnd, -1), 1))
        let steps: Int = 20
        var i: Int = 0
        while i <= steps {
            let th: Float = thEnd * Float(i) / Float(steps)
            out.append((pr * cos(th) - land, pr * sin(th)))
            i += 1
        }
        // Bevel from the arc up to the land wall.
        let zLand: Float = (pr * pr - land * land).squareRoot()
        out.append((0, zLand + brk))
        let zf0: Float = raceTopZ - raceShoulder
        out.append((0, zf0))
        let fs: Int = 8
        i = 1
        while i <= fs {
            let th: Float = Float.pi / 2 * Float(i) / Float(fs)
            out.append((raceShoulder * (1 - cos(th)), zf0 + raceShoulder * sin(th)))
            i += 1
        }
        return out
    }
    public static let hubRimZ: Float = 0.112
    public static let hubDishDrop: Float = 0.012
    /// Sapphire-style crystal over the bearing: height of its top face, thickness and rim bevel. It spans the well (to the
    /// ring's inner edge) and passes over the hub.
    public static let crystalZ: Float = 0.151
    public static let crystalThickness: Float = 0.010
    public static let crystalBevel: Float = 0.006

    // MARK: Ring features: spanner slots, lettering arcs, fluted zone
    //
    // The ring carries, on each face, two spanner slots at 3 and 9 o'clock (wing 0 up): square-ended, open through the ring's
    // outer edge, with a wide polished chamfer round the edge and a flat milled floor in the body below the ring. Between
    // them, an upper arc (12 o'clock) and a lower arc (6 o'clock) carry the lettering and, on the front face's lower arc, a
    // fluted zone either side of a plain number panel.

    /// The notch features sit at 3 and 9 o'clock. `notchStartClockwiseDegrees` is the first one's angle clockwise from the
    /// wing-0 axis (wing 0 points up), so 90 puts the pair at 3 and 9 o'clock. Angles are radians, counter-clockwise from +x.
    public static let notchCount: Int = 2
    public static let notchStartClockwiseDegrees: Float = 90
    public static let notchAngles: [Float] = {
        var out: [Float] = []
        var k: Int = 0
        while k < notchCount {
            let step: Float = 360 / Float(notchCount)
            let clockwiseDegrees: Float = notchStartClockwiseDegrees + step * Float(k)
            let math: Float = (90 - clockwiseDegrees) * Float.pi / 180
            out.append(math)
            k += 1
        }
        return out
    }()
    /// The spanner slot: 6 units wide (the angular width at the ring's mid radius; its shoulders are radial, so the opening
    /// is a hair wider at the outer edge) and 7 deep, from `slotInnerRadius` out through the ring's outer edge (chamfer
    /// included) and on into a flat pocket in the body below the ring that reaches `notchOverreach` past the ring's outer
    /// wall. The inner end is square.
    public static let slotWidth: Float = 6 * unit
    public static let slotInnerRadius: Float = 66 * unit
    public static let slotOuterRadius: Float = ringOuter
    public static let notchOverreach: Float = 1 * unit
    public static let notchPocketOuterRadius: Float = ringOuter + notchOverreach
    /// Depth of the slot's milled floor below the body face (the ring stands `ringHeight` above the face, so the walls are
    /// `ringHeight + notchPocketDepth` tall), and the polished 45 degree chamfer on the slot's top edge (1 unit wide).
    public static let notchPocketDepth: Float = 0.030
    public static let notchChamfer: Float = 1 * unit
    /// Width of the darker band along the floor's edges (a baked contact shade: the scene has no self-shadowing).
    public static let notchFloorShadeWidth: Float = 0.45 * unit

    // Ring strip coordinates. The engraved ring is meshed on a strip (u along the circumference at the ring's mid radius,
    // clockwise; v radially from the inner edge). The strip's seam sits `ringSeamOffset` clockwise of the 3 o'clock notch, in
    // plain metal clear of every feature, so no lettering, notch or flute crosses it.
    public static let ringSeamOffset: Float = 5 * unit
    public static var ringMidRadius: Float { (ringInner + ringOuter) * 0.5 }
    public static var ringCircumference: Float { 2 * Float.pi * ringMidRadius }
    /// Angle (radians, counter-clockwise from +x) at strip position 0.
    public static var ringStripOriginAngle: Float { -ringSeamOffset / ringMidRadius }
    /// Strip position of a world angle, in [0, circumference).
    public static func ringU(angle: Float) -> Float {
        let c: Float = ringCircumference
        var u: Float = (ringStripOriginAngle - angle) * ringMidRadius
        while u < 0 { u += c }
        while u >= c { u -= c }
        return u
    }
    /// World angle of a strip position.
    public static func ringAngle(u: Float) -> Float { ringStripOriginAngle - u / ringMidRadius }

    /// Half extent along the circumference (in strip units) of a notch feature's top outline (chamfer included).
    public static var notchFeatureHalfSpan: Float { slotWidth * 0.5 + notchChamfer }

    /// Lettering: one cap height on every arc, one fixed tracking value added to the natural side bearings, the band centred
    /// radially in the ring. Along the circumference every arc keeps `ringTextClearance` of plain ring between its last
    /// letter and the nearest notch feature. Stroke widths are properties of `EngravingFont` (in cap heights).
    public static let ringTextCapHeight: Float = 6 * unit
    public static let ringTextTracking: Float = 0.28 * ringTextCapHeight
    public static let ringTextBaselineV: Float = ((ringOuter - ringInner) - ringTextCapHeight) * 0.5
    public static let ringTextClearance: Float = 6 * unit
    /// Plain metal either side of the lower-arc number on the front face's flute panel.
    public static let fluteTextMargin: Float = 3 * unit

    public enum RingFace { case front, back }
    public struct RingArcSpec: Equatable {
        public let text: String
        /// False: the upper arc (12 o'clock, letter tops outward, reading clockwise). True: the lower arc (6 o'clock,
        /// letter tops toward the hub, reading left to right, so upright when wing 0 is up).
        public let lower: Bool
    }
    /// The lettering of a face, laid out in front layout (the back face is turned like the rest of that face).
    public static func ringArcs(face: RingFace) -> [RingArcSpec] {
        switch face {
        case .front:
            return [RingArcSpec(text: "KEEP YOUR OWN TIME", lower: false), RingArcSpec(text: "No 001", lower: true)]
        case .back:
            return [RingArcSpec(text: "THE VISUALIZER CO.", lower: false), RingArcSpec(text: "ADJUSTED TO THE BEAT", lower: true)]
        }
    }
    /// Strip position of an arc's centre (12 o'clock for the upper arc, 6 o'clock for the lower).
    public static func ringArcCentreU(lower: Bool) -> Float {
        ringU(angle: lower ? -Float.pi / 2 : Float.pi / 2)
    }

    /// The fluted zones on the front face's lower arc: fine radial V grooves cut into the ring's top in a radial band centred
    /// in the ring (plain metal inside and outside it), one either side of a plain panel at 6 o'clock that carries the
    /// number. Each zone's outer end stops `fluteEndClearance` short of the nearest notch feature and its inner end
    /// `fluteTextMargin` short of the number, with clean flat ends. Strip coordinates; ridges lie at `u0 + k * pitch`,
    /// valleys halfway.
    public struct FluteZone {
        public let u0: Float
        public let u1: Float
        public let v0: Float
        public let v1: Float
        public let pitch: Float
        public let depth: Float
        public let count: Int
    }
    public static let fluteInnerRadius: Float = 60 * unit
    public static let fluteOuterRadius: Float = 70 * unit
    public static let flutePitch: Float = 3 * unit
    public static let fluteDepth: Float = 0.005
    public static let fluteEndClearance: Float = 10 * unit
    /// The flute ridges stand this far below the ring's top (a hairline step that keeps the zone's border a clean wall).
    public static let fluteRidgeDrop: Float = 0.0004
    /// Half length of the plain panel at 6 o'clock: half the number's ink length plus the margin.
    public static func lowerPanelHalfLength() -> Float {
        var half: Float = 0
        for spec in ringArcs(face: .front) where spec.lower {
            half = max(half, RingTextLayout.span(of: spec.text, capHeight: ringTextCapHeight, tracking: ringTextTracking) * 0.5)
        }
        return half + fluteTextMargin
    }
    public static func fluteZones() -> [FluteZone] {
        let quarter: Float = ringCircumference * 0.25
        let centre: Float = ringArcCentreU(lower: true)
        let panel: Float = lowerPanelHalfLength()
        let room: Float = quarter - notchFeatureHalfSpan - fluteEndClearance - panel
        let count: Int = Int((room / flutePitch).rounded(.down))
        let length: Float = Float(count) * flutePitch
        let v0: Float = fluteInnerRadius - ringInner
        let v1: Float = fluteOuterRadius - ringInner
        // u grows clockwise; at 6 o'clock the lower u side is toward the 3 o'clock notch... either way the pair is symmetric.
        let loEnd: Float = centre - panel
        let hiStart: Float = centre + panel
        let a = FluteZone(u0: loEnd - length, u1: loEnd, v0: v0, v1: v1, pitch: flutePitch, depth: fluteDepth, count: count)
        let b = FluteZone(u0: hiStart, u1: hiStart + length, v0: v0, v1: v1, pitch: flutePitch, depth: fluteDepth, count: count)
        return [a, b]
    }

    /// The slot pocket's outline in the body plane for the notch at `angle`: an annular sector from `slotInnerRadius` to
    /// `notchPocketOuterRadius`, radial shoulders at +-width/2 (at the ring's mid radius). Closed, not repeating the first
    /// point; both arcs sampled with `arcSegments` segments. `inset` pulls every side in by that distance (the floor's
    /// contact-shade band).
    public static func notchPocketLoop(angle: Float, arcSegments: Int, inset: Float = 0) -> [P2] {
        let rMid: Float = ringMidRadius
        let half: Float = (slotWidth * 0.5 - inset) / rMid
        let rIn: Float = slotInnerRadius + inset
        let rOut: Float = notchPocketOuterRadius - inset
        var out: [P2] = []
        var i: Int = 0
        while i <= arcSegments {
            let t: Float = Float(i) / Float(arcSegments)
            let th: Float = angle - half + 2 * half * t
            out.append(P2(rIn * cos(th), rIn * sin(th)))
            i += 1
        }
        i = arcSegments
        while i >= 0 {
            let t: Float = Float(i) / Float(arcSegments)
            let th: Float = angle - half + 2 * half * t
            out.append(P2(rOut * cos(th), rOut * sin(th)))
            i -= 1
        }
        return out
    }

    // MARK: Helpers

    /// The wing-0 point rotated into wing `k`.
    public static func inWing(_ p: P2, _ k: Int) -> P2 {
        let a: Float = wingAngle(k)
        let c: Float = cos(a)
        let s: Float = sin(a)
        return P2(c * p.x - s * p.y, s * p.x + c * p.y)
    }
    /// Mirror in x (the back face of the body).
    public static func mirrored(_ p: P2) -> P2 { P2(-p.x, p.y) }
}
