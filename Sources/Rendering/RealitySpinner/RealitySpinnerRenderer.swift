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
// RealityKit renderer for the Spinner puck (with GPU shadow and event-synchronised
// hand-off into the app's command buffer). Everything here is macOS 15+.
import RealityKit
import Metal
import MetalPerformanceShaders
import AppKit
import simd
import Foundation

func srgbDecode(_ x: Float) -> Float {
    if x <= 0.04045 { return x / 12.92 }
    let shifted: Float = (x + 0.055) / 1.055
    let exponent: Float = 2.4
    return pow(shifted, exponent)
}
func ssf(_ a: Float, _ b: Float, _ x: Float) -> Float {
    let raw: Float = (x - a) / (b - a)
    let t: Float = max(0, min(1, raw))
    let shape: Float = 3 - 2 * t
    return t * t * shape
}

enum RKPass { case puckOnly, puckGround, groundOnly, groundNoKey }

/// Per-frame inputs read from the same state the shader path uses.
struct RKFrameParams {
    var pitchRad: Float, yawRad: Float, spinRad: Float, omega: Float   // orientation: yaw after pitch in screen space
    var metal: Int, hubFinish: Int   // hubFinish: 0 lit, 1 raised
    var plateMetal: Int, bossMetal: Int   // tri-wing: EFFECTIVE metal indices of the wing plates and the bosses (0 steel ... 4 titanium)
    var zoom: Float                  // 1 = same on-screen size as the shader (aspect handled by the caller)
    var width: Int, height: Int
    var transparent: Bool            // per-pixel alpha or window opacity: drop shadow via difference pass
    var background: V3               // scene clear colour (opaque mode ground colour)
    var offsetX: Float, offsetY: Float   // clip-space content offset (same as the shader's)
    var hubRoll: Float               // self-levelling roll of the hub domes about the puck axis, radians (SpinnerHubRoll)
    var glow: Float                  // emission multiplier (rods, arcs, lit marks)
    var roomLight: Float             // multiplier on the key light and the environment
    var spinBlur: Float              // multiplier on the blur ramp and shutter (0 = no smeared overlays or arcs)
    var shadowDarkness: Float        // peak shadow opacity
    var shadowSpread: Float          // multiplier on the shadow blur sigma
    var shadowDistance: Float        // multiplier on the shadow's offset
    var model: Int                   // SpinnerModel index: 0 disc, 1 tri-wing
    var edgeLights: Bool             // tri-wing edge-light tubes
    var lightLevel: Float            // tri-wing light level 0...1 (beat pulse); 1 unless the model is tri-wing with edge lights on
    var lightColors: [V3]?           // tri-wing wing colours (three, quantised, brightest channel 1) when the lights follow the palette; nil = original
}

/// Mirrors `RKCopyUniforms` in Shaders.metal. The render target holds a square region centred on the puck; the copy
/// pass maps scene pixel p to region uv (p - regionOrigin) / regionSize (pixels), so the region can move without
/// reallocating anything.
struct RKCopyUniforms {
    var sceneSize: SIMD2<Float>
    var regionOrigin: SIMD2<Float>
    var regionSize: SIMD2<Float>
    var shadowOpacity: Float
    var useShadow: Float
}

@MainActor @available(macOS 15.0, *)
final class RealitySpinnerRenderer {
    let dev: MTLDevice
    let renderer: RealityRenderer
    let cam = PerspectiveCamera()
    let tilt = Entity(), spin = Entity(), hub = Entity()
    let gDetail = Entity(), gRods = Entity(), gWeb = Entity(), gOv = Entity(), gArc = Entity()
    let ground = ModelEntity(mesh: .generatePlane(width: 40, height: 22), materials: [])
    let key = DirectionalLight()
    /// Lights only the shadow passes: nearly on the view axis, so the puck's shadow on the ground sits close behind it
    /// (offset about 0.10 R right and 0.13 R down for a flat disc) instead of being thrown across the window by the steep key.
    let shadowLight = DirectionalLight()
    let sort = ModelSortGroup(depthPass: nil)
    var partEntities: [(ModelEntity, MatKind)] = []
    /// The Tri-wing model (built at setup beside the disc; the groups are switched, never rebuilt).
    var tw: RKTriWing?
    var arcFaceEnt: [ModelEntity] = [], arcWallEnt: [ModelEntity] = []
    var tex: RKPuckTextures!
    var tune = RKTuning()
    var currentMetal = -1
    var currentPlate = -1, currentBoss = -1
    var currentMark = -1
    var currentGlow: Float = -1
    var curRoll = Float.nan, curRoom = Float(-1), curShadowDistance = Float(-1)
    /// Every hub entity (face, cut, raised mark, chamfer, wall): rolled together about the puck axis each frame so the marks read upright.
    var domeEntities: [ModelEntity] = []
    let camDist: Float = 8.6
    let groundZ: Float = -1.12
    var curPitch = Float.nan, curYaw = Float.nan, curSpin = Float.nan, curT = Float(-1), curLevel = -1
    var curPass: RKPass? = nil
    var outputs: [ObjectIdentifier: RealityRenderer.CameraOutput] = [:]
    var shadowOpacity: Float = 0.48
    var groundIsGrey = true
    var groundBG = V3(-1, -1, -1)
    private var arcOn = false
    var blurLo: Float = 2, blurHi: Float = 25

    // ---- output ring + static shadow inputs + sync ----
    struct Slot { var puck: MTLTexture; var half: MTLTexture? }
    var ring: [Slot] = []
    var sizeKey = ""
    /// World-space side of the square region the camera frames (R = 1 world unit at the puck's plane); drives the field of view.
    var frameWorldSide: Float = 0
    var staticB: MTLTexture?, staticB0: MTLTexture?
    var staticKey = ""
    var covTex: MTLTexture?, covBlur: MTLTexture?
    /// The RealityKit render target is a SQUARE region centred on the puck, not the whole window. Half of its side is
    /// `regionHalfSide` puck radii. Derived from the extents measured for ANY orientation: the body stays inside a
    /// sphere of radius 1.013 R (disc R plus half thickness 0.16), which perspective at a camera distance of 8.6 R
    /// grows to at most about 1.03 R on screen; the cast shadow reaches about 1.02 R (offset (z + 1.12) * (0.09, 0.116)
    /// with the ground at z = -1.12, foreshortened by 0.885), plus the blur (sigma 0.029 R, 3 sigma = 0.09 R) and the
    /// 3x3 coverage search: about 1.15 R. 1.3 leaves margin, so nothing is clipped at any pose.
    static let regionHalfSide: Float = 1.3
    /// The region's half side for a shadow offset multiplier `distance` and softness multiplier `spread`: the body
    /// (1.03 R) plus the cast shadow, which sticks out by about 0.15 R per unit of distance, plus 3 sigma of blur
    /// (0.09 R per unit of spread) and a margin. It equals `regionHalfSide` (1.3) at distance 1 and spread 1, so the
    /// default framing is unchanged; at the largest settings (2.5, 3) it grows to about 1.7 so nothing is clipped.
    static func regionHalfSide(distance: Float, spread: Float) -> Float {
        let shadowReach: Float = 0.15 * distance
        let blurReach: Float = 0.09 * spread
        return 1.06 + shadowReach + blurReach
    }
    /// Largest side (pixels) of the square render target. Up to this size the puck is drawn 1:1 with screen pixels.
    static let maxRenderSide: Float = 1536
    /// Target sizes are rounded up to a multiple of this, so a window resize or the puck moving does not reallocate on every change.
    static let renderSideGranularity: Int = 16
    /// Soft edge of the shadow, as a fraction of R (sigma 0.029 R: 2.5 half-resolution pixels at the original 86 half-px-per-R render).
    static let shadowSigmaInR: Float = 0.029
    var shadowSigma: Float = 0
    var shadowBlurObject: MPSImageGaussianBlur?
    /// Per output slot: the latest frame whose copy pass reads it (a fresh render into the slot waits on that).
    var slotRead: [UInt64] = [0, 0, 0]
    var lastSlot = -1
    var lastPoseKey = ""
    var hasCoverage = false
    let rendered: MTLSharedEvent, consumed: MTLSharedEvent
    var renderSeq: UInt64 = 0, frameNo: UInt64 = 0
    var framesRendered = 0
    var covPipeline: MTLRenderPipelineState?
    var copyOver: MTLRenderPipelineState?, copyLerp: MTLRenderPipelineState?
    var sampler: MTLSamplerState?
    var lastError: String?
    /// Frames rendered so far; the host waits for `warm` so streaming/shadow maps are settled before the swap.
    var warm: Bool { framesRendered >= 4 }
    /// Measured by the last encodeFrame: CPU milliseconds spent encoding (RealityKit updateAndRender calls + the app passes).
    var lastEncodeMs: Double = 0

    init(device: MTLDevice) throws {
        dev = device
        renderer = try RealityRenderer()
        rendered = device.makeSharedEvent()!
        consumed = device.makeSharedEvent()!
        // Resume numbering above whatever the events already carry (they are fresh, so 0).
    }

    // ------------------------------------------------------------------------------------------
    // one-time build (called with CPU data produced on a background queue)
    // ------------------------------------------------------------------------------------------
    /// Creates every RealityKit resource and the scene. Yields to the main run loop regularly so the app keeps drawing.
    func build(geometry g: RKGeometryCPU, images: RKImages, triWing: TWGeometryCPU?, lap: @MainActor (String) -> Void) async throws {
        var lastYield = DispatchTime.now().uptimeNanoseconds
        func maybeYield() async {
            let n = DispatchTime.now().uptimeNanoseconds
            if n - lastYield > 3_000_000 { await Task.yield(); lastYield = DispatchTime.now().uptimeNanoseconds }
        }
        tex = try await RKPuckTextures.make(images, step: { await Task.yield() })
        lap("texture resources (async upload)")
        // environment: async variant keeps the prefilter work off the main thread
        let env = try Self.makeEnvSync(images.env)
        lap("environment resource (async)")
        lastYield = DispatchTime.now().uptimeNanoseconds
        for p in g.parts {
            let e = ModelEntity(mesh: try p.mb.resource(name: p.name), materials: [])
            switch p.group {
            case 0:
                switch p.kind {
                case .rodCore, .rodShell: gRods.addChild(e)
                case .webSatin, .cutWall: gWeb.addChild(e)
                case .faceBrushed, .pocket, .knurl, .plate: gDetail.addChild(e)
                default: spin.addChild(e)
                }
                if case .rodCore = p.kind { e.components.set(ModelSortGroupComponent(group: sort, order: -2)) }
                if case .rodShell = p.kind { e.components.set(ModelSortGroupComponent(group: sort, order: -1)) }
            case 1:
                hub.addChild(e)
                domeEntities.append(e)
            default: gOv.addChild(e); e.components.set(ModelSortGroupComponent(group: sort, order: 0))
            }
            partEntities.append((e, p.kind))
            await maybeYield()
        }
        lap("part meshes")
        for lv in 0..<arcLevels {
            var fd: [MeshDescriptor] = [], wd: [MeshDescriptor] = []
            for a in g.faceArcs[lv] { fd.append(a.mb.descriptor(name: a.name, material: a.material)) }
            for a in g.wallArcs[lv] { wd.append(a.mb.descriptor(name: a.name, material: a.material)) }
            let f = ModelEntity(mesh: try MeshResource.generate(from: fd), materials: [])
            let w = ModelEntity(mesh: try MeshResource.generate(from: wd), materials: [])
            let arcEntities: [ModelEntity] = [f, w]
            for e in arcEntities { e.components.set(ModelSortGroupComponent(group: sort, order: 1)); e.isEnabled = false; gArc.addChild(e) }
            var faceMaterials: [PhysicallyBasedMaterial] = []
            var wallMaterials: [PhysicallyBasedMaterial] = []
            for colorIndex in 0..<4 {
                faceMaterials.append(makeArcMaterial(color: colorIndex, level: lv, wall: false, tex: tex, tune: tune))
                wallMaterials.append(makeArcMaterial(color: colorIndex, level: lv, wall: true, tex: tex, tune: tune))
            }
            f.model?.materials = faceMaterials
            w.model?.materials = wallMaterials
            arcFaceEnt.append(f); arcWallEnt.append(w)
            await maybeYield()
        }
        lap("arc meshes + materials")
        spin.addChild(gDetail); spin.addChild(gRods); spin.addChild(gWeb); spin.addChild(gOv); spin.addChild(gArc)
        gOv.isEnabled = false; gArc.isEnabled = false
        tilt.addChild(spin); tilt.addChild(hub)
        if let triGeometry = triWing {
            let t = RKTriWing()
            try await t.build(geometry: triGeometry, sort: sort, step: { await maybeYield() })
            tilt.addChild(t.spin); tilt.addChild(t.hub)
            tw = t
            lap("tri-wing entities")
        }
        renderer.entities.append(tilt)
        applyMaterials(metal: 0, finish: 0, glow: 1)
        ground.position = [0, 0, groundZ]
        setGround(grey: true, bg: V3(0, 0, 0))
        renderer.entities.append(ground)
        cam.camera.fieldOfViewInDegrees = 22; cam.camera.near = 1; cam.camera.far = 60
        cam.position = [0, 0, camDist]
        renderer.entities.append(cam); renderer.activeCamera = cam
        key.light.intensity = 800
        key.light.color = NSColor(white: 1, alpha: 1)
        let keyDirection: V3 = simd_normalize(V3(-0.55, 0.60, 0.58))   // TriWingCrystal.keyLight mirrors these numbers
        key.look(at: .zero, from: keyDirection * 10, relativeTo: nil)
        key.shadow = DirectionalLightComponent.Shadow(shadowProjection: .fixed(zNear: 1, zFar: 30, orthographicScale: 3.2), depthBias: 1.0)
        renderer.entities.append(key)
        shadowLight.light.intensity = 800
        shadowLight.light.color = NSColor(white: 1, alpha: 1)
        let shadowDirection: V3 = simd_normalize(V3(-0.09, 0.116, 1))
        shadowLight.look(at: .zero, from: shadowDirection * 10, relativeTo: nil)
        shadowLight.shadow = DirectionalLightComponent.Shadow(shadowProjection: .fixed(zNear: 1, zFar: 30, orthographicScale: 3.2), depthBias: 1.0)
        shadowLight.isEnabled = false
        renderer.entities.append(shadowLight)
        renderer.lighting.resource = env
        renderer.lighting.intensityExponent = 0
        renderer.cameraSettings.isToneMappingEnabled = false
        renderer.cameraSettings.antialiasing = .multisample4X
        renderer.cameraSettings.colorBackground = .color(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
        lap("scene assembly")
    }

    /// Synchronous creation (the deprecated macOS 15 initializer; identical output to the macOS 27 one).
    @available(macOS, deprecated: 15.0)
    static func makeEnvSync(_ img: CGImage) throws -> EnvironmentResource {
        try EnvironmentResource(equirectangular: img, withName: nil)
    }

    // ------------------------------------------------------------------------------------------
    // materials
    // ------------------------------------------------------------------------------------------
    static let metalNames = ["steel", "brass", "copper", "zirconium", "titanium"]
    /// Rebuilds materials when the metal, the hub finish or the glow brightness changes. A metal or glow change rebuilds
    /// every material (the hub tints derive from the body metal; glow scales every emissive intensity); a finish change
    /// rebuilds only the hub's face and mark meshes and switches which mark meshes are shown. All meshes exist from setup,
    /// so none of this regenerates anything. Glow is quantized to 1/40 so a slider drag does not rebuild on every tick.
    func applyMaterials(metal: Int, finish: Int, glow: Float, plate: Int = -1, boss: Int = -1) {
        let mi = min(max(metal, 0), Self.metalNames.count - 1)
        let pi = plate < 0 ? mi : min(max(plate, 0), Self.metalNames.count - 1)
        let bi = boss < 0 ? mi : min(max(boss, 0), Self.metalNames.count - 1)
        let quantized: Float = (min(max(glow, 0), 2) * 40).rounded() / 40
        let discUnchanged: Bool = (mi == currentMetal && finish == currentMark && quantized == currentGlow)
        if discUnchanged && pi == currentPlate && bi == currentBoss { return }
        let m = rkMetals[Self.metalNames[mi]]!
        tune.hubFinish = finish
        tune.glow = quantized
        let hubOnly: Bool = (mi == currentMetal && quantized == currentGlow)
        var cache: [MatKind: PhysicallyBasedMaterial] = [:]
        for (e, k) in partEntities {
            if discUnchanged { break }   // only the Tri-wing's plate or boss metal changed
            if hubOnly, !Self.isFinishDependent(k) { continue }   // only the hub's marks change with the finish
            if cache[k] == nil { cache[k] = makeMaterial(k, metal: m, tex: tex, tune: tune) }
            e.model?.materials = [cache[k]!]
            // The cut channel (lit, engraved) and the raised mark are separate meshes: show the one the finish needs.
            switch k {
            case .hubFloor, .hubCutWall: e.isEnabled = (finish != 1)
            case .hubTop, .hubTopWall: e.isEnabled = (finish == 1)
            default: break
            }
        }
        if quantized != currentGlow { rebuildArcMaterials() }
        tw?.applyMaterials(body: m, plate: rkMetals[Self.metalNames[pi]]!, boss: rkMetals[Self.metalNames[bi]]!,
                           glowValue: quantized, tex: tex, tune: tune)
        currentMetal = mi; currentMark = finish; currentGlow = quantized; currentPlate = pi; currentBoss = bi
    }

    /// Tri-wing light level (beat pulse), quantised to 1/32. Shows the edge-light materials of that level from a cache that
    /// `RKTriWing.warmLight` fills a little per frame (see `RKTriWing.applyLight`); nothing is built on the frame of a change.
    /// Returns the level that is actually showing (the nearest ready level while the exact one is still being built).
    @discardableResult
    func applyLight(_ level: Float) -> Float {
        let clamped: Float = min(max(level.isNaN ? 1 : level, 0), 1)
        let q: Float = (clamped * 32).rounded() / 32
        if let tw, currentMetal >= 0, let m = rkMetals[Self.metalNames[currentMetal]] {
            tw.exactLight = exactLight
            let applied: Float = tw.applyLight(q, metal: m, tex: tex, tune: tune)
            tune.light = applied
            tw.warmLight(budgetMs: Self.lightWarmBudgetMs, metal: m, tex: tex, tune: tune)
            lastLightTouched = tw.lastLightTouched
            return applied
        }
        tune.light = q
        return q
    }
    var lastLightTouched: Int = 0
    var lightStatsText: String {
        guard let tw else { return "no tri-wing" }
        return "light entities touched by last level change \(tw.lastLightTouched), by last colour change \(tw.lastTintTouched), light materials built \(tw.lightMaterialsBuilt)"
    }
    /// Per-frame time budget for filling the light-material cache.
    static let lightWarmBudgetMs: Double = 2.0
    /// Probe stills: build the exact light level at once (default off in the app).
    var exactLight: Bool = false

    /// Hub parts whose material depends on the finish (the plain face and the cut / raised mark meshes).
    static func isFinishDependent(_ k: MatKind) -> Bool {
        switch k {
        case .hubDomeF, .hubDomeB, .hubFloor, .hubCutWall, .hubTop, .hubTopWall: return true
        default: return false
        }
    }

    /// Arc ribbon materials carry the glow multiplier in their emissive intensity.
    func rebuildArcMaterials() {
        if arcFaceEnt.count != arcLevels || arcWallEnt.count != arcLevels { return }
        for lv in 0..<arcLevels {
            var faceMaterials: [PhysicallyBasedMaterial] = []
            var wallMaterials: [PhysicallyBasedMaterial] = []
            for colorIndex in 0..<4 {
                faceMaterials.append(makeArcMaterial(color: colorIndex, level: lv, wall: false, tex: tex, tune: tune))
                wallMaterials.append(makeArcMaterial(color: colorIndex, level: lv, wall: true, tex: tex, tune: tune))
            }
            arcFaceEnt[lv].model?.materials = faceMaterials
            arcWallEnt[lv].model?.materials = wallMaterials
        }
    }

    /// Ground for the shadow-by-difference (mid grey) or, in opaque mode, a surface that lights to the scene background.
    static let groundGreyLevel: Float = 0.5
    /// Lit radiance (linear, per channel) of the ground at base colour 1.0, measured with the studio lights.
    static var groundLitWhite = V3(0.353, 0.353, 0.376)
    func setGround(grey: Bool, bg: V3) {
        if grey == groundIsGrey && (grey || simd_distance(bg, groundBG) < 1e-5) && ground.model?.materials.isEmpty == false { return }
        var gm = PhysicallyBasedMaterial()
        var c: V3 = V3(repeating: Self.groundGreyLevel)
        if !grey {
            let decoded = V3(srgbDecode(bg.x), srgbDecode(bg.y), srgbDecode(bg.z))
            let lit: V3 = decoded / Self.groundLitWhite
            c = simd_clamp(lit, V3(repeating: 0), V3(repeating: 1))
        }
        gm.baseColor = .init(tint: lin(c)); gm.metallic = 0.0; gm.roughness = 1.0; gm.specular = 0.0
        ground.model?.materials = [gm]
        groundIsGrey = grey; groundBG = bg
        staticKey = ""      // the cached ground-only renders depend on the ground material
    }

    /// Frames the camera on a square of `worldSide` units at the puck's plane (vertical field of view; the target is square).
    func setFrameWorldSide(_ worldSide: Float) {
        if worldSide == frameWorldSide { return }
        frameWorldSide = worldSide
        let halfTan: Float = worldSide / 2 / camDist
        let halfAngle: Float = atan(halfTan)
        let fovRadians: Float = 2 * halfAngle
        cam.camera.fieldOfViewInDegrees = fovRadians * 180 / Float.pi
    }

    // ------------------------------------------------------------------------------------------
    // per-frame scene state
    // ------------------------------------------------------------------------------------------
    /// Orientation = yaw after pitch in screen space: R = Ry(yaw) * Rx(-pitch). Positive pitch tips the top edge away from
    /// the camera (rotation about +x by -pitch); positive yaw turns the right edge away (rotation about +y by +yaw). The
    /// camera, lights, environment and shadow stay fixed in the world.
    func setPose(pitchRad: Float, yawRad: Float, spinRad: Float, omega: Float, hubRoll: Float, blurScale: Float) {
        if pitchRad != curPitch || yawRad != curYaw {
            let pitchQuat = simd_quatf(angle: -pitchRad, axis: V3(1, 0, 0))
            let yawQuat = simd_quatf(angle: yawRad, axis: V3(0, 1, 0))
            tilt.orientation = yawQuat * pitchQuat
            curPitch = pitchRad
            curYaw = yawRad
            tw?.setTilt(pitch: pitchRad, yaw: yawRad)
        }
        if spinRad != curSpin {
            let q = simd_quatf(angle: spinRad, axis: V3(0, 0, 1))
            spin.orientation = q
            tw?.spin.orientation = q
            curSpin = spinRad
        }
        // Self-levelling hubs: each dome turns about the puck's own axis so its mark's up stays toward screen-up.
        if hubRoll != curRoll {
            let rollQuat = simd_quatf(angle: hubRoll, axis: V3(0, 0, 1))
            for dome in domeEntities { dome.orientation = rollQuat }
            curRoll = hubRoll
        }
        applyBlur(omega: omega * blurScale)
        applyTriWingBlur(omega: omega * blurScale)
    }

    /// Same ramp as the disc: the solid Tri-wing fades into its smeared overlay between `blurLo` and `blurHi`.
    func applyTriWingBlur(omega: Float) {
        let v: Float = abs(omega)
        let t: Float = (ssf(blurLo, blurHi, v) * 32).rounded() / 32
        tw?.setBlur(t)
    }

    /// Key light and environment intensity follow the room-light multiplier (non-emissive lighting only).
    func setRoomLight(_ room: Float) {
        if room == curRoom { return }
        curRoom = room
        key.light.intensity = 800 * room
        renderer.lighting.intensityExponent = log2(max(room, 0.01))
    }

    /// The shadow light's direction scales with the shadow distance multiplier (0 = straight behind the puck).
    func setShadowDistance(_ distance: Float) {
        if distance == curShadowDistance { return }
        curShadowDistance = distance
        let shadowDirection: V3 = simd_normalize(V3(-0.09 * distance, 0.116 * distance, 1))
        shadowLight.look(at: .zero, from: shadowDirection * 10, relativeTo: nil)
    }

    func applyBlur(omega: Float) {
        let v: Float = abs(omega)
        let blurMix: Float = ssf(blurLo, blurHi, v) * 32
        let t: Float = blurMix.rounded() / 32
        let sweepSteps: Float = v * shutterSeconds / arcSweepStep
        let level: Int = min(arcLevels - 1, Int(sweepSteps.rounded()))
        if t != curT {
            curT = t
            gOv.isEnabled = t > 0; gArc.isEnabled = t > 0
            gDetail.isEnabled = t < 1; gRods.isEnabled = t < 1; gWeb.isEnabled = t < 1
            if t > 0 && t < 1 {
                var webOpacity: Float = 1
                if t >= 0.7 { webOpacity = (1 - t) / 0.3 }
                let rodsOpacity: Float = 1 - t
                gOv.components.set(OpacityComponent(opacity: t)); gArc.components.set(OpacityComponent(opacity: t))
                gRods.components.set(OpacityComponent(opacity: rodsOpacity)); gWeb.components.set(OpacityComponent(opacity: webOpacity))
            } else {
                gOv.components.set(OpacityComponent(opacity: 1)); gArc.components.set(OpacityComponent(opacity: 1))
                gRods.components.set(OpacityComponent(opacity: 1)); gWeb.components.set(OpacityComponent(opacity: 1))
            }
        }
        if level != curLevel || (t > 0) != arcOn {
            arcOn = t > 0
            for i in 0..<arcLevels { let on = arcOn && i == level; arcFaceEnt[i].isEnabled = on; arcWallEnt[i].isEnabled = on }
            curLevel = level
        }
    }

    /// Shows the disc or the Tri-wing (the Tri-wing exists only here; without it the disc stays).
    func applyModel(_ model: Int, edgeLights: Bool) {
        let tri: Bool = (model == 1) && tw != nil
        spin.isEnabled = !tri
        hub.isEnabled = !tri
        tw?.setVisible(tri, edgeLights: edgeLights)
    }

    func configure(_ p: RKPass) {
        if curPass == p { return }
        curPass = p
        tilt.isEnabled = (p == .puckOnly || p == .puckGround)
        tw?.setShadowPass(p == .puckGround)
        ground.isEnabled = (p != .puckOnly)
        // The key lights the puck; the shadow light lights the ground passes. Neither is on in groundNoKey.
        key.isEnabled = (p == .puckOnly)
        shadowLight.isEnabled = (p == .puckGround || p == .groundOnly)
    }

    // ------------------------------------------------------------------------------------------
    // GPU resources
    // ------------------------------------------------------------------------------------------
    func makeTarget(_ w: Int, _ h: Int, private priv: Bool = false) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead, .shaderWrite]; d.storageMode = priv ? .private : .shared
        return dev.makeTexture(descriptor: d)!
    }

    func ensurePipelines() {
        if covPipeline != nil { return }
        guard let lib = dev.makeDefaultLibrary() else { lastError = "no library"; return }
        let c = MTLRenderPipelineDescriptor()
        c.vertexFunction = lib.makeFunction(name: "fullscreen_vs"); c.fragmentFunction = lib.makeFunction(name: "rk_shadow_cov_fs")
        c.colorAttachments[0].pixelFormat = .rgba16Float
        covPipeline = try? dev.makeRenderPipelineState(descriptor: c)
        func copy(lerp: Bool) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: "fullscreen_vs"); d.fragmentFunction = lib.makeFunction(name: "rk_copy_fs")
            let a = d.colorAttachments[0]!
            a.pixelFormat = .rgba16Float; a.isBlendingEnabled = true
            a.rgbBlendOperation = .add; a.alphaBlendOperation = .add
            if lerp {   // out = rk * mix + dst * (1 - mix), on premultiplied values
                a.sourceRGBBlendFactor = .blendColor; a.sourceAlphaBlendFactor = .blendAlpha
                a.destinationRGBBlendFactor = .oneMinusBlendColor; a.destinationAlphaBlendFactor = .oneMinusBlendAlpha
            } else {    // premultiplied source-over
                a.sourceRGBBlendFactor = .one; a.sourceAlphaBlendFactor = .one
                a.destinationRGBBlendFactor = .oneMinusSourceAlpha; a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try? dev.makeRenderPipelineState(descriptor: d)
        }
        copyOver = copy(lerp: false); copyLerp = copy(lerp: true)
        let s = MTLSamplerDescriptor()
        s.minFilter = .linear; s.magFilter = .linear; s.sAddressMode = .clampToZero; s.tAddressMode = .clampToZero
        sampler = dev.makeSamplerState(descriptor: s)
        if covPipeline == nil || copyOver == nil || copyLerp == nil || sampler == nil { lastError = "pipeline creation failed" }
    }

    /// Square render target of `side` pixels (rounded by the caller). Re-created only when the side changes.
    func ensureSize(side: Int, transparent: Bool) {
        let hw: Int = max(1, side / 2)
        let key: String = "\(side)"
        if key != sizeKey {
            var newRing: [Slot] = []
            for _ in 0..<3 { newRing.append(Slot(puck: makeTarget(side, side, private: true), half: nil)) }
            ring = newRing
            staticB = nil; staticB0 = nil; staticKey = ""
            covTex = nil; covBlur = nil
            lastSlot = -1; lastPoseKey = ""; hasCoverage = false; slotRead = [0, 0, 0]
            outputs.removeAll()          // CameraOutputs are keyed by texture identity; stale entries must not match a recycled address
            sizeKey = key
        }
        if transparent {
            if ring[0].half == nil { for i in 0..<3 { ring[i].half = makeTarget(hw, hw, private: true) }; outputs.removeAll() }
            if staticB == nil { staticB = makeTarget(hw, hw, private: true); staticB0 = makeTarget(hw, hw, private: true); staticKey = "" }
            if covTex == nil { covTex = makeTarget(hw, hw, private: true); covBlur = makeTarget(hw, hw, private: true) }
        }
    }

    /// The shadow blur follows the half-resolution size of R, so the shadow's softness stays the same fraction of the puck.
    func blurFor(sigma: Float) -> MPSImageGaussianBlur {
        let quantized: Float = max(0.5, (sigma * 4).rounded() / 4)
        if let existing = shadowBlurObject, quantized == shadowSigma { return existing }
        let made = MPSImageGaussianBlur(device: dev, sigma: quantized)
        made.edgeMode = .clamp
        shadowBlurObject = made
        shadowSigma = quantized
        return made
    }

    func output(for t: MTLTexture) throws -> RealityRenderer.CameraOutput {
        let id = ObjectIdentifier(t as AnyObject)
        if let o = outputs[id] { return o }
        let o = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: t))
        outputs[id] = o
        return o
    }

    /// One asynchronous RealityKit render into `t`: waits (GPU side) on `waitConsumed`, signals `rendered` with a fresh value.
    @discardableResult
    func render(into t: MTLTexture, waitConsumed: UInt64?) throws -> UInt64 {
        renderSeq += 1
        var before: [RealityRenderer.MetalEventAction] = []
        if let w = waitConsumed { before = [.wait(for: consumed, value: w)] }
        try renderer.updateAndRender(deltaTime: 1.0 / 60.0, cameraOutput: try output(for: t), whenScheduled: nil, onComplete: nil,
                                     actionsBeforeRender: before, actionsAfterRender: [.signal(rendered, value: renderSeq)])
        framesRendered += 1
        return renderSeq
    }

    // ------------------------------------------------------------------------------------------
    // the per-frame entry point
    // ------------------------------------------------------------------------------------------
    /// Renders the puck (and, in transparent mode, the shadow inputs) and encodes the hand-off into the app's command
    /// buffer: GPU wait on the RealityKit render, shadow coverage + blur (transparent), a premultiplied copy into the
    /// pass in `descriptor` (blend = source-over, or a lerp by `mix` for the crossfade), then the "consumed" signal.
    /// Returns false when nothing was encoded (the caller keeps the shader frame).
    func encodeFrame(_ p: RKFrameParams, mix: Float, descriptor: MTLRenderPassDescriptor, commandBuffer cb: MTLCommandBuffer,
                     blur: MPSImageGaussianBlur) -> Bool {
        let t0 = DispatchTime.now().uptimeNanoseconds
        ensurePipelines()
        guard lastError == nil, let covPipeline, let copyOver, let copyLerp, let sampler else { return false }
        guard let sceneTex = descriptor.colorAttachments[0].texture else { return false }
        // The shadow is always produced by difference, in opaque mode too: the puck is rendered alone and its shadow
        // is composited as black alpha over the scene, so no ground plane has to match the background colour.
        let tr = true
        // Region geometry. R_px = on-screen pixels per puck radius (R = 1 world unit at the puck's plane, camera distance
        // `camDist`, vertical half field of view 11 degrees divided by the zoom). The region is the square of
        // 2 * regionHalfSide radii centred on the puck. The target is that side rounded UP to the granularity and capped
        // at `maxRenderSide`; below the cap one target texel is exactly one screen pixel, above it the copy scales it up.
        let halfFov: Float = 11 * Float.pi / 180
        let pxPerR: Float = Float(p.height) * p.zoom / (2 * camDist * tan(halfFov))
        // Shadow offset and softness multipliers, quantized (a slider drag must not retarget on every tick).
        let distanceQ: Float = (min(max(p.shadowDistance, 0), 2.5) * 20).rounded() / 20
        let spreadQ: Float = (min(max(p.shadowSpread, 0.3), 3) * 20).rounded() / 20
        let halfSide: Float = Self.regionHalfSide(distance: distanceQ, spread: spreadQ)
        let neededSide: Float = 2 * halfSide * pxPerR
        let granularity: Float = Float(Self.renderSideGranularity)
        let roundedSide: Float = (neededSide / granularity).rounded(.up) * granularity
        let targetSide: Int = max(64, Int(min(roundedSide, Self.maxRenderSide)))
        // Side of the region on screen, in pixels: the target itself when uncapped (1:1), else the needed side.
        let regionPx: Float = (Float(targetSide) < neededSide) ? neededSide : Float(targetSide)
        let worldSide: Float = regionPx / pxPerR
        do {
            ensureSize(side: targetSide, transparent: tr)
            applyMaterials(metal: p.metal, finish: p.hubFinish, glow: p.glow, plate: p.plateMetal, boss: p.bossMetal)
            tw?.setLightColours(p.lightColors)
            let lightQ: Float = applyLight(p.lightLevel)
            setRoomLight(p.roomLight)
            setShadowDistance(distanceQ)
            shadowOpacity = min(max(p.shadowDarkness, 0), 0.85)
            setFrameWorldSide(worldSide)
            setGround(grey: true, bg: p.background)
            frameNo += 1
            // A resting spinner (same orientation, material, finish, size, framing) reuses the previous output and shadow:
            // no RealityKit render, no shadow passes, and no wait on any RealityKit work. The region's position is not part
            // of the key: moving the puck only changes the copy rectangle.
            let poseKey = "\(targetSide)w\(worldSide)p\(p.pitchRad)y\(p.yawRad)s\(p.spinRad)o\(p.omega)m\(p.metal)f\(p.hubFinish)pm\(p.plateMetal)bm\(p.bossMetal)"
                + "r\(p.hubRoll)g\(currentGlow)l\(p.roomLight)b\(p.spinBlur)d\(distanceQ)e\(spreadQ)n\(p.model)i\(p.edgeLights)h\(lightQ)c\(tw?.colourKey ?? "")"
            let reuse = poseKey == lastPoseKey && lastSlot >= 0 && hasCoverage
            if reuse {
                slotRead[lastSlot] = frameNo
            } else {
                let slot = (lastSlot + 1) % 3
                let wait: UInt64? = slotRead[slot] > 0 ? slotRead[slot] : nil
                var last: UInt64 = 0
                let key = "\(targetSide)w\(worldSide)d\(distanceQ)"
                if staticKey != key {
                    configure(.groundOnly)
                    for _ in 0..<3 { last = try render(into: staticB!, waitConsumed: nil) }
                    configure(.groundNoKey)
                    for _ in 0..<3 { last = try render(into: staticB0!, waitConsumed: nil) }
                    staticKey = key
                }
                configure(.puckOnly)
                applyModel(p.model, edgeLights: p.edgeLights)
                setPose(pitchRad: p.pitchRad, yawRad: p.yawRad, spinRad: p.spinRad, omega: p.omega,
                        hubRoll: p.hubRoll, blurScale: p.spinBlur)
                last = try render(into: ring[slot].puck, waitConsumed: wait)
                configure(.puckGround)
                last = try render(into: ring[slot].half!, waitConsumed: nil)
                cb.encodeWaitForEvent(rendered, value: last)
                // --- shadow coverage (GPU) ---
                // Half-resolution pixels per R in the target (equals R_px / 2 when the target is 1:1 with the screen).
                let rTarget: Float = Float(targetSide) * pxPerR / regionPx
                let rHalf: Float = rTarget / 2
                if let covTex, let covBlur, let b = staticB, let b0 = staticB0, let a = ring[slot].half {
                    let rp = MTLRenderPassDescriptor()
                    rp.colorAttachments[0].texture = covTex; rp.colorAttachments[0].loadAction = .dontCare; rp.colorAttachments[0].storeAction = .store
                    if let enc = cb.makeRenderCommandEncoder(descriptor: rp) {
                        enc.setRenderPipelineState(covPipeline)
                        enc.setFragmentTexture(a, index: 0); enc.setFragmentTexture(b, index: 1)
                        enc.setFragmentTexture(b0, index: 2); enc.setFragmentTexture(ring[slot].puck, index: 3)
                        enc.setFragmentSamplerState(sampler, index: 0)
                        // Shadow offset in half-resolution pixels: 0.06 R right, 0.09 R down.
                        // The silhouette threshold is the disc's 0.002; for the Tri-wing it is 0.30 so its clear crystal (alpha
                        // below that) is not a silhouette: the open bearing gap lets light through instead of casting a disc.
                        let silThreshold: Float = (p.model == 1 && tw != nil) ? 0.30 : 0.002
                        var cu = SIMD4<Float>(0.06 * rHalf * distanceQ, 0.09 * rHalf * distanceQ, silThreshold, 0)
                        enc.setFragmentBytes(&cu, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                        enc.endEncoding()
                    }
                    let blurObject: MPSImageGaussianBlur = blurFor(sigma: Self.shadowSigmaInR * spreadQ * rHalf)
                    blurObject.encode(commandBuffer: cb, sourceTexture: covTex, destinationTexture: covBlur)
                    hasCoverage = true
                }
                slotRead[slot] = frameNo
                lastSlot = slot
                lastPoseKey = poseKey
            }
            guard lastSlot >= 0 else { return false }
            let out = ring[lastSlot].puck
            // --- copy into the scene texture ---
            let cp = MTLRenderPassDescriptor()
            cp.colorAttachments[0].texture = sceneTex; cp.colorAttachments[0].loadAction = .load; cp.colorAttachments[0].storeAction = .store
            if let enc = cb.makeRenderCommandEncoder(descriptor: cp) {
                let copyPipeline: MTLRenderPipelineState = (mix >= 0.999) ? copyOver : copyLerp
                enc.setRenderPipelineState(copyPipeline)
                if mix < 0.999 { enc.setBlendColor(red: mix, green: mix, blue: mix, alpha: mix) }
                enc.setFragmentTexture(out, index: 0)
                enc.setFragmentTexture(covBlur, index: 1)
                enc.setFragmentSamplerState(sampler, index: 0)
                // Region placement: centred on the puck (window centre plus the content offset), snapped to whole pixels
                // so a 1:1 target is copied without resampling blur.
                let sceneW: Float = Float(sceneTex.width)
                let sceneH: Float = Float(sceneTex.height)
                let centerX: Float = sceneW * (0.5 + p.offsetX * 0.5)
                let centerY: Float = sceneH * (0.5 - p.offsetY * 0.5)
                let originX: Float = (centerX - regionPx / 2).rounded()
                let originY: Float = (centerY - regionPx / 2).rounded()
                var u = RKCopyUniforms(sceneSize: SIMD2<Float>(sceneW, sceneH),
                                       regionOrigin: SIMD2<Float>(originX, originY),
                                       regionSize: SIMD2<Float>(regionPx, regionPx),
                                       shadowOpacity: shadowOpacity, useShadow: 1)
                if mix >= 0.999 {
                    // Fully RealityKit: nothing outside the region changes, so only that rectangle needs to be drawn.
                    let x0: Int = max(0, Int(originX))
                    let y0: Int = max(0, Int(originY))
                    let x1: Int = min(sceneTex.width, Int(originX + regionPx) + 1)
                    let y1: Int = min(sceneTex.height, Int(originY + regionPx) + 1)
                    if x1 > x0 && y1 > y0 {
                        enc.setScissorRect(MTLScissorRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
                    }
                }
                enc.setFragmentBytes(&u, length: MemoryLayout<RKCopyUniforms>.stride, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
            }
            cb.encodeSignalEvent(consumed, value: frameNo)
            let elapsedNs: UInt64 = DispatchTime.now().uptimeNanoseconds - t0
            lastEncodeMs = Double(elapsedNs) / 1e6
            return true
        } catch {
            lastError = "\(error)"
            return false
        }
    }
}
