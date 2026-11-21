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
import AVFoundation
import Foundation
import MacVisualizerCore

// Bearing hum for the Spinner. Main-thread controlled; the render block only
// reads plain Floats (aligned 32-bit loads/stores are atomic on the supported CPUs) and
// calls the pure synth, so it takes no locks and allocates nothing. Nothing here ever sets the
// output to zero abruptly: toggling, leaving the style and music all go through gain fades in the
// synth, and the engine is stopped only after the output has sat at zero for `stopAfterSeconds`.

final class SpinnerHumPlayer {
    private var engine: AVAudioEngine?
    private var source: AVAudioSourceNode?
    private var synth: SpinnerHumSynth?
    /// [0] = signed target speed (rad/s), [1] = hum gate gain 0...1, [2] = target enabled (0 or 1), [4] = volume;
    /// written on main, read on the audio thread. [3] = current output gain, written by the audio thread.
    private let params: UnsafeMutablePointer<Float>
    private var gate = SpinnerHumGate()
    private var lastUpdate: CFTimeInterval?
    private var silentSince: CFTimeInterval?
    private var configObserver: NSObjectProtocol?
    private var needsRebuild = false
    private var lastFailure: CFTimeInterval = -.infinity
    private var loggedFailure = false
    /// Seconds the output must already have been at zero before the engine is stopped.
    private let stopAfterSeconds: CFTimeInterval = 5
    /// Output gain below this (about -74 dBFS) counts as zero.
    private let silentGain: Float = 2e-4
    private let retryAfterFailureSeconds: CFTimeInterval = 5

    init() {
        params = UnsafeMutablePointer<Float>.allocate(capacity: 5)
        params.initialize(repeating: 0, count: 5)
        params[4] = 1
    }

    deinit {
        stopEngine()
        params.deallocate()
    }

    /// Call once per frame from the draw path (main thread), in every style so the music-activity timer never
    /// stops. `enabled` is the hum toggle AND the Spinner style; `trackPlaying` is whether a player reports a track
    /// playing; `sample` is the idle audio sample (capture level, demo mode). The hum is strictly silent whenever
    /// there is any music activity (see `SpinnerHumGate`). `volume` is `SpinnerSettings.humVolume`.
    func update(now: CFTimeInterval, speed: Double, enabled: Bool, sample: IdleAudioSample,
                trackPlaying: Bool, volume: Double) {
        let dt = lastUpdate.map { now - $0 } ?? 0
        lastUpdate = now
        let gateValue = gate.update(trackPlaying: trackPlaying, sample: sample, dt: dt)
        params[0] = Float(speed)
        params[1] = Float(gateValue)
        params[2] = enabled ? 1 : 0
        params[4] = Float(volume)
        let wanted = enabled && gateValue > 0 && abs(speed) > SpinnerTuning.presenceSpeedThreshold
        if wanted {
            // A device change stopped the engine: rebuild it; the fresh synth fades in from zero.
            if needsRebuild { stopEngine(); needsRebuild = false }
            if engine == nil, now - lastFailure >= retryAfterFailureSeconds { startEngine(now: now) }
        }
        guard engine != nil else { silentSince = nil; return }
        if wanted || params[3] > silentGain {
            silentSince = nil
        } else {
            if silentSince == nil { silentSince = now }
            if let t = silentSince, now - t > stopAfterSeconds { stopEngine(); silentSince = nil }
        }
    }

    private func startEngine(now: CFTimeInterval) {
        let engine = AVAudioEngine()
        // The source is connected at the output device's own rate. A rate of 0 means the device has
        // no valid format right now (mid route change, or a device that is still waking up);
        // connecting a guessed rate to it makes start() fail, so wait and retry on a fresh graph.
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard rate > 0 else { fail(now: now, "output device has no valid format"); return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else {
            fail(now: now, "no audio format"); return
        }
        let synth = SpinnerHumSynth(sampleRate: rate)
        let p = params
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let first = abl.first, let out = first.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            synth.render(into: out, frames: Int(frameCount), targetSpeed: p[0], targetDuck: p[1], targetEnabled: p[2], targetVolume: p[4])
            p[3] = synth.currentGain
            for i in 1..<max(abl.count, 1) where i < abl.count {
                if let dst = abl[i].mData?.assumingMemoryBound(to: Float.self) {
                    dst.update(from: out, count: Int(frameCount))
                }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // Discard the whole graph; the retry builds a new engine rather than reusing this one.
            engine.stop()
            engine.detach(node)
            fail(now: now, "engine start failed: \(error.localizedDescription)")
            return
        }
        loggedFailure = false   // a later failure streak logs again
        self.engine = engine
        self.source = node
        self.synth = synth
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            // Output device changed: the engine has stopped itself. Rebuild on next use.
            self?.needsRebuild = true
        }
    }

    /// Records a failed start. Only the first failure of a streak is logged; the next attempt
    /// (after `retryAfterFailureSeconds`) always starts from a freshly built engine.
    private func fail(now: CFTimeInterval, _ message: String) {
        lastFailure = now
        if !loggedFailure {
            loggedFailure = true
            Log.spinnerHum.error("\(message, privacy: .public)")
        }
    }

    private func stopEngine() {
        if let o = configObserver { NotificationCenter.default.removeObserver(o); configObserver = nil }
        engine?.stop()
        if let engine, let source { engine.detach(source) }
        engine = nil; source = nil; synth = nil
    }
}
