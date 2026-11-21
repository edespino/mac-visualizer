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

import XCTest
@testable import MacVisualizerCore

final class SpinnerSettingsTests: XCTestCase {

    private func decode(_ json: String) throws -> SpinnerSettings {
        try JSONDecoder().decode(SpinnerSettings.self, from: Data(json.utf8))
    }

    func testDefaults() {
        let s = SpinnerSettings()
        XCTAssertEqual(s.friction, 1.0)
        XCTAssertEqual(s.pushStrength, 1.0)
        XCTAssertEqual(s.topSpeed, 60)
        XCTAssertTrue(s.directionLock)
        XCTAssertEqual(s.rotationStepDegrees, 15)
        XCTAssertEqual(s.metal, .steel)
        XCTAssertEqual(s.hubFinish, .lit)
        XCTAssertEqual(s.glowBrightness, 1.0)
        XCTAssertEqual(s.roomLight, 1.0)
        XCTAssertEqual(s.size, 1.0)
        XCTAssertEqual(s.spinBlur, 1.0)
        XCTAssertEqual(s.shadowDarkness, 0.48)
        XCTAssertEqual(s.shadowSpread, 1.0)
        XCTAssertEqual(s.shadowDistance, 1.0)
        XCTAssertTrue(s.humEnabled)
        XCTAssertEqual(s.humVolume, 1.0)
        XCTAssertEqual(s.musicMode, .off)
        XCTAssertEqual(s.musicSustain, 0.85)
        XCTAssertEqual(s.musicKick, 2.0)
        XCTAssertEqual(s.renderer, .realityKit)
        XCTAssertEqual(SpinnerSettings.defaults, s)
    }

    func testRoundTrip() throws {
        var s = SpinnerSettings()
        s.friction = 2.5
        s.pushStrength = 3
        s.topSpeed = 90
        s.directionLock = false
        s.rotationStepDegrees = 45
        s.metal = .copper
        s.hubFinish = .raised
        s.glowBrightness = 1.5
        s.roomLight = 0.7
        s.size = 0.8
        s.spinBlur = 0.2
        s.shadowDarkness = 0.7
        s.shadowSpread = 2
        s.shadowDistance = 1.7
        s.humEnabled = false
        s.humVolume = 0.5
        s.musicMode = .both
        s.musicSustain = 0.3
        s.musicKick = 4
        s.renderer = .shader
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(SpinnerSettings.self, from: data)
        XCTAssertEqual(back, s)
    }

    func testEmptyObjectDecodesToDefaults() throws {
        XCTAssertEqual(try decode("{}"), SpinnerSettings())
    }

    func testEnumsEncodeAsStableStrings() throws {
        var s = SpinnerSettings()
        s.metal = .blackZirconium
        s.musicMode = .both
        s.renderer = .shader
        s.hubFinish = .raised
        let text = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
        XCTAssertTrue(text.contains("\"blackZirconium\""))
        XCTAssertTrue(text.contains("\"both\""))
        XCTAssertTrue(text.contains("\"shader\""))
        XCTAssertTrue(text.contains("\"raised\""))
    }

    func testUnknownEnumStringsFallBackToDefaults() throws {
        let json = "{\"metal\":\"unobtainium\",\"hubFinish\":\"glossy\",\"musicMode\":\"loud\",\"renderer\":\"vulkan\"}"
        let s = try decode(json)
        XCTAssertEqual(s.metal, .steel)
        XCTAssertEqual(s.hubFinish, .lit)
        XCTAssertEqual(s.musicMode, .off)
        XCTAssertEqual(s.renderer, .realityKit)
    }

    func testOutOfRangeValuesClampOnDecode() throws {
        let json: String = """
        {"friction":99,"pushStrength":0,"topSpeed":1000,"rotationStepDegrees":7,
         "glowBrightness":-3,"roomLight":9,"size":0,"spinBlur":5,
         "shadowDarkness":2,"shadowSpread":0,"shadowDistance":10,
         "humVolume":9,"musicSustain":2,"musicKick":-1}
        """
        let s = try decode(json)
        XCTAssertEqual(s.friction, 5.0)
        XCTAssertEqual(s.pushStrength, 0.25)
        XCTAssertEqual(s.topSpeed, 120)
        XCTAssertEqual(s.rotationStepDegrees, 15)   // not one of 5, 10, 15, 30, 45: default
        XCTAssertEqual(s.glowBrightness, 0)
        XCTAssertEqual(s.roomLight, 1.6)
        XCTAssertEqual(s.size, 0.4)
        XCTAssertEqual(s.spinBlur, 1.5)
        XCTAssertEqual(s.shadowDarkness, 0.85)
        XCTAssertEqual(s.shadowSpread, 0.3)
        XCTAssertEqual(s.shadowDistance, 2.5)
        XCTAssertEqual(s.humVolume, 1.5)
        XCTAssertEqual(s.musicSustain, 1.0)
        XCTAssertEqual(s.musicKick, 0)
    }

    func testLowerBoundsAndStepSnap() throws {
        let s = try decode("{\"friction\":0,\"topSpeed\":1,\"rotationStepDegrees\":30}")
        XCTAssertEqual(s.friction, 0.2)
        XCTAssertEqual(s.topSpeed, 20)
        XCTAssertEqual(s.rotationStepDegrees, 30)
    }

    func testSettingClampsViaProperty() {
        var s = SpinnerSettings()
        s.friction = 100
        XCTAssertEqual(s.friction, 5.0)
        s.size = -1
        XCTAssertEqual(s.size, 0.4)
        s.rotationStepDegrees = 12
        XCTAssertEqual(s.rotationStepDegrees, 15)
        s.rotationStepDegrees = 45
        XCTAssertEqual(s.rotationStepDegrees, 45)
        s.shadowDarkness = 0.6
        XCTAssertEqual(s.shadowDarkness, 0.6)
    }

    func testNonFiniteValuesFallBackToDefault() {
        var s = SpinnerSettings()
        s.friction = Double.nan
        XCTAssertEqual(s.friction, 1.0)
        s.topSpeed = Double.infinity
        XCTAssertEqual(s.topSpeed, 120)
    }

    func testEnumRawValuesAndIndices() {
        XCTAssertEqual(SpinnerMetal.steel.index, 0)
        XCTAssertEqual(SpinnerMetal.anodizedTitanium.index, 4)
        XCTAssertEqual(SpinnerMetal.allCases.map { $0.index }, [0, 1, 2, 3, 4])
        XCTAssertEqual(SpinnerHubFinish.lit.index, 0)
        XCTAssertEqual(SpinnerHubFinish.raised.index, 1)
        XCTAssertEqual(SpinnerHubFinish.engraved.index, 2)
        XCTAssertEqual(SpinnerHubFinish.engraved.rawValue, "engraved")
        XCTAssertEqual(SpinnerHubFinish.allCases.count, 3)
        XCTAssertEqual(SpinnerHubMark.interlock.index, 0)
        XCTAssertEqual(SpinnerHubMark.signOff.index, 1)
        XCTAssertEqual(SpinnerMetal.blackZirconium.rawValue, "blackZirconium")
    }

    func testCyclingHelpersWrap() {
        XCTAssertEqual(SpinnerMetal.steel.next, .brass)
        XCTAssertEqual(SpinnerMetal.anodizedTitanium.next, .steel)
        XCTAssertEqual(SpinnerHubFinish.lit.next, .raised)
        XCTAssertEqual(SpinnerHubFinish.raised.next, .engraved)
        XCTAssertEqual(SpinnerHubFinish.engraved.next, .lit)
        XCTAssertEqual(SpinnerMusicMode.off.next, .sustain)
        XCTAssertEqual(SpinnerMusicMode.both.next, .off)
        XCTAssertEqual(SpinnerRendererChoice.shader.next, .realityKit)
        XCTAssertEqual(SpinnerRendererChoice.realityKit.next, .shader)
    }

    // MARK: StyleProfile / settings integration

    func testStyleProfileCarriesDefaultSpinner() {
        XCTAssertEqual(StyleProfile.defaults.spinner, SpinnerSettings())
        XCTAssertEqual(StyleProfile.defaults(for: .spinner).spinner, SpinnerSettings())
    }

    func testStyleProfileEqualityNoticesSpinnerField() {
        var a = StyleProfile.defaults
        let b = StyleProfile.defaults
        XCTAssertEqual(a, b)
        a.spinner.friction = 2
        XCTAssertNotEqual(a, b)
    }

    func testLegacyProfileJSONWithoutSpinnerKeyDecodesToDefaults() throws {
        let json = "{\"paletteName\":\"classic\",\"gain\":2.0}"
        let p = try JSONDecoder().decode(StyleProfile.self, from: Data(json.utf8))
        XCTAssertEqual(p.spinner, SpinnerSettings())
        XCTAssertEqual(p.gain, 2.0)
    }

    func testSettingsRoundTripKeepsSpinnerProfile() throws {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .spinner
        s.mutateCurrent { $0.spinner.metal = .brass; $0.spinner.friction = 0.5 }
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(VisualizerSettings.self, from: data)
        XCTAssertEqual(back.current.spinner.metal, .brass)
        XCTAssertEqual(back.current.spinner.friction, 0.5)
        XCTAssertEqual(back, s)
    }

    func testResetCurrentStyleRestoresSpinnerFields() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .spinner
        s.mutateCurrent { $0.spinner.metal = .copper; $0.spinner.shadowDarkness = 0.1 }
        s.resetCurrentStyle(to: .defaults)
        XCTAssertEqual(s.current.spinner, SpinnerSettings())
    }

    func testResetToSnapshotRestoresSnapshotSpinnerFields() {
        var snap = VisualizerSettings.defaults
        snap.visualizerStyle = .spinner
        snap.mutateCurrent { $0.spinner.humVolume = 0.25 }
        var live = snap
        live.mutateCurrent { $0.spinner.humVolume = 1.4; $0.spinner.size = 0.6 }
        live.resetCurrentStyle(to: snap)
        XCTAssertEqual(live.current.spinner.humVolume, 0.25)
        XCTAssertEqual(live.current.spinner.size, 1.0)
    }

    func testBaselineNoticesSpinnerFieldChange() {
        var live = VisualizerSettings.defaults
        live.visualizerStyle = .spinner
        let b = SettingsBaseline()
        XCTAssertFalse(b.currentStyleDiffersFromBaseline(live))
        live.mutateCurrent { $0.spinner.roomLight = 1.3 }
        XCTAssertTrue(b.currentStyleDiffersFromBaseline(live))
        XCTAssertTrue(b.currentStyleDiffersFromFactory(live))
    }

    func testBaselineValueByNestedKeyPath() {
        var snap = VisualizerSettings.defaults
        snap.visualizerStyle = .spinner
        snap.mutateCurrent { $0.spinner.glowBrightness = 0.4 }
        let b = SettingsBaseline(snapshot: snap)
        XCTAssertEqual(b.baselineValue(\StyleProfile.spinner.glowBrightness, style: .spinner), 0.4)
        XCTAssertEqual(b.factoryValue(\StyleProfile.spinner.glowBrightness, style: .spinner), 1.0)
    }

    func testSaveStyleAsDefaultsCarriesSpinnerFields() {
        var live = VisualizerSettings.defaults
        live.visualizerStyle = .spinner
        live.mutateCurrent { $0.spinner.spinBlur = 0.3 }
        let merged = SettingsBaseline().snapshotSavingCurrentStyle(of: live)
        XCTAssertEqual(merged.profiles[.spinner]?.spinner.spinBlur, 0.3)
    }
}
