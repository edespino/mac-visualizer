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

import Foundation

/// Pure request state machine behind `AudioCaptureService`'s lifecycle queue.
/// Requests may arrive from any thread (the caller serializes access with a
/// lock); the drain loop on the lifecycle queue pulls work with `next()`.
///
/// At most ONE operation is pending behind the one running, and the latest
/// request wins: a burst of starts during a long hang yields one follow-up
/// rebuild with the most recent reason, and a stop requested after a start
/// replaces it (the start never runs), while a start requested after a stop
/// replaces the stop.
public struct CaptureRequestQueue {
    public enum Operation: Equatable {
        case start(reason: String)
        case stop
    }

    public enum Submission: Equatable {
        /// Nothing was queued or running: the caller must schedule a drain pass.
        case schedule
        /// A drain is queued or running; `replaced` is the pending operation
        /// this request superseded, if any.
        case coalesced(replaced: Operation?)
    }

    private var scheduled = false
    private var pending: Operation?

    public init() {}

    /// True while a drain pass is scheduled or running.
    public var isBusy: Bool { scheduled }

    public mutating func requestStart(reason: String) -> Submission {
        submit(.start(reason: reason))
    }

    public mutating func requestStop() -> Submission {
        submit(.stop)
    }

    private mutating func submit(_ op: Operation) -> Submission {
        let replaced = pending
        pending = op
        if scheduled { return .coalesced(replaced: replaced) }
        scheduled = true
        return .schedule
    }

    /// Next operation for the drain loop, or nil once drained (the queue is
    /// then idle and the next request schedules a new pass).
    public mutating func next() -> Operation? {
        if let op = pending {
            pending = nil
            return op
        }
        scheduled = false
        return nil
    }
}
