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

final class CaptureStallMonitorTests: XCTestCase {
    // No rebuild before the stall threshold elapses with no samples.
    func testNoRebuildBeforeStallThreshold() {
        var m = CaptureStallMonitor(now: 0)
        XCTAssertFalse(m.shouldRebuild(now: CaptureStallMonitor.stallSeconds - 0.01, status: .running))
    }

    // A running capture that delivers no samples for the stall window rebuilds.
    func testRebuildAfterStallWhileRunning() {
        var m = CaptureStallMonitor(now: 0)
        XCTAssertTrue(m.shouldRebuild(now: CaptureStallMonitor.stallSeconds, status: .running))
    }

    // Never rebuild when capture is not running (a restart could not help, e.g.
    // no target process or a failed start — avoid a spin).
    func testNoRebuildWhenNotRunning() {
        var m = CaptureStallMonitor(now: 0)
        XCTAssertFalse(m.shouldRebuild(now: CaptureStallMonitor.stallSeconds + 10, status: .other))
    }

    // A fresh sample resets the stall clock, so no rebuild follows soon after.
    func testNoteSampleResetsStall() {
        var m = CaptureStallMonitor(now: 0)
        m.noteSample(now: CaptureStallMonitor.stallSeconds - 0.1)
        XCTAssertFalse(m.shouldRebuild(now: CaptureStallMonitor.stallSeconds + 0.1, status: .running))
    }

    // After a rebuild fires, the backoff suppresses an immediate re-fire so a
    // rebuild that has not yet produced samples does not storm every frame.
    func testBackoffSuppressesImmediateRefire() {
        var m = CaptureStallMonitor(now: 0)
        XCTAssertTrue(m.shouldRebuild(now: CaptureStallMonitor.stallSeconds, status: .running))
        XCTAssertFalse(m.shouldRebuild(now: CaptureStallMonitor.stallSeconds + 0.1, status: .running))
    }

    // Once the backoff elapses and the stall persists, a rebuild fires again.
    func testRefiresAfterBackoffWhenStillStalled() {
        var m = CaptureStallMonitor(now: 0)
        XCTAssertTrue(m.shouldRebuild(now: CaptureStallMonitor.stallSeconds, status: .running))
        let later = CaptureStallMonitor.stallSeconds + CaptureStallMonitor.rebuildBackoffSeconds
        XCTAssertTrue(m.shouldRebuild(now: later, status: .running))
    }

    // The initial construction grants a grace period: a just-started monitor
    // ticked immediately does not rebuild before the stall window.
    func testGracePeriodAtConstruction() {
        var m = CaptureStallMonitor(now: 100)
        XCTAssertFalse(m.shouldRebuild(now: 100, status: .running))
        XCTAssertFalse(m.shouldRebuild(now: 100 + CaptureStallMonitor.stallSeconds - 0.01, status: .running))
        XCTAssertTrue(m.shouldRebuild(now: 100 + CaptureStallMonitor.stallSeconds, status: .running))
    }

    // MARK: - Failed-state retry

    // A failed capture is retried only after the failed-retry interval.
    func testFailedRetriesAfterInterval() {
        var m = CaptureStallMonitor(now: 0)
        XCTAssertFalse(m.shouldRebuild(now: 100, status: .failed))   // first sighting starts the clock
        XCTAssertFalse(m.shouldRebuild(now: 100 + CaptureStallMonitor.failedRetrySeconds - 0.01, status: .failed))
        XCTAssertTrue(m.shouldRebuild(now: 100 + CaptureStallMonitor.failedRetrySeconds, status: .failed))
    }

    // A persistent failure keeps retrying, each retry spaced by the interval.
    func testFailedRetryRespectsBackoffRepeatedly() {
        var m = CaptureStallMonitor(now: 0)
        let r = CaptureStallMonitor.failedRetrySeconds
        _ = m.shouldRebuild(now: 10, status: .failed)
        XCTAssertTrue(m.shouldRebuild(now: 10 + r, status: .failed))
        XCTAssertFalse(m.shouldRebuild(now: 10 + r + 0.1, status: .failed))
        XCTAssertFalse(m.shouldRebuild(now: 10 + 2 * r - 0.01, status: .failed))
        XCTAssertTrue(m.shouldRebuild(now: 10 + 2 * r, status: .failed))
    }

    // Stopped / no-target states never rebuild, however long they last.
    func testOtherStatesNeverRebuild() {
        var m = CaptureStallMonitor(now: 0)
        for t in stride(from: 0.0, through: 100.0, by: 1.0) {
            XCTAssertFalse(m.shouldRebuild(now: t, status: .other))
        }
    }

    // Recovering from a failure resets the failed clock: a later failure waits
    // a full interval again.
    func testFailedClockResetsAfterRecovery() {
        var m = CaptureStallMonitor(now: 0)
        let r = CaptureStallMonitor.failedRetrySeconds
        _ = m.shouldRebuild(now: 10, status: .failed)
        XCTAssertTrue(m.shouldRebuild(now: 10 + r, status: .failed))
        m.noteSample(now: 20)
        XCTAssertFalse(m.shouldRebuild(now: 20, status: .running))
        XCTAssertFalse(m.shouldRebuild(now: 30, status: .failed))
        XCTAssertFalse(m.shouldRebuild(now: 30 + r - 0.01, status: .failed))
        XCTAssertTrue(m.shouldRebuild(now: 30 + r, status: .failed))
    }

    // MARK: - Finish-time clock

    // A rebuild that takes 10 s must not leave the stall/backoff clocks stale.
    func testRebuildFinishRestartsStallAndBackoffClocks() {
        var m = CaptureStallMonitor(now: 0)
        let stall = CaptureStallMonitor.stallSeconds
        let t = 5.0
        XCTAssertTrue(m.shouldRebuild(now: t, status: .running))
        m.noteRebuildFinished(now: t + 10)
        XCTAssertFalse(m.shouldRebuild(now: t + 10.01, status: .running))
        XCTAssertFalse(m.shouldRebuild(now: t + 10 + stall - 0.01, status: .running))
        // Stall elapsed (1.5 s) but the 3 s backoff, measured from the finish, has not.
        XCTAssertFalse(m.shouldRebuild(now: t + 10 + CaptureStallMonitor.rebuildBackoffSeconds - 0.01, status: .running))
        XCTAssertTrue(m.shouldRebuild(now: t + 10 + CaptureStallMonitor.rebuildBackoffSeconds, status: .running))
    }

    // A sample after the rebuild resets the stall clock as before.
    func testSampleAfterRebuildResetsStallClock() {
        var m = CaptureStallMonitor(now: 0)
        XCTAssertTrue(m.shouldRebuild(now: 2, status: .running))
        m.noteRebuildFinished(now: 12)
        m.noteSample(now: 14)
        XCTAssertFalse(m.shouldRebuild(now: 14 + CaptureStallMonitor.stallSeconds - 0.01, status: .running))
        XCTAssertTrue(m.shouldRebuild(now: 14 + CaptureStallMonitor.stallSeconds, status: .running))
    }

    // The failed-retry interval is measured from the finish time.
    func testFailedRetryMeasuredFromFinishTime() {
        var m = CaptureStallMonitor(now: 0)
        let r = CaptureStallMonitor.failedRetrySeconds
        _ = m.shouldRebuild(now: 10, status: .failed)
        XCTAssertTrue(m.shouldRebuild(now: 10 + r, status: .failed))
        m.noteRebuildFinished(now: 10 + r + 20)
        XCTAssertFalse(m.shouldRebuild(now: 10 + r + 20 + 0.01, status: .failed))
        XCTAssertFalse(m.shouldRebuild(now: 10 + r + 20 + r - 0.01, status: .failed))
        XCTAssertTrue(m.shouldRebuild(now: 10 + r + 20 + r, status: .failed))
    }

    // The launch start restarts the clock from its completion time.
    func testLaunchStartFinishGrantsGrace() {
        var m = CaptureStallMonitor(now: 0)
        m.noteRebuildFinished(now: 30)
        XCTAssertFalse(m.shouldRebuild(now: 30.01, status: .running))
        XCTAssertFalse(m.shouldRebuild(now: 30 + CaptureStallMonitor.stallSeconds, status: .running))   // backoff from finish
        XCTAssertTrue(m.shouldRebuild(now: 30 + CaptureStallMonitor.rebuildBackoffSeconds, status: .running))
    }

    // MARK: - Escalating backoff

    func testFruitlessRebuildsBackOffAndCap() {
        var m = CaptureStallMonitor(now: 0)
        var t = CaptureStallMonitor.stallSeconds
        XCTAssertTrue(m.shouldRebuild(now: t, status: .running))
        for expected in [3.0, 6, 12, 24, 48, 60, 60] {
            m.noteRebuildFinished(now: t)
            XCTAssertFalse(m.shouldRebuild(now: t + expected - 0.01, status: .running), "backoff \(expected)")
            t += expected
            XCTAssertTrue(m.shouldRebuild(now: t, status: .running), "backoff \(expected)")
        }
    }

    func testSampleResetsEscalation() {
        var m = CaptureStallMonitor(now: 0)
        var t = CaptureStallMonitor.stallSeconds
        for gap in [3.0, 6, 12] {
            XCTAssertTrue(m.shouldRebuild(now: t, status: .running))
            m.noteRebuildFinished(now: t)
            t += gap
        }
        XCTAssertTrue(m.shouldRebuild(now: t, status: .running))
        m.noteRebuildFinished(now: t)
        m.noteSample(now: t + 3)
        let t2 = t + 3 + CaptureStallMonitor.stallSeconds
        XCTAssertTrue(m.shouldRebuild(now: t2, status: .running))
        m.noteRebuildFinished(now: t2)
        XCTAssertFalse(m.shouldRebuild(now: t2 + 2.99, status: .running))
        XCTAssertTrue(m.shouldRebuild(now: t2 + 3, status: .running))
    }

    func testFailedRetryUnaffectedByEscalation() {
        var m = CaptureStallMonitor(now: 0)
        var t = CaptureStallMonitor.stallSeconds
        for gap in [3.0, 6, 12] {
            XCTAssertTrue(m.shouldRebuild(now: t, status: .running))
            m.noteRebuildFinished(now: t)
            t += gap
        }
        let r = CaptureStallMonitor.failedRetrySeconds
        XCTAssertFalse(m.shouldRebuild(now: t, status: .failed))
        XCTAssertTrue(m.shouldRebuild(now: t + r, status: .failed))
    }

    // MARK: - Playback gate

    func testNoStallRebuildWhilePlayerNotPlaying() {
        var m = CaptureStallMonitor(now: 0)
        for t in stride(from: 0.0, through: 600.0, by: 0.5) {
            XCTAssertFalse(m.shouldRebuild(now: t, status: .running, playerPlaying: false))
        }
    }

    func testGateFlipToPlayingStartsStallClockAtFlip() {
        var m = CaptureStallMonitor(now: 0)
        XCTAssertFalse(m.shouldRebuild(now: 100, status: .running, playerPlaying: false))
        XCTAssertFalse(m.shouldRebuild(now: 200, status: .running, playerPlaying: true))
        XCTAssertFalse(m.shouldRebuild(now: 200 + CaptureStallMonitor.stallSeconds - 0.01, status: .running, playerPlaying: true))
        XCTAssertTrue(m.shouldRebuild(now: 200 + CaptureStallMonitor.stallSeconds, status: .running, playerPlaying: true))
    }

    func testGateDoesNotAdvanceFruitlessCount() {
        var m = CaptureStallMonitor(now: 0)
        XCTAssertTrue(m.shouldRebuild(now: 2, status: .running))
        m.noteRebuildFinished(now: 2)
        XCTAssertFalse(m.shouldRebuild(now: 50, status: .running, playerPlaying: false))
        XCTAssertFalse(m.shouldRebuild(now: 60, status: .running, playerPlaying: true))
        // fruitless stays 1 -> backoff 6 s from the earlier finish (long past); stall clock from flip.
        XCTAssertTrue(m.shouldRebuild(now: 60 + CaptureStallMonitor.stallSeconds, status: .running, playerPlaying: true))
        XCTAssertEqual(m.fruitlessCount, 2)
    }

    func testFailedRetryNotGated() {
        var m = CaptureStallMonitor(now: 0)
        let r = CaptureStallMonitor.failedRetrySeconds
        XCTAssertFalse(m.shouldRebuild(now: 10, status: .failed, playerPlaying: false))
        XCTAssertTrue(m.shouldRebuild(now: 10 + r, status: .failed, playerPlaying: false))
    }

    func testBackoffSecondsReportsCurrentValue() {
        var m = CaptureStallMonitor(now: 0)
        XCTAssertEqual(m.currentBackoffSeconds, 3)
        _ = m.shouldRebuild(now: 2, status: .running)
        XCTAssertEqual(m.fruitlessCount, 1)
        XCTAssertEqual(m.currentBackoffSeconds, 3)
        m.noteRebuildFinished(now: 2)
        _ = m.shouldRebuild(now: 5, status: .running)
        XCTAssertEqual(m.fruitlessCount, 2)
        XCTAssertEqual(m.currentBackoffSeconds, 6)
    }

    // MARK: - In-flight rebuild (lifecycle runs off main)

    // A rebuild in flight suppresses further stall rebuilds, however long it takes.
    func testNoRebuildWhileRebuildInFlight() {
        var m = CaptureStallMonitor(now: 0)
        XCTAssertTrue(m.shouldRebuild(now: 2, status: .running))
        m.noteRebuildStarted(now: 2)
        XCTAssertTrue(m.isRebuildInFlight)
        for t in stride(from: 3.0, through: 122.0, by: 1.0) {
            XCTAssertFalse(m.shouldRebuild(now: t, status: .running), "t=\(t)")
        }
    }

    // After the finish, the normal stall + backoff rules apply from the finish time.
    func testNormalPolicyResumesFromFinishTime() {
        var m = CaptureStallMonitor(now: 0)
        XCTAssertTrue(m.shouldRebuild(now: 2, status: .running))
        m.noteRebuildStarted(now: 2)
        m.noteRebuildFinished(now: 92)
        XCTAssertFalse(m.isRebuildInFlight)
        XCTAssertFalse(m.shouldRebuild(now: 92 + CaptureStallMonitor.stallSeconds - 0.01, status: .running))
        // fruitless = 1 -> backoff 3 s, which is longer than the stall window here.
        XCTAssertFalse(m.shouldRebuild(now: 92 + CaptureStallMonitor.stallSeconds, status: .running))
        XCTAssertTrue(m.shouldRebuild(now: 92 + CaptureStallMonitor.rebuildBackoffSeconds, status: .running))
    }

    // Failed-state retry is suppressed while a rebuild is in flight too.
    func testFailedRetrySuppressedWhileInFlight() {
        var m = CaptureStallMonitor(now: 0)
        XCTAssertFalse(m.shouldRebuild(now: 1, status: .failed))   // starts the failed clock
        m.noteRebuildStarted(now: 1)
        XCTAssertFalse(m.shouldRebuild(now: 100, status: .failed))
        m.noteRebuildFinished(now: 100)
        XCTAssertFalse(m.shouldRebuild(now: 100 + CaptureStallMonitor.failedRetrySeconds - 0.01, status: .failed))
        XCTAssertTrue(m.shouldRebuild(now: 100 + CaptureStallMonitor.failedRetrySeconds, status: .failed))
    }

    // A second start without a finish does not need a second finish.
    func testSecondStartedWithoutFinishIsHarmless() {
        var m = CaptureStallMonitor(now: 0)
        m.noteRebuildStarted(now: 1)
        m.noteRebuildStarted(now: 2)
        XCTAssertTrue(m.isRebuildInFlight)
        m.noteRebuildFinished(now: 10)
        XCTAssertFalse(m.isRebuildInFlight)
        XCTAssertTrue(m.shouldRebuild(now: 10 + CaptureStallMonitor.rebuildBackoffSeconds, status: .running))
    }

    // The launch start is in flight from init until it finishes.
    func testLaunchStartInFlightUntilFinished() {
        var m = CaptureStallMonitor(now: 0)
        m.noteRebuildStarted(now: 0)
        XCTAssertFalse(m.shouldRebuild(now: 200, status: .running))
        XCTAssertFalse(m.shouldRebuild(now: 200, status: .failed))
        m.noteRebuildFinished(now: 200)
        XCTAssertFalse(m.shouldRebuild(now: 200 + CaptureStallMonitor.rebuildBackoffSeconds - 0.01, status: .running))
        XCTAssertTrue(m.shouldRebuild(now: 200 + CaptureStallMonitor.rebuildBackoffSeconds, status: .running))
    }

    // The playback gate keeps tracking while a rebuild is in flight.
    func testGateTracksPlaybackWhileInFlight() {
        var m = CaptureStallMonitor(now: 0)
        m.noteRebuildStarted(now: 0)
        XCTAssertFalse(m.shouldRebuild(now: 5, status: .running, playerPlaying: false))
        XCTAssertTrue(m.isGateSuppressing)
    }
}
