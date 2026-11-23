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

/// The Spinner is two ordinary styles: the Disc Spinner (`.spinner`) and the Tri-wing Spinner (`.triWingSpinner`).
final class SpinnerStyleSplitTests: XCTestCase {
    private var savedOSCheck: (() -> Bool)!
    override func setUp() { savedOSCheck = VisualizerStyle.spinnerOSCheck }
    override func tearDown() { VisualizerStyle.spinnerOSCheck = savedOSCheck }

    // MARK: Style identity and flags

    func testNamesAndRawValues() {
        XCTAssertEqual(VisualizerStyle.spinner.displayName, "Disc Spinner")
        XCTAssertEqual(VisualizerStyle.triWingSpinner.displayName, "Tri-wing Spinner")
        XCTAssertEqual(VisualizerStyle.spinner.rawValue, "spinner")
        XCTAssertEqual(VisualizerStyle.triWingSpinner.rawValue, "triWingSpinner")
        XCTAssertEqual(VisualizerStyle(rawValue: "triWingSpinner"), .triWingSpinner)
    }

    func testIsSpinnerFamily() {
        for style in VisualizerStyle.allCases {
            let expected: Bool = (style == .spinner || style == .triWingSpinner)
            XCTAssertEqual(style.isSpinnerFamily, expected, "\(style)")
        }
    }

    func testSpinnerModelIsDerivedFromTheStyle() {
        XCTAssertEqual(VisualizerStyle.spinner.spinnerModel, .disc)
        XCTAssertEqual(VisualizerStyle.triWingSpinner.spinnerModel, .triWing)
        XCTAssertNil(VisualizerStyle.bars.spinnerModel)
    }

    func testTriWingSpinnerHasTheSameCapabilityFlagsAsTheSpinner() {
        let a = VisualizerStyle.spinner
        let b = VisualizerStyle.triWingSpinner
        XCTAssertEqual(a.supportsPositionOffset, b.supportsPositionOffset)
        XCTAssertEqual(a.usesFrequencyBands, b.usesFrequencyBands)
        XCTAssertEqual(a.usesBarCount, b.usesBarCount)
        XCTAssertEqual(a.usesPeakHold, b.usesPeakHold)
        XCTAssertEqual(a.usesStereoImage, b.usesStereoImage)
        XCTAssertEqual(a.usesPalette, b.usesPalette)
        XCTAssertEqual(a.usesRoundParticles, b.usesRoundParticles)
        XCTAssertTrue(b.supportsPositionOffset)
        XCTAssertFalse(b.usesFrequencyBands)
        XCTAssertFalse(b.usesPalette)
    }

    func testBothStylesUseTheSpinnerShaderKindAndVisualizer() {
        let s = VisualizerSettings.defaults
        XCTAssertEqual(VisualizerStyle.spinner.customShader(settings: s), .spinner)
        XCTAssertEqual(VisualizerStyle.triWingSpinner.customShader(settings: s), .spinner)
        XCTAssertTrue(VisualizerStyle.spinner.makeVisualizer() is SpinnerVisualizer)
        XCTAssertTrue(VisualizerStyle.triWingSpinner.makeVisualizer() is SpinnerVisualizer)
    }

    func testAvailabilityGateAppliesToBothStyles() {
        VisualizerStyle.spinnerOSCheck = { false }
        XCTAssertFalse(VisualizerStyle.spinner.isAvailable)
        XCTAssertFalse(VisualizerStyle.triWingSpinner.isAvailable)
        XCTAssertEqual(VisualizerStyle.availableCases.count, VisualizerStyle.allCases.count - 2)
        VisualizerStyle.spinnerOSCheck = { true }
        XCTAssertTrue(VisualizerStyle.spinner.isAvailable)
        XCTAssertTrue(VisualizerStyle.triWingSpinner.isAvailable)
    }

    func testPaletteControlOnlyLiveForTriWingWithPaletteLights() {
        var sp = SpinnerSettings()
        sp.lightColors = .palette
        XCTAssertTrue(VisualizerStyle.triWingSpinner.paletteControlEnabled(spinner: sp))
        XCTAssertFalse(VisualizerStyle.spinner.paletteControlEnabled(spinner: sp), "the disc has no lights to colour")
        sp.lightColors = .original
        XCTAssertFalse(VisualizerStyle.triWingSpinner.paletteControlEnabled(spinner: sp))
    }

    func testNeighboursInTheRotation() {
        XCTAssertEqual(VisualizerStyle.musicalSpectrum.next, .spinner)
        XCTAssertEqual(VisualizerStyle.spinner.next, .triWingSpinner)
        XCTAssertEqual(VisualizerStyle.triWingSpinner.next, .bars)
        XCTAssertEqual(VisualizerStyle.triWingSpinner.previous, .spinner)
        XCTAssertEqual(VisualizerStyle.spinner.previous, .musicalSpectrum)
    }

    func testEnabledToggleIsPerStyle() {
        var s = VisualizerSettings.defaults
        s.setStyleEnabled(.triWingSpinner, false)
        XCTAssertTrue(s.isStyleEnabled(.spinner))
        XCTAssertFalse(s.isStyleEnabled(.triWingSpinner))
        XCTAssertEqual(s.nextEnabledStyle(after: .spinner), .bars)
    }

    // MARK: Profile selection

    func testGoverningStyleSelection() {
        XCTAssertEqual(SpinnerProfileSelection.style(active: .triWingSpinner, lastActive: .spinner), .triWingSpinner)
        XCTAssertEqual(SpinnerProfileSelection.style(active: .spinner, lastActive: .triWingSpinner), .spinner)
        XCTAssertEqual(SpinnerProfileSelection.style(active: .bars, lastActive: .triWingSpinner), .triWingSpinner)
        XCTAssertEqual(SpinnerProfileSelection.style(active: .bars, lastActive: .spinner), .spinner)
        XCTAssertEqual(SpinnerProfileSelection.style(active: .bars, lastActive: nil), .spinner)
        XCTAssertEqual(SpinnerProfileSelection.style(active: .bars, lastActive: .plasma), .spinner)
    }

    func testSpinnerSettingsFollowTheActiveSpinnerStyle() {
        var s = VisualizerSettings.defaults
        s.profiles[.spinner]?.spinner.friction = 2
        s.profiles[.triWingSpinner]?.spinner.friction = 3
        s.visualizerStyle = .spinner
        XCTAssertEqual(s.spinnerSettings.friction, 2)
        s.visualizerStyle = .triWingSpinner
        XCTAssertEqual(s.spinnerSettings.friction, 3)
    }

    func testHumProfileUsesLastActiveSpinnerStyleWhileAnotherStyleIsActive() {
        var s = VisualizerSettings.defaults
        s.profiles[.spinner]?.spinner.humVolume = 0.4
        s.profiles[.triWingSpinner]?.spinner.humVolume = 0.9
        s.visualizerStyle = .bars
        XCTAssertEqual(s.spinnerSettings.humVolume, 0.4, "no history: the Disc Spinner")
        XCTAssertEqual(s.spinnerSettings(lastActive: .triWingSpinner).humVolume, 0.9)
        XCTAssertEqual(s.spinnerSettings(lastActive: .spinner).humVolume, 0.4)
        XCTAssertEqual(s.spinnerSettings(lastActive: nil).humVolume, 0.4)
    }

    func testModelIsDerivedFromTheStyleNotFromTheStoredField() {
        var s = VisualizerSettings.defaults
        s.profiles[.spinner]?.spinner.model = .triWing        // an old file's value: ignored
        s.profiles[.triWingSpinner]?.spinner.model = .disc
        s.visualizerStyle = .spinner
        XCTAssertEqual(s.spinnerSettings.model, .disc)
        s.visualizerStyle = .triWingSpinner
        XCTAssertEqual(s.spinnerSettings.model, .triWing)
    }

    func testTriWingRendererIsAlwaysRealityKit() {
        var s = VisualizerSettings.defaults
        s.profiles[.triWingSpinner]?.spinner.renderer = .shader
        s.profiles[.spinner]?.spinner.renderer = .shader
        s.visualizerStyle = .triWingSpinner
        XCTAssertEqual(s.spinnerSettings.renderer, .realityKit)
        s.visualizerStyle = .spinner
        XCTAssertEqual(s.spinnerSettings.renderer, .shader, "the Disc Spinner keeps its renderer choice")
    }

    func testProfilesAreIndependent() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .triWingSpinner
        s.mutateCurrent { $0.spinner.metal = .brass; $0.gain = 1.9 }
        XCTAssertEqual(s.profiles[.spinner]?.spinner.metal, SpinnerSettings().metal)
        XCTAssertNotEqual(s.profiles[.spinner]?.gain, 1.9)
    }

    func testFactoryDefaultsForBothStyles() {
        XCTAssertEqual(StyleProfile.defaults(for: .spinner).spinner, SpinnerSettings())
        var expected = SpinnerSettings()
        expected.model = .triWing
        XCTAssertEqual(StyleProfile.defaults(for: .triWingSpinner).spinner, expected)
        XCTAssertEqual(VisualizerSettings.defaults.profiles[.triWingSpinner], StyleProfile.defaults(for: .triWingSpinner))
    }

    // MARK: Shared spin state

    func testSharedStateCarriesSpeedAngleAndOrientationAcrossVisualizers() {
        let shared = SpinnerSharedState()
        let disc = SpinnerVisualizer(shared: shared)
        let tri = SpinnerVisualizer(shared: shared)
        disc.advance(dt: 1.0 / 60, impulse: 3, now: 100)
        disc.advance(dt: 1.0 / 60, impulse: 0, now: 100.02)
        var req = SpinnerOrientationRequests()
        req.pitchSteps = 2
        req.yawSteps = -1
        disc.apply(req, stepDegrees: 15)
        XCTAssertGreaterThan(disc.physics.velocity, 0)
        XCTAssertEqual(tri.physics.velocity, disc.physics.velocity)
        XCTAssertEqual(tri.physics.angle, disc.physics.angle)
        XCTAssertEqual(tri.orientation.pitchTarget, disc.orientation.pitchTarget, accuracy: 1e-12)
        XCTAssertEqual(tri.orientation.yawTarget, disc.orientation.yawTarget, accuracy: 1e-12)
        XCTAssertNotEqual(tri.orientation.pitchTarget, 0)
        // And back: the Tri-wing advances, the disc continues from there.
        let before = tri.physics.angle
        tri.advance(dt: 1.0 / 60, impulse: 0, now: 100.04)
        XCTAssertNotEqual(disc.physics.angle, before)
        XCTAssertEqual(disc.physics.angle, tri.physics.angle)
    }

    func testDirectionLockCarriesOverBetweenVisualizers() {
        let shared = SpinnerSharedState()
        let disc = SpinnerVisualizer(shared: shared)
        let tri = SpinnerVisualizer(shared: shared)
        disc.advance(dt: 1.0 / 60, impulse: 1, now: 10)
        XCTAssertGreaterThan(tri.physics.velocity, 0)
        tri.advance(dt: 1.0 / 60, impulse: -1000, now: 10.02)   // brakes to zero
        XCTAssertEqual(disc.physics.velocity, 0)
        disc.advance(dt: 1.0 / 60, impulse: -1, now: 10.05)     // locked out: the lock lives in the shared physics
        XCTAssertEqual(tri.physics.velocity, 0)
    }

    func testStandaloneVisualizersDoNotShareState() {
        let a = SpinnerVisualizer()
        let b = SpinnerVisualizer()
        a.advance(dt: 1.0 / 60, impulse: 3, now: 5)
        XCTAssertGreaterThan(a.physics.velocity, 0)
        XCTAssertEqual(b.physics.velocity, 0)
    }

    func testFactoryVisualizersOfBothStylesShareOneState() {
        guard let a = VisualizerStyle.spinner.makeVisualizer() as? SpinnerVisualizer,
              let b = VisualizerStyle.triWingSpinner.makeVisualizer() as? SpinnerVisualizer else {
            return XCTFail("spinner family must build SpinnerVisualizer")
        }
        XCTAssertTrue(a.shared === b.shared)
    }

    // MARK: Settings migration

    /// Encodes `settings`, drops the named styles' profile entries (as an older file would lack them), decodes.
    private func decodeWithout(_ settings: VisualizerSettings, dropping dropped: [VisualizerStyle]) throws -> VisualizerSettings {
        let data = try JSONEncoder().encode(settings)
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let flat = try XCTUnwrap(obj["profiles"] as? [Any])
        var kept: [Any] = []
        var i = 0
        while i + 1 < flat.count {
            let key: String = (flat[i] as? String) ?? ""
            if !dropped.contains(where: { $0.rawValue == key }) {
                kept.append(flat[i])
                kept.append(flat[i + 1])
            }
            i += 2
        }
        obj["profiles"] = kept
        let edited = try JSONSerialization.data(withJSONObject: obj)
        return try JSONDecoder().decode(VisualizerSettings.self, from: edited)
    }

    private func customised() -> VisualizerSettings {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .spinner
        s.mutateCurrent {
            $0.gain = 1.7
            $0.paletteName = "Fire"
            $0.positionOffsetY = 0.2
            $0.enabled = false
            $0.spinner.metal = .brass
            $0.spinner.friction = 0.5
            $0.spinner.size = 0.8
            $0.spinner.model = .disc
        }
        return s
    }

    func testMissingTriWingProfileIsCopiedFromTheSpinner() throws {
        let s = try decodeWithout(customised(), dropping: [.triWingSpinner])
        let disc = try XCTUnwrap(s.profiles[.spinner])
        let tri = try XCTUnwrap(s.profiles[.triWingSpinner])
        XCTAssertEqual(tri.gain, 1.7)
        XCTAssertEqual(tri.paletteName, "Fire")
        XCTAssertEqual(tri.positionOffsetY, 0.2, accuracy: 1e-6)
        XCTAssertEqual(tri.spinner.metal, .brass)
        XCTAssertEqual(tri.spinner.friction, 0.5)
        XCTAssertEqual(tri.spinner.size, 0.8)
        XCTAssertEqual(tri.enabled, false, "enabled state is copied too")
        XCTAssertEqual(disc.spinner.metal, .brass)
        XCTAssertEqual(s.visualizerStyle, .spinner)
    }

    func testAfterTheCopyTheTwoAreIndependent() throws {
        var s = try decodeWithout(customised(), dropping: [.triWingSpinner])
        s.profiles[.triWingSpinner]?.spinner.metal = .copper
        XCTAssertEqual(s.profiles[.spinner]?.spinner.metal, .brass)
    }

    func testStoredModelFieldIsNormalisedOnTheCopy() throws {
        let s = try decodeWithout(customised(), dropping: [.triWingSpinner])
        XCTAssertEqual(s.profiles[.spinner]?.spinner.model, .disc)
        XCTAssertEqual(s.profiles[.triWingSpinner]?.spinner.model, .triWing)
    }

    func testOldTriWingModelWithSpinnerActiveBecomesTheTriWingSpinner() throws {
        var s = customised()
        s.mutateCurrent { $0.spinner.model = .triWing }
        let back = try decodeWithout(s, dropping: [.triWingSpinner])
        XCTAssertEqual(back.visualizerStyle, .triWingSpinner)
        XCTAssertEqual(back.profiles[.triWingSpinner]?.spinner.metal, .brass)
        XCTAssertEqual(back.profiles[.spinner]?.spinner.metal, .brass)
        XCTAssertEqual(back.profiles[.spinner]?.spinner.model, .disc)
        XCTAssertEqual(back.profiles[.triWingSpinner]?.spinner.model, .triWing)
    }

    func testOldTriWingModelWithAnotherStyleActiveKeepsTheActiveStyle() throws {
        var s = customised()
        s.mutateCurrent { $0.spinner.model = .triWing }
        s.visualizerStyle = .voronoi
        let back = try decodeWithout(s, dropping: [.triWingSpinner])
        XCTAssertEqual(back.visualizerStyle, .voronoi)
        XCTAssertEqual(back.profiles[.triWingSpinner]?.spinner.metal, .brass)
    }

    func testOldDiscModelKeepsTheSpinnerActive() throws {
        let back = try decodeWithout(customised(), dropping: [.triWingSpinner])
        XCTAssertEqual(back.visualizerStyle, .spinner)
    }

    func testExistingTriWingProfileIsLeftAlone() throws {
        var s = customised()
        s.mutateCurrent { $0.spinner.model = .triWing }          // would trigger the switch if the profile were missing
        s.profiles[.triWingSpinner]?.gain = 0.9
        s.profiles[.triWingSpinner]?.spinner.metal = .copper
        let back = try JSONDecoder().decode(VisualizerSettings.self, from: try JSONEncoder().encode(s))
        XCTAssertEqual(back.visualizerStyle, .spinner, "the migration runs once: the profile already exists")
        XCTAssertEqual(back.profiles[.triWingSpinner]?.gain, 0.9)
        XCTAssertEqual(back.profiles[.triWingSpinner]?.spinner.metal, .copper)
        XCTAssertEqual(back.profiles[.spinner]?.spinner.model, .disc, "the stored model is pinned to what each style draws")
    }

    func testMigrationIsStableOnReEncode() throws {
        var s = customised()
        s.mutateCurrent { $0.spinner.model = .triWing }
        let once = try decodeWithout(s, dropping: [.triWingSpinner])
        let twice = try JSONDecoder().decode(VisualizerSettings.self, from: try JSONEncoder().encode(once))
        XCTAssertEqual(twice.visualizerStyle, once.visualizerStyle)
        XCTAssertEqual(twice.profiles, once.profiles)
    }

    func testFileWithoutAnySpinnerCustomisationLoadsDefaultsForBoth() throws {
        let s = try decodeWithout(.defaults, dropping: [.spinner, .triWingSpinner])
        XCTAssertEqual(s.profiles[.spinner], StyleProfile.defaults(for: .spinner))
        XCTAssertEqual(s.profiles[.triWingSpinner], StyleProfile.defaults(for: .triWingSpinner))
        XCTAssertEqual(s.visualizerStyle, VisualizerSettings.defaults.visualizerStyle)
    }

    func testLegacyFlatFileLoadsDefaultsForBoth() throws {
        let s = try JSONDecoder().decode(VisualizerSettings.self, from: Data("{\"gain\": 1.5}".utf8))
        XCTAssertNotNil(s.profiles[.spinner])
        XCTAssertNotNil(s.profiles[.triWingSpinner])
        XCTAssertEqual(s.profiles[.triWingSpinner]?.spinner.model, .triWing)
    }

    func testMigrationLeavesOtherStylesAlone() throws {
        var s = customised()
        s.profiles[.bars]?.gain = 2.2
        s.profiles[.voronoi]?.smoothing = 0.33
        let back = try decodeWithout(s, dropping: [.triWingSpinner])
        for style in VisualizerStyle.allCases where !style.isSpinnerFamily {
            XCTAssertEqual(back.profiles[style], s.profiles[style], "\(style)")
        }
    }

    func testBaselineForTheTriWingSpinner() throws {
        let migrated = try decodeWithout(customised(), dropping: [.triWingSpinner])
        let withSnapshot = SettingsBaseline(snapshot: migrated)
        XCTAssertEqual(withSnapshot.baselineProfile(for: .triWingSpinner), migrated.profiles[.triWingSpinner])
        XCTAssertEqual(withSnapshot.baselineValue(\StyleProfile.spinner.metal, style: .triWingSpinner), .brass)
        XCTAssertEqual(withSnapshot.factoryValue(\StyleProfile.spinner.metal, style: .triWingSpinner), SpinnerSettings().metal)
        let none = SettingsBaseline(snapshot: nil)
        XCTAssertEqual(none.baselineProfile(for: .triWingSpinner), StyleProfile.defaults(for: .triWingSpinner))
    }
}
