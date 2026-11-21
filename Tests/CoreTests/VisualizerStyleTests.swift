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
import XCTest
@testable import MacVisualizerCore

final class VisualizerStyleTests: XCTestCase {
    func testAllCases() {
        XCTAssertEqual(VisualizerStyle.allCases,
                       [.bars, .radial, .mirrored, .oscilloscope, .particles, .fountain, .fireworks, .ribbonWave, .wireframe, .plasma, .bumpscope, .joyPlot, .heightfield, .voronoi, .lavaLamp, .beatCounter, .polartone, .octaveMeatballs, .starNest, .outrunRain, .xyScope, .iris, .tricentric, .musicalSpectrum, .spinner])
    }

    func testNextWrapsAround() {
        XCTAssertEqual(VisualizerStyle.bars.next, .radial)
        XCTAssertEqual(VisualizerStyle.particles.next, .fountain)
        XCTAssertEqual(VisualizerStyle.fountain.next, .fireworks)
        XCTAssertEqual(VisualizerStyle.fireworks.next, .ribbonWave)
    }

    func testPreviousWrapsAround() {
        XCTAssertEqual(VisualizerStyle.radial.previous, .bars)
        XCTAssertEqual(VisualizerStyle.fountain.previous, .particles)
        XCTAssertEqual(VisualizerStyle.fireworks.previous, .fountain)
        XCTAssertEqual(VisualizerStyle.bars.previous, .spinner)
    }

    /// Pins the positional ordering invariant new styles must maintain: cases
    /// are appended at the end, so the count and the final case move together.
    func testCaseCountIsTwentyFiveAndSpinnerIsLast() {
        XCTAssertEqual(VisualizerStyle.allCases.count, 25)
        XCTAssertEqual(VisualizerStyle.allCases.last, .spinner)
    }

    func testSupportsPositionOffsetForCenteredGeometryStyles() {
        let supported: Set<VisualizerStyle> = [
            .radial, .polartone, .iris, .tricentric, .xyScope,   // centered radial
            .heightfield, .wireframe,                            // centered 3D
            .oscilloscope, .ribbonWave, .joyPlot, .mirrored,      // centered on the mid-line (y=0)
            .spinner,
            .octaveMeatballs                                      // field shifts; uncovered window is discarded
        ]
        for style in VisualizerStyle.allCases {
            XCTAssertEqual(style.supportsPositionOffset, supported.contains(style),
                           "\(style) supportsPositionOffset should be \(supported.contains(style))")
        }
        // Bottom-anchored bar spectra, particle systems, the beat flash, and
        // fullscreen-shader styles are excluded. (Mirrored is NOT here: its bars
        // grow symmetrically about y=0, so it is a mid-line form.)
        XCTAssertFalse(VisualizerStyle.bars.supportsPositionOffset)
        XCTAssertFalse(VisualizerStyle.musicalSpectrum.supportsPositionOffset)
        XCTAssertFalse(VisualizerStyle.beatCounter.supportsPositionOffset)
        XCTAssertFalse(VisualizerStyle.voronoi.supportsPositionOffset)
        XCTAssertFalse(VisualizerStyle.lavaLamp.supportsPositionOffset)
        XCTAssertTrue(VisualizerStyle.octaveMeatballs.supportsPositionOffset)
    }

    func testRibbonWaveDisplayNameAndFactory() {
        XCTAssertEqual(VisualizerStyle.ribbonWave.displayName, "Ribbon Wave")
        XCTAssertTrue(VisualizerStyle.ribbonWave.makeVisualizer() is RibbonWaveVisualizer)
        XCTAssertFalse(VisualizerStyle.ribbonWave.usesRoundParticles)
    }

    func testRibbonWaveNextPreviousWrapping() {
        XCTAssertEqual(VisualizerStyle.fireworks.next, .ribbonWave)
        XCTAssertEqual(VisualizerStyle.ribbonWave.next, .wireframe)
        XCTAssertEqual(VisualizerStyle.bars.previous, .spinner)
        XCTAssertEqual(VisualizerStyle.ribbonWave.previous, .fireworks)
    }

    // (The former testWireframeCaseExistsAndIsLast duplicated the ordering
    // assertions above verbatim; two tests cannot share one honest name, so
    // the invariant lives solely in testCaseCountIsTwentyFiveAndSpinnerIsLast.)

    func testWireframeDisplayNameAndFactory() {
        XCTAssertEqual(VisualizerStyle.wireframe.displayName, "Wireframe")
        XCTAssertTrue(VisualizerStyle.wireframe.makeVisualizer() is WireframeVisualizer)
        XCTAssertFalse(VisualizerStyle.wireframe.usesRoundParticles)
    }

    func testWireframeNextPreviousWrapping() {
        XCTAssertEqual(VisualizerStyle.ribbonWave.next, .wireframe)
        XCTAssertEqual(VisualizerStyle.wireframe.next, .plasma)
        XCTAssertEqual(VisualizerStyle.bars.previous, .spinner)
        XCTAssertEqual(VisualizerStyle.wireframe.previous, .ribbonWave)
    }

    func testFountainAndFireworksFactories() {
        XCTAssertTrue(VisualizerStyle.fountain.makeVisualizer() is SpectrumFountainVisualizer)
        XCTAssertTrue(VisualizerStyle.fireworks.makeVisualizer() is FireworksVisualizer)
        XCTAssertFalse(VisualizerStyle.fountain.displayName.isEmpty)
        XCTAssertFalse(VisualizerStyle.fireworks.displayName.isEmpty)
    }

    func testParticlesFactory() {
        XCTAssertTrue(VisualizerStyle.particles.makeVisualizer() is ParticleVisualizer)
        XCTAssertFalse(VisualizerStyle.particles.displayName.isEmpty)
    }

    func testDisplayNamesNonEmpty() {
        for s in VisualizerStyle.allCases { XCTAssertFalse(s.displayName.isEmpty) }
    }

    func testFactoryMatchesConcreteVisualizer() {
        var settings = VisualizerSettings.defaults; settings.barCount = 4
        let frame = AudioFrame(bands: [0.2, 0.4, 0.6, 0.8], bandPeaks: [0.2, 0.4, 0.6, 0.8],
                               waveform: [0, 0.5, -0.5, 0.3], rms: 0, peak: 0, timestamp: 0)
        XCTAssertEqual(VisualizerStyle.bars.makeVisualizer().makeVertices(frame: frame, settings: settings, aspect: 1),
                       SpectrumBarsVisualizer().makeVertices(frame: frame, settings: settings, aspect: 1))
        XCTAssertEqual(VisualizerStyle.radial.makeVisualizer().makeVertices(frame: frame, settings: settings, aspect: 1),
                       RadialSpectrumVisualizer().makeVertices(frame: frame, settings: settings, aspect: 1))
        XCTAssertEqual(VisualizerStyle.mirrored.makeVisualizer().makeVertices(frame: frame, settings: settings, aspect: 1),
                       MirroredBarsVisualizer().makeVertices(frame: frame, settings: settings, aspect: 1))
        XCTAssertEqual(VisualizerStyle.oscilloscope.makeVisualizer().makeVertices(frame: frame, settings: settings, aspect: 1),
                       OscilloscopeVisualizer().makeVertices(frame: frame, settings: settings, aspect: 1))
        XCTAssertEqual(VisualizerStyle.polartone.makeVisualizer().makeVertices(frame: frame, settings: settings, aspect: 1),
                       PolartoneVisualizer().makeVertices(frame: frame, settings: settings, aspect: 1))
    }

    func testTricentricAndMusicalSpectrumAreLastTwoCases() {
        XCTAssertEqual(VisualizerStyle.allCases.count, 25)
        XCTAssertEqual(VisualizerStyle.allCases[VisualizerStyle.allCases.count - 2], .musicalSpectrum)
        XCTAssertEqual(VisualizerStyle.allCases[VisualizerStyle.allCases.count - 3], .tricentric)
    }

    func testShaderKindsForPlasmaAndBumpscope() {
        XCTAssertEqual(VisualizerStyle.plasma.displayName, "Plasma")
        XCTAssertEqual(VisualizerStyle.bumpscope.displayName, "Bumpscope")
        XCTAssertEqual(VisualizerStyle.plasma.customShader(settings: settings(for: .plasma)), .plasma)
        XCTAssertEqual(VisualizerStyle.bumpscope.customShader(settings: settings(for: .bumpscope)), .bumpscope)
        XCTAssertNil(VisualizerStyle.bars.customShader(settings: settings(for: .bars)))
        XCTAssertNil(VisualizerStyle.wireframe.customShader(settings: settings(for: .wireframe)))
        XCTAssertFalse(VisualizerStyle.plasma.usesRoundParticles)
        XCTAssertFalse(VisualizerStyle.bumpscope.usesRoundParticles)
        XCTAssertTrue(VisualizerStyle.plasma.makeVisualizer() is PlasmaVisualizer)
        XCTAssertTrue(VisualizerStyle.bumpscope.makeVisualizer() is BumpscopeVisualizer)
    }

    func testPlasmaBumpscopeWrapping() {
        XCTAssertEqual(VisualizerStyle.wireframe.next, .plasma)
        XCTAssertEqual(VisualizerStyle.plasma.next, .bumpscope)
        XCTAssertEqual(VisualizerStyle.bumpscope.next, .joyPlot)
        XCTAssertEqual(VisualizerStyle.bars.previous, .spinner)
        XCTAssertEqual(VisualizerStyle.plasma.previous, .wireframe)
        XCTAssertEqual(VisualizerStyle.bumpscope.previous, .plasma)
    }

    func testAllCasesIncludesNewStyles() {
        let names = Set(VisualizerStyle.allCases.map { $0.rawValue })
        XCTAssertTrue(names.contains("joyPlot"))
        XCTAssertTrue(names.contains("heightfield"))
        XCTAssertTrue(names.contains("voronoi"))
        XCTAssertTrue(names.contains("lavaLamp"))
        XCTAssertTrue(names.contains("polartone"))
        XCTAssertTrue(names.contains("starNest"))
        XCTAssertTrue(names.contains("outrunRain"))
        XCTAssertTrue(names.contains("xyScope"))
    }

    func testXYScopeDisplayNameFactoryAndWrapping() {
        XCTAssertEqual(VisualizerStyle.xyScope.displayName, "XY Scope")
        XCTAssertTrue(VisualizerStyle.xyScope.makeVisualizer() is XYScopeVisualizer)
        XCTAssertFalse(VisualizerStyle.xyScope.usesRoundParticles)
        XCTAssertNil(VisualizerStyle.xyScope.customShader(settings: settings(for: .xyScope)))
        XCTAssertEqual(VisualizerStyle.outrunRain.next, .xyScope)
        XCTAssertEqual(VisualizerStyle.xyScope.next, .iris)
        XCTAssertEqual(VisualizerStyle.xyScope.previous, .outrunRain)
    }

    func testIrisDisplayNameFactoryAndWrapping() {
        XCTAssertEqual(VisualizerStyle.iris.displayName, "Iris")
        XCTAssertTrue(VisualizerStyle.iris.makeVisualizer() is IrisVisualizer)
        XCTAssertFalse(VisualizerStyle.iris.usesRoundParticles)
        XCTAssertNil(VisualizerStyle.iris.customShader(settings: settings(for: .iris)))
        XCTAssertEqual(VisualizerStyle.iris.next, .tricentric)
        XCTAssertEqual(VisualizerStyle.iris.previous, .xyScope)
    }

    func testTricentricDisplayNameFactoryAndWrapping() {
        XCTAssertEqual(VisualizerStyle.tricentric.displayName, "Tricentric")
        XCTAssertTrue(VisualizerStyle.tricentric.makeVisualizer() is TricentricVisualizer)
        XCTAssertFalse(VisualizerStyle.tricentric.usesRoundParticles)
        XCTAssertNil(VisualizerStyle.tricentric.customShader(settings: settings(for: .tricentric)))
        XCTAssertEqual(VisualizerStyle.tricentric.next, .musicalSpectrum)
        XCTAssertEqual(VisualizerStyle.tricentric.previous, .iris)
    }

    func testMusicalSpectrumDisplayNameFactoryAndWrapping() {
        XCTAssertEqual(VisualizerStyle.musicalSpectrum.displayName, "Musical Spectrum")
        XCTAssertTrue(VisualizerStyle.musicalSpectrum.makeVisualizer() is MusicalSpectrumVisualizer)
        XCTAssertFalse(VisualizerStyle.musicalSpectrum.usesRoundParticles)
        XCTAssertNil(VisualizerStyle.musicalSpectrum.customShader(settings: settings(for: .musicalSpectrum)))
        XCTAssertEqual(VisualizerStyle.musicalSpectrum.next, .spinner)
        XCTAssertEqual(VisualizerStyle.musicalSpectrum.previous, .tricentric)
    }

    func testMakeVisualizerForNewStyles() {
        XCTAssertNotNil(VisualizerStyle.joyPlot.makeVisualizer())
        XCTAssertNotNil(VisualizerStyle.heightfield.makeVisualizer())
        XCTAssertNotNil(VisualizerStyle.voronoi.makeVisualizer())
        XCTAssertNotNil(VisualizerStyle.lavaLamp.makeVisualizer())
        XCTAssertNotNil(VisualizerStyle.polartone.makeVisualizer())
        XCTAssertNotNil(VisualizerStyle.starNest.makeVisualizer())
        XCTAssertNotNil(VisualizerStyle.outrunRain.makeVisualizer())
    }

    func testCustomShaderMappingForNewStyles() {
        // Pure geometry styles never take the shader path, regardless of settings.
        XCTAssertNil(VisualizerStyle.joyPlot.customShader(settings: settings(for: .joyPlot)))
        XCTAssertNil(VisualizerStyle.heightfield.customShader(settings: settings(for: .heightfield)))

        // Voronoi is mode-dependent: default (.cells) is geometry, .blobs is shader-driven.
        XCTAssertNil(VisualizerStyle.voronoi.customShader(settings: settings(for: .voronoi)))
        XCTAssertEqual(
            VisualizerStyle.voronoi.customShader(
                settings: settings(for: .voronoi) { $0.voronoiRenderMode = .blobs }),
            .voronoiBlobs)

        // LavaLamp is mode-dependent: default (.shader) is shader-driven, .marchingSquares is geometry.
        XCTAssertEqual(
            VisualizerStyle.lavaLamp.customShader(settings: settings(for: .lavaLamp)),
            .lavaLampShader)
        XCTAssertNil(
            VisualizerStyle.lavaLamp.customShader(
                settings: settings(for: .lavaLamp) { $0.lavaLampRenderMode = .marchingSquares }))

        // OctaveMeatballs is always shader-driven, regardless of settings.
        XCTAssertEqual(
            VisualizerStyle.octaveMeatballs.customShader(settings: settings(for: .octaveMeatballs)),
            .octaveMeatballs)

        // StarNest is always shader-driven, regardless of settings.
        XCTAssertEqual(
            VisualizerStyle.starNest.customShader(settings: settings(for: .starNest)),
            .starNest)

        // OutrunRain is always shader-driven, regardless of settings.
        XCTAssertEqual(
            VisualizerStyle.outrunRain.customShader(settings: settings(for: .outrunRain)),
            .outrunRain)
    }

    // MARK: - Control-relevance capability flags (drive disabling in Settings)

    func testUsesFrequencyBandsExcludesWaveformAndBeatOnlyStyles() {
        let noBands: Set<VisualizerStyle> =
            [.plasma, .fireworks, .beatCounter, .oscilloscope, .polartone, .xyScope, .spinner]
        for style in VisualizerStyle.allCases {
            XCTAssertEqual(style.usesFrequencyBands, !noBands.contains(style), "\(style)")
        }
    }

    func testUsesBarCountAlsoExcludesMusicalSpectrum() {
        XCTAssertTrue(VisualizerStyle.bars.usesBarCount)
        XCTAssertFalse(VisualizerStyle.musicalSpectrum.usesBarCount,
                       "Musical Spectrum's band count is fixed by its note mapping")
        // Anything that reads no bands also has no usable bar count.
        for style in VisualizerStyle.allCases where !style.usesFrequencyBands {
            XCTAssertFalse(style.usesBarCount, "\(style)")
        }
    }

    func testUsesPaletteIsFalseOnlyForSpinner() {
        for style in VisualizerStyle.allCases {
            XCTAssertEqual(style.usesPalette, style != .spinner, "\(style)")
        }
    }

    func testSpinnerCapabilityFlags() {
        let s = VisualizerStyle.spinner
        XCTAssertFalse(s.usesFrequencyBands)
        XCTAssertFalse(s.usesBarCount)
        XCTAssertFalse(s.usesPeakHold)
        XCTAssertFalse(s.usesStereoImage)
        XCTAssertTrue(s.supportsPositionOffset)
    }

    func testUsesPeakHoldOnlyBars() {
        for style in VisualizerStyle.allCases {
            XCTAssertEqual(style.usesPeakHold, style == .bars, "\(style)")
        }
    }

    func testUsesStereoImageSet() {
        let stereo: Set<VisualizerStyle> =
            [.bars, .radial, .ribbonWave, .joyPlot, .heightfield, .voronoi, .lavaLamp, .iris]
        for style in VisualizerStyle.allCases {
            XCTAssertEqual(style.usesStereoImage, stereo.contains(style), "\(style)")
        }
    }

    /// Build a `VisualizerSettings` with `style` active and its profile optionally
    /// mutated. `visualizerStyle` is set BEFORE `mutateCurrent` so the closure
    /// edits the intended style's profile (not the default `.bars` profile).
    private func settings(for style: VisualizerStyle,
                          _ mutate: (inout StyleProfile) -> Void = { _ in }) -> VisualizerSettings {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = style
        s.mutateCurrent(mutate)
        return s
    }
}
