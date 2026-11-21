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

/// Computes the magnitude spectrum of a real, already-windowed signal using vDSP.
/// Not thread-safe; use one instance per analysis queue.
final class FFTProcessor {
    private let n: Int
    private let halfN: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var realp: [Float]
    private var imagp: [Float]

    init(size: Int) {
        precondition(size > 0 && (size & (size - 1)) == 0, "FFT size must be a power of two")
        self.n = size
        self.halfN = size / 2
        self.log2n = vDSP_Length(log2(Float(size)))
        self.setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        self.realp = [Float](repeating: 0, count: halfN)
        self.imagp = [Float](repeating: 0, count: halfN)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// Returns `size/2` magnitudes for a real input of length `size`.
    func magnitudes(of input: [Float]) -> [Float] {
        precondition(input.count == n, "Input length must equal FFT size")
        var output = [Float](repeating: 0, count: halfN)

        realp.withUnsafeMutableBufferPointer { rp in
            imagp.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)

                input.withUnsafeBufferPointer { inPtr in
                    inPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { typed in
                        vDSP_ctoz(typed, 2, &split, 1, vDSP_Length(halfN))
                    }
                }

                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &output, 1, vDSP_Length(halfN))
            }
        }

        // Normalize by FFT size so magnitudes are independent of `size`.
        // Write to a separate buffer to avoid overlapping access on `output`.
        var scaled = [Float](repeating: 0, count: halfN)
        var scale: Float = 1.0 / Float(n)
        vDSP_vsmul(output, 1, &scale, &scaled, 1, vDSP_Length(halfN))
        return scaled
    }
}