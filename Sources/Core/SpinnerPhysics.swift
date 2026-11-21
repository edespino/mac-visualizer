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

// Physics and tuning state for the Spinner visualization.

/// Selectable body material. Raw value is the index sent to the shader.
public enum SpinnerMetal: String, Codable, CaseIterable {
    case steel, brass, copper, blackZirconium, anodizedTitanium

    /// Material index shared by the classic shader (`spMaterial`) and the RealityKit material table. The raw value is
    /// a stable string for JSON; the index is NOT persisted.
    public var index: Int {
        switch self {
        case .steel: return 0
        case .brass: return 1
        case .copper: return 2
        case .blackZirconium: return 3
        case .anodizedTitanium: return 4
        }
    }

    /// The next material, wrapping after the last.
    public var next: SpinnerMetal {
        let all = SpinnerMetal.allCases
        let i: Int = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }

    public var displayName: String {
        switch self {
        case .steel: return "Steel"
        case .brass: return "Brass"
        case .copper: return "Copper"
        case .blackZirconium: return "Black Zirconium"
        case .anodizedTitanium: return "Anodized Titanium"
        }
    }
}

/// Hub mark. The marks are fixed: the interlocked mark is on the FRONT hub and the sign-off mark on the BACK hub,
/// in both renderers (tilting the disc shows the other one). Raw value is the index sent to the shader. The
/// raw value of `SpinnerTuning.hubMark` says which mark is on the front; it is a probe-only override
/// (render-probe token `k<index>`), the app never changes it.
public enum SpinnerHubMark: String, Codable, CaseIterable {
    case interlock, signOff

    /// Mark index passed to the renderers (0 interlock, 1 sign-off).
    public var index: Int { self == .interlock ? 0 : 1 }

    public var displayName: String {
        switch self {
        case .interlock: return "Interlock"
        case .signOff: return "Sign-off"
        }
    }
}

/// Hub finish. `lit` = flat polished hub with the mark cut into it as glowing channels;
/// `raised` = plain polished hub with the mark standing proud of it as a bright low relief;
/// `engraved` = unlit: the mark laser-cut shallowly into the polished hub as a dark matte channel (no glow).
/// Independent of `SpinnerHubMark`.
public enum SpinnerHubFinish: String, Codable, CaseIterable {
    case lit, raised, engraved

    /// Finish index passed to the renderers (0 lit, 1 raised, 2 engraved).
    public var index: Int {
        switch self {
        case .lit: return 0
        case .raised: return 1
        case .engraved: return 2
        }
    }

    /// The next finish, wrapping after the last.
    public var next: SpinnerHubFinish {
        switch self {
        case .lit: return .raised
        case .raised: return .engraved
        case .engraved: return .lit
        }
    }

    public var displayName: String {
        switch self {
        case .lit: return "Lit"
        case .raised: return "Raised"
        case .engraved: return "Engraved"
        }
    }
}

/// How the playing music acts on the spin. Raw value is stable; `off` is the default.
public enum SpinnerMusicMode: String, Codable, CaseIterable {
    case off, sustain, kick, both

    /// The next mode, wrapping after the last.
    public var next: SpinnerMusicMode {
        let all = SpinnerMusicMode.allCases
        let i: Int = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .sustain: return "Sustain"
        case .kick: return "Kick"
        case .both: return "Sustain + Kick"
        }
    }
}

/// Which renderer draws the Spinner. `realityKit` is the default on macOS 15 and later; `shader` is the classic
/// renderer (bare key g switches). On older systems the shader is used automatically (see `effective(realityKitAvailable:)`).
/// While RealityKit loads, the shader is drawn and then crossfades to it.
public enum SpinnerRendererChoice: String, Codable, CaseIterable {
    case shader, realityKit

    public var displayName: String {
        switch self {
        case .shader: return "Shader"
        case .realityKit: return "RealityKit"
        }
    }
    /// The renderer actually used: RealityKit only when chosen and available on this system.
    public func effective(realityKitAvailable: Bool) -> SpinnerRendererChoice {
        self == .realityKit && realityKitAvailable ? .realityKit : .shader
    }
    public var next: SpinnerRendererChoice { self == .shader ? .realityKit : .shader }
}

/// All tuning constants for the spinner, as `static var` so they are trivial to tweak.
/// Fixed constants of the Spinner (not user options) plus the probe-only overrides. Every user-facing choice lives in
/// `SpinnerSettings` (persisted on `StyleProfile.spinner`); nothing here is mutable app state except the probe hooks
/// (`hubMark`, `debugZoom`) and the detent knobs, which are off in the app and varied by tests.
public enum SpinnerTuning {
    /// rad/s added per unit of scroll delta at `pushStrength` 1 (one ratchet notch ~ 1.0 -> 1.5 rad/s).
    public static let impulseGain: Double = 1.5
    /// The default top speed in rad/s (`SpinnerSettings.topSpeed` is the live limit). The hum's loudness and pitch curves
    /// are normalised against this value, so a higher limit simply keeps the hum at its peak.
    public static let maxSpeed: Double = SpinnerSettings.defaultTopSpeed
    /// Constant (Coulomb) deceleration in rad/s^2 at `friction` 1.
    public static let coulombFriction: Double = 0.05
    /// Viscous coefficient (1/s) at `friction` 1: deceleration proportional to speed.
    public static let viscousFriction: Double = 0.03
    /// Number of glow slots drawn by the shader (also the detent notch count when a detent is enabled).
    public static let beadCount: Int = 4
    /// Peak detent angular acceleration in rad/s^2 (0 = off; the app never enables it).
    public static var detentStrength: Double = 0
    /// Detent torque fades linearly to zero at this |velocity| (rad/s).
    public static var detentFadeSpeed: Double = 3
    /// Extra viscous damping (1/s) that acts only where the detent acts (scaled by the same speed fade), so the spinner settles into a notch in about one swing instead of rocking.
    public static var detentDamping: Double = 0
    /// Probe-only magnification of the spinner about its center. Always 1 in the app (the user's size is `SpinnerSettings.size`).
    public static var debugZoom: Double = 1
    /// Mark on the front hub (the other mark is on the back). Fixed at `.interlock` in the app; probe-only override.
    public static var hubMark: SpinnerHubMark = .interlock
    /// Option-drag sensitivity: degrees of rotation per point of mouse movement.
    public static let dragDegreesPerPoint: Double = 0.5
    /// Seconds with no scroll input after an opposing push stopped the disc before that same
    /// direction may start it again (direction lock on).
    public static let restartLockoutSeconds: Double = 0.35
    /// Time constant (s) of the ease toward the orientation target (both axes).
    public static let tiltTimeConstant: Double = 0.35
    /// Music level attack time constant (s).
    public static let musicLevelAttack: Double = 0.08
    /// Music level release time constant (s).
    public static let musicLevelRelease: Double = 0.6
    /// Scene stays visible while |velocity| exceeds this (rad/s).
    public static let presenceSpeedThreshold: Double = 0.05
    /// Seconds the scene stays visible after the spinner was last in use.
    public static let presenceLingerSeconds: Double = 8
    /// Hum peak linear gain at the reference top speed and `humVolume` 1 (0.06 is about -24 dBFS).
    public static let humMaxGain: Double = 0.06
    /// Hum loudness curve: gain = humMaxGain * (speed / maxSpeed)^exponent.
    public static let humGainExponent: Double = 1.8
    /// Time constant (s) of the hum's gain and pitch when speed rises.
    public static let humAttackSeconds: Double = 0.30
    /// Time constant (s) of the hum's gain and pitch when speed falls.
    public static let humReleaseSeconds: Double = 0.60
    /// Seconds with NO music activity (no track playing, no captured audio, no demo mode) before the hum may be heard.
    public static let humQuietSeconds: Double = 6.0
    /// Seconds the hum takes to fade to silence when music activity begins.
    public static let humFadeOutSeconds: Double = 0.8
    /// Seconds the hum takes to fade in once it is permitted again.
    public static let humFadeInSeconds: Double = 3.0
    /// Seconds the hum takes to fade in or out when toggled, on style change, and at first start.
    public static let humEnabledFadeSeconds: Double = 1.2
    /// Largest integration sub-step in seconds.
    public static let maxSubstep: Double = 1.0 / 240.0
}

public struct SpinnerPhysics: Equatable {
    public var angle: Double = 0
    public var velocity: Double = 0

    public init(angle: Double = 0, velocity: Double = 0) {
        self.angle = angle
        self.velocity = velocity
    }

    /// Direction (+1/-1) of the opposing push that last braked the disc to a stop; impulses that
    /// way are ignored until `restartLockoutSeconds` pass with no input. 0 = no lockout.
    public private(set) var lockoutDirection: Int = 0
    private var lastInputTime: TimeInterval = 0

    /// Applies a scroll impulse. The spin direction is set by the push that starts the disc from
    /// rest and kept until it stops: an opposing push only brakes (never carries through zero),
    /// and its remaining events cannot restart it the other way until a quiet `restartLockoutSeconds`.
    /// `now` is the caller's clock (seconds).
    public mutating func applyImpulse(_ scrollDelta: Double, now: TimeInterval = 0,
                                      settings: SpinnerSettings = .defaults) {
        guard scrollDelta != 0 else { return }
        let dir: Int = (scrollDelta > 0) ? 1 : -1
        let rest = SpinnerTuning.presenceSpeedThreshold
        let gain: Double = SpinnerTuning.impulseGain * settings.pushStrength
        let limit: Double = settings.topSpeed
        if !settings.directionLock {
            // No lock: an opposing push brakes, passes through zero and reverses.
            lockoutDirection = 0
            let free: Double = velocity + scrollDelta * gain
            velocity = min(max(free, -limit), limit)
            return
        }
        if lockoutDirection != 0 {
            if abs(velocity) > rest || dir != lockoutDirection {
                lockoutDirection = 0                     // moving again, or the original direction restarts it
            } else if now - lastInputTime < SpinnerTuning.restartLockoutSeconds {
                lastInputTime = now                      // ignored, but it still counts as input
                return
            } else {
                lockoutDirection = 0                     // quiet long enough: free to start this way
            }
        }
        let dv: Double = scrollDelta * gain
        let movingOpposite: Bool = (velocity > 0) != (dv > 0)
        if abs(velocity) >= rest && movingOpposite {
            let nv: Double = velocity + dv
            let crossedZero: Bool = (nv > 0) != (velocity > 0)
            if crossedZero || abs(nv) < rest {
                velocity = 0                             // stopped; the remainder is discarded
                lockoutDirection = dir
                lastInputTime = now
            } else {
                velocity = nv                            // braking only
            }
            return
        }
        let boosted: Double = velocity + dv
        velocity = min(max(boosted, -limit), limit)
    }

    /// Index of the detent barrier region the angle is in; the difference between
    /// two values is the number of notches crossed.
    private static func notchIndex(_ angle: Double) -> Int {
        let n: Double = Double(max(1, SpinnerTuning.beadCount))
        let fullTurn: Double = 2 * Double.pi
        let notches: Double = angle * n / fullTurn + 0.5
        return Int(notches.rounded(.down))
    }

    /// Adds an angular velocity change (music kick), clamped to `maxSpeed`.
    public mutating func applyKick(_ dv: Double, topSpeed: Double = SpinnerSettings.defaultTopSpeed) {
        let boosted: Double = velocity + dv
        velocity = min(max(boosted, -topSpeed), topSpeed)
    }

    /// Advances by `dt` seconds. Returns the number of bead notches crossed.
    /// `frictionScale` multiplies the Coulomb and viscous terms (1 = normal; the music drive's sustain uses it);
    /// `settings.friction` multiplies them too, and `settings.topSpeed` is the speed limit.
    @discardableResult
    public mutating func step(dt: Double, frictionScale: Double = 1,
                              settings: SpinnerSettings = .defaults) -> Int {
        var remaining = min(max(dt, 0), 0.25)
        var crossed = 0
        let total: Double = frictionScale * settings.friction
        let limit: Double = settings.topSpeed
        while remaining > 1e-9 {
            let h = min(remaining, SpinnerTuning.maxSubstep)
            remaining -= h
            crossed += substep(h, total, limit)
        }
        return crossed
    }

    private mutating func substep(_ h: Double, _ frictionScale: Double, _ limit: Double) -> Int {
        let n: Double = Double(max(1, SpinnerTuning.beadCount))
        var v: Double = velocity
        // Detent torque, fading out with speed.
        let fadeSpeed: Double = max(SpinnerTuning.detentFadeSpeed, 1e-6)
        let fade: Double = max(0, 1 - abs(v) / fadeSpeed)
        let detentTorque: Double = -SpinnerTuning.detentStrength * sin(n * angle) * fade
        v += detentTorque * h
        // Friction never reverses direction: it stops the spinner instead.
        let viscous: Double = SpinnerTuning.viscousFriction * abs(v)
        let baseFriction: Double = SpinnerTuning.coulombFriction + viscous
        let scaledFriction: Double = frictionScale * baseFriction
        let damping: Double = SpinnerTuning.detentDamping * fade * abs(v)
        let decel: Double = (scaledFriction + damping) * h
        if decel >= abs(v) {
            v = 0
        } else {
            let direction: Double = (v > 0) ? 1 : -1
            v -= decel * direction
        }
        v = min(max(v, -limit), limit)
        velocity = v
        let before: Int = Self.notchIndex(angle)
        angle += v * h
        if abs(angle) > 1e6 {
            let fullTurn: Double = 2 * Double.pi
            angle = angle.truncatingRemainder(dividingBy: fullTurn)
        }
        let after: Int = Self.notchIndex(angle)
        return abs(after - before)
    }
}

/// Plumbing from the scroll-wheel monitor to the visualizer.
/// Main-thread confined (the event monitor and the MTKView draw both run on main).
public final class SpinnerInput {
    public static let shared = SpinnerInput()
    public var pendingImpulse: Double = 0
    /// Orientation requests (key steps, reset, drag) collected between frames; drained by the visualizer.
    public var pendingOrientation = SpinnerOrientationRequests()
    /// Live angular speed, updated each frame by the visualizer (main thread).
    public private(set) var currentSpeed: Double = 0
    /// Presence tracker (stay visible while in use); times are systemUptime.
    public private(set) var presence = SpinnerPresence()
    private init() {}

    /// Called by the visualizer once per frame.
    public func noteFrame(now: TimeInterval, speed: Double, impulse: Bool) {
        currentSpeed = speed
        presence.update(now: now, speed: speed, impulse: impulse)
    }

    /// Returns and clears the accumulated orientation requests.
    public func drainOrientation() -> SpinnerOrientationRequests {
        let r = pendingOrientation
        pendingOrientation = SpinnerOrientationRequests()
        return r
    }

    /// Returns and clears the accumulated impulse.
    public func drain() -> Double {
        let v = pendingImpulse
        pendingImpulse = 0
        return v
    }
}
