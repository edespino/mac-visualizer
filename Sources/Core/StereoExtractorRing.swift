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

/// A pointer-based view of one `AudioBuffer` from an `AudioBufferList`, for
/// the allocation-free IO-proc path. The pointer aliases the AudioBufferList's
/// storage and is only valid for the duration of the IO callback.
///
/// `samples` mirrors `CaptureBuffer.samples`' optionality exactly:
/// - `nil`                     → the buffer had a null `mData` pointer.
/// - non-nil with `count == 0` → a present buffer carrying zero frames.
public struct RawCaptureBufferView {
    public let samples: UnsafeBufferPointer<Float>?
    public let channelCount: Int

    public init(samples: UnsafeBufferPointer<Float>?, channelCount: Int) {
        self.samples = samples
        self.channelCount = channelCount
    }
}

/// Reused-storage counterpart of `extractStereoFromBuffers` for the Core Audio
/// IO proc, which must not allocate per callback. A small ring of preallocated
/// `[Float]` slots receives the extracted L/R samples; the returned arrays
/// share the slot's backing storage. As long as a downstream consumer releases
/// a result before the ring cycles back to its slot (slotCount callbacks
/// later), the slot mutates in place — no allocation.
///
/// The guarantee is best-effort, not absolute — the residual allocation cases
/// on the IO thread are:
///   - **Downstream backlog spanning the ring depth.** Swift arrays are
///     copy-on-write: if a consumer (e.g. a saturated DSP queue) still holds a
///     slot's result when the ring cycles back to it, the mutation triggers
///     one COW copy per affected slot. Data is never corrupted. The default
///     ring depth of 8 makes this require a backlog of 8 callbacks (~8 IO
///     slices) before it can happen at all.
///   - **Frames above the prepared capacity.** A slice larger than the slot's
///     reserved storage grows it in place, once per new high-water mark. Call
///     `prepare(frameCapacity:)` at capture (re)start with the device's
///     negotiated buffer size so that growth happens off the IO critical
///     path; after that, conforming slices never grow.
///
/// The branching semantics (interleaved vs non-interleaved, nil-mData vs
/// present-but-empty, ragged-channel clamping) MUST match
/// `extractStereoFromBuffers` exactly — `StereoExtractorRingTests` pins parity
/// across every fixture of `AudioCaptureBufferTests`.
///
/// Not thread-safe: confine each instance to one queue (the IO proc's).
/// `prepare` is safe to call from the owning service's start path because the
/// IO proc is not yet running (or has been stopped) at that point.
public final class StereoExtractorRing {
    private var leftSlots: [[Float]]
    private var rightSlots: [[Float]]
    private var index = 0

    public init(slotCount: Int = 8, initialCapacity: Int = 4096) {
        let slots = max(1, slotCount)
        var slot = [Float]()
        slot.reserveCapacity(max(0, initialCapacity))
        leftSlots = Array(repeating: slot, count: slots)
        rightSlots = Array(repeating: slot, count: slots)
        // Force each slot to unique storage now (Array(repeating:) shares one
        // buffer) so first use never triggers a surprise copy mid-callback.
        for i in 0..<slots {
            leftSlots[i].reserveCapacity(max(1, initialCapacity))
            rightSlots[i].reserveCapacity(max(1, initialCapacity))
        }
    }

    /// The frame capacity that governs ring sizing: the LARGEST slice the
    /// device may deliver. For variable-buffer-size devices the nominal
    /// buffer frame size is the SMALLEST callback size, so the governing
    /// bound is the maximum over the published values — nominal size, buffer
    /// frame size range maximum, and the variable-size maximum when the
    /// device publishes one. Absent (nil) or non-positive readings are
    /// ignored; nil when nothing valid is known.
    public static func governingFrameCapacity(nominal: Int?,
                                              rangeMaximum: Int?,
                                              variableMaximum: Int?) -> Int? {
        [nominal, rangeMaximum, variableMaximum]
            .compactMap { $0 }
            .filter { $0 > 0 }
            .max()
    }

    /// Reserve at least `frameCapacity` frames of storage in every slot, OFF
    /// the IO critical path. Call at capture (re)start with the device's
    /// governing frame capacity (see `governingFrameCapacity`); requesting the
    /// current capacity or less is a no-op (capacity never shrinks), so an
    /// unchanged format never reallocates. Non-positive requests are ignored.
    public func prepare(frameCapacity: Int) {
        guard frameCapacity > 0 else { return }
        for i in 0..<leftSlots.count {
            leftSlots[i].reserveCapacity(frameCapacity)
            rightSlots[i].reserveCapacity(frameCapacity)
        }
    }

    /// Extract L/R into the next ring slot. See `extractStereoFromBuffers` for
    /// the full semantics contract this reproduces.
    public func extract(from buffers: [RawCaptureBufferView]) -> (left: [Float], right: [Float]) {
        guard !buffers.isEmpty else { return ([], []) }

        if buffers.count == 1 {
            // Interleaved (or already mono): one buffer with `channelCount`
            // channels. nil mData or zero frames → nothing to emit.
            guard let samples = buffers[0].samples, !samples.isEmpty else { return ([], []) }
            let ch = max(1, buffers[0].channelCount)
            if ch == 1 {
                return fill(frames: samples.count) { l, r, f in
                    l[f] = samples[f]; r[f] = samples[f]
                }
            }
            let frames = samples.count / ch
            guard frames > 0 else { return ([], []) }
            return fill(frames: frames) { l, r, f in
                let base = f * ch
                l[f] = samples[base]; r[f] = samples[base + 1]
            }
        }

        // Non-interleaved: one buffer per channel. Skip nil-data buffers;
        // include present-but-empty ones in the frame-count minimum so a
        // zero-length channel suppresses the whole callback.
        var first: UnsafeBufferPointer<Float>?
        var second: UnsafeBufferPointer<Float>?
        var frames = Int.max
        for b in buffers {
            guard let samples = b.samples else { continue }
            frames = min(frames, samples.count)
            if first == nil { first = samples } else if second == nil { second = samples }
        }
        guard let lhs = first, frames != Int.max, frames > 0 else { return ([], []) }
        let rhs = second ?? lhs
        return fill(frames: frames) { l, r, f in
            l[f] = lhs[f]; r[f] = rhs[f]
        }
    }

    /// Size the next slot pair to `frames` (reusing capacity) and populate it.
    private func fill(frames: Int,
                      _ body: (inout [Float], inout [Float], Int) -> Void) -> (left: [Float], right: [Float]) {
        index = (index + 1) % leftSlots.count
        resize(&leftSlots[index], to: frames)
        resize(&rightSlots[index], to: frames)
        for f in 0..<frames {
            body(&leftSlots[index], &rightSlots[index], f)
        }
        return (leftSlots[index], rightSlots[index])
    }

    /// In-place resize that never shrinks capacity: growing appends zeros
    /// (allocation only past the high-water mark), shrinking keeps storage.
    private func resize(_ slot: inout [Float], to count: Int) {
        if slot.count > count {
            slot.removeLast(slot.count - count)
        } else {
            slot.append(contentsOf: repeatElement(0, count: count - slot.count))
        }
    }
}
