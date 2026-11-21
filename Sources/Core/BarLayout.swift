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

/// Pure horizontal layout: maps a bar index to its normalized [0,1] x-extent.
/// Bars are evenly spaced; `gapFraction` is the portion of each slot left as a gap.
public struct BarLayout: Equatable {
    public let barCount: Int
    public let gapFraction: Float

    public init(barCount: Int, gapFraction: Float = 0.2) {
        precondition(barCount > 0, "barCount must be positive")
        precondition(gapFraction >= 0 && gapFraction < 1, "gapFraction must be in [0,1)")
        self.barCount = barCount
        self.gapFraction = gapFraction
    }

    /// Normalized [0,1] horizontal extent of the bar at `index`, centered in its slot.
    public func barXRange(_ index: Int) -> (start: Float, end: Float) {
        let slot = 1 / Float(barCount)
        let gap = slot * gapFraction
        let start = Float(index) * slot + gap / 2
        let end = Float(index + 1) * slot - gap / 2
        return (start, end)
    }
}