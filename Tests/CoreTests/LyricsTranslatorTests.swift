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

final class LyricsTranslatorTests: XCTestCase {
    private let meta = TranslationMeta(title: "Song", artist: "Artist", titleFirst: false)
    private let sleeper = SleepRecorder()

    private func translate(_ p: TranslationProvider, _ lines: [String]) async throws -> (titleEn: String, en: [String]) {
        try await LyricsTranslator.translateWithTitle(provider: p, lines: lines, meta: meta, sleep: sleeper.sleep)
    }

    private func en(_ lines: [String]) -> [String] { lines.map { "EN:\($0)" } }

    // MARK: parseResponse

    func testParsesRawJSONArray() throws {
        XCTAssertEqual(try LyricsTranslator.parseResponse(#"["a","b"]"#, expected: 2), ["a", "b"])
    }

    func testParsesFencedJSONArray() throws {
        XCTAssertEqual(try LyricsTranslator.parseResponse("```json\n[\"a\",\"b\"]\n```", expected: 2), ["a", "b"])
        XCTAssertEqual(try LyricsTranslator.parseResponse("```\n[\"a\"]\n```", expected: 1), ["a"])
    }

    func testRejectsInvalidJSON() {
        XCTAssertThrowsError(try LyricsTranslator.parseResponse("not json", expected: 1))
    }

    func testRejectsWrongLength() {
        XCTAssertThrowsError(try LyricsTranslator.parseResponse(#"["a"]"#, expected: 2))
    }

    func testRejectsNonArraysAndNonStringMembers() {
        XCTAssertThrowsError(try LyricsTranslator.parseResponse(#"{"a":"b"}"#, expected: 1))
        XCTAssertThrowsError(try LyricsTranslator.parseResponse(#"["a",2]"#, expected: 2))
        XCTAssertThrowsError(try LyricsTranslator.parseResponse(#"["a",null]"#, expected: 2))
        XCTAssertThrowsError(try LyricsTranslator.parseResponse(#"["a",{"x":1}]"#, expected: 2))
    }

    func testKeepsEmptyStrings() throws {
        XCTAssertEqual(try LyricsTranslator.parseResponse(#"["a","","b"]"#, expected: 3), ["a", "", "b"])
    }

    // MARK: buildPrompt

    func testPromptCarriesContract() {
        let prompt = LyricsTranslator.buildPrompt(lines: ["hola", "adios"], meta: meta)
        XCTAssertTrue(prompt.hasPrefix(#"Translate these Spanish song lyrics to English. The song is "Song" by Artist."#))
        XCTAssertTrue(prompt.contains("There are exactly 2 lines. Output exactly 2 lines in the same order."))
        XCTAssertTrue(prompt.contains("Output ONLY a JSON array of strings, one per input line. No other text."))
        XCTAssertTrue(prompt.hasSuffix("Lyrics (JSON array):\n[\"hola\",\"adios\"]"))
        XCTAssertFalse(prompt.contains("FIRST line"))
    }

    func testPromptTitleFirstNoteOnlyWhenSet() {
        let titled = TranslationMeta(title: "Song", artist: "Artist", titleFirst: true)
        XCTAssertTrue(LyricsTranslator.buildPrompt(lines: ["Song", "hola"], meta: titled)
            .contains("The FIRST line of the input is the song title, not a lyric. Translate it as a title."))
    }

    // MARK: translateWithTitle

    func testPrependsTitleAndSplitsItOff() async throws {
        let p = FakeTranslationProvider { lines, _ in lines.map { "EN:\($0)" } }
        let out = try await translate(p, ["hola", "adios"])
        XCTAssertEqual(p.calls, [["Song", "hola", "adios"]])
        XCTAssertEqual(out.titleEn, "EN:Song")
        XCTAssertEqual(out.en, ["EN:hola", "EN:adios"])
        XCTAssertTrue(p.prompts[0].contains("FIRST line"))
    }

    func testRetriesOnceOnCountMismatchThenSucceeds() async throws {
        let p = FakeTranslationProvider { lines, call in call == 1 ? ["only one"] : lines.map { "EN:\($0)" } }
        let out = try await translate(p, ["hola", "adios"])
        XCTAssertEqual(out.en, ["EN:hola", "EN:adios"])
        XCTAssertEqual(p.calls.count, 2)
    }

    func testResponseDroppingTitleFallsBackToChunk() async throws {
        let p = FakeTranslationProvider { lines, call in
            call <= 2 ? Array(lines.dropFirst()).map { "EN:\($0)" } : lines.map { "EN:\($0)" }
        }
        let out = try await translate(p, ["hola", "adios"])
        XCTAssertEqual(out.titleEn, "EN:Song")
        XCTAssertEqual(p.calls.count, 3)
    }

    func testFallsBackToChunksOfTwentyWithTitleInFirstChunk() async throws {
        let lines = numberedLines(25)
        let p = FakeTranslationProvider { batch, _ in batch.count > 20 ? ["wrong count"] : batch.map { "EN:\($0)" } }
        let out = try await translate(p, lines)
        XCTAssertEqual(p.calls.dropFirst(2).map(\.count), [20, 6])
        XCTAssertEqual(p.calls[2][0], "Song")
        XCTAssertEqual(p.calls[3][0], "linea 20")
        XCTAssertEqual(out.titleEn, "EN:Song")
        XCTAssertEqual(out.en, en(lines))
        // Only the first chunk's prompt carries the title-first note.
        XCTAssertTrue(p.prompts[2].contains("FIRST line"))
        XCTAssertFalse(p.prompts[3].contains("FIRST line"))
    }

    func testLargeSongChunksEvenly() async throws {
        let lines = numberedLines(59)   // 60 with the title
        let p = FakeTranslationProvider { batch, _ in batch.count > 20 ? ["wrong count"] : batch.map { "EN:\($0)" } }
        let out = try await translate(p, lines)
        XCTAssertEqual(out.en, en(lines))
        XCTAssertEqual(p.calls.count, 5)
        XCTAssertEqual(p.calls.dropFirst(2).map(\.count), [20, 20, 20])
    }

    func testBatchThrowingFallsBackToChunks() async throws {
        let lines = numberedLines(44)   // 45 with the title
        let p = FakeTranslationProvider { batch, _ in
            if batch.count > 20 { throw TranslationProviderError.other("batch fails") }
            return batch.map { "EN:\($0)" }
        }
        let out = try await translate(p, lines)
        XCTAssertEqual(out.en, en(lines))
        XCTAssertEqual(p.calls.dropFirst(2).map(\.count), [20, 20, 5])
    }

    func testChunkWithBadCountFailsWholeTranslation() async {
        let lines = numberedLines(39)
        let p = FakeTranslationProvider { batch, _ in
            if batch.count > 20 { return ["wrong count"] }
            if batch[0] == "linea 20" { return ["short"] }
            return batch.map { "EN:\($0)" }
        }
        do {
            _ = try await translate(p, lines)
            XCTFail("expected failure")
        } catch let e as TranslationFailed {
            XCTAssertEqual(e.message, "Translation failed for lines 21 to 40")
        } catch { XCTFail("wrong error \(error)") }
    }

    func testChunkThrowingFailsWholeTranslation() async {
        let lines = numberedLines(39)
        let p = FakeTranslationProvider { batch, _ in
            if batch.count > 20 || batch[0] == "linea 20" { throw TranslationProviderError.other("down") }
            return batch.map { "EN:\($0)" }
        }
        do {
            _ = try await translate(p, lines)
            XCTFail("expected failure")
        } catch is TranslationFailed {
        } catch { XCTFail("wrong error \(error)") }
    }

    func testWaitsSuggestedDelayOn429ThenSucceeds() async throws {
        let p = FakeTranslationProvider { lines, call in
            if call == 1 { throw TranslationProviderError.rateLimited(retryAfterMs: 7000) }
            return lines.map { "EN:\($0)" }
        }
        let out = try await translate(p, ["hola", "adios"])
        XCTAssertEqual(out.en, ["EN:hola", "EN:adios"])
        XCTAssertEqual(p.calls.count, 2)
        XCTAssertEqual(sleeper.delays, [7000])
    }

    func testDefaultDelaysWhenNoneSuggested() async {
        let p = FakeTranslationProvider { _, _ in throw TranslationProviderError.rateLimited(retryAfterMs: nil) }
        do {
            _ = try await translate(p, ["hola", "adios"])
            XCTFail("expected failure")
        } catch let e as TranslationFailed {
            XCTAssertEqual(e.message, "Translation provider rate limit not cleared after retries")
        } catch { XCTFail("wrong error \(error)") }
        // Initial attempt + 2 retries, then a hard stop: no fallback requests.
        XCTAssertEqual(p.calls.count, 3)
        XCTAssertEqual(sleeper.delays, [15000, 30000])
    }

    func testSuggestedDelayIsCapped() async throws {
        let p = FakeTranslationProvider { lines, call in
            if call == 1 { throw TranslationProviderError.rateLimited(retryAfterMs: 600_000) }
            return lines.map { "EN:\($0)" }
        }
        _ = try await translate(p, ["hola"])
        XCTAssertEqual(sleeper.delays, [60000])
    }

    func testModelUnavailableFailsImmediately() async {
        let p = FakeTranslationProvider { _, _ in throw TranslationProviderError.modelUnavailable(model: "retired-model") }
        do {
            _ = try await translate(p, ["hola"])
            XCTFail("expected failure")
        } catch let e as TranslationFailed {
            XCTAssertTrue(e.message.contains("retired-model"))
            XCTAssertTrue(e.message.contains("gemini-flash-lite-latest"))
        } catch { XCTFail("wrong error \(error)") }
        XCTAssertEqual(p.calls.count, 1)
    }

    func testRejectedRequestFailsImmediatelyWithKeyHint() async {
        let p = FakeTranslationProvider { _, _ in throw TranslationProviderError.rejected(statusCode: 403) }
        do {
            _ = try await translate(p, numberedLines(30))
            XCTFail("expected failure")
        } catch let e as TranslationFailed {
            XCTAssertEqual(e.message, "Gemini rejected the request (HTTP 403). Check the API key and model.")
        } catch { XCTFail("wrong error \(error)") }
        XCTAssertEqual(p.calls.count, 1)
    }

    func testNetworkFailureFailsImmediately() async {
        let p = FakeTranslationProvider { _, _ in throw TranslationProviderError.network }
        do {
            _ = try await translate(p, numberedLines(30))
            XCTFail("expected failure")
        } catch let e as TranslationFailed {
            XCTAssertEqual(e.message, "Could not reach Gemini. Check the network connection.")
        } catch { XCTFail("wrong error \(error)") }
        XCTAssertEqual(p.calls.count, 1)
    }

    func testEmptyLinesMakesNoProviderCall() async throws {
        let p = FakeTranslationProvider { lines, _ in lines }
        let out = try await translate(p, [])
        XCTAssertEqual(out.titleEn, "")
        XCTAssertEqual(out.en, [])
        XCTAssertEqual(p.calls.count, 0)
    }

    func testTranslatedOutputNeverEqualsInputOnFailure() async {
        let p = FakeTranslationProvider { _, _ in ["wrong", "count", "always", "x", "y"] }
        do {
            _ = try await translate(p, ["hola", "adios"])
            XCTFail("expected failure")
        } catch is TranslationFailed {
        } catch { XCTFail("wrong error \(error)") }
    }
}
