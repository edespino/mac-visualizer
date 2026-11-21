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

public struct ColorPalette: Equatable {
    public let stops: [RGBAColor]

    public init(stops: [RGBAColor]) {
        precondition(stops.count >= 2, "A palette needs at least two stops")
        self.stops = stops
    }

    /// Sample the gradient at position `t` in 0...1 (clamped). Stops are evenly spaced.
    public func sample(at t: Float) -> RGBAColor {
        let clamped = min(max(t, 0), 1)
        let segments = Float(stops.count - 1)
        let scaled = clamped * segments
        let lowerIndex = Int(scaled.rounded(.down))
        if lowerIndex >= stops.count - 1 { return stops[stops.count - 1] }
        let upperIndex = lowerIndex + 1
        let localT = scaled - Float(lowerIndex)
        return lerp(stops[lowerIndex], stops[upperIndex], localT)
    }

    private func lerp(_ a: RGBAColor, _ b: RGBAColor, _ t: Float) -> RGBAColor {
        RGBAColor(
            r: a.r + (b.r - a.r) * t,
            g: a.g + (b.g - a.g) * t,
            b: a.b + (b.b - a.b) * t,
            a: a.a + (b.a - a.a) * t
        )
    }
}

extension ColorPalette {
    /// Stops for the "classic" preset. Held separately so both the `presets`
    /// dictionary and the non-optional `fallback` can share one source of truth
    /// without either force-unwrapping a dictionary lookup.
    private static let classicStops: [RGBAColor] = [
        RGBAColor(r: 0.0, g: 0.8, b: 0.2, a: 1), // green
        RGBAColor(r: 0.9, g: 0.9, b: 0.0, a: 1), // yellow
        RGBAColor(r: 0.9, g: 0.1, b: 0.1, a: 1)  // red
    ]

    /// Non-optional fallback palette (the "classic" preset), constructed
    /// directly from `classicStops` rather than via a preset-name lookup. Use as
    /// `ColorPalette.preset(named: ...) ?? .fallback` so a missing or renamed
    /// preset can never crash the caller (no force-unwrap of a string literal).
    public static let fallback = ColorPalette(stops: classicStops)

    public static let presets: [String: ColorPalette] = [
        "classic": ColorPalette(stops: classicStops),
        "phosphor": ColorPalette(stops: [
            RGBAColor(r: 0.0, g: 0.15, b: 0.0, a: 1),
            RGBAColor(r: 0.2, g: 1.0, b: 0.3, a: 1)
        ]),
        "synthwave": ColorPalette(stops: [
            RGBAColor(r: 0.15, g: 0.0, b: 0.4, a: 1),
            RGBAColor(r: 0.9, g: 0.1, b: 0.6, a: 1),
            RGBAColor(r: 0.1, g: 0.9, b: 1.0, a: 1)
        ]),
        // Fire / heat ramp from libvisual's corona "Fire" palette. Punchy for
        // particles, fountain, fireworks.
        "inferno": ColorPalette(stops: [
            RGBAColor(r: 0.05, g: 0.0, b: 0.05, a: 1),
            RGBAColor(r: 0.6,  g: 0.0, b: 0.0,  a: 1),
            RGBAColor(r: 1.0,  g: 0.4, b: 0.0,  a: 1),
            RGBAColor(r: 1.8,  g: 1.4, b: 0.3,  a: 1),
            RGBAColor(r: 3.0,  g: 2.5, b: 1.5,  a: 1)
        ]),
        // Northern-lights gradient — teal → emerald → violet → magenta.
        // Distinctive cool palette that doesn't duplicate phosphor.
        "aurora": ColorPalette(stops: [
            RGBAColor(r: 0.02, g: 0.05, b: 0.12, a: 1),
            RGBAColor(r: 0.0,  g: 0.55, b: 0.55, a: 1),
            RGBAColor(r: 0.15, g: 0.95, b: 0.6,  a: 1),
            RGBAColor(r: 0.65, g: 0.5,  b: 1.4,  a: 1),
            RGBAColor(r: 1.7,  g: 1.1,  b: 2.4,  a: 1)
        ]),
        // Warm sunset / dusk — earthy alternative to synthwave's neon. Reads
        // well during quieter passages.
        "ember": ColorPalette(stops: [
            RGBAColor(r: 0.02, g: 0.0,  b: 0.0,  a: 1),
            RGBAColor(r: 0.62, g: 0.27, b: 0.20, a: 1),
            RGBAColor(r: 1.0,  g: 0.49, b: 0.38, a: 1),
            RGBAColor(r: 1.7,  g: 1.4,  b: 0.9,  a: 1),
            RGBAColor(r: 2.5,  g: 2.2,  b: 1.5,  a: 1)
        ]),
        // Cool ocean / glacier — fills the cold-blue slot the trio lacks.
        "ice": ColorPalette(stops: [
            RGBAColor(r: 0.0, g: 0.0, b: 0.18, a: 1),
            RGBAColor(r: 0.0, g: 0.3, b: 0.7, a: 1),
            RGBAColor(r: 0.0, g: 0.85, b: 1.0, a: 1),
            RGBAColor(r: 0.7, g: 0.97, b: 1.0, a: 1),
            RGBAColor(r: 1.0, g: 1.0, b: 1.0, a: 1)
        ]),
        // Pure grayscale on black — minimalist, gallery look. Pairs well with
        // high-energy content where color would be visual noise.
        "mono": ColorPalette(stops: [
            RGBAColor(r: 0.0, g: 0.0, b: 0.0, a: 1),
            RGBAColor(r: 0.25, g: 0.25, b: 0.27, a: 1),
            RGBAColor(r: 0.6, g: 0.6, b: 0.62, a: 1),
            RGBAColor(r: 0.92, g: 0.92, b: 0.95, a: 1),
            RGBAColor(r: 1.0, g: 1.0, b: 1.0, a: 1)
        ]),
        // --- Six additive palettes (appended; the eight above are unchanged). ---
        // matplotlib viridis: perceptually-uniform, colorblind-friendly.
        // dark indigo -> blue -> teal -> green -> yellow.
        "viridis": ColorPalette(stops: [
            RGBAColor(r: 0.26667, g: 0.00392, b: 0.32941, a: 1),
            RGBAColor(r: 0.23137, g: 0.32157, b: 0.54510, a: 1),
            RGBAColor(r: 0.12941, g: 0.56863, b: 0.54902, a: 1),
            RGBAColor(r: 0.36863, g: 0.78824, b: 0.38431, a: 1),
            RGBAColor(r: 0.99216, g: 0.90588, b: 0.14510, a: 1)
        ]),
        // matplotlib plasma: indigo -> magenta -> orange -> gold. A different
        // curve from synthwave/inferno.
        "plasma": ColorPalette(stops: [
            RGBAColor(r: 0.05098, g: 0.03137, b: 0.52941, a: 1),
            RGBAColor(r: 0.80000, g: 0.27843, b: 0.47059, a: 1),
            RGBAColor(r: 0.97255, g: 0.58431, b: 0.25098, a: 1),
            RGBAColor(r: 0.94118, g: 0.97647, b: 0.12941, a: 1)
        ]),
        // Full rainbow hue sweep: red -> yellow -> green -> cyan -> blue -> violet.
        "spectrum": ColorPalette(stops: [
            RGBAColor(r: 1.0, g: 0.0, b: 0.0, a: 1),
            RGBAColor(r: 1.0, g: 1.0, b: 0.0, a: 1),
            RGBAColor(r: 0.0, g: 1.0, b: 0.0, a: 1),
            RGBAColor(r: 0.0, g: 1.0, b: 1.0, a: 1),
            RGBAColor(r: 0.0, g: 0.0, b: 1.0, a: 1),
            RGBAColor(r: 1.0, g: 0.0, b: 1.0, a: 1)
        ]),
        // Soft low-saturation multi-hue: rose -> peach -> mint -> periwinkle.
        // The only desaturated palette.
        "pastel": ColorPalette(stops: [
            RGBAColor(r: 0.84, g: 0.50, b: 0.58, a: 1),
            RGBAColor(r: 0.85, g: 0.62, b: 0.43, a: 1),
            RGBAColor(r: 0.48, g: 0.82, b: 0.60, a: 1),
            RGBAColor(r: 0.50, g: 0.56, b: 0.85, a: 1)
        ]),
        // Muted greens + earthy browns + moss. The only natural/earthy palette.
        "forest": ColorPalette(stops: [
            RGBAColor(r: 0.10588, g: 0.22745, b: 0.10588, a: 1),
            RGBAColor(r: 0.18039, g: 0.36471, b: 0.20392, a: 1),
            RGBAColor(r: 0.41569, g: 0.65882, b: 0.30980, a: 1),
            RGBAColor(r: 0.47843, g: 0.32157, b: 0.18824, a: 1)
        ]),
        // Deep navy -> deep teal -> aqua. Greener and deeper than `ice`.
        "oceanic": ColorPalette(stops: [
            RGBAColor(r: 0.00392, g: 0.12549, b: 0.21961, a: 1),
            RGBAColor(r: 0.00784, g: 0.30196, b: 0.36078, a: 1),
            RGBAColor(r: 0.16863, g: 0.76863, b: 0.78824, a: 1)
        ])
    ]

    public static func preset(named name: String) -> ColorPalette? {
        presets[name]
    }

    /// Crossfade two palettes into one effective palette by mix factor `t`.
    /// Component-wise lerp of the stop arrays; `t` is clamped to `0...1`.
    /// `t == 0` returns `a` exactly and `t == 1` returns `b` exactly (exact
    /// branch, not float-rounded) — this keeps the auto-cycle a true passthrough
    /// when not mid-fade (value preservation). Pure: allocates only the result.
    public static func blend(_ a: ColorPalette, _ b: ColorPalette, _ t: Double) -> ColorPalette {
        let tt = min(max(t, 0), 1)
        if tt == 0 { return a }
        if tt == 1 { return b }
        let f = Float(tt)
        let mixed = zip(a.stops, b.stops).map { ca, cb in
            RGBAColor(r: ca.r + (cb.r - ca.r) * f,
                      g: ca.g + (cb.g - ca.g) * f,
                      b: ca.b + (cb.b - ca.b) * f,
                      a: ca.a + (cb.a - ca.a) * f)
        }
        return ColorPalette(stops: mixed)
    }

    /// Stable ordering used by palette-cycling shortcuts. `presets` is a
    /// dictionary (no defined order), so we keep a separate ordered list.
    public static let orderedPresetNames: [String] = [
        "classic", "phosphor", "synthwave",
        "inferno", "aurora", "ember", "ice", "mono",
        // Appended after `mono` (existing order preserved).
        "viridis", "plasma", "spectrum", "pastel", "forest", "oceanic"
    ]
}
