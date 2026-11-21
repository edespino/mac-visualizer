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

final class TrackInfoTests: XCTestCase {
    func testIsEmptyWhenAllNilOrBlank() {
        XCTAssertTrue(TrackInfo(title: nil, artist: nil, album: nil).isEmpty)
        XCTAssertTrue(TrackInfo(title: "", artist: "", album: "").isEmpty)
    }

    func testNotEmptyWhenTitlePresent() {
        XCTAssertFalse(TrackInfo(title: "Song", artist: nil, album: nil).isEmpty)
    }

    func testEquatable() {
        XCTAssertEqual(TrackInfo(title: "A", artist: "B", album: "C"),
                       TrackInfo(title: "A", artist: "B", album: "C"))
        XCTAssertNotEqual(TrackInfo(title: "A", artist: "B", album: "C"),
                          TrackInfo(title: "A", artist: "B", album: "D"))
    }
}