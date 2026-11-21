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

final class LyricsTextDecoderTests: XCTestCase {
    func testDecodesUtf8() {
        XCTAssertEqual(LyricsTextDecoder.decode(Data("café".utf8)), "café")
    }

    func testDecodesLatin1WhenNotUtf8() {
        // 0xE9 alone is invalid UTF-8 but is 'é' in Latin-1 / CP1252.
        XCTAssertEqual(LyricsTextDecoder.decode(Data([0x63, 0x61, 0x66, 0xE9])), "café")
    }

    func testDecodesWindows1252Punctuation() {
        // 0x92 is a right single quote in CP1252; invalid as lone UTF-8.
        XCTAssertEqual(LyricsTextDecoder.decode(Data([0x49, 0x92, 0x6D])), "I\u{2019}m")
    }

    func testEmptyDataDecodesToEmptyString() {
        XCTAssertEqual(LyricsTextDecoder.decode(Data()), "")
    }
}
