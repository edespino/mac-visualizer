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

@MainActor
final class LyricsModelTests: XCTestCase {
    private var dir: URL!
    private var cache: LyricsCacheStore!
    private var keyStore: GeminiKeyStore!
    private var fetcher: FakeLyricsFetcher!
    private var provider: FakeTranslationProvider!
    private var providersBuilt = 0
    private var builtWith: (key: String, model: String)?

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyrics-model-tests-\(UUID().uuidString)", isDirectory: true)
        cache = LyricsCacheStore(directory: dir.appendingPathComponent("lyrics", isDirectory: true))
        keyStore = GeminiKeyStore(fileURL: dir.appendingPathComponent("gemini-key"))
        try keyStore.write("test-key")
        fetcher = FakeLyricsFetcher()
        provider = FakeTranslationProvider { lines, _ in lines.map { "EN:\($0)" } }
        providersBuilt = 0
        builtWith = nil
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeModel() -> LyricsModel {
        LyricsModel(
            fetcher: fetcher,
            makeProvider: { [unowned self] key, model in
                self.providersBuilt += 1
                self.builtWith = (key, model)
                return self.provider
            },
            cache: cache,
            keyStore: keyStore,
            sleep: { _ in }
        )
    }

    private var on: LyricsSettings { var s = LyricsSettings.defaults; s.enabled = true; return s }
    private var off: LyricsSettings { var s = LyricsSettings.defaults; s.enabled = false; return s }

    private func track(_ title: String, durationMs: Int = 200_000, artist: String = "Artist") -> LyricsTrack {
        LyricsTrack(title: title, artist: artist, album: "Album", durationMs: durationMs)
    }

    private func snap(_ track: LyricsTrack, positionMs: Int = 0, playing: Bool = true, at: Double = 0) -> PlaybackSnapshot {
        PlaybackSnapshot(track: track, positionMs: positionMs, isPlaying: playing, sampledAtMs: at)
    }

    private func synced(_ texts: [String], approximate: Bool = false) -> LyricsResult {
        .synced(lines: texts.enumerated().map { LyricLine(timeMs: ($0.offset + 1) * 1000, text: $0.element) },
                lrclibId: 7, approximate: approximate)
    }

    private func waitUntil(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("condition not met in time", file: file, line: line)
    }

    // MARK: basic flows

    func testDisabledMakesNoFetch() async {
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: off)
        await model.waitForIdle()
        XCTAssertEqual(fetcher.calls.count, 0)
        XCTAssertNil(model.display)
        XCTAssertEqual(model.status, .off)
    }

    func testNoPlaybackShowsNothing() async {
        let model = makeModel()
        model.update(playback: nil, settings: on)
        await model.waitForIdle()
        XCTAssertNil(model.display)
        XCTAssertEqual(model.status, .nothingPlaying)
    }

    func testSpanishSongShowsOriginalThenTranslation() async throws {
        fetcher.results["A"] = synced(LyricSamples.spanish)
        let gate = TestGate()
        provider = FakeTranslationProvider { lines, _ in
            await gate.wait()
            return lines.map { "EN:\($0)" }
        }
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await waitUntil(model.status == .translating)

        let before = try XCTUnwrap(model.display)
        XCTAssertFalse(before.singleColumn)
        XCTAssertEqual(before.rows.map(\.original), LyricSamples.spanish)
        XCTAssertTrue(before.rows.allSatisfy { $0.translation == nil })
        XCTAssertEqual(before.rows.map(\.id), Array(0..<8))
        XCTAssertEqual(before.rows.first?.timeMs, 1000)

        await gate.release()
        await model.waitForIdle()
        let after = try XCTUnwrap(model.display)
        XCTAssertEqual(after.rows.map(\.translation), LyricSamples.spanish.map { "EN:\($0)" })
        XCTAssertEqual(model.status, .translated)
        XCTAssertEqual(builtWith?.key, "test-key")
        XCTAssertEqual(builtWith?.model, "gemini-flash-lite-latest")

        let entry = try XCTUnwrap(cache.read(track("A")))
        XCTAssertEqual(entry.titleEn, "EN:A")
        XCTAssertEqual(entry.lrclibId, 7)
        XCTAssertEqual(entry.lines.map(\.es), LyricSamples.spanish)
        XCTAssertEqual(entry.lines.map(\.en), LyricSamples.spanish.map { "EN:\($0)" })
        XCTAssertEqual(entry.lines.map(\.timeMs), Array(1...8).map { $0 * 1000 })
    }

    func testCachedSongMakesNoNetworkCall() async throws {
        let entry = TranslationEntry(title: "A", artist: "Artist", titleEn: "A en", lrclibId: nil, lines: [
            TranslationLine(timeMs: 1000, es: "hola", en: "hello"),
            TranslationLine(timeMs: 5000, es: "adios", en: "bye", editedEs: "adiós", editedEn: "goodbye"),
        ])
        try cache.write(entry, for: track("A"))
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(fetcher.calls.count, 0)
        XCTAssertEqual(providersBuilt, 0)
        XCTAssertEqual(model.status, .translated)
        XCTAssertEqual(model.display?.rows.map(\.original), ["hola", "adiós"])
        XCTAssertEqual(model.display?.rows.map(\.translation), ["hello", "goodbye"])
    }

    func testDisplayCarriesTrackTitleAndArtist() async throws {
        // The lyric-header shows the song, so the display must carry the live
        // track's title and artist — not the cache entry's stored fields.
        let entry = TranslationEntry(title: "A", artist: "Cached Artist", titleEn: nil, lrclibId: nil, lines: [
            TranslationLine(timeMs: 1000, es: "hola", en: "hello"),
            TranslationLine(timeMs: 5000, es: "adiós", en: "goodbye"),
        ])
        let t = track("A", artist: "Ibrahim Ferrer")
        try cache.write(entry, for: t)
        let model = makeModel()
        model.update(playback: snap(t), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(model.status, .translated)
        XCTAssertEqual(model.display?.title, "A")
        XCTAssertEqual(model.display?.artist, "Ibrahim Ferrer")
    }

    func testEnglishSongIsSingleColumnAndUntranslated() async throws {
        fetcher.results["A"] = synced(LyricSamples.english)
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await model.waitForIdle()
        let display = try XCTUnwrap(model.display)
        XCTAssertTrue(display.singleColumn)
        XCTAssertEqual(display.rows.map(\.original), LyricSamples.english)
        XCTAssertEqual(model.status, .englishNoTranslation)
        XCTAssertEqual(providersBuilt, 0)
        // English lyrics are cached without any translation text.
        XCTAssertEqual(cache.read(track("A"))?.lines.map(\.en), Array(repeating: "", count: LyricSamples.english.count))
    }

    func testNoKeyShowsSpanishOnly() async throws {
        try keyStore.write("")
        fetcher.results["A"] = synced(LyricSamples.spanish)
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(model.status, .noKey)
        XCTAssertEqual(model.display?.rows.map(\.original), LyricSamples.spanish)
        XCTAssertEqual(model.display?.rows.allSatisfy { $0.translation == nil }, true)
        // No key → show the lyrics untranslated in a single centered column (any
        // language), not a two-column layout with a blank translation side.
        XCTAssertEqual(model.display?.singleColumn, true)
        XCTAssertEqual(providersBuilt, 0)
    }

    func testKeyDidChangeRetriesTranslation() async throws {
        try keyStore.write("")
        fetcher.results["A"] = synced(LyricSamples.spanish)
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(model.status, .noKey)

        try keyStore.write("new-key")
        model.keyDidChange()
        await model.waitForIdle()
        XCTAssertEqual(model.status, .translated)
        XCTAssertEqual(builtWith?.key, "new-key")
        XCTAssertEqual(fetcher.calls.count, 1)
        XCTAssertEqual(model.display?.rows.first?.translation, "EN:\(LyricSamples.spanish[0])")
    }

    func testTranslationFailureLeavesTranslationNil() async throws {
        fetcher.results["A"] = synced(LyricSamples.spanish)
        provider = FakeTranslationProvider { _, _ in ["wrong count"] }
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await model.waitForIdle()
        guard case .translationFailed = model.status else { return XCTFail("status \(model.status)") }
        let rows = try XCTUnwrap(model.display?.rows)
        XCTAssertEqual(rows.count, 8)
        XCTAssertTrue(rows.allSatisfy { $0.translation == nil })
        XCTAssertNil(cache.read(track("A")))
    }

    func testPlainInstrumentalNoneAndErrorShowHeaderOnly() async {
        fetcher.results["plain"] = .plain(lines: ["a", "b"], lrclibId: nil)
        fetcher.results["inst"] = .instrumental
        fetcher.results["none"] = LyricsResult.none
        fetcher.failing = ["err"]
        let expected: [(String, LyricsStatus)] = [
            ("plain", .noSyncedLyrics), ("inst", .instrumental), ("none", .noSyncedLyrics), ("err", .lyricsError),
        ]
        let model = makeModel()
        for (title, status) in expected {
            model.update(playback: snap(track(title)), settings: on)
            await model.waitForIdle()
            // No lyric rows, but the song still shows its title/performer header.
            XCTAssertEqual(model.display?.rows.isEmpty, true, title)
            XCTAssertEqual(model.display?.title, title, title)
            XCTAssertEqual(model.display?.artist, "Artist", title)
            XCTAssertEqual(model.status, status, title)
        }
        XCTAssertEqual(providersBuilt, 0)
    }

    func testSyncedWithOnlyBlankLinesIsInstrumental() async {
        fetcher.results["A"] = synced(["", "  ", ""])
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await model.waitForIdle()
        // No lyric rows, but the title/performer header is still shown.
        XCTAssertEqual(model.display?.rows.isEmpty, true)
        XCTAssertEqual(model.display?.title, "A")
        XCTAssertEqual(model.status, .instrumental)
        XCTAssertEqual(providersBuilt, 0)
    }

    func testEmptyLinesStayEmptyInBothColumns() async throws {
        var texts = LyricSamples.spanish
        texts.insert("", at: 3)
        fetcher.results["A"] = synced(texts)
        provider = FakeTranslationProvider { lines, _ in lines.map { $0.isEmpty ? "" : "EN:\($0)" } }
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await model.waitForIdle()
        let row = try XCTUnwrap(model.display?.rows[3])
        XCTAssertEqual(row.original, "")
        XCTAssertEqual(row.translation, "")
    }

    func testChangingModelRetriesFailedTranslation() async throws {
        fetcher.results["A"] = synced(LyricSamples.spanish)
        provider = FakeTranslationProvider { [unowned self] lines, _ in
            if self.builtWith?.model == "retired-model" {
                throw TranslationProviderError.modelUnavailable(model: "retired-model")
            }
            return lines.map { "EN:\($0)" }
        }
        var bad = on
        bad.geminiModel = "retired-model"
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: bad)
        await model.waitForIdle()
        guard case .translationFailed = model.status else { return XCTFail("status \(model.status)") }

        // Same track, corrected model: retries without a track change or refetch.
        model.update(playback: snap(track("A")), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(model.status, .translated)
        XCTAssertEqual(builtWith?.model, "gemini-flash-lite-latest")
        XCTAssertEqual(fetcher.calls.count, 1)
    }

    func testUnchangedModelDoesNotRetryFailedTranslation() async throws {
        fetcher.results["A"] = synced(LyricSamples.spanish)
        provider = FakeTranslationProvider { _, _ in ["wrong count"] }
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await model.waitForIdle()
        let callsAfterFailure = provider.calls.count
        model.update(playback: snap(track("A"), positionMs: 1_500, at: 1_500), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(provider.calls.count, callsAfterFailure)
    }

    // MARK: approximate matches and fetch options

    func testApproximateMatchIsFlaggedAndCached() async throws {
        fetcher.results["A"] = synced(LyricSamples.spanish, approximate: true)
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(model.status, .translated)
        XCTAssertTrue(model.approximateMatch)
        XCTAssertEqual(cache.read(track("A"))?.approximate, true)
    }

    func testExactMatchIsNotFlagged() async throws {
        fetcher.results["A"] = synced(LyricSamples.spanish)
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await model.waitForIdle()
        XCTAssertFalse(model.approximateMatch)
        XCTAssertNil(cache.read(track("A"))?.approximate)
    }

    func testApproximateFlagRestoredFromCache() async throws {
        let entry = TranslationEntry(title: "A", artist: "Artist", titleEn: nil, lrclibId: nil, lines: [
            TranslationLine(timeMs: 1000, es: "hola", en: "hello"),
        ], approximate: true)
        try cache.write(entry, for: track("A"))
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(model.status, .translated)
        XCTAssertTrue(model.approximateMatch)
    }

    func testApproximateOffDropsCachedApproximateEntry() async throws {
        // A song cached while approximate matching was on.
        try cache.write(TranslationEntry(title: "A", artist: "Artist", titleEn: nil, lrclibId: nil, lines: [
            TranslationLine(timeMs: 1000, es: "hola", en: "hello"),
        ], approximate: true), for: track("A"))
        // No exact-length recording exists, so a strict refetch finds nothing.
        var s = on
        s.acceptApproximateMatches = false
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: s)
        await model.waitForIdle()
        // Turning the toggle off takes effect for the already-cached song:
        // the loose lyrics are not shown, the model refetches strictly, and
        // finds nothing.
        XCTAssertEqual(fetcher.calls.count, 1)
        XCTAssertFalse(model.approximateMatch)
        // No lyric rows, but the song still shows its title/performer header.
        XCTAssertEqual(model.display?.rows.isEmpty, true)
        XCTAssertEqual(model.display?.title, "A")
        XCTAssertEqual(model.status, .noSyncedLyrics)
    }

    // MARK: English lyrics cache

    func testEnglishLyricsAreCachedAndReusedWithoutRefetch() async throws {
        fetcher.results["A"] = synced(LyricSamples.english)
        let first = makeModel()
        first.update(playback: snap(track("A")), settings: on)
        await first.waitForIdle()
        XCTAssertEqual(first.status, .englishNoTranslation)
        XCTAssertEqual(fetcher.calls.count, 1)
        // The same song again (a new model sharing the cache): no lookup.
        let second = makeModel()
        second.update(playback: snap(track("A")), settings: on)
        await second.waitForIdle()
        XCTAssertEqual(fetcher.calls.count, 1)
        XCTAssertEqual(second.status, .englishNoTranslation)
        XCTAssertEqual(second.display?.singleColumn, true)
        XCTAssertEqual(second.display?.rows.map(\.original), LyricSamples.english)
        XCTAssertEqual(second.display?.rows.compactMap(\.translation), [])
    }

    func testApproximateEnglishMatchIsNotCached() async throws {
        // An approximate match may be replaced by a better one; do not pin it.
        fetcher.results["A"] = synced(LyricSamples.english, approximate: true)
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(model.status, .englishNoTranslation)
        XCTAssertNil(cache.read(track("A")))
    }

    func testUntranslatedCacheEntryForNonEnglishSongIsRefetched() async throws {
        // An entry cached without translations (as English) that no longer
        // reads as English must not show an empty translation column.
        try cache.write(TranslationEntry(title: "A", artist: "Artist", titleEn: nil, lrclibId: nil,
            lines: LyricSamples.spanish.enumerated().map { TranslationLine(timeMs: $0.offset * 1000, es: $0.element, en: "") }),
            for: track("A"))
        fetcher.results["A"] = synced(LyricSamples.spanish)
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(fetcher.calls.count, 1)
    }

    func testCachedEntryRunningPastTrackEndIsRefetched() async throws {
        // A song cached from a mis-timed record: its last line is far past the
        // end of the track (track("A") length), so the cache is not trusted.
        let t = track("A")
        try cache.write(TranslationEntry(title: "A", artist: "Artist", titleEn: nil, lrclibId: nil, lines: [
            TranslationLine(timeMs: t.durationMs + 20_000, es: "hola", en: "hello"),
        ]), for: t)
        fetcher.results["A"] = synced(LyricSamples.english)
        let model = makeModel()
        model.update(playback: snap(t), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(fetcher.calls.count, 1)
    }

    func testCachedApproximateEntryRunningPastTrackEndIsStillServed() async throws {
        // Approximate entries are a different-length recording by definition
        // (and the mis-timed fallback is stamped approximate), so no refetch loop.
        let t = track("A")
        try cache.write(TranslationEntry(title: "A", artist: "Artist", titleEn: nil, lrclibId: nil, lines: [
            TranslationLine(timeMs: t.durationMs + 20_000, es: "hola", en: "hello"),
        ], approximate: true), for: t)
        let model = makeModel()
        model.update(playback: snap(t), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(fetcher.calls.count, 0)
    }

    func testApproximateCacheStillShownWhenApproximateOn() async throws {
        // The same cached approximate entry is served (no refetch) while the
        // toggle is on, so the fix does not regress the default behavior.
        try cache.write(TranslationEntry(title: "A", artist: "Artist", titleEn: nil, lrclibId: nil, lines: [
            TranslationLine(timeMs: 1000, es: "hola", en: "hello"),
        ], approximate: true), for: track("A"))
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(fetcher.calls.count, 0)
        XCTAssertTrue(model.approximateMatch)
        XCTAssertEqual(model.status, .translated)
    }

    func testFetchOptionsCarrySettings() async throws {
        fetcher.results["A"] = synced(LyricSamples.english)
        var s = on
        s.localLyricsFolder = "/music/lyrics"
        s.acceptApproximateMatches = false
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: s)
        await model.waitForIdle()
        XCTAssertEqual(fetcher.lastOptions?.localFolder, "/music/lyrics")
        XCTAssertEqual(fetcher.lastOptions?.allowApproximateMatch, false)
    }

    func testEmptyFolderBecomesNilOption() async throws {
        fetcher.results["A"] = synced(LyricSamples.english)
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await model.waitForIdle()
        XCTAssertNil(fetcher.lastOptions?.localFolder)
        XCTAssertEqual(fetcher.lastOptions?.allowApproximateMatch, true)
    }

    func testChangingFolderRefetchesCurrentTrack() async throws {
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)   // no result for A -> none
        await model.waitForIdle()
        XCTAssertEqual(fetcher.calls.count, 1)
        var s = on
        s.localLyricsFolder = "/music/lyrics"
        model.update(playback: snap(track("A")), settings: s)
        await model.waitForIdle()
        XCTAssertEqual(fetcher.calls.count, 2)
        XCTAssertEqual(fetcher.lastOptions?.localFolder, "/music/lyrics")
    }

    func testTogglingApproximateRefetchesCurrentTrack() async throws {
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(fetcher.calls.count, 1)
        var s = on
        s.acceptApproximateMatches = false
        model.update(playback: snap(track("A")), settings: s)
        await model.waitForIdle()
        XCTAssertEqual(fetcher.calls.count, 2)
        XCTAssertEqual(fetcher.lastOptions?.allowApproximateMatch, false)
    }

    func testLocalFolderOverridesCachedRemoteEntry() async throws {
        // A stale remote translation is already cached for the track.
        try cache.write(TranslationEntry(title: "A", artist: "Artist", titleEn: nil, lrclibId: 99, lines: [
            TranslationLine(timeMs: 1000, es: "viejo", en: "old"),
        ]), for: track("A"))
        // A local file supplies different, correct lyrics.
        fetcher.localOverrides["A"] = .synced(lines: [
            LyricLine(timeMs: 1000, text: "hola"), LyricLine(timeMs: 2000, text: "mundo"),
        ], lrclibId: nil, approximate: false)
        var s = on
        s.localLyricsFolder = "/music/lyrics"
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: s)
        await model.waitForIdle()
        XCTAssertEqual(model.status, .translated)
        XCTAssertEqual(model.display?.rows.map(\.original), ["hola", "mundo"])
        XCTAssertEqual(model.display?.rows.map(\.translation), ["EN:hola", "EN:mundo"])
        XCTAssertEqual(fetcher.calls.count, 0)   // the remote service was never used
        // The override is now cached, replacing the stale remote entry.
        XCTAssertEqual(cache.read(track("A"))?.lines.map(\.es), ["hola", "mundo"])
    }

    func testLocalFolderReusesCacheForSameSource() async throws {
        try cache.write(TranslationEntry(title: "A", artist: "Artist", titleEn: nil, lrclibId: nil, lines: [
            TranslationLine(timeMs: 1000, es: "hola", en: "hello"),
        ]), for: track("A"))
        fetcher.localOverrides["A"] = .synced(lines: [LyricLine(timeMs: 1000, text: "hola")],
                                              lrclibId: nil, approximate: false)
        var s = on
        s.localLyricsFolder = "/music/lyrics"
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: s)
        await model.waitForIdle()
        XCTAssertEqual(model.status, .translated)
        XCTAssertEqual(model.display?.rows.map(\.translation), ["hello"])
        XCTAssertEqual(providersBuilt, 0)   // unchanged source: no re-translation
        XCTAssertEqual(fetcher.calls.count, 0)
    }

    func testLocalFolderMissFallsBackToRemote() async throws {
        fetcher.results["A"] = synced(LyricSamples.english)
        var s = on
        s.localLyricsFolder = "/music/lyrics"   // no local file matches "A"
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: s)
        await model.waitForIdle()
        XCTAssertEqual(fetcher.calls.count, 1)
        XCTAssertEqual(model.status, .englishNoTranslation)
    }

    func testUnchangedSourceDoesNotRefetch() async throws {
        fetcher.results["A"] = synced(LyricSamples.english)
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(fetcher.calls.count, 1)
        model.update(playback: snap(track("A"), positionMs: 2_000, at: 2_000), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(fetcher.calls.count, 1)
    }

    // MARK: Review Focus 1: stale results

    func testStaleFetchResultIsDropped() async throws {
        let gate = TestGate()
        fetcher.gates["A"] = gate
        fetcher.results["A"] = synced(LyricSamples.english)
        fetcher.results["B"] = synced(LyricSamples.english.reversed())
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await waitUntil(self.fetcher.calls.count == 1)
        model.update(playback: snap(track("B")), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(model.display?.rows.first?.original, LyricSamples.english.last)

        await gate.release()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.display?.rows.first?.original, LyricSamples.english.last)
        XCTAssertEqual(model.status, .englishNoTranslation)
    }

    func testStaleTranslationIsDroppedAndNotShown() async throws {
        let gate = TestGate()
        fetcher.results["A"] = synced(LyricSamples.spanish)
        fetcher.results["B"] = synced(LyricSamples.english)
        provider = FakeTranslationProvider { lines, _ in
            await gate.wait()
            return lines.map { "EN:\($0)" }
        }
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await waitUntil(model.status == .translating)
        model.update(playback: snap(track("B")), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(model.status, .englishNoTranslation)

        await gate.release()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.display?.rows.map(\.original), LyricSamples.english)
        XCTAssertEqual(model.display?.rows.allSatisfy { $0.translation == nil }, true)
        XCTAssertEqual(model.status, .englishNoTranslation)
        // The abandoned translation must not be cached under either track.
        XCTAssertNil(cache.read(track("A")))
        // B is English: cached as lyrics only, with no translation text.
        XCTAssertEqual(cache.read(track("B"))?.lines.allSatisfy { $0.en.isEmpty }, true)
    }

    // MARK: Review Focus 2: tracks with no usable identity

    func testUnlookupableTrackMakesNoFetch() async {
        let model = makeModel()
        model.update(playback: snap(track("A", artist: "  ")), settings: on)
        await model.waitForIdle()
        model.update(playback: snap(track("B", durationMs: 0)), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(fetcher.calls.count, 0)
        XCTAssertNil(model.display)
        XCTAssertEqual(model.status, .nothingPlaying)
    }

    // MARK: Review Focus 4: toggling mid-song

    func testEnablingMidSongLoadsCurrentTrack() async {
        fetcher.results["A"] = synced(LyricSamples.english)
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: off)
        await model.waitForIdle()
        XCTAssertEqual(fetcher.calls.count, 0)
        model.update(playback: snap(track("A")), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(fetcher.calls.count, 1)
        XCTAssertNotNil(model.display)
    }

    func testDisablingClearsDisplayAndDropsInFlight() async throws {
        let gate = TestGate()
        fetcher.gates["A"] = gate
        fetcher.results["A"] = synced(LyricSamples.english)
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await waitUntil(self.fetcher.calls.count == 1)
        model.update(playback: snap(track("A")), settings: off)
        XCTAssertNil(model.display)
        XCTAssertEqual(model.status, .off)
        await gate.release()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(model.display)
        XCTAssertEqual(model.status, .off)
    }

    // MARK: position

    private func cacheThreeLines(_ t: LyricsTrack) throws {
        try cache.write(TranslationEntry(title: t.title, artist: t.artist, titleEn: nil, lrclibId: nil, lines: [
            TranslationLine(timeMs: 1000, es: "a", en: "a"),
            TranslationLine(timeMs: 5000, es: "b", en: "b"),
            TranslationLine(timeMs: 9000, es: "c", en: "c"),
        ]), for: t)
    }

    func testActiveIndexFollowsPosition() async throws {
        try cacheThreeLines(track("A"))
        let model = makeModel()
        XCTAssertEqual(model.activeIndex(atMs: 0), -1)
        model.update(playback: snap(track("A"), positionMs: 0, playing: true, at: 10_000), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(model.activeIndex(atMs: 10_500), -1)
        XCTAssertEqual(model.activeIndex(atMs: 11_200), 0)
        XCTAssertEqual(model.activeIndex(atMs: 15_200), 1)
        XCTAssertEqual(model.activeIndex(atMs: 500_000), 2)
    }

    func testSeekReanchors() async throws {
        try cacheThreeLines(track("A"))
        let model = makeModel()
        model.update(playback: snap(track("A"), positionMs: 0, at: 0), settings: on)
        await model.waitForIdle()
        model.update(playback: snap(track("A"), positionMs: 9_500, at: 1_500), settings: on)
        XCTAssertEqual(model.activeIndex(atMs: 1_500), 2)
        model.update(playback: snap(track("A"), positionMs: 2_000, at: 3_000), settings: on)
        XCTAssertEqual(model.activeIndex(atMs: 3_000), 0)
        XCTAssertEqual(fetcher.calls.count, 0)
    }

    func testPauseAndResumeDoesNotRefetch() async throws {
        fetcher.results["A"] = synced(LyricSamples.english)
        let model = makeModel()
        model.update(playback: snap(track("A"), positionMs: 2_500, playing: true, at: 0), settings: on)
        await model.waitForIdle()
        model.update(playback: snap(track("A"), positionMs: 4_000, playing: false, at: 1_500), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(model.activeIndex(atMs: 1_500), 3)
        XCTAssertEqual(model.activeIndex(atMs: 60_000), 3)   // holds still while paused
        model.update(playback: snap(track("A"), positionMs: 4_000, playing: true, at: 60_000), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(model.activeIndex(atMs: 61_500), 4)
        XCTAssertEqual(fetcher.calls.count, 1)
        XCTAssertNotNil(model.display)
    }

    func testTrackChangeResetsPosition() async throws {
        try cacheThreeLines(track("A"))
        try cacheThreeLines(track("B"))
        let model = makeModel()
        model.update(playback: snap(track("A"), positionMs: 9_500, at: 0), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(model.activeIndex(atMs: 0), 2)
        // New track starting near where the old one was must not inherit its anchor.
        model.update(playback: snap(track("B"), positionMs: 500, at: 1_000), settings: on)
        await model.waitForIdle()
        XCTAssertEqual(model.activeIndex(atMs: 1_000), -1)
    }

    func testTimingOffsetShiftsActiveLine() async throws {
        try cacheThreeLines(track("A"))   // lines at 1000, 5000, 9000
        let model = makeModel()
        model.update(playback: snap(track("A"), positionMs: 0, playing: true, at: 10_000), settings: on)
        await model.waitForIdle()
        // Interpolated position at clock 14_000 is 4_000 -> line 0 active.
        XCTAssertEqual(model.activeIndex(atMs: 14_000), 0)
        // +2 s pulls the lyrics earlier: effective 6_000 -> line 1.
        var s = on
        s.timingOffsetMs = 2_000
        model.update(playback: snap(track("A"), positionMs: 0, playing: true, at: 10_000), settings: s)
        XCTAssertEqual(model.activeIndex(atMs: 14_000), 1)
        // -2 s holds them back: effective 2_000 -> still line 0.
        s.timingOffsetMs = -2_000
        model.update(playback: snap(track("A"), positionMs: 0, playing: true, at: 10_000), settings: s)
        XCTAssertEqual(model.activeIndex(atMs: 14_000), 0)
        // A large negative offset lands before the first line.
        s.timingOffsetMs = -10_000
        model.update(playback: snap(track("A"), positionMs: 0, playing: true, at: 10_000), settings: s)
        XCTAssertEqual(model.activeIndex(atMs: 14_000), -1)
    }

    func testPlaybackEndingClearsDisplay() async throws {
        try cacheThreeLines(track("A"))
        let model = makeModel()
        model.update(playback: snap(track("A")), settings: on)
        await model.waitForIdle()
        XCTAssertNotNil(model.display)
        model.update(playback: nil, settings: on)
        XCTAssertNil(model.display)
        XCTAssertEqual(model.status, .nothingPlaying)
        XCTAssertEqual(model.activeIndex(atMs: 5_000), -1)
    }

    func testStatusMessages() {
        XCTAssertEqual(LyricsStatus.off.message, "Lyrics off")
        XCTAssertEqual(LyricsStatus.nothingPlaying.message, "Nothing playing")
        XCTAssertEqual(LyricsStatus.loading.message, "Loading lyrics...")
        XCTAssertEqual(LyricsStatus.noSyncedLyrics.message, "No synced lyrics found")
        XCTAssertEqual(LyricsStatus.instrumental.message, "Instrumental")
        XCTAssertEqual(LyricsStatus.lyricsError.message, "Lyrics service error")
        XCTAssertEqual(LyricsStatus.englishNoTranslation.message, "Synced lyrics (English, no translation)")
        XCTAssertEqual(LyricsStatus.translating.message, "Translating...")
        XCTAssertEqual(LyricsStatus.translated.message, "Synced lyrics, translated")
        XCTAssertEqual(LyricsStatus.noKey.message, "No Gemini key set")
        XCTAssertEqual(LyricsStatus.translationFailed("boom").message, "Translation failed: boom")
    }
}
