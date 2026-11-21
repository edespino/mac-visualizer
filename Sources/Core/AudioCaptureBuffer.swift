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

/// A pure, value-type view of one `AudioBuffer` from an `AudioBufferList`:
/// the Float32 samples it carried and the channel count it declared.
/// Lets the IO-proc buffer math be tested without Core Audio pointers.
///
/// `samples` is optional to faithfully model the source `AudioBuffer`:
/// - `nil`  → the buffer had a null `mData` pointer (no backing storage).
/// - `[]`   → a present buffer that carried zero frames (`mDataByteSize == 0`).
/// These two cases are treated differently by `extractStereoFromBuffers` —
/// see its documentation.
public struct CaptureBuffer: Equatable {
    public let samples: [Float]?
    public let channelCount: Int

    public init(samples: [Float]?, channelCount: Int) {
        self.samples = samples
        self.channelCount = channelCount
    }
}

/// Extract L/R stereo from the buffers of a Core Audio tap's `AudioBufferList`.
/// This mirrors the original IO-proc branching EXACTLY (it is the extracted,
/// testable form of that code — not a behavioral change), branching on the
/// *raw* buffer count:
///
/// - **One buffer — interleaved (or mono):** the buffer carries `channelCount`
///   interleaved channels. L/R are de-interleaved by stride; mono
///   (`channelCount <= 1`) duplicates its single channel into both L and R;
///   channel count is clamped to at least 1. A `nil`-data or empty single buffer
///   yields `([], [])`.
/// - **Two or more buffers — non-interleaved:** one buffer per channel. L is
///   channel 0, R is channel 1 (or channel 0 again when only one channel is
///   present). `nil`-data buffers are skipped; a *present-but-empty* buffer drives
///   the frame count to zero and therefore suppresses the whole callback (the
///   frame count is the minimum length over all present buffers). Present buffers
///   may differ in length, so the frame count is clamped to the shortest.
///
/// Returns `([], [])` when there are no buffers or no complete frames.
public func extractStereoFromBuffers(_ buffers: [CaptureBuffer]) -> (left: [Float], right: [Float]) {
    guard !buffers.isEmpty else { return ([], []) }

    if buffers.count == 1 {
        // Interleaved (or already mono): one buffer with `channelCount` channels.
        // nil mData or zero frames → nothing to emit (matches original guards).
        guard let samples = buffers[0].samples, !samples.isEmpty else { return ([], []) }
        let ch = max(1, buffers[0].channelCount)
        return extractStereo(interleaved: samples, channelCount: ch)
    }

    // Non-interleaved: one buffer per channel. Skip nil-data buffers; include
    // present-but-empty ones in the frame-count minimum so a zero-length channel
    // suppresses the whole callback (preserving the original min-over-buffers).
    var present: [[Float]] = []
    var frames = Int.max
    for b in buffers {
        guard let samples = b.samples else { continue }
        frames = min(frames, samples.count)
        present.append(samples)
    }
    guard !present.isEmpty, frames != Int.max, frames > 0 else { return ([], []) }

    let lhs = present[0]
    let rhs = present.count >= 2 ? present[1] : present[0]
    var left = [Float](repeating: 0, count: frames)
    var right = [Float](repeating: 0, count: frames)
    for f in 0..<frames {
        left[f] = lhs[f]
        right[f] = rhs[f]
    }
    return (left, right)
}
