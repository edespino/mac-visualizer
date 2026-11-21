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

final class AudioDownmixTests: XCTestCase {
    func testMonoInputIsReturnedUnchanged() {
        let input: [Float] = [0.1, -0.2, 0.3]
        XCTAssertEqual(downmixToMono(interleaved: input, channelCount: 1), input)
    }

    func testStereoIsAveragedPerFrame() {
        // L,R interleaved: (0.0,1.0)->0.5 ; (0.2,0.4)->0.3 ; (-1.0,1.0)->0.0
        let input: [Float] = [0.0, 1.0, 0.2, 0.4, -1.0, 1.0]
        let mono = downmixToMono(interleaved: input, channelCount: 2)
        XCTAssertEqual(mono.count, 3)
        XCTAssertEqual(mono[0], 0.5, accuracy: 1e-6)
        XCTAssertEqual(mono[1], 0.3, accuracy: 1e-6)
        XCTAssertEqual(mono[2], 0.0, accuracy: 1e-6)
    }

    func testEmptyInputYieldsEmpty() {
        XCTAssertTrue(downmixToMono(interleaved: [], channelCount: 2).isEmpty)
    }

    func testIgnoresTrailingPartialFrame() {
        // 5 samples, 2 channels -> 2 complete frames, last lone sample dropped
        let input: [Float] = [1.0, 1.0, 0.5, 0.5, 0.9]
        let mono = downmixToMono(interleaved: input, channelCount: 2)
        XCTAssertEqual(mono, [1.0, 0.5])
    }

    func testExtractStereoMonoDuplicates() {
        let input: [Float] = [0.1, 0.2, 0.3]
        let (L, R) = extractStereo(interleaved: input, channelCount: 1)
        XCTAssertEqual(L, input)
        XCTAssertEqual(R, input)
    }

    func testExtractStereoTwoChannelDeinterleaves() {
        // L=0.1, R=-0.1, L=0.2, R=-0.2
        let input: [Float] = [0.1, -0.1, 0.2, -0.2]
        let (L, R) = extractStereo(interleaved: input, channelCount: 2)
        XCTAssertEqual(L, [0.1, 0.2])
        XCTAssertEqual(R, [-0.1, -0.2])
    }

    func testExtractStereoSixChannelTakesFirstTwo() {
        // 5.1 layout: L, R, C, LFE, Ls, Rs
        let input: [Float] = [0.1, -0.1, 0, 0, 0, 0,
                              0.2, -0.2, 0, 0, 0, 0]
        let (L, R) = extractStereo(interleaved: input, channelCount: 6)
        XCTAssertEqual(L, [0.1, 0.2])
        XCTAssertEqual(R, [-0.1, -0.2])
    }

    func testExtractStereoEmpty() {
        let (L, R) = extractStereo(interleaved: [], channelCount: 2)
        XCTAssertTrue(L.isEmpty)
        XCTAssertTrue(R.isEmpty)
    }
}