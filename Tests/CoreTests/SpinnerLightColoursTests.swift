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
import simd
@testable import MacVisualizerCore

final class SpinnerLightColoursTests: XCTestCase {

    private func decode(_ json: String) throws -> SpinnerSettings {
        try JSONDecoder().decode(SpinnerSettings.self, from: Data(json.utf8))
    }

    // MARK: Setting

    func testDefaultIsOriginal() {
        XCTAssertEqual(SpinnerSettings().lightColors, .original)
        XCTAssertEqual(SpinnerSettings.defaults.lightColors, .original)
    }

    func testRawValuesNamesAndNext() {
        XCTAssertEqual(SpinnerLightColors.original.rawValue, "original")
        XCTAssertEqual(SpinnerLightColors.palette.rawValue, "palette")
        XCTAssertEqual(SpinnerLightColors.allCases.count, 2)
        XCTAssertEqual(SpinnerLightColors.original.displayName, "Original")
        XCTAssertEqual(SpinnerLightColors.palette.displayName, "Follow palette")
        XCTAssertEqual(SpinnerLightColors.original.next, .palette)
        XCTAssertEqual(SpinnerLightColors.palette.next, .original)
    }

    func testRoundTrip() throws {
        var s = SpinnerSettings()
        s.lightColors = .palette
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(SpinnerSettings.self, from: data).lightColors, .palette)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"lightColors\":\"palette\""))
    }

    func testUnknownStringFallsBackToOriginal() throws {
        XCTAssertEqual(try decode("{\"lightColors\":\"neon\"}").lightColors, .original)
    }

    func testLegacyJSONWithoutKeyDecodesToOriginal() throws {
        XCTAssertEqual(try decode("{\"model\":\"triWing\"}").lightColors, .original)
    }

    func testStyleProfileEqualityNoticesLightColours() {
        var a = SpinnerSettings()
        let b = SpinnerSettings()
        a.lightColors = .palette
        XCTAssertNotEqual(a, b)
    }

    // MARK: Palette sampling

    private func maxChannel(_ c: SIMD3<Float>) -> Float { max(c.x, max(c.y, c.z)) }
    private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { simd_length(a - b) }

    func testSamplePositionsAreThreeAndSeparated() {
        let p = TriWingLightColours.samplePositions
        XCTAssertEqual(p.count, 3)
        XCTAssertEqual(p, p.sorted())
        XCTAssertGreaterThanOrEqual(p[1] - p[0], 0.3)
        XCTAssertGreaterThanOrEqual(p[2] - p[1], 0.3)
    }

    func testConditionScalesBrightestChannelToOne() {
        let c = TriWingLightColours.condition(SIMD3<Float>(0.2, 0.1, 0.05))
        XCTAssertEqual(maxChannel(c), 1, accuracy: 1e-6)
        XCTAssertEqual(c.y / c.x, 0.5, accuracy: 1e-5)   // hue (channel ratios) is kept
        XCTAssertEqual(c.z / c.x, 0.25, accuracy: 1e-5)
        let hdr = TriWingLightColours.condition(SIMD3<Float>(3.0, 2.5, 1.5))
        XCTAssertEqual(maxChannel(hdr), 1, accuracy: 1e-6)
    }

    func testConditionNeverInventsHueForGrey() {
        let g = TriWingLightColours.condition(SIMD3<Float>(0.3, 0.3, 0.3))
        XCTAssertEqual(g.x, g.y, accuracy: 1e-6)
        XCTAssertEqual(g.y, g.z, accuracy: 1e-6)
        XCTAssertEqual(maxChannel(g), 1, accuracy: 1e-6)
    }

    func testConditionBlackOrInvalidIsWhite() {
        for bad in [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1e-9, 0, 0), SIMD3<Float>(Float.nan, 0.2, 0.1)] {
            let c = TriWingLightColours.condition(bad)
            XCTAssertEqual(c, SIMD3<Float>(1, 1, 1))
        }
    }

    func testClassicPaletteGivesThreeDistinctBrightColours() {
        let c = TriWingLightColours.wingColours(from: ColorPalette.preset(named: "classic")!)
        XCTAssertEqual(c.count, 3)
        for k in c { XCTAssertEqual(maxChannel(k), 1, accuracy: 1e-5) }
        XCTAssertGreaterThan(distance(c[0], c[1]), 0.2)
        XCTAssertGreaterThan(distance(c[1], c[2]), 0.2)
        XCTAssertGreaterThan(distance(c[0], c[2]), 0.2)
    }

    func testRainbowAndSynthwaveGiveThreeDistinctColours() {
        for name in ["spectrum", "synthwave", "aurora", "inferno"] {
            let c = TriWingLightColours.wingColours(from: ColorPalette.preset(named: name)!)
            XCTAssertGreaterThan(distance(c[0], c[1]), 0.15, name)
            XCTAssertGreaterThan(distance(c[1], c[2]), 0.15, name)
            XCTAssertGreaterThan(distance(c[0], c[2]), 0.15, name)
        }
    }

    func testGreyPalettesGiveNearWhiteLights() {
        let c = TriWingLightColours.wingColours(from: ColorPalette.preset(named: "mono")!)
        for k in c {
            XCTAssertEqual(maxChannel(k), 1, accuracy: 1e-5)
            XCTAssertGreaterThan(min(k.x, min(k.y, k.z)), 0.9)   // white-ish, no invented hue
        }
    }

    func testEveryPresetGivesFiniteConditionedColours() {
        for name in ColorPalette.orderedPresetNames {
            let c = TriWingLightColours.wingColours(from: ColorPalette.preset(named: name)!)
            XCTAssertEqual(c.count, 3, name)
            for k in c {
                XCTAssertTrue(k.x.isFinite && k.y.isFinite && k.z.isFinite, name)
                XCTAssertEqual(maxChannel(k), 1, accuracy: 1e-5, name)
                XCTAssertGreaterThanOrEqual(min(k.x, min(k.y, k.z)), 0, name)
            }
        }
    }

    func testQuantisedSnapsToTheQuantum() {
        let q = TriWingLightColours.quantised([SIMD3<Float>(0.5001, 0.2503, 1.0)])[0]
        let step: Float = TriWingLightColours.quantum
        for v in [q.x, q.y, q.z] { XCTAssertEqual((v / step).rounded() * step, v, accuracy: 1e-6) }
        XCTAssertEqual(maxChannel(q), 1, accuracy: 1e-6)
        // Two colours closer than half a step quantise to the same value (so a slow crossfade does not touch materials).
        let a = TriWingLightColours.quantised([SIMD3<Float>(0.5, 0.5, 1)])
        let b = TriWingLightColours.quantised([SIMD3<Float>(0.5 + step * 0.2, 0.5, 1)])
        XCTAssertEqual(a, b)
    }

    func testRingColourIsBrightSaturatedAndKeepsGrey() {
        let r = TriWingLightColours.ringColour(SIMD3<Float>(0.25, 1.0, 0.45))
        XCTAssertEqual(maxChannel(r), 1, accuracy: 1e-5)
        XCTAssertLessThan(r.x, 0.25)
        let w = TriWingLightColours.ringColour(SIMD3<Float>(1, 1, 1))
        XCTAssertEqual(w, SIMD3<Float>(1, 1, 1))
    }

    // MARK: Swept light rings per wing

    func testGlowRingWingsSumToTheRingOpacityAndSplitIntoBands() {
        let smear = TriWingSmear.compute(radii: 128, angles: 240)
        let ring = smear.glowRing()
        let wings: [[Float]] = smear.glowRingWings()
        XCTAssertEqual(wings.count, 3)
        for w in wings { XCTAssertEqual(w.count, smear.radii) }
        var peakAt: [Int] = [0, 0, 0]
        var peak: [Float] = [0, 0, 0]
        for i in 0..<smear.radii {
            let sum: Float = wings[0][i] + wings[1][i] + wings[2][i]
            XCTAssertEqual(sum, ring.opacity[i], accuracy: 1e-4)
            for k in 0..<3 where wings[k][i] > peak[k] { peak[k] = wings[k][i]; peakAt[k] = i }
        }
        // Outermost band is wing 0, innermost wing 2 (the smear's own band split).
        for k in 0..<3 { XCTAssertGreaterThan(peak[k], 0.1) }
        XCTAssertGreaterThan(peakAt[0], peakAt[1])
        XCTAssertGreaterThan(peakAt[1], peakAt[2])
    }

    // MARK: Side band from arbitrary wing colours

    func testSideBandColoursMatchSideBand() {
        let sets: [[SIMD3<Float>]] = [TriWingSwept.defaultWingColours,
                                      [SIMD3<Float>(1, 0.2, 0.3), SIMD3<Float>(0.9, 0.9, 0.1), SIMD3<Float>(0.2, 0.3, 1)]]
        for colours in sets {
            let ref = TriWingSwept.sideBand(waistRadius: 0.6, wingColours: colours)
            let got = TriWingSwept.sideBandColours(wingColours: colours)
            XCTAssertEqual(simd_length(got.upper - ref.upper), 0, accuracy: 1e-5)
            XCTAssertEqual(simd_length(got.lower - ref.lower), 0, accuracy: 1e-5)
        }
    }

    // MARK: Palette control relevance

    func testPaletteControlIsLiveForTriWingSpinnerOnlyWhenItsLightsFollowThePalette() {
        var sp = SpinnerSettings()
        XCTAssertFalse(VisualizerStyle.triWingSpinner.paletteControlEnabled(spinner: sp))
        sp.lightColors = .palette
        XCTAssertFalse(VisualizerStyle.spinner.paletteControlEnabled(spinner: sp))   // disc: no lights to colour
        XCTAssertTrue(VisualizerStyle.triWingSpinner.paletteControlEnabled(spinner: sp))
        sp.lightColors = .original
        XCTAssertFalse(VisualizerStyle.triWingSpinner.paletteControlEnabled(spinner: sp))
    }

    func testPaletteControlForOtherStylesFollowsUsesPalette() {
        var sp = SpinnerSettings()
        sp.lightColors = .palette
        for style in VisualizerStyle.allCases where !style.isSpinnerFamily {
            XCTAssertEqual(style.paletteControlEnabled(spinner: sp), style.usesPalette, "\(style)")
        }
    }
}
