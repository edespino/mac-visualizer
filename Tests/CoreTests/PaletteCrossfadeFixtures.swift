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
@testable import MacVisualizerCore

/// Shared, deterministic input fixtures for the palette-crossfade parity and
/// propagation tests. Every CPU vertex-emit visualizer is exercised on the same
/// seeded frame sequence so that:
///  - the GOLDEN HASH captured from pre-change code (`goldenHash` / `goldenCount`)
///    proves the injected-palette substitution is value-preserving (bit-identical
///    at feature-off / not-fading), and
///  - feeding a deliberately distinct palette proves the injected palette is
///    actually consumed (propagation).
///
/// The frame/settings/stepping construction lives here ONCE so the pre-change
/// capture and the post-change parity assertions use byte-identical inputs; only
/// the code under test changes between the two.
enum PaletteFixtures {

    /// One representative scenario for a single CPU visualizer.
    struct Case {
        let name: String
        let style: VisualizerStyle
        /// Per-style settings overrides applied AFTER `visualizerStyle` is set
        /// (so `mutateCurrent` targets the right profile — see CLAUDE.md).
        let configure: (inout VisualizerSettings) -> Void

        init(_ name: String, _ style: VisualizerStyle,
             configure: @escaping (inout VisualizerSettings) -> Void = { _ in }) {
            self.name = name
            self.style = style
            self.configure = configure
        }
    }

    /// Build the settings for a case at a given palette name. `visualizerStyle`
    /// is set first so `settings.current` (and the forwarding `paletteName`
    /// setter) resolve to the case's own profile, then per-case overrides run.
    static func settings(for c: Case, palette: String) -> VisualizerSettings {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = c.style
        s.paletteName = palette
        c.configure(&s)
        return s
    }

    /// Deterministic, content-rich frame. Ascending bands, a fixed sine
    /// waveform, populated stereo channels, and an optional beat — enough to
    /// drive every visualizer's palette path to emit colored geometry.
    static func frame(t: Double, beat: Bool) -> AudioFrame {
        let n = 24
        let bandsLeft = (0..<n).map { Float($0 + 1) / Float(n) }                 // 0.0417 … 1.0
        let bandsRight = (0..<n).map { 1 - Float($0) / Float(n) }                // 1.0 … 0.0417
        let bands = zip(bandsLeft, bandsRight).map { ($0 + $1) / 2 }             // mean invariant
        let peaks = (0..<n).map { min(1, Float($0 + 2) / Float(n)) }
        let wave = (0..<256).map { sinf(Float($0) * 0.05) * 0.8 }
        return AudioFrame(bands: bands, bandsLeft: bandsLeft, bandsRight: bandsRight,
                          bandPeaks: peaks, waveform: wave,
                          rms: 0.5, peak: 0.9, timestamp: t,
                          beat: beat, beatIntensity: beat ? 0.8 : 0, trackId: nil)
    }

    /// Three frames so stateful visualizers (particles, spirals, fades) advance
    /// past their first-frame dt==0 guard; the middle frame fires a beat.
    static let frameSequence: [AudioFrame] = [
        frame(t: 0.0, beat: false),
        frame(t: 1.0 / 60.0, beat: true),
        frame(t: 2.0 / 60.0, beat: false),
    ]

    /// The 16 representative scenarios (15 visualizers; Polartone twice to cover
    /// both its ring `:113` and spiral `:254` palette lookups).
    static let cases: [Case] = [
        Case("SpectrumBars", .bars),
        Case("SpectrumBars-peakHold", .bars) { $0.peakHoldEnabled = true },
        Case("MirroredBars", .mirrored),
        Case("Oscilloscope", .oscilloscope),
        Case("RadialSpectrum", .radial),
        Case("BeatCounter", .beatCounter),
        Case("JoyPlot", .joyPlot),
        Case("RibbonWave", .ribbonWave),
        Case("Wireframe", .wireframe),
        Case("SpectrumFountain", .fountain),
        Case("Fireworks", .fireworks),
        Case("Particles", .particles),
        Case("Heightfield", .heightfield),
        Case("Voronoi", .voronoi),
        Case("Polartone-ring", .polartone) { $0.polartoneRenderMode = .ring },
        Case("Polartone-spiral", .polartone) { $0.polartoneRenderMode = .spiral },
        Case("LavaLamp", .lavaLamp) { $0.mutateCurrent { $0.lavaLampRenderMode = .marchingSquares } },
    ]

    /// Run the frame sequence through a fresh visualizer, emitting via the
    /// palette-aware 4-arg call with `palette` resolved exactly as
    /// `effectivePalette()` does when NOT mid-fade
    /// (`ColorPalette.preset(named: settings.paletteName) ?? .fallback`). This is
    /// the feature-off path the parity goldens guard.
    static func emit(_ c: Case, palette paletteName: String) -> [BarVertex] {
        let pal = ColorPalette.preset(named: paletteName) ?? .fallback
        return emit(c, settingsPalette: paletteName, injected: pal)
    }

    /// Run the frame sequence with an explicitly injected palette while
    /// `settings.paletteName` is whatever `settingsPalette` says. Lets the
    /// propagation tests prove vertex color follows the INJECTED palette, not the
    /// settings name (the crux of the crossfade fix).
    static func emit(_ c: Case, settingsPalette: String, injected: ColorPalette) -> [BarVertex] {
        let viz = c.style.makeVisualizer()
        let s = settings(for: c, palette: settingsPalette)
        var out: [BarVertex] = []
        for f in frameSequence { out = viz.makeVertices(frame: f, settings: s, palette: injected, aspect: 1.0) }
        return out
    }

    /// Pre-change golden snapshots: `(vertex count, FNV-1a digest)` captured from
    /// the unmodified (internal-lookup) code on `frameSequence` at palette
    /// "classic". Frozen — never regenerate post-substitution. Equal `(count,
    /// hash)` ⇒ the injected-palette routing is byte-identical at feature-off.
    static let goldens: [String: (count: Int, hash: UInt64)] = [
        "SpectrumBars": (count: 288, hash: 0x3613069cac7bcf0b),
        "SpectrumBars-peakHold": (count: 288, hash: 0x3613069cac7bcf0b),
        "MirroredBars": (count: 288, hash: 0xde9796c77d0a60f9),
        "Oscilloscope": (count: 1530, hash: 0x1e63fc3ffa68c930),
        "RadialSpectrum": (count: 144, hash: 0x2f4a7c79c799e06d),
        "BeatCounter": (count: 6, hash: 0xe119b232135d98f9),
        "JoyPlot": (count: 1512, hash: 0x2ad768443b231d99),
        "RibbonWave": (count: 4590, hash: 0x4f4374760e133087),
        "Wireframe": (count: 2880, hash: 0x373c856b86262d51),
        "SpectrumFountain": (count: 48, hash: 0xa40d0e87838408d1),
        "Fireworks": (count: 420, hash: 0xadd754b696c659df),
        "Particles": (count: 1200, hash: 0x79581d36433ad27d),
        "Heightfield": (count: 2880, hash: 0xa6e7e4715212a283),
        "Voronoi": (count: 1311, hash: 0xb416e11672fa9a19),
        "Polartone-ring": (count: 1536, hash: 0x16cfadb11cb7cd69),
        "Polartone-spiral": (count: 12, hash: 0x86aad2ff32c97355),
        "LavaLamp": (count: 23814, hash: 0xd21232bbfbaafacd),
    ]

    /// FNV-1a 64-bit over the raw IEEE-754 bit pattern of every vertex
    /// component. Any single-bit change in any position/color component flips
    /// the digest, so equal `(count, hash)` ⇒ bit-identical vertex arrays.
    static func hash(_ verts: [BarVertex]) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        func mix(_ f: Float) {
            var bits = UInt64(f.bitPattern)
            for _ in 0..<4 {
                h = (h ^ (bits & 0xff)) &* 0x100000001b3
                bits >>= 8
            }
        }
        for v in verts {
            mix(v.position.x); mix(v.position.y); mix(v.position.z); mix(v.position.w)
            mix(v.color.x); mix(v.color.y); mix(v.color.z); mix(v.color.w)
        }
        return h
    }
}
