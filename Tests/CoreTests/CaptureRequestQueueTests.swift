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

final class CaptureRequestQueueTests: XCTestCase {
    func testFirstStartSchedulesAndRunsOnce() {
        var q = CaptureRequestQueue()
        XCTAssertEqual(q.requestStart(reason: "launch"), .schedule)
        XCTAssertEqual(q.next(), .start(reason: "launch"))
        XCTAssertNil(q.next())
    }

    func testRequestsWhileRunningCoalesceIntoOneFollowUpWithLatestReason() {
        var q = CaptureRequestQueue()
        XCTAssertEqual(q.requestStart(reason: "launch"), .schedule)
        XCTAssertEqual(q.next(), .start(reason: "launch"))      // now running
        XCTAssertEqual(q.requestStart(reason: "a"), .coalesced(replaced: nil))
        XCTAssertEqual(q.requestStart(reason: "b"), .coalesced(replaced: .start(reason: "a")))
        XCTAssertEqual(q.requestStart(reason: "c"), .coalesced(replaced: .start(reason: "b")))
        XCTAssertEqual(q.next(), .start(reason: "c"))
        XCTAssertNil(q.next())
    }

    func testRequestBeforeFirstRunBeginsReplacesQueuedReason() {
        var q = CaptureRequestQueue()
        XCTAssertEqual(q.requestStart(reason: "a"), .schedule)
        XCTAssertEqual(q.requestStart(reason: "b"), .coalesced(replaced: .start(reason: "a")))
        XCTAssertEqual(q.next(), .start(reason: "b"))
        XCTAssertNil(q.next())
    }

    func testStopWinsOverPendingStart() {
        var q = CaptureRequestQueue()
        XCTAssertEqual(q.requestStart(reason: "launch"), .schedule)
        XCTAssertEqual(q.next(), .start(reason: "launch"))
        XCTAssertEqual(q.requestStart(reason: "stall"), .coalesced(replaced: nil))
        XCTAssertEqual(q.requestStop(), .coalesced(replaced: .start(reason: "stall")))
        XCTAssertEqual(q.next(), .stop)
        XCTAssertNil(q.next())
    }

    func testStopBeforeQueuedStartBeginsSkipsIt() {
        var q = CaptureRequestQueue()
        XCTAssertEqual(q.requestStart(reason: "a"), .schedule)
        XCTAssertEqual(q.requestStop(), .coalesced(replaced: .start(reason: "a")))
        XCTAssertEqual(q.next(), .stop)
        XCTAssertNil(q.next())
    }

    func testStartAfterStopRunsAgain() {
        var q = CaptureRequestQueue()
        XCTAssertEqual(q.requestStop(), .schedule)
        XCTAssertEqual(q.next(), .stop)
        XCTAssertNil(q.next())
        XCTAssertEqual(q.requestStart(reason: "again"), .schedule)
        XCTAssertEqual(q.next(), .start(reason: "again"))
    }

    func testStartAfterPendingStopSupersedesStop() {
        var q = CaptureRequestQueue()
        XCTAssertEqual(q.requestStart(reason: "launch"), .schedule)
        XCTAssertEqual(q.next(), .start(reason: "launch"))
        XCTAssertEqual(q.requestStop(), .coalesced(replaced: nil))
        XCTAssertEqual(q.requestStart(reason: "later"), .coalesced(replaced: .stop))
        XCTAssertEqual(q.next(), .start(reason: "later"))
    }

    func testIdleAfterDrainSchedulesAgain() {
        var q = CaptureRequestQueue()
        _ = q.requestStart(reason: "a")
        _ = q.next()
        XCTAssertNil(q.next())
        XCTAssertFalse(q.isBusy)
        XCTAssertEqual(q.requestStart(reason: "b"), .schedule)
        XCTAssertTrue(q.isBusy)
    }
}
