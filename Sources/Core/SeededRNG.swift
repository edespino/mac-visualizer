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
/// Deterministic xorshift64 RNG used by the stateful visualizers + DemoAudioSource.
/// Single internal copy shared across the module; was previously duplicated
/// inside each consumer as `private struct SeededRNG`.
///
/// - `nextU64()` advances the state and returns the raw UInt64 — useful when a
///   caller needs full 64-bit entropy (e.g. seeding per-wave noise sub-streams).
/// - `nextUnit()` returns a Float in `[0, 1)` (24-bit mantissa from the high
///   24 bits of the state).
/// - `nextSigned()` returns a Float in `[-1, +1)`.
struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        // A zero seed leaves xorshift permanently zero. Substitute the golden-
        // ratio constant — same fix every prior copy used.
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func nextU64() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func nextUnit() -> Float {
        return Float(nextU64() >> 40) / Float(1 << 24)
    }

    mutating func nextSigned() -> Float {
        return nextUnit() * 2 - 1
    }
}