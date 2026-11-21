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

import XCTest
@testable import MacVisualizerCore

/// Guards the palette-crossfade-for-CPU-styles change two ways:
///
///  1. PARITY (value preservation): emitting through the new palette-aware path
///     with `palette = ColorPalette.preset(named: settings.paletteName)` — exactly
///     what `effectivePalette()` returns when NOT mid-fade — must reproduce the
///     pre-change vertices BIT-FOR-BIT (frozen golden `(count, hash)`). If this
///     fails the substitution wasn't value-preserving; the fix is to correct the
///     code, never the golden.
///
///  2. PROPAGATION: injecting a deliberately distinct palette (while
///     `settings.paletteName` is unchanged) must change the emitted vertex colors,
///     proving CPU styles now honor the injected (blended-during-fade) palette
///     rather than re-deriving it from the settings name.
final class PaletteCrossfadeParityTests: XCTestCase {

    /// Feature-off output is byte-identical to pre-change for every CPU visualizer.
    func testFeatureOffParityIsBitIdentical() {
        for c in PaletteFixtures.cases {
            guard let golden = PaletteFixtures.goldens[c.name] else {
                XCTFail("missing golden for \(c.name)"); continue
            }
            let verts = PaletteFixtures.emit(c, palette: "classic")
            XCTAssertEqual(verts.count, golden.count, "\(c.name): vertex count drifted")
            XCTAssertEqual(PaletteFixtures.hash(verts), golden.hash,
                           "\(c.name): vertices differ from pre-change golden — substitution not value-preserving")
        }
    }

    /// The injected palette actually colors the geometry — and ONLY the color.
    /// Feeding `spectrum` instead of `classic` (with `settings.paletteName` fixed
    /// at "classic") must, per scenario: (a) keep the vertex COUNT identical,
    /// (b) leave every POSITION lane byte-identical (the palette must never move
    /// geometry), and (c) change at least one COLOR lane somewhere. Isolating
    /// color from position is a stronger, less fragile signal than a bare hash
    /// compare. A scenario that emits zero color difference is a real partial
    /// hard-cut — the assertion fails loudly rather than being weakened.
    func testInjectedPalettePropagatesToColors() {
        let classic = ColorPalette.preset(named: "classic") ?? .fallback
        let spectrum = ColorPalette.preset(named: "spectrum") ?? .fallback
        for c in PaletteFixtures.cases {
            let baseline = PaletteFixtures.emit(c, settingsPalette: "classic", injected: classic)
            let injected = PaletteFixtures.emit(c, settingsPalette: "classic", injected: spectrum)

            // (a) geometry count unchanged.
            XCTAssertEqual(baseline.count, injected.count,
                           "\(c.name): vertex count changed with palette — palette must not alter geometry")

            // (b) every position lane byte-identical; (c) track any color-lane diff.
            var anyColorDiff = false
            for (i, pair) in zip(baseline, injected).enumerated() {
                let (b, inj) = pair
                XCTAssertEqual(b.position.x.bitPattern, inj.position.x.bitPattern, "\(c.name) vert \(i): position.x moved")
                XCTAssertEqual(b.position.y.bitPattern, inj.position.y.bitPattern, "\(c.name) vert \(i): position.y moved")
                XCTAssertEqual(b.position.z.bitPattern, inj.position.z.bitPattern, "\(c.name) vert \(i): position.z moved")
                XCTAssertEqual(b.position.w.bitPattern, inj.position.w.bitPattern, "\(c.name) vert \(i): position.w moved")
                if b.color.x.bitPattern != inj.color.x.bitPattern ||
                   b.color.y.bitPattern != inj.color.y.bitPattern ||
                   b.color.z.bitPattern != inj.color.z.bitPattern ||
                   b.color.w.bitPattern != inj.color.w.bitPattern {
                    anyColorDiff = true
                }
            }
            // (c) at least one color lane differs somewhere.
            XCTAssertTrue(anyColorDiff,
                          "\(c.name): injected palette changed no color — a palette lookup still hard-cuts")
        }
    }

    /// A mid-fade blended palette (50% classic→spectrum) lands strictly between
    /// the endpoints — the gradual crossfade the feature delivers. Sampled on the
    /// simplest visualizer where the bottom-row color equals `palette.sample(0)`.
    func testBlendedPaletteProducesIntermediateColors() {
        let classic = ColorPalette.preset(named: "classic") ?? .fallback
        let spectrum = ColorPalette.preset(named: "spectrum") ?? .fallback
        let blended = ColorPalette.blend(classic, spectrum, 0.5)
        let bars = PaletteFixtures.cases.first { $0.name == "SpectrumBars" }!

        let a = PaletteFixtures.hash(PaletteFixtures.emit(bars, settingsPalette: "classic", injected: classic))
        let b = PaletteFixtures.hash(PaletteFixtures.emit(bars, settingsPalette: "classic", injected: spectrum))
        let mid = PaletteFixtures.hash(PaletteFixtures.emit(bars, settingsPalette: "classic", injected: blended))
        // The blended frame differs from both pure endpoints (a true in-between).
        XCTAssertNotEqual(mid, a, "blended palette should differ from the classic endpoint")
        XCTAssertNotEqual(mid, b, "blended palette should differ from the spectrum endpoint")
    }
}
