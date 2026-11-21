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
// CPU-only procedural textures and environment image.
import CoreGraphics
import Foundation
import simd


@_optimize(speed)
func hash1(_ x: Int, _ seed: Int) -> Float {
    var h = UInt64(bitPattern: Int64(x &* 374761393 &+ seed &* 668265263))
    h = (h ^ (h >> 13)) &* 1274126177
    h ^= h >> 16
    return Float(h & 0xFFFFFF) / Float(0xFFFFFF)
}
@_optimize(speed)
func vnoise(_ x: Float, _ seed: Int) -> Float {
    let i: Int = Int(floor(x))
    let f: Float = x - floor(x)
    let a: Float = hash1(i, seed)
    let b: Float = hash1(i + 1, seed)
    let smooth: Float = 3 - 2 * f
    let s: Float = f * f * smooth
    return a + (b - a) * s
}

@_optimize(speed)
func rgbaImage(_ w: Int, _ h: Int, _ px: [UInt8]) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let prov = CGDataProvider(data: Data(px) as CFData)!
    return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: cs,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: prov,
                   decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

/// RGBA image with straight (non-premultiplied) alpha; for opacity textures.
@_optimize(speed)
func rgbaImageStraight(_ w: Int, _ h: Int, _ px: [UInt8]) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: cs,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: CGDataProvider(data: Data(px) as CFData)!,
                   decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

/// Soft-ended ribbon textures for the blur arcs: per-colour emissive and a shared alpha profile (u along the arc, v across).
@_optimize(speed)
func makeArcTextures() -> (emissive: [CGImage], alpha: CGImage) {
    let W = 256, H = 64
    var em = [[UInt8]](repeating: [UInt8](repeating: 255, count: W * H * 4), count: 4)
    var al = [UInt8](repeating: 255, count: W * H * 4)
    for y in 0..<H { for x in 0..<W {
        let u: Float = (Float(x) + 0.5) / Float(W)
        let v: Float = (Float(y) + 0.5) / Float(H)
        let uRise: Float = ss(0, 0.30, u)
        let uFall: Float = ss(0, 0.30, 1 - u)
        let au: Float = uRise * uFall
        let vCentered: Float = rkAbs(2 * v - 1)
        let av: Float = 1 - ss(0.25, 1.0, vCentered)
        let a: Float = au * av
        let i: Int = (y * W + x) * 4
        let ab: UInt8 = rkClampByte(a * 255 + 0.5)
        al[i] = ab; al[i + 1] = ab; al[i + 2] = ab; al[i + 3] = ab
        for c in 0..<4 {
            for k in 0..<3 {
                let encoded: Float = srgbEncode(tubeColors[c][k])
                let byteValue: Int = Int(encoded * 255 + 0.5)
                em[c][i + k] = UInt8(clamping: byteValue)
            }
        }
    } }
    var emissiveImages: [CGImage] = []
    for c in 0..<4 { emissiveImages.append(rgbaImage(W, H, em[c])) }
    return (emissive: emissiveImages, alpha: rgbaImageStraight(W, H, al))
}

struct FaceTextures { var normal: CGImage; var rough: CGImage; var color: CGImage; var emissive: CGImage }

@_optimize(speed)
func ss(_ a: Float, _ b: Float, _ x: Float) -> Float {
    let raw: Float = (x - a) / (b - a)
    let t: Float = rkClamp01(raw)
    let shape: Float = 3 - 2 * t
    return t * t * shape
}

/// cos / sin of the two end angles (a - hsA, a + hsA) of each of the 8 pockets, and the pockets' centre angles. Constant
/// for the whole run, so the per-pixel pocket search needs no trigonometry for them. Raw pointers allocated once for the
/// life of the process (no reference counting in the per-pixel loop).
struct PocketTables {
    let centerAngle: UnsafeMutablePointer<Float>
    let halfSweep: UnsafeMutablePointer<Float>
    let radius: UnsafeMutablePointer<Float>
    let endCos: UnsafeMutablePointer<Float>     // index j * 2 + (0 for the -hsA end, 1 for the +hsA end)
    let endSin: UnsafeMutablePointer<Float>
    init() {
        centerAngle = UnsafeMutablePointer<Float>.allocate(capacity: 8)
        halfSweep = UnsafeMutablePointer<Float>.allocate(capacity: 8)
        radius = UnsafeMutablePointer<Float>.allocate(capacity: 8)
        endCos = UnsafeMutablePointer<Float>.allocate(capacity: 16)
        endSin = UnsafeMutablePointer<Float>.allocate(capacity: 16)
        for j in 0..<8 {
            let c: Int = j % 4
            let rc: Float = D.tubeR[c]
            let a: Float = Float(j) * Float.pi / 4
            let hsA: Float = pockHs / rc
            centerAngle[j] = a
            halfSweep[j] = hsA
            radius[j] = rc
            let lowEnd: Float = a - hsA
            let highEnd: Float = a + hsA
            endCos[j * 2] = cos(lowEnd); endSin[j * 2] = sin(lowEnd)
            endCos[j * 2 + 1] = cos(highEnd); endSin[j * 2 + 1] = sin(highEnd)
        }
    }
}
let pocketTables = PocketTables()

/// Signed distance (rho, az) to the nearest face pocket (arc-capsule, 8 of them) and the index of that pocket's colour.
/// Same result as evaluating every pocket in full: the angle difference is wrapped arithmetically (no trig), the pixel's
/// position is computed once, the end points come from `pocketTables`, and a pocket whose radial gap alone already
/// exceeds the best distance so far (its true distance can only be larger) is skipped.
@_optimize(speed)
func pocketSDF(_ rho: Float, _ az: Float) -> (d: Float, c: Int) {
    var best: Float = 9; var bc = 0
    let px: Float = rho * cos(az)
    let py: Float = rho * sin(az)
    let twoPi: Float = 2 * Float.pi
    let radius = pocketTables.radius
    let centerAngle = pocketTables.centerAngle
    let halfSweep = pocketTables.halfSweep
    let endCos = pocketTables.endCos
    let endSin = pocketTables.endSin
    var j = 0
    while j < 8 {
        let rc: Float = radius[j]
        let gap: Float = rho - rc
        let radialGap: Float = (gap < 0 ? -gap : gap) - pockRad
        if radialGap < best {
            var da: Float = az - centerAngle[j]
            da -= twoPi * (da / twoPi).rounded()
            let absDa: Float = da < 0 ? -da : da
            let d: Float
            if absDa <= halfSweep[j] {
                d = radialGap
            } else {
                let endIndex: Int = j * 2 + ((da > 0) ? 1 : 0)
                let dx: Float = px - rc * endCos[endIndex]
                let dy: Float = py - rc * endSin[endIndex]
                let dist: Float = (dx * dx + dy * dy).squareRoot()
                d = dist - pockRad
            }
            if d < best { best = d; bc = j % 4 }
        }
        j += 1
    }
    return (best, bc)
}
let haloStrength: Float = 0.10

/// Circular-brushed face maps over the square [-1,1]^2. smear = angularly integrated version for the blur overlay:
/// brush-stroke amplitude averaged, pocket rings averaged around the circumference.
@_optimize(speed)
func makeFaceTextures(size N: Int, smear: Bool) -> FaceTextures {
    let cnt = N * N * 4
    let nrm = UnsafeMutablePointer<UInt8>.allocate(capacity: cnt), rgh = UnsafeMutablePointer<UInt8>.allocate(capacity: cnt)
    let col = UnsafeMutablePointer<UInt8>.allocate(capacity: cnt), emi = UnsafeMutablePointer<UInt8>.allocate(capacity: cnt)
    let faceBuffers: [UnsafeMutablePointer<UInt8>] = [nrm, rgh, col, emi]
    for q in faceBuffers { q.initialize(repeating: 255, count: cnt) }
    defer { for q in faceBuffers { q.deallocate() } }
    func arr(_ q: UnsafeMutablePointer<UInt8>) -> [UInt8] { Array(UnsafeBufferPointer(start: q, count: cnt)) }
    let texel = 2.0 / Float(N)
    @_optimize(speed)
    func height(_ rho: Float, _ az: Float) -> Float {
        var a: Float = 0.775
        if !smear {
            let n91: Float = vnoise(az * 6, 91)
            a = 0.55 + 0.45 * n91
        }
        let n1: Float = vnoise(rho / 1.3, 1)
        let n2: Float = vnoise(rho / 3.7, 2)
        let n3: Float = vnoise(rho / 14, 3)
        let t1: Float = 0.5 * n1
        let t2: Float = 0.33 * n2
        let t3: Float = 0.17 * n3
        return a * (t1 + t2 + t3)
    }
    // radial profiles of the pocket rings averaged over the circumference (for the smeared set)
    let RP = 2048
    let ringDarkP = UnsafeMutablePointer<Float>.allocate(capacity: RP), ringGlowP = UnsafeMutablePointer<V3>.allocate(capacity: RP)
    ringDarkP.initialize(repeating: 1, count: RP); ringGlowP.initialize(repeating: V3(0, 0, 0), count: RP)
    defer { ringDarkP.deallocate(); ringGlowP.deallocate() }
    @_optimize(speed)
    func ringProfile(_ i: Int) {
        let r: Float = (Float(i) + 0.5) / Float(RP)
        var dk: Float = 0
        var gl = V3(0, 0, 0)
        let S = 256
        for k in 0..<S {
            let azFrac: Float = (Float(k) + 0.5) / Float(S)
            let az: Float = azFrac * 2 * Float.pi
            let p = pocketSDF(r, az)
            var darkness: Float = 1
            if p.d < 0 {
                darkness = 0.04
            } else if p.d < 0.012 {
                let rim: Float = p.d / 0.012
                darkness = 0.35 + 0.65 * rim
            }
            dk += darkness
            if p.d > 0 {
                let falloff: Float = exp(-p.d / 0.035)
                gl += tubeColors[p.c] * falloff
            }
        }
        ringDarkP[i] = dk / Float(S); ringGlowP[i] = gl / Float(S)
    }
    if smear {
        DispatchQueue.concurrentPerform(iterations: RP, execute: ringProfile)
    }
    @_optimize(speed)
    func faceRow(_ y: Int) {
        var x = 0
        var fx: Float = 0.5
        let fy: Float = Float(y) + 0.5
        while x < N {
            let px: Float = fx * texel - 1
            let py: Float = 1 - fy * texel
            let r: Float = sqrt(px * px + py * py)
            let rho: Float = r / texel
            let az: Float = atan2(py, px)
            let h0: Float = height(rho - 0.5, az)
            let h1: Float = height(rho + 0.5, az)
            let slope: Float = (h1 - h0) * 0.55
            let n: V3 = simd_normalize(V3(0, slope, 1))
            let i: Int = (y * N + x) * 4
            let nx: Float = (n.x * 0.5 + 0.5) * 255
            let ny: Float = (n.y * 0.5 + 0.5) * 255
            let nzc: Float = (n.z * 0.5 + 0.5) * 255
            nrm[i] = rkClampByte(nx); nrm[i + 1] = rkClampByte(ny)
            nrm[i + 2] = rkClampByte(nzc)
            let hh: Float = 0.5 * (h0 + h1)
            let rn: Float = vnoise(rho / 40, 7) - 0.5
            let roA: Float = 0.62 + 0.30 * (hh - 0.5)
            let ro: Float = roA + 0.06 * rn
            let roClamped: Float = rkClamp01(ro)
            let rg: UInt8 = rkClampByte(roClamped * 255)
            rgh[i] = rg; rgh[i + 1] = rg; rgh[i + 2] = rg
            var c: Float = 0.80 + 0.20 * hh
            var glow = V3(0, 0, 0)
            if r > 0.60 && r < 1.0 {
                if smear {
                    let k = rkMinInt(RP - 1, Int(r * Float(RP)))
                    c *= ringDarkP[k]; glow = ringGlowP[k]
                } else {
                    let p = pocketSDF(r, az)
                    if p.d < 0.012 {                                                    // ambient occlusion at the pocket rim
                        let rimFactor: Float = 0.35 + 0.65 * ss(0, 0.012, p.d)
                        c *= rimFactor
                    }
                    if p.d > 0 {                                                        // baked colour spill from the lit rod
                        let falloff: Float = exp(-p.d / 0.035)
                        glow = tubeColors[p.c] * falloff
                    }
                }
            }
            let cClamped: Float = rkClamp01(c)
            let cb: UInt8 = rkClampByte(cClamped * 255)
            col[i] = cb; col[i + 1] = cb; col[i + 2] = cb
            for k in 0..<3 {
                let glowScaled: Float = glow[k] * haloStrength * 4
                let encoded: Float = srgbEncode(glowScaled)
                emi[i + k] = rkClampByte(encoded * 255)
            }
            x += 1
            fx += 1
        }
    }
    DispatchQueue.concurrentPerform(iterations: N, execute: faceRow)
    let normalImage: CGImage = rgbaImage(N, N, arr(nrm))
    let roughImage: CGImage = rgbaImage(N, N, arr(rgh))
    let colorImage: CGImage = rgbaImage(N, N, arr(col))
    let emissiveImage: CGImage = rgbaImage(N, N, arr(emi))
    return FaceTextures(normal: normalImage, rough: roughImage, color: colorImage, emissive: emissiveImage)
}

/// IEEE 754 binary32 -> binary16 bit pattern, round to nearest even. Handles zero, subnormals,
/// overflow to infinity, infinities and NaN. Written without `Float16`, which is unavailable
/// when compiling for x86_64 macOS (the Release configuration builds a universal binary).
func halfBits(_ f: Float) -> UInt16 {
    let b = f.bitPattern
    let sign: UInt16 = UInt16((b >> 16) & 0x8000)
    let e: Int = Int((b >> 23) & 0xFF)
    let m: UInt32 = b & 0x7FFFFF
    if e == 0xFF {                                   // infinity / NaN
        var payload: UInt16 = 0
        if m != 0 {
            let quiet: UInt32 = 0x200 | (m >> 13)
            payload = UInt16(quiet)
        }
        let infBits: UInt16 = sign | 0x7C00
        return infBits | payload
    }
    let he: Int = e - 127 + 15                       // rebiased exponent
    if he >= 0x1F { return sign | 0x7C00 }           // overflow -> infinity
    if he <= 0 {                                     // half subnormal or zero
        if he < -10 { return sign }                  // underflows to signed zero
        let full: UInt32 = m | 0x800000              // restore the implicit leading 1
        let shift: UInt32 = UInt32(14 - he)
        var h: UInt32 = full >> shift
        let one: UInt32 = 1
        let mask: UInt32 = (one << shift) - 1
        let rem: UInt32 = full & mask
        let halfway: UInt32 = one << (shift - 1)
        let isOdd: Bool = (h & 1) == 1
        if rem > halfway || (rem == halfway && isOdd) { h += 1 }
        return sign | UInt16(h)
    }
    let exponentBits: UInt32 = UInt32(he) << 10
    let mantissaBits: UInt32 = m >> 13
    var h: UInt32 = exponentBits | mantissaBits
    let rem: UInt32 = m & 0x1FFF
    let isOddH: Bool = (h & 1) == 1
    if rem > 0x1000 || (rem == 0x1000 && isOddH) { h += 1 }   // carry may bump the exponent, correctly
    return sign | UInt16(h)
}

/// Procedural studio environment as a linear float16 equirect CGImage.
/// dirFn maps a unit world direction (x right, y up, z toward viewer) to linear RGB.
@_optimize(speed)
func makeEquirect(width W: Int, height H: Int, mapping: (Float, Float) -> V3, radiance: (V3) -> V3) -> CGImage {
    var data = [UInt16](repeating: 0, count: W * H * 4)
    data.withUnsafeMutableBufferPointer { (buf: inout UnsafeMutableBufferPointer<UInt16>) -> Void in
        let base: UnsafeMutablePointer<UInt16> = buf.baseAddress!
        // Rows are independent: spread them over the cores (the evaluation is pure). The row work is a function, not a
        // closure literal: closure bodies are not covered by @_optimize(speed) and run unspecialized in Debug builds.
        @_optimize(speed)
        func fillRow(_ y: Int) {
            for x in 0..<W {
                let u: Float = (Float(x) + 0.5) / Float(W)
                let v: Float = (Float(y) + 0.5) / Float(H)
                let d: V3 = mapping(u, v)
                let c: V3 = radiance(d)
                let i: Int = (y * W + x) * 4
                base[i] = halfBits(c.x); base[i + 1] = halfBits(c.y)
                base[i + 2] = halfBits(c.z); base[i + 3] = 0x3C00   // 1.0
            }
        }
        DispatchQueue.concurrentPerform(iterations: H, execute: fillRow)
    }
    let cs = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    let bytes = data.withUnsafeBytes { Data($0) }
    let prov = CGDataProvider(data: bytes as CFData)!
    let alphaBits: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue
    let floatBits: UInt32 = CGBitmapInfo.floatComponents.rawValue
    let orderBits: UInt32 = CGBitmapInfo.byteOrder16Little.rawValue
    let info = CGBitmapInfo(rawValue: alphaBits | floatBits | orderBits)
    return CGImage(width: W, height: H, bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: W * 8, space: cs, bitmapInfo: info,
                   provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}



// ---- procedural environment (port of the shader's dim studio, world frame: x right, y up, z toward viewer) ----
@_optimize(speed)
func ssm(_ a: Float, _ b: Float, _ x: Float) -> Float {
    let raw: Float = (x - a) / (b - a)
    let t: Float = rkClamp01(raw)
    let shape: Float = 3 - 2 * t
    return t * t * shape
}
@_optimize(speed)
func softBox(_ r: V3, _ c: V3, _ uu0: V3, _ hext: V2, _ soft: Float) -> Float {
    let d: Float = simd_dot(r, c)
    let m: Float = ssm(0.10, 0.40, d)
    let uProj: Float = simd_dot(uu0, c)
    let uu: V3 = simd_normalize(uu0 - c * uProj)
    let vv: V3 = simd_cross(c, uu)
    let pRaw = V2(simd_dot(r, uu), simd_dot(r, vv))
    let p: V2 = pRaw / rkMax(d, 0.10)
    let a: V2 = hext - V2(rkAbs(p.x), rkAbs(p.y))
    let sx: Float = ssm(-soft, soft, a.x)
    let sy: Float = ssm(-soft, soft, a.y)
    return m * sx * sy
}
@_optimize(speed)
func studioEnv(_ r: V3, gain: Float) -> V3 {
    var col = V3(0.040, 0.043, 0.054)
    let skyMix: Float = ssm(-0.2, 1.0, r.y)
    col += V3(0.040, 0.044, 0.056) * skyMix
    let horizonOffset: Float = r.y + 0.04
    let horizonGlow: Float = exp(-horizonOffset * horizonOffset / 0.030)
    col += V3(0.075, 0.080, 0.095) * horizonGlow
    let frontMix: Float = ssm(0.0, 0.9, r.z)
    col += V3(0.045, 0.047, 0.055) * frontMix
    do {
        let c: V3 = simd_normalize(V3(-0.42, 0.62, 0.40))
        var uu: V3 = simd_normalize(simd_cross(V3(0, 0, 1), c))
        let uuMixed: V3 = uu * 0.94 + simd_cross(c, uu) * 0.34
        uu = simd_normalize(uuMixed)
        let b: Float = softBox(r, c, uu, V2(0.80, 0.34), 0.20)
        let gradMix: Float = ssm(-0.8, 0.8, simd_dot(r, uu))
        let grad: Float = 0.60 + (1.15 - 0.60) * gradMix
        let keyColor = V3(2.6, 2.65, 2.75)
        col += keyColor * b * grad
    }
    do {
        let c: V3 = simd_normalize(V3(-0.60, 0.05, 0.80))
        let uu: V3 = simd_normalize(simd_cross(V3(0, 1, 0), c))
        let gMix: Float = ssm(0.25, 0.95, rkAbs(r.y - 0.05))
        let g: Float = 1.0 + (0.40 - 1.0) * gMix
        let fillBox: Float = softBox(r, c, uu, V2(0.42, 1.6), 0.30)
        let fillColor = V3(3.0, 3.05, 3.2)
        let fillScaled: V3 = fillColor * 0.54
        let fillGraded: V3 = fillScaled * g
        col += fillGraded * fillBox
    }
    do {
        let c1: V3 = simd_normalize(V3(0.72, 0.06, 0.48))
        let box1: Float = softBox(r, c1, V3(0, 1, 0), V2(0.55, 0.11), 0.08)
        let color1: V3 = V3(0.80, 0.88, 1.0) * 1.15
        col += color1 * box1
    }
    do {
        let c2: V3 = simd_normalize(V3(-0.62, -0.42, 0.45))
        let u2: V3 = simd_normalize(V3(0.6, -0.3, 0))
        let box2: Float = softBox(r, c2, u2, V2(0.20, 0.09), 0.07)
        let color2: V3 = V3(0.70, 0.72, 0.78) * 0.55
        col += color2 * box2
    }
    do {
        let c3: V3 = simd_normalize(V3(0.25, 0.55, -0.80))
        let box3: Float = softBox(r, c3, V3(1, 0, 0), V2(0.75, 0.10), 0.08)
        let color3: V3 = V3(0.55, 0.65, 0.90) * 1.3
        col += color3 * box3
    }
    do {
        let c4: V3 = simd_normalize(V3(-0.45, -0.30, -0.84))
        let u4: V3 = simd_normalize(V3(0.8, 0.2, 0))
        let box4: Float = softBox(r, c4, u4, V2(0.35, 0.07), 0.06)
        let color4: V3 = V3(1.0, 0.82, 0.62) * 0.55
        col += color4 * box4
    }
    do {
        let c5: V3 = simd_normalize(V3(0.60, -0.55, 0.55))
        let u5: V3 = simd_normalize(V3(0.7, 0.5, 0))
        let box5: Float = softBox(r, c5, u5, V2(0.30, 0.10), 0.09)
        let color5: V3 = V3(0.85, 0.80, 0.75) * 0.75
        col += color5 * box5
    }
    let floorMix: Float = ssm(0.05, -0.55, r.y)
    col += V3(0.120, 0.112, 0.120) * floorMix
    return col * gain
}
/// RealityKit equirect convention, measured with a mirror-sphere probe: u = fract(-atan2(x, z) / 2pi), v = acos(y) / pi.
@_optimize(speed)
func equirectDir(_ u: Float, _ v: Float) -> V3 {
    let a: Float = -2 * Float.pi * u
    let polar: Float = Float.pi * v
    let y: Float = cos(polar)
    let s: Float = sin(polar)
    return V3(s * sin(a), y, s * cos(a))
}



@_optimize(speed)
func srgbEncode(_ x: Float) -> Float {
    let c: Float = rkClamp01(x)
    if c <= 0.0031308 { return 12.92 * c }
    let exponent: Float = 1 / 2.4
    let powered: Float = pow(c, exponent)
    return 1.055 * powered - 0.055
}

/// Solid fraction of the web's circumference at each radius (the twelve slits removed): opacity of the smeared web ring.
@_optimize(speed)
func makeWebOpacity(size N: Int) -> CGImage {
    let g = SlitGeom()
    let RP = 512
    var prof = [Float](repeating: 1, count: RP)
    for i in 0..<RP {
        let r: Float = Float(i) / Float(RP)
        let innerEdge: Float = D.slitInner - g.h
        let outerEdge: Float = D.slitOuter + g.h
        if r > innerEdge && r < outerEdge, let iv = g.interval(r) {
            let sweepTotal: Float = Float(D.slitCount) * (iv.hi - iv.lo)
            let solidFraction: Float = sweepTotal / (2 * Float.pi)
            prof[i] = 1 - solidFraction
        }
    }
    let pxP = UnsafeMutablePointer<UInt8>.allocate(capacity: N * N * 4); pxP.initialize(repeating: 255, count: N * N * 4)
    defer { pxP.deallocate() }
    let profL = prof
    let texel = 2.0 / Float(N)
    @_optimize(speed)
    func webRow(_ y: Int) {
        for x in 0..<N {
            let X: Float = (Float(x) + 0.5) * texel - 1
            let Y: Float = 1 - (Float(y) + 0.5) * texel
            let r: Float = sqrt(X * X + Y * Y)
            let profIndex: Int = rkMinInt(RP - 1, Int(r * Float(RP)))
            let v: Float = profL[profIndex]
            let b: UInt8 = rkClampByte(v * 255 + 0.5)
            let i: Int = (y * N + x) * 4; pxP[i] = b; pxP[i + 1] = b; pxP[i + 2] = b; pxP[i + 3] = b
        }
    }
    DispatchQueue.concurrentPerform(iterations: N, execute: webRow)
    return rgbaImageStraight(N, N, Array(UnsafeBufferPointer(start: pxP, count: N * N * 4)))
}



// MARK: - generalized hub marks and the full image set

/// Hub mark pieces for mark index (0 interlock, 1 sign-off) as drawn on the front (+z) or back (-z) dome.
/// The back mark is authored for the view in which its face is visible: mirrored in x relative to the front design,
/// because a face seen from behind runs right to left on screen. The dome entities are rolled about the puck's own axis
/// every frame (`SpinnerHubRoll`) so the mark's up always points to screen-up: it reads upright and unmirrored at every
/// pose, including turned over about the horizontal axis (pitch 180).
@_optimize(speed)
func hubPieces(mark: Int, backDome: Bool) -> [(strokes: [(a: V2, b: V2, hw: Float)], gain: Float)] {
    let xs: Float = backDome ? -1 : 1
    let ys: Float = -1
    @_optimize(speed)
    func conv(_ list: [RKStroke], _ s: Float) -> [(a: V2, b: V2, hw: Float)] {
        var converted: [(a: V2, b: V2, hw: Float)] = []
        for st in list {
            let ax: Float = xs * (st.a.x - 100) * s
            let ay: Float = ys * (st.a.y - 100) * s
            let bx: Float = xs * (st.b.x - 100) * s
            let by: Float = ys * (st.b.y - 100) * s
            let hw: Float = st.w * s / 2
            converted.append((a: V2(ax, ay), b: V2(bx, by), hw: hw))
        }
        return converted
    }
    if mark == 0 {
        let frontPiece: [(a: V2, b: V2, hw: Float)] = conv(markFrontStrokes(), markScaleF)
        return [(strokes: frontPiece, gain: 1.0)]
    }
    let g: [Float] = [0.45, 0.75, 1.0]
    var result: [(strokes: [(a: V2, b: V2, hw: Float)], gain: Float)] = []
    let pieces: [[RKStroke]] = markBackStrokes()
    for (i, piece) in pieces.enumerated() {
        let converted: [(a: V2, b: V2, hw: Float)] = conv(piece, markScaleB)
        result.append((strokes: converted, gain: g[i]))
    }
    return result
}

/// All CPU images the puck needs (built once on a background queue).
final class RKImages: @unchecked Sendable {
    var face: FaceTextures!, smear: FaceTextures!
    var webOpacity: CGImage!
    var arcEmissive: [CGImage] = [], arcAlpha: CGImage!
    var env: CGImage!
    var timings: [(String, Double)] = []
}

@_optimize(speed)
func makeAllImages(faceSize: Int = 2048, envGain: Float = 0.35) -> RKImages {
    let out = RKImages()
    let lock = NSLock()
    @_optimize(speed)
    func lap(_ name: String, _ t0: UInt64) {
        let elapsedNs: UInt64 = DispatchTime.now().uptimeNanoseconds - t0
        let ms: Double = Double(elapsedNs) / 1e6
        lock.lock(); out.timings.append((name, ms)); lock.unlock()
    }
    var jobs: [() -> Void] = []
    let faceJob: () -> Void = { () -> Void in
        let t = DispatchTime.now().uptimeNanoseconds
        let r = makeFaceTextures(size: faceSize, smear: false)
        lock.lock(); out.face = r; lock.unlock()
        lap("face textures", t)
    }
    let smearSize: Int = faceSize / 2
    let smearJob: () -> Void = { () -> Void in
        let t = DispatchTime.now().uptimeNanoseconds
        let r = makeFaceTextures(size: smearSize, smear: true)
        lock.lock(); out.smear = r; lock.unlock()
        lap("smeared face textures", t)
    }
    let webJob: () -> Void = { () -> Void in
        let t = DispatchTime.now().uptimeNanoseconds
        let r = makeWebOpacity(size: 1024)
        let at = makeArcTextures()
        lock.lock(); out.webOpacity = r; out.arcEmissive = at.emissive; out.arcAlpha = at.alpha; lock.unlock()
        lap("web opacity + arc textures", t)
    }
    let envJob: () -> Void = { () -> Void in
        let t = DispatchTime.now().uptimeNanoseconds
        let radianceFn: (V3) -> V3 = { (dir: V3) -> V3 in studioEnv(dir, gain: envGain) }
        let r = makeEquirect(width: 1024, height: 512, mapping: equirectDir, radiance: radianceFn)
        lock.lock(); out.env = r; lock.unlock()
        lap("environment equirect", t)
    }
    jobs.append(faceJob)
    jobs.append(smearJob)
    jobs.append(webJob)
    jobs.append(envJob)
    // The jobs run one after another, because each already spreads its own rows over every core
    // (`DispatchQueue.concurrentPerform` inside). Running the jobs concurrently on top of that over-subscribed the
    // cores and made the whole set about 1.7x slower than running them in sequence (measured in Debug, 8 cores).
    for job in jobs { job() }
    return out
}
