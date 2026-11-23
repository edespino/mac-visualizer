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
// RealityKit side of the Tri-wing: entities, materials and the spin-blur overlay.
import RealityKit
import AppKit
import Foundation
import simd
import MacVisualizerCore

/// Texture resources of the Tri-wing (brushed body, ray-patterned pads).
@MainActor @available(macOS 15.0, *)
struct RKTWTextures {
    var bodyColor: TextureResource, bodyRough: TextureResource, bodyNormal: TextureResource
    var padColor: TextureResource, padRough: TextureResource, padNormal: TextureResource
    var hubColor: TextureResource?, hubRough: TextureResource?, hubNormal: TextureResource?
    var smearProfiles: [TriWingSmear] = []      // [face]: the colour images are built per metal combination (RKTriWing.updateSmear)
    var smearOpacity: TextureResource?, glowEmissive: TextureResource?, glowOpacity: TextureResource?
    var shellFade: TextureResource?, bandFade: TextureResource?
    var glowWingOpacity: [TextureResource] = []
    var glowRamp: TextureResource?, glintOpacity: TextureResource?, jewelColor: TextureResource?
    var tubeEdgeEmissive: TextureResource?, tubeEdgeOpacity: TextureResource?, slotWallEmissive: TextureResource?
    var turnedColor: TextureResource?, turnedRough: TextureResource?, turnedNormal: TextureResource?

    static func make(_ im: TWImages, smear: TWSmearImages?) async throws -> RKTWTextures {
        func gen(_ i: CGImage, _ s: TextureResource.Semantic) async throws -> TextureResource {
            try await TextureResource(image: i, options: .init(semantic: s, mipmapsMode: .allocateAndGenerateAll))
        }
        let bc = try await gen(im.body.color, .color)
        let br = try await gen(im.body.rough, .scalar)
        let bn = try await gen(im.body.normal, .normal)
        let pc = try await gen(im.pad.color, .color)
        let pr = try await gen(im.pad.rough, .scalar)
        let pn = try await gen(im.pad.normal, .normal)
        var out = RKTWTextures(bodyColor: bc, bodyRough: br, bodyNormal: bn, padColor: pc, padRough: pr, padNormal: pn)
        out.hubColor = try await gen(im.hub.color, .color)
        out.hubRough = try await gen(im.hub.rough, .scalar)
        out.hubNormal = try await gen(im.hub.normal, .normal)
        out.glowRamp = try await gen(im.ramp, PhysicallyBasedMaterial.Opacity.textureSemantic)
        out.slotWallEmissive = try await gen(im.slotWall, PhysicallyBasedMaterial.EmissiveColor.textureSemantic)
        out.glintOpacity = try await gen(im.glint, PhysicallyBasedMaterial.Opacity.textureSemantic)
        out.jewelColor = try await gen(im.jewel, .color)
        out.turnedColor = try await gen(im.turned.color, .color)
        out.turnedRough = try await gen(im.turned.rough, .scalar)
        out.turnedNormal = try await gen(im.turned.normal, .normal)
        out.tubeEdgeEmissive = try await gen(im.tubeEdge, PhysicallyBasedMaterial.EmissiveColor.textureSemantic)
        out.tubeEdgeOpacity = try await gen(im.tubeEdgeOpacity, PhysicallyBasedMaterial.Opacity.textureSemantic)
        if let sm = smear {
            out.smearProfiles = sm.profiles
            out.smearOpacity = try await gen(sm.opacity, PhysicallyBasedMaterial.Opacity.textureSemantic)
            out.glowEmissive = try await gen(sm.glowEmissive, PhysicallyBasedMaterial.EmissiveColor.textureSemantic)
            out.glowOpacity = try await gen(sm.glowOpacity, PhysicallyBasedMaterial.Opacity.textureSemantic)
            for img in sm.glowWingOpacity { out.glowWingOpacity.append(try await gen(img, PhysicallyBasedMaterial.Opacity.textureSemantic)) }
            out.shellFade = try await gen(sm.shellFade, PhysicallyBasedMaterial.Opacity.textureSemantic)
            out.bandFade = try await gen(sm.bandFade, PhysicallyBasedMaterial.Opacity.textureSemantic)
        }
        return out
    }
}

/// NSColors of the three wing colours for each light part's treatment (made once per colour change).
struct RKLightTints {
    var emissive: [NSColor] = []      // twLightColor: tube cores and shells, slot walls and floors, lips, pad tints, window lenses
    var coreBase: [NSColor] = []      // near-black base tint of the tube filament
    var shellBase: [NSColor] = []
    var ring: [NSColor] = []          // swept light rings
    var bandUpper: NSColor
    var bandLower: NSColor

    /// The original wing colours, built from exactly the values the original materials use.
    static let original: RKLightTints = RKLightTints(raw: [tubeColors[0], tubeColors[1], tubeColors[2]], band: (twSideBand.upper, twSideBand.lower))

    init(raw: [V3], band: (upper: SIMD3<Float>, lower: SIMD3<Float>)? = nil) {
        for k in 0..<3 {
            let col: V3 = twLightColor(raw: raw[k])
            emissive.append(lin(col))
            coreBase.append(lin(col * 0.05))
            shellBase.append(lin(col * 0.06))
            ring.append(lin(TriWingLightColours.ringColour(raw[k])))
        }
        let band = band ?? TriWingSwept.sideBandColours(wingColours: [raw[0], raw[1], raw[2]])
        bandUpper = lin(V3(band.upper.x, band.upper.y, band.upper.z))
        bandLower = lin(V3(band.lower.x, band.lower.y, band.lower.z))
    }
}

@MainActor @available(macOS 15.0, *)
final class RKTriWing {
    var twTex: RKTWTextures!
    /// Turns with the body (solid parts, tubes, smear overlay); the hub group is static.
    let spin = Entity(), hub = Entity(), tubes = Entity(), glow = Entity(), solid = Entity(), smear = Entity()
    /// Swept wing zone (translucent face part and thin shells) and the swept light rings and side band.
    let zone = Entity(), swGlow = Entity(), swBand = Entity()
    /// Swept volume of the spinning body: an opaque core and translucent shells (see `TriWingSmear.sweptShells`).
    let core = Entity()
    var shellOpacities: [Float] = []
    var entities: [(ModelEntity, TWKind)] = []
    /// Unlit twins of the lit tube and slot parts (see `build`).
    var entitiesOff: [(ModelEntity, TWKind)] = []
    var litEdgeEntities: [ModelEntity] = []
    var curGlow: Float = -1
    var curBlurT: Float = -1
    var curEdge: Bool? = nil

    /// Creates the entities from CPU meshes (sort order for the transparent parts comes from `sort`).
    func build(geometry g: TWGeometryCPU, sort: ModelSortGroup, step: () async -> Void) async throws {
        shellOpacities = g.shellOpacities
        if let images = g.images { twTex = try await RKTWTextures.make(images, smear: g.smearImages) }
        for p in g.parts {
            let mesh = try p.mb.resource(name: p.name)
            func place(_ e: ModelEntity) {
                switch p.group {
                case .spin: solid.addChild(e)
                case .tube: tubes.addChild(e)
                case .glow: glow.addChild(e)
                case .hub: hub.addChild(e)
                case .smear: smear.addChild(e)
                case .sweptCore: core.addChild(e)
                case .zone: zone.addChild(e)
                case .sweptGlow: swGlow.addChild(e)
                case .sweptBand: swBand.addChild(e)
                }
                switch p.kind {
                case .tubeCore: e.components.set(ModelSortGroupComponent(group: sort, order: -2))
                case .tubeShell: e.components.set(ModelSortGroupComponent(group: sort, order: -1))
                case .slotLip, .padTint: e.components.set(ModelSortGroupComponent(group: sort, order: 0))
                case .crystal: e.components.set(ModelSortGroupComponent(group: sort, order: 2))
                case .glint: e.components.set(ModelSortGroupComponent(group: sort, order: 3))
                case .smearBody: e.components.set(ModelSortGroupComponent(group: sort, order: 1))
                case .sweptShell: e.components.set(ModelSortGroupComponent(group: sort, order: -5))
                case .smearZone: e.components.set(ModelSortGroupComponent(group: sort, order: 2))
                case .smearGlow, .smearGlowWing: e.components.set(ModelSortGroupComponent(group: sort, order: 3))
                case .sideBand: e.components.set(ModelSortGroupComponent(group: sort, order: -10))
                default: break
                }
            }
            let e = ModelEntity(mesh: mesh, materials: [])
            if case .smearGlowWing = p.kind { e.isEnabled = false }   // used only while the lights follow the palette
            place(e)
            entities.append((e, p.kind))
            if twIsTube(p.kind) {
                litEdgeEntities.append(e)
                // The Edge lights setting does not swap materials (RealityKit ignores a runtime swap between materials of a
                // different structure: textures, blending): each lit part has an unlit twin, and one of the two is enabled.
                let twin = ModelEntity(mesh: mesh, materials: [])
                twin.isEnabled = false
                place(twin)
                entitiesOff.append((twin, p.kind))
            }
            await step()
        }
        spin.addChild(solid)
        spin.addChild(tubes)
        spin.addChild(glow)
        spin.addChild(smear)
        spin.addChild(core)
        spin.addChild(zone)
        spin.addChild(swGlow)
        spin.addChild(swBand)
        smear.isEnabled = false
        core.isEnabled = false
        zone.isEnabled = false
        swGlow.isEnabled = false
        swBand.isEnabled = false
        spin.isEnabled = false
        hub.isEnabled = false
    }

    /// Lit materials of the edge-light parts (the unlit twins carry their own fixed materials).
    var tubeLit: [TWKind: PhysicallyBasedMaterial] = [:]

    /// Metal- and glow-dependent materials; parts whose look is fixed are built once. The body metal drives the body, hub and
    /// swept volume, the plate metal the wing plates, the boss metal the bosses.
    func applyMaterials(body: RKMetal, plate: RKMetal, boss: RKMetal, glowValue: Float, tex: RKPuckTextures, tune: RKTuning) {
        let first: Bool = curBodyName.isEmpty
        let bodyChanged: Bool = body.name != curBodyName
        let plateChanged: Bool = plate.name != curPlateName
        let bossChanged: Bool = boss.name != curBossName
        let glowChanged: Bool = glowValue != curGlow
        if !first && !bodyChanged && !plateChanged && !bossChanged && !glowChanged { return }
        var cache: [TWKind: PhysicallyBasedMaterial] = [:]
        for (e, k) in entities {
            let role: Int = twMetalRole(k)
            let metalDependent: Bool = (role == 1 && bodyChanged) || (role == 2 && plateChanged) || (role == 3 && bossChanged)
            let glowDependent: Bool = twGlowDependent(k)
            if !first {
                if !metalDependent && !(glowChanged && glowDependent) { continue }
            }
            if case .smearBody = k { continue }   // built per metal combination by updateSmear
            if case .smearZone = k { continue }
            if twIsTube(k) {
                if tubeLit[k] == nil || glowChanged {
                    tubeLit[k] = makeTWMaterial(k, metal: body, tex: tex, twTex: twTex, tune: tune, lit: true)
                }
                e.model?.materials = [tubeLit[k]!]
                continue
            }
            if cache[k] == nil { cache[k] = makeTWMaterial(k, metal: body, plate: plate, boss: boss, tex: tex, twTex: twTex, tune: tune, shellOpacities: shellOpacities) }
            e.model?.materials = [cache[k]!]
        }
        if first {
            for (e, k) in entitiesOff {
                e.model?.materials = [makeTWMaterial(k, metal: body, tex: tex, twTex: twTex, tune: tune, lit: false)]
            }
        }
        if first || glowChanged {
            appliedLightIdx = min(32, max(0, Int((tune.light * 32).rounded())))   // light kinds were rebuilt at tune.light
            tintDirty = true                                                         // ... with the original colours
        }
        curBodyName = body.name
        curPlateName = plate.name
        curBossName = boss.name
        curMetals = (body, plate, boss)
        curGlow = glowValue
        updateSmear()
        updateCrystal()
    }
    var curBodyName = "", curPlateName = "", curBossName = ""
    var curMetals: (RKMetal, RKMetal, RKMetal)? = nil
    var smearCache: [String: TextureResource] = [:]
    var curSmearKey = ""

    /// Builds (once per combination) and applies the smeared overlay's colour images for the current body, plate and boss
    /// metals. Only while the overlay is in use (blur above 0); the images are a radial lookup, so this is a few milliseconds.
    func updateSmear() {
        guard blurT > 0, let t = twTex, let m = curMetals, !t.smearProfiles.isEmpty else { return }
        let key: String = "\(m.0.name)|\(m.1.name)|\(m.2.name)"
        if key == curSmearKey { return }
        curSmearKey = key
        var perFace: [TextureResource?] = []
        for (face, profile) in t.smearProfiles.enumerated() {
            let ck: String = "\(face)|" + key
            if let cached = smearCache[ck] { perFace.append(cached); continue }
            let img: CGImage = makeTWSmearColorImage(profile: profile, body: m.0.f0, plate: m.1.f0, boss: m.2.f0)
            let tex: TextureResource? = try? TextureResource.generate(from: img, withName: nil, options: .init(semantic: .color))
            if let tex = tex { smearCache[ck] = tex }
            perFace.append(tex)
        }
        for (e, k) in entities {
            if case .smearBody(let face) = k, face < perFace.count {
                e.model?.materials = [makeTWSmearBodyMaterial(color: perFace[face], twTex: t)]
            }
            if case .smearZone(let face) = k, face < perFace.count {
                e.model?.materials = [makeTWSmearBodyMaterial(color: perFace[face], twTex: t)]
            }
        }
    }

    // ------------------------------------------------------------------------------------------
    // Light level (beat pulse). The level is quantised to 1/32, so there are only 33 distinct looks. Building the edge lights'
    // PhysicallyBasedMaterial values costs about 19 ms per level change in a Release build (measured), more than a whole frame,
    // so each (level, kind) material is built at most once per (glow, body metal) and reused: a level change is then only the
    // assignment of ready materials. The cache is filled a little per frame (`warmLight`, a few ms of budget) starting with the
    // levels nearest to the one asked for, and until the exact level is ready the nearest ready level is shown, so a pulse never
    // waits on a build. Probes set `exactLight` so stills build the exact level at once (identical to a freshly built material).
    // ------------------------------------------------------------------------------------------
    /// Edge-light entities (lit parts only; the unlit twins carry fixed materials) and their distinct kinds, built on first use.
    private var lightEntities: [(ModelEntity, TWKind)] = []
    private var lightKinds: [TWKind] = []
    private var lightListBuilt = false
    private var lightCache: [Int: [TWKind: PhysicallyBasedMaterial]] = [:]
    /// Everything the cached light materials depend on: Glow, the body, plate and boss metals and the Edge lights state. (The
    /// light parts' materials use none of the metals and are the same lit or unlit, so these are defensive: a stale material can
    /// never be served whatever a later change to a light material starts to use.) The light COLOURS are deliberately not in
    /// it: cached materials carry the original colours and the palette colours are applied in place when they are assigned.
    private var lightCacheKey: String = ""
    private func currentLightKey(_ tune: RKTuning) -> String { "\(tune.glow)|\(curBodyName)|\(curPlateName)|\(curBossName)|\(edge)" }
    /// Level (0...32) whose materials are on the entities now, and the level last asked for.
    private(set) var appliedLightIdx: Int = 32
    private var wantedLightIdx: Int = 32
    private var lightEverChanged = false
    /// Probe stills: build the exact level synchronously instead of showing a neighbour while the cache fills.
    var exactLight = false
    /// Entities touched by the last level change (0 when nothing was assigned) and materials built over the lifetime (stats).
    private(set) var lastLightTouched: Int = 0
    private(set) var lightMaterialsBuilt: Int = 0

    private func buildLightListIfNeeded() {
        if lightListBuilt { return }
        lightListBuilt = true
        var seen: Set<TWKind> = []
        for (e, k) in entities where twLightDependent(k) {
            if case .smearGlowWing = k, tints == nil { continue }   // only while the lights follow the palette
            lightEntities.append((e, k))
            if !seen.contains(k) { seen.insert(k); lightKinds.append(k) }
        }
    }

    private func lightLevelComplete(_ idx: Int) -> Bool {
        guard let d = lightCache[idx] else { return false }
        for k in lightKinds where d[k] == nil { return false }
        return true
    }

    private func buildLightMaterial(_ k: TWKind, idx: Int, metal: RKMetal, tex: RKPuckTextures, tune: RKTuning) -> PhysicallyBasedMaterial {
        var t: RKTuning = tune
        t.light = Float(idx) / 32
        if twIsTube(k) { return makeTWMaterial(k, metal: metal, tex: tex, twTex: twTex, tune: t, lit: true) }
        return makeTWMaterial(k, metal: metal, tex: tex, twTex: twTex, tune: t, shellOpacities: shellOpacities)
    }

    private func assignLight(_ idx: Int) {
        guard let d = lightCache[idx] else { return }
        var touched: Int = 0
        for (e, k) in lightEntities {
            guard var mat = d[k] else { continue }
            if twIsTube(k) { tubeLit[k] = mat }
            if let t = tints { applyTint(&mat, k, t) }
            e.model?.materials = [mat]
            touched += 1
        }
        lastLightTouched = touched
        appliedLightIdx = idx
    }

    /// Light level (see `SpinnerLightPulse`), already quantised by the caller. Shows that level's edge-light materials (tubes,
    /// slot glow, lip lines, pad tints, smeared glow rings: `twLightDependent`) from the cache, or the nearest ready level while
    /// the exact one is still being built. Returns the level (a multiple of 1/32) that is actually showing.
    @discardableResult
    func applyLight(_ level: Float, metal: RKMetal, tex: RKPuckTextures, tune: RKTuning) -> Float {
        buildLightListIfNeeded()
        let idx: Int = min(32, max(0, Int((level * 32).rounded())))
        wantedLightIdx = idx
        let key: String = currentLightKey(tune)
        if lightCacheKey != key {
            lightCache.removeAll()
            lightCacheKey = key
        }
        if idx != appliedLightIdx { lightEverChanged = true }
        var target: Int = idx
        if !lightLevelComplete(idx) {
            if exactLight {
                var d: [TWKind: PhysicallyBasedMaterial] = lightCache[idx] ?? [:]
                for k in lightKinds where d[k] == nil {
                    d[k] = buildLightMaterial(k, idx: idx, metal: metal, tex: tex, tune: tune)
                    lightMaterialsBuilt += 1
                }
                lightCache[idx] = d
            } else {
                target = appliedLightIdx
                var best: Int = Int.max
                for j in 0...32 where lightLevelComplete(j) {
                    let dist: Int = abs(j - idx)
                    if dist < best { best = dist; target = j }
                }
            }
        }
        if target != appliedLightIdx && lightLevelComplete(target) {
            assignLight(target)
            tintPending = false
            tintDirty = false
        } else if target != appliedLightIdx {
            assignLight(target)
        }
        if tintPending || tintDirty { retint() }
        return Float(appliedLightIdx) / 32
    }

    /// Fills the cache a little per call (never more than `budgetMs` plus one material), nearest levels to the wanted one
    /// first. Idle until the level has changed once, so users without beat lights never build anything. Returns true while work remains.
    @discardableResult
    func warmLight(budgetMs: Double, metal: RKMetal, tex: RKPuckTextures, tune: RKTuning) -> Bool {
        if !on || !lightEverChanged || lightKinds.isEmpty { return false }
        if lightCacheKey != currentLightKey(tune) { return true }   // applyLight resets the cache next
        let start: UInt64 = DispatchTime.now().uptimeNanoseconds
        for d in 0...32 {
            for sign in 0..<2 {
                let idx: Int = sign == 0 ? wantedLightIdx + d : wantedLightIdx - d
                if sign == 1 && d == 0 { continue }
                if idx < 0 || idx > 32 { continue }
                if lightLevelComplete(idx) { continue }
                var dict: [TWKind: PhysicallyBasedMaterial] = lightCache[idx] ?? [:]
                for k in lightKinds where dict[k] == nil {
                    dict[k] = buildLightMaterial(k, idx: idx, metal: metal, tex: tex, tune: tune)
                    lightMaterialsBuilt += 1
                    lightCache[idx] = dict
                    let elapsedMs: Double = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
                    if elapsedMs >= budgetMs { return true }
                }
            }
        }
        return false
    }

    // ------------------------------------------------------------------------------------------
    // Light colours (palette mode). The cached light materials carry the original colours. In palette mode each assignment of
    // a cached material first changes its emissive colour (and the near-black base tint of the tube parts) to the wing's
    // palette colour: a few property writes on a value copy, no structural change, so it applies live. A colour change with
    // no level change re-tints and re-assigns the same (cached) level. Colours reach here already quantised (1/64 per channel).
    // ------------------------------------------------------------------------------------------
    private var tints: RKLightTints? = nil
    private var appliedColours: [V3]? = nil
    private(set) var colourKey: String = "original"
    private var tintPending = false
    private var tintDirty = false
    /// Light entities re-assigned by the last colour change (stats).
    private(set) var lastTintTouched: Int = 0

    /// Wing colours for the lights (three, brightest channel 1, from `TriWingLightColours`), or nil for the original colours.
    func setLightColours(_ raw: [V3]?) {
        if raw == appliedColours { return }
        let wasPalette: Bool = tints != nil
        appliedColours = raw
        if let r = raw, r.count >= 3 {
            tints = RKLightTints(raw: r)
            var parts: [String] = []
            for c in r { parts.append("\(Int((c.x * 64).rounded())).\(Int((c.y * 64).rounded())).\(Int((c.z * 64).rounded()))") }
            colourKey = parts.joined(separator: "/")
        } else {
            tints = nil
            colourKey = "original"
        }
        tintPending = true
        if (tints != nil) != wasPalette {
            let palette: Bool = tints != nil
            for (e, k) in entities {
                if case .smearGlow = k { e.isEnabled = !palette }
                if case .smearGlowWing = k { e.isEnabled = palette }
            }
            // The cache is kept (its materials carry the original colours whatever the mode); levels built before the switch
            // are complete again once their few missing wing-ring materials are built (`lightLevelComplete`, `warmLight`).
            lightListBuilt = false
            lightEntities.removeAll()
            lightKinds.removeAll()
        }
    }

    private func applyTint(_ m: inout PhysicallyBasedMaterial, _ k: TWKind, _ t: RKLightTints) {
        switch k {
        case .tubeCore(let c): m.baseColor.tint = t.coreBase[c % 3]; m.emissiveColor.color = t.emissive[c % 3]
        case .tubeShell(let c): m.baseColor.tint = t.shellBase[c % 3]; m.emissiveColor.color = t.emissive[c % 3]
        case .slotWall(let c), .slotFloor(let c), .slotLip(let c), .padTint(let c), .windowLens(let c):
            m.emissiveColor.color = t.emissive[c % 3]
        case .smearGlowWing(let c): m.emissiveColor.color = t.ring[c % 3]
        case .sideBand(let half): m.emissiveColor.color = half == 0 ? t.bandUpper : t.bandLower
        default: break
        }
    }

    /// Applies the current colours (or restores the originals) to the entities' current level without a level change.
    private func retint() {
        tintPending = false
        tintDirty = false
        let cached: [TWKind: PhysicallyBasedMaterial]? = lightLevelComplete(appliedLightIdx) ? lightCache[appliedLightIdx] : nil
        var touched: Int = 0
        for (e, k) in lightEntities {
            var mat: PhysicallyBasedMaterial
            if let c = cached, let m = c[k] {
                mat = m
            } else if let m = e.model?.materials.first as? PhysicallyBasedMaterial {
                mat = m                 // entity material is a base or already tinted material: tinting is idempotent
            } else {
                continue
            }
            // No cached level to restore from: the original colours are applied in place the same way (never a rebuild).
            applyTint(&mat, k, tints ?? RKLightTints.original)
            e.model?.materials = [mat]
            touched += 1
        }
        lastTintTouched = touched
    }

    /// The crystal (and its reflection band) are clear: in the shadow pass they are left out so the glass casts no shadow of
    /// its own into the open bearing gap (the shadow-by-difference pass would otherwise see a solid disc).
    func setShadowPass(_ on: Bool) {
        for (e, k) in entities {
            switch k {
            case .crystal, .crystalRim, .glint, .slotLip, .padTint: e.isEnabled = !on
            case .windowLens: e.isEnabled = on ? false : edge      // lit lens: back to the Edge lights state afterwards
            default: break
            }
        }
        for (e, k) in entitiesOff {
            if case .windowLens = k { e.isEnabled = on ? false : !edge }
        }
    }

    var curPitch: Float = 0
    var curYaw: Float = 0
    var tiltKey: String = ""

    /// Crystal look follows the pose: the blue anti-reflective sheen builds with the glancing angle, and the dim window ghost
    /// appears only near the pose that mirrors the key light into the camera and slides across each face's glass as the
    /// part tilts (see `TriWingCrystal`). Cheap: two small materials, only when the tilt changes.
    func setTilt(pitch: Float, yaw: Float) {
        curPitch = pitch
        curYaw = yaw
        updateCrystal()
    }

    func updateCrystal() {
        guard let t = twTex else { return }
        let key: String = "\(curPitch)|\(curYaw)"
        if key == tiltKey && !glintDirty { return }
        tiltKey = key
        glintDirty = false
        let sheen: Float = TriWingCrystal.sheenOpacity(pitch: curPitch, yaw: curYaw)
        for (e, k) in entities {
            switch k {
            case .crystal:
                e.model?.materials = [makeCrystalMaterial(sheen: sheen)]
            case .glint(let face):
                let strength: Float = TriWingCrystal.ghostStrength(pitch: curPitch, yaw: curYaw, face: face)
                let offset = TriWingCrystal.ghostOffset(pitch: curPitch, yaw: curYaw, face: face)
                e.model?.materials = [makeGlintMaterial(twTex: t, strength: strength, offset: SIMD2<Float>(offset.x, offset.y))]
            default: break
            }
        }
    }
    var glintDirty = true

    /// Shows the lit parts or their unlit twins (idempotent; done before the groups are enabled so the states are final
    /// when RealityKit first activates the entities).
    private func refreshEdgeEntities() {
        for e in litEdgeEntities where e.isEnabled != edge { e.isEnabled = edge }
        for (e, _) in entitiesOff where e.isEnabled == edge { e.isEnabled = !edge }
    }

    var on = false
    var edge = true
    var blurT: Float = 0

    /// Enables the groups for the chosen model: nothing here is built or destroyed, so switching never hitches.
    func setVisible(_ visible: Bool, edgeLights: Bool) {
        on = visible
        edge = edgeLights
        refreshEdgeEntities()
        refresh()
    }

    /// Spin blur 0 ... 1: crossfades the solid part (and its tubes) into the smeared overlay.
    func setBlur(_ t: Float) {
        if t == blurT && curBlurT >= 0 { return }
        blurT = t
        curBlurT = t
        let ramp: TriWingSwept.Ramp = TriWingSwept.ramp(t)
        let mid: Bool = t > 0 && t < 1
        solid.components.set(OpacityComponent(opacity: mid ? ramp.solid : 1))
        glow.components.set(OpacityComponent(opacity: mid ? 1 - t : 1))
        tubes.components.set(OpacityComponent(opacity: mid ? 1 - t : 1))
        smear.components.set(OpacityComponent(opacity: mid ? ramp.core : 1))
        zone.components.set(OpacityComponent(opacity: mid ? ramp.zone : 1))
        swGlow.components.set(OpacityComponent(opacity: mid ? ramp.zone : 1))
        swBand.components.set(OpacityComponent(opacity: mid ? ramp.core : 1))
        updateSmear()
        refresh()
    }

    private func refresh() {
        spin.isEnabled = on
        hub.isEnabled = on
        solid.isEnabled = blurT < 1
        tubes.isEnabled = on && blurT < 1
        glow.isEnabled = on && edge && blurT < 1
        smear.isEnabled = blurT > 0
        core.isEnabled = blurT > 0
        zone.isEnabled = blurT > 0
        swGlow.isEnabled = blurT > 0 && edge
        swBand.isEnabled = blurT > 0 && edge
    }
}

// Finish of the flat metal faces. A flat, polished face mirrors the key light across its whole area at one pose (where the key
// light's reflection meets the camera), which clips to flat white if the face is smooth. Rough, darker finishes keep the peak
// below clipping; the hub's turned finish and the plates' rays are texture detail on top. Values were tuned in stills at the
// mirror pose (pitch 19.8, yaw -19.2) and neighbouring poses.
let twBodyTint: Float = 0.60
let twBodyRoughScale: Float = 1.5      // times the body texture's roughness (about 0.46)
let twBodyMetallic: Float = 0.85       // a little diffuse keeps tilted faces from going black
let twPadTint: Float = 0.60
let twPadRoughScale: Float = 1.6       // times the plate texture's roughness (about 0.40)
let twPadMetallic: Float = 0.80
let twZirconiumLift: Float = 2.2       // plate and boss tint multiplier for black zirconium
let twWarmLift: Float = 1.10           // plate and boss tint multiplier for brass and copper (they read olive at the base tint)
let twRingTint: Float = 0.45
let twRingRough: Float = 0.65
let twFluteTint: Float = 0.26
let twFluteRough: Float = 0.70
let twHubTint: Float = 0.38
let twHubEmissive: Float = 0.08        // times the hub tone texture: keeps the turning visible face-on

// Edge-light look of the Tri-wing (its own values; the disc's rods are separate materials). Emissive intensities are
// multiplied by the Glow brightness setting; at 1 every channel stays below clipping so the tubes keep their colour.
let twFilamentEmissive: Float = 0.80
let twFilamentWhite: Float = 0.0
let twShellEmissive: Float = 0.90
let twShellOpacity: Float = 0.80
/// Saturation lift of the wing colours for the Tri-wing's lights (1 = the disc's colours).
let twLightSaturation: Float = 1.45
/// Light the tubes throw into their slots. Each overlay carries its intensity in the texture coordinate (a linear ramp
/// texture turns it into opacity); emissive strength and peak opacity per overlay below.
let twSlotWallEmissive: Float = 0.50
let twSlotFloorEmissive: Float = 0.30
let twSlotLipEmissive: Float = 1.7
let twSlotLipOpacity: Float = 0.90
let twPadTintEmissive: Float = 1.1
let twPadTintOpacity: Float = 0.55
/// Slot-wall glow at fractional slot height h (0 floor, 1 lip): full from the floor to just above the tube centre, then a
/// smooth falloff up to the lip. Baked into the wall's emissive texture (v runs 0 at the lip to 1 at the floor).
func twSlotWallIntensity(_ h: Float) -> Float {
    let above: Float = max(h - 0.15, 0)
    return 0.95 * exp(-above * 3.6)
}
/// Pad-tint intensity at `distance` from the nearest tube centre line: peak 0.7, gone a few hundredths away.
func twPadTintIntensity(distance: Float) -> Float {
    let x: Float = distance / 0.055
    return 0.7 * exp(-x * x)
}
let twSmearGlowEmissive: Float = 0.90
/// Emissive strength of an edge-light window's lens (times Glow brightness and the light level).
let twWindowEmissive: Float = 0.80

/// The wing colour of the Tri-wing's lights: the disc's colour with its saturation lifted (negative channels clamp to 0).
func twLightColor(_ c: Int) -> V3 { twLightColor(raw: tubeColors[c]) }
/// The same treatment for any wing colour (the palette's, see `TriWingLightColours`).
func twLightColor(raw col: V3) -> V3 {
    let grey: Float = col.x * 0.30 + col.y * 0.59 + col.z * 0.11
    let r: Float = max(grey + (col.x - grey) * twLightSaturation, 0)
    let g: Float = max(grey + (col.y - grey) * twLightSaturation, 0)
    let b: Float = max(grey + (col.z - grey) * twLightSaturation, 0)
    return V3(r, g, b)
}

/// Scales the shells' coverage-derived opacity (each wall is seen twice, near and far side, in a side view).
let twShellOpacityScale: Float = 0.38
/// Emissive share of the body colour on the thin shells (keeps the translucent wall from going black in the dark studio).
let twShellMetalLift: Float = 0.05

/// Which metal setting colours a part: 1 body (body, hub, swept volume), 2 wing plates, 3 bosses, 0 none (fixed materials).
func twMetalRole(_ k: TWKind) -> Int {
    switch k {
    case .bodyTop, .bodyChamfer, .bodyWall, .wellWall, .waistBevel, .waistFloor, .waistFlute, .windowFrame, .hubTurned, .hubChamfer, .hubWall, .sweptShell, .coreWall: return 1
    case .padTop, .padChamfer, .padWall: return 2
    case .bossTop, .bossChamfer, .bossWall: return 3
    default: return 0
    }
}
/// Parts with a lit and an unlit material that the Edge lights setting swaps (the tubes and the slot they sit in).
func twIsTube(_ k: TWKind) -> Bool {
    switch k {
    case .tubeCore, .tubeShell, .slotWall, .slotFloor, .windowLens: return true
    default: return false
    }
}
func twGlowDependent(_ k: TWKind) -> Bool {
    switch k {
    case .tubeCore, .tubeShell, .smearGlow, .smearGlowWing, .sideBand, .slotWall, .slotFloor, .slotLip, .padTint, .windowLens: return true
    default: return false
    }
}
/// Parts the light level (beat pulse) scales: the same set as Glow brightness (every emissive the edge lights produce).
func twLightDependent(_ k: TWKind) -> Bool { twGlowDependent(k) }

/// The crystal's clear top face: an anti-reflective coating seen as a thin blue sheen. No specular and no clearcoat (a
/// reflective clear layer would only mirror the dark studio and dull the bearing); only a blue emissive layer whose
/// opacity (`TriWingCrystal.sheenOpacity`) is zero face-on and grows with the glancing angle.
@MainActor @available(macOS 15.0, *)
func makeCrystalMaterial(sheen: Float) -> PhysicallyBasedMaterial {
    var m = PhysicallyBasedMaterial()
    m.baseColor = .init(tint: lin(twSheenBase))
    m.metallic = 0.0
    m.roughness = .init(floatLiteral: 1.0)
    m.specular = 0.0
    m.emissiveColor = .init(color: lin(V3(0.22, 0.34, 1.0)))
    m.emissiveIntensity = twSheenEmissivePerOpacity * sheen
    m.blending = .transparent(opacity: .init(floatLiteral: sheen))
    return m
}

/// Peak opacity of the window ghost and the emissive strengths of the glass layers.
let twGhostPeakOpacity: Float = 0.30
let twGhostEmissive: Float = 1.5
/// The sheen's emissive strength per unit of its opacity (emissive adds light regardless of opacity, so it is scaled with it).
let twSheenEmissivePerOpacity: Float = 0.9
/// Base colour of the sheen layer: near black. Its lit diffuse term is added at the layer's opacity over the dark hub and
/// bearing, and a saturated blue base (0.10, 0.16, 0.55) painted the whole well navy at steep tilt; the blue is the emissive's job.
let twSheenBase: V3 = V3(0.012, 0.016, 0.04)
/// Trace emissive of the cap jewel and the heat-blued screws (highlights and shading give them their form).
/// Trace emissive of the open bearing's races, balls and cage.
let twBearingLift: Float = 0.12
let twCageLift: Float = 0.08
let twJewelEmissive: Float = 0.12
let twScrewEmissive: Float = 0.12

/// The crystal's dim blue window ghost: an emissive layer whose opacity comes from the window texture (a soft rounded
/// four-pane window), scaled by `strength` (0 away from the mirror pose), slid by `offset` crystal diameters (the texture
/// spans 1.7 crystal diameters, so the transform offset is the position over 1.7, negated).
@MainActor @available(macOS 15.0, *)
func makeGlintMaterial(twTex: RKTWTextures?, strength: Float, offset: SIMD2<Float>) -> PhysicallyBasedMaterial {
    var m = PhysicallyBasedMaterial()
    m.baseColor = .init(tint: lin(V3(0.10, 0.16, 0.50)))
    m.metallic = 0.0
    m.roughness = .init(floatLiteral: 1.0)
    m.specular = 0.0
    m.emissiveColor = .init(color: lin(V3(0.22, 0.46, 1.0)))
    m.emissiveIntensity = twGhostEmissive
    if let t = twTex, let op = t.glintOpacity {
        let scale: Float = twGhostPeakOpacity * min(max(strength, 0), 1)
        m.blending = .transparent(opacity: .init(scale: scale, texture: .init(op)))
    }
    let shift = SIMD2<Float>(-offset.x / 1.7, -offset.y / 1.7)
    m.textureCoordinateTransform = .init(offset: shift, scale: SIMD2<Float>(1, 1), rotation: 0)
    return m
}

/// The swept face overlay (inside and beyond the full-coverage radius): its colour image (per face and metal combination,
/// from `RKTriWing.updateSmear`) times the zone opacity curve. Lit like turned metal: concentric anisotropy (the
/// tangent runs round the circle) gives the soft bow-tie highlight that stays fixed to the light as the part spins, and a
/// small emissive share of the colour keeps the translucent wing zone readable on a dark backdrop.
@MainActor @available(macOS 15.0, *)
func makeTWSmearBodyMaterial(color: TextureResource?, twTex: RKTWTextures?) -> PhysicallyBasedMaterial {
    var m = PhysicallyBasedMaterial()
    typealias T = PhysicallyBasedMaterial.Texture
    if let c = color {
        m.baseColor = .init(tint: lin(V3(twSweptFaceTint, twSweptFaceTint, twSweptFaceTint)), texture: T(c))
        m.emissiveColor = .init(color: lin(V3(1, 1, 1)), texture: T(c))
        m.emissiveIntensity = twSweptFaceEmissive
    }
    if let t = twTex, let op = t.smearOpacity {
        m.blending = .transparent(opacity: .init(scale: 1.0, texture: T(op)))
    }
    m.metallic = 0.85; m.roughness = .init(floatLiteral: twSweptFaceRoughness)
    m.specular = 0.5
    m.anisotropyLevel = .init(floatLiteral: twSweptAnisotropy)
    m.anisotropyAngle = .init(floatLiteral: 0)
    return m
}
let twSweptFaceEmissive: Float = 0.12
let twSweptFaceRoughness: Float = 0.64
let twSweptFaceTint: Float = 0.58
let twSweptAnisotropy: Float = 0.55
/// Side-band emissive strength and its peak opacity (times the window share of the waist circle).
let twSideBandEmissive: Float = 1.5
let twSideBandOpacityGain: Float = 3.0
/// Waist radius used for the side band's circle share (the full-coverage radius is about this).
let twSideBand: TriWingSwept.SideBand = TriWingSwept.sideBand(waistRadius: 0.60)

@MainActor @available(macOS 15.0, *)
func makeTWMaterial(_ k: TWKind, metal: RKMetal, plate: RKMetal? = nil, boss: RKMetal? = nil, tex: RKPuckTextures, twTex: RKTWTextures?, tune: RKTuning, lit: Bool = true, shellOpacities: [Float] = []) -> PhysicallyBasedMaterial {
    var m = PhysicallyBasedMaterial()
    typealias T = PhysicallyBasedMaterial.Texture
    let plateMetal: RKMetal = plate ?? metal
    /// Black zirconium is so dark that the plates' and bosses' finish (rays, polished ring) all but vanishes: a lift of their tint.
    func zl(_ m: RKMetal) -> Float {
        if m.name == "zirconium" { return twZirconiumLift }
        if m.name == "brass" || m.name == "copper" { return twWarmLift }
        return 1.0
    }
    let bossMetal: RKMetal = boss ?? metal
    func tinted(_ s: Float, _ of: RKMetal? = nil) -> PhysicallyBasedMaterial.BaseColor {
        let lift: Float = of != nil ? zl(of!) : 1.0
        let scaled: V3 = (of ?? metal).f0 * (s * lift)
        return PhysicallyBasedMaterial.BaseColor(tint: lin(scaled))
    }
    func fixed(_ r: Float, _ g: Float, _ b: Float) -> PhysicallyBasedMaterial.BaseColor {
        PhysicallyBasedMaterial.BaseColor(tint: lin(V3(r, g, b)))
    }
    func metalSet(_ rough: Float) { m.metallic = 1.0; m.roughness = .init(floatLiteral: rough) }
    /// Emissive-only translucent layer in a wing's light colour. Strength follows Glow brightness and the light level;
    /// opacity follows both up to 1 (a black-based transparent layer would otherwise darken what is under it at 0).
    func glowOverlay(_ mat: inout PhysicallyBasedMaterial, _ c: Int, emissive: Float, opacity: Float, ramp: Bool) {
        mat.baseColor = fixed(0.0, 0.0, 0.0); mat.metallic = 0.0; mat.roughness = .init(floatLiteral: 1.0)
        mat.emissiveColor = .init(color: lin(twLightColor(c)))
        mat.emissiveIntensity = emissive * tune.glow * tune.light
        let level: Float = min(max(tune.glow, 0), 1) * min(max(tune.light, 0), 1)
        let scale: Float = opacity * level
        if ramp, let t = twTex, let r = t.glowRamp {
            mat.blending = .transparent(opacity: .init(scale: scale, texture: T(r)))
        } else {
            mat.blending = .transparent(opacity: .init(floatLiteral: min(max(scale, 0), 1)))
        }
        mat.specular = 0.0
    }
    switch k {
    case .bodyTop, .padTop:
        let isPad: Bool = (k == .padTop)
        let tint: Float = isPad ? twPadTint * zl(plateMetal) : twBodyTint
        if let t = twTex {
            let color: TextureResource = isPad ? t.padColor : t.bodyColor
            let rough: TextureResource = isPad ? t.padRough : t.bodyRough
            let normal: TextureResource = isPad ? t.padNormal : t.bodyNormal
            m.baseColor = .init(tint: lin((isPad ? plateMetal : metal).f0 * tint), texture: T(color))
            m.roughness = .init(scale: isPad ? twPadRoughScale * (plateMetal.name == "zirconium" ? 0.8 : 1.0) : twBodyRoughScale, texture: T(rough))
            m.normal = .init(texture: T(normal))
        } else {
            m.baseColor = .init(tint: lin((isPad ? plateMetal : metal).f0 * tint))
            m.roughness = .init(floatLiteral: 0.45)
        }
        let metVal: Float = isPad ? twPadMetallic : twBodyMetallic
        m.metallic = .init(floatLiteral: metVal)
    case .bodyChamfer: m.baseColor = tinted(0.70); metalSet(0.14)
    case .bodyWall: m.baseColor = tinted(0.50); metalSet(0.26)
    case .coreWall:
        m.baseColor = tinted(0.58); metalSet(0.30)
        m.anisotropyLevel = .init(floatLiteral: twSweptAnisotropy)
        m.anisotropyAngle = .init(floatLiteral: 0)
    case .waistBevel: m.baseColor = tinted(0.80); metalSet(0.09)
    case .waistFloor, .waistFlute:
        // Fine turned lines (v of the band's texture coordinate) on a slightly darker, rougher floor than the satin wall.
        let isFlute: Bool = (k == .waistFlute)
        let tint: Float = isFlute ? 0.50 : 0.38
        if let t = twTex, let tc = t.turnedColor, let tr = t.turnedRough, let tn = t.turnedNormal {
            m.baseColor = .init(tint: lin(metal.f0 * tint), texture: T(tc))
            m.roughness = .init(scale: 1.0, texture: T(tr))
            m.normal = .init(texture: T(tn))
            m.metallic = 1.0
        } else {
            m.baseColor = tinted(tint); metalSet(0.40)
        }
    case .windowFrame: m.baseColor = tinted(0.90); metalSet(0.07)
    case .windowLens(let c):
        // Smoked glass: dark and glossy; lit, it glows in its wing's light colour (Glow brightness and light level).
        m.baseColor = fixed(0.012, 0.012, 0.016); m.metallic = 0.0; m.roughness = .init(floatLiteral: 0.10)
        m.clearcoat = .init(floatLiteral: 1.0); m.clearcoatRoughness = .init(floatLiteral: 0.03)
        if lit {
            m.emissiveColor = .init(color: lin(twLightColor(c)))
            m.emissiveIntensity = twWindowEmissive * tune.glow * tune.light
        }
    case .wellWall: m.baseColor = tinted(0.18); metalSet(0.40)
    case .slotFloor(let c):
        m.baseColor = fixed(0.012, 0.012, 0.015); metalSet(0.55)
        if lit {
            m.emissiveColor = .init(color: lin(twLightColor(c)))
            m.emissiveIntensity = twSlotFloorEmissive * tune.glow * tune.light
        }
    case .slotWall(let c):
        m.baseColor = fixed(0.10, 0.105, 0.115); metalSet(0.38)
        if lit, let t = twTex, let em = t.slotWallEmissive {
            m.emissiveColor = .init(color: lin(twLightColor(c)), texture: T(em))
            m.emissiveIntensity = twSlotWallEmissive * tune.glow * tune.light
        }
    case .slotLip(let c):
        glowOverlay(&m, c, emissive: twSlotLipEmissive, opacity: twSlotLipOpacity, ramp: false)
        return m
    case .padTint(let c):
        glowOverlay(&m, c, emissive: twPadTintEmissive, opacity: twPadTintOpacity, ramp: true)
        return m
    case .collar: m.baseColor = fixed(0.80, 0.81, 0.84); metalSet(0.10)
    case .padChamfer: m.baseColor = tinted(1.0, plateMetal); metalSet(0.06)
    case .padWall: m.baseColor = tinted(0.50, plateMetal); metalSet(0.28)
    case .bossTop: m.baseColor = tinted(0.97, bossMetal); metalSet(0.12)
    case .bossChamfer: m.baseColor = tinted(1.0, bossMetal); metalSet(0.05)
    case .bossWall: m.baseColor = tinted(0.50, bossMetal); metalSet(0.28)
    case .countersink: m.baseColor = fixed(0.80, 0.81, 0.83); metalSet(0.08)
    case .countersinkFloor: m.baseColor = fixed(0.02, 0.018, 0.016); metalSet(0.5)
    case .gold:
        // Polished yellow gold: a metal reflecting the dark studio reads olive, so it is part dielectric (lit base colour)
        // with a small warm emissive lift; the highlight stays sharp.
        m.baseColor = fixed(1.0, 0.78, 0.22); m.metallic = 0.55; m.roughness = .init(floatLiteral: 0.20)
        m.emissiveColor = .init(color: lin(V3(1.0, 0.62, 0.10))); m.emissiveIntensity = 0.55
    case .spring:
        // The spring is a lighter, mirror-polished gold so it reads against the satin block.
        m.baseColor = fixed(1.0, 0.84, 0.34); m.metallic = 0.80; m.roughness = .init(floatLiteral: 0.07)
        m.emissiveColor = .init(color: lin(V3(1.0, 0.70, 0.18))); m.emissiveIntensity = 0.5
    case .goldWall:
        m.baseColor = fixed(0.92, 0.66, 0.16); m.metallic = 0.60; m.roughness = .init(floatLiteral: 0.26)
        m.emissiveColor = .init(color: lin(V3(0.95, 0.52, 0.07))); m.emissiveIntensity = 0.30
    case .goldDark: m.baseColor = fixed(0.16, 0.10, 0.025); metalSet(0.45)
    case .jewelBlue:
        // Polished cabochon: painted radial depth (clear centre, deep rim) from a texture, a sharp clearcoat highlight,
        // and only a trace of emissive so the stone never goes black.
        if let t = twTex, let jc = t.jewelColor {
            m.baseColor = .init(tint: lin(V3(1, 1, 1)), texture: T(jc))
        } else {
            m.baseColor = fixed(0.03, 0.28, 1.0)
        }
        m.metallic = 0.0
        m.roughness = .init(floatLiteral: 0.04)
        m.clearcoat = .init(floatLiteral: 1.0)
        m.clearcoatRoughness = .init(floatLiteral: 0.02)
        m.emissiveColor = .init(color: lin(V3(0.02, 0.10, 0.80)))
        m.emissiveIntensity = twJewelEmissive
    case .screwBlue:
        // Heat-blued steel: saturated blue, polished (lit by the scene, not self-lit), part dielectric so it does not mirror black.
        m.baseColor = fixed(0.02, 0.12, 0.85); m.metallic = 0.55; m.roughness = .init(floatLiteral: 0.12)
        m.emissiveColor = .init(color: lin(V3(0.0, 0.03, 0.30))); m.emissiveIntensity = twScrewEmissive
    case .screwSlot: m.baseColor = fixed(0.008, 0.012, 0.045); metalSet(0.40)
    case .ringTop: m.baseColor = fixed(twRingTint, twRingTint * 1.01, twRingTint * 1.035); metalSet(twRingRough)
    case .ringChamfer: m.baseColor = fixed(0.88, 0.89, 0.91); metalSet(0.07)
    case .ringWall: m.baseColor = fixed(0.55, 0.56, 0.58); metalSet(0.18)
    case .flute:
        m.baseColor = fixed(twFluteTint, twFluteTint * 1.04, twFluteTint * 1.12); metalSet(twFluteRough)
    case .notchFloor:
        // The spanner slot's milled floor: satin metal, clearly lighter than the satin body around it.
        m.baseColor = fixed(0.78, 0.785, 0.80); m.metallic = 0.30; m.roughness = .init(floatLiteral: 0.50)
        m.emissiveColor = .init(color: lin(V3(0.70, 0.72, 0.78))); m.emissiveIntensity = 0.10
    case .notchFloorShade:
        m.baseColor = fixed(0.34, 0.345, 0.36); m.metallic = 0.20; m.roughness = .init(floatLiteral: 0.50)
    case .notchChamfer:
        // The slot's wide polished chamfer: a bright outline. Rough enough to catch light face-on instead of mirroring the studio.
        m.baseColor = fixed(0.97, 0.98, 1.0); metalSet(0.26)
        m.emissiveColor = .init(color: lin(V3(0.70, 0.72, 0.78))); m.emissiveIntensity = 0.18
    case .notchWall: m.baseColor = fixed(0.80, 0.81, 0.83); metalSet(0.34)
    case .letterFloor:
        // The engraved letters' floor: polished bright metal, rough enough that it glints rather than mirroring the dark studio.
        m.baseColor = fixed(0.97, 0.98, 1.0); metalSet(0.22)
        m.emissiveColor = .init(color: lin(V3(0.70, 0.72, 0.78))); m.emissiveIntensity = 0.22
    case .letterWall: m.baseColor = fixed(0.70, 0.71, 0.73); metalSet(0.16)
    case .engraveFloor:
        m.baseColor = fixed(0.010, 0.010, 0.012); m.metallic = 0.0; m.roughness = .init(floatLiteral: 0.7)
    case .engraveWall:
        m.baseColor = fixed(0.02, 0.02, 0.024); m.metallic = 0.0; m.roughness = .init(floatLiteral: 0.6)
    case .raceSteel, .innerRace:
        // A trace of emissive keeps the polished races readable at depth under the glass (the studio around them is dark).
        m.baseColor = fixed(0.82, 0.83, 0.85); metalSet(0.07)
        m.emissiveColor = .init(color: lin(V3(0.55, 0.57, 0.62))); m.emissiveIntensity = twBearingLift
    case .cage:
        // Satin steel, a little darker and rougher than the polished races and balls.
        m.baseColor = fixed(0.64, 0.65, 0.67); metalSet(0.24)
        m.emissiveColor = .init(color: lin(V3(0.55, 0.57, 0.62))); m.emissiveIntensity = twCageLift
    case .ballSteel:
        m.baseColor = fixed(0.90, 0.91, 0.93); metalSet(0.035)
        m.emissiveColor = .init(color: lin(V3(0.55, 0.57, 0.62))); m.emissiveIntensity = twBearingLift * 0.5
    case .tubeCore(let c):
        if lit {
            // A thin hot filament: the wing colour pushed a little toward white, kept below clipping so it stays saturated.
            let col: V3 = twLightColor(c)
            let hot: V3 = col + (V3(1, 1, 1) - col) * twFilamentWhite
            m.baseColor = .init(tint: lin(col * 0.05)); m.metallic = 0.0; m.roughness = .init(floatLiteral: 0.2)
            m.emissiveColor = .init(color: lin(hot)); m.emissiveIntensity = twFilamentEmissive * tune.glow * tune.light
            m.specular = 0.0
            return m
        }
        // Unlit: a pale glass tube, slightly translucent.
        m.baseColor = fixed(0.64, 0.65, 0.66); m.metallic = 0.0; m.roughness = .init(floatLiteral: 0.18)
        m.blending = .transparent(opacity: .init(floatLiteral: 0.75))
    case .tubeShell(let c):
        if lit {
            // Coloured glass: brighter toward the silhouette edges (emissive and opacity follow a cross-section texture),
            // so the tube reads as a lit rod with a darker centre instead of a flat bar.
            let col: V3 = twLightColor(c)
            m.baseColor = .init(tint: lin(col * 0.06)); m.metallic = 0.0; m.roughness = .init(floatLiteral: 0.05)
            m.clearcoat = .init(floatLiteral: 0.25); m.clearcoatRoughness = .init(floatLiteral: 0.04)
            if let t = twTex, let em = t.tubeEdgeEmissive, let op = t.tubeEdgeOpacity {
                m.emissiveColor = .init(color: lin(col), texture: T(em))
                m.blending = .transparent(opacity: .init(scale: twShellOpacity, texture: T(op)))
            } else {
                m.emissiveColor = .init(color: lin(col * 0.4))
                m.blending = .transparent(opacity: .init(floatLiteral: 0.3))
            }
            m.emissiveIntensity = twShellEmissive * tune.glow * tune.light
            m.specular = 0.5
            return m
        }
        m.baseColor = fixed(0.83, 0.84, 0.85); m.metallic = 0.0; m.roughness = .init(floatLiteral: 0.04)
        m.clearcoat = .init(floatLiteral: 1.0); m.clearcoatRoughness = .init(floatLiteral: 0.03)
        m.blending = .transparent(opacity: .init(floatLiteral: 0.30))
    case .hubTurned:
        if let t = twTex, let hc = t.hubColor, let hr = t.hubRough, let hn = t.hubNormal {
            m.baseColor = .init(tint: lin(metal.f0 * twHubTint), texture: T(hc))
            m.roughness = .init(scale: 1.0, texture: T(hr))
            m.normal = .init(texture: T(hn))
            m.metallic = 1.0
            m.emissiveColor = .init(color: lin(metal.f0), texture: T(hc)); m.emissiveIntensity = twHubEmissive
        } else { m.baseColor = tinted(0.85); metalSet(0.24) }
    case .hubChamfer: m.baseColor = tinted(1.0); metalSet(0.09)
    case .hubWall: m.baseColor = tinted(0.30); metalSet(0.35)
    case .crystal: return makeCrystalMaterial(sheen: 0)
    case .glint: return makeGlintMaterial(twTex: twTex, strength: 0, offset: SIMD2<Float>(0, 0))
    case .crystalRim: m.baseColor = fixed(0.95, 0.96, 1.0); metalSet(0.04)
    case .smearBody: return makeTWSmearBodyMaterial(color: nil, twTex: twTex)
    case .sweptShell(let i):
        // One shell of the swept volume: the satin body's side colour, translucent by the circle coverage at its radius.
        let a: Float = i < shellOpacities.count ? shellOpacities[i] : 0.03
        m.baseColor = tinted(0.58); metalSet(0.34)
        m.emissiveColor = .init(color: lin(metal.f0)); m.emissiveIntensity = twShellMetalLift
        m.anisotropyLevel = .init(floatLiteral: twSweptAnisotropy)
        m.anisotropyAngle = .init(floatLiteral: 0)
        m.faceCulling = .back
        if let t = twTex, let fade = t.shellFade {
            m.blending = .transparent(opacity: .init(scale: min(max(a, 0), 1), texture: T(fade)))
        } else {
            m.blending = .transparent(opacity: .init(floatLiteral: min(max(a, 0), 1)))
        }
    case .smearGlowWing(let c):
        // One wing's swept light ring: a neutral opacity mask tinted by the wing's colour (original colours here; the palette
        // mode tints it in place, see `RKTriWing.setLightColours`).
        m.baseColor = fixed(0.01, 0.01, 0.01); m.metallic = 0.0; m.roughness = .init(floatLiteral: 0.4)
        if let t = twTex, c < t.glowWingOpacity.count {
            m.emissiveColor = .init(color: lin(TriWingLightColours.ringColour(tubeColors[c])))
            m.emissiveIntensity = twSmearGlowEmissive * tune.glow * tune.light
            m.blending = .transparent(opacity: .init(scale: min(max(tune.glow, 0), 1) * min(max(tune.light, 0), 1), texture: T(t.glowWingOpacity[c])))
        }
        m.specular = 0.0
    case .sideBand(let half):
        m.baseColor = fixed(0.0, 0.0, 0.0); m.metallic = 0.0; m.roughness = .init(floatLiteral: 1.0)
        let col: SIMD3<Float> = half == 0 ? twSideBand.upper : twSideBand.lower
        m.emissiveColor = .init(color: lin(V3(col.x, col.y, col.z)))
        m.emissiveIntensity = twSideBandEmissive * tune.glow * tune.light
        let level: Float = min(max(tune.glow, 0), 1) * min(max(tune.light, 0), 1)
        let peak: Float = min(twSideBand.share * twSideBandOpacityGain, 0.95) * level
        if let t = twTex, let fade = t.bandFade {
            m.blending = .transparent(opacity: .init(scale: peak, texture: T(fade)))
        } else {
            m.blending = .transparent(opacity: .init(floatLiteral: peak))
        }
        m.specular = 0.0
        return m
    case .smearZone: return makeTWSmearBodyMaterial(color: nil, twTex: twTex)
    case .smearGlow:
        m.baseColor = fixed(0.01, 0.01, 0.01); m.metallic = 0.0; m.roughness = .init(floatLiteral: 0.4)
        if let t = twTex, let em = t.glowEmissive, let op = t.glowOpacity {
            m.emissiveColor = .init(texture: T(em))
            m.emissiveIntensity = twSmearGlowEmissive * tune.glow * tune.light
            m.blending = .transparent(opacity: .init(scale: min(max(tune.glow, 0), 1) * min(max(tune.light, 0), 1), texture: T(op)))
        }
        m.specular = 0.0
    }
    m.specular = 0.5
    return m
}
