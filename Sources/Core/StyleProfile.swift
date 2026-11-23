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

public enum VoronoiRenderMode: String, Codable, Equatable, CaseIterable {
    case cells, blobs, softCells
}

public enum VoronoiShapeMode: String, Codable, Equatable, CaseIterable {
    case fixed
    case cycle           // reshuffle every 60s
    case drift           // per-seed noise drift, re-triangulate every frame
    case perTrack        // reshuffle on track change
}

public enum HeightfieldRenderMode: String, Codable, Equatable, CaseIterable {
    case wireframe, solid
}

public enum LavaLampRenderMode: String, Codable, Equatable, CaseIterable {
    case shader, marchingSquares
}

/// Per-visualizer-style settings. One `StyleProfile` per `VisualizerStyle` lives in
/// `VisualizerSettings.profiles`. Holds every "what does this look/feel like" knob;
/// fireworks-specific tunables live separately on `VisualizerSettings` since they
/// only apply when fireworks is the active style.
public struct StyleProfile: Codable, Equatable {
    // Palette
    public var paletteName: String
    public var customStops: [RGBAColor]

    // Sensitivity / audio
    public var gain: Float
    public var barCount: Int
    public var smoothing: Float
    public var peakHoldEnabled: Bool

    // Glow
    public var glowEnabled: Bool
    public var glowIntensity: Float

    // Window / display. NOTE: track overlay (overlayEnabled/Position/Opacity),
    // alwaysOnTop and targetFPS used to live here per-style; they were promoted
    // to app-wide fields on VisualizerSettings (they are window/display chrome,
    // not part of a visualization), so they are no longer per-style.
    public var fullscreenDisplayID: UInt32?
    public var backgroundStyle: BackgroundStyle

    // Per-style render modes
    public var voronoiRenderMode: VoronoiRenderMode
    public var voronoiShapeMode: VoronoiShapeMode
    public var heightfieldRenderMode: HeightfieldRenderMode
    public var lavaLampRenderMode: LavaLampRenderMode

    // Placement: each visualization remembers its own offset (NDC units, added to
    // the centered styles' vertices). These were per-style, then app-wide on
    // VisualizerSettings (0.11-0.13), and are per-style again; the settings decoder
    // seeds every profile from an old app-wide value. Wireframe's default sits
    // slightly low (see `defaults(for:)`).
    public var positionOffsetX: Float
    public var positionOffsetY: Float

    /// Whether this style is available: shown in the style picker and visited
    /// by next/previous cycling. Resolution of a disabled active style happens
    /// in `VisualizerSettings.effectiveStyle`.
    public var enabled: Bool

    /// Frame rate for this visualization, overriding the app-wide `targetFPS`;
    /// nil = use the global rate. (A new key, NOT the legacy per-style
    /// `targetFPS`, so old files never resurrect as overrides.)
    public var frameRateOverride: Int?

    /// The Spinner's persisted settings. Every style carries a default-valued copy (so profile copies, resets and
    /// "my defaults" snapshots stay uniform); only the Spinner reads it.
    public var spinner: SpinnerSettings

    public init(paletteName: String, customStops: [RGBAColor],
                gain: Float, barCount: Int, smoothing: Float, peakHoldEnabled: Bool,
                glowEnabled: Bool, glowIntensity: Float,
                fullscreenDisplayID: UInt32?,
                backgroundStyle: BackgroundStyle,
                voronoiRenderMode: VoronoiRenderMode = .cells,
                voronoiShapeMode: VoronoiShapeMode = .fixed,
                heightfieldRenderMode: HeightfieldRenderMode = .wireframe,
                lavaLampRenderMode: LavaLampRenderMode = .shader,
                positionOffsetX: Float = 0,
                positionOffsetY: Float = 0,
                enabled: Bool = true,
                frameRateOverride: Int? = nil,
                spinner: SpinnerSettings = SpinnerSettings()) {
        self.paletteName = paletteName
        self.customStops = customStops
        self.gain = gain
        self.barCount = barCount
        self.smoothing = smoothing
        self.peakHoldEnabled = peakHoldEnabled
        self.glowEnabled = glowEnabled
        self.glowIntensity = glowIntensity
        self.fullscreenDisplayID = fullscreenDisplayID
        self.backgroundStyle = backgroundStyle
        self.voronoiRenderMode = voronoiRenderMode
        self.voronoiShapeMode = voronoiShapeMode
        self.heightfieldRenderMode = heightfieldRenderMode
        self.lavaLampRenderMode = lavaLampRenderMode
        self.positionOffsetX = positionOffsetX
        self.positionOffsetY = positionOffsetY
        self.enabled = enabled
        self.frameRateOverride = frameRateOverride
        self.spinner = spinner
    }

    public static let defaults = StyleProfile(
        paletteName: "classic",
        customStops: [],
        gain: 1.0,
        barCount: 48,
        smoothing: 0.6,
        peakHoldEnabled: true,
        glowEnabled: true,
        glowIntensity: 0.6,
        fullscreenDisplayID: nil,
        backgroundStyle: .solid,
        voronoiRenderMode: .cells,
        voronoiShapeMode: .fixed,
        heightfieldRenderMode: .wireframe,
        lavaLampRenderMode: .shader,
        positionOffsetX: 0,
        positionOffsetY: 0,
        enabled: true
    )

    /// The default profile for `style`. Identical to `defaults` except Wireframe,
    /// whose default vertical offset is -0.07.
    public static func defaults(for style: VisualizerStyle) -> StyleProfile {
        var p = StyleProfile.defaults
        if style == .wireframe { p.positionOffsetY = -0.07 }
        if style == .triWingSpinner { p.spinner.model = .triWing }
        return p
    }
}

extension StyleProfile {
    private enum CodingKeys: String, CodingKey {
        case paletteName, customStops, gain, barCount, smoothing, peakHoldEnabled
        case glowEnabled, glowIntensity
        case fullscreenDisplayID, backgroundStyle
        case voronoiRenderMode, voronoiShapeMode, heightfieldRenderMode, lavaLampRenderMode
        case positionOffsetX, positionOffsetY
        case enabled
        case frameRateOverride
        case spinner
    }

    /// Which of the offset keys a decoded profile actually carried (the settings decoder
    /// seeds the missing ones from a legacy app-wide offset).
    struct OffsetPresence {
        let x: Bool
        let y: Bool
    }

    static func offsetPresence(in decoder: Decoder) throws -> OffsetPresence {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        return OffsetPresence(x: c.contains(.positionOffsetX), y: c.contains(.positionOffsetY))
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StyleProfile.defaults
        self.init(
            paletteName: try c.decodeIfPresent(String.self, forKey: .paletteName) ?? d.paletteName,
            customStops: try c.decodeIfPresent([RGBAColor].self, forKey: .customStops) ?? d.customStops,
            gain: try c.decodeIfPresent(Float.self, forKey: .gain) ?? d.gain,
            // Clamp to >= 1: BandMapper preconditions bandCount > 0, so a
            // persisted/hand-edited barCount <= 0 would crash on analyzer setup.
            barCount: max(1, try c.decodeIfPresent(Int.self, forKey: .barCount) ?? d.barCount),
            smoothing: try c.decodeIfPresent(Float.self, forKey: .smoothing) ?? d.smoothing,
            peakHoldEnabled: try c.decodeIfPresent(Bool.self, forKey: .peakHoldEnabled) ?? d.peakHoldEnabled,
            glowEnabled: try c.decodeIfPresent(Bool.self, forKey: .glowEnabled) ?? d.glowEnabled,
            glowIntensity: try c.decodeIfPresent(Float.self, forKey: .glowIntensity) ?? d.glowIntensity,
            fullscreenDisplayID: try c.decodeIfPresent(UInt32.self, forKey: .fullscreenDisplayID) ?? d.fullscreenDisplayID,
            backgroundStyle: try c.decodeLossyEnum(BackgroundStyle.self, forKey: .backgroundStyle, default: d.backgroundStyle),
            voronoiRenderMode: try c.decodeLossyEnum(VoronoiRenderMode.self, forKey: .voronoiRenderMode, default: d.voronoiRenderMode),
            voronoiShapeMode: try c.decodeLossyEnum(VoronoiShapeMode.self, forKey: .voronoiShapeMode, default: d.voronoiShapeMode),
            heightfieldRenderMode: try c.decodeLossyEnum(HeightfieldRenderMode.self, forKey: .heightfieldRenderMode, default: d.heightfieldRenderMode),
            lavaLampRenderMode: try c.decodeLossyEnum(LavaLampRenderMode.self, forKey: .lavaLampRenderMode, default: d.lavaLampRenderMode),
            positionOffsetX: try c.decodeIfPresent(Float.self, forKey: .positionOffsetX) ?? d.positionOffsetX,
            positionOffsetY: try c.decodeIfPresent(Float.self, forKey: .positionOffsetY) ?? d.positionOffsetY,
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled,
            frameRateOverride: try c.decodeIfPresent(Int.self, forKey: .frameRateOverride),
            spinner: try c.decodeIfPresent(SpinnerSettings.self, forKey: .spinner) ?? d.spinner
        )
    }
}