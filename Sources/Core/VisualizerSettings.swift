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

public struct RGBAColor: Codable, Equatable {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float
    public init(r: Float, g: Float, b: Float, a: Float) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
}

public enum OverlayCorner: String, Codable, Equatable, CaseIterable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
}

public enum BackgroundStyle: String, Codable, Equatable, CaseIterable {
    case solid, gradient
}

public enum WindowTransparencyMode: String, Codable, Equatable, CaseIterable {
    case opaque
    case windowOpacity       // uniform window alpha via NSWindow.alphaValue
    case perPixelAlpha       // default: alpha = brightness, punch through
}

/// How the window-edge border behaves.
/// - `off`: never drawn.
/// - `auto`: revealed by a deliberate click in the window (pointer movement and
///   plain focus changes do not reveal it), held through a resize or drag, and
///   faded out after a short idle, so the resize edge is visible on demand
///   without a permanent frame.
/// - `always`: drawn statically at `windowBorderOpacity` (the original behavior).
public enum WindowBorderMode: String, Codable, Equatable, CaseIterable {
    case off, auto, always

    /// Cycles Off → Auto → Always → Off, for the ⌘⇧B menu command.
    public var next: WindowBorderMode {
        switch self {
        case .off: return .auto
        case .auto: return .always
        case .always: return .off
        }
    }
}

/// Polartone render mode: the static waveform ring (default) or a time-driven
/// breathing spiral that winds between the outer and inner radius bounds.
public enum PolartoneRenderMode: String, Codable, Equatable, CaseIterable {
    case ring, spiral
}

/// Which way the first Polartone spiral sweep travels.
public enum PolartoneStartDirection: String, Codable, Equatable, CaseIterable {
    case inward, outward
}

/// Top-level app settings. Visual + audio knobs live in per-style profiles
/// (`profiles[visualizerStyle]`); style-specific tunables live as flat fields
/// on this struct (they only apply when the active style matches).
///
/// For ergonomic access, the old flat field NAMES (`gain`, `smoothing`, etc.) are
/// preserved as computed forwarder properties that read/write the CURRENT profile.
/// That keeps every visualizer / view / test compiling unchanged after this refactor.
public struct VisualizerSettings: Equatable {
    public var visualizerStyle: VisualizerStyle
    public var profiles: [VisualizerStyle: StyleProfile]

    // Demo mode: when true, RenderModel feeds frames from DemoAudioSource
    // instead of the audio capture (so the visualizer reacts even when no
    // music is playing). Top-level (not per-style).
    public var demoModeEnabled: Bool

    // Number of waves drawn by the Ribbon Wave visualizer (1–6). Top-level (not
    // per-style) because it applies only when the active style is .ribbonWave.
    public var ribbonWaveCount: Int

    // Style "tweaks" — cross-style tunables that apply only to certain
    // visualizers. Top-level for the same reason as the fireworks tunables
    // (single style scope; don't duplicate across all 8 profiles).
    public var particleSize: Float            // multiplier on particle dot size; particles/fountain/fireworks (1.0 default)
    public var particleSpeed: Float           // multiplier on dt for particle physics + lifetime; particles/fountain/fireworks (1.0 default)
    public var barGap: Float                  // gap fraction between bars; bars/mirrored (0.15 default)
    public var oscilloscopeThickness: Float   // multiplier on oscilloscope line width (1.0 default)
    public var polartoneRadius: Float         // base circle radius; polartone (0.46 default)
    public var polartoneAmplitude: Float      // radial deflection per waveform sample; polartone (0.22 default)
    public var polartoneColorFloor: Float     // min palette-sample brightness floor; polartone (0.12 default)
    public var polartoneRotationSpeed: Float  // ring rotation rad/s (× frame.timestamp); polartone (0 default = static)
    public var polartonePointCount: Int       // waveform resample resolution; polartone (256 default = live analyzer length)
    public var polartonePhaseOffset: Float    // ring start angle in radians; polartone (0 default)
    public var polartoneLineHalfThickness: Float // base line half-thickness (× oscilloscopeThickness); polartone (0.006 default)
    public var polartoneWaveformClamp: Float  // waveform saturation clamp; polartone (1 default)
    public var polartoneRenderMode: PolartoneRenderMode // ring (default) vs breathing spiral; polartone
    public var polartoneInnerThreshold: Float // spiral inner radius where it wipes + reverses; polartone (0.05 default)
    public var polartoneDriftRevolutions: Float // spiral turns to cross outer→inner; polartone (8 default)
    public var polartoneStartDirection: PolartoneStartDirection // spiral first-sweep direction; polartone (.inward default)
    public var starNestZoom: Double           // resting fov/zoom base; star nest (0.78 default)
    public var starNestSpeed: Double          // resting fly-through speed base; star nest (0.18 default)
    public var starNestFormuparam: Double     // fractal fold parameter base; star nest (0.53 default)
    public var starNestTile: Double           // tiling fold size base; star nest (0.85 default)
    public var starNestStepsize: Double        // ray march step base; star nest (0.105 default)
    public var starNestBrightness: Double     // accumulation brightness base; star nest (0.00095 default)
    public var starNestDarkmatter: Double     // dark-matter absorption base; star nest (0.34 default)
    public var starNestDistfading: Double     // per-step distance fade base; star nest (0.73 default)
    public var starNestSaturation: Double     // color saturation base; star nest (0.82 default)
    public var starNestVolsteps: Int          // ray-march volume steps; star nest (18 default, cap 26)
    public var starNestIterations: Int        // fractal iterations per step; star nest (13 default, cap 16)
    public var wireframeBaseRadius: Double    // icosphere base radius; wireframe (0.50 default)
    public var wireframeDisplaceScale: Double // audio-driven outward displacement; wireframe (0.20 default)
    public var wireframeLineThickness: Double // edge half-thickness; wireframe (0.003 default)
    public var wireframeRotationSpeed: Double // Y-axis rotation rad/s; wireframe (0.5 default)
    public var wireframeTiltX: Double         // constant X tilt in radians; wireframe (0.3 default)
    public var wireframeLineOpacity: Double   // per-vertex color alpha; wireframe (1.0 default)
    public var wireframeSubdivisions: Int     // icosphere subdivision level; wireframe (2 default, clamp 0...4)
    // Wireframe placement — footprint scale + vertical offset, mirroring the
    // Heightfield extent/center knobs. Identity defaults (1, 1, 0) reproduce
    // the centered aspect-corrected sphere exactly; raise xExtent to fill a
    // wide window (the sphere becomes an ellipsoid) and push verticalCenter
    // negative to anchor it toward the bottom edge.
    public var wireframeXExtent: Double       // horizontal footprint multiplier; wireframe (1.0 default, clamp >0)
    public var wireframeYExtent: Double       // vertical footprint multiplier; wireframe (1.0 default, clamp >0)
    public var wireframeVerticalCenter: Double // additive NDC y offset; wireframe (0.0 default, clamp -1...1)
    // Independent auto-placement toggles, recomputed per frame from the live
    // aspect. v0.6.x had a single combined `wireframeFillWindow` flag; its JSON
    // key still decodes, setting both of these (see init(from:)).
    public var wireframeFillWidth: Bool       // auto-fit the width to the window; wireframe (false default)
    public var wireframeAnchorBottom: Bool    // pin the mesh to the bottom edge; wireframe (false default)
    // Outrun the Rain — each scalar is the prior hardcoded shader literal exposed as a
    // tunable. "*Base" fields are the resting value; the rest are audio-response
    // coefficients multiplying bass/lowMid/treble/energy. Defaults reproduce today's look.
    public var outrunHorizon: Double               // horizon band height (uv.y); outrun (0.80 default)
    public var outrunHorizonGlowScale: Double      // horizon glow falloff sharpness; outrun (6.0 default)
    public var outrunHorizonGlowBase: Double       // resting horizon glow into backdrop; outrun (0.6 default)
    public var outrunHorizonBassGlow: Double       // bass→horizon-glow coefficient; outrun (0.5 default)
    public var outrunLowMidBackdrop: Double        // lowMid→backdrop-level coefficient; outrun (0.1 default)
    public var outrunBackgroundBrightness: Double  // resting backdrop brightness; outrun (0.25 default)
    public var outrunBackgroundGlow: Double        // glow→backdrop-brightness coefficient; outrun (1.2 default)
    public var outrunLeanBase: Double              // resting diagonal rain lean; outrun (0.12 default)
    public var outrunLeanLowMid: Double            // lowMid→lean coefficient; outrun (0.15 default)
    public var outrunFallBase: Double              // resting fall speed; outrun (1.1 default)
    public var outrunFallBass: Double              // bass→fall-speed coefficient; outrun (1.6 default)
    public var outrunFallEnergy: Double            // energy→fall-speed coefficient; outrun (0.8 default)
    public var outrunDensity: Double               // base rain column count; outrun (70.0 default)
    public var outrunLayer0ColumnScale: Double     // layer 0 column multiplier; outrun (0.6 default)
    public var outrunLayer0FallScale: Double       // layer 0 fall multiplier; outrun (0.80 default)
    public var outrunLayer0Seed: Double            // layer 0 hash seed; outrun (0.0 default)
    public var outrunLayer0Thickness: Double       // layer 0 streak thinness; outrun (140.0 default)
    public var outrunLayer0Weight: Double          // layer 0 contribution weight; outrun (0.7 default)
    public var outrunLayer1ColumnScale: Double     // layer 1 column multiplier; outrun (1.0 default)
    public var outrunLayer1FallScale: Double       // layer 1 fall multiplier; outrun (1.00 default)
    public var outrunLayer1Seed: Double            // layer 1 hash seed; outrun (1.0 default)
    public var outrunLayer1Thickness: Double       // layer 1 streak thinness; outrun (220.0 default)
    public var outrunLayer1Weight: Double          // layer 1 contribution weight; outrun (1.0 default)
    public var outrunLayer2ColumnScale: Double     // layer 2 column multiplier; outrun (1.6 default)
    public var outrunLayer2FallScale: Double       // layer 2 fall multiplier; outrun (1.25 default)
    public var outrunLayer2Seed: Double            // layer 2 hash seed; outrun (2.0 default)
    public var outrunLayer2Thickness: Double       // layer 2 streak thinness; outrun (320.0 default)
    public var outrunLayer2Weight: Double          // layer 2 contribution weight; outrun (0.6 default)
    public var outrunSparkleColumnScale: Double    // sparkle column multiplier; outrun (2.4 default)
    public var outrunSparkleFallScale: Double      // sparkle fall multiplier; outrun (1.50 default)
    public var outrunSparkleSeed: Double           // sparkle hash seed; outrun (3.0 default)
    public var outrunSparkleThickness: Double      // sparkle streak thinness; outrun (520.0 default)
    public var outrunSparkleBase: Double           // resting sparkle weight; outrun (0.3 default)
    public var outrunSparkleTreble: Double         // treble→sparkle coefficient; outrun (1.8 default)
    public var outrunRainVerticalBase: Double      // rain density floor at top; outrun (0.35 default)
    public var outrunRainVerticalY: Double         // uv.y→rain-density coefficient; outrun (0.9 default)
    public var outrunRainColorBase: Double         // resting rain palette position; outrun (0.55 default)
    public var outrunRainColorTreble: Double       // treble→rain-color coefficient; outrun (0.4 default)
    public var outrunRainColorEnergy: Double       // energy→rain-color coefficient; outrun (0.2 default)
    public var outrunRainBrightnessBase: Double    // resting rain brightness; outrun (1.6 default)
    public var outrunRainBrightnessEnergy: Double  // energy→rain-brightness coefficient; outrun (1.5 default)
    public var outrunRainBrightnessTreble: Double  // treble→rain-brightness coefficient; outrun (1.2 default)
    public var outrunReflectionWidth: Double       // horizon reflection falloff sharpness; outrun (3.0 default)
    public var outrunReflectionBass: Double        // bass→reflection coefficient; outrun (0.6 default)
    // Plasma shader tunables (top-level; apply whole-app). Each is a prior
    // hardcoded literal in `plasma_fs`; defaults reproduce the original look.
    // Plasma reads ShaderInputs.time + energy only (no bands).
    public var plasmaCoordinateScale: Double       // uv*scale-offset zoom; plasma (2.0 default, clamp >0)
    public var plasmaCoordinateOffset: Double      // uv recentre offset; plasma (1.0 default)
    public var plasmaXFrequency: Double            // x sine spatial frequency; plasma (8.0 default)
    public var plasmaYFrequency: Double            // y sine spatial frequency; plasma (6.0 default)
    public var plasmaDiagonalFrequency: Double     // diagonal sine spatial frequency; plasma (5.0 default)
    public var plasmaXTimeScale: Double            // x sine time scale; plasma (1.0 default)
    public var plasmaYTimeScale: Double            // y sine time scale; plasma (1.3 default)
    public var plasmaDiagonalTimeScale: Double     // diagonal sine time scale; plasma (0.7 default)
    public var plasmaWaveDivisor: Double           // sine-sum normaliser; plasma (3.0 default, clamp >=0.1)
    public var plasmaContrast: Double              // post-normalise amplitude; plasma (0.5 default)
    public var plasmaBrightnessBias: Double        // palette-position midpoint; plasma (0.5 default)
    public var plasmaEnergyResponse: Double        // energy→brightness coefficient; plasma (0.3 default)
    public var plasmaClampMin: Double              // lower palette sample clamp; plasma (0.0 default)
    public var plasmaClampMax: Double              // upper palette sample clamp; plasma (1.0 default)
    public var plasmaAlpha: Double                 // output opacity; plasma (1.0 default, clamp 0...1)
    // Bumpscope shader tunables (top-level; apply whole-app). Each is a prior
    // hardcoded literal in `bumpscope_fs`; defaults reproduce the original look.
    // Bumpscope reads ShaderInputs.bands only (no time/energy).
    public var bumpscopeUvClampMin: Double         // lower UV x clamp; bumpscope (0.0 default, max>=min)
    public var bumpscopeUvClampMax: Double         // upper UV x clamp; bumpscope (1.0 default, max>=min)
    public var bumpscopeNeighborRadius: Int        // band sample offset for slope; bumpscope (1 default, clamp 0...15)
    public var bumpscopeSlopeScale: Double         // (hR-hL) slope scale; bumpscope (0.5 default)
    public var bumpscopeSurfaceNormalY: Double     // surface normal Y; bumpscope (1.0 default)
    public var bumpscopeSurfaceNormalZ: Double     // surface normal Z; bumpscope (0.0 default)
    public var bumpscopeLightX: Double             // light direction X; bumpscope (0.5 default)
    public var bumpscopeLightY: Double             // light direction Y; bumpscope (0.7 default)
    public var bumpscopeLightZ: Double             // light direction Z; bumpscope (0.5 default)
    public var bumpscopeDiffuseFloor: Double       // floor for dot(n,L); bumpscope (0.0 default, clamp 0...1)
    public var bumpscopeBandGain: Double           // band height response; bumpscope (2.0 default)
    public var bumpscopeIntensityBias: Double      // intensity bias; bumpscope (0.2 default)
    public var bumpscopeIntensityClampMin: Double  // lower palette sample clamp; bumpscope (0.0 default, max>=min)
    public var bumpscopeIntensityClampMax: Double  // upper palette sample clamp; bumpscope (1.0 default, max>=min)
    public var bumpscopeAlpha: Double              // output opacity; bumpscope (1.0 default, clamp 0...1)
    // Octave Meatballs shader tunables (top-level; apply whole-app). Each is a
    // prior hardcoded literal in `octave_meatballs_fs`; defaults reproduce the
    // original look. `*Octaves` is the structural loop bound (clamped 1...32).
    public var octaveMeatballsScale: Double               // radial pattern scale; octaveMeatballs (10.0 default)
    public var octaveMeatballsBallDivisor: Double          // balls-per-octave divisor; octaveMeatballs (10.0 default)
    public var octaveMeatballsBackgroundR: Double          // background color R; octaveMeatballs (0.005 default)
    public var octaveMeatballsBackgroundG: Double          // background color G; octaveMeatballs (0.0 default)
    public var octaveMeatballsBackgroundB: Double          // background color B; octaveMeatballs (0.01 default)
    public var octaveMeatballsOctavePhase: Double          // per-octave rotation phase; octaveMeatballs (0.1 default)
    public var octaveMeatballsShimmerOctaveScale: Double   // shimmer octave scale; octaveMeatballs (0.5 default)
    public var octaveMeatballsShimmerTimeScale: Double     // shimmer time scale; octaveMeatballs (0.1 default)
    public var octaveMeatballsLifeTimeScale: Double        // drift life time scale; octaveMeatballs (0.1 default)
    public var octaveMeatballsPulseEdge0: Double           // pulse smoothstep edge0; octaveMeatballs (0.4 default)
    public var octaveMeatballsPulseEdge1: Double           // pulse smoothstep edge1; octaveMeatballs (0.8 default)
    public var octaveMeatballsLifeOctaveScale: Double      // life per-octave scale; octaveMeatballs (0.02 default)
    public var octaveMeatballsLifeDenomBase: Double        // life denom base; octaveMeatballs (0.02 default)
    public var octaveMeatballsLifeDenomRadius: Double      // life denom radius coefficient; octaveMeatballs (0.001 default)
    public var octaveMeatballsLifeDenomScale: Double       // life denom scale; octaveMeatballs (60.0 default)
    public var octaveMeatballsDistanceFloor: Double        // metaball distance floor; octaveMeatballs (0.001 default)
    public var octaveMeatballsBallStrength: Double         // per-octave ball strength; octaveMeatballs (0.01 default)
    public var octaveMeatballsBallBase: Double             // resting ball brightness; octaveMeatballs (0.35 default)
    public var octaveMeatballsRedGlowR: Double             // red glow color R; octaveMeatballs (0.03 default)
    public var octaveMeatballsRedGlowG: Double             // red glow color G; octaveMeatballs (0.0 default)
    public var octaveMeatballsRedGlowB: Double             // red glow color B; octaveMeatballs (0.0 default)
    public var octaveMeatballsPaletteFieldGain: Double     // palette field gain; octaveMeatballs (1.5 default)
    public var octaveMeatballsPaletteGain: Double          // palette output gain; octaveMeatballs (2.0 default)
    public var octaveMeatballsBandPhase: Double            // band→phase coefficient; octaveMeatballs (2.0 default)
    public var octaveMeatballsBandBrightness: Double       // band→brightness coefficient; octaveMeatballs (1.6 default)
    public var octaveMeatballsEnergyBrightness: Double     // energy→brightness coefficient; octaveMeatballs (0.6 default)
    public var octaveMeatballsPaletteEnergy: Double        // energy→palette-level coefficient; octaveMeatballs (0.2 default)
    public var octaveMeatballsOctaves: Int                 // ring/octave count (loop bound); octaveMeatballs (24 default, clamp 1...32)
    public var lavaLampDensityFalloff: Double      // Gaussian density falloff K (shared shader+CPU); lavaLamp (8.0 default, clamp >0)
    public var lavaLampBrightnessResponse: Double  // density→brightness response (shared); lavaLamp (0.8 default)
    public var lavaLampPaletteDensityScale: Double // density→palette level (shared); lavaLamp (0.4 default)
    public var lavaLampMotionSpeed: Double         // point-motion noise time scale (CPU motion, drives both modes); lavaLamp (0.3 default)
    public var lavaLampDriftStrength: Double       // point drift strength (CPU motion, drives both modes); lavaLamp (0.3 default)
    public var lavaLampWrapBounds: Double          // point wrap bounds (CPU motion, drives both modes); lavaLamp (1.2 default, clamp >0)
    public var lavaLampShaderBeatBoost: Double     // shader beat brightness coefficient; lavaLamp (0.5 default)
    public var lavaLampCpuBeatBoost: Double        // CPU marching-squares beat coefficient; lavaLamp (0.2 default)
    public var lavaLampCpuBeatHalfLife: Double     // CPU beat decay half-life (seconds); lavaLamp (0.2 default, clamp >0)
    public var lavaLampGridSize: Int               // CPU marching-squares grid resolution; lavaLamp (64 default, clamp >=2)
    public var lavaLampBlobCount: Int              // metaball count (shared shader+CPU); lavaLamp (12 default, clamp 1...24)
    public var voronoiEdgeSharpness: Double        // shader edge sharpness K (1-exp(-K*dEdge)); voronoi (12.0 default, clamp >0)
    public var voronoiShaderBeatBoost: Double      // shader beat brightness coefficient; voronoi (0.3 default)
    public var voronoiSeedCount: Int               // seed/cell count (shared shader+CPU); voronoi (75 default, clamp 1...128)
    public var voronoiCyclePeriod: Double          // .cycle mode reshuffle period sec; voronoi (60.0 default, clamp >0)
    public var voronoiFadeDuration: Double         // fade-to-black leg duration sec; voronoi (0.5 default, clamp >0)
    public var voronoiDriftSpeed: Double           // .drift mode noise time scale; voronoi (0.15 default)
    public var voronoiDriftStrength: Double        // .drift mode per-seed drift strength; voronoi (0.05 default)
    public var voronoiSeedSpread: Double           // initial seed spread (reseed on change); voronoi (0.95 default)
    public var voronoiTintRange: Double            // per-cell tint half-range (1.0 ± range); voronoi (0.1 default)
    public var voronoiCpuBeatBoost: Double         // CPU cells beat brightness coefficient; voronoi (0.3 default)
    public var voronoiCpuBeatHalfLife: Double      // CPU cells beat decay half-life sec; voronoi (0.1 default, clamp >0)
    public var voronoiSoftBlurSigma: Double        // softCells Gaussian blur sigma (renderer); voronoi (1.5 default, clamp >0)
    // Heightfield — each scalar is a prior hardcoded literal in HeightfieldVisualizer
    // exposed as a tunable. CPU vertex-emit (read directly in makeVertices); defaults
    // reproduce today's look for BOTH wireframe and solid render modes. Clamps live at
    // the read sites so persisted/edited values can't break geometry.
    public var heightfieldGridSize: Int            // structural grid resolution / loop bound; heightfield (16 default, clamp 2...64)
    public var heightfieldTiltAngle: Double        // camera tilt radians; heightfield (.pi/7.5 default, clamp 0...1.5)
    public var heightfieldZScale: Double           // height/amplitude scale + color-level denominator; heightfield (0.25 default, clamp >=1e-3)
    public var heightfieldLineHalfThickness: Double // wireframe line half-width; heightfield (0.003 default, clamp >=0)
    public var heightfieldLightX: Double           // solid lighting direction X (normalized at read); heightfield (0.5 default)
    public var heightfieldLightY: Double           // solid lighting direction Y (normalized at read); heightfield (0.7 default)
    public var heightfieldLightZ: Double           // solid lighting direction Z (normalized at read); heightfield (0.5 default)
    public var heightfieldAmbientLight: Double     // solid lighting floor; heightfield (0.3 default, clamp 0...1)
    public var heightfieldVerticalFit: Double      // projection Y shrink; heightfield (0.92 default)
    public var heightfieldVerticalCenter: Double   // projection Y offset; heightfield (0.071 default)
    public var heightfieldBeatBoost: Double         // beat intensity -> height coeff (final mult 1+boost); heightfield (0.4 default)
    public var heightfieldBeatHalfLife: Double     // beat decay half-life sec; heightfield (0.2 default, clamp >0)
    public var heightfieldXExtent: Double          // geometry footprint X (1.0 = -1...1 mapping); heightfield (1.0 default, clamp >0)
    public var heightfieldYExtent: Double          // geometry footprint Y (1.0 = -1...1 mapping); heightfield (1.0 default, clamp >0)
    public var heightfieldOpacity: Double          // line + solid color alpha; heightfield (1.0 default, clamp 0...1)
    // Auto-placement, recomputed per frame from the live aspect (same pair of
    // toggles as Wireframe). Each overrides only its own manual knob.
    public var heightfieldFillWidth: Bool         // auto-fit the grid to the window width; heightfield (false default)
    public var heightfieldAnchorBottom: Bool      // pin the resting grid to the bottom edge; heightfield (false default)
    // Fountain — each scalar is a prior hardcoded literal in SpectrumFountainVisualizer
    // exposed as a tunable. CPU stateful particle system (read directly in makeVertices);
    // defaults reproduce today's look bit-exact. Clamps live at the read sites so
    // persisted/edited values can't break the particle state.
    public var fountainMaxParticles: Int           // persistent particle array capacity; fountain (600 default, range 50...4000, clamp 1...4000)
    public var fountainSpawnRate: Double           // P(spawn) = level*rate*dt coefficient; fountain (15 default, clamp >=0)
    public var fountainSpawnFloor: Double          // min band level required to spawn; fountain (0.15 default, clamp 0...1)
    public var fountainBaseUp: Double              // base upward launch velocity; fountain (0.55 default, clamp >=0)
    public var fountainLaunchScale: Double         // band-level -> extra launch velocity; fountain (1.6 default, clamp >=0)
    public var fountainLaunchJitter: Double        // ± fraction of vy randomized per spawn; fountain (0.2 default, clamp 0...1)
    public var fountainGravity: Double             // downward acceleration; fountain (1.4 default, clamp >=0)
    public var fountainHorizontalJitter: Double    // initial x velocity spread; fountain (0.04 default)
    public var fountainHorizontalDrag: Double      // per-frame x velocity damping; fountain (0.99 default, clamp 0...1)
    public var fountainBaseLifetime: Double        // particle lifetime seconds; fountain (2.6 default, clamp >0)
    public var fountainBaseSize: Double            // style-local base dot size; fountain (0.008 default, clamp >=0)
    public var fountainBeatLaunchBoost: Double     // beat coeff in 1+boost*intensity; fountain (0.6 default, clamp >=0)
    // Fireworks — each scalar is a prior hardcoded literal in FireworksVisualizer
    // exposed as a tunable. CPU stateful particle system (read directly in makeVertices);
    // bursts fire only on frame.beat. Defaults reproduce today's look bit-exact. Clamps
    // live at the read sites so persisted/edited values can't break the particle state.
    public var fireworksMaxParticles: Int          // persistent particle array capacity; fireworks (600 default, range 50...4000, clamp 1...4000)
    public var fireworksBurstParticlesMax: Int     // per-burst base count used as Int(max*scale); fireworks (60 default, clamp 1...400)
    public var fireworksBurstParticlesMin: Int     // per-burst floor count; fireworks (8 default, clamp 0...burstParticlesMax)
    public var fireworksBurstScaleBase: Double      // beat scale floor; fireworks (0.7 default)
    public var fireworksBurstScaleIntensity: Double // beat-intensity coeff; fireworks (0.6 default)
    public var fireworksBaseSpeed: Double           // radial speed base; fireworks (0.5 default)
    public var fireworksSpreadSpeed: Double         // random extra radial speed; fireworks (0.2 default)
    public var fireworksGravity: Double             // downward acceleration; fireworks (0.5 default, clamp >=0)
    public var fireworksDrag: Double                // per-frame velocity damping; fireworks (0.97 default, clamp 0...1)
    public var fireworksBaseLifetime: Double        // particle lifetime seconds; fireworks (1.5 default, clamp >0)
    public var fireworksLifetimeJitter: Double      // signed lifetime randomization; fireworks (0.3 default)
    public var fireworksMinLifetime: Double         // lifetime floor seconds; fireworks (0.3 default, clamp >0)
    public var fireworksBaseSize: Double            // style-local base dot size; fireworks (0.008 default, clamp >=0)
    public var fireworksBurstHalfX: Double          // burst center horizontal half-range; fireworks (0.6 default)
    public var fireworksBurstHalfY: Double          // burst center vertical half-range; fireworks (0.4 default)
    public var fireworksAngleJitter: Double         // per-particle angular offset; fireworks (0.05 default)
    // Particles — each scalar is a prior hardcoded literal in ParticleVisualizer (a
    // bass-reactive starfield). CPU stateful particle system (read directly in
    // makeVertices); defaults reproduce today's look bit-exact. Clamps live at the read
    // sites so persisted/edited values can't break the particle state.
    public var particlesMaxParticles: Int            // persistent particle array capacity; particles (200 default, range 20...4000, clamp 1...4000)
    public var particlesInitialVelocityScale: Double // initial particle x/y velocity spread; particles (0.05 default, range 0...0.5)
    public var particlesRespawnVelocityScale: Double // respawn velocity spread; particles (0.05 default, range 0...0.5)
    public var particlesBaseSize: Double             // baseline dot size particles decay toward; particles (0.012 default, clamp >=0)
    public var particlesBaseBrightness: Double       // baseline brightness particles decay toward; particles (0.45 default, clamp 0...1)
    public var particlesBrightnessJitter: Double     // ± initial brightness randomization; particles (0.3 default, clamp >=0)
    public var particlesBassThreshold: Double        // bass level required to trigger impulse; particles (0.5 default, range 0...1)
    public var particlesVelocityDamping: Double      // per-frame velocity damping; particles (0.985 default, clamp 0...1)
    public var particlesReturnLerpRate: Double       // rate brightness/size return to baseline (min(dt*rate,1)); particles (3 default, clamp >=0)
    public var particlesBeatHalfLife: Double         // beat boost decay half-life sec; particles (0.15 default, clamp >0)
    public var particlesBeatPulseScale: Double       // beat boost coeff (scale*intensity); particles (0.5 default, range 0...3)
    public var particlesBassImpulse: Double          // outward velocity impulse per bass; particles (0.25 default, range 0...2)
    public var particlesBassBrightnessGain: Double   // brightness gain per bass; particles (0.5 default, range 0...3)
    public var particlesBrightnessCap: Double        // max brightness after bass gain; particles (1.0 default, clamp >=0)
    public var particlesBassSizeGain: Double         // size growth per bass (× baseSize); particles (1.5 default, range 0...5)
    public var particlesSizeCapMultiplier: Double    // max size as multiple of baseSize; particles (3 default, clamp >=0)
    public var particlesRespawnOffscreenBound: Double // |position| past which a particle respawns; particles (1.15 default, clamp >0)
    public var particlesRespawnCenterHalfRange: Double // respawn position half-range around center; particles (0.15 default, clamp >=0)
    public var particlesLowBandPercent: Double       // fraction of low bands averaged for bass; particles (0.15 default, range 0.01...1.0)
    public var ribbonTiltSpacing: Float       // y-offset per wave in NDC; ribbon wave (0.18 default)
    public var ribbonDepthFalloff: Float      // back-wave amplitude shrink; ribbon wave (0.25 default)
    public var ribbonSampleCount: Int         // per-ribbon x resolution / vertex count; ribbon wave (256 default, clamp >=2)
    public var ribbonSmoothing: Double        // amplitude EMA responsiveness; ribbon wave (0.18 default, clamp 0...1)
    public var ribbonGain: Double             // band-mean -> amplitude coeff; ribbon wave (1.6 default, clamp >=0)
    public var ribbonHeightScale: Double      // max NDC vertical amplitude; ribbon wave (0.40 default, clamp >=0)
    public var ribbonMotionSpeed: Double      // phase/scroll speed; ribbon wave (0.6 default, clamp >=0)
    public var ribbonBaseFrequency: Double    // base wave frequency (radians across NDC); ribbon wave (4.0 default, clamp >0) — rebuilds waves
    public var ribbonFrequencySpread: Double  // randomized per-wave frequency range; ribbon wave (4.0 default, clamp >=0) — rebuilds waves
    public var ribbonStereoPanScale: Double   // stereo horizontal shift coeff; ribbon wave (0.27 default, clamp 0...1)
    public var ribbonPhaseSwing: Double       // noise phase wobble (radians); ribbon wave (Double(Float.pi*0.5) default, clamp >=0)
    public var ribbonMaxAmplitude: Double     // target amplitude saturation cap; ribbon wave (1.0 default, clamp >0)
    public var ribbonAlpha: Double            // ribbon opacity; ribbon wave (1.0 default, clamp 0...1)
    public var joyPlotSampleCount: Int        // per-row x resolution / vertex count; joy plot (64 default, clamp >=2)
    public var joyPlotRowSpacing: Double      // vertical NDC distance between row baselines; joy plot (0.4 default, clamp >=0)
    public var joyPlotRowHeight: Double       // per-row amplitude height in NDC; joy plot (0.15 default, clamp >=0)
    public var joyPlotBaselineOffset: Double  // additive vertical shift of all rows; joy plot (0.0 default = no change)
    public var joyPlotXExtent: Double         // half-width of the x mapping; joy plot (1.0 default reproduces [-1,1], clamp >0)
    public var joyPlotBeatHalfLife: Double    // beat-boost decay half-life (s); joy plot (0.15 default, clamp >0)
    public var joyPlotBeatBoost: Double       // beat intensity -> amplitude coeff; joy plot (0.5 default, clamp >=0)
    public var joyPlotBottomDim: Double       // bottom-edge color dim factor; joy plot (0.3 default, clamp 0...1)
    public var joyPlotAlpha: Double           // ribbon opacity (top+bottom); joy plot (1.0 default, clamp 0...1)
    // XY Scope — classic goniometer/Lissajous plotting L against R. CPU
    // vertex-emit (clamps live at the read sites in XYScopeVisualizer).
    public var xyScopeGain: Double            // deflection multiplier; xy scope (1.0 default, clamp >=0)
    public var xyScopeSampleCount: Int        // trace resolution; xy scope (256 default, clamp >=2)
    public var xyScopeLineHalfThickness: Double // segment half-width in NDC; xy scope (0.006 default, clamp >=0)
    public var xyScopeRotationDegrees: Double // trace rotation; xy scope (45 default = goniometer, 0 = Lissajous)
    public var xyScopeColorFloor: Double      // min palette-sample position; xy scope (0.12 default, clamp 0...1)
    public var xyScopeBeatBoost: Double       // beat deflection coeff (1+boost*intensity); xy scope (0.3 default, clamp >=0)
    public var xyScopeBeatHalfLife: Double    // beat pulse decay half-life sec; xy scope (0.15 default, clamp >0)
    public var xyScopeAlpha: Double           // trace opacity; xy scope (1.0 default, clamp 0...1)
    // Iris — port of the Vissonance "Iris" preset (MIT, see NOTICE). CPU
    // vertex-emit; clamps live at the read sites in IrisVisualizer.
    public var irisPetalCount: Int            // petals in the ring; iris (128 default, clamp 8...256 even)
    public var irisInnerRadius: Double        // ring hole radius NDC; iris (0.22 default, clamp 0...1)
    public var irisBaseLength: Double         // resting petal length; iris (0.18 default, clamp >=0)
    public var irisLengthScale: Double        // band level -> extra length; iris (0.55 default, clamp >=0)
    public var irisPetalWidth: Double         // petal half-width NDC; iris (0.012 default, clamp >=0)
    public var irisLoudnessSwell: Double      // loudness -> ring swell; iris (0.25 default, clamp >=0)
    public var irisInnerDim: Double           // base brightness fraction of tip; iris (0.35 default, clamp 0...1)
    public var irisAlpha: Double              // petal opacity; iris (1.0 default, clamp 0...1)
    // Tricentric — port of the Vissonance "Tricentric" preset (MIT, see
    // NOTICE). CPU vertex-emit; clamps live at the read sites.
    public var tricentricRingCount: Int       // rings in the tunnel; tricentric (32 default, clamp 4...64)
    public var tricentricBaseRadius: Double   // outermost ring radius NDC; tricentric (1.1 default, clamp >0)
    public var tricentricRadiusFalloff: Double // per-ring shrink factor; tricentric (0.97 default, clamp 0.5...0.99)
    public var tricentricScaleFloor: Double   // min ring scale at silence; tricentric (0.25 default, clamp 0...1)
    public var tricentricRotationSpeed: Double // loudness roll rad/s at full loudness; tricentric (1.0 default, clamp -6...6)
    public var tricentricLineThickness: Double // outline half-width NDC; tricentric (0.008 default, clamp >=0)
    public var tricentricAlpha: Double        // opacity multiplier; tricentric (1.0 default, clamp 0...1)
    // Musical Spectrum — note-aligned semitone bars (analyzer switches to the
    // .notes band mapping while active). Clamps at read sites.
    public var musicalStartOctave: Int        // first octave, C-based; musical (2 default = C2, clamp 0...5)
    public var musicalOctaveCount: Int        // octaves displayed; musical (6 default, clamp 1...8)
    public var musicalBarGap: Double          // gap fraction of bar cell; musical (0.2 default, clamp 0...0.9)
    public var musicalOctaveGap: Double       // extra octave gap in cell widths; musical (0.5 default, clamp 0...2)
    public var musicalPitchClassColoring: Bool // color by note-within-octave; musical (true default)
    public var musicalColorFloor: Double      // min brightness for quiet bars; musical (0.15 default, clamp 0...1)
    public var musicalAlpha: Double           // bar opacity; musical (1.0 default, clamp 0...1)
    public var trailPersistence: Float       // 0..0.97 motion-trail fade. 0 = off (current behavior). Affects all styles.
    public var useStereoImage: Bool          // when true, visualizers render L/R channels independently
    public var fftWindow: FFTWindow         // Hann (default), Rectangular, Hamming, or Blackman
    public var vignetteAmount: Float        // 0..1 corner darkening; 0 = off
    /// Global output dimmer applied to the final composited color of EVERY
    /// style (geometry and fullscreen shaders alike). 1.0 = full brightness
    /// (default, a pure no-op); lower values darken. Distinct from
    /// `windowOpacity`, which makes the window translucent rather than dim.
    /// Applied before the drawable's [0,1] clamp, so HDR palette highlights
    /// resolve into range instead of staying blown out.
    public var outputBrightness: Double
    public var kaleidoscopeFolds: Int       // 0 = off; 2..12 = N-fold mirror

    // Window transparency — top-level (not per-style) since they affect the window itself.
    public var windowTransparencyMode: WindowTransparencyMode  // default .perPixelAlpha
    public var windowOpacity: Float                             // default 1.0, range 0.2-1.0
    public var clickThroughEnabled: Bool                        // default false
    public var borderlessWindow: Bool                           // hide title bar + traffic-light buttons; default false
    // Window border — a thin outline at the window edge so the (still-resizable)
    // edge is visible to grab. Top-level, like the other window-chrome fields.
    public var windowBorderMode: WindowBorderMode               // off / auto (fade when idle) / always; default off
    public var windowBorderColor: RGBAColor                     // outline color (opacity carried separately); default white
    public var windowBorderOpacity: Float                       // outline opacity 0…1 (the "full" target); default 0.7
    public var windowBorderWidth: Float                         // outline thickness in points; default 1.0
    /// Modifier that turns click / scroll into visualizer actions (off disables only that layer); default shift.
    public var mouseControlModifier: MouseControlModifier

    /// True when the border feature is on in any mode (auto or always). The
    /// window chrome (full-bleed content + native shadow) keys off this, since
    /// an auto border still needs the window configured to show an edge even
    /// while it is momentarily faded out.
    public var windowBorderEnabled: Bool { windowBorderMode != .off }
    // Track overlay (now-playing title/artist) — app-wide window chrome, shared
    // across every style (was per-style on StyleProfile; it is not part of a
    // visualization). JSON keys overlayEnabled/overlayPosition/overlayOpacity.
    public var overlayEnabled: Bool                             // default false
    public var overlayPosition: OverlayCorner                   // default .topTrailing
    public var overlayOpacity: Float                            // default 0.85
    // Window placement / frame rate — app-wide (was per-style). They configure
    // the window and the display link, not a visualization.
    public var alwaysOnTop: Bool                                // default false
    public var targetFPS: Int                                   // default 60
    // When lyrics are on screen, center the centered (geometry) visualizations
    // in the clear space below the lowest lyric line instead of the whole
    // window, so the visualization does not sit behind the text. Global; the
    // offset is stable (does not drift as individual lines scroll). Default on.
    public var centerBelowLyrics: Bool
    // Position offset (clip space / NDC) for centered geometry visualizations:
    // +X right, +Y up, ±1 reaches a window edge. PER-STYLE: these forward to the
    // current style's `StyleProfile` (so each visualization remembers its own
    // placement); they are not stored here. Applied only to styles whose
    // `supportsPositionOffset` is true; shader/bottom-anchored styles ignore it.
    // Default 0,0 = window center (Wireframe's default Y is -0.07).
    public var positionOffsetX: Float {
        get { current.positionOffsetX }
        set { mutateCurrent { $0.positionOffsetX = newValue } }
    }
    public var positionOffsetY: Float {
        get { current.positionOffsetY }
        set { mutateCurrent { $0.positionOffsetY = newValue } }
    }

    // Palette auto-cycle — global (not per-style). When enabled, the active
    // palette advances through a shuffle deck every `paletteCycleInterval`
    // seconds, crossfading over `paletteCycleFadeDuration` seconds. Off by
    // default, so the feature is a pure no-op (bit-identical render) unless on.
    public var paletteCycleEnabled: Bool          // default false
    public var paletteCycleInterval: Double       // default 60 (seconds between advances)
    public var paletteCycleFadeDuration: Double   // default 1.5 (crossfade length, seconds)

    // Lyrics overlay — global (not per-style). On by default. JSON key "lyrics".
    public var lyrics: LyricsSettings

    public init(visualizerStyle: VisualizerStyle,
                profiles: [VisualizerStyle: StyleProfile],
                demoModeEnabled: Bool,
                ribbonWaveCount: Int,
                particleSize: Float,
                particleSpeed: Float,
                barGap: Float,
                oscilloscopeThickness: Float,
                polartoneRadius: Float,
                polartoneAmplitude: Float,
                polartoneColorFloor: Float,
                polartoneRotationSpeed: Float,
                polartonePointCount: Int,
                polartonePhaseOffset: Float,
                polartoneLineHalfThickness: Float,
                polartoneWaveformClamp: Float,
                polartoneRenderMode: PolartoneRenderMode,
                polartoneInnerThreshold: Float,
                polartoneDriftRevolutions: Float,
                polartoneStartDirection: PolartoneStartDirection,
                starNestZoom: Double,
                starNestSpeed: Double,
                starNestFormuparam: Double,
                starNestTile: Double,
                starNestStepsize: Double,
                starNestBrightness: Double,
                starNestDarkmatter: Double,
                starNestDistfading: Double,
                starNestSaturation: Double,
                starNestVolsteps: Int,
                starNestIterations: Int,
                wireframeBaseRadius: Double,
                wireframeDisplaceScale: Double,
                wireframeLineThickness: Double,
                wireframeRotationSpeed: Double,
                wireframeTiltX: Double,
                wireframeLineOpacity: Double,
                wireframeSubdivisions: Int,
                wireframeXExtent: Double = 1.0,
                wireframeYExtent: Double = 1.0,
                wireframeVerticalCenter: Double = 0.0,
                wireframeFillWidth: Bool = false,
                wireframeAnchorBottom: Bool = false,
                outrunHorizon: Double,
                outrunHorizonGlowScale: Double,
                outrunHorizonGlowBase: Double,
                outrunHorizonBassGlow: Double,
                outrunLowMidBackdrop: Double,
                outrunBackgroundBrightness: Double,
                outrunBackgroundGlow: Double,
                outrunLeanBase: Double,
                outrunLeanLowMid: Double,
                outrunFallBase: Double,
                outrunFallBass: Double,
                outrunFallEnergy: Double,
                outrunDensity: Double,
                outrunLayer0ColumnScale: Double,
                outrunLayer0FallScale: Double,
                outrunLayer0Seed: Double,
                outrunLayer0Thickness: Double,
                outrunLayer0Weight: Double,
                outrunLayer1ColumnScale: Double,
                outrunLayer1FallScale: Double,
                outrunLayer1Seed: Double,
                outrunLayer1Thickness: Double,
                outrunLayer1Weight: Double,
                outrunLayer2ColumnScale: Double,
                outrunLayer2FallScale: Double,
                outrunLayer2Seed: Double,
                outrunLayer2Thickness: Double,
                outrunLayer2Weight: Double,
                outrunSparkleColumnScale: Double,
                outrunSparkleFallScale: Double,
                outrunSparkleSeed: Double,
                outrunSparkleThickness: Double,
                outrunSparkleBase: Double,
                outrunSparkleTreble: Double,
                outrunRainVerticalBase: Double,
                outrunRainVerticalY: Double,
                outrunRainColorBase: Double,
                outrunRainColorTreble: Double,
                outrunRainColorEnergy: Double,
                outrunRainBrightnessBase: Double,
                outrunRainBrightnessEnergy: Double,
                outrunRainBrightnessTreble: Double,
                outrunReflectionWidth: Double,
                outrunReflectionBass: Double,
                plasmaCoordinateScale: Double,
                plasmaCoordinateOffset: Double,
                plasmaXFrequency: Double,
                plasmaYFrequency: Double,
                plasmaDiagonalFrequency: Double,
                plasmaXTimeScale: Double,
                plasmaYTimeScale: Double,
                plasmaDiagonalTimeScale: Double,
                plasmaWaveDivisor: Double,
                plasmaContrast: Double,
                plasmaBrightnessBias: Double,
                plasmaEnergyResponse: Double,
                plasmaClampMin: Double,
                plasmaClampMax: Double,
                plasmaAlpha: Double,
                bumpscopeUvClampMin: Double,
                bumpscopeUvClampMax: Double,
                bumpscopeNeighborRadius: Int,
                bumpscopeSlopeScale: Double,
                bumpscopeSurfaceNormalY: Double,
                bumpscopeSurfaceNormalZ: Double,
                bumpscopeLightX: Double,
                bumpscopeLightY: Double,
                bumpscopeLightZ: Double,
                bumpscopeDiffuseFloor: Double,
                bumpscopeBandGain: Double,
                bumpscopeIntensityBias: Double,
                bumpscopeIntensityClampMin: Double,
                bumpscopeIntensityClampMax: Double,
                bumpscopeAlpha: Double,
                octaveMeatballsScale: Double,
                octaveMeatballsBallDivisor: Double,
                octaveMeatballsBackgroundR: Double,
                octaveMeatballsBackgroundG: Double,
                octaveMeatballsBackgroundB: Double,
                octaveMeatballsOctavePhase: Double,
                octaveMeatballsShimmerOctaveScale: Double,
                octaveMeatballsShimmerTimeScale: Double,
                octaveMeatballsLifeTimeScale: Double,
                octaveMeatballsPulseEdge0: Double,
                octaveMeatballsPulseEdge1: Double,
                octaveMeatballsLifeOctaveScale: Double,
                octaveMeatballsLifeDenomBase: Double,
                octaveMeatballsLifeDenomRadius: Double,
                octaveMeatballsLifeDenomScale: Double,
                octaveMeatballsDistanceFloor: Double,
                octaveMeatballsBallStrength: Double,
                octaveMeatballsBallBase: Double,
                octaveMeatballsRedGlowR: Double,
                octaveMeatballsRedGlowG: Double,
                octaveMeatballsRedGlowB: Double,
                octaveMeatballsPaletteFieldGain: Double,
                octaveMeatballsPaletteGain: Double,
                octaveMeatballsBandPhase: Double,
                octaveMeatballsBandBrightness: Double,
                octaveMeatballsEnergyBrightness: Double,
                octaveMeatballsPaletteEnergy: Double,
                octaveMeatballsOctaves: Int,
                lavaLampDensityFalloff: Double,
                lavaLampBrightnessResponse: Double,
                lavaLampPaletteDensityScale: Double,
                lavaLampMotionSpeed: Double,
                lavaLampDriftStrength: Double,
                lavaLampWrapBounds: Double,
                lavaLampShaderBeatBoost: Double,
                lavaLampCpuBeatBoost: Double,
                lavaLampCpuBeatHalfLife: Double,
                lavaLampGridSize: Int,
                lavaLampBlobCount: Int,
                voronoiEdgeSharpness: Double,
                voronoiShaderBeatBoost: Double,
                voronoiSeedCount: Int,
                voronoiCyclePeriod: Double,
                voronoiFadeDuration: Double,
                voronoiDriftSpeed: Double,
                voronoiDriftStrength: Double,
                voronoiSeedSpread: Double,
                voronoiTintRange: Double,
                voronoiCpuBeatBoost: Double,
                voronoiCpuBeatHalfLife: Double,
                voronoiSoftBlurSigma: Double,
                heightfieldGridSize: Int,
                heightfieldTiltAngle: Double,
                heightfieldZScale: Double,
                heightfieldLineHalfThickness: Double,
                heightfieldLightX: Double,
                heightfieldLightY: Double,
                heightfieldLightZ: Double,
                heightfieldAmbientLight: Double,
                heightfieldVerticalFit: Double,
                heightfieldVerticalCenter: Double,
                heightfieldBeatBoost: Double,
                heightfieldBeatHalfLife: Double,
                heightfieldXExtent: Double,
                heightfieldYExtent: Double,
                heightfieldOpacity: Double,
                heightfieldFillWidth: Bool = false,
                heightfieldAnchorBottom: Bool = false,
                fountainMaxParticles: Int,
                fountainSpawnRate: Double,
                fountainSpawnFloor: Double,
                fountainBaseUp: Double,
                fountainLaunchScale: Double,
                fountainLaunchJitter: Double,
                fountainGravity: Double,
                fountainHorizontalJitter: Double,
                fountainHorizontalDrag: Double,
                fountainBaseLifetime: Double,
                fountainBaseSize: Double,
                fountainBeatLaunchBoost: Double,
                fireworksMaxParticles: Int,
                fireworksBurstParticlesMax: Int,
                fireworksBurstParticlesMin: Int,
                fireworksBurstScaleBase: Double,
                fireworksBurstScaleIntensity: Double,
                fireworksBaseSpeed: Double,
                fireworksSpreadSpeed: Double,
                fireworksGravity: Double,
                fireworksDrag: Double,
                fireworksBaseLifetime: Double,
                fireworksLifetimeJitter: Double,
                fireworksMinLifetime: Double,
                fireworksBaseSize: Double,
                fireworksBurstHalfX: Double,
                fireworksBurstHalfY: Double,
                fireworksAngleJitter: Double,
                particlesMaxParticles: Int,
                particlesInitialVelocityScale: Double,
                particlesRespawnVelocityScale: Double,
                particlesBaseSize: Double,
                particlesBaseBrightness: Double,
                particlesBrightnessJitter: Double,
                particlesBassThreshold: Double,
                particlesVelocityDamping: Double,
                particlesReturnLerpRate: Double,
                particlesBeatHalfLife: Double,
                particlesBeatPulseScale: Double,
                particlesBassImpulse: Double,
                particlesBassBrightnessGain: Double,
                particlesBrightnessCap: Double,
                particlesBassSizeGain: Double,
                particlesSizeCapMultiplier: Double,
                particlesRespawnOffscreenBound: Double,
                particlesRespawnCenterHalfRange: Double,
                particlesLowBandPercent: Double,
                ribbonTiltSpacing: Float,
                ribbonDepthFalloff: Float,
                ribbonSampleCount: Int,
                ribbonSmoothing: Double,
                ribbonGain: Double,
                ribbonHeightScale: Double,
                ribbonMotionSpeed: Double,
                ribbonBaseFrequency: Double,
                ribbonFrequencySpread: Double,
                ribbonStereoPanScale: Double,
                ribbonPhaseSwing: Double,
                ribbonMaxAmplitude: Double,
                ribbonAlpha: Double,
                joyPlotSampleCount: Int,
                joyPlotRowSpacing: Double,
                joyPlotRowHeight: Double,
                joyPlotBaselineOffset: Double,
                joyPlotXExtent: Double,
                joyPlotBeatHalfLife: Double,
                joyPlotBeatBoost: Double,
                joyPlotBottomDim: Double,
                joyPlotAlpha: Double,
                xyScopeGain: Double = 1.0,
                xyScopeSampleCount: Int = 256,
                xyScopeLineHalfThickness: Double = 0.006,
                xyScopeRotationDegrees: Double = 45,
                xyScopeColorFloor: Double = 0.12,
                xyScopeBeatBoost: Double = 0.3,
                xyScopeBeatHalfLife: Double = 0.15,
                xyScopeAlpha: Double = 1.0,
                irisPetalCount: Int = 128,
                irisInnerRadius: Double = 0.22,
                irisBaseLength: Double = 0.18,
                irisLengthScale: Double = 0.55,
                irisPetalWidth: Double = 0.012,
                irisLoudnessSwell: Double = 0.25,
                irisInnerDim: Double = 0.35,
                irisAlpha: Double = 1.0,
                tricentricRingCount: Int = 32,
                tricentricBaseRadius: Double = 1.1,
                tricentricRadiusFalloff: Double = 0.97,
                tricentricScaleFloor: Double = 0.25,
                tricentricRotationSpeed: Double = 1.0,
                tricentricLineThickness: Double = 0.008,
                tricentricAlpha: Double = 1.0,
                musicalStartOctave: Int = 2,
                musicalOctaveCount: Int = 6,
                musicalBarGap: Double = 0.2,
                musicalOctaveGap: Double = 0.5,
                musicalPitchClassColoring: Bool = true,
                musicalColorFloor: Double = 0.15,
                musicalAlpha: Double = 1.0,
                trailPersistence: Float,
                useStereoImage: Bool,
                fftWindow: FFTWindow,
                vignetteAmount: Float,
                outputBrightness: Double = 1.0,
                kaleidoscopeFolds: Int,
                windowTransparencyMode: WindowTransparencyMode,
                windowOpacity: Float,
                clickThroughEnabled: Bool,
                borderlessWindow: Bool,
                windowBorderMode: WindowBorderMode = .off,
                windowBorderColor: RGBAColor = RGBAColor(r: 1, g: 1, b: 1, a: 1),
                windowBorderOpacity: Float = 0.7,
                windowBorderWidth: Float = 1.0,
                mouseControlModifier: MouseControlModifier = .shift,
                centerBelowLyrics: Bool = true,
                overlayEnabled: Bool = false,
                overlayPosition: OverlayCorner = .topTrailing,
                overlayOpacity: Float = 0.85,
                alwaysOnTop: Bool = false,
                targetFPS: Int = 60,
                paletteCycleEnabled: Bool,
                paletteCycleInterval: Double,
                paletteCycleFadeDuration: Double,
                lyrics: LyricsSettings = .defaults) {
        self.visualizerStyle = visualizerStyle
        self.profiles = profiles
        self.demoModeEnabled = demoModeEnabled
        self.ribbonWaveCount = ribbonWaveCount
        self.particleSize = particleSize
        self.particleSpeed = particleSpeed
        self.barGap = barGap
        self.oscilloscopeThickness = oscilloscopeThickness
        self.polartoneRadius = polartoneRadius
        self.polartoneAmplitude = polartoneAmplitude
        self.polartoneColorFloor = polartoneColorFloor
        self.polartoneRotationSpeed = polartoneRotationSpeed
        self.polartonePointCount = polartonePointCount
        self.polartonePhaseOffset = polartonePhaseOffset
        self.polartoneLineHalfThickness = polartoneLineHalfThickness
        self.polartoneWaveformClamp = polartoneWaveformClamp
        self.polartoneRenderMode = polartoneRenderMode
        self.polartoneInnerThreshold = polartoneInnerThreshold
        self.polartoneDriftRevolutions = polartoneDriftRevolutions
        self.polartoneStartDirection = polartoneStartDirection
        self.starNestZoom = starNestZoom
        self.starNestSpeed = starNestSpeed
        self.starNestFormuparam = starNestFormuparam
        self.starNestTile = starNestTile
        self.starNestStepsize = starNestStepsize
        self.starNestBrightness = starNestBrightness
        self.starNestDarkmatter = starNestDarkmatter
        self.starNestDistfading = starNestDistfading
        self.starNestSaturation = starNestSaturation
        self.starNestVolsteps = starNestVolsteps
        self.starNestIterations = starNestIterations
        self.wireframeBaseRadius = wireframeBaseRadius
        self.wireframeDisplaceScale = wireframeDisplaceScale
        self.wireframeLineThickness = wireframeLineThickness
        self.wireframeRotationSpeed = wireframeRotationSpeed
        self.wireframeTiltX = wireframeTiltX
        self.wireframeLineOpacity = wireframeLineOpacity
        self.wireframeSubdivisions = wireframeSubdivisions
        self.wireframeXExtent = wireframeXExtent
        self.wireframeYExtent = wireframeYExtent
        self.wireframeVerticalCenter = wireframeVerticalCenter
        self.wireframeFillWidth = wireframeFillWidth
        self.wireframeAnchorBottom = wireframeAnchorBottom
        self.outrunHorizon = outrunHorizon
        self.outrunHorizonGlowScale = outrunHorizonGlowScale
        self.outrunHorizonGlowBase = outrunHorizonGlowBase
        self.outrunHorizonBassGlow = outrunHorizonBassGlow
        self.outrunLowMidBackdrop = outrunLowMidBackdrop
        self.outrunBackgroundBrightness = outrunBackgroundBrightness
        self.outrunBackgroundGlow = outrunBackgroundGlow
        self.outrunLeanBase = outrunLeanBase
        self.outrunLeanLowMid = outrunLeanLowMid
        self.outrunFallBase = outrunFallBase
        self.outrunFallBass = outrunFallBass
        self.outrunFallEnergy = outrunFallEnergy
        self.outrunDensity = outrunDensity
        self.outrunLayer0ColumnScale = outrunLayer0ColumnScale
        self.outrunLayer0FallScale = outrunLayer0FallScale
        self.outrunLayer0Seed = outrunLayer0Seed
        self.outrunLayer0Thickness = outrunLayer0Thickness
        self.outrunLayer0Weight = outrunLayer0Weight
        self.outrunLayer1ColumnScale = outrunLayer1ColumnScale
        self.outrunLayer1FallScale = outrunLayer1FallScale
        self.outrunLayer1Seed = outrunLayer1Seed
        self.outrunLayer1Thickness = outrunLayer1Thickness
        self.outrunLayer1Weight = outrunLayer1Weight
        self.outrunLayer2ColumnScale = outrunLayer2ColumnScale
        self.outrunLayer2FallScale = outrunLayer2FallScale
        self.outrunLayer2Seed = outrunLayer2Seed
        self.outrunLayer2Thickness = outrunLayer2Thickness
        self.outrunLayer2Weight = outrunLayer2Weight
        self.outrunSparkleColumnScale = outrunSparkleColumnScale
        self.outrunSparkleFallScale = outrunSparkleFallScale
        self.outrunSparkleSeed = outrunSparkleSeed
        self.outrunSparkleThickness = outrunSparkleThickness
        self.outrunSparkleBase = outrunSparkleBase
        self.outrunSparkleTreble = outrunSparkleTreble
        self.outrunRainVerticalBase = outrunRainVerticalBase
        self.outrunRainVerticalY = outrunRainVerticalY
        self.outrunRainColorBase = outrunRainColorBase
        self.outrunRainColorTreble = outrunRainColorTreble
        self.outrunRainColorEnergy = outrunRainColorEnergy
        self.outrunRainBrightnessBase = outrunRainBrightnessBase
        self.outrunRainBrightnessEnergy = outrunRainBrightnessEnergy
        self.outrunRainBrightnessTreble = outrunRainBrightnessTreble
        self.outrunReflectionWidth = outrunReflectionWidth
        self.outrunReflectionBass = outrunReflectionBass
        self.plasmaCoordinateScale = plasmaCoordinateScale
        self.plasmaCoordinateOffset = plasmaCoordinateOffset
        self.plasmaXFrequency = plasmaXFrequency
        self.plasmaYFrequency = plasmaYFrequency
        self.plasmaDiagonalFrequency = plasmaDiagonalFrequency
        self.plasmaXTimeScale = plasmaXTimeScale
        self.plasmaYTimeScale = plasmaYTimeScale
        self.plasmaDiagonalTimeScale = plasmaDiagonalTimeScale
        self.plasmaWaveDivisor = plasmaWaveDivisor
        self.plasmaContrast = plasmaContrast
        self.plasmaBrightnessBias = plasmaBrightnessBias
        self.plasmaEnergyResponse = plasmaEnergyResponse
        self.plasmaClampMin = plasmaClampMin
        self.plasmaClampMax = plasmaClampMax
        self.plasmaAlpha = plasmaAlpha
        self.bumpscopeUvClampMin = bumpscopeUvClampMin
        self.bumpscopeUvClampMax = bumpscopeUvClampMax
        self.bumpscopeNeighborRadius = bumpscopeNeighborRadius
        self.bumpscopeSlopeScale = bumpscopeSlopeScale
        self.bumpscopeSurfaceNormalY = bumpscopeSurfaceNormalY
        self.bumpscopeSurfaceNormalZ = bumpscopeSurfaceNormalZ
        self.bumpscopeLightX = bumpscopeLightX
        self.bumpscopeLightY = bumpscopeLightY
        self.bumpscopeLightZ = bumpscopeLightZ
        self.bumpscopeDiffuseFloor = bumpscopeDiffuseFloor
        self.bumpscopeBandGain = bumpscopeBandGain
        self.bumpscopeIntensityBias = bumpscopeIntensityBias
        self.bumpscopeIntensityClampMin = bumpscopeIntensityClampMin
        self.bumpscopeIntensityClampMax = bumpscopeIntensityClampMax
        self.bumpscopeAlpha = bumpscopeAlpha
        self.octaveMeatballsScale = octaveMeatballsScale
        self.octaveMeatballsBallDivisor = octaveMeatballsBallDivisor
        self.octaveMeatballsBackgroundR = octaveMeatballsBackgroundR
        self.octaveMeatballsBackgroundG = octaveMeatballsBackgroundG
        self.octaveMeatballsBackgroundB = octaveMeatballsBackgroundB
        self.octaveMeatballsOctavePhase = octaveMeatballsOctavePhase
        self.octaveMeatballsShimmerOctaveScale = octaveMeatballsShimmerOctaveScale
        self.octaveMeatballsShimmerTimeScale = octaveMeatballsShimmerTimeScale
        self.octaveMeatballsLifeTimeScale = octaveMeatballsLifeTimeScale
        self.octaveMeatballsPulseEdge0 = octaveMeatballsPulseEdge0
        self.octaveMeatballsPulseEdge1 = octaveMeatballsPulseEdge1
        self.octaveMeatballsLifeOctaveScale = octaveMeatballsLifeOctaveScale
        self.octaveMeatballsLifeDenomBase = octaveMeatballsLifeDenomBase
        self.octaveMeatballsLifeDenomRadius = octaveMeatballsLifeDenomRadius
        self.octaveMeatballsLifeDenomScale = octaveMeatballsLifeDenomScale
        self.octaveMeatballsDistanceFloor = octaveMeatballsDistanceFloor
        self.octaveMeatballsBallStrength = octaveMeatballsBallStrength
        self.octaveMeatballsBallBase = octaveMeatballsBallBase
        self.octaveMeatballsRedGlowR = octaveMeatballsRedGlowR
        self.octaveMeatballsRedGlowG = octaveMeatballsRedGlowG
        self.octaveMeatballsRedGlowB = octaveMeatballsRedGlowB
        self.octaveMeatballsPaletteFieldGain = octaveMeatballsPaletteFieldGain
        self.octaveMeatballsPaletteGain = octaveMeatballsPaletteGain
        self.octaveMeatballsBandPhase = octaveMeatballsBandPhase
        self.octaveMeatballsBandBrightness = octaveMeatballsBandBrightness
        self.octaveMeatballsEnergyBrightness = octaveMeatballsEnergyBrightness
        self.octaveMeatballsPaletteEnergy = octaveMeatballsPaletteEnergy
        self.octaveMeatballsOctaves = octaveMeatballsOctaves
        self.lavaLampDensityFalloff = lavaLampDensityFalloff
        self.lavaLampBrightnessResponse = lavaLampBrightnessResponse
        self.lavaLampPaletteDensityScale = lavaLampPaletteDensityScale
        self.lavaLampMotionSpeed = lavaLampMotionSpeed
        self.lavaLampDriftStrength = lavaLampDriftStrength
        self.lavaLampWrapBounds = lavaLampWrapBounds
        self.lavaLampShaderBeatBoost = lavaLampShaderBeatBoost
        self.lavaLampCpuBeatBoost = lavaLampCpuBeatBoost
        self.lavaLampCpuBeatHalfLife = lavaLampCpuBeatHalfLife
        self.lavaLampGridSize = lavaLampGridSize
        self.lavaLampBlobCount = lavaLampBlobCount
        self.voronoiEdgeSharpness = voronoiEdgeSharpness
        self.voronoiShaderBeatBoost = voronoiShaderBeatBoost
        self.voronoiSeedCount = voronoiSeedCount
        self.voronoiCyclePeriod = voronoiCyclePeriod
        self.voronoiFadeDuration = voronoiFadeDuration
        self.voronoiDriftSpeed = voronoiDriftSpeed
        self.voronoiDriftStrength = voronoiDriftStrength
        self.voronoiSeedSpread = voronoiSeedSpread
        self.voronoiTintRange = voronoiTintRange
        self.voronoiCpuBeatBoost = voronoiCpuBeatBoost
        self.voronoiCpuBeatHalfLife = voronoiCpuBeatHalfLife
        self.voronoiSoftBlurSigma = voronoiSoftBlurSigma
        self.heightfieldGridSize = heightfieldGridSize
        self.heightfieldTiltAngle = heightfieldTiltAngle
        self.heightfieldZScale = heightfieldZScale
        self.heightfieldLineHalfThickness = heightfieldLineHalfThickness
        self.heightfieldLightX = heightfieldLightX
        self.heightfieldLightY = heightfieldLightY
        self.heightfieldLightZ = heightfieldLightZ
        self.heightfieldAmbientLight = heightfieldAmbientLight
        self.heightfieldVerticalFit = heightfieldVerticalFit
        self.heightfieldVerticalCenter = heightfieldVerticalCenter
        self.heightfieldBeatBoost = heightfieldBeatBoost
        self.heightfieldBeatHalfLife = heightfieldBeatHalfLife
        self.heightfieldXExtent = heightfieldXExtent
        self.heightfieldYExtent = heightfieldYExtent
        self.heightfieldOpacity = heightfieldOpacity
        self.heightfieldFillWidth = heightfieldFillWidth
        self.heightfieldAnchorBottom = heightfieldAnchorBottom
        self.fountainMaxParticles = fountainMaxParticles
        self.fountainSpawnRate = fountainSpawnRate
        self.fountainSpawnFloor = fountainSpawnFloor
        self.fountainBaseUp = fountainBaseUp
        self.fountainLaunchScale = fountainLaunchScale
        self.fountainLaunchJitter = fountainLaunchJitter
        self.fountainGravity = fountainGravity
        self.fountainHorizontalJitter = fountainHorizontalJitter
        self.fountainHorizontalDrag = fountainHorizontalDrag
        self.fountainBaseLifetime = fountainBaseLifetime
        self.fountainBaseSize = fountainBaseSize
        self.fountainBeatLaunchBoost = fountainBeatLaunchBoost
        self.fireworksMaxParticles = fireworksMaxParticles
        self.fireworksBurstParticlesMax = fireworksBurstParticlesMax
        self.fireworksBurstParticlesMin = fireworksBurstParticlesMin
        self.fireworksBurstScaleBase = fireworksBurstScaleBase
        self.fireworksBurstScaleIntensity = fireworksBurstScaleIntensity
        self.fireworksBaseSpeed = fireworksBaseSpeed
        self.fireworksSpreadSpeed = fireworksSpreadSpeed
        self.fireworksGravity = fireworksGravity
        self.fireworksDrag = fireworksDrag
        self.fireworksBaseLifetime = fireworksBaseLifetime
        self.fireworksLifetimeJitter = fireworksLifetimeJitter
        self.fireworksMinLifetime = fireworksMinLifetime
        self.fireworksBaseSize = fireworksBaseSize
        self.fireworksBurstHalfX = fireworksBurstHalfX
        self.fireworksBurstHalfY = fireworksBurstHalfY
        self.fireworksAngleJitter = fireworksAngleJitter
        self.particlesMaxParticles = particlesMaxParticles
        self.particlesInitialVelocityScale = particlesInitialVelocityScale
        self.particlesRespawnVelocityScale = particlesRespawnVelocityScale
        self.particlesBaseSize = particlesBaseSize
        self.particlesBaseBrightness = particlesBaseBrightness
        self.particlesBrightnessJitter = particlesBrightnessJitter
        self.particlesBassThreshold = particlesBassThreshold
        self.particlesVelocityDamping = particlesVelocityDamping
        self.particlesReturnLerpRate = particlesReturnLerpRate
        self.particlesBeatHalfLife = particlesBeatHalfLife
        self.particlesBeatPulseScale = particlesBeatPulseScale
        self.particlesBassImpulse = particlesBassImpulse
        self.particlesBassBrightnessGain = particlesBassBrightnessGain
        self.particlesBrightnessCap = particlesBrightnessCap
        self.particlesBassSizeGain = particlesBassSizeGain
        self.particlesSizeCapMultiplier = particlesSizeCapMultiplier
        self.particlesRespawnOffscreenBound = particlesRespawnOffscreenBound
        self.particlesRespawnCenterHalfRange = particlesRespawnCenterHalfRange
        self.particlesLowBandPercent = particlesLowBandPercent
        self.ribbonTiltSpacing = ribbonTiltSpacing
        self.ribbonDepthFalloff = ribbonDepthFalloff
        self.ribbonSampleCount = ribbonSampleCount
        self.ribbonSmoothing = ribbonSmoothing
        self.ribbonGain = ribbonGain
        self.ribbonHeightScale = ribbonHeightScale
        self.ribbonMotionSpeed = ribbonMotionSpeed
        self.ribbonBaseFrequency = ribbonBaseFrequency
        self.ribbonFrequencySpread = ribbonFrequencySpread
        self.ribbonStereoPanScale = ribbonStereoPanScale
        self.ribbonPhaseSwing = ribbonPhaseSwing
        self.ribbonMaxAmplitude = ribbonMaxAmplitude
        self.ribbonAlpha = ribbonAlpha
        self.joyPlotSampleCount = joyPlotSampleCount
        self.joyPlotRowSpacing = joyPlotRowSpacing
        self.joyPlotRowHeight = joyPlotRowHeight
        self.joyPlotBaselineOffset = joyPlotBaselineOffset
        self.joyPlotXExtent = joyPlotXExtent
        self.joyPlotBeatHalfLife = joyPlotBeatHalfLife
        self.joyPlotBeatBoost = joyPlotBeatBoost
        self.joyPlotBottomDim = joyPlotBottomDim
        self.joyPlotAlpha = joyPlotAlpha
        self.xyScopeGain = xyScopeGain
        self.xyScopeSampleCount = xyScopeSampleCount
        self.xyScopeLineHalfThickness = xyScopeLineHalfThickness
        self.xyScopeRotationDegrees = xyScopeRotationDegrees
        self.xyScopeColorFloor = xyScopeColorFloor
        self.xyScopeBeatBoost = xyScopeBeatBoost
        self.xyScopeBeatHalfLife = xyScopeBeatHalfLife
        self.xyScopeAlpha = xyScopeAlpha
        self.irisPetalCount = irisPetalCount
        self.irisInnerRadius = irisInnerRadius
        self.irisBaseLength = irisBaseLength
        self.irisLengthScale = irisLengthScale
        self.irisPetalWidth = irisPetalWidth
        self.irisLoudnessSwell = irisLoudnessSwell
        self.irisInnerDim = irisInnerDim
        self.irisAlpha = irisAlpha
        self.tricentricRingCount = tricentricRingCount
        self.tricentricBaseRadius = tricentricBaseRadius
        self.tricentricRadiusFalloff = tricentricRadiusFalloff
        self.tricentricScaleFloor = tricentricScaleFloor
        self.tricentricRotationSpeed = tricentricRotationSpeed
        self.tricentricLineThickness = tricentricLineThickness
        self.tricentricAlpha = tricentricAlpha
        self.musicalStartOctave = musicalStartOctave
        self.musicalOctaveCount = musicalOctaveCount
        self.musicalBarGap = musicalBarGap
        self.musicalOctaveGap = musicalOctaveGap
        self.musicalPitchClassColoring = musicalPitchClassColoring
        self.musicalColorFloor = musicalColorFloor
        self.musicalAlpha = musicalAlpha
        self.trailPersistence = trailPersistence
        self.useStereoImage = useStereoImage
        self.fftWindow = fftWindow
        self.vignetteAmount = vignetteAmount
        self.outputBrightness = outputBrightness
        self.kaleidoscopeFolds = kaleidoscopeFolds
        self.windowTransparencyMode = windowTransparencyMode
        self.windowOpacity = windowOpacity
        self.clickThroughEnabled = clickThroughEnabled
        self.borderlessWindow = borderlessWindow
        self.windowBorderMode = windowBorderMode
        self.windowBorderColor = windowBorderColor
        self.windowBorderOpacity = windowBorderOpacity
        self.windowBorderWidth = windowBorderWidth
        self.mouseControlModifier = mouseControlModifier
        self.centerBelowLyrics = centerBelowLyrics
        self.overlayEnabled = overlayEnabled
        self.overlayPosition = overlayPosition
        self.overlayOpacity = overlayOpacity
        self.alwaysOnTop = alwaysOnTop
        self.targetFPS = targetFPS
        self.paletteCycleEnabled = paletteCycleEnabled
        self.paletteCycleInterval = paletteCycleInterval
        self.paletteCycleFadeDuration = paletteCycleFadeDuration
        self.lyrics = lyrics
    }

    /// Returns the profile for the current style (falls back to defaults).
    public var current: StyleProfile {
        profiles[visualizerStyle] ?? .defaults(for: visualizerStyle)
    }

    /// In-place mutation of the current style's profile.
    public mutating func mutateCurrent(_ body: (inout StyleProfile) -> Void) {
        var p = profiles[visualizerStyle] ?? .defaults(for: visualizerStyle)
        body(&p)
        profiles[visualizerStyle] = p
    }

    // MARK: - Per-style enable/disable

    /// Whether `style` is available (shown in pickers, visited by cycling).
    /// A style with no persisted profile counts as enabled.
    public func isStyleEnabled(_ style: VisualizerStyle) -> Bool {
        guard style.isAvailable else { return false }   // unavailable on this OS = disabled (profile untouched)
        return profiles[style]?.enabled ?? true
    }

    /// Set the enabled flag on `style`'s profile without touching its other
    /// fields. No last-style guard here — the UI prevents disabling the last
    /// enabled style, and resolution (`effectiveStyle`, `enabledStyles`) falls
    /// back to `.bars` even if hand-edited JSON disables everything.
    public mutating func setStyleEnabled(_ style: VisualizerStyle, _ enabled: Bool) {
        var p = profiles[style] ?? .defaults(for: style)
        p.enabled = enabled
        profiles[style] = p
    }

    /// The enabled styles in `VisualizerStyle.allCases` order. Never empty:
    /// if every style is disabled, resolves to `[.bars]`.
    public var enabledStyles: [VisualizerStyle] {
        let enabled = VisualizerStyle.allCases.filter { isStyleEnabled($0) }
        return enabled.isEmpty ? [.bars] : enabled
    }

    /// The style to actually render: the current style when enabled, else the
    /// first enabled style in case order (`.bars` when everything is disabled).
    public var effectiveStyle: VisualizerStyle {
        isStyleEnabled(visualizerStyle) ? visualizerStyle : enabledStyles[0]
    }

    /// The next enabled style after `style` in case order, wrapping around and
    /// skipping disabled styles. Returns `style` itself when it is the only
    /// enabled style, `.bars` when none are enabled.
    public func nextEnabledStyle(after style: VisualizerStyle) -> VisualizerStyle {
        steppedEnabledStyle(from: style, by: 1)
    }

    /// The previous enabled style before `style`; see `nextEnabledStyle(after:)`.
    public func previousEnabledStyle(before style: VisualizerStyle) -> VisualizerStyle {
        steppedEnabledStyle(from: style, by: -1)
    }

    private func steppedEnabledStyle(from style: VisualizerStyle, by delta: Int) -> VisualizerStyle {
        let all = VisualizerStyle.allCases
        guard let start = all.firstIndex(of: style) else { return effectiveStyle }
        let count = all.count
        for step in 1...count {
            let candidate = all[((start + delta * step) % count + count) % count]
            if isStyleEnabled(candidate) { return candidate }
        }
        return .bars
    }

    /// A random enabled style other than `current`, backing the Random Style
    /// hotkey. Returns `current` only when it is the sole enabled style. The RNG
    /// is taken by reference so callers can inject a deterministic generator.
    public func randomEnabledStyle<R: RandomNumberGenerator>(
        excluding current: VisualizerStyle, using rng: inout R
    ) -> VisualizerStyle {
        let pool = enabledStyles.filter { $0 != current }
        return pool.randomElement(using: &rng) ?? current
    }

    /// A random preset palette name other than `current`, backing the Random
    /// Palette hotkey. Returns `current` when fewer than two presets exist.
    public func randomPaletteName<R: RandomNumberGenerator>(
        excluding current: String, using rng: inout R
    ) -> String {
        let pool = ColorPalette.orderedPresetNames.filter { $0 != current }
        return pool.randomElement(using: &rng) ?? current
    }

    /// Resets the active style back to defaults: its `StyleProfile` plus the
    /// top-level tunables that are EXCLUSIVE to this style. Shared top-level
    /// fields (`barGap`, `oscilloscopeThickness`, `particleSize`/`particleSpeed`)
    /// are deliberately left alone — they back more than one style, so resetting
    /// them here would alter a style other than the active one. Other styles'
    /// profiles and fields are never touched.
    public mutating func resetCurrentStyle() {
        resetCurrentStyle(to: .defaults)
    }

    /// Same scope as `resetCurrentStyle()`, but restores from `base` (a saved
    /// "my defaults" snapshot, or `.defaults` for factory). The style's profile
    /// comes from `base.profiles[style]` (falling back to the factory profile
    /// when `base` lacks it); the style-exclusive top-level fields come from `base`.
    public mutating func resetCurrentStyle(to base: VisualizerSettings) {
        let d = base
        let style = visualizerStyle
        let profile = base.profiles[style] ?? .defaults(for: style)
        mutateCurrent { $0 = profile }
        switch visualizerStyle {
        case .ribbonWave:
            ribbonWaveCount = d.ribbonWaveCount
            ribbonTiltSpacing = d.ribbonTiltSpacing
            ribbonDepthFalloff = d.ribbonDepthFalloff
            ribbonSampleCount = d.ribbonSampleCount
            ribbonSmoothing = d.ribbonSmoothing
            ribbonGain = d.ribbonGain
            ribbonHeightScale = d.ribbonHeightScale
            ribbonMotionSpeed = d.ribbonMotionSpeed
            ribbonBaseFrequency = d.ribbonBaseFrequency
            ribbonFrequencySpread = d.ribbonFrequencySpread
            ribbonStereoPanScale = d.ribbonStereoPanScale
            ribbonPhaseSwing = d.ribbonPhaseSwing
            ribbonMaxAmplitude = d.ribbonMaxAmplitude
            ribbonAlpha = d.ribbonAlpha
        case .joyPlot:
            joyPlotSampleCount = d.joyPlotSampleCount
            joyPlotRowSpacing = d.joyPlotRowSpacing
            joyPlotRowHeight = d.joyPlotRowHeight
            joyPlotBaselineOffset = d.joyPlotBaselineOffset
            joyPlotXExtent = d.joyPlotXExtent
            joyPlotBeatHalfLife = d.joyPlotBeatHalfLife
            joyPlotBeatBoost = d.joyPlotBeatBoost
            joyPlotBottomDim = d.joyPlotBottomDim
            joyPlotAlpha = d.joyPlotAlpha
        case .polartone:
            polartoneRadius = d.polartoneRadius
            polartoneAmplitude = d.polartoneAmplitude
            polartoneColorFloor = d.polartoneColorFloor
            polartoneRotationSpeed = d.polartoneRotationSpeed
            polartonePointCount = d.polartonePointCount
            polartonePhaseOffset = d.polartonePhaseOffset
            polartoneLineHalfThickness = d.polartoneLineHalfThickness
            polartoneWaveformClamp = d.polartoneWaveformClamp
            polartoneRenderMode = d.polartoneRenderMode
            polartoneInnerThreshold = d.polartoneInnerThreshold
            polartoneDriftRevolutions = d.polartoneDriftRevolutions
            polartoneStartDirection = d.polartoneStartDirection
        case .starNest:
            starNestZoom = d.starNestZoom
            starNestSpeed = d.starNestSpeed
            starNestFormuparam = d.starNestFormuparam
            starNestTile = d.starNestTile
            starNestStepsize = d.starNestStepsize
            starNestBrightness = d.starNestBrightness
            starNestDarkmatter = d.starNestDarkmatter
            starNestDistfading = d.starNestDistfading
            starNestSaturation = d.starNestSaturation
            starNestVolsteps = d.starNestVolsteps
            starNestIterations = d.starNestIterations
        case .wireframe:
            wireframeBaseRadius = d.wireframeBaseRadius
            wireframeDisplaceScale = d.wireframeDisplaceScale
            wireframeLineThickness = d.wireframeLineThickness
            wireframeRotationSpeed = d.wireframeRotationSpeed
            wireframeTiltX = d.wireframeTiltX
            wireframeLineOpacity = d.wireframeLineOpacity
            wireframeSubdivisions = d.wireframeSubdivisions
            wireframeXExtent = d.wireframeXExtent
            wireframeYExtent = d.wireframeYExtent
            wireframeVerticalCenter = d.wireframeVerticalCenter
            wireframeFillWidth = d.wireframeFillWidth
            wireframeAnchorBottom = d.wireframeAnchorBottom
        case .outrunRain:
            outrunHorizon = d.outrunHorizon
            outrunHorizonGlowScale = d.outrunHorizonGlowScale
            outrunHorizonGlowBase = d.outrunHorizonGlowBase
            outrunHorizonBassGlow = d.outrunHorizonBassGlow
            outrunLowMidBackdrop = d.outrunLowMidBackdrop
            outrunBackgroundBrightness = d.outrunBackgroundBrightness
            outrunBackgroundGlow = d.outrunBackgroundGlow
            outrunLeanBase = d.outrunLeanBase
            outrunLeanLowMid = d.outrunLeanLowMid
            outrunFallBase = d.outrunFallBase
            outrunFallBass = d.outrunFallBass
            outrunFallEnergy = d.outrunFallEnergy
            outrunDensity = d.outrunDensity
            outrunLayer0ColumnScale = d.outrunLayer0ColumnScale
            outrunLayer0FallScale = d.outrunLayer0FallScale
            outrunLayer0Seed = d.outrunLayer0Seed
            outrunLayer0Thickness = d.outrunLayer0Thickness
            outrunLayer0Weight = d.outrunLayer0Weight
            outrunLayer1ColumnScale = d.outrunLayer1ColumnScale
            outrunLayer1FallScale = d.outrunLayer1FallScale
            outrunLayer1Seed = d.outrunLayer1Seed
            outrunLayer1Thickness = d.outrunLayer1Thickness
            outrunLayer1Weight = d.outrunLayer1Weight
            outrunLayer2ColumnScale = d.outrunLayer2ColumnScale
            outrunLayer2FallScale = d.outrunLayer2FallScale
            outrunLayer2Seed = d.outrunLayer2Seed
            outrunLayer2Thickness = d.outrunLayer2Thickness
            outrunLayer2Weight = d.outrunLayer2Weight
            outrunSparkleColumnScale = d.outrunSparkleColumnScale
            outrunSparkleFallScale = d.outrunSparkleFallScale
            outrunSparkleSeed = d.outrunSparkleSeed
            outrunSparkleThickness = d.outrunSparkleThickness
            outrunSparkleBase = d.outrunSparkleBase
            outrunSparkleTreble = d.outrunSparkleTreble
            outrunRainVerticalBase = d.outrunRainVerticalBase
            outrunRainVerticalY = d.outrunRainVerticalY
            outrunRainColorBase = d.outrunRainColorBase
            outrunRainColorTreble = d.outrunRainColorTreble
            outrunRainColorEnergy = d.outrunRainColorEnergy
            outrunRainBrightnessBase = d.outrunRainBrightnessBase
            outrunRainBrightnessEnergy = d.outrunRainBrightnessEnergy
            outrunRainBrightnessTreble = d.outrunRainBrightnessTreble
            outrunReflectionWidth = d.outrunReflectionWidth
            outrunReflectionBass = d.outrunReflectionBass
        case .octaveMeatballs:
            octaveMeatballsScale = d.octaveMeatballsScale
            octaveMeatballsBallDivisor = d.octaveMeatballsBallDivisor
            octaveMeatballsBackgroundR = d.octaveMeatballsBackgroundR
            octaveMeatballsBackgroundG = d.octaveMeatballsBackgroundG
            octaveMeatballsBackgroundB = d.octaveMeatballsBackgroundB
            octaveMeatballsOctavePhase = d.octaveMeatballsOctavePhase
            octaveMeatballsShimmerOctaveScale = d.octaveMeatballsShimmerOctaveScale
            octaveMeatballsShimmerTimeScale = d.octaveMeatballsShimmerTimeScale
            octaveMeatballsLifeTimeScale = d.octaveMeatballsLifeTimeScale
            octaveMeatballsPulseEdge0 = d.octaveMeatballsPulseEdge0
            octaveMeatballsPulseEdge1 = d.octaveMeatballsPulseEdge1
            octaveMeatballsLifeOctaveScale = d.octaveMeatballsLifeOctaveScale
            octaveMeatballsLifeDenomBase = d.octaveMeatballsLifeDenomBase
            octaveMeatballsLifeDenomRadius = d.octaveMeatballsLifeDenomRadius
            octaveMeatballsLifeDenomScale = d.octaveMeatballsLifeDenomScale
            octaveMeatballsDistanceFloor = d.octaveMeatballsDistanceFloor
            octaveMeatballsBallStrength = d.octaveMeatballsBallStrength
            octaveMeatballsBallBase = d.octaveMeatballsBallBase
            octaveMeatballsRedGlowR = d.octaveMeatballsRedGlowR
            octaveMeatballsRedGlowG = d.octaveMeatballsRedGlowG
            octaveMeatballsRedGlowB = d.octaveMeatballsRedGlowB
            octaveMeatballsPaletteFieldGain = d.octaveMeatballsPaletteFieldGain
            octaveMeatballsPaletteGain = d.octaveMeatballsPaletteGain
            octaveMeatballsBandPhase = d.octaveMeatballsBandPhase
            octaveMeatballsBandBrightness = d.octaveMeatballsBandBrightness
            octaveMeatballsEnergyBrightness = d.octaveMeatballsEnergyBrightness
            octaveMeatballsPaletteEnergy = d.octaveMeatballsPaletteEnergy
            octaveMeatballsOctaves = d.octaveMeatballsOctaves
        case .lavaLamp:
            lavaLampDensityFalloff = d.lavaLampDensityFalloff
            lavaLampBrightnessResponse = d.lavaLampBrightnessResponse
            lavaLampPaletteDensityScale = d.lavaLampPaletteDensityScale
            lavaLampMotionSpeed = d.lavaLampMotionSpeed
            lavaLampDriftStrength = d.lavaLampDriftStrength
            lavaLampWrapBounds = d.lavaLampWrapBounds
            lavaLampShaderBeatBoost = d.lavaLampShaderBeatBoost
            lavaLampCpuBeatBoost = d.lavaLampCpuBeatBoost
            lavaLampCpuBeatHalfLife = d.lavaLampCpuBeatHalfLife
            lavaLampGridSize = d.lavaLampGridSize
            lavaLampBlobCount = d.lavaLampBlobCount
        case .voronoi:
            voronoiEdgeSharpness = d.voronoiEdgeSharpness
            voronoiShaderBeatBoost = d.voronoiShaderBeatBoost
            voronoiSeedCount = d.voronoiSeedCount
            voronoiCyclePeriod = d.voronoiCyclePeriod
            voronoiFadeDuration = d.voronoiFadeDuration
            voronoiDriftSpeed = d.voronoiDriftSpeed
            voronoiDriftStrength = d.voronoiDriftStrength
            voronoiSeedSpread = d.voronoiSeedSpread
            voronoiTintRange = d.voronoiTintRange
            voronoiCpuBeatBoost = d.voronoiCpuBeatBoost
            voronoiCpuBeatHalfLife = d.voronoiCpuBeatHalfLife
            voronoiSoftBlurSigma = d.voronoiSoftBlurSigma
        case .heightfield:
            heightfieldGridSize = d.heightfieldGridSize
            heightfieldTiltAngle = d.heightfieldTiltAngle
            heightfieldZScale = d.heightfieldZScale
            heightfieldLineHalfThickness = d.heightfieldLineHalfThickness
            heightfieldLightX = d.heightfieldLightX
            heightfieldLightY = d.heightfieldLightY
            heightfieldLightZ = d.heightfieldLightZ
            heightfieldAmbientLight = d.heightfieldAmbientLight
            heightfieldVerticalFit = d.heightfieldVerticalFit
            heightfieldVerticalCenter = d.heightfieldVerticalCenter
            heightfieldBeatBoost = d.heightfieldBeatBoost
            heightfieldBeatHalfLife = d.heightfieldBeatHalfLife
            heightfieldXExtent = d.heightfieldXExtent
            heightfieldYExtent = d.heightfieldYExtent
            heightfieldOpacity = d.heightfieldOpacity
            heightfieldFillWidth = d.heightfieldFillWidth
            heightfieldAnchorBottom = d.heightfieldAnchorBottom
        case .particles:
            particlesMaxParticles = d.particlesMaxParticles
            particlesInitialVelocityScale = d.particlesInitialVelocityScale
            particlesRespawnVelocityScale = d.particlesRespawnVelocityScale
            particlesBaseSize = d.particlesBaseSize
            particlesBaseBrightness = d.particlesBaseBrightness
            particlesBrightnessJitter = d.particlesBrightnessJitter
            particlesBassThreshold = d.particlesBassThreshold
            particlesVelocityDamping = d.particlesVelocityDamping
            particlesReturnLerpRate = d.particlesReturnLerpRate
            particlesBeatHalfLife = d.particlesBeatHalfLife
            particlesBeatPulseScale = d.particlesBeatPulseScale
            particlesBassImpulse = d.particlesBassImpulse
            particlesBassBrightnessGain = d.particlesBassBrightnessGain
            particlesBrightnessCap = d.particlesBrightnessCap
            particlesBassSizeGain = d.particlesBassSizeGain
            particlesSizeCapMultiplier = d.particlesSizeCapMultiplier
            particlesRespawnOffscreenBound = d.particlesRespawnOffscreenBound
            particlesRespawnCenterHalfRange = d.particlesRespawnCenterHalfRange
            particlesLowBandPercent = d.particlesLowBandPercent
        case .fountain:
            fountainMaxParticles = d.fountainMaxParticles
            fountainSpawnRate = d.fountainSpawnRate
            fountainSpawnFloor = d.fountainSpawnFloor
            fountainBaseUp = d.fountainBaseUp
            fountainLaunchScale = d.fountainLaunchScale
            fountainLaunchJitter = d.fountainLaunchJitter
            fountainGravity = d.fountainGravity
            fountainHorizontalJitter = d.fountainHorizontalJitter
            fountainHorizontalDrag = d.fountainHorizontalDrag
            fountainBaseLifetime = d.fountainBaseLifetime
            fountainBaseSize = d.fountainBaseSize
            fountainBeatLaunchBoost = d.fountainBeatLaunchBoost
        case .fireworks:
            fireworksMaxParticles = d.fireworksMaxParticles
            fireworksBurstParticlesMax = d.fireworksBurstParticlesMax
            fireworksBurstParticlesMin = d.fireworksBurstParticlesMin
            fireworksBurstScaleBase = d.fireworksBurstScaleBase
            fireworksBurstScaleIntensity = d.fireworksBurstScaleIntensity
            fireworksBaseSpeed = d.fireworksBaseSpeed
            fireworksSpreadSpeed = d.fireworksSpreadSpeed
            fireworksGravity = d.fireworksGravity
            fireworksDrag = d.fireworksDrag
            fireworksBaseLifetime = d.fireworksBaseLifetime
            fireworksLifetimeJitter = d.fireworksLifetimeJitter
            fireworksMinLifetime = d.fireworksMinLifetime
            fireworksBaseSize = d.fireworksBaseSize
            fireworksBurstHalfX = d.fireworksBurstHalfX
            fireworksBurstHalfY = d.fireworksBurstHalfY
            fireworksAngleJitter = d.fireworksAngleJitter
        case .plasma:
            plasmaCoordinateScale = d.plasmaCoordinateScale
            plasmaCoordinateOffset = d.plasmaCoordinateOffset
            plasmaXFrequency = d.plasmaXFrequency
            plasmaYFrequency = d.plasmaYFrequency
            plasmaDiagonalFrequency = d.plasmaDiagonalFrequency
            plasmaXTimeScale = d.plasmaXTimeScale
            plasmaYTimeScale = d.plasmaYTimeScale
            plasmaDiagonalTimeScale = d.plasmaDiagonalTimeScale
            plasmaWaveDivisor = d.plasmaWaveDivisor
            plasmaContrast = d.plasmaContrast
            plasmaBrightnessBias = d.plasmaBrightnessBias
            plasmaEnergyResponse = d.plasmaEnergyResponse
            plasmaClampMin = d.plasmaClampMin
            plasmaClampMax = d.plasmaClampMax
            plasmaAlpha = d.plasmaAlpha
        case .bumpscope:
            bumpscopeUvClampMin = d.bumpscopeUvClampMin
            bumpscopeUvClampMax = d.bumpscopeUvClampMax
            bumpscopeNeighborRadius = d.bumpscopeNeighborRadius
            bumpscopeSlopeScale = d.bumpscopeSlopeScale
            bumpscopeSurfaceNormalY = d.bumpscopeSurfaceNormalY
            bumpscopeSurfaceNormalZ = d.bumpscopeSurfaceNormalZ
            bumpscopeLightX = d.bumpscopeLightX
            bumpscopeLightY = d.bumpscopeLightY
            bumpscopeLightZ = d.bumpscopeLightZ
            bumpscopeDiffuseFloor = d.bumpscopeDiffuseFloor
            bumpscopeBandGain = d.bumpscopeBandGain
            bumpscopeIntensityBias = d.bumpscopeIntensityBias
            bumpscopeIntensityClampMin = d.bumpscopeIntensityClampMin
            bumpscopeIntensityClampMax = d.bumpscopeIntensityClampMax
            bumpscopeAlpha = d.bumpscopeAlpha
        case .xyScope:
            xyScopeGain = d.xyScopeGain
            xyScopeSampleCount = d.xyScopeSampleCount
            xyScopeLineHalfThickness = d.xyScopeLineHalfThickness
            xyScopeRotationDegrees = d.xyScopeRotationDegrees
            xyScopeColorFloor = d.xyScopeColorFloor
            xyScopeBeatBoost = d.xyScopeBeatBoost
            xyScopeBeatHalfLife = d.xyScopeBeatHalfLife
            xyScopeAlpha = d.xyScopeAlpha
        case .iris:
            irisPetalCount = d.irisPetalCount
            irisInnerRadius = d.irisInnerRadius
            irisBaseLength = d.irisBaseLength
            irisLengthScale = d.irisLengthScale
            irisPetalWidth = d.irisPetalWidth
            irisLoudnessSwell = d.irisLoudnessSwell
            irisInnerDim = d.irisInnerDim
            irisAlpha = d.irisAlpha
        case .tricentric:
            tricentricRingCount = d.tricentricRingCount
            tricentricBaseRadius = d.tricentricBaseRadius
            tricentricRadiusFalloff = d.tricentricRadiusFalloff
            tricentricScaleFloor = d.tricentricScaleFloor
            tricentricRotationSpeed = d.tricentricRotationSpeed
            tricentricLineThickness = d.tricentricLineThickness
            tricentricAlpha = d.tricentricAlpha
        case .musicalSpectrum:
            musicalStartOctave = d.musicalStartOctave
            musicalOctaveCount = d.musicalOctaveCount
            musicalBarGap = d.musicalBarGap
            musicalOctaveGap = d.musicalOctaveGap
            musicalPitchClassColoring = d.musicalPitchClassColoring
            musicalColorFloor = d.musicalColorFloor
            musicalAlpha = d.musicalAlpha
        default:
            break
        }
    }

    public static let defaults: VisualizerSettings = {
        var profiles: [VisualizerStyle: StyleProfile] = [:]
        for s in VisualizerStyle.allCases { profiles[s] = .defaults(for: s) }
        return VisualizerSettings(
            visualizerStyle: .bars,
            profiles: profiles,
            demoModeEnabled: false,
            ribbonWaveCount: 3,
            particleSize: 1.0,
            particleSpeed: 1.0,
            barGap: 0.15,
            oscilloscopeThickness: 1.0,
            polartoneRadius: 0.46,
            polartoneAmplitude: 0.22,
            polartoneColorFloor: 0.12,
            polartoneRotationSpeed: 0,
            polartonePointCount: 256,
            polartonePhaseOffset: 0,
            polartoneLineHalfThickness: 0.006,
            polartoneWaveformClamp: 1,
            polartoneRenderMode: .ring,
            polartoneInnerThreshold: 0.05,
            polartoneDriftRevolutions: 8,
            polartoneStartDirection: .inward,
            starNestZoom: 0.78,
            starNestSpeed: 0.18,
            starNestFormuparam: 0.53,
            starNestTile: 0.85,
            starNestStepsize: 0.105,
            starNestBrightness: 0.00095,
            starNestDarkmatter: 0.34,
            starNestDistfading: 0.73,
            starNestSaturation: 0.82,
            starNestVolsteps: 18,
            starNestIterations: 13,
            wireframeBaseRadius: 0.50,
            wireframeDisplaceScale: 0.20,
            wireframeLineThickness: 0.003,
            wireframeRotationSpeed: 0.5,
            wireframeTiltX: 0.3,
            wireframeLineOpacity: 1.0,
            wireframeSubdivisions: 2,
            outrunHorizon: 0.80,
            outrunHorizonGlowScale: 6.0,
            outrunHorizonGlowBase: 0.6,
            outrunHorizonBassGlow: 0.5,
            outrunLowMidBackdrop: 0.1,
            outrunBackgroundBrightness: 0.25,
            outrunBackgroundGlow: 1.2,
            outrunLeanBase: 0.12,
            outrunLeanLowMid: 0.15,
            outrunFallBase: 1.1,
            outrunFallBass: 1.6,
            outrunFallEnergy: 0.8,
            outrunDensity: 70.0,
            outrunLayer0ColumnScale: 0.6,
            outrunLayer0FallScale: 0.80,
            outrunLayer0Seed: 0.0,
            outrunLayer0Thickness: 140.0,
            outrunLayer0Weight: 0.7,
            outrunLayer1ColumnScale: 1.0,
            outrunLayer1FallScale: 1.00,
            outrunLayer1Seed: 1.0,
            outrunLayer1Thickness: 220.0,
            outrunLayer1Weight: 1.0,
            outrunLayer2ColumnScale: 1.6,
            outrunLayer2FallScale: 1.25,
            outrunLayer2Seed: 2.0,
            outrunLayer2Thickness: 320.0,
            outrunLayer2Weight: 0.6,
            outrunSparkleColumnScale: 2.4,
            outrunSparkleFallScale: 1.50,
            outrunSparkleSeed: 3.0,
            outrunSparkleThickness: 520.0,
            outrunSparkleBase: 0.3,
            outrunSparkleTreble: 1.8,
            outrunRainVerticalBase: 0.35,
            outrunRainVerticalY: 0.9,
            outrunRainColorBase: 0.55,
            outrunRainColorTreble: 0.4,
            outrunRainColorEnergy: 0.2,
            outrunRainBrightnessBase: 1.6,
            outrunRainBrightnessEnergy: 1.5,
            outrunRainBrightnessTreble: 1.2,
            outrunReflectionWidth: 3.0,
            outrunReflectionBass: 0.6,
            plasmaCoordinateScale: 2.0,
            plasmaCoordinateOffset: 1.0,
            plasmaXFrequency: 8.0,
            plasmaYFrequency: 6.0,
            plasmaDiagonalFrequency: 5.0,
            plasmaXTimeScale: 1.0,
            plasmaYTimeScale: 1.3,
            plasmaDiagonalTimeScale: 0.7,
            plasmaWaveDivisor: 3.0,
            plasmaContrast: 0.5,
            plasmaBrightnessBias: 0.5,
            plasmaEnergyResponse: 0.3,
            plasmaClampMin: 0.0,
            plasmaClampMax: 1.0,
            plasmaAlpha: 1.0,
            bumpscopeUvClampMin: 0.0,
            bumpscopeUvClampMax: 1.0,
            bumpscopeNeighborRadius: 1,
            bumpscopeSlopeScale: 0.5,
            bumpscopeSurfaceNormalY: 1.0,
            bumpscopeSurfaceNormalZ: 0.0,
            bumpscopeLightX: 0.5,
            bumpscopeLightY: 0.7,
            bumpscopeLightZ: 0.5,
            bumpscopeDiffuseFloor: 0.0,
            bumpscopeBandGain: 2.0,
            bumpscopeIntensityBias: 0.2,
            bumpscopeIntensityClampMin: 0.0,
            bumpscopeIntensityClampMax: 1.0,
            bumpscopeAlpha: 1.0,
            octaveMeatballsScale: 10.0,
            octaveMeatballsBallDivisor: 10.0,
            octaveMeatballsBackgroundR: 0.005,
            octaveMeatballsBackgroundG: 0.0,
            octaveMeatballsBackgroundB: 0.01,
            octaveMeatballsOctavePhase: 0.1,
            octaveMeatballsShimmerOctaveScale: 0.5,
            octaveMeatballsShimmerTimeScale: 0.1,
            octaveMeatballsLifeTimeScale: 0.1,
            octaveMeatballsPulseEdge0: 0.4,
            octaveMeatballsPulseEdge1: 0.8,
            octaveMeatballsLifeOctaveScale: 0.02,
            octaveMeatballsLifeDenomBase: 0.02,
            octaveMeatballsLifeDenomRadius: 0.001,
            octaveMeatballsLifeDenomScale: 60.0,
            octaveMeatballsDistanceFloor: 0.001,
            octaveMeatballsBallStrength: 0.01,
            octaveMeatballsBallBase: 0.35,
            octaveMeatballsRedGlowR: 0.03,
            octaveMeatballsRedGlowG: 0.0,
            octaveMeatballsRedGlowB: 0.0,
            octaveMeatballsPaletteFieldGain: 1.5,
            octaveMeatballsPaletteGain: 2.0,
            octaveMeatballsBandPhase: 2.0,
            octaveMeatballsBandBrightness: 1.6,
            octaveMeatballsEnergyBrightness: 0.6,
            octaveMeatballsPaletteEnergy: 0.2,
            octaveMeatballsOctaves: 24,
            lavaLampDensityFalloff: 8.0,
            lavaLampBrightnessResponse: 0.8,
            lavaLampPaletteDensityScale: 0.4,
            lavaLampMotionSpeed: 0.3,
            lavaLampDriftStrength: 0.3,
            lavaLampWrapBounds: 1.2,
            lavaLampShaderBeatBoost: 0.5,
            lavaLampCpuBeatBoost: 0.2,
            lavaLampCpuBeatHalfLife: 0.2,
            lavaLampGridSize: 64,
            lavaLampBlobCount: 12,
            voronoiEdgeSharpness: 12.0,
            voronoiShaderBeatBoost: 0.3,
            voronoiSeedCount: 75,
            voronoiCyclePeriod: 60.0,
            voronoiFadeDuration: 0.5,
            voronoiDriftSpeed: 0.15,
            voronoiDriftStrength: 0.05,
            voronoiSeedSpread: 0.95,
            voronoiTintRange: 0.1,
            voronoiCpuBeatBoost: 0.3,
            voronoiCpuBeatHalfLife: 0.1,
            voronoiSoftBlurSigma: 1.5,
            heightfieldGridSize: 16,
            // Compute the OLD `Float.pi / 7.5` expression in Float, then widen to
            // Double. Float→Double→Float round-trips losslessly, so the read site's
            // `Float(...)` recovers the exact old bit pattern (1054242639).
            // `Double.pi / 7.5` would drift the recovered Float by 1 ULP.
            heightfieldTiltAngle: Double(Float.pi / 7.5),
            heightfieldZScale: 0.25,
            heightfieldLineHalfThickness: 0.003,
            heightfieldLightX: 0.5,
            heightfieldLightY: 0.7,
            heightfieldLightZ: 0.5,
            heightfieldAmbientLight: 0.3,
            heightfieldVerticalFit: 0.92,
            heightfieldVerticalCenter: 0.071,
            heightfieldBeatBoost: 0.4,
            heightfieldBeatHalfLife: 0.2,
            heightfieldXExtent: 1.0,
            heightfieldYExtent: 1.0,
            heightfieldOpacity: 1.0,
            fountainMaxParticles: 600,
            fountainSpawnRate: 15,
            fountainSpawnFloor: 0.15,
            fountainBaseUp: 0.55,
            fountainLaunchScale: 1.6,
            fountainLaunchJitter: 0.2,
            fountainGravity: 1.4,
            fountainHorizontalJitter: 0.04,
            fountainHorizontalDrag: 0.99,
            fountainBaseLifetime: 2.6,
            fountainBaseSize: 0.008,
            fountainBeatLaunchBoost: 0.6,
            fireworksMaxParticles: 600,
            fireworksBurstParticlesMax: 60,
            fireworksBurstParticlesMin: 8,
            fireworksBurstScaleBase: 0.7,
            fireworksBurstScaleIntensity: 0.6,
            fireworksBaseSpeed: 0.5,
            fireworksSpreadSpeed: 0.2,
            fireworksGravity: 0.5,
            fireworksDrag: 0.97,
            fireworksBaseLifetime: 1.5,
            fireworksLifetimeJitter: 0.3,
            fireworksMinLifetime: 0.3,
            fireworksBaseSize: 0.008,
            fireworksBurstHalfX: 0.6,
            fireworksBurstHalfY: 0.4,
            fireworksAngleJitter: 0.05,
            particlesMaxParticles: 200,
            particlesInitialVelocityScale: 0.05,
            particlesRespawnVelocityScale: 0.05,
            particlesBaseSize: 0.012,
            particlesBaseBrightness: 0.45,
            particlesBrightnessJitter: 0.3,
            particlesBassThreshold: 0.5,
            particlesVelocityDamping: 0.985,
            particlesReturnLerpRate: 3,
            particlesBeatHalfLife: 0.15,
            particlesBeatPulseScale: 0.5,
            particlesBassImpulse: 0.25,
            particlesBassBrightnessGain: 0.5,
            particlesBrightnessCap: 1.0,
            particlesBassSizeGain: 1.5,
            particlesSizeCapMultiplier: 3,
            particlesRespawnOffscreenBound: 1.15,
            particlesRespawnCenterHalfRange: 0.15,
            particlesLowBandPercent: 0.15,
            ribbonTiltSpacing: 0.18,
            ribbonDepthFalloff: 0.25,
            ribbonSampleCount: 256,
            ribbonSmoothing: 0.18,
            ribbonGain: 1.6,
            ribbonHeightScale: 0.40,
            ribbonMotionSpeed: 0.6,
            ribbonBaseFrequency: 4.0,
            ribbonFrequencySpread: 4.0,
            ribbonStereoPanScale: 0.27,
            // Stored as Double(Float.pi * 0.5): computing the OLD `.pi * 0.5`
            // expression in Float, then widening, so reading Float(setting)
            // recovers the original Float bit pattern exactly. A Double.pi-derived
            // value would drift the recovered Float by 1 ULP.
            ribbonPhaseSwing: Double(Float.pi * 0.5),
            ribbonMaxAmplitude: 1.0,
            ribbonAlpha: 1.0,
            joyPlotSampleCount: 64,
            joyPlotRowSpacing: 0.4,
            joyPlotRowHeight: 0.15,
            joyPlotBaselineOffset: 0.0,
            joyPlotXExtent: 1.0,
            joyPlotBeatHalfLife: 0.15,
            joyPlotBeatBoost: 0.5,
            joyPlotBottomDim: 0.3,
            joyPlotAlpha: 1.0,
            trailPersistence: 0,
            useStereoImage: false,
            fftWindow: .hann,
            vignetteAmount: 0,
            kaleidoscopeFolds: 0,
            windowTransparencyMode: .perPixelAlpha,
            windowOpacity: 1.0,
            clickThroughEnabled: false,
            borderlessWindow: false,
            windowBorderMode: .off,
            windowBorderColor: RGBAColor(r: 1, g: 1, b: 1, a: 1),
            windowBorderOpacity: 0.7,
            windowBorderWidth: 1.0,
            mouseControlModifier: .shift,
            centerBelowLyrics: true,
            paletteCycleEnabled: false,
            paletteCycleInterval: 60,
            paletteCycleFadeDuration: 1.5
        )
    }()
}

// MARK: - Forwarders to the current profile
//
// These let existing code (every visualizer, MetalView, RenderModel, SettingsView)
// keep using `settings.gain` / `settings.paletteName` / etc. unchanged — every read
// hits the current profile, every write mutates only the current profile.

public extension VisualizerSettings {
    var paletteName: String {
        get { current.paletteName }
        set { mutateCurrent { $0.paletteName = newValue } }
    }
    var customStops: [RGBAColor] {
        get { current.customStops }
        set { mutateCurrent { $0.customStops = newValue } }
    }
    var gain: Float {
        get { current.gain }
        set { mutateCurrent { $0.gain = newValue } }
    }
    var barCount: Int {
        get { current.barCount }
        set { mutateCurrent { $0.barCount = newValue } }
    }
    var smoothing: Float {
        get { current.smoothing }
        set { mutateCurrent { $0.smoothing = newValue } }
    }
    var peakHoldEnabled: Bool {
        get { current.peakHoldEnabled }
        set { mutateCurrent { $0.peakHoldEnabled = newValue } }
    }
    var glowEnabled: Bool {
        get { current.glowEnabled }
        set { mutateCurrent { $0.glowEnabled = newValue } }
    }
    var glowIntensity: Float {
        get { current.glowIntensity }
        set { mutateCurrent { $0.glowIntensity = newValue } }
    }
    // NOTE: overlayEnabled/overlayPosition/overlayOpacity, alwaysOnTop and
    // targetFPS are now stored app-wide fields on VisualizerSettings (above),
    // not per-style forwarders.
    var fullscreenDisplayID: UInt32? {
        get { current.fullscreenDisplayID }
        set { mutateCurrent { $0.fullscreenDisplayID = newValue } }
    }
    var backgroundStyle: BackgroundStyle {
        get { current.backgroundStyle }
        set { mutateCurrent { $0.backgroundStyle = newValue } }
    }
}

// MARK: - Persistence

public extension VisualizerSettings {
    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("MacVisualizer", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    static func load(from url: URL) -> VisualizerSettings {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // A missing file is the normal first-run case — not corruption.
            // Only treat an existing-but-unreadable file as something to preserve.
            if FileManager.default.fileExists(atPath: url.path) {
                Log.settings.error("Failed to read settings at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
                backUpCorruptSettings(at: url)
            }
            return .defaults
        }

        do {
            return try JSONDecoder().decode(VisualizerSettings.self, from: data)
        } catch {
            // Corrupt or migration-incompatible JSON. Preserve it before resetting
            // so the user's config is never silently wiped.
            Log.settings.error("Failed to decode settings at \(url.path, privacy: .public): \(String(describing: error), privacy: .public). Backing up and resetting to defaults.")
            backUpCorruptSettings(at: url)
            return .defaults
        }
    }

    /// Move the unreadable/undecodable settings file aside to
    /// `settings.corrupt-<uuid>.json` next to the original, so it is preserved
    /// for diagnostics instead of being overwritten by the next save. The UUID
    /// suffix guarantees a unique path even for multiple corruptions within the
    /// same second, so no prior backup is ever clobbered.
    private static func backUpCorruptSettings(at url: URL) {
        let suffix = UUID().uuidString
        let backup = url
            .deletingLastPathComponent()
            .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent).corrupt-\(suffix).json")
        do {
            try FileManager.default.moveItem(at: url, to: backup)
            Log.settings.error("Backed up corrupt settings to \(backup.path, privacy: .public)")
        } catch {
            Log.settings.error("Failed to back up corrupt settings at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}

/// A decoded profile plus which position-offset keys it actually carried, so the
/// settings decoder can seed the missing ones from a legacy app-wide offset.
private struct ProfileWithOffsetPresence: Decodable {
    let profile: StyleProfile
    let presence: StyleProfile.OffsetPresence
    init(from decoder: Decoder) throws {
        profile = try StyleProfile(from: decoder)
        presence = try StyleProfile.offsetPresence(in: decoder)
    }
}

// MARK: - Codable (tolerant decoder + migration from old flat-field JSON)

extension VisualizerSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case visualizerStyle, profiles
        case demoModeEnabled
        case ribbonWaveCount = "siriWaveCount"        // JSON key preserved for backward-compat
        case particleSize, particleSpeed, barGap, oscilloscopeThickness
        case polartoneRadius, polartoneAmplitude
        case polartoneColorFloor, polartoneRotationSpeed, polartonePointCount
        case polartonePhaseOffset, polartoneLineHalfThickness, polartoneWaveformClamp
        case polartoneRenderMode, polartoneInnerThreshold, polartoneDriftRevolutions, polartoneStartDirection
        case starNestZoom, starNestSpeed, starNestFormuparam, starNestTile, starNestStepsize
        case starNestBrightness, starNestDarkmatter, starNestDistfading, starNestSaturation
        case starNestVolsteps, starNestIterations
        case wireframeBaseRadius, wireframeDisplaceScale, wireframeLineThickness
        case wireframeRotationSpeed, wireframeTiltX, wireframeLineOpacity, wireframeSubdivisions
        case wireframeXExtent, wireframeYExtent, wireframeVerticalCenter
        case wireframeFillWidth, wireframeAnchorBottom
        case wireframeFillWindow   // legacy v0.6.x combined flag; read-only migration
        case outrunHorizon, outrunHorizonGlowScale, outrunHorizonGlowBase, outrunHorizonBassGlow
        case outrunLowMidBackdrop, outrunBackgroundBrightness, outrunBackgroundGlow
        case outrunLeanBase, outrunLeanLowMid, outrunFallBase, outrunFallBass, outrunFallEnergy, outrunDensity
        case outrunLayer0ColumnScale, outrunLayer0FallScale, outrunLayer0Seed, outrunLayer0Thickness, outrunLayer0Weight
        case outrunLayer1ColumnScale, outrunLayer1FallScale, outrunLayer1Seed, outrunLayer1Thickness, outrunLayer1Weight
        case outrunLayer2ColumnScale, outrunLayer2FallScale, outrunLayer2Seed, outrunLayer2Thickness, outrunLayer2Weight
        case outrunSparkleColumnScale, outrunSparkleFallScale, outrunSparkleSeed, outrunSparkleThickness
        case outrunSparkleBase, outrunSparkleTreble
        case outrunRainVerticalBase, outrunRainVerticalY
        case outrunRainColorBase, outrunRainColorTreble, outrunRainColorEnergy
        case outrunRainBrightnessBase, outrunRainBrightnessEnergy, outrunRainBrightnessTreble
        case outrunReflectionWidth, outrunReflectionBass
        case plasmaCoordinateScale, plasmaCoordinateOffset
        case plasmaXFrequency, plasmaYFrequency, plasmaDiagonalFrequency
        case plasmaXTimeScale, plasmaYTimeScale, plasmaDiagonalTimeScale
        case plasmaWaveDivisor, plasmaContrast, plasmaBrightnessBias, plasmaEnergyResponse
        case plasmaClampMin, plasmaClampMax, plasmaAlpha
        case bumpscopeUvClampMin, bumpscopeUvClampMax, bumpscopeNeighborRadius
        case bumpscopeSlopeScale, bumpscopeSurfaceNormalY, bumpscopeSurfaceNormalZ
        case bumpscopeLightX, bumpscopeLightY, bumpscopeLightZ, bumpscopeDiffuseFloor
        case bumpscopeBandGain, bumpscopeIntensityBias
        case bumpscopeIntensityClampMin, bumpscopeIntensityClampMax, bumpscopeAlpha
        case octaveMeatballsScale, octaveMeatballsBallDivisor
        case octaveMeatballsBackgroundR, octaveMeatballsBackgroundG, octaveMeatballsBackgroundB
        case octaveMeatballsOctavePhase, octaveMeatballsShimmerOctaveScale, octaveMeatballsShimmerTimeScale
        case octaveMeatballsLifeTimeScale, octaveMeatballsPulseEdge0, octaveMeatballsPulseEdge1
        case octaveMeatballsLifeOctaveScale, octaveMeatballsLifeDenomBase, octaveMeatballsLifeDenomRadius, octaveMeatballsLifeDenomScale
        case octaveMeatballsDistanceFloor, octaveMeatballsBallStrength, octaveMeatballsBallBase
        case octaveMeatballsRedGlowR, octaveMeatballsRedGlowG, octaveMeatballsRedGlowB
        case octaveMeatballsPaletteFieldGain, octaveMeatballsPaletteGain
        case octaveMeatballsBandPhase, octaveMeatballsBandBrightness, octaveMeatballsEnergyBrightness, octaveMeatballsPaletteEnergy
        case octaveMeatballsOctaves
        case lavaLampDensityFalloff, lavaLampBrightnessResponse, lavaLampPaletteDensityScale
        case lavaLampMotionSpeed, lavaLampDriftStrength, lavaLampWrapBounds
        case lavaLampShaderBeatBoost, lavaLampCpuBeatBoost, lavaLampCpuBeatHalfLife
        case lavaLampGridSize, lavaLampBlobCount
        case voronoiEdgeSharpness, voronoiShaderBeatBoost, voronoiSeedCount
        case voronoiCyclePeriod, voronoiFadeDuration, voronoiDriftSpeed, voronoiDriftStrength
        case voronoiSeedSpread, voronoiTintRange
        case voronoiCpuBeatBoost, voronoiCpuBeatHalfLife, voronoiSoftBlurSigma
        case heightfieldGridSize, heightfieldTiltAngle, heightfieldZScale, heightfieldLineHalfThickness
        case heightfieldLightX, heightfieldLightY, heightfieldLightZ, heightfieldAmbientLight
        case heightfieldVerticalFit, heightfieldVerticalCenter
        case heightfieldBeatBoost, heightfieldBeatHalfLife
        case heightfieldXExtent, heightfieldYExtent, heightfieldOpacity
        case heightfieldFillWidth, heightfieldAnchorBottom
        case fountainMaxParticles, fountainSpawnRate, fountainSpawnFloor, fountainBaseUp
        case fountainLaunchScale, fountainLaunchJitter, fountainGravity, fountainHorizontalJitter
        case fountainHorizontalDrag, fountainBaseLifetime, fountainBaseSize, fountainBeatLaunchBoost
        case fireworksMaxParticles, fireworksBurstParticlesMax, fireworksBurstParticlesMin
        case fireworksBurstScaleBase, fireworksBurstScaleIntensity, fireworksBaseSpeed, fireworksSpreadSpeed
        case fireworksGravity, fireworksDrag, fireworksBaseLifetime, fireworksLifetimeJitter
        case fireworksMinLifetime, fireworksBaseSize, fireworksBurstHalfX, fireworksBurstHalfY, fireworksAngleJitter
        case particlesMaxParticles, particlesInitialVelocityScale, particlesRespawnVelocityScale
        case particlesBaseSize, particlesBaseBrightness, particlesBrightnessJitter, particlesBassThreshold
        case particlesVelocityDamping, particlesReturnLerpRate, particlesBeatHalfLife, particlesBeatPulseScale
        case particlesBassImpulse, particlesBassBrightnessGain, particlesBrightnessCap, particlesBassSizeGain
        case particlesSizeCapMultiplier, particlesRespawnOffscreenBound, particlesRespawnCenterHalfRange, particlesLowBandPercent
        case ribbonTiltSpacing = "siriTiltSpacing"    // JSON key preserved for backward-compat
        case ribbonDepthFalloff = "siriDepthFalloff"  // JSON key preserved for backward-compat
        case ribbonSampleCount, ribbonSmoothing, ribbonGain, ribbonHeightScale
        case ribbonMotionSpeed, ribbonBaseFrequency, ribbonFrequencySpread
        case ribbonStereoPanScale, ribbonPhaseSwing, ribbonMaxAmplitude, ribbonAlpha
        case joyPlotSampleCount, joyPlotRowSpacing, joyPlotRowHeight, joyPlotBaselineOffset
        case joyPlotXExtent, joyPlotBeatHalfLife, joyPlotBeatBoost, joyPlotBottomDim, joyPlotAlpha
        case xyScopeGain, xyScopeSampleCount, xyScopeLineHalfThickness, xyScopeRotationDegrees
        case xyScopeColorFloor, xyScopeBeatBoost, xyScopeBeatHalfLife, xyScopeAlpha
        case irisPetalCount, irisInnerRadius, irisBaseLength, irisLengthScale
        case irisPetalWidth, irisLoudnessSwell, irisInnerDim, irisAlpha
        case tricentricRingCount, tricentricBaseRadius, tricentricRadiusFalloff, tricentricScaleFloor
        case tricentricRotationSpeed, tricentricLineThickness, tricentricAlpha
        case musicalStartOctave, musicalOctaveCount, musicalBarGap, musicalOctaveGap
        case musicalPitchClassColoring, musicalColorFloor, musicalAlpha
        case trailPersistence
        case useStereoImage
        case fftWindow
        case vignetteAmount
        case outputBrightness
        case kaleidoscopeFolds
        case windowTransparencyMode, windowOpacity, clickThroughEnabled, borderlessWindow
        case windowBorderMode, windowBorderEnabled, windowBorderColor, windowBorderOpacity, windowBorderWidth
        case mouseControlModifier
        case centerBelowLyrics
        case positionOffsetX, positionOffsetY   // legacy app-wide offset: read-only, seeds each profile
        case paletteCycleEnabled, paletteCycleInterval, paletteCycleFadeDuration
        case lyrics
        // Legacy flat fields (old format) — used for migration only.
        case paletteName, customStops, gain, barCount, smoothing, peakHoldEnabled
        case glowEnabled, glowIntensity
        case overlayEnabled, overlayPosition, overlayOpacity
        case alwaysOnTop, fullscreenDisplayID, targetFPS, backgroundStyle
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VisualizerSettings.defaults

        let style = try c.decodeLossyEnum(VisualizerStyle.self, forKey: .visualizerStyle, default: d.visualizerStyle)
        let dme  = try c.decodeIfPresent(Bool.self, forKey: .demoModeEnabled) ?? d.demoModeEnabled
        let swc  = try c.decodeIfPresent(Int.self, forKey: .ribbonWaveCount) ?? d.ribbonWaveCount
        let ps   = try c.decodeIfPresent(Float.self, forKey: .particleSize) ?? d.particleSize
        let psp  = try c.decodeIfPresent(Float.self, forKey: .particleSpeed) ?? d.particleSpeed
        let bg   = try c.decodeIfPresent(Float.self, forKey: .barGap) ?? d.barGap
        let ot   = try c.decodeIfPresent(Float.self, forKey: .oscilloscopeThickness) ?? d.oscilloscopeThickness
        let pr   = try c.decodeIfPresent(Float.self, forKey: .polartoneRadius) ?? d.polartoneRadius
        let pa   = try c.decodeIfPresent(Float.self, forKey: .polartoneAmplitude) ?? d.polartoneAmplitude
        let pcf  = try c.decodeIfPresent(Float.self, forKey: .polartoneColorFloor) ?? d.polartoneColorFloor
        let prs  = try c.decodeIfPresent(Float.self, forKey: .polartoneRotationSpeed) ?? d.polartoneRotationSpeed
        let ppc  = try c.decodeIfPresent(Int.self, forKey: .polartonePointCount) ?? d.polartonePointCount
        let ppo  = try c.decodeIfPresent(Float.self, forKey: .polartonePhaseOffset) ?? d.polartonePhaseOffset
        let plht = try c.decodeIfPresent(Float.self, forKey: .polartoneLineHalfThickness) ?? d.polartoneLineHalfThickness
        let pwc  = try c.decodeIfPresent(Float.self, forKey: .polartoneWaveformClamp) ?? d.polartoneWaveformClamp
        let prm  = try c.decodeLossyEnum(PolartoneRenderMode.self, forKey: .polartoneRenderMode, default: d.polartoneRenderMode)
        let pit  = try c.decodeIfPresent(Float.self, forKey: .polartoneInnerThreshold) ?? d.polartoneInnerThreshold
        let pdr  = try c.decodeIfPresent(Float.self, forKey: .polartoneDriftRevolutions) ?? d.polartoneDriftRevolutions
        let psd  = try c.decodeLossyEnum(PolartoneStartDirection.self, forKey: .polartoneStartDirection, default: d.polartoneStartDirection)
        let snz  = try c.decodeIfPresent(Double.self, forKey: .starNestZoom) ?? d.starNestZoom
        let sns  = try c.decodeIfPresent(Double.self, forKey: .starNestSpeed) ?? d.starNestSpeed
        let snf  = try c.decodeIfPresent(Double.self, forKey: .starNestFormuparam) ?? d.starNestFormuparam
        let snt  = try c.decodeIfPresent(Double.self, forKey: .starNestTile) ?? d.starNestTile
        let snss = try c.decodeIfPresent(Double.self, forKey: .starNestStepsize) ?? d.starNestStepsize
        let snb  = try c.decodeIfPresent(Double.self, forKey: .starNestBrightness) ?? d.starNestBrightness
        let snd  = try c.decodeIfPresent(Double.self, forKey: .starNestDarkmatter) ?? d.starNestDarkmatter
        let sndf = try c.decodeIfPresent(Double.self, forKey: .starNestDistfading) ?? d.starNestDistfading
        let snsa = try c.decodeIfPresent(Double.self, forKey: .starNestSaturation) ?? d.starNestSaturation
        // Clamp the persisted density ints to the shader's hard GPU caps so a
        // corrupt/hand-edited settings.json can't leave the slider state odd.
        let snvs = min(26, max(1, try c.decodeIfPresent(Int.self, forKey: .starNestVolsteps) ?? d.starNestVolsteps))
        let sni  = min(16, max(1, try c.decodeIfPresent(Int.self, forKey: .starNestIterations) ?? d.starNestIterations))
        let wbr  = try c.decodeIfPresent(Double.self, forKey: .wireframeBaseRadius) ?? d.wireframeBaseRadius
        let wds  = try c.decodeIfPresent(Double.self, forKey: .wireframeDisplaceScale) ?? d.wireframeDisplaceScale
        let wlt  = try c.decodeIfPresent(Double.self, forKey: .wireframeLineThickness) ?? d.wireframeLineThickness
        let wrs  = try c.decodeIfPresent(Double.self, forKey: .wireframeRotationSpeed) ?? d.wireframeRotationSpeed
        let wtx  = try c.decodeIfPresent(Double.self, forKey: .wireframeTiltX) ?? d.wireframeTiltX
        let wlo  = try c.decodeIfPresent(Double.self, forKey: .wireframeLineOpacity) ?? d.wireframeLineOpacity
        // Clamp the persisted subdivision level to the use-site range so a
        // corrupt/hand-edited settings.json can never push the mesh out of bounds.
        let wsub = min(4, max(0, try c.decodeIfPresent(Int.self, forKey: .wireframeSubdivisions) ?? d.wireframeSubdivisions))
        let wxe  = try c.decodeIfPresent(Double.self, forKey: .wireframeXExtent) ?? d.wireframeXExtent
        let wye  = try c.decodeIfPresent(Double.self, forKey: .wireframeYExtent) ?? d.wireframeYExtent
        let wvc  = try c.decodeIfPresent(Double.self, forKey: .wireframeVerticalCenter) ?? d.wireframeVerticalCenter
        // Legacy combined flag seeds both toggles; either explicit new key wins.
        let legacyFill = try c.decodeIfPresent(Bool.self, forKey: .wireframeFillWindow)
        let wfWidth  = try c.decodeIfPresent(Bool.self, forKey: .wireframeFillWidth)
            ?? legacyFill ?? d.wireframeFillWidth
        let wfBottom = try c.decodeIfPresent(Bool.self, forKey: .wireframeAnchorBottom)
            ?? legacyFill ?? d.wireframeAnchorBottom
        let orHorizon  = try c.decodeIfPresent(Double.self, forKey: .outrunHorizon) ?? d.outrunHorizon
        let orHGScale  = try c.decodeIfPresent(Double.self, forKey: .outrunHorizonGlowScale) ?? d.outrunHorizonGlowScale
        let orHGBase   = try c.decodeIfPresent(Double.self, forKey: .outrunHorizonGlowBase) ?? d.outrunHorizonGlowBase
        let orHBGlow   = try c.decodeIfPresent(Double.self, forKey: .outrunHorizonBassGlow) ?? d.outrunHorizonBassGlow
        let orLMBack   = try c.decodeIfPresent(Double.self, forKey: .outrunLowMidBackdrop) ?? d.outrunLowMidBackdrop
        let orBgBright = try c.decodeIfPresent(Double.self, forKey: .outrunBackgroundBrightness) ?? d.outrunBackgroundBrightness
        let orBgGlow   = try c.decodeIfPresent(Double.self, forKey: .outrunBackgroundGlow) ?? d.outrunBackgroundGlow
        let orLeanB    = try c.decodeIfPresent(Double.self, forKey: .outrunLeanBase) ?? d.outrunLeanBase
        let orLeanLM   = try c.decodeIfPresent(Double.self, forKey: .outrunLeanLowMid) ?? d.outrunLeanLowMid
        let orFallB    = try c.decodeIfPresent(Double.self, forKey: .outrunFallBase) ?? d.outrunFallBase
        let orFallBass = try c.decodeIfPresent(Double.self, forKey: .outrunFallBass) ?? d.outrunFallBass
        let orFallEn   = try c.decodeIfPresent(Double.self, forKey: .outrunFallEnergy) ?? d.outrunFallEnergy
        let orDens     = try c.decodeIfPresent(Double.self, forKey: .outrunDensity) ?? d.outrunDensity
        let orL0Col    = try c.decodeIfPresent(Double.self, forKey: .outrunLayer0ColumnScale) ?? d.outrunLayer0ColumnScale
        let orL0Fall   = try c.decodeIfPresent(Double.self, forKey: .outrunLayer0FallScale) ?? d.outrunLayer0FallScale
        let orL0Seed   = try c.decodeIfPresent(Double.self, forKey: .outrunLayer0Seed) ?? d.outrunLayer0Seed
        let orL0Thick  = try c.decodeIfPresent(Double.self, forKey: .outrunLayer0Thickness) ?? d.outrunLayer0Thickness
        let orL0Wt     = try c.decodeIfPresent(Double.self, forKey: .outrunLayer0Weight) ?? d.outrunLayer0Weight
        let orL1Col    = try c.decodeIfPresent(Double.self, forKey: .outrunLayer1ColumnScale) ?? d.outrunLayer1ColumnScale
        let orL1Fall   = try c.decodeIfPresent(Double.self, forKey: .outrunLayer1FallScale) ?? d.outrunLayer1FallScale
        let orL1Seed   = try c.decodeIfPresent(Double.self, forKey: .outrunLayer1Seed) ?? d.outrunLayer1Seed
        let orL1Thick  = try c.decodeIfPresent(Double.self, forKey: .outrunLayer1Thickness) ?? d.outrunLayer1Thickness
        let orL1Wt     = try c.decodeIfPresent(Double.self, forKey: .outrunLayer1Weight) ?? d.outrunLayer1Weight
        let orL2Col    = try c.decodeIfPresent(Double.self, forKey: .outrunLayer2ColumnScale) ?? d.outrunLayer2ColumnScale
        let orL2Fall   = try c.decodeIfPresent(Double.self, forKey: .outrunLayer2FallScale) ?? d.outrunLayer2FallScale
        let orL2Seed   = try c.decodeIfPresent(Double.self, forKey: .outrunLayer2Seed) ?? d.outrunLayer2Seed
        let orL2Thick  = try c.decodeIfPresent(Double.self, forKey: .outrunLayer2Thickness) ?? d.outrunLayer2Thickness
        let orL2Wt     = try c.decodeIfPresent(Double.self, forKey: .outrunLayer2Weight) ?? d.outrunLayer2Weight
        let orSpCol    = try c.decodeIfPresent(Double.self, forKey: .outrunSparkleColumnScale) ?? d.outrunSparkleColumnScale
        let orSpFall   = try c.decodeIfPresent(Double.self, forKey: .outrunSparkleFallScale) ?? d.outrunSparkleFallScale
        let orSpSeed   = try c.decodeIfPresent(Double.self, forKey: .outrunSparkleSeed) ?? d.outrunSparkleSeed
        let orSpThick  = try c.decodeIfPresent(Double.self, forKey: .outrunSparkleThickness) ?? d.outrunSparkleThickness
        let orSpBase   = try c.decodeIfPresent(Double.self, forKey: .outrunSparkleBase) ?? d.outrunSparkleBase
        let orSpTreb   = try c.decodeIfPresent(Double.self, forKey: .outrunSparkleTreble) ?? d.outrunSparkleTreble
        let orRVBase   = try c.decodeIfPresent(Double.self, forKey: .outrunRainVerticalBase) ?? d.outrunRainVerticalBase
        let orRVY      = try c.decodeIfPresent(Double.self, forKey: .outrunRainVerticalY) ?? d.outrunRainVerticalY
        let orRCBase   = try c.decodeIfPresent(Double.self, forKey: .outrunRainColorBase) ?? d.outrunRainColorBase
        let orRCTreb   = try c.decodeIfPresent(Double.self, forKey: .outrunRainColorTreble) ?? d.outrunRainColorTreble
        let orRCEn     = try c.decodeIfPresent(Double.self, forKey: .outrunRainColorEnergy) ?? d.outrunRainColorEnergy
        let orRBBase   = try c.decodeIfPresent(Double.self, forKey: .outrunRainBrightnessBase) ?? d.outrunRainBrightnessBase
        let orRBEn     = try c.decodeIfPresent(Double.self, forKey: .outrunRainBrightnessEnergy) ?? d.outrunRainBrightnessEnergy
        let orRBTreb   = try c.decodeIfPresent(Double.self, forKey: .outrunRainBrightnessTreble) ?? d.outrunRainBrightnessTreble
        let orRefW     = try c.decodeIfPresent(Double.self, forKey: .outrunReflectionWidth) ?? d.outrunReflectionWidth
        let orRefBass  = try c.decodeIfPresent(Double.self, forKey: .outrunReflectionBass) ?? d.outrunReflectionBass
        let plCoordSc  = try c.decodeIfPresent(Double.self, forKey: .plasmaCoordinateScale) ?? d.plasmaCoordinateScale
        let plCoordOff = try c.decodeIfPresent(Double.self, forKey: .plasmaCoordinateOffset) ?? d.plasmaCoordinateOffset
        let plXFreq    = try c.decodeIfPresent(Double.self, forKey: .plasmaXFrequency) ?? d.plasmaXFrequency
        let plYFreq    = try c.decodeIfPresent(Double.self, forKey: .plasmaYFrequency) ?? d.plasmaYFrequency
        let plDiagFreq = try c.decodeIfPresent(Double.self, forKey: .plasmaDiagonalFrequency) ?? d.plasmaDiagonalFrequency
        let plXTime    = try c.decodeIfPresent(Double.self, forKey: .plasmaXTimeScale) ?? d.plasmaXTimeScale
        let plYTime    = try c.decodeIfPresent(Double.self, forKey: .plasmaYTimeScale) ?? d.plasmaYTimeScale
        let plDiagTime = try c.decodeIfPresent(Double.self, forKey: .plasmaDiagonalTimeScale) ?? d.plasmaDiagonalTimeScale
        let plWaveDiv  = try c.decodeIfPresent(Double.self, forKey: .plasmaWaveDivisor) ?? d.plasmaWaveDivisor
        let plContrast = try c.decodeIfPresent(Double.self, forKey: .plasmaContrast) ?? d.plasmaContrast
        let plBright   = try c.decodeIfPresent(Double.self, forKey: .plasmaBrightnessBias) ?? d.plasmaBrightnessBias
        let plEnergy   = try c.decodeIfPresent(Double.self, forKey: .plasmaEnergyResponse) ?? d.plasmaEnergyResponse
        let plClampMin = try c.decodeIfPresent(Double.self, forKey: .plasmaClampMin) ?? d.plasmaClampMin
        let plClampMax = try c.decodeIfPresent(Double.self, forKey: .plasmaClampMax) ?? d.plasmaClampMax
        let plAlpha    = try c.decodeIfPresent(Double.self, forKey: .plasmaAlpha) ?? d.plasmaAlpha
        let bsUvMin    = try c.decodeIfPresent(Double.self, forKey: .bumpscopeUvClampMin) ?? d.bumpscopeUvClampMin
        let bsUvMax    = try c.decodeIfPresent(Double.self, forKey: .bumpscopeUvClampMax) ?? d.bumpscopeUvClampMax
        let bsRadius   = try c.decodeIfPresent(Int.self, forKey: .bumpscopeNeighborRadius) ?? d.bumpscopeNeighborRadius
        let bsSlope    = try c.decodeIfPresent(Double.self, forKey: .bumpscopeSlopeScale) ?? d.bumpscopeSlopeScale
        let bsNormalY  = try c.decodeIfPresent(Double.self, forKey: .bumpscopeSurfaceNormalY) ?? d.bumpscopeSurfaceNormalY
        let bsNormalZ  = try c.decodeIfPresent(Double.self, forKey: .bumpscopeSurfaceNormalZ) ?? d.bumpscopeSurfaceNormalZ
        let bsLightX   = try c.decodeIfPresent(Double.self, forKey: .bumpscopeLightX) ?? d.bumpscopeLightX
        let bsLightY   = try c.decodeIfPresent(Double.self, forKey: .bumpscopeLightY) ?? d.bumpscopeLightY
        let bsLightZ   = try c.decodeIfPresent(Double.self, forKey: .bumpscopeLightZ) ?? d.bumpscopeLightZ
        let bsDiffuse  = try c.decodeIfPresent(Double.self, forKey: .bumpscopeDiffuseFloor) ?? d.bumpscopeDiffuseFloor
        let bsGain     = try c.decodeIfPresent(Double.self, forKey: .bumpscopeBandGain) ?? d.bumpscopeBandGain
        let bsBias     = try c.decodeIfPresent(Double.self, forKey: .bumpscopeIntensityBias) ?? d.bumpscopeIntensityBias
        let bsIntMin   = try c.decodeIfPresent(Double.self, forKey: .bumpscopeIntensityClampMin) ?? d.bumpscopeIntensityClampMin
        let bsIntMax   = try c.decodeIfPresent(Double.self, forKey: .bumpscopeIntensityClampMax) ?? d.bumpscopeIntensityClampMax
        let bsAlpha    = try c.decodeIfPresent(Double.self, forKey: .bumpscopeAlpha) ?? d.bumpscopeAlpha
        let omScale    = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsScale) ?? d.octaveMeatballsScale
        let omBallDiv  = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsBallDivisor) ?? d.octaveMeatballsBallDivisor
        let omBgR      = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsBackgroundR) ?? d.octaveMeatballsBackgroundR
        let omBgG      = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsBackgroundG) ?? d.octaveMeatballsBackgroundG
        let omBgB      = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsBackgroundB) ?? d.octaveMeatballsBackgroundB
        let omOctPhase = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsOctavePhase) ?? d.octaveMeatballsOctavePhase
        let omShimOct  = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsShimmerOctaveScale) ?? d.octaveMeatballsShimmerOctaveScale
        let omShimTime = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsShimmerTimeScale) ?? d.octaveMeatballsShimmerTimeScale
        let omLifeTime = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsLifeTimeScale) ?? d.octaveMeatballsLifeTimeScale
        let omPulse0   = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsPulseEdge0) ?? d.octaveMeatballsPulseEdge0
        let omPulse1   = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsPulseEdge1) ?? d.octaveMeatballsPulseEdge1
        let omLifeOct  = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsLifeOctaveScale) ?? d.octaveMeatballsLifeOctaveScale
        let omLifeDenB = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsLifeDenomBase) ?? d.octaveMeatballsLifeDenomBase
        let omLifeDenR = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsLifeDenomRadius) ?? d.octaveMeatballsLifeDenomRadius
        let omLifeDenS = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsLifeDenomScale) ?? d.octaveMeatballsLifeDenomScale
        let omDistFlr  = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsDistanceFloor) ?? d.octaveMeatballsDistanceFloor
        let omBallStr  = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsBallStrength) ?? d.octaveMeatballsBallStrength
        let omBallBase = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsBallBase) ?? d.octaveMeatballsBallBase
        let omRedR     = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsRedGlowR) ?? d.octaveMeatballsRedGlowR
        let omRedG     = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsRedGlowG) ?? d.octaveMeatballsRedGlowG
        let omRedB     = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsRedGlowB) ?? d.octaveMeatballsRedGlowB
        let omPalField = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsPaletteFieldGain) ?? d.octaveMeatballsPaletteFieldGain
        let omPalGain  = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsPaletteGain) ?? d.octaveMeatballsPaletteGain
        let omBandPh   = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsBandPhase) ?? d.octaveMeatballsBandPhase
        let omBandBr   = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsBandBrightness) ?? d.octaveMeatballsBandBrightness
        let omEnerBr   = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsEnergyBrightness) ?? d.octaveMeatballsEnergyBrightness
        let omPalEner  = try c.decodeIfPresent(Double.self, forKey: .octaveMeatballsPaletteEnergy) ?? d.octaveMeatballsPaletteEnergy
        let omOctaves  = try c.decodeIfPresent(Int.self, forKey: .octaveMeatballsOctaves) ?? d.octaveMeatballsOctaves
        let llFalloff  = try c.decodeIfPresent(Double.self, forKey: .lavaLampDensityFalloff) ?? d.lavaLampDensityFalloff
        let llBright   = try c.decodeIfPresent(Double.self, forKey: .lavaLampBrightnessResponse) ?? d.lavaLampBrightnessResponse
        let llPalScale = try c.decodeIfPresent(Double.self, forKey: .lavaLampPaletteDensityScale) ?? d.lavaLampPaletteDensityScale
        let llMotion   = try c.decodeIfPresent(Double.self, forKey: .lavaLampMotionSpeed) ?? d.lavaLampMotionSpeed
        let llDrift    = try c.decodeIfPresent(Double.self, forKey: .lavaLampDriftStrength) ?? d.lavaLampDriftStrength
        let llWrap     = try c.decodeIfPresent(Double.self, forKey: .lavaLampWrapBounds) ?? d.lavaLampWrapBounds
        let llShBeat   = try c.decodeIfPresent(Double.self, forKey: .lavaLampShaderBeatBoost) ?? d.lavaLampShaderBeatBoost
        let llCpuBeat  = try c.decodeIfPresent(Double.self, forKey: .lavaLampCpuBeatBoost) ?? d.lavaLampCpuBeatBoost
        let llCpuHalf  = try c.decodeIfPresent(Double.self, forKey: .lavaLampCpuBeatHalfLife) ?? d.lavaLampCpuBeatHalfLife
        let llGrid     = try c.decodeIfPresent(Int.self, forKey: .lavaLampGridSize) ?? d.lavaLampGridSize
        let llBlobs    = try c.decodeIfPresent(Int.self, forKey: .lavaLampBlobCount) ?? d.lavaLampBlobCount
        let voEdge     = try c.decodeIfPresent(Double.self, forKey: .voronoiEdgeSharpness) ?? d.voronoiEdgeSharpness
        let voShBeat   = try c.decodeIfPresent(Double.self, forKey: .voronoiShaderBeatBoost) ?? d.voronoiShaderBeatBoost
        let voSeeds    = try c.decodeIfPresent(Int.self, forKey: .voronoiSeedCount) ?? d.voronoiSeedCount
        let voCycle    = try c.decodeIfPresent(Double.self, forKey: .voronoiCyclePeriod) ?? d.voronoiCyclePeriod
        let voFade     = try c.decodeIfPresent(Double.self, forKey: .voronoiFadeDuration) ?? d.voronoiFadeDuration
        let voDrSpeed  = try c.decodeIfPresent(Double.self, forKey: .voronoiDriftSpeed) ?? d.voronoiDriftSpeed
        let voDrStr    = try c.decodeIfPresent(Double.self, forKey: .voronoiDriftStrength) ?? d.voronoiDriftStrength
        let voSpread   = try c.decodeIfPresent(Double.self, forKey: .voronoiSeedSpread) ?? d.voronoiSeedSpread
        let voTint     = try c.decodeIfPresent(Double.self, forKey: .voronoiTintRange) ?? d.voronoiTintRange
        let voCpuBeat  = try c.decodeIfPresent(Double.self, forKey: .voronoiCpuBeatBoost) ?? d.voronoiCpuBeatBoost
        let voCpuHalf  = try c.decodeIfPresent(Double.self, forKey: .voronoiCpuBeatHalfLife) ?? d.voronoiCpuBeatHalfLife
        let voBlur     = try c.decodeIfPresent(Double.self, forKey: .voronoiSoftBlurSigma) ?? d.voronoiSoftBlurSigma
        let hfGrid     = try c.decodeIfPresent(Int.self, forKey: .heightfieldGridSize) ?? d.heightfieldGridSize
        let hfTilt     = try c.decodeIfPresent(Double.self, forKey: .heightfieldTiltAngle) ?? d.heightfieldTiltAngle
        let hfZScale   = try c.decodeIfPresent(Double.self, forKey: .heightfieldZScale) ?? d.heightfieldZScale
        let hfLineHT   = try c.decodeIfPresent(Double.self, forKey: .heightfieldLineHalfThickness) ?? d.heightfieldLineHalfThickness
        let hfLightX   = try c.decodeIfPresent(Double.self, forKey: .heightfieldLightX) ?? d.heightfieldLightX
        let hfLightY   = try c.decodeIfPresent(Double.self, forKey: .heightfieldLightY) ?? d.heightfieldLightY
        let hfLightZ   = try c.decodeIfPresent(Double.self, forKey: .heightfieldLightZ) ?? d.heightfieldLightZ
        let hfAmbient  = try c.decodeIfPresent(Double.self, forKey: .heightfieldAmbientLight) ?? d.heightfieldAmbientLight
        let hfVFit     = try c.decodeIfPresent(Double.self, forKey: .heightfieldVerticalFit) ?? d.heightfieldVerticalFit
        let hfVCenter  = try c.decodeIfPresent(Double.self, forKey: .heightfieldVerticalCenter) ?? d.heightfieldVerticalCenter
        let hfBeat     = try c.decodeIfPresent(Double.self, forKey: .heightfieldBeatBoost) ?? d.heightfieldBeatBoost
        let hfBeatHL   = try c.decodeIfPresent(Double.self, forKey: .heightfieldBeatHalfLife) ?? d.heightfieldBeatHalfLife
        let hfXExt     = try c.decodeIfPresent(Double.self, forKey: .heightfieldXExtent) ?? d.heightfieldXExtent
        let hfYExt     = try c.decodeIfPresent(Double.self, forKey: .heightfieldYExtent) ?? d.heightfieldYExtent
        let hfOpacity  = try c.decodeIfPresent(Double.self, forKey: .heightfieldOpacity) ?? d.heightfieldOpacity
        let hfFillW = try c.decodeIfPresent(Bool.self, forKey: .heightfieldFillWidth) ?? d.heightfieldFillWidth
        let hfAnchB = try c.decodeIfPresent(Bool.self, forKey: .heightfieldAnchorBottom) ?? d.heightfieldAnchorBottom
        let foMax    = try c.decodeIfPresent(Int.self, forKey: .fountainMaxParticles) ?? d.fountainMaxParticles
        let foRate   = try c.decodeIfPresent(Double.self, forKey: .fountainSpawnRate) ?? d.fountainSpawnRate
        let foFloor  = try c.decodeIfPresent(Double.self, forKey: .fountainSpawnFloor) ?? d.fountainSpawnFloor
        let foUp     = try c.decodeIfPresent(Double.self, forKey: .fountainBaseUp) ?? d.fountainBaseUp
        let foLScale = try c.decodeIfPresent(Double.self, forKey: .fountainLaunchScale) ?? d.fountainLaunchScale
        let foLJit   = try c.decodeIfPresent(Double.self, forKey: .fountainLaunchJitter) ?? d.fountainLaunchJitter
        let foGrav   = try c.decodeIfPresent(Double.self, forKey: .fountainGravity) ?? d.fountainGravity
        let foHJit   = try c.decodeIfPresent(Double.self, forKey: .fountainHorizontalJitter) ?? d.fountainHorizontalJitter
        let foDrag   = try c.decodeIfPresent(Double.self, forKey: .fountainHorizontalDrag) ?? d.fountainHorizontalDrag
        let foLife   = try c.decodeIfPresent(Double.self, forKey: .fountainBaseLifetime) ?? d.fountainBaseLifetime
        let foSize   = try c.decodeIfPresent(Double.self, forKey: .fountainBaseSize) ?? d.fountainBaseSize
        let foBeat   = try c.decodeIfPresent(Double.self, forKey: .fountainBeatLaunchBoost) ?? d.fountainBeatLaunchBoost
        let fwMax    = try c.decodeIfPresent(Int.self, forKey: .fireworksMaxParticles) ?? d.fireworksMaxParticles
        let fwBMax   = try c.decodeIfPresent(Int.self, forKey: .fireworksBurstParticlesMax) ?? d.fireworksBurstParticlesMax
        let fwBMin   = try c.decodeIfPresent(Int.self, forKey: .fireworksBurstParticlesMin) ?? d.fireworksBurstParticlesMin
        let fwSclB   = try c.decodeIfPresent(Double.self, forKey: .fireworksBurstScaleBase) ?? d.fireworksBurstScaleBase
        let fwSclI   = try c.decodeIfPresent(Double.self, forKey: .fireworksBurstScaleIntensity) ?? d.fireworksBurstScaleIntensity
        let fwSpd    = try c.decodeIfPresent(Double.self, forKey: .fireworksBaseSpeed) ?? d.fireworksBaseSpeed
        let fwSprd   = try c.decodeIfPresent(Double.self, forKey: .fireworksSpreadSpeed) ?? d.fireworksSpreadSpeed
        let fwGrav   = try c.decodeIfPresent(Double.self, forKey: .fireworksGravity) ?? d.fireworksGravity
        let fwDrag   = try c.decodeIfPresent(Double.self, forKey: .fireworksDrag) ?? d.fireworksDrag
        let fwLife   = try c.decodeIfPresent(Double.self, forKey: .fireworksBaseLifetime) ?? d.fireworksBaseLifetime
        let fwLJit   = try c.decodeIfPresent(Double.self, forKey: .fireworksLifetimeJitter) ?? d.fireworksLifetimeJitter
        let fwMinL   = try c.decodeIfPresent(Double.self, forKey: .fireworksMinLifetime) ?? d.fireworksMinLifetime
        let fwSize   = try c.decodeIfPresent(Double.self, forKey: .fireworksBaseSize) ?? d.fireworksBaseSize
        let fwHX     = try c.decodeIfPresent(Double.self, forKey: .fireworksBurstHalfX) ?? d.fireworksBurstHalfX
        let fwHY     = try c.decodeIfPresent(Double.self, forKey: .fireworksBurstHalfY) ?? d.fireworksBurstHalfY
        let fwAng    = try c.decodeIfPresent(Double.self, forKey: .fireworksAngleJitter) ?? d.fireworksAngleJitter
        let paMax    = try c.decodeIfPresent(Int.self, forKey: .particlesMaxParticles) ?? d.particlesMaxParticles
        let paIVel   = try c.decodeIfPresent(Double.self, forKey: .particlesInitialVelocityScale) ?? d.particlesInitialVelocityScale
        let paRVel   = try c.decodeIfPresent(Double.self, forKey: .particlesRespawnVelocityScale) ?? d.particlesRespawnVelocityScale
        let paSize   = try c.decodeIfPresent(Double.self, forKey: .particlesBaseSize) ?? d.particlesBaseSize
        let paBri    = try c.decodeIfPresent(Double.self, forKey: .particlesBaseBrightness) ?? d.particlesBaseBrightness
        let paBriJit = try c.decodeIfPresent(Double.self, forKey: .particlesBrightnessJitter) ?? d.particlesBrightnessJitter
        let paBass   = try c.decodeIfPresent(Double.self, forKey: .particlesBassThreshold) ?? d.particlesBassThreshold
        let paDamp   = try c.decodeIfPresent(Double.self, forKey: .particlesVelocityDamping) ?? d.particlesVelocityDamping
        let paLerp   = try c.decodeIfPresent(Double.self, forKey: .particlesReturnLerpRate) ?? d.particlesReturnLerpRate
        let paHalf   = try c.decodeIfPresent(Double.self, forKey: .particlesBeatHalfLife) ?? d.particlesBeatHalfLife
        let paPulse  = try c.decodeIfPresent(Double.self, forKey: .particlesBeatPulseScale) ?? d.particlesBeatPulseScale
        let paImp    = try c.decodeIfPresent(Double.self, forKey: .particlesBassImpulse) ?? d.particlesBassImpulse
        let paBriG   = try c.decodeIfPresent(Double.self, forKey: .particlesBassBrightnessGain) ?? d.particlesBassBrightnessGain
        let paBriCap = try c.decodeIfPresent(Double.self, forKey: .particlesBrightnessCap) ?? d.particlesBrightnessCap
        let paSizeG  = try c.decodeIfPresent(Double.self, forKey: .particlesBassSizeGain) ?? d.particlesBassSizeGain
        let paSizeCap = try c.decodeIfPresent(Double.self, forKey: .particlesSizeCapMultiplier) ?? d.particlesSizeCapMultiplier
        let paBound  = try c.decodeIfPresent(Double.self, forKey: .particlesRespawnOffscreenBound) ?? d.particlesRespawnOffscreenBound
        let paCenter = try c.decodeIfPresent(Double.self, forKey: .particlesRespawnCenterHalfRange) ?? d.particlesRespawnCenterHalfRange
        let paLowPct = try c.decodeIfPresent(Double.self, forKey: .particlesLowBandPercent) ?? d.particlesLowBandPercent
        let sts  = try c.decodeIfPresent(Float.self, forKey: .ribbonTiltSpacing) ?? d.ribbonTiltSpacing
        let sdf  = try c.decodeIfPresent(Float.self, forKey: .ribbonDepthFalloff) ?? d.ribbonDepthFalloff
        let rbSample = try c.decodeIfPresent(Int.self, forKey: .ribbonSampleCount) ?? d.ribbonSampleCount
        let rbSmooth = try c.decodeIfPresent(Double.self, forKey: .ribbonSmoothing) ?? d.ribbonSmoothing
        let rbGain   = try c.decodeIfPresent(Double.self, forKey: .ribbonGain) ?? d.ribbonGain
        let rbHeight = try c.decodeIfPresent(Double.self, forKey: .ribbonHeightScale) ?? d.ribbonHeightScale
        let rbMotion = try c.decodeIfPresent(Double.self, forKey: .ribbonMotionSpeed) ?? d.ribbonMotionSpeed
        let rbBaseF  = try c.decodeIfPresent(Double.self, forKey: .ribbonBaseFrequency) ?? d.ribbonBaseFrequency
        let rbSpread = try c.decodeIfPresent(Double.self, forKey: .ribbonFrequencySpread) ?? d.ribbonFrequencySpread
        let rbPan    = try c.decodeIfPresent(Double.self, forKey: .ribbonStereoPanScale) ?? d.ribbonStereoPanScale
        let rbSwing  = try c.decodeIfPresent(Double.self, forKey: .ribbonPhaseSwing) ?? d.ribbonPhaseSwing
        let rbMaxAmp = try c.decodeIfPresent(Double.self, forKey: .ribbonMaxAmplitude) ?? d.ribbonMaxAmplitude
        let rbAlpha  = try c.decodeIfPresent(Double.self, forKey: .ribbonAlpha) ?? d.ribbonAlpha
        let jpSample = try c.decodeIfPresent(Int.self, forKey: .joyPlotSampleCount) ?? d.joyPlotSampleCount
        let jpSpace  = try c.decodeIfPresent(Double.self, forKey: .joyPlotRowSpacing) ?? d.joyPlotRowSpacing
        let jpHeight = try c.decodeIfPresent(Double.self, forKey: .joyPlotRowHeight) ?? d.joyPlotRowHeight
        let jpBase   = try c.decodeIfPresent(Double.self, forKey: .joyPlotBaselineOffset) ?? d.joyPlotBaselineOffset
        let jpXExt   = try c.decodeIfPresent(Double.self, forKey: .joyPlotXExtent) ?? d.joyPlotXExtent
        let jpHalf   = try c.decodeIfPresent(Double.self, forKey: .joyPlotBeatHalfLife) ?? d.joyPlotBeatHalfLife
        let jpBoost  = try c.decodeIfPresent(Double.self, forKey: .joyPlotBeatBoost) ?? d.joyPlotBeatBoost
        let jpDim    = try c.decodeIfPresent(Double.self, forKey: .joyPlotBottomDim) ?? d.joyPlotBottomDim
        let jpAlpha  = try c.decodeIfPresent(Double.self, forKey: .joyPlotAlpha) ?? d.joyPlotAlpha
        let xyGain   = try c.decodeIfPresent(Double.self, forKey: .xyScopeGain) ?? d.xyScopeGain
        let xySamples = try c.decodeIfPresent(Int.self, forKey: .xyScopeSampleCount) ?? d.xyScopeSampleCount
        let xyThick  = try c.decodeIfPresent(Double.self, forKey: .xyScopeLineHalfThickness) ?? d.xyScopeLineHalfThickness
        let xyRot    = try c.decodeIfPresent(Double.self, forKey: .xyScopeRotationDegrees) ?? d.xyScopeRotationDegrees
        let xyFloor  = try c.decodeIfPresent(Double.self, forKey: .xyScopeColorFloor) ?? d.xyScopeColorFloor
        let xyBoost  = try c.decodeIfPresent(Double.self, forKey: .xyScopeBeatBoost) ?? d.xyScopeBeatBoost
        let xyHalf   = try c.decodeIfPresent(Double.self, forKey: .xyScopeBeatHalfLife) ?? d.xyScopeBeatHalfLife
        let xyAlpha  = try c.decodeIfPresent(Double.self, forKey: .xyScopeAlpha) ?? d.xyScopeAlpha
        let irPetals = try c.decodeIfPresent(Int.self, forKey: .irisPetalCount) ?? d.irisPetalCount
        let irInner  = try c.decodeIfPresent(Double.self, forKey: .irisInnerRadius) ?? d.irisInnerRadius
        let irBase   = try c.decodeIfPresent(Double.self, forKey: .irisBaseLength) ?? d.irisBaseLength
        let irScale  = try c.decodeIfPresent(Double.self, forKey: .irisLengthScale) ?? d.irisLengthScale
        let irWidth  = try c.decodeIfPresent(Double.self, forKey: .irisPetalWidth) ?? d.irisPetalWidth
        let irSwell  = try c.decodeIfPresent(Double.self, forKey: .irisLoudnessSwell) ?? d.irisLoudnessSwell
        let irDim    = try c.decodeIfPresent(Double.self, forKey: .irisInnerDim) ?? d.irisInnerDim
        let irAlpha  = try c.decodeIfPresent(Double.self, forKey: .irisAlpha) ?? d.irisAlpha
        let trRings  = try c.decodeIfPresent(Int.self, forKey: .tricentricRingCount) ?? d.tricentricRingCount
        let trRadius = try c.decodeIfPresent(Double.self, forKey: .tricentricBaseRadius) ?? d.tricentricBaseRadius
        let trFall   = try c.decodeIfPresent(Double.self, forKey: .tricentricRadiusFalloff) ?? d.tricentricRadiusFalloff
        let trFloor  = try c.decodeIfPresent(Double.self, forKey: .tricentricScaleFloor) ?? d.tricentricScaleFloor
        let trRot    = try c.decodeIfPresent(Double.self, forKey: .tricentricRotationSpeed) ?? d.tricentricRotationSpeed
        let trThick  = try c.decodeIfPresent(Double.self, forKey: .tricentricLineThickness) ?? d.tricentricLineThickness
        let trAlpha  = try c.decodeIfPresent(Double.self, forKey: .tricentricAlpha) ?? d.tricentricAlpha
        let muStart  = try c.decodeIfPresent(Int.self, forKey: .musicalStartOctave) ?? d.musicalStartOctave
        let muOct    = try c.decodeIfPresent(Int.self, forKey: .musicalOctaveCount) ?? d.musicalOctaveCount
        let muGap    = try c.decodeIfPresent(Double.self, forKey: .musicalBarGap) ?? d.musicalBarGap
        let muOGap   = try c.decodeIfPresent(Double.self, forKey: .musicalOctaveGap) ?? d.musicalOctaveGap
        let muPCC    = try c.decodeIfPresent(Bool.self, forKey: .musicalPitchClassColoring) ?? d.musicalPitchClassColoring
        let muFloor  = try c.decodeIfPresent(Double.self, forKey: .musicalColorFloor) ?? d.musicalColorFloor
        let muAlpha  = try c.decodeIfPresent(Double.self, forKey: .musicalAlpha) ?? d.musicalAlpha
        let tp   = try c.decodeIfPresent(Float.self, forKey: .trailPersistence) ?? d.trailPersistence
        let usi  = try c.decodeIfPresent(Bool.self, forKey: .useStereoImage) ?? d.useStereoImage
        let fw   = try c.decodeLossyEnum(FFTWindow.self, forKey: .fftWindow, default: d.fftWindow)
        let va   = try c.decodeIfPresent(Float.self, forKey: .vignetteAmount) ?? d.vignetteAmount
        let ob   = try c.decodeIfPresent(Double.self, forKey: .outputBrightness) ?? d.outputBrightness
        let kf   = try c.decodeIfPresent(Int.self, forKey: .kaleidoscopeFolds) ?? d.kaleidoscopeFolds
        let wtm  = try c.decodeLossyEnum(WindowTransparencyMode.self, forKey: .windowTransparencyMode, default: d.windowTransparencyMode)
        let wo   = try c.decodeIfPresent(Float.self, forKey: .windowOpacity) ?? d.windowOpacity
        let ct   = try c.decodeIfPresent(Bool.self, forKey: .clickThroughEnabled) ?? d.clickThroughEnabled
        let bw   = try c.decodeIfPresent(Bool.self, forKey: .borderlessWindow) ?? d.borderlessWindow
        // Migrate the old Bool `windowBorderEnabled` → the new tri-state mode:
        // a saved true meant a permanent frame, so it maps to `.always`; false
        // (or absent) to `.off`. A present `windowBorderMode` wins.
        let wbMode: WindowBorderMode
        if let m = try c.decodeIfPresent(WindowBorderMode.self, forKey: .windowBorderMode) {
            wbMode = m
        } else if let legacy = try c.decodeIfPresent(Bool.self, forKey: .windowBorderEnabled) {
            wbMode = legacy ? .always : .off
        } else {
            wbMode = d.windowBorderMode
        }
        let wbc  = try c.decodeIfPresent(RGBAColor.self, forKey: .windowBorderColor) ?? d.windowBorderColor
        let wbo  = try c.decodeIfPresent(Float.self, forKey: .windowBorderOpacity) ?? d.windowBorderOpacity
        let wbw  = try c.decodeIfPresent(Float.self, forKey: .windowBorderWidth) ?? d.windowBorderWidth
        let mcm  = try c.decodeLossyEnum(MouseControlModifier.self, forKey: .mouseControlModifier, default: d.mouseControlModifier)
        let cbl  = try c.decodeIfPresent(Bool.self, forKey: .centerBelowLyrics) ?? d.centerBelowLyrics
        // Legacy (0.11-0.13) app-wide position offset. Not encoded any more; when
        // present it seeds every profile that carries no offset of its own, so an
        // upgrade does not move anyone's picture.
        let legacyOffsetX = try c.decodeIfPresent(Float.self, forKey: .positionOffsetX)
        let legacyOffsetY = try c.decodeIfPresent(Float.self, forKey: .positionOffsetY)
        func seedOffset(_ p: StyleProfile, for style: VisualizerStyle,
                        hasX: Bool, hasY: Bool) -> StyleProfile {
            var p = p
            let def = StyleProfile.defaults(for: style)
            if !hasX { p.positionOffsetX = legacyOffsetX ?? def.positionOffsetX }
            if !hasY { p.positionOffsetY = legacyOffsetY ?? def.positionOffsetY }
            return p
        }
        // Track overlay + always-on-top + frame rate: now app-wide. These same
        // top-level keys also carry the pre-per-style (legacy flat) values, so a
        // flat settings.json migrates straight into the global fields here.
        let ove  = try c.decodeIfPresent(Bool.self, forKey: .overlayEnabled) ?? d.overlayEnabled
        let ovp  = try c.decodeLossyEnum(OverlayCorner.self, forKey: .overlayPosition, default: d.overlayPosition)
        let ovo  = try c.decodeIfPresent(Float.self, forKey: .overlayOpacity) ?? d.overlayOpacity
        let aot  = try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? d.alwaysOnTop
        let tfps = try c.decodeIfPresent(Int.self, forKey: .targetFPS) ?? d.targetFPS
        let pcEnabled  = try c.decodeIfPresent(Bool.self, forKey: .paletteCycleEnabled) ?? d.paletteCycleEnabled
        let pcInterval = try c.decodeIfPresent(Double.self, forKey: .paletteCycleInterval) ?? d.paletteCycleInterval
        let pcFade     = try c.decodeIfPresent(Double.self, forKey: .paletteCycleFadeDuration) ?? d.paletteCycleFadeDuration
        let lyrics     = try c.decodeIfPresent(LyricsSettings.self, forKey: .lyrics) ?? d.lyrics

        var profiles: [VisualizerStyle: StyleProfile]
        // Tri-wing Spinner migration inputs: whether the file carried a profile for it, and whether the Spinner's
        // profile (the old home of the Model choice) selected the Tri-wing.
        var presentStyles: Set<VisualizerStyle> = []
        if c.contains(.profiles), !(try c.decodeNil(forKey: .profiles)) {
            // New format. The enum-keyed dictionary persists as a flat
            // [key, value, key, value, ...] JSON array. PER-ENTRY problems
            // decode LOSSILY: start from defaults so any missing style is
            // populated, keep every well-formed entry, ignore unknown style
            // keys (e.g. from a newer app version), and leave a malformed
            // entry at its default — one bad pair must never throw away all
            // per-style settings. STRUCTURAL corruption of the container
            // itself (not an array at all) throws, so load() takes the
            // corrupt-file backup path instead of silently defaulting and
            // letting the next save overwrite the evidence.
            var merged: [VisualizerStyle: StyleProfile] = [:]
            for s in VisualizerStyle.allCases {
                merged[s] = seedOffset(.defaults, for: s, hasX: false, hasY: false)
            }
            var nested = try c.nestedUnkeyedContainer(forKey: .profiles)
            while !nested.isAtEnd {
                guard let rawKey = try? nested.decode(String.self) else {
                    // Key slot isn't a string: consume it and resync.
                    if (try? nested.decode(JSONFragment.self)) == nil { break }
                    continue
                }
                if nested.isAtEnd { break } // odd-length array; dangling key
                if let env = try? nested.decode(ProfileWithOffsetPresence.self) {
                    if let style = VisualizerStyle(rawValue: rawKey) {
                        merged[style] = seedOffset(env.profile, for: style,
                                                   hasX: env.presence.x, hasY: env.presence.y)
                        presentStyles.insert(style)
                    }
                } else if (try? nested.decode(JSONFragment.self)) == nil {
                    break // value unconsumable; stop rather than spin
                }
            }
            profiles = merged
        } else {
            // Migration: build one profile per style from the old flat fields.
            let dp = StyleProfile.defaults
            let migrated = StyleProfile(
                paletteName: try c.decodeIfPresent(String.self, forKey: .paletteName) ?? dp.paletteName,
                customStops: try c.decodeIfPresent([RGBAColor].self, forKey: .customStops) ?? dp.customStops,
                gain: try c.decodeIfPresent(Float.self, forKey: .gain) ?? dp.gain,
                // Clamp to >= 1 (same guard as StyleProfile's decoder, which this
                // memberwise-init migration path bypasses): BandMapper preconditions
                // bandCount > 0.
                barCount: max(1, try c.decodeIfPresent(Int.self, forKey: .barCount) ?? dp.barCount),
                smoothing: try c.decodeIfPresent(Float.self, forKey: .smoothing) ?? dp.smoothing,
                peakHoldEnabled: try c.decodeIfPresent(Bool.self, forKey: .peakHoldEnabled) ?? dp.peakHoldEnabled,
                glowEnabled: try c.decodeIfPresent(Bool.self, forKey: .glowEnabled) ?? dp.glowEnabled,
                glowIntensity: try c.decodeIfPresent(Float.self, forKey: .glowIntensity) ?? dp.glowIntensity,
                fullscreenDisplayID: try c.decodeIfPresent(UInt32.self, forKey: .fullscreenDisplayID) ?? dp.fullscreenDisplayID,
                backgroundStyle: try c.decodeLossyEnum(BackgroundStyle.self, forKey: .backgroundStyle, default: dp.backgroundStyle)
            )
            var fresh: [VisualizerStyle: StyleProfile] = [:]
            for s in VisualizerStyle.allCases {
                fresh[s] = seedOffset(migrated, for: s, hasX: false, hasY: false)
            }
            profiles = fresh
        }

        // The Spinner became two styles. A file with no profile for the Tri-wing Spinner gets a COPY of the Spinner's
        // profile (palette, offsets, Enabled, every Spinner setting), and when it was showing the Spinner with the
        // old Model choice on Tri-wing, the Tri-wing Spinner becomes the active style. A file that already has the
        // profile is left alone. Either way the stored `model` field is pinned to what each style draws.
        var resolvedStyle: VisualizerStyle = style
        if !presentStyles.contains(.triWingSpinner) {
            let source: StyleProfile = profiles[.spinner] ?? StyleProfile.defaults(for: .spinner)
            if style == .spinner && source.spinner.model == .triWing { resolvedStyle = .triWingSpinner }
            profiles[.triWingSpinner] = source
        }
        profiles[.spinner]?.spinner.model = .disc
        profiles[.triWingSpinner]?.spinner.model = .triWing

        self.init(
            visualizerStyle: resolvedStyle,
            profiles: profiles,
            demoModeEnabled: dme,
            ribbonWaveCount: swc,
            particleSize: ps,
            particleSpeed: psp,
            barGap: bg,
            oscilloscopeThickness: ot,
            polartoneRadius: pr,
            polartoneAmplitude: pa,
            polartoneColorFloor: pcf,
            polartoneRotationSpeed: prs,
            polartonePointCount: ppc,
            polartonePhaseOffset: ppo,
            polartoneLineHalfThickness: plht,
            polartoneWaveformClamp: pwc,
            polartoneRenderMode: prm,
            polartoneInnerThreshold: pit,
            polartoneDriftRevolutions: pdr,
            polartoneStartDirection: psd,
            starNestZoom: snz,
            starNestSpeed: sns,
            starNestFormuparam: snf,
            starNestTile: snt,
            starNestStepsize: snss,
            starNestBrightness: snb,
            starNestDarkmatter: snd,
            starNestDistfading: sndf,
            starNestSaturation: snsa,
            starNestVolsteps: snvs,
            starNestIterations: sni,
            wireframeBaseRadius: wbr,
            wireframeDisplaceScale: wds,
            wireframeLineThickness: wlt,
            wireframeRotationSpeed: wrs,
            wireframeTiltX: wtx,
            wireframeLineOpacity: wlo,
            wireframeSubdivisions: wsub,
            wireframeXExtent: wxe,
            wireframeYExtent: wye,
            wireframeVerticalCenter: wvc,
            wireframeFillWidth: wfWidth,
            wireframeAnchorBottom: wfBottom,
            outrunHorizon: orHorizon,
            outrunHorizonGlowScale: orHGScale,
            outrunHorizonGlowBase: orHGBase,
            outrunHorizonBassGlow: orHBGlow,
            outrunLowMidBackdrop: orLMBack,
            outrunBackgroundBrightness: orBgBright,
            outrunBackgroundGlow: orBgGlow,
            outrunLeanBase: orLeanB,
            outrunLeanLowMid: orLeanLM,
            outrunFallBase: orFallB,
            outrunFallBass: orFallBass,
            outrunFallEnergy: orFallEn,
            outrunDensity: orDens,
            outrunLayer0ColumnScale: orL0Col,
            outrunLayer0FallScale: orL0Fall,
            outrunLayer0Seed: orL0Seed,
            outrunLayer0Thickness: orL0Thick,
            outrunLayer0Weight: orL0Wt,
            outrunLayer1ColumnScale: orL1Col,
            outrunLayer1FallScale: orL1Fall,
            outrunLayer1Seed: orL1Seed,
            outrunLayer1Thickness: orL1Thick,
            outrunLayer1Weight: orL1Wt,
            outrunLayer2ColumnScale: orL2Col,
            outrunLayer2FallScale: orL2Fall,
            outrunLayer2Seed: orL2Seed,
            outrunLayer2Thickness: orL2Thick,
            outrunLayer2Weight: orL2Wt,
            outrunSparkleColumnScale: orSpCol,
            outrunSparkleFallScale: orSpFall,
            outrunSparkleSeed: orSpSeed,
            outrunSparkleThickness: orSpThick,
            outrunSparkleBase: orSpBase,
            outrunSparkleTreble: orSpTreb,
            outrunRainVerticalBase: orRVBase,
            outrunRainVerticalY: orRVY,
            outrunRainColorBase: orRCBase,
            outrunRainColorTreble: orRCTreb,
            outrunRainColorEnergy: orRCEn,
            outrunRainBrightnessBase: orRBBase,
            outrunRainBrightnessEnergy: orRBEn,
            outrunRainBrightnessTreble: orRBTreb,
            outrunReflectionWidth: orRefW,
            outrunReflectionBass: orRefBass,
            plasmaCoordinateScale: plCoordSc,
            plasmaCoordinateOffset: plCoordOff,
            plasmaXFrequency: plXFreq,
            plasmaYFrequency: plYFreq,
            plasmaDiagonalFrequency: plDiagFreq,
            plasmaXTimeScale: plXTime,
            plasmaYTimeScale: plYTime,
            plasmaDiagonalTimeScale: plDiagTime,
            plasmaWaveDivisor: plWaveDiv,
            plasmaContrast: plContrast,
            plasmaBrightnessBias: plBright,
            plasmaEnergyResponse: plEnergy,
            plasmaClampMin: plClampMin,
            plasmaClampMax: plClampMax,
            plasmaAlpha: plAlpha,
            bumpscopeUvClampMin: bsUvMin,
            bumpscopeUvClampMax: bsUvMax,
            bumpscopeNeighborRadius: bsRadius,
            bumpscopeSlopeScale: bsSlope,
            bumpscopeSurfaceNormalY: bsNormalY,
            bumpscopeSurfaceNormalZ: bsNormalZ,
            bumpscopeLightX: bsLightX,
            bumpscopeLightY: bsLightY,
            bumpscopeLightZ: bsLightZ,
            bumpscopeDiffuseFloor: bsDiffuse,
            bumpscopeBandGain: bsGain,
            bumpscopeIntensityBias: bsBias,
            bumpscopeIntensityClampMin: bsIntMin,
            bumpscopeIntensityClampMax: bsIntMax,
            bumpscopeAlpha: bsAlpha,
            octaveMeatballsScale: omScale,
            octaveMeatballsBallDivisor: omBallDiv,
            octaveMeatballsBackgroundR: omBgR,
            octaveMeatballsBackgroundG: omBgG,
            octaveMeatballsBackgroundB: omBgB,
            octaveMeatballsOctavePhase: omOctPhase,
            octaveMeatballsShimmerOctaveScale: omShimOct,
            octaveMeatballsShimmerTimeScale: omShimTime,
            octaveMeatballsLifeTimeScale: omLifeTime,
            octaveMeatballsPulseEdge0: omPulse0,
            octaveMeatballsPulseEdge1: omPulse1,
            octaveMeatballsLifeOctaveScale: omLifeOct,
            octaveMeatballsLifeDenomBase: omLifeDenB,
            octaveMeatballsLifeDenomRadius: omLifeDenR,
            octaveMeatballsLifeDenomScale: omLifeDenS,
            octaveMeatballsDistanceFloor: omDistFlr,
            octaveMeatballsBallStrength: omBallStr,
            octaveMeatballsBallBase: omBallBase,
            octaveMeatballsRedGlowR: omRedR,
            octaveMeatballsRedGlowG: omRedG,
            octaveMeatballsRedGlowB: omRedB,
            octaveMeatballsPaletteFieldGain: omPalField,
            octaveMeatballsPaletteGain: omPalGain,
            octaveMeatballsBandPhase: omBandPh,
            octaveMeatballsBandBrightness: omBandBr,
            octaveMeatballsEnergyBrightness: omEnerBr,
            octaveMeatballsPaletteEnergy: omPalEner,
            octaveMeatballsOctaves: omOctaves,
            lavaLampDensityFalloff: llFalloff,
            lavaLampBrightnessResponse: llBright,
            lavaLampPaletteDensityScale: llPalScale,
            lavaLampMotionSpeed: llMotion,
            lavaLampDriftStrength: llDrift,
            lavaLampWrapBounds: llWrap,
            lavaLampShaderBeatBoost: llShBeat,
            lavaLampCpuBeatBoost: llCpuBeat,
            lavaLampCpuBeatHalfLife: llCpuHalf,
            lavaLampGridSize: llGrid,
            lavaLampBlobCount: llBlobs,
            voronoiEdgeSharpness: voEdge,
            voronoiShaderBeatBoost: voShBeat,
            voronoiSeedCount: voSeeds,
            voronoiCyclePeriod: voCycle,
            voronoiFadeDuration: voFade,
            voronoiDriftSpeed: voDrSpeed,
            voronoiDriftStrength: voDrStr,
            voronoiSeedSpread: voSpread,
            voronoiTintRange: voTint,
            voronoiCpuBeatBoost: voCpuBeat,
            voronoiCpuBeatHalfLife: voCpuHalf,
            voronoiSoftBlurSigma: voBlur,
            heightfieldGridSize: hfGrid,
            heightfieldTiltAngle: hfTilt,
            heightfieldZScale: hfZScale,
            heightfieldLineHalfThickness: hfLineHT,
            heightfieldLightX: hfLightX,
            heightfieldLightY: hfLightY,
            heightfieldLightZ: hfLightZ,
            heightfieldAmbientLight: hfAmbient,
            heightfieldVerticalFit: hfVFit,
            heightfieldVerticalCenter: hfVCenter,
            heightfieldBeatBoost: hfBeat,
            heightfieldBeatHalfLife: hfBeatHL,
            heightfieldXExtent: hfXExt,
            heightfieldYExtent: hfYExt,
            heightfieldOpacity: hfOpacity,
            heightfieldFillWidth: hfFillW,
            heightfieldAnchorBottom: hfAnchB,
            fountainMaxParticles: foMax,
            fountainSpawnRate: foRate,
            fountainSpawnFloor: foFloor,
            fountainBaseUp: foUp,
            fountainLaunchScale: foLScale,
            fountainLaunchJitter: foLJit,
            fountainGravity: foGrav,
            fountainHorizontalJitter: foHJit,
            fountainHorizontalDrag: foDrag,
            fountainBaseLifetime: foLife,
            fountainBaseSize: foSize,
            fountainBeatLaunchBoost: foBeat,
            fireworksMaxParticles: fwMax,
            fireworksBurstParticlesMax: fwBMax,
            fireworksBurstParticlesMin: fwBMin,
            fireworksBurstScaleBase: fwSclB,
            fireworksBurstScaleIntensity: fwSclI,
            fireworksBaseSpeed: fwSpd,
            fireworksSpreadSpeed: fwSprd,
            fireworksGravity: fwGrav,
            fireworksDrag: fwDrag,
            fireworksBaseLifetime: fwLife,
            fireworksLifetimeJitter: fwLJit,
            fireworksMinLifetime: fwMinL,
            fireworksBaseSize: fwSize,
            fireworksBurstHalfX: fwHX,
            fireworksBurstHalfY: fwHY,
            fireworksAngleJitter: fwAng,
            particlesMaxParticles: paMax,
            particlesInitialVelocityScale: paIVel,
            particlesRespawnVelocityScale: paRVel,
            particlesBaseSize: paSize,
            particlesBaseBrightness: paBri,
            particlesBrightnessJitter: paBriJit,
            particlesBassThreshold: paBass,
            particlesVelocityDamping: paDamp,
            particlesReturnLerpRate: paLerp,
            particlesBeatHalfLife: paHalf,
            particlesBeatPulseScale: paPulse,
            particlesBassImpulse: paImp,
            particlesBassBrightnessGain: paBriG,
            particlesBrightnessCap: paBriCap,
            particlesBassSizeGain: paSizeG,
            particlesSizeCapMultiplier: paSizeCap,
            particlesRespawnOffscreenBound: paBound,
            particlesRespawnCenterHalfRange: paCenter,
            particlesLowBandPercent: paLowPct,
            ribbonTiltSpacing: sts,
            ribbonDepthFalloff: sdf,
            ribbonSampleCount: rbSample,
            ribbonSmoothing: rbSmooth,
            ribbonGain: rbGain,
            ribbonHeightScale: rbHeight,
            ribbonMotionSpeed: rbMotion,
            ribbonBaseFrequency: rbBaseF,
            ribbonFrequencySpread: rbSpread,
            ribbonStereoPanScale: rbPan,
            ribbonPhaseSwing: rbSwing,
            ribbonMaxAmplitude: rbMaxAmp,
            ribbonAlpha: rbAlpha,
            joyPlotSampleCount: jpSample,
            joyPlotRowSpacing: jpSpace,
            joyPlotRowHeight: jpHeight,
            joyPlotBaselineOffset: jpBase,
            joyPlotXExtent: jpXExt,
            joyPlotBeatHalfLife: jpHalf,
            joyPlotBeatBoost: jpBoost,
            joyPlotBottomDim: jpDim,
            joyPlotAlpha: jpAlpha,
            xyScopeGain: xyGain,
            xyScopeSampleCount: xySamples,
            xyScopeLineHalfThickness: xyThick,
            xyScopeRotationDegrees: xyRot,
            xyScopeColorFloor: xyFloor,
            xyScopeBeatBoost: xyBoost,
            xyScopeBeatHalfLife: xyHalf,
            xyScopeAlpha: xyAlpha,
            irisPetalCount: irPetals,
            irisInnerRadius: irInner,
            irisBaseLength: irBase,
            irisLengthScale: irScale,
            irisPetalWidth: irWidth,
            irisLoudnessSwell: irSwell,
            irisInnerDim: irDim,
            irisAlpha: irAlpha,
            tricentricRingCount: trRings,
            tricentricBaseRadius: trRadius,
            tricentricRadiusFalloff: trFall,
            tricentricScaleFloor: trFloor,
            tricentricRotationSpeed: trRot,
            tricentricLineThickness: trThick,
            tricentricAlpha: trAlpha,
            musicalStartOctave: muStart,
            musicalOctaveCount: muOct,
            musicalBarGap: muGap,
            musicalOctaveGap: muOGap,
            musicalPitchClassColoring: muPCC,
            musicalColorFloor: muFloor,
            musicalAlpha: muAlpha,
            trailPersistence: tp,
            useStereoImage: usi,
            fftWindow: fw,
            vignetteAmount: va,
            outputBrightness: ob,
            kaleidoscopeFolds: kf,
            windowTransparencyMode: wtm,
            windowOpacity: wo,
            clickThroughEnabled: ct,
            borderlessWindow: bw,
            windowBorderMode: wbMode,
            windowBorderColor: wbc,
            windowBorderOpacity: wbo,
            windowBorderWidth: wbw,
            mouseControlModifier: mcm,
            centerBelowLyrics: cbl,
            overlayEnabled: ove,
            overlayPosition: ovp,
            overlayOpacity: ovo,
            alwaysOnTop: aot,
            targetFPS: tfps,
            paletteCycleEnabled: pcEnabled,
            paletteCycleInterval: pcInterval,
            paletteCycleFadeDuration: pcFade,
            lyrics: lyrics
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(visualizerStyle, forKey: .visualizerStyle)
        try c.encode(profiles, forKey: .profiles)
        try c.encode(demoModeEnabled, forKey: .demoModeEnabled)
        try c.encode(ribbonWaveCount, forKey: .ribbonWaveCount)
        try c.encode(particleSize, forKey: .particleSize)
        try c.encode(particleSpeed, forKey: .particleSpeed)
        try c.encode(barGap, forKey: .barGap)
        try c.encode(oscilloscopeThickness, forKey: .oscilloscopeThickness)
        try c.encode(polartoneRadius, forKey: .polartoneRadius)
        try c.encode(polartoneAmplitude, forKey: .polartoneAmplitude)
        try c.encode(polartoneColorFloor, forKey: .polartoneColorFloor)
        try c.encode(polartoneRotationSpeed, forKey: .polartoneRotationSpeed)
        try c.encode(polartonePointCount, forKey: .polartonePointCount)
        try c.encode(polartonePhaseOffset, forKey: .polartonePhaseOffset)
        try c.encode(polartoneLineHalfThickness, forKey: .polartoneLineHalfThickness)
        try c.encode(polartoneWaveformClamp, forKey: .polartoneWaveformClamp)
        try c.encode(polartoneRenderMode, forKey: .polartoneRenderMode)
        try c.encode(polartoneInnerThreshold, forKey: .polartoneInnerThreshold)
        try c.encode(polartoneDriftRevolutions, forKey: .polartoneDriftRevolutions)
        try c.encode(polartoneStartDirection, forKey: .polartoneStartDirection)
        try c.encode(starNestZoom, forKey: .starNestZoom)
        try c.encode(starNestSpeed, forKey: .starNestSpeed)
        try c.encode(starNestFormuparam, forKey: .starNestFormuparam)
        try c.encode(starNestTile, forKey: .starNestTile)
        try c.encode(starNestStepsize, forKey: .starNestStepsize)
        try c.encode(starNestBrightness, forKey: .starNestBrightness)
        try c.encode(starNestDarkmatter, forKey: .starNestDarkmatter)
        try c.encode(starNestDistfading, forKey: .starNestDistfading)
        try c.encode(starNestSaturation, forKey: .starNestSaturation)
        try c.encode(starNestVolsteps, forKey: .starNestVolsteps)
        try c.encode(starNestIterations, forKey: .starNestIterations)
        try c.encode(wireframeBaseRadius, forKey: .wireframeBaseRadius)
        try c.encode(wireframeDisplaceScale, forKey: .wireframeDisplaceScale)
        try c.encode(wireframeLineThickness, forKey: .wireframeLineThickness)
        try c.encode(wireframeRotationSpeed, forKey: .wireframeRotationSpeed)
        try c.encode(wireframeTiltX, forKey: .wireframeTiltX)
        try c.encode(wireframeLineOpacity, forKey: .wireframeLineOpacity)
        try c.encode(wireframeSubdivisions, forKey: .wireframeSubdivisions)
        try c.encode(wireframeXExtent, forKey: .wireframeXExtent)
        try c.encode(wireframeYExtent, forKey: .wireframeYExtent)
        try c.encode(wireframeVerticalCenter, forKey: .wireframeVerticalCenter)
        try c.encode(wireframeFillWidth, forKey: .wireframeFillWidth)
        try c.encode(wireframeAnchorBottom, forKey: .wireframeAnchorBottom)
        try c.encode(outrunHorizon, forKey: .outrunHorizon)
        try c.encode(outrunHorizonGlowScale, forKey: .outrunHorizonGlowScale)
        try c.encode(outrunHorizonGlowBase, forKey: .outrunHorizonGlowBase)
        try c.encode(outrunHorizonBassGlow, forKey: .outrunHorizonBassGlow)
        try c.encode(outrunLowMidBackdrop, forKey: .outrunLowMidBackdrop)
        try c.encode(outrunBackgroundBrightness, forKey: .outrunBackgroundBrightness)
        try c.encode(outrunBackgroundGlow, forKey: .outrunBackgroundGlow)
        try c.encode(outrunLeanBase, forKey: .outrunLeanBase)
        try c.encode(outrunLeanLowMid, forKey: .outrunLeanLowMid)
        try c.encode(outrunFallBase, forKey: .outrunFallBase)
        try c.encode(outrunFallBass, forKey: .outrunFallBass)
        try c.encode(outrunFallEnergy, forKey: .outrunFallEnergy)
        try c.encode(outrunDensity, forKey: .outrunDensity)
        try c.encode(outrunLayer0ColumnScale, forKey: .outrunLayer0ColumnScale)
        try c.encode(outrunLayer0FallScale, forKey: .outrunLayer0FallScale)
        try c.encode(outrunLayer0Seed, forKey: .outrunLayer0Seed)
        try c.encode(outrunLayer0Thickness, forKey: .outrunLayer0Thickness)
        try c.encode(outrunLayer0Weight, forKey: .outrunLayer0Weight)
        try c.encode(outrunLayer1ColumnScale, forKey: .outrunLayer1ColumnScale)
        try c.encode(outrunLayer1FallScale, forKey: .outrunLayer1FallScale)
        try c.encode(outrunLayer1Seed, forKey: .outrunLayer1Seed)
        try c.encode(outrunLayer1Thickness, forKey: .outrunLayer1Thickness)
        try c.encode(outrunLayer1Weight, forKey: .outrunLayer1Weight)
        try c.encode(outrunLayer2ColumnScale, forKey: .outrunLayer2ColumnScale)
        try c.encode(outrunLayer2FallScale, forKey: .outrunLayer2FallScale)
        try c.encode(outrunLayer2Seed, forKey: .outrunLayer2Seed)
        try c.encode(outrunLayer2Thickness, forKey: .outrunLayer2Thickness)
        try c.encode(outrunLayer2Weight, forKey: .outrunLayer2Weight)
        try c.encode(outrunSparkleColumnScale, forKey: .outrunSparkleColumnScale)
        try c.encode(outrunSparkleFallScale, forKey: .outrunSparkleFallScale)
        try c.encode(outrunSparkleSeed, forKey: .outrunSparkleSeed)
        try c.encode(outrunSparkleThickness, forKey: .outrunSparkleThickness)
        try c.encode(outrunSparkleBase, forKey: .outrunSparkleBase)
        try c.encode(outrunSparkleTreble, forKey: .outrunSparkleTreble)
        try c.encode(outrunRainVerticalBase, forKey: .outrunRainVerticalBase)
        try c.encode(outrunRainVerticalY, forKey: .outrunRainVerticalY)
        try c.encode(outrunRainColorBase, forKey: .outrunRainColorBase)
        try c.encode(outrunRainColorTreble, forKey: .outrunRainColorTreble)
        try c.encode(outrunRainColorEnergy, forKey: .outrunRainColorEnergy)
        try c.encode(outrunRainBrightnessBase, forKey: .outrunRainBrightnessBase)
        try c.encode(outrunRainBrightnessEnergy, forKey: .outrunRainBrightnessEnergy)
        try c.encode(outrunRainBrightnessTreble, forKey: .outrunRainBrightnessTreble)
        try c.encode(outrunReflectionWidth, forKey: .outrunReflectionWidth)
        try c.encode(outrunReflectionBass, forKey: .outrunReflectionBass)
        try c.encode(plasmaCoordinateScale, forKey: .plasmaCoordinateScale)
        try c.encode(plasmaCoordinateOffset, forKey: .plasmaCoordinateOffset)
        try c.encode(plasmaXFrequency, forKey: .plasmaXFrequency)
        try c.encode(plasmaYFrequency, forKey: .plasmaYFrequency)
        try c.encode(plasmaDiagonalFrequency, forKey: .plasmaDiagonalFrequency)
        try c.encode(plasmaXTimeScale, forKey: .plasmaXTimeScale)
        try c.encode(plasmaYTimeScale, forKey: .plasmaYTimeScale)
        try c.encode(plasmaDiagonalTimeScale, forKey: .plasmaDiagonalTimeScale)
        try c.encode(plasmaWaveDivisor, forKey: .plasmaWaveDivisor)
        try c.encode(plasmaContrast, forKey: .plasmaContrast)
        try c.encode(plasmaBrightnessBias, forKey: .plasmaBrightnessBias)
        try c.encode(plasmaEnergyResponse, forKey: .plasmaEnergyResponse)
        try c.encode(plasmaClampMin, forKey: .plasmaClampMin)
        try c.encode(plasmaClampMax, forKey: .plasmaClampMax)
        try c.encode(plasmaAlpha, forKey: .plasmaAlpha)
        try c.encode(bumpscopeUvClampMin, forKey: .bumpscopeUvClampMin)
        try c.encode(bumpscopeUvClampMax, forKey: .bumpscopeUvClampMax)
        try c.encode(bumpscopeNeighborRadius, forKey: .bumpscopeNeighborRadius)
        try c.encode(bumpscopeSlopeScale, forKey: .bumpscopeSlopeScale)
        try c.encode(bumpscopeSurfaceNormalY, forKey: .bumpscopeSurfaceNormalY)
        try c.encode(bumpscopeSurfaceNormalZ, forKey: .bumpscopeSurfaceNormalZ)
        try c.encode(bumpscopeLightX, forKey: .bumpscopeLightX)
        try c.encode(bumpscopeLightY, forKey: .bumpscopeLightY)
        try c.encode(bumpscopeLightZ, forKey: .bumpscopeLightZ)
        try c.encode(bumpscopeDiffuseFloor, forKey: .bumpscopeDiffuseFloor)
        try c.encode(bumpscopeBandGain, forKey: .bumpscopeBandGain)
        try c.encode(bumpscopeIntensityBias, forKey: .bumpscopeIntensityBias)
        try c.encode(bumpscopeIntensityClampMin, forKey: .bumpscopeIntensityClampMin)
        try c.encode(bumpscopeIntensityClampMax, forKey: .bumpscopeIntensityClampMax)
        try c.encode(bumpscopeAlpha, forKey: .bumpscopeAlpha)
        try c.encode(octaveMeatballsScale, forKey: .octaveMeatballsScale)
        try c.encode(octaveMeatballsBallDivisor, forKey: .octaveMeatballsBallDivisor)
        try c.encode(octaveMeatballsBackgroundR, forKey: .octaveMeatballsBackgroundR)
        try c.encode(octaveMeatballsBackgroundG, forKey: .octaveMeatballsBackgroundG)
        try c.encode(octaveMeatballsBackgroundB, forKey: .octaveMeatballsBackgroundB)
        try c.encode(octaveMeatballsOctavePhase, forKey: .octaveMeatballsOctavePhase)
        try c.encode(octaveMeatballsShimmerOctaveScale, forKey: .octaveMeatballsShimmerOctaveScale)
        try c.encode(octaveMeatballsShimmerTimeScale, forKey: .octaveMeatballsShimmerTimeScale)
        try c.encode(octaveMeatballsLifeTimeScale, forKey: .octaveMeatballsLifeTimeScale)
        try c.encode(octaveMeatballsPulseEdge0, forKey: .octaveMeatballsPulseEdge0)
        try c.encode(octaveMeatballsPulseEdge1, forKey: .octaveMeatballsPulseEdge1)
        try c.encode(octaveMeatballsLifeOctaveScale, forKey: .octaveMeatballsLifeOctaveScale)
        try c.encode(octaveMeatballsLifeDenomBase, forKey: .octaveMeatballsLifeDenomBase)
        try c.encode(octaveMeatballsLifeDenomRadius, forKey: .octaveMeatballsLifeDenomRadius)
        try c.encode(octaveMeatballsLifeDenomScale, forKey: .octaveMeatballsLifeDenomScale)
        try c.encode(octaveMeatballsDistanceFloor, forKey: .octaveMeatballsDistanceFloor)
        try c.encode(octaveMeatballsBallStrength, forKey: .octaveMeatballsBallStrength)
        try c.encode(octaveMeatballsBallBase, forKey: .octaveMeatballsBallBase)
        try c.encode(octaveMeatballsRedGlowR, forKey: .octaveMeatballsRedGlowR)
        try c.encode(octaveMeatballsRedGlowG, forKey: .octaveMeatballsRedGlowG)
        try c.encode(octaveMeatballsRedGlowB, forKey: .octaveMeatballsRedGlowB)
        try c.encode(octaveMeatballsPaletteFieldGain, forKey: .octaveMeatballsPaletteFieldGain)
        try c.encode(octaveMeatballsPaletteGain, forKey: .octaveMeatballsPaletteGain)
        try c.encode(octaveMeatballsBandPhase, forKey: .octaveMeatballsBandPhase)
        try c.encode(octaveMeatballsBandBrightness, forKey: .octaveMeatballsBandBrightness)
        try c.encode(octaveMeatballsEnergyBrightness, forKey: .octaveMeatballsEnergyBrightness)
        try c.encode(octaveMeatballsPaletteEnergy, forKey: .octaveMeatballsPaletteEnergy)
        try c.encode(octaveMeatballsOctaves, forKey: .octaveMeatballsOctaves)
        try c.encode(lavaLampDensityFalloff, forKey: .lavaLampDensityFalloff)
        try c.encode(lavaLampBrightnessResponse, forKey: .lavaLampBrightnessResponse)
        try c.encode(lavaLampPaletteDensityScale, forKey: .lavaLampPaletteDensityScale)
        try c.encode(lavaLampMotionSpeed, forKey: .lavaLampMotionSpeed)
        try c.encode(lavaLampDriftStrength, forKey: .lavaLampDriftStrength)
        try c.encode(lavaLampWrapBounds, forKey: .lavaLampWrapBounds)
        try c.encode(lavaLampShaderBeatBoost, forKey: .lavaLampShaderBeatBoost)
        try c.encode(lavaLampCpuBeatBoost, forKey: .lavaLampCpuBeatBoost)
        try c.encode(lavaLampCpuBeatHalfLife, forKey: .lavaLampCpuBeatHalfLife)
        try c.encode(lavaLampGridSize, forKey: .lavaLampGridSize)
        try c.encode(lavaLampBlobCount, forKey: .lavaLampBlobCount)
        try c.encode(voronoiEdgeSharpness, forKey: .voronoiEdgeSharpness)
        try c.encode(voronoiShaderBeatBoost, forKey: .voronoiShaderBeatBoost)
        try c.encode(voronoiSeedCount, forKey: .voronoiSeedCount)
        try c.encode(voronoiCyclePeriod, forKey: .voronoiCyclePeriod)
        try c.encode(voronoiFadeDuration, forKey: .voronoiFadeDuration)
        try c.encode(voronoiDriftSpeed, forKey: .voronoiDriftSpeed)
        try c.encode(voronoiDriftStrength, forKey: .voronoiDriftStrength)
        try c.encode(voronoiSeedSpread, forKey: .voronoiSeedSpread)
        try c.encode(voronoiTintRange, forKey: .voronoiTintRange)
        try c.encode(voronoiCpuBeatBoost, forKey: .voronoiCpuBeatBoost)
        try c.encode(voronoiCpuBeatHalfLife, forKey: .voronoiCpuBeatHalfLife)
        try c.encode(voronoiSoftBlurSigma, forKey: .voronoiSoftBlurSigma)
        try c.encode(heightfieldGridSize, forKey: .heightfieldGridSize)
        try c.encode(heightfieldTiltAngle, forKey: .heightfieldTiltAngle)
        try c.encode(heightfieldZScale, forKey: .heightfieldZScale)
        try c.encode(heightfieldLineHalfThickness, forKey: .heightfieldLineHalfThickness)
        try c.encode(heightfieldLightX, forKey: .heightfieldLightX)
        try c.encode(heightfieldLightY, forKey: .heightfieldLightY)
        try c.encode(heightfieldLightZ, forKey: .heightfieldLightZ)
        try c.encode(heightfieldAmbientLight, forKey: .heightfieldAmbientLight)
        try c.encode(heightfieldVerticalFit, forKey: .heightfieldVerticalFit)
        try c.encode(heightfieldVerticalCenter, forKey: .heightfieldVerticalCenter)
        try c.encode(heightfieldBeatBoost, forKey: .heightfieldBeatBoost)
        try c.encode(heightfieldBeatHalfLife, forKey: .heightfieldBeatHalfLife)
        try c.encode(heightfieldXExtent, forKey: .heightfieldXExtent)
        try c.encode(heightfieldYExtent, forKey: .heightfieldYExtent)
        try c.encode(heightfieldOpacity, forKey: .heightfieldOpacity)
        try c.encode(heightfieldFillWidth, forKey: .heightfieldFillWidth)
        try c.encode(heightfieldAnchorBottom, forKey: .heightfieldAnchorBottom)
        try c.encode(fountainMaxParticles, forKey: .fountainMaxParticles)
        try c.encode(fountainSpawnRate, forKey: .fountainSpawnRate)
        try c.encode(fountainSpawnFloor, forKey: .fountainSpawnFloor)
        try c.encode(fountainBaseUp, forKey: .fountainBaseUp)
        try c.encode(fountainLaunchScale, forKey: .fountainLaunchScale)
        try c.encode(fountainLaunchJitter, forKey: .fountainLaunchJitter)
        try c.encode(fountainGravity, forKey: .fountainGravity)
        try c.encode(fountainHorizontalJitter, forKey: .fountainHorizontalJitter)
        try c.encode(fountainHorizontalDrag, forKey: .fountainHorizontalDrag)
        try c.encode(fountainBaseLifetime, forKey: .fountainBaseLifetime)
        try c.encode(fountainBaseSize, forKey: .fountainBaseSize)
        try c.encode(fountainBeatLaunchBoost, forKey: .fountainBeatLaunchBoost)
        try c.encode(fireworksMaxParticles, forKey: .fireworksMaxParticles)
        try c.encode(fireworksBurstParticlesMax, forKey: .fireworksBurstParticlesMax)
        try c.encode(fireworksBurstParticlesMin, forKey: .fireworksBurstParticlesMin)
        try c.encode(fireworksBurstScaleBase, forKey: .fireworksBurstScaleBase)
        try c.encode(fireworksBurstScaleIntensity, forKey: .fireworksBurstScaleIntensity)
        try c.encode(fireworksBaseSpeed, forKey: .fireworksBaseSpeed)
        try c.encode(fireworksSpreadSpeed, forKey: .fireworksSpreadSpeed)
        try c.encode(fireworksGravity, forKey: .fireworksGravity)
        try c.encode(fireworksDrag, forKey: .fireworksDrag)
        try c.encode(fireworksBaseLifetime, forKey: .fireworksBaseLifetime)
        try c.encode(fireworksLifetimeJitter, forKey: .fireworksLifetimeJitter)
        try c.encode(fireworksMinLifetime, forKey: .fireworksMinLifetime)
        try c.encode(fireworksBaseSize, forKey: .fireworksBaseSize)
        try c.encode(fireworksBurstHalfX, forKey: .fireworksBurstHalfX)
        try c.encode(fireworksBurstHalfY, forKey: .fireworksBurstHalfY)
        try c.encode(fireworksAngleJitter, forKey: .fireworksAngleJitter)
        try c.encode(particlesMaxParticles, forKey: .particlesMaxParticles)
        try c.encode(particlesInitialVelocityScale, forKey: .particlesInitialVelocityScale)
        try c.encode(particlesRespawnVelocityScale, forKey: .particlesRespawnVelocityScale)
        try c.encode(particlesBaseSize, forKey: .particlesBaseSize)
        try c.encode(particlesBaseBrightness, forKey: .particlesBaseBrightness)
        try c.encode(particlesBrightnessJitter, forKey: .particlesBrightnessJitter)
        try c.encode(particlesBassThreshold, forKey: .particlesBassThreshold)
        try c.encode(particlesVelocityDamping, forKey: .particlesVelocityDamping)
        try c.encode(particlesReturnLerpRate, forKey: .particlesReturnLerpRate)
        try c.encode(particlesBeatHalfLife, forKey: .particlesBeatHalfLife)
        try c.encode(particlesBeatPulseScale, forKey: .particlesBeatPulseScale)
        try c.encode(particlesBassImpulse, forKey: .particlesBassImpulse)
        try c.encode(particlesBassBrightnessGain, forKey: .particlesBassBrightnessGain)
        try c.encode(particlesBrightnessCap, forKey: .particlesBrightnessCap)
        try c.encode(particlesBassSizeGain, forKey: .particlesBassSizeGain)
        try c.encode(particlesSizeCapMultiplier, forKey: .particlesSizeCapMultiplier)
        try c.encode(particlesRespawnOffscreenBound, forKey: .particlesRespawnOffscreenBound)
        try c.encode(particlesRespawnCenterHalfRange, forKey: .particlesRespawnCenterHalfRange)
        try c.encode(particlesLowBandPercent, forKey: .particlesLowBandPercent)
        try c.encode(ribbonTiltSpacing, forKey: .ribbonTiltSpacing)
        try c.encode(ribbonDepthFalloff, forKey: .ribbonDepthFalloff)
        try c.encode(ribbonSampleCount, forKey: .ribbonSampleCount)
        try c.encode(ribbonSmoothing, forKey: .ribbonSmoothing)
        try c.encode(ribbonGain, forKey: .ribbonGain)
        try c.encode(ribbonHeightScale, forKey: .ribbonHeightScale)
        try c.encode(ribbonMotionSpeed, forKey: .ribbonMotionSpeed)
        try c.encode(ribbonBaseFrequency, forKey: .ribbonBaseFrequency)
        try c.encode(ribbonFrequencySpread, forKey: .ribbonFrequencySpread)
        try c.encode(ribbonStereoPanScale, forKey: .ribbonStereoPanScale)
        try c.encode(ribbonPhaseSwing, forKey: .ribbonPhaseSwing)
        try c.encode(ribbonMaxAmplitude, forKey: .ribbonMaxAmplitude)
        try c.encode(ribbonAlpha, forKey: .ribbonAlpha)
        try c.encode(joyPlotSampleCount, forKey: .joyPlotSampleCount)
        try c.encode(joyPlotRowSpacing, forKey: .joyPlotRowSpacing)
        try c.encode(joyPlotRowHeight, forKey: .joyPlotRowHeight)
        try c.encode(joyPlotBaselineOffset, forKey: .joyPlotBaselineOffset)
        try c.encode(joyPlotXExtent, forKey: .joyPlotXExtent)
        try c.encode(joyPlotBeatHalfLife, forKey: .joyPlotBeatHalfLife)
        try c.encode(joyPlotBeatBoost, forKey: .joyPlotBeatBoost)
        try c.encode(joyPlotBottomDim, forKey: .joyPlotBottomDim)
        try c.encode(joyPlotAlpha, forKey: .joyPlotAlpha)
        try c.encode(xyScopeGain, forKey: .xyScopeGain)
        try c.encode(xyScopeSampleCount, forKey: .xyScopeSampleCount)
        try c.encode(xyScopeLineHalfThickness, forKey: .xyScopeLineHalfThickness)
        try c.encode(xyScopeRotationDegrees, forKey: .xyScopeRotationDegrees)
        try c.encode(xyScopeColorFloor, forKey: .xyScopeColorFloor)
        try c.encode(xyScopeBeatBoost, forKey: .xyScopeBeatBoost)
        try c.encode(xyScopeBeatHalfLife, forKey: .xyScopeBeatHalfLife)
        try c.encode(xyScopeAlpha, forKey: .xyScopeAlpha)
        try c.encode(irisPetalCount, forKey: .irisPetalCount)
        try c.encode(irisInnerRadius, forKey: .irisInnerRadius)
        try c.encode(irisBaseLength, forKey: .irisBaseLength)
        try c.encode(irisLengthScale, forKey: .irisLengthScale)
        try c.encode(irisPetalWidth, forKey: .irisPetalWidth)
        try c.encode(irisLoudnessSwell, forKey: .irisLoudnessSwell)
        try c.encode(irisInnerDim, forKey: .irisInnerDim)
        try c.encode(irisAlpha, forKey: .irisAlpha)
        try c.encode(tricentricRingCount, forKey: .tricentricRingCount)
        try c.encode(tricentricBaseRadius, forKey: .tricentricBaseRadius)
        try c.encode(tricentricRadiusFalloff, forKey: .tricentricRadiusFalloff)
        try c.encode(tricentricScaleFloor, forKey: .tricentricScaleFloor)
        try c.encode(tricentricRotationSpeed, forKey: .tricentricRotationSpeed)
        try c.encode(tricentricLineThickness, forKey: .tricentricLineThickness)
        try c.encode(tricentricAlpha, forKey: .tricentricAlpha)
        try c.encode(musicalStartOctave, forKey: .musicalStartOctave)
        try c.encode(musicalOctaveCount, forKey: .musicalOctaveCount)
        try c.encode(musicalBarGap, forKey: .musicalBarGap)
        try c.encode(musicalOctaveGap, forKey: .musicalOctaveGap)
        try c.encode(musicalPitchClassColoring, forKey: .musicalPitchClassColoring)
        try c.encode(musicalColorFloor, forKey: .musicalColorFloor)
        try c.encode(musicalAlpha, forKey: .musicalAlpha)
        try c.encode(trailPersistence, forKey: .trailPersistence)
        try c.encode(useStereoImage, forKey: .useStereoImage)
        try c.encode(fftWindow, forKey: .fftWindow)
        try c.encode(vignetteAmount, forKey: .vignetteAmount)
        try c.encode(outputBrightness, forKey: .outputBrightness)
        try c.encode(kaleidoscopeFolds, forKey: .kaleidoscopeFolds)
        try c.encode(windowTransparencyMode, forKey: .windowTransparencyMode)
        try c.encode(windowOpacity, forKey: .windowOpacity)
        try c.encode(clickThroughEnabled, forKey: .clickThroughEnabled)
        try c.encode(borderlessWindow, forKey: .borderlessWindow)
        try c.encode(windowBorderMode, forKey: .windowBorderMode)
        try c.encode(windowBorderColor, forKey: .windowBorderColor)
        try c.encode(windowBorderOpacity, forKey: .windowBorderOpacity)
        try c.encode(windowBorderWidth, forKey: .windowBorderWidth)
        try c.encode(mouseControlModifier, forKey: .mouseControlModifier)
        try c.encode(centerBelowLyrics, forKey: .centerBelowLyrics)
        try c.encode(overlayEnabled, forKey: .overlayEnabled)
        try c.encode(overlayPosition, forKey: .overlayPosition)
        try c.encode(overlayOpacity, forKey: .overlayOpacity)
        try c.encode(alwaysOnTop, forKey: .alwaysOnTop)
        try c.encode(targetFPS, forKey: .targetFPS)
        try c.encode(paletteCycleEnabled, forKey: .paletteCycleEnabled)
        try c.encode(paletteCycleInterval, forKey: .paletteCycleInterval)
        try c.encode(paletteCycleFadeDuration, forKey: .paletteCycleFadeDuration)
        try c.encode(lyrics, forKey: .lyrics)
        // Legacy fields are NOT encoded — the encoder produces only the new schema.
    }
}