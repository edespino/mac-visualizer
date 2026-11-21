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

enum SignalGenerators {
    /// A pure sine wave of `frequency` Hz at `sampleRate`, `count` samples, amplitude 1.
    static func sine(frequency: Float, sampleRate: Float, count: Int) -> [Float] {
        (0..<count).map { i in
            sinf(2 * .pi * frequency * Float(i) / sampleRate)
        }
    }

    static func silence(count: Int) -> [Float] {
        [Float](repeating: 0, count: count)
    }

    /// Index of the maximum value in `values`.
    static func argmax(_ values: [Float]) -> Int {
        var best = 0
        var bestVal = -Float.greatestFiniteMagnitude
        for (i, v) in values.enumerated() where v > bestVal {
            bestVal = v; best = i
        }
        return best
    }
}