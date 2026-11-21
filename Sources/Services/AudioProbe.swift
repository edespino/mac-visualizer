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
import MacVisualizerCore

/// CLI verification: start capture, print RMS of incoming mono samples for `seconds`, then exit.
/// Run with music playing. First run triggers the system-audio permission prompt.
enum AudioProbe {
    static let startTimeout: TimeInterval = 120

    static func run(seconds: Double = 5) {
        let service = AudioCaptureService()
        let lock = NSLock()
        var window: [Float] = []

        service.onSamples = { left, _, _ in
            let samples = left   // probe only needs one channel
            lock.lock(); window.append(contentsOf: samples); lock.unlock()
        }
        // Start is asynchronous (lifecycle queue); the completion arrives on main,
        // so pump the main run loop while waiting. Bounded: a slow audio service
        // has been measured blocking start for 90 s.
        var started = false
        service.start(reason: "audio-probe") { started = true }
        let startDeadline = Date().addingTimeInterval(startTimeout)
        while !started && Date() < startDeadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        guard started else {
            FileHandle.standardError.write(Data("audio-probe error: capture did not start within \(Int(startTimeout)) s\n".utf8))
            return
        }
        FileHandle.standardError.write(Data("audio-probe state: \(service.state)\n".utf8))

        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            lock.lock(); let chunk = window; window.removeAll(); lock.unlock()
            if chunk.isEmpty { print("rms: --- (no samples)"); continue }
            let rms = sqrtf(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
            print(String(format: "rms: %.5f  (samples: %d)", rms, chunk.count))
        }
        service.stop()
    }
}