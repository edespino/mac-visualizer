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

/// The selectable visualization styles. Drives switching and the visualizer factory.
public enum VisualizerStyle: String, Codable, CaseIterable {
    case bars, radial, mirrored, oscilloscope, particles, fountain, fireworks
    case ribbonWave = "siri"   // raw value preserved for backward-compat with existing settings.json
    case wireframe, plasma, bumpscope, joyPlot, heightfield, voronoi, lavaLamp, beatCounter, polartone, octaveMeatballs, starNest, outrunRain, xyScope, iris, tricentric, musicalSpectrum
    case spinner

    public var displayName: String {
        switch self {
        case .bars: return "Bars"
        case .radial: return "Radial"
        case .mirrored: return "Mirrored"
        case .oscilloscope: return "Oscilloscope"
        case .particles: return "Particles"
        case .fountain: return "Fountain"
        case .fireworks: return "Fireworks"
        case .ribbonWave: return "Ribbon Wave"
        case .wireframe: return "Wireframe"
        case .plasma: return "Plasma"
        case .bumpscope: return "Bumpscope"
        case .joyPlot: return "Joy Plot"
        case .heightfield: return "Heightfield"
        case .voronoi: return "Voronoi"
        case .lavaLamp: return "Lava Lamp"
        case .beatCounter: return "Beat Counter"
        case .polartone: return "Polartone"
        case .octaveMeatballs: return "Octave Meatballs"
        case .starNest: return "Star Nest"
        case .outrunRain: return "Outrun the Rain"
        case .xyScope: return "XY Scope"
        case .iris: return "Iris"
        case .tricentric: return "Tricentric"
        case .musicalSpectrum: return "Musical Spectrum"
        case .spinner: return "Spinner"
        }
    }

    /// True when the style draws particle quads that should render as soft round
    /// dots (the renderer picks the `fs_round` shader). False for spectrum-bar and
    /// oscilloscope-style geometries that want sharp rectangles.
    public var usesRoundParticles: Bool {
        switch self {
        case .particles, .fountain, .fireworks: return true
        case .bars, .radial, .mirrored, .oscilloscope, .ribbonWave, .wireframe, .plasma, .bumpscope, .joyPlot, .heightfield, .voronoi, .lavaLamp, .beatCounter, .polartone, .octaveMeatballs, .starNest, .outrunRain, .xyScope, .iris, .tricentric, .musicalSpectrum, .spinner: return false
        }
    }

    /// Centered / floating geometry (vertex-emit) styles whose drawn position
    /// can be nudged — by the per-style position offset and by the global
    /// center-below-lyrics behavior. Three families qualify: centered-radial
    /// forms (Radial, Polartone, XY Scope, Iris, Tricentric), centered 3D
    /// objects (Heightfield, Wireframe), and mid-line forms centered on y=0
    /// (Oscilloscope, Ribbon Wave, Joy Plot waveforms, and Mirrored — whose bars
    /// grow up AND down symmetrically about the center line, unlike bottom-
    /// anchored Bars). Vertical centering is meaningful for the mid-line forms;
    /// they are full width, so the horizontal offset is cosmetic.
    ///
    /// Excluded: bottom-anchored bar spectra (Bars, Musical Spectrum), particle
    /// systems (Particles, Fountain, Fireworks), the Beat Counter flash quad,
    /// and fullscreen-shader styles that paint the window edge to edge (Plasma,
    /// Bumpscope, Voronoi blobs, Lava Lamp, Star Nest, Outrun Rain). An offset
    /// on those never clears space below the lyrics.
    ///
    /// Octave Meatballs is included. Its shader shifts the field by the same
    /// offset and discards the uncovered region, so the background moves with
    /// the picture instead of staying painted across the window.
    public var supportsPositionOffset: Bool {
        switch self {
        case .radial, .polartone, .iris, .tricentric, .xyScope,
             .heightfield, .wireframe,
             .oscilloscope, .ribbonWave, .joyPlot, .mirrored,
             .octaveMeatballs,
             .spinner:
            return true
        default:
            return false
        }
    }

    /// Whether the style consumes the gained/smoothed/windowed frequency bands.
    /// Governs the Gain, Smoothing and FFT-window controls — false means all
    /// three are inert for this style. False for the waveform-only forms
    /// (Oscilloscope, Polartone, XY Scope read raw PCM) and the loudness/beat-only
    /// forms (Plasma reads raw RMS; Fireworks and Beat Counter react to the
    /// raw-peak beat), none of which pass through the band pipeline. Gain,
    /// smoothing and the FFT window are all applied in the shared analyzer before
    /// `bands`, so a style that never reads `bands` sees none of them.
    public var usesFrequencyBands: Bool {
        switch self {
        case .plasma, .fireworks, .beatCounter, .oscilloscope, .polartone, .xyScope, .spinner:
            return false
        default:
            return true
        }
    }

    /// Whether the Bars (band-count) control has a visible effect. Band-reading
    /// styles qualify, except Musical Spectrum, whose band count is fixed by its
    /// note-aligned mapping (octaves × 12), so moving Bars does nothing there.
    public var usesBarCount: Bool {
        usesFrequencyBands && self != .musicalSpectrum
    }

    /// Whether the Color palette control has a visible effect. False for the Spinner, whose colours come from its
    /// metal (the RealityKit renderer ignores the palette; the classic shader uses it only for a faint reflection tint).
    public var usesPalette: Bool { self != .spinner }

    /// Whether the style draws peak-hold caps (reads `AudioFrame.bandPeaks`).
    /// Only Bars does, so the Peak-hold-caps toggle is inert everywhere else.
    public var usesPeakHold: Bool { self == .bars }

    /// Whether the style honors `useStereoImage` (splitting L/R from
    /// `bandsLeft`/`bandsRight`). The rest ignore the toggle — including XY
    /// Scope, which is a stereo plot but reads the raw L/R waveforms directly.
    public var usesStereoImage: Bool {
        switch self {
        case .bars, .radial, .ribbonWave, .joyPlot, .heightfield, .voronoi, .lavaLamp, .iris:
            return true
        default:
            return false
        }
    }

    /// Reads per-style render mode to choose a shader
    /// kind when the style supports vertex-emit + shader-driven modes.
    /// Returns nil for vertex-emit modes (standard triangle pipeline applies).
    public func customShader(settings: VisualizerSettings) -> ShaderKind? {
        switch self {
        case .plasma: return .plasma
        case .bumpscope: return .bumpscope
        case .voronoi: return settings.current.voronoiRenderMode == .blobs ? .voronoiBlobs : nil
        case .lavaLamp:
            return settings.current.lavaLampRenderMode == .shader ? .lavaLampShader : nil
        case .octaveMeatballs: return .octaveMeatballs
        case .starNest: return .starNest
        case .outrunRain: return .outrunRain
        case .spinner: return .spinner
        default: return nil
        }
    }

    public func makeVisualizer() -> Visualizer {
        switch self {
        case .bars: return SpectrumBarsVisualizer()
        case .radial: return RadialSpectrumVisualizer()
        case .mirrored: return MirroredBarsVisualizer()
        case .oscilloscope: return OscilloscopeVisualizer()
        case .particles: return ParticleVisualizer()
        case .fountain: return SpectrumFountainVisualizer()
        case .fireworks: return FireworksVisualizer()
        case .ribbonWave: return RibbonWaveVisualizer()
        case .wireframe: return WireframeVisualizer()
        case .plasma: return PlasmaVisualizer()
        case .bumpscope: return BumpscopeVisualizer()
        case .joyPlot: return JoyPlotVisualizer()
        case .heightfield: return HeightfieldVisualizer()
        case .voronoi: return VoronoiVisualizer()
        case .lavaLamp: return LavaLampVisualizer()
        case .beatCounter: return BeatCounterVisualizer()
        case .polartone: return PolartoneVisualizer()
        case .octaveMeatballs: return OctaveMeatballsVisualizer()
        case .starNest: return StarNestVisualizer()
        case .outrunRain: return OutrunRainVisualizer()
        case .xyScope: return XYScopeVisualizer()
        case .iris: return IrisVisualizer()
        case .tricentric: return TricentricVisualizer()
        case .musicalSpectrum: return MusicalSpectrumVisualizer()
        case .spinner: return SpinnerVisualizer()
        }
    }

    /// OS check for the Spinner (RealityKit needs macOS 15). Overridable so tests can force both outcomes.
    public static var spinnerOSCheck: () -> Bool = {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0))
    }

    /// False only for `.spinner` on an OS older than macOS 15. An unavailable style is treated
    /// exactly like a disabled one everywhere (its saved profile is left untouched).
    public var isAvailable: Bool {
        self == .spinner ? Self.spinnerOSCheck() : true
    }

    /// The cases that can be chosen or reached on this OS, in case order.
    public static var availableCases: [VisualizerStyle] { allCases.filter { $0.isAvailable } }

    public var next: VisualizerStyle {
        let all = Self.availableCases
        let i = all.firstIndex(of: self) ?? -1
        return all[(i + 1) % all.count]
    }

    public var previous: VisualizerStyle {
        let all = Self.availableCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i - 1 + all.count) % all.count]
    }
}
