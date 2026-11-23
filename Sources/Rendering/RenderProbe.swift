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
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import simd
import MacVisualizerCore

/// Renders a single frame offscreen to a PNG for deterministic visual verification.
/// Invoked via `MacVisualizer --render-probe <path>`.
enum RenderProbe {
    /// `renderMode`, when non-nil, selects a per-style render mode (e.g. voronoi
    /// `softCells`/`blobs`, lavaLamp `marchingSquares`, heightfield `solid`) so the
    /// probe can verify mode-dependent shader/path branches. nil preserves the
    /// style's default render mode.
    static func run(outputPath: String, style: VisualizerStyle = .bars, glow: Bool = false,
                    renderMode: String? = nil, width widthArg: Int = 800, height heightArg: Int = 400) -> Bool {
        // Spinner probe token `w<pixels>` renders a larger frame (width as given, height = width / 2) so detail
        // such as the hub mark can be judged at 1:1.
        var width: Int = widthArg
        var height: Int = heightArg
        if style.isSpinnerFamily {
            for tok in (renderMode ?? "").split(separator: ",") where tok.first == "w" {
                if let pixels = Int(tok.dropFirst()), pixels >= 64 {
                    width = pixels
                    height = pixels / 2
                }
            }
        }
        guard let renderer = MetalRenderer(pixelFormat: .bgra8Unorm) else {
            FileHandle.standardError.write(Data("RenderProbe: no Metal device\n".utf8))
            return false
        }

        // Offscreen render target.
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .managed
        guard let texture = renderer.device.makeTexture(descriptor: texDesc),
              let commandBuffer = renderer.makeCommandBuffer() else { return false }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture

        // A ramp frame: band levels increase left -> right, so the PNG shows a staircase.
        // Set the active style so shader-kind / render-mode selection reads the requested
        // style's profile (matching the live path in MetalView), instead of the .bars
        // profile that VisualizerSettings.defaults starts on.
        var settings = VisualizerSettings.defaults
        settings.visualizerStyle = style
        // Optionally override the requested style's render mode so mode-dependent
        // branches (voronoi softCells/blobs, lavaLamp shader/marchingSquares,
        // heightfield wireframe/solid) are reachable from the probe. Applies to the
        // current style's profile via mutateCurrent; an unrecognized token is ignored
        // (default mode preserved).
        if let renderMode = renderMode {
            // "dim<value>" (e.g. dim0.35) exercises the global output dimmer on
            // whichever render path the other arguments select.
            if renderMode.hasPrefix("dim"), let v = Double(renderMode.dropFirst(3)) {
                settings.outputBrightness = v
            }
            // "trails<value>" routes through renderWithTrails, whose geometry
            // pass is a separate draw from encode()'s.
            if renderMode.hasPrefix("trails"), let v = Float(renderMode.dropFirst(6)) {
                settings.trailPersistence = v
            }
            settings.mutateCurrent { profile in
                switch style {
                case .voronoi:
                    if let m = VoronoiRenderMode(rawValue: renderMode) { profile.voronoiRenderMode = m }
                case .lavaLamp:
                    if let m = LavaLampRenderMode(rawValue: renderMode) { profile.lavaLampRenderMode = m }
                case .heightfield:
                    if let m = HeightfieldRenderMode(rawValue: renderMode) { profile.heightfieldRenderMode = m }
                default:
                    break
                }
            }
            // Wireframe placement lives in top-level settings (not the profile),
            // so it is applied here rather than inside mutateCurrent. Lets the
            // probe verify the bottom-anchored / full-width branch.
            if style == .heightfield {
                if renderMode.contains("fillWidth") { settings.heightfieldFillWidth = true }
                if renderMode.contains("anchorBottom") { settings.heightfieldAnchorBottom = true }
            }
            if style == .wireframe {
                switch renderMode {
                case "bottomWide":
                    settings.wireframeXExtent = 4.0
                    settings.wireframeVerticalCenter = -0.8
                case "fillWindow":
                    settings.wireframeFillWidth = true
                    settings.wireframeAnchorBottom = true
                case "fillWidth":
                    settings.wireframeFillWidth = true
                case "anchorBottom":
                    settings.wireframeAnchorBottom = true
                default:
                    break
                }
            }
        }
        let bandCount = settings.barCount
        let bands = (0..<bandCount).map { Float($0) / Float(max(bandCount - 1, 1)) }
        let peaks = bands.map { min($0 + 0.05, 1) }
        let wave = (0..<256).map { sinf(Float($0) / 256 * 2 * .pi * 4) }
        var frame = AudioFrame(bands: bands, bandPeaks: peaks, waveform: wave,
                               rms: 0, peak: bands.last ?? 0, timestamp: 0)
        if style == .xyScope {
            // Stereo 2:3 Lissajous pair: the mono ramp frame would collapse the
            // scope to its (correct) vertical line; distinct channels show the
            // crossing figure the style exists for.
            let phases = (0..<256).map { Float($0) / 256 * 2 * .pi }
            frame = AudioFrame(bands: bands, bandsLeft: bands, bandsRight: bands,
                               bandPeaks: peaks, waveform: wave,
                               waveformLeft: phases.map { 0.8 * sinf(2 * $0) },
                               waveformRight: phases.map { 0.8 * sinf(3 * $0 + .pi / 4) },
                               rms: 0.5, peak: bands.last ?? 0, timestamp: 0)
        }
        let aspect = Float(width) / Float(height)
        let visualizer = style.makeVisualizer()
        renderer.activeVisualizer = visualizer
        // RenderMode "a<angle>,v<velocity>[,m<metal>][,k<frontMark>][,z<zoom>][,p<pitchDeg>][,y<yawDeg>][,h<hubFinish>][,g1][,t][,w<pixels>]"
        // pins the spinner state: g1 = RealityKit, t = keep the transparent window, w = frame width (height = width / 2),
        // k = which mark is on the front hub (probe-only; the app always shows the interlock mark on the front),
        // y = yaw (RealityKit only: the classic shader renderer shows pitch only). m = metal index (0 steel .. 4 anodized
        // titanium), h = hub finish index (0 lit, 1 raised). The probe builds a `SpinnerSettings` from the tokens, which
        // override the (default) settings for this render; the renderers read it like the live app's profile:
        // S<size> G<glow> L<roomLight> B<spinBlur> D<shadowDarkness> P<shadowSpread> X<shadowDistance> (Doubles); K<gray> sets a
        // lighter backdrop (0...1) so the shadow is visible. d<model index> (0 disc, 1 tri-wing; RealityKit only, so add g1) and
        // q<0|1> (tri-wing light colours: 0 original, 1 follow the palette), c<palette index> (position in ColorPalette.orderedPresetNames, default the settings' own), M<plate metal 0 same as body, 1 steel .. 5 titanium> O<boss metal 0 same as body, 1 same as plate, 2 steel .. 6 titanium>, e<0|1> (tri-wing edge lights off / on, default on), l<0...1> (forces the tri-wing light level, as the beat pulse would set it; default 1).
        var probeRealityWarmup = 0
        var probeAngle: Double = 0, probeVelocity: Double = 0, probeTilt: Double = 0, probeYaw: Double = 0   // for RK_PROBE_BENCH
        var spinnerBackdrop: Double = -1     // token K<gray 0...1>: a lighter backdrop so the shadow can be judged
        var probeCB: MTLCommandBuffer = commandBuffer   // replaced by a fresh buffer after RealityKit warm-up
        if style.isSpinnerFamily, let sp = visualizer as? SpinnerVisualizer {
            var a = 0.0, v = 0.0
            var tiltDeg = 0.0
            var yawDeg = 0.0
            var sps = SpinnerSettings()
            var probeLight: Float? = nil     // token l<0...1>: forces the tri-wing light level
            var probePaletteIndex: Int? = nil   // token c<index into ColorPalette.orderedPresetNames>
            sps.renderer = .shader   // token g1 selects RealityKit
            SpinnerTuning.hubMark = .interlock; SpinnerTuning.debugZoom = 1  // reset per render
            if !(renderMode ?? "").contains("t") { settings.windowTransparencyMode = .opaque }  // token t = keep transparent
            for tok in (renderMode ?? "").split(separator: ",") {
                let val = Double(tok.dropFirst()) ?? 0
                switch tok.first {
                case "a": a = val
                case "v": v = val
                case "z": SpinnerTuning.debugZoom = max(val, 0.1)
                case "p": tiltDeg = val
                case "y": yawDeg = val
                case "h": sps.hubFinish = SpinnerHubFinish.allCases.first(where: { (f: SpinnerHubFinish) -> Bool in f.index == Int(val) }) ?? .lit
                case "k": SpinnerTuning.hubMark = SpinnerHubMark.allCases.first(where: { (m: SpinnerHubMark) -> Bool in m.index == Int(val) }) ?? .interlock
                case "m": sps.metal = SpinnerMetal.allCases.first(where: { (m: SpinnerMetal) -> Bool in m.index == Int(val) }) ?? .steel
                case "M": sps.plateMetal = SpinnerPlateMetal.allCases.first(where: { (m: SpinnerPlateMetal) -> Bool in m.index == Int(val) }) ?? .sameAsBody
                case "O": sps.bossMetal = SpinnerBossMetal.allCases.first(where: { (m: SpinnerBossMetal) -> Bool in m.index == Int(val) }) ?? .sameAsBody
                case "g": if val > 0 { sps.renderer = .realityKit }
                case "S": sps.size = val
                case "G": sps.glowBrightness = val
                case "L": sps.roomLight = val
                case "B": sps.spinBlur = val
                case "D": sps.shadowDarkness = val
                case "P": sps.shadowSpread = val
                case "X": sps.shadowDistance = val
                case "K": spinnerBackdrop = val
                case "d": sps.model = SpinnerModel.allCases.first(where: { (m: SpinnerModel) -> Bool in m.index == Int(val) }) ?? .disc
                case "e": sps.edgeLights = val > 0
                case "l": probeLight = Float(min(max(val, 0), 1))
                case "q": sps.lightColors = val > 0 ? .palette : .original
                case "c": probePaletteIndex = Int(val)
                default: break }
            }
            // The Tri-wing Spinner style (probe name `triWingSpinner`) is always RealityKit. The long-standing tokens d1,g1 on the
            // `spinner` style draw the same thing, so they are routed through the Tri-wing Spinner style (the model is derived
            // from the style now); d1 without g1 keeps drawing the disc shader as before.
            if style == .triWingSpinner { sps.model = .triWing; sps.renderer = .realityKit }
            if sps.renderer == .realityKit && sps.model == .triWing { settings.visualizerStyle = .triWingSpinner }
            settings.mutateCurrent { (profile: inout StyleProfile) -> Void in
                profile.spinner = sps
                if let pi = probePaletteIndex, pi >= 0, pi < ColorPalette.orderedPresetNames.count {
                    profile.paletteName = ColorPalette.orderedPresetNames[pi]
                }
            }
            let tiltRadians: Double = tiltDeg * Double.pi / 180
            let yawRadians: Double = yawDeg * Double.pi / 180
            sp.debugFreeze(angle: a, velocity: v, tilt: tiltRadians, yaw: yawRadians)
            probeAngle = a; probeVelocity = v; probeTilt = tiltRadians; probeYaw = yawRadians
            if let level = probeLight { sp.debugLightLevel(level) }
            // RealityKit probe path: wait for the background setup, then warm the scene up with extra
            // frames (each is a full encode + submit through the app's own scene/composite passes) before the real one.
            if sps.renderer == .realityKit {
                let host = RealitySpinnerHost.shared
                guard host.prepareBlocking(device: renderer.device) else {
                    FileHandle.standardError.write(Data("RenderProbe: RealityKit setup failed: \(host.failure ?? "timeout")\n".utf8)); return false
                }
                host.fadeSeconds = 0       // full RealityKit in the probe
                // Stills use the exact light level at once; the frame benchmark uses the app's cached path.
                host.exactLight = ProcessInfo.processInfo.environment["RK_PROBE_BENCH"] == nil
                probeRealityWarmup = Int(ProcessInfo.processInfo.environment["RK_PROBE_FRAMES"] ?? "") ?? 8
            }
        }
        let vertices: [BarVertex]
        if style == .fountain || style == .fireworks || style == .ribbonWave {
            // Warm-up: prime the visualizer with quiet -> loud -> quiet across ~0.5 s so
            // fountain spawns and a fireworks rising-edge beat triggers a burst that has
            // time to expand before we snapshot.
            let rampBands = (0..<bandCount).map { Float($0) / Float(max(bandCount - 1, 1)) }
            let loudBands = [Float](repeating: 1.0, count: bandCount)
            let f0 = AudioFrame(bands: rampBands, bandPeaks: rampBands, waveform: wave,
                                rms: 0, peak: rampBands.last ?? 0, timestamp: 0)
            let f1 = AudioFrame(bands: loudBands, bandPeaks: loudBands, waveform: wave,
                                rms: 1, peak: 1, timestamp: 1.0 / 60.0)
            let f2 = AudioFrame(bands: rampBands, bandPeaks: rampBands, waveform: wave,
                                rms: 0, peak: rampBands.last ?? 0, timestamp: 30.0 / 60.0)
            _ = visualizer.makeVertices(frame: f0, settings: settings, aspect: aspect)
            _ = visualizer.makeVertices(frame: f1, settings: settings, aspect: aspect)
            vertices = visualizer.makeVertices(frame: f2, settings: settings, aspect: aspect)
        } else {
            vertices = visualizer.makeVertices(frame: frame, settings: settings, aspect: aspect)
        }
        let round = style.usesRoundParticles
        let shaderKind = style.customShader(settings: settings)
        let persistence = settings.trailPersistence
        if persistence > 0 {
            renderer.renderWithTrails(vertices: vertices,
                                      clearColor: MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                                      intensity: 0.9,
                                      persistence: persistence,
                                      glow: glow,
                                      settings: settings,
                                      frame: frame,
                                      finalPass: pass,
                                      width: width, height: height,
                                      commandBuffer: commandBuffer,
                                      roundParticles: round,
                                      shaderKind: shaderKind)
        } else if glow {
            renderer.renderBloom(vertices: vertices,
                                 clearColor: MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                                 intensity: 0.9,
                                 settings: settings,
                                 frame: frame,
                                 finalPass: pass,
                                 width: width, height: height,
                                 commandBuffer: commandBuffer,
                                 roundParticles: round,
                                 shaderKind: shaderKind)
        } else if shaderKind != nil {
            // Transparent-window spinner probes clear to (0,0,0,0) like the live app.
            let spinnerTransparent: Bool = (style.isSpinnerFamily && settings.windowTransparencyMode != .opaque)
            var spClear: MTLClearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)
            if spinnerBackdrop >= 0 { spClear = MTLClearColor(red: spinnerBackdrop, green: spinnerBackdrop, blue: spinnerBackdrop, alpha: 1) }
            if spinnerTransparent { spClear = MTLClearColorMake(0, 0, 0, 0) }
            // RealityKit warm-up frames, each a full renderBloom (RealityKit render + copy + blur + composite).
            if probeRealityWarmup > 0 {
                var frameMs: [Double] = []
                for _ in 0..<probeRealityWarmup {
                    let tf = DispatchTime.now().uptimeNanoseconds
                    guard let w = renderer.makeCommandBuffer() else { return false }
                    renderer.renderBloom(vertices: vertices, clearColor: spClear, intensity: 0, settings: settings, frame: frame,
                                         finalPass: pass, width: width, height: height, commandBuffer: w,
                                         roundParticles: round, shaderKind: shaderKind)
                    w.commit(); w.waitUntilCompleted()
                    let frameNs: UInt64 = DispatchTime.now().uptimeNanoseconds - tf
                    frameMs.append(Double(frameNs) / 1e6)
                }
                // Serial wall time per frame (encode + RealityKit render + copy + blur + composite + wait), warm frames only.
                let warmMs = frameMs.dropFirst(5)
                if !warmMs.isEmpty {
                    let warmTotal: Double = warmMs.reduce(0, +)
                    let warmMean: Double = warmTotal / Double(warmMs.count)
                    var allTimes: [String] = []
                    for ms in frameMs { allTimes.append(String(format: "%.1f", ms)) }
                    let allJoined: String = allTimes.joined(separator: ",")
                    let summary: String = String(format: "RK warm frame wall (serial, incl. GPU): mean %.2f ms over %d frames (all: %@)\n",
                                                 warmMean, warmMs.count, allJoined)
                    FileHandle.standardError.write(Data(summary.utf8))
                }
                RealitySpinnerHost.shared.forceMix(1)
                if let benchText = ProcessInfo.processInfo.environment["RK_PROBE_BENCH"], let benchFrames = Int(benchText), benchFrames > 0,
                   let spinnerViz = visualizer as? SpinnerVisualizer {
                    settings = runFrameBench(frames: benchFrames, renderer: renderer, spinnerViz: spinnerViz, vertices: vertices, clear: spClear,
                                  settings: settings, frame: frame, pass: pass, width: width, height: height, round: round,
                                  shaderKind: shaderKind, startAngle: probeAngle, velocity: probeVelocity,
                                  tilt: probeTilt, yaw: probeYaw)
                }
                guard let w = renderer.makeCommandBuffer() else { return false }
                probeCB = w
            }
            renderer.renderBloom(vertices: vertices,
                                 clearColor: spClear,
                                 intensity: 0,
                                 settings: settings,
                                 frame: frame,
                                 finalPass: pass,
                                 width: width, height: height,
                                 commandBuffer: probeCB,
                                 roundParticles: round,
                                 shaderKind: shaderKind)
        } else if settings.visualizerStyle == .voronoi
                    && settings.current.voronoiRenderMode == .softCells {
            // softCells requires a post-process blur pass; route through renderBloom
            // (intensity 0) so applySoftCellsBlur has an intermediate texture to work with.
            renderer.renderBloom(vertices: vertices,
                                 clearColor: MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                                 intensity: 0,
                                 settings: settings,
                                 frame: frame,
                                 finalPass: pass,
                                 width: width, height: height,
                                 commandBuffer: commandBuffer,
                                 roundParticles: round,
                                 shaderKind: shaderKind)
        } else {
            renderer.encode(vertices: vertices,
                            clearColor: MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                            into: pass, commandBuffer: commandBuffer,
                            roundParticles: round,
                            brightness: effectiveOutputBrightness(settings))
        }

        // Blit to make the managed texture's contents readable on the CPU.
        if let blit = probeCB.makeBlitCommandEncoder() {
            blit.synchronize(resource: texture)
            blit.endEncoding()
        }
        probeCB.commit()
        probeCB.waitUntilCompleted()
        if probeRealityWarmup > 0 {
            let h = RealitySpinnerHost.shared
            for (n, ms) in h.setupLog {
                let line: String = String(format: "RK setup %8.0f ms  %@\n", ms, n)
                FileHandle.standardError.write(Data(line.utf8))
            }
            FileHandle.standardError.write(Data(String(format: "RK last encode CPU %.2f ms\n", h.lastEncodeMs).utf8))
        }

        return writePNG(texture: texture, width: width, height: height, to: outputPath)
    }

    /// Frame-time benchmark (environment variable `RK_PROBE_BENCH=<frames>`, RealityKit spinner probes only; not user-facing).
    /// Renders N consecutive frames through the same `renderBloom` -> `encodeFrame` path the app uses (shadow passes included),
    /// advancing the spin angle each frame by `velocity / 60`, and prints per-frame CPU time (the whole main-thread
    /// encode call, before commit) and GPU time (command buffer GPUStartTime...GPUEndTime) as mean / median / p95 / max.
    /// `RK_PROBE_BENCH_LIGHT=tri` drives the Tri-wing light level through a triangle wave (period `RK_PROBE_BENCH_PERIOD`
    /// frames, default 48), the way the beat pulse changes it, one level step or more per frame; `=steady` leaves it as set.
    @discardableResult
    private static func runFrameBench(frames: Int, renderer: MetalRenderer, spinnerViz: SpinnerVisualizer, vertices: [BarVertex],
                                      clear: MTLClearColor, settings: VisualizerSettings, frame: AudioFrame,
                                      pass: MTLRenderPassDescriptor, width: Int, height: Int, round: Bool,
                                      shaderKind: ShaderKind?, startAngle: Double, velocity: Double, tilt: Double, yaw: Double) -> VisualizerSettings {
        let env = ProcessInfo.processInfo.environment
        let drive: String = env["RK_PROBE_BENCH_LIGHT"] ?? "steady"
        let period: Int = max(2, Int(env["RK_PROBE_BENCH_PERIOD"] ?? "") ?? 48)
        // Cache checks: `RK_PROBE_BENCH_MUTATE=glow2` / `metal3` switches that setting half way through (a cached light material
        // must not outlive a Glow or metal change); `RK_PROBE_BENCH_FINAL=<0...1>` pins the level for the last frames, so the
        // PNG written afterwards can be compared with a still rendered by a fresh process (`l<level>`).
        // Several switches may be combined with `+` (`glow2+metal3+pal7`; also `orig` / `follow` switch the light colours); `palN` switches to palette index N (ColorPalette.orderedPresetNames).
        let mutate: [String] = (env["RK_PROBE_BENCH_MUTATE"] ?? "").split(separator: "+").map { (x: Substring) -> String in String(x) }
        // `RK_PROBE_BENCH_COLORS=sweep` replaces the palette colours every frame by a slow hue sweep (period `RK_PROBE_BENCH_HUE_PERIOD`
        // frames, default 120; the lights must follow the palette, token q1); the pinned final frames use the palette again.
        let colourDrive: String = env["RK_PROBE_BENCH_COLORS"] ?? ""
        let huePeriod: Int = max(2, Int(env["RK_PROBE_BENCH_HUE_PERIOD"] ?? "") ?? 120)
        let finalLevel: Float? = Float(env["RK_PROBE_BENCH_FINAL"] ?? "")
        let finalFrames: Int = Int(env["RK_PROBE_BENCH_FINAL_FRAMES"] ?? "") ?? 60
        var settings: VisualizerSettings = settings
        var cpuMs: [Double] = []
        var gpuMs: [Double] = []
        var encodeMs: [Double] = []
        for i in 0..<frames {
            let angle: Double = startAngle + Double(i) * velocity / 60.0
            if i == frames / 2 && !mutate.isEmpty {
                settings.mutateCurrent { (profile: inout StyleProfile) -> Void in
                    if mutate.contains("glow2") { profile.spinner.glowBrightness = 2 }
                    if mutate.contains("orig") { profile.spinner.lightColors = .original }
                    if mutate.contains("follow") { profile.spinner.lightColors = .palette }
                    if mutate.contains("metal3") {
                        profile.spinner.metal = SpinnerMetal.allCases.first(where: { (m: SpinnerMetal) -> Bool in m.index == 3 }) ?? .steel
                        profile.spinner.plateMetal = SpinnerPlateMetal.allCases.first(where: { (m: SpinnerPlateMetal) -> Bool in m.index == 2 }) ?? .sameAsBody
                    }
                    for token in mutate where token.hasPrefix("pal") {
                        if let n = Int(token.dropFirst(3)), n >= 0, n < ColorPalette.orderedPresetNames.count {
                            profile.paletteName = ColorPalette.orderedPresetNames[n]
                        }
                    }
                }
            }
            if colourDrive == "sweep" && !(finalLevel != nil && i >= frames - finalFrames) {
                let hue: Float = Float(i % huePeriod) / Float(huePeriod)
                RealitySpinnerHost.shared.debugLightColors = (0..<3).map { (k: Int) -> SIMD3<Float> in benchHue(hue + Float(k) / 3) }
            } else {
                RealitySpinnerHost.shared.debugLightColors = nil
            }
            spinnerViz.debugFreeze(angle: angle, velocity: velocity, tilt: tilt, yaw: yaw)
            if let fl = finalLevel, i >= frames - finalFrames { spinnerViz.debugLightLevel(fl) }
            else if drive == "tri" {
                let phase: Double = Double(i % period) / Double(period)
                let tri: Double = phase < 0.5 ? phase * 2 : (1 - phase) * 2
                spinnerViz.debugLightLevel(Float(0.1 + 0.9 * tri))
            }
            guard let cb = renderer.makeCommandBuffer() else { return settings }
            let t0 = DispatchTime.now().uptimeNanoseconds
            renderer.renderBloom(vertices: vertices, clearColor: clear, intensity: 0, settings: settings, frame: frame,
                                 finalPass: pass, width: width, height: height, commandBuffer: cb,
                                 roundParticles: round, shaderKind: shaderKind)
            let t1 = DispatchTime.now().uptimeNanoseconds
            cb.commit(); cb.waitUntilCompleted()
            cpuMs.append(Double(t1 - t0) / 1e6)
            encodeMs.append(RealitySpinnerHost.shared.lastEncodeMs)
            gpuMs.append((cb.gpuEndTime - cb.gpuStartTime) * 1000)
        }
        func stats(_ label: String, _ xs: [Double]) {
            let sorted: [Double] = xs.sorted()
            let n: Int = sorted.count
            let mean: Double = sorted.reduce(0, +) / Double(n)
            let median: Double = sorted[n / 2]
            let p95: Double = sorted[min(n - 1, Int(Double(n) * 0.95))]
            let line: String = String(format: "RK bench %@: mean %.2f  median %.2f  p95 %.2f  max %.2f ms  (%d frames, >16.7 ms: %d)\n",
                                      label, mean, median, p95, sorted[n - 1], n, sorted.filter({ (x: Double) -> Bool in x > 16.7 }).count)
            FileHandle.standardError.write(Data(line.utf8))
        }
        stats("CPU renderBloom (whole encode call)", cpuMs)
        stats("CPU encodeFrame only               ", encodeMs)
        stats("GPU command buffer                 ", gpuMs)
        var worst: Int = 0
        for (i, x) in encodeMs.enumerated() where x > encodeMs[worst] { worst = i }
        let tail: String = "RK bench worst encode frame index \(worst) (\(String(format: "%.2f", encodeMs[worst])) ms); " + RealitySpinnerHost.shared.lightStatsText + "\n"
        FileHandle.standardError.write(Data(tail.utf8))
        return settings
    }

    /// Fully saturated colour of hue `h` (turns, wraps), for the colour-sweep benchmark.
    private static func benchHue(_ h: Float) -> SIMD3<Float> {
        let f: Float = h - h.rounded(.down)
        let r: Float = min(max(abs(f * 6 - 3) - 1, 0), 1)
        let g: Float = min(max(2 - abs(f * 6 - 2), 0), 1)
        let b: Float = min(max(2 - abs(f * 6 - 4), 0), 1)
        return SIMD3<Float>(r, g, b)
    }

    private static func writePNG(texture: MTLTexture, width: Int, height: Int, to path: String) -> Bool {
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        texture.getBytes(&data, bytesPerRow: bytesPerRow,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let alphaBits: UInt32 = CGImageAlphaInfo.premultipliedFirst.rawValue
        let orderBits: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue
        let bitmapInfo: UInt32 = alphaBits | orderBits
        guard let ctx = CGContext(data: &data, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                  space: colorSpace, bitmapInfo: bitmapInfo),
              let image = ctx.makeImage() else { return false }

        let url = URL(fileURLWithPath: path)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }
}