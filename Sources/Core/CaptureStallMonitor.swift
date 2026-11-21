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

/// Decides when a *running* audio capture has silently stalled and should be
/// rebuilt. A process-tap aggregate device is clocked to the default output
/// device; when output routing changes (notably a Bluetooth device connecting,
/// dropping, or auto-sleeping) the clock can strand and the IO proc stops
/// delivering samples with no error. The capture state stays `.running`, so
/// nothing restarts it and the scene idle-fades out indefinitely.
///
/// The caller ticks this per frame: `noteSample` whenever a fresh captured
/// frame is seen, and `shouldRebuild` to ask whether to restart. Pure and
/// clock-injected so the policy is unit-tested without real time or Core Audio.
public struct CaptureStallMonitor {
    /// What the caller's capture is doing, as far as rebuild policy cares.
    public enum Status: Equatable {
        /// Capture is running (a stall is possible).
        case running
        /// Capture hit an error and sits in a terminal failed state.
        case failed
        /// Stopped or no target process: never rebuilt by the watchdog.
        case other

        public init(_ state: CaptureState) {
            switch state {
            case .running: self = .running
            case .failed: self = .failed
            case .stopped, .noTargetProcess: self = .other
            }
        }
    }

    /// No samples for this long while running counts as a stall.
    public static let stallSeconds: TimeInterval = 1.5
    /// Minimum gap between rebuilds, so a rebuild that has not yet produced
    /// samples (or a permanent failure) does not restart every frame.
    public static let rebuildBackoffSeconds: TimeInterval = 3.0
    /// Minimum gap between retries of a `.failed` capture, so a permanent
    /// failure (e.g. recording permission denied) does not hammer Core Audio.
    public static let failedRetrySeconds: TimeInterval = 5.0

    /// Cap on the escalating backoff between fruitless stall rebuilds.
    public static let maxRebuildBackoffSeconds: TimeInterval = 60.0

    private var lastSampleTime: TimeInterval
    private var lastRebuildTime: TimeInterval?
    /// When the current run of `.failed` was first seen, or the last failed retry.
    private var failedClock: TimeInterval?
    /// Stall rebuilds decided since the last sample (i.e. that produced nothing).
    public private(set) var fruitlessCount = 0
    private var wasPlaying = true
    /// True from `noteRebuildStarted` until `noteRebuildFinished`. The rebuild
    /// runs off the main thread and can take 90 s when the audio service is
    /// slow; no policy decision may fire another one meanwhile.
    public private(set) var isRebuildInFlight = false

    /// True while the playback gate is suppressing stall rebuilds.
    public var isGateSuppressing: Bool { !wasPlaying }

    /// Backoff currently required between stall rebuilds:
    /// `rebuildBackoffSeconds * 2^(n-1)` for n fruitless rebuilds, capped.
    public var currentBackoffSeconds: TimeInterval {
        let exp = max(0, fruitlessCount - 1)
        guard exp < 16 else { return Self.maxRebuildBackoffSeconds }
        return min(Self.rebuildBackoffSeconds * Double(1 << exp), Self.maxRebuildBackoffSeconds)
    }

    /// Seed with the current time so a just-started capture gets a full
    /// `stallSeconds` grace period before the first stall can be declared.
    public init(now: TimeInterval) {
        lastSampleTime = now
        lastRebuildTime = nil
        failedClock = nil
    }

    /// Record that a fresh captured frame arrived, resetting the stall clock
    /// and the fruitless-rebuild count.
    public mutating func noteSample(now: TimeInterval) {
        lastSampleTime = now
        fruitlessCount = 0
    }

    /// Record that a rebuild (or the launch start) was requested. Until
    /// `noteRebuildFinished`, `shouldRebuild` returns false for every status,
    /// however long the rebuild takes. Calling it again while in flight is harmless.
    public mutating func noteRebuildStarted(now: TimeInterval) {
        isRebuildInFlight = true
    }

    /// Record that a rebuild (or the launch start) finished at `now`. The
    /// rebuild runs asynchronously and can take seconds; restarting both clocks
    /// from the completion time stops the next frame from re-firing at once.
    public mutating func noteRebuildFinished(now: TimeInterval) {
        isRebuildInFlight = false
        lastSampleTime = now
        lastRebuildTime = now
        if failedClock != nil { failedClock = now }
    }

    /// True when the caller should rebuild capture now; marks the rebuild time
    /// when it returns true.
    /// - `.running`: after `stallSeconds` without a sample, no more often than
    ///   the escalating backoff, and only while `playerPlaying` (a tap built
    ///   while nothing plays delivers no frames, so rebuilding cannot help).
    ///   Going from not-playing to playing restarts the stall clock.
    /// - `.failed`: `failedRetrySeconds` after the failure was first seen, then
    ///   every `failedRetrySeconds` while it persists. Not gated.
    /// - `.other`: never.
    public mutating func shouldRebuild(now: TimeInterval, status: Status,
                                       playerPlaying: Bool = true) -> Bool {
        if status != .failed { failedClock = nil }
        if !playerPlaying {
            wasPlaying = false
        } else if !wasPlaying {
            wasPlaying = true
            lastSampleTime = now
        }
        if isRebuildInFlight { return false }
        switch status {
        case .other:
            return false
        case .failed:
            guard let since = failedClock else {
                failedClock = now
                return false
            }
            guard now - since >= Self.failedRetrySeconds else { return false }
            failedClock = now
            return true
        case .running:
            guard playerPlaying else { return false }
            guard now - lastSampleTime >= Self.stallSeconds else { return false }
            if let last = lastRebuildTime, now - last < currentBackoffSeconds {
                return false
            }
            lastRebuildTime = now
            fruitlessCount += 1
            return true
        }
    }
}
