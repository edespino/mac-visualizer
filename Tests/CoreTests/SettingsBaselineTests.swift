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

final class SettingsBaselineTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("baseline-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("user-defaults.json")
    }

    private func customSettings() -> VisualizerSettings {
        var s = VisualizerSettings.defaults
        s.vignetteAmount = 0.6
        s.particlesBaseSize = 0.03
        s.lyrics.fadeLines = 4
        s.visualizerStyle = .bars
        s.mutateCurrent { $0.gain = 3.25 }
        s.visualizerStyle = .wireframe
        s.mutateCurrent { $0.positionOffsetY = 0.2 }
        return s
    }

    // MARK: no snapshot -> factory

    func testNoSnapshotBaselineEqualsFactory() {
        let b = SettingsBaseline()
        XCTAssertFalse(b.hasUserDefaults)
        XCTAssertEqual(b.baselineValue(\VisualizerSettings.vignetteAmount),
                       VisualizerSettings.defaults.vignetteAmount)
        XCTAssertEqual(b.baselineValue(\VisualizerSettings.vignetteAmount),
                       b.factoryValue(\VisualizerSettings.vignetteAmount))
        XCTAssertEqual(b.baselineValue(\StyleProfile.gain, style: .bars),
                       StyleProfile.defaults(for: .bars).gain)
    }

    // MARK: snapshot

    func testSnapshotValueIsBaselineButFactoryUnchanged() {
        let b = SettingsBaseline(snapshot: customSettings())
        XCTAssertTrue(b.hasUserDefaults)
        XCTAssertEqual(b.baselineValue(\VisualizerSettings.vignetteAmount), 0.6)
        XCTAssertEqual(b.factoryValue(\VisualizerSettings.vignetteAmount),
                       VisualizerSettings.defaults.vignetteAmount)
        XCTAssertEqual(b.baselineValue(\VisualizerSettings.lyrics.fadeLines), 4)
        XCTAssertEqual(b.baselineValue(\VisualizerSettings.particlesBaseSize), 0.03)
    }

    func testPerStyleBaselineComesFromThatStylesProfile() {
        let b = SettingsBaseline(snapshot: customSettings())
        XCTAssertEqual(b.baselineValue(\StyleProfile.gain, style: .bars), 3.25)
        // A different style's profile in the snapshot is untouched.
        XCTAssertEqual(b.baselineValue(\StyleProfile.gain, style: .plasma),
                       StyleProfile.defaults(for: .plasma).gain)
        XCTAssertEqual(b.factoryValue(\StyleProfile.gain, style: .bars),
                       StyleProfile.defaults(for: .bars).gain)
    }

    func testPerStyleFallsBackToFactoryWhenSnapshotLacksStyle() {
        var s = customSettings()
        s.profiles.removeValue(forKey: .wireframe)
        let b = SettingsBaseline(snapshot: s)
        XCTAssertEqual(b.baselineValue(\StyleProfile.positionOffsetY, style: .wireframe), -0.07,
                       accuracy: 1e-6)
    }

    func testWireframeFactoryOffsetIsMinus007() {
        let b = SettingsBaseline()
        XCTAssertEqual(b.factoryValue(\StyleProfile.positionOffsetY, style: .wireframe), -0.07,
                       accuracy: 1e-6)
        XCTAssertEqual(b.baselineValue(\StyleProfile.positionOffsetY, style: .wireframe), -0.07,
                       accuracy: 1e-6)
        XCTAssertEqual(b.factoryValue(\StyleProfile.positionOffsetY, style: .bars), 0, accuracy: 1e-6)
    }

    // MARK: persistence

    func testSaveLoadRoundTrip() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let saved = try SettingsBaseline.save(customSettings(), to: url)
        XCTAssertTrue(saved.hasUserDefaults)
        XCTAssertNotNil(saved.savedAt)
        let loaded = SettingsBaseline.load(from: url)
        XCTAssertTrue(loaded.hasUserDefaults)
        XCTAssertEqual(loaded.snapshot, customSettings())
        XCTAssertNotNil(loaded.savedAt)
    }

    func testMissingFileLoadsAsFactory() {
        let b = SettingsBaseline.load(from: tempURL())
        XCTAssertFalse(b.hasUserDefaults)
        XCTAssertNil(b.savedAt)
    }

    func testCorruptFileLoadsAsFactoryAndIsLeftInPlace() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("not json {{".utf8).write(to: url)
        let b = SettingsBaseline.load(from: url)
        XCTAssertFalse(b.hasUserDefaults)
        XCTAssertEqual(b.baselineValue(\VisualizerSettings.vignetteAmount),
                       VisualizerSettings.defaults.vignetteAmount)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testClearRemovesFileAndIsIdempotent() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        _ = try SettingsBaseline.save(customSettings(), to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try SettingsBaseline.clear(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNoThrow(try SettingsBaseline.clear(at: url))
        XCTAssertFalse(SettingsBaseline.load(from: url).hasUserDefaults)
    }

    // MARK: whole-style reset to a baseline

    func testResetCurrentStyleToSnapshotRestoresSnapshotValues() {
        var snap = VisualizerSettings.defaults
        snap.visualizerStyle = .particles
        snap.particlesBaseSize = 0.04
        snap.mutateCurrent { $0.gain = 2.5 }

        var s = VisualizerSettings.defaults
        s.visualizerStyle = .particles
        s.particlesBaseSize = 0.01
        s.mutateCurrent { $0.gain = 9 }
        s.vignetteAmount = 0.5   // app-wide field must survive a style reset

        s.resetCurrentStyle(to: snap)
        XCTAssertEqual(s.particlesBaseSize, 0.04)
        XCTAssertEqual(s.current.gain, 2.5)
        XCTAssertEqual(s.vignetteAmount, 0.5)
    }

    func testResetCurrentStyleToFactoryIgnoresSnapshot() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .particles
        s.particlesBaseSize = 0.01
        s.resetCurrentStyle(to: .defaults)
        XCTAssertEqual(s.particlesBaseSize, VisualizerSettings.defaults.particlesBaseSize)
    }
}

// MARK: - Current style vs baseline / factory

final class SettingsBaselineStyleDiffTests: XCTestCase {
    func testFactoryStyleMatchesBaselineAndFactory() {
        let b = SettingsBaseline()
        let s = VisualizerSettings.defaults
        XCTAssertFalse(b.currentStyleDiffersFromBaseline(s))
        XCTAssertFalse(b.currentStyleDiffersFromFactory(s))
    }

    func testProfileEditDiffers() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .bars
        s.mutateCurrent { $0.gain = 3.25 }
        let b = SettingsBaseline()
        XCTAssertTrue(b.currentStyleDiffersFromBaseline(s))
        XCTAssertTrue(b.currentStyleDiffersFromFactory(s))
    }

    func testStyleExclusiveTopLevelFieldDiffers() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .joyPlot
        s.joyPlotRowSpacing += 0.01
        XCTAssertTrue(SettingsBaseline().currentStyleDiffersFromBaseline(s))
    }

    func testOtherStyleEditDoesNotCount() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .wireframe
        s.mutateCurrent { $0.gain = 3.25 }
        s.visualizerStyle = .bars
        XCTAssertFalse(SettingsBaseline().currentStyleDiffersFromBaseline(s))
    }

    func testMatchesSnapshotButDiffersFromFactory() {
        var snap = VisualizerSettings.defaults
        snap.visualizerStyle = .bars
        snap.mutateCurrent { $0.gain = 3.25 }
        let b = SettingsBaseline(snapshot: snap)
        XCTAssertFalse(b.currentStyleDiffersFromBaseline(snap))
        XCTAssertTrue(b.currentStyleDiffersFromFactory(snap))
        XCTAssertTrue(b.currentStyleDiffersFromBaseline(.defaults))
    }
}

// MARK: - Save current style into the snapshot

final class SettingsBaselineSaveStyleTests: XCTestCase {
    func testNoSnapshotEqualsFactoryExceptSavedStyle() {
        var live = VisualizerSettings.defaults
        live.visualizerStyle = .bars
        live.mutateCurrent { $0.gain = 3.25 }
        live.vignetteAmount = 0.9   // app-wide, must not leak
        let out = SettingsBaseline().snapshotSavingCurrentStyle(of: live)
        var expected = VisualizerSettings.defaults
        expected.visualizerStyle = .bars
        expected.mutateCurrent { $0.gain = 3.25 }
        expected.visualizerStyle = VisualizerSettings.defaults.visualizerStyle
        XCTAssertEqual(out, expected)
    }

    func testExistingSnapshotPreservesOthers() {
        var snap = VisualizerSettings.defaults
        snap.visualizerStyle = .wireframe
        snap.mutateCurrent { $0.gain = 2.5 }
        snap.vignetteAmount = 0.6
        snap.visualizerStyle = .joyPlot
        var live = VisualizerSettings.defaults
        live.visualizerStyle = .bars
        live.mutateCurrent { $0.gain = 3.25 }
        let out = SettingsBaseline(snapshot: snap).snapshotSavingCurrentStyle(of: live)
        XCTAssertEqual(out.profiles[.wireframe]?.gain, 2.5)
        XCTAssertEqual(out.vignetteAmount, 0.6)
        XCTAssertEqual(out.profiles[.bars]?.gain, 3.25)
    }

    func testExclusiveFieldCarriedSharedFieldNot() {
        var live = VisualizerSettings.defaults
        live.visualizerStyle = .joyPlot
        live.joyPlotRowSpacing += 0.01
        live.particleSize += 0.5
        live.barGap += 0.1
        let out = SettingsBaseline().snapshotSavingCurrentStyle(of: live)
        XCTAssertEqual(out.joyPlotRowSpacing, live.joyPlotRowSpacing)
        XCTAssertEqual(out.particleSize, VisualizerSettings.defaults.particleSize)
        XCTAssertEqual(out.barGap, VisualizerSettings.defaults.barGap)
    }

    func testSnapshotActiveStyleUnchanged() {
        var snap = VisualizerSettings.defaults
        snap.visualizerStyle = .voronoi
        var live = VisualizerSettings.defaults
        live.visualizerStyle = .bars
        let out = SettingsBaseline(snapshot: snap).snapshotSavingCurrentStyle(of: live)
        XCTAssertEqual(out.visualizerStyle, .voronoi)
    }

    func testAfterSaveStyleMatchesBaseline() {
        var live = VisualizerSettings.defaults
        live.visualizerStyle = .joyPlot
        live.joyPlotRowSpacing += 0.01
        live.mutateCurrent { $0.gain = 3.25 }
        let b = SettingsBaseline(snapshot: SettingsBaseline().snapshotSavingCurrentStyle(of: live))
        XCTAssertFalse(b.currentStyleDiffersFromBaseline(live))
    }
}
