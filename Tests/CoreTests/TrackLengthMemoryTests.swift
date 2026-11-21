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

/// Spotify reports a shortened `duration` while it crossfades a song into the
/// next one. Measured on "Audition (The Fools Who Dream)" (true length 228.267 s,
/// published as 228 s): 216.267 s with a 12 s crossfade, 205.185 s in a playlist.
final class TrackLengthMemoryTests: XCTestCase {
    private let id = "6j0wBBAP3hMe4t1Ymj7GIe"

    func testUnknownTrackResolvesToReportedLength() {
        var m = TrackLengthMemory()
        XCTAssertEqual(m.resolve(id: id, reportedMs: 216_267), 216_267)
    }

    func testLongestReportedLengthWins() {
        var m = TrackLengthMemory()
        XCTAssertEqual(m.resolve(id: id, reportedMs: 228_267), 228_267)
        // The same play, once the crossfade into the next song is queued.
        XCTAssertEqual(m.resolve(id: id, reportedMs: 216_267), 228_267)
        XCTAssertEqual(m.resolve(id: id, reportedMs: 205_185), 228_267)
    }

    func testPublishedLengthCorrectsATrimmedReport() {
        var m = TrackLengthMemory()
        _ = m.resolve(id: id, reportedMs: 205_185)
        m.setPublished(id: id, seconds: 228)
        XCTAssertEqual(m.resolve(id: id, reportedMs: 205_185), 228_000)
    }

    func testPublishedLengthDoesNotReplaceAMorePreciseFullReport() {
        // Published lengths are whole seconds; a full-length report is exact.
        var m = TrackLengthMemory()
        m.setPublished(id: id, seconds: 228)
        XCTAssertEqual(m.resolve(id: id, reportedMs: 228_267), 228_267)
        var n = TrackLengthMemory()
        n.setPublished(id: id, seconds: 229)   // rounded up
        XCTAssertEqual(n.resolve(id: id, reportedMs: 228_267), 228_267)
    }

    func testTracksAreIndependentAndPublishedIsQueryable() {
        var m = TrackLengthMemory()
        m.setPublished(id: id, seconds: 228)
        XCTAssertTrue(m.hasPublished(id: id))
        XCTAssertFalse(m.hasPublished(id: "other"))
        XCTAssertEqual(m.resolve(id: "other", reportedMs: 100_000), 100_000)
    }

    func testNonsensePublishedLengthIsIgnored() {
        var m = TrackLengthMemory()
        m.setPublished(id: id, seconds: 0)
        XCTAssertFalse(m.hasPublished(id: id))
        XCTAssertEqual(m.resolve(id: id, reportedMs: 205_185), 205_185)
    }

    // MARK: Spotify track page

    func testTrackIDFromURI() {
        XCTAssertEqual(SpotifyTrackPage.trackID(fromURI: "spotify:track:6j0wBBAP3hMe4t1Ymj7GIe"), id)
        XCTAssertNil(SpotifyTrackPage.trackID(fromURI: "spotify:episode:6j0wBBAP3hMe4t1Ymj7GIe"))
        XCTAssertNil(SpotifyTrackPage.trackID(fromURI: "spotify:local:Artist:Album:Title:228"))
        XCTAssertNil(SpotifyTrackPage.trackID(fromURI: "spotify:track:../../etc?x=1"))
        XCTAssertNil(SpotifyTrackPage.trackID(fromURI: ""))
    }

    func testDurationParsedFromPageMarkup() {
        let html = #"<meta property="og:title" content="X"/><meta name="music:duration" content="228"/><meta name="music:album:track" content="12"/>"#
        XCTAssertEqual(SpotifyTrackPage.durationSeconds(inHTML: html), 228)
    }

    func testDurationMissingOrMalformedIsNil() {
        XCTAssertNil(SpotifyTrackPage.durationSeconds(inHTML: "<html></html>"))
        XCTAssertNil(SpotifyTrackPage.durationSeconds(inHTML: #"<meta name="music:duration" content="abc"/>"#))
        XCTAssertNil(SpotifyTrackPage.durationSeconds(inHTML: #"<meta name="music:duration" content="0"/>"#))
    }
}
