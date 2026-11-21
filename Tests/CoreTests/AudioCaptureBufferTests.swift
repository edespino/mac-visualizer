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

final class AudioCaptureBufferTests: XCTestCase {

    // MARK: - Interleaved (single buffer) layout

    func testInterleavedStereoIsDeinterleavedByStride() {
        // One buffer, 2 interleaved channels: L,R,L,R,L,R
        let interleaved: [Float] = [0.0, 1.0, 0.2, 0.4, -1.0, 0.5]
        let buffers = [CaptureBuffer(samples: interleaved, channelCount: 2)]
        let (left, right) = extractStereoFromBuffers(buffers)
        XCTAssertEqual(left, [0.0, 0.2, -1.0])
        XCTAssertEqual(right, [1.0, 0.4, 0.5])
    }

    func testInterleavedMonoDuplicatesIntoBothChannels() {
        let mono: [Float] = [0.1, -0.2, 0.3]
        let buffers = [CaptureBuffer(samples: mono, channelCount: 1)]
        let (left, right) = extractStereoFromBuffers(buffers)
        XCTAssertEqual(left, mono)
        XCTAssertEqual(right, mono)
    }

    func testInterleavedZeroChannelCountIsClampedToMono() {
        // A pathological channelCount of 0 must clamp to 1 (mono), not divide-by-zero.
        let samples: [Float] = [0.1, 0.2, 0.3]
        let buffers = [CaptureBuffer(samples: samples, channelCount: 0)]
        let (left, right) = extractStereoFromBuffers(buffers)
        XCTAssertEqual(left, samples)
        XCTAssertEqual(right, samples)
    }

    func testInterleaved5Point1TakesFirstTwoChannels() {
        // 6 channels interleaved, 2 frames. L = ch0, R = ch1; remaining channels dropped.
        let frame0: [Float] = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5]
        let frame1: [Float] = [1.0, 1.1, 1.2, 1.3, 1.4, 1.5]
        let buffers = [CaptureBuffer(samples: frame0 + frame1, channelCount: 6)]
        let (left, right) = extractStereoFromBuffers(buffers)
        XCTAssertEqual(left, [0.0, 1.0])
        XCTAssertEqual(right, [0.1, 1.1])
    }

    func testInterleavedTrailingPartialFrameIsIgnored() {
        // 5 samples, 2 channels -> 2 complete frames; the lone trailing sample is dropped.
        let buffers = [CaptureBuffer(samples: [0, 1, 2, 3, 4], channelCount: 2)]
        let (left, right) = extractStereoFromBuffers(buffers)
        XCTAssertEqual(left, [0, 2])
        XCTAssertEqual(right, [1, 3])
    }

    // MARK: - Non-interleaved (one buffer per channel) layout

    func testNonInterleavedStereoUsesChannel0AndChannel1() {
        let l: [Float] = [0.0, 0.2, -1.0]
        let r: [Float] = [1.0, 0.4, 0.5]
        let buffers = [
            CaptureBuffer(samples: l, channelCount: 1),
            CaptureBuffer(samples: r, channelCount: 1),
        ]
        let (left, right) = extractStereoFromBuffers(buffers)
        XCTAssertEqual(left, l)
        XCTAssertEqual(right, r)
    }

    func testNonInterleavedClampsToShortestBuffer() {
        // Ragged channels: R is shorter, so the frame count clamps to it (no over-read).
        let l: [Float] = [0.0, 0.1, 0.2, 0.3]
        let r: [Float] = [1.0, 1.1]
        let buffers = [
            CaptureBuffer(samples: l, channelCount: 1),
            CaptureBuffer(samples: r, channelCount: 1),
        ]
        let (left, right) = extractStereoFromBuffers(buffers)
        XCTAssertEqual(left, [0.0, 0.1])
        XCTAssertEqual(right, [1.0, 1.1])
    }

    func testNonInterleavedMoreThanTwoChannelsTakesFirstTwo() {
        let buffers = [
            CaptureBuffer(samples: [0.0, 0.1], channelCount: 1),
            CaptureBuffer(samples: [1.0, 1.1], channelCount: 1),
            CaptureBuffer(samples: [2.0, 2.1], channelCount: 1),
        ]
        let (left, right) = extractStereoFromBuffers(buffers)
        XCTAssertEqual(left, [0.0, 0.1])
        XCTAssertEqual(right, [1.0, 1.1])
    }

    func testNonInterleavedClampsToShortestLaterChannel() {
        // The frame count is min over ALL present buffers, so a shorter 3rd+
        // channel constrains it even though L/R come only from ch0/ch1.
        let buffers = [
            CaptureBuffer(samples: [0.0, 0.1, 0.2], channelCount: 1),
            CaptureBuffer(samples: [1.0, 1.1, 1.2], channelCount: 1),
            CaptureBuffer(samples: [2.0, 2.1], channelCount: 1),  // shortest → clamps to 2 frames
        ]
        let (left, right) = extractStereoFromBuffers(buffers)
        XCTAssertEqual(left, [0.0, 0.1])
        XCTAssertEqual(right, [1.0, 1.1])
    }

    // MARK: - Degenerate inputs

    func testNoBuffersYieldsEmpty() {
        let (left, right) = extractStereoFromBuffers([])
        XCTAssertTrue(left.isEmpty)
        XCTAssertTrue(right.isEmpty)
    }

    func testSingleEmptyInterleavedBufferYieldsEmpty() {
        let buffers = [CaptureBuffer(samples: [], channelCount: 2)]
        let (left, right) = extractStereoFromBuffers(buffers)
        XCTAssertTrue(left.isEmpty)
        XCTAssertTrue(right.isEmpty)
    }

    func testNonInterleavedAllEmptyYieldsEmpty() {
        let buffers = [
            CaptureBuffer(samples: [], channelCount: 1),
            CaptureBuffer(samples: [], channelCount: 1),
        ]
        let (left, right) = extractStereoFromBuffers(buffers)
        XCTAssertTrue(left.isEmpty)
        XCTAssertTrue(right.isEmpty)
    }

    // MARK: - nil mData vs zero-length (original IO-proc semantics pinned)

    func testSingleNilDataBufferYieldsEmpty() {
        // Interleaved path, null mData → nothing emitted (original `guard let data`).
        let buffers = [CaptureBuffer(samples: nil, channelCount: 2)]
        let (left, right) = extractStereoFromBuffers(buffers)
        XCTAssertTrue(left.isEmpty)
        XCTAssertTrue(right.isEmpty)
    }

    func testNonInterleavedNilDataChannelIsSkippedLeavingMono() {
        // 2-buffer (non-interleaved) list where channel 0 has null mData: the nil
        // buffer is skipped, leaving one present channel that is duplicated into
        // both L and R — matching the original `channelPtrs` skip + ch0/ch0 path.
        let present: [Float] = [0.0, 0.2, -1.0]
        let buffers = [
            CaptureBuffer(samples: nil, channelCount: 1),
            CaptureBuffer(samples: present, channelCount: 1),
        ]
        let (left, right) = extractStereoFromBuffers(buffers)
        XCTAssertEqual(left, present)
        XCTAssertEqual(right, present)
    }

    func testNonInterleavedPresentButEmptyChannelSuppressesWholeCallback() {
        // A present-but-empty (zero-frame) sub-buffer drives `frames = min(...)`
        // to zero, suppressing the entire callback even though channel 1 has data.
        // This is the deliberate original semantics (NOT "process the rest").
        let buffers = [
            CaptureBuffer(samples: [], channelCount: 1),
            CaptureBuffer(samples: [1.0, 1.1, 1.2], channelCount: 1),
        ]
        let (left, right) = extractStereoFromBuffers(buffers)
        XCTAssertTrue(left.isEmpty)
        XCTAssertTrue(right.isEmpty)
    }

    func testTwoBufferListWithOneNilTakesNonInterleavedPathNotInterleaved() {
        // Pins that a 2-element list branches on the RAW count (non-interleaved),
        // not on the post-skip count. Channel 0 declares 2 interleaved channels but
        // is treated as a single non-interleaved channel: had this hit the
        // interleaved path it would de-interleave into distinct L/R; instead L==R.
        let ch0: [Float] = [0.0, 1.0, 0.2, 0.4]
        let buffers = [
            CaptureBuffer(samples: ch0, channelCount: 2),
            CaptureBuffer(samples: nil, channelCount: 2),
        ]
        let (left, right) = extractStereoFromBuffers(buffers)
        XCTAssertEqual(left, ch0)
        XCTAssertEqual(right, ch0)
    }
}
