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

final class LocalLyricsMatcherTests: XCTestCase {
    private func match(_ files: [String], title: String, artist: String) -> String? {
        LocalLyricsMatcher.match(filenames: files, title: title, artist: artist)
    }

    func testMatchesArtistDashTitle() {
        let files = ["Gilberto Santa Rosa - Conteo Regresivo.lrc", "other song.lrc"]
        XCTAssertEqual(match(files, title: "Conteo Regresivo", artist: "Gilberto Santa Rosa"),
                       "Gilberto Santa Rosa - Conteo Regresivo.lrc")
    }

    func testMatchesTitleOnly() {
        XCTAssertEqual(match(["Conteo Regresivo.lrc"], title: "Conteo Regresivo", artist: "Whoever"),
                       "Conteo Regresivo.lrc")
    }

    func testMatchesTitleDashArtistOrder() {
        let files = ["Conteo Regresivo - Gilberto Santa Rosa.lrc"]
        XCTAssertEqual(match(files, title: "Conteo Regresivo", artist: "Gilberto Santa Rosa"),
                       "Conteo Regresivo - Gilberto Santa Rosa.lrc")
    }

    func testIgnoresDiacriticsPunctuationAndCase() {
        XCTAssertEqual(match(["que-culpa-tengo.lrc"], title: "¿Qué Culpa Tengo?", artist: "Little Joe"),
                       "que-culpa-tengo.lrc")
    }

    func testOnlyLrcExtensionIsConsidered() {
        XCTAssertNil(match(["Conteo Regresivo.txt"], title: "Conteo Regresivo", artist: "X"))
    }

    func testUppercaseExtensionAccepted() {
        XCTAssertEqual(match(["Conteo Regresivo.LRC"], title: "Conteo Regresivo", artist: "X"),
                       "Conteo Regresivo.LRC")
    }

    func testNoMatchReturnsNil() {
        XCTAssertNil(match(["something else.lrc"], title: "Conteo Regresivo", artist: "X"))
        XCTAssertNil(match([], title: "Conteo Regresivo", artist: "X"))
    }

    func testPrefersArtistTitleOverTitleOnly() {
        let files = ["Conteo Regresivo.lrc", "Gilberto Santa Rosa - Conteo Regresivo.lrc"]
        XCTAssertEqual(match(files, title: "Conteo Regresivo", artist: "Gilberto Santa Rosa"),
                       "Gilberto Santa Rosa - Conteo Regresivo.lrc")
    }

    func testEmptyTitleAndArtistMatchNothing() {
        XCTAssertNil(match(["anything.lrc"], title: "  ", artist: "  "))
    }
}
