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

/// `StereoExtractorRing` is the allocation-free (reused-storage) form of
/// `extractStereoFromBuffers` used by the audio IO proc. Its branching
/// semantics must match the pure function EXACTLY — including the nil-mData
/// vs present-but-empty distinction — so every fixture here is checked for
/// parity against `extractStereoFromBuffers`.
final class StereoExtractorRingTests: XCTestCase {

    /// Run `body` with `RawCaptureBufferView`s whose pointers alias the given
    /// `CaptureBuffer`s' sample storage (valid only inside `body`, matching
    /// the IO-proc lifetime of an AudioBufferList).
    private func withViews(_ buffers: [CaptureBuffer],
                           _ body: ([RawCaptureBufferView]) -> Void) {
        var views: [RawCaptureBufferView] = []
        func build(_ i: Int) {
            if i == buffers.count { body(views); return }
            if let samples = buffers[i].samples {
                samples.withUnsafeBufferPointer { ptr in
                    views.append(RawCaptureBufferView(samples: ptr, channelCount: buffers[i].channelCount))
                    build(i + 1)
                    views.removeLast()
                }
            } else {
                views.append(RawCaptureBufferView(samples: nil, channelCount: buffers[i].channelCount))
                build(i + 1)
                views.removeLast()
            }
        }
        build(0)
    }

    /// Every branch of the original semantics, checked for parity.
    func testParityWithExtractStereoFromBuffers() {
        let fixtures: [[CaptureBuffer]] = [
            // Interleaved (single buffer) layouts.
            [CaptureBuffer(samples: [0.0, 1.0, 0.2, 0.4, -1.0, 0.5], channelCount: 2)],
            [CaptureBuffer(samples: [0.1, -0.2, 0.3], channelCount: 1)],
            [CaptureBuffer(samples: [0.1, 0.2, 0.3], channelCount: 0)],       // clamps to mono
            [CaptureBuffer(samples: [0.0, 0.1, 0.2, 0.3, 0.4, 0.5,
                                     1.0, 1.1, 1.2, 1.3, 1.4, 1.5], channelCount: 6)],
            [CaptureBuffer(samples: [0, 1, 2, 3, 4], channelCount: 2)],       // trailing partial frame
            // Non-interleaved (one buffer per channel) layouts.
            [CaptureBuffer(samples: [0.0, 0.2, -1.0], channelCount: 1),
             CaptureBuffer(samples: [1.0, 0.4, 0.5], channelCount: 1)],
            [CaptureBuffer(samples: [0.0, 0.1, 0.2, 0.3], channelCount: 1),
             CaptureBuffer(samples: [1.0, 1.1], channelCount: 1)],            // ragged, clamps
            [CaptureBuffer(samples: [0.0, 0.1], channelCount: 1),
             CaptureBuffer(samples: [1.0, 1.1], channelCount: 1),
             CaptureBuffer(samples: [2.0, 2.1], channelCount: 1)],            // >2 channels
            [CaptureBuffer(samples: [0.0, 0.1, 0.2], channelCount: 1),
             CaptureBuffer(samples: [1.0, 1.1, 1.2], channelCount: 1),
             CaptureBuffer(samples: [2.0, 2.1], channelCount: 1)],            // 3rd channel clamps
            // Degenerate inputs.
            [],
            [CaptureBuffer(samples: [], channelCount: 2)],
            [CaptureBuffer(samples: [], channelCount: 1),
             CaptureBuffer(samples: [], channelCount: 1)],
            // nil mData vs zero-length distinctions.
            [CaptureBuffer(samples: nil, channelCount: 2)],
            [CaptureBuffer(samples: nil, channelCount: 1),
             CaptureBuffer(samples: [0.0, 0.2, -1.0], channelCount: 1)],       // nil skipped -> mono dup
            [CaptureBuffer(samples: [], channelCount: 1),
             CaptureBuffer(samples: [1.0, 1.1, 1.2], channelCount: 1)],        // empty suppresses all
            [CaptureBuffer(samples: [0.0, 1.0, 0.2, 0.4], channelCount: 2),
             CaptureBuffer(samples: nil, channelCount: 2)],                    // raw-count branch pin
        ]

        let ring = StereoExtractorRing()
        for (i, fixture) in fixtures.enumerated() {
            let expected = extractStereoFromBuffers(fixture)
            withViews(fixture) { views in
                let got = ring.extract(from: views)
                XCTAssertEqual(got.left, expected.left, "fixture \(i): left mismatch")
                XCTAssertEqual(got.right, expected.right, "fixture \(i): right mismatch")
            }
        }
    }

    /// Steady-state extraction must reuse its preallocated slot storage: when
    /// the caller does not retain a prior result, cycling back to the same ring
    /// slot writes into the same backing buffer (no per-callback allocation).
    func testSlotStorageIsReusedAcrossCalls() {
        let slotCount = 4
        let ring = StereoExtractorRing(slotCount: slotCount, initialCapacity: 64)
        let samples: [Float] = (0..<32).map { Float($0) }
        let fixture = [CaptureBuffer(samples: samples, channelCount: 2)]

        func extractBaseAddress() -> UnsafeRawPointer? {
            var base: UnsafeRawPointer?
            withViews(fixture) { views in
                let (left, _) = ring.extract(from: views)
                left.withUnsafeBufferPointer { base = UnsafeRawPointer($0.baseAddress) }
            }
            return base
        }

        let first = extractBaseAddress()
        XCTAssertNotNil(first)
        // Cycle through the remaining slots, dropping each result.
        for _ in 0..<(slotCount - 1) { _ = extractBaseAddress() }
        // Back at the first slot: same backing storage, not a fresh allocation.
        XCTAssertEqual(extractBaseAddress(), first)
    }

    /// Format-change path: `prepare(frameCapacity:)` re-sizes slot storage off
    /// the extract path. After a simulated format change to a larger buffer
    /// size, extraction at the new size is still parity-correct and slot
    /// storage is still reused across ring cycles.
    func testPrepareForNewFormatKeepsParityAndReuse() {
        let slotCount = 4
        let ring = StereoExtractorRing(slotCount: slotCount, initialCapacity: 16)

        // Initial small format.
        let small: [Float] = (0..<16).map { Float($0) }
        withViews([CaptureBuffer(samples: small, channelCount: 2)]) { views in
            let got = ring.extract(from: views)
            let expected = extractStereoFromBuffers([CaptureBuffer(samples: small, channelCount: 2)])
            XCTAssertEqual(got.left, expected.left)
        }

        // Capture restarts with a larger negotiated buffer: prepare off the
        // hot path, then extract at the new size.
        ring.prepare(frameCapacity: 512)
        let big: [Float] = (0..<1024).map { Float($0) }  // 512 frames interleaved
        let fixture = [CaptureBuffer(samples: big, channelCount: 2)]
        let expected = extractStereoFromBuffers(fixture)

        func extractBaseAddress() -> UnsafeRawPointer? {
            var base: UnsafeRawPointer?
            withViews(fixture) { views in
                let (left, _) = ring.extract(from: views)
                XCTAssertEqual(left, expected.left)
                left.withUnsafeBufferPointer { base = UnsafeRawPointer($0.baseAddress) }
            }
            return base
        }

        let first = extractBaseAddress()
        XCTAssertNotNil(first)
        for _ in 0..<(slotCount - 1) { _ = extractBaseAddress() }
        // Back at the first slot: storage reused at the new size too.
        XCTAssertEqual(extractBaseAddress(), first)
    }

    /// The ring must be sized from the LARGEST slice the device may deliver:
    /// for variable-buffer-size devices the nominal buffer frame size is the
    /// SMALLEST callback size, so the governing bound is the max over the
    /// published values (nominal, range maximum, variable-size maximum),
    /// ignoring absent or non-positive readings.
    func testGoverningFrameCapacityPicksLargestPublishedBound() {
        XCTAssertEqual(StereoExtractorRing.governingFrameCapacity(
            nominal: 512, rangeMaximum: 4096, variableMaximum: nil), 4096)
        XCTAssertEqual(StereoExtractorRing.governingFrameCapacity(
            nominal: 512, rangeMaximum: 4096, variableMaximum: 8192), 8192)
        XCTAssertEqual(StereoExtractorRing.governingFrameCapacity(
            nominal: 512, rangeMaximum: nil, variableMaximum: nil), 512)
        XCTAssertEqual(StereoExtractorRing.governingFrameCapacity(
            nominal: 0, rangeMaximum: -5, variableMaximum: 1024), 1024)
        XCTAssertNil(StereoExtractorRing.governingFrameCapacity(
            nominal: nil, rangeMaximum: nil, variableMaximum: nil))
        XCTAssertNil(StereoExtractorRing.governingFrameCapacity(
            nominal: 0, rangeMaximum: -5, variableMaximum: nil))
    }

    /// prepare never shrinks: a smaller (or non-positive) capacity request
    /// after a larger one leaves extraction at the larger size intact.
    func testPrepareIsNoShrinkAndIgnoresNonPositive() {
        let ring = StereoExtractorRing(slotCount: 2, initialCapacity: 8)
        ring.prepare(frameCapacity: 256)
        ring.prepare(frameCapacity: 4)
        ring.prepare(frameCapacity: 0)
        ring.prepare(frameCapacity: -1)
        let samples: [Float] = (0..<512).map { Float($0) }  // 256 frames
        let fixture = [CaptureBuffer(samples: samples, channelCount: 2)]
        let expected = extractStereoFromBuffers(fixture)
        withViews(fixture) { views in
            let got = ring.extract(from: views)
            XCTAssertEqual(got.left, expected.left)
            XCTAssertEqual(got.right, expected.right)
        }
    }

    /// Outputs are value-correct even when a downstream consumer retains a
    /// previous result across ring reuse (copy-on-write protects the data).
    func testRetainedResultSurvivesRingReuse() {
        let ring = StereoExtractorRing(slotCount: 2, initialCapacity: 16)
        let a: [Float] = [1, 2, 3, 4]
        let b: [Float] = [9, 8, 7, 6]
        var retained: (left: [Float], right: [Float]) = ([], [])
        withViews([CaptureBuffer(samples: a, channelCount: 2)]) { views in
            retained = ring.extract(from: views)
        }
        // Reuse every slot with different data.
        for _ in 0..<4 {
            withViews([CaptureBuffer(samples: b, channelCount: 2)]) { views in
                _ = ring.extract(from: views)
            }
        }
        XCTAssertEqual(retained.left, [1, 3])
        XCTAssertEqual(retained.right, [2, 4])
    }
}
