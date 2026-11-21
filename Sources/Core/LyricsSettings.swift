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

/// How lyric lines that have already been sung are drawn relative to
/// upcoming lines.
public enum LyricsPastMode: String, Codable, Equatable, CaseIterable {
    case dim, bright, neutral
}

/// How the active lyric line's drop shadow reacts to the beat: off, lift
/// (shadow offset grows, so the line pops off the page), glow (shadow blur
/// swells), or both. Modulates only the shadow; the text never moves.
public enum LyricBounceMode: String, Codable, Equatable, CaseIterable {
    case off, lift, glow, both
}

/// Where a lyric row sits relative to the active line.
public enum LyricRowPhase: Equatable {
    case past, active, upcoming
}

/// Settings for the lyrics overlay. App-wide (not per visualizer style).
/// Tolerant Codable: every field decodes with `decodeIfPresent ?? default`.
public struct LyricsSettings: Codable, Equatable {
    public var enabled: Bool
    public var textSize: Float             // points
    public var blockWidthFraction: Float   // fraction of the window width
    /// Where the active line is held vertically, as a fraction of the window
    /// height from the top (0.5 = center). A smaller value places it higher.
    public var activeLinePosition: Float
    public var activeColor: RGBAColor
    public var otherColor: RGBAColor
    public var otherOpacity: Float         // opacity of non-active lines
    public var pastMode: LyricsPastMode
    /// How many lines on each side of the active line stay visible. The
    /// nearest line keeps the full other-lines opacity and each line
    /// farther out is evenly more transparent, reaching invisible one line
    /// past this count. 0 turns the distance fade off (every non-active
    /// line shows at the same opacity).
    public var fadeLines: Int
    public var shadowEnabled: Bool
    public var shadowColor: RGBAColor
    public var shadowOpacity: Float
    public var shadowRadius: Float
    public var shadowOffsetX: Float
    public var shadowOffsetY: Float
    public var geminiModel: String
    /// Accept a close-but-not-exact LRCLIB recording when the exact length
    /// is not available (a different edit of the same song). The lyrics are
    /// flagged as approximate and their timing may drift; `timingOffsetMs`
    /// can nudge them. Off restores the strict within-tolerance match.
    public var acceptApproximateMatches: Bool
    /// A manual shift applied to the lyric timing, in milliseconds. Positive
    /// pulls lines earlier (useful for a drifted approximate match or
    /// systematic player-position latency). App-wide, not per song.
    public var timingOffsetMs: Int
    /// A folder of local `.lrc` files consulted before LRCLIB; empty
    /// disables it. A file named for the song fills a gap LRCLIB lacks or
    /// overrides what it returns.
    public var localLyricsFolder: String
    /// How the active line's drop shadow bounces to the beat. Driven by the
    /// adaptive `LyricBeatFollower` (live audio only, not Demo Mode); needs
    /// the drop shadow on. Modulates the shadow of the active line only.
    public var beatBounceMode: LyricBounceMode
    /// Visual magnitude of the beat bounce (taste), independent of the
    /// trigger. 1.0 is the natural strength; range 0.2…3.
    public var beatBounceStrength: Float

    public static let defaultGeminiModel = "gemini-flash-lite-latest"

    public static let defaults = LyricsSettings(
        enabled: true,
        textSize: 28,
        blockWidthFraction: 0.8,
        activeLinePosition: 0.15,
        // #4ade80
        activeColor: RGBAColor(r: 74.0 / 255.0, g: 222.0 / 255.0, b: 128.0 / 255.0, a: 1),
        otherColor: RGBAColor(r: 1, g: 1, b: 1, a: 1),
        otherOpacity: 0.45,
        pastMode: .dim,
        fadeLines: 3,
        shadowEnabled: true,
        shadowColor: RGBAColor(r: 0, g: 0, b: 0, a: 1),
        shadowOpacity: 0.8,
        shadowRadius: 4,
        shadowOffsetX: 0,
        shadowOffsetY: 2,
        geminiModel: LyricsSettings.defaultGeminiModel,
        acceptApproximateMatches: true,
        timingOffsetMs: 0,
        localLyricsFolder: "",
        beatBounceMode: .both,
        beatBounceStrength: 1.0
    )

    public init(enabled: Bool, textSize: Float, blockWidthFraction: Float,
                activeLinePosition: Float = 0.15,
                activeColor: RGBAColor, otherColor: RGBAColor, otherOpacity: Float,
                pastMode: LyricsPastMode, fadeLines: Int = 3,
                shadowEnabled: Bool, shadowColor: RGBAColor,
                shadowOpacity: Float, shadowRadius: Float, shadowOffsetX: Float,
                shadowOffsetY: Float, geminiModel: String,
                acceptApproximateMatches: Bool = true, timingOffsetMs: Int = 0,
                localLyricsFolder: String = "",
                beatBounceMode: LyricBounceMode = .both,
                beatBounceStrength: Float = 1.0) {
        self.enabled = enabled
        self.textSize = textSize
        self.blockWidthFraction = blockWidthFraction
        self.activeLinePosition = min(max(activeLinePosition, 0), 1)
        self.activeColor = activeColor
        self.otherColor = otherColor
        self.otherOpacity = otherOpacity
        self.pastMode = pastMode
        self.fadeLines = max(fadeLines, 0)
        self.shadowEnabled = shadowEnabled
        self.shadowColor = shadowColor
        self.shadowOpacity = shadowOpacity
        self.shadowRadius = shadowRadius
        self.shadowOffsetX = shadowOffsetX
        self.shadowOffsetY = shadowOffsetY
        self.geminiModel = geminiModel
        self.acceptApproximateMatches = acceptApproximateMatches
        self.timingOffsetMs = timingOffsetMs
        self.localLyricsFolder = localLyricsFolder
        self.beatBounceMode = beatBounceMode
        self.beatBounceStrength = beatBounceStrength
    }

    /// Opacity for a row in the given phase. Past lines scale the
    /// other-lines opacity by a factor taken from the web app's gray
    /// levels (#666 dim and #d0d0d0 bright against #8f8f8f upcoming).
    public func opacity(for phase: LyricRowPhase) -> Float {
        switch phase {
        case .active:
            return 1
        case .upcoming:
            return min(max(otherOpacity, 0), 1)
        case .past:
            let factor: Float
            switch pastMode {
            case .dim: factor = 0.7
            case .bright: factor = 1.45
            case .neutral: factor = 1.0
            }
            return min(max(otherOpacity * factor, 0), 1)
        }
    }

    /// Opacity for a row `distance` lines away from the active line
    /// (0 for the active line itself): the phase opacity scaled by the
    /// distance fade.
    public func opacity(for phase: LyricRowPhase, distance: Int) -> Float {
        let base = opacity(for: phase)
        guard phase != .active, fadeLines > 0 else { return base }
        let steps = Float(max(distance, 1) - 1)
        let falloff = min(max(1 - steps / Float(fadeLines), 0), 1)
        return base * falloff
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, textSize, blockWidthFraction, activeLinePosition, activeColor, otherColor, otherOpacity
        case pastMode, fadeLines, shadowEnabled, shadowColor, shadowOpacity, shadowRadius
        case shadowOffsetX, shadowOffsetY, geminiModel
        case acceptApproximateMatches, timingOffsetMs, localLyricsFolder
        case beatBounceMode, beatBounceStrength
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LyricsSettings.defaults
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        textSize = try c.decodeIfPresent(Float.self, forKey: .textSize) ?? d.textSize
        blockWidthFraction = try c.decodeIfPresent(Float.self, forKey: .blockWidthFraction) ?? d.blockWidthFraction
        activeLinePosition = min(max(try c.decodeIfPresent(Float.self, forKey: .activeLinePosition) ?? d.activeLinePosition, 0), 1)
        activeColor = try c.decodeIfPresent(RGBAColor.self, forKey: .activeColor) ?? d.activeColor
        otherColor = try c.decodeIfPresent(RGBAColor.self, forKey: .otherColor) ?? d.otherColor
        otherOpacity = try c.decodeIfPresent(Float.self, forKey: .otherOpacity) ?? d.otherOpacity
        pastMode = try c.decodeLossyEnum(LyricsPastMode.self, forKey: .pastMode, default: d.pastMode)
        fadeLines = max(try c.decodeIfPresent(Int.self, forKey: .fadeLines) ?? d.fadeLines, 0)
        shadowEnabled = try c.decodeIfPresent(Bool.self, forKey: .shadowEnabled) ?? d.shadowEnabled
        shadowColor = try c.decodeIfPresent(RGBAColor.self, forKey: .shadowColor) ?? d.shadowColor
        shadowOpacity = try c.decodeIfPresent(Float.self, forKey: .shadowOpacity) ?? d.shadowOpacity
        shadowRadius = try c.decodeIfPresent(Float.self, forKey: .shadowRadius) ?? d.shadowRadius
        shadowOffsetX = try c.decodeIfPresent(Float.self, forKey: .shadowOffsetX) ?? d.shadowOffsetX
        shadowOffsetY = try c.decodeIfPresent(Float.self, forKey: .shadowOffsetY) ?? d.shadowOffsetY
        let model = try c.decodeIfPresent(String.self, forKey: .geminiModel) ?? d.geminiModel
        geminiModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? d.geminiModel : model
        acceptApproximateMatches = try c.decodeIfPresent(Bool.self, forKey: .acceptApproximateMatches) ?? d.acceptApproximateMatches
        timingOffsetMs = try c.decodeIfPresent(Int.self, forKey: .timingOffsetMs) ?? d.timingOffsetMs
        localLyricsFolder = try c.decodeIfPresent(String.self, forKey: .localLyricsFolder) ?? d.localLyricsFolder
        beatBounceMode = try c.decodeLossyEnum(LyricBounceMode.self, forKey: .beatBounceMode, default: d.beatBounceMode)
        beatBounceStrength = try c.decodeIfPresent(Float.self, forKey: .beatBounceStrength) ?? d.beatBounceStrength
    }
}
