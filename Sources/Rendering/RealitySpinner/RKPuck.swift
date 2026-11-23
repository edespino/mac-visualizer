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
    var webOpacity: TextureResource
    var arcEmi: [TextureResource], arcAlpha: TextureResource

    static func make(_ im: RKImages, step: @MainActor () async -> Void = {}) async throws -> RKPuckTextures {
        func gen(_ i: CGImage, _ s: TextureResource.Semantic) async throws -> TextureResource {
            let r = try await TextureResource(image: i, options: .init(semantic: s))
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
        let web = try await gen(im.webOpacity, PhysicallyBasedMaterial.Opacity.textureSemantic)
        var arcEmi: [TextureResource] = []
        for c in im.arcEmissive { arcEmi.append(try await gen(c, emi)) }
        let arcAlpha = try await gen(im.arcAlpha, PhysicallyBasedMaterial.Opacity.textureSemantic)
        return RKPuckTextures(face: face, faceRough: faceRough, faceNormal: faceNormal, faceEmi: faceEmi,
                              sFace: sFace, sFaceRough: sFaceRough, sFaceNormal: sFaceNormal, sFaceEmi: sFaceEmi,
                              webOpacity: web, arcEmi: arcEmi, arcAlpha: arcAlpha)
    }
}

// ---- materials ----
func lin(_ c: V3) -> NSColor {
    let red: CGFloat = CGFloat(srgbEncode(c.x))
    let green: CGFloat = CGFloat(srgbEncode(c.y))
    let blue: CGFloat = CGFloat(srgbEncode(c.z))
    return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
}


// ---- hub mark material constants (linear values) ----
let hubRaisedFloor: Float = 0.07          // level of the plain hub face in the raised finish (times the pale tint)
let engravedFaceLin: Float = 0.80
let engravedFloorLin: Float = 0.03
let engravedWallLin: Float = 1.0
let engravedFaceRough: Float = 0.12
let engravedFloorRough: Float = 0.65
let engravedWallRough: Float = 0.30
let hubGlowColor: V3 = V3(0.30, 0.75, 1.0)
/// Glow gain of a piece's tone level (the sign-off mark's dash, pair and "e").
let hubToneGain: [Float] = [0.45, 0.75, 1.0]
/// Top tone of a raised piece's level.
let hubToneLevels: [Float] = [0.6, 0.8, 1.0]
/// Share of the floor's glow the cut wall's emission carries (lit finish).
var hubWallGlowFraction: Float = 0.30
/// How much darker the raised mark's wall is than its top.
let hubRaisedWallDarkening: Float = 0.55

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
    var hubFinish = 0        // SpinnerHubFinish index: 0 lit, 1 raised, 2 engraved
    var glow: Float = 1      // multiplier on every emissive intensity (SpinnerSettings.glowBrightness)
    var light: Float = 1     // Tri-wing light level 0...1 (SpinnerLightPulse), a further multiplier on the edge lights' emissive
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

/// Face tint of the engraved hub: the body metal lightened part of the way (less than `raisedTint`), so the polished face
/// stays a metal of the same family while the matte floor stays clearly darker, in every metal including black zirconium.
func engravedTint(_ f0: V3) -> V3 {
    let toWhite: V3 = V3(1, 1, 1) - f0
    let lightened: V3 = f0 + toWhite * 0.60
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
        // The hub face outside the mark: a plain polished disc, no texture (the marks are real geometry). Dark in the lit
        // and raised finishes (the raised tint multiplies the old texture's top level), a light metal in the engraved one.
        if tune.hubFinish == 1 {
            let level: V3 = raisedTint(metal.f0) * hubRaisedFloor
            m.baseColor = .init(tint: lin(level)); m.metallic = 1.0; m.roughness = 0.10
        } else if tune.hubFinish == 2 {
            let level: V3 = engravedTint(metal.f0) * engravedFaceLin
            m.baseColor = .init(tint: lin(level)); m.metallic = 1.0; m.roughness = .init(floatLiteral: engravedFaceRough)
        } else {
            m.baseColor = .init(tint: lin(V3(0.05, 0.052, 0.058))); m.metallic = 1.0; m.roughness = 0.10
        }
    case .hubFloor(let level):
        if tune.hubFinish == 2 {
            // Engraved: unlit, a dark matte floor.
            let floorLevel: V3 = engravedTint(metal.f0) * engravedFloorLin
            m.baseColor = .init(tint: lin(floorLevel)); m.metallic = 1.0; m.roughness = .init(floatLiteral: engravedFloorRough)
        } else {
            // Lit: the channel floor glows with the mark colour, scaled by the piece's tone.
            let glowColor: V3 = hubGlowColor * hubToneGain[level]
            m.baseColor = .init(tint: lin(V3(0.008, 0.010, 0.014))); m.metallic = 1.0; m.roughness = 0.5
            m.emissiveColor = .init(color: lin(glowColor)); m.emissiveIntensity = tune.markEmissive * tune.glow
        }
    case .hubCutWall(let level):
        if tune.hubFinish == 2 {
            // Engraved: a lighter, glossier metal wall shaded by the real lights.
            let wallLevel: V3 = engravedTint(metal.f0) * engravedWallLin
            m.baseColor = .init(tint: lin(wallLevel)); m.metallic = 1.0; m.roughness = .init(floatLiteral: engravedWallRough)
        } else {
            // Lit: a dark metal wall that carries a fraction of the floor's glow, so it reads as lit by the floor.
            let wallGlow: V3 = hubGlowColor * hubToneGain[level] * hubWallGlowFraction
            m.baseColor = .init(tint: lin(V3(0.03, 0.032, 0.036))); m.metallic = 1.0; m.roughness = 0.38
            m.emissiveColor = .init(color: lin(wallGlow)); m.emissiveIntensity = tune.markEmissive * tune.glow
        }
    case .hubTop(let level):
        let tone: Float = hubToneLevels[level]
        let topBase: V3 = raisedTint(metal.f0)
        let topLevel: V3 = topBase * tone
        m.baseColor = .init(tint: lin(topLevel)); m.metallic = 1.0; m.roughness = 0.40
    case .hubTopWall(let level):
        let tone: Float = hubToneLevels[level]
        let wallGain: Float = tone * hubRaisedWallDarkening
        let wallBase: V3 = raisedTint(metal.f0)
        let wallLevel: V3 = wallBase * wallGain
        m.baseColor = .init(tint: lin(wallLevel)); m.metallic = 1.0; m.roughness = 0.34
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
