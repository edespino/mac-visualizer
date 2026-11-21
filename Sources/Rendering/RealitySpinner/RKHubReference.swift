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

import CoreGraphics
import Foundation
import simd

// Reference implementation of the hub texture generation: the straightforward per-pixel version (a signed-distance
// evaluation per pixel, twice in the raised finish's shadow band). `makeHubTextures` (RKTextures.swift) replaced it in
// the app because it was the dominant setup cost; this copy stays as the oracle for `--rk-hub-check`, which renders
// both and reports the largest per-channel difference and the timings.

struct HubSampleReference {
    var d: Float
    var grad: V2
    var gain: Float
    var hw: Float
}

/// Signed distance (outside positive) from `p` to the union of the mark's strokes, with the outward direction, the
/// owning piece's gain and the nearest stroke's half width. Strokes farther than 0.01 are culled.
@_optimize(speed)
func hubSampleReference(_ p: V2, pieces: [(strokes: [(a: V2, b: V2, hw: Float)], gain: Float)], minB: V2, maxB: V2) -> HubSampleReference {
    var result = HubSampleReference(d: 9, grad: V2(0, 0), gain: 0, hw: 0)
    if p.x > minB.x && p.x < maxB.x && p.y > minB.y && p.y < maxB.y {
        for pc in pieces {
            var dp: Float = 9
            var gp = V2(0, 0)
            var hwp: Float = 0
            for s in pc.strokes {
                // A stroke farther than 0.01 from p changes nothing (all effects live within ~0.002 of an edge): cull it.
                let cullPad: Float = s.hw + 0.01
                let cullVec = V2(repeating: cullPad)
                let lo: V2 = simd_min(s.a, s.b) - cullVec
                let hi: V2 = simd_max(s.a, s.b) + cullVec
                if p.x < lo.x || p.x > hi.x || p.y < lo.y || p.y > hi.y { continue }
                let ab: V2 = s.b - s.a
                let l2: Float = simd_dot(ab, ab)
                var t: Float = 0
                if l2 > 0 {
                    let proj: Float = simd_dot(p - s.a, ab) / l2
                    t = max(0, min(1, proj))
                }
                let q: V2 = s.a + ab * t
                let v: V2 = p - q
                let vLen: Float = simd_length(v)
                let d: Float = vLen - s.hw
                if d < dp {
                    dp = d
                    hwp = s.hw
                    if vLen > 1e-9 { gp = v / vLen } else { gp = V2(1, 0) }
                }
            }
            if dp < result.d {
                result = HubSampleReference(d: dp, grad: gp, gain: pc.gain, hw: hwp)
            }
        }
    }
    return result
}

/// Marks as real-channel illusion on the hub top: signed-distance field of the union of capsule strokes (no overlap artefacts)
/// drives the emissive floor, dark floor/wall colour and a bevel normal on the lip (lit finish), and the raised finish's
/// grey ramp, roughness, bevel normal and baked contact shadow. Local frame: x right, y up, span 0.72.
@_optimize(speed)
func makeHubTexturesReference(size N: Int, pieces: [(strokes: [(a: V2, b: V2, hw: Float)], gain: Float)], front: Bool) -> HubTextures {
    let cnt = N * N * 4
    let nrm = UnsafeMutablePointer<UInt8>.allocate(capacity: cnt)
    let col = UnsafeMutablePointer<UInt8>.allocate(capacity: cnt)
    let emi = UnsafeMutablePointer<UInt8>.allocate(capacity: cnt)
    let rcol = UnsafeMutablePointer<UInt8>.allocate(capacity: cnt)
    let rrgh = UnsafeMutablePointer<UInt8>.allocate(capacity: cnt)
    let rnrm = UnsafeMutablePointer<UInt8>.allocate(capacity: cnt)
    let hubBuffers: [UnsafeMutablePointer<UInt8>] = [nrm, col, emi, rcol, rrgh, rnrm]
    for q in hubBuffers { q.initialize(repeating: 255, count: cnt) }
    defer { for q in hubBuffers { q.deallocate() } }
    func arr(_ q: UnsafeMutablePointer<UInt8>) -> [UInt8] { Array(UnsafeBufferPointer(start: q, count: cnt)) }
    let span: Float = 0.72
    let texel: Float = span / Float(N)
    let ice = V3(0.30, 0.75, 1.0)
    let dome = V3(0.05, 0.052, 0.058)
    var minB = V2(9, 9)
    var maxB = V2(-9, -9)
    for p in pieces {
        for s in p.strokes {
            let pad: Float = s.hw + 0.02
            let padVec = V2(repeating: pad)
            let ends: [V2] = [s.a, s.b]
            for q in ends {
                minB = simd_min(minB, q - padVec)
                maxB = simd_max(maxB, q + padVec)
            }
        }
    }
    let minBL = minB
    let maxBL = maxB
    // Direction toward the key light in texture space (upper left on screen). The back dome is seen turned over about the
    // vertical axis (yaw 180), which mirrors texture x on screen.
    let towardLight: V2 = front ? V2(-0.70710678, 0.70710678) : V2(0.70710678, 0.70710678)
    DispatchQueue.concurrentPerform(iterations: N) { y in
        for x in 0..<N {
            let i: Int = (y * N + x) * 4
            let pxNorm: Float = (Float(x) + 0.5) / Float(N) - 0.5
            let pyNorm: Float = 0.5 - (Float(y) + 0.5) / Float(N)
            let p: V2 = V2(pxNorm, pyNorm) * span
            let smp: HubSampleReference = hubSampleReference(p, pieces: pieces, minB: minBL, maxB: maxBL)
            let dmin: Float = smp.d
            let grad: V2 = smp.grad
            let gain: Float = smp.gain
            let edgeHalf: Float = texel * 0.8
            let cover: Float = 1 - ss(-edgeHalf, edgeHalf, dmin)                     // antialiased inside mask
            // ---------------- lit finish ----------------
            var emc: V3 = ice * gain * cover
            if cover > 0 {                                                           // slight darkening toward the channel walls
                let wallShade: Float = 0.78 + 0.22 * ss(0, 0.004, -dmin)
                emc *= wallShade
            }
            let domePart: V3 = dome * (1 - cover)
            let floorPart: V3 = V3(0.008, 0.010, 0.014) * cover
            let base: V3 = domePart + floorPart
            var n = V3(0, 0, 1)
            if dmin > 0 && dmin < 0.0016 {
                let k: Float = 0.85 * (1 - dmin / 0.0016)
                let dirY: Float = front ? grad.y : -grad.y
                let dir: V2 = V2(grad.x, dirY)
                n = simd_normalize(V3(dir.x * k, dir.y * k, 1))
            }
            // a hairline of darkness just outside the lip reads as the chamfer shadow
            var lipDark: Float = 1
            if dmin > 0 && dmin < 0.0012 { lipDark = 0.75 }
            for k in 0..<3 {
                let baseEncoded: Float = srgbEncode(base[k] * lipDark)
                let emissiveEncoded: Float = srgbEncode(emc[k])
                col[i + k] = UInt8(clamping: Int(baseEncoded * 255))
                emi[i + k] = UInt8(clamping: Int(emissiveEncoded * 255))
            }
            let nxB: Float = (n.x * 0.5 + 0.5) * 255
            let nyB: Float = (n.y * 0.5 + 0.5) * 255
            let nzB: Float = (n.z * 0.5 + 0.5) * 255
            nrm[i] = UInt8(clamping: Int(nxB)); nrm[i + 1] = UInt8(clamping: Int(nyB)); nrm[i + 2] = UInt8(clamping: Int(nzB))
            // ---------------- raised finish ----------------
            // Soft contact shadow on the hub top hugging the side of each stroke away from the light: the stroke's
            // distance field sampled a little toward the light.
            var shade: Float = 1
            if cover < 1 && dmin < 0.03 {
                let reach: Float = hubRaiseHeight * 0.6
                let towardPoint: V2 = p + towardLight * reach
                let lit: HubSampleReference = hubSampleReference(towardPoint, pieces: pieces, minB: minBL, maxB: maxBL)
                let inShadow: Float = 1 - ss(0, hubRaiseHeight * 1.2, lit.d)
                let shadowAmount: Float = (1 - cover) * inShadow
                shade = 1 - 0.65 * shadowAmount
            }
            let tone: Float = raiseTone(forGain: gain)
            let floorLin: Float = hubRaisedFloor * shade
            let topLin: Float = floorLin * (1 - cover) + tone * cover
            let topByte: Float = srgbEncode(topLin) * 255
            let roughLin: Float = 0.10 * (1 - cover) + 0.40 * cover
            let roughByte: Float = roughLin * 255
            for k in 0..<3 {
                rcol[i + k] = UInt8(clamping: Int(topByte))
                rrgh[i + k] = UInt8(clamping: Int(roughByte))
            }
            // Bevel on the top face's edge (inside the outline): the face tilts outward, so the edge toward the
            // light catches it and the opposite edge falls dark.
            var rn = V3(0, 0, 1)
            if cover > 0 {
                let widthLimit: Float = 0.45 * smp.hw
                let bevelWidth: Float = max(min(0.006, widthLimit), 0.0018)
                let inBand: Float = ss(-bevelWidth - edgeHalf, -bevelWidth + edgeHalf, dmin)
                let tilt: Float = 0.9 * cover * inBand
                let rDirY: Float = front ? grad.y : -grad.y
                let rDir: V2 = V2(grad.x, rDirY)
                rn = simd_normalize(V3(rDir.x * tilt, rDir.y * tilt, 1))
            }
            let rnx: Float = (rn.x * 0.5 + 0.5) * 255
            let rny: Float = (rn.y * 0.5 + 0.5) * 255
            let rnz: Float = (rn.z * 0.5 + 0.5) * 255
            rnrm[i] = UInt8(clamping: Int(rnx)); rnrm[i + 1] = UInt8(clamping: Int(rny)); rnrm[i + 2] = UInt8(clamping: Int(rnz))
        }
    }
    let colorImage: CGImage = rgbaImage(N, N, arr(col))
    let emissiveImage: CGImage = rgbaImage(N, N, arr(emi))
    let normalImage: CGImage = rgbaImage(N, N, arr(nrm))
    let raisedColorImage: CGImage = rgbaImage(N, N, arr(rcol))
    let raisedRoughImage: CGImage = rgbaImage(N, N, arr(rrgh))
    let raisedNormalImage: CGImage = rgbaImage(N, N, arr(rnrm))
    return HubTextures(color: colorImage, emissive: emissiveImage, normal: normalImage,
                       raisedColor: raisedColorImage, raisedRough: raisedRoughImage, raisedNormal: raisedNormalImage)
}


/// `--rk-hub-check`: generates both hub texture sets with the reference and with the fast path, prints the wall time of
/// each and the largest per-channel difference (0...255) of every map, then exits. A diagnostic, not part of the app.
enum RKHubCheck {
    static func run() {
        let size = 2048
        for backDome in [false, true] {
            let mark: Int = backDome ? 1 : 0
            let pieces = hubPieces(mark: mark, backDome: backDome)
            let t0 = DispatchTime.now().uptimeNanoseconds
            let reference = makeHubTexturesReference(size: size, pieces: pieces, front: !backDome)
            let t1 = DispatchTime.now().uptimeNanoseconds
            let fast = makeHubTextures(size: size, pieces: pieces, front: !backDome)
            let t2 = DispatchTime.now().uptimeNanoseconds
            let refMs: Double = Double(t1 - t0) / 1e6
            let fastMs: Double = Double(t2 - t1) / 1e6
            let name: String = backDome ? "back (sign-off)" : "front (interlock)"
            print(String(format: "hub %@: reference %.0f ms, fast %.0f ms", name, refMs, fastMs))
            let maps: [(String, CGImage, CGImage)] = [
                ("color", reference.color, fast.color), ("emissive", reference.emissive, fast.emissive),
                ("normal", reference.normal, fast.normal), ("raisedColor", reference.raisedColor, fast.raisedColor),
                ("raisedRough", reference.raisedRough, fast.raisedRough), ("raisedNormal", reference.raisedNormal, fast.raisedNormal),
            ]
            for (label, a, b) in maps {
                let (maxDiff, differing) = compare(a, b)
                print(String(format: "  %@: max per-channel difference %d, differing channel values %d", label, maxDiff, differing))
            }
        }
    }

    private static func bytes(_ image: CGImage) -> [UInt8] {
        let data: CFData? = image.dataProvider?.data
        guard let data else { return [] }
        let length: Int = CFDataGetLength(data)
        var out: [UInt8] = [UInt8](repeating: 0, count: length)
        CFDataGetBytes(data, CFRange(location: 0, length: length), &out)
        return out
    }

    private static func compare(_ a: CGImage, _ b: CGImage) -> (Int, Int) {
        let pa: [UInt8] = bytes(a)
        let pb: [UInt8] = bytes(b)
        if pa.count != pb.count { return (999, pa.count) }
        var maxDiff = 0
        var differing = 0
        for i in 0..<pa.count {
            let d: Int = abs(Int(pa[i]) - Int(pb[i]))
            if d > 0 { differing += 1 }
            if d > maxDiff { maxDiff = d }
        }
        return (maxDiff, differing)
    }
}
