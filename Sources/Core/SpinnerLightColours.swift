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
import simd

// Light colours of the Tri-wing: the setting (original colours or follow the app's palette) and the pure palette sampling
// that turns the current palette into the three wings' light colours.

/// Where the Tri-wing's edge lights take their colours from.
public enum SpinnerLightColors: String, Codable, CaseIterable {
    /// The three fixed wing colours (green, blue, orange).
    case original
    /// Three colours sampled from the app's current (effective) palette.
    case palette

    public var displayName: String {
        switch self {
        case .original: return "Original"
        case .palette: return "Follow palette"
        }
    }

    /// The next choice, wrapping after the last.
    public var next: SpinnerLightColors {
        let all = SpinnerLightColors.allCases
        let i: Int = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }
}

/// Pure helpers for `SpinnerLightColors.palette`. The colours returned are "wing colours" in the same sense as the
/// renderer's three fixed ones (brightest channel 1, not yet saturation-lifted): the renderer applies to them exactly the
/// per-part treatment it applies to the originals (the saturation lift of `twLightColor`, the ring and side-band
/// treatments), so a palette that happened to contain the original colours would light the Tri-wing as before.
public enum TriWingLightColours {

    /// Positions along the palette sampled for wing 0, 1 and 2: far apart so a typical palette gives three colours.
    public static let samplePositions: [Float] = [0.15, 0.50, 0.85]

    /// Step of the quantised colour (1/64 per channel): a slow crossfade changes the quantised value only every few frames.
    public static let quantum: Float = 1.0 / 64.0

    /// Scales `c` so its brightest channel is 1 (hue, meaning the channel ratios, is kept: a grey stays grey, so a grey
    /// palette gives white lights and no hue is invented). Negative channels count as 0. A black, non-finite or
    /// vanishingly dark colour becomes white.
    public static func condition(_ c: SIMD3<Float>) -> SIMD3<Float> {
        if !(c.x.isFinite && c.y.isFinite && c.z.isFinite) { return SIMD3<Float>(1, 1, 1) }
        let r: Float = max(c.x, 0)
        let g: Float = max(c.y, 0)
        let b: Float = max(c.z, 0)
        let m: Float = max(r, max(g, b))
        if m < 1e-4 { return SIMD3<Float>(1, 1, 1) }
        return SIMD3<Float>(r / m, g / m, b / m)
    }

    /// The three wing colours of `palette`: it is sampled at `samplePositions` and each sample conditioned.
    public static func wingColours(from palette: ColorPalette) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        for p in samplePositions {
            let s: RGBAColor = palette.sample(at: p)
            out.append(condition(SIMD3<Float>(s.r, s.g, s.b)))
        }
        return out
    }

    /// Each channel snapped to `quantum` (the brightest channel stays exactly 1 because 1 is a multiple of the step).
    public static func quantised(_ colours: [SIMD3<Float>]) -> [SIMD3<Float>] {
        colours.map { (c: SIMD3<Float>) -> SIMD3<Float> in
            SIMD3<Float>((c.x / quantum).rounded() * quantum, (c.y / quantum).rounded() * quantum, (c.z / quantum).rounded() * quantum)
        }
    }

    /// The swept light ring's colour for a wing colour: normalised, saturation lifted 1.25 and normalised again (the
    /// treatment `TriWingSmear.glowRing` gives the originals).
    public static func ringColour(_ raw: SIMD3<Float>) -> SIMD3<Float> {
        func norm(_ c: SIMD3<Float>) -> SIMD3<Float> {
            let m: Float = max(c.x, max(c.y, c.z))
            return m > 1e-6 ? c / m : c
        }
        return norm(TriWingSwept.liftSaturation(norm(raw), 1.25))
    }
}
