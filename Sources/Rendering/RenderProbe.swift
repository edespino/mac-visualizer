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
        if style == .spinner {
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
        // lighter backdrop (0...1) so the shadow is visible.
        var probeRealityWarmup = 0
        var spinnerBackdrop: Double = -1     // token K<gray 0...1>: a lighter backdrop so the shadow can be judged
        var probeCB: MTLCommandBuffer = commandBuffer   // replaced by a fresh buffer after RealityKit warm-up
        if style == .spinner, let sp = visualizer as? SpinnerVisualizer {
            var a = 0.0, v = 0.0
            var tiltDeg = 0.0
            var yawDeg = 0.0
            var sps = SpinnerSettings()
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
                case "g": if val > 0 { sps.renderer = .realityKit }
                case "S": sps.size = val
                case "G": sps.glowBrightness = val
                case "L": sps.roomLight = val
                case "B": sps.spinBlur = val
                case "D": sps.shadowDarkness = val
                case "P": sps.shadowSpread = val
                case "X": sps.shadowDistance = val
                case "K": spinnerBackdrop = val
                default: break }
            }
            settings.mutateCurrent { (profile: inout StyleProfile) -> Void in profile.spinner = sps }
            let tiltRadians: Double = tiltDeg * Double.pi / 180
            let yawRadians: Double = yawDeg * Double.pi / 180
            sp.debugFreeze(angle: a, velocity: v, tilt: tiltRadians, yaw: yawRadians)
            // RealityKit probe path: wait for the background setup, then warm the scene up with extra
            // frames (each is a full encode + submit through the app's own scene/composite passes) before the real one.
            if sps.renderer == .realityKit {
                let host = RealitySpinnerHost.shared
                guard host.prepareBlocking(device: renderer.device) else {
                    FileHandle.standardError.write(Data("RenderProbe: RealityKit setup failed: \(host.failure ?? "timeout")\n".utf8)); return false
                }
                host.fadeSeconds = 0       // full RealityKit in the probe
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
            let spinnerTransparent: Bool = (style == .spinner && settings.windowTransparencyMode != .opaque)
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