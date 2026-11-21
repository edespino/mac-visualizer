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

/// Averages `channelCount` interleaved channels into a mono signal.
/// A trailing partial frame (fewer than `channelCount` samples) is ignored.
public func downmixToMono(interleaved: [Float], channelCount: Int) -> [Float] {
    precondition(channelCount >= 1, "channelCount must be >= 1")
    if channelCount == 1 { return interleaved }
    let frames = interleaved.count / channelCount
    guard frames > 0 else { return [] }
    var mono = [Float](repeating: 0, count: frames)
    let inv = 1 / Float(channelCount)
    for f in 0..<frames {
        var sum: Float = 0
        let base = f * channelCount
        for c in 0..<channelCount { sum += interleaved[base + c] }
        mono[f] = sum * inv
    }
    return mono
}

/// Extract L and R channels from an interleaved buffer. For `channelCount == 1`,
/// returns `(samples, samples)` (mono → duplicate). For 2+ channels, returns
/// channels 0 and 1 (5.1 layouts conventionally place L on ch 0 and R on ch 1).
/// A trailing partial frame is ignored.
public func extractStereo(interleaved: [Float], channelCount: Int) -> (left: [Float], right: [Float]) {
    precondition(channelCount >= 1, "channelCount must be >= 1")
    if channelCount == 1 {
        return (interleaved, interleaved)
    }
    let frames = interleaved.count / channelCount
    guard frames > 0 else { return ([], []) }
    var left = [Float](repeating: 0, count: frames)
    var right = [Float](repeating: 0, count: frames)
    for f in 0..<frames {
        let base = f * channelCount
        left[f] = interleaved[base]
        right[f] = interleaved[base + 1]
    }
    return (left, right)
}