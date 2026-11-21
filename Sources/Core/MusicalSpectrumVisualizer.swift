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
import simd

/// Musical Spectrum: one bar per semitone, grouped into octaves with a wider
/// gap between octaves, colored by PITCH CLASS — the same note in every octave
/// shares its color, so chords and keys read as repeating color patterns.
/// The note-aligned band data comes from the analyzer's `.notes` band mapping
/// (RenderModel switches the mapping on while this style is active); with any
/// other band source the bars still render, grouped by 12 from the left.
///
/// Original implementation; the note-aligned-spectrum concept follows
/// ShowCQTBar-style displays, with the octave/pitch-class band mapping
/// referenced from clubber (MIT) — no source code from either was used.
///
/// Knobs (top-level settings; clamps live at the read sites):
///   - `musicalStartOctave` first octave, C-based (2 default = C2, clamp 0...5)
///     — consumed by RenderModel to configure the analyzer's note range
///   - `musicalOctaveCount` octaves displayed (6 default, clamp 1...8) — ditto
///   - `musicalBarGap` gap as a fraction of the bar cell (0.2 default, clamp 0...0.9)
///   - `musicalOctaveGap` EXTRA gap between octaves in cell widths (0.5 default, clamp 0...2)
///   - `musicalPitchClassColoring` color by note-within-octave vs by level (true default)
///   - `musicalColorFloor` minimum brightness for quiet bars (0.15 default, clamp 0...1)
///   - `musicalAlpha` bar opacity (1.0 default, clamp 0...1)
public struct MusicalSpectrumVisualizer: Visualizer {
    public init() {}

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings,
                             palette: ColorPalette, aspect: Float) -> [BarVertex] {
        let bands = frame.bands
        guard !bands.isEmpty else { return [] }
        let n = bands.count

        let gapFraction = min(0.9, max(0, Float(settings.musicalBarGap)))
        let octaveGap = min(2, max(0, Float(settings.musicalOctaveGap)))
        let pitchClassColoring = settings.musicalPitchClassColoring
        let colorFloor = min(1, max(0, Float(settings.musicalColorFloor)))
        let alpha = min(1, max(0, Float(settings.musicalAlpha)))

        // Horizontal layout over [-0.98, 0.98]: n cells plus an extra
        // `octaveGap` cell-fraction before every full octave boundary.
        let octaveBreaks = (n - 1) / 12   // boundaries strictly inside the range
        let totalCells = Float(n) + octaveGap * Float(octaveBreaks)
        let width: Float = 1.96
        let cell = width / max(totalCells, 1)
        let barHalf = cell * (1 - gapFraction) / 2

        let baseY: Float = -1
        let maxHeight: Float = 2

        var verts: [BarVertex] = []
        verts.reserveCapacity(n * 6)
        var x = -0.98 + cell / 2
        for i in 0..<n {
            if i > 0 && i % 12 == 0 { x += octaveGap * cell }
            defer { x += cell }

            let level = min(1, max(0, bands[i]))
            let c: RGBAColor
            if pitchClassColoring {
                // Same pitch class = same palette position in every octave;
                // level modulates brightness above the floor so quiet notes
                // stay legible without washing out the class identity.
                let classPos = Float(i % 12) / 11
                let base = palette.sample(at: classPos)
                let bright = max(colorFloor, level)
                c = RGBAColor(r: base.r * bright, g: base.g * bright, b: base.b * bright, a: 1)
            } else {
                c = palette.sample(at: max(colorFloor, level))
            }
            let color = SIMD4<Float>(c.r, c.g, c.b, alpha)

            let x0 = x - barHalf
            let x1 = x + barHalf
            let y0 = baseY
            let y1 = min(1, baseY + level * maxHeight)
            let bl = BarVertex(position: SIMD4<Float>(x0, y0, 0, 1), color: color)
            let tl = BarVertex(position: SIMD4<Float>(x0, y1, 0, 1), color: color)
            let br = BarVertex(position: SIMD4<Float>(x1, y0, 0, 1), color: color)
            let tr = BarVertex(position: SIMD4<Float>(x1, y1, 0, 1), color: color)
            verts.append(contentsOf: [bl, br, tl, br, tr, tl])
        }
        return verts
    }
}
