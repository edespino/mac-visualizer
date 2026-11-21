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

final class MarkdownBlocksTests: XCTestCase {
    private func parse(_ s: String) -> [MarkdownBlock] { MarkdownParser.parse(s) }

    // MARK: blocks

    func testHeadingLevelsAreClampedToThree() {
        XCTAssertEqual(parse("# One\n\n## Two\n\n### Three\n\n#### Four"), [
            .heading(level: 1, text: "One"), .heading(level: 2, text: "Two"),
            .heading(level: 3, text: "Three"), .heading(level: 3, text: "Four")])
    }

    func testHeadingKeepsInlineMarkupForTheRenderer() {
        XCTAssertEqual(parse("### `BeatDetector` (Sources/Core/BeatDetector.swift)"),
                       [.heading(level: 3, text: "`BeatDetector` (Sources/Core/BeatDetector.swift)")])
    }

    func testHardWrappedParagraphLinesAreJoinedWithSpaces() {
        let text = "mac-visualizer is original work, but several of its algorithms and visual\nconcepts were inspired by other open-source projects, listed below."
        XCTAssertEqual(parse(text), [.paragraph(
            "mac-visualizer is original work, but several of its algorithms and visual concepts were inspired by other open-source projects, listed below.")])
    }

    func testShortLineGroupKeepsItsLineBreaks() {
        XCTAssertEqual(parse("mac-visualizer\nCopyright 2026 Ed Espino"),
                       [.paragraph("mac-visualizer\nCopyright 2026 Ed Espino")])
    }

    func testBlankLineSeparatesParagraphs() {
        XCTAssertEqual(parse("First paragraph line that is long enough to count as prose, yes.\n\nSecond one."),
                       [.paragraph("First paragraph line that is long enough to count as prose, yes."), .paragraph("Second one.")])
    }

    func testRuleVariants() {
        XCTAssertEqual(parse("---\n\n***\n\n___"), [.rule, .rule, .rule])
    }

    func testBulletsAndContinuationLines() {
        let text = "- Original author: Someone\n- Note: Ported to Metal; modified for this app. Changes were\n  made: GLSL translated.\n- Last"
        XCTAssertEqual(parse(text), [
            .bullet("Original author: Someone"),
            .bullet("Note: Ported to Metal; modified for this app. Changes were made: GLSL translated."),
            .bullet("Last")])
    }

    func testBulletEndsAtBlankLine() {
        XCTAssertEqual(parse("- item\n\nParagraph after the list that is a normal sentence of prose here."),
                       [.bullet("item"), .paragraph("Paragraph after the list that is a normal sentence of prose here.")])
    }

    func testIndentedBlockIsCodeWithIndentStrippedAndBlankLinesKept() {
        let text = "MIT License notice:\n\n    Copyright (c) X\n\n    Permission is hereby granted\n      nested line\n\nAfter."
        XCTAssertEqual(parse(text), [
            .paragraph("MIT License notice:"),
            .code("Copyright (c) X\n\nPermission is hereby granted\n  nested line"),
            .paragraph("After.")])
    }

    func testFencedBlockIsCodeVerbatim() {
        XCTAssertEqual(parse("Intro\n\n```swift\nlet a = 1\n\n    indented\n```\nOutro"), [
            .paragraph("Intro"), .code("let a = 1\n\n    indented"), .paragraph("Outro")])
    }

    func testIndentedLineAfterBulletIsContinuationNotCode() {
        XCTAssertEqual(parse("- first\n    still the first"), [.bullet("first still the first")])
    }

    func testCRLFAndEmptyInput() {
        XCTAssertEqual(parse(""), [])
        XCTAssertEqual(parse("# A\r\n\r\nText\r\n"), [.heading(level: 1, text: "A"), .paragraph("Text")])
    }

    func testPreformattedKeepsTextExactly() {
        let text = "                                 Apache License\n   1. Definitions.\n\n      \"License\" shall mean"
        XCTAssertEqual(MarkdownParser.preformatted(text + "\n"), [.code(text)])
    }

    // MARK: inline

    func testInlineBoldAndCodeAreInterpretedAndMarkersRemoved() {
        let a = MarkdownInline.attributed("a **bold** and `code` word")
        XCTAssertEqual(String(a.characters), "a bold and code word")
        var sawBold = false, sawCode = false
        for run in a.runs {
            if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true { sawBold = true }
            if run.inlinePresentationIntent?.contains(.code) == true { sawCode = true }
        }
        XCTAssertTrue(sawBold); XCTAssertTrue(sawCode)
    }

    func testInlineMarkdownLinkBecomesLink() {
        let a = MarkdownInline.attributed("see **[LRCLIB](https://lrclib.net)** now")
        XCTAssertEqual(String(a.characters), "see LRCLIB now")
        XCTAssertEqual(a.runs.compactMap { $0.link }.map(\.absoluteString), ["https://lrclib.net"])
    }

    func testBareURLIsLinkedButNotInsideCode() {
        let a = MarkdownInline.attributed("Source: https://github.com/AlexVestin/musicvid.org/blob/master/x.js and `https://open.spotify.com/track/<id>`")
        let links = a.runs.compactMap { $0.link }.map(\.absoluteString)
        XCTAssertEqual(links, ["https://github.com/AlexVestin/musicvid.org/blob/master/x.js"])
    }

    func testInlineInvalidMarkupFallsBackToPlainText() {
        XCTAssertEqual(String(MarkdownInline.attributed("plain text, no markup").characters), "plain text, no markup")
    }

    // MARK: real files

    private func repoFile(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent(name)
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { throw XCTSkip("\(name) not found") }
        return s
    }

    func testNoticeParsesIntoExpectedConstructs() throws {
        let blocks = parse(try repoFile("NOTICE"))
        XCTAssertTrue(blocks.contains(.heading(level: 1, text: "Notices and Credits")))
        XCTAssertTrue(blocks.contains(.heading(level: 3, text: "`BeatDetector` (Sources/Core/BeatDetector.swift)")))
        XCTAssertTrue(blocks.contains(.rule))
        XCTAssertTrue(blocks.contains { if case .code(let c) = $0 { return c.hasPrefix("Copyright (c) Tariq Soliman") && c.contains("\n\nPermission is hereby granted") }; return false })
        XCTAssertTrue(blocks.contains { if case .bullet(let b) = $0 { return b.contains("[LRCLIB](https://lrclib.net)") }; return false })
        assertWellFormed(blocks)
    }

    func testThirdPartyParsesIntoExpectedConstructs() throws {
        let blocks = parse(try repoFile("THIRD_PARTY_NOTICES.md"))
        XCTAssertTrue(blocks.contains(.heading(level: 1, text: "Third-Party Notices")))
        XCTAssertTrue(blocks.contains(.heading(level: 2, text: "Star Nest (volumetric fractal starfield shader)")))
        XCTAssertTrue(blocks.contains { if case .bullet(let b) = $0 { return b.hasPrefix("Original author: Matt DesLauriers") }; return false })
        XCTAssertTrue(blocks.contains { if case .code(let c) = $0 { return c.hasPrefix("Copyright (c) 2013 Pablo Roman Andrioli") }; return false })
        assertWellFormed(blocks)
    }

    func testLicenseIsOneExactBlock() throws {
        let raw = try repoFile("LICENSE")
        let blocks = MarkdownParser.preformatted(raw)
        XCTAssertEqual(blocks.count, 1)
        guard case .code(let c) = blocks[0] else { return XCTFail("expected code") }
        XCTAssertTrue(c.contains("Apache License"))
        XCTAssertEqual(c, raw.trimmingCharacters(in: .newlines))
    }

    /// The files must stay table-free and leave no markdown marker at the start of any block that the renderer would show raw.
    private func assertWellFormed(_ blocks: [MarkdownBlock], file: StaticString = #filePath, line: UInt = #line) {
        for b in blocks {
            switch b {
            case .paragraph(let t), .bullet(let t):
                XCTAssertFalse(t.hasPrefix("|"), "table row in prose: \(t)", file: file, line: line)
                XCTAssertFalse(t.hasPrefix("#"), "unparsed heading: \(t)", file: file, line: line)
            case .heading(_, let t):
                XCTAssertFalse(t.hasPrefix("#"), file: file, line: line)
            default: break
            }
        }
    }
}
