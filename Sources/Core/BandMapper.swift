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

/// Reduces a linear magnitude spectrum into log-frequency-spaced bands.
/// Each band's value is the max magnitude across its bin range.
struct BandMapper {
    /// `bandCount + 1` bin indices delimiting each band's [lo, hi) range.
    let edges: [Int]

    init(bandCount: Int, fftSize: Int, sampleRate: Float, minHz: Float = 30, maxHz: Float = 16000) {
        precondition(bandCount > 0)
        let nyquistBins = fftSize / 2
        let minBin = max(1, Int(minHz * Float(fftSize) / sampleRate))
        let maxBin = min(nyquistBins, Int(maxHz * Float(fftSize) / sampleRate))
        let safeMaxBin = max(maxBin, minBin + bandCount)

        let logMin = log(Float(minBin))
        let logMax = log(Float(safeMaxBin))

        var computed = [Int]()
        computed.reserveCapacity(bandCount + 1)
        for i in 0...bandCount {
            let t = Float(i) / Float(bandCount)
            let bin = Int(exp(logMin + (logMax - logMin) * t).rounded())
            computed.append(min(max(bin, minBin), safeMaxBin))
        }
        // Guarantee strictly non-decreasing, with each band at least one bin wide.
        for i in 1..<computed.count where computed[i] <= computed[i - 1] {
            computed[i] = computed[i - 1] + 1
        }
        self.edges = computed
    }

    /// Note-aligned mapper: one band per semitone, edges at the frequency
    /// boundaries halfway between adjacent notes (f(n ± 0.5) in equal
    /// temperament, A4 = MIDI 69 = 440 Hz). Unlike the log-spaced init, edges
    /// are NOT forced strictly increasing: below the FFT's semitone resolution
    /// adjacent notes legitimately share bins, and `bands(from:)`'s
    /// `hi = max(lo + 1)` floor makes those notes read the same bin — a
    /// graceful smear instead of a misaligned stairstep. (A constant-Q
    /// transform would resolve them properly; this is the honest linear-FFT
    /// approximation.)
    init(minMidiNote: Int, noteCount: Int, fftSize: Int, sampleRate: Float) {
        precondition(noteCount > 0)
        let nyquistBins = fftSize / 2
        func hz(_ midi: Float) -> Float { 440 * powf(2, (midi - 69) / 12) }
        var computed = [Int]()
        computed.reserveCapacity(noteCount + 1)
        for i in 0...noteCount {
            let boundary = hz(Float(minMidiNote + i) - 0.5)
            let bin = Int((boundary * Float(fftSize) / sampleRate).rounded())
            computed.append(min(max(bin, 1), nyquistBins))
        }
        self.edges = computed
    }

    func bands(from magnitudes: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: edges.count - 1)
        for i in 0..<out.count {
            let lo = edges[i]
            let hi = max(edges[i + 1], lo + 1)
            var peak: Float = 0
            var b = lo
            while b < hi && b < magnitudes.count {
                peak = max(peak, magnitudes[b])
                b += 1
            }
            out[i] = peak
        }
        return out
    }
}