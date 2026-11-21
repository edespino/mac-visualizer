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

/// Generates deterministic, animated `AudioFrame`s so the renderer has lively
/// input before real audio capture exists. `frame(at:)` is a pure function of time.
public struct SyntheticFrameSource {
    public let bandCount: Int

    public init(bandCount: Int) {
        precondition(bandCount > 0, "bandCount must be positive")
        self.bandCount = bandCount
    }

    public func frame(at t: TimeInterval) -> AudioFrame {
        let tf = Float(t)
        let twoPi: Float = 2 * .pi
        var bands = [Float](repeating: 0, count: bandCount)

        // A sweeping Gaussian bump plus a per-band oscillation, clamped to [0,1].
        let sweepCenter = (sinf(tf * 0.7) * 0.5 + 0.5) * Float(max(bandCount - 1, 1))
        let sigma: Float = 2

        for i in 0..<bandCount {
            let phase = Float(i) / Float(bandCount) * twoPi
            let oscillation = 0.5 + 0.5 * sinf(tf * 2.0 + phase)
            let dist = Float(i) - sweepCenter
            let bump = expf(-(dist * dist) / (2 * sigma * sigma))
            let level = 0.12 + 0.45 * oscillation + 0.5 * bump
            bands[i] = min(max(level, 0), 1)
        }

        let peak = bands.max() ?? 0
        let sumSquares = bands.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = (bands.isEmpty ? 0 : sqrtf(sumSquares / Float(bandCount)))
        let bandPeaks = bands.map { min($0 + 0.05, 1) }

        let wavePoints = 256
        var wave = [Float](repeating: 0, count: wavePoints)
        for j in 0..<wavePoints {
            let p = Float(j) / Float(wavePoints)
            wave[j] = 0.6 * sinf(tf * 3 + p * 2 * .pi * 3) * (0.5 + 0.5 * sinf(tf * 1.3))
        }

        return AudioFrame(bands: bands, bandPeaks: bandPeaks, waveform: wave, rms: rms, peak: peak, timestamp: t)
    }
}