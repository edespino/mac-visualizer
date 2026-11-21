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
import SwiftUI
import MetalKit
import MacVisualizerCore

/// SwiftUI wrapper around an `MTKView` that continuously renders frames from the model.
struct MetalView: NSViewRepresentable {
    @ObservedObject var model: RenderModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        guard let renderer = context.coordinator.renderer else { return view }
        view.device = renderer.device
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = model.settings.activeFrameRate
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.delegate = context.coordinator
        configureViewTransparency(view, mode: model.settings.windowTransparencyMode)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        // The frame rate is set on the draw path (`Coordinator.draw`), which
        // also knows the active style's override and the idle state.
        configureViewTransparency(view, mode: model.settings.windowTransparencyMode)
    }

    private func configureViewTransparency(_ view: MTKView, mode: WindowTransparencyMode) {
        switch mode {
        case .opaque:
            view.layer?.isOpaque = true
            view.layer?.backgroundColor = nil
            view.clearColor = MTLClearColorMake(0.04, 0.04, 0.06, 1)
        case .windowOpacity, .perPixelAlpha:
            view.layer?.isOpaque = false
            view.layer?.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
            view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        }
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        let model: RenderModel
        let renderer: MetalRenderer?
        private var currentStyle: VisualizerStyle
        private var visualizer: Visualizer
        /// Idle clock. Seeded to now so a fresh launch does not fade before the
        /// first frame. Synthetic fallback frames do not count as music.
        private var idleFade = IdleFadeTracker(now: CACurrentMediaTime())
        /// Eased vertical offset contributed by the center-below-lyrics
        /// behavior, so the visualization glides (rather than jumps) when lyrics
        /// appear or disappear. The per-style manual offset is applied directly,
        /// so its sliders stay responsive.
        private var appliedLyricsOffsetY: Float = 0
        private var lastDrawTime: CFTimeInterval = CACurrentMediaTime()
        /// When the visualization last went inactive (nil while active), for the idle frame rate.
        private var inactiveSince: CFTimeInterval?

        init(model: RenderModel) {
            self.model = model
            self.renderer = MetalRenderer(pixelFormat: .bgra8Unorm)
            self.currentStyle = model.settings.effectiveStyle
            self.visualizer = model.settings.effectiveStyle.makeVisualizer()
            // Start the RealityKit scene setup (background) at launch when the Spinner is the saved style and RealityKit is the chosen renderer (the default on macOS 15+); the shader draws until it is ready.
            if currentStyle == .spinner, let r = renderer, model.settings.spinnerSettings.renderer == .realityKit {
                RealitySpinnerHost.shared.beginSetupIfNeeded(device: r.device)
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let renderer,
                  let drawable = view.currentDrawable,
                  let commandBuffer = renderer.makeCommandBuffer()
            else { return }

            // One normalized snapshot per frame: visualizerStyle is resolved to
            // the effective (enabled) style, so every read below — visualizer
            // pick, `current` profile fields, round/shader dispatch — is
            // coherent even before RenderModel's deferred correction lands.
            let settings = model.renderSettings

            let style = settings.visualizerStyle
            if style != currentStyle {
                currentStyle = style
                visualizer = style.makeVisualizer()
                // Begin RealityKit setup as soon as the Spinner becomes active (if RealityKit is the chosen renderer); the shader shows until it is ready, then crossfades.
                if style == .spinner, settings.spinnerSettings.renderer == .realityKit {
                    RealitySpinnerHost.shared.beginSetupIfNeeded(device: renderer.device)
                }
                // Clear any stale trail from the previous style before the
                // next render frame draws the new one.
                renderer.resetTrails()
            }

            let frame = model.currentFrame()

            let now = CACurrentMediaTime()
            let dt = Float(max(0, min(0.1, now - lastDrawTime)))
            lastDrawTime = now

            // Idle fade: no fresh capture, or a quiet capture, starts the hold.
            // Past the hold the visualization and lyrics ease out. A real
            // audible frame, or demo mode, brings them back. Synthetic fallback
            // frames are not music. Written only on a change.
            let audioSample = model.idleAudioSample(now: now)
            var active = idleFade.isActive(now: now, sample: audioSample)
            // Hold the scene visible while the spinner is in use, and drive the
            // bearing hum (strictly silent whenever there is music activity).
            let isSpinner = style == .spinner
            if isSpinner {
                let up = ProcessInfo.processInfo.systemUptime
                if SpinnerInput.shared.presence.isHeld(now: up) { active = true }
            }
            let spinnerSettings: SpinnerSettings = settings.spinnerSettings
            let trackPlaying: Bool = model.currentTrackId != nil
            model.spinnerHum.update(
                now: now, speed: SpinnerInput.shared.currentSpeed,
                enabled: spinnerSettings.humEnabled && isSpinner, sample: audioSample,
                trackPlaying: trackPlaying, volume: spinnerSettings.humVolume)
            if active != model.visualizerActive { model.visualizerActive = active }

            // Frame rate: the style's override or the app-wide rate while
            // playing; a low idle rate once the scene has faded out, so an idle
            // window stops loading the GPU and compositor. Written on change.
            if active { inactiveSince = nil } else if inactiveSince == nil { inactiveSince = now }
            let fps = FrameRatePolicy.rate(globalFPS: settings.targetFPS,
                                           styleOverride: settings.current.frameRateOverride,
                                           idleSeconds: inactiveSince.map { now - $0 })
            if view.preferredFramesPerSecond != fps { view.preferredFramesPerSecond = fps }

            // Rebuild capture if it has silently stalled (an output-route change
            // or a Bluetooth clock sleeping can strand the tap's aggregate with
            // no error), so the scene recovers on its own instead of staying
            // faded out while audio is actually playing.
            model.tickCaptureWatchdog(now: now)

            renderer.activeVisualizer = visualizer
            let size = view.drawableSize
            let aspect = size.height > 0 ? Float(size.width / size.height) : 1

            // Advance the palette auto-cycle on the draw path and resolve the
            // effective (possibly crossfaded) palette ONCE per frame, BEFORE vertex
            // emission. The single result feeds both CPU vertex colors (so CPU
            // vertex-emit styles crossfade too, not just shader styles) and the
            // shader fill uniform — one source of truth, no double advance. A pure
            // passthrough of the named palette when the feature is off.
            let effectivePalette = model.effectivePalette()
            var vertices = visualizer.makeVertices(frame: frame, settings: settings,
                                                   palette: effectivePalette, aspect: aspect)
            // App-wide position offset (clip space): shift a centered geometry
            // style off center. Only styles that support it are moved; shader and
            // bottom-anchored styles ignore it (shaders emit no vertices anyway).
            let supportsOffset = settings.visualizerStyle.supportsPositionOffset
            let offX: Float = supportsOffset ? settings.positionOffsetX : 0
            // Target vertical offset from the center-below-lyrics behavior: when
            // lyrics are actually on screen, center the visualization in the
            // clear space below the lowest visible line; otherwise 0 (window
            // center). The lowest-line position is stable (the active line is
            // held at its anchor and the lines below sit at fixed offsets), so a
            // settings-derived estimate in points does not drift as lines scroll.
            var lyricsTargetY: Float = 0
            if settings.centerBelowLyrics, settings.lyrics.enabled, model.lyricsShowing,
               settings.visualizerStyle.supportsPositionOffset {
                let ly = settings.lyrics
                let heightPts = Double(max(view.bounds.height, 1))
                let anchor = min(max(Double(ly.activeLinePosition), 0), 1)         // fraction from top
                let linesBelow = Double(max(ly.fadeLines, 1))                       // visible upcoming lines
                let lineHeightPts = Double(ly.textSize) * 1.6                       // text + 0.6 line spacing
                // Fraction (from top) of the lowest visible lyric line; capped so
                // the visualization keeps some room even with large text.
                let bottomFrac = min(0.9, anchor + linesBelow * lineHeightPts / heightPts)
                // Center the visualization in [bottomFrac, 1]; its natural center
                // is the window center (NDC y 0). NDC y is +1 top, -1 bottom.
                let desiredFrac = (bottomFrac + 1) / 2
                lyricsTargetY = Float(1 - 2 * desiredFrac)
            }
            // Ease the lyrics-driven offset toward its target so the position
            // glides when lyrics turn on/off (~0.6 s time constant); the manual
            // offset is applied directly for slider responsiveness.
            appliedLyricsOffsetY += (lyricsTargetY - appliedLyricsOffsetY) * min(1, dt / 0.6)
            let offY = (supportsOffset ? settings.positionOffsetY : 0) + appliedLyricsOffsetY
            if offX != 0 || abs(offY) > 0.0001 {
                let off = SIMD4<Float>(offX, offY, 0, 0)
                for i in vertices.indices { vertices[i].position += off }
            }
            renderer.contentOffsetX = offX
            renderer.contentOffsetY = offY
            let clear = renderer.clearColor(for: settings)

            guard let descriptor = view.currentRenderPassDescriptor else { return }
            let round = settings.visualizerStyle.usesRoundParticles
            let shaderKind = settings.visualizerStyle.customShader(settings: settings)
            let persistence = settings.trailPersistence
            if persistence > 0 {
                renderer.renderWithTrails(vertices: vertices, clearColor: clear,
                                          intensity: settings.glowIntensity,
                                          persistence: persistence,
                                          glow: settings.glowEnabled,
                                          settings: settings,
                                          frame: frame,
                                          finalPass: descriptor,
                                          width: Int(size.width), height: Int(size.height),
                                          commandBuffer: commandBuffer,
                                          roundParticles: round,
                                          shaderKind: shaderKind,
                                          effectivePalette: effectivePalette)
            } else if settings.glowEnabled {
                renderer.renderBloom(vertices: vertices, clearColor: clear,
                                     intensity: settings.glowIntensity,
                                     settings: settings,
                                     frame: frame,
                                     finalPass: descriptor,
                                     width: Int(size.width), height: Int(size.height),
                                     commandBuffer: commandBuffer,
                                     roundParticles: round,
                                     shaderKind: shaderKind,
                                     effectivePalette: effectivePalette)
            } else if shaderKind != nil {
                renderer.renderBloom(vertices: vertices, clearColor: clear,
                                     intensity: 0,
                                     settings: settings,
                                     frame: frame,
                                     finalPass: descriptor,
                                     width: Int(size.width), height: Int(size.height),
                                     commandBuffer: commandBuffer,
                                     roundParticles: round,
                                     shaderKind: shaderKind,
                                     effectivePalette: effectivePalette)
            } else if settings.visualizerStyle == .voronoi
                        && settings.current.voronoiRenderMode == .softCells {
                // softCells requires a post-process blur pass; route through renderBloom
                // (intensity 0) so applySoftCellsBlur has an intermediate texture to work with.
                renderer.renderBloom(vertices: vertices, clearColor: clear,
                                     intensity: 0,
                                     settings: settings,
                                     frame: frame,
                                     finalPass: descriptor,
                                     width: Int(size.width), height: Int(size.height),
                                     commandBuffer: commandBuffer,
                                     roundParticles: round,
                                     shaderKind: shaderKind,
                                     effectivePalette: effectivePalette)
            } else {
                renderer.encode(vertices: vertices, clearColor: clear,
                                into: descriptor, commandBuffer: commandBuffer,
                                roundParticles: round,
                                brightness: effectiveOutputBrightness(settings))
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}