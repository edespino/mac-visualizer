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

/// Covers `VisualizerSettings.load(from:)` resilience: corrupt files are backed
/// up (never silently wiped) before falling back to defaults.
final class VisualizerSettingsLoadTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-load-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let dir, FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    private func backupFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("settings.corrupt-") }
    }

    func testValidFileRoundTripsWithoutBackup() throws {
        let url = dir.appendingPathComponent("settings.json")
        var settings = VisualizerSettings.defaults
        settings.gain = 1.75
        try settings.save(to: url)

        let loaded = VisualizerSettings.load(from: url)
        XCTAssertEqual(loaded.gain, 1.75, accuracy: 1e-6)
        XCTAssertTrue(try backupFiles().isEmpty, "Valid settings must not produce a backup")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Original file must remain")
    }

    func testMissingFileReturnsDefaultsWithoutBackup() throws {
        let url = dir.appendingPathComponent("settings.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        let loaded = VisualizerSettings.load(from: url)
        XCTAssertEqual(loaded.visualizerStyle, VisualizerSettings.defaults.visualizerStyle)
        XCTAssertTrue(try backupFiles().isEmpty, "Missing file (first run) must not produce a backup")
    }

    func testCorruptJSONIsBackedUpAndResetsToDefaults() throws {
        let url = dir.appendingPathComponent("settings.json")
        try Data("{ this is not valid json".utf8).write(to: url)

        let loaded = VisualizerSettings.load(from: url)

        // Falls back to defaults.
        XCTAssertEqual(loaded.visualizerStyle, VisualizerSettings.defaults.visualizerStyle)
        // The bad file was moved aside (preserved), not silently wiped.
        let backups = try backupFiles()
        XCTAssertEqual(backups.count, 1, "Corrupt file must be backed up exactly once")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "Corrupt file is moved to the backup path")
        let backupContents = try String(contentsOf: backups[0], encoding: .utf8)
        XCTAssertEqual(backupContents, "{ this is not valid json",
                       "Backup must preserve the original bytes verbatim")
    }
}
