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

/// Tracks playback position between player polls using a monotonic clock.
/// A fresh poll only re-anchors the clock when it disagrees with the
/// interpolated position by more than `snapThresholdMs` (a seek), or when
/// the playing state flips. Port of the web app's `PositionTracker`
/// without its locally-initiated-seek handling.
public struct PlaybackPositionTracker {
    public static let snapThresholdMs: Double = 1500

    private var anchorPositionMs: Double = 0
    private var anchorClockMs: Double = 0
    private var playing = false
    private var hasData = false

    public init() {}

    public mutating func update(polledPositionMs: Double, isPlaying: Bool, nowMs: Double) {
        let interpolated = position(atMs: nowMs)
        let stateChanged = isPlaying != playing
        let drifted = abs(interpolated - polledPositionMs) > Self.snapThresholdMs
        if !hasData || stateChanged || drifted {
            anchorPositionMs = polledPositionMs
            anchorClockMs = nowMs
        }
        playing = isPlaying
        hasData = true
    }

    public func position(atMs nowMs: Double) -> Double {
        guard hasData else { return 0 }
        guard playing else { return anchorPositionMs }
        return anchorPositionMs + (nowMs - anchorClockMs)
    }

    public mutating func reset() {
        self = PlaybackPositionTracker()
    }
}
