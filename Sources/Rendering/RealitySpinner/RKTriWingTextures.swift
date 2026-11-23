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
// Procedural textures of the Tri-wing: fine radial brushing for the body faces and the same brushing with a curved
// ray pattern for the wing pads. Planar uv over the [-1, 1] square (x * 0.5 + 0.5). CPU only, safe off the main thread.
import CoreGraphics
import Foundation
import simd
import MacVisualizerCore

struct TWImageSet { var color: CGImage; var rough: CGImage; var normal: CGImage }
struct TWHubImages { var color: CGImage; var rough: CGImage; var normal: CGImage }
struct TWImages { var body: TWImageSet; var pad: TWImageSet; var hub: TWHubImages; var ramp: CGImage; var slotWall: CGImage; var glint: CGImage; var jewel: CGImage; var tubeEdge: CGImage; var tubeEdgeOpacity: CGImage; var turned: TWImageSet }

@_optimize(speed)
private func twHair(_ a: Float) -> Float {
    let x1: Float = a * 900
    let x2: Float = a * 2100 + 17
    let g1: Float = vnoise(x1, 11) - 0.5
    let g2: Float = vnoise(x2, 23) - 0.5
    return g1 + 0.5 * g2
}

/// Plate ray finish: even, fine rays radiating from the centre (a gentle curl with radius), a smooth sine profile (no hard
/// edges, so no noisy scratches). Returns 0...1.
@_optimize(speed)
private func twRay(_ turns: Float, _ radius: Float, _ wedges: Float) -> Float {
    let drift: Float = 0.010 * (radius - 0.5)
    let phase: Float = (turns + drift) * wedges
    return 0.5 + 0.5 * sin(phase * 2 * Float.pi)
}

/// Builds one image set. `rays` adds the pad's curved ray pattern on top of the brushing.
func makeTWImageSet(size: Int, rays: Bool) -> TWImageSet {
    let count: Int = size * size * 4
    var color = [UInt8](repeating: 255, count: count)
    var rough = [UInt8](repeating: 255, count: count)
    var normal = [UInt8](repeating: 255, count: count)
    let twoPi: Float = 2 * Float.pi
    let sizeF: Float = Float(size)
    let rayWedges: Float = 180
    let rayLevel: Float = 0.94
    let rayAmp: Float = 0.05
    let rayRough: Float = 0.40
    let rayRoughAmp: Float = 0.07
    color.withUnsafeMutableBufferPointer { (cp: inout UnsafeMutableBufferPointer<UInt8>) -> Void in
    rough.withUnsafeMutableBufferPointer { (rp: inout UnsafeMutableBufferPointer<UInt8>) -> Void in
    normal.withUnsafeMutableBufferPointer { (np: inout UnsafeMutableBufferPointer<UInt8>) -> Void in
        let cBase: UnsafeMutablePointer<UInt8> = cp.baseAddress!
        let rBase: UnsafeMutablePointer<UInt8> = rp.baseAddress!
        let nBase: UnsafeMutablePointer<UInt8> = np.baseAddress!
        @_optimize(speed)
        func row(_ y: Int) {
            var x: Int = 0
            while x < size {
                let u: Float = (Float(x) + 0.5) / sizeF
                let v: Float = (Float(y) + 0.5) / sizeF
                let px: Float = (u - 0.5) * 2
                let py: Float = (v - 0.5) * 2
                let radius: Float = (px * px + py * py).squareRoot()
                let angle: Float = atan2(py, px)
                let turns: Float = angle / twoPi + 0.5
                let hair: Float = twHair(turns)
                let hairNext: Float = twHair(turns + 0.0004)
                // Body: calm satin, very low contrast. Pad: brighter and finer with soft rays, still low contrast.
                var level: Float = 0.95 + 0.035 * hair
                var rgh: Float = 0.46 + 0.04 * hair
                var tangential: Float = (hairNext - hair) * 3
                if rays {
                    // Calm sunburst: low contrast in tone and roughness, almost no normal perturbation (a strong tangential
                    // normal sends the reflection into the dark studio at some tilts, which read as black scratches).
                    let ray: Float = twRay(turns, radius, rayWedges)
                    level = (rayLevel - rayAmp * 0.5) + rayAmp * ray + 0.008 * hair
                    rgh = (rayRough - rayRoughAmp * 0.5) + rayRoughAmp * ray + 0.01 * hair
                    tangential = (hairNext - hair) * 0.6
                }
                let tx: Float = -py / max(radius, 1e-4)
                let ty: Float = px / max(radius, 1e-4)
                let strength: Float = rays ? 0.05 : 0.12
                var nx: Float = tx * tangential * strength
                var ny: Float = ty * tangential * strength
                let nz: Float = 1
                let inv: Float = 1 / (nx * nx + ny * ny + nz * nz).squareRoot()
                nx *= inv
                ny *= inv
                let nzn: Float = nz * inv
                let i: Int = (y * size + x) * 4
                let lv: UInt8 = rkClampByte(srgbEncode(min(max(level, 0), 1)) * 255 + 0.5)
                cBase[i] = lv; cBase[i + 1] = lv; cBase[i + 2] = lv
                let rv: UInt8 = rkClampByte(min(max(rgh, 0.05), 1) * 255 + 0.5)
                rBase[i] = rv; rBase[i + 1] = rv; rBase[i + 2] = rv
                nBase[i] = rkClampByte((nx * 0.5 + 0.5) * 255 + 0.5)
                nBase[i + 1] = rkClampByte((ny * 0.5 + 0.5) * 255 + 0.5)
                nBase[i + 2] = rkClampByte((nzn * 0.5 + 0.5) * 255 + 0.5)
                x += 1
            }
        }
        DispatchQueue.concurrentPerform(iterations: size, execute: row)
    } } }
    return TWImageSet(color: rgbaImage(size, size, color), rough: rgbaImage(size, size, rough), normal: rgbaImage(size, size, normal))
}

/// Linear opacity ramp for the glow overlays: the texture coordinate u carries the overlay's intensity (0...1) and the
/// opacity equals it (straight alpha). One tiny texture serves the slot walls, floors and pad tints.
func makeTWGlowRampImage(width: Int = 256) -> CGImage {
    let height: Int = 4
    var px = [UInt8](repeating: 255, count: width * height * 4)
    var y: Int = 0
    while y < height {
        var x: Int = 0
        while x < width {
            let u: Float = (Float(x) + 0.5) / Float(width)
            let b: UInt8 = rkClampByte(u * 255 + 0.5)
            let i: Int = (y * width + x) * 4
            px[i] = b; px[i + 1] = b; px[i + 2] = b; px[i + 3] = b
            x += 1
        }
        y += 1
    }
    return rgbaImageStraight(width, height, px)
}

/// Emissive strength up a slot wall (v = 0 at the lip, 1 at the floor): `twSlotWallIntensity` of the height above the floor.
func makeTWSlotWallImage(height: Int = 64) -> CGImage {
    let width: Int = 4
    var px = [UInt8](repeating: 255, count: width * height * 4)
    var y: Int = 0
    while y < height {
        let v: Float = (Float(y) + 0.5) / Float(height)
        let level: Float = twSlotWallIntensity(1 - v)
        let b: UInt8 = rkClampByte(level * 255 + 0.5)
        var x: Int = 0
        while x < width {
            let i: Int = (y * width + x) * 4
            px[i] = b; px[i + 1] = b; px[i + 2] = b; px[i + 3] = 255
            x += 1
        }
        y += 1
    }
    return rgbaImage(width, height, px)
}

/// Brightness around a glass tube's cross-section (uv.x = angle round the tube, 0 on the side facing the viewer): dim
/// across the face, bright toward the two silhouette edges, like a glass rod seen end-on from above.
func twTubeEdgeValue(_ u: Float) -> Float {
    let s: Float = abs(sin(u * 2 * Float.pi))
    return 0.10 + 0.90 * s * s
}

func makeTWTubeEdgeImage(opacity: Bool, width: Int = 64) -> CGImage {
    let height: Int = 4
    var px = [UInt8](repeating: 255, count: width * height * 4)
    var y: Int = 0
    while y < height {
        var x: Int = 0
        while x < width {
            let u: Float = (Float(x) + 0.5) / Float(width)
            let e: Float = twTubeEdgeValue(u)
            let value: Float = opacity ? 0.12 + 0.88 * e : e
            let b: UInt8 = rkClampByte(value * 255 + 0.5)
            let i: Int = (y * width + x) * 4
            px[i] = b; px[i + 1] = b; px[i + 2] = b; px[i + 3] = opacity ? b : 255
            x += 1
        }
        y += 1
    }
    return opacity ? rgbaImageStraight(width, height, px) : rgbaImage(width, height, px)
}

/// Signed distance (negative inside) to a square of half side `a` with corner radius `r`, centred on the origin.
func twRoundedBoxSDF(_ x: Float, _ y: Float, _ a: Float, _ r: Float) -> Float {
    let qx: Float = abs(x) - (a - r)
    let qy: Float = abs(y) - (a - r)
    let ox: Float = max(qx, 0)
    let oy: Float = max(qy, 0)
    let outside: Float = (ox * ox + oy * oy).squareRoot()
    let inside: Float = min(max(qx, qy), 0)
    return outside + inside - r
}

/// Window ghost for the crystal: a soft rounded four-pane window (a mullion cross between the panes), straight alpha.
/// The texture spans 1.7 crystal diameters, so the window (half side 0.075 of the texture, 0.13 diameters) is small
/// relative to the glass and can slide (via the uv offset) without sampling the clamped edge.
func makeTWGlintImage(size: Int = 512) -> CGImage {
    var px = [UInt8](repeating: 255, count: size * size * 4)
    let half: Float = 0.075
    let corner: Float = 0.014
    let bar: Float = 0.0045
    let soft: Float = 0.006
    var y: Int = 0
    while y < size {
        var x: Int = 0
        while x < size {
            let u: Float = (Float(x) + 0.5) / Float(size) - 0.5
            let v: Float = (Float(y) + 0.5) / Float(size) - 0.5
            let d: Float = twRoundedBoxSDF(u, v, half, corner)
            let edge: Float = 1 - ss(-soft, soft, d)
            let mx: Float = ss(bar - soft, bar + soft, abs(u))
            let my: Float = ss(bar - soft, bar + soft, abs(v))
            let panes: Float = mx * my
            // Panes are brighter toward the window's centre side, so it reads as a soft reflection rather than a flat sticker.
            let falloff: Float = 1 - 0.35 * min((u * u + v * v) / (half * half), 1)
            let a: Float = edge * (0.25 + 0.75 * panes) * falloff
            let b: UInt8 = rkClampByte(a * 255 + 0.5)
            let i: Int = (y * size + x) * 4
            px[i] = b; px[i + 1] = b; px[i + 2] = b; px[i + 3] = b
            x += 1
        }
        y += 1
    }
    return rgbaImageStraight(size, size, px)
}

/// Painted depth of the cap jewel as a radial gradient (rows = radial fraction from the centre, uv.y): lighter and clearer
/// toward the centre, darker and more saturated toward the rim. Rotationally symmetric, so it does not move with the spin.
func makeTWJewelImage(height: Int = 64) -> CGImage {
    let width: Int = 4
    var px = [UInt8](repeating: 255, count: width * height * 4)
    let centre: (Float, Float, Float) = (0.30, 0.60, 1.00)
    let rim: (Float, Float, Float) = (0.01, 0.06, 0.60)
    var y: Int = 0
    while y < height {
        let t: Float = 1 - (Float(y) + 0.5) / Float(height)   // image row 0 is the rim side
        let k: Float = ss(0.10, 0.95, t)
        let r: Float = centre.0 + (rim.0 - centre.0) * k
        let g: Float = centre.1 + (rim.1 - centre.1) * k
        let b: Float = centre.2 + (rim.2 - centre.2) * k
        var x: Int = 0
        while x < width {
            let i: Int = (y * width + x) * 4
            px[i] = rkClampByte(r * 255 + 0.5); px[i + 1] = rkClampByte(g * 255 + 0.5); px[i + 2] = rkClampByte(b * 255 + 0.5); px[i + 3] = 255
            x += 1
        }
        y += 1
    }
    return rgbaImage(width, height, px)
}

/// Turned finish of the plain hub as a radial strip (rows = radius from the centre to the chamfer, uv.y = radius fraction):
/// fine concentric turning expressed as bands of roughness and a little tone, so it has no geometry to alias and the
/// texture's mip levels average it smoothly at small sizes.
func makeTWHubImages(height: Int = 2048) -> TWHubImages {
    let width: Int = 4
    let pitchR: Float = 0.0140       // ring pitch in puck radii
    let spanR: Float = TriWing.hubRadius - 0.010      // radius covered by the strip
    let roughMid: Float = 0.32
    let roughAmp: Float = 0.10
    let toneAmp: Float = 0.22
    var cpx = [UInt8](repeating: 255, count: width * height * 4)
    var rpx = [UInt8](repeating: 255, count: width * height * 4)
    var npx = [UInt8](repeating: 255, count: width * height * 4)
    let normAmp: Float = 0.30
    var y: Int = 0
    while y < height {
        let r: Float = (Float(y) + 0.5) / Float(height) * spanR
        let ph: Float = r / pitchR
        let wave: Float = 0.5 + 0.5 * sin(ph * 2 * Float.pi)
        // Each ring also differs a little from its neighbours (cutter chatter), so the pattern is not a pure sine.
        let ringId: Float = floor(ph)
        let jitter: Float = vnoise(ringId, 71) - 0.5
        let rough: Float = roughMid + roughAmp * (wave - 0.5) + 0.04 * jitter
        let tone: Float = 1.0 - toneAmp * (wave - 0.5) + 0.03 * jitter
        let lv: UInt8 = rkClampByte(srgbEncode(min(max(tone, 0), 1)) * 255 + 0.5)
        let rv: UInt8 = rkClampByte(min(max(rough, 0.05), 1) * 255 + 0.5)
        // Ring slope (the turning's V profile, as a smooth sine): the normal tilts across each ring, so the rings catch the
        // light like geometry would, while the texture's mip levels average the tilt away at small sizes (no moire).
        let slope: Float = normAmp * cos(ph * 2 * Float.pi) + 0.05 * jitter
        let inv: Float = 1 / (slope * slope + 1).squareRoot()
        let nyb: UInt8 = rkClampByte((slope * inv * 0.5 + 0.5) * 255 + 0.5)
        let nzb: UInt8 = rkClampByte((inv * 0.5 + 0.5) * 255 + 0.5)
        var x: Int = 0
        while x < width {
            let i: Int = (y * width + x) * 4
            cpx[i] = lv; cpx[i + 1] = lv; cpx[i + 2] = lv
            rpx[i] = rv; rpx[i + 1] = rv; rpx[i + 2] = rv
            npx[i] = 128; npx[i + 1] = nyb; npx[i + 2] = nzb
            x += 1
        }
        y += 1
    }
    return TWHubImages(color: rgbaImage(width, height, cpx), rough: rgbaImage(width, height, rpx), normal: rgbaImage(width, height, npx))
}

func makeTWImages(size: Int = 1024) -> TWImages {
    TWImages(body: makeTWImageSet(size: size, rays: false), pad: makeTWImageSet(size: size, rays: true), hub: makeTWHubImages(), ramp: makeTWGlowRampImage(), slotWall: makeTWSlotWallImage(), glint: makeTWGlintImage(), jewel: makeTWJewelImage(),
             tubeEdge: makeTWTubeEdgeImage(opacity: false), tubeEdgeOpacity: makeTWTubeEdgeImage(opacity: true), turned: makeTWTurnedImages())
}

/// Fine horizontal turning for the side wall's band floor: even lathe lines, a smooth profile that varies only with the texture
/// coordinate v (so the lines run along the outline). `twTurnedCycles` cycles over v in 0...1; the wall maps v = z * `twWallUVPerR`.
let twTurnedCycles: Int = 27
func makeTWTurnedImages() -> TWImageSet {
    let w: Int = 4
    let h: Int = 256
    var color = [UInt8](repeating: 255, count: w * h * 4)
    var rough = [UInt8](repeating: 255, count: w * h * 4)
    var normal = [UInt8](repeating: 255, count: w * h * 4)
    var y: Int = 0
    while y < h {
        let phase: Float = (Float(y) + 0.5) / Float(h) * Float(twTurnedCycles) * 2 * Float.pi
        let line: Float = sin(phase)
        let slope: Float = cos(phase)
        let level: Float = 0.90 + 0.09 * line
        let rgh: Float = 0.50 + 0.12 * line
        var ny: Float = slope * 0.22
        let nz: Float = 1
        let inv: Float = 1 / (ny * ny + nz * nz).squareRoot()
        ny *= inv
        let nzn: Float = nz * inv
        var x: Int = 0
        while x < w {
            let i: Int = (y * w + x) * 4
            let lv: UInt8 = rkClampByte(srgbEncode(min(max(level, 0), 1)) * 255 + 0.5)
            color[i] = lv; color[i + 1] = lv; color[i + 2] = lv
            let rv: UInt8 = rkClampByte(min(max(rgh, 0.05), 1) * 255 + 0.5)
            rough[i] = rv; rough[i + 1] = rv; rough[i + 2] = rv
            normal[i] = 128; normal[i + 1] = rkClampByte((ny * 0.5 + 0.5) * 255 + 0.5); normal[i + 2] = rkClampByte((nzn * 0.5 + 0.5) * 255 + 0.5)
            x += 1
        }
        y += 1
    }
    return TWImageSet(color: rgbaImage(w, h, color), rough: rgbaImage(w, h, rough), normal: rgbaImage(w, h, normal))
}
