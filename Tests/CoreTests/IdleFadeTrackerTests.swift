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

final class IdleFadeTrackerTests: XCTestCase {
    func testNoCaptureWithinHoldStaysActive() {
        var clock = IdleFadeTracker(now: 0)
        XCTAssertTrue(clock.isActive(now: 1, sample: .noCapture))
    }

    func testNoCapturePastHoldIsInactive() {
        var clock = IdleFadeTracker(now: 0)
        XCTAssertFalse(clock.isActive(now: IdleFadeTracker.holdSeconds + 0.1, sample: .noCapture))
    }

    func testQuietCapturePastHoldIsInactive() {
        var clock = IdleFadeTracker(now: 0)
        let quiet = IdleFadeTracker.levelEpsilon / 2
        XCTAssertFalse(clock.isActive(now: IdleFadeTracker.holdSeconds + 0.1, sample: .level(quiet)))
    }

    func testAudibleCaptureResetsTheHold() {
        var clock = IdleFadeTracker(now: 0)
        XCTAssertTrue(clock.isActive(now: 1.5, sample: .level(0.2)))
        XCTAssertTrue(clock.isActive(now: 1.5 + IdleFadeTracker.holdSeconds - 0.1, sample: .noCapture))
    }

    func testAudibleCaptureAfterIdleBecomesActiveImmediately() {
        var clock = IdleFadeTracker(now: 0)
        XCTAssertFalse(clock.isActive(now: 5, sample: .noCapture))
        XCTAssertTrue(clock.isActive(now: 5, sample: .level(0.05)))
    }

    func testDemoStaysActiveWithNoCapture() {
        var clock = IdleFadeTracker(now: 0)
        XCTAssertTrue(clock.isActive(now: 30, sample: .demo))
    }
}
