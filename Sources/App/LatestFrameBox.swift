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
import os
import QuartzCore
import MacVisualizerCore

/// Thread-safe holder for the most recent AudioFrame and when it was stored.
/// Writer (DSP queue) calls `store`; reader (render loop) calls `recent`. Last write wins.
final class LatestFrameBox {
    private var lock = os_unfair_lock_s()
    private var frame: AudioFrame = .silent
    private var storedAt: CFTimeInterval = 0

    func store(_ f: AudioFrame, at time: CFTimeInterval) {
        os_unfair_lock_lock(&lock)
        frame = f
        storedAt = time
        os_unfair_lock_unlock(&lock)
    }

    /// The latest frame if stored within `maxAge` of `now`, else nil (caller falls back).
    func recent(now: CFTimeInterval, maxAge: CFTimeInterval) -> AudioFrame? {
        os_unfair_lock_lock(&lock)
        let f = frame
        let t = storedAt
        os_unfair_lock_unlock(&lock)
        return (now - t) < maxAge ? f : nil
    }
}