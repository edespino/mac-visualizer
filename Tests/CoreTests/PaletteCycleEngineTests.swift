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

private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(_ s: UInt64) { state = s }
    mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
}

final class PaletteCycleEngineTests: XCTestCase {
    let names = ["classic","phosphor","synthwave","inferno","aurora","ember","ice","mono",
                 "viridis","plasma","spectrum","pastel","forest","oceanic"]

    func testDisabledIsPassthrough() {
        let e = PaletteCycleEngine(); var rng = SeededRNG(1)
        let o = e.advance(dt: 100, enabled: false, interval: 60, fadeDuration: 1.5,
                          currentPaletteName: "classic", availableNames: names, rng: &rng)
        XCTAssertEqual(o, PaletteCycleOutput(currentName: "classic", nextName: nil, mix: 0, committedName: nil))
    }

    func testNoAdvanceBeforeInterval() {
        let e = PaletteCycleEngine(); var rng = SeededRNG(1)
        var o = e.advance(dt: 0, enabled: true, interval: 60, fadeDuration: 1.5,
                          currentPaletteName: "classic", availableNames: names, rng: &rng)
        for _ in 0..<59 { o = e.advance(dt: 1, enabled: true, interval: 60, fadeDuration: 1.5,
                          currentPaletteName: "classic", availableNames: names, rng: &rng) }
        XCTAssertNil(o.nextName); XCTAssertEqual(o.mix, 0, accuracy: 0)
    }

    func testFadeRampThenCommitOnce() {
        let e = PaletteCycleEngine(); var rng = SeededRNG(1)
        func step(_ dt: Double) -> PaletteCycleOutput {
            e.advance(dt: dt, enabled: true, interval: 10, fadeDuration: 2,
                      currentPaletteName: "classic", availableNames: names, rng: &rng)
        }
        _ = step(0)
        _ = step(10)                 // hit interval → fade begins
        let mid = step(1)            // 1s into a 2s fade
        XCTAssertNotNil(mid.nextName); XCTAssertEqual(mid.mix, 0.5, accuracy: 1e-6)
        XCTAssertNil(mid.committedName)
        let done = step(1)           // fade completes
        XCTAssertEqual(done.mix, 1, accuracy: 0)
        XCTAssertEqual(done.committedName, mid.nextName)
        let after = step(0.001)      // commit fires exactly once
        XCTAssertNil(after.committedName)
        XCTAssertNil(after.nextName)
    }

    func testDeckExhaustsAllBeforeRepeatNoSeam() {
        let e = PaletteCycleEngine(); var rng = SeededRNG(42)
        var committed: [String] = []
        var current = "classic"
        var t = 0.0
        // advance through 2 full decks worth of commits
        while committed.count < names.count * 2 {
            let o = e.advance(dt: 0.5, enabled: true, interval: 1, fadeDuration: 0.5,
                              currentPaletteName: current, availableNames: names, rng: &rng)
            t += 0.5
            if let c = o.committedName { committed.append(c); current = c }
        }
        let firstDeck = Set(committed.prefix(names.count - 1)) // current excluded from its own deck draw
        XCTAssertEqual(firstDeck.count, committed.prefix(names.count - 1).count, "no repeat within a deck")
        // no immediate repeat at any commit boundary
        for i in 1..<committed.count { XCTAssertNotEqual(committed[i], committed[i-1], "no seam repeat") }
    }

    func testManualChangeReanchors() {
        let e = PaletteCycleEngine(); var rng = SeededRNG(7)
        _ = e.advance(dt: 0, enabled: true, interval: 60, fadeDuration: 1.5,
                      currentPaletteName: "classic", availableNames: names, rng: &rng)
        for _ in 0..<50 { _ = e.advance(dt: 1, enabled: true, interval: 60, fadeDuration: 1.5,
                      currentPaletteName: "classic", availableNames: names, rng: &rng) }
        // user picks "ember" at t≈50s → countdown must restart, no immediate fade
        let o = e.advance(dt: 1, enabled: true, interval: 60, fadeDuration: 1.5,
                      currentPaletteName: "ember", availableNames: names, rng: &rng)
        XCTAssertEqual(o.currentName, "ember"); XCTAssertNil(o.nextName); XCTAssertEqual(o.mix, 0, accuracy: 0)
        // and it should NOT fire again at the old schedule (would need another full interval)
        var last = o
        for _ in 0..<58 { last = e.advance(dt: 1, enabled: true, interval: 60, fadeDuration: 1.5,
                      currentPaletteName: "ember", availableNames: names, rng: &rng) }
        XCTAssertNil(last.nextName, "must wait a full interval from the manual pick")
    }

    func testNaNInfSanitized() {
        let e = PaletteCycleEngine(); var rng = SeededRNG(1)
        let o = e.advance(dt: .nan, enabled: true, interval: .infinity, fadeDuration: .nan,
                          currentPaletteName: "classic", availableNames: names, rng: &rng)
        XCTAssertEqual(o.mix, 0, accuracy: 0)   // no crash, no poison
        XCTAssertNil(o.nextName)
    }

    // No self-fade for degenerate inputs: an empty name list, a single name that
    // equals the current palette, or all names equal to the current palette must
    // never start a fade toward the current palette — even when dt exceeds the
    // interval across many advances.
    func testNoSelfFadeWhenNoAlternative() {
        let degenerate: [[String]] = [[], ["classic"], ["classic", "classic"]]
        for available in degenerate {
            let e = PaletteCycleEngine(); var rng = SeededRNG(1)
            _ = e.advance(dt: 0, enabled: true, interval: 1, fadeDuration: 0.5,
                          currentPaletteName: "classic", availableNames: available, rng: &rng)
            for _ in 0..<10 {
                let o = e.advance(dt: 5, enabled: true, interval: 1, fadeDuration: 0.5,
                                  currentPaletteName: "classic", availableNames: available, rng: &rng)
                XCTAssertNil(o.nextName, "available=\(available): must not target a self-fade")
                XCTAssertEqual(o.mix, 0, accuracy: 0, "available=\(available)")
                XCTAssertNil(o.committedName, "available=\(available)")
                XCTAssertEqual(o.currentName, "classic", "available=\(available)")
            }
        }
    }

    // Frame-rate independence: when a single dt overshoots the interval, the
    // overshoot is carried into the fade so the fade does not restart at 0.
    func testIntervalOvershootCarriedIntoFade() {
        let e = PaletteCycleEngine(); var rng = SeededRNG(1)
        _ = e.advance(dt: 0, enabled: true, interval: 10, fadeDuration: 2,
                      currentPaletteName: "classic", availableNames: names, rng: &rng)
        // One 11s step: 10s reaches the interval, 1s overshoot lands in a 2s fade.
        let o = e.advance(dt: 11, enabled: true, interval: 10, fadeDuration: 2,
                          currentPaletteName: "classic", availableNames: names, rng: &rng)
        XCTAssertNotNil(o.nextName)
        XCTAssertEqual(o.mix, 0.5, accuracy: 1e-6)   // 1s of a 2s fade already elapsed
        XCTAssertNil(o.committedName)
    }
}
