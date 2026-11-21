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

final class VisualizerSettingsTests: XCTestCase {
    func testDefaultsAreSensible() {
        let s = VisualizerSettings.defaults
        XCTAssertEqual(s.barCount, 48)
        XCTAssertEqual(s.targetFPS, 60)
        XCTAssertGreaterThan(s.gain, 0)
        XCTAssertTrue((0...1).contains(s.smoothing))
        XCTAssertTrue(s.peakHoldEnabled)
        XCTAssertEqual(s.paletteName, "classic")
    }

    func testJSONRoundTrips() throws {
        var s = VisualizerSettings.defaults
        s.gain = 2.5
        s.barCount = 64
        s.paletteName = "custom"
        s.customStops = [RGBAColor(r: 1, g: 0, b: 0, a: 1),
                         RGBAColor(r: 0, g: 0, b: 1, a: 1)]
        s.overlayEnabled = false

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)

        XCTAssertEqual(decoded, s)
    }

    func testLoadReturnsDefaultsWhenFileMissing() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).json")
        let loaded = VisualizerSettings.load(from: url)
        XCTAssertEqual(loaded, VisualizerSettings.defaults)
    }

    func testSaveThenLoadRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        var s = VisualizerSettings.defaults
        s.gain = 3.0
        try s.save(to: url)

        let loaded = VisualizerSettings.load(from: url)
        XCTAssertEqual(loaded, s)
    }

    func testDefaultVisualizerStyleIsBars() {
        XCTAssertEqual(VisualizerSettings.defaults.visualizerStyle, .bars)
    }

    func testVisualizerStyleRoundTrips() throws {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .oscilloscope
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.visualizerStyle, .oscilloscope)
        XCTAssertEqual(decoded, s)
    }

    func testPartialJSONDecodesWithDefaults() throws {
        let json = #"{ "gain": 2.5, "barCount": 64 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.gain, 2.5)
        XCTAssertEqual(decoded.barCount, 64)
        XCTAssertEqual(decoded.visualizerStyle, .bars)
        XCTAssertEqual(decoded.smoothing, VisualizerSettings.defaults.smoothing)
        XCTAssertEqual(decoded.paletteName, VisualizerSettings.defaults.paletteName)
    }

    func testGlowDefaults() {
        XCTAssertTrue(VisualizerSettings.defaults.glowEnabled)
        XCTAssertEqual(VisualizerSettings.defaults.glowIntensity, 0.6, accuracy: 1e-6)
    }

    func testTrackOverlayDefaultsOff() {
        // The forwarding property reads the active profile; defaults ship overlay off.
        XCTAssertFalse(VisualizerSettings.defaults.overlayEnabled)
    }

    func testGlowRoundTrips() throws {
        var s = VisualizerSettings.defaults
        s.glowEnabled = false
        s.glowIntensity = 1.2
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.glowEnabled, false)
        XCTAssertEqual(decoded.glowIntensity, 1.2, accuracy: 1e-6)
        XCTAssertEqual(decoded, s)
    }

    func testPartialJSONDefaultsGlow() throws {
        let json = #"{ "gain": 2.0 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.gain, 2.0)
        XCTAssertTrue(decoded.glowEnabled)
        XCTAssertEqual(decoded.glowIntensity, 0.6, accuracy: 1e-6)
    }

    func testProfilesPopulatedForEveryStyle() {
        let d = VisualizerSettings.defaults
        XCTAssertEqual(d.profiles.count, VisualizerStyle.allCases.count)
        for s in VisualizerStyle.allCases {
            XCTAssertEqual(d.profiles[s], StyleProfile.defaults(for: s))
        }
    }

    func testCurrentReturnsActiveProfile() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .radial
        var radial = StyleProfile.defaults
        radial.gain = 3.0
        s.profiles[.radial] = radial
        XCTAssertEqual(s.current.gain, 3.0)
    }

    func testMutateCurrentTouchesOnlyOneProfile() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .bars
        s.mutateCurrent { $0.gain = 4.0 }
        XCTAssertEqual(s.profiles[.bars]?.gain, 4.0)
        XCTAssertEqual(s.profiles[.radial]?.gain, StyleProfile.defaults.gain)
    }

    func testForwardersWriteToCurrentProfile() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .oscilloscope
        s.gain = 2.0
        s.paletteName = "synthwave"
        XCTAssertEqual(s.profiles[.oscilloscope]?.gain, 2.0)
        XCTAssertEqual(s.profiles[.oscilloscope]?.paletteName, "synthwave")
        XCTAssertEqual(s.profiles[.bars]?.gain, StyleProfile.defaults.gain)
    }

    func testSwitchingStyleSwitchesWhatCurrentReturns() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .bars
        s.gain = 2.5
        s.visualizerStyle = .particles
        s.gain = 3.5
        s.visualizerStyle = .bars
        XCTAssertEqual(s.current.gain, 2.5)
        s.visualizerStyle = .particles
        XCTAssertEqual(s.current.gain, 3.5)
    }

    // MARK: - resetCurrentStyle()

    func testResetCurrentStyleRestoresPolartoneTopLevelFields() {
        let d = VisualizerSettings.defaults
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .polartone
        // Drive every exclusive polartone* top-level field away from defaults.
        s.polartoneRadius = 0.9
        s.polartoneAmplitude = 0.6
        s.polartoneColorFloor = 0.5
        s.polartoneRotationSpeed = 2
        s.polartonePointCount = 1024
        s.polartonePhaseOffset = 3
        s.polartoneLineHalfThickness = 0.02
        s.polartoneWaveformClamp = 2
        s.polartoneRenderMode = .spiral
        s.polartoneInnerThreshold = 0.4
        s.polartoneDriftRevolutions = 40
        s.polartoneStartDirection = .outward

        s.resetCurrentStyle()

        XCTAssertEqual(s.polartoneRadius, d.polartoneRadius)
        XCTAssertEqual(s.polartoneAmplitude, d.polartoneAmplitude)
        XCTAssertEqual(s.polartoneColorFloor, d.polartoneColorFloor)
        XCTAssertEqual(s.polartoneRotationSpeed, d.polartoneRotationSpeed)
        XCTAssertEqual(s.polartonePointCount, d.polartonePointCount)
        XCTAssertEqual(s.polartonePhaseOffset, d.polartonePhaseOffset)
        XCTAssertEqual(s.polartoneLineHalfThickness, d.polartoneLineHalfThickness)
        XCTAssertEqual(s.polartoneWaveformClamp, d.polartoneWaveformClamp)
        XCTAssertEqual(s.polartoneRenderMode, d.polartoneRenderMode)
        XCTAssertEqual(s.polartoneInnerThreshold, d.polartoneInnerThreshold)
        XCTAssertEqual(s.polartoneDriftRevolutions, d.polartoneDriftRevolutions)
        XCTAssertEqual(s.polartoneStartDirection, d.polartoneStartDirection)
    }

    func testResetCurrentStyleRestoresStarNestTopLevelFields() {
        let d = VisualizerSettings.defaults
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .starNest
        s.starNestZoom = 2.0
        s.starNestSpeed = 1.0
        s.starNestFormuparam = 0.7
        s.starNestTile = 1.2
        s.starNestStepsize = 0.3
        s.starNestBrightness = 0.003
        s.starNestDarkmatter = 1.0
        s.starNestDistfading = 1.0
        s.starNestSaturation = 1.0
        s.starNestVolsteps = 26
        s.starNestIterations = 16

        s.resetCurrentStyle()

        XCTAssertEqual(s.starNestZoom, d.starNestZoom)
        XCTAssertEqual(s.starNestSpeed, d.starNestSpeed)
        XCTAssertEqual(s.starNestFormuparam, d.starNestFormuparam)
        XCTAssertEqual(s.starNestTile, d.starNestTile)
        XCTAssertEqual(s.starNestStepsize, d.starNestStepsize)
        XCTAssertEqual(s.starNestBrightness, d.starNestBrightness)
        XCTAssertEqual(s.starNestDarkmatter, d.starNestDarkmatter)
        XCTAssertEqual(s.starNestDistfading, d.starNestDistfading)
        XCTAssertEqual(s.starNestSaturation, d.starNestSaturation)
        XCTAssertEqual(s.starNestVolsteps, d.starNestVolsteps)
        XCTAssertEqual(s.starNestIterations, d.starNestIterations)
    }

    func testResetCurrentStyleAlsoResetsCurrentProfile() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .polartone
        s.mutateCurrent { $0.gain = 4.0 }

        s.resetCurrentStyle()

        XCTAssertEqual(s.current.gain, StyleProfile.defaults.gain)
    }

    func testResetCurrentStyleLeavesOtherStylesTopLevelFieldsUntouched() {
        var s = VisualizerSettings.defaults
        // Customize Star Nest's exclusive fields, then reset a DIFFERENT style.
        s.visualizerStyle = .starNest
        s.starNestZoom = 2.0
        s.starNestVolsteps = 26
        s.visualizerStyle = .polartone
        s.polartoneRadius = 0.9

        s.resetCurrentStyle()

        // Polartone reset; Star Nest's fields must be unchanged.
        XCTAssertEqual(s.polartoneRadius, VisualizerSettings.defaults.polartoneRadius)
        XCTAssertEqual(s.starNestZoom, 2.0)
        XCTAssertEqual(s.starNestVolsteps, 26)
    }

    func testResetCurrentStyleLeavesOtherStylesProfilesUntouched() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .radial
        s.mutateCurrent { $0.gain = 3.0 }
        s.visualizerStyle = .polartone
        s.mutateCurrent { $0.gain = 4.0 }

        s.resetCurrentStyle()

        XCTAssertEqual(s.profiles[.radial]?.gain, 3.0)
        XCTAssertEqual(s.profiles[.polartone]?.gain, StyleProfile.defaults.gain)
    }

    func testResetCurrentStyleDoesNotTouchSharedFields() {
        // oscilloscopeThickness is shared between .oscilloscope and .polartone
        // (the "Line width ×" slider). Resetting Polartone must NOT clobber it,
        // since that would alter another style's appearance.
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .polartone
        s.oscilloscopeThickness = 2.5
        s.polartoneRadius = 0.9

        s.resetCurrentStyle()

        XCTAssertEqual(s.polartoneRadius, VisualizerSettings.defaults.polartoneRadius)
        XCTAssertEqual(s.oscilloscopeThickness, 2.5)
    }

    func testResetCurrentStyleNeverTouchesAnySharedTopLevelField() {
        // Shared top-level fields back more than one style, so per-style reset
        // must leave them all alone regardless of the active style:
        //   barGap            -> bars, mirrored
        //   oscilloscopeThickness -> oscilloscope, polartone
        //   particleSize/Speed    -> particles, fountain, fireworks
        // Resetting any active style must preserve every one of these.
        for style in [VisualizerStyle.polartone, .starNest, .fireworks, .bars] {
            var s = VisualizerSettings.defaults
            s.visualizerStyle = style
            s.barGap = 0.5
            s.oscilloscopeThickness = 2.5
            s.particleSize = 2.5
            s.particleSpeed = 2.0

            s.resetCurrentStyle()

            XCTAssertEqual(s.barGap, 0.5, "barGap after reset of \(style)")
            XCTAssertEqual(s.oscilloscopeThickness, 2.5, "oscilloscopeThickness after reset of \(style)")
            XCTAssertEqual(s.particleSize, 2.5, "particleSize after reset of \(style)")
            XCTAssertEqual(s.particleSpeed, 2.0, "particleSpeed after reset of \(style)")
        }
    }

    func testResetCurrentStyleRestoresRibbonWaveTopLevelFields() {
        let d = VisualizerSettings.defaults
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .ribbonWave
        s.ribbonWaveCount = 6
        s.ribbonTiltSpacing = 0.4
        s.ribbonDepthFalloff = 0.5

        s.resetCurrentStyle()

        XCTAssertEqual(s.ribbonWaveCount, d.ribbonWaveCount)
        XCTAssertEqual(s.ribbonTiltSpacing, d.ribbonTiltSpacing)
        XCTAssertEqual(s.ribbonDepthFalloff, d.ribbonDepthFalloff)
    }

    func testMigrationFromOldFlatFieldJSON() throws {
        // Old-format JSON: top-level flat fields, no `profiles` key.
        let json = #"""
        { "gain": 2.5, "barCount": 64, "paletteName": "phosphor", "smoothing": 0.4 }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        // Every style's profile should be initialized from the old flat values.
        for s in VisualizerStyle.allCases {
            let profile = try XCTUnwrap(decoded.profiles[s], "profile for \(s)")
            XCTAssertEqual(profile.gain, 2.5, "gain for \(s)")
            XCTAssertEqual(profile.barCount, 64, "barCount for \(s)")
            XCTAssertEqual(profile.paletteName, "phosphor", "paletteName for \(s)")
            XCTAssertEqual(profile.smoothing, 0.4, accuracy: 1e-6, "smoothing for \(s)")
        }
    }

    func testMigrationPathPreservesPersistedOverlayEnabledTrue() throws {
        // Legacy-flat JSON (no `profiles` key) with a persisted overlay ON must
        // land on the now app-wide VisualizerSettings.overlayEnabled, not be
        // reset to the default-off.
        let json = #"""
        { "gain": 1.0, "overlayEnabled": true }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertTrue(decoded.overlayEnabled)
    }

    func testOverlayAndWindowFieldsAreAppWide() throws {
        // overlay*/alwaysOnTop/targetFPS are single app-wide values now: setting
        // them, switching the active style, and round-tripping must all agree.
        var s = VisualizerSettings.defaults
        s.overlayEnabled = true
        s.overlayPosition = .bottomLeading
        s.overlayOpacity = 0.5
        s.alwaysOnTop = true
        s.targetFPS = 120
        s.visualizerStyle = .voronoi            // switching style must not change them
        XCTAssertTrue(s.overlayEnabled)
        XCTAssertEqual(s.overlayPosition, .bottomLeading)
        XCTAssertEqual(s.targetFPS, 120)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self,
                                               from: try JSONEncoder().encode(s))
        XCTAssertEqual(decoded.overlayEnabled, true)
        XCTAssertEqual(decoded.overlayPosition, .bottomLeading)
        XCTAssertEqual(decoded.overlayOpacity, 0.5, accuracy: 1e-6)
        XCTAssertEqual(decoded.alwaysOnTop, true)
        XCTAssertEqual(decoded.targetFPS, 120)
    }

    func testNewFormatRoundTripWithDistinctProfiles() throws {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .bars
        var bars = StyleProfile.defaults; bars.gain = 1.5; bars.paletteName = "classic"
        var fireworks = StyleProfile.defaults; fireworks.gain = 3.0; fireworks.paletteName = "synthwave"
        s.profiles[.bars] = bars
        s.profiles[.fireworks] = fireworks
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.profiles[.bars]?.gain, 1.5)
        XCTAssertEqual(decoded.profiles[.bars]?.paletteName, "classic")
        XCTAssertEqual(decoded.profiles[.fireworks]?.gain, 3.0)
        XCTAssertEqual(decoded.profiles[.fireworks]?.paletteName, "synthwave")
        XCTAssertEqual(decoded, s)
    }

    func testDemoModeEnabledDefaultsFalse() {
        XCTAssertFalse(VisualizerSettings.defaults.demoModeEnabled)
    }

    func testDemoModeEnabledRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.demoModeEnabled = true
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertTrue(decoded.demoModeEnabled)
        XCTAssertEqual(decoded, s)
    }

    func testDemoModeEnabledPartialJSONDefaults() throws {
        let json = #"{ "gain": 2.5 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertFalse(decoded.demoModeEnabled)
    }

    func testRibbonWaveCountDefault() {
        XCTAssertEqual(VisualizerSettings.defaults.ribbonWaveCount, 3)
    }

    func testRibbonWaveCountRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.ribbonWaveCount = 5
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.ribbonWaveCount, 5)
        XCTAssertEqual(decoded, s)
    }

    func testRibbonWaveCountPartialJSONDefault() throws {
        let json = #"{ "gain": 2.5 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.ribbonWaveCount, 3)
    }

    // MARK: - Backward-compat: JSON wire format must stay unchanged after rename

    func testRibbonWaveStyleEncodesAsSiriRawValue() throws {
        // .ribbonWave raw value is "siri" — existing settings.json files must still load.
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .ribbonWave
        let data = try JSONEncoder().encode(s)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["visualizerStyle"] as? String, "siri",
                       "visualizerStyle must encode as \"siri\" for backward-compat")
    }

    func testLegacySiriStyleJSONDecodesAsRibbonWave() throws {
        // Legacy settings.json files have "visualizerStyle": "siri" — they must produce .ribbonWave.
        let json = #"{ "visualizerStyle": "siri" }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.visualizerStyle, .ribbonWave)
    }

    func testRibbonWaveCountEncodesAsSiriWaveCountKey() throws {
        // The JSON key for ribbonWaveCount must remain "siriWaveCount".
        var s = VisualizerSettings.defaults
        s.ribbonWaveCount = 4
        let data = try JSONEncoder().encode(s)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["siriWaveCount"] as? Int, 4,
                       "ribbonWaveCount must encode under key \"siriWaveCount\" for backward-compat")
    }

    func testLegacySiriWaveCountKeyDecodesAsRibbonWaveCount() throws {
        // Legacy JSON with "siriWaveCount" must populate ribbonWaveCount.
        let json = #"{ "siriWaveCount": 6 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.ribbonWaveCount, 6)
    }

    func testRibbonTiltAndDepthEncodeAsLegacyKeys() throws {
        // ribbonTiltSpacing and ribbonDepthFalloff must encode under the legacy "siri*" key names.
        var s = VisualizerSettings.defaults
        s.ribbonTiltSpacing = 0.25
        s.ribbonDepthFalloff = 0.35
        let data = try JSONEncoder().encode(s)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual((json["siriTiltSpacing"] as? NSNumber)?.floatValue ?? 0, 0.25, accuracy: 1e-5,
                       "ribbonTiltSpacing must encode under \"siriTiltSpacing\"")
        XCTAssertEqual((json["siriDepthFalloff"] as? NSNumber)?.floatValue ?? 0, 0.35, accuracy: 1e-5,
                       "ribbonDepthFalloff must encode under \"siriDepthFalloff\"")
    }

    func testLegacySiriTiltAndDepthKeysDecodeAsRibbonFields() throws {
        // Legacy JSON with "siriTiltSpacing"/"siriDepthFalloff" must populate the renamed fields.
        let json = #"{ "siriTiltSpacing": 0.22, "siriDepthFalloff": 0.31 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.ribbonTiltSpacing, 0.22, accuracy: 1e-5)
        XCTAssertEqual(decoded.ribbonDepthFalloff, 0.31, accuracy: 1e-5)
    }

    // MARK: - Ribbon Wave comprehensive controls

    func testRibbonWaveControlDefaults() {
        let d = VisualizerSettings.defaults
        XCTAssertEqual(d.ribbonSampleCount, 256)
        XCTAssertEqual(d.ribbonSmoothing, 0.18, accuracy: 1e-9)
        XCTAssertEqual(d.ribbonGain, 1.6, accuracy: 1e-9)
        XCTAssertEqual(d.ribbonHeightScale, 0.40, accuracy: 1e-9)
        XCTAssertEqual(d.ribbonMotionSpeed, 0.6, accuracy: 1e-9)
        XCTAssertEqual(d.ribbonBaseFrequency, 4.0, accuracy: 1e-9)
        XCTAssertEqual(d.ribbonFrequencySpread, 4.0, accuracy: 1e-9)
        XCTAssertEqual(d.ribbonStereoPanScale, 0.27, accuracy: 1e-9)
        XCTAssertEqual(d.ribbonPhaseSwing, Double(Float.pi * 0.5), accuracy: 0)
        XCTAssertEqual(d.ribbonMaxAmplitude, 1.0, accuracy: 1e-9)
        XCTAssertEqual(d.ribbonAlpha, 1.0, accuracy: 1e-9)
    }

    func testRibbonPhaseSwingDefaultRecoversFloatPiBitPattern() {
        // The default is stored as Double(Float.pi * 0.5) so that reading it back
        // as Float recovers the EXACT bit pattern the prior hardcoded `.pi * 0.5`
        // (a Float) produced — no 1-ULP drift from a Double.pi-derived value.
        let recovered = Float(VisualizerSettings.defaults.ribbonPhaseSwing)
        XCTAssertEqual(recovered.bitPattern, (Float.pi * 0.5).bitPattern)
    }

    func testRibbonWaveControlsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.ribbonSampleCount = 128
        s.ribbonSmoothing = 0.5
        s.ribbonGain = 2.2
        s.ribbonHeightScale = 0.6
        s.ribbonMotionSpeed = 1.1
        s.ribbonBaseFrequency = 6.0
        s.ribbonFrequencySpread = 7.5
        s.ribbonStereoPanScale = 0.4
        s.ribbonPhaseSwing = 2.0
        s.ribbonMaxAmplitude = 1.5
        s.ribbonAlpha = 0.7
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.ribbonSampleCount, 128)
        XCTAssertEqual(decoded.ribbonSmoothing, 0.5, accuracy: 1e-9)
        XCTAssertEqual(decoded.ribbonGain, 2.2, accuracy: 1e-9)
        XCTAssertEqual(decoded.ribbonHeightScale, 0.6, accuracy: 1e-9)
        XCTAssertEqual(decoded.ribbonMotionSpeed, 1.1, accuracy: 1e-9)
        XCTAssertEqual(decoded.ribbonBaseFrequency, 6.0, accuracy: 1e-9)
        XCTAssertEqual(decoded.ribbonFrequencySpread, 7.5, accuracy: 1e-9)
        XCTAssertEqual(decoded.ribbonStereoPanScale, 0.4, accuracy: 1e-9)
        XCTAssertEqual(decoded.ribbonPhaseSwing, 2.0, accuracy: 1e-9)
        XCTAssertEqual(decoded.ribbonMaxAmplitude, 1.5, accuracy: 1e-9)
        XCTAssertEqual(decoded.ribbonAlpha, 0.7, accuracy: 1e-9)
        XCTAssertEqual(decoded, s)
    }

    func testRibbonWaveControlsPartialJSONDefaults() throws {
        // Old JSON without any of the new keys must decode to the defaults.
        let json = #"{ "gain": 2.5 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        let d = VisualizerSettings.defaults
        XCTAssertEqual(decoded.ribbonSampleCount, d.ribbonSampleCount)
        XCTAssertEqual(decoded.ribbonSmoothing, d.ribbonSmoothing, accuracy: 1e-9)
        XCTAssertEqual(decoded.ribbonGain, d.ribbonGain, accuracy: 1e-9)
        XCTAssertEqual(decoded.ribbonHeightScale, d.ribbonHeightScale, accuracy: 1e-9)
        XCTAssertEqual(decoded.ribbonMotionSpeed, d.ribbonMotionSpeed, accuracy: 1e-9)
        XCTAssertEqual(decoded.ribbonBaseFrequency, d.ribbonBaseFrequency, accuracy: 1e-9)
        XCTAssertEqual(decoded.ribbonFrequencySpread, d.ribbonFrequencySpread, accuracy: 1e-9)
        XCTAssertEqual(decoded.ribbonStereoPanScale, d.ribbonStereoPanScale, accuracy: 1e-9)
        XCTAssertEqual(decoded.ribbonPhaseSwing, d.ribbonPhaseSwing, accuracy: 0)
        XCTAssertEqual(decoded.ribbonMaxAmplitude, d.ribbonMaxAmplitude, accuracy: 1e-9)
        XCTAssertEqual(decoded.ribbonAlpha, d.ribbonAlpha, accuracy: 1e-9)
    }

    func testResetCurrentStyleRestoresAllRibbonWaveControls() {
        let d = VisualizerSettings.defaults
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .ribbonWave
        s.ribbonSampleCount = 64
        s.ribbonSmoothing = 0.9
        s.ribbonGain = 3.0
        s.ribbonHeightScale = 0.9
        s.ribbonMotionSpeed = 2.5
        s.ribbonBaseFrequency = 12.0
        s.ribbonFrequencySpread = 15.0
        s.ribbonStereoPanScale = 0.8
        s.ribbonPhaseSwing = 3.0
        s.ribbonMaxAmplitude = 1.9
        s.ribbonAlpha = 0.2

        s.resetCurrentStyle()

        XCTAssertEqual(s.ribbonSampleCount, d.ribbonSampleCount)
        XCTAssertEqual(s.ribbonSmoothing, d.ribbonSmoothing, accuracy: 1e-9)
        XCTAssertEqual(s.ribbonGain, d.ribbonGain, accuracy: 1e-9)
        XCTAssertEqual(s.ribbonHeightScale, d.ribbonHeightScale, accuracy: 1e-9)
        XCTAssertEqual(s.ribbonMotionSpeed, d.ribbonMotionSpeed, accuracy: 1e-9)
        XCTAssertEqual(s.ribbonBaseFrequency, d.ribbonBaseFrequency, accuracy: 1e-9)
        XCTAssertEqual(s.ribbonFrequencySpread, d.ribbonFrequencySpread, accuracy: 1e-9)
        XCTAssertEqual(s.ribbonStereoPanScale, d.ribbonStereoPanScale, accuracy: 1e-9)
        XCTAssertEqual(s.ribbonPhaseSwing, d.ribbonPhaseSwing, accuracy: 0)
        XCTAssertEqual(s.ribbonMaxAmplitude, d.ribbonMaxAmplitude, accuracy: 1e-9)
        XCTAssertEqual(s.ribbonAlpha, d.ribbonAlpha, accuracy: 1e-9)
    }

    func testResetRibbonWaveDoesNotTouchOtherStyleControls() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .ribbonWave
        s.heightfieldZScale = 0.9
        s.particlesBaseSize = 0.5
        s.resetCurrentStyle()
        XCTAssertEqual(s.heightfieldZScale, 0.9, accuracy: 1e-9)
        XCTAssertEqual(s.particlesBaseSize, 0.5, accuracy: 1e-9)
    }

    // MARK: - Joy Plot comprehensive controls

    func testJoyPlotControlDefaults() {
        let d = VisualizerSettings.defaults
        XCTAssertEqual(d.joyPlotSampleCount, 64)
        XCTAssertEqual(d.joyPlotRowSpacing, 0.4, accuracy: 1e-9)
        XCTAssertEqual(d.joyPlotRowHeight, 0.15, accuracy: 1e-9)
        XCTAssertEqual(d.joyPlotBaselineOffset, 0.0, accuracy: 1e-9)
        XCTAssertEqual(d.joyPlotXExtent, 1.0, accuracy: 1e-9)
        XCTAssertEqual(d.joyPlotBeatHalfLife, 0.15, accuracy: 1e-9)
        XCTAssertEqual(d.joyPlotBeatBoost, 0.5, accuracy: 1e-9)
        XCTAssertEqual(d.joyPlotBottomDim, 0.3, accuracy: 1e-9)
        XCTAssertEqual(d.joyPlotAlpha, 1.0, accuracy: 1e-9)
    }

    func testJoyPlotDefaultsAreFloatBitExact() {
        // Every Double default must convert to Float with the EXACT bit pattern
        // of the prior hardcoded Float literal — no 1-ULP drift through Double.
        let d = VisualizerSettings.defaults
        XCTAssertEqual(Float(d.joyPlotRowSpacing).bitPattern, (0.4 as Float).bitPattern)
        XCTAssertEqual(Float(d.joyPlotRowHeight).bitPattern, (0.15 as Float).bitPattern)
        XCTAssertEqual(Float(d.joyPlotBaselineOffset).bitPattern, (0.0 as Float).bitPattern)
        XCTAssertEqual(Float(d.joyPlotXExtent).bitPattern, (1.0 as Float).bitPattern)
        XCTAssertEqual(Float(d.joyPlotBeatHalfLife).bitPattern, (0.15 as Float).bitPattern)
        XCTAssertEqual(Float(d.joyPlotBeatBoost).bitPattern, (0.5 as Float).bitPattern)
        XCTAssertEqual(Float(d.joyPlotBottomDim).bitPattern, (0.3 as Float).bitPattern)
        XCTAssertEqual(Float(d.joyPlotAlpha).bitPattern, (1.0 as Float).bitPattern)
    }

    func testJoyPlotControlsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.joyPlotSampleCount = 128
        s.joyPlotRowSpacing = 0.6
        s.joyPlotRowHeight = 0.3
        s.joyPlotBaselineOffset = -0.2
        s.joyPlotXExtent = 1.5
        s.joyPlotBeatHalfLife = 0.4
        s.joyPlotBeatBoost = 2.0
        s.joyPlotBottomDim = 0.7
        s.joyPlotAlpha = 0.5
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.joyPlotSampleCount, 128)
        XCTAssertEqual(decoded.joyPlotRowSpacing, 0.6, accuracy: 1e-9)
        XCTAssertEqual(decoded.joyPlotRowHeight, 0.3, accuracy: 1e-9)
        XCTAssertEqual(decoded.joyPlotBaselineOffset, -0.2, accuracy: 1e-9)
        XCTAssertEqual(decoded.joyPlotXExtent, 1.5, accuracy: 1e-9)
        XCTAssertEqual(decoded.joyPlotBeatHalfLife, 0.4, accuracy: 1e-9)
        XCTAssertEqual(decoded.joyPlotBeatBoost, 2.0, accuracy: 1e-9)
        XCTAssertEqual(decoded.joyPlotBottomDim, 0.7, accuracy: 1e-9)
        XCTAssertEqual(decoded.joyPlotAlpha, 0.5, accuracy: 1e-9)
        XCTAssertEqual(decoded, s)
    }

    func testJoyPlotControlsPartialJSONDefaults() throws {
        // Old JSON without any of the new keys must decode to the defaults.
        let json = #"{ "gain": 2.5 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        let d = VisualizerSettings.defaults
        XCTAssertEqual(decoded.joyPlotSampleCount, d.joyPlotSampleCount)
        XCTAssertEqual(decoded.joyPlotRowSpacing, d.joyPlotRowSpacing, accuracy: 1e-9)
        XCTAssertEqual(decoded.joyPlotRowHeight, d.joyPlotRowHeight, accuracy: 1e-9)
        XCTAssertEqual(decoded.joyPlotBaselineOffset, d.joyPlotBaselineOffset, accuracy: 1e-9)
        XCTAssertEqual(decoded.joyPlotXExtent, d.joyPlotXExtent, accuracy: 1e-9)
        XCTAssertEqual(decoded.joyPlotBeatHalfLife, d.joyPlotBeatHalfLife, accuracy: 1e-9)
        XCTAssertEqual(decoded.joyPlotBeatBoost, d.joyPlotBeatBoost, accuracy: 1e-9)
        XCTAssertEqual(decoded.joyPlotBottomDim, d.joyPlotBottomDim, accuracy: 1e-9)
        XCTAssertEqual(decoded.joyPlotAlpha, d.joyPlotAlpha, accuracy: 1e-9)
    }

    func testResetCurrentStyleRestoresAllJoyPlotControls() {
        let d = VisualizerSettings.defaults
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .joyPlot
        s.joyPlotSampleCount = 256
        s.joyPlotRowSpacing = 0.9
        s.joyPlotRowHeight = 0.5
        s.joyPlotBaselineOffset = 0.3
        s.joyPlotXExtent = 1.8
        s.joyPlotBeatHalfLife = 1.0
        s.joyPlotBeatBoost = 2.5
        s.joyPlotBottomDim = 0.1
        s.joyPlotAlpha = 0.2

        s.resetCurrentStyle()

        XCTAssertEqual(s.joyPlotSampleCount, d.joyPlotSampleCount)
        XCTAssertEqual(s.joyPlotRowSpacing, d.joyPlotRowSpacing, accuracy: 1e-9)
        XCTAssertEqual(s.joyPlotRowHeight, d.joyPlotRowHeight, accuracy: 1e-9)
        XCTAssertEqual(s.joyPlotBaselineOffset, d.joyPlotBaselineOffset, accuracy: 1e-9)
        XCTAssertEqual(s.joyPlotXExtent, d.joyPlotXExtent, accuracy: 1e-9)
        XCTAssertEqual(s.joyPlotBeatHalfLife, d.joyPlotBeatHalfLife, accuracy: 1e-9)
        XCTAssertEqual(s.joyPlotBeatBoost, d.joyPlotBeatBoost, accuracy: 1e-9)
        XCTAssertEqual(s.joyPlotBottomDim, d.joyPlotBottomDim, accuracy: 1e-9)
        XCTAssertEqual(s.joyPlotAlpha, d.joyPlotAlpha, accuracy: 1e-9)
    }

    func testResetJoyPlotDoesNotTouchOtherStyleControls() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .joyPlot
        s.heightfieldZScale = 0.9
        s.ribbonGain = 3.0
        s.resetCurrentStyle()
        XCTAssertEqual(s.heightfieldZScale, 0.9, accuracy: 1e-9)
        XCTAssertEqual(s.ribbonGain, 3.0, accuracy: 1e-9)
    }

    func testTrailPersistenceDefaultsOff() {
        XCTAssertEqual(VisualizerSettings.defaults.trailPersistence, 0, accuracy: 1e-6)
    }

    func testTrailPersistenceRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.trailPersistence = 0.85
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.trailPersistence, 0.85, accuracy: 1e-6)
        XCTAssertEqual(decoded, s)
    }

    func testTrailPersistencePartialJSONDefaults() throws {
        let json = #"{ "gain": 2.5 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.trailPersistence, 0, accuracy: 1e-6)
    }

    func testFFTWindowDefaultsToHann() {
        XCTAssertEqual(VisualizerSettings.defaults.fftWindow, .hann)
    }

    func testFFTWindowAllCasesPresent() {
        XCTAssertEqual(FFTWindow.allCases.count, 4)
        XCTAssertTrue(FFTWindow.allCases.contains(.rectangular))
        XCTAssertTrue(FFTWindow.allCases.contains(.hann))
        XCTAssertTrue(FFTWindow.allCases.contains(.hamming))
        XCTAssertTrue(FFTWindow.allCases.contains(.blackman))
    }

    func testFFTWindowRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.fftWindow = .blackman
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.fftWindow, .blackman)
        XCTAssertEqual(decoded, s)
    }

    func testFFTWindowPartialJSONDefaults() throws {
        let json = #"{ "gain": 2.5 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.fftWindow, .hann)
    }

    func testVignetteDefaultsOff() {
        XCTAssertEqual(VisualizerSettings.defaults.vignetteAmount, 0, accuracy: 1e-6)
    }

    func testVignetteRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.vignetteAmount = 0.4
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.vignetteAmount, 0.4, accuracy: 1e-6)
        XCTAssertEqual(decoded, s)
    }

    func testVignettePartialJSONDefaults() throws {
        let json = #"{ "gain": 2.5 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.vignetteAmount, 0, accuracy: 1e-6)
    }

    func testLegacyJSONWithGrainAmountDecodesSafely() throws {
        // Verifies that user settings.json files containing the removed
        // `grainAmount` key still load cleanly (tolerant decoder ignores unknown keys).
        let legacy = #"{ "gain": 2.5, "grainAmount": 0.5 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: legacy)
        XCTAssertEqual(decoded.vignetteAmount, 0, accuracy: 1e-6)
    }

    func testKaleidoscopeFoldsDefaultsZero() {
        XCTAssertEqual(VisualizerSettings.defaults.kaleidoscopeFolds, 0)
    }

    func testKaleidoscopeFoldsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.kaleidoscopeFolds = 6
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.kaleidoscopeFolds, 6)
        XCTAssertEqual(decoded, s)
    }

    func testKaleidoscopeFoldsPartialJSONDefaults() throws {
        let json = #"{ "gain": 2.5 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.kaleidoscopeFolds, 0)
    }

    func testUseStereoImageDefaultsFalse() {
        XCTAssertEqual(VisualizerSettings.defaults.useStereoImage, false)
    }

    func testUseStereoImageRoundtrip() throws {
        var s = VisualizerSettings.defaults
        s.useStereoImage = true
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertTrue(decoded.useStereoImage)
    }

    func testWindowTransparencyDefaults() {
        let d = VisualizerSettings.defaults
        XCTAssertEqual(d.windowTransparencyMode, .perPixelAlpha)
        XCTAssertEqual(d.windowOpacity, 1.0, accuracy: 1e-6)
        XCTAssertFalse(d.clickThroughEnabled)
        XCTAssertFalse(d.borderlessWindow)
    }

    func testWindowTransparencyRoundtrip() throws {
        var s = VisualizerSettings.defaults
        s.windowTransparencyMode = .perPixelAlpha
        s.windowOpacity = 0.7
        s.clickThroughEnabled = true
        s.borderlessWindow = true
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.windowTransparencyMode, .perPixelAlpha)
        XCTAssertEqual(decoded.windowOpacity, 0.7, accuracy: 1e-6)
        XCTAssertTrue(decoded.clickThroughEnabled)
        XCTAssertTrue(decoded.borderlessWindow)
    }

    func testLegacyJSONWithoutWindowFieldsDecodes() throws {
        let legacy = """
        { "visualizerStyle": "bars", "useStereoImage": false }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: legacy)
        XCTAssertEqual(decoded.windowTransparencyMode, .perPixelAlpha)
        XCTAssertEqual(decoded.windowOpacity, 1.0, accuracy: 1e-6)
        XCTAssertFalse(decoded.clickThroughEnabled)
        XCTAssertFalse(decoded.borderlessWindow)
    }

    func testCenterBelowLyricsDefaultsOn() {
        XCTAssertTrue(VisualizerSettings.defaults.centerBelowLyrics)
    }

    func testCenterBelowLyricsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.centerBelowLyrics = false
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertFalse(decoded.centerBelowLyrics)
    }

    func testLegacyJSONWithoutCenterBelowLyricsDefaultsOn() throws {
        let legacy = """
        { "visualizerStyle": "iris" }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: legacy)
        XCTAssertTrue(decoded.centerBelowLyrics)
    }

    func testWindowBorderDefaults() {
        let d = VisualizerSettings.defaults
        XCTAssertEqual(d.windowBorderMode, .off)
        XCTAssertFalse(d.windowBorderEnabled)   // computed: off → disabled
        XCTAssertEqual(d.windowBorderColor, RGBAColor(r: 1, g: 1, b: 1, a: 1))
        XCTAssertEqual(d.windowBorderOpacity, 0.7, accuracy: 1e-6)
        XCTAssertEqual(d.windowBorderWidth, 1.0, accuracy: 1e-6)
    }

    func testWindowBorderEnabledComputedFromMode() {
        var s = VisualizerSettings.defaults
        s.windowBorderMode = .off
        XCTAssertFalse(s.windowBorderEnabled)
        s.windowBorderMode = .auto
        XCTAssertTrue(s.windowBorderEnabled)
        s.windowBorderMode = .always
        XCTAssertTrue(s.windowBorderEnabled)
    }

    func testWindowBorderRoundTrip() throws {
        for mode in WindowBorderMode.allCases {
            var s = VisualizerSettings.defaults
            s.windowBorderMode = mode
            s.windowBorderColor = RGBAColor(r: 0.2, g: 0.6, b: 0.9, a: 1)
            s.windowBorderOpacity = 0.35
            s.windowBorderWidth = 4.5
            let data = try JSONEncoder().encode(s)
            let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
            XCTAssertEqual(decoded.windowBorderMode, mode)
            XCTAssertEqual(decoded.windowBorderColor, RGBAColor(r: 0.2, g: 0.6, b: 0.9, a: 1))
            XCTAssertEqual(decoded.windowBorderOpacity, 0.35, accuracy: 1e-6)
            XCTAssertEqual(decoded.windowBorderWidth, 4.5, accuracy: 1e-6)
        }
    }

    // Migration: the field used to be a Bool `windowBorderEnabled`.
    func testLegacyWindowBorderEnabledTrueMapsToAlways() throws {
        let legacy = """
        { "visualizerStyle": "bars", "windowBorderEnabled": true }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: legacy)
        XCTAssertEqual(decoded.windowBorderMode, .always)
    }

    func testLegacyWindowBorderEnabledFalseMapsToOff() throws {
        let legacy = """
        { "visualizerStyle": "bars", "windowBorderEnabled": false }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: legacy)
        XCTAssertEqual(decoded.windowBorderMode, .off)
    }

    func testWindowBorderModeDefaultsOffWhenNoBorderKeys() throws {
        let legacy = """
        { "visualizerStyle": "bars" }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: legacy)
        XCTAssertEqual(decoded.windowBorderMode, .off)
    }

    func testWindowBorderModeWinsOverLegacyEnabled() throws {
        // A newer save carries both keys; the explicit mode must win.
        let mixed = """
        { "visualizerStyle": "bars", "windowBorderMode": "auto", "windowBorderEnabled": true }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: mixed)
        XCTAssertEqual(decoded.windowBorderMode, .auto)
    }

    func testLegacyJSONWithoutWindowBorderDecodes() throws {
        let legacy = """
        { "visualizerStyle": "bars", "borderlessWindow": true }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: legacy)
        XCTAssertFalse(decoded.windowBorderEnabled)
        XCTAssertEqual(decoded.windowBorderColor, RGBAColor(r: 1, g: 1, b: 1, a: 1))
        XCTAssertEqual(decoded.windowBorderOpacity, 0.7, accuracy: 1e-6)
        XCTAssertEqual(decoded.windowBorderWidth, 1.0, accuracy: 1e-6)
    }

    func testPolartoneDefaults() {
        let d = VisualizerSettings.defaults
        XCTAssertEqual(d.polartoneRadius, 0.46, accuracy: 1e-6)
        XCTAssertEqual(d.polartoneAmplitude, 0.22, accuracy: 1e-6)
    }

    /// Pins each NEW Polartone control's default to the exact pre-control literal,
    /// so the default render stays byte-identical (parity gate).
    func testPolartoneNewControlDefaultsMatchPriorLiterals() {
        let d = VisualizerSettings.defaults
        XCTAssertEqual(d.polartoneColorFloor, 0.12, accuracy: 1e-6)        // PolartoneVisualizer.swift:61 (was max(value, 0.12))
        XCTAssertEqual(d.polartoneRotationSpeed, 0, accuracy: 1e-6)        // static ring (no time term before)
        XCTAssertEqual(d.polartonePointCount, 256)                        // == SpectrumAnalyzer.waveformPointCount (live length)
        XCTAssertEqual(d.polartonePhaseOffset, 0, accuracy: 1e-6)         // ring started at angle 0
        XCTAssertEqual(d.polartoneLineHalfThickness, 0.006, accuracy: 1e-6) // PolartoneVisualizer.swift:25 (was let halfThickness = 0.006)
        XCTAssertEqual(d.polartoneWaveformClamp, 1, accuracy: 1e-6)       // was min(max(sample, -1), 1)
    }

    func testPolartoneRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.polartoneRadius = 0.7
        s.polartoneAmplitude = 0.35
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.polartoneRadius, 0.7, accuracy: 1e-6)
        XCTAssertEqual(decoded.polartoneAmplitude, 0.35, accuracy: 1e-6)
        XCTAssertEqual(decoded, s)
    }

    func testPolartoneNewControlsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.polartoneColorFloor = 0.3
        s.polartoneRotationSpeed = -1.5
        s.polartonePointCount = 512
        s.polartonePhaseOffset = 1.25
        s.polartoneLineHalfThickness = 0.015
        s.polartoneWaveformClamp = 1.75
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.polartoneColorFloor, 0.3, accuracy: 1e-6)
        XCTAssertEqual(decoded.polartoneRotationSpeed, -1.5, accuracy: 1e-6)
        XCTAssertEqual(decoded.polartonePointCount, 512)
        XCTAssertEqual(decoded.polartonePhaseOffset, 1.25, accuracy: 1e-6)
        XCTAssertEqual(decoded.polartoneLineHalfThickness, 0.015, accuracy: 1e-6)
        XCTAssertEqual(decoded.polartoneWaveformClamp, 1.75, accuracy: 1e-6)
        XCTAssertEqual(decoded, s)
    }

    func testPolartonePartialJSONDefaults() throws {
        // Old settings.json files omit both keys; tolerant decoder yields the defaults.
        let json = #"{ "gain": 2.5 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.polartoneRadius, 0.46, accuracy: 1e-6)
        XCTAssertEqual(decoded.polartoneAmplitude, 0.22, accuracy: 1e-6)
    }

    func testPolartoneNewControlsPartialJSONDefaults() throws {
        // Settings files written before these controls existed omit the keys;
        // the tolerant decoder fills in the parity-preserving defaults.
        let json = #"{ "polartoneRadius": 0.5 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.polartoneColorFloor, 0.12, accuracy: 1e-6)
        XCTAssertEqual(decoded.polartoneRotationSpeed, 0, accuracy: 1e-6)
        XCTAssertEqual(decoded.polartonePointCount, 256)
        XCTAssertEqual(decoded.polartonePhaseOffset, 0, accuracy: 1e-6)
        XCTAssertEqual(decoded.polartoneLineHalfThickness, 0.006, accuracy: 1e-6)
        XCTAssertEqual(decoded.polartoneWaveformClamp, 1, accuracy: 1e-6)
    }

    // MARK: - Star Nest controls

    func testStarNestDefaults() {
        let s = VisualizerSettings.defaults
        XCTAssertEqual(s.starNestZoom, 0.78, accuracy: 1e-9)
        XCTAssertEqual(s.starNestSpeed, 0.18, accuracy: 1e-9)
        XCTAssertEqual(s.starNestFormuparam, 0.53, accuracy: 1e-9)
        XCTAssertEqual(s.starNestTile, 0.85, accuracy: 1e-9)
        XCTAssertEqual(s.starNestStepsize, 0.105, accuracy: 1e-9)
        XCTAssertEqual(s.starNestBrightness, 0.00095, accuracy: 1e-9)
        XCTAssertEqual(s.starNestDarkmatter, 0.34, accuracy: 1e-9)
        XCTAssertEqual(s.starNestDistfading, 0.73, accuracy: 1e-9)
        XCTAssertEqual(s.starNestSaturation, 0.82, accuracy: 1e-9)
        XCTAssertEqual(s.starNestVolsteps, 18)
        XCTAssertEqual(s.starNestIterations, 13)
    }

    func testStarNestCodableRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.starNestZoom = 1.5
        s.starNestVolsteps = 22
        s.starNestIterations = 9
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    func testStarNestDensityClampsOnDecode() throws {
        // Corrupt / hand-edited JSON with out-of-range density ints is normalized
        // to the shader's hard GPU caps at the decode layer (round-trip too).
        let hiJSON = #"{ "starNestVolsteps": 999, "starNestIterations": 999 }"#.data(using: .utf8)!
        let hi = try JSONDecoder().decode(VisualizerSettings.self, from: hiJSON)
        XCTAssertEqual(hi.starNestVolsteps, 26)
        XCTAssertEqual(hi.starNestIterations, 16)

        let loJSON = #"{ "starNestVolsteps": -5, "starNestIterations": 0 }"#.data(using: .utf8)!
        let lo = try JSONDecoder().decode(VisualizerSettings.self, from: loJSON)
        XCTAssertEqual(lo.starNestVolsteps, 1)
        XCTAssertEqual(lo.starNestIterations, 1)
    }

    func testStarNestTolerantDecodeMissingKeys() throws {
        // Legacy JSON lacking the new keys decodes to defaults.
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.starNestZoom, 0.78, accuracy: 1e-9)
        XCTAssertEqual(decoded.starNestVolsteps, 18)
    }

    // MARK: - Polartone spiral render mode + spiral-only fields

    func testPolartoneRenderModeDefaultsToRing() {
        XCTAssertEqual(VisualizerSettings.defaults.polartoneRenderMode, .ring)
    }

    func testPolartoneSpiralFieldDefaults() {
        let d = VisualizerSettings.defaults
        XCTAssertEqual(d.polartoneInnerThreshold, 0.05, accuracy: 1e-6)
        XCTAssertEqual(d.polartoneDriftRevolutions, 8, accuracy: 1e-6)
        XCTAssertEqual(d.polartoneStartDirection, .inward)
    }

    func testPolartoneSpiralFieldsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.polartoneRenderMode = .spiral
        s.polartoneInnerThreshold = 0.12
        s.polartoneDriftRevolutions = 14
        s.polartoneStartDirection = .outward
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.polartoneRenderMode, .spiral)
        XCTAssertEqual(decoded.polartoneInnerThreshold, 0.12, accuracy: 1e-6)
        XCTAssertEqual(decoded.polartoneDriftRevolutions, 14, accuracy: 1e-6)
        XCTAssertEqual(decoded.polartoneStartDirection, .outward)
        XCTAssertEqual(decoded, s)
    }

    func testPolartoneSpiralPartialJSONDefaults() throws {
        // Settings files written before spiral mode existed omit all four keys;
        // the tolerant decoder fills in the ring-preserving defaults.
        let json = #"{ "polartoneRadius": 0.5 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.polartoneRenderMode, .ring)
        XCTAssertEqual(decoded.polartoneInnerThreshold, 0.05, accuracy: 1e-6)
        XCTAssertEqual(decoded.polartoneDriftRevolutions, 8, accuracy: 1e-6)
        XCTAssertEqual(decoded.polartoneStartDirection, .inward)
    }

    func testLegacyJSONWithFireworksFieldsDecodesSafely() throws {
        let legacy = """
        {
          "visualizerStyle": "bars",
          "fireworksMinBass": 0.5,
          "fireworksMarginFloor": 0.1,
          "fireworksMarginScale": 0.5,
          "fireworksBaselineAlpha": 0.05,
          "demoModeEnabled": false,
          "siriWaveCount": 3,
          "particleSize": 1.0,
          "particleSpeed": 1.0,
          "barGap": 0.15,
          "oscilloscopeThickness": 1.0,
          "siriTiltSpacing": 0.18,
          "siriDepthFalloff": 0.25,
          "trailPersistence": 0,
          "fftWindow": "hann",
          "vignetteAmount": 0,
          "grainAmount": 0,
          "kaleidoscopeFolds": 0
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: legacy)
        XCTAssertEqual(decoded.visualizerStyle, .bars)
        XCTAssertFalse(decoded.useStereoImage)
    }

    // MARK: - Wireframe controls

    func testWireframeDefaultsMatchLiterals() {
        let d = VisualizerSettings.defaults
        XCTAssertEqual(d.wireframeBaseRadius, 0.50, accuracy: 1e-9)
        XCTAssertEqual(d.wireframeDisplaceScale, 0.20, accuracy: 1e-9)
        XCTAssertEqual(d.wireframeLineThickness, 0.003, accuracy: 1e-9)
        XCTAssertEqual(d.wireframeRotationSpeed, 0.5, accuracy: 1e-9)
        XCTAssertEqual(d.wireframeTiltX, 0.3, accuracy: 1e-9)
        XCTAssertEqual(d.wireframeLineOpacity, 1.0, accuracy: 1e-9)
        XCTAssertEqual(d.wireframeSubdivisions, 2)
    }

    func testWireframeFieldsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.wireframeBaseRadius = 0.7
        s.wireframeDisplaceScale = 0.4
        s.wireframeLineThickness = 0.01
        s.wireframeRotationSpeed = -1.0
        s.wireframeTiltX = 0.9
        s.wireframeLineOpacity = 0.5
        s.wireframeSubdivisions = 3
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(back, s)
    }

    func testWireframeTolerantDecodeUsesDefaultsWhenMissing() throws {
        // Legacy JSON without wireframe keys decodes to defaults.
        let json = #"{ "gain": 1.0 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.wireframeBaseRadius, 0.50, accuracy: 1e-9)
        XCTAssertEqual(decoded.wireframeSubdivisions, 2)
    }

    func testWireframeSubdivisionsClampOnDecode() throws {
        // Out-of-range persisted values clamp to 0...4 (mirror Star Nest density clamp).
        let high = #"{ "wireframeSubdivisions": 99 }"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(VisualizerSettings.self, from: high).wireframeSubdivisions, 4)
        let low = #"{ "wireframeSubdivisions": -5 }"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(VisualizerSettings.self, from: low).wireframeSubdivisions, 0)
    }

    func testResetCurrentStyleResetsWireframeFields() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .wireframe
        s.wireframeBaseRadius = 0.9
        s.wireframeSubdivisions = 4
        s.wireframeLineOpacity = 0.2
        s.resetCurrentStyle()
        XCTAssertEqual(s.wireframeBaseRadius, 0.50, accuracy: 1e-9)
        XCTAssertEqual(s.wireframeSubdivisions, 2)
        XCTAssertEqual(s.wireframeLineOpacity, 1.0, accuracy: 1e-9)
    }

    // MARK: - Outrun the Rain controls

    /// Mutating every Outrun field then encoding/decoding reproduces the value
    /// exactly — proves all 44 fields are wired into CodingKeys/encode/decode.
    func testOutrunRainFieldsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.outrunHorizon = 0.7
        s.outrunHorizonGlowScale = 5.0
        s.outrunHorizonGlowBase = 0.5
        s.outrunHorizonBassGlow = 0.4
        s.outrunLowMidBackdrop = 0.2
        s.outrunBackgroundBrightness = 0.3
        s.outrunBackgroundGlow = 1.0
        s.outrunLeanBase = 0.2
        s.outrunLeanLowMid = 0.25
        s.outrunFallBase = 1.4
        s.outrunFallBass = 2.0
        s.outrunFallEnergy = 1.0
        s.outrunDensity = 90.0
        s.outrunLayer0ColumnScale = 0.7
        s.outrunLayer0FallScale = 0.9
        s.outrunLayer0Seed = 0.5
        s.outrunLayer0Thickness = 160.0
        s.outrunLayer0Weight = 0.8
        s.outrunLayer1ColumnScale = 1.2
        s.outrunLayer1FallScale = 1.1
        s.outrunLayer1Seed = 1.5
        s.outrunLayer1Thickness = 250.0
        s.outrunLayer1Weight = 1.2
        s.outrunLayer2ColumnScale = 1.8
        s.outrunLayer2FallScale = 1.4
        s.outrunLayer2Seed = 2.5
        s.outrunLayer2Thickness = 360.0
        s.outrunLayer2Weight = 0.7
        s.outrunSparkleColumnScale = 2.6
        s.outrunSparkleFallScale = 1.6
        s.outrunSparkleSeed = 3.5
        s.outrunSparkleThickness = 560.0
        s.outrunSparkleBase = 0.4
        s.outrunSparkleTreble = 2.0
        s.outrunRainVerticalBase = 0.4
        s.outrunRainVerticalY = 1.0
        s.outrunRainColorBase = 0.6
        s.outrunRainColorTreble = 0.5
        s.outrunRainColorEnergy = 0.3
        s.outrunRainBrightnessBase = 1.8
        s.outrunRainBrightnessEnergy = 1.7
        s.outrunRainBrightnessTreble = 1.4
        s.outrunReflectionWidth = 3.5
        s.outrunReflectionBass = 0.7

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    /// Legacy settings.json predating these keys decodes cleanly: every Outrun
    /// field falls back to its default (tolerant decode / migration).
    func testOutrunRainPartialJSONUsesDefaults() throws {
        let d = VisualizerSettings.defaults
        let json = #"{ "gain": 1.0 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.outrunHorizon, d.outrunHorizon, accuracy: 1e-9)
        XCTAssertEqual(decoded.outrunDensity, d.outrunDensity, accuracy: 1e-9)
        XCTAssertEqual(decoded.outrunLayer0Thickness, d.outrunLayer0Thickness, accuracy: 1e-9)
        XCTAssertEqual(decoded.outrunSparkleTreble, d.outrunSparkleTreble, accuracy: 1e-9)
        XCTAssertEqual(decoded.outrunReflectionBass, d.outrunReflectionBass, accuracy: 1e-9)
        XCTAssertEqual(decoded.outrunRainBrightnessBase, d.outrunRainBrightnessBase, accuracy: 1e-9)
    }

    /// Resetting Outrun the Rain restores all 44 of its exclusive fields.
    func testResetCurrentStyleResetsOutrunRainFields() {
        let d = VisualizerSettings.defaults
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .outrunRain
        s.outrunHorizon = 0.5
        s.outrunHorizonGlowScale = 9.0
        s.outrunBackgroundGlow = 2.5
        s.outrunDensity = 120.0
        s.outrunFallBass = 3.0
        s.outrunLayer0Thickness = 400.0
        s.outrunLayer2Weight = 1.5
        s.outrunSparkleSeed = 6.0
        s.outrunRainColorBase = 0.9
        s.outrunRainBrightnessTreble = 2.8
        s.outrunReflectionWidth = 7.0

        s.resetCurrentStyle()

        XCTAssertEqual(s.outrunHorizon, d.outrunHorizon, accuracy: 1e-9)
        XCTAssertEqual(s.outrunHorizonGlowScale, d.outrunHorizonGlowScale, accuracy: 1e-9)
        XCTAssertEqual(s.outrunBackgroundGlow, d.outrunBackgroundGlow, accuracy: 1e-9)
        XCTAssertEqual(s.outrunDensity, d.outrunDensity, accuracy: 1e-9)
        XCTAssertEqual(s.outrunFallBass, d.outrunFallBass, accuracy: 1e-9)
        XCTAssertEqual(s.outrunLayer0Thickness, d.outrunLayer0Thickness, accuracy: 1e-9)
        XCTAssertEqual(s.outrunLayer2Weight, d.outrunLayer2Weight, accuracy: 1e-9)
        XCTAssertEqual(s.outrunSparkleSeed, d.outrunSparkleSeed, accuracy: 1e-9)
        XCTAssertEqual(s.outrunRainColorBase, d.outrunRainColorBase, accuracy: 1e-9)
        XCTAssertEqual(s.outrunRainBrightnessTreble, d.outrunRainBrightnessTreble, accuracy: 1e-9)
        XCTAssertEqual(s.outrunReflectionWidth, d.outrunReflectionWidth, accuracy: 1e-9)
    }

    /// Resetting a DIFFERENT style must not disturb Outrun's exclusive fields.
    func testResetCurrentStyleLeavesOutrunRainFieldsUntouched() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .outrunRain
        s.outrunDensity = 130.0
        s.outrunHorizon = 0.45
        s.visualizerStyle = .polartone
        s.polartoneRadius = 0.9

        s.resetCurrentStyle()

        XCTAssertEqual(s.polartoneRadius, VisualizerSettings.defaults.polartoneRadius)
        XCTAssertEqual(s.outrunDensity, 130.0, accuracy: 1e-9)
        XCTAssertEqual(s.outrunHorizon, 0.45, accuracy: 1e-9)
    }

    // MARK: - Plasma controls

    /// Default values match `plasma_fs`'s original hardcoded literals so the
    /// look is byte-identical until a slider moves.
    func testPlasmaDefaults() {
        let s = VisualizerSettings.defaults
        XCTAssertEqual(s.plasmaCoordinateScale, 2.0, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaCoordinateOffset, 1.0, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaXFrequency, 8.0, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaYFrequency, 6.0, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaDiagonalFrequency, 5.0, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaXTimeScale, 1.0, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaYTimeScale, 1.3, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaDiagonalTimeScale, 0.7, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaWaveDivisor, 3.0, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaContrast, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaBrightnessBias, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaEnergyResponse, 0.3, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaClampMin, 0.0, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaClampMax, 1.0, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaAlpha, 1.0, accuracy: 1e-9)
    }

    func testPlasmaFieldsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.plasmaCoordinateScale = 2.5
        s.plasmaCoordinateOffset = 1.2
        s.plasmaXFrequency = 12.0
        s.plasmaYFrequency = 9.0
        s.plasmaDiagonalFrequency = 7.0
        s.plasmaXTimeScale = 2.0
        s.plasmaYTimeScale = 2.5
        s.plasmaDiagonalTimeScale = 1.5
        s.plasmaWaveDivisor = 4.0
        s.plasmaContrast = 1.2
        s.plasmaBrightnessBias = 0.4
        s.plasmaEnergyResponse = 0.8
        s.plasmaClampMin = 0.1
        s.plasmaClampMax = 0.9
        s.plasmaAlpha = 0.8

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    /// Legacy settings.json predating these keys decodes cleanly: every Plasma
    /// field falls back to its default (tolerant decode / migration).
    func testPlasmaPartialJSONUsesDefaults() throws {
        let d = VisualizerSettings.defaults
        let json = #"{ "gain": 1.0 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.plasmaCoordinateScale, d.plasmaCoordinateScale, accuracy: 1e-9)
        XCTAssertEqual(decoded.plasmaXFrequency, d.plasmaXFrequency, accuracy: 1e-9)
        XCTAssertEqual(decoded.plasmaYTimeScale, d.plasmaYTimeScale, accuracy: 1e-9)
        XCTAssertEqual(decoded.plasmaWaveDivisor, d.plasmaWaveDivisor, accuracy: 1e-9)
        XCTAssertEqual(decoded.plasmaEnergyResponse, d.plasmaEnergyResponse, accuracy: 1e-9)
        XCTAssertEqual(decoded.plasmaAlpha, d.plasmaAlpha, accuracy: 1e-9)
    }

    /// Resetting Plasma restores all 15 of its exclusive fields.
    func testResetCurrentStyleResetsPlasmaFields() {
        let d = VisualizerSettings.defaults
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .plasma
        s.plasmaCoordinateScale = 4.0
        s.plasmaCoordinateOffset = 1.8
        s.plasmaXFrequency = 20.0
        s.plasmaYFrequency = 18.0
        s.plasmaDiagonalFrequency = 16.0
        s.plasmaXTimeScale = 3.0
        s.plasmaYTimeScale = 3.5
        s.plasmaDiagonalTimeScale = 2.0
        s.plasmaWaveDivisor = 5.0
        s.plasmaContrast = 1.8
        s.plasmaBrightnessBias = 0.2
        s.plasmaEnergyResponse = 1.5
        s.plasmaClampMin = 0.2
        s.plasmaClampMax = 0.8
        s.plasmaAlpha = 0.4

        s.resetCurrentStyle()

        XCTAssertEqual(s.plasmaCoordinateScale, d.plasmaCoordinateScale, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaCoordinateOffset, d.plasmaCoordinateOffset, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaXFrequency, d.plasmaXFrequency, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaYFrequency, d.plasmaYFrequency, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaDiagonalFrequency, d.plasmaDiagonalFrequency, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaXTimeScale, d.plasmaXTimeScale, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaYTimeScale, d.plasmaYTimeScale, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaDiagonalTimeScale, d.plasmaDiagonalTimeScale, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaWaveDivisor, d.plasmaWaveDivisor, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaContrast, d.plasmaContrast, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaBrightnessBias, d.plasmaBrightnessBias, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaEnergyResponse, d.plasmaEnergyResponse, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaClampMin, d.plasmaClampMin, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaClampMax, d.plasmaClampMax, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaAlpha, d.plasmaAlpha, accuracy: 1e-9)
    }

    /// Resetting a DIFFERENT style must not disturb Plasma's exclusive fields.
    func testResetCurrentStyleLeavesPlasmaFieldsUntouched() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .plasma
        s.plasmaXFrequency = 22.0
        s.plasmaWaveDivisor = 5.5
        s.visualizerStyle = .polartone
        s.polartoneRadius = 0.9

        s.resetCurrentStyle()

        XCTAssertEqual(s.polartoneRadius, VisualizerSettings.defaults.polartoneRadius)
        XCTAssertEqual(s.plasmaXFrequency, 22.0, accuracy: 1e-9)
        XCTAssertEqual(s.plasmaWaveDivisor, 5.5, accuracy: 1e-9)
    }

    // MARK: - Bumpscope controls

    /// Default values match `bumpscope_fs`'s original hardcoded literals so the
    /// look is byte-identical until a slider moves.
    func testBumpscopeDefaults() {
        let s = VisualizerSettings.defaults
        XCTAssertEqual(s.bumpscopeUvClampMin, 0.0, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeUvClampMax, 1.0, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeNeighborRadius, 1)
        XCTAssertEqual(s.bumpscopeSlopeScale, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeSurfaceNormalY, 1.0, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeSurfaceNormalZ, 0.0, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeLightX, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeLightY, 0.7, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeLightZ, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeDiffuseFloor, 0.0, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeBandGain, 2.0, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeIntensityBias, 0.2, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeIntensityClampMin, 0.0, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeIntensityClampMax, 1.0, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeAlpha, 1.0, accuracy: 1e-9)
    }

    func testBumpscopeFieldsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.bumpscopeUvClampMin = 0.05
        s.bumpscopeUvClampMax = 0.95
        s.bumpscopeNeighborRadius = 5
        s.bumpscopeSlopeScale = 1.2
        s.bumpscopeSurfaceNormalY = 2.5
        s.bumpscopeSurfaceNormalZ = -0.5
        s.bumpscopeLightX = -0.3
        s.bumpscopeLightY = 0.9
        s.bumpscopeLightZ = 0.2
        s.bumpscopeDiffuseFloor = 0.3
        s.bumpscopeBandGain = 4.0
        s.bumpscopeIntensityBias = 0.6
        s.bumpscopeIntensityClampMin = 0.1
        s.bumpscopeIntensityClampMax = 0.8
        s.bumpscopeAlpha = 0.7

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    /// Legacy settings.json predating these keys decodes cleanly: every Bumpscope
    /// field falls back to its default (tolerant decode / migration).
    func testBumpscopePartialJSONUsesDefaults() throws {
        let d = VisualizerSettings.defaults
        let json = #"{ "gain": 1.0 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.bumpscopeUvClampMin, d.bumpscopeUvClampMin, accuracy: 1e-9)
        XCTAssertEqual(decoded.bumpscopeUvClampMax, d.bumpscopeUvClampMax, accuracy: 1e-9)
        XCTAssertEqual(decoded.bumpscopeNeighborRadius, d.bumpscopeNeighborRadius)
        XCTAssertEqual(decoded.bumpscopeSlopeScale, d.bumpscopeSlopeScale, accuracy: 1e-9)
        XCTAssertEqual(decoded.bumpscopeLightY, d.bumpscopeLightY, accuracy: 1e-9)
        XCTAssertEqual(decoded.bumpscopeBandGain, d.bumpscopeBandGain, accuracy: 1e-9)
        XCTAssertEqual(decoded.bumpscopeIntensityBias, d.bumpscopeIntensityBias, accuracy: 1e-9)
        XCTAssertEqual(decoded.bumpscopeAlpha, d.bumpscopeAlpha, accuracy: 1e-9)
    }

    /// Resetting Bumpscope restores all 15 of its exclusive fields.
    func testResetCurrentStyleResetsBumpscopeFields() {
        let d = VisualizerSettings.defaults
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .bumpscope
        s.bumpscopeUvClampMin = 0.2
        s.bumpscopeUvClampMax = 0.7
        s.bumpscopeNeighborRadius = 8
        s.bumpscopeSlopeScale = 2.0
        s.bumpscopeSurfaceNormalY = 3.0
        s.bumpscopeSurfaceNormalZ = 1.0
        s.bumpscopeLightX = -0.5
        s.bumpscopeLightY = 0.1
        s.bumpscopeLightZ = -0.9
        s.bumpscopeDiffuseFloor = 0.5
        s.bumpscopeBandGain = 5.0
        s.bumpscopeIntensityBias = 1.0
        s.bumpscopeIntensityClampMin = 0.3
        s.bumpscopeIntensityClampMax = 0.6
        s.bumpscopeAlpha = 0.3

        s.resetCurrentStyle()

        XCTAssertEqual(s.bumpscopeUvClampMin, d.bumpscopeUvClampMin, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeUvClampMax, d.bumpscopeUvClampMax, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeNeighborRadius, d.bumpscopeNeighborRadius)
        XCTAssertEqual(s.bumpscopeSlopeScale, d.bumpscopeSlopeScale, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeSurfaceNormalY, d.bumpscopeSurfaceNormalY, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeSurfaceNormalZ, d.bumpscopeSurfaceNormalZ, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeLightX, d.bumpscopeLightX, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeLightY, d.bumpscopeLightY, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeLightZ, d.bumpscopeLightZ, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeDiffuseFloor, d.bumpscopeDiffuseFloor, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeBandGain, d.bumpscopeBandGain, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeIntensityBias, d.bumpscopeIntensityBias, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeIntensityClampMin, d.bumpscopeIntensityClampMin, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeIntensityClampMax, d.bumpscopeIntensityClampMax, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeAlpha, d.bumpscopeAlpha, accuracy: 1e-9)
    }

    /// Resetting a DIFFERENT style must not disturb Bumpscope's exclusive fields.
    func testResetCurrentStyleLeavesBumpscopeFieldsUntouched() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .bumpscope
        s.bumpscopeBandGain = 4.5
        s.bumpscopeNeighborRadius = 7
        s.visualizerStyle = .polartone
        s.polartoneRadius = 0.9

        s.resetCurrentStyle()

        XCTAssertEqual(s.polartoneRadius, VisualizerSettings.defaults.polartoneRadius)
        XCTAssertEqual(s.bumpscopeBandGain, 4.5, accuracy: 1e-9)
        XCTAssertEqual(s.bumpscopeNeighborRadius, 7)
    }

    // MARK: - Octave Meatballs controls

    /// Default values match the shader's original hardcoded literals so the
    /// look is byte-identical until a slider moves.
    func testOctaveMeatballsDefaults() {
        let s = VisualizerSettings.defaults
        XCTAssertEqual(s.octaveMeatballsScale, 10.0, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsBallDivisor, 10.0, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsBackgroundR, 0.005, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsBackgroundG, 0.0, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsBackgroundB, 0.01, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsOctavePhase, 0.1, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsShimmerOctaveScale, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsShimmerTimeScale, 0.1, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsLifeTimeScale, 0.1, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsPulseEdge0, 0.4, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsPulseEdge1, 0.8, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsLifeOctaveScale, 0.02, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsLifeDenomBase, 0.02, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsLifeDenomRadius, 0.001, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsLifeDenomScale, 60.0, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsDistanceFloor, 0.001, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsBallStrength, 0.01, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsBallBase, 0.35, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsRedGlowR, 0.03, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsRedGlowG, 0.0, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsRedGlowB, 0.0, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsPaletteFieldGain, 1.5, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsPaletteGain, 2.0, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsBandPhase, 2.0, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsBandBrightness, 1.6, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsEnergyBrightness, 0.6, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsPaletteEnergy, 0.2, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsOctaves, 24)
    }

    /// Mutating every Octave Meatballs field then encoding/decoding reproduces
    /// the value exactly — proves all fields are wired into CodingKeys/encode/decode.
    func testOctaveMeatballsFieldsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.octaveMeatballsScale = 12.0
        s.octaveMeatballsBallDivisor = 8.0
        s.octaveMeatballsBackgroundR = 0.01
        s.octaveMeatballsBackgroundG = 0.02
        s.octaveMeatballsBackgroundB = 0.03
        s.octaveMeatballsOctavePhase = 0.2
        s.octaveMeatballsShimmerOctaveScale = 0.6
        s.octaveMeatballsShimmerTimeScale = 0.2
        s.octaveMeatballsLifeTimeScale = 0.15
        s.octaveMeatballsPulseEdge0 = 0.3
        s.octaveMeatballsPulseEdge1 = 0.9
        s.octaveMeatballsLifeOctaveScale = 0.03
        s.octaveMeatballsLifeDenomBase = 0.05
        s.octaveMeatballsLifeDenomRadius = 0.002
        s.octaveMeatballsLifeDenomScale = 80.0
        s.octaveMeatballsDistanceFloor = 0.002
        s.octaveMeatballsBallStrength = 0.02
        s.octaveMeatballsBallBase = 0.4
        s.octaveMeatballsRedGlowR = 0.05
        s.octaveMeatballsRedGlowG = 0.01
        s.octaveMeatballsRedGlowB = 0.02
        s.octaveMeatballsPaletteFieldGain = 2.0
        s.octaveMeatballsPaletteGain = 2.5
        s.octaveMeatballsBandPhase = 3.0
        s.octaveMeatballsBandBrightness = 2.0
        s.octaveMeatballsEnergyBrightness = 1.0
        s.octaveMeatballsPaletteEnergy = 0.4
        s.octaveMeatballsOctaves = 30

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    /// Legacy settings.json predating these keys decodes cleanly: every Octave
    /// Meatballs field falls back to its default (tolerant decode / migration).
    func testOctaveMeatballsPartialJSONUsesDefaults() throws {
        let d = VisualizerSettings.defaults
        let json = #"{ "gain": 1.0 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.octaveMeatballsScale, d.octaveMeatballsScale, accuracy: 1e-9)
        XCTAssertEqual(decoded.octaveMeatballsBallDivisor, d.octaveMeatballsBallDivisor, accuracy: 1e-9)
        XCTAssertEqual(decoded.octaveMeatballsPulseEdge1, d.octaveMeatballsPulseEdge1, accuracy: 1e-9)
        XCTAssertEqual(decoded.octaveMeatballsPaletteGain, d.octaveMeatballsPaletteGain, accuracy: 1e-9)
        XCTAssertEqual(decoded.octaveMeatballsBandBrightness, d.octaveMeatballsBandBrightness, accuracy: 1e-9)
        XCTAssertEqual(decoded.octaveMeatballsOctaves, d.octaveMeatballsOctaves)
    }

    /// Resetting Octave Meatballs restores all of its exclusive fields.
    func testResetCurrentStyleResetsOctaveMeatballsFields() {
        let d = VisualizerSettings.defaults
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .octaveMeatballs
        s.octaveMeatballsScale = 20.0
        s.octaveMeatballsBallDivisor = 4.0
        s.octaveMeatballsOctavePhase = 0.3
        s.octaveMeatballsPulseEdge0 = 0.1
        s.octaveMeatballsPulseEdge1 = 0.95
        s.octaveMeatballsBallBase = 0.7
        s.octaveMeatballsRedGlowR = 0.1
        s.octaveMeatballsPaletteGain = 4.0
        s.octaveMeatballsBandBrightness = 3.0
        s.octaveMeatballsOctaves = 32

        s.resetCurrentStyle()

        XCTAssertEqual(s.octaveMeatballsScale, d.octaveMeatballsScale, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsBallDivisor, d.octaveMeatballsBallDivisor, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsOctavePhase, d.octaveMeatballsOctavePhase, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsPulseEdge0, d.octaveMeatballsPulseEdge0, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsPulseEdge1, d.octaveMeatballsPulseEdge1, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsBallBase, d.octaveMeatballsBallBase, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsRedGlowR, d.octaveMeatballsRedGlowR, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsPaletteGain, d.octaveMeatballsPaletteGain, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsBandBrightness, d.octaveMeatballsBandBrightness, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsOctaves, d.octaveMeatballsOctaves)
    }

    /// Resetting a DIFFERENT style must not disturb Octave Meatballs's fields.
    func testResetCurrentStyleLeavesOctaveMeatballsFieldsUntouched() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .octaveMeatballs
        s.octaveMeatballsScale = 18.0
        s.octaveMeatballsOctaves = 30
        s.visualizerStyle = .polartone
        s.polartoneRadius = 0.9

        s.resetCurrentStyle()

        XCTAssertEqual(s.polartoneRadius, VisualizerSettings.defaults.polartoneRadius)
        XCTAssertEqual(s.octaveMeatballsScale, 18.0, accuracy: 1e-9)
        XCTAssertEqual(s.octaveMeatballsOctaves, 30)
    }

    // MARK: - Lava Lamp controls

    /// Default parity: each top-level Lava Lamp field equals the prior hardcoded
    /// literal from the shader / makeLavaLampUniforms / LavaLampVisualizer, so
    /// both render modes look byte-identical until a slider moves.
    func testLavaLampDefaults() {
        let s = VisualizerSettings.defaults
        XCTAssertEqual(s.lavaLampDensityFalloff, 8.0, accuracy: 1e-9)
        XCTAssertEqual(s.lavaLampBrightnessResponse, 0.8, accuracy: 1e-9)
        XCTAssertEqual(s.lavaLampPaletteDensityScale, 0.4, accuracy: 1e-9)
        XCTAssertEqual(s.lavaLampMotionSpeed, 0.3, accuracy: 1e-9)
        XCTAssertEqual(s.lavaLampDriftStrength, 0.3, accuracy: 1e-9)
        XCTAssertEqual(s.lavaLampWrapBounds, 1.2, accuracy: 1e-9)
        XCTAssertEqual(s.lavaLampShaderBeatBoost, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.lavaLampCpuBeatBoost, 0.2, accuracy: 1e-9)
        XCTAssertEqual(s.lavaLampCpuBeatHalfLife, 0.2, accuracy: 1e-9)
        XCTAssertEqual(s.lavaLampGridSize, 64)
        XCTAssertEqual(s.lavaLampBlobCount, 12)
    }

    /// Mutating every Lava Lamp field then encoding/decoding reproduces them
    /// exactly (round-trip via Codable).
    func testLavaLampFieldsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.lavaLampDensityFalloff = 12.0
        s.lavaLampBrightnessResponse = 1.5
        s.lavaLampPaletteDensityScale = 0.6
        s.lavaLampMotionSpeed = 0.7
        s.lavaLampDriftStrength = 0.9
        s.lavaLampWrapBounds = 1.5
        s.lavaLampShaderBeatBoost = 1.2
        s.lavaLampCpuBeatBoost = 0.8
        s.lavaLampCpuBeatHalfLife = 0.5
        s.lavaLampGridSize = 96
        s.lavaLampBlobCount = 20

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    /// Legacy settings.json predating these keys decodes cleanly: every Lava
    /// Lamp field falls back to its default (tolerant decode / migration).
    func testLavaLampPartialJSONUsesDefaults() throws {
        let d = VisualizerSettings.defaults
        let json = #"{ "gain": 1.0 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.lavaLampDensityFalloff, d.lavaLampDensityFalloff, accuracy: 1e-9)
        XCTAssertEqual(decoded.lavaLampBrightnessResponse, d.lavaLampBrightnessResponse, accuracy: 1e-9)
        XCTAssertEqual(decoded.lavaLampPaletteDensityScale, d.lavaLampPaletteDensityScale, accuracy: 1e-9)
        XCTAssertEqual(decoded.lavaLampMotionSpeed, d.lavaLampMotionSpeed, accuracy: 1e-9)
        XCTAssertEqual(decoded.lavaLampDriftStrength, d.lavaLampDriftStrength, accuracy: 1e-9)
        XCTAssertEqual(decoded.lavaLampWrapBounds, d.lavaLampWrapBounds, accuracy: 1e-9)
        XCTAssertEqual(decoded.lavaLampShaderBeatBoost, d.lavaLampShaderBeatBoost, accuracy: 1e-9)
        XCTAssertEqual(decoded.lavaLampCpuBeatBoost, d.lavaLampCpuBeatBoost, accuracy: 1e-9)
        XCTAssertEqual(decoded.lavaLampCpuBeatHalfLife, d.lavaLampCpuBeatHalfLife, accuracy: 1e-9)
        XCTAssertEqual(decoded.lavaLampGridSize, d.lavaLampGridSize)
        XCTAssertEqual(decoded.lavaLampBlobCount, d.lavaLampBlobCount)
    }

    /// Resetting Lava Lamp restores all of its exclusive top-level fields.
    func testResetCurrentStyleResetsLavaLampFields() {
        let d = VisualizerSettings.defaults
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .lavaLamp
        s.lavaLampDensityFalloff = 20.0
        s.lavaLampBrightnessResponse = 2.0
        s.lavaLampPaletteDensityScale = 1.0
        s.lavaLampMotionSpeed = 1.5
        s.lavaLampDriftStrength = 1.5
        s.lavaLampWrapBounds = 1.8
        s.lavaLampShaderBeatBoost = 2.0
        s.lavaLampCpuBeatBoost = 2.0
        s.lavaLampCpuBeatHalfLife = 1.0
        s.lavaLampGridSize = 100
        s.lavaLampBlobCount = 4

        s.resetCurrentStyle()

        XCTAssertEqual(s.lavaLampDensityFalloff, d.lavaLampDensityFalloff, accuracy: 1e-9)
        XCTAssertEqual(s.lavaLampBrightnessResponse, d.lavaLampBrightnessResponse, accuracy: 1e-9)
        XCTAssertEqual(s.lavaLampPaletteDensityScale, d.lavaLampPaletteDensityScale, accuracy: 1e-9)
        XCTAssertEqual(s.lavaLampMotionSpeed, d.lavaLampMotionSpeed, accuracy: 1e-9)
        XCTAssertEqual(s.lavaLampDriftStrength, d.lavaLampDriftStrength, accuracy: 1e-9)
        XCTAssertEqual(s.lavaLampWrapBounds, d.lavaLampWrapBounds, accuracy: 1e-9)
        XCTAssertEqual(s.lavaLampShaderBeatBoost, d.lavaLampShaderBeatBoost, accuracy: 1e-9)
        XCTAssertEqual(s.lavaLampCpuBeatBoost, d.lavaLampCpuBeatBoost, accuracy: 1e-9)
        XCTAssertEqual(s.lavaLampCpuBeatHalfLife, d.lavaLampCpuBeatHalfLife, accuracy: 1e-9)
        XCTAssertEqual(s.lavaLampGridSize, d.lavaLampGridSize)
        XCTAssertEqual(s.lavaLampBlobCount, d.lavaLampBlobCount)
    }

    /// Resetting a DIFFERENT style must not disturb Lava Lamp's fields.
    func testResetCurrentStyleLeavesLavaLampFieldsUntouched() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .lavaLamp
        s.lavaLampDensityFalloff = 22.0
        s.lavaLampBlobCount = 18
        s.visualizerStyle = .polartone
        s.polartoneRadius = 0.9

        s.resetCurrentStyle()

        XCTAssertEqual(s.polartoneRadius, VisualizerSettings.defaults.polartoneRadius)
        XCTAssertEqual(s.lavaLampDensityFalloff, 22.0, accuracy: 1e-9)
        XCTAssertEqual(s.lavaLampBlobCount, 18)
    }

    // MARK: - Voronoi controls

    /// Default values must equal the prior hardcoded literals so all three
    /// render modes look byte-identical until a slider moves.
    func testVoronoiDefaults() {
        let s = VisualizerSettings.defaults
        XCTAssertEqual(s.voronoiEdgeSharpness, 12.0, accuracy: 1e-9)
        XCTAssertEqual(s.voronoiShaderBeatBoost, 0.3, accuracy: 1e-9)
        XCTAssertEqual(s.voronoiSeedCount, 75)
        XCTAssertEqual(s.voronoiCyclePeriod, 60.0, accuracy: 1e-9)
        XCTAssertEqual(s.voronoiFadeDuration, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.voronoiDriftSpeed, 0.15, accuracy: 1e-9)
        XCTAssertEqual(s.voronoiDriftStrength, 0.05, accuracy: 1e-9)
        XCTAssertEqual(s.voronoiSeedSpread, 0.95, accuracy: 1e-9)
        XCTAssertEqual(s.voronoiTintRange, 0.1, accuracy: 1e-9)
        XCTAssertEqual(s.voronoiCpuBeatBoost, 0.3, accuracy: 1e-9)
        XCTAssertEqual(s.voronoiCpuBeatHalfLife, 0.1, accuracy: 1e-9)
        XCTAssertEqual(s.voronoiSoftBlurSigma, 1.5, accuracy: 1e-9)
    }

    func testVoronoiFieldsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.voronoiEdgeSharpness = 20.0
        s.voronoiShaderBeatBoost = 1.5
        s.voronoiSeedCount = 100
        s.voronoiCyclePeriod = 120.0
        s.voronoiFadeDuration = 1.0
        s.voronoiDriftSpeed = 0.5
        s.voronoiDriftStrength = 0.25
        s.voronoiSeedSpread = 0.7
        s.voronoiTintRange = 0.3
        s.voronoiCpuBeatBoost = 1.2
        s.voronoiCpuBeatHalfLife = 0.5
        s.voronoiSoftBlurSigma = 3.0

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    /// Legacy settings.json predating these keys decodes cleanly: every Voronoi
    /// field falls back to its default (tolerant decode / migration).
    func testVoronoiPartialJSONUsesDefaults() throws {
        let d = VisualizerSettings.defaults
        let json = #"{ "gain": 1.0 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.voronoiEdgeSharpness, d.voronoiEdgeSharpness, accuracy: 1e-9)
        XCTAssertEqual(decoded.voronoiShaderBeatBoost, d.voronoiShaderBeatBoost, accuracy: 1e-9)
        XCTAssertEqual(decoded.voronoiSeedCount, d.voronoiSeedCount)
        XCTAssertEqual(decoded.voronoiCyclePeriod, d.voronoiCyclePeriod, accuracy: 1e-9)
        XCTAssertEqual(decoded.voronoiFadeDuration, d.voronoiFadeDuration, accuracy: 1e-9)
        XCTAssertEqual(decoded.voronoiDriftSpeed, d.voronoiDriftSpeed, accuracy: 1e-9)
        XCTAssertEqual(decoded.voronoiDriftStrength, d.voronoiDriftStrength, accuracy: 1e-9)
        XCTAssertEqual(decoded.voronoiSeedSpread, d.voronoiSeedSpread, accuracy: 1e-9)
        XCTAssertEqual(decoded.voronoiTintRange, d.voronoiTintRange, accuracy: 1e-9)
        XCTAssertEqual(decoded.voronoiCpuBeatBoost, d.voronoiCpuBeatBoost, accuracy: 1e-9)
        XCTAssertEqual(decoded.voronoiCpuBeatHalfLife, d.voronoiCpuBeatHalfLife, accuracy: 1e-9)
        XCTAssertEqual(decoded.voronoiSoftBlurSigma, d.voronoiSoftBlurSigma, accuracy: 1e-9)
    }

    /// Resetting Voronoi restores all of its exclusive top-level fields.
    func testResetCurrentStyleResetsVoronoiFields() {
        let d = VisualizerSettings.defaults
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .voronoi
        s.voronoiEdgeSharpness = 30.0
        s.voronoiShaderBeatBoost = 2.0
        s.voronoiSeedCount = 120
        s.voronoiCyclePeriod = 200.0
        s.voronoiFadeDuration = 2.0
        s.voronoiDriftSpeed = 0.8
        s.voronoiDriftStrength = 0.4
        s.voronoiSeedSpread = 0.6
        s.voronoiTintRange = 0.4
        s.voronoiCpuBeatBoost = 2.5
        s.voronoiCpuBeatHalfLife = 1.5
        s.voronoiSoftBlurSigma = 4.0

        s.resetCurrentStyle()

        XCTAssertEqual(s.voronoiEdgeSharpness, d.voronoiEdgeSharpness, accuracy: 1e-9)
        XCTAssertEqual(s.voronoiShaderBeatBoost, d.voronoiShaderBeatBoost, accuracy: 1e-9)
        XCTAssertEqual(s.voronoiSeedCount, d.voronoiSeedCount)
        XCTAssertEqual(s.voronoiCyclePeriod, d.voronoiCyclePeriod, accuracy: 1e-9)
        XCTAssertEqual(s.voronoiFadeDuration, d.voronoiFadeDuration, accuracy: 1e-9)
        XCTAssertEqual(s.voronoiDriftSpeed, d.voronoiDriftSpeed, accuracy: 1e-9)
        XCTAssertEqual(s.voronoiDriftStrength, d.voronoiDriftStrength, accuracy: 1e-9)
        XCTAssertEqual(s.voronoiSeedSpread, d.voronoiSeedSpread, accuracy: 1e-9)
        XCTAssertEqual(s.voronoiTintRange, d.voronoiTintRange, accuracy: 1e-9)
        XCTAssertEqual(s.voronoiCpuBeatBoost, d.voronoiCpuBeatBoost, accuracy: 1e-9)
        XCTAssertEqual(s.voronoiCpuBeatHalfLife, d.voronoiCpuBeatHalfLife, accuracy: 1e-9)
        XCTAssertEqual(s.voronoiSoftBlurSigma, d.voronoiSoftBlurSigma, accuracy: 1e-9)
    }

    /// Resetting a DIFFERENT style must not disturb Voronoi's fields.
    func testResetCurrentStyleLeavesVoronoiFieldsUntouched() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .voronoi
        s.voronoiEdgeSharpness = 25.0
        s.voronoiSeedCount = 90
        s.visualizerStyle = .polartone
        s.polartoneRadius = 0.9

        s.resetCurrentStyle()

        XCTAssertEqual(s.polartoneRadius, VisualizerSettings.defaults.polartoneRadius)
        XCTAssertEqual(s.voronoiEdgeSharpness, 25.0, accuracy: 1e-9)
        XCTAssertEqual(s.voronoiSeedCount, 90)
    }

    // MARK: - Heightfield controls

    /// Default parity: each top-level Heightfield field equals the prior
    /// hardcoded literal from HeightfieldVisualizer, so both render modes
    /// (wireframe, solid) look byte-identical until a slider moves.
    func testHeightfieldDefaults() {
        let s = VisualizerSettings.defaults
        XCTAssertEqual(s.heightfieldGridSize, 16)
        // Stored as Double(Float.pi / 7.5) so Float(...) recovers the EXACT old
        // `Float.pi / 7.5` bit pattern (1054242639); Double.pi / 7.5 would drift 1 ULP.
        XCTAssertEqual(s.heightfieldTiltAngle, Double(Float.pi / 7.5), accuracy: 1e-12)
        XCTAssertEqual(Float(s.heightfieldTiltAngle).bitPattern, (Float.pi / 7.5).bitPattern)
        XCTAssertEqual(s.heightfieldZScale, 0.25, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldLineHalfThickness, 0.003, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldLightX, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldLightY, 0.7, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldLightZ, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldAmbientLight, 0.3, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldVerticalFit, 0.92, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldVerticalCenter, 0.071, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldBeatBoost, 0.4, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldBeatHalfLife, 0.2, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldXExtent, 1.0, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldYExtent, 1.0, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldOpacity, 1.0, accuracy: 1e-9)
    }

    /// Mutating every Heightfield field then encoding/decoding reproduces them
    /// exactly (round-trip via Codable).
    func testHeightfieldFieldsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.heightfieldGridSize = 32
        s.heightfieldTiltAngle = 0.8
        s.heightfieldZScale = 0.5
        s.heightfieldLineHalfThickness = 0.01
        s.heightfieldLightX = -0.3
        s.heightfieldLightY = 0.4
        s.heightfieldLightZ = -0.9
        s.heightfieldAmbientLight = 0.6
        s.heightfieldVerticalFit = 1.1
        s.heightfieldVerticalCenter = -0.2
        s.heightfieldBeatBoost = 1.5
        s.heightfieldBeatHalfLife = 0.5
        s.heightfieldXExtent = 1.7
        s.heightfieldYExtent = 0.6
        s.heightfieldOpacity = 0.4

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    /// Legacy settings.json predating these keys decodes cleanly: every
    /// Heightfield field falls back to its default (tolerant decode / migration).
    func testHeightfieldPartialJSONUsesDefaults() throws {
        let d = VisualizerSettings.defaults
        let json = #"{ "gain": 1.0 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.heightfieldGridSize, d.heightfieldGridSize)
        XCTAssertEqual(decoded.heightfieldTiltAngle, d.heightfieldTiltAngle, accuracy: 1e-12)
        XCTAssertEqual(decoded.heightfieldZScale, d.heightfieldZScale, accuracy: 1e-9)
        XCTAssertEqual(decoded.heightfieldLineHalfThickness, d.heightfieldLineHalfThickness, accuracy: 1e-9)
        XCTAssertEqual(decoded.heightfieldLightX, d.heightfieldLightX, accuracy: 1e-9)
        XCTAssertEqual(decoded.heightfieldLightY, d.heightfieldLightY, accuracy: 1e-9)
        XCTAssertEqual(decoded.heightfieldLightZ, d.heightfieldLightZ, accuracy: 1e-9)
        XCTAssertEqual(decoded.heightfieldAmbientLight, d.heightfieldAmbientLight, accuracy: 1e-9)
        XCTAssertEqual(decoded.heightfieldVerticalFit, d.heightfieldVerticalFit, accuracy: 1e-9)
        XCTAssertEqual(decoded.heightfieldVerticalCenter, d.heightfieldVerticalCenter, accuracy: 1e-9)
        XCTAssertEqual(decoded.heightfieldBeatBoost, d.heightfieldBeatBoost, accuracy: 1e-9)
        XCTAssertEqual(decoded.heightfieldBeatHalfLife, d.heightfieldBeatHalfLife, accuracy: 1e-9)
        XCTAssertEqual(decoded.heightfieldXExtent, d.heightfieldXExtent, accuracy: 1e-9)
        XCTAssertEqual(decoded.heightfieldYExtent, d.heightfieldYExtent, accuracy: 1e-9)
        XCTAssertEqual(decoded.heightfieldOpacity, d.heightfieldOpacity, accuracy: 1e-9)
    }

    /// Resetting Heightfield restores all of its exclusive top-level fields.
    func testResetCurrentStyleResetsHeightfieldFields() {
        let d = VisualizerSettings.defaults
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .heightfield
        s.heightfieldGridSize = 40
        s.heightfieldTiltAngle = 1.2
        s.heightfieldZScale = 0.8
        s.heightfieldLineHalfThickness = 0.015
        s.heightfieldLightX = -0.5
        s.heightfieldLightY = -0.5
        s.heightfieldLightZ = 0.9
        s.heightfieldAmbientLight = 0.9
        s.heightfieldVerticalFit = 1.15
        s.heightfieldVerticalCenter = 0.3
        s.heightfieldBeatBoost = 2.5
        s.heightfieldBeatHalfLife = 1.8
        s.heightfieldXExtent = 1.9
        s.heightfieldYExtent = 0.4
        s.heightfieldOpacity = 0.2

        s.resetCurrentStyle()

        XCTAssertEqual(s.heightfieldGridSize, d.heightfieldGridSize)
        XCTAssertEqual(s.heightfieldTiltAngle, d.heightfieldTiltAngle, accuracy: 1e-12)
        XCTAssertEqual(s.heightfieldZScale, d.heightfieldZScale, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldLineHalfThickness, d.heightfieldLineHalfThickness, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldLightX, d.heightfieldLightX, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldLightY, d.heightfieldLightY, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldLightZ, d.heightfieldLightZ, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldAmbientLight, d.heightfieldAmbientLight, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldVerticalFit, d.heightfieldVerticalFit, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldVerticalCenter, d.heightfieldVerticalCenter, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldBeatBoost, d.heightfieldBeatBoost, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldBeatHalfLife, d.heightfieldBeatHalfLife, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldXExtent, d.heightfieldXExtent, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldYExtent, d.heightfieldYExtent, accuracy: 1e-9)
        XCTAssertEqual(s.heightfieldOpacity, d.heightfieldOpacity, accuracy: 1e-9)
    }

    /// Resetting a DIFFERENT style must not disturb Heightfield's fields.
    func testResetCurrentStyleLeavesHeightfieldFieldsUntouched() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .heightfield
        s.heightfieldGridSize = 48
        s.heightfieldZScale = 0.7
        s.visualizerStyle = .polartone
        s.polartoneRadius = 0.9

        s.resetCurrentStyle()

        XCTAssertEqual(s.polartoneRadius, VisualizerSettings.defaults.polartoneRadius)
        XCTAssertEqual(s.heightfieldGridSize, 48)
        XCTAssertEqual(s.heightfieldZScale, 0.7, accuracy: 1e-9)
    }

    // MARK: - Fountain controls

    /// Default parity: each top-level Fountain field equals the prior hardcoded
    /// literal from SpectrumFountainVisualizer, so the fountain look is byte-identical
    /// until a slider moves. Each Double default reproduces the old Float literal's
    /// exact bit pattern through `Float(Double(default))` (value-preservation guard).
    func testFountainDefaults() {
        let s = VisualizerSettings.defaults
        XCTAssertEqual(s.fountainMaxParticles, 600)
        XCTAssertEqual(s.fountainSpawnRate, 15, accuracy: 1e-9)
        XCTAssertEqual(s.fountainSpawnFloor, 0.15, accuracy: 1e-9)
        XCTAssertEqual(s.fountainBaseUp, 0.55, accuracy: 1e-9)
        XCTAssertEqual(s.fountainLaunchScale, 1.6, accuracy: 1e-9)
        XCTAssertEqual(s.fountainLaunchJitter, 0.2, accuracy: 1e-9)
        XCTAssertEqual(s.fountainGravity, 1.4, accuracy: 1e-9)
        XCTAssertEqual(s.fountainHorizontalJitter, 0.04, accuracy: 1e-9)
        XCTAssertEqual(s.fountainHorizontalDrag, 0.99, accuracy: 1e-9)
        XCTAssertEqual(s.fountainBaseLifetime, 2.6, accuracy: 1e-9)
        XCTAssertEqual(s.fountainBaseSize, 0.008, accuracy: 1e-9)
        XCTAssertEqual(s.fountainBeatLaunchBoost, 0.6, accuracy: 1e-9)
        // Float-bit-pattern parity: Float(Double(default)) == old Float literal.
        XCTAssertEqual(Float(s.fountainSpawnRate).bitPattern, (15 as Float).bitPattern)
        XCTAssertEqual(Float(s.fountainSpawnFloor).bitPattern, (0.15 as Float).bitPattern)
        XCTAssertEqual(Float(s.fountainBaseUp).bitPattern, (0.55 as Float).bitPattern)
        XCTAssertEqual(Float(s.fountainLaunchScale).bitPattern, (1.6 as Float).bitPattern)
        XCTAssertEqual(Float(s.fountainLaunchJitter).bitPattern, (0.2 as Float).bitPattern)
        XCTAssertEqual(Float(s.fountainGravity).bitPattern, (1.4 as Float).bitPattern)
        XCTAssertEqual(Float(s.fountainHorizontalJitter).bitPattern, (0.04 as Float).bitPattern)
        XCTAssertEqual(Float(s.fountainHorizontalDrag).bitPattern, (0.99 as Float).bitPattern)
        XCTAssertEqual(Float(s.fountainBaseLifetime).bitPattern, (2.6 as Float).bitPattern)
        XCTAssertEqual(Float(s.fountainBaseSize).bitPattern, (0.008 as Float).bitPattern)
        XCTAssertEqual(Float(s.fountainBeatLaunchBoost).bitPattern, (0.6 as Float).bitPattern)
    }

    /// Mutating every Fountain field then encoding/decoding reproduces them exactly.
    func testFountainFieldsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.fountainMaxParticles = 1200
        s.fountainSpawnRate = 40
        s.fountainSpawnFloor = 0.3
        s.fountainBaseUp = 1.1
        s.fountainLaunchScale = 3.0
        s.fountainLaunchJitter = 0.5
        s.fountainGravity = 2.2
        s.fountainHorizontalJitter = 0.12
        s.fountainHorizontalDrag = 0.85
        s.fountainBaseLifetime = 5.0
        s.fountainBaseSize = 0.02
        s.fountainBeatLaunchBoost = 1.8

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    /// Legacy settings.json predating these keys decodes cleanly: every Fountain
    /// field falls back to its default (tolerant decode / migration).
    func testFountainPartialJSONUsesDefaults() throws {
        let d = VisualizerSettings.defaults
        let json = #"{ "gain": 1.0 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.fountainMaxParticles, d.fountainMaxParticles)
        XCTAssertEqual(decoded.fountainSpawnRate, d.fountainSpawnRate, accuracy: 1e-9)
        XCTAssertEqual(decoded.fountainSpawnFloor, d.fountainSpawnFloor, accuracy: 1e-9)
        XCTAssertEqual(decoded.fountainBaseUp, d.fountainBaseUp, accuracy: 1e-9)
        XCTAssertEqual(decoded.fountainLaunchScale, d.fountainLaunchScale, accuracy: 1e-9)
        XCTAssertEqual(decoded.fountainLaunchJitter, d.fountainLaunchJitter, accuracy: 1e-9)
        XCTAssertEqual(decoded.fountainGravity, d.fountainGravity, accuracy: 1e-9)
        XCTAssertEqual(decoded.fountainHorizontalJitter, d.fountainHorizontalJitter, accuracy: 1e-9)
        XCTAssertEqual(decoded.fountainHorizontalDrag, d.fountainHorizontalDrag, accuracy: 1e-9)
        XCTAssertEqual(decoded.fountainBaseLifetime, d.fountainBaseLifetime, accuracy: 1e-9)
        XCTAssertEqual(decoded.fountainBaseSize, d.fountainBaseSize, accuracy: 1e-9)
        XCTAssertEqual(decoded.fountainBeatLaunchBoost, d.fountainBeatLaunchBoost, accuracy: 1e-9)
    }

    /// Resetting Fountain restores all of its exclusive top-level fields.
    func testResetCurrentStyleResetsFountainFields() {
        let d = VisualizerSettings.defaults
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .fountain
        s.fountainMaxParticles = 2000
        s.fountainSpawnRate = 50
        s.fountainSpawnFloor = 0.6
        s.fountainBaseUp = 1.9
        s.fountainLaunchScale = 4.4
        s.fountainLaunchJitter = 0.8
        s.fountainGravity = 3.3
        s.fountainHorizontalJitter = 0.2
        s.fountainHorizontalDrag = 0.82
        s.fountainBaseLifetime = 7.0
        s.fountainBaseSize = 0.03
        s.fountainBeatLaunchBoost = 2.5

        s.resetCurrentStyle()

        XCTAssertEqual(s.fountainMaxParticles, d.fountainMaxParticles)
        XCTAssertEqual(s.fountainSpawnRate, d.fountainSpawnRate, accuracy: 1e-9)
        XCTAssertEqual(s.fountainSpawnFloor, d.fountainSpawnFloor, accuracy: 1e-9)
        XCTAssertEqual(s.fountainBaseUp, d.fountainBaseUp, accuracy: 1e-9)
        XCTAssertEqual(s.fountainLaunchScale, d.fountainLaunchScale, accuracy: 1e-9)
        XCTAssertEqual(s.fountainLaunchJitter, d.fountainLaunchJitter, accuracy: 1e-9)
        XCTAssertEqual(s.fountainGravity, d.fountainGravity, accuracy: 1e-9)
        XCTAssertEqual(s.fountainHorizontalJitter, d.fountainHorizontalJitter, accuracy: 1e-9)
        XCTAssertEqual(s.fountainHorizontalDrag, d.fountainHorizontalDrag, accuracy: 1e-9)
        XCTAssertEqual(s.fountainBaseLifetime, d.fountainBaseLifetime, accuracy: 1e-9)
        XCTAssertEqual(s.fountainBaseSize, d.fountainBaseSize, accuracy: 1e-9)
        XCTAssertEqual(s.fountainBeatLaunchBoost, d.fountainBeatLaunchBoost, accuracy: 1e-9)
    }

    /// Resetting a DIFFERENT style must not disturb Fountain's fields.
    func testResetCurrentStyleLeavesFountainFieldsUntouched() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .fountain
        s.fountainMaxParticles = 1500
        s.fountainGravity = 2.7
        s.visualizerStyle = .polartone
        s.polartoneRadius = 0.9

        s.resetCurrentStyle()

        XCTAssertEqual(s.polartoneRadius, VisualizerSettings.defaults.polartoneRadius)
        XCTAssertEqual(s.fountainMaxParticles, 1500)
        XCTAssertEqual(s.fountainGravity, 2.7, accuracy: 1e-9)
    }

    /// Resetting Fountain must not touch the shared top-level particle fields
    /// (size/speed back particles + fountain + fireworks).
    func testResetCurrentStyleFountainDoesNotTouchSharedFields() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .fountain
        s.particleSize = 2.0
        s.particleSpeed = 1.7

        s.resetCurrentStyle()

        XCTAssertEqual(s.particleSize, 2.0)
        XCTAssertEqual(s.particleSpeed, 1.7)
    }

    // MARK: - Fireworks controls

    /// Default parity: each top-level Fireworks field equals the prior hardcoded
    /// literal from FireworksVisualizer, so the look is byte-identical until a
    /// slider moves. Each Double default is verified double-rounding-safe (the
    /// Float it narrows to matches the original Float literal bit-for-bit).
    func testFireworksDefaults() {
        let s = VisualizerSettings.defaults
        XCTAssertEqual(s.fireworksMaxParticles, 600)
        XCTAssertEqual(s.fireworksBurstParticlesMax, 60)
        XCTAssertEqual(s.fireworksBurstParticlesMin, 8)
        XCTAssertEqual(s.fireworksBurstScaleBase, 0.7, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksBurstScaleIntensity, 0.6, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksBaseSpeed, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksSpreadSpeed, 0.2, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksGravity, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksDrag, 0.97, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksBaseLifetime, 1.5, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksLifetimeJitter, 0.3, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksMinLifetime, 0.3, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksBaseSize, 0.008, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksBurstHalfX, 0.6, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksBurstHalfY, 0.4, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksAngleJitter, 0.05, accuracy: 1e-9)

        // Double-rounding safety: Float(default Double) == the original Float literal.
        XCTAssertEqual(Float(s.fireworksBurstScaleBase).bitPattern, (0.7 as Float).bitPattern)
        XCTAssertEqual(Float(s.fireworksBurstScaleIntensity).bitPattern, (0.6 as Float).bitPattern)
        XCTAssertEqual(Float(s.fireworksBaseSpeed).bitPattern, (0.5 as Float).bitPattern)
        XCTAssertEqual(Float(s.fireworksSpreadSpeed).bitPattern, (0.2 as Float).bitPattern)
        XCTAssertEqual(Float(s.fireworksGravity).bitPattern, (0.5 as Float).bitPattern)
        XCTAssertEqual(Float(s.fireworksDrag).bitPattern, (0.97 as Float).bitPattern)
        XCTAssertEqual(Float(s.fireworksBaseLifetime).bitPattern, (1.5 as Float).bitPattern)
        XCTAssertEqual(Float(s.fireworksLifetimeJitter).bitPattern, (0.3 as Float).bitPattern)
        XCTAssertEqual(Float(s.fireworksMinLifetime).bitPattern, (0.3 as Float).bitPattern)
        XCTAssertEqual(Float(s.fireworksBaseSize).bitPattern, (0.008 as Float).bitPattern)
        XCTAssertEqual(Float(s.fireworksBurstHalfX).bitPattern, (0.6 as Float).bitPattern)
        XCTAssertEqual(Float(s.fireworksBurstHalfY).bitPattern, (0.4 as Float).bitPattern)
        XCTAssertEqual(Float(s.fireworksAngleJitter).bitPattern, (0.05 as Float).bitPattern)
    }

    /// Mutating every Fireworks field then encoding/decoding reproduces them exactly.
    func testFireworksFieldsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.fireworksMaxParticles = 1200
        s.fireworksBurstParticlesMax = 120
        s.fireworksBurstParticlesMin = 20
        s.fireworksBurstScaleBase = 1.1
        s.fireworksBurstScaleIntensity = 1.4
        s.fireworksBaseSpeed = 0.9
        s.fireworksSpreadSpeed = 0.5
        s.fireworksGravity = 2.0
        s.fireworksDrag = 0.9
        s.fireworksBaseLifetime = 3.0
        s.fireworksLifetimeJitter = 0.6
        s.fireworksMinLifetime = 0.5
        s.fireworksBaseSize = 0.02
        s.fireworksBurstHalfX = 0.8
        s.fireworksBurstHalfY = 0.5
        s.fireworksAngleJitter = 0.2

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    /// Legacy settings.json predating these keys decodes cleanly: every Fireworks
    /// field falls back to its default (tolerant decode / migration).
    func testFireworksPartialJSONUsesDefaults() throws {
        let d = VisualizerSettings.defaults
        let json = #"{ "gain": 1.0 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.fireworksMaxParticles, d.fireworksMaxParticles)
        XCTAssertEqual(decoded.fireworksBurstParticlesMax, d.fireworksBurstParticlesMax)
        XCTAssertEqual(decoded.fireworksBurstParticlesMin, d.fireworksBurstParticlesMin)
        XCTAssertEqual(decoded.fireworksBurstScaleBase, d.fireworksBurstScaleBase, accuracy: 1e-9)
        XCTAssertEqual(decoded.fireworksBurstScaleIntensity, d.fireworksBurstScaleIntensity, accuracy: 1e-9)
        XCTAssertEqual(decoded.fireworksBaseSpeed, d.fireworksBaseSpeed, accuracy: 1e-9)
        XCTAssertEqual(decoded.fireworksSpreadSpeed, d.fireworksSpreadSpeed, accuracy: 1e-9)
        XCTAssertEqual(decoded.fireworksGravity, d.fireworksGravity, accuracy: 1e-9)
        XCTAssertEqual(decoded.fireworksDrag, d.fireworksDrag, accuracy: 1e-9)
        XCTAssertEqual(decoded.fireworksBaseLifetime, d.fireworksBaseLifetime, accuracy: 1e-9)
        XCTAssertEqual(decoded.fireworksLifetimeJitter, d.fireworksLifetimeJitter, accuracy: 1e-9)
        XCTAssertEqual(decoded.fireworksMinLifetime, d.fireworksMinLifetime, accuracy: 1e-9)
        XCTAssertEqual(decoded.fireworksBaseSize, d.fireworksBaseSize, accuracy: 1e-9)
        XCTAssertEqual(decoded.fireworksBurstHalfX, d.fireworksBurstHalfX, accuracy: 1e-9)
        XCTAssertEqual(decoded.fireworksBurstHalfY, d.fireworksBurstHalfY, accuracy: 1e-9)
        XCTAssertEqual(decoded.fireworksAngleJitter, d.fireworksAngleJitter, accuracy: 1e-9)
    }

    /// Resetting Fireworks restores all of its exclusive top-level fields.
    func testResetCurrentStyleResetsFireworksFields() {
        let d = VisualizerSettings.defaults
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .fireworks
        s.fireworksMaxParticles = 2000
        s.fireworksBurstParticlesMax = 200
        s.fireworksBurstParticlesMin = 40
        s.fireworksBurstScaleBase = 1.8
        s.fireworksBurstScaleIntensity = 2.2
        s.fireworksBaseSpeed = 2.0
        s.fireworksSpreadSpeed = 1.0
        s.fireworksGravity = 3.0
        s.fireworksDrag = 0.85
        s.fireworksBaseLifetime = 4.0
        s.fireworksLifetimeJitter = 0.8
        s.fireworksMinLifetime = 1.0
        s.fireworksBaseSize = 0.03
        s.fireworksBurstHalfX = 0.9
        s.fireworksBurstHalfY = 0.7
        s.fireworksAngleJitter = 0.3

        s.resetCurrentStyle()

        XCTAssertEqual(s.fireworksMaxParticles, d.fireworksMaxParticles)
        XCTAssertEqual(s.fireworksBurstParticlesMax, d.fireworksBurstParticlesMax)
        XCTAssertEqual(s.fireworksBurstParticlesMin, d.fireworksBurstParticlesMin)
        XCTAssertEqual(s.fireworksBurstScaleBase, d.fireworksBurstScaleBase, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksBurstScaleIntensity, d.fireworksBurstScaleIntensity, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksBaseSpeed, d.fireworksBaseSpeed, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksSpreadSpeed, d.fireworksSpreadSpeed, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksGravity, d.fireworksGravity, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksDrag, d.fireworksDrag, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksBaseLifetime, d.fireworksBaseLifetime, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksLifetimeJitter, d.fireworksLifetimeJitter, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksMinLifetime, d.fireworksMinLifetime, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksBaseSize, d.fireworksBaseSize, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksBurstHalfX, d.fireworksBurstHalfX, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksBurstHalfY, d.fireworksBurstHalfY, accuracy: 1e-9)
        XCTAssertEqual(s.fireworksAngleJitter, d.fireworksAngleJitter, accuracy: 1e-9)
    }

    /// Resetting a DIFFERENT style must not disturb Fireworks' fields.
    func testResetCurrentStyleLeavesFireworksFieldsUntouched() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .fireworks
        s.fireworksMaxParticles = 1500
        s.fireworksGravity = 2.7
        s.visualizerStyle = .polartone
        s.polartoneRadius = 0.9

        s.resetCurrentStyle()

        XCTAssertEqual(s.polartoneRadius, VisualizerSettings.defaults.polartoneRadius)
        XCTAssertEqual(s.fireworksMaxParticles, 1500)
        XCTAssertEqual(s.fireworksGravity, 2.7, accuracy: 1e-9)
    }

    /// Resetting Fireworks must not touch the shared top-level particle fields
    /// (size/speed back particles + fountain + fireworks).
    func testResetCurrentStyleFireworksDoesNotTouchSharedFields() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .fireworks
        s.particleSize = 2.0
        s.particleSpeed = 1.7

        s.resetCurrentStyle()

        XCTAssertEqual(s.particleSize, 2.0)
        XCTAssertEqual(s.particleSpeed, 1.7)
    }

    // MARK: - Particles controls

    /// Default parity: each top-level Particles field equals the prior hardcoded
    /// literal from ParticleVisualizer, so the starfield look is byte-identical until a
    /// slider moves. Each Double default is verified double-rounding-safe (the Float it
    /// narrows to matches the original Float literal bit-for-bit).
    func testParticlesDefaults() {
        let s = VisualizerSettings.defaults
        XCTAssertEqual(s.particlesMaxParticles, 200)
        XCTAssertEqual(s.particlesInitialVelocityScale, 0.05, accuracy: 1e-9)
        XCTAssertEqual(s.particlesRespawnVelocityScale, 0.05, accuracy: 1e-9)
        XCTAssertEqual(s.particlesBaseSize, 0.012, accuracy: 1e-9)
        XCTAssertEqual(s.particlesBaseBrightness, 0.45, accuracy: 1e-9)
        XCTAssertEqual(s.particlesBrightnessJitter, 0.3, accuracy: 1e-9)
        XCTAssertEqual(s.particlesBassThreshold, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.particlesVelocityDamping, 0.985, accuracy: 1e-9)
        XCTAssertEqual(s.particlesReturnLerpRate, 3, accuracy: 1e-9)
        XCTAssertEqual(s.particlesBeatHalfLife, 0.15, accuracy: 1e-9)
        XCTAssertEqual(s.particlesBeatPulseScale, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.particlesBassImpulse, 0.25, accuracy: 1e-9)
        XCTAssertEqual(s.particlesBassBrightnessGain, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.particlesBrightnessCap, 1.0, accuracy: 1e-9)
        XCTAssertEqual(s.particlesBassSizeGain, 1.5, accuracy: 1e-9)
        XCTAssertEqual(s.particlesSizeCapMultiplier, 3, accuracy: 1e-9)
        XCTAssertEqual(s.particlesRespawnOffscreenBound, 1.15, accuracy: 1e-9)
        XCTAssertEqual(s.particlesRespawnCenterHalfRange, 0.15, accuracy: 1e-9)
        XCTAssertEqual(s.particlesLowBandPercent, 0.15, accuracy: 1e-9)

        // Double-rounding safety: Float(default Double) == the original Float literal.
        XCTAssertEqual(Float(s.particlesInitialVelocityScale).bitPattern, (0.05 as Float).bitPattern)
        XCTAssertEqual(Float(s.particlesRespawnVelocityScale).bitPattern, (0.05 as Float).bitPattern)
        XCTAssertEqual(Float(s.particlesBaseSize).bitPattern, (0.012 as Float).bitPattern)
        XCTAssertEqual(Float(s.particlesBaseBrightness).bitPattern, (0.45 as Float).bitPattern)
        XCTAssertEqual(Float(s.particlesBrightnessJitter).bitPattern, (0.3 as Float).bitPattern)
        XCTAssertEqual(Float(s.particlesBassThreshold).bitPattern, (0.5 as Float).bitPattern)
        XCTAssertEqual(Float(s.particlesVelocityDamping).bitPattern, (0.985 as Float).bitPattern)
        XCTAssertEqual(Float(s.particlesReturnLerpRate).bitPattern, (3 as Float).bitPattern)
        XCTAssertEqual(Float(s.particlesBeatHalfLife).bitPattern, (0.15 as Float).bitPattern)
        XCTAssertEqual(Float(s.particlesBeatPulseScale).bitPattern, (0.5 as Float).bitPattern)
        XCTAssertEqual(Float(s.particlesBassImpulse).bitPattern, (0.25 as Float).bitPattern)
        XCTAssertEqual(Float(s.particlesBassBrightnessGain).bitPattern, (0.5 as Float).bitPattern)
        XCTAssertEqual(Float(s.particlesBrightnessCap).bitPattern, (1.0 as Float).bitPattern)
        XCTAssertEqual(Float(s.particlesBassSizeGain).bitPattern, (1.5 as Float).bitPattern)
        XCTAssertEqual(Float(s.particlesSizeCapMultiplier).bitPattern, (3 as Float).bitPattern)
        XCTAssertEqual(Float(s.particlesRespawnOffscreenBound).bitPattern, (1.15 as Float).bitPattern)
        XCTAssertEqual(Float(s.particlesRespawnCenterHalfRange).bitPattern, (0.15 as Float).bitPattern)
        XCTAssertEqual(Float(s.particlesLowBandPercent).bitPattern, (0.15 as Float).bitPattern)
    }

    /// Mutating every Particles field then encoding/decoding reproduces them exactly.
    func testParticlesFieldsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.particlesMaxParticles = 1200
        s.particlesInitialVelocityScale = 0.3
        s.particlesRespawnVelocityScale = 0.4
        s.particlesBaseSize = 0.03
        s.particlesBaseBrightness = 0.7
        s.particlesBrightnessJitter = 0.6
        s.particlesBassThreshold = 0.8
        s.particlesVelocityDamping = 0.9
        s.particlesReturnLerpRate = 6
        s.particlesBeatHalfLife = 0.5
        s.particlesBeatPulseScale = 2.0
        s.particlesBassImpulse = 1.0
        s.particlesBassBrightnessGain = 2.0
        s.particlesBrightnessCap = 1.5
        s.particlesBassSizeGain = 3.0
        s.particlesSizeCapMultiplier = 5
        s.particlesRespawnOffscreenBound = 1.5
        s.particlesRespawnCenterHalfRange = 0.4
        s.particlesLowBandPercent = 0.5

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    /// Legacy settings.json predating these keys decodes cleanly: every Particles
    /// field falls back to its default (tolerant decode / migration).
    func testParticlesPartialJSONUsesDefaults() throws {
        let d = VisualizerSettings.defaults
        let json = #"{ "gain": 1.0 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.particlesMaxParticles, d.particlesMaxParticles)
        XCTAssertEqual(decoded.particlesInitialVelocityScale, d.particlesInitialVelocityScale, accuracy: 1e-9)
        XCTAssertEqual(decoded.particlesRespawnVelocityScale, d.particlesRespawnVelocityScale, accuracy: 1e-9)
        XCTAssertEqual(decoded.particlesBaseSize, d.particlesBaseSize, accuracy: 1e-9)
        XCTAssertEqual(decoded.particlesBaseBrightness, d.particlesBaseBrightness, accuracy: 1e-9)
        XCTAssertEqual(decoded.particlesBrightnessJitter, d.particlesBrightnessJitter, accuracy: 1e-9)
        XCTAssertEqual(decoded.particlesBassThreshold, d.particlesBassThreshold, accuracy: 1e-9)
        XCTAssertEqual(decoded.particlesVelocityDamping, d.particlesVelocityDamping, accuracy: 1e-9)
        XCTAssertEqual(decoded.particlesReturnLerpRate, d.particlesReturnLerpRate, accuracy: 1e-9)
        XCTAssertEqual(decoded.particlesBeatHalfLife, d.particlesBeatHalfLife, accuracy: 1e-9)
        XCTAssertEqual(decoded.particlesBeatPulseScale, d.particlesBeatPulseScale, accuracy: 1e-9)
        XCTAssertEqual(decoded.particlesBassImpulse, d.particlesBassImpulse, accuracy: 1e-9)
        XCTAssertEqual(decoded.particlesBassBrightnessGain, d.particlesBassBrightnessGain, accuracy: 1e-9)
        XCTAssertEqual(decoded.particlesBrightnessCap, d.particlesBrightnessCap, accuracy: 1e-9)
        XCTAssertEqual(decoded.particlesBassSizeGain, d.particlesBassSizeGain, accuracy: 1e-9)
        XCTAssertEqual(decoded.particlesSizeCapMultiplier, d.particlesSizeCapMultiplier, accuracy: 1e-9)
        XCTAssertEqual(decoded.particlesRespawnOffscreenBound, d.particlesRespawnOffscreenBound, accuracy: 1e-9)
        XCTAssertEqual(decoded.particlesRespawnCenterHalfRange, d.particlesRespawnCenterHalfRange, accuracy: 1e-9)
        XCTAssertEqual(decoded.particlesLowBandPercent, d.particlesLowBandPercent, accuracy: 1e-9)
    }

    /// Resetting Particles restores all of its exclusive top-level fields.
    func testResetCurrentStyleResetsParticlesFields() {
        let d = VisualizerSettings.defaults
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .particles
        s.particlesMaxParticles = 2000
        s.particlesInitialVelocityScale = 0.4
        s.particlesRespawnVelocityScale = 0.45
        s.particlesBaseSize = 0.04
        s.particlesBaseBrightness = 0.8
        s.particlesBrightnessJitter = 0.7
        s.particlesBassThreshold = 0.9
        s.particlesVelocityDamping = 0.88
        s.particlesReturnLerpRate = 7
        s.particlesBeatHalfLife = 0.6
        s.particlesBeatPulseScale = 2.5
        s.particlesBassImpulse = 1.5
        s.particlesBassBrightnessGain = 2.5
        s.particlesBrightnessCap = 1.8
        s.particlesBassSizeGain = 4.0
        s.particlesSizeCapMultiplier = 6
        s.particlesRespawnOffscreenBound = 1.8
        s.particlesRespawnCenterHalfRange = 0.5
        s.particlesLowBandPercent = 0.7

        s.resetCurrentStyle()

        XCTAssertEqual(s.particlesMaxParticles, d.particlesMaxParticles)
        XCTAssertEqual(s.particlesInitialVelocityScale, d.particlesInitialVelocityScale, accuracy: 1e-9)
        XCTAssertEqual(s.particlesRespawnVelocityScale, d.particlesRespawnVelocityScale, accuracy: 1e-9)
        XCTAssertEqual(s.particlesBaseSize, d.particlesBaseSize, accuracy: 1e-9)
        XCTAssertEqual(s.particlesBaseBrightness, d.particlesBaseBrightness, accuracy: 1e-9)
        XCTAssertEqual(s.particlesBrightnessJitter, d.particlesBrightnessJitter, accuracy: 1e-9)
        XCTAssertEqual(s.particlesBassThreshold, d.particlesBassThreshold, accuracy: 1e-9)
        XCTAssertEqual(s.particlesVelocityDamping, d.particlesVelocityDamping, accuracy: 1e-9)
        XCTAssertEqual(s.particlesReturnLerpRate, d.particlesReturnLerpRate, accuracy: 1e-9)
        XCTAssertEqual(s.particlesBeatHalfLife, d.particlesBeatHalfLife, accuracy: 1e-9)
        XCTAssertEqual(s.particlesBeatPulseScale, d.particlesBeatPulseScale, accuracy: 1e-9)
        XCTAssertEqual(s.particlesBassImpulse, d.particlesBassImpulse, accuracy: 1e-9)
        XCTAssertEqual(s.particlesBassBrightnessGain, d.particlesBassBrightnessGain, accuracy: 1e-9)
        XCTAssertEqual(s.particlesBrightnessCap, d.particlesBrightnessCap, accuracy: 1e-9)
        XCTAssertEqual(s.particlesBassSizeGain, d.particlesBassSizeGain, accuracy: 1e-9)
        XCTAssertEqual(s.particlesSizeCapMultiplier, d.particlesSizeCapMultiplier, accuracy: 1e-9)
        XCTAssertEqual(s.particlesRespawnOffscreenBound, d.particlesRespawnOffscreenBound, accuracy: 1e-9)
        XCTAssertEqual(s.particlesRespawnCenterHalfRange, d.particlesRespawnCenterHalfRange, accuracy: 1e-9)
        XCTAssertEqual(s.particlesLowBandPercent, d.particlesLowBandPercent, accuracy: 1e-9)
    }

    /// Resetting a DIFFERENT style must not disturb Particles' fields.
    func testResetCurrentStyleLeavesParticlesFieldsUntouched() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .particles
        s.particlesMaxParticles = 1500
        s.particlesBassImpulse = 1.2
        s.visualizerStyle = .polartone
        s.polartoneRadius = 0.9

        s.resetCurrentStyle()

        XCTAssertEqual(s.polartoneRadius, VisualizerSettings.defaults.polartoneRadius)
        XCTAssertEqual(s.particlesMaxParticles, 1500)
        XCTAssertEqual(s.particlesBassImpulse, 1.2, accuracy: 1e-9)
    }

    /// Resetting Particles must not touch the shared top-level particle fields
    /// (size/speed back particles + fountain + fireworks).
    func testResetCurrentStyleParticlesDoesNotTouchSharedFields() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .particles
        s.particleSize = 2.0
        s.particleSpeed = 1.7

        s.resetCurrentStyle()

        XCTAssertEqual(s.particleSize, 2.0)
        XCTAssertEqual(s.particleSpeed, 1.7)
    }

    /// Legacy flat-format JSON (no "profiles" key) migrates barCount through the
    /// memberwise StyleProfile init, bypassing StyleProfile's decoder — the
    /// migration path must clamp barCount <= 0 too (BandMapper preconditions > 0).
    func testLegacyFlatBarCountClampedOnMigration() throws {
        let json = """
        { "visualizerStyle": "bars", "barCount": 0 }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertGreaterThanOrEqual(decoded.barCount, 1)
    }

    /// An unknown persisted enum raw value must fall back to the default for
    /// that field instead of throwing and losing the entire settings load.
    func testUnknownVisualizerStyleRawValueFallsBackToDefault() throws {
        let json = """
        { "visualizerStyle": "notARealStyle", "demoModeEnabled": true }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.visualizerStyle, VisualizerSettings.defaults.visualizerStyle)
        // Sibling fields in the same file must survive the bad enum value.
        XCTAssertTrue(decoded.demoModeEnabled)
    }

    func testUnknownEnumRawValuesFallBackToDefaults() throws {
        let json = """
        { "fftWindow": "kaiser",
          "windowTransparencyMode": "frosted",
          "polartoneRenderMode": "helix",
          "polartoneStartDirection": "sideways" }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        let d = VisualizerSettings.defaults
        XCTAssertEqual(decoded.fftWindow, d.fftWindow)
        XCTAssertEqual(decoded.windowTransparencyMode, d.windowTransparencyMode)
        XCTAssertEqual(decoded.polartoneRenderMode, d.polartoneRenderMode)
        XCTAssertEqual(decoded.polartoneStartDirection, d.polartoneStartDirection)
    }

    /// A wrong-typed enum value (number where a string raw value is expected)
    /// is STRUCTURAL corruption, not version drift: it must throw so
    /// VisualizerSettings.load takes the corrupt-file backup path instead of
    /// silently defaulting and letting the next save overwrite the evidence.
    /// Only an unknown raw value of the expected type decodes lossily.
    func testWrongTypedEnumValueThrows() {
        let json = """
        { "fftWindow": 3 }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(VisualizerSettings.self, from: json))
    }

    /// Known enum raw values must continue to decode exactly (lossy decoding
    /// must not flatten valid persisted values to defaults).
    func testKnownEnumRawValuesStillDecode() throws {
        let json = """
        { "visualizerStyle": "voronoi", "fftWindow": "blackman",
          "windowTransparencyMode": "perPixelAlpha" }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.visualizerStyle, .voronoi)
        XCTAssertEqual(decoded.fftWindow, .blackman)
        XCTAssertEqual(decoded.windowTransparencyMode, .perPixelAlpha)
    }

    /// Legacy migration path (no "profiles" key): unknown enum raw values in
    /// the old flat fields must also fall back instead of throwing.
    func testLegacyFlatUnknownEnumFallsBackToDefault() throws {
        let json = """
        { "overlayPosition": "center", "backgroundStyle": "sparkles" }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        // overlayPosition is app-wide now; its bad raw value falls back there.
        XCTAssertEqual(decoded.overlayPosition, VisualizerSettings.defaults.overlayPosition)
        XCTAssertEqual(decoded.current.backgroundStyle, StyleProfile.defaults.backgroundStyle)
    }

    /// An unknown style key inside "profiles" (e.g. written by a newer app
    /// version) must be ignored — not throw away every per-style profile.
    /// The persisted format is the flat [key, value, key, value, ...] array
    /// Swift Codable emits for enum-keyed dictionaries.
    func testUnknownProfileKeyIgnoredValidEntriesPreserved() throws {
        let json = """
        { "profiles": [
            "bars", { "gain": 2.0 },
            "someFutureStyle", { "gain": 9.9 }
        ] }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.profiles[.bars]?.gain, 2.0)
        // Styles missing from the JSON are still populated with defaults.
        for s in VisualizerStyle.allCases {
            XCTAssertNotNil(decoded.profiles[s], "\(s) profile missing after lossy decode")
        }
    }

    /// A malformed profile value (wrong-typed field) defaults that one entry;
    /// the other entries decode normally.
    func testMalformedProfileEntryDefaultsOnlyThatEntry() throws {
        let json = """
        { "profiles": [
            "bars", { "gain": "loud" },
            "voronoi", { "gain": 3.0 }
        ] }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.profiles[.bars], StyleProfile.defaults)
        XCTAssertEqual(decoded.profiles[.voronoi]?.gain, 3.0)
    }

    /// "profiles" present but structurally wrong (not the flat array Swift
    /// Codable writes): that is file corruption, not version drift — it must
    /// throw so VisualizerSettings.load takes the corrupt-file backup path
    /// instead of silently defaulting every profile and letting the next
    /// save overwrite the evidence. Only per-ENTRY problems decode lossily.
    func testStructurallyCorruptProfilesValueThrows() {
        let json = """
        { "profiles": "corrupt", "demoModeEnabled": true }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(VisualizerSettings.self, from: json))
    }

    func testXYScopeKnobsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.xyScopeGain = 1.7
        s.xyScopeSampleCount = 128
        s.xyScopeLineHalfThickness = 0.01
        s.xyScopeRotationDegrees = 90
        s.xyScopeColorFloor = 0.3
        s.xyScopeBeatBoost = 0.8
        s.xyScopeBeatHalfLife = 0.25
        s.xyScopeAlpha = 0.6
        let data = try JSONEncoder().encode(s)
        let d = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(d.xyScopeGain, 1.7)
        XCTAssertEqual(d.xyScopeSampleCount, 128)
        XCTAssertEqual(d.xyScopeLineHalfThickness, 0.01)
        XCTAssertEqual(d.xyScopeRotationDegrees, 90)
        XCTAssertEqual(d.xyScopeColorFloor, 0.3)
        XCTAssertEqual(d.xyScopeBeatBoost, 0.8)
        XCTAssertEqual(d.xyScopeBeatHalfLife, 0.25)
        XCTAssertEqual(d.xyScopeAlpha, 0.6)
    }

    func testLegacyJSONWithoutXYScopeKnobsGetsDefaults() throws {
        let json = """
        { "visualizerStyle": "bars" }
        """.data(using: .utf8)!
        let d = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        let def = VisualizerSettings.defaults
        XCTAssertEqual(d.xyScopeGain, def.xyScopeGain)
        XCTAssertEqual(d.xyScopeSampleCount, def.xyScopeSampleCount)
        XCTAssertEqual(d.xyScopeLineHalfThickness, def.xyScopeLineHalfThickness)
        XCTAssertEqual(d.xyScopeRotationDegrees, def.xyScopeRotationDegrees)
        XCTAssertEqual(d.xyScopeColorFloor, def.xyScopeColorFloor)
        XCTAssertEqual(d.xyScopeBeatBoost, def.xyScopeBeatBoost)
        XCTAssertEqual(d.xyScopeBeatHalfLife, def.xyScopeBeatHalfLife)
        XCTAssertEqual(d.xyScopeAlpha, def.xyScopeAlpha)
    }

    func testIrisAndTricentricKnobsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.irisPetalCount = 64
        s.irisInnerRadius = 0.3
        s.irisBaseLength = 0.25
        s.irisLengthScale = 0.7
        s.irisPetalWidth = 0.02
        s.irisLoudnessSwell = 0.4
        s.irisInnerDim = 0.5
        s.irisAlpha = 0.8
        s.tricentricRingCount = 16
        s.tricentricBaseRadius = 0.7
        s.tricentricRadiusFalloff = 0.9
        s.tricentricScaleFloor = 0.3
        s.tricentricRotationSpeed = 2.0
        s.tricentricLineThickness = 0.01
        s.tricentricAlpha = 0.9
        let data = try JSONEncoder().encode(s)
        let d = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(d.irisPetalCount, 64)
        XCTAssertEqual(d.irisInnerRadius, 0.3)
        XCTAssertEqual(d.irisBaseLength, 0.25)
        XCTAssertEqual(d.irisLengthScale, 0.7)
        XCTAssertEqual(d.irisPetalWidth, 0.02)
        XCTAssertEqual(d.irisLoudnessSwell, 0.4)
        XCTAssertEqual(d.irisInnerDim, 0.5)
        XCTAssertEqual(d.irisAlpha, 0.8)
        XCTAssertEqual(d.tricentricRingCount, 16)
        XCTAssertEqual(d.tricentricBaseRadius, 0.7)
        XCTAssertEqual(d.tricentricRadiusFalloff, 0.9)
        XCTAssertEqual(d.tricentricScaleFloor, 0.3)
        XCTAssertEqual(d.tricentricRotationSpeed, 2.0)
        XCTAssertEqual(d.tricentricLineThickness, 0.01)
        XCTAssertEqual(d.tricentricAlpha, 0.9)
    }

    func testLegacyJSONWithoutVissonanceKnobsGetsDefaults() throws {
        let json = """
        { "visualizerStyle": "bars" }
        """.data(using: .utf8)!
        let d = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        let def = VisualizerSettings.defaults
        XCTAssertEqual(d.irisPetalCount, def.irisPetalCount)
        XCTAssertEqual(d.irisAlpha, def.irisAlpha)
        XCTAssertEqual(d.tricentricRingCount, def.tricentricRingCount)
        XCTAssertEqual(d.tricentricAlpha, def.tricentricAlpha)
    }

    func testResetCurrentStyleIrisAndTricentric() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .iris
        s.irisPetalCount = 16
        s.resetCurrentStyle()
        XCTAssertEqual(s.irisPetalCount, VisualizerSettings.defaults.irisPetalCount)

        s.visualizerStyle = .tricentric
        s.tricentricRingCount = 4
        s.resetCurrentStyle()
        XCTAssertEqual(s.tricentricRingCount, VisualizerSettings.defaults.tricentricRingCount)
    }

    func testMusicalSpectrumKnobsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.musicalStartOctave = 3
        s.musicalOctaveCount = 4
        s.musicalBarGap = 0.3
        s.musicalOctaveGap = 1.2
        s.musicalPitchClassColoring = false
        s.musicalColorFloor = 0.25
        s.musicalAlpha = 0.7
        let data = try JSONEncoder().encode(s)
        let d = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(d.musicalStartOctave, 3)
        XCTAssertEqual(d.musicalOctaveCount, 4)
        XCTAssertEqual(d.musicalBarGap, 0.3)
        XCTAssertEqual(d.musicalOctaveGap, 1.2)
        XCTAssertFalse(d.musicalPitchClassColoring)
        XCTAssertEqual(d.musicalColorFloor, 0.25)
        XCTAssertEqual(d.musicalAlpha, 0.7)
    }

    func testLegacyJSONWithoutMusicalKnobsGetsDefaults() throws {
        let json = """
        { "visualizerStyle": "bars" }
        """.data(using: .utf8)!
        let d = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        let def = VisualizerSettings.defaults
        XCTAssertEqual(d.musicalStartOctave, def.musicalStartOctave)
        XCTAssertEqual(d.musicalOctaveCount, def.musicalOctaveCount)
        XCTAssertEqual(d.musicalPitchClassColoring, def.musicalPitchClassColoring)
        XCTAssertEqual(d.musicalAlpha, def.musicalAlpha)
    }

    func testResetCurrentStyleMusicalSpectrum() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .musicalSpectrum
        s.musicalOctaveCount = 2
        s.resetCurrentStyle()
        XCTAssertEqual(s.musicalOctaveCount, VisualizerSettings.defaults.musicalOctaveCount)
    }

    func testOutputBrightnessRoundTripsAndDefaultsToFullBrightness() throws {
        XCTAssertEqual(VisualizerSettings.defaults.outputBrightness, 1.0)
        var s = VisualizerSettings.defaults
        s.outputBrightness = 0.4
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(VisualizerSettings.self, from: data).outputBrightness, 0.4)
        // Files predating the dimmer load at full brightness (pure no-op).
        let legacy = "{ \"visualizerStyle\": \"bars\" }".data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(VisualizerSettings.self, from: legacy).outputBrightness, 1.0)
    }

    func testHeightfieldFillTogglesRoundTripAndDefaultOff() throws {
        XCTAssertFalse(VisualizerSettings.defaults.heightfieldFillWidth)
        XCTAssertFalse(VisualizerSettings.defaults.heightfieldAnchorBottom)
        var s = VisualizerSettings.defaults
        s.heightfieldAnchorBottom = true
        let d = try JSONDecoder().decode(VisualizerSettings.self, from: try JSONEncoder().encode(s))
        XCTAssertFalse(d.heightfieldFillWidth)
        XCTAssertTrue(d.heightfieldAnchorBottom)
        let legacy = "{ \"visualizerStyle\": \"heightfield\" }".data(using: .utf8)!
        let e = try JSONDecoder().decode(VisualizerSettings.self, from: legacy)
        XCTAssertFalse(e.heightfieldFillWidth)
        XCTAssertFalse(e.heightfieldAnchorBottom)
    }

    func testWireframeFillTogglesRoundTripIndependently() throws {
        var s = VisualizerSettings.defaults
        XCTAssertFalse(s.wireframeFillWidth)
        XCTAssertFalse(s.wireframeAnchorBottom)
        s.wireframeFillWidth = true
        let d = try JSONDecoder().decode(VisualizerSettings.self, from: try JSONEncoder().encode(s))
        XCTAssertTrue(d.wireframeFillWidth)
        XCTAssertFalse(d.wireframeAnchorBottom)
    }

    /// v0.6.x wrote a single combined "wireframeFillWindow" flag. Settings files
    /// carrying it must come back as both toggles on, preserving the look.
    func testLegacyCombinedFillWindowKeyMigratesToBothToggles() throws {
        let json = """
        { "visualizerStyle": "wireframe", "wireframeFillWindow": true }
        """.data(using: .utf8)!
        let d = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertTrue(d.wireframeFillWidth)
        XCTAssertTrue(d.wireframeAnchorBottom)

        let off = """
        { "visualizerStyle": "wireframe", "wireframeFillWindow": false }
        """.data(using: .utf8)!
        let e = try JSONDecoder().decode(VisualizerSettings.self, from: off)
        XCTAssertFalse(e.wireframeFillWidth)
        XCTAssertFalse(e.wireframeAnchorBottom)
    }

    func testWireframePlacementKnobsRoundTrip() throws {
        var s = VisualizerSettings.defaults
        s.wireframeXExtent = 2.5
        s.wireframeYExtent = 0.75
        s.wireframeVerticalCenter = -0.65
        let data = try JSONEncoder().encode(s)
        let d = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(d.wireframeXExtent, 2.5)
        XCTAssertEqual(d.wireframeYExtent, 0.75)
        XCTAssertEqual(d.wireframeVerticalCenter, -0.65)
    }

    /// Existing settings.json files predate the placement knobs: they must load
    /// with the identity defaults so the Wireframe render is unchanged.
    func testLegacyJSONWithoutWireframePlacementGetsIdentityDefaults() throws {
        let json = """
        { "visualizerStyle": "wireframe" }
        """.data(using: .utf8)!
        let d = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(d.wireframeXExtent, 1.0)
        XCTAssertEqual(d.wireframeYExtent, 1.0)
        XCTAssertEqual(d.wireframeVerticalCenter, 0.0)
    }

    func testResetCurrentStyleWireframeRestoresPlacementDefaults() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .wireframe
        s.wireframeXExtent = 3.0
        s.wireframeVerticalCenter = -0.9
        s.resetCurrentStyle()
        XCTAssertEqual(s.wireframeXExtent, VisualizerSettings.defaults.wireframeXExtent)
        XCTAssertEqual(s.wireframeVerticalCenter, VisualizerSettings.defaults.wireframeVerticalCenter)
    }

    func testResetCurrentStyleXYScopeRestoresKnobDefaults() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .xyScope
        s.xyScopeGain = 3.0
        s.xyScopeRotationDegrees = 10
        s.resetCurrentStyle()
        XCTAssertEqual(s.xyScopeGain, VisualizerSettings.defaults.xyScopeGain)
        XCTAssertEqual(s.xyScopeRotationDegrees, VisualizerSettings.defaults.xyScopeRotationDegrees)
    }

    /// The ribbonWave profile persists under its legacy raw key "siri"; the
    /// lossy path must keep resolving it to .ribbonWave.
    func testProfilesLegacySiriKeyStillMapsToRibbonWave() throws {
        let json = """
        { "profiles": [ "siri", { "gain": 4.0 } ] }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: json)
        XCTAssertEqual(decoded.profiles[.ribbonWave]?.gain, 4.0)
    }

    /// A full round-trip through the encoder must survive the lossy decoder
    /// unchanged (the on-disk format is not altered by the lossy read path).
    func testProfilesRoundTripThroughLossyDecoder() throws {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .voronoi
        s.mutateCurrent { $0.gain = 2.25; $0.voronoiRenderMode = .blobs }
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(decoded.profiles, s.profiles)
    }

    // MARK: - Random selection (backs the ⌘R / ⌘⇧R hotkeys)

    func testRandomEnabledStyleExcludesCurrentWhenOthersEnabled() {
        var s = VisualizerSettings.defaults
        XCTAssertGreaterThan(s.enabledStyles.count, 1, "precondition: more than one style enabled by default")
        var rng = LCGTestRNG(seed: 42)
        for _ in 0..<50 {
            let pick = s.randomEnabledStyle(excluding: .bars, using: &rng)
            XCTAssertNotEqual(pick, .bars)
            XCTAssertTrue(s.enabledStyles.contains(pick))
        }
    }

    func testRandomEnabledStyleReturnsSelfWhenOnlyOneEnabled() {
        var s = VisualizerSettings.defaults
        for st in VisualizerStyle.allCases where st != .bars { s.setStyleEnabled(st, false) }
        XCTAssertEqual(s.enabledStyles, [.bars])
        var rng = LCGTestRNG(seed: 1)
        XCTAssertEqual(s.randomEnabledStyle(excluding: .bars, using: &rng), .bars)
    }

    func testRandomEnabledStyleIsDeterministicForSeed() {
        let s = VisualizerSettings.defaults
        var r1 = LCGTestRNG(seed: 7)
        var r2 = LCGTestRNG(seed: 7)
        XCTAssertEqual(s.randomEnabledStyle(excluding: .bars, using: &r1),
                       s.randomEnabledStyle(excluding: .bars, using: &r2))
    }

    func testRandomPaletteNameExcludesCurrentAndIsAPreset() {
        let s = VisualizerSettings.defaults
        let presets = ColorPalette.orderedPresetNames
        XCTAssertGreaterThan(presets.count, 1, "precondition: more than one preset")
        let current = presets[0]
        var rng = LCGTestRNG(seed: 99)
        for _ in 0..<50 {
            let pick = s.randomPaletteName(excluding: current, using: &rng)
            XCTAssertNotEqual(pick, current)
            XCTAssertTrue(presets.contains(pick))
        }
    }

    func testRandomPaletteNameIsDeterministicForSeed() {
        let s = VisualizerSettings.defaults
        let current = ColorPalette.orderedPresetNames[0]
        var r1 = LCGTestRNG(seed: 11)
        var r2 = LCGTestRNG(seed: 11)
        XCTAssertEqual(s.randomPaletteName(excluding: current, using: &r1),
                       s.randomPaletteName(excluding: current, using: &r2))
    }
}

/// A tiny deterministic generator for the random-selection tests: a fixed
/// LCG so the same seed reproduces the same sequence (SeededRNG is not used
/// here to keep these tests independent of its internals).
private struct LCGTestRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
