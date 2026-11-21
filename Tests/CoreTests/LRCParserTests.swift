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

final class LRCParserTests: XCTestCase {
    private func L(_ t: Int, _ s: String) -> LyricLine { LyricLine(timeMs: t, text: s) }

    func testParsesBasicTimestampedLines() {
        XCTAssertEqual(LRCParser.parse("[00:12.34]Hola mundo\n[00:15.00]Adios"),
                       [L(12340, "Hola mundo"), L(15000, "Adios")])
    }

    func testMinutesGreaterThanNine() {
        let lines = LRCParser.parse("[10:04.95]Tarde\n[100:00.00]Muy tarde")
        XCTAssertEqual(lines[0].timeMs, 10 * 60000 + 4950)
        XCTAssertEqual(lines[1].timeMs, 100 * 60000)
    }

    func testThreeDigitAndOneDigitFractions() {
        XCTAssertEqual(LRCParser.parse("[00:01.5]a")[0].timeMs, 1500)
        XCTAssertEqual(LRCParser.parse("[00:01.500]a")[0].timeMs, 1500)
        XCTAssertEqual(LRCParser.parse("[00:01.050]a")[0].timeMs, 1050)
    }

    func testTimestampWithoutFraction() {
        XCTAssertEqual(LRCParser.parse("[01:30]a")[0].timeMs, 90000)
    }

    func testColonFractionSeparator() {
        XCTAssertEqual(LRCParser.parse("[00:01:50]a")[0].timeMs, 1500)
    }

    func testSkipsMalformedLinesAndMetadataTags() {
        let text = ["[ar:Artist]", "[ti:Title]", "not a lyric line",
                    "[99:99.99]bad seconds", "[00:10.00]good", "[0:xx]bad"].joined(separator: "\n")
        XCTAssertEqual(LRCParser.parse(text), [L(10000, "good")])
    }

    func testKeepsEmptyTextLines() {
        XCTAssertEqual(LRCParser.parse("[00:05.00]\n[00:10.00]texto"),
                       [L(5000, ""), L(10000, "texto")])
    }

    func testExpandsMultipleTimestampsAndSorts() {
        XCTAssertEqual(LRCParser.parse("[00:30.00][00:10.00]coro"),
                       [L(10000, "coro"), L(30000, "coro")])
    }

    func testToleratesLeadingWhitespaceAndCRLF() {
        XCTAssertEqual(LRCParser.parse("  [00:01.00]a\r\n[00:02.00]b"),
                       [L(1000, "a"), L(2000, "b")])
    }

    func testEmptyOrGarbageInput() {
        XCTAssertEqual(LRCParser.parse(""), [])
        XCTAssertEqual(LRCParser.parse("just some text\nmore text"), [])
    }

    func testTimestampInsideTextIsNotATimestamp() {
        XCTAssertEqual(LRCParser.parse("[00:01.00]a [00:09.00] b"), [L(1000, "a [00:09.00] b")])
    }

    // MARK: findActiveLine

    private var lines: [LyricLine] { [L(1000, "a"), L(5000, "b"), L(9000, "c")] }

    func testFindActiveLineBeforeFirst() {
        XCTAssertEqual(findActiveLine(lines, positionMs: 0), -1)
        XCTAssertEqual(findActiveLine(lines, positionMs: 999), -1)
    }

    func testFindActiveLineExactlyAtTimestamp() {
        XCTAssertEqual(findActiveLine(lines, positionMs: 1000), 0)
        XCTAssertEqual(findActiveLine(lines, positionMs: 5000), 1)
        XCTAssertEqual(findActiveLine(lines, positionMs: 9000), 2)
    }

    func testFindActiveLineBetweenTimestamps() {
        XCTAssertEqual(findActiveLine(lines, positionMs: 4999), 0)
        XCTAssertEqual(findActiveLine(lines, positionMs: 8999), 1)
    }

    func testFindActiveLinePastEnd() {
        XCTAssertEqual(findActiveLine(lines, positionMs: 100000), 2)
    }

    func testFindActiveLineEmptyLines() {
        XCTAssertEqual(findActiveLine([], positionMs: 5000), -1)
    }

    func testFindActiveLineSingleLine() {
        let single = [L(3000, "x")]
        XCTAssertEqual(findActiveLine(single, positionMs: 2999), -1)
        XCTAssertEqual(findActiveLine(single, positionMs: 3000), 0)
    }

    // MARK: LyricsTrack

    func testIsLookupable() {
        XCTAssertFalse(LyricsTrack(title: "  ", artist: "A", album: "B", durationMs: 1000).isLookupable)
        XCTAssertFalse(LyricsTrack(title: "T", artist: "", album: "B", durationMs: 1000).isLookupable)
        XCTAssertFalse(LyricsTrack(title: "T", artist: "A", album: "B", durationMs: 0).isLookupable)
        XCTAssertTrue(LyricsTrack(title: "T", artist: "A", album: "", durationMs: 1000).isLookupable)
    }
}
