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

/// Coarse capture status for UI/diagnostics.
public enum CaptureState: Equatable {
    case stopped
    case running
    case noTargetProcess      // Spotify/Music not running or not producing audio
    case failed(String)       // tap/aggregate creation or start failed (message for logging)
}

/// A source of stereo Float32 audio samples plus the sample rate they arrive at.
/// Implemented by the real Core Audio capture service (app target) and by fakes in tests.
public protocol AudioCaptureSource: AnyObject {
    var state: CaptureState { get }
    /// Called on a background queue with L and R sample buffers and the sample rate.
    /// Mono sources should pass the same buffer for both L and R.
    var onSamples: (([Float], [Float], Double) -> Void)? { get set }
    func start()
    /// Start (or rebuild) capture, recording why for diagnostics. Default
    /// forwards to `start()` so simple fakes need not implement it.
    func start(reason: String)
    func stop()
    /// Rebuild capture from scratch. Called when a running capture has gone
    /// silent because its output route changed (e.g. a Bluetooth device
    /// connecting, dropping, or sleeping stranded the aggregate's clock).
    func restart()
    /// Rebuild, recording why. Default forwards to `restart()`.
    func restart(reason: String)
    /// Start/rebuild and report completion. A real implementation may run the
    /// work off the calling thread; `completion` is then delivered on the MAIN
    /// thread once the work that covers this request has finished (whatever
    /// the resulting state). Default: synchronous, completion called inline.
    func start(reason: String, completion: @escaping () -> Void)
    func restart(reason: String, completion: @escaping () -> Void)
}

public extension AudioCaptureSource {
    func start(reason: String) { start() }
    func restart(reason: String) { restart() }
    func start(reason: String, completion: @escaping () -> Void) {
        start(reason: reason)
        completion()
    }
    func restart(reason: String, completion: @escaping () -> Void) {
        restart(reason: reason)
        completion()
    }

    /// Default: tear down and start again. The real Core Audio service
    /// overrides this with its own idempotent `start()`.
    func restart() {
        stop()
        start()
    }
}