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

final class NoteBandMapperTests: XCTestCase {
    private let fftSize = 4096
    private let sampleRate: Float = 48000

    private func binFor(_ hz: Float) -> Int { Int(hz * Float(fftSize) / sampleRate) }
    private func midiHz(_ n: Float) -> Float { 440 * powf(2, (n - 69) / 12) }

    /// A pure tone lands in the band of ITS note: 440 Hz is A4 (MIDI 69).
    func testPureToneLandsInItsNoteBand() {
        // C2 (MIDI 36), 6 octaves = 72 notes.
        let mapper = BandMapper(minMidiNote: 36, noteCount: 72,
                                fftSize: fftSize, sampleRate: sampleRate)
        var mags = [Float](repeating: 0, count: fftSize / 2)
        mags[binFor(440)] = 1.0
        let bands = mapper.bands(from: mags)
        XCTAssertEqual(bands.count, 72)
        let hot = bands.firstIndex(of: bands.max()!)!
        XCTAssertEqual(hot, 69 - 36, "440 Hz must land in A4's band")
    }

    /// Notes one octave apart map exactly 12 bands apart.
    func testOctaveSpacingIsTwelveBands() {
        let mapper = BandMapper(minMidiNote: 36, noteCount: 72,
                                fftSize: fftSize, sampleRate: sampleRate)
        var mags = [Float](repeating: 0, count: fftSize / 2)
        mags[binFor(880)] = 1.0  // A5, MIDI 81
        let bands = mapper.bands(from: mags)
        let hot = bands.firstIndex(of: bands.max()!)!
        XCTAssertEqual(hot, 81 - 36)
    }

    /// Below the FFT's semitone resolution, adjacent notes legitimately share
    /// bins: the mapper must smear (duplicate values) rather than misalign or
    /// crash. All bands stay finite and non-negative.
    func testSubResolutionNotesSmearGracefully() {
        let mapper = BandMapper(minMidiNote: 24, noteCount: 96,
                                fftSize: 2048, sampleRate: 48000)
        var mags = [Float](repeating: 0, count: 1024)
        for i in 1..<20 { mags[i] = Float(i) }
        let bands = mapper.bands(from: mags)
        XCTAssertEqual(bands.count, 96)
        for b in bands {
            XCTAssertTrue(b.isFinite)
            XCTAssertGreaterThanOrEqual(b, 0)
        }
    }
}

final class BandMapperTests: XCTestCase {
    func testProducesRequestedBandCount() {
        let mapper = BandMapper(bandCount: 24, fftSize: 2048, sampleRate: 48000)
        let mags = [Float](repeating: 0, count: 1024)
        XCTAssertEqual(mapper.bands(from: mags).count, 24)
    }

    func testEdgesAreMonotonicallyIncreasing() {
        let mapper = BandMapper(bandCount: 32, fftSize: 2048, sampleRate: 48000)
        for i in 1..<mapper.edges.count {
            XCTAssertGreaterThanOrEqual(mapper.edges[i], mapper.edges[i - 1])
        }
    }

    func testSpikeLightsUpExactlyOneBand() {
        let bandCount = 24
        let mapper = BandMapper(bandCount: bandCount, fftSize: 2048, sampleRate: 48000)

        var mags = [Float](repeating: 0, count: 1024)
        let spikeBin = 100
        mags[spikeBin] = 1.0

        let bands = mapper.bands(from: mags)

        // Find which band's [lo, hi) range contains the spike bin.
        var expectedBand = -1
        for i in 0..<(mapper.edges.count - 1) where spikeBin >= mapper.edges[i] && spikeBin < mapper.edges[i + 1] {
            expectedBand = i
        }
        XCTAssertGreaterThanOrEqual(expectedBand, 0, "spike bin should fall within mapped range")

        XCTAssertEqual(bands[expectedBand], 1.0, accuracy: 0.0001)
        for (i, v) in bands.enumerated() where i != expectedBand {
            XCTAssertEqual(v, 0, accuracy: 0.0001)
        }
    }
}