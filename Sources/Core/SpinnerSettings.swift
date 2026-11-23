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
import Foundation

import Foundation

/// The Spinner's persisted, user-facing settings. Stored on `StyleProfile.spinner` (every style carries a
/// default-valued copy; only the Spinner reads it). Every numeric field is clamped to its range on decode and on
/// every set, so an out-of-range or non-finite value (hand-edited JSON, a slider) can never reach the physics or a
/// renderer. Orientation (pitch and yaw), spin angle and speed are runtime state and are NOT part of this struct.
public struct SpinnerSettings: Codable, Equatable {

    // MARK: Ranges and defaults

    public static let frictionRange: ClosedRange<Double> = 0.2...5.0
    public static let pushStrengthRange: ClosedRange<Double> = 0.25...4.0
    public static let topSpeedRange: ClosedRange<Double> = 20...120
    public static let glowBrightnessRange: ClosedRange<Double> = 0...2.0
    public static let roomLightRange: ClosedRange<Double> = 0.3...1.6
    public static let sizeRange: ClosedRange<Double> = 0.4...1.5
    public static let spinBlurRange: ClosedRange<Double> = 0...1.5
    public static let shadowDarknessRange: ClosedRange<Double> = 0...0.85
    public static let shadowSpreadRange: ClosedRange<Double> = 0.3...3.0
    public static let shadowDistanceRange: ClosedRange<Double> = 0...2.5
    public static let humVolumeRange: ClosedRange<Double> = 0...1.5
    public static let musicSustainRange: ClosedRange<Double> = 0...1
    public static let musicKickRange: ClosedRange<Double> = 0...6
    public static let restingGlowRange: ClosedRange<Double> = 0...1
    public static let beatGlowRange: ClosedRange<Double> = 0...1
    /// The allowed key-step sizes in degrees (each divides 360 and 90, so exact face-on and edge-on stay reachable).
    public static let rotationStepChoices: [Int] = [5, 10, 15, 30, 45]

    public static let defaultRotationStep: Int = 15
    public static let defaultTopSpeed: Double = 60
    public static let defaultShadowDarkness: Double = 0.48
    public static let defaultMusicSustain: Double = 0.85
    public static let defaultMusicKick: Double = 2.0
    public static let defaultRestingGlow: Double = 0.5
    public static let defaultBeatGlow: Double = 1.0

    /// `value` limited to `range`; a non-finite value becomes the nearest bound (NaN: `fallback`).
    static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        if value.isNaN { return fallback }
        if value < range.lowerBound { return range.lowerBound }
        if value > range.upperBound { return range.upperBound }
        return value
    }

    static func validStep(_ value: Int) -> Int {
        rotationStepChoices.contains(value) ? value : defaultRotationStep
    }

    // MARK: Motion

    /// Multiplier on both friction terms (Coulomb and viscous). Lower coasts longer.
    public var friction: Double { didSet { friction = Self.clamp(friction, Self.frictionRange, fallback: 1.0) } }
    /// Multiplier on the scroll impulse gain.
    public var pushStrength: Double { didSet { pushStrength = Self.clamp(pushStrength, Self.pushStrengthRange, fallback: 1.0) } }
    /// Speed limit in rad/s.
    public var topSpeed: Double { didSet { topSpeed = Self.clamp(topSpeed, Self.topSpeedRange, fallback: Self.defaultTopSpeed) } }
    /// True: an opposing push only brakes and cannot restart the disc the other way until a quiet moment.
    /// False: an opposing push passes through zero and reverses (no lockout).
    public var directionLock: Bool
    /// Size of one orientation key step in degrees: 5, 10, 15, 30 or 45.
    public var rotationStepDegrees: Int { didSet { rotationStepDegrees = Self.validStep(rotationStepDegrees) } }

    // MARK: Look

    /// Which body is drawn: the disc or the tri-wing (RealityKit only; the classic shader always draws the disc).
    public var model: SpinnerModel
    /// Tri-wing only: the glowing tubes at the wing tips. The disc's rods are unaffected.
    public var edgeLights: Bool
    /// Tri-wing with edge lights: original wing colours, or three colours taken from the app's current palette. The disc's
    /// rods and the classic shader are unaffected.
    public var lightColors: SpinnerLightColors
    /// Tri-wing with edge lights: the lights pulse on the music's beat. Off = steady (level 1).
    public var beatLights: Bool
    /// Light level between beats, as a fraction of Glow brightness (used while `beatLights` is on).
    public var restingGlow: Double { didSet { restingGlow = Self.clamp(restingGlow, Self.restingGlowRange, fallback: Self.defaultRestingGlow) } }
    /// Light level a full beat reaches, as a fraction of Glow brightness (never below `restingGlow` when applied).
    public var beatGlow: Double { didSet { beatGlow = Self.clamp(beatGlow, Self.beatGlowRange, fallback: Self.defaultBeatGlow) } }
    public var metal: SpinnerMetal
    /// Tri-wing: the metal of the three wing plates (same as the body by default). RealityKit only.
    public var plateMetal: SpinnerPlateMetal
    /// Tri-wing: the metal of the three bosses under the jewel settings (same as the body by default). RealityKit only.
    public var bossMetal: SpinnerBossMetal
    public var hubFinish: SpinnerHubFinish
    /// Multiplier on rod and lit-mark emission (0 = no glow).
    public var glowBrightness: Double { didSet { glowBrightness = Self.clamp(glowBrightness, Self.glowBrightnessRange, fallback: 1.0) } }
    /// Multiplier on the non-emissive lighting of the metal.
    public var roomLight: Double { didSet { roomLight = Self.clamp(roomLight, Self.roomLightRange, fallback: 1.0) } }
    /// Puck scale relative to the current size.
    public var size: Double { didSet { size = Self.clamp(size, Self.sizeRange, fallback: 1.0) } }
    /// Multiplier on the spin blur (shutter length); 0 = no blur at any speed.
    public var spinBlur: Double { didSet { spinBlur = Self.clamp(spinBlur, Self.spinBlurRange, fallback: 1.0) } }

    // MARK: Shadow

    /// Peak shadow opacity.
    public var shadowDarkness: Double { didSet { shadowDarkness = Self.clamp(shadowDarkness, Self.shadowDarknessRange, fallback: Self.defaultShadowDarkness) } }
    /// Multiplier on the shadow's softness (blur radius).
    public var shadowSpread: Double { didSet { shadowSpread = Self.clamp(shadowSpread, Self.shadowSpreadRange, fallback: 1.0) } }
    /// Multiplier on the shadow's offset from the puck (0 = directly behind it).
    public var shadowDistance: Double { didSet { shadowDistance = Self.clamp(shadowDistance, Self.shadowDistanceRange, fallback: 1.0) } }

    // MARK: Sound and music

    public var humEnabled: Bool
    /// Multiplier on the hum's peak gain (`SpinnerTuning.humMaxGain`).
    public var humVolume: Double { didSet { humVolume = Self.clamp(humVolume, Self.humVolumeRange, fallback: 1.0) } }
    public var musicMode: SpinnerMusicMode
    /// Fraction of friction removed at full music level (sustain).
    public var musicSustain: Double { didSet { musicSustain = Self.clamp(musicSustain, Self.musicSustainRange, fallback: Self.defaultMusicSustain) } }
    /// Angular impulse in rad/s for a full-strength beat (kick).
    public var musicKick: Double { didSet { musicKick = Self.clamp(musicKick, Self.musicKickRange, fallback: Self.defaultMusicKick) } }

    // MARK: Renderer

    public var renderer: SpinnerRendererChoice

    public static let defaults = SpinnerSettings()

    public init() {
        friction = 1.0
        pushStrength = 1.0
        topSpeed = Self.defaultTopSpeed
        directionLock = true
        rotationStepDegrees = Self.defaultRotationStep
        model = .disc
        edgeLights = true
        lightColors = .original
        beatLights = false
        restingGlow = Self.defaultRestingGlow
        beatGlow = Self.defaultBeatGlow
        metal = .steel
        plateMetal = .sameAsBody
        bossMetal = .sameAsBody
        hubFinish = .lit
        glowBrightness = 1.0
        roomLight = 1.0
        size = 1.0
        spinBlur = 1.0
        shadowDarkness = Self.defaultShadowDarkness
        shadowSpread = 1.0
        shadowDistance = 1.0
        humEnabled = true
        humVolume = 1.0
        musicMode = .off
        musicSustain = Self.defaultMusicSustain
        musicKick = Self.defaultMusicKick
        renderer = .realityKit
    }
}

extension SpinnerSettings {
    private enum CodingKeys: String, CodingKey {
        case friction, pushStrength, topSpeed, directionLock, rotationStepDegrees
        case model, edgeLights, lightColors, beatLights, restingGlow, beatGlow
        case metal, plateMetal, bossMetal, hubFinish, glowBrightness, roomLight, size, spinBlur
        case shadowDarkness, shadowSpread, shadowDistance
        case humEnabled, humVolume, musicMode, musicSustain, musicKick
        case renderer
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SpinnerSettings()
        friction = try c.decodeIfPresent(Double.self, forKey: .friction) ?? d.friction
        pushStrength = try c.decodeIfPresent(Double.self, forKey: .pushStrength) ?? d.pushStrength
        topSpeed = try c.decodeIfPresent(Double.self, forKey: .topSpeed) ?? d.topSpeed
        directionLock = try c.decodeIfPresent(Bool.self, forKey: .directionLock) ?? d.directionLock
        rotationStepDegrees = try c.decodeIfPresent(Int.self, forKey: .rotationStepDegrees) ?? d.rotationStepDegrees
        model = try c.decodeLossyEnum(SpinnerModel.self, forKey: .model, default: d.model)
        edgeLights = try c.decodeIfPresent(Bool.self, forKey: .edgeLights) ?? d.edgeLights
        lightColors = try c.decodeLossyEnum(SpinnerLightColors.self, forKey: .lightColors, default: d.lightColors)
        beatLights = try c.decodeIfPresent(Bool.self, forKey: .beatLights) ?? d.beatLights
        restingGlow = try c.decodeIfPresent(Double.self, forKey: .restingGlow) ?? d.restingGlow
        beatGlow = try c.decodeIfPresent(Double.self, forKey: .beatGlow) ?? d.beatGlow
        metal = try c.decodeLossyEnum(SpinnerMetal.self, forKey: .metal, default: d.metal)
        plateMetal = try c.decodeLossyEnum(SpinnerPlateMetal.self, forKey: .plateMetal, default: d.plateMetal)
        bossMetal = try c.decodeLossyEnum(SpinnerBossMetal.self, forKey: .bossMetal, default: d.bossMetal)
        hubFinish = try c.decodeLossyEnum(SpinnerHubFinish.self, forKey: .hubFinish, default: d.hubFinish)
        glowBrightness = try c.decodeIfPresent(Double.self, forKey: .glowBrightness) ?? d.glowBrightness
        roomLight = try c.decodeIfPresent(Double.self, forKey: .roomLight) ?? d.roomLight
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? d.size
        spinBlur = try c.decodeIfPresent(Double.self, forKey: .spinBlur) ?? d.spinBlur
        shadowDarkness = try c.decodeIfPresent(Double.self, forKey: .shadowDarkness) ?? d.shadowDarkness
        shadowSpread = try c.decodeIfPresent(Double.self, forKey: .shadowSpread) ?? d.shadowSpread
        shadowDistance = try c.decodeIfPresent(Double.self, forKey: .shadowDistance) ?? d.shadowDistance
        humEnabled = try c.decodeIfPresent(Bool.self, forKey: .humEnabled) ?? d.humEnabled
        humVolume = try c.decodeIfPresent(Double.self, forKey: .humVolume) ?? d.humVolume
        musicMode = try c.decodeLossyEnum(SpinnerMusicMode.self, forKey: .musicMode, default: d.musicMode)
        musicSustain = try c.decodeIfPresent(Double.self, forKey: .musicSustain) ?? d.musicSustain
        musicKick = try c.decodeIfPresent(Double.self, forKey: .musicKick) ?? d.musicKick
        renderer = try c.decodeLossyEnum(SpinnerRendererChoice.self, forKey: .renderer, default: d.renderer)
        normalize()
    }

    /// Clamps every numeric field to its range (property observers do not run inside an initializer, so decoding
    /// calls this explicitly; every later set is clamped by the observers).
    mutating func normalize() {
        friction = Self.clamp(friction, Self.frictionRange, fallback: 1.0)
        pushStrength = Self.clamp(pushStrength, Self.pushStrengthRange, fallback: 1.0)
        topSpeed = Self.clamp(topSpeed, Self.topSpeedRange, fallback: Self.defaultTopSpeed)
        rotationStepDegrees = Self.validStep(rotationStepDegrees)
        glowBrightness = Self.clamp(glowBrightness, Self.glowBrightnessRange, fallback: 1.0)
        roomLight = Self.clamp(roomLight, Self.roomLightRange, fallback: 1.0)
        size = Self.clamp(size, Self.sizeRange, fallback: 1.0)
        spinBlur = Self.clamp(spinBlur, Self.spinBlurRange, fallback: 1.0)
        shadowDarkness = Self.clamp(shadowDarkness, Self.shadowDarknessRange, fallback: Self.defaultShadowDarkness)
        shadowSpread = Self.clamp(shadowSpread, Self.shadowSpreadRange, fallback: 1.0)
        shadowDistance = Self.clamp(shadowDistance, Self.shadowDistanceRange, fallback: 1.0)
        humVolume = Self.clamp(humVolume, Self.humVolumeRange, fallback: 1.0)
        musicSustain = Self.clamp(musicSustain, Self.musicSustainRange, fallback: Self.defaultMusicSustain)
        musicKick = Self.clamp(musicKick, Self.musicKickRange, fallback: Self.defaultMusicKick)
        restingGlow = Self.clamp(restingGlow, Self.restingGlowRange, fallback: Self.defaultRestingGlow)
        beatGlow = Self.clamp(beatGlow, Self.beatGlowRange, fallback: Self.defaultBeatGlow)
    }
}

/// Which spinner style's profile governs something that runs whether or not a spinner is on screen (the hum).
public enum SpinnerProfileSelection {
    /// The active style when it is a spinner; otherwise the spinner style that was most recently active; otherwise the
    /// Disc Spinner.
    public static func style(active: VisualizerStyle, lastActive: VisualizerStyle?) -> VisualizerStyle {
        if active.isSpinnerFamily { return active }
        if let last = lastActive, last.isSpinnerFamily { return last }
        return .spinner
    }
}

extension VisualizerSettings {
    /// The settings a renderer or the hum should use, from the governing spinner style's own profile (a missing
    /// profile reads as that style's defaults). The model is derived from the STYLE (the stored `model` field is
    /// only a migration input), and the Tri-wing Spinner always uses RealityKit whatever its saved `renderer` says.
    public func spinnerSettings(lastActive: VisualizerStyle?) -> SpinnerSettings {
        let style: VisualizerStyle = SpinnerProfileSelection.style(active: visualizerStyle, lastActive: lastActive)
        var sp: SpinnerSettings = profiles[style]?.spinner ?? StyleProfile.defaults(for: style).spinner
        let model: SpinnerModel = style.spinnerModel ?? .disc
        sp.model = model
        if model == .triWing { sp.renderer = .realityKit }
        return sp
    }

    /// `spinnerSettings(lastActive:)` with no history: the active spinner style's settings, else the Disc Spinner's.
    /// The renderers read this once per frame from the frame's settings snapshot (the active style is a spinner then).
    public var spinnerSettings: SpinnerSettings { spinnerSettings(lastActive: nil) }
}
