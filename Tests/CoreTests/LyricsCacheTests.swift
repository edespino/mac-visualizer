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

final class LyricsCacheTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyrics-cache-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private let track = LyricsTrack(title: "Hola Mundo", artist: "Artist", album: "Album", durationMs: 201_400)

    private func entry() -> TranslationEntry {
        TranslationEntry(title: "Hola Mundo", artist: "Artist", titleEn: "Hello World", lrclibId: 42, lines: [
            TranslationLine(timeMs: 1000, es: "hola", en: "hello", editedEs: nil, editedEn: nil),
            TranslationLine(timeMs: 2000, es: "adios", en: "bye", editedEs: "adiós", editedEn: "goodbye"),
            TranslationLine(timeMs: 3000, es: "", en: "", editedEs: nil, editedEn: nil),
        ])
    }

    // MARK: key

    func testKeyIsStableAndNormalized() {
        let a = LyricsCacheKey.make(for: LyricsTrack(title: "  Hola   Mundo ", artist: "ARTIST", album: "Album", durationMs: 201_400))
        let b = LyricsCacheKey.make(for: LyricsTrack(title: "hola mundo", artist: "artist", album: "album", durationMs: 201_900))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 64)
        XCTAssertTrue(a.allSatisfy { "0123456789abcdef".contains($0) })
    }

    func testKeyDiffersByDurationSecond() {
        var other = track
        other.durationMs = 202_000
        XCTAssertNotEqual(LyricsCacheKey.make(for: track), LyricsCacheKey.make(for: other))
    }

    func testKeyDiffersByField() {
        var other = track
        other.artist = "Someone Else"
        XCTAssertNotEqual(LyricsCacheKey.make(for: track), LyricsCacheKey.make(for: other))
        // Field boundaries matter: "ab"+"c" must differ from "a"+"bc".
        let x = LyricsTrack(title: "ab", artist: "c", album: "", durationMs: 1000)
        let y = LyricsTrack(title: "a", artist: "bc", album: "", durationMs: 1000)
        XCTAssertNotEqual(LyricsCacheKey.make(for: x), LyricsCacheKey.make(for: y))
    }

    // MARK: cache store

    func testReadMissingIsNil() {
        XCTAssertNil(LyricsCacheStore(directory: dir).read(track))
    }

    func testWriteThenReadRoundTrips() throws {
        let store = LyricsCacheStore(directory: dir)
        try store.write(entry(), for: track)
        XCTAssertEqual(store.read(track), entry())
    }

    func testApproximateFieldRoundTripsAndIsBackwardCompatible() throws {
        let store = LyricsCacheStore(directory: dir)
        XCTAssertNil(entry().approximate)
        var e = entry()
        e.approximate = true
        try store.write(e, for: track)
        XCTAssertEqual(store.read(track)?.approximate, true)
        // A file written before the field existed decodes with it nil.
        let legacy = #"{"title":"T","artist":"A","lines":[]}"#
        let decoded = try JSONDecoder().decode(TranslationEntry.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.approximate)
    }

    func testCorruptFileReadsAsNil() throws {
        let store = LyricsCacheStore(directory: dir)
        try store.write(entry(), for: track)
        let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first)
        try Data("{ not json".utf8).write(to: file)
        XCTAssertNil(store.read(track))
    }

    func testWriteOverwritesCorruptFile() throws {
        let store = LyricsCacheStore(directory: dir)
        try store.write(entry(), for: track)
        let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first)
        try Data([0xFF, 0x00, 0xFE]).write(to: file)
        XCTAssertNil(store.read(track))
        try store.write(entry(), for: track)
        XCTAssertEqual(store.read(track), entry())
    }

    func testWriteLeavesNoTempFiles() throws {
        let store = LyricsCacheStore(directory: dir)
        try store.write(entry(), for: track)
        try store.write(entry(), for: track)
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.map(\.lastPathComponent), ["\(LyricsCacheKey.make(for: track)).json"])
    }

    func testDefaultLocationsSitNextToSettings() {
        let base = VisualizerSettings.defaultFileURL().deletingLastPathComponent()
        XCTAssertEqual(LyricsCacheStore.defaultDirectory(), base.appendingPathComponent("lyrics", isDirectory: true))
        XCTAssertEqual(GeminiKeyStore.defaultFileURL(), base.appendingPathComponent("gemini-key"))
    }

    // MARK: key store

    private var keyFile: URL { dir.appendingPathComponent("gemini-key") }

    func testKeyStoreMissingIsNil() {
        XCTAssertNil(GeminiKeyStore(fileURL: keyFile).read())
    }

    func testKeyStoreRoundTrip() throws {
        let store = GeminiKeyStore(fileURL: keyFile)
        try store.write("abc")
        XCTAssertEqual(store.read(), "abc")
    }

    func testKeyStoreTrimsWhitespace() throws {
        let store = GeminiKeyStore(fileURL: keyFile)
        try store.write("  abc\n")
        XCTAssertEqual(store.read(), "abc")
        XCTAssertEqual(try String(contentsOf: keyFile, encoding: .utf8), "abc")
    }

    func testKeyStoreBlankRemovesFile() throws {
        let store = GeminiKeyStore(fileURL: keyFile)
        try store.write("abc")
        try store.write("  \n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: keyFile.path))
        XCTAssertNil(store.read())
        // Clearing when nothing is stored is not an error.
        XCTAssertNoThrow(try store.write(""))
    }

    func testKeyStoreFileIsOwnerOnly() throws {
        let store = GeminiKeyStore(fileURL: keyFile)
        try store.write("abc")
        try store.write("def")   // overwrite keeps the permissions
        let perms = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: keyFile.path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(perms.intValue, 0o600)
        XCTAssertEqual(store.read(), "def")
    }

    func testKeyStoreBlankFileReadsAsNil() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("  \n".utf8).write(to: keyFile)
        XCTAssertNil(GeminiKeyStore(fileURL: keyFile).read())
    }
}
