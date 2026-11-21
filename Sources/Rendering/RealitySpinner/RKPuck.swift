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
// RealityKit resources for the puck (meshes, textures, materials).
import RealityKit
import AppKit
import CoreGraphics
import Foundation
import simd

@available(macOS 15.0, *)
extension MB {
    @MainActor func descriptor(name: String = "m", material: UInt32 = 0) -> MeshDescriptor {
        var d = MeshDescriptor(name: name)
        d.materials = .allFaces(material)
        d.positions = MeshBuffers.Positions(p)
        d.normals = MeshBuffers.Normals(n)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        d.tangents = MeshBuffers.Tangents(t)
        d[MeshBuffers.bitangents] = MeshBuffer(b)
        d.primitives = .triangles(idx)
        return d
    }
    @MainActor func resource(name: String = "m") throws -> MeshResource {
        try MeshResource.generate(from: [descriptor(name: name)])
    }
}

@available(macOS 15.0, *)
struct RKPartDef { var mesh: MeshResource; var kind: MatKind; var group: Int }

/// Texture resources; created asynchronously (the heavy upload work runs off the main thread).
@MainActor @available(macOS 15.0, *)
struct RKPuckTextures {
    var face: TextureResource, faceRough: TextureResource, faceNormal: TextureResource, faceEmi: TextureResource
    var sFace: TextureResource, sFaceRough: TextureResource, sFaceNormal: TextureResource, sFaceEmi: TextureResource
    /// One hub dome's texture sets: the lit finish (color/emissive/normal) and the raised finish
    /// (grey ramp color, roughness, normal). Both are always resident so switching finish is a material swap.
    struct Hub {
        var color: TextureResource, emissive: TextureResource, normal: TextureResource
        var raisedColor: TextureResource, raisedRough: TextureResource, raisedNormal: TextureResource
    }
    var hubs: [Hub]
    var webOpacity: TextureResource
    var arcEmi: [TextureResource], arcAlpha: TextureResource

    static func make(_ im: RKImages, step: @MainActor () async -> Void = {}) async throws -> RKPuckTextures {
        func gen(_ i: CGImage, _ s: TextureResource.Semantic) async throws -> TextureResource {
            let r = try await TextureResource(image: i, options: .init(semantic: s))
            await step()
            return r
        }
        // Hub marks are fine, high-contrast detail: no lossy compression, and a full mip chain so the mark stays clean
        // when small or tilted (trilinear filtering through the mips).
        func genHub(_ i: CGImage, _ s: TextureResource.Semantic) async throws -> TextureResource {
            let options = TextureResource.CreateOptions(semantic: s, compression: .none, mipmapsMode: .allocateAndGenerateAll)
            let r = try await TextureResource(image: i, options: options)
            await step()
            return r
        }
        let emi = PhysicallyBasedMaterial.EmissiveColor.textureSemantic
        let f = im.face!, sm = im.smear!
        let face: TextureResource = try await gen(f.color, .color)
        let faceRough: TextureResource = try await gen(f.rough, .scalar)
        let faceNormal: TextureResource = try await gen(f.normal, .normal)
        let faceEmi: TextureResource = try await gen(f.emissive, emi)
        let sFace: TextureResource = try await gen(sm.color, .color)
        let sFaceRough: TextureResource = try await gen(sm.rough, .scalar)
        let sFaceNormal: TextureResource = try await gen(sm.normal, .normal)
        let sFaceEmi: TextureResource = try await gen(sm.emissive, emi)
        var hubs: [Hub] = []
        for h in im.hubs {
            let hh = h!
            let hubColor: TextureResource = try await genHub(hh.color, .color)
            let hubEmissive: TextureResource = try await genHub(hh.emissive, emi)
            let hubNormal: TextureResource = try await genHub(hh.normal, .normal)
            let hubRaisedColor: TextureResource = try await genHub(hh.raisedColor, .color)
            let hubRaisedRough: TextureResource = try await genHub(hh.raisedRough, .scalar)
            let hubRaisedNormal: TextureResource = try await genHub(hh.raisedNormal, .normal)
            hubs.append(Hub(color: hubColor, emissive: hubEmissive, normal: hubNormal,
                            raisedColor: hubRaisedColor, raisedRough: hubRaisedRough, raisedNormal: hubRaisedNormal))
        }
        let web = try await gen(im.webOpacity, PhysicallyBasedMaterial.Opacity.textureSemantic)
        var arcEmi: [TextureResource] = []
        for c in im.arcEmissive { arcEmi.append(try await gen(c, emi)) }
        let arcAlpha = try await gen(im.arcAlpha, PhysicallyBasedMaterial.Opacity.textureSemantic)
        return RKPuckTextures(face: face, faceRough: faceRough, faceNormal: faceNormal, faceEmi: faceEmi,
                              sFace: sFace, sFaceRough: sFaceRough, sFaceNormal: sFaceNormal, sFaceEmi: sFaceEmi,
                              hubs: hubs, webOpacity: web, arcEmi: arcEmi, arcAlpha: arcAlpha)
    }
}

// ---- materials ----
func lin(_ c: V3) -> NSColor {
    let red: CGFloat = CGFloat(srgbEncode(c.x))
    let green: CGFloat = CGFloat(srgbEncode(c.y))
    let blue: CGFloat = CGFloat(srgbEncode(c.z))
    return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
}

struct RKMetal { var name: String; var f0: V3 }
let rkMetals: [String: RKMetal] = {
    var table: [String: RKMetal] = [:]
    table["steel"] = RKMetal(name: "steel", f0: V3(0.56, 0.57, 0.58))
    table["brass"] = RKMetal(name: "brass", f0: V3(0.96, 0.76, 0.32))
    table["copper"] = RKMetal(name: "copper", f0: V3(0.95, 0.64, 0.54))
    table["zirconium"] = RKMetal(name: "zirconium", f0: V3(0.17, 0.18, 0.20))
    // Anodized titanium: RealityKit has no thin-film term (a coloured sheen lobe was tried and only darkened the metal), so
    // it draws plain titanium grey, a touch cooler and darker than steel. The colour-shifting film is classic-shader only.
    table["titanium"] = RKMetal(name: "titanium", f0: V3(0.47, 0.48, 0.51))
    return table
}()

struct RKTuning {
    var anisoLevel: Float = 0.8
    var anisoAngleScale: Float = 0.0
    var rodEmissive: Float = 1.15
    var markEmissive: Float = 1.0
    var faceTint: Float = 0.50
    var faceRough: Float = 0.62
    var webTint: Float = 0.32
    var useAniso = true
    var useNormalMaps = true
    var glass = true
    var hubFinish = 0        // SpinnerHubFinish index: 0 lit, 1 raised
    var glow: Float = 1      // multiplier on every emissive intensity (SpinnerSettings.glowBrightness)
}

/// Pale top-face tint of the raised hub mark: the body metal lightened and slightly desaturated
/// (pale steel on steel, pale gold on brass, light copper on copper, clear mid-grey on black zirconium).
func raisedTint(_ f0: V3) -> V3 {
    let luminance: Float = (f0.x + f0.y + f0.z) * 0.33
    let grey = V3(repeating: luminance)
    let desaturated: V3 = f0 + (grey - f0) * 0.12
    let toWhite: V3 = V3(1, 1, 1) - desaturated
    let lightened: V3 = desaturated + toWhite * 0.5
    return simd_min(lightened, V3(repeating: 0.95))
}

@MainActor @available(macOS 15.0, *)
func makeMaterial(_ k: MatKind, metal: RKMetal, tex: RKPuckTextures, tune: RKTuning) -> PhysicallyBasedMaterial {
    var m = PhysicallyBasedMaterial()
    typealias T = PhysicallyBasedMaterial.Texture
    func steel(_ scale: V3 = V3(1, 1, 1)) -> PhysicallyBasedMaterial.BaseColor {
        let scaled: V3 = metal.f0 * scale
        return PhysicallyBasedMaterial.BaseColor(tint: lin(scaled))
    }
    switch k {
    case .faceBrushed:
        m.baseColor = .init(tint: lin(metal.f0 * tune.faceTint), texture: T(tex.face))
        m.metallic = 1.0
        m.roughness = .init(scale: tune.faceRough, texture: T(tex.faceRough))
        m.emissiveColor = .init(texture: T(tex.faceEmi)); m.emissiveIntensity = tune.glow
        if tune.useNormalMaps { m.normal = .init(texture: T(tex.faceNormal)) }
        if tune.useAniso {
            m.anisotropyLevel = .init(scale: tune.anisoLevel, texture: nil)
            m.anisotropyAngle = .init(scale: tune.anisoAngleScale, texture: nil)
        }
    case .webSatin:
        m.baseColor = .init(tint: lin(metal.f0 * tune.webTint), texture: T(tex.face))
        m.metallic = 1.0
        m.roughness = .init(scale: 0.66, texture: T(tex.faceRough))
        if tune.useNormalMaps { m.normal = .init(texture: T(tex.faceNormal)) }
        if tune.useAniso {
            m.anisotropyLevel = .init(scale: tune.anisoLevel * 0.5, texture: nil)
            m.anisotropyAngle = .init(scale: tune.anisoAngleScale, texture: nil)
        }
    case .chamfer:
        m.baseColor = steel(V3(0.5, 0.5, 0.5)); m.metallic = 1.0; m.roughness = 0.24
    case .wallBand:
        m.baseColor = steel(V3(0.6, 0.6, 0.6)); m.metallic = 1.0; m.roughness = 0.34
    case .groove:
        m.baseColor = steel(V3(0.12, 0.12, 0.12)); m.metallic = 1.0; m.roughness = 0.5
    case .knurl:
        m.baseColor = steel(V3(0.55, 0.55, 0.55)); m.metallic = 1.0; m.roughness = 0.30
    case .plate:
        m.baseColor = steel(V3(0.5, 0.5, 0.5)); m.metallic = 1.0; m.roughness = 0.32
    case .cutWall:
        m.baseColor = steel(V3(0.10, 0.10, 0.10)); m.metallic = 1.0; m.roughness = 0.55
    case .stepWall:
        m.baseColor = steel(V3(0.25, 0.25, 0.25)); m.metallic = 1.0; m.roughness = 0.42
    case .hubDomeF, .hubDomeB:
        // The marks are fixed: the interlocked mark on the front dome (hubs[0]), the sign-off mark on the back (hubs[1]).
        let back: Bool = (k == .hubDomeB)
        let h = tex.hubs[back ? 1 : 0]
        if tune.hubFinish == 1 {
            // Raised finish: no emission; a dark polished hub top with the mark as a low relief. The texture carries the
            // top-face tone (and contact shadow); the pale metal tint multiplies it.
            m.baseColor = .init(tint: lin(raisedTint(metal.f0)), texture: T(h.raisedColor)); m.metallic = 1.0
            m.roughness = .init(scale: 1.0, texture: T(h.raisedRough))
            if tune.useNormalMaps { m.normal = .init(texture: T(h.raisedNormal)) }
        } else {
            m.baseColor = .init(tint: .white, texture: T(h.color)); m.metallic = 1.0; m.roughness = 0.10
            m.emissiveColor = .init(texture: T(h.emissive)); m.emissiveIntensity = tune.markEmissive * tune.glow
            if tune.useNormalMaps { m.normal = .init(texture: T(h.normal)) }
        }
    case .hubChamfer:
        m.baseColor = steel(V3(0.6, 0.6, 0.6)); m.metallic = 1.0; m.roughness = 0.14
    case .hubWall:
        m.baseColor = steel(V3(0.22, 0.22, 0.22)); m.metallic = 1.0; m.roughness = 0.38
    case .pocket(let c):
        m.baseColor = steel(V3(0.10, 0.10, 0.10)); m.metallic = 1.0; m.roughness = 0.5
        let pocketGlow: V3 = tubeColors[c] * 0.5
        m.emissiveColor = .init(color: lin(pocketGlow)); m.emissiveIntensity = 0.35 * tune.glow
    case .rodCore(let c):
        let col = tubeColors[c]
        let coreTint: V3 = col * 0.05
        m.baseColor = .init(tint: lin(coreTint)); m.metallic = 0.0; m.roughness = 0.2
        m.emissiveColor = .init(color: lin(col)); m.emissiveIntensity = tune.rodEmissive * tune.glow
    case .rodShell(let c):
        let col = tubeColors[c]
        let shellScaled: V3 = col * 0.10
        let shellTint: V3 = shellScaled + V3(0.01, 0.01, 0.01)
        m.baseColor = .init(tint: lin(shellTint)); m.metallic = 0.0; m.roughness = 0.04
        m.clearcoat = .init(floatLiteral: 1.0); m.clearcoatRoughness = .init(floatLiteral: 0.03)
        if tune.glass { m.blending = .transparent(opacity: .init(floatLiteral: 0.30)) }
    case .faceOv:
        m.baseColor = .init(tint: lin(metal.f0 * tune.faceTint), texture: T(tex.sFace))
        m.metallic = 1.0
        m.roughness = .init(scale: tune.faceRough, texture: T(tex.sFaceRough))
        m.emissiveColor = .init(texture: T(tex.sFaceEmi)); m.emissiveIntensity = tune.glow
        if tune.useNormalMaps { m.normal = .init(texture: T(tex.sFaceNormal)) }
        if tune.useAniso {
            m.anisotropyLevel = .init(scale: tune.anisoLevel, texture: nil)
            m.anisotropyAngle = .init(scale: tune.anisoAngleScale, texture: nil)
        }
    case .webOv:
        m.baseColor = .init(tint: lin(metal.f0 * tune.webTint), texture: T(tex.sFace))
        m.metallic = 1.0
        m.roughness = .init(scale: 0.66, texture: T(tex.sFaceRough))
        if tune.useNormalMaps { m.normal = .init(texture: T(tex.sFaceNormal)) }
        if tune.useAniso {
            m.anisotropyLevel = .init(scale: tune.anisoLevel * 0.5, texture: nil)
            m.anisotropyAngle = .init(scale: tune.anisoAngleScale, texture: nil)
        }
        m.blending = .transparent(opacity: .init(scale: 1.0, texture: T(tex.webOpacity)))
    case .wallOv:
        m.baseColor = steel(V3(0.5, 0.5, 0.5)); m.metallic = 1.0; m.roughness = 0.36
    }
    m.specular = 0.5
    return m
}

/// Arc ribbon material: emissive colour from the gradient texture, alpha from the soft-ended profile; brightness conserves total light.
@MainActor @available(macOS 15.0, *)
func makeArcMaterial(color c: Int, level: Int, wall: Bool, tex: RKPuckTextures, tune: RKTuning) -> PhysicallyBasedMaterial {
    var m = PhysicallyBasedMaterial()
    typealias T = PhysicallyBasedMaterial.Texture
    let sweep: Float = Float(level) * arcSweepStep
    var rc: Float = D.tubeR[c]
    var halfSlot: Float = pockHs
    if wall {
        rc = 0.995
        halfSlot = wPockHs
    }
    let L0: Float = 2 * (halfSlot + rodCoreR)
    let L: Float = L0 + sweep * rc
    let lengthRatio: Float = L0 / L
    let k: Float = pow(lengthRatio, 0.75)
    m.baseColor = .init(tint: lin(V3(0.01, 0.01, 0.01))); m.metallic = 0.0; m.roughness = 0.4
    m.emissiveColor = .init(texture: T(tex.arcEmi[c])); m.emissiveIntensity = tune.rodEmissive * k * tune.glow
    m.blending = .transparent(opacity: .init(scale: 1.0, texture: T(tex.arcAlpha)))
    m.specular = 0.0
    return m
}
