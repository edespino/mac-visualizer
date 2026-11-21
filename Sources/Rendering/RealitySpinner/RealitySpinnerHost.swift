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
// Availability-free facade over the RealityKit spinner renderer. MetalRenderer talks only to this class;
// every RealityKit type stays behind `@available(macOS 15.0, *)` inside it.
import Metal
import MetalPerformanceShaders
import QuartzCore
import simd
import Foundation
import MacVisualizerCore

final class RealitySpinnerHost {
    static let shared = RealitySpinnerHost()
    enum State { case idle, preparing, ready, failed }
    private(set) var state: State = .idle
    /// Crossfade 0 (shader) ... 1 (RealityKit). Moves at 1 / `fadeSeconds` per second toward the target.
    private(set) var mix: Float = 0
    var fadeSeconds: Double = 0.3
    private var lastMixTime: CFTimeInterval?
    private var impl: AnyObject?
    /// Setup phase timings (name, milliseconds), for the probe and logs.
    private(set) var setupLog: [(String, Double)] = []
    private(set) var failure: String?
    private var setupStart: UInt64 = 0
    /// Longest single main-thread step during setup (ms) -- the worst hitch the user could see.
    private(set) var maxMainStepMs: Double = 0
    private(set) var lastEncodeMs: Double = 0

    static var isSupported: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    /// Starts the background setup once (CPU textures + mesh arrays off the main thread, RealityKit resources on main in
    /// short steps). No-op before macOS 15. Safe to call every frame.
    func beginSetupIfNeeded(device: MTLDevice) {
        guard state == .idle else { return }
        guard #available(macOS 15.0, *) else { return }
        state = .preparing
        setupStart = DispatchTime.now().uptimeNanoseconds
        startAsync(device: device)
    }

    @available(macOS 15.0, *)
    private func startAsync(device: MTLDevice) {
        let group = DispatchGroup()
        var geom: RKGeometryCPU?
        var images: RKImages?
        let frontMark: Int = SpinnerTuning.hubMark.index   // the marks are fixed: this one on the front hub, the other on the back
        let t0 = DispatchTime.now().uptimeNanoseconds
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let g = buildPuckCPU(frontMark: frontMark)
            let meshNs: UInt64 = DispatchTime.now().uptimeNanoseconds - t0
            DispatchQueue.main.async {
                let meshMs: Double = Double(meshNs) / 1e6
                self.setupLog.append(("CPU mesh arrays (background)", meshMs))
                for (name, ms) in g.hubTimings { self.setupLog.append(("CPU " + name + " (inside mesh arrays)", ms)) }
            }
            geom = g; group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let im = makeAllImages()
            images = im; group.leave()
        }
        group.notify(queue: .main) { [self] in
            if let images {
                let sortedTimings: [(String, Double)] = images.timings.sorted(by: { (l: (String, Double), r: (String, Double)) -> Bool in l.0 < r.0 })
                for (n, ms) in sortedTimings {
                    let label: String = "CPU " + n + " (background)"
                    setupLog.append((label, ms))
                }
            }
            let cpuNs: UInt64 = DispatchTime.now().uptimeNanoseconds - t0
            setupLog.append(("all CPU generation done", Double(cpuNs) / 1e6))
            guard let geom, let images else { fail("CPU generation failed"); return }
            Task { @MainActor in
                do {
                    let r = try RealitySpinnerRenderer(device: device)
                    var t = DispatchTime.now().uptimeNanoseconds
                    try await r.build(geometry: geom, images: images, lap: { (name: String) -> Void in
                        let n: UInt64 = DispatchTime.now().uptimeNanoseconds
                        let stepMs: Double = Double(n - t) / 1e6
                        let label: String = name + " (main, async steps)"
                        self.setupLog.append((label, stepMs)); t = n
                    })
                    self.impl = r
                    self.state = .ready
                    let wallNs: UInt64 = DispatchTime.now().uptimeNanoseconds - self.setupStart
                    self.setupLog.append(("total setup wall time", Double(wallNs) / 1e6))
                } catch {
                    self.fail("\(error)")
                }
            }
        }
    }

    private func fail(_ s: String) { failure = s; state = .failed }

    /// Probe helper: runs the CPU generation synchronously and pumps the main run loop until the RealityKit build is done.
    func prepareBlocking(device: MTLDevice, timeout: TimeInterval = 120) -> Bool {
        beginSetupIfNeeded(device: device)
        let deadline = Date(timeIntervalSinceNow: timeout)
        while state == .preparing && Date() < deadline { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01)) }
        return state == .ready
    }

    /// Warm-up frames done?
    private var warmed: Bool {
        if #available(macOS 15.0, *), let r = impl as? RealitySpinnerRenderer { return MainActor.assumeIsolated { r.warm } }
        return false
    }

    /// Probe helper: jump the crossfade to its end.
    func forceMix(_ m: Float) { mix = m }

    /// Advances the crossfade toward the target and returns the mix.
    func updateMix(now: CFTimeInterval, wantRealityKit: Bool) -> Float {
        let elapsed: Double = now - (lastMixTime ?? now)
        let dt: Float = Float(max(0, min(0.1, elapsed)))
        lastMixTime = now
        let isReady: Bool = (state == .ready) && warmed
        let target: Float = (wantRealityKit && isReady) ? 1 : 0
        let step: Float = dt / Float(max(fadeSeconds, 1e-3))
        if target > mix {
            mix = min(target, mix + step)
        } else {
            mix = max(target, mix - step)
        }
        return mix
    }

    /// True while the RealityKit frame must be rendered this frame (ready and either shown or still warming up).
    func shouldRender(wantRealityKit: Bool) -> Bool {
        state == .ready && (wantRealityKit && (mix > 0 || true))
    }

    /// Per-frame render + hand-off into `descriptor`'s texture. `mix` from `updateMix`.
    func encode(spinner v: SpinnerVisualizer, settings sp: SpinnerSettings, width: Int, height: Int, transparent: Bool, background: SIMD3<Float>,
                offsetX: Float, offsetY: Float, mix: Float, descriptor: MTLRenderPassDescriptor,
                commandBuffer: MTLCommandBuffer, blur: MPSImageGaussianBlur) -> Bool {
        guard #available(macOS 15.0, *), let r = impl as? RealitySpinnerRenderer, height > 0 else { return false }
        let aspect: Float = Float(width) / Float(height)
        let fullTurn: Double = 2 * Double.pi
        let spinWrapped: Double = v.physics.angle.truncatingRemainder(dividingBy: fullTurn)
        var debugZoom: Double = 1
        if SpinnerTuning.debugZoom > 0 { debugZoom = SpinnerTuning.debugZoom }
        let sizeScale: Double = debugZoom * sp.size
        let zoomValue: Float = min(1, aspect) * Float(sizeScale)
        let params = RKFrameParams(
            pitchRad: Float(v.orientation.pitch),
            yawRad: Float(v.orientation.yaw),
            spinRad: Float(spinWrapped),
            omega: Float(v.physics.velocity),
            metal: sp.metal.index, hubFinish: sp.hubFinish.index,
            zoom: zoomValue,
            width: width, height: height, transparent: transparent, background: background,
            offsetX: offsetX, offsetY: offsetY,
            hubRoll: Float(v.orientation.hubRoll),
            glow: Float(sp.glowBrightness), roomLight: Float(sp.roomLight), spinBlur: Float(sp.spinBlur),
            shadowDarkness: Float(sp.shadowDarkness), shadowSpread: Float(sp.shadowSpread),
            shadowDistance: Float(sp.shadowDistance))
        return MainActor.assumeIsolated {
            let ok = r.encodeFrame(params, mix: mix, descriptor: descriptor, commandBuffer: commandBuffer, blur: blur)
            if ok { lastEncodeMs = r.lastEncodeMs } else if let e = r.lastError { fail(e) }
            return ok
        }
    }
}
