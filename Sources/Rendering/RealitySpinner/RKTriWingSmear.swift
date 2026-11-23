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
// Spin-blur overlay images of the Tri-wing, baked from the Core smear profile: radial images over the planar [-1, 1]
// square (the overlay annulus uses the same planar uv), one colour image per metal.
import CoreGraphics
import Foundation
import simd
import MacVisualizerCore

struct TWSmearImages {
    var profiles: [TriWingSmear]   // front, back: the colour images are built per metal combination on demand
    var opacity: CGImage
    var glowEmissive: CGImage
    var glowOpacity: CGImage
    /// Per wing, the light ring's opacity mask (neutral; a material tints it with the wing's colour): used when the lights follow the palette.
    var glowWingOpacity: [CGImage]
    /// Vertical alpha profile of a shell wall (soft at the top and bottom rims) and of the side band of light (full at the
    /// waist, fading toward its top and bottom edge), both a 1 x 64 strip read along v.
    var shellFade: CGImage
    var bandFade: CGImage
}

/// A 4 x 64 strip whose alpha follows `value(v)`, v = 0 ... 1 down the strip.
func twVerticalStrip(_ value: (Float) -> Float) -> CGImage {
    let w: Int = 4
    let h: Int = 64
    var px = [UInt8](repeating: 255, count: w * h * 4)
    var y: Int = 0
    while y < h {
        let v: Float = (Float(y) + 0.5) / Float(h)
        let a: UInt8 = rkClampByte(value(v) * 255 + 0.5)
        var x: Int = 0
        while x < w {
            let i: Int = (y * w + x) * 4
            px[i] = a; px[i + 1] = a; px[i + 2] = a; px[i + 3] = a
            x += 1
        }
        y += 1
    }
    return rgbaImageStraight(w, h, px)
}

/// Linear colour of each smear class for the body, plate and boss metal colours (kept in step with `makeTWMaterial`).
func twSmearClassColors(body: V3, plate: V3, boss: V3) -> [V3] {
    var out: [V3] = []
    out.append(body * 0.62)                  // body
    out.append(plate * 0.78)                 // plate
    out.append(V3(0.95, 0.70, 0.20))         // gold
    out.append(V3(0.04, 0.16, 0.70))         // jewel (mean of the painted dome)
    out.append(V3(0.03, 0.14, 0.75))         // screw
    out.append(V3(0.86, 0.87, 0.89))         // ring
    out.append(V3(0.012, 0.012, 0.014))      // engraving
    out.append(V3(0.82, 0.83, 0.85))         // bearing steel
    out.append(V3(0.02, 0.02, 0.024))        // dark
    out.append(boss * 0.85)                  // boss top ring
    return out
}

/// A radial image over the planar [-1, 1] square: pixel (x, y) takes `table[Int(r * n)]` with r its distance from the centre.
func twRadialImage(table: [V4], size: Int, straight: Bool) -> CGImage {
    let n: Int = table.count
    let sizeF: Float = Float(size)
    var px = [UInt8](repeating: 255, count: size * size * 4)
    px.withUnsafeMutableBufferPointer { (buf: inout UnsafeMutableBufferPointer<UInt8>) -> Void in
        let base: UnsafeMutablePointer<UInt8> = buf.baseAddress!
        let lookup: [V4] = table
        @_optimize(speed)
        func row(_ y: Int) {
            var x: Int = 0
            while x < size {
                let X: Float = ((Float(x) + 0.5) / sizeF - 0.5) * 2
                let Y: Float = ((Float(y) + 0.5) / sizeF - 0.5) * 2
                let r: Float = (X * X + Y * Y).squareRoot()
                let idx: Int = rkMinInt(n - 1, Int(r * Float(n)))
                let v: V4 = lookup[idx]
                let i: Int = (y * size + x) * 4
                base[i] = rkClampByte(v.x * 255 + 0.5)
                base[i + 1] = rkClampByte(v.y * 255 + 0.5)
                base[i + 2] = rkClampByte(v.z * 255 + 0.5)
                base[i + 3] = rkClampByte(v.w * 255 + 0.5)
                x += 1
            }
        }
        DispatchQueue.concurrentPerform(iterations: size, execute: row)
    }
    return straight ? rgbaImageStraight(size, size, px) : rgbaImage(size, size, px)
}

/// The smeared body's colour image for one face and one body / plate / boss metal combination.
func makeTWSmearColorImage(profile: TriWingSmear, body: V3, plate: V3, boss: V3, size: Int = 1024) -> CGImage {
    let cc: [V3] = twSmearClassColors(body: body, plate: plate, boss: boss)
    var table: [V4] = []
    for i in 0..<profile.radii {
        let cov: Float = profile.coverage[i]
        var sum = V3(0, 0, 0)
        for k in 0..<TriWingSmear.classCount { sum += cc[k] * profile.classes[i][k] }
        let avg: V3 = cov > 1e-4 ? sum / cov : V3(0.1, 0.1, 0.1)
        table.append(V4(srgbEncode(min(avg.x, 1)), srgbEncode(min(avg.y, 1)), srgbEncode(min(avg.z, 1)), 1))
    }
    return twRadialImage(table: table, size: size, straight: false)
}

/// `faces` holds the front and back profiles (they differ only in the ring's lettering share); opacity and glow come from the
/// first. The colour images are not built here: they depend on the body, plate and boss metals (`makeTWSmearColorImage`).
func makeTWSmearImages(faces: [TriWingSmear], size: Int = 1024) -> TWSmearImages {
    let profile: TriWingSmear = faces[0]
    let n: Int = profile.radii
    func radialImage(_ value: (Int) -> V4, straight: Bool) -> CGImage {
        var table: [V4] = []
        for i in 0..<n { table.append(value(i)) }
        return twRadialImage(table: table, size: size, straight: straight)
    }
    let opacity: CGImage = radialImage({ (i: Int) -> V4 in
        // The swept wing zone's opacity curve: lifted coverage with a smooth gate at the tip (no hard circular edge).
        let c: Float = TriWingSwept.zoneOpacity(coverage: min(profile.coverage[i], 1))
        return V4(c, c, c, c)
    }, straight: true)
    let ring: TriWingSmear.GlowRing = profile.glowRing()
    let glowEmissive: CGImage = radialImage({ (i: Int) -> V4 in
        let c: V3 = ring.colour[i]
        return V4(srgbEncode(c.x), srgbEncode(c.y), srgbEncode(c.z), 1)
    }, straight: false)
    let glowOpacity: CGImage = radialImage({ (i: Int) -> V4 in
        let g: Float = ring.opacity[i]
        return V4(g, g, g, g)
    }, straight: true)
    var glowWingOpacity: [CGImage] = []
    for table in profile.glowRingWings() {
        glowWingOpacity.append(radialImage({ (i: Int) -> V4 in
            let g: Float = table[i]
            return V4(g, g, g, g)
        }, straight: true))
    }
    let shellFade: CGImage = twVerticalStrip({ (v: Float) -> Float in
        let edge: Float = min(v, 1 - v) / 0.12
        let k: Float = min(max(edge, 0), 1)
        return 0.60 + 0.40 * k * k * (3 - 2 * k)
    })
    let bandFade: CGImage = twVerticalStrip({ (flipped: Float) -> Float in
        let v: Float = 1 - flipped   // the renderer reads v from the bottom of the strip
        let k: Float = min(max((v - 0.35) / 0.65, 0), 1)
        return 1 - k * k * (3 - 2 * k)
    })
    return TWSmearImages(profiles: faces, opacity: opacity, glowEmissive: glowEmissive, glowOpacity: glowOpacity, glowWingOpacity: glowWingOpacity, shellFade: shellFade, bandFade: bandFade)
}
