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
import MetalKit
import MetalPerformanceShaders
import QuartzCore
import simd
import MacVisualizerCore

// CompositeUniforms, ShaderInputs, and PaletteUniform — the pipeline-level
// POD uniforms these passes bind — live in Core
// (Sources/Core/RenderPipelineUniforms.swift) with layout/builder tests; this
// renderer is a thin caller that supplies the frame clock.

/// Owns the Metal device, command queue, and render pipeline. Encodes a list of
/// `BarVertex` triangles into a render pass. Used both by the live `MTKView` and
/// the offscreen render probe.
final class MetalRenderer {
    /// Clip-space shift for fullscreen fields that honor centering. Set each
    /// frame by the view before encode. Zero for styles that ignore it.
    var contentOffsetX: Float = 0
    var contentOffsetY: Float = 0
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState         // sharp (bars, oscilloscope, etc.) — bgra8Unorm
    private let roundPipeline: MTLRenderPipelineState?   // soft round particles — bgra8Unorm
    private let pipeline16: MTLRenderPipelineState?      // sharp, rgba16Float (trail-render path)
    private let roundPipeline16: MTLRenderPipelineState? // round, rgba16Float (trail-render path)
    private let plasmaPipeline16: MTLRenderPipelineState?
    private let bumpscopePipeline16: MTLRenderPipelineState?
    private let voronoiPipeline16: MTLRenderPipelineState?
    private let lavalampPipeline16: MTLRenderPipelineState?
    private let octaveMeatballsPipeline16: MTLRenderPipelineState?
    private let starNestPipeline16: MTLRenderPipelineState?
    private let outrunRainPipeline16: MTLRenderPipelineState?
    private let spinnerPipeline16: MTLRenderPipelineState?
    private let compositePipeline: MTLRenderPipelineState?
    private let fadePipeline: MTLRenderPipelineState?    // fullscreen fade quad for trails (rgba16Float)
    private var trailTexture: MTLTexture?                 // persistent across frames when trails on (rgba16Float)
    private var pendingTrailReset = false                 // set by resetTrails(); cleared after next render
    /// The active visualizer instance. Set by the caller before each render
    /// frame so shader-driven styles (e.g. lavaLamp) can read per-frame state.
    var activeVisualizer: Visualizer?
    private let linearSampler: MTLSamplerState?
    private var vertexBuffer: MTLBuffer?
    private var vertexBufferCapacity = 0
    private var sceneTexture: MTLTexture?
    private var blurTexture: MTLTexture?
    private var bloomWidth = 0
    private var bloomHeight = 0
    private let blurSigma: Float = 8
    // softCells blur sigma is user-driven (`voronoiSoftBlurSigma`). An MPS blur
    // kernel's sigma is fixed at construction, so the kernel is (re)created
    // whenever the requested sigma changes; `softCellsBlurSigma` caches the sigma
    // of the currently-held kernel (-1 = none built yet).
    private var softCellsBlurSigma: Float = -1
    // MPS Gaussian-blur kernels are allocated once and reused every frame —
    // their sigmas are constant, so reallocating per frame was pure overhead.
    // Created lazily on first use because MPS kernels need `device`, which is
    // only assigned at the end of init?.
    private lazy var bloomBlur: MPSImageGaussianBlur = {
        let b = MPSImageGaussianBlur(device: device, sigma: blurSigma)
        b.edgeMode = .clamp
        return b
    }()
    private var softCellsBlur: MPSImageGaussianBlur?
    /// Returns an MPS Gaussian-blur kernel for `sigma`, rebuilding it only when
    /// the sigma changed since the last call (the kernel's sigma is immutable).
    private func softCellsBlurKernel(sigma: Float) -> MPSImageGaussianBlur {
        if let k = softCellsBlur, softCellsBlurSigma == sigma { return k }
        let b = MPSImageGaussianBlur(device: device, sigma: sigma)
        b.edgeMode = .clamp
        softCellsBlur = b
        softCellsBlurSigma = sigma
        return b
    }

    init?(pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vfn = library.makeFunction(name: "vs_main"),
              let ffn = library.makeFunction(name: "fs_main")
        else { return nil }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = pixelFormat

        guard let state = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }

        // Optional second pipeline using the round fragment shader.
        let rdesc = MTLRenderPipelineDescriptor()
        rdesc.vertexFunction = vfn
        rdesc.fragmentFunction = library.makeFunction(name: "fs_round")
        rdesc.colorAttachments[0].pixelFormat = pixelFormat
        self.roundPipeline = try? device.makeRenderPipelineState(descriptor: rdesc)

        let cdesc = MTLRenderPipelineDescriptor()
        cdesc.vertexFunction = library.makeFunction(name: "fullscreen_vs")
        cdesc.fragmentFunction = library.makeFunction(name: "composite_fs")
        cdesc.colorAttachments[0].pixelFormat = pixelFormat
        self.compositePipeline = try? device.makeRenderPipelineState(descriptor: cdesc)

        // Fade pipeline — uses fullscreen_vs + fade_fs, with a per-frame
        // `blendColor`-driven fade equation. Renders into the rgba16Float
        // trail texture, so the format here is .rgba16Float (NOT pixelFormat).
        // 16-bit precision lets trails fade all the way to bg without 1/255
        // quantization sticking at a faint floor.
        let fdesc = MTLRenderPipelineDescriptor()
        fdesc.vertexFunction = library.makeFunction(name: "fullscreen_vs")
        fdesc.fragmentFunction = library.makeFunction(name: "fade_fs")
        fdesc.colorAttachments[0].pixelFormat = .rgba16Float
        fdesc.colorAttachments[0].isBlendingEnabled = true
        fdesc.colorAttachments[0].rgbBlendOperation = .add
        fdesc.colorAttachments[0].alphaBlendOperation = .add
        fdesc.colorAttachments[0].sourceRGBBlendFactor = .one
        fdesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        fdesc.colorAttachments[0].destinationRGBBlendFactor = .blendColor
        fdesc.colorAttachments[0].destinationAlphaBlendFactor = .zero
        self.fadePipeline = try? device.makeRenderPipelineState(descriptor: fdesc)

        // 16-bit-output variants of the sharp + round pipelines for the
        // geometry pass of the trail-render path (writes into the rgba16Float
        // trail texture). Identical to the 8-bit pipelines except for the
        // color attachment format.
        let desc16 = MTLRenderPipelineDescriptor()
        desc16.vertexFunction = vfn
        desc16.fragmentFunction = ffn
        desc16.colorAttachments[0].pixelFormat = .rgba16Float
        self.pipeline16 = try? device.makeRenderPipelineState(descriptor: desc16)

        let rdesc16 = MTLRenderPipelineDescriptor()
        rdesc16.vertexFunction = vfn
        rdesc16.fragmentFunction = library.makeFunction(name: "fs_round")
        rdesc16.colorAttachments[0].pixelFormat = .rgba16Float
        self.roundPipeline16 = try? device.makeRenderPipelineState(descriptor: rdesc16)

        // Plasma / Bumpscope pipelines — fullscreen_vs + their own fragment
        // shader, writing into the rgba16Float scene/trail texture.
        let pdesc = MTLRenderPipelineDescriptor()
        pdesc.vertexFunction = library.makeFunction(name: "fullscreen_vs")
        pdesc.fragmentFunction = library.makeFunction(name: "plasma_fs")
        pdesc.colorAttachments[0].pixelFormat = .rgba16Float
        self.plasmaPipeline16 = try? device.makeRenderPipelineState(descriptor: pdesc)

        let bdesc = MTLRenderPipelineDescriptor()
        bdesc.vertexFunction = library.makeFunction(name: "fullscreen_vs")
        bdesc.fragmentFunction = library.makeFunction(name: "bumpscope_fs")
        bdesc.colorAttachments[0].pixelFormat = .rgba16Float
        self.bumpscopePipeline16 = try? device.makeRenderPipelineState(descriptor: bdesc)

        let vdesc = MTLRenderPipelineDescriptor()
        vdesc.vertexFunction = library.makeFunction(name: "fullscreen_vs")
        vdesc.fragmentFunction = library.makeFunction(name: "voronoi_fs")
        vdesc.colorAttachments[0].pixelFormat = .rgba16Float
        self.voronoiPipeline16 = try? device.makeRenderPipelineState(descriptor: vdesc)

        let ldesc = MTLRenderPipelineDescriptor()
        ldesc.vertexFunction = library.makeFunction(name: "fullscreen_vs")
        ldesc.fragmentFunction = library.makeFunction(name: "lavalamp_fs")
        ldesc.colorAttachments[0].pixelFormat = .rgba16Float
        self.lavalampPipeline16 = try? device.makeRenderPipelineState(descriptor: ldesc)

        let odesc = MTLRenderPipelineDescriptor()
        odesc.vertexFunction = library.makeFunction(name: "fullscreen_vs")
        odesc.fragmentFunction = library.makeFunction(name: "octave_meatballs_fs")
        odesc.colorAttachments[0].pixelFormat = .rgba16Float
        self.octaveMeatballsPipeline16 = try? device.makeRenderPipelineState(descriptor: odesc)

        let sndesc = MTLRenderPipelineDescriptor()
        sndesc.vertexFunction = library.makeFunction(name: "fullscreen_vs")
        sndesc.fragmentFunction = library.makeFunction(name: "star_nest_fs")
        sndesc.colorAttachments[0].pixelFormat = .rgba16Float
        self.starNestPipeline16 = try? device.makeRenderPipelineState(descriptor: sndesc)

        let ordesc = MTLRenderPipelineDescriptor()
        ordesc.vertexFunction = library.makeFunction(name: "fullscreen_vs")
        ordesc.fragmentFunction = library.makeFunction(name: "outrun_rain_fs")
        ordesc.colorAttachments[0].pixelFormat = .rgba16Float
        self.outrunRainPipeline16 = try? device.makeRenderPipelineState(descriptor: ordesc)

        // Premultiplied-alpha blend so the cleared background (opaque or
        // transparent) shows through around the object and its soft shadow.
        let spdesc = MTLRenderPipelineDescriptor()
        spdesc.vertexFunction = library.makeFunction(name: "fullscreen_vs")
        spdesc.fragmentFunction = library.makeFunction(name: "spinner_fs")
        spdesc.colorAttachments[0].pixelFormat = .rgba16Float
        spdesc.colorAttachments[0].isBlendingEnabled = true
        spdesc.colorAttachments[0].rgbBlendOperation = .add
        spdesc.colorAttachments[0].alphaBlendOperation = .add
        spdesc.colorAttachments[0].sourceRGBBlendFactor = .one
        spdesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        spdesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        spdesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        self.spinnerPipeline16 = try? device.makeRenderPipelineState(descriptor: spdesc)

        let sdesc = MTLSamplerDescriptor()
        sdesc.minFilter = .linear
        sdesc.magFilter = .linear
        sdesc.sAddressMode = .clampToEdge
        sdesc.tAddressMode = .clampToEdge
        self.linearSampler = device.makeSamplerState(descriptor: sdesc)

        self.device = device
        self.commandQueue = queue
        self.pipeline = state
    }

    /// Background clear color. Soft off-black for opaque mode; fully transparent
    /// black for transparency modes so empty pixels become see-through.
    func clearColor(for settings: VisualizerSettings) -> MTLClearColor {
        if settings.windowTransparencyMode == .opaque {
            return MTLClearColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)
        }
        return MTLClearColorMake(0, 0, 0, 0)
    }

    /// Encode one frame: clear to `clearColor`, then draw `vertices` as triangles.
    /// Pass `roundParticles: true` for particle-style visualizers (particles, fountain,
    /// fireworks) so each emitted quad renders as a soft circle instead of a sharp square.
    /// Pass `highPrecision: true` when the destination texture is rgba16Float
    /// (the bloom scene texture); selects `pipeline16`/`roundPipeline16` which
    /// declare matching color-attachment formats. Default false targets the
    /// bgra8Unorm drawable in the no-glow no-trail path.
    func encode(vertices: [BarVertex],
                clearColor: MTLClearColor,
                into descriptor: MTLRenderPassDescriptor,
                commandBuffer: MTLCommandBuffer,
                roundParticles: Bool = false,
                highPrecision: Bool = false,
                brightness: Float = 1) {
        descriptor.colorAttachments[0].loadAction = .clear
        // Dim the background alongside the geometry so this path matches the
        // composite path, where the dimmer multiplies the whole frame
        // (background included, since it lives in the scene texture). Callers
        // that feed composite pass brightness 1, making this a no-op for them.
        let dimmed = Double(brightness)
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: clearColor.red * dimmed,
            green: clearColor.green * dimmed,
            blue: clearColor.blue * dimmed,
            alpha: clearColor.alpha)
        descriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        let selected: MTLRenderPipelineState
        if highPrecision {
            selected = (roundParticles ? roundPipeline16 : nil) ?? pipeline16 ?? pipeline
        } else {
            selected = (roundParticles ? roundPipeline : nil) ?? pipeline
        }
        encoder.setRenderPipelineState(selected)

        if !vertices.isEmpty {
            drawGeometry(vertices, into: encoder, brightness: brightness)
        }
        encoder.endEncoding()
    }

    /// Uploads `vertices` into the reused vertex buffer, binds the global
    /// dimmer at fragment buffer 0, and draws. `fs_main` / `fs_round` REQUIRE
    /// that uniform — a draw that skips it reads an unbound buffer and renders
    /// the geometry black — so every geometry draw goes through here rather
    /// than repeating the sequence. Passes that hand their output to
    /// `composite_fs` use brightness 1, since composite applies the dimmer to
    /// the whole frame; only draws that land directly on the drawable dim here.
    ///
    /// Grow-only pooled vertex buffer: reallocated only when a larger one is
    /// needed, then memcpy'd each frame (no per-draw allocation in the loop).
    private func drawGeometry(_ vertices: [BarVertex],
                              into encoder: MTLRenderCommandEncoder,
                              brightness: Float) {
        let length = vertices.count * MemoryLayout<BarVertex>.stride
        if vertexBuffer == nil || vertexBufferCapacity < length {
            vertexBuffer = device.makeBuffer(length: length, options: .storageModeShared)
            vertexBufferCapacity = length
        }
        guard let buffer = vertexBuffer else { return }
        vertices.withUnsafeBytes { raw in
            memcpy(buffer.contents(), raw.baseAddress!, length)
        }
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        var dim = brightness
        encoder.setFragmentBytes(&dim, length: MemoryLayout<Float>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    func makeCommandBuffer() -> MTLCommandBuffer? { commandQueue.makeCommandBuffer() }

    /// Schedule the persistent trail texture to be cleared on the next render
    /// frame. Used when switching visualizer styles so the new style starts on
    /// a clean background instead of inheriting the previous style's faded
    /// content.
    func resetTrails() {
        pendingTrailReset = true
    }

    private func ensureBloomTextures(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        if width == bloomWidth, height == bloomHeight, sceneTexture != nil { return }
        // All offscreen textures (scene, blur, trail) are rgba16Float so HDR
        // palette stops (RGB > 1) survive geometry-write -> MPS blur -> composite
        // unclamped. Final clamp to [0,1] happens at the drawable write inside
        // composite_fs's float4 return. The geometry pipelines used to write to
        // scene/trail are pipeline16 / roundPipeline16 (rgba16Float-output);
        // the bgra8Unorm pipeline / roundPipeline only target the drawable
        // directly via the no-glow `encode()` path.
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead, .shaderWrite]
        d.storageMode = .private
        sceneTexture = device.makeTexture(descriptor: d)
        blurTexture = device.makeTexture(descriptor: d)
        trailTexture = device.makeTexture(descriptor: d)
        bloomWidth = width
        bloomHeight = height
        // A freshly allocated trailTexture holds undefined contents; blending
        // the fade pass over it would show garbage pixels on the first frames.
        // Request the one-shot clear the trail path already implements (see
        // pendingTrailReset in renderWithTrails) so first use starts from the
        // background color.
        pendingTrailReset = true
    }

    /// Bloom path: geometry -> sceneTexture, MPS blur -> blurTexture, composite -> finalPass.
    /// `finalPass` is the destination pass (drawable's for live, an offscreen pass for the probe).
    /// Caller presents/commits the command buffer.
    func renderBloom(vertices: [BarVertex],
                     clearColor: MTLClearColor,
                     intensity: Float,
                     settings: VisualizerSettings,
                     frame: AudioFrame,
                     finalPass: MTLRenderPassDescriptor,
                     width: Int,
                     height: Int,
                     commandBuffer: MTLCommandBuffer,
                     roundParticles: Bool = false,
                     shaderKind: ShaderKind? = nil,
                     effectivePalette: ColorPalette? = nil) {
        ensureBloomTextures(width: width, height: height)
        guard let sceneTexture, let blurTexture,
              let compositePipeline, let linearSampler else {
            encode(vertices: vertices, clearColor: clearColor, into: finalPass,
                   commandBuffer: commandBuffer, roundParticles: roundParticles,
                   brightness: effectiveOutputBrightness(settings))
            return
        }

        // Pass 1: scene fill -> sceneTexture. Geometry path for normal styles;
        // shader path for plasma / bumpscope (writes through encodeShaderFill).
        let scenePass = MTLRenderPassDescriptor()
        scenePass.colorAttachments[0].texture = sceneTexture
        if let shaderKind {
            encodeShaderFill(kind: shaderKind, frame: frame, settings: settings,
                             clearColor: clearColor, into: scenePass,
                             commandBuffer: commandBuffer, effectivePalette: effectivePalette)
        } else {
            encode(vertices: vertices, clearColor: clearColor, into: scenePass,
                   commandBuffer: commandBuffer, roundParticles: roundParticles,
                   highPrecision: true)
        }

        // SoftCells post-process: blur sceneTexture in-place before the bloom pass.
        let isVoronoiSoftCellsBloom = settings.visualizerStyle == .voronoi
                                       && settings.current.voronoiRenderMode == .softCells
        if isVoronoiSoftCellsBloom {
            applySoftCellsBlur(source: sceneTexture, temp: blurTexture,
                               sigma: Float(max(1e-2, settings.voronoiSoftBlurSigma)),
                               commandBuffer: commandBuffer)
        }

        // Pass 2: MPS Gaussian blur sceneTexture -> blurTexture.
        bloomBlur.encode(commandBuffer: commandBuffer, sourceTexture: sceneTexture, destinationTexture: blurTexture)

        // Pass 3: composite -> finalPass.
        finalPass.colorAttachments[0].loadAction = .clear
        finalPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        finalPass.colorAttachments[0].storeAction = .store
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: finalPass) else { return }
        enc.setRenderPipelineState(compositePipeline)
        enc.setFragmentTexture(sceneTexture, index: 0)
        enc.setFragmentTexture(blurTexture, index: 1)
        enc.setFragmentSamplerState(linearSampler, index: 0)
        var u = makeCompositeUniforms(intensity: intensity, settings: settings)
        enc.setFragmentBytes(&u, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// Trail-persistence render path. Each frame: fade the persistent
    /// `trailTexture` toward the bg by `(1 - persistence)`, draw geometry
    /// on top with `loadAction = .load`, blur for bloom, composite to
    /// `finalPass`.
    ///
    /// `persistence` should be in `[0, 0.97]`. When `persistence == 0` the
    /// fade pass produces `bg + dst*0 = bg`, equivalent to a clear; callers
    /// can still avoid this method when they want zero overhead.
    func renderWithTrails(vertices: [BarVertex],
                          clearColor: MTLClearColor,
                          intensity: Float,
                          persistence: Float,
                          glow: Bool,
                          settings: VisualizerSettings,
                          frame: AudioFrame,
                          finalPass: MTLRenderPassDescriptor,
                          width: Int,
                          height: Int,
                          commandBuffer: MTLCommandBuffer,
                          roundParticles: Bool = false,
                          shaderKind: ShaderKind? = nil,
                          effectivePalette: ColorPalette? = nil) {
        ensureBloomTextures(width: width, height: height)
        guard let trailTexture, let blurTexture,
              let fadePipeline, let compositePipeline, let linearSampler,
              let pipeline16 else {
            // Fallback: behave like the non-trail path so we never lose a frame.
            if glow {
                renderBloom(vertices: vertices, clearColor: clearColor, intensity: intensity,
                            settings: settings, frame: frame,
                            finalPass: finalPass, width: width, height: height,
                            commandBuffer: commandBuffer, roundParticles: roundParticles,
                            shaderKind: shaderKind)
            } else if let shaderKind {
                renderBloom(vertices: vertices, clearColor: clearColor, intensity: 0,
                            settings: settings, frame: frame,
                            finalPass: finalPass, width: width, height: height,
                            commandBuffer: commandBuffer, roundParticles: roundParticles,
                            shaderKind: shaderKind)
            } else {
                encode(vertices: vertices, clearColor: clearColor, into: finalPass,
                       commandBuffer: commandBuffer, roundParticles: roundParticles,
                       brightness: effectiveOutputBrightness(settings))
            }
            return
        }

        let bgR = Float(clearColor.red)
        let bgG = Float(clearColor.green)
        let bgB = Float(clearColor.blue)
        let invP = 1.0 - persistence

        // Trail reset (requested by resetTrails(), typically on style switch):
        // do a one-shot clear of the trail texture to the bg color before the
        // fade pass runs, so the new style starts on a clean background.
        if pendingTrailReset {
            let reset = MTLRenderPassDescriptor()
            reset.colorAttachments[0].texture = trailTexture
            reset.colorAttachments[0].loadAction = .clear
            reset.colorAttachments[0].clearColor = clearColor
            reset.colorAttachments[0].storeAction = .store
            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: reset) {
                enc.endEncoding()
                // Clear the flag only once the clear pass is actually encoded;
                // a transient encoder failure keeps the reset pending so the
                // next frame retries instead of blending undefined contents.
                pendingTrailReset = false
            }
        }

        // Pass 1: Fade pass — render fullscreen fade quad into trailTexture
        // with loadAction = .load so existing contents are preserved.
        //
        // Skipped for shader-driven visualizers (plasma, bumpscope) because
        // their fullscreen fragment shaders write opaque RGBA over every
        // pixel of the trail texture, fully overwriting any faded prior
        // frames. trailPersistence is effectively a no-op for shader styles —
        // they redraw the whole scene each frame. Skipping the fade saves a
        // pass and avoids a misleading code path.
        if shaderKind == nil {
            let fadePass = MTLRenderPassDescriptor()
            fadePass.colorAttachments[0].texture = trailTexture
            fadePass.colorAttachments[0].loadAction = .load
            fadePass.colorAttachments[0].storeAction = .store
            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: fadePass) {
                enc.setRenderPipelineState(fadePipeline)
                // Source color = bg * (1 - persistence). Blend equation does the rest.
                var fadeRGBA = SIMD4<Float>(bgR * invP, bgG * invP, bgB * invP, 1)
                enc.setFragmentBytes(&fadeRGBA, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                enc.setBlendColor(red: persistence, green: persistence, blue: persistence, alpha: 1)
                // The fullscreen_vs vertex shader synthesizes a screen-covering triangle from vid.
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
            }
        }

        // Pass 2: Scene fill — either draw vertex geometry on top of the
        // faded trail (loadAction = .load preserves the fade), OR run the
        // shader-driven fragment shader (loadAction = .clear starts each
        // frame fresh since the shader overwrites everything anyway).
        if let shaderKind {
            // Identical to the bloom path's scene fill: clear the trail texture
            // and run the shader. Shared via encodeShaderFill so the
            // kind->pipeline switch + uniform binding live in exactly one place.
            let geomPass = MTLRenderPassDescriptor()
            geomPass.colorAttachments[0].texture = trailTexture
            encodeShaderFill(kind: shaderKind, frame: frame, settings: settings,
                             clearColor: clearColor, into: geomPass,
                             commandBuffer: commandBuffer, effectivePalette: effectivePalette)
        } else if !vertices.isEmpty {
            let geomPass = MTLRenderPassDescriptor()
            geomPass.colorAttachments[0].texture = trailTexture
            geomPass.colorAttachments[0].loadAction = .load
            geomPass.colorAttachments[0].storeAction = .store
            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: geomPass) {
                enc.setRenderPipelineState((roundParticles ? roundPipeline16 : nil) ?? pipeline16)
                // brightness 1: this writes into the trail texture, which
                // composite_fs later dims for the whole frame.
                drawGeometry(vertices, into: enc, brightness: 1)
                enc.endEncoding()
            }
        }

        // SoftCells post-process: if voronoi softCells mode is active, apply a
        // soft Gaussian blur to trailTexture before the bloom/composite passes.
        // Blur trailTexture → blurTexture, then blit back; blurTexture is safe
        // to reuse here because the bloom blur (below) will overwrite it again.
        let isVoronoiSoftCells = settings.visualizerStyle == .voronoi
                                  && settings.current.voronoiRenderMode == .softCells
        if isVoronoiSoftCells {
            applySoftCellsBlur(source: trailTexture, temp: blurTexture,
                               sigma: Float(max(1e-2, settings.voronoiSoftBlurSigma)),
                               commandBuffer: commandBuffer)
        }

        if glow {
            // Pass 3: MPS Gaussian blur trailTexture -> blurTexture.
            bloomBlur.encode(commandBuffer: commandBuffer, sourceTexture: trailTexture, destinationTexture: blurTexture)

            // Pass 4: composite (trail + blur*intensity) -> finalPass.
            finalPass.colorAttachments[0].loadAction = .clear
            finalPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            finalPass.colorAttachments[0].storeAction = .store
            guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: finalPass) else { return }
            enc.setRenderPipelineState(compositePipeline)
            enc.setFragmentTexture(trailTexture, index: 0)
            enc.setFragmentTexture(blurTexture, index: 1)
            enc.setFragmentSamplerState(linearSampler, index: 0)
            var u = makeCompositeUniforms(intensity: intensity, settings: settings)
            enc.setFragmentBytes(&u, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        } else {
            // No-glow trail path: blit trailTexture straight to finalPass via
            // the composite shader with intensity 0 (so the blur term is dark).
            // Reuse `blurTexture` as a dummy — it gets multiplied by 0.
            finalPass.colorAttachments[0].loadAction = .clear
            finalPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            finalPass.colorAttachments[0].storeAction = .store
            guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: finalPass) else { return }
            enc.setRenderPipelineState(compositePipeline)
            enc.setFragmentTexture(trailTexture, index: 0)
            enc.setFragmentTexture(blurTexture, index: 1)
            enc.setFragmentSamplerState(linearSampler, index: 0)
            // intensity = 0 so the blur term doesn't contribute; vignette/grain
            // still apply for visual consistency with the glow path.
            var u = makeCompositeUniforms(intensity: 0, settings: settings)
            enc.setFragmentBytes(&u, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }
    }

    /// Shared frame clock for shader uniforms. CACurrentMediaTime() modulo
    /// 1024 seconds (~17 minutes) so the Float never loses precision over
    /// long sessions.
    private func shaderTime() -> Float {
        Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 1024))
    }

    /// Fill the destination pass with a fullscreen-shader visualizer. Used by
    /// `renderBloom` / `renderWithTrails` when `shaderKind` is non-nil.
    private func encodeShaderFill(kind: ShaderKind,
                                  frame: AudioFrame,
                                  settings: VisualizerSettings,
                                  clearColor: MTLClearColor,
                                  into descriptor: MTLRenderPassDescriptor,
                                  commandBuffer: MTLCommandBuffer,
                                  effectivePalette: ColorPalette? = nil) {
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = clearColor
        descriptor.colorAttachments[0].storeAction = .store

        // RealityKit renderer. mix 0 = shader only, 1 = RealityKit only (shader pass skipped), between = crossfade.
        // While the RealityKit scene warms up (first frames after setup) it renders with mix 0, invisible.
        var rkPlan: (host: RealitySpinnerHost, sv: SpinnerVisualizer, mix: Float)?
        if kind == .spinner, let sv = activeVisualizer as? SpinnerVisualizer {
            let host = RealitySpinnerHost.shared
            let want = settings.spinnerSettings.renderer.effective(realityKitAvailable: RealitySpinnerHost.isSupported) == .realityKit
            if want { host.beginSetupIfNeeded(device: device) }
            let m = host.updateMix(now: CACurrentMediaTime(), wantRealityKit: want)
            if host.state == .ready && (m > 0 || want) { rkPlan = (host, sv, m) }
        }
        let skipShader = (rkPlan?.mix ?? 0) >= 0.999

        let pipeline: MTLRenderPipelineState?
        switch kind {
        case .plasma: pipeline = plasmaPipeline16
        case .bumpscope: pipeline = bumpscopePipeline16
        case .voronoiBlobs: pipeline = voronoiPipeline16
        case .lavaLampShader: pipeline = lavalampPipeline16
        case .octaveMeatballs: pipeline = octaveMeatballsPipeline16
        case .starNest: pipeline = starNestPipeline16
        case .outrunRain: pipeline = outrunRainPipeline16
        case .spinner: pipeline = spinnerPipeline16
        }
        if skipShader {   // fully RealityKit; the pass only clears
            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) { enc.endEncoding() }
            encodeRealitySpinner(rkPlan, descriptor: descriptor, commandBuffer: commandBuffer, settings: settings, clearColor: clearColor)
            return
        }
        guard let pipeline,
              let enc = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        enc.setRenderPipelineState(pipeline)
        var inputs = makeShaderInputs(frame: frame, time: shaderTime())
        // When the caller supplies an already-resolved effective palette (the
        // auto-cycle crossfade), bind it; otherwise fall back to the named
        // current palette — which is bit-identical to the pre-feature build.
        var palette = effectivePalette.map { makePaletteUniform(from: $0) }
            ?? makePaletteUniform(named: settings.paletteName)
        enc.setFragmentBytes(&inputs, length: MemoryLayout<ShaderInputs>.stride, index: 0)
        enc.setFragmentBytes(&palette, length: MemoryLayout<PaletteUniform>.stride, index: 1)
        if kind == .plasma {
            var p = makePlasmaUniforms(settings)
            enc.setFragmentBytes(&p, length: MemoryLayout<PlasmaUniforms>.stride, index: 2)
        }
        if kind == .bumpscope {
            var b = makeBumpscopeUniforms(settings)
            enc.setFragmentBytes(&b, length: MemoryLayout<BumpscopeUniforms>.stride, index: 2)
        }
        if kind == .voronoiBlobs {
            let fade = (activeVisualizer as? VoronoiVisualizer)?.currentFadeBrightness() ?? 1.0
            var v = makeVoronoiUniforms(seeds: MetalRenderer.voronoiSeeds, fadeBrightness: fade,
                                        frame: frame, settings: settings)
            enc.setFragmentBytes(&v, length: MemoryLayout<VoronoiUniforms>.stride, index: 2)
        }
        if kind == .lavaLampShader {
            var l = makeLavaLampUniforms(visualizer: activeVisualizer as? LavaLampVisualizer,
                                         frame: frame, settings: settings)
            enc.setFragmentBytes(&l, length: MemoryLayout<LavaLampUniforms>.stride, index: 2)
        }
        if kind == .octaveMeatballs {
            var om = makeOctaveMeatballsUniforms(settings,
                                                  offsetX: contentOffsetX,
                                                  offsetY: contentOffsetY)
            enc.setFragmentBytes(&om, length: MemoryLayout<OctaveMeatballsUniforms>.stride, index: 2)
        }
        if kind == .starNest {
            var sn = makeStarNestUniforms(settings)
            enc.setFragmentBytes(&sn, length: MemoryLayout<StarNestUniforms>.stride, index: 2)
        }
        if kind == .outrunRain {
            var or = makeOutrunRainUniforms(settings)
            enc.setFragmentBytes(&or, length: MemoryLayout<OutrunRainUniforms>.stride, index: 2)
        }
        if kind == .spinner {
            var sp = (activeVisualizer as? SpinnerVisualizer)?
                .makeUniforms(offsetX: contentOffsetX, offsetY: contentOffsetY, settings: settings.spinnerSettings) ?? SpinnerUniforms()
            enc.setFragmentBytes(&sp, length: MemoryLayout<SpinnerUniforms>.stride, index: 2)
        }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        encodeRealitySpinner(rkPlan, descriptor: descriptor, commandBuffer: commandBuffer, settings: settings, clearColor: clearColor)
    }

    /// Render the RealityKit puck and copy it into the scene texture over/into what the shader pass drew.
    private func encodeRealitySpinner(_ plan: (host: RealitySpinnerHost, sv: SpinnerVisualizer, mix: Float)?,
                                      descriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer,
                                      settings: VisualizerSettings, clearColor: MTLClearColor) {
        guard let plan, let tex = descriptor.colorAttachments[0].texture else { return }
        let bg = SIMD3<Float>(Float(clearColor.red), Float(clearColor.green), Float(clearColor.blue))
        _ = plan.host.encode(spinner: plan.sv, settings: settings.spinnerSettings, width: tex.width, height: tex.height,
                             transparent: settings.windowTransparencyMode != .opaque, background: bg,
                             offsetX: contentOffsetX, offsetY: contentOffsetY, mix: plan.mix,
                             descriptor: descriptor, commandBuffer: commandBuffer, blur: bloomBlur)
    }

    // Deterministic xorshift64 RNG — matches SeededRNG in Core exactly.
    // Needed here because Core's SeededRNG is internal and not exported.
    private struct LocalRNG {
        private var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
        mutating func nextU64() -> UInt64 {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return state
        }
        mutating func nextSigned() -> Float {
            let u = Float(nextU64() >> 40) / Float(1 << 24)
            return u * 2 - 1
        }
    }

    // Static seed set for the blobs render path. Distinct from the live
    // `VoronoiVisualizer.seeds` used by cells/softCells (this static/live
    // divergence is pre-existing and intentionally preserved). Generated to
    // `kVoronoiSeedCapacity`; the Core builder reads the first `voronoiSeedCount`.
    // The first 75 values are byte-identical to the prior fixed-75 set (same RNG
    // seed/sequence), so the default look is unchanged. `VoronoiUniforms` +
    // `makeVoronoiUniforms` now live in Core (Sources/Core/VoronoiUniforms.swift);
    // this renderer is a thin caller.
    private static let voronoiSeeds: [SIMD2<Float>] = {
        var rng = LocalRNG(seed: 0xCE110155)
        return (0..<kVoronoiSeedCapacity).map { _ in SIMD2<Float>(rng.nextSigned() * 0.95, rng.nextSigned() * 0.95) }
    }()

    /// Apply a soft Gaussian blur to `source` in-place. Used by the Voronoi
    /// `.softCells` render mode to soften cell edges after the standard triangle
    /// pass. The `temp` texture (same dimensions/format as `source`) is used as
    /// an intermediate destination; `source` is overwritten with the blurred result.
    private func applySoftCellsBlur(source: MTLTexture, temp: MTLTexture,
                                     sigma: Float, commandBuffer: MTLCommandBuffer) {
        let kernel = softCellsBlurKernel(sigma: sigma)
        kernel.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: temp)
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: temp,
                  sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: source.width, height: source.height, depth: 1),
                  to: source,
                  destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
    }

    private func makeCompositeUniforms(intensity: Float, settings: VisualizerSettings) -> CompositeUniforms {
        var u = MacVisualizerCore.makeCompositeUniforms(intensity: intensity, settings: settings,
                                                        time: shaderTime())
        // The spinner supplies its own coverage in the scene alpha channel.
        if settings.visualizerStyle == .spinner && u.perPixelAlphaMode > 0.5 { u.perPixelAlphaMode = 2 }
        return u
    }
}
