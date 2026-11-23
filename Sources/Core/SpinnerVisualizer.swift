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
import simd
import Foundation
import simd

// The Spinner visualizer: physics-driven, drawn by a fragment shader or by RealityKit.

/// Spinner shader parameters bound at fragment buffer index 2.
/// Field order/types MUST match `SpinnerUniforms` in Shaders.metal
/// (7 x float, 1 x int, then float zoom, tilt, hubFinish; 44 bytes, no padding).
public struct SpinnerUniforms {
    public var angle: Float = 0          // body rotation, rad
    public var velocity: Float = 0       // rad/s
    public var frameDt: Float = 0        // seconds covered by this frame (motion blur sweep)
    public var hubMark: Float = 0        // hub mark index (SpinnerHubMark.index) as a float
    public var aspect: Float = 1         // viewport width / height
    public var offsetX: Float = 0        // clip-space content offset
    public var offsetY: Float = 0
    public var metal: Int32 = 0          // SpinnerMetal.index (material index)
    public var zoom: Float = 1           // probe-only magnification; 1 in the live app
    public var tilt: Float = 0           // view tilt about the horizontal axis, rad (0 = face-on)
    public var hubFinish: Float = 0      // SpinnerHubFinish index as a float (0 lit, 1 raised, 2 engraved)
    // Appended settings (layout must match the Metal struct): all 1 / default at the factory settings.
    public var roomLight: Float = 1      // multiplier on the non-emissive lighting of the metal
    public var glowBrightness: Float = 1 // multiplier on rod / arc / lit-mark emission
    public var spinBlur: Float = 1       // multiplier on the blur sweep (shutter length); 0 = none
    public var shadowDarkness: Float = 0.48   // peak shadow opacity (0.48 = the original look)
    public var shadowSpread: Float = 1   // multiplier on the shadow's softness
    public var shadowDistance: Float = 1 // multiplier on the shadow's offset from the puck
    public init() {}
}

/// Tilt helpers for the two-sided disc. A full turn is 360 degrees; the back face
/// shows for tilts strictly between 90 and 270.
public enum SpinnerTilt {
    /// Radians reduced to [0, 2 pi).
    public static func normalized(_ radians: Double) -> Double {
        var t = radians.truncatingRemainder(dividingBy: 2 * Double.pi)
        if t < 0 { t += 2 * Double.pi }
        return t
    }
    public static func isBackFacing(radians: Double) -> Bool {
        let t = normalized(radians)
        return t > Double.pi / 2 && t < 3 * Double.pi / 2
    }
    /// Scroll-sign side: like `isBackFacing`, but the exact edge-on poses keep the side the disc
    /// arrived from (90 reads front, 270 reads back) so the sign cannot flip-flop at rest there.
    public static func scrollIsBack(radians: Double) -> Bool {
        let t = normalized(radians), eps = 1e-9
        return t > Double.pi / 2 + eps && t <= 3 * Double.pi / 2 + eps
    }
}

/// The spin state shared by the Disc Spinner and the Tri-wing Spinner: angle, speed and the direction lock (inside
/// `SpinnerPhysics`) and the orientation (pitch and yaw with their targets). Switching between the two styles
/// therefore continues the same motion and pose. Everything else (settings, music drive, light pulse) is per style.
public final class SpinnerSharedState {
    /// The app's one shared instance (what `VisualizerStyle.makeVisualizer()` hands to both spinner styles).
    public static let shared = SpinnerSharedState()
    public var physics = SpinnerPhysics()
    public var orientation = SpinnerOrientation()
    /// Wall-clock time of the last advance, so the first frame after a switch measures dt from the other style's last frame.
    public var lastTime: TimeInterval?
    public init() {}
}

/// A spinning machined-metal toy driven by the scroll wheel (see `SpinnerInput`).
/// Drawn entirely by `spinner_fs`; `makeVertices` only advances the physics.
/// Uses wall-clock time, not `particleSpeed`.
public final class SpinnerVisualizer: Visualizer {
    /// The spin state (see `SpinnerSharedState`). A standalone `SpinnerVisualizer()` owns a private one.
    public let shared: SpinnerSharedState
    public private(set) var physics: SpinnerPhysics {
        get { shared.physics }
        set { shared.physics = newValue }
    }
    public private(set) var flash: Float = 0
    public private(set) var frameDt: Double = 0
    public private(set) var aspect: Float = 1
    private var lastTime: TimeInterval? {
        get { shared.lastTime }
        set { shared.lastTime = newValue }
    }
    private var frozen = false
    /// Pitch and yaw of the puck (see `SpinnerOrientation` for the convention).
    public private(set) var orientation: SpinnerOrientation {
        get { shared.orientation }
        set { shared.orientation = newValue }
    }
    /// Pitch in radians (the classic shader renderer shows pitch only).
    public var currentTilt: Double { orientation.pitch }
    /// Yaw in radians (RealityKit only).
    public var currentYaw: Double { orientation.yaw }
    private var music = SpinnerMusicDrive()
    private var clock: Double = 0
    /// Tri-wing light level (0...1) for this frame: the beat pulse of the edge lights (`SpinnerLightPulse`). 1 unless
    /// `beatLights` is on. The probe can pin it with `debugLightLevel`.
    public private(set) var lightLevel: Float = 1
    private var lightPulse = SpinnerLightPulse()
    private var debugLight: Float?

    /// Probe hook: forces the light level (0...1) for stills.
    public func debugLightLevel(_ level: Float) { debugLight = level; lightLevel = level }

    public init(shared: SpinnerSharedState = SpinnerSharedState()) { self.shared = shared }

    /// True while the back face shows (the front face's normal points away from the viewer).
    public var isBackFacing: Bool { !orientation.facesViewerFront }

    /// Applies key steps, a reset and drag movement collected since the last frame.
    public func apply(_ requests: SpinnerOrientationRequests, stepDegrees: Double = Double(SpinnerSettings.defaultRotationStep)) {
        let step: Double = stepDegrees * Double.pi / 180
        if requests.dragPitchRadians != 0 || requests.dragYawRadians != 0 {
            orientation.nudge(pitchBy: requests.dragPitchRadians, yawBy: requests.dragYawRadians)
        }
        var pitchLeft: Int = requests.pitchSteps
        while pitchLeft != 0 {
            let direction: Int = pitchLeft > 0 ? 1 : -1
            orientation.step(pitch: direction, stepRadians: step)
            pitchLeft -= direction
        }
        var yawLeft: Int = requests.yawSteps
        while yawLeft != 0 {
            let direction: Int = yawLeft > 0 ? 1 : -1
            orientation.step(yaw: direction, stepRadians: step)
            yawLeft -= direction
        }
        if requests.reset { orientation.reset() }
        if requests.resetOrFlip { orientation.resetOrFlip() }
        if requests.resetOrFlipYaw { orientation.resetOrFlipYaw() }
    }

    /// Probe hook. Pins angle/velocity and the blur dt so the offscreen
    /// render probe can snapshot a given state; physics no longer advances.
    public func debugFreeze(angle: Double, velocity: Double, dt: Double = 1.0 / 60.0, flash: Float = 0, tilt: Double? = nil, yaw: Double? = nil) {
        if tilt != nil || yaw != nil {
            orientation.set(pitch: tilt ?? orientation.pitch, yaw: yaw ?? orientation.yaw)
        }
        physics = SpinnerPhysics(angle: angle, velocity: velocity)
        frameDt = dt
        self.flash = flash
        frozen = true
    }

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings,
                             palette: ColorPalette, aspect: Float) -> [BarVertex] {
        self.aspect = aspect
        let impulse = SpinnerInput.shared.drain()
        if frozen { return [] }
        let spinner: SpinnerSettings = settings.current.spinner
        apply(SpinnerInput.shared.drainOrientation(), stepDegrees: Double(spinner.rotationStepDegrees))
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed: Double = now - (lastTime ?? now)
        let dt: Double = min(max(elapsed, 0), 0.1)
        lastTime = now
        advance(dt: dt, impulse: impulse, rms: frame.rms, bassEnergy: frame.bassEnergy, now: now, spinner: spinner)
        // Beats come from the analysis queue through the inbox (the lyric beat follower's pulses); music is "playing" while
        // the frame carries a track id (the same signal the hum gate uses).
        let beat: Float = SpinnerLightInbox.shared.drain(now: now)
        lightLevel = debugLight ?? lightPulse.update(dt: dt, beatStrength: beat, trackPlaying: frame.trackId != nil, settings: spinner)
        SpinnerInput.shared.noteFrame(now: now, speed: physics.velocity, impulse: impulse != 0)
        return []
    }

    /// Deterministic core, split out for tests.
    func advance(dt: Double, impulse: Double, rms: Float = 0, bassEnergy: Float = 0, now: TimeInterval? = nil,
                 spinner: SpinnerSettings = .defaults) {
        clock += max(dt, 0)
        // The wheel pushes the same way on screen on either side: negate it on the back face.
        if impulse != 0 {
            let onBack: Bool = !orientation.facesViewerFront
            let signedImpulse: Double = onBack ? -impulse : impulse
            physics.applyImpulse(signedImpulse, now: now ?? clock, settings: spinner)
        }
        let drive = music.update(rms: rms, bassEnergy: bassEnergy, dt: dt,
                                 velocity: physics.velocity, mode: spinner.musicMode,
                                 sustain: spinner.musicSustain, kick: spinner.musicKick)
        if drive.impulse != 0 { physics.applyKick(drive.impulse, topSpeed: spinner.topSpeed) }
        let notches = physics.step(dt: dt, frictionScale: drive.frictionScale, settings: spinner)
        orientation.ease(dt: dt, timeConstant: SpinnerTuning.tiltTimeConstant)
        frameDt = dt
        if notches > 0 {
            flash = 1
        } else {
            let decayed: Float = flash - Float(dt) / 0.08
            flash = max(0, decayed)
        }
    }

    /// Uniforms for the classic shader. `settings` is the Spinner's persisted settings for this frame; the probe-only
    /// overrides (`SpinnerTuning.hubMark`, `debugZoom`) stay separate from it.
    public func makeUniforms(offsetX: Float, offsetY: Float, settings: SpinnerSettings = .defaults) -> SpinnerUniforms {
        var u = SpinnerUniforms()
        let fullTurn: Double = 2 * Double.pi
        u.angle = Float(physics.angle.truncatingRemainder(dividingBy: fullTurn))
        u.velocity = Float(physics.velocity)
        u.frameDt = Float(frameDt)
        u.hubMark = Float(SpinnerTuning.hubMark.index)
        let zoom: Double = SpinnerTuning.debugZoom * settings.size
        u.zoom = Float(zoom)
        u.aspect = max(aspect, 1e-3)
        u.offsetX = offsetX
        u.offsetY = offsetY
        u.metal = Int32(settings.metal.index)
        u.tilt = Float(orientation.normalizedPitch)
        u.hubFinish = Float(settings.hubFinish.index)
        u.roomLight = Float(settings.roomLight)
        u.glowBrightness = Float(settings.glowBrightness)
        u.spinBlur = Float(settings.spinBlur)
        u.shadowDarkness = Float(settings.shadowDarkness)
        u.shadowSpread = Float(settings.shadowSpread)
        u.shadowDistance = Float(settings.shadowDistance)
        return u
    }
}
