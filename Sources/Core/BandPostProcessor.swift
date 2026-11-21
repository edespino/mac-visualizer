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

/// Stateful per-band post-processing: dB-normalize, gain, exponential smoothing, peak-hold.
/// One instance per analyzer; call `process` once per audio frame.
final class BandPostProcessor {
    var gain: Float
    /// 0 = no smoothing (use current), →1 = very smooth (mostly previous).
    var smoothing: Float
    /// Per-frame multiplicative decay applied to held peaks.
    var peakDecay: Float

    private let floorDb: Float = -80
    private let refDb: Float = 0
    private var smoothed: [Float]
    private var peaks: [Float]

    init(bandCount: Int, gain: Float, smoothing: Float, peakDecay: Float = 0.95) {
        self.gain = gain
        self.smoothing = smoothing
        self.peakDecay = peakDecay
        self.smoothed = [Float](repeating: 0, count: bandCount)
        self.peaks = [Float](repeating: 0, count: bandCount)
    }

    func process(_ rawMagnitudes: [Float]) -> (bands: [Float], peaks: [Float]) {
        let count = min(rawMagnitudes.count, smoothed.count)
        var bands = [Float](repeating: 0, count: count)

        for i in 0..<count {
            // magnitude -> dB
            let db = 20 * log10(max(rawMagnitudes[i], 1e-9))
            // normalize to 0...1 against the noise floor
            let normalized = min(max((db - floorDb) / (refDb - floorDb), 0), 1)
            // gain (linear below saturation), clamped
            let gained = min(max(normalized * gain, 0), 1)
            // exponential smoothing
            smoothed[i] = smoothing * smoothed[i] + (1 - smoothing) * gained
            // peak-hold
            peaks[i] = max(peaks[i] * peakDecay, smoothed[i])
            bands[i] = smoothed[i]
        }

        return (bands, Array(peaks[0..<count]))
    }
}