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
import Accelerate

/// FFT analysis-window choices. Higher-quality windows (Hann/Hamming/Blackman)
/// reduce spectral leakage between adjacent frequency bins at the cost of
/// slight resolution loss. Rectangular is "no window" — the default for many
/// quick-and-dirty FFTs and what you get if you skip the multiplication.
public enum FFTWindow: String, Codable, CaseIterable {
    case rectangular, hann, hamming, blackman

    public var displayName: String {
        switch self {
        case .rectangular: return "Rectangular"
        case .hann:        return "Hann"
        case .hamming:     return "Hamming"
        case .blackman:    return "Blackman"
        }
    }
}

/// Build a window of the given length. The result is multiplied element-wise
/// into the time-domain samples before the FFT.
func makeWindow(_ kind: FFTWindow, count: Int) -> [Float] {
    var w = [Float](repeating: 0, count: count)
    switch kind {
    case .rectangular:
        for i in 0..<count { w[i] = 1 }
    case .hann:
        vDSP_hann_window(&w, vDSP_Length(count), Int32(vDSP_HANN_DENORM))
    case .hamming:
        vDSP_hamm_window(&w, vDSP_Length(count), 0)
    case .blackman:
        vDSP_blkman_window(&w, vDSP_Length(count), 0)
    }
    return w
}

/// Convenience for existing callers — preserved for backwards compat.
func makeHannWindow(_ count: Int) -> [Float] {
    return makeWindow(.hann, count: count)
}